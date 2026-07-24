import { z } from 'zod';

/**
 * Environment-variable value coercion for the config loader.
 *
 * Family contract (R14, M31, M33):
 * - Environment values arrive as strings. `true`/`false` (case-insensitive)
 *   become booleans; clean integer/decimal strings become numbers.
 * - Number conversion goes through zod (`z.coerce.number`), never a hand-rolled
 *   `Number()` — M31.
 * - A blank value means "unset": it is dropped, not written as an empty string
 *   — M33.
 * - There is NO JSON-in-env: objects and arrays are expressed with indexed keys
 *   (`FOO__0`, `FOO__1`), never an encoded JSON literal.
 */

const NUMERIC = /^-?\d+(?:\.\d+)?$/;
const numberCoercer = z.coerce.number();

/**
 * Normalize a key for case- and separator-insensitive matching so a
 * snake_case env segment matches a snake / PascalCase / camelCase / kebab-case
 * object key. `MAX_RETRIES`, `maxRetries`, `MaxRetries`, and `max-retries` all
 * normalize to `maxretries`.
 */
export const normalizeKey = (key: string): string => key.replace(/[_-]/g, '').toLowerCase();

/**
 * Coerce a single raw environment value into its typed scalar.
 *
 * Returns `undefined` when the value is blank (M33 unset). Booleans and clean
 * numbers are coerced; every other string is preserved verbatim.
 */
export const coerceScalar = (raw: string): string | number | boolean | undefined => {
  if (raw === '') return undefined;
  const lowered = raw.toLowerCase();
  if (lowered === 'true') return true;
  if (lowered === 'false') return false;
  if (NUMERIC.test(raw)) {
    const parsed = numberCoercer.safeParse(raw);
    if (parsed.success) return parsed.data;
  }
  return raw;
};
