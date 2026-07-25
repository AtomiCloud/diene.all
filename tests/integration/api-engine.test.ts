import { afterAll, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { YamlConfigSource, loadConfig } from '@atomicloud/diene.config';
import { createClientAuthCache, ClientAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import { configRegistry } from '../../src/config';
import { backendBindings } from '../../src/adapters/external/core';
import { buildApiEngine } from '../../src/adapters/external/engine';
import type { RootConfig } from '../../src/adapters/server-config';

// Integration: the registration point composes real api-engine bindings from
// config, and the engine resolves Result-mapped clients per coordinate.

let server: ReturnType<typeof Bun.serve>;
let config: RootConfig;

const retriever = new ClientAuthStateRetriever({
  cache: createClientAuthCache(),
  // The fixture backend requires no auth; the retriever never gets called
  // because the sample client factory does not attach a security worker.
  fetch: async () => Response.json(['ok', { __kind: 'unauthed', value: { isAuthed: false } }]),
});

beforeAll(async () => {
  server = Bun.serve({
    port: 0,
    fetch: request => {
      const url = new URL(request.url);
      if (url.pathname === '/ping') return Response.json({ pong: true });
      return new Response('not found', { status: 404 });
    },
  });

  const dir = `${import.meta.dir}/fixtures/config`;
  await Bun.write(
    `${dir}/config.yaml`,
    (await Bun.file(`${import.meta.dir}/../../config/config.yaml`).text()).replace(
      'backends: {}',
      `backends:
  fixture:
    baseUrl: http://127.0.0.1:${server.port}
    platform: diene
    service: fixture
    module: api`,
    ),
  );
  config = (await loadConfig(new YamlConfigSource({ dir }), configRegistry, {
    prefix: 'ATOMI_',
    landscape: 'base',
  })) as RootConfig;
});

afterAll(() => {
  server.stop(true);
});

describe('backendBindings', () => {
  it('should derive one binding per configured backend with the LPSM coordinate', () => {
    // Arrange

    // Act
    const bindings = backendBindings(config, 'base', retriever);

    // Assert
    should(bindings.length).equal(1);
    should(bindings[0]?.coordinate).deepEqual({
      landscape: 'base',
      platform: 'diene',
      service: 'fixture',
      module: 'api',
    });
    should(bindings[0]?.resource.resourceName).equal('fixture');
    should(bindings[0]?.retry).equal('opaque-network-once');
  });
});

describe('buildApiEngine', () => {
  it('should resolve the configured backend and list its coordinate', async () => {
    // Arrange

    // Act
    const listed = await buildApiEngine(config, 'base', retriever)
      .map(engine => engine.list())
      .serial();

    // Assert
    should(listed[0]).equal('ok');
    if (listed[0] === 'ok') {
      should(listed[1].length).equal(1);
      should(listed[1][0]?.key).equal('base/diene/fixture/api');
      should(listed[1][0]?.baseUrl).startWith('http://127.0.0.1:');
    }
  });

  it('should reach the fixture backend through the default JSON client', async () => {
    // Arrange
    const engine = await buildApiEngine(config, 'base', retriever).serial();
    should(engine[0]).equal('ok');
    if (engine[0] !== 'ok') return;

    // Act — resolve the raw client and hit the fixture.
    const resolved = await engine[1]
      .resolve<{ request: (path: string) => Promise<Response> }>({
        landscape: 'base',
        platform: 'diene',
        service: 'fixture',
        module: 'api',
      })
      .serial();

    // Assert
    should(resolved[0]).equal('ok');
  });
});
