import { afterEach, describe, expect, it } from 'bun:test';
import { mkdir, mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BunFileSystem } from '../../src/adapters/filesystem/bun-filesystem';

const roots: string[] = [];

async function scratchRoot(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), 'releaser-files-'));
  roots.push(root);
  return root;
}

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe('Bun filesystem adapter', () => {
  it('should cover new files, reads, hashes, matching, removal, and missing paths', async () => {
    const root = await scratchRoot();
    const subject = new BunFileSystem(root);
    const absolute = join(root, 'absolute.txt');

    await subject.writeAtomic('nested/data.txt', 'exact bytes\n');
    await subject.writeAtomic(absolute, 'absolute bytes\n');

    expect(await subject.readText('nested/data.txt')).toBe('exact bytes\n');
    expect(await subject.readTextIfExists(absolute)).toBe('absolute bytes\n');
    expect(await subject.exists('nested/data.txt')).toBe(true);
    expect(await subject.hashIfExists('nested/data.txt')).toBe(
      new Bun.CryptoHasher('sha256').update('exact bytes\n').digest('hex'),
    );
    expect(subject.matchesAny('./nested/data.txt', ['nested/*.txt'])).toBe(true);
    expect(subject.matchesAny('nested\\data.txt', ['./nested/data.txt'])).toBe(true);
    expect(subject.matchesAny('nested/data.txt', ['other/**'])).toBe(false);

    await subject.remove('nested/data.txt');
    expect(await subject.exists('nested/data.txt')).toBe(false);
    expect(await subject.readTextIfExists('nested/data.txt')).toBeNull();
    expect(await subject.hashIfExists('nested/data.txt')).toBeNull();
    await expect(subject.readText('nested/data.txt')).rejects.toThrow('file not found: nested/data.txt');
  });

  it('should remove a temporary file when the atomic rename fails', async () => {
    const root = await scratchRoot();
    await mkdir(join(root, 'blocked'));
    await Bun.write(join(root, 'blocked', 'keep.txt'), 'keep\n');
    const subject = new BunFileSystem(root);

    await expect(subject.writeAtomic('blocked', 'replacement\n')).rejects.toThrow();

    expect((await readdir(root)).filter(path => path.startsWith('blocked.tmp-'))).toEqual([]);
    expect(await Bun.file(join(root, 'blocked', 'keep.txt')).text()).toBe('keep\n');
  });
});
