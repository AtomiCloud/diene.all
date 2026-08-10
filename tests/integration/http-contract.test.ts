import { afterAll, describe, it } from 'bun:test';
import should from 'should';

import { type BackendClientContext, createApiEngine } from '../../src';
import { canonicalTestResource, createApiTestProblems, fakeAuthed, problemFixture } from '../../src/test-helper';

const { problems } = await createApiTestProblems();
const coordinate = {
  landscape: 'local',
  platform: 'platform',
  service: 'integration',
  module: 'http',
};
const resource = {
  platform: 'platform',
  landscape: 'local',
  service: 'integration',
  resourceName: 'api',
};
const resourceKey = await canonicalTestResource(resource);
const rfcProblem = problemFixture(
  problems.UpstreamFailure,
  { backend: 'local/platform/integration/http', status: 409 },
  'real RFC 9457 response',
);

const server = Bun.serve({
  hostname: '127.0.0.1',
  port: 0,
  routes: {
    '/ok': Response.json({ source: 'real-server' }),
    '/problem': new Response(JSON.stringify(rfcProblem), {
      status: 409,
      headers: { 'content-type': 'application/problem+json' },
    }),
    '/legacy-json': Response.json({ message: 'legacy server error' }, { status: 500 }),
    '/plain': new Response('plain upstream failure', {
      status: 502,
      headers: { 'content-type': 'text/plain' },
    }),
    '/status-only': new Response(null, { status: 503 }),
    '/body-failure': () => {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode('{"partial":'));
          controller.error(new Error('real streamed body failure'));
        },
      });
      return new Response(stream, {
        status: 502,
        headers: { 'content-type': 'application/json' },
      });
    },
  },
  fetch: () => new Response(null, { status: 404 }),
});

afterAll(() => server.stop(true));

function httpClient(context: BackendClientContext) {
  return {
    get(path: string) {
      return context.fetch(`${context.baseUrl}${path}`);
    },
  };
}

async function realClient(baseUrl = server.url.origin) {
  const engine = await createApiEngine({
    problems,
    bindings: [
      {
        coordinate,
        resource,
        baseUrl,
        auth: fakeAuthed({ [resourceKey]: 'integration-token' }),
        createClient: httpClient,
        timeoutMs: 500,
      },
    ],
  }).serial();
  if (engine[0] === 'err') throw new Error(engine[1].detail ?? engine[1].title);
  const client = await engine[1].resolve<ReturnType<typeof httpClient>>(coordinate).serial();
  if (client[0] === 'err') throw new Error(client[1].detail ?? client[1].title);
  return client[1];
}

describe('real HTTP reconciliation contract', () => {
  it('should handle OK JSON and RFC 9457', async () => {
    // Arrange
    const client = await realClient();

    // Act
    const actualOk = await client.get('/ok').serial();
    const actualProblem = await client.get('/problem').serial();

    // Assert
    should(actualOk).deepEqual(['ok', { source: 'real-server' }]);
    should(actualProblem[0]).equal('err');
    if (actualProblem[0] === 'err') should(actualProblem[1]).match({ type: rfcProblem.type, status: 409 });
  });

  it('should classify JSON, plain-text, and status-only failures', async () => {
    // Arrange
    const client = await realClient();

    // Act
    const legacy = await client.get('/legacy-json').serial();
    const plain = await client.get('/plain').serial();
    const statusOnly = await client.get('/status-only').serial();

    // Assert
    if (legacy[0] === 'err') should(legacy[1].type).equal(problems.UpstreamFailure.type);
    else throw new Error('expected legacy JSON failure');
    if (plain[0] === 'err') should(plain[1].type).equal(problems.TransportFailure.type);
    else throw new Error('expected plain transport failure');
    if (statusOnly[0] === 'err') should(statusOnly[1].type).equal(problems.TransportFailure.type);
    else throw new Error('expected status-only transport failure');
  });

  it('should map a real streamed body failure to a transport Err', async () => {
    // Arrange
    const client = await realClient();

    // Act
    const actual = await client.get('/body-failure').serial();

    // Assert
    should(actual[0]).equal('err');
    if (actual[0] === 'err') should(actual[1].type).equal(problems.TransportFailure.type);
  });

  it('should map a closed local port to a transport Err after the bounded retry', async () => {
    // Arrange
    const disposable = Bun.serve({ hostname: '127.0.0.1', port: 0, fetch: () => new Response('ok') });
    const closedOrigin = disposable.url.origin;
    disposable.stop(true);
    const client = await realClient(closedOrigin);

    // Act
    const actual = await client.get('/closed').serial();

    // Assert
    should(actual[0]).equal('err');
    if (actual[0] === 'err') should(actual[1].type).equal(problems.TransportFailure.type);
  });
});
