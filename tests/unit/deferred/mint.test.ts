import { describe, it } from 'bun:test';
import { Err } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import {
  DEFERRED_NONCE_BYTE_LENGTH,
  DEFERRED_NONCE_TTL,
  type DeferredSession,
  mintDeferredToken,
} from '../../../src/lib/deferred/mint';
import { FakeClock, genericExpiry, ScriptedStore, testAuthProblems } from './support';

const problems = testAuthProblems();
const NONCE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const START = Temporal.Instant.from('2026-07-24T12:00:00Z');
const zeroBytes = (length: number): Uint8Array => new Uint8Array(length);

describe('mintDeferredToken', () => {
  it('mints a 43-char base64url nonce with a 15-minute expiry and stores an active record', async () => {
    // Arrange
    const store = new ScriptedStore();
    const clock = new FakeClock(START);
    const input = { sub: 'usr_1', email: 'user@example.com' };
    const expected = START.add(DEFERRED_NONCE_TTL);

    // Act
    const actual = await mintDeferredToken(input, { store, problems, clock }).unwrap();

    // Assert
    should(actual.nonce).match(NONCE_PATTERN);
    should(actual.expiresAt.equals(expected)).be.true();
    should(store.calls.create).equal(1);
    should(store.lastCreate?.nonce).equal(actual.nonce);
    should(store.lastCreate?.record.sub).equal('usr_1');
    should(store.lastCreate?.record.email).equal('user@example.com');
    should(store.lastCreate?.record.state).equal('active');
    should(store.lastCreate?.record.expiresAt.equals(expected)).be.true();
  });

  it('derives the nonce deterministically from the injected random bytes', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { sub: 'usr_1', email: 'user@example.com' };
    const expected = 'A'.repeat(43);

    // Act
    const actual = await mintDeferredToken(input, {
      store,
      problems,
      clock: new FakeClock(START),
      randomBytes: zeroBytes,
    }).unwrap();

    // Assert
    should(actual.nonce).equal(expected);
  });

  it('rejects a blank sub before any store hit (M33)', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { sub: '   ', email: 'user@example.com' };

    // Act
    const result = mintDeferredToken(input, { store, problems });
    const actual = await result.unwrapErr();

    // Assert
    should(await result.isErr()).be.true();
    should(actual.status).equal(401);
    should(store.calls.create).equal(0);
  });

  it('rejects a blank email before any store hit (M33)', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { sub: 'usr_1', email: '' };

    // Act
    const actual = await mintDeferredToken(input, { store, problems }).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.create).equal(0);
  });

  it('does not throw on a malformed session runtime value and hits no store', async () => {
    // Arrange
    const store = new ScriptedStore();
    const input = { sub: 123, email: null } as unknown as DeferredSession;

    // Act
    const actual = await mintDeferredToken(input, { store, problems }).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.create).equal(0);
  });

  it('propagates a store create failure', async () => {
    // Arrange
    const store = new ScriptedStore({ create: Err(genericExpiry()) });
    const input = { sub: 'usr_1', email: 'user@example.com' };

    // Act
    const actual = await mintDeferredToken(input, { store, problems }).isErr();

    // Assert
    should(actual).be.true();
    should(store.calls.create).equal(1);
  });

  it('maps malformed or throwing nonce generators to typed failures before storage', async () => {
    // Arrange
    const generators: Array<(length: number) => Uint8Array> = [
      () => new Uint8Array(DEFERRED_NONCE_BYTE_LENGTH - 1),
      () => {
        throw new Error('entropy unavailable');
      },
    ];

    // Act
    const outcomes = await Promise.all(
      generators.map(async randomBytes => {
        const store = new ScriptedStore();
        const result = await mintDeferredToken(
          { sub: 'usr_1', email: 'user@example.com' },
          { store, problems, clock: new FakeClock(START), randomBytes },
        ).serial();
        return { result, createCalls: store.calls.create };
      }),
    );

    // Assert
    should(outcomes.map(outcome => outcome.result[0])).deepEqual(['err', 'err']);
    should(outcomes.map(outcome => outcome.createCalls)).deepEqual([0, 0]);
    should(outcomes.map(outcome => (outcome.result[0] === 'err' ? outcome.result[1].status : 0))).deepEqual([502, 502]);
  });
});
