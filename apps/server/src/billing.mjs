import Stripe from 'stripe';
import { reconcileEntitlement } from './billing_entitlements.mjs';
import { appleConfig, syncAppleTransaction } from './apple_billing.mjs';
import { subscriptionForUser, userFromRequest } from './auth.mjs';

export const BILLING_EVENTS = [
  'checkout.session.completed', 'checkout.session.async_payment_succeeded',
  'customer.subscription.created', 'customer.subscription.updated',
  'customer.subscription.deleted', 'invoice.paid', 'invoice.payment_failed'
];
const respond = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }
});
const objectId = (value) => typeof value === 'string' ? value : value?.id;

export function createStripe(env) {
  return new Stripe(env.STRIPE_SECRET_KEY, {
    httpClient: Stripe.createFetchHttpClient(), maxNetworkRetries: 2, timeout: 15000
  });
}

function ready(env) {
  return Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_WEBHOOK_SECRET &&
    env.STRIPE_PRICE_MONTHLY && env.STRIPE_PRICE_ANNUAL);
}

async function catalog(stripe, env) {
  return Promise.all(['monthly', 'annual'].map(async (id) => {
    const price = await stripe.prices.retrieve(id === 'monthly' ? env.STRIPE_PRICE_MONTHLY : env.STRIPE_PRICE_ANNUAL);
    const interval = id === 'monthly' ? 'month' : 'year';
    if (!price.active || price.currency !== 'nzd' || price.type !== 'recurring' ||
      price.recurring?.interval !== interval || price.recurring?.interval_count !== 1 ||
      !Number.isInteger(price.unit_amount) || price.unit_amount <= 0) {
      throw new Error('Invalid Plus price configuration');
    }
    return { id, priceId: price.id, amount: price.unit_amount, currency: price.currency, interval };
  }));
}

async function customerForUser(db, stripe, user, now) {
  let row = await db.prepare('SELECT customer_id FROM billing_customers WHERE user_id = ?').bind(user.id).first();
  if (!row) {
    const customer = await stripe.customers.create({
      email: user.email, metadata: { kiwi_user_id: user.id }
    }, { idempotencyKey: `kiwi-customer-${user.id}` });
    await db.prepare('INSERT INTO billing_customers (user_id, customer_id, created_at) VALUES (?, ?, ?) ON CONFLICT(user_id) DO NOTHING')
      .bind(user.id, customer.id, now).run();
    row = await db.prepare('SELECT customer_id FROM billing_customers WHERE user_id = ?').bind(user.id).first();
  }
  return row.customer_id;
}

// Read current Stripe state instead of trusting webhook delivery order or a success URL.
export async function syncSubscription(db, stripe, env, subscriptionId, now = Date.now()) {
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);
  const customerId = objectId(subscription.customer);
  const owner = await db.prepare('SELECT user_id FROM billing_customers WHERE customer_id = ?').bind(customerId).first();
  if (!owner) return false;
  const item = subscription.items?.data?.find((i) => [env.STRIPE_PRICE_MONTHLY, env.STRIPE_PRICE_ANNUAL].includes(objectId(i.price)));
  // Unrelated products in the same Stripe account never grant Kiwi Plus.
  if (!item) return false;
  const periodEnd = Number(item.current_period_end ?? subscription.current_period_end) * 1000;
  if (!Number.isFinite(periodEnd) || periodEnd <= 0) throw new Error('Missing subscription period');
  await db.prepare(`INSERT INTO billing_subscriptions
    (subscription_id, user_id, customer_id, price_id, status, period_end, cancel_at_period_end, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(subscription_id) DO UPDATE SET
    status = excluded.status, period_end = excluded.period_end, price_id = excluded.price_id,
    cancel_at_period_end = excluded.cancel_at_period_end, updated_at = excluded.updated_at
    WHERE billing_subscriptions.updated_at <= excluded.updated_at`)
    .bind(subscription.id, owner.user_id, customerId, objectId(item.price), subscription.status,
      periodEnd, subscription.cancel_at_period_end ? 1 : 0, now).run();
  await reconcileEntitlement(db, owner.user_id, now);
  return true;
}

async function billingState(db, userId, now) {
  const entitlement = await subscriptionForUser(db, userId, now);
  const row = await db.prepare(`SELECT subscription_id, status, period_end, cancel_at_period_end
    FROM billing_subscriptions WHERE user_id = ? ORDER BY period_end DESC LIMIT 1`).bind(userId).first();
  return { ...entitlement, billing: row ? {
    status: row.status, periodEnd: row.period_end, cancelAtPeriodEnd: Boolean(row.cancel_at_period_end)
  } : null };
}

