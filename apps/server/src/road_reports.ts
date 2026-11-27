import { validCoordinate } from './geo.ts';

/** Legacy shared KV snapshot; read only to import reports created before D1. */
const LEGACY_KEY = 'road-reports/current';
const MAX_REPORTS = 250;
const REPORT_LIFETIME_MS = 2 * 60 * 60 * 1000;
const ALLOWED = new Set(['incident', 'roadworks', 'roadClosure', 'congestion', 'flooding', 'slip']);
// One legacy import attempt per isolate and KV namespace.
const legacyImports = new WeakMap<object, Promise<void>>();

export interface ReportBounds { west: number; south: number; east: number; north: number }

export function validRoadReportInput(payload) {
  return validCoordinate(Number(payload?.latitude), Number(payload?.longitude)) && ALLOWED.has(String(payload?.type || ''));
}

function stillValid(report, now: Date) {
  const until = Date.parse(report?.validUntil || '');
  return Number.isFinite(until) && until > now.getTime();
}

async function readLegacyReports(env) {
  if (!env.CAMERA_DATA?.get) return [];
  const state = await env.CAMERA_DATA.get(LEGACY_KEY, 'json');
  return Array.isArray(state?.reports) ? state.reports : [];
}

function insertReport(db, report, reporterId: string | null = null) {
  const latitude = Number(report?.location?.latitude);
  const longitude = Number(report?.location?.longitude);
  return db.prepare(`INSERT OR IGNORE INTO road_reports
    (id, report_json, reporter_id, latitude, longitude, created_at, valid_until) VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .bind(String(report.id), JSON.stringify(report), reporterId, latitude, longitude,
      Date.parse(report.validFrom || report.metadata?.reportedAt || '') || Date.now(), Date.parse(report.validUntil));
}

/** Copy still-valid reports from the legacy KV array into D1, then clear the
 * KV key so later reads skip it. Idempotent across isolates (INSERT OR IGNORE). */
function importLegacyReports(env, now: Date) {
  if (!env.CAMERA_DATA || !env.USER_DB) return Promise.resolve();
  let pending = legacyImports.get(env.CAMERA_DATA);
  if (!pending) {
    pending = (async () => {
      const state = await env.CAMERA_DATA.get(LEGACY_KEY, 'json');
      const legacy = (Array.isArray(state?.reports) ? state.reports : []).filter((report) => stillValid(report, now) &&
        validCoordinate(Number(report?.location?.latitude), Number(report?.location?.longitude)) && report?.id);
      if (legacy.length) {
        await env.USER_DB.batch(legacy.slice(0, MAX_REPORTS).map((report) =>
          insertReport(env.USER_DB, report, typeof report.metadata?.reporterId === 'string' ? report.metadata.reporterId : null)));
        console.info(JSON.stringify({ level: 'info', event: 'road_reports_legacy_imported', reports: legacy.length }));
      }
      // Clear only after a successful import; a failure retries on a later read.
      if (state && typeof env.CAMERA_DATA.delete === 'function') await env.CAMERA_DATA.delete(LEGACY_KEY);
    })().catch((error) => {
      legacyImports.delete(env.CAMERA_DATA);
      console.warn(JSON.stringify({ level: 'warn', event: 'road_reports_legacy_import_failed',
        message: String(error?.message || error).slice(0, 200) }));
    });
    legacyImports.set(env.CAMERA_DATA, pending);
  }
  return pending;
}

export async function readRoadReports(env, now = new Date(), bounds: ReportBounds | null = null) {
  if (!env.USER_DB) {
    // Without D1 (local tooling) only the legacy snapshot can be read.
    try { return (await readLegacyReports(env)).filter((report) => stillValid(report, now)); }
    catch { return []; }
  }
  await importLegacyReports(env, now);
  try {
    const rows = bounds
      ? await env.USER_DB.prepare(`SELECT report_json FROM road_reports
          WHERE valid_until > ? AND latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?
          ORDER BY created_at DESC LIMIT ?`)
        .bind(now.getTime(), bounds.south, bounds.north, bounds.west, bounds.east, MAX_REPORTS).all()
      : await env.USER_DB.prepare(`SELECT report_json FROM road_reports WHERE valid_until > ?
          ORDER BY created_at DESC LIMIT ?`).bind(now.getTime(), MAX_REPORTS).all();
    return (rows.results || []).flatMap((row) => {
      try { return [JSON.parse(row.report_json)]; } catch { return []; }
    });
  } catch (error) {
    // Community reports are supplementary; official events are still served.
    console.warn(JSON.stringify({ level: 'warn', event: 'road_reports_read_failed',
      message: String(error?.message || error).slice(0, 200) }));
    return [];
  }
}

/// Remove any remaining report authored by a deleted account. Failure must
/// prevent reporting deletion success.
export async function purgeDeletedReporterReports(env, userId: string) {
  if (env.USER_DB) {
    await env.USER_DB.prepare('DELETE FROM road_reports WHERE reporter_id = ?').bind(userId).run();
  }
  if (!env.CAMERA_DATA) return;
  const state = await env.CAMERA_DATA.get(LEGACY_KEY, 'json');
  if (!Array.isArray(state?.reports)) return;
  const filtered = state.reports.filter(report => report?.metadata?.reporterId !== userId);
  if (filtered.length !== state.reports.length) {
    await env.CAMERA_DATA.put(LEGACY_KEY, JSON.stringify({ ...state, reports: filtered }));
  }
}

export async function createRoadReport(env, payload, reporter = null, now = new Date()) {
  const latitude = Number(payload?.latitude);
  const longitude = Number(payload?.longitude);
  const type = String(payload?.type || '');
  if (!validRoadReportInput(payload)) {
    throw new TypeError('Valid global road report required');
  }
  if (!env.USER_DB) throw new Error('Road report storage unavailable');
  const heading = Number(payload?.headingDegrees);
  const id = crypto.randomUUID();
  const report = {
    id: 'waybi:report:' + id,
    type,
    location: { latitude, longitude },
    geometry: [{ latitude, longitude }],
    severity: type === 'roadClosure' ? 'critical' : type === 'incident' ? 'warning' : 'advisory',
    confidence: 0.65,
    observation: 'observed',
    headingDegrees: Number.isFinite(heading) ? ((heading % 360) + 360) % 360 : null,
    validFrom: now.toISOString(),
    validUntil: new Date(now.getTime() + REPORT_LIFETIME_MS).toISOString(),
    source: {
      provider: 'Waybi road reports',
      country: null,
      region: null,
      sourceId: id,
      updatedAt: now.toISOString()
    },
    metadata: {
      description: String(payload?.description || '').trim().slice(0, 120),
      userReported: true,
      // Reports are shared anonymously, not as public location-linked
      // profiles. Keep legacy field shape for older Waybi clients.
      reporterName: 'Waybi driver',
      reporterId: null,
      reportedAt: now.toISOString()
    }
  };
  // One row per report: concurrent reports from different PoPs can no longer
  // overwrite each other's read-modify-write of a shared array.
  await insertReport(env.USER_DB, report).run();
  return report;
}
