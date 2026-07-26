/**
 * Compute the SHA-256 digest of a UTF-8 string as lowercase hexadecimal.
 *
 * Implemented on the Web Crypto API (`crypto.subtle`) and `TextEncoder`, both
 * of which are standard globals in Bun and in the emitted Node ESM/CJS builds,
 * so the same source works across every target without a runtime import.
 */
export async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await globalThis.crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map(byte => byte.toString(16).padStart(2, '0'))
    .join('');
}
