import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.ts';
import { handleBilling } from '../src/billing.ts';
import { readRoadEventState } from '../src/road_events.ts';
import { mockEdgeCache } from './mock_edge_cache.ts';

const ctx = { waitUntil() {} };

function roadEvent(id: string, longitude: number, latitude: number) {
  return { id, type: 'roadworks', severity: 'warning', location: { latitude, longitude }, geometry: [],
    validFrom: null, validUntil: null, roadName: 'SH1', observation: 'official', confidence: 0.9,
    source: { provider: 'NZTA', country: 'NZ', region: null, sourceId: id, updatedAt: null }, metadata: {} };
}

function snapshotEnv(events) {
  let gets = 0;
  const state = { events, source: 'test', checkedAt: new Date().toISOString(), retrievedAt: new Date().toISOString(),
    syncStatus: 'live', syncError: null };
  return { env: { CAMERA_DATA: { async get() { gets++; return state; }, async put() {} } }, gets: () => gets };
}

test('road-event snapshots are parsed once per isolate per minute', async () => {
  const { env, gets } = snapshotEnv([roadEvent('a', 174.76, -36.85)]);
  const first = await readRoadEventState(env as any);
  const second = await readRoadEventState(env as any);
  assert.equal(gets(), 1);
  assert.equal(first, second);
});

test('/api/road-events supports optional bbox and near+radiusMeters filters, unchanged without them', async () => {
  const { env } = snapshotEnv([roadEvent('cbd', 174.763, -36.848), roadEvent('airport', 174.79, -37.008), roadEvent('hamilton', 175.28, -37.79)]);
  const ids = async (query: string) => {
    const response = await worker.fetch(new Request(`https://w.test/api/road-events${query}`), env, ctx);
    assert.equal(response.status, 200, query);
    return (await response.json()).events.map((event) => event.id).sort();
  };
  assert.deepEqual(await ids(''), ['airport', 'cbd', 'hamilton']);
  assert.deepEqual(await ids('?near=174.76,-36.85'), ['airport', 'cbd', 'hamilton'], 'near alone only selects the region');
  assert.deepEqual(await ids('?bbox=174.6,-37.1,174.9,-36.7'), ['airport', 'cbd']);
  assert.deepEqual(await ids('?near=174.76,-36.85&radiusMeters=5000'), ['cbd']);
  for (const query of ['?bbox=1,2,3', '?bbox=175,-37,174,-36', '?bbox=160,-48,179,-34', '?near=174.76,-36.85&radiusMeters=10']) {
    assert.equal((await worker.fetch(new Request(`https://w.test/api/road-events${query}`), env, ctx)).status, 400, query);
  }
});

test('the Stripe plan catalog is cached for ten minutes', async () => {
  let retrievals = 0;
  const stripe = { prices: { retrieve: async (id) => { retrievals++; return { id, active: true, type: 'recurring', currency: 'nzd',
    unit_amount: id === 'price_cache_m' ? 499 : 3999, recurring: { interval: id === 'price_cache_m' ? 'month' : 'year', interval_count: 1 } }; } } };
  const env = { STRIPE_SECRET_KEY: 'sk_test_cache', STRIPE_WEBHOOK_SECRET: 'whsec_x', STRIPE_PRICE_MONTHLY: 'price_cache_m', STRIPE_PRICE_ANNUAL: 'price_cache_y' };
  const plans = (now: number) => handleBilling(new Request('https://w.test/api/billing/plans'), env, { stripe: stripe as any, now });
  const start = Date.now();
  assert.deepEqual((await (await plans(start)).json()).plans.map((plan) => plan.amount), [499, 3999]);
  await plans(start + 60_000);
  assert.equal(retrievals, 2, 'one catalog fetch (two prices) serves repeated views');
  await plans(start + 11 * 60_000);
  assert.equal(retrievals, 4);
});

test('/api/speed-limit shares one NZTA lookup per ~11 m cell through the edge cache', async () => {
  const cache = mockEdgeCache();
  const originalFetch = globalThis.fetch;
  const queried: string[] = [];
  globalThis.fetch = async (input) => {
    queried.push(new URL(String(input)).searchParams.get('geometry')!);
    return Response.json({ features: [{ attributes: { speedLimitZoneValue: '50', speedLimitZoneName: 'CBD', whenEffective: 0, whenIneffective: null } }] });
  };
  try {
    for (const at of ['174.763312,-36.848498', '174.763340,-36.848460']) {
      const response = await worker.fetch(new Request(`https://w.test/api/speed-limit?at=${at}`), {}, ctx);
      assert.equal((await response.json()).speedLimitKph, 50);
    }
    assert.deepEqual(queried, ['174.7633,-36.8485']);
    assert.ok([...cache.entries.keys()].some((key) => key.endsWith('/speed-limit/v1/174.7633,-36.8485')));
    await worker.fetch(new Request('https://w.test/api/speed-limit?at=174.7700,-36.8485'), {}, ctx);
    assert.equal(queried.length, 2, 'a different cell is looked up');
  } finally { globalThis.fetch = originalFetch; cache.restore(); }
});
