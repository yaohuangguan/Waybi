export async function reconcileEntitlement(db, userId, now = Date.now()) {
  // Read both providers and write access in one statement, avoiding a stale
  // read overwriting concurrent fulfillment by the other provider.
  await db.prepare(`WITH active AS (
    SELECT 'stripe' AS provider, period_end AS expires_at FROM billing_subscriptions
      WHERE user_id = ? AND status IN ('active', 'trialing') AND period_end > ?
    UNION ALL
    SELECT 'apple' AS provider, expires_at FROM apple_subscriptions
      WHERE user_id = ? AND status IN (1, 4) AND expires_at > ?
  ) INSERT INTO user_subscriptions (user_id, plan, source, expires_at, updated_at)
    SELECT ?, CASE WHEN COUNT(*) > 0 THEN 'plus' ELSE 'free' END,
      CASE WHEN MAX(provider = 'apple') = 1 THEN 'apple' ELSE 'stripe' END,
      COALESCE(MAX(expires_at), ?), ? FROM active WHERE 1
    ON CONFLICT(user_id) DO UPDATE SET
    plan = excluded.plan, source = excluded.source, expires_at = excluded.expires_at, updated_at = excluded.updated_at
    WHERE user_subscriptions.source IN ('stripe', 'apple') OR user_subscriptions.plan = 'free'
      OR (user_subscriptions.expires_at IS NOT NULL AND user_subscriptions.expires_at <= ?)`)
    .bind(userId, now, userId, now, userId, now, now, now).run();
}
