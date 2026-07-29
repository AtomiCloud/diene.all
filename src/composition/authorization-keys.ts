import type { SecretReader } from '../domain/index.ts';
import { readRequiredSecret } from './secrets.ts';

const signingAlgorithm = { name: 'ECDSA', namedCurve: 'P-256' } as const;
const verificationAlgorithm = { name: 'ECDSA', hash: 'SHA-256' } as const;

export interface ConsoleAuthorizationKeys {
  readonly privateKey: CryptoKey;
  readonly publicKey: CryptoKey;
  readonly keyId: string;
}

const arrayBuffer = (bytes: Uint8Array): ArrayBuffer => {
  const output = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(output).set(bytes);
  return output;
};

const ownedBytes = (bytes: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(arrayBuffer(bytes));

const decodePem = (material: Uint8Array, type: 'PRIVATE KEY' | 'PUBLIC KEY'): Uint8Array<ArrayBuffer> => {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(material);
  const match = new RegExp(`^-----BEGIN ${type}-----\\s+([A-Za-z0-9+/=\\s]+)-----END ${type}-----\\s*$`).exec(text);
  if (match?.[1] === undefined) {
    throw new Error(`console authorization ${type.toLowerCase()} is malformed`);
  }
  const encoded = match[1].replace(/\s/g, '');
  const decoded = Buffer.from(encoded, 'base64');
  if (decoded.byteLength === 0 || decoded.toString('base64').replace(/=+$/, '') !== encoded.replace(/=+$/, '')) {
    throw new Error(`console authorization ${type.toLowerCase()} is malformed`);
  }
  return ownedBytes(decoded);
};

const keyMaterial = (material: Uint8Array, type: 'PRIVATE KEY' | 'PUBLIC KEY'): Uint8Array<ArrayBuffer> => {
  const prefix = new TextDecoder().decode(material.slice(0, 16));
  return prefix.startsWith('-----BEGIN') ? decodePem(material, type) : ownedBytes(material);
};

/** Loads and pair-checks the shared ES256 key used between console and landscapes. */
export async function loadConsoleAuthorizationKeys(
  secrets: SecretReader,
  privateKeyReference: string,
  publicKeyReference: string,
): Promise<ConsoleAuthorizationKeys> {
  const [privateSecret, publicSecret] = await Promise.all([
    readRequiredSecret(secrets, privateKeyReference, 'console authorization private key', 32),
    readRequiredSecret(secrets, publicKeyReference, 'console authorization public key', 32),
  ]);

  let privateDer = new Uint8Array();
  let publicDer = new Uint8Array();
  try {
    privateDer = keyMaterial(privateSecret, 'PRIVATE KEY');
    publicDer = keyMaterial(publicSecret, 'PUBLIC KEY');
    const [privateKey, publicKey] = await Promise.all([
      crypto.subtle.importKey('pkcs8', arrayBuffer(privateDer), signingAlgorithm, false, ['sign']),
      crypto.subtle.importKey('spki', arrayBuffer(publicDer), signingAlgorithm, false, ['verify']),
    ]);
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const signature = await crypto.subtle.sign(verificationAlgorithm, privateKey, challenge);
    if (!(await crypto.subtle.verify(verificationAlgorithm, publicKey, signature, challenge))) {
      throw new Error('console authorization key pair does not match');
    }
    const digest = await crypto.subtle.digest('SHA-256', arrayBuffer(publicDer));
    return {
      privateKey,
      publicKey,
      keyId: Buffer.from(digest).toString('base64url').slice(0, 32),
    };
  } catch (error) {
    if (error instanceof Error && error.message === 'console authorization key pair does not match') {
      throw error;
    }
    throw new Error('console authorization keys are invalid');
  } finally {
    privateSecret.fill(0);
    publicSecret.fill(0);
    privateDer.fill(0);
    publicDer.fill(0);
  }
}
