import { describe, it } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { portError, type VirtualFileSystem } from '@atomicloud/diene.interfaces';
import { Err, Ok } from '@atomicloud/diene.result';
import should from 'should';
import {
  ensureDirectory,
  fileExists,
  readUtf8File,
  readVfsTextFile,
  safeJoin,
  writeUtf8File,
  writeVfsTextFile,
} from '../../src/fs';

describe('safeJoin', () => {
  it('should resolve a relative path beneath an explicit root', () => {
    // Arrange
    const root = '/tmp/core-utils';

    // Act
    const actual = safeJoin(root, 'nested', 'file.txt');

    // Assert
    should(actual).equal(resolve(root, 'nested', 'file.txt'));
  });

  it.each(['../escape.txt', '../../escape.txt', '/etc/passwd'])('should reject a path outside the root: %s', path => {
    // Arrange
    const root = '/tmp/core-utils';

    // Act
    const actual = () => safeJoin(root, path);

    // Assert
    should(actual).throw(RangeError, { message: 'path must remain beneath root' });
  });

  it('should reject an empty root', () => {
    // Arrange

    // Act
    const actual = () => safeJoin('   ', 'file.txt');

    // Assert
    should(actual).throw(RangeError, { message: 'root must not be empty' });
  });
});

describe('node filesystem helpers', () => {
  it('should create directories and round-trip UTF-8 files beneath a root', async () => {
    // Arrange
    const root = await mkdtemp(join(tmpdir(), 'diene-core-utils-'));

    try {
      // Act
      const directory = await ensureDirectory(root, 'nested');
      const path = await writeUtf8File(root, 'nested/message.txt', 'héllo');
      const contents = await readUtf8File(root, 'nested/message.txt');
      const exists = await fileExists(root, 'nested/message.txt');
      const missing = await fileExists(root, 'nested/missing.txt');

      // Assert
      should(directory).equal(resolve(root, 'nested'));
      should(path).equal(resolve(root, 'nested/message.txt'));
      should(contents).equal('héllo');
      should(exists).equal(true);
      should(missing).equal(false);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it('should preserve unexpected filesystem failures', async () => {
    // Arrange
    const root = await mkdtemp(join(tmpdir(), 'diene-core-utils-'));

    try {
      await writeUtf8File(root, 'file.txt', 'contents');

      // Act
      const actual = fileExists(root, 'file.txt/child');

      // Assert
      await should(actual).be.rejectedWith({ code: 'ENOTDIR' });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe('VirtualFileSystem text helpers', () => {
  it('should exercise the published interface and result packages for UTF-8 I/O', async () => {
    // Arrange
    let written: Uint8Array = new Uint8Array();
    const vfs = {
      readFile: () => Ok<Uint8Array>(new TextEncoder().encode('héllo')),
      writeFile: (_path: string, contents: Uint8Array) => {
        written = contents;
        return Ok<void>(undefined);
      },
    } as Pick<VirtualFileSystem, 'readFile' | 'writeFile'> as VirtualFileSystem;

    // Act
    const readResult = readVfsTextFile(vfs, '/message.txt');
    const writeResult = writeVfsTextFile(vfs, '/message.txt', 'world');

    // Assert
    should(await readResult.unwrap()).equal('héllo');
    should(await writeResult.isOk()).equal(true);
    should(new TextDecoder().decode(written)).equal('world');
  });

  it('should return published interface validation errors without calling the port', async () => {
    // Arrange
    let called = false;
    const error = portError('vfs', 'io', 'unused', 'unused');
    const vfs = {
      readFile: () => {
        called = true;
        return Err<Uint8Array, typeof error>(error);
      },
      writeFile: () => {
        called = true;
        return Err<void, typeof error>(error);
      },
    } as Pick<VirtualFileSystem, 'readFile' | 'writeFile'> as VirtualFileSystem;

    // Act
    const readResult = readVfsTextFile(vfs, '');
    const writeResult = writeVfsTextFile(vfs, '', 'contents');

    // Assert
    should(await readResult.isErr()).equal(true);
    should(await writeResult.isErr()).equal(true);
    should(called).equal(false);
  });
});
