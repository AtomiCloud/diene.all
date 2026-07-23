// ─── DOMAIN WIRING · the sample export surface (delete through END to replace the sample) ────────
export type { IKeyValueStore, RedisConnection } from './adapters/kv-store';
export { buildSampleKey, createRedisStore, persistSample } from './lib/sample';
// ─── END DOMAIN WIRING ────────────────────────────────────────────────────────────────────────────
