import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import type { AuthClock } from './provider';

export const DEFAULT_TOKEN_CACHE_SKEW = Temporal.Duration.from({ seconds: 30 });

export interface CacheEntry<V> {
  readonly value: V;
  readonly expiresAt: Temporal.Instant;
}

export interface SingleFlightCacheOptions<K, V> {
  readonly coordinator: SingleFlightCoordinator<K, V>;
  readonly clock: AuthClock;
  readonly skew?: Temporal.Duration;
  readonly mapError?: (error: unknown) => Problem;
}

/** Ready cache behavior exposed only through {@link createSingleFlightCache}. */
export interface SingleFlightCache<K, V> {
  readonly size: number;
  get(key: K, fetcher: () => Result<CacheEntry<V>, Problem>): Result<V, Problem>;
  set(key: K, entry: CacheEntry<V>): Result<void, Problem>;
  peek(key: K): CacheEntry<V> | undefined;
  delete(key: K): boolean;
  clear(): void;
}

export type CacheSlot<V> = CacheEntry<V> | { readonly inFlight: Promise<ResultSerial<CacheEntry<V>, Problem>> };

/** Mutable cache/flight state lives behind this injected port. */
export interface SingleFlightCoordinator<K, V> {
  readonly size: number;
  get(key: K): CacheSlot<V> | undefined;
  set(key: K, slot: CacheSlot<V>): void;
  delete(key: K): boolean;
  clear(): void;
}

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

const cacheOptionsSchema = z
  .object({
    coordinator: z.custom<SingleFlightCoordinator<unknown, unknown>>(
      value =>
        typeof value === 'object' &&
        value !== null &&
        typeof (value as SingleFlightCoordinator<unknown, unknown>).get === 'function' &&
        typeof (value as SingleFlightCoordinator<unknown, unknown>).set === 'function' &&
        typeof (value as SingleFlightCoordinator<unknown, unknown>).delete === 'function' &&
        typeof (value as SingleFlightCoordinator<unknown, unknown>).clear === 'function',
      'coordinator must implement SingleFlightCoordinator',
    ),
    clock: z.custom<AuthClock>(
      value => typeof value === 'object' && value !== null && typeof (value as AuthClock).now === 'function',
      'clock must implement AuthClock',
    ),
    skew: fixedDurationSchema.optional(),
    mapError: z.custom<(error: unknown) => Problem>(value => typeof value === 'function').optional(),
  })
  .strict();

const cacheEntrySchema = z
  .object({
    value: z.unknown(),
    expiresAt: z.custom<Temporal.Instant>(
      value => value instanceof Temporal.Instant,
      'expiresAt must be a Temporal.Instant',
    ),
  })
  .strict();

function isInFlight<V>(
  slot: CacheSlot<V>,
): slot is { readonly inFlight: Promise<ResultSerial<CacheEntry<V>, Problem>> } {
  return 'inFlight' in slot;
}

function defaultMapError(error: unknown): Problem {
  return {
    type: 'about:blank',
    title: 'Cache refresh failed',
    status: 500,
    detail: error instanceof Error ? error.message : 'The cache refresh failed.',
    data: {},
  };
}

function configuredMapError(input: unknown): (error: unknown) => Problem {
  if (typeof input === 'object' && input !== null && 'mapError' in input && typeof input.mapError === 'function') {
    return input.mapError as (error: unknown) => Problem;
  }
  return defaultMapError;
}

function isFresh<V>(entry: CacheEntry<V>, clock: AuthClock, skew: Temporal.Duration): boolean {
  return Temporal.Instant.compare(clock.now(), entry.expiresAt.subtract(skew)) < 0;
}

/**
 * Schema-validating composition factory. The returned cache is ready to use;
 * callers never need a separate state-registration step.
 */
export function createSingleFlightCache<K, V>(input: unknown): Result<SingleFlightCache<K, V>, Problem> {
  const parsed = cacheOptionsSchema.safeParse(input);
  if (!parsed.success) return Err(configuredMapError(input)(new Error(z.prettifyError(parsed.error))));
  const options = parsed.data as SingleFlightCacheOptions<K, V>;
  return Ok(new SingleFlightCacheService(options));
}

/** Expiry-aware keyed cache that shares one refresh promise among concurrent callers. */
class SingleFlightCacheService<K, V> implements SingleFlightCache<K, V> {
  readonly #coordinator: SingleFlightCoordinator<K, V>;
  readonly #clock: AuthClock;
  readonly #skew: Temporal.Duration;
  readonly #mapError: (error: unknown) => Problem;

  constructor(options: SingleFlightCacheOptions<K, V>) {
    this.#coordinator = options.coordinator;
    this.#clock = options.clock;
    this.#skew = options.skew ?? DEFAULT_TOKEN_CACHE_SKEW;
    this.#mapError = options.mapError ?? defaultMapError;
  }

  get size(): number {
    return this.#coordinator.size;
  }

  get(key: K, fetcher: () => Result<CacheEntry<V>, Problem>): Result<V, Problem> {
    return Res.async<V, Problem>(async () => {
      let slot: { readonly inFlight: Promise<ResultSerial<CacheEntry<V>, Problem>> } | undefined;
      try {
        const current = this.#coordinator.get(key);
        if (current !== undefined) {
          if (isInFlight(current)) {
            const shared = await current.inFlight;
            return shared[0] === 'ok' ? Ok<V, Problem>(shared[1].value) : Err<V, Problem>(shared[1]);
          }
          if (isFresh(current, this.#clock, this.#skew)) return Ok(current.value);
        }

        const inFlight = fetcher().serial();
        slot = Object.freeze({ inFlight });
        this.#coordinator.set(key, slot);

        const result = await inFlight;
        if (result[0] === 'err') {
          if (this.#coordinator.get(key) === slot) this.#coordinator.delete(key);
          return Err(result[1]);
        }

        const parsed = cacheEntrySchema.safeParse(result[1]);
        if (!parsed.success) {
          if (this.#coordinator.get(key) === slot) this.#coordinator.delete(key);
          return Err(this.#mapError(new Error(z.prettifyError(parsed.error))));
        }
        if (this.#coordinator.get(key) === slot) this.#coordinator.set(key, result[1]);
        return Ok(result[1].value);
      } catch (error: unknown) {
        if (slot !== undefined && this.#coordinator.get(key) === slot) this.#coordinator.delete(key);
        return Err(this.#mapError(error));
      }
    });
  }

  set(key: K, entry: CacheEntry<V>): Result<void, Problem> {
    const parsed = cacheEntrySchema.safeParse(entry);
    if (!parsed.success) return Err(this.#mapError(new Error(z.prettifyError(parsed.error))));
    try {
      this.#coordinator.set(key, entry);
      return Ok(undefined);
    } catch (error: unknown) {
      return Err(this.#mapError(error));
    }
  }

  peek(key: K): CacheEntry<V> | undefined {
    const slot = this.#coordinator.get(key);
    return slot === undefined || isInFlight(slot) ? undefined : slot;
  }

  delete(key: K): boolean {
    return this.#coordinator.delete(key);
  }

  clear(): void {
    this.#coordinator.clear();
  }
}
