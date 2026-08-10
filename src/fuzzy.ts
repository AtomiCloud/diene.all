/**
 * Case-insensitive substring test.
 *
 * Returns `true` when `b` (the needle) appears anywhere within `a` (the
 * haystack), ignoring letter case. An empty needle is always contained.
 */
export function fuzzyIncludes(a: string, b: string): boolean {
  return a.toLowerCase().includes(b.toLowerCase());
}
