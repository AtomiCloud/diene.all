import { describe, it } from 'bun:test';
import should from 'should';
import { encodeWorkerMessage } from '../../src/lib/message-codec';
import { closeSafely, consumerDriver, initialize, postgresClient, redisClient, storageClient } from './driver';

describe('message journey SIT', () => {
  it('should consume, persist, encrypt-store, and acknowledge a Redis stream message', async () => {
    // Arrange
    const driver = consumerDriver();
    should((await initialize(driver)).code).equal(0);
    const redis = redisClient();
    const database = postgresClient();
    const storage = storageClient();
    const id = crypto.randomUUID();
    const stream = `sit.message.${id}`;
    const group = `sit-${id}`;
    const environment = {
      ATOMI_TRANSPORT__CONSUMER_GROUP: group,
      ATOMI_TRANSPORT__IDLE_MS: '0',
      ATOMI_TRANSPORT__STREAM: stream,
    };

    try {
      await redis.xadd(
        stream,
        '*',
        'payload',
        encodeWorkerMessage({ createdAt: new Date().toISOString(), id, payload: 'journey' }),
      );

      // Act
      const result = await driver.run(['worker', '--once'], environment);
      const rows = await database.unsafe<{ object_key: string; payload: string }[]>(
        'SELECT object_key, payload FROM processed_messages WHERE id = $1',
        [id],
      );
      const object = rows[0]?.object_key ? await storage.file(rows[0].object_key).exists() : false;
      const pending = (await redis.xpending(stream, group)) as [number, string | null, string | null, unknown[]];

      // Assert
      should(result.code).equal(0);
      should(rows).have.length(1);
      should(rows[0]?.payload).equal('journey');
      should(object).equal(true);
      should(pending[0]).equal(0);
    } finally {
      await closeSafely(redis);
      await closeSafely(database);
    }
  });
});
