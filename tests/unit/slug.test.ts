import { describe, it } from 'bun:test';
import should from 'should';
import { NamespacedKeyValidationError, namespacedKey, slugify } from '../../src/slug';

describe('slugify', () => {
  it.each([
    { input: 'Hello World', expected: 'hello-world' },
    { input: '  Trim Me  ', expected: 'trim-me' },
    { input: 'Multiple   Spaces', expected: 'multiple-spaces' },
    { input: 'Symbols!@#Here', expected: 'symbols-here' },
    { input: 'already-slugged', expected: 'already-slugged' },
    { input: 'mañana', expected: 'manana' },
    { input: 'résumé café', expected: 'resume-cafe' },
    { input: '!!! ???', expected: '' },
  ])('should slugify "$input" to "$expected"', ({ input, expected }) => {
    // Arrange

    // Act
    const actual = slugify(input);

    // Assert
    should(actual).equal(expected);
  });
});

describe('namespacedKey', () => {
  it('should dogfood the published Result package for a valid key', async () => {
    // Arrange
    const namespace = 'Bun Core Utils';
    const key = 'Published Result';

    // Act
    const actual = namespacedKey(namespace, key);

    // Assert
    should(await actual.isOk()).equal(true);
    should(await actual.unwrap()).equal('bun-core-utils:published-result');
    should(await actual.serial()).deepEqual(['ok', 'bun-core-utils:published-result']);
  });

  it.each([
    {
      namespace: '!!!',
      key: 'key',
      field: 'namespace' as const,
      message: 'namespace must not be empty',
    },
    {
      namespace: 'namespace',
      key: '!!!',
      field: 'key' as const,
      message: 'key must not be empty',
    },
  ])('should return a published Result Err when $field is empty', async fixture => {
    // Arrange

    // Act
    const actual = namespacedKey(fixture.namespace, fixture.key);
    const error = await actual.unwrapErr();

    // Assert
    should(await actual.isErr()).equal(true);
    should(error).be.instanceof(NamespacedKeyValidationError);
    should(error.field).equal(fixture.field);
    should(error.reason).equal('must not be empty');
    should(error.message).equal(fixture.message);
    should(error.name).equal('NamespacedKeyValidationError');
  });
});
