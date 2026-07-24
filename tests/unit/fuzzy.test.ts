import { describe, it } from 'bun:test';
import should from 'should';
import { fuzzyIncludes } from '../../src/fuzzy';

describe('fuzzyIncludes', () => {
  it.each([
    { a: 'Hello World', b: 'world', expected: true },
    { a: 'Hello World', b: 'HELLO', expected: true },
    { a: 'Hello World', b: 'lo Wo', expected: true },
    { a: 'Hello World', b: 'planet', expected: false },
    { a: 'abc', b: '', expected: true },
    { a: '', b: 'a', expected: false },
    { a: '', b: '', expected: true },
    { a: 'CaseMix', b: 'casemix', expected: true },
  ])('should return $expected for needle "$b" in haystack "$a"', ({ a, b, expected }) => {
    // Arrange

    // Act
    const actual = fuzzyIncludes(a, b);

    // Assert
    should(actual).equal(expected);
  });
});
