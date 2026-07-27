import type { z } from 'zod';
import { keyedPreset } from './keyed';
import { type RedisConnectionEntry, redisConnectionEntry } from './redis';

/**
 * A single named kv connection. kv is PERSISTENT (Upstash cloud; the lapras
 * realization is Dragonfly with SNAPSHOT durability — Q-A2-amended: AOF does not
 * exist upstream, so kv is a distinct snapshot-persisted instance, NOT a relabel
 * of {@link cache}). Redis protocol.
 */
export const kvEntry = redisConnectionEntry;

/** One named kv connection entry. */
export type KvEntry = RedisConnectionEntry;

/**
 * The `kv` preset: a keyed map of named persistent kv endpoints. SEPARATE preset
 * from {@link cache} — the durability contract differs even though the Redis
 * connection fields are identical.
 *
 * C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go.
 */
export const kv = keyedPreset(kvEntry);

/** The resolved `kv` block: `Record<UPPERCASE_NAME, KvEntry>`. */
export type KvBlock = z.infer<typeof kv>;
