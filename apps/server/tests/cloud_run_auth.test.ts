import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { cloudRunIdentityToken } from '../src/cloud_run_auth.ts';
import { fetchNzRouting } from '../src/nz_routing.ts';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
function credentials(id: string) {
  return JSON.stringify({ type: 'service_account', private_key: pem, private_key_id: id,
    client_email: 'waybi-test@kiwi-lens-2026-sam.iam.gserviceaccount.com', token_uri: 'https://untrusted.example' });
}
const audience = 'https://waybi-test.a.run.app';
const signal = () => AbortSignal.timeout(5000);
const jwt = (claims: object) => `header.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.signature`;
const validToken = (aud = audience, exp = Math.floor(Date.now() / 1000) + 3600) =>
  jwt({ aud, exp, iss: 'https://accounts.google.com' });

test('signs an audience-bound JWT; deduplicates exchange, caches, and refreshes after credential rotation', async () => {
  let calls = 0;
  const fetcher = async (url, init) => {
    calls++;
    assert.equal(url, 'https://oauth2.googleapis.com/token');
    assert.equal(init.redirect, 'manual');
    const params = new URLSearchParams(init.body as string);
    assert.equal(params.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [header, claims, signature] = params.get('assertion')!.split('.');
    const parsed = JSON.parse(Buffer.from(claims, 'base64url').toString());
    assert.equal(parsed.target_audience, audience);
    assert.equal(parsed.aud, url);
    assert.equal(parsed.exp - parsed.iat, 3600);
    assert.equal(verify('RSA-SHA256', Buffer.from(`${header}.${claims}`), publicKey,
      Buffer.from(signature, 'base64url')), true);
    return Response.json({ id_token: validToken() });
  };
  const key = credentials('cache-test');
  const tokens = await Promise.all(Array.from({ length: 8 }, () => cloudRunIdentityToken(key, audience, signal(), fetcher)));
  assert.equal(new Set(tokens).size, 1);
  await cloudRunIdentityToken(key, audience, signal(), fetcher);
  assert.equal(calls, 1);
  await cloudRunIdentityToken(credentials('rotated-key'), audience, signal(), fetcher);
  assert.equal(calls, 2);
});

test('rejects invalid destinations and token responses; a failed exchange can be retried', async () => {
  const key = credentials('bad-responses');
  let calls = 0;
  const fetcher = async () => { calls++; return Response.json({ id_token: validToken() }); };
  for (const url of ['http://waybi-test.a.run.app', 'https://evil.example', `${audience}/route`, `${audience}/`]) {
    await assert.rejects(cloudRunIdentityToken(key, url, signal(), fetcher), /canonical/);
  }
  assert.equal(calls, 0);
  for (const data of [{}, { id_token: validToken('https://wrong.a.run.app') },
    { id_token: validToken(audience, 1) }, { id_token: 'broken' }]) {
    await assert.rejects(cloudRunIdentityToken(key, audience, signal(), async () => Response.json(data)));
  }
  await assert.rejects(cloudRunIdentityToken(key, audience, signal(), async () => new Response('', { status: 403 })), /HTTP 403/);
  await assert.rejects(cloudRunIdentityToken(key, audience, signal(), async () => new Response('', {
    status: 302, headers: { location: 'https://untrusted.example' },
  })), /HTTP 302/);
  await cloudRunIdentityToken(key, audience, signal(), fetcher);
  assert.equal(calls, 1);
});

test('private routing shares a deadline, keeps closures, and never follows redirects with its identity token', async () => {
  let calls = 0;
  let exchangeSignal;
  const points: [number, number][] = [[174.76, -36.85], [175.28, -37.78]];
  const exclusions = [{ lat: -36.9, lon: 174.8, heading: 90 }];
  const env = { WAYBI_NZ_ROUTING_URL: audience, WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT: credentials('route-test') };
  await fetchNzRouting(env, points, 'DRIVE', { language: 'zh' }, exclusions, async (url, init) => {
    calls++;
    if (String(url) === 'https://oauth2.googleapis.com/token') {
      exchangeSignal = init.signal;
      return Response.json({ id_token: validToken() });
    }
    assert.equal(String(url), `${audience}/route`);
    assert.equal(init.headers['authorization'], `Bearer ${validToken()}`);
    assert.equal(init.redirect, 'manual');
    assert.equal(init.signal, exchangeSignal);
    const body = JSON.parse(init.body as string);
    assert.deepEqual(body.exclude_locations, exclusions);
    assert.deepEqual(body.date_time, { type: 0 });
    assert.equal(body.language, 'zh-CN');
    return Response.json({ code: 'Ok', routes: [{}] });
  });
  assert.equal(calls, 2);
  await assert.rejects(fetchNzRouting({ ...env, WAYBI_NZ_ROUTING_URL: `${audience}/base` }, points,
    'DRIVE', {}, [], async () => { throw new Error('must not fetch'); }), /canonical/);
});
