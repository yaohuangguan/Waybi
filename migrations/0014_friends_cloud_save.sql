CREATE TABLE IF NOT EXISTS friends_saves (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
  state_json TEXT NOT NULL CHECK(json_valid(state_json)),
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS friends_memories (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  memory_id TEXT NOT NULL,
  source_trip_id TEXT,
  returned_at INTEGER NOT NULL,
  memory_json TEXT NOT NULL CHECK(json_valid(memory_json)),
  PRIMARY KEY(user_id, memory_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS friends_memories_trip
  ON friends_memories(user_id, source_trip_id) WHERE source_trip_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS friends_memories_page
  ON friends_memories(user_id, returned_at DESC, memory_id DESC);
