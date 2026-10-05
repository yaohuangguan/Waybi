CREATE TABLE IF NOT EXISTS navigation_feedback (
  id TEXT PRIMARY KEY,
  vote INTEGER NOT NULL CHECK (vote IN (-1, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
