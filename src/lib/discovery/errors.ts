import type { DiscoveryError, TransportOutcome } from './types';

/**
 * Factories for the discovery problem catalogue. Each returns a frozen, typed
 * {@link DiscoveryError}; discovery code returns these through `Result`, never
 * throws them.
 */

export const malformedDoc = (doc: 'A' | 'B' | 'C', reason: string): DiscoveryError =>
  Object.freeze({ kind: 'malformed-doc', doc, reason });

export const staleVersion = (key: string, seen: number, incoming: number): DiscoveryError =>
  Object.freeze({ kind: 'stale-version', key, seen, incoming });

export const endpointNotHttps = (url: string): DiscoveryError => Object.freeze({ kind: 'endpoint-not-https', url });

export const endpointSuffixRejected = (url: string, host: string): DiscoveryError =>
  Object.freeze({ kind: 'endpoint-suffix-rejected', url, host });

export const endpointUnparseable = (url: string): DiscoveryError =>
  Object.freeze({ kind: 'endpoint-unparseable', url });

export const rescueDisabled = (context: string): DiscoveryError => Object.freeze({ kind: 'rescue-disabled', context });

export const rescueBudgetExhausted = (attempts: number, elapsedMs: number): DiscoveryError =>
  Object.freeze({ kind: 'rescue-budget-exhausted', attempts, elapsedMs });

export const noCandidateReachable = (attempts: number): DiscoveryError =>
  Object.freeze({ kind: 'no-candidate-reachable', attempts });

export const notAConnectFailure = (outcome: TransportOutcome['kind']): DiscoveryError =>
  Object.freeze({ kind: 'not-a-connect-failure', outcome });

export const noHomePicked = (chosen: string): DiscoveryError => Object.freeze({ kind: 'no-home-picked', chosen });

export const catalogFetchFailed = (host: string, reason: string): DiscoveryError =>
  Object.freeze({ kind: 'catalog-fetch-failed', host, reason });
