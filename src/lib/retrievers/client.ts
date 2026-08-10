import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import type { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import type { Claims } from '../jwt';
import type { AuthClock } from '../provider';
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

export interface ClientAuthEndpoints {
  readonly tokenSet: string;
  readonly claims: string;
  readonly userInfo: string;
  readonly forceTokenSet: string;
}

export const defaultClientAuthEndpoints: ClientAuthEndpoints = Object.freeze({
  tokenSet: '/api/auth/tokens',
  claims: '/api/auth/claims',
  userInfo: '/api/auth/user',
  forceTokenSet: '/api/auth/force_tokens',
});

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/**
 * Injected, explicit cache for the client retriever. All mutable state lives in
 * these cells rather than on the retriever object, so the service stays
 * stateless and the cache can be shared, inspected, or reset in isolation.
 */
export interface ClientAuthCache {
  readonly tokenSet: AuthStateCell<TokenSet>;
  readonly tokenFlight: SingleFlightCell<TokenSet>;
  readonly forceFlight: SingleFlightCell<TokenSet>;
  readonly claims: AuthStateCell<Claims>;
  readonly userInfo: AuthStateCell<UserInfo>;
}

export function createClientAuthCache(): ClientAuthCache {
  return {
    tokenSet: createAuthStateCell<TokenSet>(),
    tokenFlight: createSingleFlightCell<TokenSet>(),
    forceFlight: createSingleFlightCell<TokenSet>(),
    claims: createAuthStateCell<Claims>(),
    userInfo: createAuthStateCell<UserInfo>(),
  };
}

export interface ClientAuthStateRetrieverOptions {
  readonly fetch?: FetchLike;
  readonly endpoints?: Partial<ClientAuthEndpoints>;
  readonly mapError?: (error: unknown) => Problem;
  readonly clock?: AuthClock;
  readonly skew?: Temporal.Duration;
  readonly cache?: ClientAuthCache;
}

interface ClientAuthConfig {
  readonly fetch: FetchLike;
  readonly endpoints: ClientAuthEndpoints;
  readonly mapError: (error: unknown) => Problem;
  readonly clock: AuthClock;
  readonly skew: Temporal.Duration;
}

const dnsLabelPattern = '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?';
const canonicalResourceKeySchema = z.string().regex(new RegExp(`^${dnsLabelPattern}(?:/${dnsLabelPattern}){3}$`));
const endpointSchema = z.union([
  z.string().regex(/^\/(?!\/)(?!.*\s).*$/),
  z.url().refine(value => value.startsWith('https://') || value.startsWith('http://')),
]);
const problemWireSchema = z
  .object({
    type: z.string().min(1),
    title: z.string().min(1),
    status: z.number().int().min(100).max(599),
    detail: z.string().optional(),
    instance: z.string().optional(),
    data: z.unknown(),
  })
  .strict();
const claimsWireSchema = z.record(z.string(), z.unknown());
const userInfoWireSchema = z.record(z.string(), z.unknown());
const tokenSetWireSchema = z
  .object({
    idToken: z.string().min(1),
    accessTokens: z.record(canonicalResourceKeySchema, z.string().min(1)),
  })
  .strict();

function authStateWireSchema<T extends AuthData>(dataSchema: z.ZodType<T>): z.ZodType<AuthState<T>> {
  return z.union([
    z
      .object({
        __kind: z.literal('authed'),
        value: z.object({ isAuthed: z.literal(true), data: dataSchema }).strict(),
      })
      .strict(),
    z
      .object({
        __kind: z.literal('unauthed'),
        value: z.object({ isAuthed: z.literal(false) }).strict(),
      })
      .strict(),
  ]) as z.ZodType<AuthState<T>>;
}

function authResultWireSchema<T extends AuthData>(
  dataSchema: z.ZodType<T>,
): z.ZodType<ResultSerial<AuthState<T>, Problem>> {
  return z.union([
    z.tuple([z.literal('ok'), authStateWireSchema(dataSchema)]),
    z.tuple([z.literal('err'), problemWireSchema]),
  ]) as z.ZodType<ResultSerial<AuthState<T>, Problem>>;
}

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

function fetchClientState<T extends AuthData>(
  config: ClientAuthConfig,
  endpoint: string,
  dataSchema: z.ZodType<T>,
): Result<AuthState<T>, Problem> {
  return Res.async<AuthState<T>, Problem>(async () => {
    const parsedEndpoint = endpointSchema.safeParse(endpoint);
    if (!parsedEndpoint.success) {
      return Err(config.mapError(new TypeError(`Invalid auth-state endpoint ${endpoint}`)));
    }
    try {
      const response = await config.fetch(parsedEndpoint.data, { headers: { accept: 'application/json' } });
      const body: unknown = await response.json();
      const parsedResult = authResultWireSchema(dataSchema).safeParse(body);
      if (parsedResult.success) return Res.fromSerial<AuthState<T>, Problem>(parsedResult.data);
      const parsedProblem = problemWireSchema.safeParse(body);
      if (parsedProblem.success) return Err<AuthState<T>, Problem>(parsedProblem.data);
      return Err<AuthState<T>, Problem>(
        config.mapError(new TypeError(`Invalid auth-state response from ${parsedEndpoint.data}`)),
      );
    } catch (error: unknown) {
      return Err<AuthState<T>, Problem>(config.mapError(error));
    }
  });
}

function readCachedOrFetch<T extends AuthData>(
  config: ClientAuthConfig,
  cell: AuthStateCell<T>,
  endpoint: string,
  dataSchema: z.ZodType<T>,
): Result<AuthState<T>, Problem> {
  const cached = cell.peek();
  return cached === undefined ? fetchClientState<T>(config, endpoint, dataSchema) : Ok(cached);
}

function fetchClientTokenSet(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<TokenSet>, Problem> {
  return readCachedOrFetch<TokenSet>(config, cache.tokenSet, config.endpoints.tokenSet, tokenSetWireSchema)
    .andThen(state => {
      if (!state.value.isAuthed) return Ok<AuthState<TokenSet>, Problem>(state);
      return stateNeedRefresh(state.value.data, { skew: config.skew, now: config.clock.now() }).andThen(needsRefresh =>
        needsRefresh ? fetchClientState<TokenSet>(config, config.endpoints.tokenSet, tokenSetWireSchema) : Ok(state),
      );
    })
    .run(state => {
      cache.tokenSet.write(state);
    });
}

function getClientTokenSet(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<TokenSet>, Problem> {
  return Res.async<AuthState<TokenSet>, Problem>(async () => {
    const forcing = cache.forceFlight.peek();
    if (forcing !== undefined) return Res.fromSerial<AuthState<TokenSet>, Problem>(forcing);

    const existing = cache.tokenFlight.peek();
    if (existing !== undefined) return Res.fromSerial<AuthState<TokenSet>, Problem>(existing);

    const flight = fetchClientTokenSet(config, cache).serial();
    cache.tokenFlight.begin(flight);
    try {
      return Res.fromSerial<AuthState<TokenSet>, Problem>(await flight);
    } finally {
      cache.tokenFlight.settle(flight);
    }
  });
}

function getClientClaims(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<Claims>, Problem> {
  return readCachedOrFetch<Claims>(config, cache.claims, config.endpoints.claims, claimsWireSchema).run(state => {
    cache.claims.write(state);
  });
}

function getClientUserInfo(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<UserInfo>, Problem> {
  return readCachedOrFetch<UserInfo>(config, cache.userInfo, config.endpoints.userInfo, userInfoWireSchema).run(
    state => {
      cache.userInfo.write(state);
    },
  );
}

function forceClientTokenSet(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<TokenSet>, Problem> {
  const existing = cache.forceFlight.peek();
  if (existing !== undefined) return Res.fromSerial(existing);

  let flight!: Promise<ResultSerial<AuthState<TokenSet>, Problem>>;
  flight = (async () => {
    try {
      const readFlight = cache.tokenFlight.peek();
      if (readFlight !== undefined) await readFlight;
      cache.tokenSet.clear();
      cache.tokenFlight.clear();
      cache.claims.clear();
      cache.userInfo.clear();
      const fetched = await fetchClientState<TokenSet>(
        config,
        config.endpoints.forceTokenSet,
        tokenSetWireSchema,
      ).serial();
      if (fetched[0] === 'ok') cache.tokenSet.write(fetched[1]);
      return fetched;
    } finally {
      cache.forceFlight.settle(flight);
    }
  })();
  cache.forceFlight.begin(flight);
  return Res.fromSerial(flight);
}

function getClientStates(config: ClientAuthConfig, cache: ClientAuthCache): Result<AuthState<AllAuthState>, Problem> {
  return Res.all(getClientTokenSet(config, cache), getClientUserInfo(config, cache), getClientClaims(config, cache))
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

/** Browser-context retriever; all state is held in the injected {@link ClientAuthCache}. */
export class ClientAuthStateRetriever implements IAuthStateRetriever {
  readonly #config: ClientAuthConfig;
  readonly #cache: ClientAuthCache;

  constructor(options: ClientAuthStateRetrieverOptions = {}) {
    this.#config = Object.freeze({
      fetch: options.fetch ?? globalThis.fetch.bind(globalThis),
      endpoints: Object.freeze({ ...defaultClientAuthEndpoints, ...options.endpoints }),
      mapError: options.mapError ?? defaultMapError,
      clock: options.clock ?? systemClock,
      skew: options.skew ?? DEFAULT_REFRESH_SKEW,
    });
    this.#cache = options.cache ?? createClientAuthCache();
  }

  getStates(): Result<AuthState<AllAuthState>, Problem> {
    return getClientStates(this.#config, this.#cache);
  }

  forceTokenSet(): Result<AuthState<TokenSet>, Problem> {
    return forceClientTokenSet(this.#config, this.#cache);
  }

  getTokenSet(): Result<AuthState<TokenSet>, Problem> {
    return getClientTokenSet(this.#config, this.#cache);
  }

  getClaims(): Result<AuthState<Claims>, Problem> {
    return getClientClaims(this.#config, this.#cache);
  }

  getUserInfo(): Result<AuthState<UserInfo>, Problem> {
    return getClientUserInfo(this.#config, this.#cache);
  }
}
