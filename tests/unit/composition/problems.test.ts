import { describe, expect, test } from 'bun:test';
import { IntakeProblemCatalog, defaultIntakePortal } from '../../../src/http/intake/problems.ts';

describe('Mercury problem catalog', () => {
  test('publishes stable transport error classes', () => {
    const problems = new IntakeProblemCatalog(defaultIntakePortal).registry;

    expect(problems.list().map(({ id }) => id)).toEqual([
      'compiled_address_stale',
      'persistence_unavailable',
      'quota_exhausted',
      'unknown_route',
      'verification_failed',
    ]);
    expect(problems.require('quota_exhausted').status).toBe(429);
    expect(problems.require('compiled_address_stale').status).toBe(421);
  });
});
