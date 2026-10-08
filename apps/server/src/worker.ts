import type { ProviderPayload } from "./types.ts";
import { loadSearchEnrichments, mergeAndRankSearchResults } from './search/search_orchestrator.ts';
import { clientKind } from './brand_compat.ts';
import { saveNavigationFeedback } from './navigation_feedback.ts';
import { handleTrafficTile } from './traffic_tiles.ts';
import { parseLonLat, parseNzLonLat } from './geo.ts';
import { rankPlaces } from './place_search_rank.ts';
import seed from '../data/cameras.json' with { type: 'json' };
import { fetchNztaCameras, SOURCE_URL } from './sync.ts';
import { handleAccount, roadReportAuthor, userFromRequest, userHasPlus } from './auth.ts';
import { syncAllAppleSubscriptions } from './apple_billing.ts';
import { handleBilling } from './billing.ts';
import { handlePlaces } from './places.ts';
import { independentPlaceDetails } from './independent_place_details.ts';
import { routeOptions } from './routes.ts';
import { nearbyAtParking, AT_PARKING_SOURCE } from './parking.ts';
import { loadRoadEventState, refreshRoadEventState } from './road_events.ts';
import { refreshNswRoadEventState } from './au_road_events.ts';
import { loadRegionalRoadEvents } from './regional_road_events.ts';
import { readTrafficFlowState, refreshTrafficFlowState } from './traffic_flow.ts';
import { handleRoadIntelligence } from './road_intelligence_api.ts';
import { createRoadReport, readRoadReports } from './road_reports.ts';
import { recordApiUsage, readUsageSummary } from './cost_guard.ts';
import {
  evaluateAllRouteWatches,
  handleRouteWatch,
  handleRouteWatchAlerts,
} from './route_watch.ts';

const CAMERA_KEY = 'cameras/current';
const CAMERA_SYNC_COOLDOWN_MS = 10 * 60 * 1000;
let lastSearchAt = 0;

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
    const next = {
      ...fresh,
      checkedAt: new Date().toISOString(),
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

async function upstreamJson(url, headers = {}) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Map service HTTP ${response.status}`);
  return response.json<ProviderPayload>();
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
    try {
      const reporter = env.USER_DB
        ? await roadReportAuthor(env.USER_DB, request)
        : null;
      const report = await createRoadReport(
        env,
        await request.json<ProviderPayload>(),
        reporter
      );
      return json({ ok: true, report }, 201);
    } catch (error) {
      return json({ error: String(error.message || error) }, 400);
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
      current.syncStatus === 'live' &&
      Number.isFinite(checkedAt) &&
      Date.now() - checkedAt < CAMERA_SYNC_COOLDOWN_MS;
    const state = recentlyChecked ? current : await syncCameras(env);
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
      fetchMode: state.fetchMode ?? null
    });
  }
  if (url.pathname === '/api/cameras') {
    const state = await readCameraState(env);
    if (state.syncStatus === 'seed') ctx.waitUntil(syncCameras(env));
    return json({ ...state, source: SOURCE_URL });
  }
  if (url.pathname === '/api/road-events') {
    const reports = await readRoadReports(env);
    let state;
    try { state = await loadRegionalRoadEvents(env,
      parseLonLat(url.searchParams.get('near')), url.searchParams.get('country') || 'NZ'); }
    catch { state = { events: [], syncStatus: 'unavailable' }; }
    return json({ ...state, events: [...reports, ...state.events] });
  }
  if (url.pathname.startsWith('/api/map/traffic/tiles/')) return handleTrafficTile(request, env);
  if (url.pathname === '/api/traffic-flow') {
    const state = await readTrafficFlowState(env);
    return json(state ?? await refreshTrafficFlowState(env));
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

    const [longitude, latitude] = at;
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

    if (!current) {
      return json({
        speedLimitKph: null,
        source: 'NZTA National Speed Limit Register',
        sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
      });
    }

    const parsed = Number.parseInt(String(current.speedLimitZoneValue || current.speedLimitZoneMaxValue || ''), 10);
    return json({
      speedLimitKph: Number.isFinite(parsed) ? parsed : null,
      zoneName: current.speedLimitZoneName || null,
      source: 'NZTA National Speed Limit Register',
      sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
    });
  }
  if (url.pathname === '/api/route-options') {
    const from = validateCoordinatePair(url.searchParams.get('from'));
    const to = validateCoordinatePair(url.searchParams.get('to'));
    if (!from || !to) return json({ error: 'Valid coordinates required' }, 400);
    const stops = (url.searchParams.get('stops') || '')
      .split(';')
      .filter(Boolean)
      .map((value) => validateCoordinatePair(value))
      .filter(Boolean);
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
        alternatives: alternatives == null ? undefined : alternatives === 'true',
        headingDegrees,
        language: url.searchParams.get('lang') === 'zh' ? 'zh' : 'en',
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
    const wait = Math.max(0, 1050 - (Date.now() - lastSearchAt));
    if (wait) await new Promise((resolve) => setTimeout(resolve, wait));
    lastSearchAt = Date.now();
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
    const results = await upstreamJson(search.toString(), { 'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)', 'referer': 'https://github.com/yaohuangguan/Waybi', accept: 'application/json' });
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
    const stops = (url.searchParams.get('stops') || '')
      .split(';')
      .filter(Boolean)
      .map((value) => validateCoordinatePair(value))
      .filter(Boolean);
    if (stops.length > 23) return json({ error: 'At most 23 intermediate stops are supported' }, 400);
    const points = [from, ...stops, to];
    const routeUrl = `https://routing.openstreetmap.de/routed-car/route/v1/driving/${points.map((point) => point.join(',')).join(';')}?overview=full&geometries=geojson&steps=true`;
    const result = await upstreamJson(routeUrl, { 'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)', referer: 'https://routing.openstreetmap.de/', accept: 'application/json' });
    if (result.code !== 'Ok' || !result.routes?.length) return json({ error: 'No driving route found' }, 422);
    const selected = result.routes[0];
    const steps = selected.legs.flatMap((leg) => leg.steps.map((step) => {
      const laneIntersection = step.intersections?.find((intersection) => Array.isArray(intersection.lanes) && intersection.lanes.length);
      const lanes = laneIntersection?.lanes?.map((lane) => ({
        indications: Array.isArray(lane.indications) ? lane.indications : [],
        valid: lane.valid === true
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
    try {
      const featureResponse =
        await handleRoadIntelligence(request, env, ctx, readCameraState) ||
        await handleBilling(request, env) ||
        await handleAccount(request, env) ||
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
      console.error(error);
      return json({ error: String(error.message || error) }, 502);
    }
  },
  async scheduled(event, env, ctx) {
    if (env.WAYBI_MIGRATION_PAUSED === 'true') return;
    if (event.cron === '*/5 * * * *') {
      ctx.waitUntil(refreshTrafficFlowState(env));
      return;
    }
    if (event.cron === '*/10 * * * *') {
      ctx.waitUntil(refreshRoadEventState(env));
      ctx.waitUntil(refreshNswRoadEventState(env));
      return;
    }
    if (event.cron === '*/15 * * * *') {
      ctx.waitUntil(syncAllAppleSubscriptions(env));
      ctx.waitUntil(evaluateAllRouteWatches(env));
      return;
    }
    if (event.cron === '0 */6 * * *') {
      ctx.waitUntil(syncCameras(env));
    }
  }
};
