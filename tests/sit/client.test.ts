import { afterEach, describe, expect, it } from 'bun:test';
import { type ScenarioEvidence, validScenarioEvidence } from './client-fixtures.ts';
import { type MercuryTestStack, type ProviderName, requiredProviderNames } from './contract.ts';
import { createMercuryTestStackFromEnvironment } from './stack-adapter.ts';

interface StoppableServer {
  stop(closeActiveConnections?: boolean): void | Promise<void>;
}

interface RecordedRequest {
  readonly method: string;
  readonly pathname: string;
  readonly authorization: string | null;
  readonly accept: string | null;
  readonly contentType: string | null;
  readonly protocol: string | null;
  readonly body: unknown;
}

interface ClientErrorShape extends Error {
  readonly code?: string;
}

const sessionId = 'mercury-sit-session_1';
const productBaseUrl = 'https://mercury.example.test';
const liveServers: StoppableServer[] = [];

const scenarioCalls = [
  ['inspectDependencies', 'dependencies'],
  ['runProviderVerificationMatrix', 'provider-verification'],
  ['runAtomicAcceptance', 'atomic-acceptance'],
  ['runFanout', 'fanout'],
  ['runSignatureLifecycle', 'signature-lifecycle'],
  ['runConsoleJourney', 'console-journey'],
  ['runAppleBackfill', 'apple-backfill'],
  ['inspectGoogleSubscription', 'google-subscription'],
  ['runArchiveLifecycle', 'archive-lifecycle'],
  ['inspectRoute53Landing', 'route53-landing'],
] as const satisfies readonly [Exclude<keyof MercuryTestStack, 'close'>, keyof ScenarioEvidence][];

const startControlServer = (
  handler: (request: Request) => Response | Promise<Response>,
): { readonly baseUrl: string } => {
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: 0,
    fetch: handler,
  });
  const { port } = server;
  if (port === undefined) {
    void server.stop(true);
    throw new Error('Ephemeral SIT control server did not bind a port');
  }
  liveServers.push(server);
  return {
    baseUrl: `http://127.0.0.1:${port}`,
  };
};

const environmentFor = (
  controlBaseUrl: string,
  overrides: Readonly<Record<string, string | undefined>> = {},
): Readonly<Record<string, string | undefined>> => ({
  MERCURY_SIT_BASE_URL: productBaseUrl,
  MERCURY_SIT_CONTROL_URL: controlBaseUrl,
  ...overrides,
});

const recordRequest = async (request: Request): Promise<RecordedRequest> => {
  const body = await request.text();
  return {
    method: request.method,
    pathname: new URL(request.url).pathname,
    authorization: request.headers.get('authorization'),
    accept: request.headers.get('accept'),
    contentType: request.headers.get('content-type'),
    protocol: request.headers.get('x-mercury-sit-protocol'),
    body: body.length === 0 ? undefined : JSON.parse(body),
  };
};

const jsonResponse = (payload: unknown, status = 200): Response =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });

const captureError = async (operation: Promise<unknown>): Promise<ClientErrorShape> => {
  try {
    await operation;
  } catch (error) {
    expect(error).toBeInstanceOf(Error);
    return error as ClientErrorShape;
  }
  throw new Error('Expected operation to reject');
};

afterEach(async () => {
  const servers = liveServers.splice(0);
  await Promise.all(servers.map(server => server.stop(true)));
});

