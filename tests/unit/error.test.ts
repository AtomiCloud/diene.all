import { describe, it } from 'bun:test';
import should from 'should';
import { UnwrapError } from '../../src/lib/error.js';

describe('UnwrapError', () => {
  it('should expose the canonical result mismatch details', () => {
    // Arrange
    const message = 'Failed to unwrap';

    // Act
    const actual = new UnwrapError(message, 'result', 'Expected Ok got Error');

    // Assert
    should(actual).be.instanceof(Error);
    should(actual.name).equal('UnwrapError');
    should(actual.message).equal(message);
    should(actual.monadType).equal('result');
    should(actual.type).equal('Expected Ok got Error');
  });

  it('should expose the canonical option mismatch details', () => {
    // Arrange
    const message = 'Failed to unwrap';

    // Act
    const actual = new UnwrapError(message, 'option', 'Expected Some got None');

    // Assert
    should(actual.monadType).equal('option');
    should(actual.type).equal('Expected Some got None');
  });
});
