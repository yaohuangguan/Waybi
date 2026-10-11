import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { handleFriendsBackup, readFriendsBackup, saveFriendsBackup } from '../src/friends_backup.ts';
import { handleAccount } from '../src/auth.ts';

function database() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('PRAGMA foreign_keys=ON; CREATE TABLE users(id TEXT PRIMARY KEY); INSERT INTO users VALUES (\'alice\'), (\'bob\');');
  sqlite.exec(readFileSync(new URL('../../../migrations/0014_friends_cloud_save.sql', import.meta.url), 'utf8'));
  const db = {
    prepare(sql) {
      return { bind(...values) { return { sql, values }; } };
    },
    async batch(statements) {
      sqlite.exec('BEGIN');
      try {
        const results = statements.map(({ sql, values }) => {
          const statement = sqlite.prepare(sql);
          return { results: statement.columns().length ? statement.all(...values) : (statement.run(...values), []) };
        });
        sqlite.exec('COMMIT');
        return results;
      } catch (error) { sqlite.exec('ROLLBACK'); throw error; }
    },
  } as unknown as D1Database;
  return { sqlite, db };
}

function memory(id = 'souvenir-1', sourceTripId: string | null = null) {
  return { id, sourceTripId, destinationId: 'garden', returnedAt: '2026-10-08T01:00:00Z',
    itemIds: ['map'], title: 'A small adventure', story: 'A memory.', souvenir: 'A leaf', traveller: 'clover' };
}
function backup(revision = 0, memories = [memory()]) {
  return { schemaVersion: 1, revision, game: { memories, selectedItemIds: ['map'], activeJourney: null,
    roomLife: { startedAt: '2026-10-08T00:00:00Z', traveller: 'waybi', scene: 'room',
      interactions: { sett: { at: '2026-10-08T00:01:00Z', from: [0.2, 0.8], to: [0.7, 0.8] } } } } };
}

test('accounts stay isolated, incomplete devices preserve memories, deleted accounts remove their backups', async () => {
  const { sqlite, db } = database();
  try {
    assert.equal((await saveFriendsBackup(db, 'alice', backup())).revision, 1);
    assert.equal((await readFriendsBackup(db, 'bob')).game, null);
    await saveFriendsBackup(db, 'bob', backup(0, [memory('bob-1')]));
    await saveFriendsBackup(db, 'alice', backup(1, [memory('souvenir-2')]));
    const saved = await readFriendsBackup(db, 'alice');
    assert.equal(saved.revision, 2);
    assert.deepEqual(new Set(saved.game.memories.map(m => m.id)), new Set(['souvenir-1', 'souvenir-2']));
    assert.deepEqual(saved.game.roomLife.interactions.sett.to, [0.7, 0.8]);
    sqlite.prepare('DELETE FROM users WHERE id=?').run('alice');
    assert.equal((await readFriendsBackup(db, 'alice')).game, null);
    assert.equal((await readFriendsBackup(db, 'bob')).game.memories[0].id, 'bob-1');
  } finally { sqlite.close(); }
});

test('concurrent devices use revisions; stale uploads cannot add or erase memories, retry deduplicates trips', async () => {
  const { sqlite, db } = database();
  try {
    const results = await Promise.all([
      saveFriendsBackup(db, 'alice', backup(0, [memory('phone-1', 'trip-1')])),
      saveFriendsBackup(db, 'alice', backup(0, [memory('stale-1', 'trip-2')])),
    ]);
    assert.equal(results.filter(result => result.conflict).length, 1);
    assert.deepEqual((await readFriendsBackup(db, 'alice')).game.memories.map(m => m.id), ['phone-1']);
    await saveFriendsBackup(db, 'alice', backup(1, [memory('second-id', 'trip-1'), memory('phone-2', 'trip-2')]));
    assert.equal((await readFriendsBackup(db, 'alice')).game.memories.length, 2);
  } finally { sqlite.close(); }
});

test('pagination handles equal timestamps and Unicode IDs without skipping memories', async () => {
  const { sqlite, db } = database();
  try {
    await saveFriendsBackup(db, 'alice', backup(0, Array.from({ length: 403 }, (_, i) => memory(`旅行-${i.toString().padStart(4, '0')}`))));
    const all = [];
    let cursor = null;
    do {
      const page = await readFriendsBackup(db, 'alice', cursor);
      assert.equal(page.revision, 1);
      all.push(...page.game.memories);
      cursor = page.nextCursor;
    } while (cursor);
    assert.equal(all.length, 403);
    assert.equal(new Set(all.map(m => m.id)).size, 403);
    await assert.rejects(readFriendsBackup(db, 'alice', 'invalid'), TypeError);
  } finally { sqlite.close(); }
});

test('backup API requires authentication, bounds streamed bodies and refuses invalid saves without changing existing data', async () => {
  const { sqlite, db } = database();
  try {
    const anonymous = await handleAccount(new Request('https://waybi.co/api/profile/friends'), { USER_DB: db });
    assert.equal(anonymous.status, 401);
    await saveFriendsBackup(db, 'alice', backup());
    for (const value of [null, backup(-1), { ...backup(1), game: { ...backup().game, memories: [{ ...memory(), returnedAt: 'bad' }] } }]) {
      const response = await handleFriendsBackup(new Request('https://waybi.co/api/profile/friends', { method: 'POST', body: JSON.stringify(value) }), db, 'alice');
      assert.equal(response.status, 400);
    }
    const tooLarge = new Request('https://waybi.co/api/profile/friends', { method: 'POST', body: 'x'.repeat(1_500_001) });
    assert.equal((await handleFriendsBackup(tooLarge, db, 'alice')).status, 413);
    const stale = new Request('https://waybi.co/api/profile/friends', { method: 'POST', body: JSON.stringify(backup()) });
    assert.equal((await handleFriendsBackup(stale, db, 'alice')).status, 409);
    const saved = await handleFriendsBackup(new Request('https://waybi.co/api/profile/friends'), db, 'alice');
    assert.equal(saved.headers.get('cache-control'), 'no-store');
    assert.equal((await saved.json()).revision, 1);
  } finally { sqlite.close(); }
});
