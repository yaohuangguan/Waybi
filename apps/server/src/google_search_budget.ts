// Both counters update in one atomic SQLite row. Never issue a Google query
// when D1 is unavailable. Reservations are conservative and never refunded.
export const GOOGLE_SEARCH_DAY_LIMIT = 9990;
export const GOOGLE_SEARCH_MONTH_LIMIT = 9990;

export function googleSearchPeriods(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
  const get = (type) => parts.find(part => part.type === type)!.value;
  const month = `${get('year')}-${get('month')}`;
  return {month, day:`${month}-${get('day')}`};
}

export async function reserveGoogleSearch(db: any, now = new Date()) {
  if (!db) return {allowed:false,reason:'unavailable'};
  const {month,day} = googleSearchPeriods(now);
  try {
    const row = await db.prepare(`INSERT INTO google_search_budget (month,calls,day,day_calls) VALUES (?,1,?,1)
      ON CONFLICT(month) DO UPDATE SET calls=calls+1,day=excluded.day,
        day_calls=CASE WHEN day=excluded.day THEN day_calls+1 ELSE 1 END
      WHERE calls < ? AND (day != excluded.day OR day_calls < ?) RETURNING calls,day_calls`)
      .bind(month,day,GOOGLE_SEARCH_MONTH_LIMIT,GOOGLE_SEARCH_DAY_LIMIT).first();
    const usage = row || await db.prepare('SELECT calls,day,day_calls FROM google_search_budget WHERE month=?').bind(month).first();
    const monthly = Number(usage?.calls || 0);
    const daily = !row && usage?.day !== day ? 0 : Number(usage?.day_calls || 0);
    const exhausted = monthly >= GOOGLE_SEARCH_MONTH_LIMIT ? month : daily >= GOOGLE_SEARCH_DAY_LIMIT ? day : null;
    if (exhausted) await db.prepare('INSERT OR IGNORE INTO google_search_alerts (period) VALUES (?)').bind(exhausted).run();
    return {allowed:!!row,reason:row?'available':exhausted===month?'monthly_limit':'daily_limit',monthly,daily};
  } catch {
    return {allowed:false,reason:'unavailable'};
  }
}

export async function sendGoogleSearchAlerts(env: any, now = new Date(), fetcher: typeof fetch = fetch) {
  if (!env.USER_DB || !env.WAYBI_RESEND_API_KEY) return;
  const time = now.getTime();
  const rows = await env.USER_DB.prepare(`SELECT period FROM google_search_alerts
    WHERE status='pending' AND next_attempt<=? AND lease_until<=? AND attempts<6 LIMIT 4`).bind(time,time).all();
  for (const {period} of rows.results || []) {
    const claim = await env.USER_DB.prepare(`UPDATE google_search_alerts SET lease_until=?,attempts=attempts+1
      WHERE period=? AND status='pending' AND lease_until<=? AND next_attempt<=? AND attempts<6 RETURNING attempts`).bind(time+60000,period,time,time).first();
    if (!claim) continue;
    try {
      const response = await fetcher('https://api.resend.com/emails', {method:'POST',headers:{
        Authorization:`Bearer ${env.WAYBI_RESEND_API_KEY}`,'Content-Type':'application/json',
        'Idempotency-Key':`waybi-google-search-budget-${period}`,
      },body:JSON.stringify({from:'Waybi <alerts@waybi.co>',to:['moviegoer24@gmail.com'],
        subject:'Waybi：Google 搜索已达到免费保护额度，自动使用免费地址源',
        text:`Google 地点搜索的${period.length===7?'月度':'今日'}保护额度已达到上限（${period}）。Waybi 已自动改用免费地址源，导航服务继续可用。\n\n应用保护：9990 次/月（共用月度总额），为 10000 次免费额度留出 10 次余量。Google 平台硬限额：基础 UI Kit 查询 9990 次/日，其他 UI Kit SKU 为 0。\n\n这是保护额度提醒，不表示已经产生 Google 超额费用。额度周期重置后会恢复优先使用 Google。`,
      }),signal:AbortSignal.timeout(8000)});
      if (response.ok) {
        await env.USER_DB.prepare("UPDATE google_search_alerts SET status='sent',sent_at=?,lease_until=0 WHERE period=?").bind(time,period).run();
      } else {
        const retry = response.status===429 || response.status>=500;
        await env.USER_DB.prepare('UPDATE google_search_alerts SET status=?,lease_until=0,next_attempt=? WHERE period=?')
          .bind(retry?'pending':'failed',time+Math.min(3600000,60000*2**claim.attempts),period).run();
      }
    } catch {
      await env.USER_DB.prepare('UPDATE google_search_alerts SET lease_until=0,next_attempt=? WHERE period=?')
        .bind(time+Math.min(3600000,60000*2**claim.attempts),period).run();
    }
  }
}
