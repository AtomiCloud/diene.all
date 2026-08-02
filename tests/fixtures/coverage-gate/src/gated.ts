// Stand-in for a real source file, measured by the fixture ledger only. Nothing in the application
// imports it — its whole job is to have a function that goes uncovered when a test is skipped.

export function alwaysMeasured(value: number): number {
  return value + 1;
}

export function measuredOnlyWhileTheSuiteRuns(value: number): number {
  return value * 2;
}
