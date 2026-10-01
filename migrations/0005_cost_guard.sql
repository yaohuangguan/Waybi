CREATE TABLE IF NOT EXISTS api_usage_daily (
  day TEXT NOT NULL,
  provider TEXT NOT NULL,
  sku TEXT NOT NULL,
  calls INTEGER NOT NULL DEFAULT 0,
  units INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (day, provider, sku)
);

CREATE INDEX IF NOT EXISTS api_usage_daily_day
  ON api_usage_daily(day DESC);
