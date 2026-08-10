import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { type Claims, decodeToken } from '../jwt';
import type { AuthClock, AuthProvider } from '../provider';
import type { CanonicalResourceKey } from '../resource-tree';
import {
  type AllAuthState,
  type AuthData,
  type AuthState,
  type AuthStateCell,
  authed,
  createAuthStateCell,
  createSingleFlightCell,
  DEFAULT_REFRESH_SKEW,
  type IAuthStateRetriever,
  type SingleFlightCell,
  stateNeedRefresh,
  systemClock,
  type TokenSet,
  type UserInfo,
  unauthed,
} from '../retriever';

export interface AuthSessionAccessor {
  isAuthenticated(): boolean | Promise<boolean>;
  getUserInfo(): Result<UserInfo, Problem>;
}

/**
 * Injected, explicit coordination state for the server retriever. The cached
 * token set and the single-flight refresh promise live here rather than on the
 * retriever object, keeping the service stateless and free of temporal coupling.
 */
export interface ServerAuthCoordinator {
  readonly tokenSet: AuthStateCell<TokenSet>;
  readonly flight: SingleFlightCell<TokenSet>;
  readonly forceFlight: SingleFlightCell<TokenSet>;
}

export function createServerAuthCoordinator(): ServerAuthCoordinator {
  return {
    tokenSet: createAuthStateCell<TokenSet>(),
    flight: createSingleFlightCell<TokenSet>(),
    forceFlight: createSingleFlightCell<TokenSet>(),
  };
}

export interface ServerAuthStateRetrieverOptions {
  readonly provider: AuthProvider;
  readonly resources: Readonly<Record<CanonicalResourceKey, string>>;
  readonly session: AuthSessionAccessor;
  readonly mapError?: (error: unknown) => Problem;
  readonly clock?: AuthClock;
  readonly skew?: Temporal.Duration;
  readonly coordinator?: ServerAuthCoordinator;
}

interface ServerAuthConfig {
  readonly provider: AuthProvider;
  readonly resources: Readonly<Record<CanonicalResourceKey, string>>;
  readonly session: AuthSessionAccessor;
  readonly mapError: (error: unknown) => Problem;
  readonly clock: AuthClock;
  readonly skew: Temporal.Duration;
}

const dnsLabelPattern = '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?';
const canonicalResourceKeySchema = z.string().regex(new RegExp(`^${dnsLabelPattern}(?:/${dnsLabelPattern}){3}$`));
const resourceAudienceSchema = z.url().refine(value => value.startsWith('https://') || value.startsWith('http://'));
const serverResourcesSchema = z.record(canonicalResourceKeySchema, resourceAudienceSchema);
const tokenResponseSchema = z
  .object({
    token: z.string().min(1),
    expiresAt: z.custom<Temporal.Instant>(value => value instanceof Temporal.Instant),
  })
  .strict();
const idTokenSchema = z.string().min(1);

function defaultMapError(error: unknown): Problem {
  const detail = error instanceof Error ? error.message : 'Authentication state could not be retrieved.';
  return {
    type: 'about:blank',
    title: 'Authentication refresh failed',
    status: 502,
    detail,
    data: {},
  };
}

function getAuthenticatedState<T extends AuthData>(
  config: ServerAuthConfig,
  getter: () => Result<T, Problem> | Promise<Result<T, Problem>>,
): Result<AuthState<T>, Problem> {
  return Res.async(async () => {
    try {
      if (!(await config.session.isAuthenticated())) return Ok(unauthed<T>());
      const result = await getter();
      return result.map(data => authed<T>(data));
    } catch (error: unknown) {
      return Err(config.mapError(error));
    }
  });
}

function fetchServerTokenSet(config: ServerAuthConfig): Result<AuthState<TokenSet>, Problem> {
  const parsedResources = serverResourcesSchema.safeParse(config.resources);
  if (!parsedResources.success) {
    return Err(config.mapError(new TypeError(`Invalid server auth resources: ${parsedResources.error.message}`)));
  }
  return getAuthenticatedState<TokenSet>(config, async () => {
    const accessResults = Object.entries(parsedResources.data).map(async ([key, resource]) => {
      const result = await config.provider.getAccessToken(resource).serial();
      return [key as CanonicalResourceKey, result] as const;
    });
    const [idToken, accessTokens] = await Promise.all([
      config.provider.getIdToken().serial(),
      Promise.all(accessResults),
    ]);
    if (idToken[0] === 'err') return Err(idToken[1]);
    const parsedIdToken = idTokenSchema.safeParse(idToken[1]);
    if (!parsedIdToken.success)
      return Err(config.mapError(new TypeError('The provider returned an invalid ID token.')));

    const tokens: Partial<Record<CanonicalResourceKey, string>> = {};
    for (const [key, result] of accessTokens) {
      if (result[0] === 'err') return Err(result[1]);
      const parsed = tokenResponseSchema.safeParse(result[1]);
      if (!parsed.success) {
        return Err(config.mapError(new TypeError(`The provider returned an invalid access token for ${key}.`)));
      }
      tokens[key] = parsed.data.token;
    }
    return Ok({ idToken: parsedIdToken.data, accessTokens: tokens as Record<CanonicalResourceKey, string> });
  });
}

