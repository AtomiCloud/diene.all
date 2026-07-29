import type { ConsoleRequestSecurity } from './ports.ts';

const encodeBase64Url = (bytes: Uint8Array): string => Buffer.from(bytes).toString('base64url');

export class WebCryptoConsoleRequestSecurity implements ConsoleRequestSecurity {
  issueToken(byteLength: number): string {
    if (!Number.isSafeInteger(byteLength) || byteLength < 16 || byteLength > 128) {
      throw new Error('Console request token length is invalid');
    }

    return encodeBase64Url(crypto.getRandomValues(new Uint8Array(byteLength)));
  }

  equal(left: string, right: string): boolean {
    const length = Math.max(left.length, right.length);
    let difference = left.length ^ right.length;

    for (let index = 0; index < length; index += 1) {
      difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
    }

    return difference === 0;
  }
}
