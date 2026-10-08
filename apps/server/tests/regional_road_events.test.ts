import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeNswRoadEvent, loadNswRoadEventState } from '../src/au_road_events.ts';
import { loadRegionalRoadEvents } from '../src/regional_road_events.ts';
import { loadRoadEventState, normalizeRoadEvent } from '../src/road_events.ts';

const now = new Date('2026-10-06T08:20:00Z');
const nzEvent = (extra = {}) => ({ id: 1, status: 'Active', impact: 'Road Closed',
  locationArea: 'SH1 Symonds Street On-ramp Southbound', geometry: 'POINT (174.76356 -36.85880)',
  startDate: '2026-10-06T08:00:00Z', endDate: '2026-10-06T16:00:00Z', ...extra });
const nswEvent = (extra = {}) => ({ type: 'Feature', id: 7,
  geometry: { type: 'Point', coordinates: [151.2, -33.86] },
  properties: { ended: false, incidentKind: 'Unplanned', mainCategory: 'Crash',
    periods: [{ closureType: 'ROAD_CLOSURE', direction: 'Southbound' }],
    roads: [{ mainStreet: 'Pacific Highway' }], otherAdvice: '<p>Use <b>another route</b></p>', ...extra } });
function kv(initial = new Map()) {
  return { CAMERA_DATA: { async get(key) { return initial.get(key) ?? null; },
    async put(key, value) { initial.set(key, JSON.parse(value)); } } };
}
test('Symonds ramp closure is active during the evening and its curved ramp is not excluded by motorway heading', () => {
  const closure = normalizeRoadEvent(nzEvent(), now);
  assert.equal(closure.type, 'roadClosure');
  assert.equal(closure.headingDegrees, null);
  assert.equal(normalizeRoadEvent(nzEvent({ locationArea: 'SH1 Southbound' }), now).headingDegrees, 180);
  assert.equal(normalizeRoadEvent(nzEvent({ status: 'Resolved' }), now), null);
  assert.equal(normalizeRoadEvent(nzEvent(), new Date('2026-10-06T17:00:00Z')), null);
});
test('NZ snapshots coalesce concurrent requests, filter expired events and back off after outages', async () => {
  let calls = 0;
  const store = new Map(), env = kv(store);
  const fetcher = async () => { calls++; return Response.json({ response: { roadevent: [nzEvent()] } }); };
  const results = await Promise.all(Array.from({length: 50}, () => loadRoadEventState(env, fetcher, now)));
  assert.equal(calls, 1);
  assert.ok(results.every(state => state.events.length === 1));
  assert.equal((await loadRoadEventState(env, fetcher, new Date(now.getTime()+60000))).syncStatus, 'live');
  assert.equal(calls, 1);
  assert.equal((await loadRoadEventState(env, fetcher, new Date(now.getTime()+11*60000))).syncStatus, 'live');
  assert.equal(calls, 1, 'requests between Crons should not write KV');
  const failure = async () => { calls++; throw new Error('offline'); };
  const later = new Date(now.getTime()+13*60000);
  const stale = await loadRoadEventState(env, failure, later);
  assert.equal(stale.syncStatus, 'stale');
  assert.equal(stale.retrievedAt, now.toISOString());
  await loadRoadEventState(env, failure, new Date(later.getTime()+60000));
  assert.equal(calls, 2);
  const expired = await loadRoadEventState(env, failure, new Date(now.getTime()+20*60000));
  assert.equal(expired.syncStatus, 'unavailable');
  assert.deepEqual(expired.events, []);
});
test('TfNSW distinguishes full closures from lane works, strips HTML and does not invent closure lines', () => {
  const closure = normalizeNswRoadEvent(nswEvent(), now);
  assert.equal(closure.type, 'roadClosure');
  assert.equal(closure.headingDegrees, 180);
  assert.deepEqual(closure.geometry, []);
  assert.equal(closure.source.country, 'AU');
  assert.equal(closure.metadata.comments, 'Use another route');
  const works = normalizeNswRoadEvent(nswEvent({ mainCategory: 'Roadworks',
    periods: [{ closureType: 'LANE_CLOSURE', direction: 'Both directions' }] }), now);
  assert.equal(works.type, 'roadworks');
  assert.equal(works.headingDegrees, null);
  assert.equal(normalizeNswRoadEvent(nswEvent({ ended: true }), now), null);
  assert.equal(normalizeNswRoadEvent(nswEvent({ incidentKind: 'Planned', impactingNetwork: false }), now), null);
  assert.equal(normalizeNswRoadEvent(nswEvent({ end: now.getTime()-1 }), now), null);
});
test('NSW shares the three feeds for concurrent users; request area selects coverage instead of account country', async () => {
  const env = kv(); let calls = 0;
  const fetcher = async () => { calls++; return Response.json({type:'FeatureCollection', features:[nswEvent()]}); };
  const states = await Promise.all(Array.from({length: 25}, () => loadNswRoadEventState(env, fetcher, now)));
  assert.equal(calls, 3);
  assert.ok(states.every(state => state.events.length === 1));
  const sydney = await loadRegionalRoadEvents(env, [151.2,-33.86], 'NZ', fetcher, now);
  assert.deepEqual(sydney.officialCoverage, ['AU-NSW']);
  const tokyo = await loadRegionalRoadEvents(env, [139.7,35.6], 'NZ', fetcher, now);
  const melbourne = await loadRegionalRoadEvents(env, [144.96,-37.81], 'AU', fetcher, now);
  assert.deepEqual(tokyo.officialCoverage, []);
  assert.deepEqual(melbourne.officialCoverage, []);
  assert.equal(calls, 3);
});
