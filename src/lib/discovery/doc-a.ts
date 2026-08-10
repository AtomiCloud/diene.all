import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { catalogFetchFailed, malformedDoc } from './errors';
import { parseDocA } from './parse';
import { retryOnceOnNetworkError } from './transport';
import type { DiscoveryError, DocA, Transport } from './types';

/** The version-ledger key under which Doc A monotonicity is tracked. */
export const DOC_A_LEDGER_KEY = 'doc-a';

/** Where a returned Doc A came from: a live seed, or the retained cache. */
export type DocASource = 'network' | 'cache';

export interface DocARefreshResult {
  readonly doc: DocA;
  readonly source: DocASource;
}

export interface RefreshDocAParams {
  /** Baked seed URLs (R2, S3/CloudFront, CloudFront host, rescue aliases). */
  readonly seeds: readonly string[];
  readonly transport: Transport;
  /** Accepts a version for {@link DOC_A_LEDGER_KEY}; rejects older-than-seen. */
  readonly acceptVersion: (key: string, incoming: number) => Result<number, DiscoveryError>;
  /** The newest Doc A previously retained, or `null` on a cold start. */
  readonly cached: DocA | null;
}

const safeJsonParse = (text: string): Result<unknown, DiscoveryError> => {
  try {
    return Ok(JSON.parse(text) as unknown);
  } catch {
    return Err(malformedDoc('A', 'seed body is not valid JSON'));
  }
};

/**
 * Refresh Doc A from the baked seeds with stale-while-revalidate semantics.
 *
 * Seeds are tried in order; the first that returns a well-formed doc whose
 * version is not older-than-seen wins. A seed that is unreachable, non-200, or
 * malformed is skipped. If revalidation only surfaces an older version, the
 * retained cache is served. If every seed fails, the retained cache is served
 * (stale) when present; otherwise the last failure is returned.
 *
 * Seeds are BAKED constants and therefore not subject to the doc-sourced
 * endpoint-suffix allowlist — only URLs carried inside docs are.
 */
export const refreshDocA = async (params: RefreshDocAParams): Promise<Result<DocARefreshResult, DiscoveryError>> => {
  const { seeds, transport, acceptVersion, cached } = params;
  let lastError: DiscoveryError = malformedDoc('A', 'no seed produced a usable doc');

  for (const seed of seeds) {
    const outcome = await retryOnceOnNetworkError(transport, seed);
    if (outcome.kind !== 'ok') {
      lastError = catalogFetchFailed(seed, outcome.kind);
      continue;
    }

    const json = safeJsonParse(outcome.body);
    if (await json.isErr()) {
      lastError = await json.unwrapErr();
      continue;
    }

    const parsed = parseDocA(await json.unwrap());
    if (await parsed.isErr()) {
      lastError = await parsed.unwrapErr();
      continue;
    }

    const doc = await parsed.unwrap();
    const accepted = acceptVersion(DOC_A_LEDGER_KEY, doc.version);
    if (await accepted.isOk()) {
      return Ok({ doc, source: 'network' });
    }
    // Revalidation found nothing newer than what we already hold.
    if (cached !== null) {
      return Ok({ doc: cached, source: 'cache' });
    }
    return Err(await accepted.unwrapErr());
  }

  if (cached !== null) {
    return Ok({ doc: cached, source: 'cache' });
  }
  return Err(lastError);
};
