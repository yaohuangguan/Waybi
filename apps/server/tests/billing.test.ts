import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import Stripe from 'stripe';
import { createStripe, handleBilling } from '../src/billing.ts';

const token = 'a'.repeat(64);
const now = Date.now();
function fixture(t) {
  const sqlite = new DatabaseSync(':memory:');
  t.after(() => sqlite.close());
  sqlite.exec(`CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT);
    CREATE TABLE sessions (token_hash TEXT, user_id TEXT, expires_at INTEGER);
    INSERT INTO users VALUES ('user-1', 'driver@example.test');`);
  sqlite.prepare('INSERT INTO sessions VALUES (?, ?, ?)').run(createHash('sha256').update(token).digest('hex'), 'user-1', now + 86400000);
  sqlite.exec(readFileSync(new URL('../../../migrations/0007_subscriptions.sql', import.meta.url), 'utf8'));
  sqlite.exec(readFileSync(new URL('../../../migrations/0009_stripe_billing.sql', import.meta.url), 'utf8'));
  sqlite.exec(readFileSync(new URL('../../../migrations/0010_apple_billing.sql', import.meta.url), 'utf8'));
  const db = { prepare(sql) { return { bind(...values) { const stmt = sqlite.prepare(sql); return {
    first: async () => stmt.get(...values) || null,
    all: async () => ({ results: stmt.all(...values) }),
    run: async () => stmt.run(...values)
  }; } }; } };
  const env = { USER_DB: db, STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_WEBHOOK_SECRET: 'whsec_fixture',
    STRIPE_PRICE_MONTHLY: 'price_month', STRIPE_PRICE_ANNUAL: 'price_year' };
  const subscriptions = new Map();
  const checkouts = [];
  let subscriptionReads = 0;
  const stripe = {
    prices: { retrieve: async (id) => ({ id, active: true, type: 'recurring', currency: 'nzd',
      unit_amount: id === 'price_month' ? 499 : 3999,
      recurring: { interval: id === 'price_month' ? 'month' : 'year', interval_count: 1 } }) },
    customers: { create: async () => ({ id: 'cus_driver' }) },
    subscriptions: {
      list: async () => ({ data: [...subscriptions.values()] }),
      retrieve: async (id) => { subscriptionReads++; return subscriptions.get(id); }
    },
    checkout: { sessions: {
      list: async () => ({ data: checkouts }),
      create: async (params, options) => {
        const row = { id: `cs_test_${checkouts.length}`, status: 'open', url: 'https://checkout.stripe.com/test', ...params, options };
        checkouts.push(row); return row;
      },
      expire: async (id) => { checkouts.find((s) => s.id === id).status = 'expired'; },
      retrieve: async (id) => checkouts.find((s) => s.id === id)
    } },
    billingPortal: { sessions: { create: async (params) => ({ url: `https://billing.stripe.com/${params.customer}` }) } },
    webhooks: createStripe(env).webhooks
  };
  const request = (path, body, headers = {}) => new Request(`https://kiwi.test/api/billing/${path}`, {
    method: body ? 'POST' : 'GET', headers: { cookie: `waybi_session=${token}`, origin: 'https://kiwi.test',
      'x-waybi-client': 'web', 'content-type': 'application/json', ...headers }, ...(body ? { body: JSON.stringify(body) } : {})
  });
  const call = (path, body, headers) => handleBilling(request(path, body, headers), env, { stripe, now });
  const linkCustomer = () => sqlite.prepare('INSERT OR IGNORE INTO billing_customers VALUES (?, ?, ?)').run('user-1', 'cus_driver', now);
  const subscription = (status = 'active') => {
    const sub = { id: 'sub_driver', customer: 'cus_driver', status, cancel_at_period_end: false,
      items: { data: [{ price: { id: 'price_year' }, current_period_end: Math.floor(now / 1000) + 86400 }] } };
    subscriptions.set(sub.id, sub); return sub;
  };
  const event = async (type, object, id = 'evt_test') => {
    const payload = JSON.stringify({ id, type, livemode: false, data: { object } });
    const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret: env.STRIPE_WEBHOOK_SECRET });
    return handleBilling(new Request('https://kiwi.test/api/billing/webhook', { method: 'POST', body: payload,
      headers: { 'stripe-signature': signature } }), env, { stripe, now });
  };
  return { sqlite, env, stripe, call, event, subscription, linkCustomer, checkouts, reads: () => subscriptionReads };
}

test('public catalog uses Stripe prices and unavailable billing never creates a checkout', async (t) => {
  const f = fixture(t);
  assert.deepEqual((await (await f.call('plans')).json()).plans.map((p) => p.amount), [499, 3999]);
  delete f.env.STRIPE_WEBHOOK_SECRET;
  assert.equal((await (await f.call('plans')).json()).ready, false);
  assert.equal((await f.call('checkout', { plan: 'annual' })).status, 503);
  assert.equal(f.checkouts.length, 0);
});

