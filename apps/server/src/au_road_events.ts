import type { OfficialRoadEvent, RoadEventState, GeoPoint } from './types.ts';
import { validCoordinate } from './geo.ts';
import { currentOrUpcoming, SCHEDULED_WINDOW_MS } from './road_events.ts';

/** Transport for NSW's published GeoJSON feed. AU coverage starts with NSW;
 * additional state sources join this adapter registry as they are validated.
 * Source and licence: https://opendata.transport.nsw.gov.au/data/dataset/live-traffic-hazards
 */
export const NSW_SOURCE_PAGE = 'https://opendata.transport.nsw.gov.au/data/dataset/live-traffic-hazards';
const FEED_KINDS = ['incident', 'roadwork', 'flood'] as const;
const feedUrl = (kind: string) => `https://data.livetraffic.com/traffic/hazards/${kind}-open.json`;
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
  const upcoming = Boolean(from && Date.parse(from) > now.getTime());
  // Keep events scheduled to start within the window (with their start time);
  // consumers that need only active events filter by validFrom themselves.
  if ((from && Date.parse(from) > now.getTime() + SCHEDULED_WINDOW_MS) || (until && Date.parse(until) <= now.getTime())) return null;
  // An open planned event can contain periods not active at this time. Do not
  // call its road closed unless the publisher says it affects the network now.
  if (p.incidentKind === 'Planned' && p.impactingNetwork !== true && !upcoming) return null;
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

/**
 * Fetch the three TfNSW feeds independently. One failing feed no longer
 * discards the other two: its events from the previous snapshot are retained
 * while that snapshot is recent, and the failure is reported in failedFeeds.
 * Only when every feed fails is the refresh treated as a failure.
 */
export async function fetchNswRoadEvents(fetcher: typeof fetch = fetch, now = new Date(),
  previous: RoadEventState | null = null): Promise<RoadEventState> {
  const settled = await Promise.allSettled(FEED_KINDS.map(async kind => {
    const response = await fetcher(feedUrl(kind), { headers: { accept: 'application/json', 'user-agent': 'Waybi/1.0 (+https://waybi.co)' }, signal: AbortSignal.timeout(12000) });
    if (!response.ok) throw new Error(`TfNSW ${kind} HTTP ${response.status}`);
    const body = await response.json<JsonObject>();
    if (body.type !== 'FeatureCollection' || !Array.isArray(body.features)) throw new Error(`Invalid TfNSW ${kind} feed`);
    return body.features.slice(0, 3000).map(item => normalizeNswRoadEvent(item, now))
      .filter((e): e is OfficialRoadEvent => e !== null)
      .map(event => ({ ...event, metadata: { ...event.metadata, feed: kind } }));
  }));
  const failedFeeds = FEED_KINDS.filter((_, index) => settled[index].status === 'rejected');
  if (failedFeeds.length === FEED_KINDS.length) {
    throw new Error(`TfNSW feeds unavailable: ${settled.map(result =>
      result.status === 'rejected' ? String(result.reason?.message || result.reason) : '').join('; ')}`);
  }
  const fresh = settled.flatMap(result => result.status === 'fulfilled' ? result.value : []);
  const previousAge = now.getTime() - Date.parse(previous?.retrievedAt || '');
  const retained = failedFeeds.length && Number.isFinite(previousAge) && previousAge >= 0 && previousAge <= 15 * 60000
    ? (previous?.events || []).filter(event => failedFeeds.includes(event.metadata?.feed as typeof FEED_KINDS[number]))
    : [];
  if (failedFeeds.length) {
    console.warn(JSON.stringify({ level: 'warn', event: 'tfnsw_feed_failed', failedFeeds, retainedEvents: retained.length }));
  }
  const events = [...new Map([...retained, ...fresh].map(event => [event.id, event])).values()];
  return { events, source: NSW_SOURCE_PAGE, checkedAt: now.toISOString(), retrievedAt: now.toISOString(), syncStatus: 'live',
    syncError: failedFeeds.length ? `TfNSW feeds unavailable: ${failedFeeds.join(', ')}` : null,
    ...(failedFeeds.length ? { failedFeeds: [...failedFeeds] } : {}) };
}

function current(state: RoadEventState, now: Date): RoadEventState {
  const age = now.getTime() - Date.parse(state.retrievedAt || '');
  if (state.syncStatus === 'stale' && (!Number.isFinite(age) || age > 15 * 60000)) return { ...state, events: [], syncStatus: 'unavailable' };
  return { ...state, events: state.events.filter(event => currentOrUpcoming(event, now)),
    scheduledWindowHours: SCHEDULED_WINDOW_MS / 3600000 };
}

export async function refreshNswRoadEventState(env: Env, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const existing = pending.get(env.CAMERA_DATA);
  if (existing) return current(await existing, now);
  const job = (async () => {
    const stored = await env.CAMERA_DATA.get<RoadEventState>(KEY, 'json');
    let state: RoadEventState;
    try { state = await fetchNswRoadEvents(fetcher, now, stored); }
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

export async function readNswRoadEventState(env: Env): Promise<RoadEventState | null> {
  return env.CAMERA_DATA.get<RoadEventState>(KEY, 'json');
}

export async function loadNswRoadEventState(env: Env, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const stored = await env.CAMERA_DATA.get<RoadEventState>(KEY, 'json');
  const age = now.getTime() - Date.parse(stored?.checkedAt || '');
  // NSW is refreshed by the 10-minute Cron; avoid extra writes on hot paths.
  if (Number.isFinite(age) && age >= 0 && age < 12 * 60000) return current(stored, now);
  return refreshNswRoadEventState(env, fetcher, now);
}
