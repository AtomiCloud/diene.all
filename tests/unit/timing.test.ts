import { describe, it } from 'bun:test';
import should from 'should';
import { noop, sleep } from '../../src/timing';

describe('sleep', () => {
  it('should resolve to undefined for a zero delay', async () => {
    // Arrange
    const seconds = 0;

    // Act
    const actual = await sleep(seconds);

    // Assert
    should(actual).be.undefined();
  });

  it('should resolve after a small positive delay', async () => {
    // Arrange
    const seconds = 0.01;

    // Act
    const actual = await sleep(seconds);

    // Assert
    should(actual).be.undefined();
  });

  it.each([
    { seconds: -1, label: 'negative' },
    { seconds: Number.NaN, label: 'NaN' },
    { seconds: Number.POSITIVE_INFINITY, label: 'infinite' },
  ])('should reject with a RangeError for a $label delay', async ({ seconds }) => {
    // Arrange
    let error: unknown;

    // Act
    try {
      await sleep(seconds);
    } catch (caught) {
      error = caught;
    }

    // Assert
    should(error).be.instanceof(RangeError);
  });
});

describe('noop', () => {
  it('should return undefined and do nothing', () => {
    // Arrange

    // Act
    const actual = noop();

    // Assert
    should(actual).be.undefined();
  });
});
