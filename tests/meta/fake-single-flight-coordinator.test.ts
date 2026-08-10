import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { CacheEntry } from '../../src/lib/cache';
import { InMemorySingleFlightCoordinator } from '../../src/test-helper';

describe('InMemorySingleFlightCoordinator', () => {
  it('stores, retrieves, deletes, and clears independent cache slots', () => {
    // Arrange
    const subject = new InMemorySingleFlightCoordinator<string, string>();
    const first: CacheEntry<string> = {
      value: 'first',
      expiresAt: Temporal.Instant.from('2026-07-24T12:10:00Z'),
    };
    const second: CacheEntry<string> = {
      value: 'second',
      expiresAt: Temporal.Instant.from('2026-07-24T12:20:00Z'),
    };

    // Act
    subject.set('first-key', first);
    subject.set('second-key', second);
    const firstValue = subject.get('first-key');
    const missingValue = subject.get('missing-key');
    const deleted = subject.delete('first-key');
    const deletedAgain = subject.delete('first-key');
    const sizeBeforeClear = subject.size;
    subject.clear();

    // Assert
    should(firstValue).equal(first);
    should(missingValue).be.undefined();
    should(deleted).be.true();
    should(deletedAgain).be.false();
    should(sizeBeforeClear).equal(1);
    should(subject.size).equal(0);
    should(subject.values.size).equal(0);
  });
});
