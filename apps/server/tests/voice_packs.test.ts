import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import worker from '../src/worker.ts';
import { handleAccount } from '../src/auth.ts';
import {
  generateShareCode, handleVoicePacks, looksLikeAudio, normalizeShareCode, purgeVoicePacksForDeletion,
  SHARE_CODE_ALPHABET, VOICE_PACK_LIMITS, voicePackLandingPage,
} from '../src/voice_packs.ts';
import { migratedD1 } from './d1_fixture.ts';

/** In-memory R2 with the subset of the API the Worker uses. */
function fakeR2() {
  const objects = new Map<string, { bytes: Uint8Array; options: any }>();
  const calls: string[] = [];
  const store = {
    objects, calls,
    failPut: false, failDelete: false, failList: false,
    async put(key: string, value: Uint8Array, options: any) {
      calls.push(`put:${key}`);
      if (store.failPut && objects.size >= 1) throw new Error('R2 put failed');
      objects.set(key, { bytes: new Uint8Array(value), options });
    },
    async get(key: string) {
      const object = objects.get(key);
      if (!object) return null;
      return { body: new Blob([object.bytes]).stream(), size: object.bytes.length };
    },
    async delete(keys: string | string[]) {
      if (store.failDelete) throw new Error('R2 delete failed');
      for (const key of Array.isArray(keys) ? keys : [keys]) objects.delete(key);
    },
    async list({ prefix, cursor, limit = 1000 }: { prefix: string; cursor?: string; limit?: number }) {
      if (store.failList) throw new Error('R2 list failed');
      // Small pages, with a cursor that survives deletes like R2's does.
      const keys = [...objects.keys()].filter((key) => key.startsWith(prefix) && (!cursor || key > cursor)).sort();
      const page = keys.slice(0, Math.min(limit, 2));
      return { objects: page.map((key) => ({ key })), truncated: keys.length > page.length, cursor: page.at(-1) };
    },
  };
  return store;
}

function limiter(allow = () => true) {
  const keys: string[] = [];
  return { keys, async limit({ key }: { key: string }) { keys.push(key); return { success: allow() }; } };
}

function setup({ plus = true } = {}) {
  const { sqlite, db } = migratedD1();
  const users: Record<string, string> = {};
  for (const id of ['alice', 'bob', 'carol']) {
    sqlite.prepare('INSERT INTO users(id,email,password_salt,password_hash,created_at) VALUES(?,?,?,?,?)')
      .run(id, `${id}@waybi.test`, '', '', 0);
    const token = createHash('sha256').update(id).digest('hex');
    sqlite.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)')
      .run(createHash('sha256').update(token).digest('hex'), id, Date.now() + 60_000);
    users[id] = token;
  }
  if (plus) {
    for (const id of ['alice', 'bob']) {
      sqlite.prepare('INSERT INTO user_subscriptions(user_id,plan,source,updated_at) VALUES(?,?,?,?)').run(id, 'plus', 'manual', 0);
    }
  }
  const r2 = fakeR2();
  const rate = limiter();
  const env: any = { USER_DB: db, VOICE_PACKS: r2, RATE_LIMIT_VOICE: rate };
  return { sqlite, db, r2, rate, env, users };
}

function m4a(size = 2048, seed = 1) {
  const bytes = new Uint8Array(size).fill(seed);
  bytes.set([0, 0, 0, 24], 0);
  bytes.set([...'ftypM4A '].map((c) => c.charCodeAt(0)), 4);
  return bytes;
}

const sha = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

type Clip = { language: string; phraseId: string; bytes?: Uint8Array; contentType?: string; claim?: Record<string, unknown> };

function uploadRequest(token: string | null, clips: Clip[], options: {
  name?: unknown; consent?: unknown; headers?: Record<string, string>; extra?: Record<string, Blob>; manifest?: string;
} = {}) {
  const form = new FormData();
  form.set('manifest', options.manifest ?? JSON.stringify({
    name: 'name' in options ? options.name : 'Grandma',
    consent: 'consent' in options ? options.consent : true,
    clips: clips.map((clip) => ({
      language: clip.language, phraseId: clip.phraseId, contentType: clip.contentType ?? 'audio/mp4',
      bytes: (clip.bytes ?? m4a()).length, sha256: sha(clip.bytes ?? m4a()), ...clip.claim,
    })),
  }));
  for (const clip of clips) {
    form.set(`clip:${clip.language}:${clip.phraseId}`, new Blob([clip.bytes ?? m4a()]), `${clip.phraseId}.m4a`);
  }
  for (const [field, blob] of Object.entries(options.extra ?? {})) form.set(field, blob);
  return new Request('https://waybi.co/api/voice-packs', {
    method: 'POST',
    headers: {
      'x-waybi-client': 'mobile',
      ...(token ? { cookie: `waybi_session=${token}` } : {}),
      ...options.headers,
    },
    body: form,
  });
}

