CREATE TABLE IF NOT EXISTS user_subscriptions (
  user_id TEXT PRIMARY KEY,
  plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'plus')),
  source TEXT,
  expires_at INTEGER,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS user_subscriptions_plan
  ON user_subscriptions(plan, expires_at);

-- Bootstrap the owner account as a permanent Plus entitlement.
INSERT OR REPLACE INTO user_subscriptions (
  user_id, plan, source, expires_at, updated_at
)
SELECT
  id,
  'plus',
  'manual',
  NULL,
  CAST(strftime('%s', 'now') AS INTEGER) * 1000
FROM users
WHERE lower(email) = 'moviegoer24@gmail.com';
