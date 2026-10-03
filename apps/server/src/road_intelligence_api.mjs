import { userFromRequest } from './auth.mjs';
import { loadRoadEventState, ROAD_EVENTS_SOURCE_PAGE } from './road_events.mjs';
import { validCoordinate } from './geo.mjs';

const ROOT = '/api/v1/road-intelligence';
const encoder = new TextEncoder();
const NZTA_TERMS = 'https://www.nzta.govt.nz/about-us/our-data-and-official-information/use-our-data/terms-of-use';
export const capabilities = {
  apiVersion: '1', stage: 'preview', coverage: 'global', sourceCoverage: { officialRoadEvents: ['NZ'], userReports: 'global' }, cameraCoverage: ['NZ'],
  features: ['bbox', 'nearby', 'route-corridor', 'api-keys', 'quotas', 'source-freshness'],
  limits: { dailyRequests: 1000, requestsPerMinute: 60, resultsPerPage: 100, routePoints: 250 },
  dataUse: { commercialRedistribution: false, attributionRequired: true,
    note: 'Free evaluation. NZTA source data is not licensed here for paid resale. Obtain appropriate source permissions before a paid B2B launch.', termsUrl: NZTA_TERMS },
};

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: {
    'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
    'access-control-allow-origin': '*', ...extra,
  } });
}
function failure(code, message, status) { return json({ error: { code, message } }, status); }
function number(value) {
  if (value == null || value === '' || typeof value === 'boolean') return null;
  const n = Number(value); return Number.isFinite(n) ? n : null;
}
function point(value) {
  if (!Array.isArray(value) || value.length !== 2) return null;
  const [longitude, latitude] = value.map(number);
  return validCoordinate(latitude, longitude) ? { longitude, latitude } : null;
}
function metres(a, b) {
  return Math.hypot((a.latitude - b.latitude) * 111320,
    (a.longitude - b.longitude) * 111320 * Math.cos((a.latitude + b.latitude) * Math.PI / 360));
}
export function project(point, route) {
  let best = null, along = 0;
  for (let i = 1; i < route.length; i++) {
    const a = route[i - 1], b = route[i];
    const x = 111320 * Math.cos(point.latitude * Math.PI / 180), y = 111320;
    const ax = (a.longitude - point.longitude) * x, ay = (a.latitude - point.latitude) * y;
    const dx = (b.longitude - a.longitude) * x, dy = (b.latitude - a.latitude) * y;
    const length = Math.hypot(dx, dy);
    const t = length === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / (length * length)));
    const offset = Math.hypot(ax + dx * t, ay + dy * t);
    if (!best || offset < best.offset) best = { offset, along: along + length * t };
    along += length;
  }
  return best;
}

export function queryEvents(events, query, now = Date.now()) {
  return events.flatMap((event) => {
    const from = Date.parse(event.validFrom), until = Date.parse(event.validUntil);
    if ((Number.isFinite(from) && from > now) || (Number.isFinite(until) && until <= now)) return [];
    if (query.types?.length && !query.types.includes(event.type)) return [];
    const locations = event.geometry?.length ? event.geometry : [event.location];
    if (query.bbox) {
      const [west, south, east, north] = query.bbox;
      return locations.some((p) => p.longitude >= west && p.longitude <= east && p.latitude >= south && p.latitude <= north) ? [event] : [];
    }
    if (query.near) {
      const distance = Math.min(...locations.map((p) => metres(p, query.near)));
      return distance <= query.radius ? [{ ...event, distanceMeters: Math.round(distance) }] : [];
    }
    const match = locations.map((p) => project(p, query.route)).filter(Boolean).sort((a, b) => a.offset - b.offset)[0];
    return match && match.offset <= query.buffer ? [{ ...event, distanceFromRouteMeters: Math.round(match.offset), distanceAlongRouteMeters: Math.round(match.along) }] : [];
  }).sort((a, b) => (a.distanceAlongRouteMeters ?? a.distanceMeters ?? 0) - (b.distanceAlongRouteMeters ?? b.distanceMeters ?? 0) || a.id.localeCompare(b.id));
}

