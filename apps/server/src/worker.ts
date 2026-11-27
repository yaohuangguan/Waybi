import { refreshAppleAuthorizations } from './apple_auth.ts';
import { parseRouteExclusions } from './routing_closures.ts';
import type { ProviderPayload } from "./types.ts";
import { loadSearchEnrichments, mergeAndRankSearchResults } from './search/search_orchestrator.ts';
import { clientKind } from './brand_compat.ts';
import { saveNavigationFeedback } from './navigation_feedback.ts';
import { handleTrafficTile } from './traffic_tiles.ts';
import { distanceMeters, parseLonLat, parseNzLonLat } from './geo.ts';
import { rankPlaces } from './place_search_rank.ts';
import seed from '../data/cameras.json' with { type: 'json' };
import { fetchNztaCameras, SOURCE_URL } from './sync.ts';
import { handleAccount, roadReportAuthor, userFromRequest, userHasPlus } from './auth.ts';
import { syncAllAppleSubscriptions } from './apple_billing.ts';
import { handleBilling } from './billing.ts';
import { handlePlaces } from './places.ts';
import { independentPlaceDetails } from './independent_place_details.ts';
import { routeOptions, maneuverLanes, crossesTasmanSea } from './routes.ts';
import { nearbyAtParking, AT_PARKING_SOURCE } from './parking.ts';
import { loadRoadEventState, refreshRoadEventState } from './road_events.ts';
import { refreshNswRoadEventState } from './au_road_events.ts';
import { loadRegionalRoadEvents } from './regional_road_events.ts';
import { readTrafficFlowState, refreshTrafficFlowState } from './traffic_flow.ts';
import { handleRoadIntelligence } from './road_intelligence_api.ts';
import { createRoadReport, readRoadReports, validRoadReportInput } from './road_reports.ts';
import { refundRoadReportQuota, reserveRoadReportQuota } from './road_report_quota.ts';
import { runDailyCleanup } from './retention.ts';
import { handleGooglePlacePicker } from './google_place_picker.ts';
import { sendGoogleSearchAlerts } from './google_search_budget.ts';
import { readPublicEdgeJson, writePublicEdgeJson } from './public_edge_cache.ts';
import { recordApiUsage, readUsageSummary } from './cost_guard.ts';
import { readTransitSnapshot, refreshTransitSnapshot } from './transit_lanes.ts';
import {
  evaluateAllRouteWatches,
  handleRouteWatch,
  handleRouteWatchAlerts,
} from './route_watch.ts';
import { apiErrorResponse, UpstreamError } from './http_errors.ts';
import { clientFingerprint, clientIp, guardApiRequest } from './abuse_guard.ts';
import { reserveGoogleUnits } from './google_budget.ts';
import { nominatimArray } from './nominatim.ts';
import { nzRoutingEndpoint } from './nz_routing.ts';
import { handleVoicePacks, voicePackLandingPage } from './voice_packs.ts';

const CAMERA_KEY = 'cameras/current';
// Camera locations are slow-changing metadata, not live traffic frames.
// A shared daily refresh is sufficient; manual checks must respect the same window.
const CAMERA_SYNC_COOLDOWN_MS = 24 * 60 * 60 * 1000;
/** Route Watch has its own trigger so its CPU never competes with the Apple jobs. */
export const ROUTE_WATCH_CRON = '7,22,37,52 * * * *';

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

function seedState() {
  return {
    ...seed,
    checkedAt: null,
    lastSuccessfulAt: null,
    syncStatus: 'seed',
    syncError: null,
    fetchMode: 'bundled-seed',
    change: { added: 0, removed: 0 }
  };
}

export async function readCameraState(env) {
  const stored = await env.CAMERA_DATA.get(CAMERA_KEY, 'json');
  return stored?.cameras?.length >= 50 ? stored : seedState();
}

