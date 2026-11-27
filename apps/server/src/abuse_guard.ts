/**
 * Burst protection for endpoints that spend paid upstream quota, shared free
 * quota (NZ routing, Nominatim, NZTA ArcGIS) or CPU (scrypt).
 *
 * Workers Rate Limiting bindings are per Cloudflare location and approximate,
 * so they bound bursts from one client; daily spend is bounded separately by
 * the D1 budgets in google_budget.ts and nz_routing_quota.ts. A missing binding
 * (tests, `wrangler dev` without the config) or a limiter outage allows the
 * request: availability of navigation wins over a best-effort burst limit.
 */
export type RateLimitBinding =
  | 'RATE_LIMIT_SEARCH'
  | 'RATE_LIMIT_PLACES'
  | 'RATE_LIMIT_ROUTING'
  | 'RATE_LIMIT_SPEED_LIMIT'
  | 'RATE_LIMIT_AUTH'
  | 'RATE_LIMIT_FEEDBACK'
  | 'RATE_LIMIT_VOICE';

interface RateLimiter { limit(options: { key: string }): Promise<{ success: boolean }> }

interface Rule { binding: RateLimitBinding; scope: string; period: number }

const encoder = new TextEncoder();

export function clientIp(request: Request): string {
  return request.headers.get('cf-connecting-ip')?.trim().slice(0, 64) || 'unknown';
}

/** Pseudonymous, stable per-client key for D1 counters. Raw IPs are never
 * stored; with a configured secret the key cannot be reversed by brute force. */
export async function clientFingerprint(env: any, value: string): Promise<string> {
  const secret = String(env?.WAYBI_CLIENT_KEY_SECRET || env?.EMAIL_OTP_SECRET || 'waybi-client-key-v1');
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(`client:${value}`)));
  return Array.from(signature.slice(0, 16), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function allowRequest(env: any, binding: RateLimitBinding, key: string): Promise<boolean> {
  const limiter = env?.[binding] as RateLimiter | undefined;
  if (!limiter || typeof limiter.limit !== 'function') return true;
  try {
    const outcome = await limiter.limit({ key });
    return outcome?.success !== false;
  } catch (error) {
    console.warn(JSON.stringify({ level: 'warn', event: 'rate_limiter_unavailable', binding,
      message: String((error as Error)?.message || error).slice(0, 200) }));
    return true;
  }
}

export function rateLimitedResponse(retryAfterSeconds = 60, message = 'Too many requests. Please retry shortly.') {
  return new Response(JSON.stringify({ error: message, code: 'RATE_LIMITED', retryAfter: retryAfterSeconds }), {
    status: 429,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'retry-after': String(retryAfterSeconds),
    },
  });
}

const RULES: Array<{ paths: string[]; methods?: string[]; rule: Rule }> = [
  { paths: ['/api/suggest', '/api/search', '/api/reverse'], methods: ['GET'],
    rule: { binding: 'RATE_LIMIT_SEARCH', scope: 'search', period: 60 } },
  { paths: ['/api/explore', '/api/place-details', '/api/place-photo', '/api/independent-place-details'], methods: ['GET'],
    rule: { binding: 'RATE_LIMIT_PLACES', scope: 'places', period: 60 } },
  // The Google UI Kit allowance is a shared monthly budget; one client must not drain it.
  { paths: ['/api/search/google/reserve'], methods: ['POST'],
    rule: { binding: 'RATE_LIMIT_PLACES', scope: 'google-ui-kit', period: 60 } },
  { paths: ['/api/route-options', '/api/route'], methods: ['GET'],
    rule: { binding: 'RATE_LIMIT_ROUTING', scope: 'routing', period: 60 } },
  { paths: ['/api/speed-limit'], methods: ['GET'],
    rule: { binding: 'RATE_LIMIT_SPEED_LIMIT', scope: 'speed-limit', period: 60 } },
  { paths: ['/api/auth/login', '/api/auth/register', '/api/auth/email/request'], methods: ['POST'],
    rule: { binding: 'RATE_LIMIT_AUTH', scope: 'auth', period: 60 } },
  { paths: ['/api/navigation-feedback', '/api/telemetry/usage', '/api/road-reports'], methods: ['POST'],
    rule: { binding: 'RATE_LIMIT_FEEDBACK', scope: 'feedback', period: 60 } },
];

export function rateLimitRule(pathname: string, method: string): Rule | null {
  for (const entry of RULES) {
    if (entry.paths.includes(pathname) && (!entry.methods || entry.methods.includes(method))) return entry.rule;
  }
  return null;
}

/** Returns a 429 response when the client exceeded its burst allowance. */
export async function guardApiRequest(request: Request, env: any): Promise<Response | null> {
  const rule = rateLimitRule(new URL(request.url).pathname, request.method);
  if (!rule) return null;
  const allowed = await allowRequest(env, rule.binding, `${rule.scope}:${clientIp(request)}`);
  return allowed ? null : rateLimitedResponse(rule.period);
}
