import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { handleAccount } from '../src/auth.ts';

function fixture() {
  const sql = new DatabaseSync(':memory:');
  sql.exec('PRAGMA foreign_keys=ON');
  const root = new URL('../../../migrations/', import.meta.url);
  for (const file of readdirSync(root).filter(f => /^\d+.*\.sql$/.test(f)).sort()) sql.exec(readFileSync(new URL(file, root), 'utf8'));
  const db: any = { prepare(query: string) { return { bind(...values: any[]) { return { sql: query, values,
    async first() { return sql.prepare(query).get(...values) || null; },
    async all() { return { results: sql.prepare(query).all(...values) }; },
    async run() { return sql.prepare(query).run(...values); }
  }; } }; }, async batch(items: any[]) {
    sql.exec('BEGIN');
    try { const results = items.map(s => sql.prepare(s.sql).run(...s.values)); sql.exec('COMMIT'); return results; }
    catch (error) { sql.exec('ROLLBACK'); throw error; }
  } };
  const env = { USER_DB: db, SENDPULSE_API_KEY: 'canary-sendpulse-key', AUTH_EMAIL_FROM: 'accounts@waybi.test',
    EMAIL_OTP_SECRET: 'canary-otp-secret-'.repeat(4), WAYBI_RESEND_API_KEY: 'canary-resend-key' };
  const sent: { provider: string; code: string; email: string }[] = [];
  let pulseStatus = 200, resendStatus = 200, pulseMessage = 'Sending quota or bandwidth exceeded';
  const fetcher: typeof fetch = async (url, init) => {
    assert.equal(init?.method, 'POST');
    assert.ok(init?.signal, 'network calls must be bounded');
    const body = JSON.parse(String(init.body));
    const pulse = String(url) === 'https://api.sendpulse.com/smtp/emails';
    assert.ok(pulse || String(url) === 'https://api.resend.com/emails', 'unexpected external request');
    assert.equal(init.headers['authorization'], 'Bearer ' + (pulse ? env.SENDPULSE_API_KEY : env.WAYBI_RESEND_API_KEY));
    const status = pulse ? pulseStatus : resendStatus;
    if (pulse && status === 422) return Response.json({message: pulseMessage, error_code: 422}, {status});
    if (status !== 200) return Response.json({ error: 'canary-provider-private-error' }, { status });
    const mail = pulse ? body.email : body;
    const code = mail.text.match(/\b\d{6}\b/)[0];
    sent.push({ provider: pulse ? 'sendpulse' : 'resend', code, email: pulse ? mail.to[0].email : mail.to[0] });
    return Response.json(pulse ? { result: true, id: 'pulse-message' } : { id: 'resend-message' });
  };
  return { sql, env, sent, fetcher, pulseStatus(value: number, message = 'Sending quota or bandwidth exceeded') { pulseStatus = value; pulseMessage = message; }, resendStatus(value: number) { resendStatus = value; } };
}
function request(action: string, body: any, extraHeaders = {}) {
  return new Request('https://waybi.co/api/auth/email/' + action, { method: 'POST', headers: {
    'content-type': 'application/json', 'x-waybi-client': 'web', origin: 'https://waybi.co', 'cf-connecting-ip': '192.0.2.1', ...extraHeaders,
  }, body: JSON.stringify(body) });
}
async function withFixture(run: (f: ReturnType<typeof fixture>) => Promise<void>) {
  const f = fixture(); const original = globalThis.fetch; globalThis.fetch = f.fetcher;
  try { await run(f); } finally { globalThis.fetch = original; f.sql.close(); }
}
const email = 'driver@example.test';