export async function syncCameras(env, fetcher: typeof fetch = fetch) {
  const previous = await readCameraState(env);
  try {
    const fresh = await fetchNztaCameras(fetcher);
    if (fresh.sourceUpdatedAt < previous.sourceUpdatedAt) throw new Error('NZTA page is older than the stored camera snapshot');
    const oldIds = new Set(previous.cameras.map((camera) => camera.id) as string[]);
    const newIds = new Set(fresh.cameras.map((camera) => camera.id) as string[]);
    const checkedAt = new Date().toISOString();
    const next = {
      ...fresh,
      checkedAt,
      lastSuccessfulAt: checkedAt,
      syncStatus: 'live',
      syncError: null,
      change: {
        added: fresh.cameras.filter((camera) => !oldIds.has(camera.id)).length,
        removed: previous.cameras.filter((camera) => !newIds.has(camera.id)).length
      }
    };
    await env.CAMERA_DATA.put(CAMERA_KEY, JSON.stringify(next));
    console.info(`NZTA sync: ${next.cameras.length} cameras, +${next.change.added}/-${next.change.removed}`);
    return next;
  } catch (error) {
    const retained = {
      ...previous,
      lastSuccessfulAt: previous.lastSuccessfulAt ?? (previous.syncStatus === 'live' ? previous.checkedAt : null) ?? null,
      checkedAt: new Date().toISOString(),
      syncStatus: 'stale',
      syncError: String(error.message || error)
    };
    await env.CAMERA_DATA.put(CAMERA_KEY, JSON.stringify(retained));
    console.warn(`NZTA sync failed; retained ${retained.cameras.length} validated cameras: ${retained.syncError}`);
    return retained;
  }
}

function validateCoordinatePair(value) { return parseLonLat(value); }
function validateNzCoordinatePair(value) { return parseNzLonLat(value); }

/** Every intermediate stop must be a valid coordinate. A malformed entry is
 * rejected instead of being dropped, which silently changed the route. */
export function parseStops(value: string | null): ReturnType<typeof parseLonLat>[] | null {
  if (value == null || value === '') return [];
  const entries = value.split(';');
  if (entries.length > 24) return null;
  const stops = entries.map((entry) => validateCoordinatePair(entry.trim()));
  return stops.every(Boolean) ? stops : null;
}

async function upstreamJson(url, headers = {}) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new UpstreamError(`Map service HTTP ${response.status}`);
  try { return await response.json<ProviderPayload>(); }
  catch (error) { throw new UpstreamError('Map service returned invalid JSON', { cause: error }); }
}

/**
 * Optional area filter for /api/road-events. Without `bbox` or `radiusMeters`
 * the response is unchanged (`near` alone still only selects the region).
 * Returns null for an invalid area.
 */
export function parseRoadEventArea(url: URL) {
  const rawBox = url.searchParams.get('bbox');
  const rawRadius = url.searchParams.get('radiusMeters');
  if (rawBox != null) {
    const box = rawBox.split(',').map((value) => Number(value));
    if (box.length !== 4 || !box.every(Number.isFinite)) return null;
    const [west, south, east, north] = box;
    if (west < -180 || east > 180 || south < -90 || north > 90 || west >= east || south >= north ||
        east - west > 10 || north - south > 10) return null;
    const inside = (p) => p && p.longitude >= west && p.longitude <= east && p.latitude >= south && p.latitude <= north;
    return { bounds: { west, south, east, north }, center: [(west + east) / 2, (south + north) / 2] as [number, number],
      matches: (event) => inside(event?.location) || (Array.isArray(event?.geometry) && event.geometry.some(inside)) };
  }
  if (rawRadius != null) {
    const near = parseLonLat(url.searchParams.get('near'));
    const radius = Number(rawRadius);
    if (!near || !Number.isFinite(radius) || radius < 100 || radius > 300_000) return null;
    const latPad = radius / 111_320, lonPad = radius / (111_320 * Math.max(0.01, Math.cos(near[1] * Math.PI / 180)));
    const close = (p) => p && Number.isFinite(p.longitude) && Number.isFinite(p.latitude) &&
      distanceMeters(near, [p.longitude, p.latitude]) <= radius;
    return { bounds: { west: near[0] - lonPad, south: near[1] - latPad, east: near[0] + lonPad, north: near[1] + latPad },
      center: near, matches: (event) => close(event?.location) || (Array.isArray(event?.geometry) && event.geometry.some(close)) };
  }
  return { bounds: null, center: null, matches: null };
}

