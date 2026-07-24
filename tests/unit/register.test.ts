import { ConfigRegistry } from '@atomicloud/diene.config';
import { describe, expect, it } from 'bun:test';
import { cache, kv, postgres, storage } from '../../src/index';
import { PRESETS, registerStandardConfigs } from '../../src/register';

describe('PRESETS', () => {
  it('maps every frozen block key to its schema', () => {
    expect(PRESETS.postgres).toBe(postgres);
    expect(PRESETS.cache).toBe(cache);
    expect(PRESETS.kv).toBe(kv);
    expect(PRESETS.storage).toBe(storage);
  });
});

describe('registerStandardConfigs', () => {
  it('registers the chosen presets into a config registry', () => {
    const registry = registerStandardConfigs(ConfigRegistry.create(), {
      which: ['postgres', 'cache', 'kv', 'storage'] as const,
    });
    expect([...registry.keys].sort()).toEqual(['cache', 'kv', 'postgres', 'storage']);
  });

  it('registers only the requested subset', () => {
    const registry = registerStandardConfigs(ConfigRegistry.create(), {
      which: ['postgres'] as const,
    });
    expect([...registry.keys]).toEqual(['postgres']);
  });

  it('composes onto an existing registry without dropping prior blocks', () => {
    const base = ConfigRegistry.create().register('postgres', postgres);
    const registry = registerStandardConfigs(base, { which: ['cache'] as const });
    expect([...registry.keys].sort()).toEqual(['cache', 'postgres']);
  });

  it('throws when a preset key is already registered (register invariant)', () => {
    expect(() =>
      registerStandardConfigs(ConfigRegistry.create(), { which: ['postgres', 'postgres'] as const }),
    ).toThrow();
  });

  it('produces a root schema that validates a full composed config', () => {
    const registry = registerStandardConfigs(ConfigRegistry.create(), {
      which: ['postgres', 'cache'] as const,
    });
    const result = registry.rootSchema().safeParse({
      postgres: {
        MAIN: {
          host: 'db',
          port: 5432,
          database: 'app',
          username: 'app',
          password: '',
          ssl: false,
          pool: { min: 0, max: 10 },
        },
      },
      cache: { MAIN: { host: 'r', port: 6379, password: '', db: 0, tls: false } },
    });
    expect(result.success).toBe(true);
  });
});
