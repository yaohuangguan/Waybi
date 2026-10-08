/** Short-lived geocoding results, keyed by query, language and search area.
 * No account, history, route or authenticated response enters this cache.
 * Memory coalesces in-flight requests; the Workers Cache API shares completed
 * results between isolates at the same Cloudflare location.
 */
const TTL_MS = 5 * 60 * 1000;
const MAX_ENTRIES = 160;
type Cached = { at: number; body: string; headers: Headers };
type SearchContext = Pick<ExecutionContext, 'waitUntil'>;

export function suggestionCacheKey(query: string, point: number[] | null, language: string): string {
  return [
    query.trim().normalize('NFKC').toLowerCase(), language,
    point ? point[0].toFixed(2) : '', point ? point[1].toFixed(2) : '',
  ].join('|');
}

export class SuggestionCache {
  private memory = new Map<string, Cached>();
  private pending = new Map<string, Promise<Response>>();
  private edge: () => Cache | undefined;
  private now: () => number;

  constructor(
    edge: () => Cache | undefined = () =>
      typeof caches === 'undefined' ? undefined : (caches as CacheStorage & { default: Cache }).default,
    now: () => number = Date.now,
  ) { this.edge = edge; this.now = now; }

  private response(entry: Cached, cache: string): Response {
    const headers = new Headers(entry.headers);
    headers.set('x-waybi-search-cache', cache);
    headers.set('cache-control', 'no-store');
    return new Response(entry.body, { headers });
  }

  async load(key: string, loader: () => Promise<Response>, ctx?: SearchContext): Promise<Response> {
    const started = performance.now();
    const timed = (response: Response) => {
      const output = response.clone();
      output.headers.set('server-timing', `search;dur=${(performance.now() - started).toFixed(1)}`);
      return output;
    };
    const cached = this.memory.get(key);
    if (cached && this.now() - cached.at < TTL_MS) return timed(this.response(cached, 'MEMORY'));
    if (cached) this.memory.delete(key);
    const inFlight = this.pending.get(key);
    if (inFlight) return timed(await inFlight);

    const request = this.loadUncached(key, loader, ctx);
    this.pending.set(key, request);
    try { return timed(await request); }
    finally { if (this.pending.get(key) === request) this.pending.delete(key); }
  }

  private remember(key: string, entry: Cached) {
    if (this.memory.size >= MAX_ENTRIES) this.memory.delete(this.memory.keys().next().value);
    this.memory.set(key, entry);
  }

  private async loadUncached(key: string, loader: () => Promise<Response>, ctx?: SearchContext): Promise<Response> {
    let edge: Cache | undefined;
    let cacheRequest: Request | undefined;
    try {
      edge = this.edge();
      if (edge) {
        const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key));
        const id = Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2, '0')).join('');
        cacheRequest = new Request(`https://waybi.co/__suggestions/v1/${id}`);
        const hit = await edge.match(cacheRequest);
        if (hit) {
          const entry = { at: this.now(), body: await hit.text(), headers: hit.headers };
          this.remember(key, entry);
          return this.response(entry, 'EDGE');
        }
      }
    } catch { /* Cache failure never makes search unavailable. */ }

    const response = await loader();
    if (response.status !== 200) return response;
    const body = await response.clone().text();
    let results: unknown;
    try { results = JSON.parse(body); } catch { return response; }
    // A transient empty result must not prevent a retry for five minutes.
    if (!Array.isArray(results) || !results.length) return response;
    const entry = { at: this.now(), body, headers: response.headers };
    this.remember(key, entry);
    if (edge && cacheRequest) {
      const headers = new Headers(response.headers);
      headers.set('cache-control', `public, max-age=${TTL_MS / 1000}`);
      const destination = edge;
      const target = cacheRequest;
      const write = Promise.resolve().then(() =>
        destination.put(target, new Response(body, { headers }))
      ).catch(() => {});
      if (ctx) ctx.waitUntil(write);
      else await write;
    }
    return this.response(entry, 'MISS');
  }
}

export const independentSuggestionCache = new SuggestionCache();
