import { Redis } from 'ioredis';
import type { ILogger } from '../lib/logger';
import type { IKeyValueStore, RedisConnection } from './kv-store';

/** ioredis reconnects on its own after a refused connection, so that code is routine churn. */
const ROUTINE_CONNECTION_ERROR_CODE = 'ECONNREFUSED';

export class RedisKeyValueStore implements IKeyValueStore {
  private readonly client: Redis;

  constructor(connection: RedisConnection, logger: ILogger) {
    this.client = new Redis({
      host: connection.host,
      port: connection.port,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    });
    // ioredis crashes the process on an unhandled 'error' event, so this listener has to exist.
    this.client.on('error', (error: Error) => {
      if ((error as NodeJS.ErrnoException).code === ROUTINE_CONNECTION_ERROR_CODE) return;
      logger.error(
        { host: connection.host, port: connection.port, reason: error.message },
        'unexpected redis connection error',
      );
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
