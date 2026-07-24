import { coerceScalar, normalizeKey } from './coerce.js';
import { type ConfigRecord, isRecord } from './merge.js';

/**
 * Runtime / build-time environment overlay.
 *
 * A flat env record (`{ ATOMI_SERVER__PORT: '8080', ... }`) is projected onto an
 * already-merged config object. Each prefixed key is split on `__` into a path;
 * path segments match existing object keys case- and separator-insensitively
 * (snake ↔ Pascal/camel/kebab); numeric segments index into arrays (indexed-key
 * list encoding, `FOO__0`/`FOO__1`); values are coerced (`coerce.ts`); blank
 * values are dropped (M33). The env tier is applied LAST so it wins over every
 * file tier. Neither input is mutated — a deep clone is returned.
 */

/** Separator between path segments inside a prefixed env key. */
export const NESTING_SEPARATOR = '__';

/** Upper bound on an indexed-list position, guarding against runaway growth. */
const MAX_INDEX = 4096;

type Container = ConfigRecord | unknown[];

const isIndex = (segment: string): boolean => /^\d+$/.test(segment);

/** Resolve the existing object key matching `segment`, else the lowercased segment. */
const resolveObjectKey = (container: ConfigRecord, segment: string): string => {
  const target = normalizeKey(segment);
  for (const key of Object.keys(container)) {
    if (normalizeKey(key) === target) return key;
  }
  return segment.toLowerCase();
};

const growArray = (array: unknown[], index: number): void => {
  while (array.length <= index) array.push(undefined);
};

const childAt = (container: Container, key: string | number): unknown =>
  Array.isArray(container) ? container[key as number] : container[key as string];

const assign = (container: Container, key: string | number, value: unknown): void => {
  if (Array.isArray(container)) container[key as number] = value;
  else container[key as string] = value;
};

/** Recursively place `value` at `segments`, creating intermediate containers. */
const setAtPath = (container: Container, segments: readonly string[], value: unknown): void => {
  const head = segments[0];
  if (head === undefined) return;

  let key: string | number;
  if (Array.isArray(container)) {
    if (!isIndex(head)) return; // non-numeric segment into an array is malformed
    key = Number.parseInt(head, 10);
    if (key > MAX_INDEX) return;
    growArray(container, key);
  } else {
    key = resolveObjectKey(container, head);
  }

  if (segments.length === 1) {
    assign(container, key, value);
    return;
  }

  const nextIsIndex = isIndex(segments[1] as string);
  const existing = childAt(container, key);
  const child: Container = isRecord(existing) || Array.isArray(existing) ? existing : nextIsIndex ? [] : {};
  assign(container, key, child);
  setAtPath(child, segments.slice(1), value);
};

/**
 * Return a deep clone of `merged` with every `prefix`-prefixed variable in `env`
 * overlaid. Blank values are skipped (M33). Segments that are empty (a malformed
 * key such as a trailing `__`) are ignored.
 */
export const applyEnvOverrides = (
  merged: ConfigRecord,
  env: Record<string, string | undefined>,
  prefix: string,
): ConfigRecord => {
  const result = structuredClone(merged);
  for (const [rawKey, rawValue] of Object.entries(env)) {
    if (!rawKey.startsWith(prefix) || rawValue === undefined) continue;
    const coerced = coerceScalar(rawValue);
    if (coerced === undefined) continue; // blank env value = unset (M33)
    const segments = rawKey.slice(prefix.length).split(NESTING_SEPARATOR);
    if (segments.length === 0 || segments.some(segment => segment === '')) continue;
    setAtPath(result, segments, coerced);
  }
  return result;
};
