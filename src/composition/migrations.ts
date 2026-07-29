import { join } from 'node:path';
import type postgres from 'postgres';

type Sql = postgres.Sql;

// PostgreSQL's two-key advisory-lock form keeps both values inside signed
// int32, which the postgres client can encode without an ambiguous bigint
// parameter type. Together they spell "MERC" / "URY" for this product.
const MIGRATION_LOCK_NAMESPACE = 0x4d455243;
const MIGRATION_LOCK_KEY = 0x555259;
const migrationNamePattern = /^\d{3}_[a-z0-9_]+\.sql$/;

export interface MercuryMigration {
  readonly name: string;
  readonly path: string;
  readonly sha256: string;
  readonly sql: string;
}

export async function discoverMercuryMigrations(
  directory = join(process.cwd(), 'migrations'),
): Promise<MercuryMigration[]> {
  const names: string[] = [];
  for await (const name of new Bun.Glob('*.sql').scan({ cwd: directory, onlyFiles: true })) {
    if (!migrationNamePattern.test(name)) {
      throw new Error(`Invalid Mercury migration filename: ${name}`);
    }
    names.push(name);
  }

  names.sort();
  const migrations: MercuryMigration[] = [];
  for (const name of names) {
    const path = join(directory, name);
    const sql = await Bun.file(path).text();
    if (/^\s*(?:BEGIN|COMMIT)\s*;/im.test(sql)) {
      throw new Error(`Mercury migration ${name} must not own its transaction boundary`);
    }
    migrations.push({
      name,
      path,
      sha256: new Bun.CryptoHasher('sha256').update(sql).digest('hex'),
      sql,
    });
  }
  return migrations;
}

export async function runMercuryMigrations(sql: Sql, directory?: string): Promise<readonly MercuryMigration[]> {
  const migrations = await discoverMercuryMigrations(directory);
  const connection = await sql.reserve();
  let locked = false;

  try {
    await connection`SELECT pg_advisory_lock(${MIGRATION_LOCK_NAMESPACE}, ${MIGRATION_LOCK_KEY})`;
    locked = true;
    await connection`
      CREATE TABLE IF NOT EXISTS public.mercury_schema_migrations (
        name text PRIMARY KEY,
        sha256 text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `;
    for (const migration of migrations) {
      const existing = await connection<{ sha256: string }[]>`
        SELECT sha256
        FROM public.mercury_schema_migrations
        WHERE name = ${migration.name}
      `;
      const applied = existing[0];
      if (applied !== undefined) {
        if (applied.sha256 !== migration.sha256) {
          throw new Error(`Applied Mercury migration changed: ${migration.name}`);
        }
        continue;
      }

      await connection.unsafe('BEGIN');
      try {
        await connection.unsafe(migration.sql);
        await connection`
          INSERT INTO public.mercury_schema_migrations (name, sha256)
          VALUES (${migration.name}, ${migration.sha256})
        `;
        await connection.unsafe('COMMIT');
      } catch (error) {
        try {
          await connection.unsafe('ROLLBACK');
        } catch {
          // A broken connection has already released its transaction and lock server-side.
        }
        throw error;
      }
    }
  } finally {
    try {
      if (locked) {
        await connection`SELECT pg_advisory_unlock(${MIGRATION_LOCK_NAMESPACE}, ${MIGRATION_LOCK_KEY})`;
      }
    } finally {
      connection.release();
    }
  }

  return migrations;
}
