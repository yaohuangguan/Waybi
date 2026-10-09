import type { ProviderPayload } from "./types.ts";
import type { LonLat, RouteRequestOptions, UsageRecorder } from './types.ts';
import { fetchNzRouting, nzRoutingEndpoint } from './nz_routing.ts';
import { readRouteRoadSnapshots } from './regional_road_events.ts';
import { matchRouteClosures, crossesExcludedRoads } from './routing_closures.ts';
import type { ClosureLocation } from './routing_closures.ts';
import { readTransitSnapshot, transitRoadBlocks } from './transit_lanes.ts';
const GOOGLE_ROUTES_URL = 'https://routes.googleapis.com/directions/v2:computeRoutes';

function seconds(value) {
  if (typeof value !== 'string' || !value.endsWith('s')) return null;
  const parsed = Number(value.slice(0, -1));
  return Number.isFinite(parsed) ? parsed : null;
}

function waypoint([longitude, latitude]: LonLat) {
  return { location: { latLng: { latitude, longitude } } };
}

function transitSummary(route) {
  const items = [];
  for (const leg of route.legs || []) {
    for (const step of leg.steps || []) {
      const details = step.transitDetails;
      if (!details) continue;
      const line = details.transitLine || {};
      const vehicle = line.vehicle || {};
      const stops = details.stopDetails || {};
      items.push({
        lineName: line.nameShort || line.name || '',
        headsign: details.headsign || '',
        vehicleType: vehicle.type || '',
        vehicleName: vehicle.name?.text || '',
        color: line.color || '',
        textColor: line.textColor || '',
        departureStop: stops.departureStop?.name || '',
        arrivalStop: stops.arrivalStop?.name || '',
        departureTime: stops.departureTime || null,
        arrivalTime: stops.arrivalTime || null,
        stopCount: Number(details.stopCount || 0),
        agencies: (line.agencies || []).map((agency) => agency.name).filter(Boolean)
      });
    }
  }
  return items;
}

function trafficIntervals(route) {
  return (route.travelAdvisory?.speedReadingIntervals || []).map((interval) => ({
    startPolylinePointIndex: Number(interval.startPolylinePointIndex || 0),
    endPolylinePointIndex: Number(interval.endPolylinePointIndex || 0),
    speed: interval.speed === 'TRAFFIC_JAM'
      ? 'trafficJam'
      : interval.speed === 'SLOW'
        ? 'slow'
        : 'normal'
  }));
}

function trafficSummary(intervals) {
  const counts = { normal: 0, slow: 0, trafficJam: 0 };
  for (const interval of intervals) counts[interval.speed] += 1;
  return counts;
}

function routeSteps(route) {
  const result = [];
  for (const leg of route.legs || []) {
    for (const step of leg.steps || []) {
      const instruction = step.navigationInstruction || {};
      const point = step.startLocation?.latLng;
      if (!point) continue;
      const maneuverName = String(instruction.maneuver || '').toLowerCase();
      const modifier = maneuverName.includes('left')
        ? 'left'
        : maneuverName.includes('right')
          ? 'right'
          : maneuverName.includes('uturn')
            ? 'uturn'
            : undefined;
      result.push({
        distance: Number(step.distanceMeters || 0),
        duration: seconds(step.staticDuration) || 0,
        name: '',
        instruction: instruction.instructions || '',
        maneuver: maneuverName.includes('roundabout')
          ? 'roundabout'
          : maneuverName.includes('destination')
            ? 'arrive'
            : maneuverName.includes('depart')
              ? 'depart'
              : 'turn',
        modifier,
        location: [Number(point.longitude), Number(point.latitude)]
      });
    }
  }
  return result;
}

