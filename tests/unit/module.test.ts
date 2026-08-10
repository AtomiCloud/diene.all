import { describe, expect, test } from 'bun:test';
import { createModuleRegistry, defineModule } from '../../src/lib/module';

describe('module contract and registry', () => {
  test('defines and freezes a valid module', () => {
    const definition = defineModule({ id: 'profile.card', create: (value: number) => value * 2 });
    expect(Object.isFrozen(definition)).toBe(true);
    expect(definition.id).toBe('profile.card');
  });

  test('rejects invalid module definitions', () => {
    expect(() => defineModule({ id: 'Bad module', create: () => true })).toThrow('invalid module id');
  });

  test('registers and resolves without exposing a container', async () => {
    const registry = createModuleRegistry();
    const definition = defineModule({ id: 'profile.card', create: (value: number) => value * 2 });

    expect(await registry.register(definition, 21).unwrap()).toBe(42);
    expect(registry.has('profile.card')).toBe(true);
    expect(await registry.resolve<number>('profile.card').unwrap()).toBe(42);
  });

  test('returns typed errors for invalid, duplicate, and missing modules', async () => {
    const registry = createModuleRegistry();
    const definition = { id: 'profile.card', create: () => 1 };

    await registry.register({ id: 'Bad module', create: () => 0 }, undefined).match({
      ok: () => {
        throw new Error('expected invalid id');
      },
      err: error => expect(error).toEqual({ kind: 'invalid-id', id: 'Bad module' }),
    });
    expect(await registry.register(definition, undefined).unwrap()).toBe(1);
    await registry.register(definition, undefined).match({
      ok: () => {
        throw new Error('expected duplicate id');
      },
      err: error => expect(error).toEqual({ kind: 'duplicate-id', id: 'profile.card' }),
    });
    expect(registry.has('missing')).toBe(false);
    await registry.resolve('missing').match({
      ok: () => {
        throw new Error('expected missing module');
      },
      err: error => expect(error).toEqual({ kind: 'missing-module', id: 'missing' }),
    });
  });
});
