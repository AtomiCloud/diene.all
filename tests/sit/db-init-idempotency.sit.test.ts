import { describe, it } from 'bun:test';
import should from 'should';
import { closeSafely, consumerDriver, initialize, postgresClient } from './driver';

describe('db-init idempotency SIT', () => {
  it('should create no duplicate seed records on a second run', async () => {
    // Arrange
    const driver = consumerDriver();
    const database = postgresClient();

    try {
      // Act
      const first = await initialize(driver);
      const before = await database.unsafe<{ count: number }[]>('SELECT COUNT(*)::int AS count FROM seed_records');
      const second = await initialize(driver);
      const after = await database.unsafe<{ count: number }[]>('SELECT COUNT(*)::int AS count FROM seed_records');

      // Assert
      should(first.code).equal(0);
      should(second.code).equal(0);
      should(after[0]?.count).equal(before[0]?.count);
    } finally {
      await closeSafely(database);
    }
  });
});
