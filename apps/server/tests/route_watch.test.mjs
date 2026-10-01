import test from 'node:test';
import assert from 'node:assert/strict';

import { evaluateRouteWatch, routeGeometryFresh, __test } from '../src/route_watch.mjs';

const route = [
  { latitude: -36.85, longitude: 174.75 },
  { latitude: -36.85, longitude: 174.80 },
  { latitude: -36.85, longitude: 174.85 }
];

function event({
  id,
  latitude,
  longitude,
  severity = 'warning',
  type = 'roadworks',
  validFrom = null,
  validUntil = null
}) {
  return {
    id,
    type,
    severity,
    location: { latitude, longitude },
    geometry: [],
    validFrom,
    validUntil,
    roadName: 'SH1',
    metadata: {
      description: 'Road works',
      impact: severity === 'critical' ? 'Road closed' : 'Delays'
    }
  };
}

test('Route Watch keeps the production corridor and uses a 29-day route cache', () => {
  assert.equal(__test.ROUTE_CORRIDOR_METERS, 180);
  assert.equal(__test.ROUTE_CACHE_MS, 29 * 24 * 60 * 60 * 1000);
});

test('expired route geometry is not eligible for background monitoring', () => {
  const now = new Date('2026-10-02T00:00:00Z');
  assert.equal(routeGeometryFresh({ geometry_expires_at: now.getTime() + 1 }, now), true);
  assert.equal(routeGeometryFresh({ geometry_expires_at: now.getTime() }, now), false);
  assert.equal(routeGeometryFresh({ geometry_expires_at: null }, now), false);
});

test('Route Watch matches official events near the saved route corridor', () => {
  const result = evaluateRouteWatch(route, [
    event({ id: 'near', latitude: -36.8495, longitude: 174.80 }),
    event({ id: 'far', latitude: -36.84, longitude: 174.80 })
  ], new Date('2026-10-02T00:00:00Z'));

  assert.equal(result.status, 'warning');
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0].id, 'near');
  assert.ok(result.events[0].distanceFromRouteMeters < __test.ROUTE_CORRIDOR_METERS);
});

test('Route Watch promotes closures to disrupted and ignores expired events', () => {
  const now = new Date('2026-10-02T00:00:00Z');
  const result = evaluateRouteWatch(route, [
    event({
      id: 'closed',
      latitude: -36.85,
      longitude: 174.81,
      severity: 'critical',
      type: 'roadClosure'
    }),
    event({
      id: 'expired',
      latitude: -36.85,
      longitude: 174.82,
      validUntil: '2026-10-01T23:00:00Z'
    })
  ], now);

  assert.equal(result.status, 'disrupted');
  assert.deepEqual(result.events.map((item) => item.id), ['closed']);
});

test('Route Watch stays healthy when no official event intersects the route', () => {
  const result = evaluateRouteWatch(route, [
    event({ id: 'far', latitude: -36.82, longitude: 174.80 })
  ]);
  assert.equal(result.status, 'healthy');
  assert.deepEqual(result.events, []);
});
