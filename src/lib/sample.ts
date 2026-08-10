import type { IKeyValueStore } from '../adapters/kv-store';
import { RedisKeyValueStore } from '../adapters/redis-kv-store';
import { createLogger, type ILogger } from './logger';
import type { RedisConnection } from './redis-config';
import { namespacedKey } from './slug';

export function buildSampleKey(namespace: string, key: string): string {
  return namespacedKey(namespace, key);
}

export function createRedisStore(connection: RedisConnection, logger: ILogger = createLogger()): IKeyValueStore {
  return new RedisKeyValueStore(connection, logger);
}

export async function persistSample(
  store: IKeyValueStore,
  namespace: string,
  key: string,
  value: string,
): Promise<string | null> {
  const composed = buildSampleKey(namespace, key);
  await store.set(composed, value);
  return store.get(composed);
}
