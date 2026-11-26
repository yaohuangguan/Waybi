-- Plus for the dedicated App Review / Beta App Review demo account, so Apple's
-- reviewers can reach camera alerts, Smart Commute and the other Plus features
-- while StoreKit products are not yet live. The account was created through
-- the normal password registration; its password lives only in the
-- ASC_REVIEW_DEMO_PASSWORD repository secret and App Store Connect.
-- The grant expires on 2027-06-01 UTC; extend it with a new migration if review
-- still needs it then. No-op if the account does not exist.
INSERT OR REPLACE INTO user_subscriptions (
  user_id, plan, source, expires_at, updated_at
)
SELECT
  id,
  'plus',
  'manual',
  1811808000000,
  CAST(strftime('%s', 'now') AS INTEGER) * 1000
FROM users
WHERE lower(email) = 'appreview@waybi.co';
