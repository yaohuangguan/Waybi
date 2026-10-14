const encoder = new TextEncoder();
const appleHost = 'https://appleid.apple.com';
const b64 = (bytes: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const encoded = (value: unknown) => b64(encoder.encode(JSON.stringify(value)));
function bytes(value: string) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Invalid Apple token encoding');
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0));
}
const part = (value: string) => JSON.parse(new TextDecoder().decode(bytes(value)));
const keys = new WeakMap<typeof fetch, { until: number; fetchedAt: number; values: JsonWebKey[] }>();
export function appleAuthConfig(env: any) {
  return { clientId: env.APPLE_AUTH_CLIENT_ID || 'co.waybi.ios',
    ready: Boolean(env.APPLE_AUTH_TEAM_ID && env.APPLE_AUTH_KEY_ID && env.APPLE_AUTH_PRIVATE_KEY &&
      /^[a-f0-9]{64}$/i.test(env.APPLE_AUTH_TOKEN_KEY || '')) };
}
export async function nonceHash(raw: string) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(raw)))]
    .map(n => n.toString(16).padStart(2, '0')).join('');
}
export async function verifyAppleIdentity(token: unknown, clientId: string, nonce: string,
  { fetcher = fetch, now = Date.now() } = {}) {
  if (typeof token !== 'string' || token.length > 10000 || !nonce) throw new Error('Invalid Apple identity');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Invalid Apple identity');
  const header = part(parts[0]), claims = part(parts[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' || header.kid.length > 255 || claims.iss !== appleHost ||
      claims.aud !== clientId || !Number.isFinite(claims.exp) || claims.exp * 1000 <= now ||
      !Number.isFinite(claims.iat) || claims.iat * 1000 > now + 60000 ||
      (claims.nbf != null && (!Number.isFinite(claims.nbf) || claims.nbf * 1000 > now + 60000)) ||
      typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255 || claims.nonce !== nonce) {
    throw new Error('Invalid Apple identity claims');
  }
  let cached = keys.get(fetcher);
  if (!cached || cached.until <= now || (!cached.values.some((key: any) => key.kid === header.kid) && now - cached.fetchedAt >= 60000)) {
    const r = await fetcher(appleHost + '/auth/keys', { signal: AbortSignal.timeout(5000) });
    if (!r.ok) throw new Error('Apple signing keys unavailable');
    const d: any = await r.json();
    if (!Array.isArray(d.keys)) throw new Error('Invalid Apple signing keys');
    cached = { until: now + 3600000, fetchedAt: now, values: d.keys }; keys.set(fetcher, cached);
  }
  const jwk: any = cached.values.find((key: any) =>
    key.kid === header.kid && key.kty === 'RSA' && key.use === 'sig' && key.alg === 'RS256');
  if (!jwk) throw new Error('Apple signing key unavailable');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, bytes(parts[2]), encoder.encode(parts[0] + '.' + parts[1]))) {
    throw new Error('Invalid Apple signature');
  }
  const verified = claims.email_verified === true || claims.email_verified === 'true';
  return { sub: claims.sub as string, email: verified && typeof claims.email === 'string' ? claims.email.trim().toLowerCase() : null };
}
export async function appleClientSecret(env: any, now = Date.now()) {
  if (!appleAuthConfig(env).ready) throw new Error('Apple sign-in unavailable');
  const pem = env.APPLE_AUTH_PRIVATE_KEY.replace(/\\n/g, '\n').replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const token = encoded({ alg: 'ES256', kid: env.APPLE_AUTH_KEY_ID, typ: 'JWT' }) + '.' + encoded({
    iss: env.APPLE_AUTH_TEAM_ID, sub: appleAuthConfig(env).clientId, aud: appleHost,
    iat: Math.floor(now / 1000), exp: Math.floor(now / 1000) + 300,
  });
  return token + '.' + b64(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(token)));
}
async function tokenRequest(env: any, fields: Record<string, string>, fetcher: typeof fetch) {
  const r = await fetcher(appleHost + '/auth/token', { method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: appleAuthConfig(env).clientId,
      client_secret: await appleClientSecret(env), ...fields }), signal: AbortSignal.timeout(5000) });
  const data: any = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error('Apple token validation failed'), { revoked: r.status === 400 && data.error === 'invalid_grant' });
  return data;
}
export async function exchangeAppleAuthorization(env: any, body: any, fetcher: typeof fetch = fetch) {
  if (typeof body?.rawNonce !== 'string' || !/^[a-zA-Z0-9_-]{32,128}$/.test(body.rawNonce) ||
      typeof body.authorizationCode !== 'string' || !body.authorizationCode || body.authorizationCode.length > 2048) {
    throw new Error('Invalid Apple authorization');
  }
  const nonce = await nonceHash(body.rawNonce);
  const identity = await verifyAppleIdentity(body.identityToken, appleAuthConfig(env).clientId, nonce, { fetcher });
  const tokens = await tokenRequest(env, { grant_type: 'authorization_code', code: body.authorizationCode }, fetcher);
  const exchanged = await verifyAppleIdentity(tokens.id_token, appleAuthConfig(env).clientId, nonce, { fetcher });
  if (exchanged.sub !== identity.sub) throw new Error('Apple identity mismatch');
  return { ...identity, refreshToken: typeof tokens.refresh_token === 'string' && tokens.refresh_token ? tokens.refresh_token : null };
}
async function tokenKey(env: any) {
  if (!/^[a-f0-9]{64}$/i.test(env.APPLE_AUTH_TOKEN_KEY || '')) throw new Error('Apple token storage unavailable');
  return crypto.subtle.importKey('raw', Uint8Array.from(String(env.APPLE_AUTH_TOKEN_KEY).match(/../g)!, (v: string) => parseInt(v, 16)),
    'AES-GCM', false, ['encrypt', 'decrypt']);
}
export async function sealAppleToken(env: any, token: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode('waybi.apple-refresh.v1') },
    await tokenKey(env), encoder.encode(token));
  return 'v1.' + b64(iv) + '.' + b64(ciphertext);
}
export async function openAppleToken(env: any, value: string) {
  const [version, iv, ciphertext, extra] = value.split('.');
  if (version !== 'v1' || !iv || !ciphertext || extra) throw new Error('Invalid stored Apple token');
  return new TextDecoder().decode(await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: bytes(iv), additionalData: encoder.encode('waybi.apple-refresh.v1') },
    await tokenKey(env), bytes(ciphertext)));
}
export async function revokeAppleAuthorization(env: any, sealed: string, fetcher: typeof fetch = fetch) {
  const r = await fetcher(appleHost + '/auth/revoke', { method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: appleAuthConfig(env).clientId, client_secret: await appleClientSecret(env),
      token: await openAppleToken(env, sealed), token_type_hint: 'refresh_token' }), signal: AbortSignal.timeout(5000) });
  if (!r.ok) throw new Error('Apple authorization could not be revoked; retry deletion');
}
/** Use existing 15-minute cron; check up to five oldest identities per run,
 * each at most daily. Never interpret an outage as revoked authorization. */
