import { describe, it } from 'bun:test';
import should from 'should';
import { Aes256GcmEncryptor, EncryptionError } from '../../src/lib/encryption';

const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

describe('Aes256GcmEncryptor', () => {
  it('should encrypt and decrypt a payload with the default random source', async () => {
    // Arrange
    const subject = new Aes256GcmEncryptor(key);

    // Act
    const encrypted = await subject
      .encrypt('classified')
      .match({ err: error => Promise.reject(error), ok: value => value });
    const actual = await subject.decrypt(encrypted).match({ err: error => Promise.reject(error), ok: value => value });

    // Assert
    should(actual).equal('classified');
    should(encrypted).not.equal('classified');
  });

  it('should reject a key that is not 32 bytes', () => {
    // Arrange
    const invalid = Buffer.from('short').toString('base64');

    // Act
    const actual = () => new Aes256GcmEncryptor(invalid);

    // Assert
    should(actual).throw(EncryptionError, { message: 'encryption.key must be a base64-encoded 32-byte key' });
  });

  it('should return an encryption error when randomness fails', async () => {
    // Arrange
    const subject = new Aes256GcmEncryptor(key, {
      fill: () => {
        throw new Error('entropy unavailable');
      },
    });

    // Act
    const actual = await subject.encrypt('payload').match({ err: error => error, ok: () => undefined });

    // Assert
    should(actual).be.instanceOf(EncryptionError);
    should(actual?.message).equal('failed to encrypt payload');
  });

  it.each(['not-json', '{"version":1,"iv":"x","ciphertext":"not-valid"}'])(
    'should return a decryption error for malformed ciphertext %s',
    async payload => {
      // Arrange
      const subject = new Aes256GcmEncryptor(key);

      // Act
      const actual = await subject.decrypt(payload).match({ err: error => error, ok: () => undefined });

      // Assert
      should(actual).be.instanceOf(EncryptionError);
      should(actual?.message).equal('failed to decrypt payload');
    },
  );
});
