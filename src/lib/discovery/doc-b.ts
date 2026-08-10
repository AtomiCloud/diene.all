import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { validateEndpoint } from './allowlist';
import { noHomePicked } from './errors';
import { retryOnceOnNetworkError } from './transport';
import type {
  AllowlistConfig,
  Clock,
  DiscoveryError,
  DocB,
  HomeAssignment,
  PingConvention,
  PingResult,
  Transport,
} from './types';

/**
 * The home ASSIGNMENT contract handed to auth-engine. Discovery stops here:
 * auth-engine drives the OIDC login + OnboardSync that actually writes the home
 * claim (ARCHITECTURE §5). This object is the boundary, nothing more.
 */
export interface AuthEngineHandoff {
  readonly kind: 'home-assignment';
  readonly landscape: string;
  readonly pingUrl: string;
  readonly latencyMs: number;
}

/**
 * Derive a landscape's ping URL by naming convention — ping addresses are NOT
 * carried in Doc B. `ping.<landscape>.<root>` over HTTPS. Convention output is
 * still doc-adjacent, so callers validate it against the allowlist before use.
 */
export const derivePingUrl = (landscape: string, convention: PingConvention): string =>
  `https://ping.${landscape}.${convention.root}`;

/**
 * Deterministic ordering for ping candidates: reachable first, then ascending
 * latency, then landscape name (stable tie-break). No wall-clock nondeterminism
 * survives — latency comes from the injected clock.
 */
const comparePings = (a: PingResult, b: PingResult): number => {
  if (a.reachable !== b.reachable) {
    return a.reachable ? -1 : 1;
  }
  if (a.latencyMs !== b.latencyMs) {
    return a.latencyMs - b.latencyMs;
  }
  return a.landscape < b.landscape ? -1 : a.landscape > b.landscape ? 1 : 0;
};

/**
 * Ping every landscape in Doc B at its convention-derived URL and return the
 * results in deterministic candidate order. A landscape whose derived URL fails
 * the allowlist is dropped (that URL rejected, not the whole doc). Latency is
 * measured with the injected clock; each ping uses the hot-path retry-once
 * primitive.
 */
export const pingLandscapes = async (
  doc: DocB,
  convention: PingConvention,
  transport: Transport,
  clock: Clock,
  allowlist: AllowlistConfig,
): Promise<readonly PingResult[]> => {
  const results: PingResult[] = [];

  for (const landscape of doc.landscapes) {
    const url = derivePingUrl(landscape.name, convention);
    const valid = validateEndpoint(url, allowlist);
    if (await valid.isErr()) {
      continue;
    }

    const start = clock.now();
    const outcome = await retryOnceOnNetworkError(transport, url);
    const latencyMs = clock.now() - start;
    results.push({
      landscape: landscape.name,
      url,
      reachable: outcome.kind === 'ok',
      latencyMs,
    });
  }

  return Object.freeze([...results].sort(comparePings));
};

/**
 * The user picks a landscape by name from the ping candidates. The pick must be
 * present and reachable; otherwise a `no-home-picked` error is returned. On
 * success the {@link HomeAssignment} is produced.
 */
export const pickHome = (pings: readonly PingResult[], chosen: string): Result<HomeAssignment, DiscoveryError> => {
  const match = pings.find(ping => ping.landscape === chosen);
  if (match === undefined || !match.reachable) {
    return Err(noHomePicked(chosen));
  }
  return Ok(
    Object.freeze({
      landscape: match.landscape,
      pingUrl: match.url,
      latencyMs: match.latencyMs,
    }),
  );
};

/** Wrap a {@link HomeAssignment} into the auth-engine handoff contract. */
export const handoffToAuthEngine = (assignment: HomeAssignment): AuthEngineHandoff =>
  Object.freeze({
    kind: 'home-assignment',
    landscape: assignment.landscape,
    pingUrl: assignment.pingUrl,
    latencyMs: assignment.latencyMs,
  });
