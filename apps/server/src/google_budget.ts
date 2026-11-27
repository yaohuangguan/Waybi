/**
 * Daily global ceilings for server-side Google SKUs (Places and Routes). The
 * reservation is one atomic D1 UPSERT, so concurrent Worker isolates cannot
 * overshoot; when a ceiling is reached callers fall back to the independent
 * providers (or answer 503 where no equivalent exists).
 *
 * Counters share api_usage_daily under the '__waybi_quotas' provider, which
 * Cost Guard excludes from spend reports. Override the defaults with the
 * WAYBI_GOOGLE_DAILY_BUDGET variable, a JSON object such as
 * {"places_text_search":500,"routes_compute":800}. Days are UTC.
 */
export const DEFAULT_GOOGLE_DAILY_BUDGET: Record<string, number> = {
  places_text_search: 300,
  places_nearby_search: 200,
  place_details: 100,
  place_photo: 500,
  routes_compute: 500,
};

export type GoogleSku = keyof typeof DEFAULT_GOOGLE_DAILY_BUDGET;

let parsedOverride: { raw: string; value: Record<string, number> } | null = null;

export function googleDailyLimit(env: any, sku: string): number {
  const raw = typeof env?.WAYBI_GOOGLE_DAILY_BUDGET === 'string' ? env.WAYBI_GOOGLE_DAILY_BUDGET : '';
  if (raw && parsedOverride?.raw !== raw) {
    let value: Record<string, number> = {};
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') value = parsed;
    } catch {
      console.warn(JSON.stringify({ level: 'warn', event: 'google_budget_config_invalid' }));
    }
    parsedOverride = { raw, value };
  }
  const override = raw ? Number(parsedOverride?.value?.[sku]) : NaN;
  if (Number.isSafeInteger(override) && override >= 0) return override;
  return DEFAULT_GOOGLE_DAILY_BUDGET[sku] ?? 0;
}

export function secondsUntilUtcMidnight(now = new Date()) {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(60, Math.ceil((next - now.getTime()) / 1000));
}

/**
 * Reserve `units` of a Google SKU for today. Without a D1 binding (unit tests,
 * a local Worker without storage) the ceiling is not enforced; a D1 failure
 * fails closed so an outage can never turn into unbounded spend.
 */
export async function reserveGoogleUnits(env: any, sku: string, units = 1, now = new Date()): Promise<boolean> {
  const db = env?.USER_DB;
  if (!db?.prepare) return true;
  const limit = googleDailyLimit(env, sku);
  const amount = Math.max(1, Math.round(units));
  if (amount > limit) return false;
  try {
    const row = await db.prepare(`
      INSERT INTO api_usage_daily (day, provider, sku, calls, units, updated_at)
      VALUES (?, '__waybi_quotas', ?, 1, ?, ?)
      ON CONFLICT(day, provider, sku) DO UPDATE SET
        calls = calls + 1, units = units + excluded.units, updated_at = excluded.updated_at
      WHERE units + excluded.units <= ?
      RETURNING units
    `).bind(now.toISOString().slice(0, 10), `google:${sku}`, amount, now.getTime(), limit).first();
    if (!row) console.warn(JSON.stringify({ level: 'warn', event: 'google_daily_budget_exhausted', sku, limit }));
    return Boolean(row);
  } catch (error) {
    console.warn(JSON.stringify({ level: 'warn', event: 'google_budget_unavailable', sku,
      message: String((error as Error)?.message || error).slice(0, 200) }));
    return false;
  }
}

export function googleBudgetExhaustedResponse(now = new Date()) {
  const retryAfter = secondsUntilUtcMidnight(now);
  return new Response(JSON.stringify({
    error: 'This Google-powered feature has reached today\'s usage limit. Please try again later.',
    code: 'GOOGLE_BUDGET_EXHAUSTED', retryAfter,
  }), { status: 503, headers: {
    'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
    'access-control-allow-origin': '*', 'retry-after': String(retryAfter),
  } });
}
