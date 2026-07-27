import { describe, it } from 'bun:test';
import should from 'should';
import { coerceScalar, normalizeKey } from '../../src/lib/coerce.js';

describe('normalizeKey', () => {
  it.each([
    { input: 'maxRetries', expected: 'maxretries' },
    { input: 'MAX_RETRIES', expected: 'maxretries' },
    { input: 'MaxRetries', expected: 'maxretries' },
    { input: 'max-retries', expected: 'maxretries' },
    { input: 'port', expected: 'port' },
  ])('should normalize "$input" to "$expected"', ({ input, expected }) => {
    // Arrange

    // Act
    const actual = normalizeKey(input);

    // Assert
    should(actual).equal(expected);
  });
});

describe('coerceScalar', () => {
  it.each([
    { raw: 'true', expected: true },
    { raw: 'TRUE', expected: true },
    { raw: 'True', expected: true },
    { raw: 'false', expected: false },
    { raw: 'FALSE', expected: false },
    { raw: '0', expected: 0 },
    { raw: '42', expected: 42 },
    { raw: '-7', expected: -7 },
    { raw: '3.14', expected: 3.14 },
    { raw: 'hello', expected: 'hello' },
    { raw: 'v1.2.3', expected: 'v1.2.3' },
    { raw: '8080abc', expected: '8080abc' },
    { raw: '{"json":true}', expected: '{"json":true}' },
  ])('should coerce "$raw" to $expected', ({ raw, expected }) => {
    // Arrange

    // Act
    const actual = coerceScalar(raw);

    // Assert
    should(actual).equal(expected);
  });

  it('should treat a blank value as unset (undefined) per M33', () => {
    // Arrange
    const raw = '';

    // Act
    const actual = coerceScalar(raw);

    // Assert
    should(actual).be.undefined();
  });
});
