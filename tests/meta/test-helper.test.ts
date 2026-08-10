import { describe, it } from 'bun:test';
import should from 'should';
import { None, Some } from '../../src/lib/option.js';
import { Err, Ok } from '../../src/lib/result.js';
import { expectErr, expectNone, expectOk, expectSome, TestHelperError } from '../../src/test-helper/index.js';

describe('Result TestHelper assertions', () => {
  it('should return matching Ok and Err payloads', async () => {
    // Arrange
    const ok = Ok<number, string>(5);
    const err = Err<number, string>('boom');

    // Act
    const okValue = expectOk(ok);
    const errValue = expectErr(err);

    // Assert
    should(await okValue).equal(5);
    should(await errValue).equal('boom');
  });

  it('should fail loudly with an Err object payload diff when Ok was expected', async () => {
    // Arrange
    const actual = Err<number, { code: number }>({ code: 409 });

    // Act
    const assertion = (await expectOk(actual).catch(error => error as TestHelperError)) as TestHelperError;

    // Assert
    should(assertion).be.instanceof(TestHelperError);
    should(assertion.expected).equal('Ok');
    should(assertion.actual).equal('Err');
    should(assertion.payload).eql({ code: 409 });
    should(assertion.message).equal('Expected variant: Ok\nActual variant: Err\nActual payload:\n{\n  "code": 409\n}');
  });

  it('should fail loudly with an Ok payload diff when Err was expected', async () => {
    // Arrange
    const actual = Ok<number, string>(7);

    // Act
    const assertion = (await expectErr(actual).catch(error => error as TestHelperError)) as TestHelperError;

    // Assert
    should(assertion).be.instanceof(TestHelperError);
    should(assertion.expected).equal('Err');
    should(assertion.actual).equal('Ok');
    should(assertion.payload).equal(7);
  });

  it('should render an explicit undefined payload for payload-bearing variants', async () => {
    // Arrange
    const actual = Err<number, undefined>(undefined);

    // Act
    const assertion = (await expectOk(actual).catch(error => error as TestHelperError)) as TestHelperError;

    // Assert
    should(assertion.actual).equal('Err');
    should(assertion.payload).be.undefined();
    should(assertion.message).equal('Expected variant: Ok\nActual variant: Err\nActual payload:\nundefined');
  });
});

describe('Option TestHelper assertions', () => {
  it('should return matching Some payloads and accept None', async () => {
    // Arrange
    const some = Some(9);
    const none = None<number>();

    // Act
    const someValue = expectSome(some);
    const noneValue = expectNone(none);

    // Assert
    should(await someValue).equal(9);
    should(await noneValue).be.undefined();
  });

  it('should fail loudly when None was expected but Some was received', async () => {
    // Arrange
    const actual = Some('present');

    // Act
    const assertion = (await expectNone(actual).catch(error => error as TestHelperError)) as TestHelperError;

    // Assert
    should(assertion).be.instanceof(TestHelperError);
    should(assertion.expected).equal('None');
    should(assertion.actual).equal('Some');
    should(assertion.payload).equal('present');
    should(assertion.message).equal('Expected variant: None\nActual variant: Some\nActual payload:\n"present"');
  });

  it('should fail loudly when Some was expected but None was received', async () => {
    // Arrange
    const actual = None<number>();

    // Act
    const assertion = (await expectSome(actual).catch(error => error as TestHelperError)) as TestHelperError;

    // Assert
    should(assertion).be.instanceof(TestHelperError);
    should(assertion.expected).equal('Some');
    should(assertion.actual).equal('None');
    should(assertion.payload).be.undefined();
    should(assertion.message).equal('Expected variant: Some\nActual variant: None');
  });
});

describe('TestHelper payload formatting', () => {
  it('should fall back to String for non-JSON payloads', () => {
    // Arrange
    const functionPayload = () => undefined;
    const circularPayload: { self?: unknown } = {};
    circularPayload.self = circularPayload;

    // Act
    const functionError = new TestHelperError('Ok', 'Err', functionPayload);
    const circularError = new TestHelperError('None', 'Some', circularPayload);

    // Assert
    should(functionError.message).startWith('Expected variant: Ok\nActual variant: Err\nActual payload:\n');
    should(circularError.message).equal(
      'Expected variant: None\nActual variant: Some\nActual payload:\n[object Object]',
    );
  });
});
