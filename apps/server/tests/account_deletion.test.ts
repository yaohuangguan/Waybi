import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { handleAccount } from '../src/auth.ts';
import { migratedD1 } from './d1_fixture.ts';

function makeDb() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('PRAGMA foreign_keys=ON');
  const migrationDir = new URL('../../../migrations/', import.meta.url);
  for (const file of readdirSync(migrationDir).filter(name => /^\d+.*\.sql$/.test(name)).sort()) {
    sqlite.exec(readFileSync(new URL(file, migrationDir), 'utf8'));
  }
  const db = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          const query = () => sqlite.prepare(sql);
          return {
            async first() { return query().get(...values as []) || null; },
            async all() { return { results: query().all(...values as []) }; },
            async run() { return query().run(...values as []); },
            sql,
            values,
          };
        },
      };
    },
    async batch(statements: Array<{sql: string; values: unknown[]}>) {
      sqlite.exec('BEGIN');
      try {
        const results = statements.map(({sql, values}) => {
          const statement = sqlite.prepare(sql);
          return {results: statement.columns().length ? statement.all(...values as []) : (statement.run(...values as []), [])};
        });
        sqlite.exec('COMMIT');
        return results;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
  } as unknown as D1Database;
  return { sqlite, db };
}

function call(token: string, email: string, confirmation = 'DELETE') {
  return new Request('https://waybi.co/api/auth/delete', {
    method: 'POST',
    headers: {
      'x-waybi-client': 'mobile',
      'content-type': 'application/json',
      cookie: `waybi_session=${token}`,
    },
    body: JSON.stringify({ email, confirmation }),
  });
}

test('account deletion requires current session and exact confirmation, cascades cloud data without touching other accounts', async () => {
  const {sqlite, db} = makeDb();
  try {
    for (const [id, email] of [['alice', 'alice@waybi.test'], ['bob', 'bob@waybi.test']]) {
      sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)')
        .run(id, email, '', '', 0);
      sqlite.prepare('INSERT INTO profiles(user_id,language,voice_enabled) VALUES(?,?,?)').run(id, 'en', 1);
      sqlite.prepare('INSERT INTO route_history(id,user_id,destination_name,destination_latitude,destination_longitude,mode,started_at) VALUES(?,?,?,?,?,?,?)')
        .run(id + '-route', id, 'Airport', -36.9, 174.8, 'drive', 1234);
      sqlite.prepare('INSERT INTO friends_saves(user_id,revision,state_json,updated_at) VALUES(?,?,?,?)').run(id,0,'{}',0);
      sqlite.prepare('INSERT INTO user_subscriptions(user_id,plan,source,updated_at) VALUES(?,?,?,?)').run(id,'plus','manual',0);
    }
    const token = 'a'.repeat(64);
    const tokenHash = createHash('sha256').update(token).digest('hex');
    sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)').run(tokenHash,'alice',Date.now() + 60000);
    sqlite.prepare('INSERT INTO login_attempts(email,failures,window_start) VALUES(?,?,?)').run('alice@waybi.test',2,Date.now());
    sqlite.prepare('INSERT INTO api_usage_daily(day,provider,sku,calls,units,updated_at) VALUES(?,?,?,?,?,?)')
      .run('2026-10-14','__waybi_quotas','user:alice',1,0,Date.now());
    let reports = {reports: [
      { id: 'alice-report', metadata: { reporterId: 'alice' }},
      { id: 'bob-report', metadata: { reporterId: 'bob' }},
    ], updatedAt: '2026-10-14T00:00:00Z'};
    const env = {USER_DB: db, CAMERA_DATA: {
      async get() { return reports; },
      async put(_key, json) { reports = JSON.parse(json); },
    }};
    assert.equal((await handleAccount(call(token, 'bob@waybi.test'), env)).status, 400);
    assert.equal((await handleAccount(call(token, 'alice@waybi.test', 'wrong'), env)).status, 400);
    assert.equal((await handleAccount(call('b'.repeat(64), 'alice@waybi.test'), env)).status, 401);
    assert.equal(sqlite.prepare('SELECT count(*) as c FROM users').get().c, 2);
    const deleted = await handleAccount(call(token, 'alice@waybi.test'), env);
    assert.equal(deleted.status, 200);
    assert.deepEqual(await deleted.json(), {ok: true, appleSubscriptionActive: false, stripeSubscriptionsCancelled: 0});
    assert.match(deleted.headers.get('set-cookie') || '', /Max-Age=0/);
    for (const table of ['users','profiles','sessions','route_history','friends_saves','user_subscriptions']) {
      const key = table === 'users' ? 'id' : 'user_id';
      assert.equal(sqlite.prepare(`SELECT count(*) AS c FROM ${table} WHERE ${key}=?`).get('alice').c, 0, table);
    }
    assert.equal(sqlite.prepare('SELECT count(*) as c FROM login_attempts WHERE email=?').get('alice@waybi.test').c, 0);
    assert.equal(sqlite.prepare("SELECT count(*) as c FROM api_usage_daily WHERE provider='__waybi_quotas' AND sku='user:alice'").get().c, 0);
    assert.deepEqual(reports.reports.map(report => report.id), ['bob-report']);
    assert.equal(sqlite.prepare('SELECT count(*) as c FROM users WHERE id=?').get('bob').c, 1);
    assert.equal(sqlite.prepare('SELECT count(*) as c FROM friends_saves WHERE user_id=?').get('bob').c, 1);
    assert.equal((await handleAccount(call(token, 'alice@waybi.test'), env)).status, 401);
  } finally {
    sqlite.close();
  }
});

