/** Reserve a small bounded slice of the account-wide free Workers KV quota.
 * D1's atomic UPSERT keeps users in different Worker regions from racing KV.
 * These budgets apply only to community reports, not safety-critical feeds.
 */
const MAX_USER_REPORTS_PER_DAY = 5;
const MAX_GLOBAL_REPORTS_PER_DAY = 200;

async function claim(db, day: string, bucket: string, limit: number): Promise<boolean> {
  const row = await db.prepare(`
    INSERT INTO road_report_write_budget (day, bucket, used)
    VALUES (?, ?, 1)
    ON CONFLICT(day, bucket) DO UPDATE SET used = used + 1 WHERE used < ?
    RETURNING used
  `).bind(day, bucket, limit).first();
  return Boolean(row);
}

export async function reserveRoadReportQuota(db, userId: string, now = new Date()): Promise<boolean> {
  const day = now.toISOString().slice(0, 10); // UTC, matching Workers KV reset.
  if (!await claim(db, day, `user:${userId}`, MAX_USER_REPORTS_PER_DAY)) return false;
  return claim(db, day, 'global', MAX_GLOBAL_REPORTS_PER_DAY);
}
