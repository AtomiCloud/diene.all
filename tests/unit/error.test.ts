import { describe, it } from 'bun:test';
import should from 'should';
import { UnwrapError } from '../../src/error.ts';
import { type Option, Some } from '../../src/option.ts';
import { Ok, type Result } from '../../src/result.ts';

describe('UnwrapError', () => {
  it('should render its message and expose its fields', () => {
    // Arrange
    const payload = { reason: 'x' };

    // Act
    const actual = new UnwrapError({ monad: 'result', expected: 'Ok', actual: 'Err', payload });

    // Assert
    should(actual).be.instanceof(Error);
    should(actual.name).equal('UnwrapError');
    should(actual.message).equal('Expected Ok, got Err.');
    should(actual.monad).equal('result');
    should(actual.expected).equal('Ok');
    should(actual.actual).equal('Err');
    should(actual.payload).equal(payload);
  });

  it('should leave payload undefined when omitted', () => {
    // Act
    const actual = new UnwrapError({ monad: 'option', expected: 'Some', actual: 'None' });

    // Assert
    should(actual.payload).be.undefined();
  });
});

describe('three-state guard', () => {
  it('should throw UnwrapError when a malformed Result is dispatched', () => {
    // Arrange
    const malformed = Object.create(Ok.prototype) as { kind: string };
    malformed.kind = 'bogus';

    // Act
    let caught: UnwrapError | undefined;
    try {
      (malformed as unknown as Result<number, string>).unwrap();
    } catch (error) {
      caught = error as UnwrapError;
    }

    // Assert
    should(caught).be.instanceof(UnwrapError);
    should(caught?.monad).equal('result');
    should(caught?.expected).equal('Ok or Err');
    should(caught?.actual).equal('bogus');
  });

  it('should throw UnwrapError when a malformed Option is dispatched', () => {
    // Arrange
    const malformed = Object.create(Some.prototype) as { kind: string };
    malformed.kind = 'bogus';

    // Act
    let caught: UnwrapError | undefined;
    try {
      (malformed as unknown as Option<number>).unwrap();
    } catch (error) {
      caught = error as UnwrapError;
    }

    // Assert
    should(caught).be.instanceof(UnwrapError);
    should(caught?.monad).equal('option');
    should(caught?.expected).equal('Some or None');
    should(caught?.actual).equal('bogus');
  });
});
