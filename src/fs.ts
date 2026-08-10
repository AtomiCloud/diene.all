import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { type VfsError, type VirtualFileSystem, validateVfsPath } from '@atomicloud/diene.interfaces';
import type { Result } from '@atomicloud/diene.result';

function outsideRoot(root: string, candidate: string): boolean {
  const pathFromRoot = relative(root, candidate);
  return pathFromRoot === '..' || pathFromRoot.startsWith(`..${sep}`) || isAbsolute(pathFromRoot);
}

/**
 * Resolves path segments beneath an explicit root and rejects traversal outside it.
 */
export function safeJoin(root: string, ...segments: readonly string[]): string {
  if (root.trim() === '') {
    throw new RangeError('root must not be empty');
  }

  const resolvedRoot = resolve(root);
  const candidate = resolve(resolvedRoot, ...segments);
  if (outsideRoot(resolvedRoot, candidate)) {
    throw new RangeError('path must remain beneath root');
  }
  return candidate;
}

export async function ensureDirectory(root: string, path = '.'): Promise<string> {
  const target = safeJoin(root, path);
  await mkdir(target, { recursive: true });
  return target;
}

export async function readUtf8File(root: string, path: string): Promise<string> {
  return readFile(safeJoin(root, path), 'utf8');
}

export async function writeUtf8File(root: string, path: string, contents: string): Promise<string> {
  const target = safeJoin(root, path);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, contents, 'utf8');
  return target;
}

export async function fileExists(root: string, path: string): Promise<boolean> {
  try {
    await stat(safeJoin(root, path));
    return true;
  } catch (error: unknown) {
    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      (error as { readonly code?: unknown }).code === 'ENOENT'
    ) {
      return false;
    }
    throw error;
  }
}

/**
 * Reads UTF-8 through the published interfaces package's VirtualFileSystem port.
 */
export function readVfsTextFile(vfs: VirtualFileSystem, path: string): Result<string, VfsError> {
  return validateVfsPath(path, 'readVfsTextFile')
    .andThen(validatedPath => vfs.readFile(validatedPath))
    .map(contents => new TextDecoder().decode(contents));
}

/**
 * Writes UTF-8 through the published interfaces package's VirtualFileSystem port.
 */
export function writeVfsTextFile(vfs: VirtualFileSystem, path: string, contents: string): Result<void, VfsError> {
  return validateVfsPath(path, 'writeVfsTextFile').andThen(validatedPath =>
    vfs.writeFile(validatedPath, new TextEncoder().encode(contents)),
  );
}
