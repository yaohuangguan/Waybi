/** Atomically count every owned-engine attempt, including closure retries.
 * Reuse the deployed Cost Guard table; no schema or account migration needed.
 * A missing/unavailable database fails closed and leaves route fallback intact.
 */
export async function reserveNzRoutingQuota(db: any, configuredLimit: string, now = new Date()): Promise<void> {
  const limit = Number(configuredLimit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 3000 || !db?.prepare) {
    throw new Error('NZ routing budget unavailable');
  }
  const row = await db.prepare(`
    INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
    VALUES (?, 'waybi-valhalla', 'route', 1, 1, ?)
    ON CONFLICT(day, provider, sku) DO UPDATE SET
      calls = calls + 1, units = units + 1, updated_at = excluded.updated_at
    WHERE calls < ?
    RETURNING calls
  `).bind(now.toISOString().slice(0, 10), now.getTime(), limit).first();
  if (!row) throw new Error('NZ routing daily budget reached');
}
