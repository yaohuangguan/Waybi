-- Bound user-generated Workers KV writes under the account-wide free tier.
-- The counters reset with the Workers KV daily quota at 00:00 UTC.
CREATE TABLE IF NOT EXISTS road_report_write_budget (
  day TEXT NOT NULL,
  bucket TEXT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, bucket)
);