describe('Mercury remote SIT client protocol', () => {
  it('initializes once, covers every scenario endpoint, and cleans up exactly once', async () => {
    const requests: RecordedRequest[] = [];
    const { baseUrl } = startControlServer(async request => {
      const recorded = await recordRequest(request);
      requests.push(recorded);

      if (recorded.pathname === '/v1/sessions') {
        return jsonResponse({ sessionId });
      }
      if (recorded.pathname === `/v1/sessions/${sessionId}`) {
        return new Response(null, { status: 204 });
      }

      const prefix = `/v1/sessions/${sessionId}/scenarios/`;
      if (recorded.pathname.startsWith(prefix)) {
        const scenarioName = recorded.pathname.slice(prefix.length) as keyof ScenarioEvidence;
        const evidence: unknown = validScenarioEvidence[scenarioName];
        if (evidence !== undefined) {
          return jsonResponse(evidence);
        }
      }
      return new Response('not found', { status: 404 });
    });

    const stack = await createMercuryTestStackFromEnvironment(
      environmentFor(baseUrl, { MERCURY_SIT_CONTROL_BEARER: 'control-token' }),
    );

    for (const [method, scenarioName] of scenarioCalls) {
      const evidence = await stack[method]();
      expect(evidence).toEqual(validScenarioEvidence[scenarioName]);
    }

    const firstClose = stack.close();
    const secondClose = stack.close();
    expect(secondClose).toBe(firstClose);
    await Promise.all([firstClose, secondClose]);
    await stack.close();

    expect(requests).toHaveLength(scenarioCalls.length + 2);
    expect(requests[0]).toEqual({
      method: 'POST',
      pathname: '/v1/sessions',
      authorization: 'Bearer control-token',
      accept: 'application/json',
      contentType: 'application/json',
      protocol: '1',
      body: {
        productBaseUrl,
        providerFixtures: requiredProviderNames,
      },
    });

    for (const [index, [, scenarioName]] of scenarioCalls.entries()) {
      expect(requests[index + 1]).toEqual({
        method: 'POST',
        pathname: `/v1/sessions/${sessionId}/scenarios/${scenarioName}`,
        authorization: 'Bearer control-token',
        accept: 'application/json',
        contentType: 'application/json',
        protocol: '1',
        body: {},
      });
    }

    expect(requests.at(-1)).toEqual({
      method: 'DELETE',
      pathname: `/v1/sessions/${sessionId}`,
      authorization: 'Bearer control-token',
      accept: 'application/json',
      contentType: null,
      protocol: '1',
      body: undefined,
    });

    const closedError = await captureError(stack.inspectDependencies());
    expect(closedError).toMatchObject({ code: 'closed' });
  });

  it('omits authorization when no control bearer is injected', async () => {
    const authorizations: Array<string | null> = [];
    const { baseUrl } = startControlServer(request => {
      authorizations.push(request.headers.get('authorization'));
      const pathname = new URL(request.url).pathname;
      if (pathname === '/v1/sessions') {
        return jsonResponse({ sessionId });
      }
      return new Response(null, { status: 204 });
    });

    const stack = await createMercuryTestStackFromEnvironment(environmentFor(baseUrl));
    await stack.close();

    expect(authorizations).toEqual([null, null]);
  });

  it('rejects an unsafe session identifier before constructing scenario paths', async () => {
    let requestCount = 0;
    const { baseUrl } = startControlServer(() => {
      requestCount += 1;
      return jsonResponse({ sessionId: '..' });
    });

    const error = await captureError(createMercuryTestStackFromEnvironment(environmentFor(baseUrl)));
    expect(error).toMatchObject({ code: 'protocol' });
    expect(error.message).toContain('sessionId');
    expect(requestCount).toBe(1);
  });

  for (const failure of [
    {
      name: 'non-success HTTP status',
      response: () => jsonResponse({ message: 'unavailable' }, 503),
      code: 'http',
      message: 'returned HTTP 503',
    },
    {
      name: 'wrong content type',
      response: () => new Response(JSON.stringify(validScenarioEvidence.dependencies)),
      code: 'protocol',
      message: 'must return application/json',
    },
    {
      name: 'malformed JSON',
      response: () =>
        new Response('{"neon":', {
          headers: { 'Content-Type': 'application/json' },
        }),
      code: 'protocol',
      message: 'returned malformed JSON',
    },
    {
      name: 'missing nested evidence',
      response: () => {
        const incomplete = structuredClone(validScenarioEvidence.dependencies);
        Reflect.deleteProperty(incomplete.tigris, 'readAfterWriteVerified');
        return jsonResponse(incomplete);
      },
      code: 'protocol',
      message: 'tigris.readAfterWriteVerified',
    },
  ]) {
    it(`rejects ${failure.name}`, async () => {
      const { baseUrl } = startControlServer(request => {
        const pathname = new URL(request.url).pathname;
        if (pathname === '/v1/sessions') {
          return jsonResponse({ sessionId });
        }
        if (request.method === 'DELETE') {
          return new Response(null, { status: 204 });
        }
        return failure.response();
      });

      const stack = await createMercuryTestStackFromEnvironment(environmentFor(baseUrl));
      const error = await captureError(stack.inspectDependencies());
      expect(error).toMatchObject({ code: failure.code });
      expect(error.message).toContain(failure.message);
      await stack.close();
    });
  }

  it('bounds a stalled scenario request with the injected timeout', async () => {
    let releaseScenario = (): void => {};
    const stalledScenario = new Promise<void>(resolve => {
      releaseScenario = resolve;
    });
    const { baseUrl } = startControlServer(async request => {
      const pathname = new URL(request.url).pathname;
      if (pathname === '/v1/sessions') {
        return jsonResponse({ sessionId });
      }
      if (request.method === 'DELETE') {
        return new Response(null, { status: 204 });
      }
      await stalledScenario;
      return jsonResponse(validScenarioEvidence.dependencies);
    });

    const stack = await createMercuryTestStackFromEnvironment(
      environmentFor(baseUrl, { MERCURY_SIT_TIMEOUT_MS: '500' }),
    );
    const error = await captureError(stack.inspectDependencies());
    expect(error).toMatchObject({ code: 'timeout' });
    expect(error.message).toContain('exceeded 500ms');

    releaseScenario();
    await stack.close();
  });

  it('classifies a refused control connection as a network failure', async () => {
    const error = await captureError(
      createMercuryTestStackFromEnvironment(environmentFor('http://127.0.0.1:1', { MERCURY_SIT_TIMEOUT_MS: '250' })),
    );
    expect(error).toMatchObject({ code: 'network' });
    expect(error.message).toContain('initialize failed');
  });

  it('returns the same cleanup failure and sends only one DELETE', async () => {
    let deleteCount = 0;
    const { baseUrl } = startControlServer(request => {
      const pathname = new URL(request.url).pathname;
      if (pathname === '/v1/sessions') {
        return jsonResponse({ sessionId });
      }
      deleteCount += 1;
      return jsonResponse({ message: 'cleanup failed' }, 503);
    });

    const stack = await createMercuryTestStackFromEnvironment(environmentFor(baseUrl));
    const firstClose = stack.close();
    const secondClose = stack.close();
    expect(secondClose).toBe(firstClose);

    const [firstError, secondError] = await Promise.all([captureError(firstClose), captureError(secondClose)]);
    expect(firstError).toBe(secondError);
    expect(firstError).toMatchObject({ code: 'http' });
    expect(firstError.message).toContain('cleanup returned HTTP 503');
    expect(stack.close()).toBe(firstClose);
    expect(deleteCount).toBe(1);
  });
});

