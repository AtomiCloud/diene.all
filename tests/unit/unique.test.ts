import { describe, it } from 'bun:test';
import should from 'should';
import { unique } from '../../src/unique';

describe('unique', () => {
  it('should drop duplicate primitives while preserving first occurrence order', () => {
    // Arrange
    const items = [1, 2, 2, 3, 1, 3];

    // Act
    const actual = items.filter(unique);

    // Assert
    should(actual).deepEqual([1, 2, 3]);
  });

  it('should de-duplicate strings by value', () => {
    // Arrange
    const items = ['a', 'b', 'a', 'c', 'b'];

    // Act
    const actual = items.filter(unique);

    // Assert
    should(actual).deepEqual(['a', 'b', 'c']);
  });

  it('should treat NaN as equal to NaN (SameValueZero)', () => {
    // Arrange
    const items = [Number.NaN, Number.NaN, 1];

    // Act
    const actual = items.filter(unique);

    // Assert
    should(actual).have.length(2);
    should(Number.isNaN(actual[0] as number)).be.true();
    should(actual[1]).equal(1);
  });

  it('should treat +0 and -0 as the same value', () => {
    // Arrange
    const items = [0, -0, 0];

    // Act
    const actual = items.filter(unique);

    // Assert
    should(actual).deepEqual([0]);
  });

  it('should distinguish objects by reference identity', () => {
    // Arrange
    const shared = { id: 1 };
    const other = { id: 1 };
    const items = [shared, shared, other];

    // Act
    const actual = items.filter(unique);

    // Assert
    should(actual).have.length(2);
    should(actual[0]).equal(shared);
    should(actual[1]).equal(other);
  });
});
