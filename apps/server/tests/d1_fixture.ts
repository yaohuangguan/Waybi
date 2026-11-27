import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';

/** An in-memory SQLite database with every migration applied, wrapped in the
 * subset of the D1 API the Worker uses (prepare/bind/first/all/run/batch).
 * Like D1, `batch` is one transaction and returns `{ results }` per statement. */
export function migratedD1() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('PRAGMA foreign_keys=ON');
  const root = new URL('../../../migrations/', import.meta.url);
  for (const file of readdirSync(root).filter((name) => /^\d+.*\.sql$/.test(name)).sort()) {
    sqlite.exec(readFileSync(new URL(file, root), 'utf8'));
  }
  const statements: string[] = [];
  const execute = (sql: string, values: unknown[]) => {
    const statement = sqlite.prepare(sql);
    if (statement.columns().length) return { results: statement.all(...values as []), meta: { changes: 0 } };
    const outcome = statement.run(...values as []);
    return { results: [], meta: { changes: Number(outcome.changes) } };
  };
  const db = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            sql, values,
            async first() { statements.push(sql); return sqlite.prepare(sql).get(...values as []) || null; },
            async all() { statements.push(sql); return { results: sqlite.prepare(sql).all(...values as []) }; },
            async run() { statements.push(sql); return execute(sql, values); },
          };
        },
      };
    },
    async batch(items: Array<{ sql: string; values: unknown[] }>) {
      sqlite.exec('BEGIN');
      try {
        const results = items.map(({ sql, values }) => { statements.push(sql); return execute(sql, values); });
        sqlite.exec('COMMIT');
        return results;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
  };
  return { sqlite, db: db as any, statements };
}
