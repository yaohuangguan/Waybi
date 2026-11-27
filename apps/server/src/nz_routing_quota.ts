/** Atomically count every owned-engine attempt, including closure retries.
 * Reuse the deployed Cost Guard table; no schema or account migration needed.
 * A missing/unavailable database fails closed and leaves route fallback intact.
 *
 * Each client (signed-in user, else a pseudonymous IP key) may use only a share
 * of the shared daily limit, so one stuck or abusive client cannot push every
 * other driver onto the public fallback. A client over its share falls back to
 * the public router, exactly as when the global limit is reached.
 */
export interface NzRoutingClient {
  key: string;
  /** WAYBI_NZ_ROUTING_CLIENT_DAILY_LIMIT; defaults to 10% of the daily limit. */
  limit?: string | number | null;
}

export function nzRoutingClientShare(limit: number, configured?: string | number | null): number {
  const value = Number(configured);
  if (configured != null && configured !== '' && Number.isSafeInteger(value) && value >= 1) return Math.min(limit, value);
  return Math.max(20, Math.floor(limit * 0.1));
}

export async function reserveNzRoutingQuota(db: any, configuredLimit: string, now = new Date(), client?: NzRoutingClient | null): Promise<void> {
  const limit = Number(configuredLimit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 3000 || !db?.prepare) {
    throw new Error('NZ routing budget unavailable');
  }
  const day = now.toISOString().slice(0, 10);
  if (client?.key) {
    const share = nzRoutingClientShare(limit, client.limit);
    const claimed = await db.prepare(`
      INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
      VALUES (?, '__waybi_quotas', ?, 1, 0, ?)
      ON CONFLICT(day, provider, sku) DO UPDATE SET
        calls = calls + 1, updated_at = excluded.updated_at
      WHERE calls < ?
      RETURNING calls
    `).bind(day, `nz-routing:${client.key}`, now.getTime(), share).first();
    if (!claimed) throw new Error('NZ routing client share reached');
  }
  const row = await db.prepare(`
    INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
    VALUES (?, 'waybi-valhalla', 'route', 1, 1, ?)
    ON CONFLICT(day, provider, sku) DO UPDATE SET
      calls = calls + 1, units = units + 1, updated_at = excluded.updated_at
    WHERE calls < ?
    RETURNING calls
  `).bind(day, now.getTime(), limit).first();
  if (!row) throw new Error('NZ routing daily budget reached');
}
