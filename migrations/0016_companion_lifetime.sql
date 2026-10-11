-- Preserve aggregate navigation history independently of the 100-row activity feed.
-- Backfill once from all route_history rows still present at migration time.
CREATE TABLE IF NOT EXISTS companion_totals (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  distance_meters INTEGER NOT NULL DEFAULT 0 CHECK (distance_meters >= 0),
  trip_count INTEGER NOT NULL DEFAULT 0 CHECK (trip_count >= 0),
  duration_seconds INTEGER NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0)
);

INSERT OR IGNORE INTO companion_totals (user_id, distance_meters, trip_count, duration_seconds)
SELECT user_id,
  SUM(MAX(0, COALESCE(distance_meters, 0))),
  COUNT(*),
  SUM(MAX(0, COALESCE(duration_seconds, 0)))
FROM route_history
GROUP BY user_id;

-- Keep stable upload IDs after the 100-entry activity feed is pruned.
-- This ledger is tiny per trip and guarantees late retries do not duplicate totals.
CREATE TABLE IF NOT EXISTS companion_route_receipts (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  journey_id TEXT NOT NULL,
  PRIMARY KEY (user_id, journey_id)
);

INSERT OR IGNORE INTO companion_route_receipts (user_id, journey_id)
SELECT user_id, id FROM route_history;

-- Triggered inside the same SQLite transaction as route insertion.
-- Pruning route_history does not decrement the permanent aggregate.
CREATE TRIGGER IF NOT EXISTS companion_route_recorded
AFTER INSERT ON route_history
BEGIN
  INSERT INTO companion_route_receipts (user_id, journey_id)
  VALUES (NEW.user_id, NEW.id);

  INSERT INTO companion_totals (user_id, distance_meters, trip_count, duration_seconds)
  VALUES (NEW.user_id, MAX(0, COALESCE(NEW.distance_meters, 0)), 1,
          MAX(0, COALESCE(NEW.duration_seconds, 0)))
  ON CONFLICT(user_id) DO UPDATE SET
    distance_meters = distance_meters + excluded.distance_meters,
    trip_count = trip_count + 1,
    duration_seconds = duration_seconds + excluded.duration_seconds;
END;

-- Guest aggregates can be imported once per account/device batch.
CREATE TABLE IF NOT EXISTS companion_guest_imports (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  import_id TEXT NOT NULL,
  distance_meters INTEGER NOT NULL CHECK (distance_meters BETWEEN 0 AND 1000000000),
  trip_count INTEGER NOT NULL CHECK (trip_count BETWEEN 0 AND 1000000),
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds BETWEEN 0 AND 1000000000),
  created_at INTEGER NOT NULL,
  PRIMARY KEY(user_id, import_id)
);

CREATE TRIGGER IF NOT EXISTS companion_guest_imported
AFTER INSERT ON companion_guest_imports
BEGIN
  INSERT INTO companion_totals (user_id, distance_meters, trip_count, duration_seconds)
  VALUES (NEW.user_id, NEW.distance_meters, NEW.trip_count, NEW.duration_seconds)
  ON CONFLICT(user_id) DO UPDATE SET
    distance_meters = distance_meters + excluded.distance_meters,
    trip_count = trip_count + excluded.trip_count,
    duration_seconds = duration_seconds + excluded.duration_seconds;
END;
