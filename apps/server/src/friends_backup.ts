type ObjectValue = Record<string, any>;
const MAX_BODY_BYTES = 1_500_000;
const PAGE_SIZE = 200;
const kinds = ['waybi', 'clover', 'sett'];

function object(value: unknown): value is ObjectValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function text(value: unknown, limit: number, optional = false): boolean {
  return optional && value == null || typeof value === 'string' && value.length <= limit;
}
function date(value: unknown, optional = false): boolean {
  return optional && value == null || typeof value === 'string' && value.length < 80 && Number.isFinite(Date.parse(value));
}
function items(value: unknown, max = 32): boolean {
  return Array.isArray(value) && value.length <= max && value.every(item => text(item, 128));
}
function roomPoint(value: unknown): boolean {
  return Array.isArray(value) && value.length === 2 &&
    value.every(coordinate => Number.isFinite(coordinate) && Math.abs(coordinate) <= 4);
}
function journey(value: unknown): boolean {
  return value == null || object(value) && text(value.destinationId, 256) &&
    date(value.departedAt) && date(value.returnAt) && items(value.itemIds) &&
    (value.traveller == null || kinds.includes(value.traveller));
}
function room(value: unknown): boolean {
  if (value == null) return true;
  if (!object(value) || !date(value.startedAt) || !date(value.departedAt, true) ||
      !date(value.arrivedAt, true) || !kinds.includes(value.traveller) ||
      !['room', 'garden'].includes(value.scene)) return false;
  if (value.departureFrom != null && !roomPoint(value.departureFrom)) return false;
  if (value.interactions != null && (!object(value.interactions) ||
      Object.keys(value.interactions).some(kind => !kinds.includes(kind)))) return false;
  for (const interaction of Object.values(value.interactions || {})) {
    if (!object(interaction) || !date(interaction.at) ||
        !roomPoint(interaction.from) || !roomPoint(interaction.to)) return false;
  }
  return true;
}

export function validateFriendsBackup(body: unknown) {
  if (!object(body) || body.schemaVersion !== 1 || !Number.isSafeInteger(body.revision) || body.revision < 0 ||
      !object(body.game) || !Array.isArray(body.game.memories) || body.game.memories.length > 5000 ||
      !items(body.game.selectedItemIds, 2) || !journey(body.game.activeJourney) || !room(body.game.roomLife)) {
    throw new TypeError('Invalid Friends backup');
  }
  const ids = new Set<string>(), tripIds = new Set<string>();
  const memories = body.game.memories.map(memory => {
    if (!object(memory) || !text(memory.id, 256) || !memory.id || !text(memory.destinationId, 256) ||
        !date(memory.returnedAt) || !items(memory.itemIds) || !text(memory.title, 1024) ||
        !text(memory.story, 16000) || !text(memory.souvenir, 2048) ||
        !text(memory.souvenirId, 256, true) || !text(memory.titleZh, 1024, true) ||
        !text(memory.storyZh, 16000, true) || !text(memory.destinationName, 1024, true) ||
        !text(memory.countryCode, 8, true) || !text(memory.sourceTripId, 256, true) ||
        (memory.traveller != null && !kinds.includes(memory.traveller))) throw new TypeError('Invalid travel memory');
    const fields = ['id', 'destinationId', 'returnedAt', 'itemIds', 'title', 'story', 'souvenir',
      'souvenirId', 'traveller', 'titleZh', 'storyZh', 'destinationName', 'countryCode', 'sourceTripId'];
    const clean = Object.fromEntries(fields.filter(key => key in memory).map(key => [key, memory[key]]));
    clean.traveller ??= 'waybi';
    // Empty legacy trip IDs do not accidentally make all old memories collide.
    clean.sourceTripId = clean.sourceTripId || null;
    if (ids.has(clean.id) || clean.sourceTripId && tripIds.has(clean.sourceTripId)) return null;
    ids.add(clean.id); if (clean.sourceTripId) tripIds.add(clean.sourceTripId);
    return { ...clean, returnedAtMs: Date.parse(clean.returnedAt) };
  }).filter(Boolean);
  return { revision: body.revision, memories, state: {
    activeJourney: body.game.activeJourney ?? null, roomLife: body.game.roomLife ?? null,
    selectedItemIds: body.game.selectedItemIds,
  } };
}