/** Signed-in callers share by account; anonymous callers by a pseudonymous
 * IP key. Only consulted when the owned NZ engine would be used. */
async function routingClientKey(request: Request, env) {
  if (env.USER_DB && /(?:^|;\s*)(?:waybi|kiwi)_session=/.test(request.headers.get('cookie') || '')) {
    const user = await userFromRequest(env.USER_DB, request).catch(() => null);
    if (user?.id) return `user:${user.id}`;
  }
  return `ip:${await clientFingerprint(env, clientIp(request))}`;
}

async function handleApi(request: Request, env, ctx) {
  const url = new URL(request.url);
  if (url.pathname === '/api/navigation-feedback') {
    if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
    if (clientKind(request) !== 'mobile') return json({ error: 'Invalid feedback client' }, 403);
    if (!env.USER_DB) return json({ error: 'Feedback storage unavailable' }, 503);
    const raw = await request.text();
    if (raw.length > 1024) return json({ error: 'Feedback is too large' }, 413);
    let body;
    try {
      body = JSON.parse(raw);
      if (!body || typeof body.id !== 'string' || !/^[a-f0-9]{32}$/.test(body.id) || ![-1, 1].includes(body.vote)) throw new Error();
    } catch { return json({ error: 'Invalid feedback vote' }, 400); }
    await saveNavigationFeedback(env.USER_DB, body);
    return json({ ok: true }, 202);
  }
  if (url.pathname === '/api/telemetry/usage' && request.method === 'POST') {
    if (clientKind(request) !== 'mobile') {
      return json({ error: 'Invalid telemetry client' }, 403);
    }
    const body = await request.json<ProviderPayload>().catch(() => null);
    const events = {
      google_navigation_destination: ['google', 'navigation_destination'],
      mapbox_navigation_trip: ['mapbox', 'navigation_trip'],
      mapbox_search_session: ['mapbox', 'search_session']
    };
    const event = events[body?.event];
    if (!event) return json({ error: 'Unknown usage event' }, 400);
    const units = Math.max(1, Math.min(25, Math.round(Number(body?.units) || 1)));
    ctx.waitUntil(recordApiUsage(env, {
      provider: event[0],
      sku: event[1],
      calls: 1,
      units
    }));
    return json({ ok: true }, 202);
  }
  if (url.pathname === '/api/road-reports' && request.method === 'POST') {
    if (clientKind(request) !== 'mobile') return json({ error: 'Mobile client required' }, 403);
    if (!env.USER_DB) return json({ error: 'Report account storage unavailable' }, 503);
    const reporter = await roadReportAuthor(env.USER_DB, request);
    if (!reporter) return json({ error: 'Sign in to report a road event' }, 401);
    if (Number(request.headers.get('content-length')) > 2048) return json({ error: 'Report is too large' }, 413);
    const raw = await request.text();
    if (raw.length > 2048) return json({ error: 'Report is too large' }, 413);
    let payload: ProviderPayload;
    try { payload = JSON.parse(raw); }
    catch { return json({ error: 'Invalid road report JSON' }, 400); }
    if (!validRoadReportInput(payload)) return json({ error: 'Valid global road report required' }, 400);
    // Authenticated writes are bounded across all Worker regions via D1.
    if (!await reserveRoadReportQuota(env.USER_DB, reporter.id)) {
      return json({ error: 'Road report limit reached. Try again tomorrow.' }, 429);
    }
    try {
      const report = await createRoadReport(env, payload, reporter);
      return json({ ok: true, report }, 201);
    } catch (error) {
      console.error(JSON.stringify({ level: 'error', event: 'road_report_write_failed',
        errorName: error?.name, message: String(error?.message || error).slice(0, 200) }));
      // The report was not stored, so it must not count against the user.
      await refundRoadReportQuota(env.USER_DB, reporter.id).catch(() => {});
      return json({ error: 'Road reports are temporarily unavailable. Please try again.' }, 503);
    }
  }
  if (url.pathname === '/api/cameras/sync' && request.method === 'POST') {
    if (!env.USER_DB) return json({ error: 'Account storage is not configured' }, 503);
    if (clientKind(request) !== 'mobile') {
      return json({ error: 'Invalid client' }, 403);
    }
    const user = await userFromRequest(env.USER_DB, request);
    if (!user) return json({ error: 'Sign in required', code: 'SIGN_IN_REQUIRED' }, 401);
    if (!await userHasPlus(env.USER_DB, user.id)) {
      return json({
        error: 'Waybi Plus is required to check NZTA camera updates now',
        code: 'PLUS_REQUIRED'
      }, 403);
    }

    const current = await readCameraState(env);
    const checkedAt = Date.parse(current.checkedAt || '');
    const recentlyChecked =
      current.syncStatus !== 'seed' &&
      Number.isFinite(checkedAt) &&
      Date.now() >= checkedAt &&
      Date.now() - checkedAt < CAMERA_SYNC_COOLDOWN_MS;
    const state = recentlyChecked ? current : await syncCameras(env);
    // A successful manual check must also replace this PoP's older public copy.
    await writePublicEdgeJson(`${url.origin}/__edge-cache/cameras/v1`, state, 3600);
    return json({
      ...state,
      source: SOURCE_URL,
      skipped: recentlyChecked,
      cooldownSeconds: Math.round(CAMERA_SYNC_COOLDOWN_MS / 1000)
    });
  }
  if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
  if (url.pathname === '/api/admin/costs') {
    const configuredAdmins = String(env.ADMIN_EMAILS || '')
      .split(',')
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean);
    const user = env.USER_DB ? await userFromRequest(env.USER_DB, request) : null;
    if (!user || !configuredAdmins.includes(String(user.email || '').toLowerCase())) {
      return json({ error: 'Admin access required' }, 403);
    }
    const days = Number.parseInt(url.searchParams.get('days') || '31', 10);
    return json(await readUsageSummary(env, days));
  }
  if (url.pathname === '/api/config') {
    if (!env.GOOGLE_MAPS_BROWSER_API_KEY) {
      return json({ error: 'Google Maps browser key is not configured' }, 503);
    }
    return json({
      googleMapsApiKey: env.GOOGLE_MAPS_BROWSER_API_KEY,
      googleMapId: env.GOOGLE_MAP_ID || null
    });
  }
  if (url.pathname === '/api/health') {
    const state = await readCameraState(env);
    return json({
      ok: true,
      cameraCount: state.cameras.length,
      syncStatus: state.syncStatus,
      sourceUpdatedAt: state.sourceUpdatedAt,
      checkedAt: state.checkedAt,
      lastSuccessfulAt: state.lastSuccessfulAt ?? null,
      fetchMode: state.fetchMode ?? null
    });
  }
  if (url.pathname === '/api/cameras') {
    // Public camera metadata is shared by every visitor. An edge read cache
    // avoids one billable KV get per user, without caching private accounts.
    const cacheKey = `${url.origin}/__edge-cache/cameras/v1`;
    const cached = await readPublicEdgeJson<{ cameras: unknown[] }>(cacheKey);
    const validCached = Array.isArray(cached?.cameras) && cached.cameras.length >= 50;
    const state = validCached ? cached : await readCameraState(env);
    if (!validCached) await writePublicEdgeJson(cacheKey, state, 3600);
    // The bundled seed is safe to read; an empty KV must not cause every
    // visitor to launch a competing global sync (and one KV put each).
    const result = json({ ...state, source: SOURCE_URL });
    result.headers.set('cache-control', 'public, max-age=300, s-maxage=3600');
    return result;
  }
  if (url.pathname === '/api/transit-lanes') {
    const result=json(await readTransitSnapshot(env));
    result.headers.set('cache-control','public, max-age=86400, s-maxage=86400');
    return result;
  }
  if (url.pathname === '/api/road-events') {
    const area = parseRoadEventArea(url);
    if (!area) {
      return json({ error: 'bbox must be west,south,east,north (at most 10°), or near with radiusMeters 100–300000' }, 400);
    }
    const reports = await readRoadReports(env, new Date(), area.bounds);
    let state;
    try { state = await loadRegionalRoadEvents(env,
      parseLonLat(url.searchParams.get('near')) || area.center, url.searchParams.get('country') || 'NZ'); }
    catch { state = { events: [], syncStatus: 'unavailable' }; }
    const events = [...reports, ...state.events];
    return json({ ...state, events: area.matches ? events.filter(area.matches) : events });
  }
  if (url.pathname.startsWith('/api/map/traffic/tiles/')) return handleTrafficTile(request, env);
  if (url.pathname === '/api/traffic-flow') {
    // The Cron owns all authoritative traffic-flow writes. Serving an empty
    // snapshot must not let many incoming drivers race to refresh KV.
    const cacheKey = `${url.origin}/__edge-cache/traffic-flow/v1`;
    const cached = await readPublicEdgeJson<{ segments?: unknown[] }>(cacheKey);
    if (Array.isArray(cached?.segments) && cached.segments.length) {
      const result = json(cached);
      result.headers.set('cache-control', 'public, max-age=30');
      return result;
    }
    const state = await readTrafficFlowState(env);
    if (!state) return json({ error: 'Traffic snapshot unavailable; retry shortly' }, 503);
    await writePublicEdgeJson(cacheKey, state, 30);
    const result = json(state);
    result.headers.set('cache-control', 'public, max-age=30');
    return result;
  }
  if (url.pathname === '/api/parking') {
    const at = validateNzCoordinatePair(url.searchParams.get('at'));
    if (!at) return json({ error: 'Valid NZ coordinate required' }, 400);
    try {
      return json({ places: await nearbyAtParking(at), source: 'Auckland Transport Open GIS', sourceUrl: AT_PARKING_SOURCE });
    } catch (error) {
      console.warn('AT parking query failed', error);
      return json({ error: 'Parking data temporarily unavailable' }, 502);
    }
  }
  if (url.pathname === '/api/speed-limit') {
    const at = validateCoordinatePair(url.searchParams.get('at'));
    if (!at) return json({ error: 'Valid coordinate required' }, 400);
    if (!parseNzLonLat(url.searchParams.get('at'))) {
      return json({ speedLimitKph: null, available: false, coverage: ['NZ'], source: null });
    }

    // Speed zones change rarely; share one upstream lookup per ~11 m cell
    // for an hour at this PoP instead of one ArcGIS query per GPS fix.
    const longitude = Math.round(at[0] * 1e4) / 1e4;
    const latitude = Math.round(at[1] * 1e4) / 1e4;
    const cacheKey = `${url.origin}/__edge-cache/speed-limit/v1/${longitude.toFixed(4)},${latitude.toFixed(4)}`;
    const cached = await readPublicEdgeJson<Record<string, unknown>>(cacheKey);
    if (cached && 'speedLimitKph' in cached) return json(cached);
    const params = new URLSearchParams({
      f: 'json',
      geometry: `${longitude},${latitude}`,
      geometryType: 'esriGeometryPoint',
      inSR: '4326',
      spatialRel: 'esriSpatialRelIntersects',
      outFields: 'speedLimitZoneValue,speedLimitZoneMaxValue,speedLimitZoneName,whenEffective,whenIneffective',
      returnGeometry: 'false'
    });
    const nslrUrl =
      'https://services.arcgis.com/CXBb7LAjgIIdcsPt/arcgis/rest/services/' +
      'SpeedLimitZoneFull__View/FeatureServer/0/query?' +
      params.toString();
    const result = await upstreamJson(nslrUrl, {
      accept: 'application/json',
      'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)'
    });
    const now = Date.now();
    const current = (result.features || [])
      .map((feature) => feature.attributes || {})
      .filter((attributes) => {
        const starts = attributes.whenEffective == null || Number(attributes.whenEffective) <= now;
        const active = attributes.whenIneffective == null || Number(attributes.whenIneffective) > now;
        return starts && active;
      })
      .sort((a, b) => Number(b.whenEffective || 0) - Number(a.whenEffective || 0))[0];

    const parsed = current
      ? Number.parseInt(String(current.speedLimitZoneValue || current.speedLimitZoneMaxValue || ''), 10)
      : NaN;
    const body = current ? {
      speedLimitKph: Number.isFinite(parsed) ? parsed : null,
      zoneName: current.speedLimitZoneName || null,
      source: 'NZTA National Speed Limit Register',
      sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
    } : {
      speedLimitKph: null,
      source: 'NZTA National Speed Limit Register',
      sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
    };
    // A zone that starts or ends within the hour must not be cached past it.
    const boundaries = (result.features || []).flatMap((feature) => [feature.attributes?.whenEffective, feature.attributes?.whenIneffective])
      .map(Number).filter((time) => Number.isFinite(time) && time > now);
    const ttl = Math.max(60, Math.min(3600, Math.floor((Math.min(now + 3_600_000, ...boundaries) - now) / 1000)));
    await writePublicEdgeJson(cacheKey, body, ttl);
    return json(body);
  }
  if (url.pathname === '/api/route-options') {
    const from = validateCoordinatePair(url.searchParams.get('from'));
    const to = validateCoordinatePair(url.searchParams.get('to'));
    if (!from || !to) return json({ error: 'Valid coordinates required' }, 400);
    const stops = parseStops(url.searchParams.get('stops'));
    if (!stops) return json({ error: 'stops must be up to 23 longitude,latitude pairs separated by ;' }, 400);
    if (stops.length > 23) return json({ error: 'At most 23 intermediate stops are supported' }, 400);
    const requestedMode = url.searchParams.get('mode');
    const googleMode = requestedMode == null ? null : ({
      drive: 'DRIVE',
      transit: 'TRANSIT',
      walk: 'WALK',
      bicycle: 'BICYCLE'
    })[requestedMode];
    if (requestedMode != null && !googleMode) {
      return json({ error: 'mode must be drive, transit, walk or bicycle' }, 400);
    }
    if (crossesTasmanSea([from, ...stops, to])) {
      return json({
        code: 'NO_LAND_ROUTE',
        error: 'No land route is available between New Zealand and Australia',
      }, 422);
    }
    if (stops.length && googleMode === 'TRANSIT') {
      return json({ error: 'Transit route options do not support intermediate stops' }, 400);
    }
    const requestedProvider = url.searchParams.get('provider');
    if (requestedProvider && requestedProvider !== 'independent') {
      return json({ error: 'provider must be independent when specified' }, 400);
    }
    if (requestedProvider === 'independent' && googleMode === 'TRANSIT') {
      return json({ error: 'Waybi Map transit uses the transit routing endpoint' }, 400);
    }
    const alternatives = url.searchParams.get('alternatives');
    if (alternatives != null && alternatives !== 'true' && alternatives !== 'false') {
      return json({ error: 'alternatives must be true or false' }, 400);
    }
    const rawHeading = url.searchParams.get('heading');
    const headingDegrees = rawHeading == null ? null : Number(rawHeading);
    if (rawHeading != null && !Number.isFinite(headingDegrees)) {
      return json({ error: 'heading must be a finite number' }, 400);
    }
    const exclusions = parseRouteExclusions(url.searchParams.get('avoid'));
    if (exclusions == null) return json({ error: 'avoid requires up to 32 lon,lat,heading entries' }, 400);
    let ownedEngine = false;
    try { ownedEngine = Boolean(nzRoutingEndpoint(env, [from, ...stops, to])); } catch { /* misconfigured engine: routeOptions falls back */ }
    return json(await routeOptions(
      from,
      to,
      env,
      stops,
      googleMode ? [googleMode] : null,
      (provider, sku, units) => ctx.waitUntil(
        recordApiUsage(env, { provider, sku, calls: units, units })
      ),
      {
        forceIndependent: requestedProvider === 'independent',
        exclusions,
        alternatives: alternatives == null ? undefined : alternatives === 'true',
        headingDegrees,
        language: url.searchParams.get('lang') === 'zh' ? 'zh' : 'en',
        routingClientKey: ownedEngine ? await routingClientKey(request, env) : undefined,
        reserveGoogle: (sku, units) => reserveGoogleUnits(env, sku, units),
      }
    ));
  }
  if (url.pathname === '/api/independent-place-details') {
    return independentPlaceDetails(url, env);
  }
  if (url.pathname === '/api/search') {
    if (url.searchParams.get('provider') === 'independent') {
      // Keep Waybi's fallback inside the same bounded, cached search stack.
      // Public Nominatim is a legacy compatibility path, not typeahead.
      const suggestUrl = new URL(url);
      suggestUrl.pathname = '/api/suggest';
      return handlePlaces(new Request(suggestUrl, request), env,
        (provider, sku, units) => ctx.waitUntil(recordApiUsage(env, { provider, sku, calls: units, units })), ctx);
    }
    const query = (url.searchParams.get('q') || '').trim();
    if ([...query].length < 2 || query.length > 120) return json({ error: 'Search query must be 2–120 characters' }, 400);
    const prefersChinese = url.searchParams.get('lang') === 'zh' || /[\u3400-\u9fff\uf900-\ufaff]/u.test(query);
    const near = validateCoordinatePair(url.searchParams.get('near'));
    const enrichmentPromise = loadSearchEnrichments(query, near).catch(() => []);
    const search = new URL('https://nominatim.openstreetmap.org/search');
    search.searchParams.set('format', 'jsonv2');
    search.searchParams.set('addressdetails', '1');
    search.searchParams.set('namedetails', '1');
    search.searchParams.set('accept-language', prefersChinese ? 'zh,en' : 'en');
    search.searchParams.set('limit', '12');
    search.searchParams.set('q', query);
    if (near) {
      const lonDelta = 0.75;
      const latDelta = 0.55;
      search.searchParams.set('viewbox', [near[0] - lonDelta, near[1] + latDelta, near[0] + lonDelta, near[1] - latDelta].join(','));
      search.searchParams.set('bounded', '0');
    }
    // Serialized per isolate at Nominatim's one-request-per-second policy.
    const results = await nominatimArray(search);
    const globalResults = results.map((place) => {
      const address = place.address || {};
      const poiClasses = new Set([
        'amenity', 'tourism', 'shop', 'office', 'leisure', 'healthcare',
        'craft', 'historic', 'railway', 'aeroway', 'club', 'sport'
      ]);
      const isPoi = poiClasses.has(place.class);
      const streetAddress = [
        [address.house_number, address.road || address.pedestrian].filter(Boolean).join(' '),
        address.suburb || address.neighbourhood,
        address.city || address.town || address.village,
        address.postcode,
        address.country
      ].filter(Boolean).filter((item, index, values) => values.indexOf(item) === index).join(', ');
      const fullAddress = place.display_name || streetAddress;
      const name = isPoi
        ? (place.name || place.namedetails?.name || fullAddress)
        : fullAddress;
      return {
        id: place.place_id,
        provider: 'osm',
        name,
        address: isPoi ? (streetAddress || fullAddress) : fullAddress,
        label: fullAddress,
        isPoi,
        latitude: Number(place.lat),
        longitude: Number(place.lon)
      };
    });
    const enrichments = await enrichmentPromise;
    return json(
      mergeAndRankSearchResults([enrichments, globalResults], query, near, 12)
    );
  }
  if (url.pathname === '/api/route') {
    const from = validateCoordinatePair(url.searchParams.get('from'));
    const to = validateCoordinatePair(url.searchParams.get('to'));
    if (!from || !to) return json({ error: 'Valid coordinates required' }, 400);
    const stops = parseStops(url.searchParams.get('stops'));
    if (!stops) return json({ error: 'stops must be up to 23 longitude,latitude pairs separated by ;' }, 400);
    if (stops.length > 23) return json({ error: 'At most 23 intermediate stops are supported' }, 400);
    const points = [from, ...stops, to];
    const routeUrl = `https://routing.openstreetmap.de/routed-car/route/v1/driving/${points.map((point) => point.join(',')).join(';')}?overview=full&geometries=geojson&steps=true`;
    const result = await upstreamJson(routeUrl, { 'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)', referer: 'https://routing.openstreetmap.de/', accept: 'application/json' });
    if (result.code !== 'Ok' || !result.routes?.length) return json({ error: 'No driving route found' }, 422);
    const selected = result.routes[0];
    const steps = selected.legs.flatMap((leg) => leg.steps.map((step) => {
      const lanes = maneuverLanes(step).map((lane) => ({
        indications: Array.isArray(lane.indications) ? lane.indications : [],
        valid: lane.valid === true,
        ...(typeof lane.active === 'boolean' ? { active: lane.active } : {})
      }));
      return {
        distance: step.distance,
        duration: step.duration,
        name: step.name || '',
        maneuver: step.maneuver?.type || 'continue',
        modifier: step.maneuver?.modifier || '',
        instruction: [step.maneuver?.type, step.maneuver?.modifier, step.name].filter(Boolean).join(' '),
        location: step.maneuver.location,
        ...(lanes?.length ? { lanes } : {})
      };
    }));
    return json({ coordinates: selected.geometry.coordinates, distance: selected.distance, duration: selected.duration, steps });
  }
  return json({ error: 'Not found' }, 404);
}

