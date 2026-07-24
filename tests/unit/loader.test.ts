import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import { ConfigLoader, ConfigLoaderError, loadConfig } from '../../src/lib/loader.js';
import type { ConfigRecord } from '../../src/lib/merge.js';
import { ConfigRegistry } from '../../src/lib/registry.js';
import type { ConfigSource, EnvRecord } from '../../src/lib/source.js';
import { ConfigValidationError } from '../../src/lib/validator.js';

interface FakeTiers {
  base?: ConfigRecord;
  overlays?: Record<string, ConfigRecord>;
  buildTimeEnv?: EnvRecord;
  runtimeEnv?: EnvRecord;
  failBase?: Error;
}

class FakeSource implements ConfigSource {
  constructor(private readonly tiers: FakeTiers) {}
  async base(): Promise<ConfigRecord> {
    if (this.tiers.failBase) throw this.tiers.failBase;
    return this.tiers.base ?? {};
  }
  async overlay(landscape: string): Promise<ConfigRecord> {
    return this.tiers.overlays?.[landscape] ?? {};
  }
  async buildTimeEnv(): Promise<EnvRecord> {
    return this.tiers.buildTimeEnv ?? {};
  }
  async runtimeEnv(): Promise<EnvRecord> {
    return this.tiers.runtimeEnv ?? {};
  }
}

const serverRegistry = ConfigRegistry.create().register(
  'server',
  z.object({ a: z.string(), b: z.string(), c: z.string(), d: z.string() }),
);

describe('ConfigLoader — 4-tier merge precedence', () => {
  it('should apply base < overlay < build-time < runtime in order', async () => {
    // Arrange
    const source = new FakeSource({
      base: { server: { a: 'base', b: 'base', c: 'base', d: 'base' } },
      overlays: { prod: { server: { b: 'overlay', c: 'overlay', d: 'overlay' } } },
      buildTimeEnv: { ATOMI_SERVER__C: 'build', ATOMI_SERVER__D: 'build' },
      runtimeEnv: { ATOMI_SERVER__D: 'runtime' },
    });
    const loader = new ConfigLoader(source, serverRegistry, { prefix: 'ATOMI_', landscape: 'prod' });

    // Act
    const config = await loader.load();

    // Assert
    should(config.get('server')).deepEqual({ a: 'base', b: 'overlay', c: 'build', d: 'runtime' });
  });
});

describe('ConfigLoader — accessor', () => {
  it('should expose the value as a callable, via get, and via all', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const source = new FakeSource({ base: { server: { port: 8080 } } });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_' });

    // Assert
    should(config('server')).deepEqual({ port: 8080 });
    should(config.get('server')).deepEqual({ port: 8080 });
    should(config.all()).deepEqual({ server: { port: 8080 } });
  });
});

describe('ConfigLoader — validation', () => {
  it('should validate the FINAL merged layer only, not intermediate tiers', async () => {
    // Arrange — base is invalid (port missing); runtime env supplies it.
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const source = new FakeSource({
      base: { server: {} },
      runtimeEnv: { ATOMI_SERVER__PORT: '8080' },
    });

    // Act
    const config = await loadConfig(source, registry, { prefix: 'ATOMI_' });

    // Assert
    should(config.get('server')).deepEqual({ port: 8080 });
  });

  it('should throw ConfigValidationError when the final layer is invalid (fail-fast)', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const source = new FakeSource({ base: { server: { port: 'not-a-number' } } });

    // Act
    const act = loadConfig(source, registry, { prefix: 'ATOMI_' });

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should(error).be.instanceof(ConfigValidationError),
    );
  });
});

describe('ConfigLoader — loadResult (railway variant)', () => {
  it('should return Ok on a valid config', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const loader = new ConfigLoader(new FakeSource({ base: { server: { port: 1 } } }), registry, { prefix: 'ATOMI_' });

    // Act
    const result = await loader.loadResult();

    // Assert
    should(await result.isOk()).be.true();
  });

  it('should return Err on a validation failure', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const loader = new ConfigLoader(new FakeSource({ base: { server: { port: 'x' } } }), registry, {
      prefix: 'ATOMI_',
    });

    // Act
    const result = await loader.loadResult();

    // Assert
    should(await result.isErr()).be.true();
    const error = await result.unwrapErr();
    should(error).be.instanceof(ConfigValidationError);
  });

  it('should rethrow a non-validation (IO) error', async () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
    const loader = new ConfigLoader(new FakeSource({ failBase: new Error('disk gone') }), registry, {
      prefix: 'ATOMI_',
    });

    // Act
    const act = loader.loadResult();

    // Assert
    await act.then(
      () => should.fail('resolved', 'rejected', 'expected rejection'),
      error => should((error as Error).message).equal('disk gone'),
    );
  });
});

describe('ConfigLoader — construction', () => {
  it('should reject an empty prefix (no baked default)', () => {
    // Arrange
    const registry = ConfigRegistry.create();

    // Act
    const actual = () => new ConfigLoader(new FakeSource({}), registry, { prefix: '' });

    // Assert
    should(actual).throw(ConfigLoaderError);
  });
});
