import { describe, expect, test } from 'bun:test';
import { APPLE_BACKFILL_STATE_MIGRATION_SQL } from '../../../src/provider-operations/postgres-apple-backfill-store.ts';

const migration = (
  await Bun.file(new URL('../../../migrations/002_provider_operation_state.sql', import.meta.url)).text()
).trim();

describe('provider operation state migration shape', () => {
  test('matches the provider operation store contract exactly', () => {
    expect(migration).toBe(APPLE_BACKFILL_STATE_MIGRATION_SQL);
    expect(migration).toContain('CREATE TABLE IF NOT EXISTS mercury_management.provider_operation_state');
    expect(migration).toContain('provider_operation_state_lease_expiry_idx');
    expect(migration).not.toMatch(/^\s*(BEGIN|COMMIT);/m);
  });
});