function seedAccount(sqlite, id = 'carol', email = 'carol@waybi.test') {
  sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)').run(id, email, '', '', 0);
  const token = 'c'.repeat(64);
  sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)')
    .run(createHash('sha256').update(token).digest('hex'), id, Date.now() + 60000);
  return { id, email, token };
}

function stripeMock(subscriptions, { failCancel = false } = {}) {
  const cancelled = [];
  return { cancelled, stripe: { subscriptions: {
    async list({ customer }) { assert.equal(customer, 'cus_carol'); return { data: subscriptions }; },
    async cancel(id, _params, options) {
      assert.match(options.idempotencyKey, /^waybi-account-deletion-/);
      if (failCancel) throw Object.assign(new Error('stripe down'), { type: 'StripeConnectionError' });
      cancelled.push(id);
      return { id, status: 'canceled' };
    },
  } } };
}

test('account deletion cancels live Stripe subscriptions first and reports a renewing App Store subscription', async () => {
  const { sqlite, db } = migratedD1();
  try {
    const { id, email, token } = seedAccount(sqlite);
    sqlite.prepare('INSERT INTO billing_customers(user_id,customer_id,created_at) VALUES(?,?,?)').run(id, 'cus_carol', 0);
    sqlite.prepare(`INSERT INTO apple_subscriptions(original_transaction_id,user_id,transaction_id,product_id,status,expires_at,cancel_at_period_end,updated_at)
      VALUES('1000001',?,'1000002','co.waybi.ios.plus.monthly',1,?,0,0)`).run(id, Date.now() + 86_400_000);
    const { stripe, cancelled } = stripeMock([
      { id: 'sub_live', status: 'active' }, { id: 'sub_retrying', status: 'past_due' }, { id: 'sub_old', status: 'canceled' },
    ]);
    const response = await handleAccount(call(token, email), { USER_DB: db, STRIPE_SECRET_KEY: 'sk_test_x' }, undefined, { stripe });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, appleSubscriptionActive: true, stripeSubscriptionsCancelled: 2 });
    assert.deepEqual(cancelled, ['sub_live', 'sub_retrying']);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM users').get().c, 0);
  } finally { sqlite.close(); }
});

test('account deletion is refused with 503 when Stripe cancellation fails, and nothing is deleted', async () => {
  const { sqlite, db } = migratedD1();
  try {
    const { id, email, token } = seedAccount(sqlite);
    sqlite.prepare('INSERT INTO billing_customers(user_id,customer_id,created_at) VALUES(?,?,?)').run(id, 'cus_carol', 0);
    const { stripe } = stripeMock([{ id: 'sub_live', status: 'trialing' }], { failCancel: true });
    const response = await handleAccount(call(token, email), { USER_DB: db, STRIPE_SECRET_KEY: 'sk_test_x' }, undefined, { stripe });
    assert.equal(response.status, 503);
    assert.equal((await response.json()).code, 'SUBSCRIPTION_CANCEL_FAILED');
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM users').get().c, 1);
    assert.equal(sqlite.prepare('SELECT count(*) AS c FROM billing_customers').get().c, 1);
  } finally { sqlite.close(); }
});

test('profile and billing status expose whether an App Store subscription still renews', async () => {
  const { sqlite, db } = migratedD1();
  try {
    const { id, token } = seedAccount(sqlite);
    sqlite.prepare(`INSERT INTO apple_subscriptions(original_transaction_id,user_id,transaction_id,product_id,status,expires_at,cancel_at_period_end,updated_at)
      VALUES('2000001',?,'2000002','co.waybi.ios.plus.annual',1,?,1,?)`).run(id, Date.now() + 86_400_000, Date.now());
    const me = await handleAccount(new Request('https://waybi.co/api/auth/me', { headers: { cookie: `waybi_session=${token}` } }), { USER_DB: db });
    assert.equal((await me.json()).subscription.appleSubscriptionActive, false, 'auto-renew already turned off');
    sqlite.prepare('UPDATE apple_subscriptions SET cancel_at_period_end = 0').run();
    const again = await handleAccount(new Request('https://waybi.co/api/auth/me', { headers: { cookie: `waybi_session=${token}` } }), { USER_DB: db });
    assert.equal((await again.json()).subscription.appleSubscriptionActive, true);
  } finally { sqlite.close(); }
});