export default {
  async fetch(request: Request, env, ctx) {
    const requestUrl = new URL(request.url);
    const pathname = requestUrl.pathname;
    const canonicalHost =
      requestUrl.hostname === 'www.waybi.co' ||
      (requestUrl.hostname === 'waybi.nzs.workers.dev' && !pathname.startsWith('/api/'))
        ? 'waybi.co'
        : requestUrl.hostname;
    if (requestUrl.protocol !== 'https:' || canonicalHost !== requestUrl.hostname) {
      requestUrl.protocol = 'https:';
      requestUrl.hostname = canonicalHost;
      requestUrl.port = '';
      return Response.redirect(requestUrl.toString(), 301);
    }
    if (!pathname.startsWith('/api/')) {
      const voiceLanding = voicePackLandingPage(request);
      if (voiceLanding) return voiceLanding;
      const productSurface =
        pathname === '/app' || pathname.startsWith('/app/') ||
        pathname === '/dashboard' || pathname.startsWith('/dashboard/');
      const assetRequest = productSurface
        ? new Request(new URL('/', request.url), request)
        : request;
      const response = await env.ASSETS.fetch(assetRequest);
      if (!productSurface) return response;

      const headers = new Headers(response.headers);
      headers.set('x-robots-tag', 'noindex, follow');
      headers.set('cache-control', 'private, no-cache');
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    }
    if (env.WAYBI_MIGRATION_PAUSED === 'true') {
      return new Response(JSON.stringify({ error: 'Service updating. Please retry shortly.' }), {
        status: 503,
        headers: { 'Content-Type': 'application/json', 'Retry-After': '60' }
      });
    }
    const requestId = crypto.randomUUID();
    try {
      const limited = await guardApiRequest(request, env);
      if (limited) return limited;
      const featureResponse =
        await handleGooglePlacePicker(request, env, ctx) ||
        await handleRoadIntelligence(request, env, ctx, readCameraState) ||
        await handleBilling(request, env) ||
        await handleAccount(request, env, ctx) ||
        await handleVoicePacks(request, env) ||
        await handleRouteWatchAlerts(request, env) ||
        await handleRouteWatch(request, env) ||
        await handlePlaces(
          request,
          env,
          (provider, sku, units) => ctx.waitUntil(
            recordApiUsage(env, { provider, sku, calls: units, units })
          ),
          ctx
        );
      if (featureResponse) return featureResponse;
      return await handleApi(request, env, ctx);
    } catch (error) {
      // Generic body with a request id; details go to the structured log only.
      return apiErrorResponse(error, request, requestId);
    }
  },
  async scheduled(event, env, ctx) {
    if (env.WAYBI_MIGRATION_PAUSED === 'true') return;
    if (event.cron === '*/5 * * * *') {
      ctx.waitUntil(sendGoogleSearchAlerts(env));
      ctx.waitUntil(refreshTrafficFlowState(env));
      return;
    }
    if (event.cron === '*/10 * * * *') {
      ctx.waitUntil(refreshRoadEventState(env));
      ctx.waitUntil(refreshNswRoadEventState(env));
      return;
    }
    if (event.cron === '*/15 * * * *') {
      ctx.waitUntil(refreshAppleAuthorizations(env));
      ctx.waitUntil(syncAllAppleSubscriptions(env));
      return;
    }
    if (event.cron === ROUTE_WATCH_CRON) {
      ctx.waitUntil(evaluateAllRouteWatches(env));
      return;
    }
    if (event.cron === '0 3 * * *') {
      ctx.waitUntil(syncCameras(env));
      ctx.waitUntil(refreshTransitSnapshot(env));
      ctx.waitUntil(runDailyCleanup(env));
    }
  }
};
