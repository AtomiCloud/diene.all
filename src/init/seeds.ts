import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { PostgresAdapter } from '../adapters/postgres';
import { parseSeedRecords, selectMissingSeedRecords } from '../lib/seed-records';
import { requireResult } from './result';

export class SeedLoader {
  constructor(
    readonly postgres: PostgresAdapter,
    readonly directory: string,
  ) {}

  async run(): Promise<number> {
    const names = (await readdir(this.directory)).filter(name => name.endsWith('.json')).sort();
    const records = (
      await Promise.all(names.map(name => Bun.file(join(this.directory, name)).json().then(parseSeedRecords)))
    ).flat();
    const existing = await requireResult(this.postgres.listSeedIds());
    const missing = selectMissingSeedRecords(records, existing);
    for (const record of missing) await requireResult(this.postgres.insertSeed(record));
    return missing.length;
  }
}
