import { describe, it } from 'bun:test';
import should from 'should';
import { parseSeedRecords, selectMissingSeedRecords } from '../../src/lib/seed-records';

describe('seed record logic', () => {
  it('should parse seed input and select only missing records', () => {
    // Arrange
    const records = parseSeedRecords([
      { id: 'existing', value: 'one' },
      { id: 'missing', value: 'two' },
    ]);

    // Act
    const actual = selectMissingSeedRecords(records, new Set(['existing']));

    // Assert
    should(actual).deepEqual([{ id: 'missing', value: 'two' }]);
  });

  it('should reject a blank seed id', () => {
    // Arrange
    const input = [{ id: '', value: 'bad' }];

    // Act
    const actual = () => parseSeedRecords(input);

    // Assert
    should(actual).throw();
  });
});
