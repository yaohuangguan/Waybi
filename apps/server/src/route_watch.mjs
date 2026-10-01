import { userFromRequest } from './auth.mjs';
import { loadRoadEventState } from './road_events.mjs';

const MAX_WATCHES_PER_USER = 8;
const MAX_POINTS = 250;
const ROUTE_CORRIDOR_METERS = 180;
const ROUTE_CACHE_MS = 29 * 24 * 60 * 60 * 1000;
const MAX_MATCHES = 6;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*'
    }
  });
}

function finite(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function validPoint(point) {
  const latitude = finite(point?.latitude);
  const longitude = finite(point?.longitude);
  if (
    latitude == null ||
    longitude == null ||
    latitude <= -48 ||
    latitude >= -34 ||
    longitude <= 166 ||
    longitude >= 179
  ) {
    return null;
  }
  return { latitude, longitude };
}

function normalizePoints(value) {
  if (!Array.isArray(value) || value.length < 2 || value.length > MAX_POINTS) return null;
  const points = value.map(validPoint);
  return points.every(Boolean) ? points : null;
}

function metresBetween(a, b) {
  const latScale = 111_320;
  const lonScale =
    111_320 * Math.cos(((a.latitude + b.latitude) / 2) * Math.PI / 180);
  return Math.hypot(
    (b.longitude - a.longitude) * lonScale,
    (b.latitude - a.latitude) * latScale
  );
}

function pointToSegmentMetres(point, start, end) {
  const latScale = 111_320;
  const refLat = (point.latitude + start.latitude + end.latitude) / 3;
  const lonScale = 111_320 * Math.cos(refLat * Math.PI / 180);
  const ax = (start.longitude - point.longitude) * lonScale;
  const ay = (start.latitude - point.latitude) * latScale;
  const bx = (end.longitude - point.longitude) * lonScale;
  const by = (end.latitude - point.latitude) * latScale;
  const dx = bx - ax;
  const dy = by - ay;
  const denom = dx * dx + dy * dy;
  const t = denom === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / denom));
  return Math.hypot(ax + dx * t, ay + dy * t);
}

function distanceToRoute(point, routePoints) {
  let best = Infinity;
  for (let i = 1; i < routePoints.length; i++) {
    best = Math.min(best, pointToSegmentMetres(point, routePoints[i - 1], routePoints[i]));
    if (best <= 20) break;
  }
  return best;
}

function eventPoints(event) {
  const geometry = Array.isArray(event?.geometry) ? event.geometry : [];
  const points = geometry.map(validPoint).filter(Boolean);
  const location = validPoint(event?.location);
  if (location) points.push(location);
  return points;
}

function eventRank(event) {
  if (event.severity === 'critical') return 3;
  if (event.severity === 'warning') return 2;
  if (event.severity === 'advisory') return 1;
  return 0;
}

function eventSummary(event) {
  return {
    id: String(event.id || ''),
    type: String(event.type || 'incident'),
    severity: String(event.severity || 'advisory'),
    roadName: event.roadName || null,
    validUntil: event.validUntil || null,
    description: event.metadata?.description || '',
    comments: event.metadata?.comments || '',
    impact: event.metadata?.impact || '',
    alternativeRoute: event.metadata?.alternativeRoute || ''
  };
}

export function evaluateRouteWatch(routePoints, events, now = new Date()) {
  if (!Array.isArray(routePoints) || routePoints.length < 2) {
    return { status: 'unknown', events: [] };
  }
  const time = now.getTime();
  const matches = [];
  for (const event of events || []) {
    const from = Date.parse(event.validFrom || '');
    const until = Date.parse(event.validUntil || '');
    if (Number.isFinite(from) && from > time) continue;
    if (Number.isFinite(until) && until <= time) continue;
    const points = eventPoints(event);
    if (!points.length) continue;
    let best = Infinity;
    for (const point of points) {
      best = Math.min(best, distanceToRoute(point, routePoints));
      if (best <= 20) break;
    }
    if (best > ROUTE_CORRIDOR_METERS) continue;
    matches.push({ ...eventSummary(event), distanceFromRouteMeters: Math.round(best) });
  }

  matches.sort((a, b) => {
    const rank = eventRank(b) - eventRank(a);
    return rank || a.distanceFromRouteMeters - b.distanceFromRouteMeters;
  });
  const selected = matches.slice(0, MAX_MATCHES);
  const status = selected.some((event) => event.severity === 'critical')
    ? 'disrupted'
    : selected.some((event) => event.severity === 'warning')
      ? 'warning'
      : selected.length
        ? 'advisory'
        : 'healthy';
  return { status, events: selected };
}

