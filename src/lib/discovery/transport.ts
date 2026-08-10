import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { notAConnectFailure } from './errors';
import type { DiscoveryError, RescueTripToken, Transport, TransportOutcome } from './types';

/** A network error is retryable: a soft timeout or a hard connect-failure. */
const isNetworkError = (outcome: TransportOutcome): boolean =>
  outcome.kind === 'timeout' || outcome.kind === 'connect-failure';

/** The single hard-failure classifier: only `connect-failure` trips rescue. */
export const isHardConnectFailure = (outcome: TransportOutcome): boolean => outcome.kind === 'connect-failure';

/**
 * The ONLY failure-handling primitive on the HOT PATH: attempt once, and on a
 * network error (timeout or connect-failure) retry exactly once. HTTP responses
 * — including bad statuses — are never retried. Returns the final outcome.
 */
export const retryOnceOnNetworkError = async (transport: Transport, url: string): Promise<TransportOutcome> => {
  const first = await transport.fetch(url);
  if (!isNetworkError(first)) {
    return first;
  }
  return transport.fetch(url);
};

/**
 * Mint a rescue-trip token — the ONLY way to unlock a Doc C fetch. Succeeds iff
 * the outcome is a hard `connect-failure`; a soft/retryable error (or any
 * response) is rejected, so the dormant router (and Doc C) can never wake on
 * anything but a hard connect-failure.
 */
export const tripOnConnectFailure = (outcome: TransportOutcome): Result<RescueTripToken, DiscoveryError> => {
  if (!isHardConnectFailure(outcome)) {
    return Err(notAConnectFailure(outcome.kind));
  }
  return Ok(Object.freeze({ reason: 'hard-connect-failure' }));
};
