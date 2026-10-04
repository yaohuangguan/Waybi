import { reconcileEntitlement } from './billing_entitlements.mjs';

const bundleId = 'co.waybi.ios';
export function appleConfig(env) {
  return {
    ready: Boolean(env.APPLE_IAP_ISSUER_ID && env.APPLE_IAP_KEY_ID && env.APPLE_IAP_PRIVATE_KEY),
    monthly: env.APPLE_IAP_PRODUCT_MONTHLY || `${bundleId}.plus.monthly`,
    annual: env.APPLE_IAP_PRODUCT_ANNUAL || `${bundleId}.plus.annual`
  };
}
const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const encode = (value) => b64url(new TextEncoder().encode(JSON.stringify(value)));
function decode(value) {
  const part = value?.split('.')[1];
  if (!part) throw new Error('Missing Apple transaction');
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - part.length % 4) % 4)), (c) => c.charCodeAt(0))));
}
export async function appleToken(env, now = Date.now()) {
  const pem = env.APPLE_IAP_PRIVATE_KEY.replace(/\\n/g, '\n').replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const token = `${encode({ alg: 'ES256', kid: env.APPLE_IAP_KEY_ID, typ: 'JWT' })}.${encode({
    iss: env.APPLE_IAP_ISSUER_ID, iat: Math.floor(now / 1000), exp: Math.floor(now / 1000) + 300,
    aud: 'appstoreconnect-v1', bid: bundleId
  })}`;
  return `${token}.${b64url(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(token)))}`;
}

async function appleGet(env, path, fetcher, now) {
  const host = env.APPLE_IAP_ENVIRONMENT === 'Sandbox' ? 'api.storekit-sandbox.apple.com' : 'api.storekit.apple.com';
  const res = await fetcher(`https://${host}/inApps/v1/${path}`, {
    headers: { authorization: `Bearer ${await appleToken(env, now)}` }, signal: AbortSignal.timeout(15000)
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const error = new Error(`Apple verification HTTP ${res.status}`);
    error.apiCode = body.errorCode;
    throw error;
  }
  return res.json();
}
function validateTransaction(transaction, env, userId) {
  const config = appleConfig(env);
  if (transaction.bundleId !== bundleId || ![config.monthly, config.annual].includes(transaction.productId) ||
    transaction.type !== 'Auto-Renewable Subscription' ||
    transaction.environment !== (env.APPLE_IAP_ENVIRONMENT === 'Sandbox' ? 'Sandbox' : 'Production') ||
    !transaction.appAccountToken || transaction.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    throw new Error('Apple purchase does not belong to this account or product');
  }
}

// JWS values are decoded ONLY from authenticated, fixed-host Apple API responses.
// No receipt, signed payload, expiry, product or account claim supplied by the app is trusted.
export async function syncAppleTransaction(db, env, transactionId, userId, { fetcher = fetch, now = Date.now() } = {}) {
  if (!/^\d{5,30}$/.test(transactionId)) throw new Error('Invalid Apple transaction id');
  let apiEnv = env;
  let info;
  try { info = await appleGet(apiEnv, `transactions/${transactionId}`, fetcher, now); }
  catch (error) {
    // Apple's documented production-first lookup also supports TestFlight/App Review.
    // Authentication or service errors never trigger an environment fallback.
    if (env.APPLE_IAP_ENVIRONMENT === 'Sandbox' || error.apiCode !== 4040010) throw error;
    apiEnv = { ...env, APPLE_IAP_ENVIRONMENT: 'Sandbox' };
    info = await appleGet(apiEnv, `transactions/${transactionId}`, fetcher, now);
  }
  const initial = decode(info.signedTransactionInfo);
  validateTransaction(initial, apiEnv, userId);
  if (String(initial.transactionId) !== transactionId || !/^\d{5,30}$/.test(initial.originalTransactionId)) throw new Error('Apple transaction mismatch');
  const original = String(initial.originalTransactionId);
  const owner = await db.prepare('SELECT user_id FROM apple_subscriptions WHERE original_transaction_id = ?').bind(original).first();
  if (owner && owner.user_id !== userId) throw new Error('Apple subscription already linked');
  const state = await appleGet(apiEnv, `subscriptions/${original}`, fetcher, now);
  const candidates = (state.data || []).flatMap((g) => g.lastTransactions || [])
    .filter((entry) => String(entry.originalTransactionId) === original);
  if (!candidates.length) throw new Error('Apple subscription status missing');
  const current = candidates.map((entry) => ({ ...entry, transaction: decode(entry.signedTransactionInfo),
    renewal: entry.signedRenewalInfo ? decode(entry.signedRenewalInfo) : {} }))
    .sort((a, b) => Number(b.transaction.purchaseDate) - Number(a.transaction.purchaseDate))[0];
  const transaction = current.transaction;
  validateTransaction(transaction, apiEnv, userId);
  if (String(transaction.originalTransactionId) !== original) throw new Error('Apple subscription mismatch');
  const status = transaction.revocationDate ? 5 : Number(current.status);
  const expiry = Number(status === 4 ? current.renewal.gracePeriodExpiresDate : transaction.expiresDate);
  if (!Number.isFinite(expiry) || expiry <= 0 || ![1, 2, 3, 4, 5].includes(status)) throw new Error('Invalid Apple subscription period');
  await db.prepare(`INSERT INTO apple_subscriptions
    (original_transaction_id, user_id, transaction_id, product_id, status, expires_at, cancel_at_period_end, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(original_transaction_id) DO UPDATE SET
    transaction_id = excluded.transaction_id, product_id = excluded.product_id, status = excluded.status,
    expires_at = excluded.expires_at, cancel_at_period_end = excluded.cancel_at_period_end, updated_at = excluded.updated_at
    WHERE apple_subscriptions.user_id = excluded.user_id AND apple_subscriptions.updated_at <= excluded.updated_at`)
    .bind(original, userId, String(transaction.transactionId), transaction.productId, status, expiry,
      current.renewal.autoRenewStatus === 0 ? 1 : 0, now).run();
  await reconcileEntitlement(db, userId, now);
  return { verified: true, active: [1, 4].includes(status) && expiry > now && !transaction.revocationDate };
}

export async function syncAppleForUser(db, env, userId) {
  if (!appleConfig(env).ready) return;
  const rows = await db.prepare('SELECT transaction_id FROM apple_subscriptions WHERE user_id = ? AND updated_at < ?')
    .bind(userId, Date.now() - 60000).all();
  for (const row of rows.results || []) await syncAppleTransaction(db, env, row.transaction_id, userId);
}
export async function syncAllAppleSubscriptions(env) {
  if (!env.USER_DB || !appleConfig(env).ready) return;
  const rows = await env.USER_DB.prepare('SELECT transaction_id, user_id FROM apple_subscriptions WHERE updated_at < ? ORDER BY updated_at LIMIT 50')
    .bind(Date.now() - 10 * 60000).all();
  const pending = rows.results || [];
  // Bound API concurrency and total runtime for a scheduled Worker invocation.
  for (let i = 0; i < pending.length; i += 5) {
    await Promise.all(pending.slice(i, i + 5).map(async (row) => {
      try { await syncAppleTransaction(env.USER_DB, env, row.transaction_id, row.user_id); }
      catch { console.warn('Apple subscription refresh will be retried'); }
    }));
  }
}
