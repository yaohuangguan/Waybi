import type { LonLat, ProviderPayload, RouteRequestOptions, UsageRecorder } from './types.ts';
import { AMAP_ATTRIBUTION, AMAP_PROVIDER, amapConfigured, amapGet, amapNumber, amapText } from './amap_client.ts';
import type { AmapApi } from './amap_client.ts';
import { allInMainlandChina, gcjParameter, parseGcjPolyline, wgs84ToGcj02 } from './china_geo.ts';
import { distanceMeters } from './geo.ts';
import { crossesExcludedRoads } from './routing_closures.ts';
import type { ClosureLocation } from './routing_closures.ts';

/**
 * Amap (AutoNavi) driving, walking and cycling routes inside mainland China,
 * normalised to the exact route-option shape Waybi already produces from
 * Valhalla/OSRM: WGS-84 geometry, OSRM-style steps (the maneuver happens at
 * the step's start; `along` is its distance from the route start), alternatives,
 * waypoint `arrive` steps and live traffic intervals from Amap's `tmcs`.
 *
 * Amap's own steps are the other way round: each one says "drive along X for
 * N metres, then <action>". The action of step k-1 therefore becomes the
 * maneuver of normalised step k, located at the first point of Amap step k.
 *
 * Public transport is not offered here: Waybi's transit itineraries come from
 * a separate client-side provider, so transit in China keeps its current
 * "not available" state.
 */
export const AMAP_MAX_WAYPOINTS = 16;
const DRIVING_TIMEOUT_MS = 8000;
const ACTIVE_TIMEOUT_MS = 6000;
const TRAFFIC_TTL_MS = 5 * 60 * 1000;

const MODE_API: Record<string, AmapApi> = { DRIVE: 'driving', WALK: 'walking', BICYCLE: 'bicycling' };
const FALLBACK_SPEED: Record<string, number> = { DRIVE: 11, WALK: 1.3, BICYCLE: 4 };

export function amapSupportsMode(mode: string, stopCount: number): boolean {
  if (mode === 'DRIVE') return stopCount <= AMAP_MAX_WAYPOINTS;
  return (mode === 'WALK' || mode === 'BICYCLE') && stopCount === 0;
}

/** Every point (origin, stops, destination) must be in mainland China. A trip
 * that leaves it (to Hong Kong, Macau, or abroad) keeps the current engine. */
export function amapRoutingApplies(env: any, points: LonLat[]): boolean {
  return points.length >= 2 && amapConfigured(env) && allInMainlandChina(points);
}

export interface AmapManeuver { type: string; modifier: string }

const ACTION_MANEUVERS: Array<[RegExp, AmapManeuver]> = [
  [/调头|掉头/, { type: 'turn', modifier: 'uturn' }],
  [/离开环岛|驶出环岛/, { type: 'exit roundabout', modifier: 'straight' }],
  [/进入环岛|环岛/, { type: 'roundabout', modifier: 'straight' }],
  [/向左前方/, { type: 'turn', modifier: 'slight left' }],
  [/向右前方/, { type: 'turn', modifier: 'slight right' }],
  [/向左后方/, { type: 'turn', modifier: 'sharp left' }],
  [/向右后方/, { type: 'turn', modifier: 'sharp right' }],
  [/左转/, { type: 'turn', modifier: 'left' }],
  [/右转/, { type: 'turn', modifier: 'right' }],
  [/靠左/, { type: 'fork', modifier: 'slight left' }],
  [/靠右/, { type: 'fork', modifier: 'slight right' }],
  [/直行|减速行驶/, { type: 'continue', modifier: 'straight' }],
];

/**
 * Map Amap `navi.action` / `navi.assistant_action` (左转, 向左前方行驶, 靠左,
 * 左转调头, 进入环岛, 进入匝道, 离开主路, 到达途经地, 到达目的地, …) to the
 * OSRM vocabulary that RouteOption.fromJson and navigation_language.dart use.
 */
