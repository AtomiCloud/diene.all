import { afterEach, describe, it } from 'bun:test';
import { mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import should from 'should';
import { MountedSecretReader } from '../../../src/runtime/secrets.ts';

const decoder = new TextDecoder();
const temporaryDirectories: string[] = [];

const temporaryDirectory = async (): Promise<string> => {
  const directory = await mkdtemp(join(tmpdir(), 'mercury-secrets-'));
  temporaryDirectories.push(directory);
  return directory;
};

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map(directory => rm(directory, { force: true, recursive: true })));
});

describe('MountedSecretReader', () => {
  it('should read only regular files beneath the mounted root and allow contained symlinks', async () => {
    // Arrange
    const root = await temporaryDirectory();
    await mkdir(join(root, 'delivery'));
    await writeFile(join(root, 'delivery', 'signing'), 'exact-secret-bytes');
    await symlink(join(root, 'delivery', 'signing'), join(root, 'current'));
    const subject = new MountedSecretReader({ root });

    // Act
    const direct = await (await subject.read('/delivery/signing')).unwrap();
    const linked = await (await subject.read('current')).unwrap();
    direct[0] = 0;
    const reread = await (await subject.read('delivery/signing')).unwrap();

    // Assert
    should(decoder.decode(linked)).equal('exact-secret-bytes');
    should(decoder.decode(reread)).equal('exact-secret-bytes');
  });

  it('should reject traversal, symlink escape, directories, missing files, and oversized material with typed failures', async () => {
    // Arrange
    const root = await temporaryDirectory();
    const outside = await temporaryDirectory();
    await mkdir(join(root, 'directory'));
    await writeFile(join(root, 'large'), '12345');
    await writeFile(join(outside, 'secret'), 'escaped');
    await symlink(join(outside, 'secret'), join(root, 'escape'));
    const subject = new MountedSecretReader({ root, maxBytes: 4 });

    // Act
    const traversal = await subject.read('../secret');
    const vaultTraversal = await subject.read('/../secret');
    const absolute = await subject.read(join(outside, 'secret'));
    const escaped = await subject.read('escape');
    const directory = await subject.read('directory');
    const missing = await subject.read('missing');
    const oversized = await subject.read('large');

    // Assert
    should((await traversal.unwrapErr()).code).equal('invalid-reference');
    should((await vaultTraversal.unwrapErr()).code).equal('invalid-reference');
    should((await absolute.unwrapErr()).code).equal('not-found');
    should((await escaped.unwrapErr()).code).equal('invalid-reference');
    should((await directory.unwrapErr()).code).equal('not-file');
    should((await missing.unwrapErr()).code).equal('not-found');
    should((await oversized.unwrapErr()).code).equal('too-large');
  });

  it('should resolve only exact injected mappings and enforce the same read cap', async () => {
    // Arrange
    const outside = await temporaryDirectory();
    const mappedFile = join(outside, 'mapped');
    await writeFile(mappedFile, 'file');
    const subject = new MountedSecretReader({
      mapping: {
        'provider/file': mappedFile,
        'provider/value': new TextEncoder().encode('data'),
        'provider/oversized': new TextEncoder().encode('12345'),
      },
      maxBytes: 4,
    });

    // Act
    const file = await (await subject.read('provider/file')).unwrap();
    const value = await (await subject.read('provider/value')).unwrap();
    const unknown = await subject.read('provider/unknown');
    const oversized = await subject.read('provider/oversized');

    // Assert
    should(decoder.decode(file)).equal('file');
    should(decoder.decode(value)).equal('data');
    should((await unknown.unwrapErr()).code).equal('invalid-reference');
    should((await oversized.unwrapErr()).code).equal('too-large');
  });
});
