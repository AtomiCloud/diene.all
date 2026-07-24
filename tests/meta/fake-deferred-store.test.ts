import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { Clock, DeferredNonceRecord } from '../../src/lib/deferred/store';
import { InMemoryDeferredStore } from '../../src/test-helper';
import { describeDeferredStoreContract } from '../contract/deferred-store-contract';
import { testAuthProblems } from '../support/auth-problems';

const START = Temporal.Instant.from('2026-07-24T12:00:00Z');
const MALFORMED_NONCE = 'm'.repeat(43);
const EXPIRED_NONCE = 'e'.repeat(43);
const INSPECTABLE_NONCE = 'i'.repeat(43);

class FakeClock implements Clock {
  instant: Temporal.Instant;

  constructor(instant: Temporal.Instant) {
    this.instant = instant;
  }

  now(): Temporal.Instant {
    return this.instant;
  }

  advance(duration: Temporal.Duration): void {
    this.instant = this.instant.add(duration);
  }
}

let clock = new FakeClock(START);

describeDeferredStoreContract('TestHelper InMemoryDeferredStore', {
  makeStore: () => {
    clock = new FakeClock(START);
    return new InMemoryDeferredStore({ clock });
  },
  now: () => clock.now(),
  expire: async (ttl: Temporal.Duration) => {
    clock.advance(ttl.add({ nanoseconds: 1 }));
  },
});

function liveRecord(overrides: Partial<DeferredNonceRecord> = {}): DeferredNonceRecord {
  return {
    sub: 'meta-user',
    email: 'meta@example.invalid',
    expiresAt: START.add({ minutes: 15 }),
    state: 'active',
    ...overrides,
  };
}

describe('TestHelper InMemoryDeferredStore validation and inspection', () => {
  it('rejects every blank or malformed public nonce before touching state', async () => {
    // Arrange
    const subject = new InMemoryDeferredStore({ clock: new FakeClock(START) });

    // Act
    const create = await subject.create(' ', liveRecord()).serial();
    const claim = await subject.claim('\t').serial();
    const consume = await subject.consume('\n').serial();
    const revoke = await subject.revoke('').serial();
    const short = await subject.create('a'.repeat(42), liveRecord()).serial();
    const badCharacter = await subject.claim(`${'a'.repeat(42)}!`).serial();

    // Assert
    should(create[0]).equal('err');
    should(claim[0]).equal('err');
    should(consume[0]).equal('err');
    should(revoke[0]).equal('err');
    should(short[0]).equal('err');
    should(badCharacter[0]).equal('err');
    should(subject.storeHits).equal(0);
  });

  it('rejects malformed or expired records and exposes stored records for assertions', async () => {
    // Arrange
    const fakeClock = new FakeClock(START);
    const subject = new InMemoryDeferredStore({ clock: fakeClock });
    const malformed = { ...liveRecord(), expiresAt: 'not-an-instant' } as unknown as DeferredNonceRecord;

    // Act
    const malformedResult = await subject.create(MALFORMED_NONCE, malformed).serial();
    const expiredResult = await subject
      .create(EXPIRED_NONCE, liveRecord({ expiresAt: START.subtract({ nanoseconds: 1 }) }))
      .serial();
    const created = await subject.create(INSPECTABLE_NONCE, liveRecord()).serial();
    const actual = subject.inspect(INSPECTABLE_NONCE);

    // Assert
    should(malformedResult[0]).equal('err');
    should(expiredResult[0]).equal('err');
    should(created[0]).equal('ok');
    should(actual?.sub).equal('meta-user');
    should(actual?.state).equal('active');
  });

  it('uses the injected registered no-oracle Problem', async () => {
    // Arrange
    const problems = testAuthProblems();
    const subject = new InMemoryDeferredStore({ clock: new FakeClock(START), problems });

    // Act
    const actual = await subject.claim('missing').serial();

    // Assert
    should(actual[0]).equal('err');
    if (actual[0] !== 'err') return;
    should(actual[1].type).equal(problems.AppHandoffExpired.type);
    should(actual[1].status).equal(410);
  });
});