async function googleModeRoutes(from, to, mode, apiKey, stops = []) {
  const driving = mode === 'DRIVE';
  const supportsStops = mode !== 'TRANSIT';
  const body = {
    origin: waypoint(from),
    destination: waypoint(to),
    ...(supportsStops && stops.length
      ? { intermediates: stops.slice(0, 23).map(waypoint) }
      : {}),
    travelMode: mode,
    computeAlternativeRoutes: driving && stops.length === 0,
    languageCode: 'en',
    units: 'METRIC',
    polylineQuality: 'HIGH_QUALITY',
    ...(driving ? { routingPreference: 'TRAFFIC_AWARE_OPTIMAL', extraComputations: ['TRAFFIC_ON_POLYLINE'] } : {})
  };

  const response = await fetch(GOOGLE_ROUTES_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-goog-api-key': apiKey,
      'x-goog-fieldmask': [
        'routes.duration',
        'routes.staticDuration',
        'routes.distanceMeters',
        'routes.polyline.encodedPolyline',
        'routes.routeLabels',
        'routes.description',
        'routes.routeToken',
        'routes.warnings',
        'routes.travelAdvisory.speedReadingIntervals',
        'routes.legs.steps.distanceMeters',
        'routes.legs.steps.staticDuration',
        'routes.legs.steps.startLocation',
        'routes.legs.steps.navigationInstruction',
        'routes.legs.steps.transitDetails'
      ].join(',')
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(`Google Routes ${mode} HTTP ${response.status}: ${detail.slice(0, 180)}`);
  }

  const payload = await response.json<ProviderPayload>();
  return (payload.routes || []).slice(0, driving ? 3 : 1).map((route, index) => {
    const durationSeconds = seconds(route.duration);
    const staticDurationSeconds = seconds(route.staticDuration);
    const intervals = trafficIntervals(route);
    const traffic = trafficSummary(intervals);
    const warnings = Array.isArray(route.warnings) ? route.warnings : [];
    return {
      id: `${mode.toLowerCase()}-${index}`,
      mode: mode.toLowerCase(),
      durationSeconds,
      staticDurationSeconds,
      trafficDelaySeconds: driving && durationSeconds != null && staticDurationSeconds != null
        ? Math.max(0, Math.round(durationSeconds - staticDurationSeconds))
        : null,
      distanceMeters: Number(route.distanceMeters || 0),
      encodedPolyline: route.polyline?.encodedPolyline || null,
      routeToken: route.routeToken || null,
      description: route.description || '',
      labels: Array.isArray(route.routeLabels) ? route.routeLabels : [],
      warnings,
      traffic,
      trafficIntervals: intervals,
      steps: routeSteps(route),
      transit: mode === 'TRANSIT' ? transitSummary(route) : [],
      provider: 'google'
    };
  });
}

