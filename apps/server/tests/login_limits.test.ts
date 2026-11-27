import test from 'node:test';
import assert from 'node:assert/strict';
import { handleAccount, hashPassword, LOGIN_LIMITS } from '../src/auth.ts';
import { migratedD1 } from './d1_fixture.ts';

const email = 'driver@example.test';
const salt = '00112233445566778899aabbccddeeff';

async function fixture() {
  const { sqlite, db } = migratedD1();
  sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)')
    .run('driver', email, salt, await hashPassword('correct-horse-battery', salt), 0);
  sqlite.prepare('INSERT INTO profiles(user_id,language,voice_enabled) VALUES(?,?,?)').run('driver', 'en', 1);
  return { sqlite, env: { USER_DB: db, EMAIL_OTP_SECRET: 'login-limit-test-secret-'.repeat(2) } };
}

function login(password: string, ip = '203.0.113.10', target = email) {
  return new Request('https://waybi.co/api/auth/login', { method: 'POST', headers: {
    'content-type': 'application/json', 'x-waybi-client': 'mobile', 'cf-connecting-ip': ip,
  }, body: JSON.stringify({ email: target, password }) });
}

test('concurrent wrong guesses reserve attempts atomically, so at most five reach password hashing', async () => {
  const { sqlite, env } = await fixture();
  try {
    const results = await Promise.all(Array.from({ length: 12 }, () => handleAccount(login('wrong-password-guess'), env)));
    const statuses = results.map((response) => response.status);
    assert.equal(statuses.filter((status) => status === 401).length, LOGIN_LIMITS.pair);
    assert.equal(statuses.filter((status) => status === 429).length, 12 - LOGIN_LIMITS.pair);
    const locked = results.find((response) => response.status === 429)!;
    assert.equal(locked.headers.get('retry-after'), '900');
    assert.equal((await locked.json()).code, 'LOGIN_LOCKED');
    // The correct password from the attacking client is also refused while locked.
    assert.equal((await handleAccount(login('correct-horse-battery'), env)).status, 429);
  } finally { sqlite.close(); }
});

test('a stranger locking one client does not lock the owner out from another client', async () => {
  const { sqlite, env } = await fixture();
  try {
    for (let i = 0; i < LOGIN_LIMITS.pair + 2; i++) await handleAccount(login('wrong-password-guess', '198.51.100.66'), env);
    const owner = await handleAccount(login('correct-horse-battery', '192.0.2.44'), env);
    assert.equal(owner.status, 200);
    assert.match(owner.headers.get('set-cookie') || '', /waybi_session=/);
    // Success returns its reserved units: the shared email counter is not consumed by it.
    const counter = sqlite.prepare("SELECT failures FROM auth_login_limits WHERE subject = ?").get(`email:${email}`) as any;
    assert.equal(counter.failures, LOGIN_LIMITS.pair);
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM auth_login_limits WHERE subject LIKE 'pair:%' AND failures > 0").get().c, 1,
      'only the guessing client stays locked');
  } finally { sqlite.close(); }
});

test('the looser per-email cap bounds a distributed guessing attack, and one client cannot spray many accounts', async () => {
  const { sqlite, env } = await fixture();
  try {
    let refused = 0;
    for (let i = 0; i < LOGIN_LIMITS.email + 5; i++) {
      const response = await handleAccount(login('wrong-password-guess', `203.0.113.${i + 20}`), env);
      if (response.status === 429) refused++;
    }
    assert.equal(refused, 5);
    let sprayRefused = 0;
    for (let i = 0; i < LOGIN_LIMITS.client + 3; i++) {
      const response = await handleAccount(login('wrong-password-guess', '198.51.100.200', `user${i}@example.test`), env);
      if (response.status === 429) sprayRefused++;
    }
    assert.equal(sprayRefused, 3);
    assert.equal(sqlite.prepare("SELECT count(*) AS c FROM auth_login_limits WHERE subject LIKE '%198.51.100.200%'").get().c, 0,
      'raw client IPs are never stored');
  } finally { sqlite.close(); }
});
