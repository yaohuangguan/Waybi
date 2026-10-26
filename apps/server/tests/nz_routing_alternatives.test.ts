import test from 'node:test';
import assert from 'node:assert/strict';
import { distinctValhallaRoutes, fetchNzRouting } from '../src/nz_routing.ts';
import { routeOptions } from '../src/routes.ts';
import type { LonLat } from '../src/types.ts';

const points: LonLat[] = [[174.76, -36.85], [174.80, -37.0]];
const env = { WAYBI_NZ_ROUTING_URL: 'https://waybi-test.a.run.app', WAYBI_NZ_ROUTING_TOKEN: 'test' };
function route(index = 0) {
  return { distance: [29000, 20700, 20000][index], duration: [1692, 1716, 1758][index],
    geometry: { coordinates: [points[0], [174.70 + index * .02, -36.92], points[1]] },
    legs: [{ steps: [{ distance: 100, maneuver: { type: 'depart', location: points[0] },
      intersections: [{ lanes: [{ indications: ['left'], valid: true }] }] }] }] };
}
const payload = (index = 0) => Response.json({ code: 'Ok', routes: [route(index)] });

test('three time-aware cost mixes preserve heading, exclusions, lanes and a shared deadline', async () => {
  const bodies = [], signals = [];
  const exclusions = [{ lat: -36.90, lon: 174.74, heading: 90, heading_tolerance: 45, radius: 30, node_snap_tolerance: 0 }];
  const result = await fetchNzRouting(env, points, 'DRIVE', { alternatives: true, headingDegrees: -45, language: 'zh' }, exclusions,
    async (url, init) => {
      assert.equal(String(url), env.WAYBI_NZ_ROUTING_URL + '/route');
      assert.equal(init.headers['authorization'], 'Bearer test');
      bodies.push(JSON.parse(init.body as string)); signals.push(init.signal);
      return payload(bodies.length - 1);
    });
  assert.equal(result.routes.length, 3);
  assert.deepEqual(bodies.map(b => b.costing_options?.auto?.use_distance), [undefined, .25, .5]);
  for (const body of bodies) {
    assert.deepEqual(body.date_time, { type: 0 });
    assert.deepEqual(body.exclude_locations, exclusions);
    assert.equal(body.locations[0].heading, 315);
    assert.equal(body.locations.length, 2);
    assert.equal(body.language, 'zh-CN');
    assert.equal(body.alternates, 0);
    assert.equal(body.shape_format, 'polyline6');
    assert.equal(body.costing_options?.auto?.ignore_restrictions, undefined);
    assert.equal(body.costing_options?.auto?.shortest, undefined);
  }
  assert.ok(signals.every(s => s === signals[0]));
  assert.equal(result.routes[1].legs[0].steps[0].intersections[0].lanes.length, 1);
});

test('identical geometry never becomes three claimed alternatives', async () => {
  let calls = 0;
  const result = await fetchNzRouting(env, points, 'DRIVE', { alternatives: true }, [], async () => { calls++; return payload(); });
  assert.equal(calls, 3);
  assert.equal(result.routes.length, 1);
});

test('a failed optional route preserves the owned primary instead of causing provider fallback', async () => {
  let calls = 0;
  const result = await fetchNzRouting(env, points, 'DRIVE', { alternatives: true }, [], async () =>
    ++calls === 1 ? payload() : new Response('unavailable', { status: 503 }));
  assert.equal(calls, 2);
  assert.deepEqual(result.routes, [route()]);
});

test('every optional call reserves quota; exhaustion preserves the usable result', async () => {
  let reservations = 0, calls = 0;
  const db = { prepare() { return { bind() { return { async first() { return ++reservations <= 1 ? { calls: 1 } : null; } }; } }; } };
  const result = await fetchNzRouting({ ...env, WAYBI_NZ_ROUTING_DAILY_LIMIT: '1', USER_DB: db }, points,
    'DRIVE', { alternatives: true }, [], async () => { calls++; return payload(); });
  assert.equal(calls, 1);
  assert.equal(reservations, 2);
  assert.equal(result.routes.length, 1);
});

test('single routes, other modes, via points and local-road rescue do not spend optional requests', async () => {
  for (const [mode, requestPoints, options] of [
    ['DRIVE', points, { alternatives: false }], ['DRIVE', points, {}],
    ['WALK', points, { alternatives: true }], ['BICYCLE', points, { alternatives: true }],
    ['DRIVE', [points[0], [174.77, -36.95], points[1]], { alternatives: true }],
    ['DRIVE', points, { alternatives: true, detourLocalRoads: true }],
  ] as const) {
    let calls = 0;
    await fetchNzRouting(env, requestPoints as LonLat[], mode, options, [], async () => { calls++; return payload(); });
    assert.equal(calls, 1);
  }
});

test('alternate discovery retains public API closure and explicit road exclusion checks', async () => {
  const previous = globalThis.fetch;
  const bodies = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body as string); bodies.push(body);
    return payload(body.costing_options?.auto?.use_distance === .25 ? 1 : body.costing_options?.auto?.use_distance === .5 ? 2 : 0);
  };
  try {
    const exclusion = { lat: -36.92, lon: 174.70, heading: 200, heading_tolerance: 90, radius: 40, node_snap_tolerance: 0 };
    const result = await routeOptions(points[0], points[1], { ...env,
      CAMERA_DATA: { async get() { return { events: [], syncStatus: 'live', retrievedAt: new Date().toISOString() }; } },
    }, [], ['DRIVE'], () => {}, { forceIndependent: true, alternatives: true, exclusions: [exclusion] });
    assert.equal(bodies.length, 3);
    assert.ok(bodies.every(b => b.exclude_locations.length === 1));
    assert.ok(result.options.length > 0);
    assert.ok(result.options.every(r => r.provider === 'independent' && r.steps[0].lanes.length === 1));
    assert.ok(result.options.every(r => r.coordinates[1][0] !== 174.70));
  } finally { globalThis.fetch = previous; }
});

test('geometry deduplication retains genuinely different corridors and removes bad results', () => {
  const duplicate = { ...route(), geometry: { coordinates: route().geometry.coordinates.map(([x, y]) => [x + .000001, y]) } };
  assert.equal(distinctValhallaRoutes([route(), duplicate, route(1), route(2)]).length, 3);
  assert.equal(distinctValhallaRoutes([
    { ...route(), geometry: { coordinates: [] } }, { ...route(), duration: 0 },
    { ...route(), geometry: { coordinates: [points[0], null] } },
    { ...route(), geometry: { coordinates: [points[0], [NaN, -36.9]] } },
    { ...route(), distance: Infinity },
  ]).length, 0);
});
