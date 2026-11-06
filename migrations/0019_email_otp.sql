-- Additive: existing password, Google, Apple accounts and sessions remain valid.
CREATE TABLE IF NOT EXISTS email_otp_challenges (
  email_key TEXT PRIMARY KEY,
  challenge_id TEXT NOT NULL UNIQUE,
  code_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  delivered INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS email_otp_expiry ON email_otp_challenges(expires_at);

CREATE TABLE IF NOT EXISTS email_identities (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  verified_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_email_budgets (
  provider TEXT PRIMARY KEY,
  hour_start INTEGER NOT NULL,
  hour_count INTEGER NOT NULL,
  day_start INTEGER NOT NULL,
  day_count INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS email_otp_limits (
  subject TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  requests INTEGER NOT NULL
);
