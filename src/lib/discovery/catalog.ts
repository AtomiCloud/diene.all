import { isRecord } from '@atomicloud/diene.core-utils';
import type { ProblemResource, ProblemResourceEntry } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { validateEndpoint } from './allowlist';
import { catalogFetchFailed } from './errors';
import { retryOnceOnNetworkError } from './transport';
import type { AllowlistConfig, DiscoveryError, Transport } from './types';

/**
 * Fetches the per-service Problem catalogue from Doc A's edge `catalogHosts`.
 * Frontends classify errors (recoverable vs fatal) from this edge copy and
 * never call Primordial, even during error storms. The catalogue SHAPE is owned
 * by `@atomicloud/diene.problems` ({@link ProblemResource}); this lib only
 * fetches, validates, and hands it back.
 */

const isProblemEntry = (value: unknown): value is ProblemResourceEntry =>
  isRecord(value) &&
  typeof value.id === 'string' &&
  typeof value.type === 'string' &&
  typeof value.title === 'string' &&
  typeof value.status === 'number' &&
  typeof value.recoverable === 'boolean' &&
  isRecord(value.schema) &&
  Array.isArray(value.endpoints);

const isProblemResource = (value: unknown): value is ProblemResource => {
  if (!isRecord(value)) {
    return false;
  }
  if (value.apiVersion !== 'atomi.cloud/v1alpha1' || value.kind !== 'Problem') {
    return false;
  }
  const metadata = value.metadata;
  if (!isRecord(metadata) || typeof metadata.name !== 'string' || typeof metadata.namespace !== 'string') {
    return false;
  }
  const spec = value.spec;
  if (!isRecord(spec)) {
    return false;
  }
  if (
    typeof spec.platform !== 'string' ||
    typeof spec.service !== 'string' ||
    typeof spec.landscape !== 'string' ||
    typeof spec.version !== 'string'
  ) {
    return false;
  }
  return Array.isArray(spec.problems) && spec.problems.every(isProblemEntry);
};

/**
 * Fetch + validate a service Problem catalogue from one edge host. The host is
 * doc-sourced (Doc A's `catalogHosts`), so it is validated against the
 * endpoint-suffix allowlist AT USE TIME before any request is made.
 */
export const fetchProblemCatalog = async (
  host: string,
  transport: Transport,
  allowlist: AllowlistConfig,
): Promise<Result<ProblemResource, DiscoveryError>> => {
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
    return Err(catalogFetchFailed(host, 'body is not valid JSON'));
  }

  if (!isProblemResource(json)) {
    return Err(catalogFetchFailed(host, 'body is not a Problem resource'));
  }
  return Ok(json);
};
