import { mapWithConcurrency } from '@atomicloud/diene.core-utils';
import { isProblem, type Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { DEFAULT_TOKEN_CACHE_SKEW, type SingleFlightCache } from './cache';
import { type AuthProblems, createAuthRefreshFailed } from './problems';
import type { AuthClock, AuthProvider, TokenResponse } from './provider';

export interface ResourceKey {
  readonly platform: string;
  readonly landscape: string;
  readonly service: string;
  readonly resourceName: string;
}

export type CanonicalResourceKey = `${string}/${string}/${string}/${string}`;

export interface BackendRegistration {
  readonly backendId: string;
  readonly resources: readonly ResourceKey[];
  readonly onboardingResource: ResourceKey;
}

export type TokenBatchEntry = TokenResponse | Problem;
export type TokenBatch = Readonly<Record<CanonicalResourceKey, TokenBatchEntry>>;
export type BackendTokenBatch = Readonly<Record<CanonicalResourceKey, TokenResponse>>;

export interface TokenCacheStore {
  get(key: CanonicalResourceKey): Result<TokenResponse | undefined, Problem>;
  set(key: CanonicalResourceKey, value: TokenResponse): Result<void, Problem>;
  delete(key: CanonicalResourceKey): Result<void, Problem>;
  clear?(): Result<void, Problem>;
}

/** Read-only registry view retained for consumers that expose the configured bindings. */
export interface BackendRegistry {
  get(backendId: string): BackendRegistration | undefined;
  list(): readonly BackendRegistration[];
}

export interface ResourceTreeOptions {
  /** Immutable, complete backend configuration; no later registration step exists. */
  readonly bindings: readonly BackendRegistration[];
  /** Production callers must bind a KV-backed store explicitly. */
  readonly store: TokenCacheStore;
  readonly tokenCache: SingleFlightCache<CanonicalResourceKey, TokenResponse>;
  readonly clock: AuthClock;
  readonly problems: Pick<AuthProblems, 'AuthRefreshFailed'>;
  readonly concurrency?: number;
  readonly skew?: Temporal.Duration;
  readonly mapError?: (error: unknown) => Problem;
}

/** Ready, immutable resource-tree behavior exposed only through the validating factory. */
export interface ResourceTree {
  getBackend(backendId: unknown): Result<BackendRegistration, Problem>;
  listBackends(): readonly BackendRegistration[];
  getToken(resource: unknown): Result<TokenResponse, Problem>;
  fetchAllTokens(): Result<TokenBatch, Problem>;
  backendTokens(batch: TokenBatch, backendId: unknown): Result<BackendTokenBatch, Problem>;
  fetchBackendTokens(backendId: unknown): Result<BackendTokenBatch, Problem>;
  invalidate(resource: unknown): Result<void, Problem>;
  invalidateAll(): Result<void, Problem>;
}

const dnsLabelSchema = z
  .string()
  .min(1)
  .max(63)
  .regex(/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/, 'must be an explicit lowercase DNS label');

export const resourceKeySchema = z
  .object({
    platform: dnsLabelSchema,
    landscape: dnsLabelSchema,
    service: dnsLabelSchema,
    resourceName: dnsLabelSchema,
  })
  .strict();

export const backendIdSchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?$/, 'must be an explicit lowercase backend id');

const backendRegistrationSchema = z
  .object({
    backendId: backendIdSchema,
    resources: z.array(resourceKeySchema).min(1).readonly(),
    onboardingResource: resourceKeySchema,
  })
  .strict()
  .superRefine((registration, context) => {
    const keys = registration.resources.map(canonicalResourceKeyOf);
    if (new Set(keys).size !== keys.length) {
      context.addIssue({ code: 'custom', path: ['resources'], message: 'resources must be unique' });
    }
    if (!keys.includes(canonicalResourceKeyOf(registration.onboardingResource))) {
      context.addIssue({
        code: 'custom',
        path: ['onboardingResource'],
        message: 'onboardingResource must be one of resources',
      });
    }
  });

const fixedDurationSchema = z.custom<Temporal.Duration>(
  value =>
    value instanceof Temporal.Duration &&
    value.sign >= 0 &&
    value.years === 0 &&
    value.months === 0 &&
    value.weeks === 0 &&
    value.days === 0,
  'skew must be a non-negative, time-only Temporal.Duration',
);

