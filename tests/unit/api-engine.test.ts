import { describe, it } from 'bun:test';
import should from 'should';
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

function requestHeaders(input: Parameters<FetchLike>[0], init?: RequestInit): Headers {
  return new Headers(input instanceof Request ? input.headers : init?.headers);
}

describe('SDK result reconciliation', () => {
  it('returns typed/direct success as Ok', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'return', value: { id: 7 } }] });
    const client = await resolvedClient(scripted.client);

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial).eql(['ok', { id: 7 }]);
  });

  it('flattens a direct Result without throwing unwrap', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: Ok({ source: 'result' }) },
        { kind: 'return', value: Err(problemFixture(problems.TransportFailure, { backend: 'x', reason: 'x' })) },
      ],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const success = await client.root().serial();
    const failure = await client.root().serial();

    // Assert
    should(success).eql(['ok', { source: 'result' }]);
    should(failure[0]).equal('err');
  });

  it('decodes a successful JSON Response', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [{ kind: 'resolve', value: jsonResponse({ items: [1, 2] }) }],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial).eql(['ok', { items: [1, 2] }]);
  });

  it('keeps nested Problem-shaped audit data successful in direct and JSON values', async () => {
    // Arrange
    const problem = problemFixture(
      problems.UpstreamFailure,
      { backend: 'local/platform/orders/public', status: 409 },
      'historical failure',
    );
    const audit = { history: { latestProblem: problem } };
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'return', value: audit },
        { kind: 'resolve', value: jsonResponse(audit) },
      ],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const direct = await client.root().serial();
    const json = await client.root().serial();

    // Assert
    should(direct).eql(['ok', audit]);
    should(json).eql(['ok', audit]);
  });

  it('passes successful non-JSON/stream Responses through without consuming them', async () => {
    // Arrange
    const response = textResponse('download');
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'resolve', value: response }] });
    const client = await resolvedClient(scripted.client);

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial).eql(['ok', response]);
    should(response.bodyUsed).equal(false);
  });

  it('maps direct and nested Problems to Err', async () => {
    // Arrange
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

    // Act
    const direct = await client.root().serial();
    const nested = await client.root().serial();

    // Assert
    should(direct).eql(['err', problem]);
    should(nested).eql(['err', problem]);
  });

  it('finds Problems through Error causes and terminates cyclic cause chains', async () => {
    // Arrange
    const problem = problemFixture(
      problems.UpstreamFailure,
      { backend: 'local/platform/orders/public', status: 409 },
      'caused failure',
    );
    const cyclic = new Error('cyclic failure');
    Object.defineProperty(cyclic, 'cause', { value: cyclic });
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'throw', error: new Error('wrapper', { cause: problem }) },
        { kind: 'throw', error: cyclic },
      ],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const causedSerial = await client.root().serial();
    const cyclicSerial = await client.root().serial();

    // Assert
    should(causedSerial).eql(['err', problem]);
    should(cyclicSerial[0]).equal('err');
    if (cyclicSerial[0] === 'err') should(cyclicSerial[1].type).equal(problems.TransportFailure.type);
  });

  it('maps RFC 9457 and nested RFC 9457 HTTP bodies to Err', async () => {
    // Arrange
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

    // Act
    const direct = await client.root().serial();
    const nested = await client.root().serial();

    // Assert
    should(direct[1]).match({ type: problem.type, status: 422 });
    should(nested[1]).match({ type: problem.type, status: 422 });
  });

  it('distinguishes JSON non-Problem server failure from transport failures', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'resolve', value: jsonResponse({ message: 'legacy failure' }, 500) },
        { kind: 'resolve', value: textResponse('gateway bytes', 502) },
        { kind: 'resolve', value: statusOnlyResponse(503) },
      ],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const json = await client.root().serial();
    const text = await client.root().serial();
    const empty = await client.root().serial();

    // Assert
    should(json[1]).match({ type: problems.UpstreamFailure.type });
    should(text[1]).match({ type: problems.TransportFailure.type });
    should(empty[1]).match({ type: problems.TransportFailure.type });
  });

  it('turns response-body failures into transport Problems', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({ root: [{ kind: 'resolve', value: unreadableResponse() }] });
    const client = await resolvedClient(scripted.client);

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial[0]).equal('err');
    should(serial[1]).match({ type: problems.TransportFailure.type });
  });

  it('catches sync throws and rejected promises so proxied calls never reject', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [
        { kind: 'throw', error: new Error('sync exploded') },
        { kind: 'reject', error: new Error('async exploded') },
      ],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const synchronous = await client.root().serial();
    const asynchronous = await client.root().serial();

    // Assert
    should(synchronous[0]).equal('err');
    should(asynchronous[0]).equal('err');
  });
});

