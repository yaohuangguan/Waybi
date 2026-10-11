import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const migrations = ['0001_accounts.sql', '0003_profile_activity.sql', '0016_companion_lifetime.sql'];

function database() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON;');
  for (const name of migrations.slice(0, 2)) {
    db.exec(readFileSync(new URL('../../../migrations/' + name, import.meta.url), 'utf8'));
  }
  db.prepare('INSERT INTO users (id,email,password_salt,password_hash,created_at) VALUES (?,?,?,?,?)')
    .run('sam', 'sam@example.com', '', '', 1);
  return db;
}

function record(db, id, metres, seconds = 1800) {
  db.prepare(`INSERT OR IGNORE INTO route_history
    (id,user_id,destination_name,destination_latitude,destination_longitude,mode,
     distance_meters,duration_seconds,started_at) VALUES (?,?,?,?,?,?,?,?,?)`)
    .run(id, 'sam', 'Auckland', -36.85, 174.76, 'drive', metres, seconds, Date.now());
}

function upload(db, id, metres, seconds = 1800) {
  db.prepare(`INSERT OR IGNORE INTO route_history
    (id,user_id,destination_name,destination_latitude,destination_longitude,mode,
     distance_meters,duration_seconds,started_at)
    SELECT ?,?,?,?,?,?,?,?,? WHERE NOT EXISTS
    (SELECT 1 FROM companion_route_receipts WHERE user_id = ? AND journey_id = ?)`)
    .run(id, 'sam', 'Auckland', -36.85, 174.76, 'drive', metres, seconds, Date.now(), 'sam', id);
}

function totals(db) {
  return { ...db.prepare('SELECT distance_meters,trip_count,duration_seconds FROM companion_totals WHERE user_id = ?').get('sam') };
}

test('migration backfills known history and does not count repeated imports', () => {
  const db = database();
  record(db, 'old-route-1', 42000);
  record(db, 'old-route-2', 9000, 1200);
  db.exec(readFileSync(new URL('../../../migrations/0016_companion_lifetime.sql', import.meta.url), 'utf8'));
  assert.deepEqual(totals(db), { distance_meters: 51000, trip_count: 2, duration_seconds: 3000 });

  upload(db, 'new-route-1', 2300, 600);
  upload(db, 'new-route-1', 2300, 600); // Retry, same stable route id.
  assert.deepEqual(totals(db), { distance_meters: 53300, trip_count: 3, duration_seconds: 3600 });

  db.prepare('DELETE FROM route_history WHERE user_id = ?').run('sam');
  upload(db, 'new-route-1', 2300, 600); // Even months later, after history has been pruned.
  assert.deepEqual(totals(db), { distance_meters: 53300, trip_count: 3, duration_seconds: 3600 });

  const guest = db.prepare(`INSERT OR IGNORE INTO companion_guest_imports
    (user_id,import_id,distance_meters,trip_count,duration_seconds,created_at) VALUES (?,?,?,?,?,?)`);
  guest.run('sam', 'guest-upload-123456', 5000, 2, 900, Date.now());
  guest.run('sam', 'guest-upload-123456', 5000, 2, 900, Date.now());
  assert.deepEqual(totals(db), { distance_meters: 58300, trip_count: 5, duration_seconds: 4500 });
  db.close();
});

test('same account retains all lifetime totals beyond 100 recent routes', () => {
  const db = database();
  db.exec(readFileSync(new URL('../../../migrations/0016_companion_lifetime.sql', import.meta.url), 'utf8'));
  for (let i = 0; i < 130; i++) upload(db, 'journey-' + String(i).padStart(6, '0'), 1000);
  db.exec(`DELETE FROM route_history WHERE user_id = 'sam' AND id NOT IN
    (SELECT id FROM route_history WHERE user_id = 'sam' ORDER BY started_at DESC, id DESC LIMIT 100)`);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM route_history').get().count, 100);
  assert.deepEqual(totals(db), { distance_meters: 130000, trip_count: 130, duration_seconds: 234000 });
  db.close();
});
