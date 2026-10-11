import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { reserveRoadReportQuota } from '../src/road_report_quota.ts';
import worker from '../src/worker.ts';

function quotaDb() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../../../migrations/0005_cost_guard.sql', import.meta.url), 'utf8'));
  const db = { prepare(sql) { return { bind(...args) { return {
    async first() { return sqlite.prepare(sql).get(...args) ?? null; }
  }; } }; } };
  return { db, sqlite };
}

test('report budget caps each signed-in user at 5/day and resets at UTC midnight', async () => {
  const { db, sqlite } = quotaDb();
  try {
    const day = new Date('2026-10-09T00:00:01Z');
    for (let n = 0; n < 5; n++) assert.equal(await reserveRoadReportQuota(db, 'user-a', day), true);
    assert.equal(await reserveRoadReportQuota(db, 'user-a', day), false);
    assert.equal(await reserveRoadReportQuota(db, 'user-b', day), true);
    assert.equal(await reserveRoadReportQuota(db, 'user-a', new Date('2026-10-10T00:00:01Z')), true);
  } finally { sqlite.close(); }
});

test('global community report budget prevents more than 200 KV writes per day', async () => {
  const { db, sqlite } = quotaDb();
  try {
    const now = new Date('2026-10-09T13:00:00Z');
    for (let i = 0; i < 200; i++) assert.equal(await reserveRoadReportQuota(db, `u-${i}`, now), true);
    assert.equal(await reserveRoadReportQuota(db, 'one-more-user', now), false);
    const total = sqlite.prepare("SELECT calls FROM api_usage_daily WHERE day = '2026-10-09' AND provider = '__waybi_quotas' AND sku = 'global'").get();
    assert.equal(total.calls, 200);
  } finally { sqlite.close(); }
});

test('unauthenticated community reports cannot trigger KV writes', async () => {
  const env = { CAMERA_DATA: { async put() { assert.fail('No KV writes for anonymous posts'); } },
    USER_DB: { prepare() { assert.fail('No D1 queries without a session cookie'); } } };
  const response = await worker.fetch(new Request('https://waybi.co/api/road-reports', {
    method: 'POST', headers: { 'x-waybi-client': 'mobile', 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'incident', latitude: -36.85, longitude: 174.76 })
  }), env, { waitUntil() {} });
  assert.equal(response.status, 401);
});


test('authenticated mobile report creates KV entry but further submissions return 429', async () => {
  const { db, sqlite } = quotaDb();
  const snapshots = new Map(); let writes = 0;
  const env = {
    USER_DB: { prepare(sql) {
      if (sql.includes('FROM sessions')) return { bind() { return { async first() { return { id: 'real-user', email: 'user@example.com' }; } }; } };
      if (sql.includes('FROM profiles')) return { bind() { return { async first() { return null; } }; } };
      return db.prepare(sql);
    } },
    CAMERA_DATA: {
      async get(key) { return snapshots.get(key) ?? null; },
      async put(key, value) { writes++; snapshots.set(key, JSON.parse(value)); }
    },
  };
  try {
    for (let i = 0; i < 6; i++) {
      const response = await worker.fetch(new Request('https://waybi.co/api/road-reports', {
        method: 'POST',
        headers: { 'x-waybi-client': 'mobile', 'content-type': 'application/json',
          cookie: `waybi_session=${'a'.repeat(64)}` },
        body: JSON.stringify({ type: 'incident', latitude: -36.85, longitude: 174.76 }),
      }), env, { waitUntil() {} });
      assert.equal(response.status, i < 5 ? 201 : 429);
    }
    assert.equal(writes, 5);
  } finally { sqlite.close(); }
});
