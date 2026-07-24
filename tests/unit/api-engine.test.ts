import { describe, expect, test } from 'bun:test';
import { ProblemRegistry } from '@atomicloud/diene.problems';
import { Err, Ok } from '@atomicloud/diene.result';

import {
  type ApiClient,
  ApiConfigurationFailure,
  type ApiEngineOptions,
  type BackendClientContext,
  createApiEngine,
  createAuthenticationProblem,
  type FetchLike,
  type LpsmCoordinate,
  reconcileApiFailure,
  registerApiProblems,
} from '../../src';
import {
  assertProblem,
  canonicalTestResource,
  createApiTestProblems,
  createScriptedKiotaClient,
  fakeAuthed,
  fakeUnauthed,
  jsonResponse,
  problemFixture,
  problemResponse,
  statusOnlyResponse,
  testPortal,
  textResponse,
  unreadableResponse,
} from '../../src/test-helper';

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

async function resolvedClient<TClient extends object>(
  client: TClient,
  options: Partial<Pick<ApiEngineOptions, 'fetch'>> = {},
  auth = fakeAuthed({ [resourceKey]: 'orders-token' }),
  bindingOptions: {
    readonly timeoutMs?: number;
    readonly rescue?: ApiEngineOptions['bindings'][number]['rescue'];
  } = {},
): Promise<ApiClient<TClient>> {
  const engineSerial = await createApiEngine({
    problems,
    bindings: [
      {
        coordinate,
        resource,
        baseUrl: 'https://orders.local.test/api',
        auth,
        createClient: () => client,
        ...bindingOptions,
      },
    ],
    ...options,
  }).serial();
  if (engineSerial[0] === 'err') throw new Error(engineSerial[1].detail ?? engineSerial[1].title);
  const clientSerial = await engineSerial[1].resolve<TClient>(coordinate).serial();
  if (clientSerial[0] === 'err') throw new Error(clientSerial[1].detail ?? clientSerial[1].title);
  return clientSerial[1];
}

function fetchClient(context: BackendClientContext) {
  return {
    root(init?: RequestInit) {
      return context.fetch(`${context.baseUrl}/items`, init);
    },
  };
}

describe('SDK result reconciliation', () => {
  test('returns typed/direct success as Ok', async () => {
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'return', value: { id: 7 } }] });
    const client = await resolvedClient(scripted.client);
    expect(await client.root().serial()).toEqual(['ok', { id: 7 }]);
  });

  test('flattens a direct Result without throwing unwrap', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: Ok({ source: 'result' }) },
        { kind: 'return', value: Err(problemFixture(problems.TransportFailure, { backend: 'x', reason: 'x' })) },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect(await client.root().serial()).toEqual(['ok', { source: 'result' }]);
    expect((await client.root().serial())[0]).toBe('err');
  });

  test('decodes a successful JSON Response', async () => {
    const scripted = createScriptedKiotaClient({
      root: [{ kind: 'resolve', value: jsonResponse({ items: [1, 2] }) }],
    });
    const client = await resolvedClient(scripted.client);
    expect(await client.root().serial()).toEqual(['ok', { items: [1, 2] }]);
  });

  test('passes successful non-JSON/stream Responses through without consuming them', async () => {
    const response = textResponse('download');
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'resolve', value: response }] });
    const client = await resolvedClient(scripted.client);
    const serial = await client.root().serial();
    expect(serial).toEqual(['ok', response]);
    expect(response.bodyUsed).toBe(false);
  });

  test('maps direct and nested Problems to Err', async () => {
    const problem = problemFixture(
      problems.UpstreamFailure,
      { backend: 'local/platform/orders/public', status: 409 },
      'conflict',
    );
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: problem },
        { kind: 'throw', error: { error: { additionalData: { problem } } } },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect(await client.root().serial()).toEqual(['err', problem]);
    expect(await client.root().serial()).toEqual(['err', problem]);
  });

  test('maps RFC 9457 and nested RFC 9457 HTTP bodies to Err', async () => {
    const problem = problemFixture(
      problems.UpstreamFailure,
      { backend: 'local/platform/orders/public', status: 422 },
      'unprocessable',
    );
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'resolve', value: problemResponse(problem, 422) },
        { kind: 'resolve', value: jsonResponse({ error: { problem } }, 422) },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect((await client.root().serial())[1]).toMatchObject({ type: problem.type, status: 422 });
    expect((await client.root().serial())[1]).toMatchObject({ type: problem.type, status: 422 });
  });

  test('distinguishes JSON non-Problem server failure from transport failures', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'resolve', value: jsonResponse({ message: 'legacy failure' }, 500) },
        { kind: 'resolve', value: textResponse('gateway bytes', 502) },
        { kind: 'resolve', value: statusOnlyResponse(503) },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect((await client.root().serial())[1]).toMatchObject({ type: problems.UpstreamFailure.type });
    expect((await client.root().serial())[1]).toMatchObject({ type: problems.TransportFailure.type });
    expect((await client.root().serial())[1]).toMatchObject({ type: problems.TransportFailure.type });
  });

  test('turns response-body failures into transport Problems', async () => {
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'resolve', value: unreadableResponse() }] });
    const client = await resolvedClient(scripted.client);
    const serial = await client.root().serial();
    expect(serial[0]).toBe('err');
    expect(serial[1]).toMatchObject({ type: problems.TransportFailure.type });
  });

  test('catches sync throws and rejected promises so proxied calls never reject', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'throw', error: new Error('sync exploded') },
        { kind: 'reject', error: new Error('async exploded') },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect((await client.root().serial())[0]).toBe('err');
    expect((await client.root().serial())[0]).toBe('err');
  });
});

