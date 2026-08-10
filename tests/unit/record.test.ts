import { describe, it } from 'bun:test';
import should from 'should';
import { isRecord, stableConfig } from '../../src/record';

describe('isRecord', () => {
  it.each([
    { value: {}, expected: true, label: 'empty object' },
    { value: { a: 1 }, expected: true, label: 'populated object' },
    { value: null, expected: false, label: 'null' },
    { value: [], expected: false, label: 'array' },
    { value: 'text', expected: false, label: 'string' },
    { value: 42, expected: false, label: 'number' },
    { value: undefined, expected: false, label: 'undefined' },
    { value: () => 1, expected: false, label: 'function' },
  ])('should return $expected for a $label', ({ value, expected }) => {
    // Arrange

    // Act
    const actual = isRecord(value);

    // Assert
    should(actual).equal(expected);
  });
});

describe('stableConfig', () => {
  it('should sort record keys deeply while preserving array order', () => {
    // Arrange
    const input = { b: 1, a: { d: 4, c: 3 }, list: [3, 1, 2] };

    // Act
    const actual = stableConfig(input);

    // Assert
    should(JSON.stringify(actual)).equal('{"a":{"c":3,"d":4},"b":1,"list":[3,1,2]}');
  });

  it('should sort keys of records nested inside arrays', () => {
    // Arrange
    const input = [{ y: 2, x: 1 }];

    // Act
    const actual = stableConfig(input);

    // Assert
    should(JSON.stringify(actual)).equal('[{"x":1,"y":2}]');
  });

  it.each([
    { value: 42, label: 'number' },
    { value: 'text', label: 'string' },
    { value: null, label: 'null' },
    { value: true, label: 'boolean' },
  ])('should pass a $label primitive through untouched', ({ value }) => {
    // Arrange

    // Act
    const actual = stableConfig(value);

    // Assert
    should(actual).equal(value);
  });

  it('should allow a non-cyclic value shared across sibling branches', () => {
    // Arrange
    const shared = { z: 26, a: 1 };
    const input = { first: shared, second: shared };

    // Act
    const actual = stableConfig(input);

    // Assert
    should(JSON.stringify(actual)).equal('{"first":{"a":1,"z":26},"second":{"a":1,"z":26}}');
  });

  it('should reject a circular record with a TypeError', () => {
    // Arrange
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;

    // Act
    const actual = () => stableConfig(cyclic);

    // Assert
    should(actual).throw(TypeError);
  });

  it('should reject a circular array with a TypeError', () => {
    // Arrange
    const cyclic: unknown[] = [];
    cyclic.push(cyclic);

    // Act
    const actual = () => stableConfig(cyclic);

    // Assert
    should(actual).throw(TypeError);
  });
});
