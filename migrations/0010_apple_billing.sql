CREATE TABLE IF NOT EXISTS apple_subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  status INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_subscriptions_user ON apple_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS apple_subscriptions_refresh ON apple_subscriptions(updated_at);
