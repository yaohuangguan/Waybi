import { randomInt } from 'node:crypto';
import { emailDeliveryReady, sendSignInEmail } from './auth_email.ts';

const encoder = new TextEncoder();
function reply(body, status = 200, headers = {}) {
  return Response.json(body, { status, headers: { 'cache-control': 'no-store', ...headers } });
}
export function emailOtpReady(env) {
  return emailDeliveryReady(env) && typeof env.EMAIL_OTP_SECRET === 'string' && env.EMAIL_OTP_SECRET.length >= 32;
}
async function mac(secret: string, value: string) {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value))), b => b.toString(16).padStart(2, '0')).join('');
}
async function reserveRequests(db, subject: string, limit: number, now: number) {
  return db.prepare(`INSERT INTO email_otp_limits VALUES (?, ?, 1)
    ON CONFLICT(subject) DO UPDATE SET
      requests = CASE WHEN ? - window_start >= 3600000 THEN 1 ELSE requests + 1 END,
      window_start = CASE WHEN ? - window_start >= 3600000 THEN ? ELSE window_start END
    WHERE ? - window_start >= 3600000 OR requests < ? RETURNING requests`)
    .bind(subject, now, now, now, now, now, limit).first();
}

export async function handleEmailOtp(request: Request, env, authenticated: (user: { id: string; email: string }) => Promise<Response>) {
  const path = new URL(request.url).pathname;
  if (!['/api/auth/email/request', '/api/auth/email/verify'].includes(path) || request.method !== 'POST') return null;
  if (!emailOtpReady(env)) return reply({ error: 'Email codes are not configured yet. Use an existing sign-in method.' }, 503);
  if (!request.headers.get('content-type')?.startsWith('application/json')) return reply({ error: 'JSON required' }, 400);
  // Check actual streamed size as well as Content-Length, before decoding JSON.
  const reader = request.body?.getReader();
  if (!reader) return reply({ error: 'Invalid request' }, 400);
  let size = 0, raw = '';
  const decoder = new TextDecoder();
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    size += chunk.value.byteLength;
    if (size > 4096) { await reader.cancel(); return reply({ error: 'Request too large' }, 413); }
    raw += decoder.decode(chunk.value, { stream: true });
  }
  let body;
  try { body = JSON.parse(raw + decoder.decode()); } catch { return reply({ error: 'Invalid request' }, 400); }
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply({ error: 'Enter a valid email address' }, 400);
  const db = env.USER_DB, now = Date.now();
  const emailKey = await mac(env.EMAIL_OTP_SECRET, `email:${email}`);
  const ipKey = await mac(env.EMAIL_OTP_SECRET, `ip:${request.headers.get('cf-connecting-ip') || 'unknown'}`);
  const requesting = path.endsWith('/request');
  if (!await reserveRequests(db, `${requesting ? 'send' : 'verify'}:${ipKey}`, requesting ? 20 : 60, now)) {
    return reply({ error: 'Too many requests. Please try again later.' }, 429, { 'retry-after': '3600' });
  }
  if (requesting) {
    const existing = await db.prepare('SELECT created_at FROM email_otp_challenges WHERE email_key = ?').bind(emailKey).first();
    if (existing && now - existing.created_at < 60_000) return reply({ error: 'Wait before requesting another code.' }, 429, { 'retry-after': String(Math.ceil((60_000 - now + existing.created_at) / 1000)) });
    if (!await reserveRequests(db, `email:${emailKey}`, 5, now)) return reply({ error: 'Too many codes requested. Please try again later.' }, 429, { 'retry-after': '3600' });
    const id = crypto.randomUUID(), code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const hash = await mac(env.EMAIL_OTP_SECRET, `${emailKey}:${id}:${code}`);
    const reserved = await db.prepare(`INSERT INTO email_otp_challenges VALUES (?, ?, ?, ?, ?, 0, 0)
      ON CONFLICT(email_key) DO UPDATE SET challenge_id = excluded.challenge_id, code_hash = excluded.code_hash,
        created_at = excluded.created_at, expires_at = excluded.expires_at, attempts = 0, delivered = 0
      WHERE email_otp_challenges.created_at <= ? RETURNING challenge_id`)
      .bind(emailKey, id, hash, now, now + 600_000, now - 60_000).first();
    if (!reserved) return reply({ error: 'Wait before requesting another code.' }, 429, { 'retry-after': '60' });
    try {
      if (!await sendSignInEmail(db, env, email, code, body.language)) {
        return reply({ error: 'Email sending limit reached. Please try again later or use another sign-in method.' }, 429, { 'retry-after': '3600' });
      }
      await db.prepare('UPDATE email_otp_challenges SET delivered = 1 WHERE challenge_id = ?').bind(id).run();
    } catch {
      return reply({ error: 'Could not send a code. Please try again later or use another sign-in method.' }, 503);
    }
    // Opportunistic cleanup; no email addresses, IPs, codes or provider keys in logs.
    await db.batch([
      db.prepare('DELETE FROM email_otp_challenges WHERE expires_at < ?').bind(now - 86_400_000),
      db.prepare('DELETE FROM email_otp_limits WHERE window_start < ?').bind(now - 86_400_000),
    ]);
    return reply({ challengeId: id, retryAfter: 60, expiresIn: 600 });
  }
  if (typeof body.challengeId !== 'string' || !/^[0-9a-f-]{36}$/.test(body.challengeId) ||
      typeof body.code !== 'string' || !/^\d{6}$/.test(body.code)) return reply({ error: 'Enter the six-digit code from your email.' }, 400);
  const attempted = await db.prepare(`UPDATE email_otp_challenges SET attempts = attempts + 1
    WHERE email_key = ? AND challenge_id = ? AND expires_at > ? AND attempts < 5 AND delivered = 1
    RETURNING challenge_id`).bind(emailKey, body.challengeId, now).first();
  if (!attempted) return reply({ error: 'Code is invalid or expired. Request a new code.' }, 401);
  const hash = await mac(env.EMAIL_OTP_SECRET, `${emailKey}:${body.challengeId}:${body.code}`);
  // Atomic consumption prevents replays and concurrent successful verifications.
  const consumed = await db.prepare(`DELETE FROM email_otp_challenges
    WHERE email_key = ? AND challenge_id = ? AND code_hash = ? AND expires_at > ? AND attempts <= 5 AND delivered = 1
    RETURNING challenge_id`).bind(emailKey, body.challengeId, hash, now).first();
  if (!consumed) return reply({ error: 'Code is invalid or expired. Request a new code.' }, 401);
  await db.batch([
    db.prepare(`INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, '', '', ?)
      ON CONFLICT(email) DO NOTHING`).bind(crypto.randomUUID(), email, now),
    db.prepare(`INSERT INTO profiles (user_id, language, voice_enabled)
      SELECT id, ?, ? FROM users WHERE email = ? ON CONFLICT(user_id) DO NOTHING`)
      .bind(body.language === 'zh' ? 'zh' : 'en', body.voiceEnabled === false ? 0 : 1, email),
    db.prepare(`INSERT INTO email_identities (user_id, verified_at) SELECT id, ? FROM users WHERE email = ?
      ON CONFLICT(user_id) DO UPDATE SET verified_at = excluded.verified_at`).bind(now, email),
  ]);
  const user = await db.prepare('SELECT id, email FROM users WHERE email = ?').bind(email).first();
  return authenticated(user);
}
