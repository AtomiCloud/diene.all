// This fixture exposes a function that the sabotage deliberately leaves uncovered.

export function alwaysMeasured(value: number): number {
  return value + 1;
}

export function measuredOnlyWhileTheSuiteRuns(value: number): number {
  return value * 2;
}
