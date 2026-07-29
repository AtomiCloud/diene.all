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
