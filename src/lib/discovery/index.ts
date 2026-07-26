/**
 * `discovery/` — the three-doc edge client (Doc A/B/C) and the dormant rescue
 * router (ARCHITECTURE §4, Posture B). Pure, React-free, SSR-safe domain core
 * with injected seams (Transport/Clock/Random/Wait/Storage) and no DI container.
 *
 * Lifecycles differ per doc:
 * - Doc A (fleet doc) — constantly refreshed, stale-while-revalidate, from baked seeds.
 * - Doc B (landscape selector) — fetched once at sign-up; drives ping-and-pick-home.
 * - Doc C (platform catalog) — DORMANT; fetched only during an actual rescue trip.
 *
 * The hot path holds one home hostname and only ever retries once on a network
 * error; the rescue router is a dormant layer that trips only on hard
 * connect-failure. The auth issuer is always baked, never doc-sourced, and every
 * doc-sourced URL is validated against the endpoint-suffix allowlist at use time.
 */

export { DEFAULT_ALLOWLIST, isHostAllowed, validateEndpoint } from './allowlist';
export { fetchProblemCatalog } from './catalog';
export {
  DOC_A_LEDGER_KEY,
  type DocARefreshResult,
  type DocASource,
  type RefreshDocAParams,
  refreshDocA,
} from './doc-a';
export { type AuthEngineHandoff, derivePingUrl, handoffToAuthEngine, pickHome, pingLandscapes } from './doc-b';
export { candidatesFor, DOC_C_LEDGER_KEY, type FetchDocCParams, fetchDocC } from './doc-c';
export { parseDocA, parseDocB, parseDocC } from './parse';
export {
  BROWSER_RESCUE_CONTEXT,
  checkHeal,
  createRescueContext,
  FLUTTER_RESCUE_CONTEXT,
  NEXTJS_SERVER_RESCUE_CONTEXT,
  type RunRescueParams,
  readLastKnownGood,
  runRescue,
} from './rescue';
export { isHardConnectFailure, retryOnceOnNetworkError, tripOnConnectFailure } from './transport';
export type {
  AllowlistConfig,
  Clock,
  DiscoveryError,
  DocA,
  DocB,
  DocBLandscape,
  DocC,
  DocCCandidateList,
  HomeAssignment,
  Landscape,
  PingConvention,
  PingResult,
  Random,
  RescueBudget,
  RescueContext,
  RescueOutcome,
  RescueTripToken,
  ServiceModuleKey,
  Storage,
  Transport,
  TransportOutcome,
  VersionLedger,
  Wait,
} from './types';
export { createVersionLedger, type MutableVersionLedger } from './version';
