import { describe, it } from 'bun:test';
import should from 'should';
import { consumerDriver, initialize } from './driver';

describe('health subcommand SIT', () => {
  it('should report a fresh internal heartbeat without checking dependencies', async () => {
    // Arrange
    const driver = consumerDriver();
    should((await initialize(driver)).code).equal(0);
    const heartbeat = `dist/run/health-${crypto.randomUUID()}.json`;
    should((await driver.run(['worker', '--once'], { ATOMI_HEALTH__HEARTBEAT_FILE: heartbeat })).code).equal(0);

    // Act
    const actual = await driver.run(['health'], {
      ATOMI_HEALTH__HEARTBEAT_FILE: heartbeat,
      ATOMI_POSTGRES__MAIN__HOST: 'dependency-is-not-consulted.invalid',
      ATOMI_KV__MAIN__HOST: 'dependency-is-not-consulted.invalid',
      ATOMI_STORAGE__MAIN__ENDPOINT: 'http://dependency-is-not-consulted.invalid',
    });

    // Assert
    should(actual.code).equal(0);
    should(JSON.parse(actual.out).healthy).equal(true);
  });
});
