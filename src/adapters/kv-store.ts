// `RedisConnection` is a domain value type owned by `src/lib/redis-config.ts`.
// It is re-exported here so existing adapter-side importers keep working while
// the domain keeps its dependency direction (domain never imports an adapter).
export type { RedisConnection } from '../lib/redis-config';

export interface IKeyValueStore {
  set(key: string, value: string): Promise<void>;
  get(key: string): Promise<string | null>;
  close(): Promise<void>;
}
