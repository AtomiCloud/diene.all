import { type Problem, ProblemTransformer } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import {
  type CodeTokenResponse,
  fetchTokenByAuthorizationCode,
  fetchTokenByRefreshToken,
  generateSignInUri,
  Prompt,
  type RefreshTokenTokenResponse,
  type Requester,
  revoke,
  type SignInUriParameters,
} from '@logto/js';
import { z } from 'zod';
import { type AuthProblems, createAuthRefreshFailed, createUnauthorized } from '../../lib/problems';
import {
  ACCESS_TOKEN_LIFETIME,
  type AuthClock,
  type AuthProvider,
  type SignInUrlOptions,
  type TokenResponse,
} from '../../lib/provider';

/** The subset of registered problems the Logto provider surfaces. */
type ProviderProblems = Pick<AuthProblems, 'AuthRefreshFailed' | 'Unauthorized'>;

/** Injected session state port. All mutable auth state lives behind this seam. */
export interface LogtoTokenSession {
  readonly refreshToken: string;
  readonly idToken?: string;
  readonly accessTokens: Readonly<Record<string, TokenResponse>>;
}

/**
 * Storage port for the provider's session. The provider holds no session state
 * itself; every read/write goes through this injected seam. Consumers supply a
 * concrete adapter (KV, Redis, cookie, …); no in-memory default ships here so
 * the adapter carries no hidden mutable state or test double.
 */
export interface LogtoTokenStorage {
  get(): Result<LogtoTokenSession | undefined, Problem>;
  set(session: LogtoTokenSession): Result<void, Problem>;
  clear(): Result<void, Problem>;
}

/** Minimal Web-standard fetch surface used by the Logto SDK adapter. */
export type LogtoFetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/**
 * Serialises refresh-token grants across resource audiences. Rotating refresh
 * tokens are single-use, so two resources must never consume the same token in
 * parallel. The coordinator is injectable to make that ordering observable in
 * tests and shareable when several provider facades use one session store.
 */
export interface LogtoRefreshCoordinator {
  run<T>(operation: () => Promise<ResultSerial<T, Problem>>): Promise<ResultSerial<T, Problem>>;
}

/** Build a FIFO refresh coordinator with no rejected internal promise. */
export function createLogtoRefreshCoordinator(): LogtoRefreshCoordinator {
  let tail: Promise<void> = Promise.resolve();
  return {
    run: async operation => {
      const previous = tail;
      let release: (() => void) | undefined;
      tail = new Promise<void>(resolve => {
        release = resolve;
      });
      await previous;
      try {
        return await operation();
      } finally {
        release?.();
      }
    },
  };
}

export interface AuthorizationCodeExchangeOptions {
  readonly code: string;
  readonly redirectUri: string;
  readonly codeVerifier: string;
  readonly resource?: string;
}

/** External, config-driven scalars (validated) plus injected collaborators. */
export interface LogtoProviderOptions {
  readonly endpoint: string;
  readonly appId: string;
  readonly appSecret: string;
  readonly storage: LogtoTokenStorage;
  readonly problems: ProviderProblems;
  readonly clock: AuthClock;
  readonly fetch?: LogtoFetchLike;
  readonly tokenSkew?: Temporal.Duration;
  readonly refreshCoordinator?: LogtoRefreshCoordinator;
}

/** OIDC endpoints derived once from the configured issuer base. */
interface LogtoEndpoints {
  readonly token: string;
  readonly authorization: string;
  readonly revocation: string;
}

/** Immutable, fully-resolved dependency bundle threaded to every collaborator. */
interface ProviderContext {
  readonly endpoints: LogtoEndpoints;
  readonly appId: string;
  readonly appSecret: string;
  readonly storage: LogtoTokenStorage;
  readonly problems: ProviderProblems;
  readonly clock: AuthClock;
  readonly fetch: LogtoFetchLike;
  readonly skew: Temporal.Duration;
  readonly refreshCoordinator: LogtoRefreshCoordinator;
  readonly transformer: ProblemTransformer<ProviderProblems['AuthRefreshFailed']['dataSchema']>;
}

