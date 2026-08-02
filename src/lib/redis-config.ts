import { z } from 'zod';
import type { RedisConnection } from '../adapters/kv-store';

const DEFAULT_REDIS_PORT = 6379;
const MIN_PORT = 1;
const MAX_PORT = 65535;

/** The slice of the process environment this module reads. */
export interface RedisEnvironment {
  readonly [name: string]: string | undefined;
}

export type RedisConfigResult =
  | { readonly ok: true; readonly connection: RedisConnection | undefined }
  | { readonly ok: false; readonly issues: readonly string[] };

/**
 * A variable that is present but blank carries no more information than an absent one, so both
 * collapse to `undefined` before validation and let the defaults apply.
 */
function blankAsUnset(value: unknown): unknown {
  return typeof value === 'string' && value.trim() === '' ? undefined : value;
}

const redisEnvironmentSchema = z.object({
  REDIS_HOST: z.preprocess(blankAsUnset, z.string().trim().optional()),
  REDIS_PORT: z.preprocess(
    blankAsUnset,
    z
      .string()
      .trim()
      .regex(/^\d+$/, 'must be a whole number, for example 6379')
      .transform(Number)
      .refine(port => port >= MIN_PORT && port <= MAX_PORT, `must be between ${MIN_PORT} and ${MAX_PORT}`)
      .default(DEFAULT_REDIS_PORT),
  ),
});

/**
 * Total function: invalid configuration comes back as readable issues instead of an exception, so
 * the caller decides how to report it.
 *
 * A missing host is not an error — it means "run without Redis", which is the sample's default.
 */
export function parseRedisEnvironment(environment: RedisEnvironment): RedisConfigResult {
  const parsed = redisEnvironmentSchema.safeParse(environment);

  if (!parsed.success) {
    return {
      ok: false,
      issues: parsed.error.issues.map(issue => `${issue.path.join('.')} ${issue.message}`),
    };
  }

  const { REDIS_HOST: host, REDIS_PORT: port } = parsed.data;
  return { ok: true, connection: host === undefined ? undefined : { host, port } };
}
