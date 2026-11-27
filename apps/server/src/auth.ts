import type { ProviderPayload } from "./types.ts";
import { clientKind, sessionCookieName } from './brand_compat.ts';
import { pbkdf2, scrypt } from 'node:crypto';
import { syncAppleForUser } from './apple_billing.ts';
import { verifyGoogleIdToken } from './google_token.ts';
import { validCoordinate } from './geo.ts';
import { handleFriendsBackup } from './friends_backup.ts';
import { purgeDeletedReporterReports } from './road_reports.ts';
import { appleAuthConfig, exchangeAppleAuthorization, sealAppleToken, revokeAppleAuthorization } from './apple_auth.ts';
import { emailOtpReady, handleEmailOtp } from './email_otp.ts';
import { clientFingerprint, clientIp } from './abuse_guard.ts';
import { cancelStripeSubscriptionsForDeletion } from './billing.ts';

const encoder = new TextEncoder();
const SESSION_SECONDS = 30 * 24 * 60 * 60;
const LEGACY_HASH_ITERATIONS = 210_000;
const PASSWORD_HASH_VERSION = 'scrypt-v1$';

function response(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers }
  });
}

function hex(bytes) {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function fromHex(value: string) {
  if (!/^(?:[0-9a-f]{2})+$/i.test(value)) return new Uint8Array(0);
  return Uint8Array.from(value.match(/.{2}/g), (part) => Number.parseInt(part, 16));
}

async function digest(value) {
  return hex(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
}

export async function hashPassword(password, saltHex) {
  const salt = fromHex(saltHex);
  if (salt.length !== 16) throw new Error('Invalid password salt');
  const derived = await new Promise((resolve, reject) => {
    scrypt(password, salt, 32, { N: 16_384, r: 8, p: 1, maxmem: 32 * 1024 * 1024 }, (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
  return PASSWORD_HASH_VERSION + hex(derived);
}

function constantTimeEquals(a, b) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

export async function verifyPassword(password, saltHex, storedHash) {
  if (typeof storedHash !== 'string') return false;
  if (storedHash.startsWith(PASSWORD_HASH_VERSION)) {
    return constantTimeEquals(await hashPassword(password, saltHex), storedHash);
  }
  // Accounts created before the Worker-compatible migration used PBKDF2-SHA256.
  if (!/^[0-9a-f]{64}$/i.test(storedHash)) return false;
  const salt = fromHex(saltHex);
  if (salt.length !== 16) return false;
  const legacyHash = await new Promise((resolve, reject) => {
    pbkdf2(password, salt, LEGACY_HASH_ITERATIONS, 32, 'sha256', (error, key) => {
      if (error) reject(error);
      else resolve(hex(key));
    });
  });
  return constantTimeEquals(legacyHash, storedHash);
}

function cookieHeader(token, request: Request) {
  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  return `${sessionCookieName(request)}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_SECONDS}${secure}`;
}

function clearCookieHeader(request: Request) {
  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  return `${sessionCookieName(request)}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0${secure}`;
}

function sessionToken(request: Request) {
  const cookies = request.headers.get('cookie') || '';
  const match = cookies.match(/(?:^|;\s*)(?:waybi|kiwi)_session=([0-9a-f]{64})(?:;|$)/);
  return match?.[1] || null;
}

export async function userFromRequest(db, request: Request) {
  const token = sessionToken(request);
  if (!token) return null;
  return db.prepare(`SELECT users.id, users.email FROM sessions
    JOIN users ON users.id = sessions.user_id
    WHERE sessions.token_hash = ? AND sessions.expires_at > ?`)
    .bind(await digest(token), Date.now()).first();
}

function subscriptionFromRow(row, now = Date.now()) {
  const activePlus = row?.plan === 'plus' &&
    (row.expiresAt == null || Number(row.expiresAt) > now);
  return activePlus
    ? { plan: 'plus', source: row.source || null, expiresAt: row.expiresAt ?? null }
    : { plan: 'free', source: null, expiresAt: null };
}

export async function subscriptionForUser(db, userId, now = Date.now()) {
  const row = await db.prepare(
    'SELECT plan, source, expires_at AS expiresAt FROM user_subscriptions WHERE user_id = ?'
  ).bind(userId).first();
  return subscriptionFromRow(row, now);
}

/** An App Store subscription that will renew unless the user cancels it in
 * the App Store. Waybi cannot cancel Apple subscriptions on the user's behalf. */
export const APPLE_RENEWING_SQL = `SELECT COUNT(*) AS renewing FROM apple_subscriptions
  WHERE user_id = ? AND status IN (1, 3, 4) AND expires_at > ? AND cancel_at_period_end = 0`;

export async function appleSubscriptionRenewing(db, userId, now = Date.now()) {
  const row = await db.prepare(APPLE_RENEWING_SQL).bind(userId, now).first();
  return Number(row?.renewing || 0) > 0;
}

export async function userHasPlus(db, userId, now = Date.now()) {
  return (await subscriptionForUser(db, userId, now)).plan === 'plus';
}

export async function roadReportAuthor(db, request: Request) {
  const user = await userFromRequest(db, request);
  if (!user) return null;
  const profile = await db.prepare(
    'SELECT display_name FROM profiles WHERE user_id = ?'
  ).bind(user.id).first();
  const displayName = String(profile?.display_name || '').trim();
  return {
    id: user.id,
    displayName: displayName || 'Waybi driver'
  };
}

const QUICK_LOCATION_IDS = {
  Home: 'waybi:quick:home',
  Work: 'waybi:quick:work',
};

export function quickLocationsFromBookmarks(rows = []) {
  return rows.flatMap((place) => {
    const label = place.placeId === QUICK_LOCATION_IDS.Home
      ? 'Home'
      : place.placeId === QUICK_LOCATION_IDS.Work
        ? 'Work'
        : null;
    if (!label) return [];
    return [{
      label,
      name: place.name,
      address: place.address || '',
      latitude: place.latitude,
      longitude: place.longitude,
      provider: place.note === 'independent' ? 'independent' : 'google',
      updatedAt: place.updatedAt,
    }];
  });
}

/** Refresh App Store state off the request path where the runtime allows it.
 * The 15-minute Cron also refreshes every subscription. */
function refreshAppleInBackground(db, env, userId, ctx?: Pick<ExecutionContext, 'waitUntil'>) {
  const job = syncAppleForUser(db, env || {}, userId).catch(() => { /* retain last verified expiry */ });
  if (ctx?.waitUntil) ctx.waitUntil(job);
  return ctx?.waitUntil ? Promise.resolve() : job;
}

async function userProfile(db, user, env, now = Date.now()) {
  // One D1 round trip instead of a dozen sequential queries.
  const [profileRows, googleRows, appleRows, passwordRows, emailRows, recent, saved, quick, routes, reviews,
    companionRows, subscriptionRows, appleRenewingRows] = await db.batch([
    db.prepare('SELECT language, voice_enabled, display_name FROM profiles WHERE user_id = ?').bind(user.id),
    db.prepare('SELECT google_sub FROM google_identities WHERE user_id = ?').bind(user.id),
    db.prepare('SELECT apple_sub FROM apple_identities WHERE user_id = ?').bind(user.id),
    db.prepare('SELECT password_hash FROM users WHERE id = ?').bind(user.id),
    db.prepare('SELECT verified_at FROM email_identities WHERE user_id = ?').bind(user.id),
    db.prepare(`SELECT label, latitude, longitude FROM recent_destinations
      WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20`).bind(user.id),
    db.prepare(`SELECT place_id AS placeId, name, address, latitude, longitude,
        is_favorite AS isFavorite, note, updated_at AS updatedAt
      FROM place_bookmarks
      WHERE user_id = ? AND (is_favorite = 1 OR note <> '')
        AND place_id NOT IN ('waybi:quick:home', 'waybi:quick:work')
      ORDER BY updated_at DESC LIMIT 100`).bind(user.id),
    db.prepare(`SELECT place_id AS placeId, name, address, latitude, longitude,
        note, updated_at AS updatedAt
      FROM place_bookmarks
      WHERE user_id = ? AND place_id IN ('waybi:quick:home', 'waybi:quick:work')
      ORDER BY updated_at DESC`).bind(user.id),
    db.prepare(`SELECT id, destination_name AS destinationName,
      destination_latitude AS latitude, destination_longitude AS longitude, mode,
      distance_meters AS distanceMeters, duration_seconds AS durationSeconds, started_at AS startedAt
      FROM route_history WHERE user_id = ? ORDER BY started_at DESC LIMIT 100`).bind(user.id),
    db.prepare(`SELECT place_id AS placeId, place_name AS placeName,
      rating, comment, updated_at AS updatedAt
      FROM place_reviews WHERE user_id = ? ORDER BY updated_at DESC LIMIT 100`).bind(user.id),
    db.prepare(`SELECT distance_meters AS distanceMeters,
      trip_count AS tripCount, duration_seconds AS durationSeconds
      FROM companion_totals WHERE user_id = ?`).bind(user.id),
    db.prepare('SELECT plan, source, expires_at AS expiresAt FROM user_subscriptions WHERE user_id = ?').bind(user.id),
    db.prepare(APPLE_RENEWING_SQL).bind(user.id, now),
  ]);
  const first = (result) => result?.results?.[0] || null;
  const rows = (result) => result?.results || [];
  const profile = first(profileRows);
  const companion = first(companionRows);
  const passwordUser = first(passwordRows);
  return {
    user: { id: user.id, email: user.email, displayName: profile?.display_name || '', providers: [
      ...(first(emailRows) ? ['email'] : []), ...(passwordUser?.password_hash ? ['password'] : []),
      ...(first(googleRows) ? ['google'] : []), ...(first(appleRows) ? ['apple'] : [])
    ] },
    language: profile?.language === 'zh' ? 'zh' : 'en',
    voiceEnabled: profile?.voice_enabled !== 0,
    subscription: {
      ...subscriptionFromRow(first(subscriptionRows), now),
      // Additive: tells the app to send the user to App Store subscription
      // management before deleting the account.
      appleSubscriptionActive: Number(first(appleRenewingRows)?.renewing || 0) > 0,
    },
    recentDestinations: rows(recent),
    savedPlaces: rows(saved).map((place) => ({
      ...place,
      isFavorite: place.isFavorite === 1
    })),
    quickLocations: quickLocationsFromBookmarks(rows(quick)),
    routeHistory: rows(routes),
    companionTotals: {
      distanceMeters: companion?.distanceMeters ?? 0,
      tripCount: companion?.tripCount ?? 0,
      durationSeconds: companion?.durationSeconds ?? 0,
    },
    reviews: rows(reviews)
  };
}

async function issueSession(db, user, request: Request, env) {
  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  await db.prepare('INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)')
    .bind(await digest(token), user.id, Date.now() + SESSION_SECONDS * 1000).run();
  return response(await userProfile(db, user, env), 200, { 'set-cookie': cookieHeader(token, request) });
}

async function readBody(request: Request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) return null;
  if (Number(request.headers.get('content-length') || 0) > 4096) return null;
  return request.json<ProviderPayload>().catch(() => null);
}

function validEmail(email) {
  return typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

const LOGIN_WINDOW_MS = 15 * 60_000;
// The tight lock is per email+client, so a stranger cannot lock a user out of
// their own device by guessing. The per-email cap is looser and only bounds a
// distributed guessing attack; the per-client cap bounds one client spraying
// many accounts. Email codes remain available while a password is locked.
export const LOGIN_LIMITS = { pair: 5, email: 20, client: 50 };

async function reserveLoginSubject(db, subject: string, limit: number, now: number) {
  return db.prepare(`INSERT INTO auth_login_limits (subject, failures, window_start) VALUES (?, 1, ?)
    ON CONFLICT(subject) DO UPDATE SET
      failures = CASE WHEN ? - window_start >= ${LOGIN_WINDOW_MS} THEN 1 ELSE failures + 1 END,
      window_start = CASE WHEN ? - window_start >= ${LOGIN_WINDOW_MS} THEN ? ELSE window_start END
    WHERE ? - window_start >= ${LOGIN_WINDOW_MS} OR failures < ?
    RETURNING failures`).bind(subject, now, now, now, now, now, limit).first();
}

async function releaseLoginSubjects(db, subjects: string[]) {
  if (!subjects.length) return;
  await db.batch(subjects.map((subject) => db.prepare(
    'UPDATE auth_login_limits SET failures = MAX(0, failures - 1) WHERE subject = ?').bind(subject)));
}

/** Atomically reserve an attempt before any password hashing, so concurrent
 * guesses cannot all pass a read-then-increment check. */
async function reserveLoginAttempt(db, env, request: Request, email: string, now = Date.now()) {
  const client = await clientFingerprint(env, clientIp(request));
  const subjects: Array<[string, number]> = [
    [`client:${client}`, LOGIN_LIMITS.client],
    [`email:${email}`, LOGIN_LIMITS.email],
    [`pair:${email}|${client}`, LOGIN_LIMITS.pair],
  ];
  const reserved: string[] = [];
  for (const [subject, limit] of subjects) {
    if (await reserveLoginSubject(db, subject, limit, now)) {
      reserved.push(subject);
      continue;
    }
    await releaseLoginSubjects(db, reserved);
    return null;
  }
  return { pair: reserved[2], counters: reserved.slice(0, 2) };
}

export async function handleAccount(request: Request, env, ctx?: Pick<ExecutionContext, 'waitUntil'>,
  dependencies: { stripe?: any } = {}) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith('/api/auth/') && !path.startsWith('/api/profile')) return null;
  if (!env.USER_DB) return response({ error: 'Account storage is not configured' }, 503);
  if (['POST', 'PATCH', 'DELETE'].includes(request.method)) {
    const origin = request.headers.get('origin');
    const client = clientKind(request);
    if ((origin && origin !== new URL(request.url).origin) || !['web', 'mobile'].includes(client) || (client === 'mobile' && origin)) {
      return response({ error: 'Invalid request origin' }, 403);
    }
  }
  const db = env.USER_DB;

  if (path === '/api/auth/config' && request.method === 'GET') return response({
    emailOtp: emailOtpReady(env), google: Boolean(env.GOOGLE_OAUTH_CLIENT_IDS), apple: appleAuthConfig(env).ready,
  });
  const emailResponse = await handleEmailOtp(request, env, user => issueSession(db, user, request, env));
  if (emailResponse) return emailResponse;

  if (path === '/api/auth/apple/config' && request.method === 'GET') return response(appleAuthConfig(env));
  if ((path === '/api/auth/apple' || path === '/api/auth/apple/link') && request.method === 'POST') {
    const linking = path.endsWith('/link');
    const current = linking ? await userFromRequest(db, request) : null;
    if (linking && !current) return response({ error: 'Not signed in' }, 401);
    const body = await readBody(request);
    let identity;
    try { identity = await exchangeAppleAuthorization(env, body); }
    catch { return response({ error: 'Apple sign-in could not be verified. Please try again.' }, 401); }
    const linked = await db.prepare(`SELECT users.id, users.email, apple_identities.refresh_token FROM apple_identities
      JOIN users ON users.id = apple_identities.user_id WHERE apple_sub = ?`).bind(identity.sub).first();
    // Apple only returns an email it has verified; record it so a later first
    // email-code proof can tell this link apart from one added before proof.
    const appleVerifiedEmail = validEmail(identity.email) ? identity.email : null;
    if (linking && linked && linked.id !== current.id) return response({ error: 'Apple account is linked elsewhere' }, 409);
    let user = linking ? current : linked;
    if (linking) {
      const already = await db.prepare('SELECT apple_sub FROM apple_identities WHERE user_id = ?').bind(current.id).first();
      if (already && already.apple_sub !== identity.sub) return response({ error: 'A different Apple account is already linked' }, 409);
    }
    if (!user) {
      if (!validEmail(identity.email)) return response({ error: 'A verified Apple email is required to create an account' }, 401);
      const existing = await db.prepare('SELECT id FROM users WHERE email = ?').bind(identity.email).first();
      if (existing) return response({ error: 'This email already has an account. Sign in with your existing method, then link Apple in My Account.' }, 409);
      user = { id: crypto.randomUUID(), email: identity.email };
    }
    // Without the optional Sign in with Apple key there is no refresh token; '' marks
    // an identity verified from Apple's signed identity token alone.
    const storedToken = identity.refreshToken ? await sealAppleToken(env, identity.refreshToken)
      : linked?.refresh_token ?? (appleAuthConfig(env).tokenExchange ? null : '');
    if (storedToken == null) return response({ error: 'Apple authorization is incomplete. Please try again.' }, 401);
    const statements = [];
    if (!linking && !linked) statements.push(
      db.prepare('INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
        .bind(user.id, user.email, '', '', Date.now()),
      db.prepare('INSERT INTO profiles (user_id, language, voice_enabled, display_name) VALUES (?, ?, ?, ?)')
        .bind(user.id, body.language === 'zh' ? 'zh' : 'en', 1, typeof body.fullName === 'string' ? body.fullName.trim().slice(0, 100) : '')
    );
    statements.push(linked
      ? db.prepare(`UPDATE apple_identities SET refresh_token = ?, checked_at = ?, revoked_at = NULL,
          verified_email = COALESCE(?, verified_email)
          WHERE apple_sub = ? AND user_id = ?`)
        .bind(storedToken, Date.now(), appleVerifiedEmail, identity.sub, user.id)
      : db.prepare('INSERT INTO apple_identities (apple_sub, user_id, refresh_token, created_at, checked_at, verified_email) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(identity.sub, user.id, storedToken, Date.now(), Date.now(), appleVerifiedEmail));
    try { await db.batch(statements); }
    catch (error) {
      if (/UNIQUE/i.test(String(error))) return response({ error: 'Apple account is already linked. Please try again.' }, 409);
      throw error;
    }
    return linking ? response(await userProfile(db, user, env)) : issueSession(db, user, request, env);
  }

  if (path === '/api/auth/register' && request.method === 'POST') {
    const body = await readBody(request);
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = body?.password;
    if (!validEmail(email) || typeof password !== 'string' || password.length < 12 || password.length > 128) {
      return response({ error: 'Use a valid email and a password of 12–128 characters' }, 400);
    }
    const existing = await db.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
    if (existing) return response({ error: 'This email is already registered' }, 409);
    const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
    const user = { id: crypto.randomUUID(), email };
    try {
      await db.batch([
        db.prepare('INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
          .bind(user.id, email, salt, await hashPassword(password, salt), Date.now()),
        db.prepare('INSERT INTO profiles (user_id, language, voice_enabled) VALUES (?, ?, ?)')
          .bind(user.id, body.language === 'zh' ? 'zh' : 'en', body.voiceEnabled === false ? 0 : 1)
      ]);
    } catch (error) {
      if (/UNIQUE/i.test(String(error))) return response({ error: 'This email is already registered' }, 409);
      throw error;
    }
    return issueSession(db, user, request, env);
  }

  if (path === '/api/auth/login' && request.method === 'POST') {
    const body = await readBody(request);
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
    if (!validEmail(email) || typeof body?.password !== 'string' || body.password.length > 1024) {
      return response({ error: 'Invalid credentials' }, 401);
    }
    const attempt = await reserveLoginAttempt(db, env, request, email);
    if (!attempt) {
      return response({ error: 'Too many attempts. Try again in 15 minutes, or sign in with an email code.', code: 'LOGIN_LOCKED' },
        429, { 'retry-after': String(LOGIN_WINDOW_MS / 1000) });
    }
    const user = await db.prepare('SELECT id, email, password_salt, password_hash FROM users WHERE email = ?').bind(email).first();
    if (!user || !await verifyPassword(body.password, user.password_salt, user.password_hash)) {
      return response({ error: 'Invalid credentials' }, 401);
    }
    // A successful sign-in is not a failure: clear this client's lock and
    // return the reserved units to the shared counters.
    await db.batch([
      db.prepare('DELETE FROM auth_login_limits WHERE subject = ?').bind(attempt.pair),
      ...attempt.counters.map((subject) => db.prepare(
        'UPDATE auth_login_limits SET failures = MAX(0, failures - 1) WHERE subject = ?').bind(subject)),
      db.prepare('DELETE FROM login_attempts WHERE email = ?').bind(email),
    ]);
    return issueSession(db, user, request, env);
  }

  if (path === '/api/auth/google' && request.method === 'POST') {
    if (!env.GOOGLE_OAUTH_CLIENT_IDS) return response({ error: 'Google sign-in is not configured' }, 503);
    const body = await readBody(request);
    let identity;
    try {
      identity = await verifyGoogleIdToken(body?.idToken, env.GOOGLE_OAUTH_CLIENT_IDS);
    } catch {
      return response({ error: 'Google sign-in could not be verified' }, 401);
    }
    if (!validEmail(identity.email)) return response({ error: 'Google email is unavailable' }, 401);
    const linked = await db.prepare(`SELECT users.id, users.email FROM google_identities
      JOIN users ON users.id = google_identities.user_id WHERE google_sub = ?`).bind(identity.sub).first();
    if (linked) {
      // verifyGoogleIdToken only accepts email_verified tokens; keep the
      // verified address current so the link survives a first email-code proof.
      await db.prepare('UPDATE google_identities SET verified_email = ? WHERE google_sub = ?')
        .bind(identity.email, identity.sub).run();
      return issueSession(db, linked, request, env);
    }
    // Never take over a password account based solely on an email claim.
    const existing = await db.prepare('SELECT id FROM users WHERE email = ?').bind(identity.email).first();
    if (existing) return response({ error: 'This email already has an account. Sign in with email first, then link Google in My Account.' }, 409);
    const user = { id: crypto.randomUUID(), email: identity.email };
    try {
      await db.batch([
        db.prepare('INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
          .bind(user.id, user.email, '', '', Date.now()),
        db.prepare('INSERT INTO profiles (user_id, language, voice_enabled, display_name) VALUES (?, ?, ?, ?)')
          .bind(user.id, 'en', 1, identity.name),
        db.prepare('INSERT INTO google_identities (google_sub, user_id, created_at, verified_email) VALUES (?, ?, ?, ?)')
          .bind(identity.sub, user.id, Date.now(), identity.email)
      ]);
    } catch (error) {
      if (/UNIQUE/i.test(String(error))) return response({ error: 'Google account is already linked. Try signing in again.' }, 409);
      throw error;
    }
    return issueSession(db, user, request, env);
  }

  if (path === '/api/auth/logout' && request.method === 'POST') {
    const token = sessionToken(request);
    if (token) await db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await digest(token)).run();
    return response({ ok: true }, 200, { 'set-cookie': clearCookieHeader(request) });
  }

  const user = await userFromRequest(db, request);
  if (!user) return response({ error: 'Not signed in' }, 401);
  if (path === '/api/auth/delete' && request.method === 'POST') {
    const body = await readBody(request);
    // Require a live session plus an explicit, case-sensitive confirmation.
    // Browser CSRF and mobile caller validation are enforced above.
    if (body?.confirmation !== 'DELETE' || body?.email !== user.email) {
      return response({ error: 'Confirm account email and DELETE to proceed' }, 400);
    }
    // D1 enforces foreign keys; deleting the parent atomically cascades to
    // saved places, routes, sessions, subscriptions, API keys and Friends data.
    // Login throttling entries are keyed by email, not a user foreign key.
    // Reports are stored in Workers KV, outside D1 cascades. Purge them
    // before removing the account so a KV failure never returns a false
    // deletion confirmation.
    const apple = await db.prepare('SELECT refresh_token FROM apple_identities WHERE user_id = ?').bind(user.id).first();
    if (apple?.refresh_token) {
      try { await revokeAppleAuthorization(env, apple.refresh_token); }
      catch { return response({ error: 'Apple authorization could not be revoked. Please retry account deletion.' }, 503); }
    }
    // Deleting the account cascades billing_customers away; a live Stripe
    // subscription would keep charging with no account for its webhooks.
    const stripe = await cancelStripeSubscriptionsForDeletion(db, env, user.id, dependencies.stripe);
    if (!stripe.ok) {
      return response({ error: 'Your subscription could not be cancelled. Please retry account deletion.',
        code: 'SUBSCRIPTION_CANCEL_FAILED' }, 503);
    }
    // Apple subscriptions can only be cancelled by the user in the App Store.
    const appleSubscriptionActive = await appleSubscriptionRenewing(db, user.id);
    await purgeDeletedReporterReports(env, user.id);
    await db.batch([
      db.prepare('DELETE FROM login_attempts WHERE email = ?').bind(user.email),
      db.prepare('DELETE FROM auth_login_limits WHERE subject = ? OR substr(subject, 1, length(?)) = ?')
        .bind(`email:${user.email}`, `pair:${user.email}|`, `pair:${user.email}|`),
      db.prepare("DELETE FROM api_usage_daily WHERE provider = '__waybi_quotas' AND sku IN (?, ?)")
        .bind(`user:${user.id}`, `nz-routing:user:${user.id}`),
      db.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
    ]);
    return response({ ok: true, appleSubscriptionActive, stripeSubscriptionsCancelled: stripe.cancelled },
      200, { 'set-cookie': clearCookieHeader(request) });
  }
  if (path === '/api/profile/friends') return handleFriendsBackup(request, db, user.id);
  if ((path === '/api/auth/me' || path === '/api/profile') && request.method === 'GET') {
    // App Store state refreshes in the background (and every 15 minutes via
    // Cron); profile writes such as finishing a trip never wait on Apple.
    await refreshAppleInBackground(db, env, user.id, ctx);
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/auth/google/link' && request.method === 'POST') {
    if (!env.GOOGLE_OAUTH_CLIENT_IDS) return response({ error: 'Google sign-in is not configured' }, 503);
    const body = await readBody(request);
    let identity;
    try {
      identity = await verifyGoogleIdToken(body?.idToken, env.GOOGLE_OAUTH_CLIENT_IDS);
    } catch {
      return response({ error: 'Google sign-in could not be verified' }, 401);
    }
    if (identity.email !== user.email) return response({ error: 'Google email must match your account email' }, 409);
    const existing = await db.prepare('SELECT user_id FROM google_identities WHERE google_sub = ?').bind(identity.sub).first();
    if (existing && existing.user_id !== user.id) return response({ error: 'Google account is linked elsewhere' }, 409);
    const already = await db.prepare('SELECT google_sub FROM google_identities WHERE user_id = ?').bind(user.id).first();
    if (already && already.google_sub !== identity.sub) return response({ error: 'A different Google account is already linked' }, 409);
    if (!already) await db.prepare('INSERT INTO google_identities (google_sub, user_id, created_at, verified_email) VALUES (?, ?, ?, ?)')
      .bind(identity.sub, user.id, Date.now(), identity.email).run();
    else await db.prepare('UPDATE google_identities SET verified_email = ? WHERE google_sub = ?')
      .bind(identity.email, identity.sub).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/details' && request.method === 'PATCH') {
    const body = await readBody(request);
    const displayName = typeof body?.displayName === 'string' ? body.displayName.trim() : null;
    if (displayName === null || displayName.length > 100) return response({ error: 'Display name must be at most 100 characters' }, 400);
    await db.prepare('UPDATE profiles SET display_name = ? WHERE user_id = ?').bind(displayName, user.id).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile' && request.method === 'PATCH') {
    const body = await readBody(request);
    if (!body || !['en', 'zh'].includes(body.language) || typeof body.voiceEnabled !== 'boolean') {
      return response({ error: 'Invalid preferences' }, 400);
    }
    await db.prepare('UPDATE profiles SET language = ?, voice_enabled = ? WHERE user_id = ?')
      .bind(body.language, body.voiceEnabled ? 1 : 0, user.id).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/destinations' && request.method === 'POST') {
    const body = await readBody(request);
    if (typeof body?.label !== 'string' || body.label.length < 1 || body.label.length > 200 ||
      !validCoordinate(body.latitude, body.longitude)) {
      return response({ error: 'Invalid destination' }, 400);
    }
    await db.prepare(`INSERT INTO recent_destinations (user_id, label, latitude, longitude, updated_at)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, latitude, longitude)
      DO UPDATE SET label = excluded.label, updated_at = excluded.updated_at`)
      .bind(user.id, body.label, body.latitude, body.longitude, Date.now()).run();
    await db.prepare(`DELETE FROM recent_destinations WHERE user_id = ? AND (latitude, longitude) NOT IN
      (SELECT latitude, longitude FROM recent_destinations WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20)`)
      .bind(user.id, user.id).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/quick-locations' && request.method === 'POST') {
    const body = await readBody(request);
    const label = body?.label;
    const placeId = QUICK_LOCATION_IDS[label];
    const name = typeof body?.name === 'string' ? body.name.trim() : '';
    const address = typeof body?.address === 'string' ? body.address.trim() : '';
    const provider = body?.provider === 'independent'
      ? 'independent'
      : body?.provider === 'google'
        ? 'google'
        : null;
    if (!placeId || !name || name.length > 200 || address.length > 500 || !provider ||
      !validCoordinate(body.latitude, body.longitude)) {
      return response({ error: 'Invalid quick location' }, 400);
    }
    await db.prepare(`INSERT INTO place_bookmarks
      (user_id, place_id, name, address, latitude, longitude, is_favorite, note, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
      ON CONFLICT(user_id, place_id) DO UPDATE SET
        name = excluded.name,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        is_favorite = 0,
        note = excluded.note,
        updated_at = excluded.updated_at`)
      .bind(user.id, placeId, name, address, body.latitude, body.longitude, provider, Date.now()).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/places' && request.method === 'POST') {
    const body = await readBody(request);
    const placeId = typeof body?.placeId === 'string' ? body.placeId.trim() : '';
    const name = typeof body?.name === 'string' ? body.name.trim() : '';
    const address = typeof body?.address === 'string' ? body.address.trim() : '';
    const note = typeof body?.note === 'string' ? body.note.trim() : '';
    if (!placeId || placeId.length > 256 || !name || name.length > 200 || address.length > 500 ||
      note.length > 2000 || typeof body?.isFavorite !== 'boolean' ||
      !validCoordinate(body.latitude, body.longitude)) {
      return response({ error: 'Invalid place bookmark' }, 400);
    }
    await db.prepare(`INSERT INTO place_bookmarks
      (user_id, place_id, name, address, latitude, longitude, is_favorite, note, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, place_id) DO UPDATE SET
        name = excluded.name,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        is_favorite = excluded.is_favorite,
        note = excluded.note,
        updated_at = excluded.updated_at`)
      .bind(
        user.id, placeId, name, address, body.latitude, body.longitude,
        body.isFavorite ? 1 : 0, note, Date.now()
      ).run();
    if (!body.isFavorite && !note) {
      await db.prepare('DELETE FROM place_bookmarks WHERE user_id = ? AND place_id = ?')
        .bind(user.id, placeId).run();
    }
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/routes' && request.method === 'POST') {
    const body = await readBody(request);
    const name = typeof body?.destinationName === 'string' ? body.destinationName.trim() : '';
    const mode = body?.mode;
    const distance = body?.distanceMeters;
    const duration = body?.durationSeconds;
    // A stable client-generated ID makes network retries exactly-once.
    const recordId = body?.journeyId == null ? crypto.randomUUID() : body.journeyId;
    if (typeof recordId !== 'string' || !/^[a-zA-Z0-9_-]{12,100}$/.test(recordId)) {
      return response({ error: 'Invalid journey id' }, 400);
    }
    if (!name || name.length > 200 || !['drive', 'transit', 'walk', 'bicycle'].includes(mode) ||
      !validCoordinate(body.latitude, body.longitude) ||
      (distance != null && (!Number.isFinite(distance) || distance < 0 || distance > 5_000_000)) ||
      (duration != null && (!Number.isFinite(duration) || duration < 0 || duration > 2_000_000))) {
      return response({ error: 'Invalid route history' }, 400);
    }
    await db.prepare(`INSERT OR IGNORE INTO route_history (id, user_id, destination_name,
      destination_latitude, destination_longitude, mode, distance_meters, duration_seconds, started_at)
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
      WHERE NOT EXISTS (
        SELECT 1 FROM companion_route_receipts WHERE user_id = ? AND journey_id = ?
      )`)
      .bind(recordId, user.id, name, body.latitude, body.longitude, mode,
        distance == null ? null : Math.round(distance), duration == null ? null : Math.round(duration), Date.now(),
        user.id, recordId).run();
    await db.prepare(`DELETE FROM route_history WHERE user_id = ? AND id NOT IN
      (SELECT id FROM route_history WHERE user_id = ? ORDER BY started_at DESC LIMIT 100)`)
      .bind(user.id, user.id).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/companion/import' && request.method === 'POST') {
    const body = await readBody(request);
    const { importId, distanceMeters, tripCount, durationSeconds } = body || {};
    if (typeof importId !== 'string' || !/^[a-zA-Z0-9_-]{12,100}$/.test(importId) ||
        !Number.isSafeInteger(distanceMeters) || distanceMeters < 0 || distanceMeters > 1_000_000_000 ||
        !Number.isSafeInteger(tripCount) || tripCount < 1 || tripCount > 1_000_000 ||
        !Number.isSafeInteger(durationSeconds) || durationSeconds < 0 || durationSeconds > 1_000_000_000) {
      return response({ error: 'Invalid companion import' }, 400);
    }
    await db.prepare(`INSERT OR IGNORE INTO companion_guest_imports
      (user_id, import_id, distance_meters, trip_count, duration_seconds, created_at)
      VALUES (?, ?, ?, ?, ?, ?)`)
      .bind(user.id, importId, distanceMeters, tripCount, durationSeconds, Date.now()).run();
    return response(await userProfile(db, user, env));
  }
  if (path === '/api/profile/reviews' && request.method === 'POST') {
    const body = await readBody(request);
    const placeId = typeof body?.placeId === 'string' ? body.placeId.trim() : '';
    const placeName = typeof body?.placeName === 'string' ? body.placeName.trim() : '';
    const comment = typeof body?.comment === 'string' ? body.comment.trim() : '';
    const rating = body?.rating;
    if (!placeId || placeId.length > 256 || !placeName || placeName.length > 200 ||
      !Number.isInteger(rating) || rating < 1 || rating > 5 || comment.length > 2000) {
      return response({ error: 'Invalid place review' }, 400);
    }
    await db.prepare(`INSERT INTO place_reviews
      (user_id, place_id, place_name, rating, comment, updated_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, place_id) DO UPDATE SET
        place_name = excluded.place_name, rating = excluded.rating,
        comment = excluded.comment, updated_at = excluded.updated_at`)
      .bind(user.id, placeId, placeName, rating, comment, Date.now()).run();
    return response(await userProfile(db, user, env));
  }
  return response({ error: 'Not found' }, 404);
}
