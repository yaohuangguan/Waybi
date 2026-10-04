import roadGeometry from '../data/traffic-road-geometry.json' with { type: 'json' };
import { distance } from './traffic_geometry.mjs';
import { trafficTileConfig } from './traffic_tiles.mjs';
export const TRAFFIC_FLOW_SOURCE =
  'https://trafficnz.info/service/traffic-conditions/rest/2';
export const TRAFFIC_FLOW_SOURCE_PAGE =
  'https://www.nzta.govt.nz/about-us/our-data-and-official-information/use-our-data/about-the-apis';

const CACHE_KEY = 'waybi:traffic-flow/v2';
const FRESH_MS = 10 * 60 * 1000;

function finite(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function trafficLevel(value) {
  const text = String(value || '').trim().toLowerCase();
  if (!text) return 'unknown';
  if (
    text.includes('free') ||
    text.includes('uncongested') ||
    text.includes('normal')
  ) {
    return 'free';
  }
  if (text.includes('moderate') || text.includes('medium')) return 'moderate';
  if (
    text.includes('heavy') ||
    text.includes('congested') ||
    text.includes('severe') ||
    text.includes('very slow')
  ) {
    return 'heavy';
  }
  if (text.includes('slow')) return 'moderate';
  return 'unknown';
}

function usableCoordinates(startLat, startLon, endLat, endLon) {
  return (
    startLat != null &&
    startLon != null &&
    endLat != null &&
    endLon != null &&
    startLat >= -48 &&
    startLat <= -34 &&
    endLat >= -48 &&
    endLat <= -34 &&
    startLon >= 166 &&
    startLon <= 179 &&
    endLon >= 166 &&
    endLon <= 179
  );
}

function segmentFromRaw(raw, motorwayName, fallbackId) {
  const startLat = finite(raw?.startLat);
  const startLon = finite(raw?.startLon ?? raw?.startLong);
  const endLat = finite(raw?.endLat);
  const endLon = finite(raw?.endLon ?? raw?.endLong);
  if (!usableCoordinates(startLat, startLon, endLat, endLon)) return null;
  const id = raw?.id == null ? fallbackId : raw.id;
  const congestion = String(raw?.congestion || 'Unknown').trim();
  return {
    id: `nzta:traffic:${id}`,
    motorway: String(motorwayName || raw?.motorway || '').trim(),
    name: String(raw?.name || motorwayName || 'Traffic segment').trim(),
    direction: String(raw?.direction || '').trim(),
    congestion,
    level: trafficLevel(congestion),
    start: { latitude: startLat, longitude: startLon },
    end: { latitude: endLat, longitude: endLon },
  };
}

export function normalizeTrafficFlow(payload, now = new Date()) {
  const conditions =
    payload?.getTrafficConditionsResponse?.trafficConditions ??
    payload?.trafficConditions;
  const motorways = Array.isArray(conditions?.motorways)
    ? conditions.motorways
    : [];
  const segments = [];

  for (const motorway of motorways) {
    const motorwayName = String(motorway?.name || '').trim();
    for (const raw of Array.isArray(motorway?.locations)
      ? motorway.locations
      : []) {
      const segment = segmentFromRaw(raw, motorwayName, segments.length);
      if (segment) segments.push(segment);
    }
  }

  if (!segments.length) {
    throw new Error('NZTA traffic conditions contained no usable segments');
  }

  return {
    segments,
    source: TRAFFIC_FLOW_SOURCE_PAGE,
    sourceUpdatedAt: conditions?.lastUpdated || null,
    checkedAt: now.toISOString(),
    syncStatus: 'live',
    syncError: null,
  };
}

function decodeXml(value) {
  return String(value ?? '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .trim();
}

function xmlBlocks(xml, tag) {
  const namespace = '(?:[A-Za-z_][\\w.-]*:)?';
  const pattern = new RegExp(
    `<${namespace}${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${namespace}${tag}>`,
    'gi',
  );
  return [...String(xml).matchAll(pattern)].map((match) => match[1]);
}

function xmlText(xml, ...tags) {
  for (const tag of tags) {
    const value = xmlBlocks(xml, tag)[0];
    if (value != null) return decodeXml(value.replace(/<[^>]+>/g, ''));
  }
  return '';
}

function xmlLocationObjects(xml) {
  const singular = xmlBlocks(xml, 'location').filter((block) =>
    /<(?:[A-Za-z_][\w.-]*:)?startLat(?:\s[^>]*)?>/i.test(block),
  );
  if (singular.length) return singular;
  return xmlBlocks(xml, 'locations').filter((block) =>
    /<(?:[A-Za-z_][\w.-]*:)?startLat(?:\s[^>]*)?>/i.test(block),
  );
}

/// trafficnz REST currently advertises a REST endpoint but responds with XML.
/// Keep JSON support for test fixtures/future content negotiation and parse the
/// namespaced XML response instead of assuming response.json().
export function normalizeTrafficFlowXml(xml, now = new Date()) {
  const segments = [];
  const seen = new Set();
  const motorwayCandidates = [
    ...xmlBlocks(xml, 'motorway'),
    ...xmlBlocks(xml, 'motorways'),
  ].filter((block) => /startLat/i.test(block));

  const groups = motorwayCandidates.length
    ? motorwayCandidates.map((block) => ({
        name: xmlText(block, 'name', 'motorwayName'),
        locations: xmlLocationObjects(block),
      }))
    : [{ name: '', locations: xmlLocationObjects(xml) }];

  for (const group of groups) {
    for (const block of group.locations) {
      const raw = {
        id: xmlText(block, 'id', 'reference'),
        name: xmlText(block, 'name', 'description'),
        direction: xmlText(block, 'direction'),
        congestion: xmlText(block, 'congestion', 'status'),
        startLat: xmlText(block, 'startLat', 'startLatitude'),
        startLon: xmlText(block, 'startLon', 'startLong', 'startLongitude'),
        endLat: xmlText(block, 'endLat', 'endLatitude'),
        endLon: xmlText(block, 'endLon', 'endLong', 'endLongitude'),
      };
      const segment = segmentFromRaw(raw, group.name, segments.length);
      if (!segment) continue;
      const key = [
        segment.start.latitude,
        segment.start.longitude,
        segment.end.latitude,
        segment.end.longitude,
        segment.name,
        segment.direction,
      ].join('|');
      if (seen.add(key)) segments.push(segment);
    }
  }

  if (!segments.length) {
    throw new Error('NZTA traffic conditions XML contained no usable segments');
  }

  return {
    segments,
    source: TRAFFIC_FLOW_SOURCE_PAGE,
    sourceUpdatedAt:
      xmlText(xml, 'lastUpdated', 'lastUpdate', 'updated') || null,
    checkedAt: now.toISOString(),
    syncStatus: 'live',
    syncError: null,
  };
}

export async function fetchNztaTrafficFlow(fetcher = fetch, now = new Date()) {
  const response = await fetcher(TRAFFIC_FLOW_SOURCE, {
    headers: {
      accept: 'application/xml, application/json;q=0.9',
      'user-agent':
        'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)',
    },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    throw new Error(`NZTA traffic flow HTTP ${response.status}`);
  }

  const raw = await response.text();
  const contentType = response.headers.get('content-type') || '';
  if (
    contentType.includes('json') ||
    raw.trimStart().startsWith('{') ||
    raw.trimStart().startsWith('[')
  ) {
    return normalizeTrafficFlow(JSON.parse(raw), now);
  }
  return normalizeTrafficFlowXml(raw, now);
}

export function withRoadGeometry(state, env = {}, now = new Date()) {
  const sourceAt = Date.parse(state.sourceUpdatedAt || '');
  const live = state.syncStatus === 'live' && Number.isFinite(sourceAt) && now.getTime() - sourceAt < 10 * 60 * 1000;
  return { ...state,
    syncStatus: live ? 'live' : 'stale',
    coverage: 'published-nzta-sections',
    tileOverlay: trafficTileConfig(env),
    geometryUpdatedAt: roadGeometry.generatedAt,
    segments: state.segments.map(segment => {
      const shape = roadGeometry.segments[segment.id];
      const start = [segment.start.longitude, segment.start.latitude], end = [segment.end.longitude, segment.end.latitude];
      const valid = shape && distance(start, shape.start) < 40 && distance(end, shape.end) < 40;
      return { ...segment, level: live ? segment.level : 'unknown',
        geometry: valid ? { type: 'LineString', coordinates: shape.coordinates } : null,
        geometryQuality: valid ? 'road-matched' : 'unmatched', source: 'nzta',
      };
    }),
  };
}

async function storedTrafficFlow(env) {
  return env.CAMERA_DATA.get(CACHE_KEY, 'json');
}

export async function readTrafficFlowState(env, now = new Date()) {
  const stored = await storedTrafficFlow(env);
  if (!Array.isArray(stored?.segments) || !stored.segments.length) return null;
  return withRoadGeometry(stored, env, now);
}

export async function refreshTrafficFlowState(
  env,
  fetcher = fetch,
  now = new Date(),
) {
  const stored = await storedTrafficFlow(env);
  try {
    const live = await fetchNztaTrafficFlow(fetcher, now);
    await env.CAMERA_DATA.put(CACHE_KEY, JSON.stringify(live));
    return withRoadGeometry(live, env, now);
  } catch (error) {
    if (Array.isArray(stored?.segments) && stored.segments.length) {
      return withRoadGeometry({
        ...stored,
        syncStatus: 'stale',
        syncError: String(error?.message || error),
      }, env, now);
    }
    throw error;
  }
}

export async function loadTrafficFlowState(
  env,
  fetcher = fetch,
  now = new Date(),
) {
  const stored = await storedTrafficFlow(env);
  const checked = Date.parse(stored?.checkedAt || '');
  const fresh =
    Number.isFinite(checked) && now.getTime() - checked < FRESH_MS;
  if (fresh && Array.isArray(stored?.segments) && stored.segments.length) {
    return withRoadGeometry(stored, env, now);
  }
  return refreshTrafficFlowState(env, fetcher, now);
}
