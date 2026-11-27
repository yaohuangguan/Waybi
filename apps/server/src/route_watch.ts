import type { ProviderPayload } from "./types.ts";
import { userFromRequest, userHasPlus } from './auth.ts';
import { readRoadEventSnapshot } from './road_events.ts';

const MAX_WATCHES_PER_USER = 8;
const MAX_POINTS = 250;
const ROUTE_CORRIDOR_METERS = 180;
const ROUTE_CACHE_MS = 29 * 24 * 60 * 60 * 1000;
const MAX_MATCHES = 6;
/** GET re-evaluates a watch only when neither it nor the Cron checked it recently. */
const STALE_AFTER_MS = 15 * 60 * 1000;
const CRON_PAGE_SIZE = 100;
// Bounding boxes are padded a little beyond the corridor so the planar
// approximation used for the box can never drop an event inside the corridor.
const BOUNDS_PADDING_METERS = ROUTE_CORRIDOR_METERS * 1.1;
const JOB_NAME = 'route_watch';

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

type Bounds = [minLongitude: number, minLatitude: number, maxLongitude: number, maxLatitude: number];

function boundsOf(points): Bounds | null {
  if (!points?.length) return null;
  let minLon = Infinity, minLat = Infinity, maxLon = -Infinity, maxLat = -Infinity;
  for (const point of points) {
    if (point.longitude < minLon) minLon = point.longitude;
    if (point.longitude > maxLon) maxLon = point.longitude;
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
  }
  return [minLon, minLat, maxLon, maxLat];
}

function padBounds(bounds: Bounds, metres: number): Bounds {
  const latPad = metres / 111_320;
  const maxAbsLat = Math.max(Math.abs(bounds[1]), Math.abs(bounds[3]));
  const lonPad = metres / (111_320 * Math.max(0.01, Math.cos(maxAbsLat * Math.PI / 180)));
  return [bounds[0] - lonPad, bounds[1] - latPad, bounds[2] + lonPad, bounds[3] + latPad];
}

function intersects(a: Bounds, b: Bounds) {
  return a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];
}

function contains(bounds: Bounds, point) {
  return point.longitude >= bounds[0] && point.longitude <= bounds[2] &&
    point.latitude >= bounds[1] && point.latitude <= bounds[3];
}

export interface PreparedRouteWatchEvent {
  event: any;
  points: { latitude: number; longitude: number }[];
  bounds: Bounds;
  from: number;
  until: number;
}

/** Parse and box every event once per evaluation run instead of once per watch. */
export function prepareRouteWatchEvents(events): PreparedRouteWatchEvent[] {
  const prepared: PreparedRouteWatchEvent[] = [];
  for (const event of events || []) {
    const points = eventPoints(event);
    const bounds = boundsOf(points);
    if (!bounds) continue;
    prepared.push({ event, points, bounds,
      from: Date.parse(event.validFrom || ''), until: Date.parse(event.validUntil || '') });
  }
  return prepared;
}

function distanceToRoute(point, routePoints) {
  let best = Infinity;
  for (let i = 1; i < routePoints.length; i++) {
    best = Math.min(best, pointToSegmentMetres(point, routePoints[i - 1], routePoints[i]));
    if (best <= 20) break;
  }
  return best;
}

// Route segments are bucketed into a coarse grid (about 450 m cells) using
// each segment's box padded past the corridor, so an event point only measures
// against the few segments that could be within the corridor.
const GRID_DEGREES = 0.004;
const MAX_CELLS_PER_SEGMENT = 400;
interface SegmentIndex { cells: Map<string, number[]>; long: number[] }

function cellKey(longitude: number, latitude: number) {
  return `${Math.floor(longitude / GRID_DEGREES)}:${Math.floor(latitude / GRID_DEGREES)}`;
}

function indexRouteSegments(routePoints): SegmentIndex {
  const cells = new Map<string, number[]>();
  const long: number[] = [];
  for (let i = 1; i < routePoints.length; i++) {
    const box = padBounds(boundsOf([routePoints[i - 1], routePoints[i]])!, BOUNDS_PADDING_METERS);
    const west = Math.floor(box[0] / GRID_DEGREES), east = Math.floor(box[2] / GRID_DEGREES);
    const south = Math.floor(box[1] / GRID_DEGREES), north = Math.floor(box[3] / GRID_DEGREES);
    if ((east - west + 1) * (north - south + 1) > MAX_CELLS_PER_SEGMENT) { long.push(i); continue; }
    for (let x = west; x <= east; x++) {
      for (let y = south; y <= north; y++) {
        const key = `${x}:${y}`;
        const bucket = cells.get(key);
        if (bucket) bucket.push(i);
        else cells.set(key, [i]);
      }
    }
  }
  return { cells, long };
}

