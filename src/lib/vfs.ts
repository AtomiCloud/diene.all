import type { Result } from '@atomicloud/diene.result';
import { portError, type VfsError } from './error.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

type VfsEntryKind = 'directory' | 'file';

interface VfsEntry {
  readonly name: string;
  readonly kind: VfsEntryKind;
}

interface VfsStat {
  readonly kind: VfsEntryKind;
  readonly size: number;
}

interface CreateDirectoryOptions {
  readonly recursive?: boolean;
}

interface RemoveOptions {
  readonly recursive?: boolean;
}

interface VirtualFileSystem {
  readFile(path: string): Result<Uint8Array, VfsError>;
  writeFile(path: string, contents: Uint8Array): Result<void, VfsError>;
  exists(path: string): Result<boolean, VfsError>;
  stat(path: string): Result<VfsStat, VfsError>;
  list(path: string): Result<readonly VfsEntry[], VfsError>;
  createDirectory(path: string, options?: CreateDirectoryOptions): Result<void, VfsError>;
  remove(path: string, options?: RemoveOptions): Result<void, VfsError>;
}

function invalidVfsInput(operation: string, field: string, message: string): Checked<never, VfsError> {
  return rejected(portError('vfs', 'invalid-input', operation, message, { field }));
}

function checkVfsPath(path: string, operation = 'path'): Checked<string, VfsError> {
  if (typeof path !== 'string' || path === '' || path.includes('\0')) {
    return invalidVfsInput(operation, 'path', 'VFS path must be a non-empty NUL-free string');
  }
  if (!path.startsWith('/')) {
    return invalidVfsInput(operation, 'path', 'VFS path must be absolute');
  }
  if (path !== '/' && (path.endsWith('/') || path.includes('//'))) {
    return invalidVfsInput(operation, 'path', 'VFS path must be canonical');
  }
  if (path.split('/').some(segment => segment === '.' || segment === '..')) {
    return invalidVfsInput(operation, 'path', 'VFS path must not contain dot segments');
  }
  return accepted(path);
}

function checkFileContents(contents: Uint8Array): Checked<Uint8Array, VfsError> {
  if (!(contents instanceof Uint8Array)) {
    return invalidVfsInput('writeFile', 'contents', 'VFS file contents must be Uint8Array bytes');
  }
  return accepted(new Uint8Array(contents));
}

function checkRecursiveOptions(
  options: CreateDirectoryOptions | RemoveOptions | undefined,
  operation: 'createDirectory' | 'remove',
): Checked<Required<CreateDirectoryOptions>, VfsError> {
  if (options === undefined) return accepted(Object.freeze({ recursive: false }));
  if (
    typeof options !== 'object' ||
    options === null ||
    Array.isArray(options) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(options))
  ) {
    return invalidVfsInput(operation, 'options', 'VFS options must be an object');
  }
  if (options.recursive !== undefined && typeof options.recursive !== 'boolean') {
    return invalidVfsInput(operation, 'recursive', 'recursive must be a boolean');
  }
  return accepted(Object.freeze({ recursive: options.recursive ?? false }));
}

function validateVfsPath(path: string, operation = 'path'): Result<string, VfsError> {
  return resultFromChecked(checkVfsPath(path, operation));
}

function validateFileContents(contents: Uint8Array): Result<Uint8Array, VfsError> {
  return resultFromChecked(checkFileContents(contents));
}

function validateCreateDirectoryOptions(
  options: CreateDirectoryOptions | undefined,
): Result<Required<CreateDirectoryOptions>, VfsError> {
  return resultFromChecked(checkRecursiveOptions(options, 'createDirectory'));
}

function validateRemoveOptions(options: RemoveOptions | undefined): Result<Required<RemoveOptions>, VfsError> {
  return resultFromChecked(checkRecursiveOptions(options, 'remove'));
}

export type { CreateDirectoryOptions, RemoveOptions, VfsEntry, VfsEntryKind, VfsStat, VirtualFileSystem };
export {
  checkFileContents,
  checkRecursiveOptions,
  checkVfsPath,
  validateCreateDirectoryOptions,
  validateFileContents,
  validateRemoveOptions,
  validateVfsPath,
};