export function amapManeuver(action: unknown, assistant: unknown): AmapManeuver {
  const main = amapText(action);
  const extra = amapText(assistant);
  if (/到达(?:途经地|途径地|途经点)/.test(extra)) return { type: 'arrive', modifier: '' };
  if (/到达目的地/.test(main) || /到达目的地/.test(extra)) return { type: 'arrive', modifier: '' };
  const turn = ACTION_MANEUVERS.find(([pattern]) => pattern.test(main))?.[1];
  const side = /左/.test(main) || /左侧/.test(extra) ? 'left' : /右/.test(main) || /右侧/.test(extra) ? 'right' : '';
  const ramp = /匝道|进入高速/.test(extra);
  if (/离开主路|驶出|出口/.test(extra)) return { type: 'off ramp', modifier: `slight ${side || 'right'}` };
  if (ramp && (!turn || turn.type === 'continue' || turn.type === 'fork')) {
    return { type: 'on ramp', modifier: side ? `slight ${side}` : 'straight' };
  }
  if (/进入主路/.test(extra) && (!turn || turn.type === 'continue' || turn.type === 'fork')) {
    return { type: 'merge', modifier: side ? `slight ${side}` : 'straight' };
  }
  if (/进入辅路|岔道/.test(extra) && (!turn || turn.type === 'continue' || turn.type === 'fork')) {
    if (/中间/.test(extra)) return { type: 'fork', modifier: 'straight' };
    return { type: 'fork', modifier: `slight ${side || 'right'}` };
  }
  if (/环岛/.test(extra) && !turn) {
    return /离开/.test(extra) ? { type: 'exit roundabout', modifier: 'straight' } : { type: 'roundabout', modifier: 'straight' };
  }
  return turn ?? { type: 'continue', modifier: 'straight' };
}

const ORIENTATION_EN: Record<string, string> = {
  东: 'east', 南: 'south', 西: 'west', 北: 'north', 东北: 'northeast', 东南: 'southeast', 西北: 'northwest', 西南: 'southwest',
};

function roundaboutExit(instruction: string): number | null {
  const match = /第\s*(\d+)\s*个?出口/.exec(instruction);
  return match ? Number(match[1]) : null;
}

/** One instruction per normalised step, in the app's language. */
export function amapInstruction(maneuver: AmapManeuver, road: string, language: string, options: {
  depart?: boolean; orientation?: string; waypoint?: boolean; exit?: number | null;
} = {}): string {
  const zh = language === 'zh';
  if (options.depart) {
    const heading = amapText(options.orientation);
    if (zh) return `${heading ? `向${heading}` : ''}出发${road ? `，沿${road}行驶` : ''}`;
    const english = ORIENTATION_EN[heading];
    return `Head ${english || 'out'}${road ? ` on ${road}` : ''}`;
  }
  if (maneuver.type === 'arrive') {
    if (options.waypoint) return zh ? '到达途经点' : 'Arrive at your stop';
    return zh ? '到达目的地' : 'Arrive at destination';
  }
  const { type, modifier } = maneuver;
  const left = modifier.includes('left');
  let action: string;
  if (type === 'roundabout') {
    action = options.exit
      ? (zh ? `进入环岛，从第 ${options.exit} 个出口驶出` : `At the roundabout, take exit ${options.exit}`)
      : (zh ? '驶入环岛' : 'Enter the roundabout');
  } else if (type === 'exit roundabout') action = zh ? '驶出环岛' : 'Exit the roundabout';
  else if (modifier === 'uturn') action = zh ? '掉头' : 'Make a U-turn';
  else if (type === 'off ramp') action = zh ? `从${left ? '左侧' : '右侧'}出口驶出` : `Take the ${left ? 'left' : 'right'} exit`;
  else if (type === 'on ramp') action = zh ? '驶入匝道' : 'Take the ramp';
  else if (type === 'merge') action = zh ? '汇入主路' : 'Merge onto the main road';
  else if (type === 'fork') action = modifier === 'straight' ? (zh ? '走中间道路' : 'Keep straight')
    : zh ? (left ? '靠左行驶' : '靠右行驶') : (left ? 'Keep left' : 'Keep right');
  else if (modifier === 'slight left') action = zh ? '向左前方行驶' : 'Bear left';
  else if (modifier === 'slight right') action = zh ? '向右前方行驶' : 'Bear right';
  else if (modifier === 'sharp left') action = zh ? '向左后方急转' : 'Turn sharp left';
  else if (modifier === 'sharp right') action = zh ? '向右后方急转' : 'Turn sharp right';
  else if (modifier === 'left') action = zh ? '左转' : 'Turn left';
  else if (modifier === 'right') action = zh ? '右转' : 'Turn right';
  else action = zh ? '继续直行' : 'Continue straight';
  if (!road) return action;
  return zh ? `${action}，进入${road}` : `${action} onto ${road}`;
}

