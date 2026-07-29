import type Redis from 'ioredis';
import { z } from 'zod';
import type { ConsoleSessionRecord } from './model.ts';
import type { ConsoleClock, ConsoleSessionRepository } from './ports.ts';

const MAX_RECORD_BYTES = 32_768;
const DEFAULT_KEY_PREFIX = 'mercury:console:session';
const TOKEN_HASH_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const KEY_PREFIX_PATTERN = /^[A-Za-z0-9:_-]{1,96}$/;

const scopeValueSchema = z.union([z.literal('*'), z.array(z.string().min(1).max(256)).max(1_024)]);
const recordSchema = z
  .object({
    schema: z.literal(1),
    id: z.string().min(20).max(256),
    revision: z.number().int().nonnegative(),
    tokenHash: z.string().regex(TOKEN_HASH_PATTERN),
    identity: z
      .object({
        accountId: z.string().min(1).max(256),
        accountName: z.string().min(1).max(256),
        accountKind: z.enum(['default-internal', 'internal', 'external']),
      })
      .strict(),
    scope: z
      .object({
        tenants: scopeValueSchema,
        landscapes: scopeValueSchema,
        capabilities: z
          .array(
            z.enum(['operations:read', 'events:replay', 'endpoints:replay', 'endpoints:reenable', 'retention:run']),
          )
          .max(5),
      })
      .strict(),
    createdAt: z.iso.datetime(),
    lastSeenAt: z.iso.datetime(),
    idleExpiresAt: z.iso.datetime(),
    absoluteExpiresAt: z.iso.datetime(),
    rotateAt: z.iso.datetime(),
  })
  .strict();

const TOUCH_SCRIPT = `
local current = redis.call('GET', KEYS[1])
if not current or current ~= ARGV[1] then
  return 0
end
redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3])
return 1
`;

const ROTATE_SCRIPT = `
if redis.call('EXISTS', KEYS[1]) == 0 then
  return 0
end
if KEYS[1] == KEYS[2] or redis.call('EXISTS', KEYS[2]) == 1 then
  return 0
end
redis.call('SET', KEYS[2], ARGV[1], 'PX', ARGV[2])
redis.call('DEL', KEYS[1])
return 1
`;

const serializeRecord = (record: ConsoleSessionRecord): string =>
  JSON.stringify({
    schema: 1,
    id: record.id,
    revision: record.revision,
    tokenHash: record.tokenHash,
    identity: {
      accountId: record.identity.accountId,
      accountName: record.identity.accountName,
      accountKind: record.identity.accountKind,
    },
    scope: {
      tenants: record.scope.tenants,
      landscapes: record.scope.landscapes,
      capabilities: record.scope.capabilities,
    },
    createdAt: record.createdAt.toISOString(),
    lastSeenAt: record.lastSeenAt.toISOString(),
    idleExpiresAt: record.idleExpiresAt.toISOString(),
    absoluteExpiresAt: record.absoluteExpiresAt.toISOString(),
    rotateAt: record.rotateAt.toISOString(),
  });

const deserializeRecord = (serialized: string, expectedTokenHash: string): ConsoleSessionRecord | undefined => {
  if (new TextEncoder().encode(serialized).byteLength > MAX_RECORD_BYTES) return undefined;
  let json: unknown;
  try {
    json = JSON.parse(serialized);
  } catch {
    return undefined;
  }
  const parsed = recordSchema.safeParse(json);
  if (!parsed.success || parsed.data.tokenHash !== expectedTokenHash) return undefined;
  return {
    id: parsed.data.id,
    revision: parsed.data.revision,
    tokenHash: parsed.data.tokenHash,
    identity: { ...parsed.data.identity },
    scope: {
      tenants: parsed.data.scope.tenants,
      landscapes: parsed.data.scope.landscapes,
      capabilities: parsed.data.scope.capabilities,
    },
    createdAt: new Date(parsed.data.createdAt),
    lastSeenAt: new Date(parsed.data.lastSeenAt),
    idleExpiresAt: new Date(parsed.data.idleExpiresAt),
    absoluteExpiresAt: new Date(parsed.data.absoluteExpiresAt),
    rotateAt: new Date(parsed.data.rotateAt),
  };
};

