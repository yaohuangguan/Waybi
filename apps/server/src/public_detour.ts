import { valhallaRequest } from './nz_routing.ts';
import type { ClosureLocation } from './routing_closures.ts';
import type { LonLat, ProviderPayload, RouteRequestOptions } from './types.ts';

// Same FOSSGIS fair-use boundary as the existing OSRM fallback. Detours only,
// one upstream request, no key or paid SKU; coalesce retries and cache briefly.
const states = new WeakMap<typeof fetch, {
  pending: Map<string, Promise<ProviderPayload>>;
  cache: Map<string, { until: number; payload: ProviderPayload }>;
}>();
let slot = Promise.resolve();
let lastStart = 0;
let queued = 0;
export function fetchPublicDetour(points: LonLat[], options: RouteRequestOptions,
  exclusions: ClosureLocation[], fetcher: typeof fetch = fetch): Promise<ProviderPayload> {
  if (!exclusions.length || exclusions.length > 128) return Promise.reject(new Error('Invalid detour exclusions'));
  let state = states.get(fetcher);
  if (!state) {
    state = { pending: new Map(), cache: new Map() };
    states.set(fetcher, state);
  }
  const { pending, cache } = state;
  const body = JSON.stringify(valhallaRequest(points, 'DRIVE', options, exclusions));
  const cached = cache.get(body);
  if (cached && cached.until > Date.now()) return Promise.resolve(cached.payload);
  if (pending.has(body)) return pending.get(body)!;
  if (queued >= 4) return Promise.reject(new Error('Detour routing busy; retry shortly'));
  queued++;
  const reservation = slot.then(async () => {
    const delay = 1100 - (Date.now() - lastStart);
    if (delay > 0) await new Promise(resolve => setTimeout(resolve, delay));
    lastStart = Date.now();
  });
  slot = reservation.catch(() => {});
  const request = reservation.then(async () => {
    const response = await fetcher('https://valhalla1.openstreetmap.de/route', {
      method: 'POST', headers: { 'content-type': 'application/json',
        'user-agent': 'Waybi/1.0 (+https://github.com/yaohuangguan/Waybi)' },
      body, signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error(`Detour routing HTTP ${response.status}`);
    const payload = await response.json<ProviderPayload>();
    if (payload.code !== 'Ok' || !payload.routes?.length) throw new Error('No detour found');
    if (cache.size >= 32) cache.delete(cache.keys().next().value!);
    cache.set(body, { until: Date.now() + 30000, payload });
    return payload;
  }).finally(() => { pending.delete(body); queued--; });
  pending.set(body, request);
  return request;
}
