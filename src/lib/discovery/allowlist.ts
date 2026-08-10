import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { endpointNotHttps, endpointSuffixRejected, endpointUnparseable } from './errors';
import type { AllowlistConfig, DiscoveryError } from './types';

/**
 * The baked default allowlist: cluster suffix + a rescue root. Callers may pass
 * their own baked config; the point is that it is BAKED, validated AT USE TIME,
 * and replaces doc signing.
 */
export const DEFAULT_ALLOWLIST: AllowlistConfig = Object.freeze({
  suffixes: Object.freeze(['.cluster.atomi.cloud']) as readonly string[],
  rescueRoots: Object.freeze(['rescue.atomi.cloud']) as readonly string[],
});

/** True iff `host` ends with an allowed suffix or exactly equals a rescue root. */
export const isHostAllowed = (host: string, config: AllowlistConfig): boolean => {
  const lower = host.toLowerCase();
  const bySuffix = config.suffixes.some(suffix => lower.endsWith(suffix.toLowerCase()));
  if (bySuffix) {
    return true;
  }
  return config.rescueRoots.some(root => lower === root.toLowerCase());
};

/**
 * Validate a doc-sourced URL against the endpoint-suffix allowlist AT USE TIME.
 * Rejects (a) anything that does not parse, (b) any non-HTTPS scheme, and
 * (c) any host outside the allowlist. On success returns the parsed {@link URL}.
 * A single bad URL is rejected — never the whole doc.
 */
export const validateEndpoint = (url: string, config: AllowlistConfig): Result<URL, DiscoveryError> => {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return Err(endpointUnparseable(url));
  }
  if (parsed.protocol !== 'https:') {
    return Err(endpointNotHttps(url));
  }
  if (!isHostAllowed(parsed.hostname, config)) {
    return Err(endpointSuffixRejected(url, parsed.hostname));
  }
  return Ok(parsed);
};
