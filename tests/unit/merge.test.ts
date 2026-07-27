import { ConfigRegistry, generateJsonSchema, loadConfig } from '@atomicloud/diene.config';
import { InMemoryConfigSource } from '@atomicloud/diene.config/test-helper';
import { describe, expect, it } from 'bun:test';
import { named } from '../../src/lib/presets/keyed';
import { registerStandardConfigs } from '../../src/lib/register';

const registry = registerStandardConfigs(ConfigRegistry.create(), {
  which: ['postgres', 'cache'] as const,
});

interface Tiers {
  base?: Record<string, unknown>;
  overlays?: Record<string, Record<string, unknown>>;
  buildTimeEnv?: Record<string, string | undefined>;
  runtimeEnv?: Record<string, string | undefined>;
}

const load = (tiers: Tiers, landscape?: string) =>
  loadConfig(new InMemoryConfigSource(tiers), registry, { prefix: 'ATOMI_', landscape });

const baseConfig = {
  postgres: {
    MAIN: {
      host: 'localhost',
      port: 5432,
      database: 'app',
      username: 'app',
      password: '', // secret — blank-in-yaml (R14)
      ssl: false,
      pool: { min: 0, max: 10 },
    },
  },
  cache: {
    MAIN: { host: 'localhost', port: 6379, password: '', db: 0, tls: false },
  },
};

describe('4-tier merge through lib/bun/config', () => {
  it('applies a landscape overlay that flips a preset value', async () => {
    const config = await load(
      {
        base: baseConfig,
        overlays: { lapras: { postgres: { MAIN: { ssl: true, host: 'prod.db.internal' } } } },
      },
      'lapras',
    );
    const main = named(config('postgres'), 'MAIN');
    expect(main.ssl).toBe(true);
    expect(main.host).toBe('prod.db.internal');
    expect(main.port).toBe(5432); // untouched key survives the sparse overlay
  });

  it('injects a blank-in-yaml secret via the env tier (round trip)', async () => {
    const config = await load({ base: baseConfig, runtimeEnv: { ATOMI_POSTGRES__MAIN__PASSWORD: 's3cr3t' } });
    expect(named(config('postgres'), 'MAIN').password).toBe('s3cr3t');
  });

  it('leaves the blank secret blank when the env value is empty (M33)', async () => {
    const config = await load({ base: baseConfig, runtimeEnv: { ATOMI_POSTGRES__MAIN__PASSWORD: '' } });
    expect(named(config('postgres'), 'MAIN').password).toBe('');
  });

  it('adds a second keyed instance from YAML alone (no schema change)', async () => {
    const config = await load({
      base: {
        ...baseConfig,
        postgres: { ...baseConfig.postgres, REPLICA: { ...baseConfig.postgres.MAIN, host: 'replica.db' } },
      },
    });
    expect(Object.keys(config('postgres')).sort()).toEqual(['MAIN', 'REPLICA']);
    expect(named(config('postgres'), 'REPLICA').host).toBe('replica.db');
  });

  it('fails validation on a malformed preset value', async () => {
    let issues = '';
    try {
      await load({ base: { ...baseConfig, postgres: { MAIN: { ...baseConfig.postgres.MAIN, port: 'nope' } } } });
      throw new Error('expected validation to fail');
    } catch (error) {
      issues = (error as { issues?: string[] }).issues?.join('; ') ?? String(error);
    }
    expect(issues).toContain('port');
  });
});

describe('generated $schema', () => {
  it('emits a JSON schema whose properties include every registered preset', () => {
    const schema = generateJsonSchema(registry, { id: 'https://schemas.atomicloud.io/standard-config.json' });
    expect(schema.$id).toBe('https://schemas.atomicloud.io/standard-config.json');
    const properties = (schema as { properties?: Record<string, unknown> }).properties ?? {};
    expect(Object.keys(properties).sort()).toEqual(['cache', 'postgres']);
  });
});
