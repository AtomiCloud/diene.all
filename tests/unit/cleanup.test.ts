import { describe, it } from 'bun:test';
import should from 'should';
import { withCleanup } from '../../src/lib/cleanup';

const PRIMARY = new Error('the operation blew up');
const SECONDARY = new Error('the disconnect blew up');

describe('withCleanup', () => {
  it('should return the operation result and run the cleanup', async () => {
    // Arrange
    const calls: string[] = [];
    const expected = 'value';

    // Act
    const actual = await withCleanup(
      async () => {
        calls.push('operation');
        return expected;
      },
      async () => {
        calls.push('cleanup');
      },
      () => calls.push('reported'),
    );

    // Assert
    should(actual).equal(expected);
    should(calls).eql(['operation', 'cleanup']);
  });

  it('should surface a cleanup failure when the operation succeeded', async () => {
    // Arrange
    const reported: unknown[] = [];

    // Act
    const actual = withCleanup(
      async () => 'value',
      async () => {
        throw SECONDARY;
      },
      error => reported.push(error),
    );

    // Assert
    await should(actual).be.rejectedWith(SECONDARY);
    should(reported).eql([]);
  });

  it('should rethrow the operation error after a successful cleanup', async () => {
    // Arrange
    const calls: string[] = [];

    // Act
    const actual = withCleanup(
      async () => {
        throw PRIMARY;
      },
      async () => {
        calls.push('cleanup');
      },
      () => calls.push('reported'),
    );

    // Assert
    await should(actual).be.rejectedWith(PRIMARY);
    should(calls).eql(['cleanup']);
  });

  it('should keep the operation error when the cleanup also fails', async () => {
    // Arrange
    const reported: unknown[] = [];

    // Act
    const actual = withCleanup(
      async () => {
        throw PRIMARY;
      },
      async () => {
        throw SECONDARY;
      },
      error => reported.push(error),
    );

    // Assert
    await should(actual).be.rejectedWith(PRIMARY);
    should(reported).eql([SECONDARY]);
  });

  it('should keep the operation error when cleanup reporting also fails', async () => {
    // Arrange
    const reportingError = new Error('reporting blew up');

    // Act
    const actual = withCleanup(
      async () => {
        throw PRIMARY;
      },
      async () => {
        throw SECONDARY;
      },
      () => {
        throw reportingError;
      },
    );

    // Assert
    await should(actual).be.rejectedWith(PRIMARY);
  });
});
