// ─── DOMAIN WIRING · the illustrative sample (delete through END to replace the sample) ──────────
import type { IKeyValueStore, RedisConnection } from './adapters/kv-store';
import { RedisKeyValueStore } from './adapters/redis-kv-store';
import { withCleanup } from './lib/cleanup';
import { createLogger, type ILogger } from './lib/logger';
import { parseRedisEnvironment } from './lib/redis-config';
import { namespacedKey } from './lib/slug';

export function buildSampleKey(namespace: string, key: string): string {
  return namespacedKey(namespace, key);
}

export function createRedisStore(connection: RedisConnection, logger: ILogger): IKeyValueStore {
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

async function main(): Promise<void> {
  const logger = createLogger();
  const parsed = parseRedisEnvironment(process.env);

  if (!parsed.ok) {
    logger.error({ issues: parsed.issues }, 'invalid redis configuration');
    process.exitCode = 1;
    return;
  }

  const { connection } = parsed;
  if (connection === undefined) {
    logger.info({ key: buildSampleKey('Bun Base', 'sample key') }, 'composed key');
    return;
  }

  const store = createRedisStore(connection, logger);
  const value = await withCleanup(
    () => persistSample(store, 'Bun Base', 'sample key', 'sample value'),
    () => store.close(),
    error => logger.warn({ reason: String(error) }, 'failed to close the redis connection'),
  );
  logger.info({ value }, 'round-tripped value');
}

if (import.meta.main) {
  await main();
}
// ─── END DOMAIN WIRING ────────────────────────────────────────────────────────────────────────────