/** Only the external scalars are schema-validated; injected ports are trusted. */
const nonBlankStringSchema = z.string().trim().min(1);
const nonBlankOpaqueSchema = z.string().refine(value => value.trim() !== '', {
  message: 'Value must not be blank.',
});
const httpUrlSchema = z.url().refine(value => value.startsWith('https://') || value.startsWith('http://'), {
  message: 'URL must use http or https.',
});
const issuerOriginSchema = httpUrlSchema.superRefine((value, context) => {
  if (!URL.canParse(value)) return;
  const url = new URL(value);
  if (url.username !== '' || url.password !== '' || url.pathname !== '/' || url.search !== '' || url.hash !== '') {
    context.addIssue({
      code: 'custom',
      message: 'Logto endpoint must be a canonical origin without credentials, path, query, or fragment.',
    });
  }
});
const providerConfigSchema = z
  .object({
    endpoint: issuerOriginSchema,
    appId: nonBlankStringSchema,
    appSecret: nonBlankOpaqueSchema,
  })
  .strict();
const oauthParameterUrlSchema = httpUrlSchema.superRefine((value, context) => {
  if (!URL.canParse(value)) return;
  const url = new URL(value);
  if (url.username !== '' || url.password !== '' || url.hash !== '') {
    context.addIssue({
      code: 'custom',
      message: 'OAuth URLs must not contain credentials or fragments.',
    });
  }
});
const resourceSchema = oauthParameterUrlSchema;
const reservedSignInParameters = new Set([
  'client_id',
  'redirect_uri',
  'code_challenge',
  'code_challenge_method',
  'state',
  'response_type',
  'prompt',
  'scope',
  'resource',
]);
const extraParametersSchema = z.record(z.string().min(1), z.string()).superRefine((parameters, context) => {
  for (const key of Object.keys(parameters)) {
    if (reservedSignInParameters.has(key)) {
      context.addIssue({
        code: 'custom',
        path: [key],
        message: `Extra parameter ${key} cannot override an OAuth parameter.`,
      });
    }
  }
});
const authorizationCodeExchangeSchema = z
  .object({
    code: nonBlankOpaqueSchema,
    redirectUri: oauthParameterUrlSchema,
    codeVerifier: nonBlankOpaqueSchema,
    resource: resourceSchema.optional(),
  })
  .strict();
const signInUrlOptionsSchema = z
  .object({
    redirectUri: oauthParameterUrlSchema,
    state: nonBlankOpaqueSchema,
    codeChallenge: nonBlankOpaqueSchema,
    scopes: z.array(nonBlankStringSchema).optional(),
    resources: z.array(resourceSchema).optional(),
    prompt: z.enum([Prompt.None, Prompt.Login, Prompt.Consent]).optional(),
    extraParameters: extraParametersSchema.optional(),
  })
  .strict();
const nonNegativeDurationSchema = z
  .custom<Temporal.Duration>(value => value instanceof Temporal.Duration)
  .refine(value => {
    try {
      const reference = Temporal.Instant.from('2000-01-01T00:00:00Z');
      return Temporal.Instant.compare(reference.subtract(value), reference) <= 0;
    } catch {
      return false;
    }
  });

/**
 * Structural validation of a token response returned by the SDK/requester. Keys
 * are already camelCased by `@logto/js`; the documented OAuth metadata is
 * enumerated so unexpected keys are rejected rather than silently stripped.
 * The access token, replacement refresh token, id token, and numeric expiry are
 * validated here rather than trusted via a cast; rotation/blank semantics are then
 * enforced by the callers so each failure maps to its own typed problem.
 */
const sdkTokenResponseSchema = z
  .object({
    accessToken: z.string(),
    refreshToken: z.string().optional(),
    idToken: z.string().optional(),
    scope: z.string().optional(),
    tokenType: z.string().optional(),
    expiresIn: z
      .number()
      .refine(value => Number.isFinite(value), 'expires_in must be a finite number.')
      .nonnegative()
      .optional(),
  })
  .strict();

type SdkTokenResponse = z.infer<typeof sdkTokenResponseSchema>;

/** Best-effort extraction of a candidate replacement refresh token from a raw response. */
function readRefreshTokenCandidate(raw: unknown): string {
  if (typeof raw === 'object' && raw !== null) {
    const value = (raw as Record<string, unknown>).refreshToken;
    if (typeof value === 'string') return value.trim();
  }
  return '';
}

const DEFAULT_TOKEN_SKEW = Temporal.Duration.from({ seconds: 30 });

