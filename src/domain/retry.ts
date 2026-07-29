export const MAX_RETRY_WINDOW_MS = 72 * 60 * 60 * 1000;
const DEFAULT_INITIAL_RETRY_DELAY_MS = 5_000;
const DEFAULT_MAX_RETRY_DELAY_MS = 6 * 60 * 60 * 1000;
export const DEFAULT_CIRCUIT_FAILURE_WINDOW_MS = 24 * 60 * 60 * 1000;

export interface RetryDecisionInput {
  readonly attemptNumber: number;
  readonly createdAtMs: number;
  readonly nowMs: number;
  readonly retryWindowMs: number;
  readonly initialDelayMs?: number;
  readonly maxDelayMs?: number;
}

export type RetryDecision =
  | Readonly<{ kind: 'dead-letter' }>
  | Readonly<{ dueAtMs: number; kind: 'retry'; delayMs: number }>;

export const boundedRetryWindowMs = (configuredMs: number): number =>
  Math.max(0, Math.min(configuredMs, MAX_RETRY_WINDOW_MS));

export const nextRetry = (input: RetryDecisionInput): RetryDecision => {
  const initialDelayMs = input.initialDelayMs ?? DEFAULT_INITIAL_RETRY_DELAY_MS;
  const maxDelayMs = input.maxDelayMs ?? DEFAULT_MAX_RETRY_DELAY_MS;
  const exponent = Math.max(0, input.attemptNumber - 1);
  const delayMs = Math.min(initialDelayMs * 2 ** exponent, maxDelayMs);
  const deadlineMs = input.createdAtMs + boundedRetryWindowMs(input.retryWindowMs);
  const dueAtMs = input.nowMs + delayMs;

  if (input.nowMs >= deadlineMs || dueAtMs > deadlineMs) {
    return { kind: 'dead-letter' };
  }

  return { dueAtMs, kind: 'retry', delayMs };
};