async function webhook(request, env, stripe, now) {
  let event;
  try {
    event = await stripe.webhooks.constructEventAsync(await request.text(),
      request.headers.get('stripe-signature'), env.STRIPE_WEBHOOK_SECRET, undefined, Stripe.createSubtleCryptoProvider());
  } catch { return respond({ error: 'Invalid webhook signature' }, 400); }
  if (!BILLING_EVENTS.includes(event.type)) return respond({ received: true });
  if (Boolean(event.livemode) !== env.STRIPE_SECRET_KEY.startsWith('sk_live_')) return respond({ error: 'Stripe mode mismatch' }, 400);
  const db = env.USER_DB;
  if (await db.prepare('SELECT event_id FROM billing_events WHERE event_id = ?').bind(event.id).first()) {
    return respond({ received: true });
  }
  const object = event.data.object;
  const subscriptionId = event.type.startsWith('customer.subscription.') ? object.id
    : objectId(object.subscription ?? object.parent?.subscription_details?.subscription);
  if (subscriptionId) await syncSubscription(db, stripe, env, subscriptionId, now);
  // Record only after successful fulfillment so failed deliveries can be retried.
  await db.prepare('INSERT INTO billing_events (event_id, processed_at) VALUES (?, ?) ON CONFLICT(event_id) DO NOTHING')
    .bind(event.id, now).run();
  return respond({ received: true });
}