const resourceTreeOptionsSchema = z
  .object({
    bindings: z
      .array(backendRegistrationSchema)
      .superRefine((bindings, context) => {
        const ids = bindings.map(binding => binding.backendId);
        if (new Set(ids).size !== ids.length) {
          context.addIssue({ code: 'custom', message: 'backend ids must be unique' });
        }
      })
      .readonly(),
    store: z.custom<TokenCacheStore>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as TokenCacheStore).get === 'function' &&
        typeof (value as TokenCacheStore).set === 'function' &&
        typeof (value as TokenCacheStore).delete === 'function',
      'store must implement TokenCacheStore',
    ),
    tokenCache: z.custom<SingleFlightCache<CanonicalResourceKey, TokenResponse>>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as SingleFlightCache<CanonicalResourceKey, TokenResponse>).get === 'function' &&
        typeof (value as SingleFlightCache<CanonicalResourceKey, TokenResponse>).set === 'function' &&
        typeof (value as SingleFlightCache<CanonicalResourceKey, TokenResponse>).peek === 'function' &&
        typeof (value as SingleFlightCache<CanonicalResourceKey, TokenResponse>).delete === 'function' &&
        typeof (value as SingleFlightCache<CanonicalResourceKey, TokenResponse>).clear === 'function',
      'tokenCache must be a SingleFlightCache',
    ),
    clock: z.custom<AuthClock>(
      value => typeof value === 'object' && value !== null && typeof (value as AuthClock).now === 'function',
      'clock must implement AuthClock',
    ),
    problems: z.custom<Pick<AuthProblems, 'AuthRefreshFailed'>>(
      value => typeof value === 'object' && value !== null && 'AuthRefreshFailed' in value,
      'problems must include AuthRefreshFailed',
    ),
    concurrency: z.number().int().min(1).max(64).optional(),
    skew: fixedDurationSchema.optional(),
    mapError: z.custom<(error: unknown) => Problem>(value => typeof value === 'function').optional(),
  })
  .strict();

const authProviderSchema = z.custom<AuthProvider>(
  value => typeof value === 'object' && value !== null && typeof (value as AuthProvider).getAccessToken === 'function',
  'provider must implement AuthProvider',
);

const tokenResponseSchema = z
  .object({
    token: z.string().min(1),
    expiresAt: z.custom<Temporal.Instant>(
      value => value instanceof Temporal.Instant,
      'expiresAt must be a Temporal.Instant',
    ),
  })
  .strict();

function fallbackProblem(error: unknown): Problem {
  return {
    type: 'about:blank',
    title: 'Authentication resource configuration failed',
    status: 500,
    detail: error instanceof Error ? error.message : 'The authentication resource configuration is invalid.',
    data: {},
  };
}

function configuredMapError(input: unknown): (error: unknown) => Problem {
  if (typeof input === 'object' && input !== null) {
    if ('mapError' in input && typeof input.mapError === 'function') {
      return input.mapError as (error: unknown) => Problem;
    }
    if ('problems' in input && typeof input.problems === 'object' && input.problems !== null) {
      const problems = input.problems as Partial<Pick<AuthProblems, 'AuthRefreshFailed'>>;
      if (problems.AuthRefreshFailed !== undefined) {
        return error =>
          createAuthRefreshFailed(
            problems as Pick<AuthProblems, 'AuthRefreshFailed'>,
            error instanceof Error ? error.message : 'The authentication resource operation failed.',
          );
      }
    }
  }
  return fallbackProblem;
}

function canonicalResourceKeyOf(resource: ResourceKey): CanonicalResourceKey {
  return `${resource.platform}/${resource.landscape}/${resource.service}/${resource.resourceName}`;
}

function resourceAudienceOf(resource: ResourceKey): string {
  return `https://${resource.resourceName}.${resource.service}.${resource.platform}.${resource.landscape}.cluster.atomi.cloud`;
}

function cloneResource(resource: ResourceKey): ResourceKey {
  return Object.freeze({ ...resource });
}

function cloneRegistration(registration: BackendRegistration): BackendRegistration {
  return Object.freeze({
    backendId: registration.backendId,
    resources: Object.freeze(registration.resources.map(cloneResource)),
    onboardingResource: cloneResource(registration.onboardingResource),
  });
}

function findBackend(bindings: readonly BackendRegistration[], backendId: string): BackendRegistration | undefined {
  return bindings.find(binding => binding.backendId === backendId);
}

function isFresh(response: TokenResponse, clock: AuthClock, skew: Temporal.Duration): boolean {
  return Temporal.Instant.compare(clock.now(), response.expiresAt.subtract(skew)) < 0;
}

