import { constants } from 'node:fs';
import { open, realpath, stat } from 'node:fs/promises';
import { isAbsolute, relative, resolve } from 'node:path';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { SecretReader, SecretReadFailure } from '../domain/index.ts';

const DEFAULT_MAX_SECRET_BYTES = 64 * 1_024;
const MAX_CONFIGURED_SECRET_BYTES = 1024 * 1_024;

export interface MountedSecretReaderOptions {
  readonly root?: string;
  readonly mapping?: Readonly<Record<string, string | Uint8Array>>;
  readonly maxBytes?: number;
}

const failure = (code: SecretReadFailure['code'], message: string): SecretReadFailure => ({ code, message });

const filesystemFailure = (error: unknown): SecretReadFailure => {
  const code = (error as NodeJS.ErrnoException | undefined)?.code;
  if (code === 'ENOENT') {
    return failure('not-found', 'secret reference was not found');
  }
  if (code === 'ELOOP') {
    return failure('invalid-reference', 'secret reference contains an unsafe symbolic-link cycle');
  }
  if (code === 'ENOTDIR' || code === 'EISDIR') {
    return failure('not-file', 'secret reference does not resolve to a regular file');
  }
  return failure('unavailable', 'secret material could not be read');
};

const validRootReference = (secretRef: string): boolean =>
  secretRef.length > 0 &&
  secretRef.length <= 512 &&
  !secretRef.includes('\0') &&
  !secretRef.includes('\\') &&
  !isAbsolute(secretRef) &&
  secretRef.split('/').every(part => part.length > 0 && part !== '.' && part !== '..');

const normalizedRootReference = (secretRef: string): string | null => {
  const normalized = secretRef.startsWith('/') && !secretRef.startsWith('//') ? secretRef.slice(1) : secretRef;
  return validRootReference(normalized) ? normalized : null;
};

const beneath = (root: string, target: string): boolean => {
  const pathFromRoot = relative(root, target);
  return (
    pathFromRoot.length > 0 &&
    pathFromRoot !== '..' &&
    !pathFromRoot.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) &&
    !isAbsolute(pathFromRoot)
  );
};

/** Reads mounted secret bytes without ever logging, formatting, or coercing the material. */
export class MountedSecretReader implements SecretReader {
  readonly root: string | undefined;
  readonly mapping: ReadonlyMap<string, string | Uint8Array>;
  readonly maxBytes: number;

  constructor(options: MountedSecretReaderOptions) {
    const maxBytes = options.maxBytes ?? DEFAULT_MAX_SECRET_BYTES;
    if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > MAX_CONFIGURED_SECRET_BYTES) {
      throw new RangeError(`maxBytes must be between 1 and ${MAX_CONFIGURED_SECRET_BYTES}`);
    }
    const entries = Object.entries(options.mapping ?? {});
    if (options.root === undefined && entries.length === 0) {
      throw new TypeError('a mounted-secret root or explicit mapping is required');
    }
    this.root = options.root;
    this.mapping = new Map(
      entries.map(([reference, target]) => [reference, typeof target === 'string' ? target : target.slice()]),
    );
    this.maxBytes = maxBytes;
  }

  async read(secretRef: string): Promise<Result<Uint8Array, SecretReadFailure>> {
    const mapped = this.mapping.get(secretRef);
    if (mapped instanceof Uint8Array) {
      return mapped.byteLength > this.maxBytes
        ? Err(failure('too-large', 'secret material exceeds the configured read limit'))
        : Ok(mapped.slice());
    }

    let target: string;
    let mountedRoot: string | undefined;
    try {
      if (typeof mapped === 'string') {
        if (!isAbsolute(mapped)) {
          return Err(failure('invalid-reference', 'explicit secret file mappings must be absolute'));
        }
        target = await realpath(mapped);
      } else {
        const normalized = normalizedRootReference(secretRef);
        if (this.root === undefined || normalized === null) {
          return Err(failure('invalid-reference', 'secret reference is outside the configured mount'));
        }
        mountedRoot = await realpath(this.root);
        target = await realpath(resolve(mountedRoot, normalized));
        if (!beneath(mountedRoot, target)) {
          return Err(failure('invalid-reference', 'secret reference escapes the configured mount'));
        }
      }

      const metadata = await stat(target);
      if (!metadata.isFile()) {
        return Err(failure('not-file', 'secret reference does not resolve to a regular file'));
      }
      if (metadata.size > this.maxBytes) {
        return Err(failure('too-large', 'secret material exceeds the configured read limit'));
      }

      const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW);
      try {
        const bytes = new Uint8Array(this.maxBytes + 1);
        let offset = 0;
        while (offset < bytes.byteLength) {
          const read = await handle.read(bytes, offset, bytes.byteLength - offset, null);
          if (read.bytesRead === 0) {
            break;
          }
          offset += read.bytesRead;
        }
        if (offset > this.maxBytes) {
          return Err(failure('too-large', 'secret material exceeds the configured read limit'));
        }
        return Ok(bytes.slice(0, offset));
      } finally {
        await handle.close();
      }
    } catch (error) {
      return Err(filesystemFailure(error));
    }
  }
}
