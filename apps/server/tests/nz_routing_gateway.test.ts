import test from 'node:test';
import assert from 'node:assert/strict';
import { engineGateway } from '../../../infra/nz-routing/cloudflare/gateway.ts';

const route = { locations: [{ lat: -36.85, lon: 174.76 }, { lat: -37.78, lon: 175.28 }],
  costing: 'auto', format: 'osrm', shape_format: 'geojson', date_time: { type: 0 } };
const request = (body = route, authorization = 'Bearer test-only-key') => new Request('https://engine.example/route', {
  method: 'POST', headers: { authorization }, body: JSON.stringify(body),
});

test('unconfigured, unauthorized and unsupported requests never start a billable container', async () => {
  const fetchEngine = async () => { throw new Error('must not start'); };
  assert.equal((await engineGateway(request(), undefined, fetchEngine)).status, 503);
  for (const key of ['', 'Bearer bad', 'Bearer test-only-key-extra']) {
    assert.equal((await engineGateway(request(route, key), 'test-only-key', fetchEngine)).status, 401);
  }
  assert.equal((await engineGateway(new Request('https://engine.example/matrix', {
    headers: { authorization: 'Bearer test-only-key' } }), 'test-only-key', fetchEngine)).status, 404);
});

test('NZ validation and streamed byte limits hold before forwarding the original route and its exclusions', async () => {
  const fetchEngine = async (request: Request) => {
    assert.equal(request.headers.get('authorization'), null);
    assert.equal(request.url, 'http://container/route');
    assert.deepEqual(await request.json(), route);
    return Response.json({ code: 'Ok', routes: [1] });
  };
  const response = await engineGateway(request(), 'test-only-key', fetchEngine);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  for (const invalid of [{ ...route, locations: [{ lat: 35.6, lon: 139.7 }, route.locations[1]] },
    { ...route, locations: Array(11).fill(route.locations[0]) }, { ...route, costing: 'transit' },
    { ...route, shape_format: 'polyline6' }]) {
    assert.equal((await engineGateway(request(invalid), 'test-only-key', async () => { throw new Error('must not forward'); })).status, 400);
  }
  const oversized = new Request('https://engine.example/route', { method: 'POST',
    headers: { authorization: 'Bearer test-only-key' }, body: '界'.repeat(22_000) });
  assert.equal((await engineGateway(oversized, 'test-only-key', fetchEngine)).status, 413);
});
