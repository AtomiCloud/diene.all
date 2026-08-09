import { describe, it } from 'bun:test';
import should from 'should';
import { consumerDriver } from './driver';

describe('db-init mode SIT', () => {
  it('should reach every dependency and complete migrations and seeds', async () => {
    // Arrange
    const driver = consumerDriver();

    // Act
    const actual = await driver.run(['db-init'], { ATOMI_DB_INIT__CREATE_BUCKET: 'true' });

    // Assert
    should(actual.code).equal(0);
    should(JSON.parse(actual.out)).have.properties({ ok: true });
  });
});
