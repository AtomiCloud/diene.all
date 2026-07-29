import { describe, it } from 'bun:test';
import type Redis from 'ioredis';
import should from 'should';
import type { ConsoleSessionRecord } from '../../../src/console/model.ts';
import type { ConsoleClock } from '../../../src/console/ports.ts';
import { RedisConsoleLoginRateLimiter } from '../../../src/console/redis-login-rate-limiter.ts';
import { RedisConsoleSessionRepository } from '../../../src/console/redis-session-repository.ts';
import { WebCryptoConsoleRequestSecurity } from '../../../src/console/security.ts';

class MutableClock implements ConsoleClock {
  value = new Date('2026-07-29T01:00:00.000Z');

  now(): Date {
    return new Date(this.value);
  }
}

class MockRedis {
  readonly delCalls: string[][] = [];
  readonly evalCalls: unknown[][] = [];
  readonly getCalls: string[] = [];
  readonly setCalls: unknown[][] = [];
  readonly evalResults: unknown[] = [];
  readonly getResults: Array<string | null> = [];
  readonly setResults: Array<'OK' | null> = [];

  async eval(...arguments_: unknown[]): Promise<unknown> {
    this.evalCalls.push(arguments_);
    return this.evalResults.shift();
  }

  async get(key: string): Promise<string | null> {
    this.getCalls.push(key);
    return this.getResults.shift() ?? null;
  }

  async set(...arguments_: unknown[]): Promise<'OK' | null> {
    this.setCalls.push(arguments_);
    return this.setResults.shift() ?? 'OK';
  }

  async del(...keys: string[]): Promise<number> {
    this.delCalls.push(keys);
    return keys.length;
  }
}

const asRedis = (redis: MockRedis): Redis => redis as unknown as Redis;
const clock = new MutableClock();
const hash = (character: string): string => character.repeat(43);

const sessionRecord = (tokenHash = hash('a'), overrides: Partial<ConsoleSessionRecord> = {}): ConsoleSessionRecord => ({
  id: 'logical-console-session-id-1',
  revision: 0,
  tokenHash,
  identity: {
    accountId: 'account-1',
    accountName: 'internal/default',
    accountKind: 'default-internal',
  },
  scope: {
    tenants: ['tenant-1'],
    landscapes: ['serving'],
    capabilities: ['operations:read', 'events:replay'],
  },
  createdAt: clock.now(),
  lastSeenAt: clock.now(),
  idleExpiresAt: new Date(clock.now().getTime() + 120_000),
  absoluteExpiresAt: new Date(clock.now().getTime() + 300_000),
  rotateAt: new Date(clock.now().getTime() + 60_000),
  ...overrides,
});

const serializeFixture = (record: ConsoleSessionRecord): string =>
  JSON.stringify({
    schema: 1,
    id: record.id,
    revision: record.revision,
    tokenHash: record.tokenHash,
    identity: record.identity,
    scope: record.scope,
    createdAt: record.createdAt.toISOString(),
    lastSeenAt: record.lastSeenAt.toISOString(),
    idleExpiresAt: record.idleExpiresAt.toISOString(),
    absoluteExpiresAt: record.absoluteExpiresAt.toISOString(),
    rotateAt: record.rotateAt.toISOString(),
  });

const expectRejection = async (operation: () => Promise<unknown>, message: string): Promise<void> => {
  let failure: unknown;
  try {
    await operation();
  } catch (error) {
    failure = error;
  }
  should(failure).be.instanceOf(Error);
  if (!(failure instanceof Error)) throw new Error('Expected operation to reject');
  should(failure.message).equal(message);
};

