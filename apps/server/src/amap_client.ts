import type { ProviderPayload, UsageRecorder } from './types.ts';
import { reserveAmapCall } from './amap_budget.ts';
import { clientFingerprint, clientIp } from './abuse_guard.ts';

/**
 * The single gateway to the Amap (AutoNavi, 高德) Web Service API. The key is
 * the Worker secret AMAP_WEB_KEY: it is only ever placed in the outgoing
 * request URL and never logged, echoed or returned to a client.
 *
 * Amap reports most failures as HTTP 200 with `status: "0"` and an `infocode`
 * (for example 10001 invalid key, 10003 daily quota, 10004 too frequent).
 * Every failure becomes an AmapUnavailableError so callers can fall back to
 * Waybi's existing OpenStreetMap stack.
 */
export const AMAP_PROVIDER = 'amap';
export const AMAP_ATTRIBUTION = '高德地图 / AutoNavi';
export const AMAP_ORIGIN = 'https://restapi.amap.com';

export const AMAP_ENDPOINTS = {
  inputtips: '/v3/assistant/inputtips',
  place_text: '/v5/place/text',
  place_around: '/v5/place/around',
  regeo: '/v3/geocode/regeo',
  driving: '/v5/direction/driving',
  walking: '/v5/direction/walking',
  bicycling: '/v5/direction/bicycling',
} as const;

export type AmapApi = keyof typeof AMAP_ENDPOINTS;

export type AmapFailure =
  | 'not_configured' | 'budget_exhausted' | 'client_share' | 'budget_unavailable'
  | 'backoff' | 'http' | 'status' | 'timeout' | 'network' | 'invalid_json';

export class AmapUnavailableError extends Error {
  readonly reason: AmapFailure;
  readonly api: AmapApi;
  readonly infocode: string | null;
  constructor(api: AmapApi, reason: AmapFailure, infocode: string | null = null) {
    super(`Amap ${api} unavailable: ${reason}${infocode ? ` (${infocode})` : ''}`);
    this.name = 'AmapUnavailableError';
    this.api = api;
    this.reason = reason;
    this.infocode = infocode;
  }
}

/** Account-level problems: retrying every request would only add latency. */
const KEY_INFOCODES = new Set(['10001', '10002', '10005', '10006', '10007', '10008', '10009', '10010', '10011', '10012', '10013']);
const QUOTA_INFOCODES = new Set(['10003', '10044', '10045', '10014', '10015', '10019', '10020', '10021', '10029']);
const BACKOFF_MS = 10 * 60 * 1000;
const backoff = new Map<string, number>();

export function amapKey(env: any): string {
  const key = typeof env?.AMAP_WEB_KEY === 'string' ? env.AMAP_WEB_KEY.trim() : '';
  return /^[A-Za-z0-9]{16,64}$/.test(key) ? key : '';
}

export function amapConfigured(env: any): boolean {
  return Boolean(amapKey(env));
}

/** Pseudonymous per-client key for the daily Amap share (never a raw IP). */
export async function amapClientKey(request: Request, env: any): Promise<string> {
  return `ip:${await clientFingerprint(env, clientIp(request))}`;
}

/** Test hook: forget any per-isolate back-off. */
export function resetAmapBackoff() { backoff.clear(); }

function logFailure(api: AmapApi, reason: AmapFailure, extra: Record<string, unknown> = {}) {
  // No URL, query, coordinate or key: only what an operator needs to act.
  console.warn(JSON.stringify({ level: 'warn', event: 'amap_request_failed', api, reason, ...extra }));
}

export interface AmapRequestOptions {
  timeoutMs?: number;
  clientKey?: string | null;
  trackUsage?: UsageRecorder;
  fetcher?: typeof fetch;
  now?: () => number;
}

export async function amapGet(env: any, api: AmapApi, params: Record<string, string | undefined>,
  options: AmapRequestOptions = {}): Promise<ProviderPayload> {
  const key = amapKey(env);
  if (!key) throw new AmapUnavailableError(api, 'not_configured');
  const now = options.now ?? Date.now;
  const until = Math.max(backoff.get(api) ?? 0, backoff.get('*') ?? 0);
  if (until > now()) throw new AmapUnavailableError(api, 'backoff');
  const budget = await reserveAmapCall(env, api, options.clientKey);
  if (budget !== 'reserved') {
    const reason: AmapFailure = budget === 'exhausted' ? 'budget_exhausted'
      : budget === 'client_share' ? 'client_share' : 'budget_unavailable';
    logFailure(api, reason);
    throw new AmapUnavailableError(api, reason);
  }
  const url = new URL(AMAP_ENDPOINTS[api], AMAP_ORIGIN);
  for (const [name, value] of Object.entries(params)) {
    if (value != null && value !== '') url.searchParams.set(name, value);
  }
  url.searchParams.set('output', 'json');
  url.searchParams.set('key', key);
  options.trackUsage?.('amap', api, 1);
  let response: Response;
  try {
    response = await (options.fetcher ?? fetch)(url, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(options.timeoutMs ?? 6000),
    });
  } catch (error) {
    const name = (error as Error)?.name;
    const reason: AmapFailure = name === 'TimeoutError' || name === 'AbortError' ? 'timeout' : 'network';
    logFailure(api, reason);
    throw new AmapUnavailableError(api, reason);
  }
  if (!response.ok) {
    logFailure(api, 'http', { httpStatus: response.status });
    throw new AmapUnavailableError(api, 'http');
  }
  let payload: ProviderPayload;
  try { payload = await response.json<ProviderPayload>(); }
  catch {
    logFailure(api, 'invalid_json');
    throw new AmapUnavailableError(api, 'invalid_json');
  }
  if (!payload || typeof payload !== 'object' || String(payload.status) !== '1') {
    const infocode = typeof payload?.infocode === 'string' ? payload.infocode.slice(0, 12) : null;
    if (infocode && KEY_INFOCODES.has(infocode)) backoff.set('*', now() + BACKOFF_MS);
    else if (infocode && QUOTA_INFOCODES.has(infocode)) backoff.set(api, now() + BACKOFF_MS);
    logFailure(api, 'status', { infocode,
      info: typeof payload?.info === 'string' ? payload.info.replace(/[^A-Z0-9_]/gi, '').slice(0, 60) : null });
    throw new AmapUnavailableError(api, 'status', infocode);
  }
  return payload;
}

/** Amap returns `[]` instead of an empty string for missing text fields. */
export function amapText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

export function amapNumber(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(amapText(value));
  return Number.isFinite(parsed) ? parsed : 0;
}