class LogtoSdkRequestError extends Error {
  constructor(
    readonly response: Response,
    readonly payload: unknown,
  ) {
    super(`Logto token endpoint returned ${response.status}`);
    this.name = 'LogtoSdkRequestError';
  }
}

function isInvalidGrant(value: unknown): boolean {
  if (typeof value === 'string') return value.includes('invalid_grant');
  if (value instanceof LogtoSdkRequestError) return isInvalidGrant(value.payload);
  if (typeof value !== 'object' || value === null) return false;
  const body = value as Record<string, unknown>;
  return body.error === 'invalid_grant' || body.code === 'oidc.invalid_grant';
}

function toLogtoPrompt(prompt: string | undefined): Prompt | undefined {
  if (prompt === undefined) return undefined;
  if (prompt === Prompt.None) return Prompt.None;
  if (prompt === Prompt.Login) return Prompt.Login;
  if (prompt === Prompt.Consent) return Prompt.Consent;
  return undefined;
}

function deriveEndpoints(endpoint: string): LogtoEndpoints {
  const base = endpoint.replace(/\/+$/, '');
  return {
    token: `${base}/oidc/token`,
    authorization: `${base}/oidc/auth`,
    revocation: `${base}/oidc/token/revocation`,
  };
}

/**
 * A Logto SDK requester built on the injected `fetch`. It appends the confidential
 * `client_secret` to every token request and normalises non-2xx responses into a
 * typed error carrying the original response for problem mapping.
 */
function buildRequester(ctx: ProviderContext): Requester {
  const requester: Requester = async <T>(
    input: Parameters<LogtoFetchLike>[0],
    init?: Parameters<LogtoFetchLike>[1],
  ): Promise<T> => {
    const parameters = new URLSearchParams(typeof init?.body === 'string' ? init.body : undefined);
    parameters.set('client_secret', ctx.appSecret);
    const response = await ctx.fetch(input, {
      ...init,
      headers: { accept: 'application/json', ...init?.headers },
      body: parameters.toString(),
    });
    const retained = response.clone() as unknown as Response;
    let payload: unknown;
    try {
      payload = await response.json();
    } catch {
      payload = {};
    }
    if (!response.ok) throw new LogtoSdkRequestError(retained, payload);
    return payload as T;
  };
  return requester;
}

/**
 * Build a domain {@link TokenResponse} from a validated access token and optional
 * expiry (seconds). Enforces the fixed ten-minute access-token contract by capping
 * the SDK's `expires_in` at {@link ACCESS_TOKEN_LIFETIME}; expiry is an absolute
 * {@link Temporal.Instant} off the injected clock. Inputs are pre-validated by
 * {@link sdkTokenResponseSchema} and the callers' blank-access checks, so this is
 * total (never throws).
 */
function toTokenResponse(
  ctx: ProviderContext,
  accessToken: string,
  expiresInSeconds: number | undefined,
): TokenResponse {
  const requestedSeconds =
    expiresInSeconds === undefined
      ? Math.floor(ACCESS_TOKEN_LIFETIME.total({ unit: 'seconds' }))
      : Math.max(0, Math.floor(expiresInSeconds));
  const requested = Temporal.Duration.from({ seconds: requestedSeconds });
  const capped = Temporal.Duration.compare(requested, ACCESS_TOKEN_LIFETIME) > 0 ? ACCESS_TOKEN_LIFETIME : requested;
  return { token: accessToken, expiresAt: ctx.clock.now().add(capped) };
}

/**
 * Best-effort revoke of a (possibly dead) refresh token, then unconditionally clear
 * the cached session. A blank token skips revocation; clearing always runs so the
 * consumed session can never be reused.
 */
async function revokeAndClear(ctx: ProviderContext, refreshToken: string): Promise<void> {
  if (refreshToken.trim() !== '') {
    try {
      await revoke(ctx.endpoints.revocation, ctx.appId, refreshToken, buildRequester(ctx));
    } catch {
      // Revocation is best-effort; dropping the cached session is what closes the door.
    }
  }
  await ctx.storage.clear().native();
}

/**
 * Map an SDK/transport error to a problem. `invalid_grant` (a consumed or stolen
 * refresh token) stays fail-closed: clear the session and surface Unauthorized.
 */
