import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { reserveNzRoutingQuota } from '../src/nz_routing_quota.ts';
import { fetchNzRouting } from '../src/nz_routing.ts';

function quotaDb() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../../../migrations/0005_cost_guard.sql', import.meta.url), 'utf8'));
  const db = { prepare(sql) { return { bind(...args) { return {
    async first() { return sqlite.prepare(sql).get(...args) ?? null; }
  }; } }; } };
  return { db, sqlite };
}

test('simultaneous engine reservations cannot exceed the shared daily limit and reset at UTC midnight', async () => {
  const { db, sqlite } = quotaDb();
  try {
    const now = new Date('2026-10-26T23:59:59Z');
    const settled = await Promise.allSettled(Array.from({ length: 20 }, () => reserveNzRoutingQuota(db, '3', now)));
    assert.equal(settled.filter(result => result.status === 'fulfilled').length, 3);
    assert.equal(sqlite.prepare("SELECT calls FROM api_usage_daily WHERE provider='waybi-valhalla'").get()!.calls, 3);
    await reserveNzRoutingQuota(db, '3', new Date('2026-10-27T00:00:00Z'));
  } finally { sqlite.close(); }
});

test('unavailable or exhausted budget never invokes the owned engine, including closure requests', async () => {
  const { db, sqlite } = quotaDb();
  let calls = 0;
  const fetcher = async () => { calls++; return Response.json({ code: 'Ok', routes: [{}] }); };
  const env = { WAYBI_NZ_ROUTING_URL: 'https://waybi-test.a.run.app',
    WAYBI_NZ_ROUTING_TOKEN: 'test', WAYBI_NZ_ROUTING_DAILY_LIMIT: '1', USER_DB: db };
  const points: [number, number][] = [[174.76, -36.85], [175.28, -37.78]];
  try {
    await fetchNzRouting(env, points, 'DRIVE', {}, [], fetcher);
    await assert.rejects(fetchNzRouting(env, points, 'DRIVE', {}, [{ lat: -36.9, lon: 174.8, heading: 90 }], fetcher), /budget reached/);
    assert.equal(calls, 1);
    for (const limit of ['0', '3001', 'NaN', '1.5']) {
      await assert.rejects(fetchNzRouting({ ...env, WAYBI_NZ_ROUTING_DAILY_LIMIT: limit }, points, 'DRIVE', {}, [], fetcher), /budget unavailable/);
    }
    await assert.rejects(fetchNzRouting({ ...env, USER_DB: undefined }, points, 'DRIVE', {}, [], fetcher), /budget unavailable/);
    assert.equal(calls, 1);
  } finally { sqlite.close(); }
});
