import { describe, expect, test } from 'bun:test';

import {
  apiEngineConfigBlockSchema,
  createSwaggerAdapter,
  DEFAULT_BACKEND_TIMEOUT_MS,
  type IAuth,
  isProblem,
  isProblemDetail,
  isResponse,
  OPAQUE_NETWORK_RETRY_ONCE,
  proxyApiClient,
  type ReconciliationContext,
  toResult,
} from '../../src';
import { canonicalTestResource, createApiTestProblems, fakeAuthed, problemFixture } from '../../src/test-helper';

const { problems } = await createApiTestProblems();
const coordinate = Object.freeze({
  landscape: 'local',
  platform: 'platform',
  service: 'orders',
  module: 'public',
});
const resource = Object.freeze({
  platform: 'platform',
  landscape: 'local',
  service: 'orders',
  resourceName: 'api',
});
const resourceKey = await canonicalTestResource(resource);
const auth: IAuth = fakeAuthed({ [resourceKey]: 'orders-token' });
const context: ReconciliationContext = {
  backend: coordinate,
  backendKey: 'local/platform/orders/public',
  problems,
};

function validConfigBlock() {
  return {
    coordinate,
    baseUrl: 'https://orders.local.test/api/',
    resource,
    timeoutMs: 250,
    retry: OPAQUE_NETWORK_RETRY_ONCE,
    auth,
    createClient: () => ({ root: () => ({ ok: true }) }),
    rescue: { enabled: true, trip: () => undefined },
  };
}

describe('engine-owned config block', () => {
  test('accepts the complete backend block and applies fixed defaults', () => {
    const parsed = apiEngineConfigBlockSchema.parse(validConfigBlock());
    expect(parsed.coordinate).toEqual(coordinate);
    expect(parsed.baseUrl).toBe('https://orders.local.test/api');
    expect(parsed.timeoutMs).toBe(250);
    expect(parsed.retry).toBe(OPAQUE_NETWORK_RETRY_ONCE);
    expect(parsed.auth).toBe(auth);
    expect(parsed.rescue?.enabled).toBe(true);

    const defaults = apiEngineConfigBlockSchema.parse({
      ...validConfigBlock(),
      timeoutMs: undefined,
      retry: undefined,
    });
    expect(defaults.timeoutMs).toBe(DEFAULT_BACKEND_TIMEOUT_MS);
    expect(defaults.retry).toBe(OPAQUE_NETWORK_RETRY_ONCE);
  });

  test('rejects malformed coordinates, URLs, timeouts, retry profiles, and collaborators', () => {
    const base = validConfigBlock();
    const invalid = [
      { ...base, coordinate: { ...coordinate, module: 'bad/module' } },
      { ...base, baseUrl: 'file:///tmp/orders' },
      { ...base, timeoutMs: 0 },
      { ...base, retry: 'always' },
      { ...base, auth: {} },
      { ...base, createClient: 7 },
      { ...base, rescue: { enabled: true, trip: 'not-a-function' } },
    ];
    for (const candidate of invalid) expect(apiEngineConfigBlockSchema.safeParse(candidate).success).toBe(false);
  });
});

describe('public bridge and adapter facade', () => {
  test('delegates Problem guards and recognizes Responses', () => {
    const problem = problemFixture(problems.TransportFailure, { backend: 'orders', reason: 'offline' });
    expect(isProblem(problem)).toBe(true);
    expect(isProblemDetail(problem)).toBe(true);
    expect(isProblem({ type: problem.type })).toBe(false);
    expect(isProblemDetail({})).toBe(false);
    expect(isResponse(Response.json({ ok: true }))).toBe(true);
    expect(isResponse({ status: 200 })).toBe(false);
  });

  test('toResult uses full reconciliation and never rejects', async () => {
    expect(await toResult(Promise.resolve(Response.json({ bridged: true })), context).serial()).toEqual([
      'ok',
      { bridged: true },
    ]);
    const failure = await toResult(Promise.reject(new Error('bridge failure')), context).serial();
    expect(failure[0]).toBe('err');
    if (failure[0] === 'err') expect(failure[1].type).toBe(problems.TransportFailure.type);
  });

  test('exports the recursive Swagger adapter through both public names', async () => {
    expect(createSwaggerAdapter).toBe(proxyApiClient);
    const client = createSwaggerAdapter({ root: () => ({ adapted: true }) }, context);
    expect(await client.root().serial()).toEqual(['ok', { adapted: true }]);
  });
});