describe('RedisConsoleLoginRateLimiter', () => {
  it('rejects invalid prefix and rate-limit bounds', () => {
    // Arrange
    const redis = asRedis(new MockRedis());
    const invalidOptions = [
      { keyPrefix: 'contains spaces', maxAttempts: 1, globalMaxAttempts: 1, windowSeconds: 60 },
      { maxAttempts: 0, globalMaxAttempts: 1, windowSeconds: 60 },
      { maxAttempts: 2, globalMaxAttempts: 1, windowSeconds: 60 },
      { maxAttempts: 1, globalMaxAttempts: 1, windowSeconds: 0 },
      { maxAttempts: 1, globalMaxAttempts: 1, windowSeconds: 3_601 },
    ];

    // Act / Assert
    for (const options of invalidOptions) {
      should(() => new RedisConsoleLoginRateLimiter(redis, options)).throw(
        'Console login rate limiter configuration is invalid',
      );
    }
  });

  it('normalizes account digests, returns allowed and rounded retry results, and resets only that account', async () => {
    // Arrange
    const redis = new MockRedis();
    redis.evalResults.push([1, 1], [0, 1_501]);
    const limiter = new RedisConsoleLoginRateLimiter(asRedis(redis), {
      keyPrefix: 'test:console:login',
      maxAttempts: 2,
      globalMaxAttempts: 8,
      windowSeconds: 60,
    });

    // Act
    const allowed = await limiter.attempt('JOSÉ');
    const rejected = await limiter.attempt('jose\u0301');
    await limiter.reset('josé');

    // Assert
    should(allowed).deepEqual({ allowed: true });
    should(rejected).deepEqual({ allowed: false, retryAfterSeconds: 2 });
    const firstAccountKey = redis.evalCalls[0]?.[2];
    const secondAccountKey = redis.evalCalls[1]?.[2];
    should(firstAccountKey).equal(secondAccountKey);
    should(firstAccountKey).match(/^test:console:login:account:[A-Za-z0-9_-]{43}$/);
    should(String(firstAccountKey)).not.containEql('jos');
    should(redis.evalCalls[0]?.slice(3)).deepEqual(['test:console:login:global', '60000', '2', '8']);
    should(redis.delCalls).deepEqual([[firstAccountKey]]);
  });

  it('rejects malformed Redis script results', async () => {
    // Arrange
    const redis = new MockRedis();
    redis.evalResults.push({ allowed: true });
    const limiter = new RedisConsoleLoginRateLimiter(asRedis(redis), {
      maxAttempts: 1,
      globalMaxAttempts: 1,
      windowSeconds: 60,
    });

    // Act / Assert
    await expectRejection(
      () => limiter.attempt('internal/default'),
      'Console login rate limiter returned an invalid result',
    );
  });
});

