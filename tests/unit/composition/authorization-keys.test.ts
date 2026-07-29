import { describe, expect, test } from 'bun:test';
import { loadConsoleAuthorizationKeys } from '../../../src/composition/authorization-keys.ts';
import { MemorySecretReader } from '../../../src/runtime/index.ts';

const exportedPair = async (): Promise<{ readonly privateKey: Uint8Array; readonly publicKey: Uint8Array }> => {
  const pair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair;
  return {
    privateKey: new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey)),
    publicKey: new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)),
  };
};

describe('console authorization key composition', () => {
  test('imports and pair-checks shared ES256 material', async () => {
    const pair = await exportedPair();
    const keys = await loadConsoleAuthorizationKeys(
      new MemorySecretReader({ private: pair.privateKey, public: pair.publicKey }),
      'private',
      'public',
    );

    expect(keys.privateKey.usages).toEqual(['sign']);
    expect(keys.publicKey.usages).toEqual(['verify']);
    expect(keys.keyId).toMatch(/^[A-Za-z0-9_-]{32}$/);
  });

  test('rejects a mismatched key pair', async () => {
    const first = await exportedPair();
    const second = await exportedPair();

    await expect(
      loadConsoleAuthorizationKeys(
        new MemorySecretReader({ private: first.privateKey, public: second.publicKey }),
        'private',
        'public',
      ),
    ).rejects.toThrow('key pair does not match');
  });
});
