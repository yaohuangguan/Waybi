import type { LonLat, RoadEventState } from './types.ts';
import { loadRoadEventState } from './road_events.ts';
import { loadNswRoadEventState } from './au_road_events.ts';

const sources = [
  { id: 'NZ', country: 'NZ', bounds: [166, -48, 179, -34], load: loadRoadEventState },
  { id: 'AU-NSW', country: 'AU', bounds: [140.9, -37.6, 153.7, -28.1], load: loadNswRoadEventState },
] as const;

/** Select by the requested map/route area, not account country or nationality. */
export async function loadRegionalRoadEvents(
  env: Pick<WorkerBindings, 'CAMERA_DATA'>,
  point: LonLat | null, country = 'NZ', fetcher: typeof fetch = fetch, now = new Date(),
): Promise<RoadEventState & { officialCoverage: string[] }> {
  const source = sources.find(source => point ?
    point[0] >= source.bounds[0] && point[0] <= source.bounds[2] &&
    point[1] >= source.bounds[1] && point[1] <= source.bounds[3] : source.country === country);
  if (!source) return { events: [], officialCoverage: [], source: '', checkedAt: now.toISOString(),
    retrievedAt: null, syncStatus: 'unavailable', syncError: null };
  return { ...await source.load(env, fetcher, now), officialCoverage: [source.id] };
}