test('email OTP creates no account before verification; code is private, single use and returns the existing session format', () => withFixture(async f => {
  const result = await handleAccount(request('request', { email: ' Driver@Example.Test ', language: 'zh' }), f.env);
  assert.equal(result.status, 200);
  const challenge = await result.json() as any;
  assert.match(challenge.challengeId, /^[0-9a-f-]{36}$/);
  assert.equal(challenge.retryAfter, 60);
  assert.equal(challenge.expiresIn, 600);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM users').get().n, 0);
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].email, email);
  const stored = f.sql.prepare('SELECT * FROM email_otp_challenges').get();
  assert.ok(!JSON.stringify(stored).includes(f.sent[0].code));
  assert.ok(!JSON.stringify(challenge).includes(f.sent[0].code));
  const verified = await handleAccount(request('verify', { email, challengeId: challenge.challengeId, code: f.sent[0].code, language: 'zh', voiceEnabled: false }), f.env);
  assert.equal(verified.status, 200);
  assert.match(verified.headers.get('set-cookie'), /waybi_session=[0-9a-f]{64}; HttpOnly; SameSite=Lax; Path=\//);
  const profile = await verified.json() as any;
  assert.equal(profile.user.email, email);
  assert.ok(profile.user.providers.includes('email'));
  assert.equal(profile.language, 'zh');
  assert.equal(profile.voiceEnabled, false);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM sessions').get().n, 1);
  assert.equal((await handleAccount(request('verify', { email, challengeId: challenge.challengeId, code: f.sent[0].code }), f.env)).status, 401);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM sessions').get().n, 1);
}));

test('email OTP safely signs into an existing password account without overwriting its profile or password', () => withFixture(async f => {
  const registered = await handleAccount(new Request('https://waybi.co/api/auth/register', { method: 'POST', headers: {
    'content-type': 'application/json', 'x-waybi-client': 'mobile',
  }, body: JSON.stringify({ email, password: 'existing-long-password', language: 'en' }) }), f.env);
  assert.equal(registered.status, 200);
  const user = f.sql.prepare('SELECT * FROM users').get();
  const challenge = await (await handleAccount(request('request', { email }), f.env)).json() as any;
  const verified = await handleAccount(request('verify', { email, challengeId: challenge.challengeId, code: f.sent[0].code, language: 'zh' }), f.env);
  assert.equal(verified.status, 200);
  assert.equal((await verified.json() as any).user.id, user.id);
  assert.deepEqual(f.sql.prepare('SELECT * FROM users').get(), user);
  assert.equal(f.sql.prepare('SELECT language FROM profiles').get().language, 'en');
}));

test('invalid input, missing configuration and cross-origin requests never send or create accounts', () => withFixture(async f => {
  assert.equal((await handleAccount(request('request', { email }), { ...f.env, EMAIL_OTP_SECRET: '' })).status, 503);
  for (const value of ['', 'bad', 'a'.repeat(255) + '@example.test', {}, null]) {
    assert.equal((await handleAccount(request('request', { email: value }), f.env)).status, 400);
  }
  assert.equal((await handleAccount(request('request', { email }, { origin: 'https://attacker.test' }), f.env)).status, 403);
  assert.equal(f.sent.length, 0);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM users').get().n, 0);
}));

test('resend cooldown and five-attempt lockout are enforced on the server', () => withFixture(async f => {
  const challenge = await (await handleAccount(request('request', { email }), f.env)).json() as any;
  assert.equal((await handleAccount(request('request', { email }), f.env)).status, 429);
  assert.equal(f.sent.length, 1);
  const wrong = f.sent[0].code === '000000' ? '000001' : '000000';
  for (let i = 0; i < 5; i++) assert.equal((await handleAccount(request('verify', { email, challengeId: challenge.challengeId, code: wrong }), f.env)).status, 401);
  assert.equal((await handleAccount(request('verify', { email, challengeId: challenge.challengeId, code: f.sent[0].code }), f.env)).status, 401);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM sessions').get().n, 0);
}));

test('expired and mismatched challenges fail closed; concurrent verification creates only one session', () => withFixture(async f => {
  const challenge = await (await handleAccount(request('request', { email }), f.env)).json() as any;
  const body = { email, challengeId: challenge.challengeId, code: f.sent[0].code };
  assert.equal((await handleAccount(request('verify', { ...body, email: 'other@example.test' }), f.env)).status, 401);
  f.sql.prepare('UPDATE email_otp_challenges SET expires_at = 0').run();
  assert.equal((await handleAccount(request('verify', body), f.env)).status, 401);
  f.sql.prepare('UPDATE email_otp_challenges SET expires_at = ?').run(Date.now() + 600_000);
  const results = await Promise.all([handleAccount(request('verify', body), f.env), handleAccount(request('verify', body), f.env)]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 401]);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM sessions').get().n, 1);
}));

