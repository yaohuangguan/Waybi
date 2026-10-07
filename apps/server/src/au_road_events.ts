import type { OfficialRoadEvent, RoadEventState, GeoPoint } from './types.ts';
import { validCoordinate } from './geo.ts';

/** Transport for NSW's published GeoJSON feed. AU coverage starts with NSW;
 * additional state sources join this adapter registry as they are validated.
 * Source and licence: https://opendata.transport.nsw.gov.au/data/dataset/live-traffic-hazards
 */
export const NSW_SOURCE_PAGE = 'https://opendata.transport.nsw.gov.au/data/dataset/live-traffic-hazards';
const FEEDS = ['incident', 'roadwork', 'flood'].map(kind =>
  `https://data.livetraffic.com/traffic/hazards/${kind}-open.json`);
const KEY = 'road-events/au-nsw/current';
type Env = Pick<WorkerBindings, 'CAMERA_DATA'>;
type JsonObject = Record<string, unknown>;
const pending = new WeakMap<KVNamespace, Promise<RoadEventState>>();
const text = (value: unknown, max = 400) => typeof value === 'string' ?
  value.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim().slice(0, max) : '';
const object = (value: unknown): JsonObject => value && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
const objects = (value: unknown): JsonObject[] => Array.isArray(value) ? value.map(object) : [];
function timestamp(value: unknown): string | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

export function normalizeNswRoadEvent(input: unknown, now = new Date()): OfficialRoadEvent | null {
  const feature = object(input), p = object(feature.properties), g = object(feature.geometry);
  if (feature.type !== 'Feature' || p.ended === true ||
      (typeof feature.id !== 'string' && typeof feature.id !== 'number')) return null;
  const coordinates = g.coordinates;
  if (g.type !== 'Point' || !Array.isArray(coordinates) ||
      typeof coordinates[0] !== 'number' || typeof coordinates[1] !== 'number' ||
      !validCoordinate(coordinates[1], coordinates[0])) return null;
  const location: GeoPoint = { longitude: coordinates[0], latitude: coordinates[1] };
  if (location.longitude < 140 || location.longitude > 154 || location.latitude < -38 || location.latitude > -27) return null;
  const from = timestamp(p.start), until = timestamp(p.end);
  if ((from && Date.parse(from) > now.getTime()) || (until && Date.parse(until) <= now.getTime())) return null;
  // An open planned event can contain periods not active at this time. Do not
  // call its road closed unless the publisher says it affects the network now.
  if (p.incidentKind === 'Planned' && p.impactingNetwork !== true) return null;
  const periods = objects(p.periods), roads = objects(p.roads);
  const closed = periods.some(period => period.closureType === 'ROAD_CLOSURE');
  const category = text(p.mainCategory).toLowerCase();
  const type = closed ? 'roadClosure' : /flood/.test(category) ? 'flooding' :
    /roadwork|road work/.test(category) ? 'roadworks' : 'incident';
  const directions = new Set(periods.map(period => text(period.direction).toLowerCase()).filter(Boolean));
  const singleDirection = directions.size === 1 ? [...directions][0] : '';
  const headings = { northbound: 0, eastbound: 90, southbound: 180, westbound: 270 };
  const roadName = roads.map(road => text(road.mainStreet, 160)).filter(Boolean).join(' / ').slice(0, 160);
  return {
    id: `tfnsw:event:${feature.id}`, type, location, geometry: [],
    roadName: roadName || null,
    headingDegrees: /\b(?:on|off)[ -]?ramp\b/i.test(roadName) ? null : headings[singleDirection] ?? null,
    severity: closed ? 'critical' : p.isMajor === true || type === 'flooding' ? 'warning' : 'advisory',
    observation: 'official', confidence: .9, validFrom: from, validUntil: until,
    source: { provider: 'Transport for NSW', country: 'AU', region: 'NSW', sourceId: String(feature.id), updatedAt: timestamp(p.lastUpdated) },
    metadata: {
      description: text(p.displayName || p.headline || p.mainCategory, 160),
      comments: [text(p.otherAdvice), text(p.adviceA), text(p.adviceB)].filter(Boolean).join(' · ').slice(0, 600),
      alternativeRoute: text(p.diversions, 400), planned: p.incidentKind === 'Planned',
      geometryType: 'POINT', impact: closed ? 'Road closed' : text(p.mainCategory, 80),
      sourceUrl: NSW_SOURCE_PAGE,
    },
  };
}

export async function fetchNswRoadEvents(fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const batches = await Promise.all(FEEDS.map(async url => {
    const response = await fetcher(url, { headers: { accept: 'application/json', 'user-agent': 'Waybi/1.0 (+https://waybi.co)' }, signal: AbortSignal.timeout(12000) });
    if (!response.ok) throw new Error(`TfNSW HTTP ${response.status}`);
    const body = await response.json<JsonObject>();
    if (body.type !== 'FeatureCollection' || !Array.isArray(body.features)) throw new Error('Invalid TfNSW feed');
    return body.features.slice(0, 3000).map(item => normalizeNswRoadEvent(item, now)).filter((e): e is OfficialRoadEvent => e !== null);
  }));
  const events = [...new Map(batches.flat().map(event => [event.id, event])).values()];
  return { events, source: NSW_SOURCE_PAGE, checkedAt: now.toISOString(), retrievedAt: now.toISOString(), syncStatus: 'live', syncError: null };
}

function current(state: RoadEventState, now: Date): RoadEventState {
  const age = now.getTime() - Date.parse(state.retrievedAt || '');
  if (state.syncStatus === 'stale' && (!Number.isFinite(age) || age > 15 * 60000)) return { ...state, events: [], syncStatus: 'unavailable' };
  return { ...state, events: state.events.filter(event =>
    (!event.validFrom || Date.parse(event.validFrom) <= now.getTime()) &&
    (!event.validUntil || Date.parse(event.validUntil) > now.getTime())) };
}

export async function refreshNswRoadEventState(env: Env, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const existing = pending.get(env.CAMERA_DATA);
  if (existing) return current(await existing, now);
  const job = (async () => {
    const stored = await env.CAMERA_DATA.get<RoadEventState>(KEY, 'json');
    let state: RoadEventState;
    try { state = await fetchNswRoadEvents(fetcher, now); }
    catch (error) {
      const age = now.getTime() - Date.parse(stored?.retrievedAt || '');
      const usable = Number.isFinite(age) && age >= 0 && age <= 15 * 60000;
      state = current({ events: usable ? stored.events : [], source: NSW_SOURCE_PAGE,
        checkedAt: now.toISOString(), retrievedAt: stored?.retrievedAt ?? null,
        syncStatus: usable ? 'stale' : 'unavailable', syncError: String(error.message || error) }, now);
    }
    await env.CAMERA_DATA.put(KEY, JSON.stringify(state));
    return state;
  })();
  pending.set(env.CAMERA_DATA, job);
  try { return await job; }
  finally { if (pending.get(env.CAMERA_DATA) === job) pending.delete(env.CAMERA_DATA); }
}

export async function loadNswRoadEventState(env: Env, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const stored = await env.CAMERA_DATA.get<RoadEventState>(KEY, 'json');
  const age = now.getTime() - Date.parse(stored?.checkedAt || '');
  if (Number.isFinite(age) && age >= 0 && age < 5 * 60000) return current(stored, now);
  return refreshNswRoadEventState(env, fetcher, now);
}