async function hash(value) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))), (v) => v.toString(16).padStart(2, '0')).join('');
}
async function body(request) {
  if (Number(request.headers.get('content-length')) > 24000) return null;
  const reader = request.body?.getReader();
  if (!reader) return null;
  const chunks = []; let size = 0;
  for (;;) {
    const part = await reader.read(); if (part.done) break;
    size += part.value.byteLength;
    if (size > 24000) { await reader.cancel(); return null; }
    chunks.push(part.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const raw = new TextDecoder().decode(bytes);
  try { const value = JSON.parse(raw); return value && !Array.isArray(value) && typeof value === 'object' ? value : null; }
  catch { return null; }
}

async function manageKeys(request, env, url) {
  const user = await userFromRequest(env.USER_DB, request);
  if (!user) return failure('unauthenticated', 'Sign in to manage API keys', 401);
  const id = url.pathname.slice(`${ROOT}/keys/`.length);
  if (request.method === 'DELETE' && url.pathname.startsWith(`${ROOT}/keys/`)) {
    const result = await env.USER_DB.prepare('UPDATE road_api_keys SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL')
      .bind(Date.now(), id, user.id).run();
    return result.meta.changes ? json({ revoked: true }) : failure('not-found', 'Key not found', 404);
  }
  if (url.pathname !== `${ROOT}/keys`) return failure('not-found', 'Endpoint not found', 404);
  if (request.method === 'GET') {
    const result = await env.USER_DB.prepare('SELECT id, name, key_prefix AS prefix, created_at AS createdAt, expires_at AS expiresAt, revoked_at AS revokedAt FROM road_api_keys WHERE user_id = ? ORDER BY created_at DESC').bind(user.id).all();
    return json({ keys: result.results });
  }
  if (request.method !== 'POST') return failure('method-not-allowed', 'Use GET, POST or DELETE', 405);
  const input = await body(request);
  const name = typeof input?.name === 'string' ? input.name.trim().slice(0, 80) : '';
  if (!name) return failure('invalid-request', 'name is required', 400);
  const idValue = crypto.randomUUID();
  const random = Array.from(crypto.getRandomValues(new Uint8Array(32)), (n) => n.toString(16).padStart(2, '0')).join('');
  const token = `klri_${random}`;
  const created = Date.now(), expires = created + 90 * 86400000;
  // Conditional insert atomically enforces five active keys per account.
  const saved = await env.USER_DB.prepare(`INSERT INTO road_api_keys (id, user_id, name, key_hash, key_prefix, created_at, expires_at)
    SELECT ?, ?, ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM road_api_keys WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?) < 5`)
    .bind(idValue, user.id, name, await hash(token), token.slice(0, 13), created, expires, user.id, created).run();
  return saved.meta.changes ? json({ id: idValue, name, key: token, createdAt: created, expiresAt: expires, scope: 'preview:read', showOnce: true }, 201)
    : failure('key-limit', 'Revoke an existing key before creating another', 409);
}

async function authorize(request, db, now) {
  const token = request.headers.get('authorization')?.match(/^Bearer (klri_[a-f0-9]{64})$/)?.[1];
  if (!token) return { response: failure('unauthenticated', 'A Road Intelligence bearer key is required', 401) };
  const key = await db.prepare('SELECT id FROM road_api_keys WHERE key_hash = ? AND revoked_at IS NULL AND expires_at > ?').bind(await hash(token), now).first();
  if (!key) return { response: failure('invalid-key', 'Key is invalid, expired or revoked', 401) };
  const windows = [{ name: 'day', start: Math.floor(now / 86400000) * 86400000, limit: 1000, seconds: 86400 },
    { name: 'minute', start: Math.floor(now / 60000) * 60000, limit: 60, seconds: 60 }];
  const results = await db.batch(windows.map((w) => db.prepare(`INSERT INTO road_api_usage (key_id, window_type, window_start, requests)
    VALUES (?, ?, ?, 1) ON CONFLICT(key_id, window_type, window_start) DO UPDATE SET requests = requests + 1
    WHERE requests < ? RETURNING requests`).bind(key.id, w.name, w.start, w.limit)));
  const denied = results.findIndex((r) => !r.results?.length);
  if (denied >= 0) return { response: json({ error: { code: 'rate-limited', message: 'Preview request quota exceeded' } }, 429,
    { 'retry-after': String(Math.ceil((windows[denied].start + windows[denied].seconds * 1000 - now) / 1000)) }) };
  return { key, headers: { 'x-ratelimit-limit': '1000', 'x-ratelimit-remaining': String(1000 - results[0].results[0].requests),
    'x-ratelimit-reset': String((windows[0].start + 86400000) / 1000) } };
}

export function normalizeSnapshot(cameras, roads, now = Date.now()) {
  const cameraTime = cameras.sourceUpdatedAt ?? cameras.checkedAt ?? null;
  const roadTime = roads.retrievedAt ?? (roads.syncStatus === 'live' ? roads.checkedAt : null);
  const sources = [
    { id: 'nzta-cameras', attribution: 'NZ Transport Agency Waka Kotahi', url: cameras.source ?? 'https://www.nzta.govt.nz/safety/driving-safely/safety-cameras/',
      retrievedAt: cameraTime, checkedAt: cameras.checkedAt ?? null, status: cameras.syncStatus,
      stale: cameras.syncStatus !== 'live' || !Number.isFinite(Date.parse(cameraTime)) || now - Date.parse(cameraTime) > 86400000,
      commercialRedistribution: false, termsUrl: 'https://www.nzta.govt.nz/about-us/about-this-site' },
    { id: 'nzta-road-events', attribution: 'NZ Transport Agency Waka Kotahi', url: ROAD_EVENTS_SOURCE_PAGE,
      retrievedAt: roadTime, checkedAt: roads.checkedAt ?? null, status: roads.syncStatus,
      stale: roads.syncStatus !== 'live' || !Number.isFinite(Date.parse(roadTime)) || now - Date.parse(roadTime) > 600000,
      commercialRedistribution: false, termsUrl: NZTA_TERMS },
  ];
  const events = [
    ...(cameras.cameras ?? []).map((c) => ({ id: `nzta:camera:${c.id}`, type: 'safetyCamera',
      location: { latitude: c.latitude, longitude: c.longitude }, geometry: [], roadName: c.location || c.name,
      severity: 'advisory', observation: 'official', confidence: null, validFrom: null, validUntil: null,
      sourceId: 'nzta-cameras', metadata: { cameraType: c.type, region: c.region, suburb: c.suburb } })),
    ...(roads.events ?? []).map((e) => ({ id: e.id, type: e.type, location: e.location,
      geometry: e.geometry ?? [], roadName: e.roadName, severity: e.severity, observation: e.observation,
      confidence: e.confidence ?? null, validFrom: e.validFrom, validUntil: e.validUntil,
      sourceId: 'nzta-road-events', sourceUpdatedAt: e.source?.updatedAt ?? null, metadata: e.metadata ?? {} })),
  ].filter((e) => point([e.location?.longitude, e.location?.latitude]));
  return { events, sources };
}

export async function handleRoadIntelligence(request, env, ctx, readCameras, options = {}) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(ROOT)) return null;
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: {
    'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
    'access-control-allow-headers': 'Authorization, Content-Type', 'access-control-max-age': '3600' } });
  if (url.pathname === `${ROOT}/capabilities` && request.method === 'GET') return json(capabilities);
  if (url.pathname === `${ROOT}/openapi.json` && request.method === 'GET') return json(openapi);
  if (!env.USER_DB) return failure('unavailable', 'Road Intelligence storage is not configured', 503);
  if (url.pathname === `${ROOT}/keys` || url.pathname.startsWith(`${ROOT}/keys/`)) return manageKeys(request, env, url);
  const corridor = url.pathname === `${ROOT}/corridor`;
  if (!corridor && url.pathname !== `${ROOT}/events`) return failure('not-found', 'Endpoint not found', 404);
  if (request.method !== (corridor ? 'POST' : 'GET')) return failure('method-not-allowed', corridor ? 'Use POST' : 'Use GET', 405);
  const now = options.now ?? Date.now();
  const auth = await authorize(request, env.USER_DB, now);
  if (auth.response) return auth.response;
  let query;
  if (corridor) {
    const input = await body(request);
    const route = Array.isArray(input?.coordinates) ? input.coordinates.map(point) : [];
    const buffer = input?.bufferMeters == null ? 180 : number(input.bufferMeters);
    if (route.length < 2 || route.length > 250 || !route.every(Boolean) || buffer == null || buffer < 25 || buffer > 500)
      return failure('invalid-request', 'Provide 2–250 NZ [longitude, latitude] coordinates and bufferMeters 25–500', 400);
    query = { route, buffer };
  } else {
    const bbox = url.searchParams.get('bbox')?.split(',').map(number);
    const near = point(url.searchParams.get('near')?.split(',') ?? []);
    const radius = url.searchParams.has('radiusMeters') ? number(url.searchParams.get('radiusMeters')) : 1500;
    if (bbox && (url.searchParams.has('near') || bbox.length !== 4 || !point(bbox.slice(0, 2)) || !point(bbox.slice(2)) || bbox[0] >= bbox[2] || bbox[1] >= bbox[3] || bbox[2] - bbox[0] > 2 || bbox[3] - bbox[1] > 2))
      return failure('invalid-request', 'bbox must be west,south,east,north in NZ, at most 2° wide/high', 400);
    if (!bbox && (!near || radius == null || radius < 50 || radius > 10000))
      return failure('invalid-request', 'Provide bbox or near=longitude,latitude with radiusMeters 50–10000', 400);
    query = bbox ? { bbox } : { near, radius };
  }
  query.types = url.searchParams.get('types')?.split(',');
  const limit = url.searchParams.has('limit') ? number(url.searchParams.get('limit')) : 50;
  const cursor = url.searchParams.has('cursor') ? number(url.searchParams.get('cursor')) : 0;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100 || !Number.isInteger(cursor) || cursor < 0 || cursor > 10000)
    return failure('invalid-request', 'limit must be 1–100; cursor must be a nonnegative integer', 400);
  const cameraState = await readCameras(env);
  let roads;
  try { roads = await (options.loadRoads ?? loadRoadEventState)(env); }
  catch { roads = { events: [], syncStatus: 'unavailable', checkedAt: null }; }
  const snapshot = normalizeSnapshot(cameraState, roads, now);
  const matches = queryEvents(snapshot.events, query, now);
  ctx.waitUntil(env.USER_DB.prepare('DELETE FROM road_api_usage WHERE window_start < ?').bind(now - 7 * 86400000).run());
  return json({ apiVersion: '1', requestId: crypto.randomUUID(), generatedAt: new Date(now).toISOString(),
    dataUse: capabilities.dataUse, sources: snapshot.sources, events: matches.slice(cursor, cursor + limit),
    total: matches.length, nextCursor: cursor + limit < matches.length ? String(cursor + limit) : null }, 200, auth.headers);
}

