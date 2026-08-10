import { describe, expect, test } from 'bun:test';
import {
  contentStates,
  createFakeModuleRegistry,
  createInMemoryPersistence,
  createPinnedProviderHarness,
  landscapeFixtureMatrix,
  landscapeFixtures,
} from '../../src/test-helper';

describe('frontend-utils TestHelper', () => {
  test('builds the full landscape source fixture matrix', () => {
    expect(landscapeFixtureMatrix).toEqual([
      'lapras',
      'ditto',
      'rotom',
      'absol',
      'eevee',
      'plusle',
      'minun',
      'pichu',
      'pikachu',
      'raichu',
    ]);
    expect(landscapeFixtures.binding('lapras')).toEqual({ source: 'binding', value: 'lapras' });
    expect(landscapeFixtures.bakedConstant('pikachu')).toEqual({
      source: 'baked-constant',
      value: 'pikachu',
    });
    expect(landscapeFixtures.dartDefine('raichu')).toEqual({ source: 'dart-define', value: 'raichu' });
  });

  test('provides a complete in-memory persistence fake', () => {
    const persistence = createInMemoryPersistence({ theme: 'dark' });
    expect(persistence.length).toBe(1);
    expect(persistence.getItem('theme')).toBe('dark');
    expect(persistence.get('theme')).toBe('dark');
    expect(persistence.getItem('missing')).toBeNull();
    expect(persistence.key(0)).toBe('theme');
    expect(persistence.key(3)).toBeNull();

    persistence.setItem('draft', 'saved');
    persistence.set('theme', 'light');
    expect(persistence.snapshot()).toEqual({ theme: 'light', draft: 'saved' });
    persistence.remove('theme');
    expect(persistence.length).toBe(1);
    persistence.set('theme', 'dark');
    persistence.removeItem('theme');
    persistence.clear();
    expect(persistence.snapshot()).toEqual({});
  });

  test('pins provider values through a consumer-owned wrapper', () => {
    const pins = { landscape: landscapeFixtures.binding('lapras'), theme: 'night' };
    let observed: unknown;
    const harness = createPinnedProviderHarness(pins, (active, children) => {
      observed = { active, children };
      return children;
    });

    expect(harness.pins).toEqual(pins);
    expect(Object.isFrozen(harness.pins)).toBe(true);
    expect(harness.Wrapper({ children: 'content' })).toBe('content');
    expect(observed).toEqual({ active: pins, children: 'content' });
  });

  test('creates an isolated fake module registry', async () => {
    const registry = createFakeModuleRegistry();
    expect(registry.has('profile')).toBe(false);
    expect(await registry.register({ id: 'profile', create: (value: string) => value }, 'ready').unwrap()).toBe(
      'ready',
    );
  });

  test('builds every content state including a stack-carrying LocalError', () => {
    expect(contentStates.idle()).toEqual({ status: 'idle' });
    expect(contentStates.loading()).toEqual({ status: 'loading' });
    expect(contentStates.empty()).toEqual({ status: 'empty', reason: 'No content found' });
    expect(contentStates.empty('Nothing matched')).toEqual({ status: 'empty', reason: 'Nothing matched' });
    expect(contentStates.content({ id: 1 })).toEqual({ status: 'content', data: { id: 1 } });
    const state = contentStates.error(new Error('consumer failed'));
    expect(state.status).toBe('error');
    if (state.status === 'error') {
      expect(state.problem.detail).toBe('consumer failed');
      expect(state.problem.data).toHaveProperty('stack');
    }
  });
});
