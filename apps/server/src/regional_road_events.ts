import type { LonLat, RoadEventState } from './types.ts';
import { loadRoadEventState, readRoadEventState } from './road_events.ts';
import { loadNswRoadEventState, readNswRoadEventState } from './au_road_events.ts';

const sources = [
  { id: 'NZ', country: 'NZ', bounds: [166, -48, 179, -34], load: loadRoadEventState, read: readRoadEventState },
  { id: 'AU-NSW', country: 'AU', bounds: [140.9, -37.6, 153.7, -28.1], load: loadNswRoadEventState, read: readNswRoadEventState },
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

/** Routing reads shared snapshots only; a route request never fans out to the
 * upstream official feeds. Select all regions touched by the actual route. */
export async function readRouteRoadSnapshots(
  env: Pick<WorkerBindings, 'CAMERA_DATA'>, routes: { coordinates: LonLat[] }[], now = new Date(),
): Promise<{ events: RoadEventState['events']; status: string; retrievedAt: string | null; officialCoverage: string[] }> {
  if (!env.CAMERA_DATA) return { events: [], status: 'unavailable', retrievedAt: null, officialCoverage: [] };
  const selected = sources.filter(source => routes.some(route => route.coordinates.some(p =>
    p[0] >= source.bounds[0] && p[0] <= source.bounds[2] &&
    p[1] >= source.bounds[1] && p[1] <= source.bounds[3])));
  const loaded = await Promise.all(selected.map(async source => {
    try { return { source, state: await source.read(env) }; }
    catch { return { source, state: null }; }
  }));
  const useful = loaded.filter(({ state }) => {
    const age = now.getTime() - Date.parse(state?.retrievedAt || '');
    return state && state.syncStatus !== 'unavailable' && Number.isFinite(age) && age >= 0 && age <= 15 * 60000;
  });
  const dates = useful.map(({ state }) => state.retrievedAt).sort();
  return { events: useful.flatMap(({ state }) => state.events),
    status: useful.length !== loaded.length || !loaded.length ? 'unavailable' :
      useful.some(({ state }) => state.syncStatus === 'stale' ||
        now.getTime() - Date.parse(state.retrievedAt) > 5 * 60000) ? 'stale' : 'live',
    retrievedAt: dates[0] ?? null, officialCoverage: selected.map(source => source.id) };
}
