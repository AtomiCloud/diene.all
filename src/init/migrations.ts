import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import type { PostgresAdapter } from '../adapters/postgres';
import type { RedisAdapter } from '../adapters/redis';
import { requireResult } from './result';

const migrationNameSchema = z.string().regex(/^\d+[-_][a-z0-9_-]+\.sql$/);

export class MigrationRunner {
  constructor(
    readonly postgres: PostgresAdapter,
    readonly redis: RedisAdapter,
    readonly postgresDirectory: string,
    readonly redisMigrationKey: string,
  ) {}

  async run(): Promise<void> {
    await requireResult(
      this.postgres.query(
        'CREATE TABLE IF NOT EXISTS diene_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())',
      ),
    );
    const appliedRows = await requireResult(this.postgres.query<{ name: string }>('SELECT name FROM diene_migrations'));
    const applied = new Set(appliedRows.map(row => row.name));
    const names = (await readdir(this.postgresDirectory))
      .filter(name => name.endsWith('.sql'))
      .map(name => migrationNameSchema.parse(name))
      .sort();
    for (const name of names) {
      if (applied.has(name)) continue;
      await requireResult(this.postgres.query(await readFile(join(this.postgresDirectory, name), 'utf8')));
      await requireResult(
        this.postgres.query('INSERT INTO diene_migrations (name) VALUES ($1) ON CONFLICT (name) DO NOTHING', [name]),
      );
    }
    await requireResult(this.redis.setIfAbsent(this.redisMigrationKey, 'ready'));
  }
}
