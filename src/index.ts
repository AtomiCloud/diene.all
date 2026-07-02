// ─── DOMAIN WIRING · the illustrative sample (delete through END to replace the sample) ──────────
import type { IKeyValueStore, RedisConnection } from './adapters/kv-store';
import { RedisKeyValueStore } from './adapters/redis-kv-store';
import { namespacedKey } from './lib/slug';

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

async function main(): Promise<void> {
  const parsedPort = process.env.REDIS_PORT === undefined ? undefined : Number(process.env.REDIS_PORT);
  const connection =
    process.env.REDIS_HOST &&
    parsedPort !== undefined &&
    Number.isInteger(parsedPort) &&
    parsedPort > 0 &&
    parsedPort <= 65535
      ? {
          host: process.env.REDIS_HOST,
          port: parsedPort,
        }
      : undefined;

  if (connection) {
    const store = createRedisStore(connection);
    try {
      const value = await persistSample(store, 'Bun Base', 'sample key', 'sample value');
      console.log(`round-tripped value: ${value}`);
    } finally {
      await store.close();
    }
    return;
  }

  console.log(`composed key: ${buildSampleKey('Bun Base', 'sample key')}`);
}

if (import.meta.main) {
  await main();
}
// ─── END DOMAIN WIRING ────────────────────────────────────────────────────────────────────────────
