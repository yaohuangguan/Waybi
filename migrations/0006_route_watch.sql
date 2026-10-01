CREATE TABLE IF NOT EXISTS route_watches (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  label TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  destination_latitude REAL NOT NULL,
  destination_longitude REAL NOT NULL,
  route_points_json TEXT NOT NULL,
  baseline_duration_seconds INTEGER,
  baseline_distance_meters INTEGER,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_checked_at INTEGER,
  last_status TEXT NOT NULL DEFAULT 'healthy',
  last_event_count INTEGER NOT NULL DEFAULT 0,
  last_events_json TEXT NOT NULL DEFAULT '[]',
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, label)
);

CREATE INDEX IF NOT EXISTS route_watches_user_enabled
  ON route_watches(user_id, enabled, updated_at DESC);