describe('recursive SDK proxy', () => {
  it('proxies namespaces, preserves method this, and leaves Promise properties alone', async () => {
    // Arrange
    const scripted = createScriptedKiotaClient({
      root: [{ kind: 'return', value: 'root' }],
      'nested.call': [{ kind: 'return', value: 'nested' }],
    });
    const client = await resolvedClient(scripted.client);

    // Act
    const root = await client.root('a').serial();
    const nested = await client.nested.call('b').serial();
    const promisedNamespace = await client.promisedNamespace;

    // Assert
    should(root).eql(['ok', 'root']);
    should(nested).eql(['ok', 'nested']);
    should(scripted.backend.calls[0]?.owner).equal(scripted.client);
    should(scripted.backend.calls[1]?.owner).equal(scripted.client.nested);
    should(promisedNamespace).eql({ untouched: true });
    should('serial' in client.promisedNamespace).equal(false);
  });
});

describe('immutable LPSM backend tree', () => {
  it('rejects duplicate registration and reports missing resolution as Results', async () => {
    // Arrange
    const auth = fakeAuthed({ [resourceKey]: 'token' });
    const binding = {
      coordinate,
      resource,
      baseUrl: 'https://orders.local.test',
      auth,
      createClient: () => ({ root: () => true }),
    };

    // Act
    const duplicate = await createApiEngine({ problems, bindings: [binding, binding] }).serial();
    const engine = await createApiEngine({ problems, bindings: [binding] }).serial();
    if (engine[0] === 'err') throw new Error('engine setup failed');
    const missing = await engine[1].resolve({ ...coordinate, module: 'missing' }).serial();

    // Assert
    should(duplicate[0]).equal('err');
    if (duplicate[0] === 'err') should(duplicate[1].type).equal(problems.ConfigurationFailure.type);
    should(missing[0]).equal('err');
    if (missing[0] === 'err') should(missing[1].type).equal(problems.BackendNotFound.type);
    should(engine[1].list()[0]).match({
      key: 'local/platform/orders/public',
      baseUrl: 'https://orders.local.test',
      resourceKey,
    });
  });

  it('rejects invalid coordinates, URLs, resources, and asynchronous factories as Results', async () => {
    // Arrange
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

    // Act
    const invalidSerials = await Promise.all(
      invalids.map(binding => createApiEngine({ problems, bindings: [binding] }).serial()),
    );
    const ready = await createApiEngine({
      problems,
      bindings: [{ ...base, createClient: (() => Promise.resolve({})) as never }],
    }).serial();
    if (ready[0] === 'err') throw new Error('engine setup failed');
    const asynchronousFactory = await ready[1].resolve(coordinate).serial();

    // Assert
    for (const serial of invalidSerials) should(serial[0]).equal('err');
    should(asynchronousFactory[0]).equal('err');
  });

  it('returns malformed coordinate and base URL forms as configuration Problems', async () => {
    // Arrange
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
    const hostile = { problems } as ApiEngineOptions;
    Object.defineProperty(hostile, 'bindings', {
      get() {
        throw new Error('hostile bindings getter');
      },
    });

    // Act
    const invalidSerials = await Promise.all(
      invalids.map(binding => createApiEngine({ problems, bindings: [binding] }).serial()),
    );
    const hostileSerial = await createApiEngine(hostile).serial();

    // Assert
    for (const serial of invalidSerials) should(serial[0]).equal('err');
    should(hostileSerial[0]).equal('err');
  });
});

describe('problem registration contract', () => {
  it('compatibly reuses definitions and rejects a conflicting contract', async () => {
    // Arrange
    const registry = new ProblemRegistry(testPortal);
    const conflicting = new ProblemRegistry(testPortal);
    conflicting.register({ ...ApiConfigurationFailure, title: 'Different title' });

    // Act
    const first = await registerApiProblems(registry).serial();
    const second = await registerApiProblems(registry).serial();
    const conflictingSerial = await registerApiProblems(conflicting).serial();

    // Assert
    should(first[0]).equal('ok');
    should(second[0]).equal('ok');
    should(conflictingSerial[0]).equal('err');
    if (conflictingSerial[0] === 'err') {
      const expectedType = new ProblemRegistry(testPortal).register(ApiConfigurationFailure).type;
      should(conflictingSerial[1].type).equal(expectedType);
    }
  });

  it('maps a non-Error registry failure to a registration Problem', async () => {
    // Arrange
    const failingRegistry = {
      portal: testPortal,
      get: () => undefined,
      register: () => {
        throw 'registry failed';
      },
    } as unknown as ProblemRegistry;

    // Act
    const serial = await registerApiProblems(failingRegistry).serial();

    // Assert
    should(serial[0]).equal('err');
    if (serial[0] === 'err') {
      const expectedType = new ProblemRegistry(testPortal).register(ApiConfigurationFailure).type;
      should(serial[1].type).equal(expectedType);
      should(serial[1].detail).equal('registry failed');
    }
  });

  it('creates authentication failures through the registered definition', () => {
    // Arrange
    const expected = { type: problems.AuthenticationFailure.type, status: 401 };

    // Act
    const problem = createAuthenticationProblem(problems, 'backend', 'missing token');

    // Assert
    should(problem).match(expected);
  });
});

