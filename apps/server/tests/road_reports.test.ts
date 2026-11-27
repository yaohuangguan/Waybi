import test from 'node:test';
import assert from 'node:assert/strict';
import { createRoadReport, purgeDeletedReporterReports, readRoadReports } from '../src/road_reports.ts';
import { migratedD1 } from './d1_fixture.ts';

function envWithStore(legacy = null) {
  let stored = legacy;
  const { sqlite, db } = migratedD1();
  return {
    sqlite,
    get legacy() { return stored; },
    env: {
      USER_DB: db,
      CAMERA_DATA: {
        async get() { return stored; },
        async put(_key, value) { stored = JSON.parse(value); },
        async delete() { stored = null; },
      },
    },
  };
}

test('creates and reads a short-lived road report stored as its own D1 row', async () => {
  const { env, sqlite } = envWithStore();
  try {
    const now = new Date('2026-09-26T02:00:00Z');
    const report = await createRoadReport(env, {
      type: 'roadworks',
      latitude: -36.85,
      longitude: 174.76,
      headingDegrees: 375
    }, { id: 'user-1', displayName: 'Sam' }, now);
    assert.equal(report.type, 'roadworks');
    assert.equal(report.observation, 'observed');
    assert.equal(report.headingDegrees, 15);
    assert.equal(report.metadata.reporterName, 'Waybi driver');
    assert.equal(report.metadata.reporterId, null);
    assert.equal(sqlite.prepare('SELECT reporter_id FROM road_reports').get().reporter_id, null, 'reports stay anonymous');
    assert.equal((await readRoadReports(env, now)).length, 1);
    assert.equal((await readRoadReports(env, new Date('2026-09-26T05:00:00Z'))).length, 0);
  } finally { sqlite.close(); }
});

test('concurrent reports are all kept (no shared read-modify-write array)', async () => {
  const { env, sqlite } = envWithStore();
  try {
    const now = new Date();
    await Promise.all(Array.from({ length: 20 }, (_, i) =>
      createRoadReport(env, { type: 'incident', latitude: -36.85 + i * 0.001, longitude: 174.76 }, null, now)));
    assert.equal((await readRoadReports(env, now)).length, 20);
    const nearby = await readRoadReports(env, now, { west: 174.7, south: -36.851, east: 174.8, north: -36.845 });
    assert.equal(nearby.length, 6, 'optional bounds are applied in D1');
  } finally { sqlite.close(); }
});

test('valid legacy KV reports are imported once, and account deletion still purges legacy authors', async () => {
  const now = new Date('2026-09-26T02:00:00Z');
  const legacyReport = (id, reporterId, until = '2026-09-26T03:00:00Z') => ({ id, type: 'incident',
    location: { latitude: -36.85, longitude: 174.76 }, validFrom: '2026-09-26T01:00:00Z', validUntil: until,
    metadata: { reporterId } });
  const fixture = envWithStore({ reports: [
    legacyReport('waybi:report:alice', 'alice'), legacyReport('waybi:report:bob', 'bob'),
    legacyReport('waybi:report:expired', 'bob', '2026-09-26T01:30:00Z'),
  ] });
  try {
    const reports = await readRoadReports(fixture.env, now);
    assert.deepEqual(reports.map((r) => r.id).sort(), ['waybi:report:alice', 'waybi:report:bob']);
    assert.equal(fixture.legacy, null, 'the legacy KV key is cleared after import');
    await purgeDeletedReporterReports(fixture.env, 'alice');
    assert.deepEqual((await readRoadReports(fixture.env, now)).map((r) => r.id), ['waybi:report:bob']);
  } finally { fixture.sqlite.close(); }
});

test('accepts global road reports and rejects invalid world coordinates', async () => {
  const { env, sqlite } = envWithStore();
  try {
    const global = await createRoadReport(env, { type: 'incident', latitude: 40.7128, longitude: -74.006 });
    assert.equal(global.location.latitude, 40.7128);
    assert.equal(global.source.country, null);
    await assert.rejects(
      () => createRoadReport(env, { type: 'incident', latitude: 91, longitude: 0 }),
      /Valid global road report/
    );
  } finally { sqlite.close(); }
});
