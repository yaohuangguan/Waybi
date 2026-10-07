import type { OfficialRoadEvent, OfficialRoadEventType, RoadEventState } from './types.ts';

interface NztaEvent {
  id?: unknown; status?: unknown; geometry?: unknown; impact?: unknown;
  eventType?: unknown; eventDescription?: unknown; eventComments?: unknown;
  locationArea?: unknown; startDate?: unknown; endDate?: unknown;
  eventModified?: unknown; eventCreated?: unknown; planned?: unknown;
  alternativeRoute?: unknown; expectedResolution?: unknown;
  region?: { name?: unknown }; journey?: { name?: unknown };
}
type RoadEventEnv = Pick<WorkerBindings, 'CAMERA_DATA'>;
// NZTA Traffic and Travel v4 stays inside this adapter.
export const ROAD_EVENTS_SOURCE = 'https://trafficnz.info/service/traffic/rest/4/events/all/10';
export const ROAD_EVENTS_SOURCE_PAGE = 'https://www.journeys.nzta.govt.nz/highway-conditions';
const CACHE_KEY = 'road-events/current';
const FRESH_MS = 5 * 60 * 1000;
const MAX_STALE_MS = 15 * 60 * 1000;
// Coalesce overlapping requests within a Worker isolate. Scheduled refreshes
// publish one shared snapshot to KV; App requests normally only read it.
const refreshes = new WeakMap<KVNamespace, Promise<RoadEventState>>();
const NZ_BOUNDS = { minLon: 166, maxLon: 179, minLat: -48, maxLat: -34 };

function text(value: unknown, limit = 400): string {
  return typeof value === 'string' ? value.trim().slice(0, limit) : '';
}

