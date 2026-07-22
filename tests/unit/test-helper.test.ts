import { describe, it } from 'bun:test';
import should from 'should';
import { Option } from '../../src/option.ts';
import { Result } from '../../src/result.ts';
import { beErr, beNone, beOk, beSome, TestHelperFailure } from '../../src/test-helper.ts';

describe('beOk', () => {
  it('should return the Ok value on a match', () => {
    // Act / Assert
    should(beOk(Result.ok<number, string>(5))).equal(5);
  });

  it('should throw a TestHelperFailure describing the Err on a mismatch', () => {
    // Act
    const actual = () => beOk(Result.err<string, number>('boom'));

    // Assert
    should(actual).throw(TestHelperFailure, { message: 'Expected Ok, got Err carrying boom.' });
  });
});

describe('beErr', () => {
  it('should return the Err error on a match', () => {
    // Act / Assert
    should(beErr(Result.err<string, number>('boom'))).equal('boom');
  });

  it('should throw a TestHelperFailure describing the Ok on a mismatch', () => {
    // Act
    const actual = () => beErr(Result.ok<number, string>(7));

    // Assert
    should(actual).throw(TestHelperFailure, { message: 'Expected Err, got Ok carrying 7.' });
  });
});

describe('beSome', () => {
  it('should return the Some value on a match', () => {
    // Act / Assert
    should(beSome(Option.some(9))).equal(9);
  });

  it('should throw a TestHelperFailure on a None', () => {
    // Act
    const actual = () => beSome(Option.none<number>());

    // Assert
    should(actual).throw(TestHelperFailure, { message: 'Expected Some, got None.' });
  });
});

describe('beNone', () => {
  it('should return without throwing on a None', () => {
    // Act
    const actual = () => beNone(Option.none<number>());

    // Assert
    should(actual).not.throw();
  });

  it('should throw a TestHelperFailure describing the Some on a mismatch', () => {
    // Act
    const actual = () => beNone(Option.some(3));

    // Assert
    should(actual).throw(TestHelperFailure, { message: 'Expected None, got Some carrying 3.' });
  });
});
