import test from 'node:test';
import assert from 'node:assert/strict';
import { matchRouteClosures, crossesExcludedRoads } from '../src/routing_closures.ts';
import { routeOptions } from '../src/routes.ts';
import { fetchNzRouting, nzRoutingEndpoint } from '../src/nz_routing.ts';
import type { LonLat, OfficialRoadEvent } from '../src/types.ts';

const now = new Date('2026-10-08T08:00:00Z');
const points: LonLat[] = [[174.76, -36.86], [174.76, -36.85]];
const route = { coordinates: points, durationSeconds: 1200 };
function closure(extra = {}): OfficialRoadEvent {
  return { id: 'ramp', type: 'roadClosure', location: { longitude: 174.76, latitude: -36.855 },
    geometry: [], headingDegrees: null, confidence: .95, observation: 'official', roadName: 'A curved ramp',
    severity: 'critical', validFrom: null, validUntil: null,
    source: { provider: 'NZTA', country: 'NZ', region: null, sourceId: 'ramp', updatedAt: null },
    metadata: {}, ...extra };
}
function payload(coordinates = points) {
  return { code: 'Ok', routes: [{ duration: 1200, distance: 1800,
    geometry: { coordinates }, legs: [{ steps: [{ maneuver: { type: 'on ramp', location: coordinates[0] },
      intersections: [{ lanes: [{ indications: ['left'], valid: true }] }] }] }] }] };
}

test('directed ramp exclusions preserve the opposite carriageway and distant roads', () => {
  const matches = matchRouteClosures(route, [closure()], now);
  assert.equal(matches.length, 1);
  assert.equal(matches[0].locations[0].heading, 0);
  assert.equal(matches[0].locations[0].node_snap_tolerance, 0);
  assert.equal(crossesExcludedRoads(route, matches[0].locations), true);
  assert.equal(crossesExcludedRoads({ ...route, coordinates: [...points].reverse() }, matches[0].locations), false);
  assert.equal(matchRouteClosures(route, [closure({ headingDegrees: 180 })], now).length, 0);
  assert.equal(matchRouteClosures(route, [closure({ location: { longitude: 174.77, latitude: -36.855 } })], now).length, 0);
});

test('scheduled closures are checked at arrival; expired, malformed and inferred incidents do not block', () => {
  assert.equal(matchRouteClosures(route, [closure({ validFrom: new Date(now.getTime() + 300000).toISOString() })], now).length, 1);
  for (const extra of [
    { validFrom: new Date(now.getTime() + 3600000).toISOString() },
    { validFrom: new Date(now.getTime() + 60000).toISOString(), validUntil: new Date(now.getTime() + 120000).toISOString() },
    { validUntil: now.toISOString() }, { validFrom: 'bad-date' },
    { observation: 'inferred' }, { confidence: .2 }, { type: 'roadworks' },
  ]) assert.equal(matchRouteClosures(route, [closure(extra)], now).length, 0);
});

test('a curved ramp uses its own directed segment rather than the joined motorway direction', () => {
  const matches = matchRouteClosures(route, [closure({
    headingDegrees: 180, roadName: 'SH1 Southbound on-ramp',
  })], now);
  assert.equal(matches.length, 1);
  assert.equal(matches[0].locations[0].heading, 0);
});

test('owned routing requires all requested points in NZ and retains directions, languages and stops', async () => {
  const env = { WAYBI_NZ_ROUTING_URL: 'https://nz-route.example/base', WAYBI_NZ_ROUTING_TOKEN: 'test' };
  assert.equal(nzRoutingEndpoint(env, [[139.7, 35.6], points[1]]), null);
  assert.throws(() => nzRoutingEndpoint({ WAYBI_NZ_ROUTING_URL: 'http://public.example' }, points), /HTTPS/);
  let body;
  await fetchNzRouting(env, [points[0], [174.761, -36.855], points[1]], 'DRIVE',
    { language: 'zh', headingDegrees: -45 }, [], async (url, init) => {
      assert.equal(String(url), 'https://nz-route.example/base/route');
      assert.equal(init.headers['authorization'], 'Bearer test');
      body = JSON.parse(init.body as string);
      return Response.json(payload());
    });
  assert.equal(body.locations.length, 3);
  assert.equal(body.locations[0].heading, 315);
  assert.equal(body.language, 'zh-CN');
  assert.equal(body.alternates, 0);
  assert.equal(body.shape_format, 'geojson');
});

test('all blocked alternatives request exclusions; a verified detour retains lanes and independent provider', async () => {
  const previous = globalThis.fetch;
  const calls = [];
  const detour: LonLat[] = [points[0], [174.763, -36.856], [174.763, -36.852], points[1]];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body as string); calls.push(body);
    return Response.json(payload(body.exclude_locations ? detour : points));
  };
  try {
    const time = new Date();
    const plan = await routeOptions(points[0], points[1], {
      WAYBI_NZ_ROUTING_URL: 'https://nz-route.example',
      CAMERA_DATA: { async get() { return { events: [closure()], syncStatus: 'live', retrievedAt: time.toISOString() }; } },
    }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(calls.length, 2);
    assert.equal(calls[1].exclude_locations[0].heading, 0);
    assert.equal(plan.roadAwareness.avoidance, 'detour');
    assert.equal(plan.options[0].provider, 'independent');
    assert.equal(plan.options[0].steps[0].lanes.length, 1);
    assert.deepEqual(plan.options[0].coordinates, detour);
  } finally { globalThis.fetch = previous; }
});

test('an engine that ignores exclusions cannot turn a blocked route into a valid detour', async () => {
  const previous = globalThis.fetch;
  // The shared snapshot exists before the request. Generating its timestamp
  // inside get() can put it after routing's captured clock on slower runners.
  const retrievedAt = new Date(Date.now() - 1000).toISOString();
  globalThis.fetch = async () => Response.json(payload());
  try {
    const plan = await routeOptions(points[0], points[1], {
      WAYBI_NZ_ROUTING_URL: 'https://nz-route.example',
      CAMERA_DATA: { async get() { return { events: [closure()], syncStatus: 'live', retrievedAt }; } },
    }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(plan.roadAwareness.avoidance, 'blocked');
    assert.deepEqual(plan.options[0].closureIds, ['ramp']);
  } finally { globalThis.fetch = previous; }
});

test('overseas routes retain fallback and an expired shared snapshot cannot block them', async () => {
  const previous = globalThis.fetch;
  const coordinates: LonLat[] = [[151.2, -33.86], [151.2, -33.85]];
  globalThis.fetch = async url => {
    assert.equal(new URL(String(url)).hostname, 'routing.openstreetmap.de');
    return Response.json(payload(coordinates));
  };
  try {
    const plan = await routeOptions(coordinates[0], coordinates[1], {
      WAYBI_NZ_ROUTING_URL: 'https://nz-route.example',
      CAMERA_DATA: { async get() { return { events: [closure()], syncStatus: 'live',
        retrievedAt: new Date(Date.now() - 3600000).toISOString() }; } },
    }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(plan.options[0].provider, 'independent');
    assert.equal(plan.roadAwareness.status, 'unavailable');
    assert.deepEqual(plan.roadAwareness.matchedClosureIds, []);
  } finally { globalThis.fetch = previous; }
});
