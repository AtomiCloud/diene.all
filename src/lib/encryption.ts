import { Err, Ok, Res, type Result } from '@atomicloud/diene.e2e/result';
import { z } from 'zod';

const encryptedPayloadSchema = z
  .object({
    ciphertext: z.string().min(1),
    iv: z.string().min(1),
    version: z.literal(1),
  })
  .strict();

export class EncryptionError extends Error {
  constructor(
    message: string,
    override readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'EncryptionError';
  }
}

export interface RandomSource {
  fill(bytes: Uint8Array): Uint8Array;
}

export interface IEncryptor {
  decrypt(payload: string): Result<string, EncryptionError>;
  encrypt(plaintext: string): Result<string, EncryptionError>;
}

export class Aes256GcmEncryptor implements IEncryptor {
  readonly key: ArrayBuffer;

  constructor(
    encodedKey: string,
    readonly random: RandomSource = { fill: bytes => crypto.getRandomValues(bytes) },
  ) {
    const key = Uint8Array.from(Buffer.from(encodedKey, 'base64'));
    if (key.byteLength !== 32) throw new EncryptionError('encryption.key must be a base64-encoded 32-byte key');
    this.key = key.buffer as ArrayBuffer;
  }

  encrypt(plaintext: string): Result<string, EncryptionError> {
    return Res.async(async () => {
      try {
        const iv = this.random.fill(new Uint8Array(12));
        const key = await crypto.subtle.importKey('raw', this.key, 'AES-GCM', false, ['encrypt']);
        const ivBuffer = iv.buffer.slice(iv.byteOffset, iv.byteOffset + iv.byteLength) as ArrayBuffer;
        const encodedPlaintext = new TextEncoder().encode(plaintext);
        const ciphertext = await crypto.subtle.encrypt(
          { iv: ivBuffer, name: 'AES-GCM' },
          key,
          encodedPlaintext.buffer as ArrayBuffer,
        );
        return Ok(
          JSON.stringify({
            ciphertext: Buffer.from(ciphertext).toString('base64'),
            iv: Buffer.from(iv).toString('base64'),
            version: 1,
          }),
        );
      } catch (error) {
        return Err(new EncryptionError('failed to encrypt payload', error));
      }
    });
  }

  decrypt(payload: string): Result<string, EncryptionError> {
    return Res.async(async () => {
      try {
        const envelope = encryptedPayloadSchema.parse(JSON.parse(payload));
        const key = await crypto.subtle.importKey('raw', this.key, 'AES-GCM', false, ['decrypt']);
        const iv = Uint8Array.from(Buffer.from(envelope.iv, 'base64'));
        const ciphertext = Uint8Array.from(Buffer.from(envelope.ciphertext, 'base64'));
        const plaintext = await crypto.subtle.decrypt(
          { iv: iv.buffer as ArrayBuffer, name: 'AES-GCM' },
          key,
          ciphertext.buffer as ArrayBuffer,
        );
        return Ok(new TextDecoder().decode(plaintext));
      } catch (error) {
        return Err(new EncryptionError('failed to decrypt payload', error));
      }
    });
  }
}
