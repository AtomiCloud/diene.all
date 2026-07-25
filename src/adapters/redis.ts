import { Err, Ok, Res, type Result } from '@atomicloud/diene.e2e/result';
import type { RedisConnectionEntry } from '@atomicloud/diene.e2e/standard-config';
import Redis from 'ioredis';
import { toRedisOptions } from '../lib/connection-options';
import { AdapterError } from './error';
import { type ApplicationTracer, withAdapterSpan } from './tracing';

export class RedisAdapter {
  constructor(
    readonly client: Redis,
    readonly tracer: ApplicationTracer,
    readonly name: string,
    readonly role: 'cache' | 'kv',
  ) {}

  connect(): Result<void, AdapterError> {
    return Res.async(async () => {
      try {
        await withAdapterSpan(
          this.tracer,
          'redis.connect',
          { 'atomi.adapter': 'redis', 'atomi.connection.name': this.name, 'atomi.redis.role': this.role },
          () => this.client.connect(),
        );
        return Ok(undefined);
      } catch (error) {
        return Err(new AdapterError('redis.connect', 'redis connection failed', error));
      }
    });
  }

  ping(): Result<void, AdapterError> {
    return Res.async(async () => {
      try {
        await withAdapterSpan(
          this.tracer,
          'redis.ping',
          { 'atomi.adapter': 'redis', 'atomi.connection.name': this.name, 'atomi.redis.role': this.role },
          () => this.client.ping(),
        );
        return Ok(undefined);
      } catch (error) {
        return Err(new AdapterError('redis.ping', 'redis ping failed', error));
      }
    });
  }

  setIfAbsent(key: string, value: string): Result<boolean, AdapterError> {
    return Res.async(async () => {
      try {
        const response = await withAdapterSpan(
          this.tracer,
          'redis.set',
          { 'atomi.adapter': 'redis', 'atomi.connection.name': this.name, 'atomi.redis.role': this.role },
          () => this.client.set(key, value, 'NX'),
        );
        return Ok(response === 'OK');
      } catch (error) {
        return Err(new AdapterError('redis.set', 'redis set failed', error));
      }
    });
  }

  get(key: string): Result<string | null, AdapterError> {
    return Res.async(async () => {
      try {
        const value = await withAdapterSpan(
          this.tracer,
          'redis.get',
          { 'atomi.adapter': 'redis', 'atomi.connection.name': this.name, 'atomi.redis.role': this.role },
          () => this.client.get(key),
        );
        return Ok(value);
      } catch (error) {
        return Err(new AdapterError('redis.get', 'redis get failed', error));
      }
    });
  }

  async close(): Promise<void> {
    await this.client.quit();
  }
}

export function buildRedisAdapters(
  block: Readonly<Record<string, RedisConnectionEntry>>,
  tracer: ApplicationTracer,
  role: 'cache' | 'kv',
): ReadonlyMap<string, RedisAdapter> {
  return new Map(
    Object.entries(block).map(([name, entry]) => {
      const client = new Redis(toRedisOptions(entry));
      return [name, new RedisAdapter(client, tracer, name, role)] as const;
    }),
  );
}
