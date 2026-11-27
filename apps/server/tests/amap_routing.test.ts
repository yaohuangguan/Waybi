import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import worker from '../src/worker.ts';
import { routeOptions } from '../src/routes.ts';
import { amapInstruction, amapManeuver, amapRoutingApplies, amapSupportsMode, normalizeAmapPath } from '../src/amap_routing.ts';
import { resetAmapBackoff } from '../src/amap_client.ts';
import { gcjParameter } from '../src/china_geo.ts';
import { distanceMeters } from '../src/geo.ts';
import { migratedD1 } from './d1_fixture.ts';

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/amap/${name}.json`, import.meta.url), 'utf8'));
const KEY = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const ORIGIN: [number, number] = [114.5, 38.03];
const STOP: [number, number] = [114.517, 38.05];
const DESTINATION: [number, number] = [114.56, 38.07];

const OSRM_OK = {
  code: 'Ok',
  routes: [{ duration: 600, distance: 9000, geometry: { coordinates: [[114.5, 38.03], [114.56, 38.07]] },
    legs: [{ steps: [{ distance: 9000, duration: 600, name: 'osm road', maneuver: { type: 'depart', location: [114.5, 38.03] } }] }] }],
};

async function withRoutes<T>(handlers: Record<string, (url: URL) => unknown>, work: (calls: URL[]) => Promise<T>) {
  const previous = globalThis.fetch;
  const calls: URL[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = new URL(String(input));
    calls.push(url);
    const handler = handlers[url.hostname === 'restapi.amap.com' ? url.pathname : url.hostname];
    if (!handler) throw new Error(`unexpected ${url.hostname}${url.pathname}`);
    return Response.json(handler(url));
  }) as typeof fetch;
  resetAmapBackoff();
  const warn = console.warn;
  console.warn = () => {};
  try { return await work(calls); } finally { globalThis.fetch = previous; console.warn = warn; }
}

const near = (a: number[], b: number[]) => distanceMeters(a as [number, number], b as [number, number]) < 1;

test('Amap driving with a waypoint maps to the normalised route the app consumes', async () => {
  await withRoutes({ '/v5/direction/driving': () => fixture('driving_waypoint') }, async (calls) => {
    const plan = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [STOP], ['DRIVE'], () => {},
      { forceIndependent: true, language: 'zh', alternatives: true });
    const request = calls[0];
    assert.equal(request.searchParams.get('origin'), gcjParameter(ORIGIN));
    assert.equal(request.searchParams.get('destination'), gcjParameter(DESTINATION));
    assert.equal(request.searchParams.get('waypoints'), gcjParameter(STOP));
    assert.equal(request.searchParams.get('show_fields'), 'cost,navi,tmcs,polyline');
    assert.equal(request.searchParams.get('strategy'), '32');
    assert.equal(calls.length, 1);

    assert.equal(plan.provider, 'independent');
    assert.equal(plan.trafficAvailable, true);
    assert.equal(plan.attribution, '高德地图 / AutoNavi');
    const [route] = plan.options;
    assert.equal(route.provider, 'independent', 'the app navigation engine requires an independent route');
    assert.equal(route.routingEngine, 'amap');
    assert.equal(route.mode, 'drive');
    assert.equal(route.distanceMeters, 8666);
    assert.equal(route.durationSeconds, 1260);
    assert.equal(route.coordinates.length, 8, 'shared step vertices are not repeated');
    assert.ok(near(route.coordinates[0], ORIGIN) && near(route.coordinates.at(-1), DESTINATION), 'GCJ-02 → WGS-84');

    assert.deepEqual(route.steps.map(step => [step.maneuver, step.modifier, step.name]), [
      ['depart', '', '中山东路'],
      ['turn', 'left', '建设北大街'],
      ['arrive', '', ''],
      ['depart', '', '北二环东路'],
      ['turn', 'slight right', '胜利北大街'],
      ['arrive', '', ''],
    ]);
    assert.deepEqual(route.steps.map(step => step.along), [0, 1489, 3713, 3713, 6166, 8666]);
    assert.deepEqual(route.steps.map(step => step.distance), [1489, 2224, 0, 2453, 2500, 0]);
    assert.ok(near(route.steps[1].location, [114.517, 38.03]), 'the left turn is where 中山东路 ends');
    assert.ok(near(route.steps[2].location, STOP));
    assert.equal(route.steps[1].instruction, '左转，进入建设北大街');
    assert.equal(route.steps[2].instruction, '到达途经点');
    assert.equal(route.steps[4].instruction, '向右前方行驶，进入胜利北大街');
    assert.equal(route.steps[0].instruction, '向东出发，沿中山东路行驶');

    assert.deepEqual(route.trafficIntervals, [
      { startPolylinePointIndex: 0, endPolylinePointIndex: 1, speed: 'normal' },
      { startPolylinePointIndex: 1, endPolylinePointIndex: 2, speed: 'slow' },
      { startPolylinePointIndex: 2, endPolylinePointIndex: 3, speed: 'trafficJam' },
      { startPolylinePointIndex: 3, endPolylinePointIndex: 4, speed: 'trafficJam' },
      { startPolylinePointIndex: 4, endPolylinePointIndex: 5, speed: 'normal' },
      { startPolylinePointIndex: 6, endPolylinePointIndex: 7, speed: 'normal' },
    ]);
    assert.deepEqual(route.traffic, { normal: 3, slow: 1, trafficJam: 2 });
    assert.equal(route.conditions.trafficStatus, 'live');
    assert.equal(route.conditions.coveredMeters, 7352, '未知 sections are not claimed as covered');
    assert.equal(route.conditions.heavyMeters, 2224);
    assert.equal(route.conditions.moderateMeters, 613);
    assert.ok(Date.parse(route.conditions.expiresAt) > Date.now());
    assert.deepEqual(route.warnings, []);
  });
});

test('Amap alternatives, restrictions, tolls and roundabouts', async () => {
  await withRoutes({ '/v5/direction/driving': () => fixture('driving_alternatives') }, async () => {
    const plan = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [], ['DRIVE'], () => {},
      { forceIndependent: true, language: 'en' });
    assert.equal(plan.options.length, 2);
    const [best, alternative] = plan.options;
    assert.equal(best.id, 'drive-0');
    assert.equal(best.description, '北二环东路 · 胜利北大街', 'the two longest roads, in route order');
    assert.equal(best.steps[1].instruction, 'Turn left onto 建设北大街');
    assert.equal(best.steps[2].instruction, 'Turn right onto 北二环东路');
    assert.equal(best.steps.filter(step => step.maneuver === 'arrive').length, 1);
    assert.equal(alternative.id, 'drive-1');
    assert.match(alternative.description, /Tolls about ¥5$/);
    assert.equal(alternative.tollsYuan, 5);
    assert.deepEqual(alternative.warnings, ['This route passes a traffic-restricted section that cannot be avoided.']);
    assert.equal(alternative.steps[1].maneuver, 'roundabout');
    assert.equal(alternative.steps[1].instruction, 'At the roundabout, take exit 2 onto 北三环东路');
    assert.equal(alternative.conditions.moderateMeters, 5260);

    const single = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [], ['DRIVE'], () => {},
      { forceIndependent: true, alternatives: false });
    assert.equal(single.options.length, 1);
  });
});

test('Amap walking routes keep the walk mode and carry no traffic claims', async () => {
  await withRoutes({ '/v5/direction/walking': () => fixture('walking') }, async (calls) => {
    const plan = await routeOptions(ORIGIN, [114.517, 38.03], { AMAP_WEB_KEY: KEY }, [], ['WALK'], () => {},
      { forceIndependent: true, language: 'zh' });
    assert.equal(calls[0].searchParams.get('show_fields'), 'cost,navi,polyline');
    const [route] = plan.options;
    assert.equal(route.mode, 'walk');
    assert.equal(route.durationSeconds, 1190);
    assert.equal('conditions' in route, false);
    assert.deepEqual(route.trafficIntervals, []);
    assert.deepEqual(route.steps.map(step => step.maneuver), ['depart', 'turn', 'arrive']);
    assert.equal(route.steps[1].instruction, '左转');
  });
});

test('cycling uses Amap bicycling; multi-stop cycling keeps the existing engine', async () => {
  await withRoutes({
    '/v5/direction/bicycling': () => fixture('walking'),
    'routing.openstreetmap.de': () => OSRM_OK,
  }, async (calls) => {
    const plan = await routeOptions(ORIGIN, [114.517, 38.03], { AMAP_WEB_KEY: KEY }, [], ['BICYCLE'], () => {},
      { forceIndependent: true });
    assert.equal(plan.options[0].mode, 'bicycle');
    assert.equal(plan.options[0].routingEngine, 'amap');
    assert.equal(calls[0].pathname, '/v5/direction/bicycling');
    calls.length = 0;
    const multiStop = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [STOP], ['BICYCLE'], () => {},
      { forceIndependent: true });
    assert.equal(multiStop.options[0].routingEngine, 'osrm');
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false);
  });
});

test('Hong Kong, Macau, Kinmen and Taiwan trips keep the existing engine', async () => {
  const trips: Array<[[number, number], [number, number]]> = [
    [[114.0579, 22.5431], [114.1589, 22.284]], // Shenzhen → Hong Kong
    [[113.5767, 22.2707], [113.5439, 22.1987]], // Zhuhai → Macau
    [[118.0894, 24.4798], [118.3171, 24.4321]], // Xiamen → Kinmen
    [[121.56, 25.03], [120.3, 22.62]], // Taipei → Kaohsiung
  ];
  await withRoutes({ 'routing.openstreetmap.de': () => OSRM_OK }, async (calls) => {
    for (const [from, to] of trips) {
      assert.equal(amapRoutingApplies({ AMAP_WEB_KEY: KEY }, [from, to]), false);
      const plan = await routeOptions(from, to, { AMAP_WEB_KEY: KEY }, [], ['DRIVE'], () => {}, { forceIndependent: true });
      assert.equal(plan.options[0].routingEngine, 'osrm');
    }
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false);
  });
});

test('Amap route errors, missing key and exhausted budget fall back to the existing engine', async () => {
  const { db } = migratedD1();
  await withRoutes({
    '/v5/direction/driving': () => ({ status: '0', info: 'ROUTE_FAIL', infocode: '20802' }),
    'routing.openstreetmap.de': () => OSRM_OK,
  }, async (calls) => {
    const failed = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(failed.options[0].routingEngine, 'osrm');
    assert.ok(calls.some(url => url.pathname === '/v5/direction/driving'));

    calls.length = 0;
    const keyless = await routeOptions(ORIGIN, DESTINATION, {}, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(keyless.options[0].routingEngine, 'osrm');
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false);

    calls.length = 0;
    const exhausted = await routeOptions(ORIGIN, DESTINATION,
      { AMAP_WEB_KEY: KEY, USER_DB: db, WAYBI_AMAP_DAILY_BUDGET: '{"driving":0}' }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(exhausted.options[0].routingEngine, 'osrm');
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false, 'no Amap call past the budget');
  });
});

test('more than 16 stops exceed Amap waypoints and use the existing engine', async () => {
  assert.equal(amapSupportsMode('DRIVE', 16), true);
  assert.equal(amapSupportsMode('DRIVE', 17), false);
  assert.equal(amapSupportsMode('WALK', 1), false);
  assert.equal(amapSupportsMode('TRANSIT', 0), false);
  const stops = Array.from({ length: 17 }, (_, i) => [114.5 + i * 0.002, 38.04] as [number, number]);
  await withRoutes({ 'routing.openstreetmap.de': () => OSRM_OK }, async (calls) => {
    const plan = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, stops, ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(plan.options[0].routingEngine, 'osrm');
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false);
  });
});

test('road exclusions become Amap avoid polygons', async () => {
  await withRoutes({ '/v5/direction/driving': () => fixture('driving_alternatives') }, async (calls) => {
    const exclusions = [{ lon: 114.9, lat: 38.5, heading: 90, heading_tolerance: 45, radius: 10, node_snap_tolerance: 5 }];
    await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [], ['DRIVE'], () => {}, { forceIndependent: true, exclusions });
    const polygons = calls[0].searchParams.get('avoidpolygons');
    assert.equal(polygons.split('|').length, 1);
    assert.equal(polygons.split(';').length, 4);
  });
});

test('the default (non-Waybi) route request in China tags options as Amap', async () => {
  await withRoutes({
    '/v5/direction/driving': () => fixture('driving_alternatives'),
    '/v5/direction/walking': () => fixture('walking'),
    '/v5/direction/bicycling': () => fixture('walking'),
  }, async (calls) => {
    const plan = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY, GOOGLE_ROUTES_API_KEY: 'unused' }, [], null, () => {}, {});
    assert.equal(plan.provider, 'amap');
    assert.deepEqual([...new Set(plan.options.map(option => option.mode))], ['drive', 'walk', 'bicycle']);
    assert.ok(plan.options.every(option => option.provider === 'amap'));
    assert.equal(calls.some(url => url.hostname === 'routes.googleapis.com'), false);
  });
});

test('Amap navi actions map onto the app maneuver vocabulary', () => {
  const cases: Array<[unknown, unknown, string, string]> = [
    ['左转', '', 'turn', 'left'],
    ['右转', [], 'turn', 'right'],
    ['向左前方行驶', '', 'turn', 'slight left'],
    ['向右前方行驶', '', 'turn', 'slight right'],
    ['向左后方行驶', '', 'turn', 'sharp left'],
    ['向右后方行驶', '', 'turn', 'sharp right'],
    ['左转调头', '', 'turn', 'uturn'],
    ['掉头', '', 'turn', 'uturn'],
    ['靠左', '', 'fork', 'slight left'],
    ['靠右', '', 'fork', 'slight right'],
    ['直行', '', 'continue', 'straight'],
    ['减速行驶', '', 'continue', 'straight'],
    ['进入环岛', '', 'roundabout', 'straight'],
    ['离开环岛', '', 'exit roundabout', 'straight'],
    [[], '进入环岛', 'roundabout', 'straight'],
    ['靠右', '进入匝道', 'on ramp', 'slight right'],
    ['', '进入高速', 'on ramp', 'straight'],
    ['靠左', '离开主路', 'off ramp', 'slight left'],
    ['', '离开主路', 'off ramp', 'slight right'],
    ['靠右', '进入主路', 'merge', 'slight right'],
    ['靠右', '进入辅路', 'fork', 'slight right'],
    ['', '进入左侧岔道', 'fork', 'slight left'],
    ['', '进入中间岔道', 'fork', 'straight'],
    ['', '到达途经地', 'arrive', ''],
    ['', '到达目的地', 'arrive', ''],
    ['', '沿途经过收费站', 'continue', 'straight'],
    [[], [], 'continue', 'straight'],
    ['右转', '进入隧道', 'turn', 'right'],
  ];
  for (const [action, assistant, type, modifier] of cases) {
    assert.deepEqual(amapManeuver(action, assistant), { type, modifier }, `${action}/${assistant}`);
  }
  assert.equal(amapInstruction({ type: 'turn', modifier: 'uturn' }, '', 'zh'), '掉头');
  assert.equal(amapInstruction({ type: 'turn', modifier: 'uturn' }, '', 'en'), 'Make a U-turn');
  assert.equal(amapInstruction({ type: 'off ramp', modifier: 'slight left' }, '京港澳高速', 'zh'), '从左侧出口驶出，进入京港澳高速');
  assert.equal(amapInstruction({ type: 'fork', modifier: 'slight right' }, '', 'en'), 'Keep right');
  assert.equal(amapInstruction({ type: 'arrive', modifier: '' }, '', 'en', { waypoint: true }), 'Arrive at your stop');
  assert.equal(amapInstruction({ type: 'depart', modifier: '' }, '', 'en', { depart: true, orientation: '西北' }), 'Head northwest');
});

test('a path without geometry is unusable', () => {
  assert.equal(normalizeAmapPath({ distance: '100', steps: [{ polyline: [] }] }, 0, 'DRIVE'), null);
  const estimated = normalizeAmapPath({ distance: '1300', steps: [{ step_distance: '1300', polyline: '114.506,38.03;114.52,38.03' }] }, 0, 'WALK');
  assert.equal(estimated.durationSeconds, 1000, 'missing durations are estimated, never zero');
});

test('worker /api/route-options and the legacy /api/route use Amap in mainland China', async () => {
  await withRoutes({ '/v5/direction/driving': () => fixture('driving_alternatives') }, async (calls) => {
    const usage: string[] = [];
    const ctx = { waitUntil(promise: Promise<unknown>) { usage.push('recorded'); return promise; } };
    const options = await worker.fetch(new Request(
      `https://waybi.test/api/route-options?from=${ORIGIN}&to=${DESTINATION}&mode=drive&provider=independent&lang=zh&alternatives=true`),
      { AMAP_WEB_KEY: KEY }, ctx);
    assert.equal(options.status, 200);
    const plan = await options.json();
    assert.equal(plan.options[0].routingEngine, 'amap');
    assert.equal(plan.options[0].provider, 'independent');
    assert.ok(usage.length > 0, 'Amap usage is recorded for Cost Guard');

    const legacy = await worker.fetch(new Request(`https://waybi.test/api/route?from=${ORIGIN}&to=${DESTINATION}`),
      { AMAP_WEB_KEY: KEY }, ctx);
    assert.equal(legacy.status, 200);
    const route = await legacy.json();
    assert.equal(route.provider, 'amap');
    assert.equal(route.distance, 8666);
    assert.equal(route.steps[1].maneuver, 'turn');
    assert.equal(calls.filter(url => url.hostname === 'restapi.amap.com').length, 2);
    assert.ok(calls.every(url => url.hostname !== 'routing.openstreetmap.de'));
  });
});

test('the app contract fixture is exactly what the Worker produces today', async () => {
  const mobile = JSON.parse(readFileSync(new URL('../../mobile/test/support/amap_route_options.json', import.meta.url), 'utf8'));
  await withRoutes({ '/v5/direction/driving': () => fixture('driving_waypoint') }, async () => {
    const plan = await routeOptions(ORIGIN, DESTINATION, { AMAP_WEB_KEY: KEY }, [STOP], ['DRIVE'], () => {},
      { forceIndependent: true, language: 'zh' });
    for (const option of plan.options) {
      option.conditions.expiresAt = mobile.options[0].conditions.expiresAt;
      option.conditions.trafficSourceUpdatedAt = mobile.options[0].conditions.trafficSourceUpdatedAt;
    }
    assert.deepEqual(JSON.parse(JSON.stringify(plan)), mobile,
      'regenerate apps/mobile/test/support/amap_route_options.json when the normalised shape changes');
  });
});
