import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { discoverMercuryMigrations } from '../../../src/composition/migrations.ts';

describe('Mercury migration discovery', () => {
  test('sorts migrations and hashes their exact contents', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'mercury-migrations-'));
    try {
      await writeFile(join(directory, '002_second.sql'), 'SELECT 2;\n');
      await writeFile(join(directory, '001_first.sql'), 'SELECT 1;\n');

      const migrations = await discoverMercuryMigrations(directory);

      expect(migrations.map(migration => migration.name)).toEqual(['001_first.sql', '002_second.sql']);
      expect(migrations.every(migration => /^[a-f\d]{64}$/.test(migration.sha256))).toBe(true);
      expect(migrations[0]?.sql).toBe('SELECT 1;\n');
    } finally {
      await rm(directory, { force: true, recursive: true });
    }
  });

  test('rejects migration-owned transactions and invalid filenames', async () => {
    const transactionDirectory = await mkdtemp(join(tmpdir(), 'mercury-migrations-'));
    const invalidDirectory = await mkdtemp(join(tmpdir(), 'mercury-migrations-'));
    try {
      await writeFile(join(transactionDirectory, '001_nested.sql'), 'BEGIN;\nSELECT 1;\nCOMMIT;\n');
      await writeFile(join(invalidDirectory, 'manual.sql'), 'SELECT 1;\n');

      await expect(discoverMercuryMigrations(transactionDirectory)).rejects.toThrow(
        'must not own its transaction boundary',
      );
      await expect(discoverMercuryMigrations(invalidDirectory)).rejects.toThrow('Invalid Mercury migration filename');
    } finally {
      await Promise.all([
        rm(transactionDirectory, { force: true, recursive: true }),
        rm(invalidDirectory, { force: true, recursive: true }),
      ]);
    }
  });

  test('keeps every mounted-secret column constrained to one flat Kubernetes key', async () => {
    const directory = fileURLToPath(new URL('../../../migrations/', import.meta.url));
    const migrations = await discoverMercuryMigrations(directory);
    const management = migrations.find(migration => migration.name === '001_mercury_management.sql');
    expect(management).toBeDefined();
    expect(management?.sql.split("~ '^/[A-Za-z0-9._-]{1,253}$'").length).toBe(6);
    expect(management?.sql).toContain("secret_pointer NOT IN ('/.', '/..')");
  });
});
