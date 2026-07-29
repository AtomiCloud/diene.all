import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type postgres from 'postgres';
import type {
  AppleBackfillLease,
  AppleBackfillState,
  AppleBackfillStateStore,
  AppleBackfillStoreFailure,
} from './apple-backfill.ts';

type Sql = postgres.Sql;
type DbRow = Record<string, unknown>;

/**
 * Central management-DB migration contract for Apple history backfill state.
 *
 * The controller should add this fragment to the central migration. The row is
 * both the singleton lease and the durable cursor/missed-cycle checkpoint.
 */
export const APPLE_BACKFILL_STATE_MIGRATION_SQL = `
CREATE TABLE IF NOT EXISTS mercury_management.provider_operation_state (
  operation_key text PRIMARY KEY,
  cursor text,
  lease_owner text,
  lease_token text,
  lease_expires_at timestamptz,
  consecutive_missed_cycles integer NOT NULL DEFAULT 0
    CHECK (consecutive_missed_cycles >= 0),
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS provider_operation_state_lease_expiry_idx
  ON mercury_management.provider_operation_state (lease_expires_at)
  WHERE lease_expires_at IS NOT NULL;
`.trim();

const stateFrom = (row: DbRow): AppleBackfillState => {
  const missed = Number(row.consecutive_missed_cycles);
  return {
    ...(row.cursor === null || row.cursor === undefined ? {} : { cursor: String(row.cursor) }),
    consecutiveMissedCycles: missed,
    alert: missed > 2,
  };
};

const leaseFrom = (row: DbRow): AppleBackfillLease => ({
  operationKey: String(row.operation_key),
  ownerId: String(row.lease_owner),
  token: String(row.lease_token),
  expiresAtMs: new Date(String(row.lease_expires_at)).getTime(),
});

const databaseFailure = (): AppleBackfillStoreFailure => ({
  code: 'unavailable',
  message: 'Apple backfill state database is unavailable',
  retryable: true,
});

export class PostgresAppleBackfillStateStore implements AppleBackfillStateStore {
  constructor(readonly sql: Sql) {}

  async acquireLease(input: {
    readonly operationKey: string;
    readonly ownerId: string;
    readonly token: string;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>> {
    try {
      const now = new Date(input.nowMs);
      const expiresAt = new Date(input.nowMs + input.leaseDurationMs);
      const rows = await this.sql<DbRow[]>`
				INSERT INTO mercury_management.provider_operation_state
					(operation_key, lease_owner, lease_token, lease_expires_at,
					 consecutive_missed_cycles, last_attempt_at, updated_at)
				VALUES
					(${input.operationKey}, ${input.ownerId}, ${input.token}, ${expiresAt},
					 0, ${now}, ${now})
				ON CONFLICT (operation_key) DO UPDATE SET
					lease_owner = EXCLUDED.lease_owner,
					lease_token = EXCLUDED.lease_token,
					lease_expires_at = EXCLUDED.lease_expires_at,
					last_attempt_at = EXCLUDED.last_attempt_at,
					updated_at = EXCLUDED.updated_at
				WHERE mercury_management.provider_operation_state.lease_expires_at IS NULL
					OR mercury_management.provider_operation_state.lease_expires_at <= ${now}
				RETURNING operation_key, lease_owner, lease_token, lease_expires_at
			`;
      return Ok(rows[0] === undefined ? null : leaseFrom(rows[0]));
    } catch {
      return Err(databaseFailure());
    }
  }

  async renewLease(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>> {
    try {
      const now = new Date(input.nowMs);
      const expiresAt = new Date(input.nowMs + input.leaseDurationMs);
      const rows = await this.sql<DbRow[]>`
				UPDATE mercury_management.provider_operation_state
				SET lease_expires_at = ${expiresAt}, updated_at = ${now}
				WHERE operation_key = ${input.lease.operationKey}
					AND lease_owner = ${input.lease.ownerId}
					AND lease_token = ${input.lease.token}
					AND lease_expires_at > ${now}
				RETURNING operation_key, lease_owner, lease_token, lease_expires_at
			`;
      return Ok(rows[0] === undefined ? null : leaseFrom(rows[0]));
    } catch {
      return Err(databaseFailure());
    }
  }

  async releaseLease(lease: AppleBackfillLease): Promise<Result<boolean, AppleBackfillStoreFailure>> {
    try {
      const rows = await this.sql<DbRow[]>`
				UPDATE mercury_management.provider_operation_state
				SET lease_owner = NULL, lease_token = NULL, lease_expires_at = NULL
				WHERE operation_key = ${lease.operationKey}
					AND lease_owner = ${lease.ownerId}
					AND lease_token = ${lease.token}
				RETURNING operation_key
			`;
      return Ok(rows.length > 0);
    } catch {
      return Err(databaseFailure());
    }
  }

  async readState(operationKey: string): Promise<Result<AppleBackfillState, AppleBackfillStoreFailure>> {
    try {
      const rows = await this.sql<DbRow[]>`
				SELECT cursor, consecutive_missed_cycles
				FROM mercury_management.provider_operation_state
				WHERE operation_key = ${operationKey}
			`;
      const row = rows[0];
      return row === undefined
        ? Err({
            code: 'invalid-state',
            message: 'Apple backfill state row does not exist',
            retryable: false,
          })
        : Ok(stateFrom(row));
    } catch {
      return Err(databaseFailure());
    }
  }

  async advanceCursor(input: {
    readonly lease: AppleBackfillLease;
    readonly expectedCursor?: string;
    readonly cursorAfter: string;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    try {
      const now = new Date(input.nowMs);
      const rows = await this.sql<DbRow[]>`
				UPDATE mercury_management.provider_operation_state
				SET cursor = ${input.cursorAfter}, updated_at = ${now}
				WHERE operation_key = ${input.lease.operationKey}
					AND lease_owner = ${input.lease.ownerId}
					AND lease_token = ${input.lease.token}
					AND lease_expires_at > ${now}
					AND cursor IS NOT DISTINCT FROM ${input.expectedCursor ?? null}
				RETURNING cursor, consecutive_missed_cycles
			`;
      return Ok(rows[0] === undefined ? null : stateFrom(rows[0]));
    } catch {
      return Err(databaseFailure());
    }
  }

  async recordCycleSuccess(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    try {
      const now = new Date(input.nowMs);
      const rows = await this.sql<DbRow[]>`
				UPDATE mercury_management.provider_operation_state
				SET consecutive_missed_cycles = 0,
					last_success_at = ${now},
					updated_at = ${now}
				WHERE operation_key = ${input.lease.operationKey}
					AND lease_owner = ${input.lease.ownerId}
					AND lease_token = ${input.lease.token}
					AND lease_expires_at > ${now}
				RETURNING cursor, consecutive_missed_cycles
			`;
      return Ok(rows[0] === undefined ? null : stateFrom(rows[0]));
    } catch {
      return Err(databaseFailure());
    }
  }

  async recordMissedCycle(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    try {
      const now = new Date(input.nowMs);
      const rows = await this.sql<DbRow[]>`
				UPDATE mercury_management.provider_operation_state
				SET consecutive_missed_cycles = consecutive_missed_cycles + 1,
					last_attempt_at = ${now},
					updated_at = ${now}
				WHERE operation_key = ${input.lease.operationKey}
					AND lease_owner = ${input.lease.ownerId}
					AND lease_token = ${input.lease.token}
					AND lease_expires_at > ${now}
				RETURNING cursor, consecutive_missed_cycles
			`;
      return Ok(rows[0] === undefined ? null : stateFrom(rows[0]));
    } catch {
      return Err(databaseFailure());
    }
  }
}
