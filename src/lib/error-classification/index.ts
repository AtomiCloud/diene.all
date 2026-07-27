import type { Problem, ProblemCatalogEntry } from '@atomicloud/diene.problems';

/**
 * Catalog-driven error classification (product-thoughtfulness #6): the
 * per-endpoint Problem catalog fetched from the edge channel drives
 * recoverable-vs-fatal UX. Uncatalogued problems are treated as 5xx-fatal AND
 * reported so they feed the catalog loop.
 */

type ErrorTier =
  /** Tier 1: inline retry — recoverable, the control retries in place. */
  | 'recoverable'
  /** Tier 2: stay-on-page error surface. */
  | 'fatal'
  /** Tier 3: uncatalogued — full failure + copy-error + catalog-loop report. */
  | 'uncatalogued';

export interface Classification {
  readonly tier: ErrorTier;
  readonly entry?: ProblemCatalogEntry;
}

/** Look up a Problem in the catalog copy and classify it. Pure. */
export const classifyProblem = (problem: Problem, catalog: readonly ProblemCatalogEntry[]): Classification => {
  const entry = catalog.find(candidate => candidate.type === problem.type);
  if (entry === undefined) return { tier: 'uncatalogued' };
  return { tier: entry.recoverable ? 'recoverable' : 'fatal', entry };
};
