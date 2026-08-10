/**
 * Typed contracts for the three-doc edge client (Doc A/B/C) and the dormant
 * rescue router (ARCHITECTURE §4, Posture B). Pure types only — no runtime — so
 * this file never carries executable lines into the unit coverage ledger.
 *
 * Design posture (goals/lib/bun-frontend-utils.md):
 * - React-free, SSR-safe, pure domain core with injected seams (no DI container,
 *   no hostname sniffing).
 * - Doc A: fleet doc, constantly refreshed, carries `catalogHosts` + version.
 * - Doc B: landscape selector, fetched once at sign-up, drives ping-and-pick-home.
 * - Doc C: platform catalog, DORMANT — fetched only during an actual rescue trip.
 * - Every doc-sourced URL is validated against the endpoint-suffix allowlist AT
 *   USE TIME; the auth issuer is ALWAYS baked, never doc-sourced.
 */

/** A landscape name (e.g. `lapras`, `pichu`, `pikachu`, `raichu`). */
export type Landscape = string;

/** Identifies an ordered candidate list inside Doc C. */
export interface ServiceModuleKey {
  readonly landscape: Landscape;
  readonly service: string;
  readonly module: string;
}

// ─── Doc A · fleet doc ──────────────────────────────────────────────────────

/**
 * Doc A — the fleet doc. ~200B, constantly refreshed (stale-while-revalidate,
 * cheap 304s) from baked seeds spanning failure domains. Carries the edge
 * `catalogHosts` (used for Doc C and the per-service Problem catalogue) plus its
 * own monotonic `version` and a `ttlSeconds` refresh hint.
 */
export interface DocA {
  readonly version: number;
  readonly ttlSeconds: number;
  readonly catalogHosts: readonly string[];
}

// ─── Doc B · landscape selector ─────────────────────────────────────────────

/** One selectable landscape in Doc B: name + display metadata ONLY — no address. */
export interface DocBLandscape {
  readonly name: Landscape;
  readonly displayName: string;
  readonly metadata: Readonly<Record<string, string>>;
}

/**
 * Doc B — the landscape selector, per platform×env. Landscape names + metadata
 * ONLY (no addresses, no issuer). Fetched at SIGN-UP ONLY; drives
 * ping-and-pick-home. Ping URLs are derived by naming convention, never carried
 * in the doc.
 */
export interface DocB {
  readonly version: number;
  readonly platform: string;
  readonly env: string;
  readonly landscapes: readonly DocBLandscape[];
}

// ─── Doc C · platform catalog ───────────────────────────────────────────────

/** An ordered candidate list for one landscape×service×module — primary first. */
export interface DocCCandidateList {
  readonly landscape: Landscape;
  readonly service: string;
  readonly module: string;
  /** Full addresses, primary first, rescue-domain alternates after. */
  readonly candidates: readonly string[];
}

/**
 * Doc C — the platform catalog, per platform×env. FULL addresses (no `{root}`
 * templating), an ORDERED candidate list per landscape×service×module. DORMANT:
 * only ever fetched during an actual rescue trip (guarded by a {@link RescueTripToken}).
 */
export interface DocC {
  readonly version: number;
  readonly platform: string;
  readonly env: string;
  readonly lists: readonly DocCCandidateList[];
}

// ─── Endpoint-suffix allowlist ──────────────────────────────────────────────

/**
 * The baked endpoint-suffix allowlist. Every doc-sourced URL must be HTTPS and
 * its host must end with one of `suffixes` (e.g. `.cluster.atomi.cloud`) or
 * exactly equal one of `rescueRoots`. There is no doc signing; the allowlist
 * replaces it.
 */
export interface AllowlistConfig {
  /** Host suffixes, each beginning with a dot (e.g. `.cluster.atomi.cloud`). */
  readonly suffixes: readonly string[];
  /** Exact rescue-root hosts (e.g. `rescue.atomi.cloud`). */
  readonly rescueRoots: readonly string[];
}

// ─── Transport & injected seams (NO DI container) ───────────────────────────

/**
 * The outcome of a single transport attempt. `connect-failure` is the HARD
 * failure that (and only that) trips the dormant rescue router; `timeout` is a
 * soft/retryable network error; `http-error` is a real response with a bad
 * status (never trips rescue).
 */
export type TransportOutcome =
  | { readonly kind: 'ok'; readonly status: number; readonly body: string }
  | { readonly kind: 'http-error'; readonly status: number }
  | { readonly kind: 'timeout' }
  | { readonly kind: 'connect-failure' };

/** Network seam. The only I/O dependency of the doc client and rescue router. */
export interface Transport {
  fetch(url: string): Promise<TransportOutcome>;
}

