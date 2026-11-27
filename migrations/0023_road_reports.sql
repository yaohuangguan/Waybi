-- Community road reports move from one shared Workers KV array (read-modify-
-- write across PoPs lost reports, and KV allows one write per key per second)
-- to D1 rows. Reports stay anonymous: reporter_id is only carried over from
-- legacy KV entries that had one, so account deletion can still purge them.
-- Valid legacy KV reports are imported by the Worker on first read (reports
-- live for two hours, so the KV copy is short-lived either way).
CREATE TABLE IF NOT EXISTS road_reports (
  id TEXT PRIMARY KEY,
  report_json TEXT NOT NULL CHECK (json_valid(report_json)),
  reporter_id TEXT,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  created_at INTEGER NOT NULL,
  valid_until INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS road_reports_valid ON road_reports(valid_until, created_at DESC);
CREATE INDEX IF NOT EXISTS road_reports_reporter ON road_reports(reporter_id) WHERE reporter_id IS NOT NULL;
