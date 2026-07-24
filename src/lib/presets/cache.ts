import type { z } from 'zod';
import { keyedPreset } from './keyed';
import { type RedisConnectionEntry, redisConnectionEntry } from './redis';

/**
 * A single named cache connection. Cache is Dragonfly: RAM-backed and
 * EPHEMERAL — losing it must never lose durable state. Redis protocol.
 */
export const cacheEntry = redisConnectionEntry;

/** One named cache connection entry. */
export type CacheEntry = RedisConnectionEntry;

/**
 * The `cache` preset: a keyed map of named cache endpoints (`MAIN`, `SESSION`, …).
 * Distinct from {@link kv} despite the shared Redis protocol — cache is
 * ephemeral, kv is persistent.
 *
 * C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go.
 */
export const cache = keyedPreset(cacheEntry);

/** The resolved `cache` block: `Record<UPPERCASE_NAME, CacheEntry>`. */
export type CacheBlock = z.infer<typeof cache>;