export async function refreshAppleAuthorizations(env: any, now = Date.now(), fetcher: typeof fetch = fetch) {
  if (!env.USER_DB || !appleAuthConfig(env).ready) return;
  const db = env.USER_DB;
  const rows = await db.prepare('SELECT apple_sub, user_id, refresh_token FROM apple_identities WHERE checked_at < ? AND revoked_at IS NULL ORDER BY checked_at LIMIT 5')
    .bind(now - 86400000).all();
  for (const row of rows.results || []) {
    try {
      const data = await tokenRequest(env, { grant_type: 'refresh_token', refresh_token: await openAppleToken(env, row.refresh_token) }, fetcher);
      if (!data.access_token) continue;
      await db.prepare('UPDATE apple_identities SET checked_at = ? WHERE apple_sub = ? AND refresh_token = ?')
        .bind(now, row.apple_sub, row.refresh_token).run();
    } catch (error) {
      if (error.revoked) await db.batch([
        db.prepare('DELETE FROM sessions WHERE user_id = ? AND EXISTS (SELECT 1 FROM apple_identities WHERE apple_sub = ? AND refresh_token = ?)')
          .bind(row.user_id, row.apple_sub, row.refresh_token),
        db.prepare('UPDATE apple_identities SET revoked_at = ?, checked_at = ? WHERE apple_sub = ? AND refresh_token = ?')
          .bind(now, now, row.apple_sub, row.refresh_token),
      ]);
    }
  }
}
