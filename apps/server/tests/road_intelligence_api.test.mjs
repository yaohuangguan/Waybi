import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { handleRoadIntelligence, normalizeSnapshot, queryEvents, project, openapi } from '../src/road_intelligence_api.mjs';

const ROOT = 'https://kiwi.example/api/v1/road-intelligence';
const NOW = Date.parse('2026-10-02T01:00:00Z');
const cam = { id: 'camera-1', latitude: -36.85, longitude: 174.77, location: 'Queen Street', type: 'Spot speed', region: 'Auckland' };
const cameras = { cameras: [cam], checkedAt: new Date(NOW).toISOString(), syncStatus: 'live' };
const roads = { events: [{ id: 'works-1', type: 'roadworks', location: { latitude: -36.8503, longitude: 174.78 }, geometry: [], severity: 'warning', observation: 'official', source: { updatedAt: '2026-10-02T00:30:00Z' }, metadata: { description: 'Roadworks' } }], checkedAt: new Date(NOW).toISOString(), syncStatus: 'live' };

async function fixture(t) {
  const sqlite = new DatabaseSync(':memory:');
  t.after(() => sqlite.close());
  sqlite.exec('PRAGMA foreign_keys=ON; CREATE TABLE users(id TEXT PRIMARY KEY, email TEXT); CREATE TABLE sessions(user_id TEXT, token_hash TEXT, expires_at INTEGER);');
  sqlite.exec(readFileSync(new URL('../../../migrations/0011_road_intelligence_api.sql', import.meta.url), 'utf8'));
  const token = 'a'.repeat(64);
  const hash = Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token))).toString('hex');
  sqlite.prepare('INSERT INTO users VALUES (?, ?)').run('u1', 'tester@example.com');
  sqlite.prepare('INSERT INTO sessions VALUES (?, ?, ?)').run('u1', hash, Date.now() + 86400000);
  const db = { prepare(sql) {
    let args = [];
    const query = {
      bind(...values) { args = values; return query; },
      async first() { return sqlite.prepare(sql).get(...args) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...args) }; },
      async run() { return { meta: { changes: Number(sqlite.prepare(sql).run(...args).changes) } }; },
    }; return query;
  }, async batch(statements) {
    sqlite.exec('BEGIN');
    try { const results = []; for (const stmt of statements) results.push(await stmt.all()); sqlite.exec('COMMIT'); return results; }
    catch (e) { sqlite.exec('ROLLBACK'); throw e; }
  } };
  const pending = [];
  const env = { USER_DB: db };
  const call = (path, options = {}) => handleRoadIntelligence(new Request(ROOT + path, options), env,
    { waitUntil(promise) { pending.push(promise); } }, async () => cameras, { now: NOW, loadRoads: async () => roads });
  t.after(async () => { await Promise.all(pending); });
  const created = await call('/keys', { method: 'POST', headers: { cookie: `waybi_session=${token}` }, body: JSON.stringify({ name: 'Integration test' }) });
  assert.equal(created.status, 201);
  const key = await created.json();
  return { call, key, sqlite, headers: { authorization: `Bearer ${key.key}` }, cookie: `waybi_session=${token}` };
}

test('keys are hashed, returned once, owned by the session and revocable', async (t) => {
  const { call, key, sqlite, cookie, headers } = await fixture(t);
  const row = sqlite.prepare('SELECT * FROM road_api_keys').get();
  assert.notEqual(row.key_hash, key.key);
  assert.equal(row.key_hash.length, 64);
  const listed = await (await call('/keys', { headers: { cookie } })).text();
  assert.equal(listed.includes(key.key), false);
  assert.equal(listed.includes(row.key_hash), false);
  assert.equal((await call('/keys')).status, 401);
  assert.equal((await call('/keys/' + key.id, { method: 'DELETE', headers: { cookie } })).status, 200);
  assert.equal((await call('/events?near=174.77,-36.85', { headers })).status, 401);
});

test('area and corridor results have provenance, pagination, freshness and no private reports', async (t) => {
  const { call, headers } = await fixture(t);
  const response = await call('/events?bbox=174.7,-36.9,174.9,-36.8&limit=1', { headers });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.total, 2);
  assert.equal(data.events.length, 1);
  assert.equal(data.nextCursor, '1');
  assert.equal(data.sources.length, 2);
  assert.equal(data.sources[0].stale, false);
  assert.equal(data.dataUse.commercialRedistribution, false);
  assert.equal(response.headers.get('x-ratelimit-remaining'), '999');
  const second = await (await call('/events?bbox=174.7,-36.9,174.9,-36.8&limit=1&cursor=1', { headers })).json();
  assert.notEqual(second.events[0].id, data.events[0].id);
  const corridor = await (await call('/corridor', { method: 'POST', headers, body: JSON.stringify({ coordinates: [[174.76, -36.85], [174.80, -36.85]], bufferMeters: 100 }) })).json();
  assert.equal(corridor.events.length, 2);
  assert.equal(corridor.events[0].type, 'safetyCamera');
  assert.ok(corridor.events[1].distanceAlongRouteMeters > corridor.events[0].distanceAlongRouteMeters);
});