function parseStoredPoints(raw) {
  try {
    const parsed = JSON.parse(raw || '[]');
    return normalizePoints(parsed) || [];
  } catch {
    return [];
  }
}

export function routeGeometryFresh(row, now = new Date()) {
  return Number(row?.geometry_expires_at || 0) > now.getTime();
}

function parseEvents(raw) {
  try {
    const parsed = JSON.parse(raw || '[]');
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function routeWatchJson(row) {
  return {
    id: row.id,
    label: row.label,
    originName: row.origin_name || '',
    origin: row.origin_latitude == null || row.origin_longitude == null
      ? null
      : {
          latitude: Number(row.origin_latitude),
          longitude: Number(row.origin_longitude)
        },
    destinationName: row.destination_name,
    destination: {
      latitude: Number(row.destination_latitude),
      longitude: Number(row.destination_longitude)
    },
    routeProvider: row.route_provider || 'unknown',
    geometryExpiresAt: row.geometry_expires_at == null
      ? null
      : new Date(Number(row.geometry_expires_at)).toISOString(),
    baselineDurationSeconds: row.baseline_duration_seconds == null
      ? null
      : Number(row.baseline_duration_seconds),
    baselineDistanceMeters: row.baseline_distance_meters == null
      ? null
      : Number(row.baseline_distance_meters),
    enabled: row.enabled === 1,
    status: row.last_status || 'healthy',
    eventCount: Number(row.last_event_count || 0),
    events: parseEvents(row.last_events_json),
    lastCheckedAt: row.last_checked_at == null
      ? null
      : new Date(Number(row.last_checked_at)).toISOString(),
    updatedAt: new Date(Number(row.updated_at)).toISOString()
  };
}

async function evaluateRow(db, row, events, now = new Date()) {
  const checkedAt = now.getTime();
  const geometryFresh = routeGeometryFresh(row, now);
  const result = geometryFresh
    ? evaluateRouteWatch(parseStoredPoints(row.route_points_json), events, now)
    : { status: 'unknown', events: [] };
  await db.prepare(`
    UPDATE route_watches
    SET last_checked_at = ?, last_status = ?, last_event_count = ?, last_events_json = ?
    WHERE id = ?
  `).bind(
    checkedAt,
    result.status,
    result.events.length,
    JSON.stringify(result.events),
    row.id
  ).run();
  return {
    ...row,
    last_checked_at: checkedAt,
    last_status: result.status,
    last_event_count: result.events.length,
    last_events_json: JSON.stringify(result.events)
  };
}

async function listUserWatches(db, userId) {
  const result = await db.prepare(`
    SELECT * FROM route_watches
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `).bind(userId).all();
  return result.results || [];
}

export async function evaluateAllRouteWatches(env, now = new Date()) {
  if (!env?.USER_DB || !env?.CAMERA_DATA) return { checked: 0 };
  const result = await env.USER_DB.prepare(`
    SELECT * FROM route_watches
    WHERE enabled = 1
    ORDER BY updated_at DESC
    LIMIT 500
  `).all();
  const rows = result.results || [];
  if (!rows.length) return { checked: 0 };
  const hasFreshGeometry = rows.some((row) => routeGeometryFresh(row, now));
  const state = hasFreshGeometry
    ? await loadRoadEventState(env, fetch, now)
    : { events: [] };
  let checked = 0;
  for (const row of rows) {
    await evaluateRow(env.USER_DB, row, state.events || [], now);
    checked += 1;
  }
  return { checked };
}

export async function handleRouteWatch(request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/route-watches')) return null;
  if (!env.USER_DB) return json({ error: 'Account storage is not configured' }, 503);

  const user = await userFromRequest(env.USER_DB, request);
  if (!user) return json({ error: 'Sign in required' }, 401);

  if (request.method === 'GET' && url.pathname === '/api/route-watches') {
    const rows = await listUserWatches(env.USER_DB, user.id);
    const now = new Date();
    const hasFreshGeometry = rows.some(
      (row) => row.enabled === 1 && routeGeometryFresh(row, now)
    );
    const state = hasFreshGeometry
      ? await loadRoadEventState(env)
      : { events: [] };
    const output = [];
    for (const row of rows) {
      const evaluated = row.enabled === 1
        ? await evaluateRow(env.USER_DB, row, state.events || [])
        : row;
      output.push(routeWatchJson(evaluated));
    }
    return json({
      entitlement: 'plus-preview',
      watches: output
    });
  }

  if (request.method === 'POST' && url.pathname === '/api/route-watches') {
    if (request.headers.get('x-kiwi-client') !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    const body = await request.json().catch(() => null);
    const label = typeof body?.label === 'string' ? body.label.trim().slice(0, 80) : '';
    const originName = typeof body?.originName === 'string'
      ? body.originName.trim().slice(0, 200)
      : '';
    const origin = validPoint(body?.origin);
    const destinationName = typeof body?.destinationName === 'string'
      ? body.destinationName.trim().slice(0, 200)
      : '';
    const destination = validPoint(body?.destination);
    const routeProvider = typeof body?.routeProvider === 'string'
      ? body.routeProvider.trim().toLowerCase().slice(0, 40)
      : '';
    const routePoints = normalizePoints(body?.routePoints);
    const baselineDuration = finite(body?.baselineDurationSeconds);
    const baselineDistance = finite(body?.baselineDistanceMeters);
    if (
      !label ||
      !originName ||
      !origin ||
      !destinationName ||
      !destination ||
      !routeProvider ||
      !/^[a-z0-9_.-]+$/.test(routeProvider) ||
      !routePoints ||
      (baselineDuration != null && (baselineDuration < 0 || baselineDuration > 2_000_000)) ||
      (baselineDistance != null && (baselineDistance < 0 || baselineDistance > 5_000_000))
    ) {
      return json({ error: 'Invalid route watch' }, 400);
    }

    const existing = await env.USER_DB.prepare(
      'SELECT id FROM route_watches WHERE user_id = ? AND label = ?'
    ).bind(user.id, label).first();
    if (!existing) {
      const count = await env.USER_DB.prepare(
        'SELECT COUNT(*) AS count FROM route_watches WHERE user_id = ?'
      ).bind(user.id).first();
      if (Number(count?.count || 0) >= MAX_WATCHES_PER_USER) {
        return json({ error: `At most ${MAX_WATCHES_PER_USER} route watches are supported` }, 409);
      }
    }

    const id = existing?.id || crypto.randomUUID();
    const now = Date.now();
    const geometryExpiresAt = now + ROUTE_CACHE_MS;
    await env.USER_DB.prepare(`
      INSERT INTO route_watches (
        id, user_id, label,
        origin_name, origin_latitude, origin_longitude,
        destination_name, destination_latitude, destination_longitude,
        route_provider, route_points_json, geometry_expires_at,
        baseline_duration_seconds, baseline_distance_meters,
        enabled, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(user_id, label) DO UPDATE SET
        origin_name = excluded.origin_name,
        origin_latitude = excluded.origin_latitude,
        origin_longitude = excluded.origin_longitude,
        destination_name = excluded.destination_name,
        destination_latitude = excluded.destination_latitude,
        destination_longitude = excluded.destination_longitude,
        route_provider = excluded.route_provider,
        route_points_json = excluded.route_points_json,
        geometry_expires_at = excluded.geometry_expires_at,
        baseline_duration_seconds = excluded.baseline_duration_seconds,
        baseline_distance_meters = excluded.baseline_distance_meters,
        enabled = 1,
        updated_at = excluded.updated_at
    `).bind(
      id,
      user.id,
      label,
      originName,
      origin.latitude,
      origin.longitude,
      destinationName,
      destination.latitude,
      destination.longitude,
      routeProvider,
      JSON.stringify(routePoints),
      geometryExpiresAt,
      baselineDuration == null ? null : Math.round(baselineDuration),
      baselineDistance == null ? null : Math.round(baselineDistance),
      now,
      now
    ).run();

    const state = await loadRoadEventState(env);
    const stored = await env.USER_DB.prepare(
      'SELECT * FROM route_watches WHERE user_id = ? AND label = ?'
    ).bind(user.id, label).first();
    const evaluated = await evaluateRow(env.USER_DB, stored, state.events || []);
    return json({ entitlement: 'plus-preview', watch: routeWatchJson(evaluated) }, 201);
  }

  const match = /^\/api\/route-watches\/([^/]+)$/.exec(url.pathname);
  if (match && request.method === 'DELETE') {
    if (request.headers.get('x-kiwi-client') !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    const id = decodeURIComponent(match[1]);
    await env.USER_DB.prepare(
      'DELETE FROM route_watches WHERE id = ? AND user_id = ?'
    ).bind(id, user.id).run();
    return json({ ok: true });
  }

  return json({ error: 'Not found' }, 404);
}

export const __test = {
  metresBetween,
  pointToSegmentMetres,
  distanceToRoute,
  ROUTE_CORRIDOR_METERS,
  ROUTE_CACHE_MS
};
