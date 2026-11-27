/**
 * Daily D1 retention (runs from the `0 3 * * *` Cron). Every statement is
 * bounded by an indexed timestamp; failures are logged and never affect the
 * camera or transit refreshes that share the trigger.
 */
const DAY_MS = 24 * 60 * 60 * 1000;
export const RETENTION = {
  routeWatchAlertsDays: 180,
  billingEventsDays: 180,
  loginAttemptsDays: 1,
  quotaCountersDays: 7,
  roadReportsDays: 1,
  emailOtpDays: 1,
  navigationFeedbackDays: 365,
};

export async function runDailyCleanup(env, now = Date.now()) {
  const db = env?.USER_DB;
  if (!db?.batch) return null;
  const day = (offsetDays: number) => new Date(now - offsetDays * DAY_MS).toISOString().slice(0, 10);
  const statements: Array<[string, any]> = [
    ['sessions', db.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(now)],
    ['login_attempts', db.prepare('DELETE FROM login_attempts WHERE window_start < ?').bind(now - RETENTION.loginAttemptsDays * DAY_MS)],
    ['auth_login_limits', db.prepare('DELETE FROM auth_login_limits WHERE window_start < ?').bind(now - RETENTION.loginAttemptsDays * DAY_MS)],
    ['route_watch_alerts', db.prepare('DELETE FROM route_watch_alerts WHERE created_at < ?').bind(now - RETENTION.routeWatchAlertsDays * DAY_MS)],
    // Stripe retries a webhook for at most three days; 180 days of event ids is ample for de-duplication.
    ['billing_events', db.prepare('DELETE FROM billing_events WHERE processed_at < ?').bind(now - RETENTION.billingEventsDays * DAY_MS)],
    ['road_reports', db.prepare('DELETE FROM road_reports WHERE valid_until < ?').bind(now - RETENTION.roadReportsDays * DAY_MS)],
    ['email_otp_challenges', db.prepare('DELETE FROM email_otp_challenges WHERE expires_at < ?').bind(now - RETENTION.emailOtpDays * DAY_MS)],
    ['email_otp_limits', db.prepare('DELETE FROM email_otp_limits WHERE window_start < ?').bind(now - RETENTION.emailOtpDays * DAY_MS)],
    // Anonymous thumbs-up/down votes only matter for recent guidance quality.
    ['navigation_feedback', db.prepare('DELETE FROM navigation_feedback WHERE created_at < ?')
      .bind(new Date(now - RETENTION.navigationFeedbackDays * DAY_MS).toISOString())],
    // Per-day quota counters (road reports, Google budgets, routing shares) are useless after their day.
    ['quota_counters', db.prepare("DELETE FROM api_usage_daily WHERE provider = '__waybi_quotas' AND day < ?").bind(day(RETENTION.quotaCountersDays))],
  ];
  try {
    const results = await db.batch(statements.map(([, statement]) => statement));
    const deleted = Object.fromEntries(statements.map(([table], index) =>
      [table, Number(results?.[index]?.meta?.changes ?? 0)]));
    console.info(JSON.stringify({ level: 'info', event: 'daily_cleanup', deleted }));
    return deleted;
  } catch (error) {
    console.error(JSON.stringify({ level: 'error', event: 'daily_cleanup_failed',
      message: String(error?.message || error).slice(0, 200) }));
    return null;
  }
}
