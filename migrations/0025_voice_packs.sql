-- Shared custom navigation voices. A Plus member uploads recorded guidance
-- phrases; anyone with the share code can import them. Clip audio lives in
-- the VOICE_PACKS R2 bucket under
-- voice-packs/<owner_id>/<id>/<language>/<phrase_id>. The Worker deletes
-- those objects when a pack is revoked and before an account is deleted
-- (D1 then cascades these rows away).
CREATE TABLE IF NOT EXISTS voice_packs (
  id TEXT PRIMARY KEY,
  share_code TEXT NOT NULL UNIQUE,
  owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  -- JSON array of language packs, e.g. ["en","zh"].
  languages TEXT NOT NULL,
  -- JSON: { "<language>": { "<phrase_id>": { "bytes", "contentType", "sha256" } } }
  manifest_json TEXT NOT NULL,
  clip_count INTEGER NOT NULL,
  total_bytes INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  import_count INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS voice_packs_owner_active
  ON voice_packs(owner_id, revoked_at, created_at);