export const openapi = {
  openapi: '3.1.0', info: { title: 'Waybi Road Intelligence', version: '1.0.0-preview', description: capabilities.dataUse.note },
  servers: [{ url: 'https://waybi.nzs.workers.dev' }],
  components: {
    securitySchemes: {
      RoadApiKey: { type: 'http', scheme: 'bearer', description: 'klri_ key; 90-day expiry, preview:read scope' },
      AccountSession: { type: 'apiKey', in: 'cookie', name: 'waybi_session' },
    },
    schemas: {
      Point: { type: 'object', required: ['latitude', 'longitude'], properties: { latitude: { type: 'number' }, longitude: { type: 'number' } } },
      Source: { type: 'object', required: ['id', 'attribution', 'url', 'stale', 'commercialRedistribution'], properties: {
        id: { type: 'string' }, attribution: { type: 'string' }, url: { type: 'string', format: 'uri' },
        retrievedAt: { type: ['string', 'null'], format: 'date-time' }, checkedAt: { type: ['string', 'null'], format: 'date-time' },
        status: { type: 'string' }, stale: { type: 'boolean' }, commercialRedistribution: { const: false }, termsUrl: { type: 'string', format: 'uri' },
      } },
      Event: { type: 'object', required: ['id', 'type', 'location', 'sourceId'], properties: {
        id: { type: 'string' }, type: { type: 'string' }, location: { $ref: '#/components/schemas/Point' },
        geometry: { type: 'array', items: { $ref: '#/components/schemas/Point' } }, roadName: { type: 'string' },
        severity: { type: 'string' }, observation: { type: 'string' }, confidence: { type: ['number', 'null'] },
        validFrom: { type: ['string', 'null'], format: 'date-time' }, validUntil: { type: ['string', 'null'], format: 'date-time' },
        sourceId: { type: 'string' }, sourceUpdatedAt: { type: ['string', 'null'], format: 'date-time' },
        metadata: { type: 'object', additionalProperties: true }, distanceMeters: { type: 'integer' },
        distanceFromRouteMeters: { type: 'integer' }, distanceAlongRouteMeters: { type: 'integer' },
      } },
      Snapshot: { type: 'object', required: ['apiVersion', 'requestId', 'generatedAt', 'dataUse', 'sources', 'events', 'total', 'nextCursor'], properties: {
        apiVersion: { const: '1' }, requestId: { type: 'string', format: 'uuid' }, generatedAt: { type: 'string', format: 'date-time' },
        dataUse: { type: 'object', additionalProperties: true }, sources: { type: 'array', items: { $ref: '#/components/schemas/Source' } },
        events: { type: 'array', items: { $ref: '#/components/schemas/Event' } }, total: { type: 'integer' }, nextCursor: { type: ['string', 'null'] },
      } },
    },
  },
  paths: {
    [`${ROOT}/capabilities`]: { get: { summary: 'Capabilities and source data usage conditions', responses: { 200: { description: 'Preview capabilities' } } } },
    [`${ROOT}/keys`]: { get: { summary: 'List signed-in account keys', security: [{ AccountSession: [] }], responses: { 200: { description: 'Key metadata only' }, 401: { description: 'Session required' } } },
      post: { summary: 'Create signed-in account preview key', security: [{ AccountSession: [] }], requestBody: { required: true, content: { 'application/json': { schema: { type: 'object', required: ['name'], properties: { name: { type: 'string' } } } } } }, responses: { 201: { description: 'Secret returned once' }, 401: { description: 'Session required' }, 409: { description: 'Five active keys allowed' } } } },
    [`${ROOT}/keys/{id}`]: { delete: { summary: 'Revoke own key', security: [{ AccountSession: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'Revoked' }, 404: { description: 'Key not owned/found' } } } },
    [`${ROOT}/events`]: { get: { summary: 'Official events and cameras in an area or nearby', security: [{ RoadApiKey: [] }], parameters: [
      ...['bbox', 'near', 'types', 'cursor'].map((name) => ({ name, in: 'query', schema: { type: 'string' } })),
      { name: 'radiusMeters', in: 'query', schema: { type: 'integer', minimum: 50, maximum: 10000, default: 1500 } },
      { name: 'limit', in: 'query', schema: { type: 'integer', minimum: 1, maximum: 100, default: 50 } },
    ], responses: { 200: { description: 'Events with source freshness and pagination', content: { 'application/json': { schema: { $ref: '#/components/schemas/Snapshot' } } } }, 400: { description: 'Invalid area' }, 401: { description: 'Key required' }, 429: { description: 'Quota exceeded; Retry-After header' } } } },
    [`${ROOT}/corridor`]: { post: { summary: 'Events within a route corridor; geometry is never stored', security: [{ RoadApiKey: [] }], requestBody: { required: true, content: { 'application/json': { schema: { type: 'object', required: ['coordinates'], properties: {
      coordinates: { type: 'array', minItems: 2, maxItems: 250, items: { type: 'array', minItems: 2, maxItems: 2, items: { type: 'number' } } },
      bufferMeters: { type: 'integer', minimum: 25, maximum: 500, default: 180 },
    } } } } }, responses: { 200: { description: 'Events ordered by distance along route', content: { 'application/json': { schema: { $ref: '#/components/schemas/Snapshot' } } } }, 400: { description: 'Invalid geometry' }, 401: { description: 'Key required' }, 429: { description: 'Quota exceeded' } } } },
  },
};
