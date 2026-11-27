import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { reserveRoadReportQuota } from '../src/road_report_quota.ts';
import worker from '../src/worker.ts';
import { createHash } from 'node:crypto';
import { migratedD1 } from './d1_fixture.ts';

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

test('global community report budget caps reports at 200 per day', async () => {
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


test('authenticated mobile reports are stored in D1, further submissions return 429, and failed writes are refunded', async () => {
  const { sqlite, db } = migratedD1();
  const token = 'a'.repeat(64);
  sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)').run('real-user', 'user@example.com', '', '', 0);
  sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)')
    .run(createHash('sha256').update(token).digest('hex'), 'real-user', Date.now() + 60000);
  const kvWrites = [];
  const env = { USER_DB: db, CAMERA_DATA: { async get() { return null; }, async put(key) { kvWrites.push(key); } } };
  const post = () => worker.fetch(new Request('https://waybi.co/api/road-reports', {
    method: 'POST',
    headers: { 'x-waybi-client': 'mobile', 'content-type': 'application/json', cookie: `waybi_session=${token}` },
    body: JSON.stringify({ type: 'incident', latitude: -36.85, longitude: 174.76 }),
  }), env, { waitUntil() {} });
  try {
    // A storage failure returns 503 and does not consume the daily allowance.
    sqlite.exec('ALTER TABLE road_reports RENAME TO road_reports_offline');
    const failed = await post();
    assert.equal(failed.status, 503);
    assert.ok(!JSON.stringify(await failed.json()).includes('road_reports'));
    sqlite.exec('ALTER TABLE road_reports_offline RENAME TO road_reports');
    for (let i = 0; i < 6; i++) assert.equal((await post()).status, i < 5 ? 201 : 429);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM road_reports').get().c, 5);
    assert.deepEqual(kvWrites, [], 'reports no longer write the shared KV array');
  } finally { sqlite.close(); }
});

test('a refused global reservation returns the user unit', async () => {
  const { db, sqlite } = quotaDb();
  try {
    const now = new Date('2026-10-09T13:00:00Z');
    for (let i = 0; i < 200; i++) await reserveRoadReportQuota(db, `u-${i}`, now);
    assert.equal(await reserveRoadReportQuota(db, 'late-user', now), false);
    const user = sqlite.prepare("SELECT calls FROM api_usage_daily WHERE sku = 'user:late-user'").get();
    assert.equal(user.calls, 0);
  } finally { sqlite.close(); }
});