const TMC_SPEED: Record<string, 'normal' | 'slow' | 'trafficJam'> = {
  畅通: 'normal', 缓行: 'slow', 拥堵: 'trafficJam', 严重拥堵: 'trafficJam',
};

interface NormalisedStep {
  distance: number; duration: number; name: string; maneuver: string; modifier: string;
  location: LonLat; instruction: string; lanes: []; along: number;
}

function pathDuration(path: ProviderPayload, steps: ProviderPayload[], distance: number, mode: string): number {
  const direct = amapNumber(path?.cost?.duration) || amapNumber(path?.duration);
  if (direct > 0) return direct;
  const summed = steps.reduce((total, step) => total + amapNumber(step?.cost?.duration ?? step?.duration), 0);
  return summed > 0 ? summed : Math.round(distance / FALLBACK_SPEED[mode]);
}

function majorRoads(steps: ProviderPayload[]): string {
  const roads = new Map<string, number>();
  for (const step of steps) {
    const name = amapText(step?.road_name);
    if (name) roads.set(name, (roads.get(name) || 0) + amapNumber(step?.step_distance));
  }
  const major = new Set([...roads].sort((a, b) => b[1] - a[1]).slice(0, 2).map(([name]) => name));
  return [...roads.keys()].filter(name => major.has(name)).join(' · ').slice(0, 180);
}

