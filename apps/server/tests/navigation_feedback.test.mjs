import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { saveNavigationFeedback } from '../src/navigation_feedback.mjs';

test('feedback migration and offline receipts preserve exactly one vote', async () => {
  const sqlite = new DatabaseSync(':memory:');
  try {
    sqlite.exec(readFileSync(new URL('../../../migrations/0013_navigation_feedback.sql',import.meta.url),'utf8'));
    const db = {prepare(sql) { const statement=sqlite.prepare(sql); return {bind(...values) {return {async run() {return statement.run(...values);}};}};}};
    const id='0123456789abcdef0123456789abcdef';
    await saveNavigationFeedback(db,{id,vote:1});
    await saveNavigationFeedback(db,{id,vote:-1});
    assert.equal(sqlite.prepare('SELECT COUNT(*) AS count FROM navigation_feedback').get().count,1);
    assert.equal(sqlite.prepare('SELECT vote FROM navigation_feedback').get().vote,1);
    for (const body of [{id,vote:0},{id:'bad',vote:1},{id:[id],vote:1},null]) {
      await assert.rejects(saveNavigationFeedback(db,body),TypeError);
    }
  } finally { sqlite.close(); }
});
