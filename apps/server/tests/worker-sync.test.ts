import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../data/cameras.json' with { type: 'json' };
import { syncCameras } from '../src/worker.ts';

function fakeEnv(initial = null) {
  let value = initial;
  return {
    CAMERA_DATA: {
      async get() { return value; },
      async put(_key, serialized) { value = JSON.parse(serialized); }
    }
  };
}

function nztaHtml(date, cameras) {
  const rows = cameras.map((camera) => `<tr><td>${camera.suburb}</td><td>${camera.location}</td><td>${camera.type}</td><td>${camera.latitude}</td><td>${camera.longitude}</td></tr>`).join('');
  return `<main><p>Last update: ${date}</p><h3>Northland</h3><table>${rows}</table></main>`;
}

test('successful sync records added and removed cameras while retaining a complete snapshot', async () => {
  const env = fakeEnv();
  const replacement = { suburb: 'Testville', location: 'Test Road', type: 'Spot speed', latitude: -36.85, longitude: 174.76 };
  const html = nztaHtml('2 October 2026', [...seed.cameras.slice(1), replacement]);
  const state = await syncCameras(env, async () => new Response(html));
  assert.equal(state.syncStatus, 'live');
  assert.equal(state.lastSuccessfulAt, state.checkedAt);
  assert.equal(state.sourceUpdatedAt, '2026-10-02');
  assert.equal(state.cameras.length, seed.cameras.length);
  assert.deepEqual(state.change, { added: 1, removed: 1 });
});

test('older NZTA snapshots cannot replace a newer KV snapshot', async () => {
  const env = fakeEnv();
  const newerHtml = nztaHtml('2 October 2026', seed.cameras);
  const newer = await syncCameras(env, async () => new Response(newerHtml));
  const olderHtml = nztaHtml('1 October 2026', seed.cameras.slice(1));
  const retained = await syncCameras(env, async () => new Response(olderHtml));
  assert.equal(retained.syncStatus, 'stale');
  assert.equal(retained.lastSuccessfulAt, newer.lastSuccessfulAt);
  assert.equal(retained.sourceUpdatedAt, newer.sourceUpdatedAt);
  assert.equal(retained.cameras.length, newer.cameras.length);
});


test('repeated source failures preserve the last verified time, not the latest attempt', async () => {
  const verified = '2026-10-10T03:00:00.000Z';
  const env = fakeEnv({ ...seed, syncStatus: 'live', checkedAt: verified });
  const fail = async () => new Response('unavailable', { status: 503 });
  const first = await syncCameras(env, fail);
  const second = await syncCameras(env, fail);
  assert.equal(first.lastSuccessfulAt, verified);
  assert.equal(second.lastSuccessfulAt, verified);
  assert.notEqual(second.checkedAt, verified);
  assert.equal(second.cameras.length, seed.cameras.length);
});

test('bundled seed and failed legacy records do not claim a successful source check', async () => {
  for (const initial of [null, { ...seed, syncStatus: 'stale', checkedAt: '2026-10-14T03:00:00Z' }]) {
    const state = await syncCameras(fakeEnv(initial), async () => new Response('', { status: 503 }));
    assert.equal(state.lastSuccessfulAt, null);
  }
});
