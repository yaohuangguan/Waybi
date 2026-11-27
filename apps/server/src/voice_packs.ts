import { allowRequest, clientIp } from './abuse_guard.ts';
import { clientKind } from './brand_compat.ts';
import { userFromRequest, userHasPlus } from './auth.ts';

/**
 * Shared custom navigation voices ("voice packs").
 *
 * A Waybi Plus member uploads their recorded guidance phrases once and gets
 * a share code. Anyone with the code can download the clips and use them in
 * the app; there is no public gallery or search. Clips live in R2 under the
 * owner's prefix, so revoking a pack or deleting the account removes every
 * object even if an earlier upload was interrupted.
 */

export const VOICE_PACK_LIMITS = {
  maxClipBytes: 256 * 1024,
  minClipBytes: 512,
  maxTotalBytes: 8 * 1024 * 1024,
  maxClips: 200,
  maxNameLength: 40,
  maxActivePacks: 5,
} as const;

/** Formats the app records (AAC-LC in an .m4a container) and plain ADTS AAC. */
export const VOICE_CLIP_TYPES = ['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac'] as const;
export const VOICE_PACK_LANGUAGES = ['en', 'zh'] as const;

/** No 0/O, 1/I/L: codes are typed from a screen or read aloud. */
export const SHARE_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const SHARE_CODE_LENGTH = 10;
const SHARE_CODE_PATTERN = new RegExp(`^[${SHARE_CODE_ALPHABET}]{${SHARE_CODE_LENGTH}}$`);
const PHRASE_ID = /^[a-z0-9_]{1,48}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const PUBLIC_ORIGIN = 'https://waybi.co';

export interface VoicePackBucket {
  put(key: string, value: ArrayBuffer | Uint8Array, options?: Record<string, unknown>): Promise<unknown>;
  get(key: string): Promise<{ body: ReadableStream | null; httpEtag?: string; size?: number } | null>;
  delete(keys: string | string[]): Promise<void>;
  list(options: { prefix: string; cursor?: string; limit?: number }): Promise<{
    objects: Array<{ key: string }>; truncated: boolean; cursor?: string;
  }>;
}

type ClipMeta = { bytes: number; contentType: string; sha256: string };
type Manifest = Record<string, Record<string, ClipMeta>>;

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      ...headers,
    },
  });
}

function failure(status: number, error: string, code: string, extra: Record<string, unknown> = {}) {
  return json({ error, code, ...extra }, status);
}

const unavailable = () =>
  failure(503, 'Voice sharing is temporarily unavailable. Please try again later.', 'VOICE_SHARING_UNAVAILABLE');
const notFound = () =>
  failure(404, 'This voice pack is not available. Check the code, or ask for a new one.', 'VOICE_PACK_NOT_FOUND');
const rateLimited = () => json(
  { error: 'Too many requests. Please retry shortly.', code: 'RATE_LIMITED', retryAfter: 60 },
  429, { 'retry-after': '60' },
);

function bucket(env): VoicePackBucket | null {
  const binding = env?.VOICE_PACKS;
  return binding && typeof binding.put === 'function' && typeof binding.get === 'function' ? binding : null;
}

