import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { validateEndpoint } from './allowlist';
import { catalogFetchFailed, malformedDoc } from './errors';
import { parseDocC } from './parse';
import { retryOnceOnNetworkError } from './transport';
import type { AllowlistConfig, DiscoveryError, DocC, RescueTripToken, ServiceModuleKey, Transport } from './types';

/** The version-ledger key under which Doc C monotonicity is tracked. */
export const DOC_C_LEDGER_KEY = 'doc-c';

export interface FetchDocCParams {
  /** A Doc A `catalogHosts` entry (doc-sourced; validated at use time). */
  readonly host: string;
  readonly transport: Transport;
  readonly allowlist: AllowlistConfig;
  /** Proof of a real hard connect-failure. Doc C cannot be fetched without it. */
  readonly token: RescueTripToken;
  readonly acceptVersion: (key: string, incoming: number) => Result<number, DiscoveryError>;
}

/**
 * Fetch Doc C — the DORMANT platform catalog. The mandatory {@link RescueTripToken}
 * makes it impossible to fetch outside an actual rescue trip: the token is
 * minted ONLY by `tripOnConnectFailure` on a hard connect-failure. The host is
 * doc-sourced, so it is allowlist-validated at use time; version monotonicity is
 * enforced against {@link DOC_C_LEDGER_KEY}.
 */
export const fetchDocC = async (params: FetchDocCParams): Promise<Result<DocC, DiscoveryError>> => {
  const { host, transport, allowlist, token, acceptVersion } = params;
  // The token is required by the type system; assert it at runtime too so the
  // dormant-only invariant holds even for untyped callers.
  if (token.reason !== 'hard-connect-failure') {
    return Err<DocC, DiscoveryError>(
      Object.freeze({
        kind: 'doc-c-fetch-forbidden',
        reason: 'Doc C fetch requires a hard-connect-failure trip token',
      }),
    );
  }

  const endpoint = validateEndpoint(host, allowlist);
  if (await endpoint.isErr()) {
    return Err(await endpoint.unwrapErr());
  }

  const outcome = await retryOnceOnNetworkError(transport, host);
  if (outcome.kind !== 'ok') {
    return Err(catalogFetchFailed(host, outcome.kind));
  }

  let json: unknown;
  try {
    json = JSON.parse(outcome.body) as unknown;
  } catch {
    return Err(malformedDoc('C', 'body is not valid JSON'));
  }

  const parsed = parseDocC(json);
  if (await parsed.isErr()) {
    return Err(await parsed.unwrapErr());
  }

  const doc = await parsed.unwrap();
  const accepted = acceptVersion(DOC_C_LEDGER_KEY, doc.version);
  if (await accepted.isErr()) {
    return Err(await accepted.unwrapErr());
  }
  return Ok(doc);
};

/**
 * The ordered candidate list for a landscape×service×module — primary first,
 * rescue-domain alternates after — or an empty list if Doc C carries none.
 * Candidates are validated against the allowlist by the rescue router at use
 * time, not here.
 */
export const candidatesFor = (doc: DocC, key: ServiceModuleKey): readonly string[] => {
  const list = doc.lists.find(
    entry => entry.landscape === key.landscape && entry.service === key.service && entry.module === key.module,
  );
  return list === undefined ? Object.freeze([]) : list.candidates;
};
