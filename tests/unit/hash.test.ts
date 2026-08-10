import { describe, it } from 'bun:test';
import should from 'should';
import { sha256 } from '../../src/hash';

describe('sha256', () => {
  it.each([
    {
      input: '',
      expected: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    },
    {
      input: 'abc',
      expected: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    },
    {
      input: 'The quick brown fox jumps over the lazy dog',
      expected: 'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
    },
  ])('should hash "$input" to its known digest', async ({ input, expected }) => {
    // Arrange

    // Act
    const actual = await sha256(input);

    // Assert
    should(actual).equal(expected);
  });

  it('should produce lowercase hexadecimal of 64 characters', async () => {
    // Arrange
    const input = 'AtomiCloud';

    // Act
    const actual = await sha256(input);

    // Assert
    should(actual).match(/^[0-9a-f]{64}$/);
  });
});