function getServerTokenSet(
  config: ServerAuthConfig,
  coordinator: ServerAuthCoordinator,
): Result<AuthState<TokenSet>, Problem> {
  return Res.async<AuthState<TokenSet>, Problem>(async () => {
    const forcing = coordinator.forceFlight.peek();
    if (forcing !== undefined) return Res.fromSerial<AuthState<TokenSet>, Problem>(forcing);

    const cached = coordinator.tokenSet.peek();
    if (cached !== undefined) {
      if (!cached.value.isAuthed) return Ok(cached);
      const needsRefresh = await stateNeedRefresh(cached.value.data, {
        skew: config.skew,
        now: config.clock.now(),
      }).serial();
      if (needsRefresh[0] === 'err') return Err(needsRefresh[1]);
      if (!needsRefresh[1]) return Ok(cached);
    }

    const existing = coordinator.flight.peek();
    if (existing !== undefined) return Res.fromSerial<AuthState<TokenSet>, Problem>(existing);

    const flight = fetchServerTokenSet(config).serial();
    coordinator.flight.begin(flight);
    try {
      const result = await flight;
      if (result[0] === 'ok') coordinator.tokenSet.write(result[1]);
      return Res.fromSerial<AuthState<TokenSet>, Problem>(result);
    } finally {
      coordinator.flight.settle(flight);
    }
  });
}

function forceServerTokenSet(
  config: ServerAuthConfig,
  coordinator: ServerAuthCoordinator,
): Result<AuthState<TokenSet>, Problem> {
  const existing = coordinator.forceFlight.peek();
  if (existing !== undefined) return Res.fromSerial(existing);

  let flight!: Promise<ResultSerial<AuthState<TokenSet>, Problem>>;
  flight = (async () => {
    try {
      const readFlight = coordinator.flight.peek();
      if (readFlight !== undefined) await readFlight;
      coordinator.tokenSet.clear();
      coordinator.flight.clear();

      const cleared = await config.provider.clearTokens().serial();
      if (cleared[0] === 'err') return ['err', cleared[1]];
      const refreshed = await config.provider.refresh().serial();
      if (refreshed[0] === 'err') return ['err', refreshed[1]];
      const fetched = await fetchServerTokenSet(config).serial();
      if (fetched[0] === 'ok') coordinator.tokenSet.write(fetched[1]);
      return fetched;
    } finally {
      coordinator.forceFlight.settle(flight);
    }
  })();
  coordinator.forceFlight.begin(flight);
  return Res.fromSerial(flight);
}

function getServerClaims(config: ServerAuthConfig): Result<AuthState<Claims>, Problem> {
  return getAuthenticatedState<Claims>(config, async () => {
    const idToken = await config.provider.getIdToken().serial();
    if (idToken[0] === 'err') return Err(idToken[1]);
    return decodeToken(idToken[1]);
  });
}

function getServerUserInfo(config: ServerAuthConfig): Result<AuthState<UserInfo>, Problem> {
  return getAuthenticatedState<UserInfo>(config, async () => config.session.getUserInfo());
}

function getServerStates(
  config: ServerAuthConfig,
  coordinator: ServerAuthCoordinator,
): Result<AuthState<AllAuthState>, Problem> {
  return Res.all(getServerTokenSet(config, coordinator), getServerUserInfo(config), getServerClaims(config))
    .andThen(values => {
      const [tokens, user, claims] = values as [AuthState<TokenSet>, AuthState<UserInfo>, AuthState<Claims>];
      if (tokens.value.isAuthed && user.value.isAuthed && claims.value.isAuthed) {
        return Ok<AuthState<AllAuthState>, Problem[]>(
          authed({ tokens: tokens.value.data, claims: claims.value.data, user: user.value.data }),
        );
      }
      return Ok<AuthState<AllAuthState>, Problem[]>(unauthed<AllAuthState>());
    })
    .mapErr(errors => errors[0] as Problem);
}

/**
 * Server/edge retriever. Uses Web-standard APIs only (no `node:*`) and delegates
 * to an injected {@link AuthProvider} and {@link AuthSessionAccessor}; all mutable
 * state lives in the injected {@link ServerAuthCoordinator}.
 */
export class ServerAuthStateRetriever implements IAuthStateRetriever {
  readonly #config: ServerAuthConfig;
  readonly #coordinator: ServerAuthCoordinator;

  constructor(options: ServerAuthStateRetrieverOptions) {
    this.#config = Object.freeze({
      provider: options.provider,
      resources: Object.freeze({ ...options.resources }),
      session: options.session,
      mapError: options.mapError ?? defaultMapError,
      clock: options.clock ?? systemClock,
      skew: options.skew ?? DEFAULT_REFRESH_SKEW,
    });
    this.#coordinator = options.coordinator ?? createServerAuthCoordinator();
  }

  getStates(): Result<AuthState<AllAuthState>, Problem> {
    return getServerStates(this.#config, this.#coordinator);
  }

  forceTokenSet(): Result<AuthState<TokenSet>, Problem> {
    return forceServerTokenSet(this.#config, this.#coordinator);
  }

  getTokenSet(): Result<AuthState<TokenSet>, Problem> {
    return getServerTokenSet(this.#config, this.#coordinator);
  }

  getClaims(): Result<AuthState<Claims>, Problem> {
    return getServerClaims(this.#config);
  }

  getUserInfo(): Result<AuthState<UserInfo>, Problem> {
    return getServerUserInfo(this.#config);
  }
}
