/**
 * Narrow a value to a plain record: a non-null object that is not an array.
 */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalize(value: unknown, seen: WeakSet<object>): unknown {
  if (Array.isArray(value)) {
    if (seen.has(value)) {
      throw new TypeError('stableConfig cannot process a circular structure');
    }
    seen.add(value);
    const mapped = value.map(item => normalize(item, seen));
    seen.delete(value);
    return mapped;
  }

  if (isRecord(value)) {
    if (seen.has(value)) {
      throw new TypeError('stableConfig cannot process a circular structure');
    }
    seen.add(value);
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value).sort()) {
      sorted[key] = normalize(value[key], seen);
    }
    seen.delete(value);
    return sorted;
  }

  return value;
}

/**
 * Produce a deterministic clone of a config-like value.
 *
 * Plain-record keys are recursively re-emitted in sorted order while array
 * element order is preserved and primitives pass through untouched. Circular
 * references are rejected with a {@link TypeError} rather than recursing
 * forever; a value shared across sibling branches (a non-cyclic DAG) is fine.
 */
export function stableConfig(value: unknown): unknown {
  return normalize(value, new WeakSet<object>());
}
