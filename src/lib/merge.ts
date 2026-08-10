import { isRecord } from '@atomicloud/diene.core-utils';

/** A plain JSON-shaped object; the tier layers the loader merges. */
export type ConfigRecord = { [key: string]: unknown };

/**
 * True for a plain object (not an array, not null) that can be deep-merged.
 * Re-exported from `@atomicloud/diene.core-utils` — the family's single
 * record-narrowing predicate.
 */
export { isRecord };

/**
 * Recursively merge `override` onto `base`, producing a new object.
 *
 * Plain-object values merge key-by-key; every other value (scalars, arrays,
 * `null`) replaces the base wholesale — arrays are never element-merged here
 * (per-index array overrides are an env-tier concern handled in `env.ts`).
 * Neither input is mutated.
 */
export const deepMerge = <T extends ConfigRecord>(base: T, override: ConfigRecord): T => {
  const out: ConfigRecord = { ...base };
  for (const [key, value] of Object.entries(override)) {
    const existing = out[key];
    out[key] = isRecord(existing) && isRecord(value) ? deepMerge(existing, value) : value;
  }
  return out as T;
};
