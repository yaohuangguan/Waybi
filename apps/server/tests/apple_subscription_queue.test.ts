import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { appleRetryDelayMs, syncAllAppleSubscriptions } from '../src/apple_billing.ts';
import { migratedD1 } from './d1_fixture.ts';

const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const env = { APPLE_IAP_ISSUER_ID: 'issuer', APPLE_IAP_KEY_ID: 'key', APPLE_IAP_ENVIRONMENT: 'Sandbox',
  APPLE_IAP_PRIVATE_KEY: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }) };

function seed(sqlite, now: number) {
  sqlite.prepare("INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES('u','u@w.test','','',0)").run();
  const insert = sqlite.prepare(`INSERT INTO apple_subscriptions(original_transaction_id,user_id,transaction_id,product_id,
    status,expires_at,cancel_at_period_end,updated_at) VALUES(?, 'u', ?, 'co.waybi.ios.plus.monthly', ?, ?, 0, ?)`);
  // 60 permanently failing rows that are the oldest in the queue.
  for (let i = 0; i < 60; i++) insert.run(`1${String(i).padStart(9, '0')}`, `9${String(i).padStart(9, '0')}`, 1, now + 86_400_000, i);
  insert.run('2000000001', '2000000002', 1, now + 86_400_000, 10_000); // healthy renewal, newer row
  insert.run('3000000001', '3000000002', 5, now + 86_400_000, 0);      // revoked/refunded
  insert.run('4000000001', '4000000002', 2, now - 31 * 86_400_000, 0); // expired 31 days ago
}

test('failing App Store rows back off, so they cannot starve other renewals; revoked and long-expired rows are not polled', async () => {
  const { sqlite, db } = migratedD1();
  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    const now = Date.now();
    seed(sqlite, now);
    const requested = new Set<string>();
    const fetcher = async (url: string) => {
      const id = url.split('/').at(-1)!;
      requested.add(id);
      return Response.json({ errorCode: 4040010 }, { status: 404 });
    };
    const first = await syncAllAppleSubscriptions({ ...env, USER_DB: db }, now, fetcher as typeof fetch);
    assert.equal(first.checked, 50);
    assert.equal(first.failed, 50);
    const backedOff = sqlite.prepare('SELECT count(*) AS c FROM apple_subscriptions WHERE check_failures = 1 AND next_check_at > ?').get(now) as any;
    assert.equal(backedOff.c, 50, 'every failed attempt schedules its next check later');
    const second = await syncAllAppleSubscriptions({ ...env, USER_DB: db }, now + 1000, fetcher as typeof fetch);
    assert.equal(second.checked, 11, 'the remaining rows, including the healthy one, get their turn');
    assert.ok(requested.has('2000000002'));
    assert.ok(!requested.has('3000000002'), 'revoked subscriptions are not polled');
    assert.ok(!requested.has('4000000002'), 'subscriptions expired > 30 days are not polled');
    assert.equal(appleRetryDelayMs(1), 15 * 60_000);
    assert.equal(appleRetryDelayMs(20), 24 * 60 * 60_000);
  } finally { console.warn = originalWarn; sqlite.close(); }
});
