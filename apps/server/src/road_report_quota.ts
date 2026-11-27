/** Per-user and global daily ceilings for community road reports.
 * D1's atomic UPSERT keeps users in different Worker regions from racing.
 * Reports are stored in D1 now; the global ceiling remains an anti-spam bound.
 * A reservation whose write fails is refunded, so failures never use quota.
 */
const MAX_USER_REPORTS_PER_DAY = 5;
const MAX_GLOBAL_REPORTS_PER_DAY = 200;

async function claim(db, day: string, bucket: string, limit: number): Promise<boolean> {
  const row = await db.prepare(`
    INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
    VALUES (?, '__waybi_quotas', ?, 1, 0, ?)
    ON CONFLICT(day, provider, sku) DO UPDATE SET
      calls = calls + 1, updated_at = excluded.updated_at
    WHERE calls < ?
    RETURNING calls
  `).bind(day, bucket, Date.now(), limit).first();
  return Boolean(row);
}

async function release(db, day: string, bucket: string) {
  await db.prepare(`UPDATE api_usage_daily SET calls = MAX(0, calls - 1), updated_at = ?
    WHERE day = ? AND provider = '__waybi_quotas' AND sku = ?`).bind(Date.now(), day, bucket).first();
}

export async function reserveRoadReportQuota(db, userId: string, now = new Date()): Promise<boolean> {
  const day = now.toISOString().slice(0, 10); // UTC.
  if (!await claim(db, day, `user:${userId}`, MAX_USER_REPORTS_PER_DAY)) return false;
  if (await claim(db, day, 'global', MAX_GLOBAL_REPORTS_PER_DAY)) return true;
  // The global ceiling refused: the user's own unit was not used either.
  await release(db, day, `user:${userId}`);
  return false;
}

/** Return both units after a reservation whose report could not be stored. */
export async function refundRoadReportQuota(db, userId: string, now = new Date()): Promise<void> {
  const day = now.toISOString().slice(0, 10);
  await release(db, day, `user:${userId}`);
  await release(db, day, 'global');
}
