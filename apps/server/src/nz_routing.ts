import { validCoordinate, validNzCoordinate } from './geo.ts';
import type { LonLat, ProviderPayload, RouteRequestOptions } from './types.ts';
import type { ClosureLocation } from './routing_closures.ts';
import { cloudRunIdentityToken } from './cloud_run_auth.ts';
import { restoreValhallaGeometry } from './valhalla_geometry.ts';
import { reserveNzRoutingQuota } from './nz_routing_quota.ts';

export interface NzRoutingConfig {
  WAYBI_NZ_ROUTING_URL?: string;
  WAYBI_NZ_ROUTING_TOKEN?: string;
  /** Worker secret, never a client credential. Only run.invoker on this service. */
  WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT?: string;
  WAYBI_NZ_ROUTING_DAILY_LIMIT?: string;
  USER_DB?: any;
}

export function nzRoutingEndpoint(env: NzRoutingConfig, points: LonLat[]): URL | null {
  if (!env.WAYBI_NZ_ROUTING_URL || !points.every(p => validNzCoordinate(p[1], p[0]))) return null;
  const url = new URL(env.WAYBI_NZ_ROUTING_URL);
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
    throw new Error('NZ routing requires an HTTPS service endpoint');
  }
  if (url.username || url.password || url.search || url.hash) throw new Error('Invalid NZ routing endpoint');
  url.pathname = `${url.pathname.replace(/\/$/, '')}/route`;
  return url;
}

export async function fetchNzRouting(
  env: NzRoutingConfig, points: LonLat[], mode: string, options: RouteRequestOptions = {},
  exclusions: ClosureLocation[] = [], fetcher: typeof fetch = fetch,
): Promise<ProviderPayload> {
  const url = nzRoutingEndpoint(env, points);
  const costing = ({ DRIVE: 'auto', WALK: 'pedestrian', BICYCLE: 'bicycle' })[mode];
  if (!url || !costing) throw new Error('NZ routing unavailable for this request');
  if (exclusions.length > 128) throw new Error('Too many closed road segments for a reliable detour');
  // Identity exchange and routing share the existing fallback deadline.
  const signal = AbortSignal.timeout(exclusions.length ? 4000 : 5000);
  if (env.WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT && url.pathname !== '/route') {
    throw new Error('Cloud Run requires its canonical service endpoint');
  }
  const token = env.WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT
    ? await cloudRunIdentityToken(env.WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT, url.origin, signal, fetcher)
    : env.WAYBI_NZ_ROUTING_TOKEN;
  const body = valhallaRequest(points, mode, options, exclusions);
  // Native Cloud Run accepts polyline6. The separate Cloudflare container
  // gateway keeps its established GeoJSON validation and request contract.
  if (url.hostname.endsWith('.run.app')) body.shape_format = 'polyline6';
  const request = async (requestBody: ProviderPayload) => {
    if (env.WAYBI_NZ_ROUTING_DAILY_LIMIT != null) {
      await reserveNzRoutingQuota(env.USER_DB, env.WAYBI_NZ_ROUTING_DAILY_LIMIT);
    }
    const response = await fetcher(url, {
      method: 'POST', redirect: 'manual',
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(requestBody), signal,
    });
    if (!response.ok) throw new Error(`NZ routing HTTP ${response.status}`);
    const payload = await response.json<ProviderPayload>();
    if (payload.code !== 'Ok' || !payload.routes?.length) throw new Error('NZ routing returned no route');
    return restoreValhallaGeometry(payload);
  };
  const primary = await request(body);
  // Valhalla cannot produce native alternates with time-dependent routing.
  // Keep departure-time restrictions and discover routes using two moderate
  // time/distance cost mixes instead. Never relax access, closures or headings.
  if (mode !== 'DRIVE' || options.alternatives !== true || points.length !== 2 || options.detourLocalRoads) {
    return primary;
  }
  const routes = [...primary.routes];
  for (const use_distance of [.25, .5]) {
    if (signal.aborted) break;
    try {
      const candidate = await request({ ...body, costing_options: { auto: { use_distance } } });
      routes.push(...candidate.routes);
    } catch {
      // Exhausting the optional alternatives budget must not discard a good
      // owned-engine result or trigger the public fallback.
      break;
    }
  }
  return { ...primary, routes: distinctValhallaRoutes(routes) };
}

/** Collapse identical road geometry, including tiny coordinate noise. */
export function distinctValhallaRoutes(routes: ProviderPayload[]): ProviderPayload[] {
  const seen = new Set<string>();
  return routes.filter(route => {
    const coordinates = route.geometry?.coordinates;
    if (!Array.isArray(coordinates) || coordinates.length < 2 ||
      !coordinates.every(p => Array.isArray(p) && validCoordinate(p[1], p[0])) ||
      !Number.isFinite(route.distance) || !(route.distance > 0) ||
      !Number.isFinite(route.duration) || !(route.duration > 0)) return false;
    const cells: string[] = [];
    for (const [lon, lat] of coordinates) {
      const cell = `${Number(lon).toFixed(4)},${Number(lat).toFixed(4)}`;
      if (cell !== cells.at(-1)) cells.push(cell);
    }
    const key = cells.join(';');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((a, b) => a.duration - b.duration || a.distance - b.distance).slice(0, 3);
}

export function valhallaRequest(points: LonLat[], mode: string, options: RouteRequestOptions,
  exclusions: ClosureLocation[]) {
  const costing = ({ DRIVE: 'auto', WALK: 'pedestrian', BICYCLE: 'bicycle' })[mode];
  const heading = options.headingDegrees;
  return {
      locations: points.map(([lon, lat], index) => ({ lon, lat, type: 'break',
        ...(index === 0 && Number.isFinite(heading) ? { heading: ((heading % 360) + 360) % 360 } : {}) })),
      costing, format: 'osrm', shape_format: 'geojson', units: 'kilometers',
      language: options.language === 'zh' ? 'zh-CN' : 'en-GB',
      // Time-dependent native alternates are unsupported; fetched above.
      alternates: 0,
      directions_type: 'instructions', turn_lanes: true,
      // When successive exclusions still leave a closed motorway, attempt a
      // local-road-biased path; this is a cost preference, not a safety claim.
      ...(mode === 'DRIVE' && options.detourLocalRoads
        ? { costing_options: { auto: { use_highways: 0 } } } : {}),
      date_time: { type: 0 },
      ...(exclusions.length ? { exclude_locations: exclusions } : {}),
    };
}