export async function readFriendsBackup(db: D1Database, userId: string, cursor: string | null = null) {
  let before = null;
  if (cursor) {
    try {
      before = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(cursor), character => character.charCodeAt(0))));
    } catch { throw new TypeError('Invalid backup cursor'); }
    if (!Array.isArray(before) || before.length !== 2 || !Number.isSafeInteger(before[0]) ||
        !text(before[1], 256)) throw new TypeError('Invalid backup cursor');
  }
  // One read batch is a consistent D1 snapshot. The mobile client restarts its
  // pagination if a later page has another revision.
  const results = await db.batch([
    db.prepare('SELECT revision, state_json, updated_at FROM friends_saves WHERE user_id = ?').bind(userId),
    db.prepare(`SELECT memory_id, returned_at, memory_json FROM friends_memories WHERE user_id = ?
      ${before ? 'AND (returned_at < ? OR (returned_at = ? AND memory_id < ?))' : ''}
      ORDER BY returned_at DESC, memory_id DESC LIMIT ?`).bind(userId,
        ...(before ? [before[0], before[0], before[1]] : []), PAGE_SIZE + 1),
  ]);
  const row = results[0].results[0] as ObjectValue | undefined;
  const entries = results[1].results as ObjectValue[];
  const page = entries.slice(0, PAGE_SIZE), last = page.at(-1);
  return { schemaVersion: 1, revision: row?.revision ?? 0, updatedAt: row?.updated_at ?? null,
    game: row ? { ...JSON.parse(row.state_json), memories: page.map(entry => JSON.parse(entry.memory_json)) } : null,
    nextCursor: entries.length > PAGE_SIZE ? btoa(String.fromCharCode(...new TextEncoder().encode(
      JSON.stringify([last.returned_at, last.memory_id])))) : null };
}

export async function saveFriendsBackup(db: D1Database, userId: string, body: unknown, now = Date.now()) {
  const backup = validateFriendsBackup(body);
  // All writes share a transaction and the same expected revision. A stale
  // device cannot replace room state or erase a memory written by another one.
  const results = await db.batch([
    db.prepare(`INSERT INTO friends_saves(user_id, revision, state_json, updated_at)
      VALUES (?, 0, '{"memories":[]}', ?) ON CONFLICT(user_id) DO NOTHING`).bind(userId, now),
    db.prepare(`INSERT OR IGNORE INTO friends_memories
      (user_id, memory_id, source_trip_id, returned_at, memory_json)
      SELECT ?, json_extract(value, '$.id'), json_extract(value, '$.sourceTripId'),
        json_extract(value, '$.returnedAtMs'), json_remove(value, '$.returnedAtMs')
      FROM json_each(?) WHERE EXISTS
        (SELECT 1 FROM friends_saves WHERE user_id = ? AND revision = ?)`).bind(
      userId, JSON.stringify(backup.memories), userId, backup.revision),
    db.prepare(`UPDATE friends_saves SET state_json = ?, revision = revision + 1, updated_at = ?
      WHERE user_id = ? AND revision = ? RETURNING revision`).bind(
      JSON.stringify(backup.state), now, userId, backup.revision),
  ]);
  const revision = (results[2].results[0] as { revision: number } | undefined)?.revision;
  return revision == null ? { conflict: true } : { conflict: false, schemaVersion: 1, revision, updatedAt: now };
}

async function boundedBody(request: Request): Promise<unknown> {
  if (Number(request.headers.get('content-length')) > MAX_BODY_BYTES) throw new RangeError('Backup too large');
  const reader = request.body?.getReader();
  if (!reader) throw new TypeError('Missing backup');
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > MAX_BODY_BYTES) { await reader.cancel(); throw new RangeError('Backup too large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const data = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(data));
}

export async function handleFriendsBackup(request: Request, db: D1Database, userId: string): Promise<Response> {
  const json = (value, status = 200) => Response.json(value, { status, headers: { 'cache-control': 'no-store' } });
  try {
    if (request.method === 'GET') {
      return json(await readFriendsBackup(db, userId, new URL(request.url).searchParams.get('cursor')));
    }
    if (request.method === 'POST') {
      const saved = await saveFriendsBackup(db, userId, await boundedBody(request));
      return saved.conflict ? json({ error: 'Backup changed. Reload and merge before retrying.' }, 409) : json(saved);
    }
    return json({ error: 'Method not allowed' }, 405);
  } catch (error) {
    if (error instanceof RangeError) return json({ error: 'Backup is too large' }, 413);
    if (error instanceof TypeError || error instanceof SyntaxError) return json({ error: 'Invalid Friends backup' }, 400);
    throw error;
  }
}
