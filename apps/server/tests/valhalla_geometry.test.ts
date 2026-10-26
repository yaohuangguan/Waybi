import test from 'node:test';
import assert from 'node:assert/strict';
import { decodePolyline6 } from '../src/valhalla_geometry.ts';
import { fetchNzRouting } from '../src/nz_routing.ts';
import { crossesExcludedRoads } from '../src/routing_closures.ts';
import { normalizeOsrmRoutes } from '../src/routes.ts';

// Independent reference encoder with multiplication/division, not bit shifts.
function encode(points: number[][]) {
  let previous = [0, 0], result = '';
  for (const [lon, lat] of points) {
    const next = [Math.round(lat * 1e6), Math.round(lon * 1e6)];
    for (let i = 0; i < 2; i++) {
      const d = next[i] - previous[i];
      let n = d < 0 ? -2 * d - 1 : 2 * d;
      while (n >= 32) { result += String.fromCharCode((n % 32) + 32 + 63); n = Math.floor(n / 32); }
      result += String.fromCharCode(n + 63);
    }
    previous = next;
  }
  return result;
}

test('polyline6 retains southern/eastern coordinates and metre-level closure geometry', async () => {
  const coordinates = [[174.76, -36.86], [174.76, -36.85]];
  assert.deepEqual(decodePolyline6(encode(coordinates)), coordinates);
  const payload = await fetchNzRouting({ WAYBI_NZ_ROUTING_URL: 'https://waybi-test.a.run.app',
    WAYBI_NZ_ROUTING_TOKEN: 'test' }, coordinates as [number, number][], 'DRIVE', {}, [], async (_url, init) => {
    assert.equal(JSON.parse(init.body as string).shape_format, 'polyline6');
    return Response.json({ code: 'Ok', routes: [{ geometry: encode(coordinates), distance: 1110,
      duration: 100, legs: [{ steps: [{ maneuver: { location: coordinates[0] },
        intersections: [{ lanes: [{ indications: ['left'], valid: true }] }] }] }] }] });
  });
  const route = normalizeOsrmRoutes(payload, 'DRIVE')[0];
  assert.deepEqual(route.coordinates, coordinates);
  assert.equal(route.steps[0].lanes.length, 1);
  assert.equal(crossesExcludedRoads(route, [{ lat: -36.855, lon: 174.76, heading: 0 }]), true);
});

test('polyline6 supports negative longitude, deltas crossing zero, and rejects malformed shapes', () => {
  const points = [[-122.123456, 38.123456], [0, 0], [174.999999, -36.999999]];
  assert.deepEqual(decodePolyline6(encode(points)), points);
  for (const malformed of ['', '?', '_', '______', '\n\n', '??', encode([[200, 100], [201, 101]])]) {
    assert.throws(() => decodePolyline6(malformed), /Invalid|Incomplete/);
  }
});