describe('recursive SDK proxy', () => {
  test('proxies namespaces, preserves method this, and leaves Promise properties alone', async () => {
    const scripted = createScriptedKiotaClient({
      root: [{ kind: 'return', value: 'root' }],
      'nested.call': [{ kind: 'return', value: 'nested' }],
    });
    const client = await resolvedClient(scripted.client);
    expect(await client.root('a').serial()).toEqual(['ok', 'root']);
    expect(await client.nested.call('b').serial()).toEqual(['ok', 'nested']);
    expect(scripted.backend.calls[0]?.owner).toBe(scripted.client);
    expect(scripted.backend.calls[1]?.owner).toBe(scripted.client.nested);
    expect(await client.promisedNamespace).toEqual({ untouched: true });
    expect('serial' in client.promisedNamespace).toBe(false);
  });
});

describe('immutable LPSM backend tree', () => {
  test('rejects duplicate registration and reports missing resolution as Results', async () => {
    const auth = fakeAuthed({ [resourceKey]: 'token' });
    const binding = {
      coordinate,
      resource,
      baseUrl: 'https://orders.local.test',
      auth,
      createClient: () => ({ root: () => true }),
    };
    const duplicate = await createApiEngine({ problems, bindings: [binding, binding] }).serial();
    expect(duplicate[0]).toBe('err');
    if (duplicate[0] === 'err') expect(duplicate[1].type).toBe(problems.ConfigurationFailure.type);

    const engine = await createApiEngine({ problems, bindings: [binding] }).serial();
    if (engine[0] === 'err') throw new Error('engine setup failed');
    const missing = await engine[1].resolve({ ...coordinate, module: 'missing' }).serial();
    expect(missing[0]).toBe('err');
    if (missing[0] === 'err') expect(missing[1].type).toBe(problems.BackendNotFound.type);
    expect(engine[1].list()[0]).toMatchObject({
      key: 'local/platform/orders/public',
      baseUrl: 'https://orders.local.test',
      resourceKey,
    });
  });

  test('rejects invalid coordinates, URLs, resources, and asynchronous factories as Results', async () => {
    const auth = fakeAuthed({ [resourceKey]: 'token' });
    const base = {
      coordinate,
      resource,
      baseUrl: 'https://orders.local.test',
      auth,
      createClient: () => ({ root: () => true }),
    };
    const invalids = [
      { ...base, coordinate: { ...coordinate, module: '' } },
      { ...base, baseUrl: 'file:///tmp/api' },
      { ...base, resource: { ...resource, resourceName: '' } },
      { ...base, timeoutMs: 0 },
    ];
    for (const binding of invalids)
      expect((await createApiEngine({ problems, bindings: [binding] }).serial())[0]).toBe('err');

    const ready = await createApiEngine({
      problems,
      bindings: [{ ...base, createClient: (() => Promise.resolve({})) as never }],
    }).serial();
    if (ready[0] === 'err') throw new Error('engine setup failed');
    expect((await ready[1].resolve(coordinate).serial())[0]).toBe('err');
  });

  test('returns malformed coordinate and base URL forms as configuration Problems', async () => {
    const auth = fakeAuthed({ [resourceKey]: 'token' });
    const base = {
      coordinate,
      resource,
      baseUrl: 'https://orders.local.test',
      auth,
      createClient: () => ({ root: () => true }),
    };
    const invalids = [
      { ...base, coordinate: null as never },
      { ...base, coordinate: { ...coordinate, module: 'bad/module' } },
      { ...base, baseUrl: 7 as never },
      { ...base, baseUrl: 'https://user:secret@orders.local.test' },
      { ...base, baseUrl: 'not a URL' },
    ];
    for (const binding of invalids) {
      expect((await createApiEngine({ problems, bindings: [binding] }).serial())[0]).toBe('err');
    }

    const hostile = { problems } as ApiEngineOptions;
    Object.defineProperty(hostile, 'bindings', {
      get() {
        throw new Error('hostile bindings getter');
      },
    });
    expect((await createApiEngine(hostile).serial())[0]).toBe('err');
  });
});