function call(path: string, { method = 'GET', token, headers = {} }: { method?: string; token?: string; headers?: Record<string, string> } = {}) {
  return new Request(`https://waybi.co${path}`, {
    method,
    headers: {
      ...(method === 'GET' ? {} : { 'x-waybi-client': 'mobile' }),
      ...(token ? { cookie: `waybi_session=${token}` } : {}),
      'cf-connecting-ip': '203.0.113.7',
      ...headers,
    },
  });
}

const twoClips: Clip[] = [
  { language: 'en', phraseId: 'turn_left', bytes: m4a(2048, 1) },
  { language: 'zh', phraseId: 'conn_toward', bytes: m4a(4096, 2) },
];

async function share(env, token: string, clips = twoClips) {
  const response = await handleVoicePacks(uploadRequest(token, clips), env);
  assert.equal(response?.status, 201, await response?.clone().text());
  return (await response!.json()).pack;
}

test('a Plus member shares a voice and anyone with the code can import it', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const pack = await share(env, users.alice);
    assert.match(pack.code, new RegExp(`^[${SHARE_CODE_ALPHABET}]{10}$`));
    assert.equal(pack.url, `https://waybi.co/voice/${pack.code}`);
    assert.deepEqual(pack.languages, ['en', 'zh']);
    assert.equal(pack.clipCount, 2);
    assert.equal(pack.totalBytes, 2048 + 4096);
    assert.equal(pack.importCount, 0);
    assert.equal(pack.clips, undefined, 'The owner listing has no clip manifest');
    assert.equal(r2.objects.size, 2);
    for (const [key, object] of r2.objects) {
      assert.match(key, /^voice-packs\/alice\/[0-9a-f-]{36}\/(en|zh)\/(turn_left|conn_toward)$/);
      assert.equal(object.options.httpMetadata.contentType, 'audio/mp4');
    }

    const manifest = await handleVoicePacks(call(`/api/voice-packs/${pack.code.toLowerCase()}`), env);
    assert.equal(manifest?.status, 200);
    assert.equal(manifest?.headers.get('cache-control'), 'no-store');
    const shared = (await manifest!.json()).pack;
    assert.equal(shared.name, 'Grandma');
    assert.deepEqual(shared.clips.en.turn_left, { bytes: 2048, contentType: 'audio/mp4', sha256: sha(m4a(2048, 1)) });
    assert.equal(shared.clips.zh.conn_toward.sha256, sha(m4a(4096, 2)));

    const clip = await handleVoicePacks(call(`/api/voice-packs/${pack.code}/clips/zh/conn_toward`), env);
    assert.equal(clip?.status, 200);
    assert.equal(clip?.headers.get('content-type'), 'audio/mp4');
    assert.equal(clip?.headers.get('cache-control'), 'public, max-age=31536000, immutable');
    assert.equal(clip?.headers.get('etag'), `"${sha(m4a(4096, 2))}"`);
    assert.equal(sha(new Uint8Array(await clip!.arrayBuffer())), sha(m4a(4096, 2)));
    for (const path of ['clips/zh/turn_left', 'clips/fr/turn_left', 'clips/en/Turn-Left', 'clips/en', 'other']) {
      assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/${path}`), env))?.status, 404, path);
    }

    const count = () => sqlite.prepare('SELECT import_count AS c FROM voice_packs').get().c;
    assert.equal(count(), 0, 'Viewing a manifest is not an import');
    const imported = await handleVoicePacks(call(`/api/voice-packs/${pack.code}/import`, { method: 'POST' }), env);
    assert.equal(imported?.status, 200);
    assert.equal(count(), 1);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/import`), env))?.status, 405);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/import`, {
      method: 'POST', headers: { origin: 'https://evil.test', 'x-waybi-client': 'web' },
    }), env))?.status, 403);

    const mine = await handleVoicePacks(call('/api/voice-packs/mine', { token: users.alice }), env);
    const listed = await mine!.json();
    assert.equal(listed.limit, 5);
    assert.deepEqual(listed.packs.map((p) => [p.code, p.importCount]), [[pack.code, 1]]);
    const bobs = await (await handleVoicePacks(call('/api/voice-packs/mine', { token: users.bob }), env))!.json();
    assert.deepEqual(bobs.packs, []);
    assert.equal((await handleVoicePacks(call('/api/voice-packs/mine'), env))?.status, 401);
    assert.equal((await handleVoicePacks(call('/api/voice-packs/mine', { method: 'POST' }), env))?.status, 405);
  } finally { sqlite.close(); }
});

test('sharing requires a signed-in Plus member, a same-site client and consent', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const status = async (request: Request) => {
      const response = (await handleVoicePacks(request, env))!;
      return [response.status, (await response.json()).code];
    };
    assert.deepEqual(await status(uploadRequest(null, twoClips)), [401, 'SIGN_IN_REQUIRED']);
    assert.deepEqual(await status(uploadRequest(users.carol, twoClips)), [403, 'PLUS_REQUIRED']);
    assert.deepEqual(await status(uploadRequest(users.alice, twoClips, { consent: 'yes' })), [400, 'CONSENT_REQUIRED']);
    assert.deepEqual(await status(uploadRequest(users.alice, twoClips, {
      headers: { 'x-waybi-client': 'web', origin: 'https://evil.test' },
    })), [403, 'INVALID_REQUEST']);
    assert.deepEqual(await status(uploadRequest(users.alice, twoClips, { headers: { 'x-waybi-client': '' } })), [403, 'INVALID_REQUEST']);
    assert.deepEqual(await status(uploadRequest(users.alice, twoClips, { headers: { origin: 'https://waybi.co' } })), [403, 'INVALID_REQUEST']);
    assert.equal(r2.objects.size, 0);
    assert.equal((await handleVoicePacks(call('/api/voice-packs'), env))?.status, 405);
  } finally { sqlite.close(); }
});

test('uploads are validated clip by clip and nothing is stored on failure', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const rejects = async (request: Request, status: number, code: string) => {
      const response = (await handleVoicePacks(request, env))!;
      assert.equal(response.status, status, code);
      assert.equal((await response.json()).code, code);
    };
    const one = (clip: Partial<Clip> = {}) => [{ language: 'en', phraseId: 'turn_left', ...clip }];
    await rejects(uploadRequest(users.alice, one({ phraseId: 'Turn-Left' })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ phraseId: 'x'.repeat(49) })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ language: 'fr' })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ contentType: 'audio/wav' })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ bytes: new Uint8Array(4096).fill(9) })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ bytes: m4a(100) })), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one({ bytes: m4a(VOICE_PACK_LIMITS.maxClipBytes + 1) })), 413, 'VOICE_PACK_TOO_LARGE');
    await rejects(uploadRequest(users.alice, one({ claim: { sha256: 'a'.repeat(64) } })), 400, 'CLIP_INTEGRITY');
    await rejects(uploadRequest(users.alice, one({ claim: { bytes: 1 } })), 400, 'CLIP_INTEGRITY');
    await rejects(uploadRequest(users.alice, [...one(), ...one()]), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, one(), { extra: { 'clip:en:merge': new Blob([m4a()]) } }), 400, 'INVALID_CLIP');
    await rejects(uploadRequest(users.alice, []), 400, 'INVALID_REQUEST');
    await rejects(uploadRequest(users.alice, one(), { name: '' }), 400, 'INVALID_REQUEST');
    await rejects(uploadRequest(users.alice, one(), { name: 'x'.repeat(41) }), 400, 'INVALID_REQUEST');
    await rejects(uploadRequest(users.alice, one(), { name: '<b>me</b>' }), 400, 'INVALID_REQUEST');
    await rejects(uploadRequest(users.alice, one(), { manifest: '{oops' }), 400, 'INVALID_REQUEST');
    const tooMany = Array.from({ length: VOICE_PACK_LIMITS.maxClips + 1 }, (_, i) => ({ language: 'en', phraseId: `p${i}` }));
    await rejects(uploadRequest(users.alice, tooMany), 400, 'INVALID_REQUEST');
    const missing = uploadRequest(users.alice, one());
    const form = await missing.formData();
    form.delete('clip:en:turn_left');
    const headers = new Headers(missing.headers);
    headers.delete('content-type');
    await rejects(new Request(missing.url, { method: 'POST', headers, body: form }), 400, 'INVALID_CLIP');
    const big = Array.from({ length: 33 }, (_, i) => ({ language: 'en', phraseId: `p${i}`, bytes: m4a(VOICE_PACK_LIMITS.maxClipBytes, i) }));
    await rejects(uploadRequest(users.alice, big), 413, 'VOICE_PACK_TOO_LARGE');
    await rejects(new Request('https://waybi.co/api/voice-packs', {
      method: 'POST', headers: { 'x-waybi-client': 'mobile', cookie: `waybi_session=${users.alice}`,
        'content-length': String(10 * 1024 * 1024) }, body: 'x',
    }), 413, 'VOICE_PACK_TOO_LARGE');
    await rejects(new Request('https://waybi.co/api/voice-packs', {
      method: 'POST', headers: { 'x-waybi-client': 'mobile', cookie: `waybi_session=${users.alice}`,
        'content-type': 'multipart/form-data; boundary=x' }, body: 'not multipart',
    }), 400, 'INVALID_REQUEST');
    assert.equal(r2.objects.size, 0);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM voice_packs').get().c, 0);

    const aac = new Uint8Array(1024).fill(0);
    aac.set([0xff, 0xf1], 0);
    const pack = await share(env, users.alice, [{ language: 'en', phraseId: 'merge', bytes: aac, contentType: 'audio/aac' }]);
    assert.deepEqual(pack.languages, ['en']);
    const name = await share(env, users.alice, [{ language: 'zh', phraseId: 'merge' }]);
    assert.equal(name.name, 'Grandma');
  } finally { sqlite.close(); }
});

test('a storage failure mid-upload removes the clips already written', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    r2.failPut = true;
    const response = (await handleVoicePacks(uploadRequest(users.alice, twoClips), env))!;
    assert.equal(response.status, 503);
    assert.equal((await response.json()).code, 'VOICE_SHARING_UNAVAILABLE');
    assert.equal(r2.objects.size, 0);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM voice_packs').get().c, 0);
  } finally { sqlite.close(); }
});

test('each member shares at most five active packs; revoking frees a slot', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const codes = [];
    for (let i = 0; i < 5; i++) codes.push((await share(env, users.alice)).code);
    const sixth = (await handleVoicePacks(uploadRequest(users.alice, twoClips), env))!;
    assert.equal(sixth.status, 409);
    assert.equal((await sixth.json()).code, 'VOICE_PACK_LIMIT');
    assert.equal(r2.objects.size, 10, 'The refused upload stored nothing');
    assert.equal((await share(env, users.bob)).clipCount, 2, 'Limits are per member');

    // Another device filled the last slot while this upload was in flight.
    sqlite.prepare('UPDATE voice_packs SET revoked_at = 1 WHERE share_code = ?').run(codes[0]);
    const racing = uploadRequest(users.alice, twoClips);
    const db = env.USER_DB;
    let first = true;
    const racingEnv = { ...env, USER_DB: { ...db, prepare(sql: string) {
      if (first && sql.startsWith('INSERT INTO voice_packs')) {
        first = false;
        sqlite.prepare('UPDATE voice_packs SET revoked_at = NULL WHERE share_code = ?').run(codes[0]);
      }
      return db.prepare(sql);
    } } };
    const raced = (await handleVoicePacks(racing, racingEnv))!;
    assert.equal(raced.status, 409);
    assert.equal(r2.objects.size, 12);

    const revoked = await handleVoicePacks(call(`/api/voice-packs/${codes[1]}`, { method: 'DELETE', token: users.alice }), env);
    assert.equal(revoked?.status, 200);
    assert.equal((await share(env, users.alice)).clipCount, 2);
  } finally { sqlite.close(); }
});

test('only the owner can revoke; revoked packs and their clips are gone', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const pack = await share(env, users.alice);
    const bobs = await share(env, users.bob);
    const del = (code: string, token?: string, headers = {}) =>
      handleVoicePacks(call(`/api/voice-packs/${code}`, { method: 'DELETE', token, headers }), env);
    assert.equal((await del(pack.code))?.status, 401);
    assert.equal((await del(pack.code, users.bob))?.status, 404);
    assert.equal((await del(pack.code, users.alice, { origin: 'https://evil.test', 'x-waybi-client': 'web' }))?.status, 403);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}`, { method: 'PUT', token: users.alice }), env))?.status, 405);

    r2.failDelete = true;
    const partial = (await del(pack.code, users.alice))!;
    assert.equal(partial.status, 503);
    assert.equal((await partial.json()).code, 'VOICE_PACK_PURGE_FAILED');
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}`), env))?.status, 404,
      'A revoked pack stops being served even before its clips are gone');
    r2.failDelete = false;
    assert.equal((await del(pack.code, users.alice))?.status, 200, 'Revoking again finishes the purge');
    assert.deepEqual([...r2.objects.keys()].filter((key) => key.includes('/alice/')), []);
    assert.equal([...r2.objects.keys()].filter((key) => key.includes('/bob/')).length, 2);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/clips/en/turn_left`), env))?.status, 404);
    const mine = await (await handleVoicePacks(call('/api/voice-packs/mine', { token: users.alice }), env))!.json();
    assert.deepEqual(mine.packs, []);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/import`, { method: 'POST' }), env))?.status, 404);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${bobs.code}`), env))?.status, 200);

    // A stored object that went missing reads as unavailable, not a crash.
    r2.objects.clear();
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${bobs.code}/clips/en/turn_left`), env))?.status, 404);
  } finally { sqlite.close(); }
});

test('account deletion removes shared recordings before the account, and fails safe', async () => {
  const { sqlite, env, r2, users } = setup();
  try {
    const pack = await share(env, users.alice);
    await share(env, users.bob);
    // An interrupted earlier upload left an object without a pack row.
    r2.objects.set('voice-packs/alice/orphan/en/merge', { bytes: m4a(), options: {} });
    const deletion = () => handleAccount(new Request('https://waybi.co/api/auth/delete', {
      method: 'POST',
      headers: { 'x-waybi-client': 'mobile', 'content-type': 'application/json', cookie: `waybi_session=${users.alice}` },
      body: JSON.stringify({ email: 'alice@waybi.test', confirmation: 'DELETE' }),
    }), env);

    r2.failList = true;
    const failed = (await deletion())!;
    assert.equal(failed.status, 503);
    assert.equal((await failed.json()).code, 'VOICE_PACK_DELETE_FAILED');
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM users WHERE id = ?').get('alice').c, 1);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM voice_packs WHERE owner_id = ? AND revoked_at IS NULL').get('alice').c, 0,
      'A failed deletion still stops sharing');

    r2.failList = false;
    const deleted = (await deletion())!;
    assert.equal(deleted.status, 200);
    assert.deepEqual([...r2.objects.keys()].filter((key) => key.startsWith('voice-packs/alice/')), []);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM voice_packs WHERE owner_id = ?').get('alice').c, 0);
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS c FROM voice_packs WHERE owner_id = ?').get('bob').c, 1);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}`), env))?.status, 404);

    // Without the bucket binding, members who never shared can still delete.
    assert.equal(await purgeVoicePacksForDeletion({}, env.USER_DB, 'carol'), true);
    assert.equal(await purgeVoicePacksForDeletion({}, env.USER_DB, 'bob'), false);
  } finally { sqlite.close(); }
});

