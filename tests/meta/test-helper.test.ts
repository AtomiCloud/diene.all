import { afterAll, describe, it } from 'bun:test';
import { type TokenSet, unauthed } from '@atomicloud/diene.auth-engine';
import { createProblem, isProblem, ProblemRegistry } from '@atomicloud/diene.problems';
import should from 'should';

import { reconcileApiValue } from '../../src';
import {
  assertProblem,
  assertResultSerial,
  canonicalTestResource,
  createApiTestProblems,
  createScriptedKiotaClient,
  FakeAuthStateRetriever,
  fakeAuthed,
  fakeUnauthed,
  jsonResponse,
  problemFixture,
  problemResponse,
  ScriptedBackend,
  statusOnlyResponse,
  testPortal,
  textResponse,
  unreadableResponse,
} from '../../src/test-helper';

const kit = await createApiTestProblems();
const resourceA = {
  platform: 'p',
  landscape: 'l',
  service: 'orders',
  resourceName: 'api',
};
const resourceB = { ...resourceA, service: 'billing', resourceName: 'billing-api' };
const keyA = await canonicalTestResource(resourceA);
const keyB = await canonicalTestResource(resourceB);
const problem = problemFixture(
  kit.problems.UpstreamFailure,
  { backend: 'l/p/orders/m', status: 409 },
  'fixture conflict',
);
const context = {
  backend: { landscape: 'l', platform: 'p', service: 'orders', module: 'm' },
  backendKey: 'l/p/orders/m' as const,
  problems: kit.problems,
};

const server = Bun.serve({
  hostname: '127.0.0.1',
  port: 0,
  routes: {
    '/ok': Response.json({ parity: true }),
    '/problem': new Response(JSON.stringify(problem), {
      status: 409,
      headers: { 'content-type': 'application/problem+json' },
    }),
    '/transport': () => new Response('gateway bytes', { status: 502 }),
  },
  fetch: () => new Response(null, { status: 404 }),
});
afterAll(() => server.stop(true));

