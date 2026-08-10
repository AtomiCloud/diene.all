import { beforeEach, describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import type { DeferredNonceRecord, DeferredTokenStore } from '../../src/lib/deferred/store';

/**
 * Shared behavioural contract for {@link DeferredTokenStore} implementations
 * (C0 §7). One suite runs against the in-memory reference (unit tier, fake
 * clock) and the Redis adapter (integration tier, real TTL), and is reused
 * verbatim by the TestHelper meta tier — the single source of truth for store
 * semantics.
 *
 * The harness owns time: `now()` reports the clock the store observes and
 * `expire(ttl)` makes that clock pass a TTL (fake-clock advance for the
 * in-memory path; a real wait only where the backing store cannot be faked).
 */
export interface DeferredStoreContractHarness {
  makeStore(): DeferredTokenStore | Promise<DeferredTokenStore>;
  now(): Temporal.Instant;
  expire(ttl: Temporal.Duration): Promise<void>;
  teardown?(store: DeferredTokenStore): Promise<void> | void;
}

let counter = 0;

function uniqueNonce(): string {
  counter += 1;
  // Canonical 32-byte base64url carrier shape used by every implementation.
  return `contract-nonce-${counter}-${counter.toString(36)}`.padEnd(43, '0');
}

function recordExpiringAt(expiresAt: Temporal.Instant): DeferredNonceRecord {
  return {
    sub: 'usr_contract_subject',
    email: 'Contract.User@Example.com',
    expiresAt,
    state: 'active',
  };
}

export function describeDeferredStoreContract(label: string, harness: DeferredStoreContractHarness): void {
  describe(`DeferredTokenStore contract: ${label}`, () => {
    let subject: DeferredTokenStore;

    beforeEach(async () => {
      subject = await harness.makeStore();
    });

    async function done(): Promise<void> {
      await harness.teardown?.(subject);
    }

    const longTtl = Temporal.Duration.from({ minutes: 15 });

    it('creates then claims an active nonce, returning the stored identity', async () => {
      // Arrange
      const input = uniqueNonce();
      const record = recordExpiringAt(harness.now().add(longTtl));

      // Act
      const created = await subject.create(input, record).isOk();
      const claim = subject.claim(input);
      const actual = await claim.unwrap();

      // Assert
      should(created).be.true();
      should(actual.sub).equal(record.sub);
      should(actual.email).equal(record.email);
      await done();
    });

    it('rejects a duplicate create for a live nonce', async () => {
      // Arrange
      const input = uniqueNonce();
      await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).serial();

      // Act
      const actual = await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).isErr();

      // Assert
      should(actual).be.true();
      await done();
    });

    it('rejects an already-expired record at creation time', async () => {
      // Arrange
      const input = uniqueNonce();
      const record = recordExpiringAt(harness.now().subtract({ nanoseconds: 1 }));

      // Act
      const actual = await subject.create(input, record).isErr();

      // Assert
      should(actual).be.true();
      await done();
    });

    it('claims exclusively — a replayed claim fails', async () => {
      // Arrange
      const input = uniqueNonce();
      await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).serial();

      // Act
      const first = await subject.claim(input).isOk();
      const second = await subject.claim(input).isErr();

      // Assert
      should(first).be.true();
      should(second).be.true();
      await done();
    });

    it('fails to claim a nonce that was never created', async () => {
      // Arrange
      const input = uniqueNonce();

      // Act
      const actual = await subject.claim(input).isErr();

      // Assert
      should(actual).be.true();
      await done();
    });

    it('expires a nonce after its TTL elapses', async () => {
      // Arrange
      const input = uniqueNonce();
      const ttl = Temporal.Duration.from({ milliseconds: 300 });
      await subject.create(input, recordExpiringAt(harness.now().add(ttl))).serial();

      // Act
      await harness.expire(ttl);
      const actual = await subject.claim(input).isErr();

      // Assert
      should(actual).be.true();
      await done();
    });

    it('allows the same opaque nonce to be created again after its prior TTL expires', async () => {
      // Arrange
      const input = uniqueNonce();
      const ttl = Temporal.Duration.from({ milliseconds: 300 });
      await subject.create(input, recordExpiringAt(harness.now().add(ttl))).serial();
      await harness.expire(ttl);

      // Act
      const recreated = await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).isOk();
      const claimed = await subject.claim(input).isOk();

      // Assert
      should(recreated).be.true();
      should(claimed).be.true();
      await done();
    });

    it('rejects consume and revoke after the underlying records expire', async () => {
      // Arrange
      const consumeNonce = uniqueNonce();
      const revokeNonce = uniqueNonce();
      const ttl = Temporal.Duration.from({ milliseconds: 300 });
      const expiresAt = harness.now().add(ttl);
      await subject.create(consumeNonce, recordExpiringAt(expiresAt)).serial();
      await subject.claim(consumeNonce).serial();
      await subject.create(revokeNonce, recordExpiringAt(expiresAt)).serial();
      await harness.expire(ttl);

      // Act
      const consumed = await subject.consume(consumeNonce).isErr();
      const revoked = await subject.revoke(revokeNonce).isErr();

      // Assert
      should(consumed).be.true();
      should(revoked).be.true();
      await done();
    });

    it('consumes a claimed nonce and blocks any later claim', async () => {
      // Arrange
      const input = uniqueNonce();
      await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).serial();
      await subject.claim(input).serial();

      // Act
      const consumed = await subject.consume(input).isOk();
      const reclaim = await subject.claim(input).isErr();

      // Assert
      should(consumed).be.true();
      should(reclaim).be.true();
      await done();
    });

    it('cannot consume a nonce that was never claimed', async () => {
      // Arrange
      const input = uniqueNonce();
      await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).serial();

      // Act
      const actual = await subject.consume(input).isErr();

      // Assert
      should(actual).be.true();
      await done();
    });

    it('revokes a live nonce and blocks any later claim', async () => {
      // Arrange
      const input = uniqueNonce();
      await subject.create(input, recordExpiringAt(harness.now().add(longTtl))).serial();

      // Act
      const revoked = await subject.revoke(input).isOk();
      const reclaim = await subject.claim(input).isErr();

      // Assert
      should(revoked).be.true();
      should(reclaim).be.true();
      await done();
    });
  });
}
