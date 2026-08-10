import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { TokenResponse } from '../../src/lib/provider';
import type { CanonicalResourceKey } from '../../src/lib/resource-tree';
import { InMemoryTokenCacheStore } from '../../src/test-helper';

const KEY: CanonicalResourceKey = 'alcohol/lapras/zinc/api';
const SECOND_KEY: CanonicalResourceKey = 'alcohol/lapras/tin/api';

function cacheToken(value: string): TokenResponse {
  return {
    token: value,
    expiresAt: Temporal.Instant.from('2026-07-24T12:10:00Z'),
  };
}

function cacheProblem(): Problem {
  return {
    type: 'about:blank',
    title: 'Cache store failure',
    status: 503,
    detail: 'The fake cache store was instructed to fail.',
    data: {},
  };
}

describe('InMemoryTokenCacheStore', () => {
  it('implements the complete TokenCacheStore lifecycle', async () => {
    // Arrange
    const subject = new InMemoryTokenCacheStore();
    const first = cacheToken('first');
    const second = cacheToken('second');

    // Act
    const initiallyMissing = await subject.get(KEY).serial();
    const firstSet = await subject.set(KEY, first).serial();
    const secondSet = await subject.set(SECOND_KEY, second).serial();
    const stored = await subject.get(KEY).serial();
    const inspected = subject.inspect(KEY);
    const deleted = await subject.delete(KEY).serial();
    const afterDelete = await subject.get(KEY).serial();
    const cleared = await subject.clear().serial();
    const afterClear = await subject.get(SECOND_KEY).serial();

    // Assert
    should(initiallyMissing).deepEqual(['ok', undefined]);
    should(firstSet[0]).equal('ok');
    should(secondSet[0]).equal('ok');
    should(stored).deepEqual(['ok', first]);
    should(inspected).equal(first);
    should(deleted[0]).equal('ok');
    should(afterDelete).deepEqual(['ok', undefined]);
    should(cleared[0]).equal('ok');
    should(afterClear).deepEqual(['ok', undefined]);
  });

  it('returns the configured failure from every fallible store operation', async () => {
    // Arrange
    const subject = new InMemoryTokenCacheStore();
    const problem = cacheProblem();
    subject.setFailure(problem);

    // Act
    const get = await subject.get(KEY).serial();
    const set = await subject.set(KEY, cacheToken('blocked')).serial();
    const deleted = await subject.delete(KEY).serial();
    const cleared = await subject.clear().serial();
    subject.setFailure();
    const recovered = await subject.set(KEY, cacheToken('recovered')).serial();

    // Assert
    should(get).deepEqual(['err', problem]);
    should(set).deepEqual(['err', problem]);
    should(deleted).deepEqual(['err', problem]);
    should(cleared).deepEqual(['err', problem]);
    should(recovered[0]).equal('ok');
  });
});
