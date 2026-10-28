CREATE TABLE IF NOT EXISTS google_search_budget (
  month TEXT PRIMARY KEY,
  calls INTEGER NOT NULL DEFAULT 0,
  day TEXT NOT NULL,
  day_calls INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS google_search_alerts (
  period TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt INTEGER NOT NULL DEFAULT 0,
  lease_until INTEGER NOT NULL DEFAULT 0,
  sent_at INTEGER
);