/** Normalise one Amap path. Returns null when it lacks usable geometry. */
export function normalizeAmapPath(path: ProviderPayload, index: number, mode: string, language = 'en', now = new Date()) {
  const amapSteps: ProviderPayload[] = Array.isArray(path?.steps) ? path.steps : [];
  const coordinates: LonLat[] = [];
  const ranges: Array<[number, number]> = [];
  for (const step of amapSteps) {
    const line = parseGcjPolyline(step?.polyline);
    const before = coordinates.length;
    // Consecutive step polylines share their joining vertex.
    const shared = before > 0 && line.length > 0 && distanceMeters(coordinates[before - 1], line[0]) < 0.05;
    if (shared) line.shift();
    coordinates.push(...line);
    const end = Math.max(0, coordinates.length - 1);
    ranges.push([Math.min(shared ? before - 1 : before, end), end]);
  }
  if (coordinates.length < 2) return null;

  // Cumulative metres at every vertex, for along-route traffic intervals.
  const alongVertex = [0];
  for (let i = 1; i < coordinates.length; i++) alongVertex.push(alongVertex[i - 1] + distanceMeters(coordinates[i - 1], coordinates[i]));
  const geometricLength = alongVertex.at(-1);
  const distance = amapNumber(path?.distance) || Math.round(geometricLength);
  const durationSeconds = pathDuration(path, amapSteps, distance, mode);

  const steps: NormalisedStep[] = [];
  let along = 0;
  const push = (step: Omit<NormalisedStep, 'along' | 'lanes'>) => {
    steps.push({ ...step, lanes: [], along });
    along += step.distance;
  };
  amapSteps.forEach((step, k) => {
    const [start] = ranges[k];
    const location = coordinates[start];
    const road = amapText(step?.road_name);
    const metres = amapNumber(step?.step_distance);
    const seconds = amapNumber(step?.cost?.duration ?? step?.duration);
    if (k === 0) {
      push({ distance: metres, duration: seconds, name: road, maneuver: 'depart', modifier: '', location,
        instruction: amapInstruction({ type: 'depart', modifier: '' }, road, language, { depart: true, orientation: step?.orientation }) });
      return;
    }
    const previous = amapSteps[k - 1];
    const maneuver = amapManeuver(previous?.navi?.action ?? previous?.action, previous?.navi?.assistant_action ?? previous?.assistant_action);
    if (maneuver.type === 'arrive') {
      // A waypoint ends one leg and starts the next, exactly like OSRM legs.
      push({ distance: 0, duration: 0, name: '', maneuver: 'arrive', modifier: '', location,
        instruction: amapInstruction(maneuver, '', language, { waypoint: true }) });
      push({ distance: metres, duration: seconds, name: road, maneuver: 'depart', modifier: '', location,
        instruction: amapInstruction({ type: 'depart', modifier: '' }, road, language, { depart: true, orientation: step?.orientation }) });
      return;
    }
    push({ distance: metres, duration: seconds, name: road, maneuver: maneuver.type, modifier: maneuver.modifier, location,
      instruction: amapInstruction(maneuver, road, language, { exit: roundaboutExit(amapText(previous?.instruction)) }) });
  });
  push({ distance: 0, duration: 0, name: '', maneuver: 'arrive', modifier: '', location: coordinates.at(-1),
    instruction: amapInstruction({ type: 'arrive', modifier: '' }, '', language) });

  const trafficIntervals: Array<{ startPolylinePointIndex: number; endPolylinePointIndex: number; speed: string }> = [];
  const levels = { normal: 0, slow: 0, trafficJam: 0, heavyMeters: 0, moderateMeters: 0, coveredMeters: 0 };
  if (mode === 'DRIVE') {
    amapSteps.forEach((step, k) => {
      const tmcs: ProviderPayload[] = Array.isArray(step?.tmcs) ? step.tmcs : [];
      const [first, last] = ranges[k];
      let cursor = alongVertex[first];
      let startIndex = first;
      tmcs.forEach((tmc, t) => {
        const metres = amapNumber(tmc?.tmc_distance);
        const target = cursor + metres;
        let endIndex = startIndex;
        if (t === tmcs.length - 1) endIndex = last;
        else while (endIndex < last && Math.abs(alongVertex[endIndex + 1] - target) <= Math.abs(alongVertex[endIndex] - target)) endIndex++;
        const speed = TMC_SPEED[amapText(tmc?.tmc_status)];
        if (speed && endIndex > startIndex) {
          trafficIntervals.push({ startPolylinePointIndex: startIndex, endPolylinePointIndex: endIndex, speed });
          levels[speed] += 1;
          levels.coveredMeters += metres;
          if (speed === 'trafficJam') levels.heavyMeters += metres;
          if (speed === 'slow') levels.moderateMeters += metres;
        }
        cursor = target;
        startIndex = endIndex;
      });
    });
  }

  const zh = language === 'zh';
  const tolls = amapNumber(path?.cost?.tolls);
  const warnings = amapText(path?.restriction) === '1'
    ? [zh ? '路线经过无法避开的限行路段' : 'This route passes a traffic-restricted section that cannot be avoided.'] : [];
  const roads = majorRoads(amapSteps);
  const description = [roads || (index === 0 ? (zh ? '推荐路线' : 'Recommended route') : (zh ? `备选路线 ${index + 1}` : `Alternative ${index + 1}`)),
    tolls > 0 ? (zh ? `收费约 ¥${tolls}` : `Tolls about ¥${tolls}`) : ''].filter(Boolean).join(' · ');
  const covered = Math.round(levels.coveredMeters);
  return {
    id: `${mode.toLowerCase()}-${index}`,
    mode: mode.toLowerCase(),
    durationSeconds: Math.round(durationSeconds),
    // Amap's duration already reflects live traffic; it publishes no
    // free-flow time, so no delay is claimed.
    staticDurationSeconds: null,
    trafficDelaySeconds: null,
    distanceMeters: Math.round(distance),
    coordinates,
    encodedPolyline: null,
    routeToken: null,
    description,
    labels: [],
    warnings,
    traffic: { normal: levels.normal, slow: levels.slow, trafficJam: levels.trafficJam },
    trafficIntervals,
    steps,
    transit: [],
    provider: AMAP_PROVIDER,
    routingEngine: 'amap',
    attribution: AMAP_ATTRIBUTION,
    ...(tolls > 0 ? { tollsYuan: tolls } : {}),
    ...(mode === 'DRIVE' ? {
      conditions: {
        sources: covered > 0 ? ['AutoNavi'] : [],
        coverage: 'amap-tmcs',
        trafficStatus: covered > 0 ? 'live' : 'unavailable',
        trafficSourceUpdatedAt: now.toISOString(),
        expiresAt: new Date(now.getTime() + TRAFFIC_TTL_MS).toISOString(),
        coveredMeters: covered,
        heavyMeters: Math.round(levels.heavyMeters),
        moderateMeters: Math.round(levels.moderateMeters),
        // Amap's ETA already includes congestion; no extra ranking penalty.
        rankingPenalty: 0,
        penaltyBasis: 'provider-duration-includes-traffic',
        incidentIds: [], roadworkIds: [],
      },
    } : {}),
  };
}

