import test from 'node:test';
import assert from 'node:assert/strict';

import {
  evaluateRouteWatch,
  handleRouteWatch,
  handleRouteWatchAlerts,
  routeGeometryFresh,
  __test
} from '../src/route_watch.ts';

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


function entitlementDb(plan) {
  return {
    prepare(sql) {
      return {
        bind() {
          return {
            async first() {
              if (sql.includes('FROM sessions')) {
                return { id: 'user-1', email: 'test@example.com' };
              }
              if (sql.includes('FROM user_subscriptions')) {
                return plan === 'plus'
                  ? { plan: 'plus', source: 'test', expiresAt: null }
                  : null;
              }
              return null;
            },
            async all() {
              if (sql.includes('FROM route_watches')) return { results: [] };
              return { results: [] };
            },
            async run() {
              return { success: true };
            }
          };
        }
      };
    }
  };
}

test('Route Watch rejects signed-in free users with PLUS_REQUIRED', async () => {
  const response = await handleRouteWatch(
    new Request('https://example.test/api/route-watches', {
      headers: { cookie: `waybi_session=${'a'.repeat(64)}` }
    }),
    { USER_DB: entitlementDb('free'), CAMERA_DATA: {} }
  );
  assert.equal(response.status, 403);
  const body = await response.json();
  assert.equal(body.code, 'PLUS_REQUIRED');
});

test('Route Watch returns Plus entitlement for active Plus users', async () => {
  const response = await handleRouteWatch(
    new Request('https://example.test/api/route-watches', {
      headers: { cookie: `waybi_session=${'b'.repeat(64)}` }
    }),
    { USER_DB: entitlementDb('plus'), CAMERA_DATA: {} }
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.entitlement, 'plus');
  assert.deepEqual(body.watches, []);
});


test('Route Watch alert signatures only persist warning/disrupted event sets', () => {
  assert.equal(
    __test.routeAlertSignature({
      status: 'warning',
      events: [{ id: 'b' }, { id: 'a' }]
    }),
    'warning:a|b'
  );
  assert.equal(
    __test.routeAlertSignature({
      status: 'disrupted',
      events: [{ id: 'closed' }]
    }),
    'disrupted:closed'
  );
  assert.equal(
    __test.routeAlertSignature({ status: 'healthy', events: [] }),
    ''
  );
});

test('proactive alert feed rejects free users with PLUS_REQUIRED', async () => {
  const response = await handleRouteWatchAlerts(
    new Request('https://example.test/api/route-watch-alerts', {
      headers: { cookie: `waybi_session=${'c'.repeat(64)}` }
    }),
    { USER_DB: entitlementDb('free'), CAMERA_DATA: {} }
  );
  assert.equal(response.status, 403);
  assert.equal((await response.json()).code, 'PLUS_REQUIRED');
});

test('proactive alert feed returns unread alerts for Plus users', async () => {
  const db = entitlementDb('plus');
  const originalPrepare = db.prepare.bind(db);
  db.prepare = (sql) => {
    if (sql.includes('FROM route_watch_alerts')) {
      return {
        bind() {
          return {
            async all() {
              return {
                results: [{
                  id: 'alert-1',
                  route_watch_id: 'watch-1',
                  label: 'Work',
                  status: 'warning',
                  events_json: JSON.stringify([{ id: 'road-1', roadName: 'SH1' }]),
                  created_at: Date.parse('2026-10-02T00:00:00Z'),
                  read_at: null,
                }]
              };
            }
          };
        }
      };
    }
    return originalPrepare(sql);
  };

  const response = await handleRouteWatchAlerts(
    new Request('https://example.test/api/route-watch-alerts', {
      headers: { cookie: `waybi_session=${'d'.repeat(64)}` }
    }),
    { USER_DB: db, CAMERA_DATA: {} }
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.entitlement, 'plus');
  assert.equal(body.alerts.length, 1);
  assert.equal(body.alerts[0].label, 'Work');
  assert.equal(body.alerts[0].events[0].roadName, 'SH1');
});
