ALTER TABLE route_watches ADD COLUMN last_alert_signature TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS route_watch_alerts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  route_watch_id TEXT NOT NULL,
  label TEXT NOT NULL,
  status TEXT NOT NULL,
  events_json TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  read_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (route_watch_id) REFERENCES route_watches(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS route_watch_alerts_user_unread
  ON route_watch_alerts(user_id, read_at, created_at DESC);

CREATE INDEX IF NOT EXISTS route_watch_alerts_watch_created
  ON route_watch_alerts(route_watch_id, created_at DESC);
