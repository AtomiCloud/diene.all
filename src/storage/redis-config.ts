import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type Redis from 'ioredis';
import type { LandscapeRuntimeConfig, RuntimeConfigStore, StorageFailure } from '../domain/index.ts';
import { decodeRuntimeConfig, encodeRuntimeConfig } from './codec.ts';

const redisFailure = (operation: string, error: unknown): StorageFailure => ({
  code: 'unavailable',
  operation,
  message: error instanceof Error ? error.message : String(error),
});

const generationKey = (generation: number): string => `cfg:${generation}:landscape`;
const generationIndexKey = (generation: number): string => `cfg:${generation}:keys`;
const RETAINED_GENERATIONS_KEY = 'cfg:retained';
const tenantPart = (tenantId: string): string => encodeURIComponent(tenantId);

const activateScript = `
local current = redis.call('GET', KEYS[1])
local expected = ARGV[1]
if expected == '' then
  if current then return 0 end
elseif current ~= expected then
  return 0
end
if redis.call('EXISTS', KEYS[2]) ~= 1 then return -1 end
redis.call('SET', KEYS[1], ARGV[2])
redis.call('ZREM', KEYS[3], ARGV[2])
if expected ~= '' and ARGV[3] ~= '' then
  redis.call('ZADD', KEYS[3], ARGV[3], expected)
end
return 1
`;

const reserveGenerationScript = `
local reserved = tonumber(redis.call('GET', KEYS[1])) or 0
local active = tonumber(redis.call('GET', KEYS[2])) or 0
if active > reserved then reserved = active end
reserved = reserved + 1
redis.call('SET', KEYS[1], tostring(reserved))
return reserved
`;

const discardScript = `
local generation = ARGV[1]
if redis.call('GET', KEYS[1]) == generation then return 0 end
local indexed = redis.call('SMEMBERS', KEYS[2])
for _, key in ipairs(indexed) do
  redis.call('DEL', key)
end
redis.call('DEL', KEYS[2], KEYS[3])
redis.call('ZREM', KEYS[4], generation)
return 1
`;

const retainGenerationScript = `
local generation = ARGV[1]
if redis.call('GET', KEYS[1]) == generation then return 0 end
if redis.call('EXISTS', KEYS[2]) ~= 1 then return -1 end
redis.call('ZADD', KEYS[3], ARGV[2], generation)
return 1
`;

/** Redis/Upstash generation store. Only Mercury's compiler is given this writer. */
export class RedisRuntimeConfigStore implements RuntimeConfigStore {
  constructor(readonly redis: Redis) {}

  async readActive(): Promise<Result<LandscapeRuntimeConfig | null, StorageFailure>> {
    try {
      const generation = await this.redis.get('cfg:gen');
      if (generation === null) {
        return Ok(null);
      }
      const value = await this.redis.get(generationKey(Number(generation)));
      if (value === null) {
        return Err({
          code: 'invalid-data',
          operation: 'read-config',
          message: `active config generation ${generation} is incomplete`,
        });
      }
      return Ok(decodeRuntimeConfig(value));
    } catch (error) {
      return Err(redisFailure('read-config', error));
    }
  }

  async reserveGeneration(): Promise<Result<number, StorageFailure>> {
    try {
      return Ok(Number(await this.redis.eval(reserveGenerationScript, 2, 'cfg:next-gen', 'cfg:gen')));
    } catch (error) {
      return Err(redisFailure('reserve-generation', error));
    }
  }

