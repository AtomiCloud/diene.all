import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { isHostAllowed, validateEndpoint } from './allowlist';
import { noCandidateReachable, rescueBudgetExhausted, rescueDisabled } from './errors';
import { retryOnceOnNetworkError } from './transport';
import type {
  AllowlistConfig,
  Clock,
  DiscoveryError,
  Random,
  RescueBudget,
  RescueContext,
  RescueOutcome,
  Storage,
  Transport,
  Wait,
} from './types';

/** Build a per-context enable flag for the rescue router. */
export const createRescueContext = (label: string, enabled: boolean): RescueContext =>
  Object.freeze({ label, enabled });

/** Rescue is ON in the browser. */
export const BROWSER_RESCUE_CONTEXT: RescueContext = createRescueContext('browser', true);
/** Rescue is ON in Flutter. */
export const FLUTTER_RESCUE_CONTEXT: RescueContext = createRescueContext('flutter', true);
/** Rescue is OFF by construction in the nextjs SERVER runtime — its rescue is redeploy. */
export const NEXTJS_SERVER_RESCUE_CONTEXT: RescueContext = createRescueContext('nextjs-server', false);

export interface RunRescueParams {
  readonly context: RescueContext;
  /** Doc C's ordered candidates (primary first, rescue alternates after). */
  readonly candidates: readonly string[];
  readonly allowlist: AllowlistConfig;
  readonly transport: Transport;
  readonly clock: Clock;
  readonly random: Random;
  readonly wait: Wait;
  readonly budget: RescueBudget;
  readonly storage: Storage;
  /** Storage key under which the last-known-good winner is retained forever. */
  readonly storageKey: string;
}

/** Read the retained last-known-good address, or `null` if none was ever pinned. */
export const readLastKnownGood = (storage: Storage, storageKey: string): string | null => storage.read(storageKey);

/**
 * Compute the scan order: the retained last-known-good first (when present,
 * still allowlist-valid, and among the current candidates), then the remaining
 * candidates in Doc C order. Returns the order plus whether an LKG fast-path was
 * prepended.
 */
const buildScanOrder = (
  candidates: readonly string[],
  allowlist: AllowlistConfig,
  lkg: string | null,
): { readonly order: readonly string[]; readonly usedLkg: boolean } => {
  if (lkg !== null && candidates.includes(lkg)) {
    let host: string;
    try {
      host = new URL(lkg).hostname;
    } catch {
      return { order: candidates, usedLkg: false };
    }
    if (isHostAllowed(host, allowlist)) {
      return { order: [lkg, ...candidates.filter(candidate => candidate !== lkg)], usedLkg: true };
    }
  }
  return { order: candidates, usedLkg: false };
};

/**
 * The dormant rescue router. It is invoked ONLY after a hard connect-failure
 * (the caller mints a trip token to even reach Doc C). It walks Doc C's ordered
 * candidates with a jittered, budgeted scan — bounded by attempts and
 * wall-clock — validating every candidate against the allowlist at use time,
 * pins the first reachable address, and persists it as last-known-good (kept
 * forever). It is a no-op when the context has rescue disabled (e.g. the nextjs
 * server), and it never runs on soft/retryable errors — only the caller's hard
 * connect-failure brings it here.
 */
export const runRescue = async (params: RunRescueParams): Promise<Result<RescueOutcome, DiscoveryError>> => {
  const { context, candidates, allowlist, transport, clock, random, wait, budget, storage, storageKey } = params;

  if (!context.enabled) {
    return Err(rescueDisabled(context.label));
  }

  const lkg = readLastKnownGood(storage, storageKey);
  const { order, usedLkg } = buildScanOrder(candidates, allowlist, lkg);

  const start = clock.now();
  const deadline = start + budget.budgetMs;
  let attempts = 0;

  for (const url of order) {
    const valid = validateEndpoint(url, allowlist);
    if (await valid.isErr()) {
      continue;
    }

    if (attempts >= budget.maxAttempts || clock.now() >= deadline) {
      return Err(rescueBudgetExhausted(attempts, clock.now() - start));
    }

    const jitter = Math.floor(budget.baseJitterMs * random.next());
    await wait(jitter);
    attempts += 1;

    const outcome = await retryOnceOnNetworkError(transport, url);
    if (outcome.kind === 'ok') {
      storage.write(storageKey, url);
      return Ok(
        Object.freeze({
          pinnedUrl: url,
          attempts,
          elapsedMs: clock.now() - start,
          triedFromLastKnownGood: usedLkg && url === lkg,
        }),
      );
    }
  }

  return Err(noCandidateReachable(attempts));
};

/**
 * Probe whether the pinned primary has healed, so the hot path can drop the pin
 * and return to its single home hostname. Uses the hot-path retry-once primitive.
 */
export const checkHeal = async (transport: Transport, primaryUrl: string): Promise<boolean> => {
  const outcome = await retryOnceOnNetworkError(transport, primaryUrl);
  return outcome.kind === 'ok';
};
