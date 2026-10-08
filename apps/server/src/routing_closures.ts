import type { LonLat, OfficialRoadEvent } from './types.ts';
import { distanceMeters } from './geo.ts';

export interface ClosureRoute {
  coordinates: LonLat[];
  durationSeconds: number;
}
export interface ClosureLocation {
  lat: number;
  lon: number;
  heading: number;
  heading_tolerance: number;
  radius: number;
  node_snap_tolerance: number;
}
export interface RouteClosureMatch {
  event: OfficialRoadEvent;
  locations: ClosureLocation[];
}

function bearing(a: LonLat, b: LonLat): number {
  const r = Math.PI / 180, lat1 = a[1] * r, lat2 = b[1] * r;
  const d = (b[0] - a[0]) * r;
  return (Math.atan2(Math.sin(d) * Math.cos(lat2),
    Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(d)) / r + 360) % 360;
}
function angle(a: number, b: number): number {
  return Math.abs(((a - b + 540) % 360) - 180);
}

/** Project an official point onto a directed route segment. The exclusion uses
 * the segment bearing, not the named motorway direction of a curved ramp. */
export function matchRouteClosures(
  route: ClosureRoute, events: OfficialRoadEvent[], now = new Date(), maxOffset = 35,
): RouteClosureMatch[] {
  if (route.coordinates.length < 2 || !events.length) return [];
  const cumulative = [0];
  for (let i = 1; i < route.coordinates.length; i++) {
    cumulative.push(cumulative[i - 1] + distanceMeters(route.coordinates[i - 1], route.coordinates[i]));
  }
  const length = cumulative.at(-1)!;
  if (!length) return [];
  // Index segments once. An NZ-wide feed must not scan every route vertex for
  // every incident/geometry point on the Worker's request thread.
  const cells = new Map<string, number[]>(), longSegments: number[] = [];
  const cell = (value: number) => Math.floor(value * 100);
  for (let i = 1; i < route.coordinates.length; i++) {
    const a = route.coordinates[i - 1], b = route.coordinates[i];
    const west = cell(Math.min(a[0], b[0]) - .001), east = cell(Math.max(a[0], b[0]) + .001);
    const south = cell(Math.min(a[1], b[1]) - .0005), north = cell(Math.max(a[1], b[1]) + .0005);
    if ((east - west + 1) * (north - south + 1) > 256) { longSegments.push(i); continue; }
    for (let x = west; x <= east; x++) for (let y = south; y <= north; y++) {
      const key = `${x}:${y}`, bucket = cells.get(key) || [];
      bucket.push(i); cells.set(key, bucket);
    }
  }
  const matches: RouteClosureMatch[] = [];
  const seen = new Set<string>();
  for (const event of events) {
    if (event.type !== 'roadClosure' || event.observation !== 'official' ||
        event.confidence < .5 || seen.has(event.id)) continue;
    seen.add(event.id);
    // A ramp's motorway direction is not the local bearing of its curved
    // approach. Exclude the actual directed segment after spatial matching.
    const ramp = /\b(?:on[ -]?ramp|off[ -]?ramp)\b/i.test([
      event.roadName, event.metadata?.description, event.metadata?.comments,
    ].join(' '));
    const points = event.geometry.length ? event.geometry : [event.location];
    const locations: ClosureLocation[] = [];
    for (const point of points) {
      const p: LonLat = [point.longitude, point.latitude];
      if (!Number.isFinite(p[0]) || !Number.isFinite(p[1])) continue;
      let best: { offset: number; along: number; coordinate: LonLat; heading: number } | null = null;
      const xScale = 111320 * Math.cos(point.latitude * Math.PI / 180);
      const candidates = [...(cells.get(`${cell(p[0])}:${cell(p[1])}`) || []), ...longSegments];
      for (const i of candidates) {
        const a = route.coordinates[i - 1], b = route.coordinates[i];
        const ax = (a[0] - p[0]) * xScale, ay = (a[1] - p[1]) * 111320;
        const dx = (b[0] - a[0]) * xScale, dy = (b[1] - a[1]) * 111320;
        const square = dx * dx + dy * dy;
        if (!square) continue;
        const t = Math.max(0, Math.min(1, -(ax * dx + ay * dy) / square));
        const offset = Math.hypot(ax + t * dx, ay + t * dy);
        if (offset > maxOffset || (best && offset >= best.offset)) continue;
        const heading = bearing(a, b);
        if (!ramp && event.headingDegrees != null && angle(event.headingDegrees, heading) > 55) continue;
        best = { offset, heading, along: cumulative[i - 1] + t * (cumulative[i] - cumulative[i - 1]),
          coordinate: [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])] };
      }
      if (!best) continue;
      const arrival = now.getTime() + route.durationSeconds * best.along / length * 1000;
      const from = event.validFrom ? Date.parse(event.validFrom) : -Infinity;
      const until = event.validUntil ? Date.parse(event.validUntil) : Infinity;
      if ((event.validFrom && !Number.isFinite(from)) ||
          (event.validUntil && !Number.isFinite(until))) continue;
      // Keep a current closure even if it may expire before arrival. Never
      // retain an expired record; scheduled closures matter when we reach them.
      if (until <= now.getTime() ||
          from > now.getTime() && (from > arrival || until <= arrival)) continue;
      const previous = locations.at(-1);
      if (previous && distanceMeters([previous.lon, previous.lat], best.coordinate) < 20) continue;
      locations.push({ lon: best.coordinate[0], lat: best.coordinate[1], heading: best.heading,
        heading_tolerance: 35, radius: 20, node_snap_tolerance: 0 });
    }
    if (locations.length) matches.push({ event, locations });
  }
  return matches;
}

/** Verify against the originally excluded directed segments, so the opposite
 * carriageway is not mistaken for the blocked direction of a point-only event. */
export function crossesExcludedRoads(route: ClosureRoute, locations: ClosureLocation[]): boolean {
  return locations.some(location => matchRouteClosures(route, [{
    id: 'excluded', type: 'roadClosure', location: { latitude: location.lat, longitude: location.lon },
    geometry: [], headingDegrees: location.heading, roadName: null, confidence: 1,
    severity: 'critical', observation: 'official', validFrom: null, validUntil: null,
    source: { provider: '', country: '', region: null, sourceId: '', updatedAt: null }, metadata: {},
  }], new Date(), 20).length > 0);
}
