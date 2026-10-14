import type { LonLat, ProviderPayload, RouteRequestOptions } from './types.ts';

export interface OsrmFallbackConfig {
  WAYBI_OSRM_URL?: string;
  WAYBI_OSRM_TOKEN?: string;
  WAYBI_DISABLE_PUBLIC_ROUTING?: string;
}

type CacheEntry = { until: number; payload: ProviderPayload };
const states = new WeakMap<typeof fetch, {
  pending: Map<string, Promise<ProviderPayload>>;
  cache: Map<string, CacheEntry>;
}>();

export function configuredOsrmRoute(env: OsrmFallbackConfig, points: LonLat[],
  mode: string, options: RouteRequestOptions = {}) {
  const profiles: Record<string, string> = { DRIVE: 'driving', WALK: 'walking', BICYCLE: 'cycling' };
  const profile = profiles[mode];
  if (!profile) throw new Error('Unsupported independent travel mode');
  const coordinates = points.map(([lon, lat]) => String(lon) + ',' + String(lat)).join(';');
  let url: URL;
  let kind: 'managed' | 'public' = 'public';
  if (env.WAYBI_OSRM_URL) {
    const base = new URL(env.WAYBI_OSRM_URL);
    if ((base.protocol !== 'https:' &&
        !(base.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(base.hostname))) ||
      base.username || base.password || base.search || base.hash) {
      throw new Error('Managed OSRM endpoint must be HTTPS without credentials or query');
    }
    url = new URL(base.origin + base.pathname.replace(/\/$/, '') + '/route/v1/' + profile + '/' + coordinates);
    kind = 'managed';
  } else {
    if (env.WAYBI_DISABLE_PUBLIC_ROUTING === 'true') {
      throw new Error('Independent routing temporarily unavailable: configure an owned or licensed provider');
    }
    const publicProfile = ({ DRIVE: 'car', WALK: 'foot', BICYCLE: 'bike' } as Record<string, string>)[mode];
    url = new URL('https://routing.openstreetmap.de/routed-' + publicProfile +
      '/route/v1/driving/' + coordinates);
  }
  url.searchParams.set('overview', 'full');
  url.searchParams.set('geometries', 'geojson');
  url.searchParams.set('steps', 'true');
  url.searchParams.set('alternatives', points.length > 2 || options.alternatives === false ? 'false' : '3');
  if (Number.isFinite(options.headingDegrees)) {
    const heading = options.headingDegrees as number;
    const normalized = Math.round(((heading % 360) + 360) % 360);
    url.searchParams.set('bearings', [String(normalized) + ',60', ...points.slice(1).map(()=>'')].join(';'));
  }
  const headers: Record<string,string> = {
    accept: 'application/json',
    'user-agent': 'Waybi/1.0 (+https://waybi.co)',
  };
  if (kind === 'managed' && env.WAYBI_OSRM_TOKEN) headers.authorization = 'Bearer ' + env.WAYBI_OSRM_TOKEN;
  if (kind === 'public') headers.referer = 'https://routing.openstreetmap.de/';
  return { url, headers, kind };
}

/** Per-instance coalescing helps latency, NOT global public-server quota compliance. */
export function fetchOsrmFallback(env: OsrmFallbackConfig, points: LonLat[],
  mode: string, options: RouteRequestOptions = {}, fetcher: typeof fetch = fetch):
  Promise<{ payload: ProviderPayload; kind: 'managed' | 'public' }> {
  const request = configuredOsrmRoute(env, points, mode, options);
  let state = states.get(fetcher);
  if (!state) {
    state = { pending: new Map(), cache: new Map() };
    states.set(fetcher, state);
  }
  const key = String(request.url) + '|' + request.kind + '|' + (env.WAYBI_OSRM_TOKEN || '');
  const cached = state.cache.get(key);
  if (cached && cached.until > Date.now()) return Promise.resolve({payload:cached.payload, kind:request.kind});
  const waiting = state.pending.get(key);
  if (waiting) return waiting.then(payload=>({payload,kind:request.kind}));
  if (state.pending.size >= 8) return Promise.reject(new Error('Routing busy; retry shortly'));
  const promise = (async()=>{
    const res = await fetcher(request.url, { headers: request.headers, signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error('Routing upstream HTTP ' + res.status);
    const payload = await res.json<ProviderPayload>();
    if (payload.code !== 'Ok' || !payload.routes?.length) throw new Error('No usable upstream route');
    if (state!.cache.size >= 64) state!.cache.delete(state!.cache.keys().next().value!);
    state!.cache.set(key,{until:Date.now()+3000,payload});
    return payload;
  })().finally(()=>state!.pending.delete(key));
  state.pending.set(key,promise);
  return promise.then(payload=>({payload,kind:request.kind}));
}
