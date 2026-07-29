CREATE TABLE IF NOT EXISTS processed_messages (
  id TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  object_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS seed_records (
  id TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
