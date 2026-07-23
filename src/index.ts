// ─── DOMAIN WIRING · the sample export surface (delete through END to replace the sample) ────────
import type { IKeyValueStore, RedisConnection } from './adapters/kv-store';
import { RedisKeyValueStore } from './adapters/redis-kv-store';
import { namespacedKey } from './lib/slug';

export type { IKeyValueStore, RedisConnection } from './adapters/kv-store';

export function buildSampleKey(namespace: string, key: string): string {
  return namespacedKey(namespace, key);
}

export function createRedisStore(connection: RedisConnection): IKeyValueStore {
  return new RedisKeyValueStore(connection);
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
// ─── END DOMAIN WIRING ────────────────────────────────────────────────────────────────────────────
