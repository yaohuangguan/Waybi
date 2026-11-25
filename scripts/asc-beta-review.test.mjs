import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { ascToken, createClient, submitForBetaReview, mergeReviewDetail, missingContact, WHAT_TO_TEST } from './asc-beta-review.mjs';

test('App Store Connect token is a short-lived ES256 JWT', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const token = ascToken({ keyId: 'KEY', issuerId: 'ISSUER', now: 1_000_000_000_000,
    privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
  const [header, payload, signature] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY', typ: 'JWT' });
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.equal(claims.aud, 'appstoreconnect-v1');
  assert.equal(claims.exp - claims.iat, 900);
  assert.ok(createVerify('SHA256').update(`${header}.${payload}`)
    .verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
});

test('existing review contact wins; secrets fill only the gaps', () => {
  const merged = mergeReviewDetail({ contactFirstName: 'Existing', contactPhone: '' },
    { ASC_REVIEW_CONTACT_FIRST_NAME: 'Secret', ASC_REVIEW_CONTACT_LAST_NAME: 'Owner' });
  assert.equal(merged.contactFirstName, 'Existing');
  assert.equal(merged.contactLastName, 'Owner');
  assert.equal(merged.contactEmail, 'support@waybi.co');
  assert.equal(merged.demoAccountRequired, false);
  assert.deepEqual(missingContact(merged), ['contactPhone']);
  assert.ok(WHAT_TO_TEST.length < 4000);
});

function fakeAppStore({ processing = ['PROCESSING', 'VALID'], contact = true, group = null, externalState = 'READY_FOR_BETA_SUBMISSION' } = {}) {
  const calls = [];
  const states = [...processing];
  const routes = {
    'GET /v1/apps': () => ({ data: [{ id: 'app', attributes: { name: 'Waybi', primaryLocale: 'en-AU' } }] }),
    'GET /v1/builds': () => ({ data: [{ id: 'build', attributes: { processingState: states.length > 1 ? states.shift() : states[0], usesNonExemptEncryption: null } }] }),
    'GET /v1/apps/app/betaAppLocalizations': () => ({ data: [] }),
    'GET /v1/apps/app/betaAppReviewDetail': () => ({ data: { id: 'app', attributes: contact
      ? { contactFirstName: 'A', contactLastName: 'B', contactPhone: '+64 0', contactEmail: 'a@b.test' } : {} } }),
    'GET /v1/builds/build/betaBuildLocalizations': () => ({ data: [{ id: 'loc', attributes: { locale: 'en-AU' } }] }),
    'GET /v1/betaGroups': () => ({ data: group ? [group] : [] }),
    'POST /v1/betaGroups': body => ({ data: { id: 'group', ...body.data } }),
    'GET /v1/builds/build/buildBetaDetail': () => ({ data: { attributes: { externalBuildState: externalState } } }),
    'GET /v1/betaGroups/group': () => ({ data: { id: 'group', attributes: { publicLink: 'https://testflight.apple.com/join/abc' } } }),
  };
  const fetcher = async (url, init) => {
    const path = new URL(url).pathname;
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ method: init.method, path, body });
    assert.match(init.headers.authorization, /^Bearer token$/);
    const handler = routes[`${init.method} ${path}`];
    if (handler) return Response.json(handler(body));
    if (init.method === 'POST' && path === '/v1/betaGroups/group/relationships/builds') return new Response(null, { status: 204 });
    if (init.method === 'PATCH' || init.method === 'POST') return Response.json({ data: body?.data ?? null }, { status: 201 });
    return Response.json({ errors: [{ code: 'NOT_FOUND', detail: path }] }, { status: 404 });
  };
  return { calls, fetcher };
}

const options = { bundleId: 'co.waybi.ios', appVersion: '1.0.0', buildNumber: '50', groupName: 'Public testers', log: () => {}, pollMs: 0 };

test('waits for processing, fills test information, opens a public group and submits once', async () => {
  const store = fakeAppStore();
  const result = await submitForBetaReview(createClient({ token: () => 'token', fetcher: store.fetcher }), options);
  assert.equal(result.submitted, true);
  assert.equal(result.publicLink, 'https://testflight.apple.com/join/abc');
  const writes = store.calls.filter(call => call.method !== 'GET').map(call => `${call.method} ${call.path}`);
  assert.deepEqual(writes, [
    'PATCH /v1/builds/build',
    'POST /v1/betaAppLocalizations',
    'PATCH /v1/betaAppReviewDetails/app',
    'PATCH /v1/betaBuildLocalizations/loc',
    'POST /v1/betaGroups',
    'POST /v1/betaGroups/group/relationships/builds',
    'POST /v1/betaAppReviewSubmissions',
  ]);
  const compliance = store.calls.find(call => call.path === '/v1/builds/build' && call.method === 'PATCH');
  assert.equal(compliance.body.data.attributes.usesNonExemptEncryption, false);
  const groupBody = store.calls.find(call => call.path === '/v1/betaGroups' && call.method === 'POST').body;
  assert.equal(groupBody.data.attributes.publicLinkEnabled, true);
  assert.equal(store.calls.filter(call => call.path === '/v1/builds').length, 2, 'polls until VALID');
});

test('missing contact stops before anything is submitted; repeat runs do not resubmit', async () => {
  const incomplete = fakeAppStore({ contact: false });
  await assert.rejects(submitForBetaReview(createClient({ token: () => 'token', fetcher: incomplete.fetcher }), options),
    /contactFirstName, contactLastName, contactPhone/);
  assert.equal(incomplete.calls.some(call => call.path === '/v1/betaAppReviewSubmissions'), false);

  const again = fakeAppStore({ group: { id: 'group', attributes: { name: 'Public testers', isInternalGroup: false, publicLinkEnabled: true } },
    externalState: 'WAITING_FOR_BETA_REVIEW' });
  const result = await submitForBetaReview(createClient({ token: () => 'token', fetcher: again.fetcher }), options);
  assert.equal(result.submitted, false);
  assert.equal(again.calls.some(call => call.path === '/v1/betaAppReviewSubmissions'), false);
  assert.equal(again.calls.some(call => call.method === 'POST' && call.path === '/v1/betaGroups'), false);
});

test('failed processing and dry runs are safe', async () => {
  const failed = fakeAppStore({ processing: ['FAILED'] });
  await assert.rejects(submitForBetaReview(createClient({ token: () => 'token', fetcher: failed.fetcher }), options), /FAILED/);
  const dry = fakeAppStore();
  const result = await submitForBetaReview(createClient({ token: () => 'token', fetcher: dry.fetcher, dryRun: true, log: () => {} }), options);
  assert.equal(dry.calls.every(call => call.method === 'GET'), true);
  assert.equal(result.buildId, 'build');
});
