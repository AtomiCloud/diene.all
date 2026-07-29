import { Err, Ok, Res, type Result } from '@atomicloud/diene.e2e/result';
import type { PostgresBlock } from '@atomicloud/diene.e2e/standard-config';
import postgres from 'postgres';
import { toPostgresOptions } from '../lib/connection-options';
import type { ProcessedMessageRecord } from '../domain/handler';
import type { SeedRecord } from '../lib/seed-records';
import { AdapterError } from './error';
import { type ApplicationTracer, withAdapterSpan } from './tracing';

export type PostgresClient = ReturnType<typeof postgres>;

export class PostgresAdapter {
  constructor(
    readonly client: PostgresClient,
    readonly tracer: ApplicationTracer,
    readonly name: string,
  ) {}

  query<T extends Record<string, unknown>>(
    statement: string,
    parameters: readonly (boolean | number | string | null)[] = [],
  ): Result<readonly T[], AdapterError> {
    return Res.async(async () => {
      try {
        const rows = await withAdapterSpan(
          this.tracer,
          'postgres.query',
          { 'atomi.adapter': 'postgres', 'atomi.connection.name': this.name, 'db.system.name': 'postgresql' },
          () => this.client.unsafe(statement, [...parameters]),
        );
        return Ok(rows as unknown as readonly T[]);
      } catch (error) {
        return Err(new AdapterError('postgres.query', 'postgres query failed', error));
      }
    });
  }

  ping(): Result<void, AdapterError> {
    return this.query('SELECT 1 AS ok').map(() => undefined);
  }

  insert(record: ProcessedMessageRecord): Result<boolean, AdapterError> {
    return this.query<{ id: string }>(
      'INSERT INTO processed_messages (id, payload, object_key, created_at) VALUES ($1, $2, $3, $4) ON CONFLICT (id) DO NOTHING RETURNING id',
      [record.id, record.payload, record.objectKey, record.createdAt],
    ).map(rows => rows.length === 1);
  }

  countProcessedMessages(id?: string): Result<number, AdapterError> {
    const statement = id
      ? 'SELECT COUNT(*)::int AS count FROM processed_messages WHERE id = $1'
      : 'SELECT COUNT(*)::int AS count FROM processed_messages';
    return this.query<{ count: number }>(statement, id ? [id] : []).map(rows => rows[0]?.count ?? 0);
  }

  listSeedIds(): Result<ReadonlySet<string>, AdapterError> {
    return this.query<{ id: string }>('SELECT id FROM seed_records').map(rows => new Set(rows.map(row => row.id)));
  }

  insertSeed(record: SeedRecord): Result<boolean, AdapterError> {
    return this.query<{ id: string }>(
      'INSERT INTO seed_records (id, value) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING RETURNING id',
      [record.id, record.value],
    ).map(rows => rows.length === 1);
  }

  countSeeds(): Result<number, AdapterError> {
    return this.query<{ count: number }>('SELECT COUNT(*)::int AS count FROM seed_records').map(
      rows => rows[0]?.count ?? 0,
    );
  }

  async close(): Promise<void> {
    await this.client.end({ timeout: 5 });
  }
}

export function buildPostgresAdapters(
  block: PostgresBlock,
  tracer: ApplicationTracer,
): ReadonlyMap<string, PostgresAdapter> {
  return new Map(
    Object.entries(block).map(([name, entry]) => {
      const client = postgres({ ...toPostgresOptions(entry), onnotice: () => undefined });
      return [name, new PostgresAdapter(client, tracer, name)] as const;
    }),
  );
}