test('bad coordinates, unbounded queries, methods and oversized input fail closed', async (t) => {
  const { call, headers } = await fixture(t);
  for (const path of ['/events', '/events?near=181,91', '/events?bbox=170,-48,178,-34', '/events?near=174.77,-36.85&limit=0', '/events?bbox=174.7,-36.9,174.9,-36.8&near=broken']) {
    assert.equal((await call(path, { headers })).status, 400, path);
  }
  assert.equal((await call('/events', { method: 'POST', headers })).status, 405);
  assert.equal((await call('/corridor', { method: 'POST', headers, body: JSON.stringify({ coordinates: [[181, 91], [1, 1]] }) })).status, 400);
  assert.equal((await call('/corridor', { method: 'POST', headers, body: 'x'.repeat(25000) })).status, 400);
  assert.equal((await call('/events?near=174.77,-36.85')).status, 401);
});

test('minute and daily quotas use atomic conditional SQL updates', async (t) => {
  const { call, headers, sqlite, key } = await fixture(t);
  for (let i = 0; i < 60; i++) assert.equal((await call('/events?near=174.77,-36.85', { headers })).status, 200);
  const limited = await call('/events?near=174.77,-36.85', { headers });
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('retry-after'), '60');
  sqlite.prepare("DELETE FROM road_api_usage WHERE window_type='minute'").run();
  sqlite.prepare("UPDATE road_api_usage SET requests=999 WHERE key_id=? AND window_type='day'").run(key.id);
  assert.equal((await call('/events?near=174.77,-36.85', { headers })).status, 200);
  assert.equal((await call('/events?near=174.77,-36.85', { headers })).status, 429);
});

test('stale source timestamps never become fresh on a failed refresh', () => {
  const snapshot = normalizeSnapshot({ ...cameras, syncStatus: 'seed' }, { ...roads, syncStatus: 'stale', retrievedAt: '2026-10-01T00:00:00Z' }, NOW);
  assert.ok(snapshot.sources.every((s) => s.stale));
  assert.equal(snapshot.sources[1].retrievedAt, '2026-10-01T00:00:00Z');
  assert.equal(snapshot.events.some((e) => e.metadata.author), false);
});

test('overseas reports retain community provenance without reporter identity', () => {
  const report = {id:'world-report',type:'congestion',location:{latitude:40.71,longitude:-74},
    source:{provider:'Waybi road reports'},observation:'observed',metadata:{userReported:true,
      reporterId:'private-id',reporterName:'private-name',description:'Traffic'}};
  const snapshot = normalizeSnapshot(cameras,{...roads,events:[report]},NOW);
  const found = queryEvents(snapshot.events,{near:report.location,radius:500},NOW);
  assert.equal(found.length,1);
  assert.equal(found[0].sourceId,'waybi-reports');
  assert.equal(found[0].metadata.reporterId,undefined);
  assert.equal(found[0].metadata.reporterName,undefined);
  assert.equal(snapshot.sources.find(s=>s.id==='waybi-reports').coverage,'global');
});

test('corridor projection, geometry and validity avoid unrelated parallel-road events', () => {
  const route = [{ longitude: 174.76, latitude: -36.85 }, { longitude: 174.80, latitude: -36.85 }];
  assert.ok(project({ longitude: 174.77, latitude: -36.85 }, route).offset < 1);
  const snapshot = normalizeSnapshot(cameras, roads, NOW);
  const all = [...snapshot.events, { ...snapshot.events[0], id: 'far', location: { longitude: 174.77, latitude: -36.84 } }, { ...snapshot.events[0], id: 'expired', validUntil: '2026-10-01T00:00:00Z' }];
  assert.equal(queryEvents(all, { route, buffer: 100 }, NOW).length, 2);
  assert.equal(queryEvents(all, { near: route[0], radius: 5000, types: ['roadworks'] }, NOW).length, 1);
  assert.equal(openapi.openapi, '3.1.0');
  assert.ok(openapi.paths['/api/v1/road-intelligence/corridor'].post.security);
});
