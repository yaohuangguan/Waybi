import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { evaluateAllRouteWatches, evaluateRouteWatch, handleRouteWatch, __test } from '../src/route_watch.ts';
import worker, { ROUTE_WATCH_CRON } from '../src/worker.ts';
import { runDailyCleanup } from '../src/retention.ts';
import { migratedD1 } from './d1_fixture.ts';

const route = [
  { latitude: -36.85, longitude: 174.75 },
  { latitude: -36.85, longitude: 174.80 },
  { latitude: -36.85, longitude: 174.85 },
];

function roadEvent(id: string, longitude: number, severity = 'warning', latitude = -36.8501) {
  return { id, type: severity === 'critical' ? 'roadClosure' : 'roadworks', severity, location: { latitude, longitude },
    geometry: [], validFrom: null, validUntil: null, roadName: 'SH1', metadata: { description: 'Works' } };
}

function snapshotKv(events: any[], retrievedAt = new Date()) {
  const state = { events, source: 'test', checkedAt: retrievedAt.toISOString(), retrievedAt: retrievedAt.toISOString(),
    syncStatus: 'live', syncError: null };
  const puts: string[] = [];
  return { puts, kv: { async get() { return state; }, async put(key) { puts.push(key); } } };
}

function seed(sqlite, users: number, watchesPerUser = 1, plan = 'plus') {
  const now = Date.now();
  for (let u = 0; u < users; u++) {
    const userId = `user-${String(u).padStart(4, '0')}`;
    sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)').run(userId, `${userId}@w.test`, '', '', 0);
    sqlite.prepare('INSERT INTO user_subscriptions(user_id,plan,source,expires_at,updated_at) VALUES(?,?,?,?,?)').run(userId, plan, 'manual', null, 0);
    for (let w = 0; w < watchesPerUser; w++) {
      sqlite.prepare(`INSERT INTO route_watches(id,user_id,label,destination_name,destination_latitude,destination_longitude,
        route_points_json,enabled,created_at,updated_at,geometry_expires_at) VALUES(?,?,?,?,?,?,?,1,?,?,?)`)
        .run(`${userId}-w${w}`, userId, `Route ${w}`, 'Work', -36.85, 174.85, JSON.stringify(route), now - 1000, now - 1000, now + 86_400_000);
    }
  }
}

test('Route Watch Cron pages through every enabled watch (no 500 cap) and writes only rows that change', async () => {
  const { sqlite, db, statements } = migratedD1();
  try {
    seed(sqlite, 23);
    const { kv, puts } = snapshotKv([roadEvent('near', 174.80), roadEvent('far-away', 172.0, 'warning', -41)]);
    const env = { USER_DB: db, CAMERA_DATA: kv };
    const first = await evaluateAllRouteWatches(env, new Date(), { pageSize: 5 });
    assert.deepEqual(first, { checked: 23, changed: 23, alerts: 23, failed: 0 });
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM route_watches WHERE last_status = 'warning'").get().c, 23);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM route_watch_alerts').get().c, 23);
    assert.deepEqual(puts, [], 'the Route Watch job never refreshes the road-event KV snapshot');
    statements.length = 0;
    const second = await evaluateAllRouteWatches(env, new Date(), { pageSize: 5 });
    assert.deepEqual(second, { checked: 23, changed: 0, alerts: 0, failed: 0 });
    assert.equal(statements.filter((sql) => /^\s*UPDATE route_watches/.test(sql)).length, 0, 'unchanged rows are not rewritten');
    assert.ok(sqlite.prepare("SELECT completed_at FROM scheduled_job_runs WHERE job = 'route_watch'").get().completed_at);
  } finally { sqlite.close(); }
});

test('one broken watch is logged and skipped without stopping the run', async () => {
  const { sqlite, db } = migratedD1();
  const originalError = console.error;
  const logged: string[] = [];
  console.error = (line) => { logged.push(String(line)); };
  try {
    seed(sqlite, 3);
    const { kv } = snapshotKv([roadEvent('near', 174.80)]);
    // A trigger makes the alert insert for one watch fail.
    sqlite.exec(`CREATE TRIGGER fail_alert BEFORE INSERT ON route_watch_alerts WHEN NEW.route_watch_id = 'user-0001-w0'
      BEGIN SELECT RAISE(ABORT, 'simulated D1 failure'); END;`);
    const result = await evaluateAllRouteWatches({ USER_DB: db, CAMERA_DATA: kv }, new Date());
    assert.equal(result.checked, 2);
    assert.equal(result.failed, 1);
    assert.equal(result.alerts, 2);
    const entry = JSON.parse(logged.find((line) => line.includes('route_watch_row_failed'))!);
    assert.equal(entry.watchId, 'user-0001-w0');
    // The failed alert restored the old signature, so the next run retries it.
    assert.equal(sqlite.prepare("SELECT last_alert_signature AS s FROM route_watches WHERE id = 'user-0001-w0'").get().s, '');
    sqlite.exec('DROP TRIGGER fail_alert');
    assert.equal((await evaluateAllRouteWatches({ USER_DB: db, CAMERA_DATA: kv }, new Date())).alerts, 1);
  } finally { console.error = originalError; sqlite.close(); }
});

