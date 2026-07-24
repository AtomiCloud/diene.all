import { describe, it } from 'bun:test';
import should from 'should';

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
  it('should accept the complete backend block and apply fixed defaults', () => {
    // Arrange
    const input = validConfigBlock();

    // Act
    const actual = apiEngineConfigBlockSchema.parse(input);
    const defaults = apiEngineConfigBlockSchema.parse({
      ...input,
      timeoutMs: undefined,
      retry: undefined,
    });

    // Assert
    should(actual.coordinate).deepEqual(coordinate);
    should(actual.baseUrl).equal('https://orders.local.test/api');
    should(actual.timeoutMs).equal(250);
    should(actual.retry).equal(OPAQUE_NETWORK_RETRY_ONCE);
    should(actual.auth).equal(auth);
    should(actual.rescue?.enabled).be.true();
    should(defaults.timeoutMs).equal(DEFAULT_BACKEND_TIMEOUT_MS);
    should(defaults.retry).equal(OPAQUE_NETWORK_RETRY_ONCE);
  });

  it('should reject malformed coordinates, URLs, timeouts, retry profiles, and collaborators', () => {
    // Arrange
    const base = validConfigBlock();
    const input = [
      { ...base, coordinate: { ...coordinate, module: 'bad/module' } },
      { ...base, baseUrl: 'file:///tmp/orders' },
      { ...base, timeoutMs: 0 },
      { ...base, retry: 'always' },
      { ...base, auth: {} },
      { ...base, createClient: 7 },
      { ...base, rescue: { enabled: true, trip: 'not-a-function' } },
    ];

    // Act
    const actual = input.map(candidate => apiEngineConfigBlockSchema.safeParse(candidate).success);

    // Assert
    should(actual).deepEqual([false, false, false, false, false, false, false]);
  });
});

describe('public bridge and adapter facade', () => {
  it('should delegate Problem guards and recognize Responses', () => {
    // Arrange
    const problem = problemFixture(problems.TransportFailure, { backend: 'orders', reason: 'offline' });

    // Act
    const actual = {
      problem: isProblem(problem),
      detail: isProblemDetail(problem),
      incompleteProblem: isProblem({ type: problem.type }),
      emptyDetail: isProblemDetail({}),
      response: isResponse(Response.json({ ok: true })),
      plainObject: isResponse({ status: 200 }),
    };

    // Assert
    should(actual).deepEqual({
      problem: true,
      detail: true,
      incompleteProblem: false,
      emptyDetail: false,
      response: true,
      plainObject: false,
    });
  });

  it('should use full reconciliation without rejecting', async () => {
    // Arrange
    const success = toResult(Promise.resolve(Response.json({ bridged: true })), context);
    const failure = toResult(Promise.reject(new Error('bridge failure')), context);

    // Act
    const actualSuccess = await success.serial();
    const actualFailure = await failure.serial();

    // Assert
    should(actualSuccess).deepEqual(['ok', { bridged: true }]);
    should(actualFailure[0]).equal('err');
    if (actualFailure[0] === 'err') should(actualFailure[1].type).equal(problems.TransportFailure.type);
  });

  it('should export the recursive Swagger adapter through both public names', async () => {
    // Arrange
    const client = createSwaggerAdapter({ root: () => ({ adapted: true }) }, context);

    // Act
    const actual = await client.root().serial();

    // Assert
    should(createSwaggerAdapter).equal(proxyApiClient);
    should(actual).deepEqual(['ok', { adapted: true }]);
  });
});
