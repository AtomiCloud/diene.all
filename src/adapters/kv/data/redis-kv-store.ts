import { Redis } from 'ioredis';
import type { IKeyValueStore } from '../../../lib/kv/interfaces';

export interface RedisConnection {
  readonly host: string;
  readonly port: number;
}

export class RedisKeyValueStore implements IKeyValueStore {
  private readonly client: Redis;

  constructor(connection: RedisConnection) {
    this.client = new Redis({
      host: connection.host,
      port: connection.port,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    });
    // Keep ioredis error events observed; rendering belongs to the injected terminal adapters.
    this.client.on('error', () => undefined);
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (ttlSeconds !== undefined) {
      await this.client.set(key, value, 'EX', ttlSeconds);
      return;
    }
    await this.client.set(key, value);
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async close(): Promise<void> {
    await this.client.quit();
  }
}
