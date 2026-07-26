import { afterAll, beforeAll, describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import { Redis } from 'ioredis';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { RedisDeferredStore } from '../../src/adapters/redis-deferred-store';
import type { DeferredNonceRecord } from '../../src/lib/deferred/store';
import { describeDeferredStoreContract } from '../contract/deferred-store-contract';
import { testAuthProblems } from '../support/auth-problems';

const problems = testAuthProblems();

let container: StartedTestContainer | undefined;
let client: Redis | undefined;

async function sleep(ms: number): Promise<void> {
  await new Promise<void>(resolve => {
    setTimeout(resolve, ms);
  });
}

beforeAll(async () => {
  container = await new GenericContainer('redis:7.4.5-alpine')
    .withExposedPorts(6379)
    .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
    .start();
  client = new Redis({ host: container.getHost(), port: container.getMappedPort(6379), maxRetriesPerRequest: 3 });
}, 120_000);

afterAll(async () => {
  try {
    await client?.quit();
  } finally {
    await container?.stop();
  }
}, 120_000);

// The Redis adapter must satisfy the same C0 §7 store contract as the reference.
// TTL is enforced by real server expiry, so this is the one path that must wait.
describeDeferredStoreContract('RedisDeferredStore (Testcontainers)', {
  makeStore: () => new RedisDeferredStore({ client: client as Redis, problems }),
  now: () => Temporal.Now.instant(),
  expire: async (ttl: Temporal.Duration) => {
    await sleep(ttl.total({ unit: 'milliseconds' }) + 400);
  },
});

describe('RedisDeferredStore concurrency', () => {
  function nonceFor(prefix: string): string {
    return `${prefix}-${Temporal.Now.instant().epochNanoseconds}`.padEnd(43, '0').slice(0, 43);
  }

  function futureRecord(): DeferredNonceRecord {
    return {
      sub: 'usr_race',
      email: 'race@example.com',
      expiresAt: Temporal.Now.instant().add({ minutes: 1 }),
      state: 'active',
    };
  }

  it('lets exactly one of two parallel claims win the race', async () => {
    // Arrange
    const subject = new RedisDeferredStore({ client: client as Redis, problems });
    const input = nonceFor('race');
    await subject.create(input, futureRecord()).serial();

    // Act
    const [first, second] = await Promise.all([subject.claim(input).serial(), subject.claim(input).serial()]);
    const actual = [first, second].filter(outcome => outcome[0] === 'ok').length;

    // Assert
    should(actual).equal(1);
  });

  it('constructs from a connection and round-trips (production wiring)', async () => {
    // Arrange
    const subject = new RedisDeferredStore({
      connection: {
        host: (container as StartedTestContainer).getHost(),
        port: (container as StartedTestContainer).getMappedPort(6379),
      },
      problems,
    });
    const input = nonceFor('conn');

    // Act
    const created = await subject.create(input, futureRecord()).isOk();
    const claimed = await subject.claim(input).isOk();
    await subject.close();

    // Assert
    should(created).be.true();
    should(claimed).be.true();
  });

  it('guards a double close (M32)', async () => {
    // Arrange
    const solo = new Redis({
      host: (container as StartedTestContainer).getHost(),
      port: (container as StartedTestContainer).getMappedPort(6379),
      maxRetriesPerRequest: 3,
    });
    const subject = new RedisDeferredStore({ client: solo, problems });

    // Act
    await subject.close();
    await subject.close(); // second call must be a safe no-op

    // Assert
    should(true).be.true();
  });

  it('rejects corrupt or non-strict stored records as the generic problem', async () => {
    // Arrange
    const subject = new RedisDeferredStore({ client: client as Redis, problems });
    const invalidInstantNonce = nonceFor('bad-instant');
    const unknownKeyNonce = nonceFor('unknown-key');
    const base = { sub: 'usr', email: 'user@example.com', state: 'active' };
    await (client as Redis).set(
      `diene:app-handoff:${invalidInstantNonce}`,
      JSON.stringify({ ...base, expiresAt: 'not-an-instant' }),
      'PX',
      60_000,
    );
    await (client as Redis).set(
      `diene:app-handoff:${unknownKeyNonce}`,
      JSON.stringify({ ...base, expiresAt: Temporal.Now.instant().add({ minutes: 1 }).toString(), extra: true }),
      'PX',
      60_000,
    );

    // Act
    const invalidInstant = await subject.claim(invalidInstantNonce).isErr();
    const unknownKey = await subject.claim(unknownKeyNonce).isErr();

    // Assert
    should(invalidInstant).be.true();
    should(unknownKey).be.true();
  });
});

describe('RedisDeferredStore input guards (M33)', () => {
  function countingClient(): { client: Redis; calls: { set: number; eval: number } } {
    const calls = { set: 0, eval: 0 };
    const client = {
      set: async () => {
        calls.set += 1;
        return 'OK';
      },
      eval: async () => {
        calls.eval += 1;
        return 1;
      },
      quit: async () => 'OK',
      disconnect: () => {},
    } as unknown as Redis;
    return { client, calls };
  }

  function liveRecord(): DeferredNonceRecord {
    return {
      sub: 'usr_guard',
      email: 'guard@example.com',
      expiresAt: Temporal.Now.instant().add({ minutes: 1 }),
      state: 'active',
    };
  }

  const NONCE = 'g'.repeat(43);

  it('create rejects a blank nonce with no Redis call', async () => {
    // Arrange
    const { client, calls } = countingClient();
    const subject = new RedisDeferredStore({ client, problems });

    // Act
    const actual = await subject.create('   ', liveRecord()).isErr();

    // Assert
    should(actual).be.true();
    should(calls.set).equal(0);
  });

  it('create rejects a blank sub or email with no Redis call', async () => {
    // Arrange
    const { client, calls } = countingClient();
    const subject = new RedisDeferredStore({ client, problems });

    // Act
    const blankSub = await subject.create(NONCE, { ...liveRecord(), sub: ' ' }).isErr();
    const blankEmail = await subject.create(NONCE, { ...liveRecord(), email: '' }).isErr();

    // Assert
    should(blankSub).be.true();
    should(blankEmail).be.true();
    should(calls.set).equal(0);
  });

  it('create rejects malformed or already-expired records with no Redis call', async () => {
    // Arrange
    const { client, calls } = countingClient();
    const subject = new RedisDeferredStore({ client, problems });
    const malformed = { ...liveRecord(), expiresAt: 'not-an-instant' } as unknown as DeferredNonceRecord;
    const expired = { ...liveRecord(), expiresAt: Temporal.Now.instant().subtract({ seconds: 1 }) };

    // Act
    const malformedResult = await subject.create(NONCE, malformed).isErr();
    const expiredResult = await subject.create(NONCE, expired).isErr();

    // Assert
    should(malformedResult).be.true();
    should(expiredResult).be.true();
    should(calls.set).equal(0);
  });

  it('claim/consume/revoke reject a blank nonce with no Redis call', async () => {
    // Arrange
    const { client, calls } = countingClient();
    const subject = new RedisDeferredStore({ client, problems });

    // Act
    const claim = await subject.claim('  ').isErr();
    const consume = await subject.consume('').isErr();
    const revoke = await subject.revoke('\t').isErr();

    // Assert
    should(claim).be.true();
    should(consume).be.true();
    should(revoke).be.true();
    should(calls.eval).equal(0);
  });

  it('rejects malformed nonces before any Redis call', async () => {
    // Arrange
    const { client, calls } = countingClient();
    const subject = new RedisDeferredStore({ client, problems });

    // Act
    const created = await subject.create('short', liveRecord()).isErr();
    const claimed = await subject.claim(`${'a'.repeat(42)}!`).isErr();

    // Assert
    should(created).be.true();
    should(claimed).be.true();
    should(calls.set).equal(0);
    should(calls.eval).equal(0);
  });
});
