import { describe, expect, test } from 'bun:test';
import {
  readRequiredSecretText,
  SecretBackedProviderConfigurationReader,
  VaultPointerSecretReader,
} from '../../../src/composition/secrets.ts';
import { MemorySecretReader } from '../../../src/runtime/index.ts';

describe('Mercury secret composition', () => {
  test('maps logical vault pointers beneath the mounted secret root', async () => {
    const mounted = new MemorySecretReader({
      'stripe.json': new TextEncoder().encode('{"secrets":["current","next"]}'),
    });
    const vault = new VaultPointerSecretReader(mounted);

    const resolved = await vault.read('/stripe.json');

    expect(await resolved.isOk()).toBe(true);
    expect(new TextDecoder().decode(await resolved.unwrap())).toBe('{"secrets":["current","next"]}');
    // The flat mount rejects hierarchy, traversal, and un-anchored references.
    expect(await (await vault.read('/tenants/acme/stripe')).isErr()).toBe(true);
    expect(await (await vault.read('/tenants/../escape')).isErr()).toBe(true);
    expect(await (await vault.read('/..')).isErr()).toBe(true);
    expect(await (await vault.read('stripe.json')).isErr()).toBe(true);
  });

  test('parses provider configuration and fails closed on malformed material', async () => {
    const reader = new SecretBackedProviderConfigurationReader(
      new MemorySecretReader({
        valid: new TextEncoder().encode('{"secrets":["current","next"]}'),
        invalid: new TextEncoder().encode('{not-json'),
      }),
    );

    expect(await reader.read('valid')).toEqual({ secrets: ['current', 'next'] });
    await expect(reader.read('invalid')).rejects.toThrow('provider configuration is malformed');
    await expect(reader.read('missing')).rejects.toThrow('provider configuration is unavailable');
  });

  test('reads a required single-line secret without returning the backing bytes', async () => {
    const reader = new MemorySecretReader({ token: new TextEncoder().encode('native-token\n') });

    expect(await readRequiredSecretText(reader, 'token', 'bootstrap token')).toBe('native-token');
    await expect(
      readRequiredSecretText(
        new MemorySecretReader({ token: new TextEncoder().encode('line-one\nline-two') }),
        'token',
        'bootstrap token',
      ),
    ).rejects.toThrow('bootstrap token is invalid');
  });
});