const sessionKey = (keyPrefix: string, tokenHash: string): string => {
  if (!TOKEN_HASH_PATTERN.test(tokenHash)) {
    throw new Error('Console session token hash is invalid');
  }
  return `${keyPrefix}:${tokenHash}`;
};

const ttlMilliseconds = (clock: ConsoleClock, record: ConsoleSessionRecord): number | undefined => {
  const expiresAt = Math.min(record.idleExpiresAt.getTime(), record.absoluteExpiresAt.getTime());
  const ttl = expiresAt - clock.now().getTime();
  return Number.isSafeInteger(ttl) && ttl > 0 ? ttl : undefined;
};

export interface RedisConsoleSessionRepositoryOptions {
  readonly clock: ConsoleClock;
  readonly keyPrefix?: string;
}

export class RedisConsoleSessionRepository implements ConsoleSessionRepository {
  readonly #redis: Redis;
  readonly #clock: ConsoleClock;
  readonly #keyPrefix: string;

  constructor(redis: Redis, options: RedisConsoleSessionRepositoryOptions) {
    const keyPrefix = options.keyPrefix ?? DEFAULT_KEY_PREFIX;
    if (!KEY_PREFIX_PATTERN.test(keyPrefix)) {
      throw new Error('Console Redis session key prefix is invalid');
    }
    this.#redis = redis;
    this.#clock = options.clock;
    this.#keyPrefix = keyPrefix;
  }

  async find(tokenHash: string): Promise<ConsoleSessionRecord | undefined> {
    const key = sessionKey(this.#keyPrefix, tokenHash);
    const serialized = await this.#redis.get(key);
    if (serialized === null) return undefined;
    const record = deserializeRecord(serialized, tokenHash);
    if (record !== undefined) return record;
    await this.#redis.del(key);
    return undefined;
  }

  async create(record: ConsoleSessionRecord): Promise<boolean> {
    const ttl = ttlMilliseconds(this.#clock, record);
    if (ttl === undefined) return false;
    const result = await this.#redis.set(
      sessionKey(this.#keyPrefix, record.tokenHash),
      serializeRecord(record),
      'PX',
      ttl,
      'NX',
    );
    return result === 'OK';
  }

  async touch(current: ConsoleSessionRecord, replacement: ConsoleSessionRecord): Promise<boolean> {
    if (
      current.tokenHash !== replacement.tokenHash ||
      current.id !== replacement.id ||
      replacement.revision !== current.revision + 1
    ) {
      return false;
    }
    const ttl = ttlMilliseconds(this.#clock, replacement);
    if (ttl === undefined) return false;
    const result = await this.#redis.eval(
      TOUCH_SCRIPT,
      1,
      sessionKey(this.#keyPrefix, current.tokenHash),
      serializeRecord(current),
      serializeRecord(replacement),
      String(ttl),
    );
    return Number(result) === 1;
  }

  async rotate(currentTokenHash: string, replacement: ConsoleSessionRecord): Promise<boolean> {
    const ttl = ttlMilliseconds(this.#clock, replacement);
    if (ttl === undefined) return false;
    const result = await this.#redis.eval(
      ROTATE_SCRIPT,
      2,
      sessionKey(this.#keyPrefix, currentTokenHash),
      sessionKey(this.#keyPrefix, replacement.tokenHash),
      serializeRecord(replacement),
      String(ttl),
    );
    return Number(result) === 1;
  }

  async delete(tokenHash: string): Promise<void> {
    await this.#redis.del(sessionKey(this.#keyPrefix, tokenHash));
  }
}