describe('Mercury remote SIT client configuration', () => {
  const validEnvironment = environmentFor('http://127.0.0.1:1');
  const configurationFailures: readonly {
    readonly name: string;
    readonly environment?: Readonly<Record<string, string | undefined>>;
    readonly fixtures?: readonly string[];
  }[] = [
    { name: 'missing product URL', environment: { MERCURY_SIT_BASE_URL: undefined } },
    { name: 'non-HTTPS product URL', environment: { MERCURY_SIT_BASE_URL: 'http://mercury.example.test' } },
    {
      name: 'product URL path',
      environment: { MERCURY_SIT_BASE_URL: 'https://mercury.example.test/webhooks' },
    },
    { name: 'missing control URL', environment: { MERCURY_SIT_CONTROL_URL: undefined } },
    { name: 'invalid control protocol', environment: { MERCURY_SIT_CONTROL_URL: 'ftp://control.example.test' } },
    {
      name: 'control URL query',
      environment: { MERCURY_SIT_CONTROL_URL: 'https://control.example.test?session=1' },
    },
    { name: 'empty bearer', environment: { MERCURY_SIT_CONTROL_BEARER: '' } },
    { name: 'bearer whitespace', environment: { MERCURY_SIT_CONTROL_BEARER: 'two tokens' } },
    { name: 'fractional timeout', environment: { MERCURY_SIT_TIMEOUT_MS: '1.5' } },
    { name: 'zero timeout', environment: { MERCURY_SIT_TIMEOUT_MS: '0' } },
    { name: 'oversized timeout', environment: { MERCURY_SIT_TIMEOUT_MS: '300001' } },
    { name: 'missing provider fixture', fixtures: requiredProviderNames.slice(0, -1) },
    { name: 'reordered provider fixtures', fixtures: [...requiredProviderNames].reverse() },
    {
      name: 'unknown provider fixture',
      fixtures: [...requiredProviderNames.slice(0, -1), 'unknown-provider'],
    },
  ];

  for (const failure of configurationFailures) {
    it(`rejects ${failure.name} before opening a control session`, async () => {
      const environment = { ...validEnvironment, ...failure.environment };
      const fixtures = (failure.fixtures ?? requiredProviderNames) as readonly ProviderName[];
      const error = await captureError(createMercuryTestStackFromEnvironment(environment, fixtures));
      expect(error).toMatchObject({ code: 'configuration' });
    });
  }
});
