import { afterAll, beforeAll, beforeEach, describe, it } from 'bun:test';
import Redis from 'ioredis';
import should from 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import type { ConsoleSessionRecord } from '../../../src/console/model.ts';
import type { ConsoleClock } from '../../../src/console/ports.ts';
import { RedisConsoleLoginRateLimiter } from '../../../src/console/redis-login-rate-limiter.ts';
import { RedisConsoleSessionRepository } from '../../../src/console/redis-session-repository.ts';

class MutableClock implements ConsoleClock {
  value = new Date('2026-07-29T01:00:00.000Z');

  now(): Date {
    return new Date(this.value);
  }
}

const clock = new MutableClock();
const hash = (character: string): string => character.repeat(43);

const sessionRecord = (
  tokenHash: string,
  revision = 0,
  idleSeconds = 120,
  absoluteSeconds = 300,
): ConsoleSessionRecord => ({
  id: 'logical-console-session-id-1',
  revision,
  tokenHash,
  identity: {
    accountId: 'account-1',
    accountName: 'internal/default',
    accountKind: 'default-internal',
  },
  scope: {
    tenants: ['tenant-1'],
    landscapes: ['serving'],
    capabilities: ['operations:read', 'events:replay', 'retention:run'],
  },
  createdAt: clock.now(),
  lastSeenAt: clock.now(),
  idleExpiresAt: new Date(clock.now().getTime() + idleSeconds * 1_000),
  absoluteExpiresAt: new Date(clock.now().getTime() + absoluteSeconds * 1_000),
  rotateAt: new Date(clock.now().getTime() + 60_000),
});

describe('Redis console production adapters', () => {
  let container: StartedTestContainer;
  let redis: Redis;

  beforeAll(async () => {
    container = await new GenericContainer('redis:7.4.2-alpine')
      .withExposedPorts(6379)
      .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
      .start();
    redis = new Redis({
      host: container.getHost(),
      port: container.getMappedPort(6379),
      maxRetriesPerRequest: 1,
    });
  });

  beforeEach(async () => {
    clock.value = new Date('2026-07-29T01:00:00.000Z');
    await redis.flushdb();
  });

  afterAll(async () => {
    redis?.disconnect();
    await container?.stop();
  });

  it('creates collision-safely with TTL bounded by idle expiry', async () => {
    // Arrange
    const repository = new RedisConsoleSessionRepository(redis, {
      clock,
      keyPrefix: 'test:console:session',
    });
    const record = sessionRecord(hash('a'));

    // Act
    const outcomes = await Promise.all(Array.from({ length: 12 }, () => repository.create(record)));
    const ttl = await redis.pttl(`test:console:session:${record.tokenHash}`);

    // Assert
    should(outcomes.filter(Boolean)).have.length(1);
    should(outcomes.filter(value => !value)).have.length(11);
    should(ttl).be.within(119_000, 120_000);
    should(await repository.find(record.tokenHash)).deepEqual(record);
  });

  it('compare-and-updates touch so only one concurrent revision wins', async () => {
    // Arrange
    const repository = new RedisConsoleSessionRepository(redis, {
      clock,
      keyPrefix: 'test:console:session',
    });
    const current = sessionRecord(hash('b'));
    await repository.create(current);
    const replacement: ConsoleSessionRecord = {
      ...current,
      revision: 1,
      lastSeenAt: new Date(clock.now().getTime() + 10_000),
      idleExpiresAt: new Date(clock.now().getTime() + 180_000),
    };

    // Act
    const outcomes = await Promise.all([
      repository.touch(current, replacement),
      repository.touch(current, replacement),
    ]);

    // Assert
    should(outcomes.filter(Boolean)).have.length(1);
    should((await repository.find(current.tokenHash))?.revision).equal(1);
    should(await redis.pttl(`test:console:session:${current.tokenHash}`)).be.within(179_000, 180_000);
  });

  it('rotates atomically to exactly one collision-free replacement and revokes it', async () => {
    // Arrange
    const repository = new RedisConsoleSessionRepository(redis, {
      clock,
      keyPrefix: 'test:console:session',
    });
    const current = sessionRecord(hash('c'));
    await repository.create(current);
    const replacements = [sessionRecord(hash('d'), 0, 90), sessionRecord(hash('e'), 0, 90)];

    // Act
    const outcomes = await Promise.all(
      replacements.map(replacement => repository.rotate(current.tokenHash, replacement)),
    );
    const live = await Promise.all(replacements.map(replacement => repository.find(replacement.tokenHash)));
    const winner = live.find(record => record !== undefined);

    // Assert
    should(outcomes.filter(Boolean)).have.length(1);
    should(await repository.find(current.tokenHash)).equal(undefined);
    should(live.filter(record => record !== undefined)).have.length(1);
    should(winner).not.equal(undefined);
    if (winner === undefined) throw new Error('Expected rotated session');
    should(await redis.pttl(`test:console:session:${winner.tokenHash}`)).be.within(89_000, 90_000);

    // Act / Assert revoke
    await repository.delete(winner.tokenHash);
    should(await repository.find(winner.tokenHash)).equal(undefined);
    should(await redis.exists(`test:console:session:${winner.tokenHash}`)).equal(0);
  });

  it('fails closed and deletes a corrupt stored session record', async () => {
    // Arrange
    const repository = new RedisConsoleSessionRepository(redis, {
      clock,
      keyPrefix: 'test:console:session',
    });
    const tokenHash = hash('f');
    const key = `test:console:session:${tokenHash}`;
    await redis.set(key, '{"schema":1,"secret":"native-bearer"}', 'PX', 60_000);

    // Act
    const found = await repository.find(tokenHash);

    // Assert
    should(found).equal(undefined);
    should(await redis.exists(key)).equal(0);
  });

  it('rate-limits atomically with hashed account keys and resets only the successful account bucket', async () => {
    // Arrange
    const limiter = new RedisConsoleLoginRateLimiter(redis, {
      keyPrefix: 'test:console:login',
      maxAttempts: 2,
      globalMaxAttempts: 10,
      windowSeconds: 60,
    });

    // Act
    const first = await limiter.attempt('internal/default');
    const second = await limiter.attempt('internal/default');
    const rejected = await limiter.attempt('internal/default');
    const keysBeforeReset = await redis.keys('test:console:login:*');
    await limiter.reset('internal/default');
    const afterReset = await limiter.attempt('internal/default');

    // Assert
    should(first.allowed).equal(true);
    should(second.allowed).equal(true);
    should(rejected.allowed).equal(false);
    if (rejected.allowed) throw new Error('Expected rate limit');
    should(rejected.retryAfterSeconds).be.within(1, 60);
    should(keysBeforeReset.some(key => key.includes('internal/default'))).equal(false);
    should(afterReset.allowed).equal(true);
    should(await redis.exists('test:console:login:global')).equal(1);
  });
});
