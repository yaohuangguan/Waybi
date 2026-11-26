/**
 * Small fetch wrapper shared by the web map. It turns HTTP and network
 * failures into an `ApiError` that says whether the user is offline or rate
 * limited (HTTP 429 with `retry-after`), so callers can back off instead of
 * flooding the user with error toasts.
 */
export type ApiGroup = 'search' | 'routing' | 'other';

export class ApiError extends Error {
  readonly status: number;
  readonly retryAfterMs: number | null;
  readonly offline: boolean;
  constructor(message: string, status: number, options: { retryAfterMs?: number | null; offline?: boolean } = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.retryAfterMs = options.retryAfterMs ?? null;
    this.offline = options.offline ?? false;
  }
  get rateLimited() { return this.status === 429; }
  /** Server-side trouble or throttling: worth retrying later, not the user's fault. */
  get transient() { return this.offline || this.status === 429 || this.status === 503 || this.status === 502 || this.status === 504; }
}

export function isAbortError(error: unknown) {
  return error instanceof DOMException ? error.name === 'AbortError' || error.name === 'TimeoutError'
    : (error as Error | null)?.name === 'AbortError';
}

/** Parses `retry-after` as delta-seconds or an HTTP date. Returns milliseconds, or null when absent/invalid. */
export function parseRetryAfter(value: string | null | undefined, now = Date.now()): number | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (/^\d+(\.\d+)?$/.test(trimmed)) return Math.min(Math.round(Number(trimmed) * 1000), 3_600_000);
  const date = Date.parse(trimmed);
  if (!Number.isFinite(date)) return null;
  return Math.max(0, Math.min(date - now, 3_600_000));
}

export function groupFor(path: string): ApiGroup {
  if (/^\/api\/(search|suggest)\b/.test(path)) return 'search';
  if (/^\/api\/(route-options|route)\b/.test(path)) return 'routing';
  return 'other';
}

/**
 * Remembers when the server asked us to slow down, per endpoint group, so no
 * request is even sent before `retry-after` has passed.
 */
export class RateLimitGate {
  private until = new Map<ApiGroup, number>();
  block(group: ApiGroup, ms: number, now = Date.now()) {
    if (group === 'other') return;
    this.until.set(group, Math.max(this.until.get(group) || 0, now + Math.max(1000, ms)));
  }
  remaining(group: ApiGroup, now = Date.now()) {
    return Math.max(0, (this.until.get(group) || 0) - now);
  }
  clear() { this.until.clear(); }
}

export const rateLimits = new RateLimitGate();
const DEFAULT_RATE_LIMIT_MS = 30_000;

export function isOffline() {
  try { return typeof navigator !== 'undefined' && navigator.onLine === false; } catch { return false; }
}

/** Fetches a Waybi API path and parses JSON, throwing an `ApiError` (or the abort error) on failure. */
export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const group = groupFor(path);
  const wait = rateLimits.remaining(group);
  if (wait > 0) throw new ApiError('Rate limited', 429, { retryAfterMs: wait });
  let response: Response;
  try {
    response = await fetch(path, init);
  } catch (error) {
    if (isAbortError(error)) throw error;
    throw new ApiError((error as Error)?.message || 'Network error', 0, { offline: true });
  }
  if (!response.ok) {
    const retryAfterMs = parseRetryAfter(response.headers.get('retry-after'));
    if (response.status === 429) rateLimits.block(group, retryAfterMs ?? DEFAULT_RATE_LIMIT_MS);
    const body = await response.json().catch(() => ({})) as { error?: string };
    throw new ApiError(body.error || `HTTP ${response.status}`, response.status, {
      retryAfterMs: response.status === 429 ? retryAfterMs ?? DEFAULT_RATE_LIMIT_MS : retryAfterMs
    });
  }
  return response.json() as Promise<T>;
}

/** Normalises any thrown value into an ApiError-like description. */
export function describeError(error: unknown): { offline: boolean; rateLimited: boolean; retryAfterMs: number | null; status: number; message: string } {
  if (error instanceof ApiError) {
    return { offline: error.offline || isOffline(), rateLimited: error.rateLimited, retryAfterMs: error.retryAfterMs, status: error.status, message: error.message };
  }
  const message = (error as Error | null)?.message || String(error);
  const offline = isOffline() || error instanceof TypeError;
  return { offline, rateLimited: false, retryAfterMs: null, status: 0, message };
}