describe('problem registration contract', () => {
  test('compatibly reuses definitions and rejects a conflicting contract', async () => {
    const registry = new ProblemRegistry(testPortal);
    expect((await registerApiProblems(registry).serial())[0]).toBe('ok');
    expect((await registerApiProblems(registry).serial())[0]).toBe('ok');

    const conflicting = new ProblemRegistry(testPortal);
    conflicting.register({ ...ApiConfigurationFailure, title: 'Different title' });
    const serial = await registerApiProblems(conflicting).serial();
    expect(serial[0]).toBe('err');
    if (serial[0] === 'err') expect(serial[1].type).toBe('about:blank');
  });

  test('maps a non-Error registry failure to a registration Problem', async () => {
    const failingRegistry = {
      portal: testPortal,
      get: () => undefined,
      register: () => {
        throw 'registry failed';
      },
    } as unknown as ProblemRegistry;
    const serial = await registerApiProblems(failingRegistry).serial();
    expect(serial[0]).toBe('err');
    if (serial[0] === 'err') expect(serial[1].detail).toContain('could not be registered');
  });

  test('creates authentication failures through the registered definition', () => {
    expect(createAuthenticationProblem(problems, 'backend', 'missing token')).toMatchObject({
      type: problems.AuthenticationFailure.type,
      status: 401,
    });
  });
});