test('overlapping Cron runs create exactly one alert per new signature', async () => {
  const { sqlite, db } = migratedD1();
  try {
    seed(sqlite, 4);
    const { kv } = snapshotKv([roadEvent('closure', 174.81, 'critical')]);
    const env = { USER_DB: db, CAMERA_DATA: kv };
    await Promise.all([evaluateAllRouteWatches(env), evaluateAllRouteWatches(env), evaluateAllRouteWatches(env)]);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM route_watch_alerts').get().c, 4);
  } finally { sqlite.close(); }
});

test('an unavailable road-event snapshot keeps last statuses instead of flipping every watch', async () => {
  const { sqlite, db } = migratedD1();
  try {
    seed(sqlite, 2);
    sqlite.prepare("UPDATE route_watches SET last_status = 'warning'").run();
    const old = snapshotKv([roadEvent('near', 174.80)], new Date(Date.now() - 2 * 60 * 60_000));
    const result = await evaluateAllRouteWatches({ USER_DB: db, CAMERA_DATA: old.kv }, new Date());
    assert.equal(result.skipped, 'road-events-unavailable');
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM route_watches WHERE last_status = 'warning'").get().c, 2);
  } finally { sqlite.close(); }
});

test('the bounding-box prefilter skips far events and still matches every event inside the corridor', () => {
  const far = Array.from({ length: 300 }, (_, i) => roadEvent(`far-${i}`, 172 + i * 0.001, 'warning', -41));
  const edge = roadEvent('edge', 174.80, 'warning', -36.85 + 170 / 111_320);
  const outside = roadEvent('outside', 174.80, 'warning', -36.85 + 200 / 111_320);
  const result = evaluateRouteWatch(route, [...far, edge, outside], new Date());
  assert.deepEqual(result.events.map((event) => event.id), ['edge']);
});

async function plusSession(sqlite) {
  const token = 'f'.repeat(64);
  sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)')
    .run(createHash('sha256').update(token).digest('hex'), 'user-0000', Date.now() + 60_000);
  return { cookie: `waybi_session=${token}` };
}

test('GET /api/route-watches returns stored status and re-evaluates only stale watches', async () => {
  const { sqlite, db, statements } = migratedD1();
  try {
    seed(sqlite, 1, 3);
    const headers = await plusSession(sqlite);
    const { kv } = snapshotKv([roadEvent('near', 174.80)]);
    const env = { USER_DB: db, CAMERA_DATA: kv };
    await evaluateAllRouteWatches(env, new Date());
    statements.length = 0;
    const fresh = await handleRouteWatch(new Request('https://w.test/api/route-watches', { headers }), env);
    const body = await fresh!.json();
    assert.equal(body.watches.length, 3);
    assert.ok(body.watches.every((watch) => watch.status === 'warning' && watch.lastCheckedAt));
    assert.equal(statements.filter((sql) => /UPDATE route_watches/.test(sql)).length, 0, 'fresh watches are not re-evaluated');

    // Older than 15 minutes for both the row and the last Cron run: re-evaluate that one.
    const old = Date.now() - __test.STALE_AFTER_MS - 60_000;
    sqlite.prepare('UPDATE scheduled_job_runs SET started_at = ?, completed_at = ?').run(old, old);
    sqlite.prepare("UPDATE route_watches SET last_checked_at = ?, last_status = 'healthy', last_events_json = '[]'").run(old);
    sqlite.prepare("UPDATE route_watches SET last_checked_at = ? WHERE id != 'user-0000-w1'").run(Date.now());
    statements.length = 0;
    const stale = await (await handleRouteWatch(new Request('https://w.test/api/route-watches', { headers }), env))!.json();
    const byId = Object.fromEntries(stale.watches.map((watch) => [watch.id, watch.status]));
    assert.equal(byId['user-0000-w1'], 'warning');
    assert.equal(byId['user-0000-w0'], 'healthy', 'a recently checked watch keeps its stored status');
    assert.equal(statements.filter((sql) => /UPDATE route_watches/.test(sql)).length, 1);

    // A missing snapshot reports unknown for stale watches without persisting it.
    sqlite.prepare('UPDATE route_watches SET last_checked_at = ?').run(old);
    const missing = { USER_DB: db, CAMERA_DATA: { async get() { throw new Error('KV down'); } } };
    const unknown = await (await handleRouteWatch(new Request('https://w.test/api/route-watches', { headers }), missing))!.json();
    assert.ok(unknown.watches.every((watch) => watch.status === 'unknown'));
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM route_watches WHERE last_status = 'unknown'").get().c, 0);
  } finally { sqlite.close(); }
});

