import { describe, it } from 'bun:test';
import should from 'should';
import type { IKeyValueStore } from '../../src/adapters/kv-store';
import { RedisKeyValueStore } from '../../src/adapters/redis-kv-store';
import { buildSampleKey, createRedisStore, persistSample } from '../../src/lib/sample';

describe('sample library surface', () => {
  it('should build a namespaced sample key', () => {
    // Arrange
    const namespace = 'Sample Library';
    const key = 'Primary Value';

    // Act
    const actual = buildSampleKey(namespace, key);

    // Assert
    should(actual).equal('sample-library:primary-value');
  });

  it('should create a lazy Redis-backed store', () => {
    // Arrange
    const connection = { host: '127.0.0.1', port: 6379 };

    // Act
    const actual = createRedisStore(connection);

    // Assert
    should(actual).be.instanceof(RedisKeyValueStore);
  });

  it('should persist and return a sample value', async () => {
    // Arrange
    const values = new Map<string, string>();
    const store: IKeyValueStore = {
      async set(key, value) {
        values.set(key, value);
      },
      async get(key) {
        return values.get(key) ?? null;
      },
      async close() {},
    };

    // Act
    const actual = await persistSample(store, 'Sample Library', 'Primary Value', 'stored');

    // Assert
    should(actual).equal('stored');
    should(values.get('sample-library:primary-value')).equal('stored');
  });
});