describe('defensive reconciliation paths', () => {
  const reconciliationContext = {
    backend: coordinate,
    backendKey: 'local/platform/orders/public' as const,
    problems,
  };

  it('maps invalid successful JSON, invalid failed JSON, and empty JSON deterministically', async () => {
    // Arrange
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

    // Act
    const invalidSuccess = await client.root().serial();
    const invalidFailure = await client.root().serial();
    const emptySuccess = await client.root().serial();

    // Assert
    should(invalidSuccess[0]).equal('err');
    should(invalidFailure[0]).equal('err');
    should(emptySuccess).eql(['ok', undefined]);
  });

  it('handles Kiota status/body shapes and every fallback detail shape', async () => {
    // Arrange
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

    // Act
    const upstream = await client.root().serial();
    const transports = [
      await client.root().serial(),
      await client.root().serial(),
      await client.root().serial(),
      await client.root().serial(),
    ];

    // Assert
    should(upstream[1]).match({ type: problems.UpstreamFailure.type });
    for (const transport of transports) should(transport[1]).match({ type: problems.TransportFailure.type });
  });

  it('reconciles nested Responses and fail-closes a rejected successful Response', async () => {
    // Arrange
    const nestedResponse = { response: jsonResponse({ message: 'nested response' }, 500) };
    const successfulResponse = textResponse('ok');

    // Act
    const nested = await reconcileApiFailure(nestedResponse, reconciliationContext);
    const impossible = await reconcileApiFailure(successfulResponse, reconciliationContext);

    // Assert
    should(nested[0]).equal('err');
    should(impossible[0]).equal('err');
    should(impossible[1].detail).containEql('unexpectedly contained');
  });

  it('keeps built-in response-like values out of namespace proxying', async () => {
    // Arrange
    const response = textResponse('raw');

    // Act
    const client = await resolvedClient({ response, bytes: new Uint8Array([1]), value: null });

    // Assert
    should((client as unknown as { response: Response }).response).equal(response);
    should((client as unknown as { bytes: Uint8Array }).bytes).be.instanceOf(Uint8Array);
    should((client as unknown as { value: null }).value).equal(null);
  });
});

