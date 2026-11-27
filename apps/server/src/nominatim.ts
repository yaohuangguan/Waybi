import { HttpError, UpstreamError } from './http_errors.ts';

/**
 * Public Nominatim allows at most one request per second per application.
 * Requests from one Worker isolate are serialized through a promise queue so
 * concurrent searches can no longer compute the same wait and fire together.
 * Each slot starts at least MIN_INTERVAL_MS after the previous one; a deep
 * queue is rejected instead of holding requests for many seconds.
 */
let minIntervalMs = 1050;
const MAX_QUEUED = 8;
export const NOMINATIM_HEADERS = {
  'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)',
  referer: 'https://github.com/yaohuangguan/Waybi',
  accept: 'application/json',
};

let tail: Promise<void> = Promise.resolve();
let lastStartedAt = 0;
let queued = 0;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export function scheduleNominatim<T>(task: () => Promise<T>): Promise<T> {
  if (queued >= MAX_QUEUED) {
    return Promise.reject(new HttpError(503, 'Address search is busy. Please retry shortly.', {
      code: 'SEARCH_BUSY', headers: { 'retry-after': '2' },
    }));
  }
  queued++;
  const slot = tail.then(async () => {
    const wait = Math.max(0, minIntervalMs - (Date.now() - lastStartedAt));
    if (wait) await sleep(wait);
    lastStartedAt = Date.now();
  });
  tail = slot.catch(() => {});
  return slot.then(task).finally(() => { queued--; });
}

/** Fetch a Nominatim JSON array; anything else is an upstream failure. */
export async function nominatimArray(url: string | URL, fetcher: typeof fetch = fetch): Promise<any[]> {
  return scheduleNominatim(async () => {
    const response = await fetcher(url, { headers: NOMINATIM_HEADERS, signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new UpstreamError(`Nominatim HTTP ${response.status}`);
    let body: unknown;
    try { body = await response.json(); }
    catch (error) { throw new UpstreamError('Nominatim returned invalid JSON', { cause: error }); }
    if (!Array.isArray(body)) throw new UpstreamError('Nominatim returned an unexpected payload');
    return body;
  });
}

/** Fetch a Nominatim JSON object (reverse geocoding). */
export async function nominatimObject(url: string | URL, fetcher: typeof fetch = fetch): Promise<Record<string, any>> {
  return scheduleNominatim(async () => {
    const response = await fetcher(url, { headers: NOMINATIM_HEADERS, signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new UpstreamError(`Nominatim HTTP ${response.status}`);
    let body: unknown;
    try { body = await response.json(); }
    catch (error) { throw new UpstreamError('Nominatim returned invalid JSON', { cause: error }); }
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new UpstreamError('Nominatim returned an unexpected payload');
    return body as Record<string, any>;
  });
}

export const __test = {
  reset(intervalMs = 1050) { tail = Promise.resolve(); lastStartedAt = 0; queued = 0; minIntervalMs = intervalMs; },
  get MIN_INTERVAL_MS() { return minIntervalMs; },
  MAX_QUEUED,
};
