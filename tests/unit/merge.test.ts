import { describe, it } from 'bun:test';
import should from 'should';
import { type ConfigRecord, deepMerge, isRecord } from '../../src/lib/merge.js';

describe('isRecord', () => {
  it.each([
    { label: 'plain object', value: { a: 1 }, expected: true },
    { label: 'empty object', value: {}, expected: true },
    { label: 'array', value: [1, 2], expected: false },
    { label: 'null', value: null, expected: false },
    { label: 'string', value: 'x', expected: false },
    { label: 'number', value: 3, expected: false },
  ])('should return $expected for a $label', ({ value, expected }) => {
    // Arrange

    // Act
    const actual = isRecord(value);

    // Assert
    should(actual).equal(expected);
  });
});

describe('deepMerge', () => {
  it('should overlay scalar keys, source winning', () => {
    // Arrange
    const base: ConfigRecord = { a: 1, b: 2 };
    const override: ConfigRecord = { b: 3, c: 4 };

    // Act
    const actual = deepMerge(base, override);

    // Assert
    should(actual).deepEqual({ a: 1, b: 3, c: 4 });
  });

  it('should recursively merge nested objects', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80, host: 'a' }, flag: false };
    const override: ConfigRecord = { server: { port: 8080 } };

    // Act
    const actual = deepMerge(base, override);

    // Assert
    should(actual).deepEqual({ server: { port: 8080, host: 'a' }, flag: false });
  });

  it('should replace arrays wholesale rather than element-merging', () => {
    // Arrange
    const base: ConfigRecord = { hosts: ['a', 'b', 'c'] };
    const override: ConfigRecord = { hosts: ['x'] };

    // Act
    const actual = deepMerge(base, override);

    // Assert
    should(actual).deepEqual({ hosts: ['x'] });
  });

  it('should replace an object with a scalar when the override is scalar', () => {
    // Arrange
    const base: ConfigRecord = { a: { nested: 1 } };
    const override: ConfigRecord = { a: 5 };

    // Act
    const actual = deepMerge(base, override);

    // Assert
    should(actual).deepEqual({ a: 5 });
  });

  it('should not mutate the inputs', () => {
    // Arrange
    const base: ConfigRecord = { a: { b: 1 } };
    const override: ConfigRecord = { a: { c: 2 } };

    // Act
    deepMerge(base, override);

    // Assert
    should(base).deepEqual({ a: { b: 1 } });
    should(override).deepEqual({ a: { c: 2 } });
  });
});
