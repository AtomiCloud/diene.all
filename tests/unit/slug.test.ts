import { describe, it } from 'bun:test';
import should from 'should';
import { NamespacedKeyValidationError, namespacedKey, slugify } from '../../src/lib/slug';

describe('slugify', () => {
  it.each([
    { input: 'Hello World', expected: 'hello-world' },
    { input: '  Trim Me  ', expected: 'trim-me' },
    { input: 'Multiple   Spaces', expected: 'multiple-spaces' },
    { input: 'Symbols!@#Here', expected: 'symbols-here' },
    { input: 'already-slugged', expected: 'already-slugged' },
    { input: 'mañana', expected: 'manana' },
    { input: 'résumé café', expected: 'resume-cafe' },
  ])('should slugify "$input" to "$expected"', ({ input, expected }) => {
    // Act
    const actual = slugify(input);

    // Assert
    should(actual).equal(expected);
  });

  it('should collapse a fully non-alphanumeric string to empty', () => {
    // Arrange
    const input = '!!! ???';
    const expected = '';

    // Act
    const actual = slugify(input);

    // Assert
    should(actual).equal(expected);
  });
});

describe('namespacedKey', () => {
  it('should join a slugified namespace and key with a colon', () => {
    // Arrange
    const namespace = 'Bun Base';
    const key = 'Sample Key';
    const expected = 'bun-base:sample-key';

    // Act
    const actual = namespacedKey(namespace, key);

    // Assert
    should(actual).equal(expected);
  });

  it('should throw NamespacedKeyValidationError when the namespace slugifies to empty', () => {
    // Arrange
    const namespace = '!!!';
    const key = 'key';

    // Act
    const actual = () => namespacedKey(namespace, key);

    // Assert
    should(actual).throw(NamespacedKeyValidationError, { message: 'namespace must not be empty' });
  });

  it('should throw NamespacedKeyValidationError when the key slugifies to empty', () => {
    // Arrange
    const namespace = 'ns';
    const key = '!!!';

    // Act
    const actual = () => namespacedKey(namespace, key);

    // Assert
    should(actual).throw(NamespacedKeyValidationError, { message: 'key must not be empty' });
  });
});