describe('defensive reconciliation paths', () => {
  const reconciliationContext = {
    backend: coordinate,
    backendKey: 'local/platform/orders/public' as const,
    problems,
  };

  test('maps invalid successful JSON, invalid failed JSON, and empty JSON deterministically', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        {
          kind: 'resolve',
          value: new Response('{invalid', {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }),
        },
        {
          kind: 'resolve',
          value: new Response('{invalid', {
            status: 500,
            headers: { 'content-type': 'application/json' },
          }),
        },
        {
          kind: 'resolve',
          value: new Response('', {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }),
        },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect((await client.root().serial())[0]).toBe('err');
    expect((await client.root().serial())[0]).toBe('err');
    expect(await client.root().serial()).toEqual(['ok', undefined]);
  });

  test('handles Kiota status/body shapes and every fallback detail shape', async () => {
    const scripted = createScriptedKiotaClient({
      root: [
        {
          kind: 'throw',
          error: { responseStatusCode: 500, responseBody: { message: 'kiota body' } },
        },
        { kind: 'throw', error: { detail: 'detail field' } },
        { kind: 'throw', error: { message: 'message field' } },
        { kind: 'throw', error: 'string failure' },
        { kind: 'throw', error: null },
      ],
    });
    const client = await resolvedClient(scripted.client);
    expect((await client.root().serial())[1]).toMatchObject({ type: problems.UpstreamFailure.type });
    for (let index = 0; index < 4; index += 1) {
      expect((await client.root().serial())[1]).toMatchObject({ type: problems.TransportFailure.type });
    }
  });

  test('reconciles nested Responses and fail-closes a rejected successful Response', async () => {
    const nested = await reconcileApiFailure(
      { response: jsonResponse({ message: 'nested response' }, 500) },
      reconciliationContext,
    );
    expect(nested[0]).toBe('err');
    const impossible = await reconcileApiFailure(textResponse('ok'), reconciliationContext);
    expect(impossible[0]).toBe('err');
    expect(impossible[1].detail).toContain('unexpectedly contained');
  });

  test('keeps built-in response-like values out of namespace proxying', async () => {
    const response = textResponse('raw');
    const client = await resolvedClient({ response, bytes: new Uint8Array([1]), value: null });
    expect((client as unknown as { response: Response }).response).toBe(response);
    expect((client as unknown as { bytes: Uint8Array }).bytes).toBeInstanceOf(Uint8Array);
    expect((client as unknown as { value: null }).value).toBeNull();
  });
});

