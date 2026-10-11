import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../data/transit-lanes.json' with { type: 'json' };
import type { TransitSnapshot, TransitLane } from '../src/transit_lanes.ts';
import { parseTransitSchedule, transitActive, transitActiveDuring, matchTransitRoute, transitRoadBlocks, readTransitSnapshot, refreshTransitSnapshot } from '../src/transit_lanes.ts';
import { applyTransitRoadRestrictions } from '../src/routes.ts';

const snapshot = seed as TransitSnapshot;
const lane = snapshot.lanes.find(l => l.id === 'at:svl:69:0')!;
const bridge = snapshot.lanes.find(l => l.roadName === 'Grafton Bridge')!;
const friday = new Date('2026-10-08T19:00:00Z'); // Friday 08:00 NZDT.
const route = (l: TransitLane = lane) => ({ mode: 'drive', coordinates: l.coordinates, durationSeconds: 60, steps: [{ name: l.roadName }], warnings: [], distanceMeters: 200 });

test('official seed preserves all GIS lanes, unknown hours and explicit whole-road scope', () => {
  assert.equal(snapshot.lanes.length, 361);
  assert.equal(snapshot.lanes.filter(l => l.wholeRoad).length, 2);
  assert.equal(snapshot.lanes.filter(l => !l.schedule.known).length, 90);
  assert.ok(snapshot.lanes.filter(l => l.kind === 'BusOnly').every(l => !l.wholeRoad));
  assert.equal(lane.schedule.known, true);
  assert.deepEqual(lane.schedule.windows, [[0, 1440]]);
});

test('hours parser handles published formats without guessing missing or provisional hours', () => {
  for (const raw of ['0700-1000,1600-1900', '7-10am & 4-7pm Monday to Friday', '7-10am, 4-7pm Monday to Friday']) {
    assert.deepEqual(parseTransitSchedule('Monday to Friday', raw), { days: [1, 2, 3, 4, 5], windows: [[420, 600], [960, 1140]], known: true });
  }
  assert.deepEqual(parseTransitSchedule('Monday to Friday', '0630 - 0930, 1500 - 1900 (Mon. - Fri)').windows, [[390, 570], [900, 1140]]);
  for (const raw of [null, '', 'Mon-Fri', '3-7pm TBC', '25:90-10am']) assert.equal(parseTransitSchedule('Monday to Friday', raw).known, false);
});

test('NZ local time includes weekdays, exclusive end, overnight and DST independently of caller timezone', () => {
  const peak = parseTransitSchedule('Monday to Friday', '7-10am & 4-7pm Monday to Friday');
  assert.equal(transitActive(peak, new Date('2026-10-08T18:00:00Z')), true);
  assert.equal(transitActive(peak, new Date('2026-10-08T21:00:00Z')), false);
  assert.equal(transitActive(peak, new Date('2026-10-09T19:00:00Z')), false); // Saturday.
  assert.equal(transitActive(peak, new Date('2026-07-09T19:00:00Z')), true); // NZST 07:00.
  const night = parseTransitSchedule('Monday to Friday', '2200-0200');
  assert.equal(transitActive(night, new Date('2026-10-09T12:00:00Z')), true); // Sat 01:00, Friday window.
  assert.equal(transitActive(night, new Date('2026-10-09T13:00:00Z')), false);
  assert.equal(transitActiveDuring(peak, new Date('2026-10-08T17:59:50Z'), new Date('2026-10-08T18:00:10Z')), true);
});

test('actual Symonds lane geometry matches the northbound approach, not opposite or crossing traffic', () => {
  assert.equal(matchTransitRoute(route(), [lane]).length, 1);
  assert.equal(matchTransitRoute({ ...route(), coordinates: [...lane.coordinates].reverse() }, [lane]).length, 0);
  const [x, y] = lane.coordinates[0];
  assert.equal(matchTransitRoute({ ...route(), coordinates: [[x - .002, y - .002], [x + .002, y - .002]] }, [lane]).length, 0);
  assert.equal(transitRoadBlocks(route(), snapshot, friday).length, 0);
});

test('whole-road restriction applies by time and direction without blocking a neighbouring general lane', async () => {
  assert.equal(transitRoadBlocks(route(bridge), snapshot, friday).length, 1);
  assert.equal(transitRoadBlocks(route(bridge), snapshot, new Date('2026-10-10T19:00:00Z')).length, 0);
  assert.equal(transitRoadBlocks({ ...route(bridge), coordinates: bridge.coordinates.map(([x, y]) => [x + .001, y]) }, snapshot, friday).length, 0);
  const blocked = { id: 'bridge', ...route(bridge) }, legal = { id: 'legal', ...route() };
  const env = { CAMERA_DATA: { get: async () => snapshot } };
  assert.deepEqual((await applyTransitRoadRestrictions([blocked, legal], env, friday)).map(r => r.id), ['legal']);
  const only = await applyTransitRoadRestrictions([blocked], env, friday);
  assert.ok(only[0].restrictedRoadIds.length);
  assert.equal((await applyTransitRoadRestrictions([blocked], env, new Date('2026-10-10T19:00:00Z')))[0].restrictedRoadIds, undefined);
});

test('weekly cron retains seed on failure and visitors never cause a source sync', async () => {
  let puts = 0, fetches = 0, stored: any = snapshot;
  const env = { CAMERA_DATA: { get: async () => stored, put: async (_k: string, v: string) => { puts++; stored = JSON.parse(v); } } };
  const fetcher = async () => { fetches++; throw new Error('offline'); };
  await refreshTransitSnapshot(env, fetcher as typeof fetch, new Date(Date.parse(snapshot.checkedAt) + 86400000));
  assert.equal(fetches, 0); assert.equal(puts, 0);
  const later = new Date(Date.parse(snapshot.checkedAt) + 8 * 86400000);
  await refreshTransitSnapshot(env, fetcher as typeof fetch, later);
  assert.equal(fetches, 1); assert.equal(puts, 1); assert.equal(stored.lanes.length, 361); assert.equal(stored.syncStatus, 'stale');
  await refreshTransitSnapshot(env, fetcher as typeof fetch, new Date(later.getTime() + 86400000));
  assert.equal(fetches, 1); assert.equal(puts, 1);
});

test('KV failure retains the bundled lanes and still protects restricted routes', async () => {
  const env = { CAMERA_DATA: { get: async () => { throw new Error('KV unavailable'); } } };
  assert.equal((await readTransitSnapshot(env, false)).lanes.length, 361);
  const result = await applyTransitRoadRestrictions([{ id: 'bridge', ...route(bridge) }], env, friday);
  assert.ok(result[0].restrictedRoadIds.length);
});