async function problemForSdkError(ctx: ProviderContext, error: unknown): Promise<Problem> {
  if (isInvalidGrant(error)) {
    await ctx.storage.clear().native();
    return createUnauthorized(ctx.problems, 'The refresh token was rejected as already used.');
  }
  if (error instanceof LogtoSdkRequestError) return ctx.transformer.fromHttpError(error.response);
  return ctx.transformer.fromError(error);
}

/**
 * Perform the OIDC `refresh_token` grant and persist the rotated session.
 *
 * Rotating-refresh contract: the IdP MUST return a fresh `refresh_token`. A
 * missing or blank replacement is a typed failure — the consumed token is
 * revoked, the cached session is cleared, and the old token is never reused.
 */
function refreshSessionLocked(
  ctx: ProviderContext,
  resource?: string,
  reuseFreshResource = false,
): Result<TokenResponse | undefined, Problem> {
  return Res.async<TokenResponse | undefined, Problem>(async () => {
    const stored = await ctx.storage.get().serial();
    if (stored[0] === 'err') return Err(stored[1]);
    const session = stored[1];
    if (session === undefined || session.refreshToken.trim() === '') {
      return Err(createUnauthorized(ctx.problems, 'No refresh token is available.'));
    }
    const cached = resource === undefined ? undefined : session.accessTokens[resource];
    if (
      reuseFreshResource &&
      cached !== undefined &&
      Temporal.Instant.compare(ctx.clock.now(), cached.expiresAt.subtract(ctx.skew)) < 0
    ) {
      return Ok(cached);
    }

    let response: RefreshTokenTokenResponse;
    try {
      response = await fetchTokenByRefreshToken(
        {
          clientId: ctx.appId,
          tokenEndpoint: ctx.endpoints.token,
          refreshToken: session.refreshToken,
          resource,
        },
        buildRequester(ctx),
      );
    } catch (error: unknown) {
      return Err(await problemForSdkError(ctx, error));
    }

    // The old refresh token is now consumed. Every failure below is fail-closed:
    // revoke whatever replacement exists, clear the session, never reuse the old.
    const parsed = sdkTokenResponseSchema.safeParse(response);
    if (!parsed.success) {
      const candidate = readRefreshTokenCandidate(response);
      await revokeAndClear(ctx, candidate === '' ? session.refreshToken : candidate);
      return Err(ctx.transformer.fromError(new TypeError(`Malformed Logto token response: ${parsed.error.message}`)));
    }
    const data: SdkTokenResponse = parsed.data;

    const replacement = (data.refreshToken ?? '').trim();
    if (replacement === '') {
      await revokeAndClear(ctx, session.refreshToken);
      return Err(
        createAuthRefreshFailed(ctx.problems, 'Logto did not rotate the refresh token; the session was cleared.'),
      );
    }
    if (data.accessToken.trim() === '') {
      await revokeAndClear(ctx, replacement);
      return Err(ctx.transformer.fromError(new TypeError('Logto token response omitted access_token')));
    }

    const token = toTokenResponse(ctx, data.accessToken, data.expiresIn);
    const idToken = data.idToken ?? session.idToken;
    const accessTokens = resource === undefined ? session.accessTokens : { ...session.accessTokens, [resource]: token };
    const persisted = await ctx.storage
      .set({
        refreshToken: replacement,
        ...(idToken === undefined ? {} : { idToken }),
        accessTokens,
      })
      .serial();
    if (persisted[0] === 'err') {
      await revokeAndClear(ctx, replacement);
      return Err(persisted[1]);
    }
    return Ok(resource === undefined ? undefined : token);
  });
}

function refreshSession(
  ctx: ProviderContext,
  resource?: string,
  reuseFreshResource = false,
): Result<TokenResponse | undefined, Problem> {
  return Res.fromSerial(
    ctx.refreshCoordinator.run(() => refreshSessionLocked(ctx, resource, reuseFreshResource).serial()),
  );
}

