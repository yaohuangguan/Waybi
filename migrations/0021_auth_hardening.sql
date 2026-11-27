-- Provider links record the email address the provider verified when the link
-- was made. On the first email-code proof of an account, links without a
-- matching verified address are treated as set up before proof and removed.
-- Existing rows stay NULL: their verified address was never stored. A Google
-- link is refreshed on its next Google sign-in, an Apple link on its next
-- Apple sign-in that returns an email.
ALTER TABLE google_identities ADD COLUMN verified_email TEXT;
ALTER TABLE apple_identities ADD COLUMN verified_email TEXT;

-- Password sign-in attempts are reserved atomically before hashing. Subjects:
--   pair:<email>|<client>  tight lock for one client guessing one account
--   email:<email>          looser cap for distributed guessing
--   client:<client>        cap for one client spraying many accounts
-- <client> is an HMAC of the connecting IP; raw IPs are never stored.
CREATE TABLE IF NOT EXISTS auth_login_limits (
  subject TEXT PRIMARY KEY,
  failures INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_login_limits_window ON auth_login_limits(window_start);