describe('per-backend auth and fetch policy', () => {
  test('uses each backend canonical ResourceKey without token bleed', async () => {
    const secondCoordinate: LpsmCoordinate = { ...coordinate, service: 'billing' };
    const secondResource = { ...resource, service: 'billing', resourceName: 'billing-api' };
    const secondKey = await canonicalTestResource(secondResource);
    const headers: string[] = [];
    const fetch: FetchLike = async (_input, init) => {
      headers.push(new Headers(init?.headers).get('authorization') ?? '');
      return jsonResponse({ ok: true });
    };
    const firstAuth = fakeAuthed({ [resourceKey]: 'orders-token' });
    const secondAuth = fakeAuthed({ [secondKey]: 'billing-token' });
    const engine = await createApiEngine({
      problems,
      fetch,
      bindings: [
        {
          coordinate,
          resource,
          baseUrl: 'https://orders.local.test',
          auth: firstAuth,
          createClient: fetchClient,
        },
        {
          coordinate: secondCoordinate,
          resource: secondResource,
          baseUrl: 'https://billing.local.test',
          auth: secondAuth,
          createClient: fetchClient,
        },
      ],
    }).serial();
    if (engine[0] === 'err') throw new Error('engine setup failed');
    const first = await engine[1].resolve<ReturnType<typeof fetchClient>>(coordinate).serial();
    const second = await engine[1].resolve<ReturnType<typeof fetchClient>>(secondCoordinate).serial();
    if (first[0] === 'err' || second[0] === 'err') throw new Error('client setup failed');
    await first[1].root().serial();
    await second[1].root().serial();
    expect(headers).toEqual(['Bearer orders-token', 'Bearer billing-token']);
  });

  test('forces token state once when the canonical resource token is initially absent', async () => {
    const auth = fakeUnauthed({ [resourceKey]: 'forced-token' });
    const seen: string[] = [];
    const client = await createFetchResolvedClient(
      async (_input, init) => {
        seen.push(new Headers(init?.headers).get('authorization') ?? '');
        return statusOnlyResponse(204);
      },
      undefined,
      undefined,
      auth,
    );
    await client.root().serial();
    expect(auth.getCalls).toBe(1);
    expect(auth.forceCalls).toBe(1);
    expect(seen).toEqual(['Bearer forced-token']);
  });

  test('returns an authentication Problem when forceTokenSet still has no resource token', async () => {
    let calls = 0;
    const auth = fakeUnauthed();
    const client = await createFetchResolvedClient(
      async () => {
        calls += 1;
        return statusOnlyResponse(204);
      },
      undefined,
      undefined,
      auth,
    );
    const serial = await client.root().serial();
    expect(serial[0]).toBe('err');
    if (serial[0] === 'err') expect(serial[1].type).toBe(problems.AuthenticationFailure.type);
    expect(calls).toBe(0);
  });

  test('does not retry a received 5xx response', async () => {
    let calls = 0;
    const auth = fakeAuthed({ [resourceKey]: 'token' });
    const engine = await createApiEngine({
      problems,
      fetch: async () => {
        calls += 1;
        return jsonResponse({ message: 'unavailable' }, 503);
      },
      bindings: [{ coordinate, resource, baseUrl: 'https://orders.local.test', auth, createClient: fetchClient }],
    }).serial();
    if (engine[0] === 'err') throw new Error('engine setup failed');
    const client = await engine[1].resolve<ReturnType<typeof fetchClient>>(coordinate).serial();
    if (client[0] === 'err') throw new Error('client setup failed');
    expect((await client[1].root().serial())[0]).toBe('err');
    expect(calls).toBe(1);
  });

  test('retries one opaque failure and succeeds on the second attempt', async () => {
    let calls = 0;
    const fetch: FetchLike = async () => {
      calls += 1;
      if (calls === 1) throw new TypeError('socket closed');
      return jsonResponse({ recovered: true });
    };
    const client = await createFetchResolvedClient(fetch);
    expect(await client.root().serial()).toEqual(['ok', { recovered: true }]);
    expect(calls).toBe(2);
  });

  test('trips rescue only after two opaque failures when enabled', async () => {
    let calls = 0;
    let trips = 0;
    const fetch: FetchLike = async () => {
      calls += 1;
      throw new TypeError('closed');
    };
    const client = await createFetchResolvedClient(fetch, {
      enabled: true,
      trip(context) {
        trips += 1;
        expect(context.attempts).toBe(2);
      },
    });
    const serial = await client.root().serial();
    expect(serial[0]).toBe('err');
    expect(calls).toBe(2);
    expect(trips).toBe(1);
  });

  test('does not trip rescue when disabled', async () => {
    let trips = 0;
    const client = await createFetchResolvedClient(
      async () => {
        throw new TypeError('closed');
      },
      {
        enabled: false,
        trip: () => {
          trips += 1;
        },
      },
    );
    await client.root().serial();
    expect(trips).toBe(0);
  });

  test('maps timeout and caller abort to transport Problems without retry', async () => {
    let calls = 0;
    const fetch: FetchLike = async (_input, init) => {
      calls += 1;
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      });
    };
    const timed = await createFetchResolvedClient(fetch, undefined, 5);
    const timedSerial = await timed.root().serial();
    expect(timedSerial[0]).toBe('err');
    if (timedSerial[0] === 'err') assertProblem(timedSerial[1], problems.TransportFailure.type);
    expect(calls).toBe(1);

    const controller = new AbortController();
    controller.abort();
    const aborted = await createFetchResolvedClient(fetch);
    expect((await aborted.root({ signal: controller.signal }).serial())[0]).toBe('err');
    expect(calls).toBe(1);

    const liveController = new AbortController();
    const liveAbort = aborted.root({ signal: liveController.signal }).serial();
    setTimeout(() => liveController.abort(), 1);
    expect((await liveAbort)[0]).toBe('err');
    expect(calls).toBe(2);
  });
});

async function createFetchResolvedClient(
  fetch: FetchLike,
  rescue?: ApiEngineOptions['bindings'][number]['rescue'],
  timeoutMs?: number,
  auth = fakeAuthed({ [resourceKey]: 'token' }),
) {
  const engine = await createApiEngine({
    problems,
    fetch,
    bindings: [
      {
        coordinate,
        resource,
        baseUrl: 'https://orders.local.test',
        auth,
        createClient: fetchClient,
        ...(rescue === undefined ? {} : { rescue }),
        ...(timeoutMs === undefined ? {} : { timeoutMs }),
      },
    ],
  }).serial();
  if (engine[0] === 'err') throw new Error('engine setup failed');
  const client = await engine[1].resolve<ReturnType<typeof fetchClient>>(coordinate).serial();
  if (client[0] === 'err') throw new Error('client setup failed');
  return client[1];
}
