import type Redis from 'ioredis';
import type { ConsoleLoginRateLimiter } from './ports.ts';

const DEFAULT_PREFIX = 'mercury:console:login';
const PREFIX_PATTERN = /^[A-Za-z0-9:_-]{1,96}$/;

const ATTEMPT_SCRIPT = `
local function increment(key, window)
  local value = redis.call('INCR', key)
  if value == 1 then
    redis.call('PEXPIRE', key, window)
  end
  return value
end

local account = increment(KEYS[1], ARGV[1])
local global = increment(KEYS[2], ARGV[1])
local accountTtl = redis.call('PTTL', KEYS[1])
local globalTtl = redis.call('PTTL', KEYS[2])
if account > tonumber(ARGV[2]) or global > tonumber(ARGV[3]) then
  return {0, math.max(accountTtl, globalTtl)}
end
return {1, math.max(accountTtl, globalTtl)}
`;

const accountDigest = async (accountName: string): Promise<string> => {
  const encoded = new TextEncoder().encode(accountName.normalize('NFC').toLowerCase());
  const buffer = new ArrayBuffer(encoded.byteLength);
  new Uint8Array(buffer).set(encoded);
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  return Buffer.from(digest).toString('base64url');
};

export interface RedisConsoleLoginRateLimiterOptions {
  readonly keyPrefix?: string;
  readonly maxAttempts: number;
  readonly globalMaxAttempts: number;
  readonly windowSeconds: number;
}

export class RedisConsoleLoginRateLimiter implements ConsoleLoginRateLimiter {
  readonly #redis: Redis;
  readonly #keyPrefix: string;
  readonly #maxAttempts: number;
  readonly #globalMaxAttempts: number;
  readonly #windowMilliseconds: number;

  constructor(redis: Redis, options: RedisConsoleLoginRateLimiterOptions) {
    const keyPrefix = options.keyPrefix ?? DEFAULT_PREFIX;
    if (
      !PREFIX_PATTERN.test(keyPrefix) ||
      !Number.isSafeInteger(options.maxAttempts) ||
      !Number.isSafeInteger(options.globalMaxAttempts) ||
      !Number.isSafeInteger(options.windowSeconds) ||
      options.maxAttempts <= 0 ||
      options.globalMaxAttempts < options.maxAttempts ||
      options.windowSeconds <= 0 ||
      options.windowSeconds > 3_600
    ) {
      throw new Error('Console login rate limiter configuration is invalid');
    }
    this.#redis = redis;
    this.#keyPrefix = keyPrefix;
    this.#maxAttempts = options.maxAttempts;
    this.#globalMaxAttempts = options.globalMaxAttempts;
    this.#windowMilliseconds = options.windowSeconds * 1_000;
  }

  async attempt(
    accountName: string,
  ): Promise<{ readonly allowed: true } | { readonly allowed: false; readonly retryAfterSeconds: number }> {
    const digest = await accountDigest(accountName);
    const result = await this.#redis.eval(
      ATTEMPT_SCRIPT,
      2,
      `${this.#keyPrefix}:account:${digest}`,
      `${this.#keyPrefix}:global`,
      String(this.#windowMilliseconds),
      String(this.#maxAttempts),
      String(this.#globalMaxAttempts),
    );
    if (!Array.isArray(result) || result.length !== 2) {
      throw new Error('Console login rate limiter returned an invalid result');
    }
    const allowed = Number(result[0]) === 1;
    const retryAfterSeconds = Math.max(1, Math.ceil(Number(result[1]) / 1_000));
    return allowed ? { allowed: true } : { allowed: false, retryAfterSeconds };
  }

  async reset(accountName: string): Promise<void> {
    await this.#redis.del(`${this.#keyPrefix}:account:${await accountDigest(accountName)}`);
  }
}
