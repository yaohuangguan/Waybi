ALTER TABLE route_watches ADD COLUMN origin_name TEXT NOT NULL DEFAULT '';
ALTER TABLE route_watches ADD COLUMN origin_latitude REAL;
ALTER TABLE route_watches ADD COLUMN origin_longitude REAL;
ALTER TABLE route_watches ADD COLUMN route_provider TEXT NOT NULL DEFAULT 'unknown';
ALTER TABLE route_watches ADD COLUMN geometry_expires_at INTEGER;

-- v1 watches used the phone's current position as an implicit origin. They cannot
-- be safely converted into stable commutes, so require users to recreate them.
DELETE FROM route_watches WHERE label IN ('Home', 'Work');