/** Injected monotonic clock seam (milliseconds); enables deterministic budgets. */
export interface Clock {
  now(): number;
}

/** Injected randomness seam in `[0, 1)`; enables deterministic jitter. */
export interface Random {
  next(): number;
}

/** Injected delay seam; stubbed to a no-op in tests so jitter never sleeps. */
export type Wait = (ms: number) => Promise<void>;

/**
 * Injected persistence seam for last-known-good. Synchronous string KV; the
 * real adapter is disk (Flutter/browser), the SSR server passes a disabled
 * context so this is never touched there.
 */
export interface Storage {
  read(key: string): string | null;
  write(key: string, value: string): void;
}

// ─── Discovery error catalogue ──────────────────────────────────────────────

/**
 * The discovery problem catalogue — the typed, total error vocabulary returned
 * (never thrown) by the doc client and rescue router.
 */
export type DiscoveryError =
  | { readonly kind: 'malformed-doc'; readonly doc: 'A' | 'B' | 'C'; readonly reason: string }
  | { readonly kind: 'stale-version'; readonly key: string; readonly seen: number; readonly incoming: number }
  | { readonly kind: 'endpoint-not-https'; readonly url: string }
  | { readonly kind: 'endpoint-suffix-rejected'; readonly url: string; readonly host: string }
  | { readonly kind: 'endpoint-unparseable'; readonly url: string }
  | { readonly kind: 'doc-c-fetch-forbidden'; readonly reason: string }
  | { readonly kind: 'rescue-disabled'; readonly context: string }
  | { readonly kind: 'rescue-budget-exhausted'; readonly attempts: number; readonly elapsedMs: number }
  | { readonly kind: 'no-candidate-reachable'; readonly attempts: number }
  | { readonly kind: 'not-a-connect-failure'; readonly outcome: TransportOutcome['kind'] }
  | { readonly kind: 'no-home-picked'; readonly chosen: string }
  | { readonly kind: 'catalog-fetch-failed'; readonly host: string; readonly reason: string };

// ─── Version ledger ─────────────────────────────────────────────────────────

/**
 * Per-document monotonic version ledger. Keys are per-doc (A/B/C, or finer), so
 * monotonicity is enforced independently — never global. A client never accepts
 * a doc older than the newest it has seen for that key.
 */
export interface VersionLedger {
  /** Newest version seen for `key`, or `undefined` if never seen. */
  seen(key: string): number | undefined;
}

// ─── Doc B · ping-and-pick-home lifecycle ───────────────────────────────────

/** The result of pinging one landscape's convention-derived ping URL. */
export interface PingResult {
  readonly landscape: Landscape;
  readonly url: string;
  readonly reachable: boolean;
  readonly latencyMs: number;
}

/**
 * The home ASSIGNMENT handed off to auth-engine after the user picks a landscape.
 * Discovery does NOT write the home claim — auth-engine drives the OIDC login +
 * OnboardSync that does. This is the contract boundary object only.
 */
export interface HomeAssignment {
  readonly landscape: Landscape;
  readonly pingUrl: string;
  readonly latencyMs: number;
}

/** Convention config for deriving Doc B ping URLs (host is doc-free by design). */
export interface PingConvention {
  /** e.g. `cluster.atomi.cloud`; ping host becomes `ping.<landscape>.<root>`. */
  readonly root: string;
}

// ─── Dormant rescue router ──────────────────────────────────────────────────

/**
 * A capability token proving a real hard connect-failure occurred. It is the
 * ONLY key that unlocks a Doc C fetch — Doc C can never be fetched outside a
 * rescue trip. Minted solely by `tripOnConnectFailure`.
 */
export interface RescueTripToken {
  readonly reason: 'hard-connect-failure';
}

/**
 * Per-context enable/disable for the rescue router. ON in Flutter + browser,
 * OFF (by construction) in the nextjs SERVER runtime — its rescue is redeploy,
 * not client routing.
 */
export interface RescueContext {
  readonly label: string;
  readonly enabled: boolean;
}

/** Bounds on a rescue scan — attempts and wall-clock, whichever trips first. */
export interface RescueBudget {
  readonly maxAttempts: number;
  readonly budgetMs: number;
  /** Upper bound of jitter added before each attempt, in ms. */
  readonly baseJitterMs: number;
}

/** A successful rescue: the pinned winner plus scan telemetry. */
export interface RescueOutcome {
  readonly pinnedUrl: string;
  readonly attempts: number;
  readonly elapsedMs: number;
  readonly triedFromLastKnownGood: boolean;
}
