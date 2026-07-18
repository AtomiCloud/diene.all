import { Redis } from 'ioredis';
import type { IKeyValueStore, RedisConnection } from './kv-store';

export class RedisKeyValueStore implements IKeyValueStore {
  private readonly client: Redis;

  constructor(connection: RedisConnection) {
    this.client = new Redis({
      host: connection.host,
      port: connection.port,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    });
  }

  async set(key: string, value: string): Promise<void> {
    await this.client.set(key, value);
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async close(): Promise<void> {
    await this.client.quit();
  }
}