describe('RedisConsoleSessionRepository', () => {
  it('validates prefixes and token hashes before issuing Redis calls', async () => {
    // Arrange
    const redis = new MockRedis();
    const repository = new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'test:console:session' });

    // Act / Assert
    should(() => new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'invalid prefix' })).throw(
      'Console Redis session key prefix is invalid',
    );
    await expectRejection(() => repository.find('short'), 'Console session token hash is invalid');
    await expectRejection(() => repository.create(sessionRecord('short')), 'Console session token hash is invalid');
    should(redis.getCalls).deepEqual([]);
    should(redis.setCalls).deepEqual([]);
  });

  it('creates only live sessions with an idle-bounded PX TTL and NX collision protection', async () => {
    // Arrange
    const redis = new MockRedis();
    redis.setResults.push('OK');
    const repository = new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'test:console:session' });
    const record = sessionRecord(hash('b'));
    const expired = sessionRecord(hash('c'), { idleExpiresAt: clock.now() });

    // Act
    const created = await repository.create(record);
    const expiredCreated = await repository.create(expired);

    // Assert
    should(created).equal(true);
    should(expiredCreated).equal(false);
    should(redis.setCalls).have.length(1);
    should(redis.setCalls[0]?.[0]).equal(`test:console:session:${record.tokenHash}`);
    should(redis.setCalls[0]?.[2]).equal('PX');
    should(redis.setCalls[0]?.[3]).equal(120_000);
    should(redis.setCalls[0]?.[4]).equal('NX');
    should(JSON.parse(String(redis.setCalls[0]?.[1]))).deepEqual(JSON.parse(serializeFixture(record)));
  });

  it('returns missing and valid records but deletes malformed, mismatched, and oversized records', async () => {
    // Arrange
    const redis = new MockRedis();
    const repository = new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'test:console:session' });
    const tokenHash = hash('d');
    const valid = sessionRecord(tokenHash);
    redis.getResults.push(
      null,
      serializeFixture(valid),
      '{not-json',
      serializeFixture(sessionRecord(hash('e'))),
      'x'.repeat(32_769),
    );

    // Act
    const missing = await repository.find(tokenHash);
    const found = await repository.find(tokenHash);
    const malformed = await repository.find(tokenHash);
    const mismatched = await repository.find(tokenHash);
    const oversized = await repository.find(tokenHash);

    // Assert
    should(missing).equal(undefined);
    should(found).deepEqual(valid);
    should(malformed).equal(undefined);
    should(mismatched).equal(undefined);
    should(oversized).equal(undefined);
    should(redis.delCalls).deepEqual([
      [`test:console:session:${tokenHash}`],
      [`test:console:session:${tokenHash}`],
      [`test:console:session:${tokenHash}`],
    ]);
  });

  it('requires a revision-preserving live replacement for touch and returns script outcomes', async () => {
    // Arrange
    const redis = new MockRedis();
    redis.evalResults.push(1, 0);
    const repository = new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'test:console:session' });
    const current = sessionRecord(hash('f'));
    const replacement = sessionRecord(current.tokenHash, {
      revision: 1,
      lastSeenAt: new Date(clock.now().getTime() + 10_000),
      idleExpiresAt: new Date(clock.now().getTime() + 180_000),
    });

    // Act
    const changed = await repository.touch(current, replacement);
    const missing = await repository.touch(current, replacement);
    const wrongRevision = await repository.touch(current, { ...replacement, revision: 3 });
    const expired = await repository.touch(current, { ...replacement, idleExpiresAt: clock.now() });

    // Assert
    should(changed).equal(true);
    should(missing).equal(false);
    should(wrongRevision).equal(false);
    should(expired).equal(false);
    should(redis.evalCalls).have.length(2);
    should(redis.evalCalls[0]?.[1]).equal(1);
    should(redis.evalCalls[0]?.[2]).equal(`test:console:session:${current.tokenHash}`);
    should(redis.evalCalls[0]?.[5]).equal('180000');
  });

  it('uses live replacement TTLs for atomic rotation and deletes records by validated hash', async () => {
    // Arrange
    const redis = new MockRedis();
    redis.evalResults.push(1, 0);
    const repository = new RedisConsoleSessionRepository(asRedis(redis), { clock, keyPrefix: 'test:console:session' });
    const currentTokenHash = hash('g');
    const replacement = sessionRecord(hash('h'), { idleExpiresAt: new Date(clock.now().getTime() + 90_000) });

    // Act
    const rotated = await repository.rotate(currentTokenHash, replacement);
    const refused = await repository.rotate(currentTokenHash, replacement);
    const expired = await repository.rotate(currentTokenHash, { ...replacement, idleExpiresAt: clock.now() });
    await repository.delete(replacement.tokenHash);

    // Assert
    should(rotated).equal(true);
    should(refused).equal(false);
    should(expired).equal(false);
    should(redis.evalCalls).have.length(2);
    should(redis.evalCalls[0]?.[1]).equal(2);
    should(redis.evalCalls[0]?.slice(2, 4)).deepEqual([
      `test:console:session:${currentTokenHash}`,
      `test:console:session:${replacement.tokenHash}`,
    ]);
    should(redis.evalCalls[0]?.[5]).equal('90000');
    should(redis.delCalls).deepEqual([[`test:console:session:${replacement.tokenHash}`]]);
  });
});

describe('WebCryptoConsoleRequestSecurity', () => {
  it('enforces token byte-length bounds and issues opaque base64url entropy', () => {
    // Arrange
    const security = new WebCryptoConsoleRequestSecurity();

    // Act / Assert
    for (const byteLength of [15, 129, Number.NaN, 16.5]) {
      should(() => security.issueToken(byteLength)).throw('Console request token length is invalid');
    }
    const tokens = Array.from({ length: 4 }, () => security.issueToken(32));
    should(tokens).matchEach(token => /^[A-Za-z0-9_-]+$/.test(token));
    should(new Set(tokens).size).equal(tokens.length);
    should(Buffer.from(tokens[0] ?? '', 'base64url')).have.length(32);
  });

  it('compares equal, unequal, and unequal-length request values', () => {
    // Arrange
    const security = new WebCryptoConsoleRequestSecurity();

    // Act / Assert
    should(security.equal('same-token', 'same-token')).equal(true);
    should(security.equal('same-token', 'same-value')).equal(false);
    should(security.equal('same-token', 'same-token-longer')).equal(false);
  });
});