  async stage(config: LandscapeRuntimeConfig): Promise<Result<void, StorageFailure>> {
    try {
      const fullKey = generationKey(config.generation);
      const indexKey = generationIndexKey(config.generation);
      const transaction = this.redis
        .multi()
        .set(fullKey, encodeRuntimeConfig(config))
        .del(indexKey)
        .sadd(indexKey, fullKey);

      for (const tenant of config.tenants) {
        const encodedTenant = tenantPart(tenant.id);
        const tenantKey = `cfg:${config.generation}:tenant:${encodedTenant}`;
        const routesKey = `cfg:${config.generation}:routes:${encodedTenant}`;
        transaction.set(tenantKey, JSON.stringify({ ...tenant, routes: undefined }));
        transaction.del(routesKey);
        for (const route of tenant.routes) {
          transaction.hset(routesKey, route.path, JSON.stringify(route));
        }
        transaction.sadd(indexKey, tenantKey, routesKey);
      }

      const outcome = await transaction.exec();
      if (outcome === null || outcome.some(([error]) => error !== null)) {
        return Err({
          code: 'unavailable',
          operation: 'stage-config',
          message: 'Redis transaction failed',
        });
      }
      return Ok(undefined);
    } catch (error) {
      return Err(redisFailure('stage-config', error));
    }
  }

  async activate(
    generation: number,
    expectedPreviousGeneration: number | null,
    retainPreviousUntilMs?: number,
  ): Promise<Result<void, StorageFailure>> {
    try {
      const outcome = Number(
        await this.redis.eval(
          activateScript,
          3,
          'cfg:gen',
          generationKey(generation),
          RETAINED_GENERATIONS_KEY,
          expectedPreviousGeneration === null ? '' : String(expectedPreviousGeneration),
          String(generation),
          retainPreviousUntilMs === undefined ? '' : String(retainPreviousUntilMs),
        ),
      );
      if (outcome === 0) {
        return Err({
          code: 'conflict',
          operation: 'activate-config',
          message: 'active generation changed concurrently',
        });
      }
      if (outcome === -1) {
        return Err({
          code: 'invalid-data',
          operation: 'activate-config',
          message: 'generation was not fully staged',
        });
      }
      return Ok(undefined);
    } catch (error) {
      return Err(redisFailure('activate-config', error));
    }
  }

  async discardExpired(nowMs: number): Promise<Result<readonly number[], StorageFailure>> {
    try {
      const generations = await this.redis.zrangebyscore(RETAINED_GENERATIONS_KEY, '-inf', nowMs);
      const discarded: number[] = [];
      for (const value of generations) {
        const generation = Number(value);
        const outcome = Number(
          await this.redis.eval(
            discardScript,
            4,
            'cfg:gen',
            generationIndexKey(generation),
            generationKey(generation),
            RETAINED_GENERATIONS_KEY,
            value,
          ),
        );
        if (outcome === 1) {
          discarded.push(generation);
        }
      }
      return Ok(discarded);
    } catch (error) {
      return Err(redisFailure('discard-expired-config', error));
    }
  }

  async retainGeneration(generation: number, untilMs: number): Promise<Result<void, StorageFailure>> {
    if (!Number.isSafeInteger(untilMs) || untilMs < 0) {
      return Err({
        code: 'invalid-data',
        operation: 'retain-config',
        message: 'generation retention deadline is invalid',
      });
    }
    try {
      const outcome = Number(
        await this.redis.eval(
          retainGenerationScript,
          3,
          'cfg:gen',
          generationKey(generation),
          RETAINED_GENERATIONS_KEY,
          String(generation),
          String(untilMs),
        ),
      );
      if (outcome === 0) {
        return Err({
          code: 'conflict',
          operation: 'retain-config',
          message: 'active generation cannot be scheduled for retention cleanup',
        });
      }
      if (outcome === -1) {
        return Err({
          code: 'invalid-data',
          operation: 'retain-config',
          message: 'generation is not staged',
        });
      }
      return Ok(undefined);
    } catch (error) {
      return Err(redisFailure('retain-config', error));
    }
  }

  async discard(generation: number): Promise<Result<void, StorageFailure>> {
    try {
      const outcome = Number(
        await this.redis.eval(
          discardScript,
          4,
          'cfg:gen',
          generationIndexKey(generation),
          generationKey(generation),
          RETAINED_GENERATIONS_KEY,
          String(generation),
        ),
      );
      if (outcome === 0) {
        return Err({
          code: 'conflict',
          operation: 'discard-config',
          message: 'active generation cannot be discarded',
        });
      }
      return Ok(undefined);
    } catch (error) {
      return Err(redisFailure('discard-config', error));
    }
  }
}