function indexedDistanceToRoute(point, routePoints, index: SegmentIndex) {
  let best = Infinity;
  const nearby = index.cells.get(cellKey(point.longitude, point.latitude));
  for (const list of [nearby, index.long]) {
    if (!list) continue;
    for (const i of list) {
      best = Math.min(best, pointToSegmentMetres(point, routePoints[i - 1], routePoints[i]));
      if (best <= 20) return best;
    }
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
  return evaluatePreparedRouteWatch(routePoints, prepareRouteWatchEvents(events), now);
}

/**
 * Match prepared events against one saved corridor. Events whose padded box
 * does not overlap the route's padded box are skipped without any distance
 * maths, and so are individual event points outside the route's box. Only
 * events active at `now` count: the shared snapshot also carries closures
 * scheduled to start later.
 */
export function evaluatePreparedRouteWatch(routePoints, prepared: PreparedRouteWatchEvent[], now = new Date()) {
  if (!Array.isArray(routePoints) || routePoints.length < 2) {
    return { status: 'unknown', events: [] };
  }
  const routeBounds = padBounds(boundsOf(routePoints)!, BOUNDS_PADDING_METERS);
  const time = now.getTime();
  const matches = [];
  let index: SegmentIndex | null = null;
  for (const item of prepared) {
    if (Number.isFinite(item.from) && item.from > time) continue;
    if (Number.isFinite(item.until) && item.until <= time) continue;
    if (!intersects(item.bounds, routeBounds)) continue;
    index ??= indexRouteSegments(routePoints);
    let best = Infinity;
    for (const point of item.points) {
      if (!contains(routeBounds, point)) continue;
      best = Math.min(best, indexedDistanceToRoute(point, routePoints, index));
      if (best <= 20) break;
    }
    if (best > ROUTE_CORRIDOR_METERS) continue;
    matches.push({ ...eventSummary(item.event), distanceFromRouteMeters: Math.round(best) });
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

function routeWatchJson(row, checkedAt = row.last_checked_at) {
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
    lastCheckedAt: checkedAt == null
      ? null
      : new Date(Number(checkedAt)).toISOString(),
    updatedAt: new Date(Number(row.updated_at)).toISOString()
  };
}

function routeAlertSignature(result) {
  if (!['warning', 'disrupted'].includes(result?.status)) return '';
  const ids = (result.events || [])
    .map((event) => String(event.id || ''))
    .filter(Boolean)
    .sort();
  return `${result.status}:${ids.join('|')}`;
}

function evaluateStoredRow(row, prepared: PreparedRouteWatchEvent[], now = new Date()) {
  return routeGeometryFresh(row, now)
    ? evaluatePreparedRouteWatch(parseStoredPoints(row.route_points_json), prepared, now)
    : { status: 'unknown', events: [] };
}

function resultChanged(row, result) {
  return (row.last_status || 'healthy') !== result.status ||
    String(row.last_events_json || '[]') !== JSON.stringify(result.events);
}

function statusUpdate(db, row, result, checkedAt: number) {
  return db.prepare(`
    UPDATE route_watches
    SET last_checked_at = ?, last_status = ?, last_event_count = ?, last_events_json = ?
    WHERE id = ?
  `).bind(checkedAt, result.status, result.events.length, JSON.stringify(result.events), row.id);
}

/**
 * Claim the new alert signature atomically; only the evaluator whose UPDATE
 * matched the previous signature inserts the alert, so overlapping runs (Cron
 * retries, a slow previous run) cannot create duplicate alerts. If the insert
 * fails, the previous signature is restored so the next run retries.
 */
async function claimAlert(db, row, result, signature: string, checkedAt: number) {
  const previous = String(row.last_alert_signature || '');
  const claimed = await db.prepare(
    'UPDATE route_watches SET last_alert_signature = ? WHERE id = ? AND last_alert_signature IS ? RETURNING id'
  ).bind(signature, row.id, previous).first();
  if (!claimed || !signature) return false;
  try {
    await db.prepare(`
      INSERT INTO route_watch_alerts (
        id, user_id, route_watch_id, label, status, events_json, created_at, read_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
    `).bind(crypto.randomUUID(), row.user_id, row.id, row.label, result.status,
      JSON.stringify(result.events), checkedAt).run();
    return true;
  } catch (error) {
    await db.prepare('UPDATE route_watches SET last_alert_signature = ? WHERE id = ? AND last_alert_signature IS ?')
      .bind(previous, row.id, signature).run().catch(() => {});
    throw error;
  }
}

function logJob(level: 'info' | 'warn' | 'error', event: string, fields: Record<string, unknown> = {}) {
  const line = JSON.stringify({ level, event, job: JOB_NAME, ...fields });
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.info(line);
}

async function listUserWatches(db, userId) {
  const result = await db.prepare(`
    SELECT * FROM route_watches
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `).bind(userId).all();
  return result.results || [];
}

async function lastRouteWatchRun(db) {
  try {
    return await db.prepare('SELECT started_at, completed_at FROM scheduled_job_runs WHERE job = ?')
      .bind(JOB_NAME).first();
  } catch {
    return null;
  }
}

/** A watch that existed when the latest complete Cron run started was checked
 * by that run even when nothing changed (unchanged rows are not rewritten). */
function effectiveCheckedAt(row, run) {
  const own = Number(row.last_checked_at || 0);
  const covered = run?.completed_at && Number(row.updated_at || 0) <= Number(run.started_at)
    ? Number(run.completed_at) : 0;
  const latest = Math.max(own, covered);
  return latest > 0 ? latest : null;
}

/**
 * Cron entry point. Pages through every enabled Plus watch with a keyset
 * cursor, evaluates each against events prepared once for the whole run,
 * writes only rows whose status or events changed (one D1 batch per page),
 * isolates failures per row, and records the run so GET can trust it.
 * The road-event snapshot is read, never refreshed: the 10-minute Cron owns it.
 */
export async function evaluateAllRouteWatches(env, now = new Date(), { pageSize = CRON_PAGE_SIZE } = {}) {
  if (!env?.USER_DB || !env?.CAMERA_DATA) return { checked: 0, changed: 0, alerts: 0, failed: 0 };
  const db = env.USER_DB;
  const started = Date.now();
  let state;
  try {
    state = await readRoadEventSnapshot(env, now);
  } catch (error) {
    logJob('error', 'route_watch_events_unavailable', { message: String(error?.message || error).slice(0, 200) });
    return { checked: 0, changed: 0, alerts: 0, failed: 0, skipped: 'road-events-unavailable' };
  }
  if (state.syncStatus === 'unavailable') {
    // Keep the last known statuses instead of flipping every watch to unknown.
    logJob('warn', 'route_watch_skipped', { reason: state.syncError || 'road events unavailable' });
    return { checked: 0, changed: 0, alerts: 0, failed: 0, skipped: 'road-events-unavailable' };
  }
  const prepared = prepareRouteWatchEvents(state.events || []);
  const checkedAt = now.getTime();
  let cursor = '';
  let checked = 0, changed = 0, alerts = 0, failed = 0;
  for (;;) {
    let page;
    try {
      page = (await db.prepare(`
        SELECT route_watches.id, route_watches.user_id, route_watches.label, route_watches.route_points_json,
          route_watches.geometry_expires_at, route_watches.last_status, route_watches.last_events_json,
          route_watches.last_alert_signature
        FROM route_watches
        JOIN user_subscriptions ON user_subscriptions.user_id = route_watches.user_id
        WHERE route_watches.enabled = 1
          AND user_subscriptions.plan = 'plus'
          AND (user_subscriptions.expires_at IS NULL OR user_subscriptions.expires_at > ?)
          AND route_watches.id > ?
        ORDER BY route_watches.id
        LIMIT ?
      `).bind(checkedAt, cursor, pageSize).all()).results || [];
    } catch (error) {
      logJob('error', 'route_watch_page_failed', { cursor, message: String(error?.message || error).slice(0, 200) });
      return { checked, changed, alerts, failed: failed + 1, incomplete: true };
    }
    if (!page.length) break;
    cursor = page[page.length - 1].id;
    const writes = [];
    for (const row of page) {
      try {
        const result = evaluateStoredRow(row, prepared, now);
        if (resultChanged(row, result)) writes.push(statusUpdate(db, row, result, checkedAt));
        const signature = routeAlertSignature(result);
        if (signature !== String(row.last_alert_signature || '') &&
            await claimAlert(db, row, result, signature, checkedAt)) alerts++;
        checked++;
      } catch (error) {
        failed++;
        logJob('error', 'route_watch_row_failed', { watchId: row.id, message: String(error?.message || error).slice(0, 200) });
      }
    }
    if (writes.length) {
      try {
        await db.batch(writes);
        changed += writes.length;
      } catch (error) {
        failed += writes.length;
        logJob('error', 'route_watch_batch_failed', { rows: writes.length, message: String(error?.message || error).slice(0, 200) });
      }
    }
    if (page.length < pageSize) break;
  }
  try {
    await db.prepare(`INSERT INTO scheduled_job_runs (job, started_at, completed_at, processed, failed)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(job) DO UPDATE SET started_at = excluded.started_at,
        completed_at = excluded.completed_at, processed = excluded.processed, failed = excluded.failed`)
      .bind(JOB_NAME, checkedAt, Date.now(), checked, failed).run();
  } catch (error) {
    logJob('warn', 'route_watch_run_marker_failed', { message: String(error?.message || error).slice(0, 200) });
  }
  logJob(failed ? 'warn' : 'info', 'route_watch_run', { checked, changed, alerts, failed,
    events: prepared.length, durationMs: Date.now() - started });
  return { checked, changed, alerts, failed };
}

/** Evaluate a user's own watches that are stale, reading the snapshot only. */
async function refreshStaleWatches(env, rows, now: Date) {
  const db = env.USER_DB;
  const run = await lastRouteWatchRun(db);
  const output = new Map<string, { row: any; checkedAt: number | null }>();
  const stale = [];
  for (const row of rows) {
    const checkedAt = effectiveCheckedAt(row, run);
    output.set(row.id, { row, checkedAt });
    if (row.enabled === 1 && (checkedAt == null || now.getTime() - checkedAt > STALE_AFTER_MS)) stale.push(row);
  }
  if (!stale.length) return output;
  let state = null;
  try { state = await readRoadEventSnapshot(env, now); } catch { state = null; }
  if (!state || state.syncStatus === 'unavailable') {
    // Report unknown without persisting it; the Cron will evaluate later.
    for (const row of stale) {
      output.set(row.id, { row: { ...row, last_status: 'unknown', last_event_count: 0, last_events_json: '[]' },
        checkedAt: output.get(row.id)!.checkedAt });
    }
    return output;
  }
  const prepared = prepareRouteWatchEvents(state.events || []);
  const checkedAt = now.getTime();
  const writes = [];
  for (const row of stale) {
    const result = evaluateStoredRow(row, prepared, now);
    writes.push(resultChanged(row, result)
      ? statusUpdate(db, row, result, checkedAt)
      : db.prepare('UPDATE route_watches SET last_checked_at = ? WHERE id = ?').bind(checkedAt, row.id));
    output.set(row.id, { row: { ...row, last_status: result.status, last_event_count: result.events.length,
      last_events_json: JSON.stringify(result.events), last_checked_at: checkedAt }, checkedAt });
  }
  try {
    if (db.batch) await db.batch(writes);
    else for (const write of writes) await write.run();
  } catch (error) {
    logJob('warn', 'route_watch_refresh_write_failed', { message: String(error?.message || error).slice(0, 200) });
  }
  return output;
}

function routeWatchAlertJson(row) {
  return {
    id: row.id,
    routeWatchId: row.route_watch_id,
    label: row.label,
    status: row.status,
    events: parseEvents(row.events_json),
    createdAt: new Date(Number(row.created_at)).toISOString(),
    readAt: row.read_at == null
      ? null
      : new Date(Number(row.read_at)).toISOString()
  };
}

export async function handleRouteWatchAlerts(request: Request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/route-watch-alerts')) return null;
  if (!env.USER_DB) return json({ error: 'Account storage is not configured' }, 503);

  const user = await userFromRequest(env.USER_DB, request);
  if (!user) return json({ error: 'Sign in required' }, 401);
  if (!await userHasPlus(env.USER_DB, user.id)) {
    return json({
      error: 'Waybi Plus is required for proactive commute alerts',
      code: 'PLUS_REQUIRED'
    }, 403);
  }

  if (request.method === 'GET' && url.pathname === '/api/route-watch-alerts') {
    const includeRead = url.searchParams.get('all') === '1';
    const result = includeRead
      ? await env.USER_DB.prepare(`
          SELECT * FROM route_watch_alerts
          WHERE user_id = ?
          ORDER BY created_at DESC
          LIMIT 50
        `).bind(user.id).all()
      : await env.USER_DB.prepare(`
          SELECT * FROM route_watch_alerts
          WHERE user_id = ? AND read_at IS NULL
          ORDER BY created_at DESC
          LIMIT 50
        `).bind(user.id).all();
    return json({
      entitlement: 'plus',
      alerts: (result.results || []).map(routeWatchAlertJson)
    });
  }

  if (
    request.method === 'POST' &&
    url.pathname === '/api/route-watch-alerts/read'
  ) {
    if (request.headers.get('x-waybi-client') !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    const body = await request.json<ProviderPayload>().catch(() => null);
    const ids = Array.isArray(body?.ids)
      ? body.ids
          .map((value) => String(value || '').trim())
          .filter(Boolean)
          .slice(0, 50)
      : [];
    if (!ids.length) return json({ ok: true, updated: 0 });

    let updated = 0;
    const readAt = Date.now();
    for (const id of ids) {
      const result = await env.USER_DB.prepare(`
        UPDATE route_watch_alerts
        SET read_at = COALESCE(read_at, ?)
        WHERE id = ? AND user_id = ?
      `).bind(readAt, id, user.id).run();
      updated += Number(result.meta?.changes || 0);
    }
    return json({ ok: true, updated });
  }

  return json({ error: 'Not found' }, 404);
}

export async function handleRouteWatch(request: Request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/route-watches')) return null;
  if (!env.USER_DB) return json({ error: 'Account storage is not configured' }, 503);

  const user = await userFromRequest(env.USER_DB, request);
  if (!user) return json({ error: 'Sign in required' }, 401);
  if (!await userHasPlus(env.USER_DB, user.id)) {
    return json({
      error: 'Waybi Plus is required for Smart Commute',
      code: 'PLUS_REQUIRED'
    }, 403);
  }

  if (request.method === 'GET' && url.pathname === '/api/route-watches') {
    // Return stored status; only watches not checked in the last 15 minutes
    // (by the Cron or a previous request) are re-evaluated here.
    const rows = await listUserWatches(env.USER_DB, user.id);
    const evaluated = await refreshStaleWatches(env, rows, new Date());
    return json({
      entitlement: 'plus',
      watches: rows.map((row) => {
        const entry = evaluated.get(row.id)!;
        return routeWatchJson(entry.row, entry.checkedAt);
      })
    });
  }

  if (request.method === 'POST' && url.pathname === '/api/route-watches') {
    if (request.headers.get('x-waybi-client') !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    const body = await request.json<ProviderPayload>().catch(() => null);
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

    // One statement enforces the per-user limit atomically: a new label is
    // inserted only while the user has fewer than the maximum, and updating
    // an existing label is always allowed. Concurrent creates cannot overshoot.
    const id = crypto.randomUUID();
    const now = Date.now();
    const geometryExpiresAt = now + ROUTE_CACHE_MS;
    const saved = await env.USER_DB.prepare(`
      INSERT INTO route_watches (
        id, user_id, label,
        origin_name, origin_latitude, origin_longitude,
        destination_name, destination_latitude, destination_longitude,
        route_provider, route_points_json, geometry_expires_at,
        baseline_duration_seconds, baseline_distance_meters,
        enabled, created_at, updated_at
      )
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?
      WHERE (SELECT COUNT(*) FROM route_watches WHERE user_id = ?) < ?
         OR EXISTS (SELECT 1 FROM route_watches WHERE user_id = ? AND label = ?)
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
      RETURNING id
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
      now,
      user.id,
      MAX_WATCHES_PER_USER,
      user.id,
      label
    ).first();
    if (!saved) {
      return json({
        error: `At most ${MAX_WATCHES_PER_USER} route watches are supported`,
        code: 'ROUTE_WATCH_LIMIT'
      }, 409);
    }

    const stored = await env.USER_DB.prepare(
      'SELECT * FROM route_watches WHERE user_id = ? AND label = ?'
    ).bind(user.id, label).first();
    // Saved geometry changed, so evaluate it now against the shared snapshot.
    const evaluated = await refreshStaleWatches(env, [{ ...stored, last_checked_at: null, updated_at: Number.MAX_SAFE_INTEGER }], new Date());
    const entry = evaluated.get(stored.id)!;
    return json({ entitlement: 'plus', watch: routeWatchJson({ ...entry.row, updated_at: stored.updated_at }, entry.checkedAt) }, 201);
  }

  const match = /^\/api\/route-watches\/([^/]+)$/.exec(url.pathname);
  if (match && request.method === 'DELETE') {
    if (request.headers.get('x-waybi-client') !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    let id;
    try { id = decodeURIComponent(match[1]); }
    catch { return json({ error: 'Invalid route watch id' }, 400); }
    await env.USER_DB.prepare(
      'DELETE FROM route_watches WHERE id = ? AND user_id = ?'
    ).bind(id, user.id).run();
    return json({ ok: true });
  }

  return json({ error: 'Not found' }, 404);
}

export const __test = {
  STALE_AFTER_MS,
  effectiveCheckedAt,
  metresBetween,
  pointToSegmentMetres,
  distanceToRoute,
  routeAlertSignature,
  ROUTE_CORRIDOR_METERS,
  ROUTE_CACHE_MS
};