/** Upper-cases and strips spaces/dashes; accepts a full share link too. */
export function normalizeShareCode(value: string): string | null {
  let raw = String(value || '').trim();
  const link = raw.match(/\/voice\/([^/?#]+)/i);
  if (link) raw = link[1];
  const code = raw.replace(/[\s-]+/g, '').toUpperCase();
  return SHARE_CODE_PATTERN.test(code) ? code : null;
}

export function generateShareCode(random: (bytes: Uint8Array) => Uint8Array = (b) => crypto.getRandomValues(b)): string {
  const alphabet = SHARE_CODE_ALPHABET;
  // Rejection sampling keeps every character equally likely.
  const limit = 256 - (256 % alphabet.length);
  let code = '';
  while (code.length < SHARE_CODE_LENGTH) {
    for (const byte of random(new Uint8Array(16))) {
      if (byte < limit && code.length < SHARE_CODE_LENGTH) code += alphabet[byte % alphabet.length];
    }
  }
  return code;
}

export function voicePackUrl(code: string) {
  return `${PUBLIC_ORIGIN}/voice/${code}`;
}

function ownerPrefix(ownerId: string) {
  return `voice-packs/${ownerId}/`;
}

function clipKey(ownerId: string, packId: string, language: string, phraseId: string) {
  return `${ownerPrefix(ownerId)}${packId}/${language}/${phraseId}`;
}

async function sha256Hex(bytes: ArrayBuffer) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** A light content check: an MP4/M4A file box or an ADTS AAC frame. */
export function looksLikeAudio(bytes: Uint8Array, contentType: string) {
  if (contentType === 'audio/aac') return bytes.length > 2 && bytes[0] === 0xff && (bytes[1] & 0xf6) === 0xf0;
  return bytes.length > 12 && String.fromCharCode(...bytes.subarray(4, 8)) === 'ftyp';
}

/** Deletes every object under [prefix]. Throws if R2 fails. */
async function purgePrefix(store: VoicePackBucket, prefix: string) {
  let cursor: string | undefined;
  do {
    const page = await store.list({ prefix, cursor, limit: 1000 });
    const keys = page.objects.map((object) => object.key);
    if (keys.length) await store.delete(keys);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

/**
 * Removes a deleted account's shared clips before D1 cascades its rows
 * away. Returns false if they could not be removed: the account deletion
 * must then fail rather than report success and leave recordings behind.
 */
export async function purgeVoicePacksForDeletion(env, db, userId: string): Promise<boolean> {
  const row = await db.prepare('SELECT COUNT(*) AS packs FROM voice_packs WHERE owner_id = ?').bind(userId).first();
  if (!Number(row?.packs || 0)) return true;
  const store = bucket(env);
  if (!store) return false;
  try {
    // Nothing is served any more, even if the deletion stops at a later step.
    await db.prepare('UPDATE voice_packs SET revoked_at = ? WHERE owner_id = ? AND revoked_at IS NULL')
      .bind(Date.now(), userId).run();
    await purgePrefix(store, ownerPrefix(userId));
    return true;
  } catch (error) {
    console.error(JSON.stringify({ level: 'error', event: 'voice_pack_purge_failed',
      message: String((error as Error)?.message || error).slice(0, 200) }));
    return false;
  }
}

function publicPack(row) {
  const manifest: Manifest = JSON.parse(row.manifest_json);
  return {
    code: row.share_code,
    name: row.display_name,
    languages: JSON.parse(row.languages),
    clipCount: Number(row.clip_count),
    totalBytes: Number(row.total_bytes),
    createdAt: Number(row.created_at),
    importCount: Number(row.import_count),
    url: voicePackUrl(row.share_code),
    clips: manifest,
  };
}

function ownedPack(row) {
  const { clips: _clips, ...pack } = publicPack(row);
  return pack;
}

async function activePack(db, code: string) {
  return db.prepare('SELECT * FROM voice_packs WHERE share_code = ? AND revoked_at IS NULL').bind(code).first();
}

function crossSiteWrite(request: Request) {
  const origin = request.headers.get('origin');
  const client = clientKind(request);
  return (origin && origin !== new URL(request.url).origin) ||
    !['web', 'mobile'].includes(client || '') || (client === 'mobile' && Boolean(origin));
}

function validName(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const name = value.normalize('NFC').replace(/\s+/g, ' ').trim();
  // eslint-disable-next-line no-control-regex
  if (!name || [...name].length > VOICE_PACK_LIMITS.maxNameLength || /[\u0000-\u001f\u007f<>]/.test(name)) return null;
  return name;
}

interface UploadClip { language: string; phraseId: string; contentType: string; bytes?: number; sha256?: string }

async function upload(request: Request, env, db, store: VoicePackBucket, now: () => number) {
  if (crossSiteWrite(request)) return failure(403, 'Invalid request origin', 'INVALID_REQUEST');
  const user = await userFromRequest(db, request);
  if (!user) return failure(401, 'Sign in to share your voice', 'SIGN_IN_REQUIRED');
  if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-write:${user.id}`)) return rateLimited();
  if (!await userHasPlus(db, user.id)) {
    return failure(403, 'Sharing your voice needs Waybi Plus', 'PLUS_REQUIRED');
  }
  const declared = Number(request.headers.get('content-length'));
  // Multipart framing adds a little to the clip bytes.
  if (Number.isFinite(declared) && declared > VOICE_PACK_LIMITS.maxTotalBytes + 512 * 1024) {
    return failure(413, 'This voice pack is too large to share', 'VOICE_PACK_TOO_LARGE');
  }
  const active = await db.prepare('SELECT COUNT(*) AS packs FROM voice_packs WHERE owner_id = ? AND revoked_at IS NULL')
    .bind(user.id).first();
  if (Number(active?.packs || 0) >= VOICE_PACK_LIMITS.maxActivePacks) {
    return failure(409, 'You already share 5 voice packs. Revoke one to share another.', 'VOICE_PACK_LIMIT');
  }
  let form: FormData;
  try { form = await request.formData(); }
  catch { return failure(400, 'Invalid voice pack upload', 'INVALID_REQUEST'); }
  let manifest;
  try { manifest = JSON.parse(String(form.get('manifest') ?? '')); }
  catch { return failure(400, 'Invalid voice pack manifest', 'INVALID_REQUEST'); }
  if (manifest?.consent !== true) {
    return failure(400, 'Confirm this is your own voice and that you agree to share it', 'CONSENT_REQUIRED');
  }
  const name = validName(manifest?.name);
  if (!name) return failure(400, `Give your voice a name of up to ${VOICE_PACK_LIMITS.maxNameLength} characters`, 'INVALID_REQUEST');
  const clips: UploadClip[] = Array.isArray(manifest?.clips) ? manifest.clips : [];
  if (!clips.length || clips.length > VOICE_PACK_LIMITS.maxClips) {
    return failure(400, `A voice pack holds 1 to ${VOICE_PACK_LIMITS.maxClips} recordings`, 'INVALID_REQUEST');
  }
  const prepared: Array<{ language: string; phraseId: string; contentType: string; bytes: Uint8Array; sha256: string }> = [];
  const seen = new Set<string>();
  let total = 0;
  for (const clip of clips) {
    const language = String(clip?.language ?? '');
    const phraseId = String(clip?.phraseId ?? '');
    const contentType = String(clip?.contentType ?? '').toLowerCase();
    if (!(VOICE_PACK_LANGUAGES as readonly string[]).includes(language) || !PHRASE_ID.test(phraseId) ||
        !(VOICE_CLIP_TYPES as readonly string[]).includes(contentType)) {
      return failure(400, 'A recording in this voice pack is not supported', 'INVALID_CLIP');
    }
    const key = `${language}:${phraseId}`;
    if (seen.has(key)) return failure(400, 'Each phrase can only be shared once', 'INVALID_CLIP');
    seen.add(key);
    const part = form.get(`clip:${key}`);
    if (!part || typeof part === 'string') return failure(400, 'A recording is missing from the upload', 'INVALID_CLIP');
    const bytes = new Uint8Array(await (part as Blob).arrayBuffer());
    if (bytes.length > VOICE_PACK_LIMITS.maxClipBytes) {
      return failure(413, 'A recording is too long to share', 'VOICE_PACK_TOO_LARGE');
    }
    if (bytes.length < VOICE_PACK_LIMITS.minClipBytes || !looksLikeAudio(bytes, contentType)) {
      return failure(400, 'A recording in this voice pack is not supported', 'INVALID_CLIP');
    }
    total += bytes.length;
    if (total > VOICE_PACK_LIMITS.maxTotalBytes) {
      return failure(413, 'This voice pack is too large to share', 'VOICE_PACK_TOO_LARGE');
    }
    const sha256 = await sha256Hex(bytes.slice().buffer);
    const claimed = clip?.sha256 == null ? null : String(clip.sha256).toLowerCase();
    if ((claimed != null && (!SHA256.test(claimed) || claimed !== sha256)) ||
        (clip?.bytes != null && Number(clip.bytes) !== bytes.length)) {
      return failure(400, 'A recording was damaged during upload. Please try again.', 'CLIP_INTEGRITY');
    }
    prepared.push({ language, phraseId, contentType, bytes, sha256 });
  }
  const extra = [...form.keys()].find((field) => field !== 'manifest' && !seen.has(field.replace(/^clip:/, '')));
  if (extra) return failure(400, 'The upload has a recording that is not in its manifest', 'INVALID_CLIP');

  const id = crypto.randomUUID();
  const stored: Manifest = {};
  const written: string[] = [];
  try {
    for (const clip of prepared) {
      const key = clipKey(user.id, id, clip.language, clip.phraseId);
      await store.put(key, clip.bytes, {
        httpMetadata: { contentType: clip.contentType, cacheControl: 'public, max-age=31536000, immutable' },
        customMetadata: { sha256: clip.sha256 },
      });
      written.push(key);
      (stored[clip.language] ??= {})[clip.phraseId] = {
        bytes: clip.bytes.length, contentType: clip.contentType, sha256: clip.sha256,
      };
    }
  } catch (error) {
    await store.delete(written).catch(() => {});
    console.error(JSON.stringify({ level: 'error', event: 'voice_pack_upload_failed',
      message: String((error as Error)?.message || error).slice(0, 200) }));
    return unavailable();
  }
  const languages = VOICE_PACK_LANGUAGES.filter((language) => stored[language]);
  for (let attempt = 0; attempt < 3; attempt++) {
    const code = generateShareCode();
    try {
      // The active-pack limit is re-checked atomically with the insert.
      const result = await db.prepare(`INSERT INTO voice_packs
          (id, share_code, owner_id, display_name, languages, manifest_json, clip_count, total_bytes, created_at)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
        WHERE (SELECT COUNT(*) FROM voice_packs WHERE owner_id = ? AND revoked_at IS NULL) < ?`)
        .bind(id, code, user.id, name, JSON.stringify(languages), JSON.stringify(stored), prepared.length, total,
          now(), user.id, VOICE_PACK_LIMITS.maxActivePacks)
        .run();
      if (!Number(result?.meta?.changes ?? 0)) {
        await purgePrefix(store, `${ownerPrefix(user.id)}${id}/`).catch(() => {});
        return failure(409, 'You already share 5 voice packs. Revoke one to share another.', 'VOICE_PACK_LIMIT');
      }
      const row = await db.prepare('SELECT * FROM voice_packs WHERE id = ?').bind(id).first();
      return json({ pack: ownedPack(row) }, 201);
    } catch (error) {
      // A share-code collision is astronomically unlikely; anything else is a real failure.
      if (attempt < 2 && /UNIQUE/i.test(String((error as Error)?.message))) continue;
      await purgePrefix(store, `${ownerPrefix(user.id)}${id}/`).catch(() => {});
      throw error;
    }
  }
  return unavailable();
}

async function revoke(request: Request, env, db, store: VoicePackBucket, code: string, now: () => number) {
  if (crossSiteWrite(request)) return failure(403, 'Invalid request origin', 'INVALID_REQUEST');
  const user = await userFromRequest(db, request);
  if (!user) return failure(401, 'Sign in to manage your shared voices', 'SIGN_IN_REQUIRED');
  if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-write:${user.id}`)) return rateLimited();
  const row = await db.prepare('SELECT id, revoked_at FROM voice_packs WHERE share_code = ? AND owner_id = ?')
    .bind(code, user.id).first();
  if (!row) return notFound();
  // Stop serving first; a failed purge is retried by revoking again.
  if (row.revoked_at == null) {
    await db.prepare('UPDATE voice_packs SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL').bind(now(), row.id).run();
  }
  try {
    await purgePrefix(store, `${ownerPrefix(user.id)}${row.id}/`);
  } catch {
    return failure(503, 'The pack was revoked, but some recordings could not be removed yet. Please try again.',
      'VOICE_PACK_PURGE_FAILED');
  }
  return json({ ok: true });
}

async function clip(request: Request, env, db, store: VoicePackBucket, code: string, language: string, phraseId: string) {
  const row = await activePack(db, code);
  const meta: ClipMeta | undefined = row ? JSON.parse(row.manifest_json)?.[language]?.[phraseId] : undefined;
  if (!row || !meta) {
    // Only misses count, so a real import of many clips is never throttled
    // while guessing codes is.
    if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-lookup:${clientIp(request)}`)) return rateLimited();
    return notFound();
  }
  const object = await store.get(clipKey(row.owner_id, row.id, language, phraseId));
  if (!object?.body) return notFound();
  return new Response(object.body, {
    headers: {
      'content-type': meta.contentType,
      'content-length': String(meta.bytes),
      // Clips never change within a pack: a new recording is a new pack.
      'cache-control': 'public, max-age=31536000, immutable',
      etag: `"${meta.sha256}"`,
      'x-content-sha256': meta.sha256,
      'access-control-allow-origin': '*',
      'x-content-type-options': 'nosniff',
    },
  });
}

/** Handles `/api/voice-packs…`; returns null for any other path. */
export async function handleVoicePacks(request: Request, env, now: () => number = Date.now): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== '/api/voice-packs' && !url.pathname.startsWith('/api/voice-packs/')) return null;
  const db = env?.USER_DB;
  const store = bucket(env);
  if (!db || !store) return unavailable();
  const segments = url.pathname.split('/').slice(3).map((segment) => decodeURIComponent(segment));
  if (!segments.length) {
    if (request.method === 'POST') return upload(request, env, db, store, now);
    return failure(405, 'Method not allowed', 'INVALID_REQUEST');
  }
  if (segments.length === 1 && segments[0] === 'mine') {
    if (request.method !== 'GET') return failure(405, 'Method not allowed', 'INVALID_REQUEST');
    const user = await userFromRequest(db, request);
    if (!user) return failure(401, 'Sign in to see your shared voices', 'SIGN_IN_REQUIRED');
    const { results } = await db.prepare(`SELECT * FROM voice_packs WHERE owner_id = ? AND revoked_at IS NULL
      ORDER BY created_at DESC`).bind(user.id).all();
    return json({ packs: (results || []).map(ownedPack), limit: VOICE_PACK_LIMITS.maxActivePacks });
  }
  const code = normalizeShareCode(segments[0]);
  if (!code) {
    if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-lookup:${clientIp(request)}`)) return rateLimited();
    return notFound();
  }
  if (segments.length === 1) {
    if (request.method === 'DELETE') return revoke(request, env, db, store, code, now);
    if (request.method !== 'GET') return failure(405, 'Method not allowed', 'INVALID_REQUEST');
    if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-lookup:${clientIp(request)}`)) return rateLimited();
    const row = await activePack(db, code);
    return row ? json({ pack: publicPack(row) }) : notFound();
  }
  if (segments.length === 2 && segments[1] === 'import') {
    if (request.method !== 'POST') return failure(405, 'Method not allowed', 'INVALID_REQUEST');
    if (crossSiteWrite(request)) return failure(403, 'Invalid request origin', 'INVALID_REQUEST');
    if (!await allowRequest(env, 'RATE_LIMIT_VOICE', `voice-lookup:${clientIp(request)}`)) return rateLimited();
    const result = await db.prepare('UPDATE voice_packs SET import_count = import_count + 1 WHERE share_code = ? AND revoked_at IS NULL')
      .bind(code).run();
    return Number(result?.meta?.changes ?? 0) ? json({ ok: true }) : notFound();
  }
  if (segments.length === 4 && segments[1] === 'clips') {
    if (request.method !== 'GET') return failure(405, 'Method not allowed', 'INVALID_REQUEST');
    const [, , language, phraseId] = segments;
    if (!(VOICE_PACK_LANGUAGES as readonly string[]).includes(language) || !PHRASE_ID.test(phraseId)) return notFound();
    return clip(request, env, db, store, code, language, phraseId);
  }
  return notFound();
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

/** `GET /voice/:code`: where a shared link lands outside the app. */
export function voicePackLandingPage(request: Request): Response | null {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/voice\/([^/]+)\/?$/);
  if (!match || !['GET', 'HEAD'].includes(request.method)) return null;
  const code = normalizeShareCode(decodeURIComponent(match[1]));
  const shown = code ? escapeHtml(code.replace(/^(.{5})/, '$1 ')) : null;
  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Waybi shared voice</title>
<style>
:root{color-scheme:light dark;--bg:#f7f7f5;--fg:#1c1c1a;--muted:#5c5c57;--card:#fff;--accent:#0f6e56}
@media (prefers-color-scheme:dark){:root{--bg:#141413;--fg:#f2f2ef;--muted:#b4b4ad;--card:#20201e;--accent:#5fd3b0}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,"PingFang SC","Noto Sans SC",sans-serif}
main{max-width:32rem;margin:0 auto;padding:48px 16px}
.card{background:var(--card);border-radius:16px;padding:24px}
.code{font:700 28px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em;color:var(--accent);margin:12px 0 20px}
p{margin:0 0 12px}.muted{color:var(--muted)}
</style>
</head>
<body><main><div class="card">
${shown ? `<p>Someone shared a navigation voice with you.</p>
<p class="code">${shown}</p>
<p>Open the Waybi app, go to <strong>Profile → My navigation voice → Use a shared voice</strong>, and enter this code.</p>
<p lang="zh-CN">有人与你分享了一个导航语音。打开 Waybi App，进入“我的 → 我的导航语音 → 使用分享的语音”，输入上面的代码即可。</p>`
    : `<p>This voice link is not valid. Ask for the code again.</p>
<p lang="zh-CN">这个语音链接无效，请向对方重新索取代码。</p>`}
<p class="muted">Don’t have Waybi yet? Get it from <a href="https://waybi.co/">waybi.co</a>.</p>
</div></main></body>
</html>`;
  return new Response(request.method === 'HEAD' ? null : body, {
    status: code ? 200 : 404,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=300',
      'x-robots-tag': 'noindex',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    },
  });
}
