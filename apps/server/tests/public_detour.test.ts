import test from 'node:test';
import assert from 'node:assert/strict';
import { routeOptions } from '../src/routes.ts';
import { fetchPublicDetour } from '../src/public_detour.ts';
import { matchRouteClosures, parseRouteExclusions } from '../src/routing_closures.ts';
import type { LonLat, OfficialRoadEvent } from '../src/types.ts';

function payload(points: LonLat[]) { return { code: 'Ok', routes: [{ distance: 2000, duration: 200,
  geometry: { coordinates: points }, legs: [{ steps: [] }] }] }; }
for (const [label, x, y] of [['NZ', 174.76, -36.85], ['AU', 151.18, -33.94]] as const) {
  test(`${label} closed route detours with free routing even without an owned engine`, async () => {
    const previous = globalThis.fetch;
    const points: LonLat[] = [[x, y], [x, y + .02]];
    const clear: LonLat[] = [points[0], [x + .01, y + .01], points[1]];
    const event: OfficialRoadEvent = { id: label, type: 'roadClosure', location: { longitude: x, latitude: y + .01 },
      geometry: [], headingDegrees: 0, roadName: 'Closed road', confidence: 1, severity: 'critical', observation: 'official',
      validFrom: null, validUntil: null, metadata: {}, source: { provider: label, country: label, region: null, sourceId: label, updatedAt: null } };
    const calls: string[] = [];
    globalThis.fetch = async (url, init) => {
      const host = new URL(String(url)).host; calls.push(host);
      if (host === 'routing.openstreetmap.de') return Response.json(payload(points));
      assert.equal(host, 'valhalla1.openstreetmap.de');
      assert.equal(init.headers['authorization'], undefined);
      const body = JSON.parse(init.body as string);
      assert.equal(body.exclude_locations.length, 1);
      assert.equal(body.exclude_locations[0].node_snap_tolerance, 0);
      assert.deepEqual(body.locations.map(p => [p.lon, p.lat]), points);
      return Response.json({ code: 'Ok', routes: [...payload(points).routes, ...payload(clear).routes] });
    };
    try {
      const plan = await routeOptions(points[0], points[1], {
        CAMERA_DATA: { async get() { return { events: [event], syncStatus: 'live', retrievedAt: new Date(Date.now() - 1000).toISOString() }; } },
      }, [], ['DRIVE'], () => {}, { forceIndependent: true });
      assert.deepEqual(calls, ['routing.openstreetmap.de', 'valhalla1.openstreetmap.de']);
      assert.equal(plan.roadAwareness.avoidance, 'detour');
      assert.equal(plan.options.length, 1);
      assert.deepEqual(plan.options[0].coordinates, clear);
    } finally { globalThis.fetch = previous; }
  });
}
test('requested exclusions are validated, normalized and bounded', () => {
  assert.deepEqual(parseRouteExclusions(null), []);
  assert.equal(parseRouteExclusions('174.76,-36.85,-45')[0].heading, 315);
  for (const input of ['a,1,2', '181,1,2', '1,91,2', '1,,2', '1,2', Array(33).fill('1,2,3').join(';')]) {
    assert.equal(parseRouteExclusions(input), null);
  }
});
test('an engine ignoring a client exclusion cannot yield a usable route', async () => {
  const previous = globalThis.fetch;
  const points: LonLat[] = [[150, -34], [150, -33.98]];
  globalThis.fetch = async () => Response.json(payload(points));
  try {
    await assert.rejects(routeOptions(points[0], points[1], {}, [], ['DRIVE'], () => {}, {
      forceIndependent: true, exclusions: parseRouteExclusions('150,-33.99,0'),
    }), /No routes/);
  } finally { globalThis.fetch = previous; }
});
test('public detour requests coalesce and cache without paid credentials', async () => {
  let calls = 0;
  const points: LonLat[] = [[152, -33], [152, -32.98]];
  const fetcher: typeof fetch = async () => { calls++; return Response.json(payload(points)); };
  const exclusions = parseRouteExclusions('152,-32.99,0');
  await Promise.all([fetchPublicDetour(points, {}, exclusions, fetcher), fetchPublicDetour(points, {}, exclusions, fetcher)]);
  await fetchPublicDetour(points, {}, exclusions, fetcher);
  assert.equal(calls, 1);
});
test('a ramp beside an explicit through-motorway step does not close the motorway', () => {
  const event: any = { id: 'ramp', type: 'roadClosure', location: { longitude: 174.76, latitude: -36.84 },
    geometry: [], headingDegrees: 0, roadName: 'SH20 Queenstown Rd On-ramp Southbound', confidence: 1,
    observation: 'official', validFrom: null, validUntil: null, metadata: {} };
  const route = { coordinates: [[174.76, -36.85], [174.76, -36.83]] as LonLat[], durationSeconds: 200,
    steps: [{ distance: 2000, name: 'Southwestern Motorway', maneuver: 'depart' }] };
  assert.equal(matchRouteClosures(route, [event]).length, 0);
  assert.equal(matchRouteClosures({ ...route, steps: [{ distance: 2000, name: '', maneuver: 'on ramp' }] }, [event]).length, 1);
  assert.equal(matchRouteClosures({ ...route, steps: [{ distance: 2000, name: 'SH20 On-ramp', maneuver: 'turn' }] }, [event]).length, 1);
  assert.equal(matchRouteClosures(route, [{ ...event, roadName: 'SH20 closed between Queenstown on-ramp and Maioro off-ramp' }]).length, 1);
  const transfer = { ...route, steps: [{ distance: 500, name: 'Northwestern Motorway', maneuver: 'depart' },
    { distance: 1500, name: 'Southwestern Motorway', maneuver: 'off ramp' }] };
  assert.equal(matchRouteClosures(transfer, [event]).length, 0);
  assert.equal(matchRouteClosures(transfer, [{ ...event, roadName: 'SH16 SH20 Off-ramp' }]).length, 1);
});

