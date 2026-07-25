import { describe, it } from 'bun:test';
import should from 'should';
import { consumerDriver, initialize, waitFor } from './driver';

describe('worker mode SIT', () => {
  it('should run the worker composition through the compiled binary', async () => {
    // Arrange
    const driver = consumerDriver();
    const initialized = await initialize(driver);
    should(initialized.code).equal(0);
    const heartbeat = `dist/run/worker-${crypto.randomUUID()}.json`;

    // Act
    const running = driver.start(['worker'], { ATOMI_HEALTH__HEARTBEAT_FILE: heartbeat });
    let health = await driver.run(['health'], { ATOMI_HEALTH__HEARTBEAT_FILE: heartbeat });
    await waitFor(async () => {
      health = await driver.run(['health'], { ATOMI_HEALTH__HEARTBEAT_FILE: heartbeat });
      return health.code === 0;
    });
    const stopped = await running.stop();

    // Assert
    should(health.code).equal(0);
    should(JSON.parse(health.out).healthy).equal(true);
    should([0, 143]).containEql(stopped.code);
  });
});