describe('TestHelper meta-contract', () => {
  it('should prove both pass and fail assertion behavior', async () => {
    // Arrange
    const statusOnly = statusOnlyResponse(503);
    const text = textResponse('body', 502);

    // Act
    const actualText = await text.text();
    const actualFailure = unreadableResponse().text();

    // Assert
    should(() => assertProblem(problem, problem.type)).not.throw();
    should(() => assertProblem({ status: 500 })).throw();
    should(() => assertProblem(problem, 'https://wrong.test/problem')).throw();
    should(() => assertResultSerial(['ok', 1], 'ok')).not.throw();
    should(() => assertResultSerial(['ok', 1], 'err')).throw();
    should(statusOnly.status).equal(503);
    should(actualText).equal('body');
    await should(actualFailure).be.rejectedWith('scripted body read failure');
  });

  it('should reconcile fake and real OK, Problem, and transport responses identically', async () => {
    // Arrange
    const fakeOkResponse = jsonResponse({ parity: true });
    const fakeProblemResponse = problemResponse(problem, 409);
    const fakeTransportResponse = textResponse('gateway bytes', 502);

    // Act
    const fakeOk = await reconcileApiValue(fakeOkResponse, context);
    const realOk = await reconcileApiValue(await fetch(`${server.url.origin}/ok`), context);
    const fakeProblem = await reconcileApiValue(fakeProblemResponse, context);
    const realProblem = await reconcileApiValue(await fetch(`${server.url.origin}/problem`), context);
    const fakeTransport = await reconcileApiValue(fakeTransportResponse, context);
    const realTransport = await reconcileApiValue(await fetch(`${server.url.origin}/transport`), context);

    // Assert
    should(fakeOk).deepEqual(realOk);
    should(fakeProblem).deepEqual(realProblem);
    should(isProblem(fakeProblem[1])).be.true();
    should(fakeTransport).deepEqual(realTransport);
    assertResultSerial(fakeTransport, 'err');
    assertResultSerial(realTransport, 'err');
    should(isProblem(fakeTransport[1])).be.true();
    should(isProblem(realTransport[1])).be.true();
    if (fakeTransport[0] === 'err' && realTransport[0] === 'err') {
      should(fakeTransport[1].type).equal(kit.problems.TransportFailure.type);
      should(realTransport[1].type).equal(kit.problems.TransportFailure.type);
    }
  });

  it('should isolate fake auth resources without token bleed', async () => {
    // Arrange
    const auth = fakeAuthed({ [keyA]: 'orders-token', [keyB]: 'billing-token' });
    const forced = fakeUnauthed({ [keyA]: 'forced-token' });

    // Act
    const serial = await auth.getTokenSet().serial();
    const forcedSerial = await forced.getTokenSet().serial();
    const forcedTokenSerial = await forced.forceTokenSet().serial();

    // Assert
    if (serial[0] === 'err' || serial[1].__kind === 'unauthed') throw new Error('expected auth state');
    should(serial[1].value.data.accessTokens[keyA]).equal('orders-token');
    should(serial[1].value.data.accessTokens[keyB]).equal('billing-token');
    should(auth.getCalls).equal(1);
    should(forcedSerial[1]).match({ __kind: 'unauthed' });
    should(forcedTokenSerial[1]).match({ __kind: 'authed' });
    should(fakeUnauthed().forcedTokenState.__kind).equal('unauthed');
  });

  it('should cover sync, async, nested, and exhausted scripted Kiota calls', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: 1 },
        { kind: 'resolve', value: 2 },
      ],
      'nested.call': [{ kind: 'return', value: 3 }],
    });
    const syncScripted = createScriptedKiotaClient({ root: [{ kind: 'throw', error: new Error('sync') }] });
    const asyncScripted = createScriptedKiotaClient({ root: [{ kind: 'reject', error: new Error('async') }] });
    const direct = new ScriptedBackend({ method: [{ kind: 'return', value: 'direct' }] });

    // Act
    const first = scripted.client.root();
    const second = await scripted.client.root();
    const syncFailure = () => syncScripted.client.root();
    const asyncFailure = asyncScripted.client.root() as Promise<unknown>;
    const nested = scripted.client.nested.call();
    const namespace = await scripted.client.promisedNamespace;
    const exhausted = () => scripted.client.nested.call();
    const directValue = direct.invoke('method', direct, []);

    // Assert
    should(first).equal(1);
    should(second).equal(2);
    should(syncFailure).throw('sync');
    await should(asyncFailure).be.rejectedWith('async');
    should(nested).equal(3);
    should(namespace).deepEqual({ untouched: true });
    should(exhausted).throw(/No scripted outcome/);
    should(scripted.backend.calls).have.length(4);
    should(directValue).equal('direct');
  });

  it('should create registry fixtures and reject incompatible shapes', async () => {
    // Arrange
    const custom = await createApiTestProblems({ ...testPortal, module: 'custom' });
    const customProblem = createProblem(custom.problems.BackendNotFound, {
      data: { backend: 'missing' },
    });
    const fake = new FakeAuthStateRetriever(unauthed<TokenSet>());
    fake.failure = customProblem;

    // Act
    const invalidResource = canonicalTestResource({ ...resourceA, resourceName: '' });
    const tokenSet = await fake.getTokenSet().serial();
    const forcedTokenSet = await fake.forceTokenSet().serial();

    // Assert
    should(testPortal.module).equal('tests');
    should(kit.registry).be.instanceOf(ProblemRegistry);
    should(isProblem(problem)).be.true();
    should(isProblem({ ...problem, status: 999 })).be.false();
    assertProblem(customProblem, custom.problems.BackendNotFound.type);
    await should(invalidResource).be.rejected();
    should((await fake.getClaims().serial())[0]).equal('ok');
    should((await fake.getUserInfo().serial())[0]).equal('ok');
    should((await fake.getStates().serial())[0]).equal('ok');
    should(tokenSet[0]).equal('err');
    should(forcedTokenSet[0]).equal('err');
  });
});
