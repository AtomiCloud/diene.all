import { describe, it } from 'bun:test';
import {
  checkTelemetryAttributes,
  type TelemetryAttributes,
  validateTelemetryAttributes,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

describe('validateTelemetryAttributes', () => {
  it('should pass undefined attributes through as undefined', async () => {
    // Act
    const actual = await expectOk(validateTelemetryAttributes(undefined, 'logging', 'emit'));

    // Assert
    (actual === undefined).should.be.true();
  });

  it('should accept and sort finite primitive attributes into a frozen record', async () => {
    // Arrange - deliberately unsorted keys and every primitive value kind
    const input = { zebra: 'z', alpha: 1, mid: true } as TelemetryAttributes;

    // Act
    const actual = await expectOk(validateTelemetryAttributes(input, 'metrics', 'record'));

    // Assert
    const normalized = actual ?? {};
    Object.keys(normalized).should.eql(['alpha', 'mid', 'zebra']);
    normalized.should.eql({ alpha: 1, mid: true, zebra: 'z' });
    Object.isFrozen(actual).should.be.true();
  });

  it('should accept a null-prototype record', async () => {
    // Arrange
    const input = Object.assign(Object.create(null), { a: 1 }) as TelemetryAttributes;

    // Act
    const actual = await expectOk(validateTelemetryAttributes(input, 'logging', 'emit'));

    // Assert
    const normalized = actual ?? {};
    normalized.should.eql({ a: 1 });
  });

  it.each([
    ['an array', [] as unknown],
    ['null', null as unknown],
    ['a primitive', 5 as unknown],
    ['a Map', new Map() as unknown],
    ['a class instance', new (class Attrs {})() as unknown],
  ])('should reject non-record attributes (%s)', async (_label, value) => {
    // Act
    const error = await expectErr(validateTelemetryAttributes(value as TelemetryAttributes, 'logging', 'emit'));

    // Assert
    error.port.should.eql('logging');
    error.code.should.eql('invalid-input');
    error.operation.should.eql('emit');
    error.message.should.match(/primitive record/);
  });

  it.each([
    ['empty', ''],
    ['whitespace', '   '],
    ['NUL', 'a\0b'],
  ])('should reject blank or NUL attribute names (%s)', async (_label, key) => {
    // Act
    const error = await expectErr(
      validateTelemetryAttributes({ [key]: 1 } as TelemetryAttributes, 'metrics', 'record'),
    );

    // Assert
    error.details.should.eql({});
    error.message.should.match(/name/i);
  });

  it.each([
    ['a nested object', { a: {} as unknown as number }],
    ['null value', { a: null as unknown as number }],
    ['NaN', { a: Number.NaN }],
    ['Infinity', { a: Number.POSITIVE_INFINITY }],
  ])('should reject non-finite-primitive values (%s)', async (_label, input) => {
    // Act
    const error = await expectErr(validateTelemetryAttributes(input as TelemetryAttributes, 'logging', 'emit'));

    // Assert
    error.message.should.match(/finite primitives/);
  });
});

describe('checkTelemetryAttributes', () => {
  it('should expose the accepted branch as a Checked value', () => {
    // Act
    const checked = checkTelemetryAttributes({ a: 1 }, 'metrics', 'record');

    // Assert - the check* variant returns the discriminated Checked, not a Result
    checked.ok.should.be.true();
    if (checked.ok) {
      (checked.value === undefined).should.be.false();
      if (checked.value !== undefined) checked.value.should.eql({ a: 1 });
    }
  });

  it('should expose the rejected branch as a Checked value', () => {
    // Act
    const checked = checkTelemetryAttributes(5 as unknown as TelemetryAttributes, 'logging', 'emit');

    // Assert
    checked.ok.should.be.false();
    if (!checked.ok) checked.error.code.should.eql('invalid-input');
  });
});