function validateResourceInput(input: unknown, mapError: (error: unknown) => Problem): Result<ResourceKey, Problem> {
  const parsed = resourceKeySchema.safeParse(input);
  return parsed.success ? Ok(Object.freeze(parsed.data)) : Err(mapError(new Error(z.prettifyError(parsed.error))));
}

function parseBackendId(input: unknown, mapError: (error: unknown) => Problem): Result<string, Problem> {
  const parsed = backendIdSchema.safeParse(input);
  return parsed.success ? Ok(parsed.data) : Err(mapError(new Error(z.prettifyError(parsed.error))));
}

/** Validate a public resource value without throwing. */
export function validateResourceKey(
  resource: unknown,
  problems?: Pick<AuthProblems, 'AuthRefreshFailed'>,
): Result<ResourceKey, Problem> {
  const mapError =
    problems === undefined
      ? fallbackProblem
      : (error: unknown) =>
          createAuthRefreshFailed(
            problems,
            error instanceof Error ? error.message : 'The authentication resource is invalid.',
          );
  return validateResourceInput(resource, mapError);
}

/** Parse and canonicalize a public resource value without throwing. */
export function canonicalResourceKey(
  resource: unknown,
  problems?: Pick<AuthProblems, 'AuthRefreshFailed'>,
): Result<CanonicalResourceKey, Problem> {
  return validateResourceKey(resource, problems).map(canonicalResourceKeyOf);
}

/** Parse a public resource value and build its audience without throwing. */
export function resourceAudience(
  resource: unknown,
  problems?: Pick<AuthProblems, 'AuthRefreshFailed'>,
): Result<string, Problem> {
  return validateResourceKey(resource, problems).map(resourceAudienceOf);
}

/**
 * Build a ready, immutable resource tree. Binding/configuration validation is
 * Result-typed and happens before an instance is exposed.
 */
export function createResourceTree(provider: unknown, input: unknown): Result<ResourceTree, Problem> {
  const mapError = configuredMapError(input);
  const parsedProvider = authProviderSchema.safeParse(provider);
  if (!parsedProvider.success) return Err(mapError(new Error(z.prettifyError(parsedProvider.error))));
  const parsedOptions = resourceTreeOptionsSchema.safeParse(input);
  if (!parsedOptions.success) return Err(mapError(new Error(z.prettifyError(parsedOptions.error))));

  const options = parsedOptions.data as ResourceTreeOptions;
  const immutableOptions: ResourceTreeOptions = Object.freeze({
    ...options,
    bindings: Object.freeze(options.bindings.map(cloneRegistration)),
    concurrency: options.concurrency ?? 8,
    skew: options.skew ?? DEFAULT_TOKEN_CACHE_SKEW,
    mapError,
  });
  return Ok(new ResourceTreeService(parsedProvider.data, immutableOptions));
}

class ResourceTreeService implements ResourceTree {
  readonly #provider: AuthProvider;
  readonly #store: TokenCacheStore;
  readonly #cache: SingleFlightCache<CanonicalResourceKey, TokenResponse>;
  readonly #bindings: readonly BackendRegistration[];
  readonly #concurrency: number;
  readonly #clock: AuthClock;
  readonly #skew: Temporal.Duration;
  readonly #mapError: (error: unknown) => Problem;

  constructor(provider: AuthProvider, options: ResourceTreeOptions) {
    this.#provider = provider;
    this.#store = options.store;
    this.#cache = options.tokenCache;
    this.#bindings = options.bindings;
    this.#concurrency = options.concurrency ?? 8;
    this.#clock = options.clock;
    this.#skew = options.skew ?? DEFAULT_TOKEN_CACHE_SKEW;
    this.#mapError = options.mapError ?? configuredMapError(options);
  }

