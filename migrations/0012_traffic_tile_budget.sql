CREATE TABLE IF NOT EXISTS traffic_tile_budget (
  month TEXT PRIMARY KEY,
  requests INTEGER NOT NULL DEFAULT 0
);
