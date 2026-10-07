function cleanDimension(value, fallback) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_.-]+/g, '_')
    .slice(0, 80);
  return normalized || fallback;
}

export async function recordApiUsage(
  env,
  { provider, sku, calls = 1, units = calls }
) {
  if (!env?.USER_DB) return;
  const normalizedCalls = Math.max(1, Math.min(1000, Math.round(Number(calls) || 1)));
  const normalizedUnits = Math.max(1, Math.min(10000, Math.round(Number(units) || normalizedCalls)));
  const day = new Date().toISOString().slice(0, 10);
  try {
    await env.USER_DB.prepare(`
      INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(day, provider, sku) DO UPDATE SET
        calls = calls + excluded.calls,
        units = units + excluded.units,
        updated_at = excluded.updated_at
    `)
      .bind(
        day,
        cleanDimension(provider, 'unknown'),
        cleanDimension(sku, 'unknown'),
        normalizedCalls,
        normalizedUnits,
        Date.now()
      )
      .run();
  } catch (error) {
    // Usage tracking must never break navigation/search if a migration is pending.
    console.warn('Cost Guard usage write failed', error);
  }
}

export async function readUsageSummary(env, days = 31) {
  if (!env?.USER_DB) return { days, rows: [], totals: { calls: 0, units: 0 } };
  const safeDays = Math.max(1, Math.min(93, Math.round(Number(days) || 31)));
  const start = new Date(Date.now() - (safeDays - 1) * 86400000)
    .toISOString()
    .slice(0, 10);
  try {
    const result = await env.USER_DB.prepare(`
      SELECT day, provider, sku, calls, units, updated_at AS updatedAt
      FROM api_usage_daily
      WHERE day >= ?
      ORDER BY day DESC, provider ASC, sku ASC
    `).bind(start).all();
    const rows = result.results || [];
    return {
      days: safeDays,
      rows,
      totals: rows.reduce(
        (totals, row) => ({
          calls: totals.calls + Number(row.calls || 0),
          units: totals.units + Number(row.units || 0)
        }),
        { calls: 0, units: 0 }
      )
    };
  } catch (error) {
    console.warn('Cost Guard usage read failed', error);
    return { days: safeDays, rows: [], totals: { calls: 0, units: 0 }, migrationPending: true };
  }
}