function geometryPoints(geometry: unknown) {
  if (typeof geometry !== 'string' || geometry.length > 100000) return null;
  const raw = [...geometry.matchAll(/(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/g)]
    .map((match) => ({
      longitude: Number(match[1]),
      latitude: Number(match[2])
    }))
    .filter((point) =>
      point.longitude > NZ_BOUNDS.minLon && point.longitude < NZ_BOUNDS.maxLon &&
      point.latitude > NZ_BOUNDS.minLat && point.latitude < NZ_BOUNDS.maxLat
    );
  if (!raw.length || raw.length > 5000) return null;

  const sampled = [];
  const push = (point) => {
    const previous = sampled.at(-1);
    if (!previous || previous.latitude !== point.latitude || previous.longitude !== point.longitude) {
      sampled.push(point);
    }
  };

  for (let index = 0; index < raw.length; index++) {
    const point = raw[index];
    if (index === 0) {
      push(point);
      continue;
    }
    const previous = raw[index - 1];
    const latScale = 111320;
    const lonScale = 111320 * Math.cos(((previous.latitude + point.latitude) / 2) * Math.PI / 180);
    const dy = (point.latitude - previous.latitude) * latScale;
    const dx = (point.longitude - previous.longitude) * lonScale;
    const metres = Math.hypot(dx, dy);
    const steps = Math.min(32, Math.max(1, Math.ceil(metres / 300)));
    for (let step = 1; step <= steps; step++) {
      const fraction = step / steps;
      push({
        latitude: previous.latitude + (point.latitude - previous.latitude) * fraction,
        longitude: previous.longitude + (point.longitude - previous.longitude) * fraction
      });
    }
  }

  if (sampled.length > 200) {
    const stride = (sampled.length - 1) / 199;
    return Array.from({ length: 200 }, (_, index) => sampled[Math.round(index * stride)]);
  }
  return sampled;
}

function geometryPosition(points) {
  if (!Array.isArray(points) || !points.length) return null;
  return points[Math.floor(points.length / 2)];
}

function eventType(event: NztaEvent): OfficialRoadEventType {
  const impact = text(event.impact).toLowerCase();
  const category = text(event.eventType).toLowerCase();
  const description = text(event.eventDescription).toLowerCase();
  const comments = text(event.eventComments).toLowerCase();
  const combined = `${category} ${description} ${comments}`;
  if (impact === 'road closed' || /road closure|closed to all traffic/.test(combined)) {
    return 'roadClosure';
  }
  if (/flood/.test(combined)) return 'flooding';
  if (/\bslip\b|landslide/.test(combined)) return 'slip';
  if (/road work|roadwork|road works|road construction|maintenance|pavement repair|resurfacing/.test(combined)) {
    return 'roadworks';
  }
  return 'incident';
}

function severity(event: NztaEvent, type: OfficialRoadEventType): OfficialRoadEvent['severity'] {
  const impact = text(event.impact).toLowerCase();
  if (type === 'roadClosure') return 'critical';
  if (type === 'flooding' || type === 'slip') return 'warning';
  if (/delay|caution|lane closed|stop\/go/.test(impact)) return 'warning';
  return 'advisory';
}

function directionHeading(roadName: string): number | null {
  // Ramp direction names describe the motorway joined, not the bearing of
  // the curved ramp itself. Applying that compass direction at the point can
  // wrongly suppress a closure on the exact ramp the driver will take.
  if (/\b(?:on|off)[ -]?ramp\b/i.test(roadName)) return null;
  const directions = [...roadName.matchAll(/\b(north|east|south|west)[ -]?bound\b/gi)];
  const unique = new Set(directions.map((match) => match[1].toLowerCase()));
  if (unique.size !== 1) return null;
  return { north: 0, east: 90, south: 180, west: 270 }[[...unique][0]];
}

export function normalizeRoadEvent(input: unknown, now = new Date()): OfficialRoadEvent | null {
  if (!input || typeof input !== 'object') return null;
  const event = input as NztaEvent;
  if (event.status !== 'Active' ||
      (typeof event.id !== 'string' && typeof event.id !== 'number')) return null;
  const geometry = geometryPoints(event.geometry);
  const location = geometryPosition(geometry);
  if (!location) return null;
  const from = Date.parse(text(event.startDate));
  const until = Date.parse(text(event.endDate));
  const time = now.getTime();
  if (Number.isFinite(from) && from > time) return null;
  if (Number.isFinite(until) && until <= time) return null;

  const type = eventType(event);
  const sourceId = String(event.id);
  return {
    id: `nzta:event:${sourceId}`,
    type,
    location,
    geometry,
    roadName: text(event.locationArea, 160) || text(event.journey?.name, 80) || null,
    headingDegrees: directionHeading(text(event.locationArea, 160)),
    severity: severity(event, type),
    confidence: text(event.geometry).startsWith('POINT') ? 0.95 : 0.75,
    observation: 'official',
    validFrom: Number.isFinite(from) ? new Date(from).toISOString() : null,
    validUntil: Number.isFinite(until) ? new Date(until).toISOString() : null,
    source: {
      provider: 'NZTA Traffic and Travel',
      country: 'NZ',
      region: text(event.region?.name, 80) || null,
      sourceId,
      updatedAt: text(event.eventModified) || text(event.eventCreated) || null
    },
    metadata: {
      description: text(event.eventDescription, 160),
      comments: text(event.eventComments, 400),
      impact: text(event.impact, 80),
      planned: event.planned === true,
      eventType: text(event.eventType, 80),
      alternativeRoute: text(event.alternativeRoute, 240),
      expectedResolution: text(event.expectedResolution, 120),
      geometryType: text(event.geometry, 24).split(' ')[0] || null
    }
  };
}

export async function fetchNztaRoadEvents(fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const response = await fetcher(ROAD_EVENTS_SOURCE, {
    headers: {
      accept: 'application/json',
      'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)'
    },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`NZTA road events HTTP ${response.status}`);
  const body = await response.json<{ response?: { roadevent?: unknown } }>();
  const raw = body?.response?.roadevent;
  if (!Array.isArray(raw)) throw new Error('NZTA road events payload is invalid');
  const events = raw.map((event) => normalizeRoadEvent(event, now)).filter(Boolean);
  return {
    events,
    source: ROAD_EVENTS_SOURCE_PAGE,
    checkedAt: now.toISOString(),
    retrievedAt: now.toISOString(),
    syncStatus: 'live',
    syncError: null
  };
}

export async function readRoadEventState(env: RoadEventEnv): Promise<RoadEventState | null> {
  return await env.CAMERA_DATA.get<RoadEventState>(CACHE_KEY, 'json');
}

function currentSnapshot(state: RoadEventState, now: Date): RoadEventState {
  const age = now.getTime() - Date.parse(state.retrievedAt || '');
  if (state.syncStatus === 'stale' && (!Number.isFinite(age) || age > MAX_STALE_MS)) {
    return { ...state, events: [], syncStatus: 'unavailable' };
  }
  return {
    ...state,
    events: (state.events ?? []).filter((event) => {
      const from = Date.parse(event.validFrom || '');
      const until = Date.parse(event.validUntil || '');
      return (!Number.isFinite(from) || from <= now.getTime()) &&
        (!Number.isFinite(until) || until > now.getTime());
    })
  };
}

export async function refreshRoadEventState(env: RoadEventEnv, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const pending = refreshes.get(env.CAMERA_DATA);
  if (pending) return currentSnapshot(await pending, now);
  const refresh = (async () => {
    const stored = await readRoadEventState(env);
    try {
      const live = await fetchNztaRoadEvents(fetcher, now);
      await env.CAMERA_DATA.put(CACHE_KEY, JSON.stringify(live));
      return live;
    } catch (error) {
      const retrievedAt = stored?.retrievedAt ??
        (stored?.syncStatus === 'live' ? stored.checkedAt : null);
      const age = now.getTime() - Date.parse(retrievedAt || '');
      const usable = Number.isFinite(age) && age >= 0 && age <= MAX_STALE_MS;
      const state = currentSnapshot({
        events: usable && Array.isArray(stored?.events) ? stored.events : [],
        source: ROAD_EVENTS_SOURCE_PAGE,
        retrievedAt,
        checkedAt: now.toISOString(),
        syncStatus: usable ? 'stale' : 'unavailable',
        syncError: String(error.message || error)
      }, now);
      // Cache failure attempts too, so an outage does not trigger a retry per
      // user. The original retrieval timestamp is never moved forward.
      await env.CAMERA_DATA.put(CACHE_KEY, JSON.stringify(state));
      return state;
    }
  })();
  refreshes.set(env.CAMERA_DATA, refresh);
  try { return await refresh; }
  finally { if (refreshes.get(env.CAMERA_DATA) === refresh) refreshes.delete(env.CAMERA_DATA); }
}

export async function loadRoadEventState(env: RoadEventEnv, fetcher: typeof fetch = fetch, now = new Date()): Promise<RoadEventState> {
  const stored = await readRoadEventState(env);
  const checked = Date.parse(stored?.checkedAt || '');
  const age = now.getTime() - checked;
  const fresh = Number.isFinite(age) && age >= 0 && age < FRESH_MS;
  if (fresh && Array.isArray(stored.events)) return currentSnapshot(stored, now);
  return refreshRoadEventState(env, fetcher, now);
}
