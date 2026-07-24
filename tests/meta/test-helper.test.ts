import { afterAll, describe, expect, test } from 'bun:test';
import { type TokenSet, unauthed } from '@atomicloud/diene.auth-engine';
import { createProblem, isProblem, ProblemRegistry } from '@atomicloud/diene.problems';

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
  },
  fetch: () => new Response(null, { status: 404 }),
});
afterAll(() => server.stop(true));

describe('TestHelper meta-contract', () => {
  test('its assertions prove both pass and fail behavior', async () => {
    expect(() => assertProblem(problem, problem.type)).not.toThrow();
    expect(() => assertProblem({ status: 500 })).toThrow();
    expect(() => assertProblem(problem, 'https://wrong.test/problem')).toThrow();
    expect(() => assertResultSerial(['ok', 1], 'ok')).not.toThrow();
    expect(() => assertResultSerial(['ok', 1], 'err')).toThrow();

    const statusOnly = statusOnlyResponse(503);
    expect(statusOnly.status).toBe(503);
    const text = textResponse('body', 502);
    expect(await text.text()).toBe('body');
    await expect(unreadableResponse().text()).rejects.toThrow('scripted body read failure');
  });

  test('fake and real responses obey the same reconciliation contract', async () => {
    const fakeOk = await reconcileApiValue(jsonResponse({ parity: true }), context);
    const realOk = await reconcileApiValue(await fetch(`${server.url.origin}/ok`), context);
    expect(fakeOk).toEqual(realOk);

    const fakeProblem = await reconcileApiValue(problemResponse(problem, 409), context);
    const realProblem = await reconcileApiValue(await fetch(`${server.url.origin}/problem`), context);
    expect(fakeProblem).toEqual(realProblem);
    expect(isProblem(fakeProblem[1])).toBe(true);
  });

  test('fake auth mirrors canonical resource isolation with no token bleed', async () => {
    const auth = fakeAuthed({ [keyA]: 'orders-token', [keyB]: 'billing-token' });
    const serial = await auth.getTokenSet().serial();
    if (serial[0] === 'err' || serial[1].__kind === 'unauthed') throw new Error('expected auth state');
    expect(serial[1].value.data.accessTokens[keyA]).toBe('orders-token');
    expect(serial[1].value.data.accessTokens[keyB]).toBe('billing-token');
    expect(auth.getCalls).toBe(1);

    const forced = fakeUnauthed({ [keyA]: 'forced-token' });
    expect((await forced.getTokenSet().serial())[1]).toMatchObject({ __kind: 'unauthed' });
    expect((await forced.forceTokenSet().serial())[1]).toMatchObject({ __kind: 'authed' });
    expect(fakeUnauthed().forcedTokenState.__kind).toBe('unauthed');
  });

  test('scripted Kiota fake covers sync, async, throw, reject, nesting, and exhaustion', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: 1 },
        { kind: 'resolve', value: 2 },
        { kind: 'throw', error: new Error('sync') },
        { kind: 'reject', error: new Error('async') },
      ],
      'nested.call': [{ kind: 'return', value: 3 }],
    });
    expect(scripted.client.root()).toBe(1);
    expect(await scripted.client.root()).toBe(2);
    expect(() => scripted.client.root()).toThrow('sync');
    await expect(scripted.client.root() as Promise<unknown>).rejects.toThrow('async');
    expect(scripted.client.nested.call()).toBe(3);
    expect(await scripted.client.promisedNamespace).toEqual({ untouched: true });
    expect(() => scripted.client.nested.call()).toThrow('No scripted outcome');
    expect(scripted.backend.calls).toHaveLength(6);

    const direct = new ScriptedBackend({ method: [{ kind: 'return', value: 'direct' }] });
    expect(direct.invoke('method', direct, [])).toBe('direct');
  });

  test('fixtures are registry-created and guards reject incompatible shapes', async () => {
    expect(testPortal.module).toBe('tests');
    expect(kit.registry).toBeInstanceOf(ProblemRegistry);
    expect(isProblem(problem)).toBe(true);
    expect(isProblem({ ...problem, status: 999 })).toBe(false);

    const custom = await createApiTestProblems({ ...testPortal, module: 'custom' });
    const customProblem = createProblem(custom.problems.BackendNotFound, {
      data: { backend: 'missing' },
    });
    assertProblem(customProblem, custom.problems.BackendNotFound.type);

    await expect(canonicalTestResource({ ...resourceA, resourceName: '' })).rejects.toThrow();

    const fake = new FakeAuthStateRetriever(unauthed<TokenSet>());
    expect((await fake.getClaims().serial())[0]).toBe('ok');
    expect((await fake.getUserInfo().serial())[0]).toBe('ok');
    expect((await fake.getStates().serial())[0]).toBe('ok');
    fake.failure = customProblem;
    expect((await fake.getTokenSet().serial())[0]).toBe('err');
    expect((await fake.forceTokenSet().serial())[0]).toBe('err');
  });
});