export async function handleBilling(request, env, dependencies = {}) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/billing/')) return null;
  const now = dependencies.now ?? Date.now();
  if (url.pathname === '/api/billing/apple/config' && request.method === 'GET') return respond(appleConfig(env));
  const stripe = dependencies.stripe ?? (env.STRIPE_SECRET_KEY ? createStripe(env) : null);
  if (url.pathname === '/api/billing/plans' && request.method === 'GET') {
    if (!ready(env)) return respond({ ready: false, plans: [
      { id: 'monthly', amount: 499, currency: 'nzd', interval: 'month' },
      { id: 'annual', amount: 3999, currency: 'nzd', interval: 'year' }
    ] });
    try {
      return respond({ ready: true, plans: (await catalog(stripe, env)).map(({ priceId, ...publicPrice }) => publicPrice) });
    } catch { return respond({ ready: false, error: 'Subscriptions are temporarily unavailable. Please try again later.', plans: [] }, 503); }
  }
  if (!env.USER_DB) return respond({ error: 'Account storage is not configured' }, 503);
  if (url.pathname === '/api/billing/webhook') {
    if (request.method !== 'POST') return respond({ error: 'Method not allowed' }, 405);
    if (!ready(env)) return respond({ error: 'Billing is not configured' }, 503);
    try { return await webhook(request, env, stripe, now); }
    catch (error) { console.error('Stripe fulfillment failed', error?.type || 'storage'); return respond({ error: 'Fulfillment will be retried' }, 500); }
  }
  if (request.method !== 'GET' && (!((request.headers.get('origin') === url.origin && request.headers.get('x-kiwi-client') === 'web') ||
      (url.pathname === '/api/billing/apple/verify' && !request.headers.get('origin') && request.headers.get('x-kiwi-client') === 'mobile')))) {
    return respond({ error: 'Invalid request origin' }, 403);
  }
  const user = await userFromRequest(env.USER_DB, request);
  if (!user) return respond({ error: 'Sign in required', code: 'SIGN_IN_REQUIRED' }, 401);
  const db = env.USER_DB;
  if (url.pathname === '/api/billing/status' && request.method === 'GET') return respond(await billingState(db, user.id, now));
  if (url.pathname === '/api/billing/apple/verify' && request.method === 'POST') {
    if (!appleConfig(env).ready) return respond({ error: 'App Store billing is not configured' }, 503);
    const body = await request.json().catch(() => null);
    try { return respond(await syncAppleTransaction(db, env, body?.transactionId || '', user.id, { now })); }
    catch { return respond({ error: 'App Store purchase could not be verified for this account' }, 400); }
  }
  if (!ready(env)) return respond({ error: 'Subscriptions are not available yet', code: 'BILLING_UNAVAILABLE' }, 503);
  try {
    if (url.pathname === '/api/billing/checkout' && request.method === 'POST') {
      const body = await request.json().catch(() => null);
      if (!['monthly', 'annual'].includes(body?.plan)) return respond({ error: 'Choose a valid plan' }, 400);
      const entitlement = await subscriptionForUser(db, user.id, now);
      if (entitlement.plan === 'plus') return respond({ error: 'Plus is already active', code: 'ALREADY_PLUS' }, 409);
      const plan = (await catalog(stripe, env)).find((p) => p.id === body.plan);
      const customer = await customerForUser(db, stripe, user, now);
      // Catch an active subscription even if its webhook has not reached us yet.
      const existing = await stripe.subscriptions.list({ customer, status: 'all', limit: 100 });
      const current = existing.data.find((s) => ['active', 'trialing', 'past_due', 'unpaid', 'incomplete'].includes(s.status) &&
        s.items?.data?.some((i) => [env.STRIPE_PRICE_MONTHLY, env.STRIPE_PRICE_ANNUAL].includes(objectId(i.price))));
      if (current) {
        await syncSubscription(db, stripe, env, current.id, now);
        return respond({ error: 'Manage your existing subscription instead', code: 'EXISTING_SUBSCRIPTION' }, 409);
      }
      const recent = await stripe.checkout.sessions.list({ customer, limit: 100 });
      const ownSessions = recent.data.filter((s) => s.client_reference_id === user.id);
      const open = { data: ownSessions.filter((s) => s.status === 'open') };
      // Reuse an open checkout for this plan; expire another plan before switching.
      const reusable = open.data.find((s) => s.metadata?.kiwi_plan === body.plan && s.client_reference_id === user.id);
      if (reusable) return respond({ url: reusable.url });
      for (const session of open.data.filter((s) => s.client_reference_id === user.id)) await stripe.checkout.sessions.expire(session.id);
      const previous = ownSessions.find((s) => s.metadata?.kiwi_plan === body.plan && s.status !== 'open');
      const session = await stripe.checkout.sessions.create({
        mode: 'subscription', customer, client_reference_id: user.id,
        line_items: [{ price: plan.priceId, quantity: 1 }],
        success_url: `${url.origin}/subscribe?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${url.origin}/subscribe?checkout=cancelled&plan=${body.plan}`,
        locale: body.language === 'zh' ? 'zh' : 'en',
        metadata: { kiwi_plan: body.plan, kiwi_user_id: user.id },
        subscription_data: { metadata: { kiwi_user_id: user.id } }
      }, { idempotencyKey: `kiwi-checkout-${user.id}-${body.plan}-${previous?.id || 'first'}` });
      return respond({ url: session.url });
    }
    if (url.pathname === '/api/billing/confirm' && request.method === 'POST') {
      const body = await request.json().catch(() => null);
      if (!/^cs_[a-zA-Z0-9_]+$/.test(body?.sessionId || '')) return respond({ error: 'Invalid checkout session' }, 400);
      const session = await stripe.checkout.sessions.retrieve(body.sessionId);
      const customer = await db.prepare('SELECT customer_id FROM billing_customers WHERE user_id = ?').bind(user.id).first();
      if (session.client_reference_id !== user.id || objectId(session.customer) !== customer?.customer_id) return respond({ error: 'Checkout does not belong to this account' }, 403);
      if (session.status === 'complete' && objectId(session.subscription)) await syncSubscription(db, stripe, env, objectId(session.subscription), now);
      return respond(await billingState(db, user.id, now));
    }
    if (url.pathname === '/api/billing/portal' && request.method === 'POST') {
      const customer = await db.prepare('SELECT customer_id FROM billing_customers WHERE user_id = ?').bind(user.id).first();
      if (!customer) return respond({ error: 'No Stripe subscription to manage' }, 404);
      const session = await stripe.billingPortal.sessions.create({ customer: customer.customer_id,
        return_url: `${url.origin}/subscribe`, ...(env.STRIPE_PORTAL_CONFIGURATION ? { configuration: env.STRIPE_PORTAL_CONFIGURATION } : {}) });
      return respond({ url: session.url });
    }
    return respond({ error: 'Not found' }, 404);
  } catch (error) {
    console.error('Stripe request failed', error?.type || 'billing');
    return respond({ error: 'Billing is temporarily unavailable. Please try again.', code: 'BILLING_ERROR' }, 502);
  }
}
