import { distanceMeters } from './geo.ts';
import { readTrafficFlowState } from './traffic_flow.ts';
import { matchRouteClosures } from './routing_closures.ts';
import type { LonLat, OfficialRoadEvent } from './types.ts';

interface FlowEdge { a: LonLat; b: LonLat; level: string; road: string; dx: number; dy: number }
const cell = (p: LonLat) => `${Math.floor(p[0] * 200)},${Math.floor(p[1] * 200)}`;
function roadKey(value: string) {
  const key = value.toLowerCase().replace(/auckland|northbound|southbound|eastbound|westbound/g, '').replace(/[^a-z0-9]/g, '');
  return ({ southernmotorway: 'sh1', northernmotorway: 'sh1', northwesternmotorway: 'sh16',
    southwesternmotorway: 'sh20', upperharbourmotorway: 'sh18', upperharbourhighway: 'sh18',
    georgeboltmemorialdrive: 'sh20a' })[key] || key.replace('statehighway', 'sh');
}

/** Only actual directed OSM-matched NZTA geometry is used, never endpoint
 * chords, nearby streets, the opposite carriageway or unknown/stale levels. */
function trafficIndex(state: any) {
  const cells = new Map<string, FlowEdge[]>();
  if (state?.syncStatus !== 'live') return cells;
  for (const segment of state.segments || []) {
    if (segment.geometryQuality !== 'road-matched' || !['free', 'moderate', 'heavy'].includes(segment.level)) continue;
    const points = segment.geometry?.coordinates || [];
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i];
      const dx = (b[0] - a[0]) * Math.cos(a[1] * Math.PI / 180), dy = b[1] - a[1];
      if (!Math.hypot(dx, dy)) continue;
      const edge = { a, b, level: segment.level, road: roadKey(segment.motorway || ''), dx, dy };
      const west = Math.floor((Math.min(a[0], b[0]) - .0004) * 200), east = Math.floor((Math.max(a[0], b[0]) + .0004) * 200);
      const south = Math.floor((Math.min(a[1], b[1]) - .0003) * 200), north = Math.floor((Math.max(a[1], b[1]) + .0003) * 200);
      if ((east - west + 1) * (north - south + 1) > 100) continue;
      for (let x = west; x <= east; x++) for (let y = south; y <= north; y++) {
        const key = `${x},${y}`, list = cells.get(key) || [];
        list.push(edge); cells.set(key, list);
      }
    }
  }
  return cells;
}

function trafficOverlap(route: any, index: Map<string, FlowEdge[]>) {
  const totals = { free: 0, moderate: 0, heavy: 0 };
  if (!index.size) return totals;
  const points: LonLat[] = route.coordinates || [];
  const steps = route.steps || [];
  let alongRoute = 0, stepIndex = 0, stepEnd = steps[0]?.distance || 0;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i], metres = distanceMeters(a, b);
    if (!metres) continue;
    const cos = Math.cos(a[1] * Math.PI / 180);
    const dx = (b[0] - a[0]) * cos, dy = b[1] - a[1], magnitude = Math.hypot(dx, dy);
    const samples = Math.min(200, Math.max(1, Math.ceil(metres / 80)));
    for (let n = 0; n < samples; n++) {
      const t = (n + .5) / samples, p: LonLat = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      while (stepIndex < steps.length - 1 && stepEnd < alongRoute + metres * t) {
        stepIndex++; stepEnd += steps[stepIndex].distance;
      }
      const road = roadKey(steps[stepIndex]?.name || '');
      let nearest = 25, level: string | null = null;
      for (const edge of index.get(cell(p)) || []) {
        if (road && edge.road && road !== edge.road) continue;
        // 45 degrees and 25 metres avoid borrowing a parallel/reverse road.
        if ((dx * edge.dx + dy * edge.dy) / (magnitude * Math.hypot(edge.dx, edge.dy)) < Math.SQRT1_2) continue;
        const ex = (edge.b[0] - edge.a[0]) * cos * 111320, ey = (edge.b[1] - edge.a[1]) * 111320;
        const px = (p[0] - edge.a[0]) * cos * 111320, py = (p[1] - edge.a[1]) * 111320;
        const along = Math.max(0, Math.min(1, (px * ex + py * ey) / (ex * ex + ey * ey)));
        const offset = Math.hypot(px - along * ex, py - along * ey);
        if (offset <= nearest) { nearest = offset; level = edge.level; }
      }
      // At most one level per route sample: overlapping feed records cannot
      // multiply congestion or coverage for the same road.
      if (level) totals[level] += metres / samples;
    }
    alongRoute += metres;
  }
  return totals;
}