/** Exchange an authorization code for the initial session (SDK auth-code grant). */
function exchangeCode(ctx: ProviderContext, options: AuthorizationCodeExchangeOptions): Result<void, Problem> {
  return Res.async<void, Problem>(async () => {
    const parsed = authorizationCodeExchangeSchema.safeParse(options);
    if (!parsed.success) {
      return Err(createAuthRefreshFailed(ctx.problems, `Invalid authorization-code exchange: ${parsed.error.message}`));
    }
    let response: CodeTokenResponse;
    try {
      response = await fetchTokenByAuthorizationCode(
        {
          clientId: ctx.appId,
          tokenEndpoint: ctx.endpoints.token,
          redirectUri: parsed.data.redirectUri,
          codeVerifier: parsed.data.codeVerifier,
          code: parsed.data.code,
          resource: parsed.data.resource,
        },
        buildRequester(ctx),
      );
    } catch (error: unknown) {
      return Err(await problemForSdkError(ctx, error));
    }

    const parsedResponse = sdkTokenResponseSchema.safeParse(response);
    if (!parsedResponse.success) {
      await revokeAndClear(ctx, readRefreshTokenCandidate(response));
      return Err(
        ctx.transformer.fromError(new TypeError(`Malformed Logto token response: ${parsedResponse.error.message}`)),
      );
    }
    const data: SdkTokenResponse = parsedResponse.data;

    const refreshToken = (data.refreshToken ?? '').trim();
    if (refreshToken === '') {
      return Err(createAuthRefreshFailed(ctx.problems, 'Logto authorization-code response omitted a refresh token.'));
    }
    if (data.accessToken.trim() === '') {
      await revokeAndClear(ctx, refreshToken);
      return Err(ctx.transformer.fromError(new TypeError('Logto token response omitted access_token')));
    }

    const accessToken = toTokenResponse(ctx, data.accessToken, data.expiresIn);
    const persisted = await ctx.storage
      .set({
        refreshToken,
        ...(data.idToken === undefined ? {} : { idToken: data.idToken }),
        accessTokens: parsed.data.resource === undefined ? {} : { [parsed.data.resource]: accessToken },
      })
      .serial();
    if (persisted[0] === 'err') {
      await revokeAndClear(ctx, refreshToken);
      return Err(persisted[1]);
    }
    return Ok(undefined);
  });
}

/** Return a cached access token when still fresh, else refresh for the resource. */
function readAccessToken(ctx: ProviderContext, resource: string): Result<TokenResponse, Problem> {
  return Res.async<TokenResponse, Problem>(async () => {
    const parsed = resourceSchema.safeParse(resource);
    if (!parsed.success) {
      return Err(createAuthRefreshFailed(ctx.problems, `Invalid Logto resource: ${parsed.error.message}`));
    }
    const stored = await ctx.storage.get().serial();
    if (stored[0] === 'err') return Err(stored[1]);
    const cached = stored[1]?.accessTokens[parsed.data];
    if (cached !== undefined && Temporal.Instant.compare(ctx.clock.now(), cached.expiresAt.subtract(ctx.skew)) < 0) {
      return Ok(cached);
    }
    const refreshed = await refreshSession(ctx, parsed.data, true).serial();
    if (refreshed[0] === 'err') return Err(refreshed[1]);
    if (refreshed[1] === undefined) {
      return Err(ctx.transformer.fromError(new TypeError('Logto did not return an access token')));
    }
    return Ok(refreshed[1]);
  });
}

function readIdToken(ctx: ProviderContext): Result<string, Problem> {
  return Res.async<string, Problem>(async () => {
    const stored = await ctx.storage.get().serial();
    if (stored[0] === 'err') return Err(stored[1]);
    const idToken = stored[1]?.idToken;
    return idToken === undefined || idToken.trim() === ''
      ? Err(createUnauthorized(ctx.problems, 'No ID token is available.'))
      : Ok(idToken);
  });
}

function buildSignInUrl(ctx: ProviderContext, options: SignInUrlOptions): Result<string, Problem> {
  const parsed = signInUrlOptionsSchema.safeParse(options);
  if (!parsed.success) {
    return Err(createAuthRefreshFailed(ctx.problems, `Invalid Logto sign-in options: ${parsed.error.message}`));
  }
  try {
    const parameters: SignInUriParameters = {
      authorizationEndpoint: ctx.endpoints.authorization,
      clientId: ctx.appId,
      redirectUri: parsed.data.redirectUri,
      state: parsed.data.state,
      codeChallenge: parsed.data.codeChallenge,
      scopes: parsed.data.scopes,
      resources: parsed.data.resources,
      prompt: toLogtoPrompt(parsed.data.prompt),
      extraParams: parsed.data.extraParameters,
    };
    return Ok(generateSignInUri(parameters));
  } catch (error: unknown) {
    return Err(ctx.transformer.fromError(error));
  }
}