test('mutations require same-origin authenticated web requests and server-owned plan selection', async (t) => {
  const f = fixture(t);
  assert.equal((await f.call('checkout', { plan: 'annual' }, { cookie: '' })).status, 401);
  assert.equal((await f.call('checkout', { plan: 'annual' }, { origin: 'https://evil.test' })).status, 403);
  assert.equal((await f.call('checkout', { plan: 'annual' }, { 'x-waybi-client': '' })).status, 403);
  assert.equal((await f.call('checkout', { plan: 'price_evil' })).status, 400);
  assert.equal(f.checkouts.length, 0);
});

test('checkout binds to the signed-in user and reuses an open session', async (t) => {
  const f = fixture(t);
  assert.equal((await f.call('checkout', { plan: 'annual', priceId: 'price_evil', customer: 'cus_evil' })).status, 200);
  const s = f.checkouts[0];
  assert.equal(s.customer, 'cus_driver');
  assert.equal(s.client_reference_id, 'user-1');
  assert.deepEqual(s.line_items, [{ price: 'price_year', quantity: 1 }]);
  assert.equal(s.subscription_data.metadata.kiwi_user_id, 'user-1');
  assert.ok(s.options.idempotencyKey);
  await f.call('checkout', { plan: 'annual' });
  assert.equal(f.checkouts.length, 1);
  await f.call('checkout', { plan: 'monthly' });
  assert.equal(s.status, 'expired');
  assert.equal(f.checkouts.length, 2);
});

test('an existing Stripe subscription prevents a second purchase even before webhook delivery', async (t) => {
  const f = fixture(t); f.linkCustomer(); f.subscription();
  assert.equal((await f.call('checkout', { plan: 'annual' })).status, 409);
  assert.equal(f.checkouts.length, 0);
  assert.equal((await (await f.call('status')).json()).plan, 'plus');
});

test('checkout confirmation rejects another account and grants only current active Stripe state', async (t) => {
  const f = fixture(t); f.linkCustomer(); const sub = f.subscription('incomplete');
  f.checkouts.push({ id: 'cs_test_return', status: 'complete', customer: 'cus_driver', client_reference_id: 'other-user', subscription: sub.id });
  assert.equal((await f.call('confirm', { sessionId: 'cs_test_return' })).status, 403);
  f.checkouts[0].client_reference_id = 'user-1';
  assert.equal((await (await f.call('confirm', { sessionId: 'cs_test_return' })).json()).plan, 'free');
  sub.status = 'active';
  assert.equal((await (await f.call('confirm', { sessionId: 'cs_test_return' })).json()).plan, 'plus');
});

test('webhooks verify the raw-body signature, deduplicate and read current state for out-of-order events', async (t) => {
  const f = fixture(t); f.linkCustomer(); const sub = f.subscription();
  const bad = new Request('https://kiwi.test/api/billing/webhook', { method: 'POST', body: '{}', headers: { 'stripe-signature': 'bad' } });
  assert.equal((await handleBilling(bad, f.env, { stripe: f.stripe, now })).status, 400);
  assert.equal((await f.event('customer.subscription.updated', sub)).status, 200);
  assert.equal((await (await f.call('status')).json()).plan, 'plus');
  await f.event('customer.subscription.updated', sub);
  assert.equal(f.reads(), 1);
  sub.status = 'canceled';
  await f.event('customer.subscription.updated', { id: sub.id, status: 'active' }, 'evt_old_snapshot');
  assert.equal((await (await f.call('status')).json()).plan, 'free');
});

test('cancel at period end keeps paid access; payment failure revokes Stripe access and manual Plus survives', async (t) => {
  const f = fixture(t); f.linkCustomer(); const sub = f.subscription(); sub.cancel_at_period_end = true;
  await f.event('customer.subscription.updated', sub);
  const active = await (await f.call('status')).json();
  assert.equal(active.plan, 'plus'); assert.equal(active.billing.cancelAtPeriodEnd, true);
  sub.status = 'past_due';
  await f.event('invoice.payment_failed', { parent: { subscription_details: { subscription: sub.id } } }, 'evt_invoice');
  assert.equal((await (await f.call('status')).json()).plan, 'free');
  f.sqlite.prepare("UPDATE user_subscriptions SET plan='plus', source='manual', expires_at=NULL").run();
  sub.status = 'canceled';
  await f.event('customer.subscription.deleted', sub, 'evt_manual');
  assert.equal((await (await f.call('status')).json()).source, 'manual');
});

test('portal uses the authenticated customer; other Stripe products do not unlock Plus', async (t) => {
  const f = fixture(t); f.linkCustomer(); const sub = f.subscription(); sub.items.data[0].price.id = 'price_other_product';
  await f.event('customer.subscription.updated', sub);
  assert.equal((await (await f.call('status')).json()).plan, 'free');
  const res = await f.call('portal', { customer: 'cus_evil' });
  assert.equal((await res.json()).url, 'https://billing.stripe.com/cus_driver');
});
