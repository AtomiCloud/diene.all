function sameValueZero(a: unknown, b: unknown): boolean {
  // `===` covers every case except NaN (never `===` to itself) and treats
  // +0/-0 as equal, matching SameValueZero once NaN is handled. `Number.isNaN`
  // is true only for the actual NaN number, so non-number values fall through
  // to the `===` result exactly as SameValueZero requires.
  return a === b || (Number.isNaN(a) && Number.isNaN(b));
}

/**
 * `Array.prototype.filter` predicate that keeps the first occurrence of each
 * value using SameValueZero equality (so `NaN` de-duplicates against `NaN`).
 *
 * @example
 * [1, 2, 2, 3].filter(unique); // [1, 2, 3]
 */
export function unique<T>(value: T, index: number, array: readonly T[]): boolean {
  return array.findIndex(candidate => sameValueZero(candidate, value)) === index;
}
