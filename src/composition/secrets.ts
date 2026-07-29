import { Err, type Result } from '@atomicloud/diene.result';
import type { SecretReader, SecretReadFailure } from '../domain/index.ts';
import type { ProviderConfigurationReader } from '../providers/index.ts';

// The ESO `dataFrom.extract` volume is flat: the rendered Secret has one flat
// key per credential, projected as a single file directly under the mount root.
// A vault pointer is therefore a leading slash plus exactly one flat filename
// segment — no hierarchy, no `.`/`..` traversal — so the adapter fails closed
// before any host-path projection.
const vaultPointerPattern = /^\/[A-Za-z0-9._-]{1,253}$/;

const invalidReference = (): SecretReadFailure => ({
  code: 'invalid-reference',
  message: 'secret reference is not a valid vault pointer',
});

/**
 * Translates the absolute-looking vault pointers stored in Neon into relative
 * paths for a root-confined mounted-secret reader. The leading slash is a
 * logical vault namespace marker; it is never treated as a host filesystem
 * root.
 */
export class VaultPointerSecretReader implements SecretReader {
  constructor(readonly mounted: SecretReader) {}

  read(secretRef: string): Promise<Result<Uint8Array, SecretReadFailure>> {
    const segment = secretRef.slice(1);
    if (!vaultPointerPattern.test(secretRef) || segment === '.' || segment === '..' || segment.includes('..')) {
      return Promise.resolve(Err(invalidReference()));
    }
    return this.mounted.read(segment);
  }
}

/** Parses opaque provider configuration JSON without logging secret material. */
export class SecretBackedProviderConfigurationReader implements ProviderConfigurationReader {
  constructor(readonly secrets: SecretReader) {}

  async read(reference: string): Promise<unknown | undefined> {
    const result = await this.secrets.read(reference);
    if (await result.isErr()) {
      throw new Error('provider configuration is unavailable');
    }

    const bytes = await result.unwrap();
    try {
      const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      return JSON.parse(text) as unknown;
    } catch {
      throw new Error('provider configuration is malformed');
    } finally {
      bytes.fill(0);
    }
  }
}

export async function readRequiredSecret(
  secrets: SecretReader,
  reference: string,
  label: string,
  minimumBytes = 1,
): Promise<Uint8Array> {
  const result = await secrets.read(reference);
  if (await result.isErr()) {
    throw new Error(`${label} is unavailable`);
  }
  const material = await result.unwrap();
  if (material.byteLength < minimumBytes) {
    material.fill(0);
    throw new Error(`${label} is invalid`);
  }
  return material;
}

export async function readRequiredSecretText(secrets: SecretReader, reference: string, label: string): Promise<string> {
  const material = await readRequiredSecret(secrets, reference, label);
  try {
    const value = new TextDecoder('utf-8', { fatal: true }).decode(material).trim();
    if (value.length === 0 || /[\r\n]/.test(value)) {
      throw new Error(`${label} is invalid`);
    }
    return value;
  } catch (error) {
    if (error instanceof Error && error.message === `${label} is invalid`) {
      throw error;
    }
    throw new Error(`${label} is invalid`);
  } finally {
    material.fill(0);
  }
}