test('the 8-watch limit is atomic under concurrent creates and returns 409', async () => {
  const { sqlite, db } = migratedD1();
  try {
    seed(sqlite, 1, 0);
    const headers = { ...(await plusSession(sqlite)), 'x-waybi-client': 'mobile', 'content-type': 'application/json' };
    const { kv } = snapshotKv([]);
    const env = { USER_DB: db, CAMERA_DATA: kv };
    const create = (label: string) => handleRouteWatch(new Request('https://w.test/api/route-watches', { method: 'POST', headers,
      body: JSON.stringify({ label, originName: 'Home', origin: route[0], destinationName: 'Work', destination: route[2],
        routeProvider: 'waybi', routePoints: route }) }), env);
    const results = await Promise.all(Array.from({ length: 12 }, (_, i) => create(`Route ${i}`)));
    const statuses = results.map((response) => response!.status);
    assert.equal(statuses.filter((status) => status === 201).length, 8);
    assert.equal(statuses.filter((status) => status === 409).length, 4);
    assert.equal((await results.find((r) => r!.status === 409)!.json()).code, 'ROUTE_WATCH_LIMIT');
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM route_watches').get().c, 8);
    assert.equal((await create('Route 0'))!.status, 201, 'updating an existing label is always allowed');
  } finally { sqlite.close(); }
});

test('a malformed route watch id is a 400, not an upstream error', async () => {
  const { sqlite, db } = migratedD1();
  try {
    seed(sqlite, 1, 0);
    const headers = { ...(await plusSession(sqlite)), 'x-waybi-client': 'mobile' };
    const response = await worker.fetch(new Request('https://w.test/api/route-watches/%E0', { method: 'DELETE', headers }),
      { USER_DB: db, CAMERA_DATA: snapshotKv([]).kv }, { waitUntil() {} });
    assert.equal(response.status, 400);
  } finally { sqlite.close(); }
});

test('Route Watch runs on its own Cron; the daily Cron also prunes expired data', async () => {
  const { sqlite, db } = migratedD1();
  try {
    seed(sqlite, 1);
    const now = Date.now();
    sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)').run('expired', 'user-0000', now - 1);
    sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)').run('live', 'user-0000', now + 60_000);
    sqlite.prepare('INSERT INTO login_attempts(email,failures,window_start) VALUES(?,?,?)').run('a@w.test', 5, now - 2 * 86_400_000);
    sqlite.prepare(`INSERT INTO route_watch_alerts(id,user_id,route_watch_id,label,status,created_at) VALUES
      ('old','user-0000','user-0000-w0','R','warning',?), ('new','user-0000','user-0000-w0','R','warning',?)`)
      .run(now - 181 * 86_400_000, now);
    sqlite.prepare('INSERT INTO billing_events(event_id,processed_at) VALUES(?,?),(?,?)').run('evt_old', now - 200 * 86_400_000, 'evt_new', now);
    sqlite.prepare("INSERT INTO api_usage_daily(day,provider,sku,calls,units,updated_at) VALUES('2020-01-01','__waybi_quotas','global',1,0,0),('2020-01-01','google','places_text_search',1,1,0)").run();
    sqlite.prepare('INSERT INTO navigation_feedback(id,vote,created_at) VALUES(?,?,?),(?,?,?)')
      .run('fb_old', 1, new Date(now - 400 * 86_400_000).toISOString(), 'fb_new', -1, new Date(now).toISOString());
    const deleted = await runDailyCleanup({ USER_DB: db }, now);
    assert.equal(deleted.sessions, 1);
    assert.equal(deleted.navigation_feedback, 1);
    assert.deepEqual(sqlite.prepare('SELECT id FROM navigation_feedback').all().map((row: any) => row.id), ['fb_new']);
    assert.deepEqual(sqlite.prepare('SELECT token_hash FROM sessions').all().map((row: any) => row.token_hash), ['live']);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM login_attempts').get().c, 0);
    assert.deepEqual(sqlite.prepare('SELECT id FROM route_watch_alerts').all().map((row: any) => row.id), ['new']);
    assert.deepEqual(sqlite.prepare('SELECT event_id FROM billing_events').all().map((row: any) => row.event_id), ['evt_new']);
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM api_usage_daily WHERE provider = 'google'").get().c, 1, 'cost history is kept');
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM api_usage_daily WHERE provider = '__waybi_quotas'").get().c, 0);

    const jobs: Promise<unknown>[] = [];
    const ctx = { waitUntil(promise) { jobs.push(promise); } };
    const env = { USER_DB: db, CAMERA_DATA: snapshotKv([roadEvent('near', 174.80)]).kv };
    await worker.scheduled({ cron: '*/15 * * * *' }, env, ctx);
    await Promise.all(jobs);
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM scheduled_job_runs").get().c, 0, 'the Apple Cron no longer runs Route Watch');
    jobs.length = 0;
    await worker.scheduled({ cron: ROUTE_WATCH_CRON }, env, ctx);
    assert.equal(jobs.length, 1);
    await Promise.all(jobs);
    assert.equal(sqlite.prepare("SELECT last_status FROM route_watches").get().last_status, 'warning');
  } finally { sqlite.close(); }
});
