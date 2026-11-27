import test from 'node:test';
import assert from 'node:assert/strict';
import { distanceMeters, formatDistance, matchCamerasToRoute, nearestOnRoute, roadMatches, type Camera, type Route } from '../src/index.ts';

const camera = (latitude: number, longitude: number, location = 'Queen Street'): Camera => ({ id: `${latitude}`, name: 'Camera', region: 'Auckland', suburb: 'CBD', location, type: 'Spot speed', latitude, longitude, source: 'NZTA', updatedAt: '2026-08-26' });
const route: Route = { coordinates: [[174.764, -36.85], [174.764, -36.84]], distance: 1110, duration: 100, steps: [{ distance: 1110, duration: 100, name: 'Queen Street', instruction: 'Continue', maneuver: 'straight', location: [174.764, -36.85] }] };

test('distance and route projection use metres', () => {
  assert.ok(distanceMeters([174.764, -36.85], [174.764, -36.84]) > 1000);
  const projection = nearestOnRoute([174.764, -36.845], route.coordinates);
  assert.ok(projection.alongMeters > 400 && projection.alongMeters < 700);
});

test('road normalization accepts road abbreviations', () => {
  assert.equal(roadMatches('Queen Street', 'Queen St'), true);
  assert.equal(roadMatches('State Highway 1', 'SH1'), true);
});

test('adjacent road is excluded from route alerts', () => {
  const hits = matchCamerasToRoute([camera(-36.845, 174.764), camera(-36.845, 174.765, 'Albert Street')], route);
  assert.equal(hits.length, 1);
  assert.equal(hits[0]?.camera.location, 'Queen Street');
});

test('distances use units of the active language', () => {
  assert.equal(formatDistance(240, 'en'), '240 m');
  assert.equal(formatDistance(240, 'zh'), '240 米');
  assert.equal(formatDistance(2400, 'en'), '2.4 km');
  assert.equal(formatDistance(2400, 'zh'), '2.4 公里');
  assert.equal(formatDistance(24000, 'zh'), '24 公里');
});
