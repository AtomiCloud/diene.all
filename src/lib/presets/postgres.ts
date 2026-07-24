import { z } from 'zod';
import { keyedPreset } from './keyed';

/**
 * A single named Postgres connection. Provider-agnostic (Neon / CNPG / local
 * container all speak this shape); the provider matrix per landscape lives in
 * `goals/garden-environments.md`, never in the connection block.
 *
 * `password` is a secret: blank-in-yaml (R14), injected per landscape via the
 * env-override tier (M33 — a blank value is unset, so the base YAML placeholder
 * never survives when the landscape supplies the real secret).
 */
export const postgresEntry = z.object({
  /** Hostname of the Postgres endpoint. */
  host: z.string().min(1),
  /** TCP port. */
  port: z.number().int().min(1).max(65535),
  /** Database name. */
  database: z.string().min(1),
  /** Role/user name. */
  username: z.string().min(1),
  /** Secret — blank-in-yaml, injected per landscape (R14/M33). */
  password: z.string(),
  /** Whether to require TLS on the connection. */
  ssl: z.boolean(),
  /** Connection-pool sizing. */
  pool: z.object({
    min: z.number().int().min(0),
    max: z.number().int().min(1),
  }),
});

/** One named Postgres connection entry. */
export type PostgresEntry = z.infer<typeof postgresEntry>;

/**
 * The `postgres` preset: a keyed map of named connections (`MAIN`, `REPLICA`, …).
 * UPPERCASE keys are enforced by the schema; adding an instance is YAML only.
 *
 * C0-FROZEN (c0-contracts.md §3): this key set is matched key-for-key across the
 * bun / dotnet / go standard-config libraries — do not drift the keys.
 */
export const postgres = keyedPreset(postgresEntry);

/** The resolved `postgres` block: `Record<UPPERCASE_NAME, PostgresEntry>`. */
export type PostgresBlock = z.infer<typeof postgres>;
