import { validNzCoordinate } from './geo.ts';
import type { LonLat, ProviderPayload, RouteRequestOptions } from './types.ts';
import type { ClosureLocation } from './routing_closures.ts';

export interface NzRoutingConfig {
  WAYBI_NZ_ROUTING_URL?: string;
  WAYBI_NZ_ROUTING_TOKEN?: string;
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
  const heading = options.headingDegrees;
  const response = await fetcher(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(env.WAYBI_NZ_ROUTING_TOKEN ? { authorization: `Bearer ${env.WAYBI_NZ_ROUTING_TOKEN}` } : {}),
    },
    body: JSON.stringify({
      locations: points.map(([lon, lat], index) => ({ lon, lat, type: 'break',
        ...(index === 0 && Number.isFinite(heading) ? { heading: ((heading % 360) + 360) % 360 } : {}) })),
      costing, format: 'osrm', shape_format: 'geojson', units: 'kilometers',
      language: options.language === 'zh' ? 'zh-CN' : 'en-GB',
      alternates: options.alternatives === false || points.length > 2 ? 0 : 2,
      directions_type: 'instructions', turn_lanes: true,
      date_time: { type: 0 },
      ...(exclusions.length ? { exclude_locations: exclusions } : {}),
    }),
    signal: AbortSignal.timeout(exclusions.length ? 4000 : 5000),
  });
  if (!response.ok) throw new Error(`NZ routing HTTP ${response.status}`);
  const payload = await response.json<ProviderPayload>();
  if (payload.code !== 'Ok' || !payload.routes?.length) throw new Error('NZ routing returned no route');
  return payload;
}