async function fallbackDrivingRoutes(from, to, stops: LonLat[] = [], mode = 'DRIVE', options: RouteRequestOptions = {}) {
  const profile = ({ DRIVE: 'car', WALK: 'foot', BICYCLE: 'bike' })[mode];
  if (!profile) throw new Error('Transit routes require a transit provider');
  const points = [from, ...stops.slice(0, 23), to];
  const routeUrl = new URL(
    `https://routing.openstreetmap.de/routed-${profile}/route/v1/driving/${points.map((point) => point.join(',')).join(';')}`
  );
  routeUrl.searchParams.set('overview', 'full');
  routeUrl.searchParams.set('geometries', 'geojson');
  routeUrl.searchParams.set('steps', 'true');
  routeUrl.searchParams.set(
    'alternatives',
    stops.length || options.alternatives === false ? 'false' : '3'
  );
  if (Number.isFinite(options.headingDegrees)) {
    const normalized = Math.round(((options.headingDegrees % 360) + 360) % 360);
    routeUrl.searchParams.set(
      'bearings',
      [`${normalized},90`, ...points.slice(1).map(() => '')].join(';')
    );
  }
  const response = await fetch(routeUrl, {
    headers: {
      'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)',
      referer: 'https://routing.openstreetmap.de/',
      accept: 'application/json'
    },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`Fallback route HTTP ${response.status}`);
  const payload = await response.json<ProviderPayload>();
  if (payload.code !== 'Ok') throw new Error('Fallback route unavailable');
  return normalizeOsrmRoutes(payload, mode);
}

export function maneuverLanes(step: ProviderPayload) {
  // OSRM's first intersection belongs to this maneuver. The rest describe
  // junctions further along the outgoing road, not additional incoming lanes.
  const intersection = step.intersections?.[0];
  if (!intersection) return [];
  const at = step.maneuver?.location;
  const location = intersection.location;
  if (Array.isArray(at) && Array.isArray(location) &&
      (Math.abs(at[0] - location[0]) > 0.00001 || Math.abs(at[1] - location[1]) > 0.00001)) {
    return [];
  }
  return Array.isArray(intersection.lanes) ? intersection.lanes : [];
}

export function normalizeOsrmRoutes(payload: ProviderPayload, mode: string) {
  return (payload.routes || []).slice(0, 3).map((route, index) => ({
    id: `${mode.toLowerCase()}-${index}`,
    mode: mode.toLowerCase(),
    durationSeconds: Number(route.duration || 0),
    staticDurationSeconds: Number(route.duration || 0),
    trafficDelaySeconds: null,
    distanceMeters: Number(route.distance || 0),
    coordinates: route.geometry?.coordinates || [],
    encodedPolyline: null,
    routeToken: null,
    description: index === 0 ? 'Recommended route' : `Alternative ${index + 1}`,
    labels: [],
    warnings: [],
    traffic: { normal: 0, slow: 0, trafficJam: 0 },
    trafficIntervals: [],
    steps: (route.legs || []).flatMap((leg) => (leg.steps || []).map((step) => ({
      distance: Number(step.distance || 0), duration: Number(step.duration || 0),
      name: step.name || '', maneuver: step.maneuver?.type || '',
      modifier: step.maneuver?.modifier || '', location: step.maneuver?.location || [],
      instruction: step.maneuver?.instruction || '',
      lanes: maneuverLanes(step)
    }))),
    transit: [],
    provider: 'osm-fallback'
  }));
}

export async function routeOptions(
  from,
  to,
  env,
  stops = [],
  requestedModes = null,
  trackUsage: UsageRecorder = () => {},
  options: RouteRequestOptions = {}
) {
  const forceIndependent = options.forceIndependent === true;
  if (!forceIndependent && env.GOOGLE_ROUTES_API_KEY) {
    const defaultModes = stops.length
      ? ['DRIVE', 'WALK', 'BICYCLE']
      : ['DRIVE', 'TRANSIT', 'WALK', 'BICYCLE'];
    const modes = requestedModes?.length ? requestedModes : defaultModes;
    trackUsage('google', 'routes_compute', modes.length);
    const settled = await Promise.allSettled(
      modes.map((mode) => googleModeRoutes(from, to, mode, env.GOOGLE_ROUTES_API_KEY, stops))
    );
    const options = settled.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
    const driving = options.filter((option) => option.mode === 'drive');
    if (options.length && (driving.length || requestedModes?.length)) {
      return {
        provider: 'google',
        trafficAvailable: driving.some((option) => option.trafficIntervals.length > 0),
        stopsApplied: stops.length,
        options: await applyTransitRoadRestrictions(options, env)
      };
    }
  }

  const modes = requestedModes?.length ? requestedModes : ['DRIVE'];
  const points: LonLat[] = [from, ...stops, to];
  const fetchIndependent = async (mode: string, exclusions: ClosureLocation[] = []) => {
    if (nzRoutingEndpoint(env, points)) {
      try {
        return normalizeOsrmRoutes(await fetchNzRouting(env, points, mode, options, exclusions), mode);
      } catch (error) {
        // A failed exclusion request must not quietly drop its exclusions.
        if (exclusions.length) throw error;
      }
    }
    if (exclusions.length) throw new Error('No engine supports these road exclusions');
    return fallbackDrivingRoutes(from, to, stops, mode, options);
  };
  const settled = await Promise.allSettled(
    modes.map(mode => fetchIndependent(mode))
  );
  let driving = settled.flatMap((result) =>
    result.status === 'fulfilled' ? result.value : []
  );
  if (!driving.length) throw new Error('No routes available for the requested travel mode');
  let roadAwareness = null;
  if (forceIndependent && driving.some(route => route.mode === 'drive')) {
    const now = new Date();
    const snapshot = await readRouteRoadSnapshots(env, driving, now);
    const blocked = driving.filter(route => route.mode === 'drive').map(route => ({
      route, matches: matchRouteClosures(route, snapshot.events, now),
    }));
    const clear = blocked.filter(item => !item.matches.length).map(item => item.route);
    let selected = clear;
    let avoidance = 'unchecked';
    if (blocked.length && blocked.some(item => item.matches.length)) {
      avoidance = clear.length ? 'alternative' : 'blocked';
      if (!clear.length && nzRoutingEndpoint(env, points)) {
        const locations = blocked.flatMap(item => item.matches.flatMap(match => match.locations));
        const unique = [...new Map(locations.map(location =>
          [`${location.lon.toFixed(5)}:${location.lat.toFixed(5)}:${Math.round(location.heading / 10)}`, location])).values()];
        try {
          const detours = await fetchIndependent('DRIVE', unique);
          selected = detours.filter(route => !crossesExcludedRoads(route, unique) &&
            !matchRouteClosures(route, snapshot.events, now).length);
          if (selected.length) avoidance = 'detour';
        } catch { /* Keep the blocked routes visibly blocked, without pretending avoidance succeeded. */ }
      }
      if (selected.length) {
        driving = [...selected, ...driving.filter(route => route.mode !== 'drive')];
      } else {
        driving = driving.map(route => ({ ...route,
          closureIds: blocked.find(item => item.route === route)?.matches.map(match => match.event.id) || [],
        }));
      }
    }
    roadAwareness = { status: snapshot.status, retrievedAt: snapshot.retrievedAt,
      officialCoverage: snapshot.officialCoverage, avoidance,
      matchedClosureIds: [...new Set(blocked.flatMap(item => item.matches.map(match => match.event.id)))] };
  }
  if (forceIndependent) {
    driving = driving.map((route) => ({ ...route, provider: 'independent' }));
  }
  return {
    provider: forceIndependent ? 'independent' : 'osm-fallback',
    trafficAvailable: false,
    stopsApplied: stops.length,
    options: await applyTransitRoadRestrictions(driving, env),
    ...(roadAwareness ? { roadAwareness } : {}),
  };
}

/** Filter legal alternatives; if none exist, retain explicit blocks for the
 * client to refuse. A lane beside general traffic never blocks its road. */
export async function applyTransitRoadRestrictions(options: any[], env: any, at = new Date()) {
  const relevant = options.filter(route => route.mode === 'drive' && route.coordinates?.some(
    ([x, y]) => x >= 174.3 && x <= 175.6 && y >= -37.5 && y <= -36.3
  ));
  if (!relevant.length) return options;
  const snapshot = await readTransitSnapshot(env);
  const checked = options.map(route => {
    if (!relevant.includes(route)) return route;
    const blocks = transitRoadBlocks(route, snapshot, at);
    return blocks.length ? {
      ...route,
      restrictedRoadIds: blocks.map(m => m.lane.id),
      warnings: [...(route.warnings || []), ...blocks.map(m =>
        `Bus-only access: ${m.lane.roadName} · ${m.lane.operatingDays} ${m.lane.operatingHours}`
      )]
    } : route;
  });
  return checked.some(r => r.mode === 'drive' && !r.restrictedRoadIds?.length && !r.closureIds?.length)
    ? checked.filter(r => !r.restrictedRoadIds?.length) : checked;
}