test('lookups are rate limited and a missing bucket is a clear 503', async () => {
  const { sqlite, env, rate, users } = setup();
  try {
    const pack = await share(env, users.alice);
    assert.deepEqual(rate.keys, ['voice-write:alice']);
    let allowed = 3;
    env.RATE_LIMIT_VOICE = limiter(() => allowed-- > 0);
    for (let i = 0; i < 4; i++) {
      await handleVoicePacks(call(`/api/voice-packs/${pack.code}/clips/en/turn_left`), env);
    }
    assert.deepEqual(env.RATE_LIMIT_VOICE.keys, [], 'Clips of a valid pack are never charged');
    assert.equal((await handleVoicePacks(call('/api/voice-packs/AAAAAAAAAA'), env))?.status, 404);
    assert.equal((await handleVoicePacks(call('/api/voice-packs/not-a-code'), env))?.status, 404);
    assert.equal((await handleVoicePacks(call('/api/voice-packs/AAAAAAAAAA/clips/en/turn_left'), env))?.status, 404);
    const limited = (await handleVoicePacks(call(`/api/voice-packs/${pack.code}`), env))!;
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get('retry-after'), '60');
    assert.equal((await limited.json()).code, 'RATE_LIMITED');
    assert.equal((await handleVoicePacks(call('/api/voice-packs/AAAAAAAAAA/clips/en/turn_left'), env))?.status, 429);
    assert.equal((await handleVoicePacks(call('/api/voice-packs/bad'), env))?.status, 429);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}/import`, { method: 'POST' }), env))?.status, 429);
    assert.equal((await handleVoicePacks(uploadRequest(users.alice, twoClips), env))?.status, 429);
    assert.equal((await handleVoicePacks(call(`/api/voice-packs/${pack.code}`, { method: 'DELETE', token: users.alice }), env))?.status, 429);
    assert.ok(env.RATE_LIMIT_VOICE.keys.every((key) => /^voice-(lookup:203\.0\.113\.7|write:alice)$/.test(key)));

    for (const missing of [{ ...env, VOICE_PACKS: undefined }, { ...env, USER_DB: undefined }]) {
      const response = (await handleVoicePacks(call(`/api/voice-packs/${pack.code}`), missing))!;
      assert.equal(response.status, 503);
      assert.equal((await response.json()).code, 'VOICE_SHARING_UNAVAILABLE');
    }
    assert.equal(await handleVoicePacks(call('/api/voice-packsx'), env), null);
  } finally { sqlite.close(); }
});

test('the Worker routes voice pack API calls and share links', async () => {
  const { sqlite, env, users } = setup();
  try {
    const pack = await share(env, users.alice);
    const ctx = { waitUntil() {} };
    const api = await worker.fetch(call(`/api/voice-packs/${pack.code}`), env, ctx);
    assert.equal(api.status, 200);
    const missing = await worker.fetch(call(`/api/voice-packs/${pack.code}`), {}, ctx);
    assert.equal((await missing.json()).code, 'VOICE_SHARING_UNAVAILABLE');
    const page = await worker.fetch(call(`/voice/${pack.code}`), { ...env, ASSETS: { fetch: () => assert.fail('No asset lookup') } }, ctx);
    assert.equal(page.status, 200);
    assert.match(page.headers.get('content-type') || '', /text\/html/);
    const html = await page.text();
    assert.ok(html.includes(`${pack.code.slice(0, 5)} ${pack.code.slice(5)}`));
    assert.match(html, /Open the Waybi app/);
    assert.match(html, /使用分享的语音/);
    const malformed = await worker.fetch(call('/voice/%3Cscript%3E'), env, ctx);
    assert.equal(malformed.status, 404);
    assert.doesNotMatch(await malformed.text(), /<script>/);
    const head = voicePackLandingPage(call(`/voice/${pack.code}/`, { method: 'HEAD' }))!;
    assert.equal(head.status, 200);
    assert.equal(await head.text(), '');
    assert.equal(voicePackLandingPage(call(`/voice/${pack.code}`, { method: 'POST' })), null);
    assert.equal(voicePackLandingPage(call('/voices/x')), null);
  } finally { sqlite.close(); }
});

test('share codes are unambiguous and links are accepted where a code is', () => {
  const codes = new Set(Array.from({ length: 200 }, () => generateShareCode()));
  assert.equal(codes.size, 200);
  for (const code of codes) assert.match(code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{10}$/);
  // Bytes outside the unbiased range are skipped, not folded onto the alphabet.
  let calls = 0;
  const biased = generateShareCode((bytes) => {
    calls++;
    return bytes.fill(calls === 1 ? 255 : 0);
  });
  assert.equal(biased, '2222222222');
  assert.equal(normalizeShareCode(' abcde-fghjk '), 'ABCDEFGHJK');
  assert.equal(normalizeShareCode('https://waybi.co/voice/ABCDE FGHJK?x=1'), 'ABCDEFGHJK');
  assert.equal(normalizeShareCode('ABCDEFGHJ0'), null, 'Zero is not in the alphabet');
  assert.equal(normalizeShareCode(''), null);
  assert.equal(looksLikeAudio(m4a(), 'audio/x-m4a'), true);
  assert.equal(looksLikeAudio(new Uint8Array([0xff, 0xf9, 0]), 'audio/aac'), true);
  assert.equal(looksLikeAudio(new Uint8Array([0x49, 0x44, 0x33]), 'audio/aac'), false);
});