test('SendPulse quota rejection falls back to Resend; ambiguous failures do not send a second email or leak secrets', () => withFixture(async f => {
  f.pulseStatus(429);
  assert.equal((await handleAccount(request('request', { email }), f.env)).status, 200);
  assert.equal(f.sent[0].provider, 'resend');
  f.pulseStatus(503);
  const failed = await handleAccount(request('request', { email: 'another@example.test' }), f.env);
  assert.equal(failed.status, 503);
  assert.ok(!(await failed.text()).includes('canary'));
  assert.equal(f.sent.length, 1);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM email_otp_challenges WHERE delivered = 1').get().n, 1);
}));

test('persisted provider budgets switch to Resend before SendPulse hourly cap; exhausted providers send nothing', () => withFixture(async f => {
  f.sql.prepare('INSERT INTO auth_email_budgets VALUES (?, ?, ?, ?, ?)').run('sendpulse', Date.now(), 50, Date.now(), 400);
  assert.equal((await handleAccount(request('request', { email }), f.env)).status, 200);
  assert.equal(f.sent[0].provider, 'resend');
  f.sql.prepare('UPDATE auth_email_budgets SET day_count = 100 WHERE provider = ?').run('resend');
  assert.equal((await handleAccount(request('request', { email: 'another@example.test' }), f.env)).status, 429);
  assert.equal(f.sent.length, 1);
}));

test('a replacement invalidates the old code, and the fifth correct attempt is accepted', () => withFixture(async f => {
  const first = await (await handleAccount(request('request', { email }), f.env)).json() as any;
  f.sql.prepare('UPDATE email_otp_challenges SET created_at = ?').run(Date.now() - 60_001);
  const second = await (await handleAccount(request('request', { email }), f.env)).json() as any;
  assert.equal((await handleAccount(request('verify', { email, challengeId: first.challengeId, code: f.sent[0].code }), f.env)).status, 401);
  const code = f.sent[1].code, wrong = code === '000000' ? '000001' : '000000';
  for (let i = 0; i < 4; i++) assert.equal((await handleAccount(request('verify', { email, challengeId: second.challengeId, code: wrong }), f.env)).status, 401);
  assert.equal((await handleAccount(request('verify', { email, challengeId: second.challengeId, code }), f.env)).status, 200);
  const before = f.sql.prepare('SELECT * FROM users').all();
  const migration = readFileSync(new URL('../../../migrations/0019_email_otp.sql', import.meta.url), 'utf8');
  f.sql.exec(migration); f.sql.exec(migration);
  assert.deepEqual(f.sql.prepare('SELECT * FROM users').all(), before);
}));

test('size limit, verification input validation and IP request limits deny requests before a send', () => withFixture(async f => {
  assert.equal((await handleAccount(request('request', { email, padding: 'x'.repeat(4096) }), f.env)).status, 413);
  assert.equal((await handleAccount(request('verify', { email, challengeId: 'invalid', code: '123456' }), f.env)).status, 400);
  for (let i = 0; i < 20; i++) await handleAccount(request('request', { email }), f.env);
  assert.equal((await handleAccount(request('request', { email: 'other@example.test' }), f.env)).status, 429);
  assert.equal(f.sent.length, 1);
}));

test('SendPulse documented 422 quota error falls back, while a sender configuration error does not', () => withFixture(async f => {
  f.pulseStatus(422);
  assert.equal((await handleAccount(request('request', {email}), f.env)).status, 200);
  assert.equal(f.sent[0].provider, 'resend');
  f.pulseStatus(422, 'Sender is not valid');
  assert.equal((await handleAccount(request('request', {email: 'other@example.test'}), f.env)).status, 503);
  assert.equal(f.sent.length, 1);
}));