export function assessRouteConditions(route: any, flow: any, events: OfficialRoadEvent[] = [],
  eventsAt: string | null = null, now = new Date(), index = trafficIndex(flow)) {
  const levels = trafficOverlap(route, index);
  const matches = matchRouteClosures(route, events.filter(e => e.type !== 'roadClosure')
    .map(event => ({ ...event, type: 'roadClosure' as const })), now);
  const originals = new Map(events.map(e => [e.id, e]));
  const incidentIds = matches.filter(m => originals.get(m.event.id)?.type !== 'roadworks').map(m => m.event.id);
  const roadworkIds = matches.filter(m => originals.get(m.event.id)?.type === 'roadworks').map(m => m.event.id);
  const sourceAt = Date.parse(flow?.sourceUpdatedAt || '');
  const trafficLive = flow?.syncStatus === 'live' && Number.isFinite(sourceAt) &&
    now.getTime() >= sourceAt && now.getTime() - sourceAt < 10 * 60000;
  const eventExpiry = Date.parse(eventsAt || '') + 15 * 60000;
  const eventFresh = Number.isFinite(eventExpiry) && eventExpiry > now.getTime();
  const covered = trafficLive ? levels.free + levels.moderate + levels.heavy : 0;
  // These are comparative ranking weights, NOT measured delay seconds. NZTA
  // publishes congestion levels here, not speed or per-road travel times.
  const trafficPenalty = trafficLive ? Math.round((levels.heavy * .12 + levels.moderate * .03)) : 0;
  const eventPenalty = eventFresh ? incidentIds.length * 120 + roadworkIds.length * 30 : 0;
  const expires = Math.min(now.getTime() + 5 * 60000,
    trafficLive ? sourceAt + 10 * 60000 : Infinity, eventFresh ? eventExpiry : Infinity);
  const sources = [...new Set([...(trafficLive ? ['NZTA'] : []),
    ...(eventFresh ? matches.map(m => originals.get(m.event.id)?.source.provider).filter(Boolean) : [])])];
  return { sources, coverage: 'published-nzta-sections',
    trafficStatus: trafficLive ? 'live' : flow ? 'stale' : 'unavailable',
    trafficSourceUpdatedAt: flow?.sourceUpdatedAt || null,
    expiresAt: new Date(expires).toISOString(),
    coveredMeters: Math.round(covered), heavyMeters: trafficLive ? Math.round(levels.heavy) : 0,
    moderateMeters: trafficLive ? Math.round(levels.moderate) : 0,
    rankingPenalty: Math.min(1800, trafficPenalty + eventPenalty),
    penaltyBasis: 'qualitative-ranking-only',
    incidentIds: eventFresh ? incidentIds : [], roadworkIds: eventFresh ? roadworkIds : [],
  };
}

export async function applyRouteConditions(routes: any[], env: any, events: OfficialRoadEvent[] = [],
  eventsAt: string | null = null, now = new Date()) {
  let flow = null;
  try { if (env.CAMERA_DATA) flow = await readTrafficFlowState(env, now); } catch { /* Shared feed unavailable. */ }
  const index = trafficIndex(flow);
  return routes.map(route => route.mode !== 'drive' ? route : { ...route,
    conditions: assessRouteConditions(route, flow, events, eventsAt, now, index) });
}