/** Small GCJ-02 squares around directed closure points for `avoidpolygons`. */
export function amapAvoidPolygons(exclusions: ClosureLocation[] = []): string {
  return exclusions.slice(0, 32).map(({ lon, lat }) => {
    const dLat = 25 / 111_320;
    const dLon = 25 / (111_320 * Math.max(0.2, Math.cos(lat * Math.PI / 180)));
    return [[lon - dLon, lat - dLat], [lon + dLon, lat - dLat], [lon + dLon, lat + dLat], [lon - dLon, lat + dLat]]
      .map(([x, y]) => wgs84ToGcj02(x, y).map(value => value.toFixed(6)).join(',')).join(';');
  }).join('|');
}

interface AmapModeArgs {
  env: any; points: LonLat[]; mode: string; options: RouteRequestOptions; trackUsage?: UsageRecorder;
  fetcher?: typeof fetch; now?: Date;
}

/** Routes for one mode, or throws AmapUnavailableError / Error('no route'). */
export async function amapModeRoutes({ env, points, mode, options, trackUsage, fetcher, now = new Date() }: AmapModeArgs) {
  const api = MODE_API[mode];
  if (!api || !amapSupportsMode(mode, points.length - 2)) throw new Error(`Amap does not support ${mode} with these stops`);
  const alternatives = options.alternatives !== false;
  const params: Record<string, string | undefined> = {
    origin: gcjParameter(points[0]),
    destination: gcjParameter(points.at(-1)),
  };
  if (mode === 'DRIVE') {
    params.strategy = '32';
    params.show_fields = 'cost,navi,tmcs,polyline';
    if (points.length > 2) params.waypoints = points.slice(1, -1).map(gcjParameter).join(';');
    if (options.exclusions?.length) params.avoidpolygons = amapAvoidPolygons(options.exclusions);
  } else {
    params.show_fields = 'cost,navi,polyline';
    if (alternatives) params.alternative_route = '2';
  }
  const payload = await amapGet(env, api, params, {
    timeoutMs: mode === 'DRIVE' ? DRIVING_TIMEOUT_MS : ACTIVE_TIMEOUT_MS,
    clientKey: options.routingClientKey, trackUsage, fetcher,
  });
  const paths: ProviderPayload[] = Array.isArray(payload?.route?.paths) ? payload.route.paths : [];
  let routes = paths.slice(0, alternatives ? 3 : 1)
    .map((path, index) => normalizeAmapPath(path, index, mode, options.language, now))
    .filter(route => route && route.distanceMeters > 0);
  if (mode === 'DRIVE' && options.exclusions?.length) {
    routes = routes.filter(route => !crossesExcludedRoads(route, options.exclusions));
  }
  if (!routes.length) throw new Error('Amap returned no usable route');
  return routes;
}

/**
 * Route options for a trip entirely in mainland China. Modes Amap cannot
 * answer (transit, multi-stop walking or cycling) or that fail (no key,
 * budget, Amap error) are listed in `missing` for the existing engines.
 */
export async function amapRouteOptions(env: any, points: LonLat[], modes: string[], options: RouteRequestOptions,
  trackUsage?: UsageRecorder, fetcher?: typeof fetch) {
  const settled = await Promise.all(modes.map(async mode => {
    if (!amapSupportsMode(mode, points.length - 2)) return null;
    try { return await amapModeRoutes({ env, points, mode, options, trackUsage, fetcher }); }
    catch (error) {
      if (!(error as Error)?.name?.startsWith('Amap')) {
        console.warn(JSON.stringify({ level: 'warn', event: 'amap_route_unusable', mode }));
      }
      return null;
    }
  }));
  return {
    routes: settled.flatMap(result => result || []),
    missing: modes.filter((_, index) => !settled[index]),
  };
}

/** Legacy /api/route shape (first driving route only). */
export async function amapLegacyRoute(env: any, points: LonLat[], trackUsage?: UsageRecorder) {
  const [route] = await amapModeRoutes({ env, points, mode: 'DRIVE', options: { alternatives: false, language: 'zh' }, trackUsage });
  return {
    coordinates: route.coordinates,
    distance: route.distanceMeters,
    duration: route.durationSeconds,
    provider: AMAP_PROVIDER,
    attribution: AMAP_ATTRIBUTION,
    steps: route.steps.map(({ distance, duration, name, maneuver, modifier, instruction, location }) =>
      ({ distance, duration, name, maneuver, modifier, instruction, location })),
  };
}
