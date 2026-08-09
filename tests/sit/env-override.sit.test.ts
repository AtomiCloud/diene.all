import { describe, it } from 'bun:test';
import should from 'should';
import { encodeWorkerMessage } from '../../src/lib/message-codec';
import { closeSafely, consumerDriver, initialize, redisClient } from './driver';

describe('environment override SIT', () => {
  it('should let ATOMI_TRANSPORT__CONSUMER_NAME override file configuration', async () => {
    // Arrange
    const driver = consumerDriver();
    should((await initialize(driver)).code).equal(0);
    const redis = redisClient();
    const id = crypto.randomUUID();
    const stream = `sit.override.${id}`;
    const group = `sit-${id}`;
    const consumer = `override-${id}`;
    await redis.xadd(
      stream,
      '*',
      'payload',
      encodeWorkerMessage({ createdAt: new Date().toISOString(), id, payload: 'override' }),
    );

    try {
      // Act
      const result = await driver.run(['worker', '--once'], {
        ATOMI_TRANSPORT__CONSUMER_GROUP: group,
        ATOMI_TRANSPORT__CONSUMER_NAME: consumer,
        ATOMI_TRANSPORT__STREAM: stream,
      });
      const consumers = (await redis.xinfo('CONSUMERS', stream, group)) as unknown[][];

      // Assert
      should(result.code).equal(0);
      should(consumers.flat()).containEql(consumer);
    } finally {
      await closeSafely(redis);
    }
  });
});