  getBackend(backendId: unknown): Result<BackendRegistration, Problem> {
    return parseBackendId(backendId, this.#mapError).andThen(validated => {
      const backend = findBackend(this.#bindings, validated);
      return backend === undefined ? Err(this.#mapError(new Error(`Unknown backend ${validated}`))) : Ok(backend);
    });
  }

  listBackends(): readonly BackendRegistration[] {
    return this.#bindings;
  }

  getToken(resource: unknown): Result<TokenResponse, Problem> {
    return validateResourceInput(resource, this.#mapError).andThen(validated => {
      const key = canonicalResourceKeyOf(validated);
      return this.#cache.get(key, () =>
        Res.async(async () => {
          try {
            const stored = await this.#store.get(key).serial();
            if (stored[0] === 'err') return Err(stored[1]);
            if (stored[1] !== undefined) {
              const parsedStored = tokenResponseSchema.safeParse(stored[1]);
              if (!parsedStored.success) {
                return Err(this.#mapError(new Error(z.prettifyError(parsedStored.error))));
              }
              if (isFresh(parsedStored.data, this.#clock, this.#skew)) {
                return Ok({ value: parsedStored.data, expiresAt: parsedStored.data.expiresAt });
              }
            }

            const acquired = await this.#provider.getAccessToken(resourceAudienceOf(validated)).serial();
            if (acquired[0] === 'err') return Err(acquired[1]);
            const parsedAcquired = tokenResponseSchema.safeParse(acquired[1]);
            if (!parsedAcquired.success) {
              return Err(this.#mapError(new Error(z.prettifyError(parsedAcquired.error))));
            }
            const persisted = await this.#store.set(key, parsedAcquired.data).serial();
            if (persisted[0] === 'err') return Err(persisted[1]);
            return Ok({ value: parsedAcquired.data, expiresAt: parsedAcquired.data.expiresAt });
          } catch (error: unknown) {
            return Err(this.#mapError(error));
          }
        }),
      );
    });
  }

  fetchAllTokens(): Result<TokenBatch, Problem> {
    return Res.async(async () => {
      const resources = new Map<CanonicalResourceKey, ResourceKey>();
      for (const backend of this.#bindings) {
        for (const resource of backend.resources) resources.set(canonicalResourceKeyOf(resource), resource);
      }

      try {
        const entries = await mapWithConcurrency(
          [...resources.entries()],
          this.#concurrency,
          async ([key, resource]) => {
            const result = await this.getToken(resource).serial();
            return [key, result[1]] as const;
          },
        );
        return Ok(Object.freeze(Object.fromEntries(entries)) as TokenBatch);
      } catch (error: unknown) {
        return Err(this.#mapError(error));
      }
    });
  }

  backendTokens(batch: TokenBatch, backendId: unknown): Result<BackendTokenBatch, Problem> {
    return this.getBackend(backendId).andThen(backend => {
      const entries: [CanonicalResourceKey, TokenResponse][] = [];
      for (const resource of backend.resources) {
        const key = canonicalResourceKeyOf(resource);
        const entry = batch[key];
        if (entry === undefined) return Err(this.#mapError(new Error(`Token batch omitted ${key}`)));
        if (isProblem(entry)) return Err(entry);
        const parsed = tokenResponseSchema.safeParse(entry);
        if (!parsed.success) return Err(this.#mapError(new Error(z.prettifyError(parsed.error))));
        entries.push([key, parsed.data]);
      }
      return Ok(Object.freeze(Object.fromEntries(entries)) as BackendTokenBatch);
    });
  }

  fetchBackendTokens(backendId: unknown): Result<BackendTokenBatch, Problem> {
    return this.getBackend(backendId).andThen(backend =>
      Res.async(async () => {
        try {
          const entries = await mapWithConcurrency(backend.resources, this.#concurrency, async resource => {
            const key = canonicalResourceKeyOf(resource);
            const result = await this.getToken(resource).serial();
            return [key, result] as const;
          });
          const tokens: [CanonicalResourceKey, TokenResponse][] = [];
          for (const [key, result] of entries) {
            if (result[0] === 'err') return Err(result[1]);
            tokens.push([key, result[1]]);
          }
          return Ok(Object.freeze(Object.fromEntries(tokens)) as BackendTokenBatch);
        } catch (error: unknown) {
          return Err(this.#mapError(error));
        }
      }),
    );
  }

  invalidate(resource: unknown): Result<void, Problem> {
    return validateResourceInput(resource, this.#mapError).andThen(validated =>
      Res.async(async () => {
        try {
          const key = canonicalResourceKeyOf(validated);
          this.#cache.delete(key);
          return this.#store.delete(key);
        } catch (error: unknown) {
          return Err(this.#mapError(error));
        }
      }),
    );
  }

  invalidateAll(): Result<void, Problem> {
    return Res.async(async () => {
      try {
        this.#cache.clear();
        if (this.#store.clear !== undefined) return this.#store.clear();

        const keys = new Set(this.#bindings.flatMap(backend => backend.resources.map(canonicalResourceKeyOf)));
        for (const key of keys) {
          const deleted = await this.#store.delete(key).serial();
          if (deleted[0] === 'err') return Err(deleted[1]);
        }
        return Ok(undefined);
      } catch (error: unknown) {
        return Err(this.#mapError(error));
      }
    });
  }
}
