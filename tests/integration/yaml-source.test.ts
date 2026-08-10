import { afterAll, beforeAll, describe, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import should from 'should';
import { z } from 'zod';
import { YamlConfigSource, YamlConfigSourceError } from '../../src/adapters/yaml-source.js';
import { loadConfig } from '../../src/lib/loader.js';
import { ConfigRegistry } from '../../src/lib/registry.js';

const registry = ConfigRegistry.create().register(
  'server',
  z.object({ port: z.number(), host: z.string(), tags: z.array(z.string()) }),
);

let dir: string;

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), 'diene-config-int-'));
  await writeFile(
    join(dir, 'config.yaml'),
    ['$schema: ./schema.json', 'server:', '  port: 80', '  host: base-host', '  tags:', '    - a', '    - b'].join(
      '\n',
    ),
  );
  await writeFile(join(dir, 'prod.config.yaml'), ['server:', '  host: prod-host'].join('\n'));
  await writeFile(join(dir, 'empty.config.yaml'), '');
  await writeFile(join(dir, 'broken.config.yaml'), '- just\n- a\n- list\n');
});

afterAll(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe('YamlConfigSource — through the full loader', () => {
  it('should load base + landscape overlay + runtime env with indexed-list override', async () => {
    // Arrange
    const source = new YamlConfigSource({
      dir,
      env: { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__TAGS__1: 'z' },
    });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_', landscape: 'prod' });

    // Assert
    should(config.get('server')).deepEqual({ port: 8080, host: 'prod-host', tags: ['a', 'z'] });
  });

  it('should treat a missing overlay file as an empty overlay', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: { ATOMI_SERVER__PORT: '80' } });

    // Act — landscape with no file present
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_', landscape: 'staging' });

    // Assert — base host survives
    should(config.get('server').host).equal('base-host');
  });

  it('should read runtime values from process.env by default', async () => {
    // Arrange
    process.env.ATOMI_SERVER__PORT = '9090';
    const source = new YamlConfigSource({ dir });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_' });

    // Assert
    should(config.get('server').port).equal(9090);
    delete process.env.ATOMI_SERVER__PORT;
  });

  it('should apply a build-time env map before runtime env', async () => {
    // Arrange
    const source = new YamlConfigSource({
      dir,
      buildTimeEnv: { ATOMI_SERVER__HOST: 'build-host', ATOMI_SERVER__PORT: '1' },
      env: { ATOMI_SERVER__PORT: '2' },
    });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_' });

    // Assert — build-time host stays, runtime port wins
    should(config.get('server').host).equal('build-host');
    should(config.get('server').port).equal(2);
  });

  it('should honour a custom baseFile and overlayFile', async () => {
    // Arrange
    const source = new YamlConfigSource({
      dir,
      baseFile: 'config.yaml',
      overlayFile: landscape => `${landscape}.config.yaml`,
      env: { ATOMI_SERVER__PORT: '80' },
    });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_', landscape: 'prod' });

    // Assert
    should(config.get('server').host).equal('prod-host');
  });

  it('should read an empty YAML overlay as an empty object', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: { ATOMI_SERVER__PORT: '80' } });

    // Act
    const overlay = await source.overlay('empty');

    // Assert
    should(overlay).deepEqual({});
  });

  it('should reject a YAML file that is not a mapping', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir });

    // Act
    const act = source.overlay('broken');

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(YamlConfigSourceError),
    );
  });

  it('should reject when the required base file is missing', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, baseFile: 'does-not-exist.yaml' });

    // Act
    const act = source.base();

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should((error as { code?: string }).code).equal('ENOENT'),
    );
  });

  it('should default build-time env to empty', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir });

    // Act
    const buildTime = await source.buildTimeEnv();

    // Assert
    should(buildTime).deepEqual({});
  });
});
