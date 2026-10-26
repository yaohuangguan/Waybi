import test from 'node:test';
import assert from 'node:assert/strict';
import { assessRouteConditions, applyRouteConditions } from '../src/route_conditions.ts';
import type { LonLat, OfficialRoadEvent } from '../src/types.ts';

const now = new Date('2026-10-27T00:00:00Z');
const points: LonLat[] = [[174.76, -36.86], [174.76, -36.85]];
const route = { mode: 'drive', coordinates: points, distanceMeters: 1112, durationSeconds: 120 };
function flow(extra = {}, segment = {}) {
  return { syncStatus: 'live', sourceUpdatedAt: now.toISOString(), segments: [{
    level: 'heavy', geometryQuality: 'road-matched', geometry: { coordinates: points }, ...segment,
  }], ...extra };
}
function event(type: OfficialRoadEvent['type'], extra = {}): OfficialRoadEvent {
  return { id: type, type, location: { longitude: 174.76, latitude: -36.855 }, geometry: [],
    roadName: null, headingDegrees: null, confidence: 1, observation: 'official', severity: 'warning',
    validFrom: null, validUntil: null, source: { provider: 'NZTA', country: 'NZ', region: null,
      sourceId: type, updatedAt: now.toISOString() }, metadata: {}, ...extra };
}

test('fresh directed road geometry contributes covered length and a ranking penalty, never an invented ETA', () => {
  const result = assessRouteConditions(route, flow(), [], null, now);
  assert.equal(result.trafficStatus, 'live');
  assert.ok(result.coveredMeters > 1100 && result.coveredMeters < 1120);
  assert.equal(result.heavyMeters, result.coveredMeters);
  assert.equal(result.moderateMeters, 0);
  assert.ok(result.rankingPenalty > 130 && result.rankingPenalty < 140);
  assert.equal(result.penaltyBasis, 'qualitative-ranking-only');
  assert.equal(result['trafficDelaySeconds'], undefined);
  assert.equal(result['durationSeconds'], undefined);
});

test('moderate and free sections are distinguished; overlaps never double count road length', () => {
  const moderate = assessRouteConditions(route, flow({}, { level: 'moderate' }), [], null, now);
  const free = assessRouteConditions(route, flow({}, { level: 'free' }), [], null, now);
  assert.ok(moderate.moderateMeters > 1100);
  assert.ok(moderate.rankingPenalty > 30 && moderate.rankingPenalty < 40);
  assert.equal(free.rankingPenalty, 0);
  const duplicated = flow(); duplicated.segments.push(duplicated.segments[0]);
  assert.equal(assessRouteConditions(route, duplicated, [], null, now).coveredMeters, moderate.coveredMeters);
});

test('reverse carriageways, nearby roads, unmatched geometry and unknown conditions are not borrowed', () => {
  for (const segment of [
    { geometry: { coordinates: [...points].reverse() } },
    { geometry: { coordinates: points.map(([x, y]) => [x + .001, y]) } },
    { geometryQuality: 'unmatched' }, { level: 'unknown' },
    { geometry: { coordinates: [points[0], points[0]] } },
  ]) {
    const result = assessRouteConditions(route, flow({}, segment), [], null, now);
    assert.equal(result.coveredMeters, 0);
    assert.equal(result.rankingPenalty, 0);
  }
});

test('old, future or absent traffic cannot claim live congestion or influence ranking', () => {
  for (const state of [null, flow({ syncStatus: 'stale' }),
    flow({ sourceUpdatedAt: new Date(now.getTime() - 11 * 60000).toISOString() }),
    flow({ sourceUpdatedAt: new Date(now.getTime() + 60000).toISOString() })]) {
    const result = assessRouteConditions(route, state, [], null, now);
    assert.notEqual(result.trafficStatus, 'live');
    assert.equal(result.coveredMeters, 0);
    assert.equal(result.rankingPenalty, 0);
  }
});

test('a nearby parallel street cannot borrow motorway congestion; posted aliases still match', () => {
  const state = flow({}, { motorway: 'Southwestern Motorway' });
  const otherRoad = { ...route, steps: [{ distance: 2000, name: 'Airport Road' }] };
  assert.equal(assessRouteConditions(otherRoad, state, [], null, now).coveredMeters, 0);
  const motorway = { ...route, steps: [{ distance: 500, name: 'Auckland Southwestern Motorway' },
    { distance: 1500, name: 'State Highway 20' }] };
  assert.ok(assessRouteConditions(motorway, state, [], null, now).coveredMeters > 1100);
});

test('official active incidents and roadworks affect ranking without becoming fake road closures', () => {
  const events = [event('incident'), event('roadworks'), event('roadClosure'),
    event('flooding', { validUntil: now.toISOString() }), event('slip', { observation: 'inferred' })];
  const result = assessRouteConditions(route, null, events, now.toISOString(), now);
  assert.deepEqual(result.incidentIds, ['incident']);
  assert.deepEqual(result.roadworkIds, ['roadworks']);
  assert.equal(result.rankingPenalty, 150);
  assert.equal(result['closureIds'], undefined);
  const stale = assessRouteConditions(route, null, events, new Date(now.getTime() - 16 * 60000).toISOString(), now);
  assert.equal(stale.rankingPenalty, 0);
  assert.deepEqual(stale.incidentIds, []);
});

test('missing shared snapshots fail without network fan-out or changing mode or ETA', async () => {
  const walk = { ...route, mode: 'walk' };
  const rows = await applyRouteConditions([route, walk], { CAMERA_DATA: { async get() { throw Error('KV unavailable'); } } }, [], null, now);
  assert.equal(rows[0].durationSeconds, route.durationSeconds);
  assert.equal(rows[0].conditions.trafficStatus, 'unavailable');
  assert.equal(rows[1], walk);
});
