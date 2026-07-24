import { z } from 'zod';

/**
 * Connection-pool names are UPPERCASE by contract (R14, C0 §3). A preset is a
 * keyed map of named connections — `MAIN`, `REPLICA`, `ANALYTICS` — so adding a
 * second instance is pure YAML, never a schema change (keyed multi-instance).
 */
export const UPPERCASE_KEY = /^[A-Z][A-Z0-9_]*$/;

/**
 * The shared error for this library. Kept deliberately small — presets validate
 * through zod (surfaced as `ConfigValidationError` by the config lib); this is
 * only for the few imperative helpers (keyed lookup, storage IO).
 */
export class StandardConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StandardConfigError';
  }
}

/**
 * Wrap an entry schema as a keyed map of named connections whose keys MUST be
 * UPPERCASE. This is the one shape every infra preset takes, so a service adds a
 * named instance (`MAIN` → `REPLICA`) by editing YAML alone — no schema surgery.
 */
export const keyedPreset = <T extends z.ZodType>(entry: T): z.ZodType<Record<string, z.infer<T>>> =>
  z.record(
    z.string().regex(UPPERCASE_KEY, 'connection-pool names must be UPPERCASE (R14)'),
    entry,
  ) as unknown as z.ZodType<Record<string, z.infer<T>>>;

/**
 * Fail-fast keyed lookup over a resolved preset block, so `named(config('postgres'), 'MAIN')`
 * reads like `postgres('MAIN')`. Throws `StandardConfigError` naming the known
 * keys when the connection is absent — a config typo fails loudly at use, not
 * silently as `undefined`.
 */
export const named = <T>(block: Record<string, T>, key: string): T => {
  const entry = block[key];
  if (entry === undefined) {
    const have = Object.keys(block);
    const known = have.length > 0 ? have.join(', ') : '(none registered)';
    throw new StandardConfigError(`no "${key}" connection in this block; known keys: ${known}`);
  }
  return entry;
};
