import { describe, it } from 'bun:test';
import should from 'should';
import { mapWithConcurrency } from '../../src/concurrency';
import { sleep } from '../../src/timing';

describe('mapWithConcurrency', () => {
  it('should preserve input order regardless of completion order', async () => {
    // Arrange
    const items = [40, 10, 30, 20, 0];

    // Act — later items resolve sooner, yet order must follow the input
    const actual = await mapWithConcurrency(items, 2, async item => {
      await sleep(item / 1000);
      return item * 2;
    });

    // Assert
    should(actual).deepEqual([80, 20, 60, 40, 0]);
  });

  it('should pass the index to the mapper', async () => {
    // Arrange
    const items = ['a', 'b', 'c'];

    // Act
    const actual = await mapWithConcurrency(items, 3, (item, index) => `${index}:${item}`);

    // Assert
    should(actual).deepEqual(['0:a', '1:b', '2:c']);
  });

  it('should never exceed the concurrency bound of active work', async () => {
    // Arrange
    const items = Array.from({ length: 12 }, (_, index) => index);
    const concurrency = 3;
    let active = 0;
    let peak = 0;

    // Act
    await mapWithConcurrency(items, concurrency, async item => {
      active += 1;
      peak = Math.max(peak, active);
      await sleep(0.005);
      active -= 1;
      return item;
    });

    // Assert
    should(peak).be.belowOrEqual(concurrency);
  });

  it('should return an empty array for empty input', async () => {
    // Arrange
    const items: number[] = [];

    // Act
    const actual = await mapWithConcurrency(items, 4, async item => item);

    // Assert
    should(actual).deepEqual([]);
  });

  it.each([
    { concurrency: 0, label: 'zero' },
    { concurrency: -2, label: 'negative' },
    { concurrency: 1.5, label: 'non-integer' },
    { concurrency: Number.NaN, label: 'NaN' },
  ])('should reject a $label concurrency with a RangeError', async ({ concurrency }) => {
    // Arrange
    let error: unknown;

    // Act
    try {
      await mapWithConcurrency([1, 2, 3], concurrency, async item => item);
    } catch (caught) {
      error = caught;
    }

    // Assert
    should(error).be.instanceof(RangeError);
  });

  it('should propagate a mapper rejection', async () => {
    // Arrange
    const boom = new Error('mapper failed');
    let error: unknown;

    // Act
    try {
      await mapWithConcurrency([1, 2, 3], 2, async item => {
        if (item === 2) throw boom;
        return item;
      });
    } catch (caught) {
      error = caught;
    }

    // Assert
    should(error).equal(boom);
  });
});
