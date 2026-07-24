import { z } from 'zod';

/**
 * The Redis-protocol connection shape shared by the `cache` and `kv` presets.
 *
 * Cache (Dragonfly) and kv (Upstash / lapras dragonfly-with-snapshot) both speak
 * the Redis protocol, so the CONNECTION fields are identical — but they are
 * deliberately SEPARATE presets registered under distinct root keys, because
 * their durability semantics differ (cache = RAM-backed, EPHEMERAL; kv =
 * PERSISTENT, snapshot durability). Sharing this entry shape is an internal
 * detail; the cache-may-not-be-relabeled-KV rule holds at the block boundary.
 *
 * `password` is a secret: blank-in-yaml (R14/M33).
 */
export const redisConnectionEntry = z.object({
  /** Hostname of the Redis-protocol endpoint. */
  host: z.string().min(1),
  /** TCP port. */
  port: z.number().int().min(1).max(65535),
  /** Secret — blank-in-yaml, injected per landscape (R14/M33). */
  password: z.string(),
  /** Logical database index (Redis `SELECT`). */
  db: z.number().int().min(0),
  /** Whether to require TLS on the connection. */
  tls: z.boolean(),
});

/** One named Redis-protocol connection entry (cache or kv). */
export type RedisConnectionEntry = z.infer<typeof redisConnectionEntry>;