describe('per-backend auth and fetch policy', () => {
  it('uses each backend canonical ResourceKey without token bleed', async () => {
    // Arrange
    const secondCoordinate: LpsmCoordinate = { ...coordinate, service: 'billing' };
    const secondResource = { ...resource, service: 'billing', resourceName: 'billing-api' };
    const secondKey = await canonicalTestResource(secondResource);
    const headers: string[] = [];
    const fetch: FetchLike = async (input, init) => {
      headers.push(requestHeaders(input, init).get('authorization') ?? '');
      return jsonResponse({ ok: true });
    };
    const firstAuth = fakeAuthed({ [resourceKey]: 'orders-token' });
    const secondAuth = fakeAuthed({ [secondKey]: 'billing-token' });

    // Act
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

    // Assert
    should(headers).eql(['Bearer orders-token', 'Bearer billing-token']);
  });

  it('forces token state once when the canonical resource token is initially absent', async () => {
    // Arrange
    const auth = fakeUnauthed({ [resourceKey]: 'forced-token' });
    const seen: string[] = [];
    const client = await createFetchResolvedClient(
      async (input, init) => {
        seen.push(requestHeaders(input, init).get('authorization') ?? '');
        return statusOnlyResponse(204);
      },
      undefined,
      undefined,
      auth,
    );

    // Act
    await client.root().serial();

    // Assert
    should(auth.getCalls).equal(1);
    should(auth.forceCalls).equal(1);
    should(seen).eql(['Bearer forced-token']);
  });

  it('returns an authentication Problem when forceTokenSet still has no resource token', async () => {
    // Arrange
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

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial[0]).equal('err');
    if (serial[0] === 'err') should(serial[1].type).equal(problems.AuthenticationFailure.type);
    should(calls).equal(0);
  });

  it('does not retry a received 5xx response', async () => {
    // Arrange
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

    // Act
    const serial = await client[1].root().serial();

    // Assert
    should(serial[0]).equal('err');
    should(calls).equal(1);
  });

  it('does not retry a received status carried by an Error cause', async () => {
    // Arrange
    let calls = 0;
    const client = await createFetchResolvedClient(async () => {
      calls += 1;
      throw new Error('wrapped response failure', { cause: { status: 503 } });
    });

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial[0]).equal('err');
    should(calls).equal(1);
  });

  it('retries a status-free cyclic cause failure exactly once', async () => {
    // Arrange
    let calls = 0;
    const cyclic = new Error('opaque cyclic failure');
    Object.defineProperty(cyclic, 'cause', { value: cyclic });
    const client = await createFetchResolvedClient(async () => {
      calls += 1;
      if (calls === 1) throw cyclic;
      return jsonResponse({ recovered: true });
    });

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial).eql(['ok', { recovered: true }]);
    should(calls).equal(2);
  });

  it('retries one opaque failure and succeeds on the second attempt', async () => {
    // Arrange
    let calls = 0;
    const fetch: FetchLike = async () => {
      calls += 1;
      if (calls === 1) throw new TypeError('socket closed');
      return jsonResponse({ recovered: true });
    };
    const client = await createFetchResolvedClient(fetch);

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial).eql(['ok', { recovered: true }]);
    should(calls).equal(2);
  });

  it('retries a POST with two fresh Request clones carrying the same body and auth', async () => {
    // Arrange
    const requests: Request[] = [];
    const methods: string[] = [];
    const bodies: string[] = [];
    const authorizations: string[] = [];
    const fetch: FetchLike = async input => {
      should(input).be.instanceOf(Request);
      const request = input as Request;
      requests.push(request);
      methods.push(request.method);
      authorizations.push(request.headers.get('authorization') ?? '');
      bodies.push(await request.text());
      if (requests.length === 1) throw new TypeError('opaque first-attempt failure');
      return jsonResponse({ recovered: true });
    };
    const client = await createFetchResolvedClient(fetch);

    // Act
    const serial = await client
      .root({ method: 'POST', body: 'same-body', headers: { 'content-type': 'text/plain' } })
      .serial();

    // Assert
    should(serial).eql(['ok', { recovered: true }]);
    should(requests).have.length(2);
    should(requests[0]).not.equal(requests[1]);
    should(methods).eql(['POST', 'POST']);
    should(bodies).eql(['same-body', 'same-body']);
    should(authorizations).eql(['Bearer token', 'Bearer token']);
  });

  it('trips rescue only after two opaque failures when enabled', async () => {
    // Arrange
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
        should(context.attempts).equal(2);
      },
    });

    // Act
    const serial = await client.root().serial();

    // Assert
    should(serial[0]).equal('err');
    should(calls).equal(2);
    should(trips).equal(1);
  });

  it('does not trip rescue when disabled', async () => {
    // Arrange
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

    // Act
    await client.root().serial();

    // Assert
    should(trips).equal(0);
  });

  it('maps timeout and caller abort to transport Problems without retry', async () => {
    // Arrange
    let calls = 0;
    const fetch: FetchLike = async (_input, init) => {
      calls += 1;
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      });
    };

    // Act
    const timed = await createFetchResolvedClient(fetch, undefined, 5);
    const timedSerial = await timed.root().serial();

    // Assert
    should(timedSerial[0]).equal('err');
    if (timedSerial[0] === 'err') assertProblem(timedSerial[1], problems.TransportFailure.type);
    should(calls).equal(1);

    // Arrange
    const controller = new AbortController();
    controller.abort();
    const aborted = await createFetchResolvedClient(fetch);

    // Act
    const preAbortedSerial = await aborted.root({ signal: controller.signal }).serial();

    // Assert
    should(preAbortedSerial[0]).equal('err');
    should(calls).equal(1);

    // Arrange
    const liveController = new AbortController();

    // Act
    const liveAbort = aborted.root({ signal: liveController.signal }).serial();
    setTimeout(() => liveController.abort(), 1);
    const liveAbortSerial = await liveAbort;

    // Assert
    should(liveAbortSerial[0]).equal('err');
    should(calls).equal(2);
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
