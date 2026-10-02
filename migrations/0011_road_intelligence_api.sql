CREATE TABLE road_api_keys (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  key_prefix TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX road_api_keys_user ON road_api_keys(user_id);
CREATE TABLE road_api_usage (
  key_id TEXT NOT NULL REFERENCES road_api_keys(id) ON DELETE CASCADE,
  window_type TEXT NOT NULL CHECK(window_type IN ('day', 'minute')),
  window_start INTEGER NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(key_id, window_type, window_start)
);