test('unavailable detour service retains the original explicitly blocked route', async () => {
  const previous = globalThis.fetch;
  const points: LonLat[] = [[175, -37], [175, -36.98]];
  const event: any = { id: 'failed-detour', type: 'roadClosure',
    location: { longitude: 175, latitude: -36.99 }, geometry: [], headingDegrees: 0,
    roadName: 'Closed road', confidence: 1, observation: 'official', severity: 'critical',
    validFrom: null, validUntil: null, metadata: {},
    source: { provider: 'NZTA', country: 'NZ', sourceId: 'failed-detour' } };
  globalThis.fetch = async url => new URL(String(url)).host === 'valhalla1.openstreetmap.de'
    ? new Response('unavailable', { status: 503 }) : Response.json(payload(points));
  try {
    const plan = await routeOptions(points[0], points[1], {
      CAMERA_DATA: { async get() { return { events: [event], syncStatus: 'live', retrievedAt: new Date(Date.now()-1000).toISOString() }; } },
    }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(plan.roadAwareness.avoidance, 'blocked');
    assert.deepEqual(plan.options[0].closureIds, ['failed-detour']);
    assert.deepEqual(plan.options[0].coordinates, points);
  } finally { globalThis.fetch = previous; }
});

test('signed motorway direction follows a curved carriageway while its opposite stays open', () => {
  const points: LonLat[] = [[174.73,-36.91],[174.75,-36.916]];
  const event: any = { id: 'curve', type: 'roadClosure', location: { longitude: 174.74, latitude: -36.913 },
    geometry: [], headingDegrees: 180, roadName: 'SH20 Full Closure Southbound', confidence: 1,
    observation: 'official', validFrom: null, validUntil: null, metadata: {} };
  assert.equal(matchRouteClosures({ coordinates: points, durationSeconds: 200 }, [event]).length, 1);
  assert.equal(matchRouteClosures({ coordinates: [...points].reverse(), durationSeconds: 200 }, [event]).length, 0);
});
test('a newly encountered closure is excluded in one bounded further detour round', async () => {
  const previous = globalThis.fetch;
  const from: LonLat = [176,-38], to: LonLat = [176,-37.98];
  const original = [from,to];
  const first: LonLat[] = [from,[176.01,-37.99],to];
  const final: LonLat[] = [from,[175.99,-37.99],to];
  const event = (id: string, longitude: number, latitude: number): any => ({ id, type: 'roadClosure',
    location: { longitude, latitude }, geometry: [], headingDegrees: null, roadName: 'Closed street', confidence: 1,
    observation: 'official', severity: 'critical', validFrom: null, validUntil: null, metadata: {},
    source: { provider: 'NZTA', country: 'NZ', sourceId: id } });
  const events=[event('initial',176,-37.99),event('new',176.01,-37.99)];
  let rounds=0;
  globalThis.fetch=async (url,init) => {
    if (new URL(String(url)).host==='routing.openstreetmap.de') return Response.json(payload(original));
    rounds++;
    const body=JSON.parse(init.body as string);
    assert.equal(body.exclude_locations.length,rounds);
    return Response.json(payload(rounds===1?first:final));
  };
  try {
    const plan=await routeOptions(from,to,{CAMERA_DATA:{async get(){return {events,syncStatus:'live',retrievedAt:new Date(Date.now()-1000).toISOString()};}}},[],['DRIVE'],()=>{},{forceIndependent:true});
    assert.equal(rounds,2);
    assert.equal(plan.roadAwareness.avoidance,'detour');
    assert.deepEqual(plan.options[0].coordinates,final);
  } finally {globalThis.fetch=previous;}
});

test('closed corridors switch to local roads after bounded attempts and verify final route', async () => {
  const previous = globalThis.fetch;
  const from: LonLat = [176,-38], to: LonLat = [176,-37.98];
  const original: LonLat[] = [from,to];
  const first: LonLat[] = [from,[176.01,-37.99],to];
  const safe: LonLat[] = [from,[175.99,-37.99],to];
  const event = (id: string, longitude: number, latitude: number): any => ({
    id, type: 'roadClosure', location: { longitude, latitude },
    geometry: [], headingDegrees: null, roadName: 'Closed street',
    confidence: 1, observation: 'official', severity: 'critical',
    validFrom: null, validUntil: null, metadata: {},
    source: { provider: 'NZTA', country: 'NZ', sourceId: id }
  });
  const events = [event('original',176,-37.99), event('alternative',176.01,-37.99)];
  const requests: any[] = [];
  globalThis.fetch = async (url, init) => {
    if (new URL(String(url)).host === 'routing.openstreetmap.de') return Response.json(payload(original));
    const request = JSON.parse(init.body as string);
    requests.push(request);
    if (requests.length === 3) return Response.json(payload(safe));
    return Response.json(payload(first));
  };
  try {
    const plan = await routeOptions(from, to, {
      CAMERA_DATA: { async get() {
        return { events, syncStatus: 'live', retrievedAt: new Date(Date.now()-1000).toISOString() };
      } }
    }, [], ['DRIVE'], () => {}, { forceIndependent: true });
    assert.equal(requests.length, 3);
    assert.equal(requests[0].costing_options, undefined);
    assert.equal(requests[1].costing_options, undefined);
    assert.equal(requests[2].costing_options.auto.use_highways, 0);
    assert.equal(requests[2].exclude_locations.length, 2);
    assert.equal(plan.roadAwareness.avoidance, 'detour');
    assert.deepEqual(plan.options[0].coordinates, safe);
  } finally { globalThis.fetch = previous; }
});