/** Drop cached access tokens while retaining the refresh/id session. */
function clearAccessTokens(ctx: ProviderContext): Result<void, Problem> {
  return Res.async<void, Problem>(async () => {
    const stored = await ctx.storage.get().serial();
    if (stored[0] === 'err') return Err(stored[1]);
    const session = stored[1];
    if (session !== undefined) {
      const cleared = await ctx.storage.set({ ...session, accessTokens: {} }).serial();
      if (cleared[0] === 'err') return Err(cleared[1]);
    }
    return Ok(undefined);
  });
}

/**
 * Public Logto provider surface: the domain {@link AuthProvider} plus the Logto
 * authorization-code exchange. Exposed as an interface with no public constructor,
 * so {@link createLogtoAuthProvider} (which validates config) is the only way to
 * obtain one — runtime and TS consumers cannot bypass validation.
 */
export interface LogtoAuthProvider extends AuthProvider {
  exchangeAuthorizationCode(options: AuthorizationCodeExchangeOptions): Result<void, Problem>;
}

/**
 * Logto {@link AuthProvider} implementation (int ledger). Every `@logto/js` import
 * is confined to this module; no SDK type crosses the public domain interface. The
 * class is a thin, immutable façade over an injected {@link ProviderContext}; all
 * behaviour lives in the top-level collaborators above. Unexported: the only
 * construction path is the validating factory.
 */
class LogtoAuthProviderImpl implements LogtoAuthProvider {
  readonly #ctx: ProviderContext;

  constructor(ctx: ProviderContext) {
    this.#ctx = ctx;
  }

  getAccessToken(resource: string): Result<TokenResponse, Problem> {
    return readAccessToken(this.#ctx, resource);
  }

  refresh(): Result<void, Problem> {
    return refreshSession(this.#ctx).map(() => undefined);
  }

  exchangeAuthorizationCode(options: AuthorizationCodeExchangeOptions): Result<void, Problem> {
    return exchangeCode(this.#ctx, options);
  }

  getIdToken(): Result<string, Problem> {
    return readIdToken(this.#ctx);
  }

  signInUrl(options: SignInUrlOptions): Result<string, Problem> {
    return buildSignInUrl(this.#ctx, options);
  }

  clearTokens(): Result<void, Problem> {
    return clearAccessTokens(this.#ctx);
  }
}

/**
 * Construct a {@link LogtoAuthProvider}. External scalar config and the optional
 * token skew are validated with Zod `safeParse`; injected ports (storage, clock,
 * problems) are trusted. Returns a typed problem when the configuration is invalid.
 * This is the sole public construction path — the concrete class is unexported.
 */
export function createLogtoAuthProvider(options: LogtoProviderOptions): Result<LogtoAuthProvider, Problem> {
  const parsed = providerConfigSchema.safeParse({
    endpoint: options.endpoint,
    appId: options.appId,
    appSecret: options.appSecret,
  });
  if (!parsed.success) {
    return Err(
      createAuthRefreshFailed(options.problems, `Invalid Logto provider configuration: ${parsed.error.message}`),
    );
  }
  const parsedSkew = nonNegativeDurationSchema.safeParse(options.tokenSkew ?? DEFAULT_TOKEN_SKEW);
  if (!parsedSkew.success) {
    return Err(createAuthRefreshFailed(options.problems, `Invalid Logto token skew: ${parsedSkew.error.message}`));
  }
  const transformer = new ProblemTransformer({
    fallback: options.problems.AuthRefreshFailed,
    fallbackData: () => ({}),
  });
  const ctx: ProviderContext = {
    endpoints: deriveEndpoints(parsed.data.endpoint),
    appId: parsed.data.appId,
    appSecret: parsed.data.appSecret,
    storage: options.storage,
    problems: options.problems,
    clock: options.clock,
    fetch: options.fetch ?? globalThis.fetch.bind(globalThis),
    skew: parsedSkew.data,
    refreshCoordinator: options.refreshCoordinator ?? createLogtoRefreshCoordinator(),
    transformer,
  };
  return Ok(new LogtoAuthProviderImpl(ctx));
}
