import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import postgres, { type Sql } from 'postgres';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import {
  APPLE_BACKFILL_STATE_MIGRATION_SQL,
  PostgresAppleBackfillStateStore,
} from '../../../src/provider-operations/postgres-apple-backfill-store.ts';

describe('Postgres Apple backfill state store', () => {
  let container: StartedTestContainer;
  let sql: Sql;

  beforeAll(async () => {
    container = await new GenericContainer('postgres:17-alpine')
      .withEnvironment({
        POSTGRES_DB: 'mercury',
        POSTGRES_PASSWORD: 'mercury',
        POSTGRES_USER: 'mercury',
      })
      .withExposedPorts(5432)
      .withWaitStrategy(Wait.forLogMessage(/database system is ready to accept connections/u, 2))
      .start();
    sql = postgres({
      host: container.getHost(),
      port: container.getMappedPort(5432),
      database: 'mercury',
      username: 'mercury',
      password: 'mercury',
      max: 2,
    });
    await sql`CREATE SCHEMA IF NOT EXISTS mercury_management`;
    await sql.unsafe(APPLE_BACKFILL_STATE_MIGRATION_SQL, [], {
      prepare: false,
    });
    await sql`
			TRUNCATE TABLE mercury_management.provider_operation_state
		`;
  }, 120_000);

  afterAll(async () => {
    await sql?.end();
    await container?.stop();
  }, 120_000);

  test('enforces the singleton lease and allows takeover only after expiry', async () => {
    const store = new PostgresAppleBackfillStateStore(sql);
    const nowMs = Date.parse('2026-07-29T00:00:00.000Z');
    const first = await store.acquireLease({
      operationKey: 'apple-history:singleton',
      ownerId: 'mew',
      token: 'token-1',
      nowMs,
      leaseDurationMs: 1_000,
    });
    expect(await first.unwrap()).toMatchObject({
      ownerId: 'mew',
      token: 'token-1',
    });
    const excluded = await store.acquireLease({
      operationKey: 'apple-history:singleton',
      ownerId: 'raichu',
      token: 'token-2',
      nowMs: nowMs + 999,
      leaseDurationMs: 1_000,
    });
    expect(await excluded.unwrap()).toBeNull();

    const takeover = await store.acquireLease({
      operationKey: 'apple-history:singleton',
      ownerId: 'raichu',
      token: 'token-2',
      nowMs: nowMs + 1_000,
      leaseDurationMs: 1_000,
    });
    expect(await takeover.unwrap()).toMatchObject({
      ownerId: 'raichu',
      token: 'token-2',
    });
  });

  test('durably checkpoints cursors and missed-cycle alerts across adapter instances', async () => {
    const nowMs = Date.parse('2026-07-29T01:00:00.000Z');
    const store = new PostgresAppleBackfillStateStore(sql);
    const lease = await (
      await store.acquireLease({
        operationKey: 'apple-history:durability',
        ownerId: 'mew',
        token: 'durable-token',
        nowMs,
        leaseDurationMs: 60_000,
      })
    ).unwrap();
    expect(lease).not.toBeNull();
    if (lease === null) {
      throw new Error('expected lease');
    }

    const advanced = await store.advanceCursor({
      lease,
      cursorAfter: 'cursor-1',
      nowMs: nowMs + 1,
    });
    expect(await advanced.unwrap()).toMatchObject({ cursor: 'cursor-1' });
    const staleAdvance = await store.advanceCursor({
      lease,
      expectedCursor: 'stale-cursor',
      cursorAfter: 'cursor-2',
      nowMs: nowMs + 2,
    });
    expect(await staleAdvance.unwrap()).toBeNull();

    for (let attempt = 1; attempt <= 3; attempt += 1) {
      const missed = await store.recordMissedCycle({
        lease,
        nowMs: nowMs + 2 + attempt,
      });
      expect(await missed.unwrap()).toMatchObject({
        cursor: 'cursor-1',
        consecutiveMissedCycles: attempt,
        alert: attempt > 2,
      });
    }
    const reloaded = await new PostgresAppleBackfillStateStore(sql).readState('apple-history:durability');
    expect(await reloaded.unwrap()).toEqual({
      cursor: 'cursor-1',
      consecutiveMissedCycles: 3,
      alert: true,
    });

    const success = await store.recordCycleSuccess({
      lease,
      nowMs: nowMs + 10,
    });
    expect(await success.unwrap()).toEqual({
      cursor: 'cursor-1',
      consecutiveMissedCycles: 0,
      alert: false,
    });
    expect(await (await store.releaseLease(lease)).unwrap()).toBe(true);
  });
});
