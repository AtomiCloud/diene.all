import { describe, expect, test } from 'bun:test';
import { preserveMutationBeforeRestore } from './helpers.ts';

function memoryRepo(initial: Record<string, string>, failEvidenceWrite = false) {
  const files = new Map(Object.entries(initial));
  return {
    files,
    async read(path: string): Promise<string> {
      const value = files.get(path);
      if (value === undefined) {
        throw new Error(`missing fixture: ${path}`);
      }
      return value;
    },
    async write(path: string, value: string): Promise<void> {
      if (failEvidenceWrite && path.startsWith('.probe-evidence/')) {
        throw new Error('evidence write refused');
      }
      files.set(path, value);
    },
  };
}

describe('probe mutation evidence', () => {
  test('copies the exact mutated bytes before restoring the source', async () => {
    const repo = memoryRepo({ 'nested/source.txt': 'mutated\nbytes\n' });

    await preserveMutationBeforeRestore(repo, 'example-row', 'nested/source.txt', 'original\nbytes\n');

    expect(repo.files.get('.probe-evidence/example-row/nested/source.txt')).toBe('mutated\nbytes\n');
    expect(repo.files.get('nested/source.txt')).toBe('original\nbytes\n');
  });

  test('restores the source and fails closed when evidence cannot be written', async () => {
    const repo = memoryRepo({ 'nested/source.txt': 'mutated\n' }, true);

    await expect(preserveMutationBeforeRestore(repo, 'example-row', 'nested/source.txt', 'original\n')).rejects.toThrow(
      'evidence write refused',
    );
    expect(repo.files.get('nested/source.txt')).toBe('original\n');
  });
});
