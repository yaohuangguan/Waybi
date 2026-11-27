import { reserveDailyQuotaUnits } from './google_budget.ts';

/**
 * Daily ceilings for Amap (AutoNavi) Web Service calls, enforced in D1 exactly
 * like the Google budgets: one atomic UPSERT per call in api_usage_daily under
 * the '__waybi_quotas' provider, UTC days. Past a ceiling, Waybi answers from
 * its existing OpenStreetMap stack instead of calling Amap.
 *
 * Amap's free quota for a certified personal developer is monthly and pooled:
 * 基础搜索服务 (input tips, keyword and around search) 5,000 calls/month and
 * 基础LBS服务 (route planning, geocoding, reverse geocoding) 150,000/month.
 * The defaults below stay under both pools in a 31-day month:
 *   search: (90 + 30 + 30) × 31 = 4,650 < 5,000
 *   LBS:    (1,000 + 2,500 + 400 + 400) × 31 = 133,300 < 150,000
 *
 * Override with WAYBI_AMAP_DAILY_BUDGET, a JSON object such as
 * {"inputtips":300,"driving":6000,"client_share":0.25}. `client_share` is the
 * fraction (0–1] of each API's daily ceiling one client may use (default 0.5),
 * so one device cannot spend the whole day's search quota.
 */
export const DEFAULT_AMAP_DAILY_BUDGET: Record<string, number> = {
  inputtips: 90,
  place_text: 30,
  place_around: 30,
  regeo: 1000,
  driving: 2500,
  walking: 400,
  bicycling: 400,
};

export const DEFAULT_AMAP_CLIENT_SHARE = 0.5;

let parsedOverride: { raw: string; value: Record<string, number> } | null = null;

function override(env: any): Record<string, number> {
  const raw = typeof env?.WAYBI_AMAP_DAILY_BUDGET === 'string' ? env.WAYBI_AMAP_DAILY_BUDGET : '';
  if (!raw) return {};
  if (parsedOverride?.raw !== raw) {
    let value: Record<string, number> = {};
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) value = parsed;
    } catch {
      console.warn(JSON.stringify({ level: 'warn', event: 'amap_budget_config_invalid' }));
    }
    parsedOverride = { raw, value };
  }
  return parsedOverride.value;
}

export function amapDailyLimit(env: any, api: string): number {
  const configured = Number(override(env)[api]);
  if (Number.isSafeInteger(configured) && configured >= 0) return configured;
  return DEFAULT_AMAP_DAILY_BUDGET[api] ?? 0;
}

export function amapClientDailyLimit(env: any, api: string): number {
  const limit = amapDailyLimit(env, api);
  const configured = Number(override(env).client_share);
  const share = Number.isFinite(configured) && configured > 0 && configured <= 1 ? configured : DEFAULT_AMAP_CLIENT_SHARE;
  return Math.min(limit, Math.max(1, Math.floor(limit * share)));
}

export type AmapBudgetOutcome = 'reserved' | 'exhausted' | 'client_share' | 'unavailable';

/**
 * Reserve one call of `api` for today, first against the client's share, then
 * against the global ceiling. Without a D1 binding (unit tests, local dev) the
 * ceiling is not enforced; a D1 failure fails closed so an outage can never
 * become unbounded spend.
 */
export async function reserveAmapCall(env: any, api: string, clientKey?: string | null, now = new Date()): Promise<AmapBudgetOutcome> {
  const db = env?.USER_DB;
  if (!db?.prepare) return 'reserved';
  const limit = amapDailyLimit(env, api);
  if (limit < 1) return 'exhausted';
  try {
    if (clientKey && !await reserveDailyQuotaUnits(db, `amap-client:${api}:${clientKey}`, 1, amapClientDailyLimit(env, api), now)) {
      return 'client_share';
    }
    return await reserveDailyQuotaUnits(db, `amap:${api}`, 1, limit, now) ? 'reserved' : 'exhausted';
  } catch (error) {
    console.warn(JSON.stringify({ level: 'warn', event: 'amap_budget_unavailable', api,
      message: String((error as Error)?.message || error).slice(0, 200) }));
    return 'unavailable';
  }
}
