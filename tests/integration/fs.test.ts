import { describe, it } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { VirtualFileSystem } from '@atomicloud/diene.interfaces';
import { Ok } from '@atomicloud/diene.result';
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

describe('filesystem helpers integration', () => {
  it('should round-trip a nested UTF-8 file in a real temporary directory', async () => {
    // Arrange
    const root = await mkdtemp(join(tmpdir(), 'diene-core-utils-integration-'));

    try {
      // Act
      const directory = await ensureDirectory(root, 'nested');
      await writeUtf8File(root, 'nested/config.json', '{"enabled":true}\n');
      const contents = await readUtf8File(root, 'nested/config.json');
      const exists = await fileExists(root, 'nested/config.json');
      const missing = await fileExists(root, 'nested/missing.json');

      // Assert
      should(directory).equal(resolve(root, 'nested'));
      should(contents).equal('{"enabled":true}\n');
      should(exists).equal(true);
      should(missing).equal(false);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it('should reject unsafe roots and traversal paths', () => {
    // Arrange
    const root = '/tmp/diene-core-utils';

    // Act
    const emptyRoot = () => safeJoin(' ', 'file.txt');
    const traversal = () => safeJoin(root, '../file.txt');
    const absolute = () => safeJoin(root, '/etc/passwd');

    // Assert
    should(emptyRoot).throw(RangeError);
    should(traversal).throw(RangeError);
    should(absolute).throw(RangeError);
  });

  it('should propagate unexpected filesystem errors', async () => {
    // Arrange
    const root = await mkdtemp(join(tmpdir(), 'diene-core-utils-integration-'));

    try {
      // Act
      const actual = fileExists(root, '../outside.txt');

      // Assert
      await should(actual).be.rejectedWith(RangeError);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it('should exercise UTF-8 helpers through the published VFS interface', async () => {
    // Arrange
    let written: Uint8Array = new Uint8Array();
    const vfs = {
      readFile: () => Ok<Uint8Array>(new TextEncoder().encode('read')),
      writeFile: (_path: string, contents: Uint8Array) => {
        written = contents;
        return Ok<void>(undefined);
      },
    } as Pick<VirtualFileSystem, 'readFile' | 'writeFile'> as VirtualFileSystem;

    // Act
    const read = readVfsTextFile(vfs, '/message.txt');
    const write = writeVfsTextFile(vfs, '/message.txt', 'written');
    const invalidRead = readVfsTextFile(vfs, '');
    const invalidWrite = writeVfsTextFile(vfs, '', 'ignored');

    // Assert
    should(await read.unwrap()).equal('read');
    should(await write.isOk()).equal(true);
    should(new TextDecoder().decode(written)).equal('written');
    should(await invalidRead.isErr()).equal(true);
    should(await invalidWrite.isErr()).equal(true);
  });
});
