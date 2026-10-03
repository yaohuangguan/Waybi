import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { appleToken, syncAppleTransaction } from '../src/apple_billing.mjs';

const userId = '729db2f1-5891-4b09-9b2c-72ba7a8f271b';
const now = Date.now();
const transactionId = '100000000000001';
const jws = (value) => `header.${Buffer.from(JSON.stringify(value)).toString('base64url')}.signature`;
function fixture(t) {
  const sqlite = new DatabaseSync(':memory:'); t.after(() => sqlite.close());
  sqlite.exec(`CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT); INSERT INTO users VALUES ('${userId}', 'driver@example.test');`);
  for (const migration of ['0007_subscriptions', '0009_stripe_billing', '0010_apple_billing']) {
    sqlite.exec(readFileSync(new URL(`../../../migrations/${migration}.sql`, import.meta.url), 'utf8'));
  }
  const db = { prepare(sql) { return { bind(...values) { const stmt = sqlite.prepare(sql); return {
    first: async () => stmt.get(...values) || null, all: async () => ({ results: stmt.all(...values) }), run: async () => stmt.run(...values)
  }; } }; } };
  const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const env = { APPLE_IAP_ISSUER_ID: 'test-issuer', APPLE_IAP_KEY_ID: 'test-key',
    APPLE_IAP_PRIVATE_KEY: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }), APPLE_IAP_ENVIRONMENT: 'Sandbox' };
  const transaction = { transactionId, originalTransactionId: transactionId, appAccountToken: userId,
    environment: 'Sandbox', bundleId: 'me.samyao.waybi', productId: 'me.samyao.waybi.plus.annual',
    type: 'Auto-Renewable Subscription', purchaseDate: now - 1000, expiresDate: now + 86400000 };
  const current = { status: 1, transaction: { ...transaction }, renewal: { autoRenewStatus: 1 } };
  const fetcher = async (url, options) => {
    assert.ok(url.startsWith('https://api.storekit-sandbox.apple.com/inApps/v1/'));
    assert.ok(options.headers.authorization.startsWith('Bearer '));
    return new Response(JSON.stringify(url.includes('/transactions/') ? { signedTransactionInfo: jws(transaction) }
      : { data: [{ lastTransactions: [{ status: current.status, originalTransactionId: transactionId,
        signedTransactionInfo: jws(current.transaction), signedRenewalInfo: jws(current.renewal) }] }] }));
  };
  return { sqlite, db, env, keys, transaction, current, fetcher,
    sync: () => syncAppleTransaction(db, env, transactionId, userId, { fetcher, now }),
    row: () => sqlite.prepare('SELECT * FROM user_subscriptions WHERE user_id = ?').get(userId) };
}
test('Apple API JWT uses an actual ES256 signature and app-bound claims', async (t) => {
  const f = fixture(t);
  const token = await appleToken(f.env, now);
  const [header, payload, signature] = token.split('.');
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.equal(claims.bid, 'me.samyao.waybi'); assert.equal(claims.aud, 'appstoreconnect-v1');
  assert.equal(verify('sha256', Buffer.from(`${header}.${payload}`), { key: f.keys.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
});
test('Apple validates current account, app, product and environment before granting access', async (t) => {
  const f = fixture(t);
  f.transaction.appAccountToken = 'different-user';
  await assert.rejects(f.sync()); assert.equal(f.row(), undefined);
  f.transaction.appAccountToken = userId; f.transaction.productId = 'other.product';
  await assert.rejects(f.sync());
  f.transaction.productId = 'me.samyao.waybi.plus.annual'; f.transaction.environment = 'Production';
  await assert.rejects(f.sync());
  f.transaction.environment = 'Sandbox';
  assert.equal((await f.sync()).active, true); assert.equal(f.row().source, 'apple');
});
test('production lookup falls back only for transaction-not-found and validates the sandbox response', async (t) => {
  const f = fixture(t);
  const env = { ...f.env, APPLE_IAP_ENVIRONMENT: 'Production' };
  const calls = [];
  const fetcher = async (url, options) => {
    calls.push(url);
    if (url.startsWith('https://api.storekit.apple.com/')) {
      return new Response(JSON.stringify({ errorCode: 4040010 }), { status: 404 });
    }
    return f.fetcher(url, options);
  };
  assert.equal((await syncAppleTransaction(f.db, env, transactionId, userId, { fetcher, now })).active, true);
  assert.equal(calls.length, 3);
  assert.ok(calls[1].includes('storekit-sandbox.apple.com'));
  let failedCalls = 0;
  await assert.rejects(syncAppleTransaction(f.db, env, transactionId, userId, {
    now, fetcher: async () => { failedCalls++; return new Response('{}', { status: 401 }); }
  }));
  assert.equal(failedCalls, 1);
});
test('restoring an old transaction uses the latest renewal, cancellation keeps paid access and refunds revoke it', async (t) => {
  const f = fixture(t); f.transaction.expiresDate = now - 1000;
  f.current.transaction.expiresDate = now + 500000; f.current.renewal.autoRenewStatus = 0;
  await f.sync(); assert.equal(f.row().plan, 'plus'); assert.equal(f.row().expires_at, now + 500000);
  assert.equal(f.sqlite.prepare('SELECT cancel_at_period_end FROM apple_subscriptions').get().cancel_at_period_end, 1);
  f.current.status = 5; f.current.transaction.revocationDate = now;
  await f.sync(); assert.equal(f.row().plan, 'free');
});
test('Apple revocation does not remove another active Stripe subscription or permanent owner Plus', async (t) => {
  const f = fixture(t);
  f.sqlite.prepare('INSERT INTO billing_subscriptions VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
    .run('sub_stripe', userId, 'cus_driver', 'price_year', 'active', now + 100000, 0, now);
  f.current.status = 2; f.current.transaction.expiresDate = now - 1000;
  await f.sync(); assert.equal(f.row().plan, 'plus'); assert.equal(f.row().source, 'stripe');
  f.sqlite.prepare("UPDATE user_subscriptions SET source='manual', expires_at=NULL").run();
  await f.sync(); assert.equal(f.row().source, 'manual'); assert.equal(f.row().expires_at, null);
});
