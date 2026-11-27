-- Latest completed run of each scheduled job. Route Watch rewrites a watch only
-- when its status changes, so GET /api/route-watches treats watches that
-- existed when the last complete run started as checked by that run.
CREATE TABLE IF NOT EXISTS scheduled_job_runs (
  job TEXT PRIMARY KEY,
  started_at INTEGER NOT NULL,
  completed_at INTEGER,
  processed INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0
);

-- Route Watch Cron pages through enabled watches by id.
CREATE INDEX IF NOT EXISTS route_watches_enabled_id ON route_watches(enabled, id);

-- App Store subscription polling: every attempt schedules the next one, with
-- exponential backoff after failures, so failing rows cannot starve the queue.
ALTER TABLE apple_subscriptions ADD COLUMN next_check_at INTEGER;
ALTER TABLE apple_subscriptions ADD COLUMN check_failures INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS apple_subscriptions_next_check ON apple_subscriptions(next_check_at);

-- Sign in with Apple authorization checks get the same treatment.
ALTER TABLE apple_identities ADD COLUMN next_check_at INTEGER;
ALTER TABLE apple_identities ADD COLUMN check_failures INTEGER NOT NULL DEFAULT 0;

-- Daily retention cleanup (0 3 * * * Cron).
CREATE INDEX IF NOT EXISTS sessions_expires_at ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS login_attempts_window ON login_attempts(window_start);
CREATE INDEX IF NOT EXISTS route_watch_alerts_created ON route_watch_alerts(created_at);
CREATE INDEX IF NOT EXISTS billing_events_processed ON billing_events(processed_at);
