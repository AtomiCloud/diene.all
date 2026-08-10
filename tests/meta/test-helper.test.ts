import { afterAll, beforeAll, describe, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import should from 'should';
import { z } from 'zod';
import { YamlConfigSource } from '../../src/adapters/yaml-source.js';
import { loadConfig } from '../../src/lib/loader.js';
import { ConfigRegistry } from '../../src/lib/registry.js';
import {
  expectInvalid,
  expectValid,
  InMemoryConfigSource,
  stubConfig,
  TestHelperError,
  withLandscape,
} from '../../src/test-helper/index.js';

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number(), host: z.string() }));

describe('InMemoryConfigSource', () => {
  it('should default every tier to empty', async () => {
    // Arrange
    const source = new InMemoryConfigSource();

    // Act / Assert
    should(await source.base()).deepEqual({});
    should(await source.overlay('prod')).deepEqual({});
    should(await source.buildTimeEnv()).deepEqual({});
    should(await source.runtimeEnv()).deepEqual({});
  });

  it('should serve the provided tiers', async () => {
    // Arrange
    const source = new InMemoryConfigSource({
      base: { a: 1 },
      overlays: { prod: { a: 2 } },
      buildTimeEnv: { ATOMI_A: '3' },
      runtimeEnv: { ATOMI_A: '4' },
    });

    // Act / Assert
    should(await source.base()).deepEqual({ a: 1 });
    should(await source.overlay('prod')).deepEqual({ a: 2 });
    should(await source.overlay('missing')).deepEqual({});
    should(await source.buildTimeEnv()).deepEqual({ ATOMI_A: '3' });
    should(await source.runtimeEnv()).deepEqual({ ATOMI_A: '4' });
  });
});

describe('stubConfig — builder invariant (always passes the registry)', () => {
  it('should build a validated config from in-memory tiers', async () => {
    // Arrange / Act
    const config = await stubConfig(registry, { base: { server: { port: 80, host: 'h' } } });

    // Assert
    should(config.get('server')).deepEqual({ port: 80, host: 'h' });
  });

  it('should honour a custom prefix and explicit landscape', async () => {
    // Arrange / Act
    const config = await stubConfig(
      registry,
      { base: { server: { port: 80, host: 'base' } }, overlays: { prod: { server: { host: 'prod' } } } },
      { prefix: 'X_', landscape: 'prod' },
    );

    // Assert
    should(config.get('server').host).equal('prod');
  });
});

describe('withLandscape — landscape fake', () => {
  it('should stamp app.landscape onto a base without an app block', async () => {
    // Arrange
    const source = withLandscape('prod');

    // Act
    const base = (await source.base()) as { app: { landscape: string } };

    // Assert
    should(base.app.landscape).equal('prod');
  });

  it('should merge into an existing app block', async () => {
    // Arrange
    const source = withLandscape('prod', { base: { app: { team: 'core' }, server: { port: 1 } } });

    // Act
    const base = (await source.base()) as { app: { landscape: string; team: string } };

    // Assert
    should(base.app).deepEqual({ team: 'core', landscape: 'prod' });
  });
});

describe('expectValid / expectInvalid — assert-the-asserter', () => {
  it('expectValid should return the config on a known-good input', async () => {
    // Arrange / Act
    const config = await expectValid(registry, { base: { server: { port: 80, host: 'h' } } });

    // Assert
    should(config.get('server').port).equal(80);
  });

  it('expectValid should throw TestHelperError on a known-bad (invalid) input', async () => {
    // Arrange / Act
    const act = expectValid(registry, { base: { server: { port: 'x', host: 'h' } } });

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(TestHelperError),
    );
  });

  it('expectValid should surface a non-validation error as a TestHelperError', async () => {
    // Arrange / Act — an unsafe landscape throws before validation
    const act = expectValid(registry, {}, { landscape: '../bad' });

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(TestHelperError),
    );
  });

  it('expectInvalid should return the ConfigValidationError on a known-bad input', async () => {
    // Arrange / Act
    const error = await expectInvalid(registry, { base: { server: { port: 'x', host: 'h' } } });

    // Assert
    should(error.issues.length).be.above(0);
  });

  it('expectInvalid should throw TestHelperError when the config is actually valid', async () => {
    // Arrange / Act
    const act = expectInvalid(registry, { base: { server: { port: 80, host: 'h' } } });

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(TestHelperError),
    );
  });

  it('expectInvalid should throw TestHelperError on a non-validation error', async () => {
    // Arrange / Act
    const act = expectInvalid(registry, {}, { landscape: '../bad' });

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(TestHelperError),
    );
  });
});

describe('contract parity — real loader vs fake source', () => {
  let dir: string;

  beforeAll(async () => {
    dir = await mkdtemp(join(tmpdir(), 'diene-config-meta-'));
    await writeFile(join(dir, 'config.yaml'), ['server:', '  port: 80', '  host: base'].join('\n'));
    await writeFile(join(dir, 'prod.config.yaml'), ['server:', '  host: prod'].join('\n'));
  });

  afterAll(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('should produce identical config from YAML files and in-memory fakes', async () => {
    // Arrange
    const env = { ATOMI_SERVER__PORT: '8080' };
    const real = new YamlConfigSource({ dir, env });
    const fake = new InMemoryConfigSource({
      base: { server: { port: 80, host: 'base' } },
      overlays: { prod: { server: { host: 'prod' } } },
      runtimeEnv: env,
    });

    // Act
    const fromReal = await loadConfig(real, registry, { prefix: 'ATOMI_', landscape: 'prod' });
    const fromFake = await loadConfig(fake, registry, { prefix: 'ATOMI_', landscape: 'prod' });

    // Assert
    should(fromReal.all()).deepEqual(fromFake.all());
    should(fromFake.get('server')).deepEqual({ port: 8080, host: 'prod' });
  });
});
