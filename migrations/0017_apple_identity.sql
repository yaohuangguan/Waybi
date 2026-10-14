CREATE TABLE IF NOT EXISTS apple_identities (
  apple_sub TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  refresh_token TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  checked_at INTEGER NOT NULL,
  revoked_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS apple_identities_refresh ON apple_identities(checked_at) WHERE revoked_at IS NULL;
