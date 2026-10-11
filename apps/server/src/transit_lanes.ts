import seed from '../data/transit-lanes.json' with { type: 'json' };
import { distanceMeters } from './geo.ts';
import type { LonLat } from './types.ts';
import { readPublicEdgeJson, writePublicEdgeJson } from './public_edge_cache.ts';
import accessPolicies from '../data/transit-road-access.json' with { type: 'json' };

export const AT_TRANSIT_SOURCE = 'https://services2.arcgis.com/JkPEgZJGxhSjYOo0/arcgis/rest/services/OpenData_TransitLanes/FeatureServer/0';
export const AT_TRANSIT_GUIDE = 'https://at.govt.nz/driving-and-parking/carpooling-ridesharing/bus-transit-priority-lanes';
export const TRANSIT_REFRESH_MS = 7 * 86400000;
const KEY = 'transit-lanes/auckland/v1';
export interface TransitSchedule { days: number[]; windows: number[][]; known: boolean }
export interface TransitLane {
  id: string; roadName: string; kind: string; start: string; end: string;
  operatingDays: string; operatingHours: string; schedule: TransitSchedule;
  coordinates: LonLat[]; directionKnown: boolean; wholeRoad: boolean; accessSource?: string;
}
export interface TransitSnapshot {
  schemaVersion: number; source: string; attribution: string; license: string;
  checkedAt: string; sourceUpdatedAt: string | null; lanes: TransitLane[]; syncStatus: string;
}
export interface TransitEnv { CAMERA_DATA?: { get(key: string, type: 'json'): Promise<any>; put(key: string, value: string): Promise<void> } }

/** Missing GIS times are unknown, never silently converted to a 24/7 ban. */
export function parseTransitSchedule(dayValue: unknown, hoursValue: unknown): TransitSchedule {
  const day = String(dayValue ?? '').trim().toLowerCase();
  let hours = String(hoursValue ?? '').trim().toLowerCase().replace(/[–—]/g, '-');
  let days = /monday to sunday/.test(day) ? [1, 2, 3, 4, 5, 6, 7]
    : /monday to friday/.test(day) ? [1, 2, 3, 4, 5] : [];
  if (!days.length && /monday to friday|mon\.?\s*-\s*fri|\(m\s*-\s*f\)/i.test(hours)) days = [1, 2, 3, 4, 5];
  if (!days.length && /monday to sunday/.test(hours)) days = [1, 2, 3, 4, 5, 6, 7];
  if (/^(24\/7|all times)$/.test(hours)) return { days: days.length ? days : [1, 2, 3, 4, 5, 6, 7], windows: [[0, 1440]], known: true };
  hours = hours.replace(/monday to (?:friday|sunday)|\(?mon\.?\s*-\s*fri\)?|\(m\s*-\s*f\)/g, '').trim();
  const windows: number[][] = [];
  const clock = (value: string, meridiem: string): number | null => {
    const [h, m] = value.includes(':') ? value.split(':').map(Number)
      : value.length >= 3 ? [Number(value.slice(0, -2)), Number(value.slice(-2))] : [Number(value), 0];
    if (m > 59 || h > (meridiem ? 12 : 23) || (meridiem && h < 1)) return null;
    return (meridiem ? h % 12 + (meridiem === 'pm' ? 12 : 0) : h) * 60 + m;
  };
  hours = hours.replace(/(\d{1,4}(?::\d{2})?)\s*(am|pm)?\s*-\s*(\d{1,4}(?::\d{2})?)\s*(am|pm)?/g,
    (_, a, ap, b, bp) => {
      const from = clock(a, ap || bp || ''), until = clock(b, bp || ap || '');
      if (from == null || until == null || from === until) return 'invalid';
      windows.push([from, until]); return '';
    });
  return { days, windows, known: days.length > 0 && windows.length > 0 && !hours.replace(/[\s,&]/g, '') };
}

export function normalizeTransitFeatures(payload: any, checkedAt: string, sourceUpdatedAt: string | null): TransitSnapshot {
  if (!Array.isArray(payload.features) || payload.exceededTransferLimit) throw new Error('Incomplete AT transit-lane snapshot');
  const lanes: TransitLane[] = [];
  for (const feature of payload.features) {
    const p = feature.properties || feature.attributes || {};
    const paths = feature.geometry?.type === 'LineString' ? [feature.geometry.coordinates]
      : feature.geometry?.type === 'MultiLineString' ? feature.geometry.coordinates : [];
    for (let i = 0;i < paths.length;i++) {
      const coordinates = paths[i].map((v: number[]) => [Number(v[0].toFixed(6)), Number(v[1].toFixed(6))]) as LonLat[];
      if (coordinates.length < 2 || !coordinates.every(([x, y]) => x >= 174 && x <= 176 && y >= -38 && y <= -35)) continue;
      const roadName = String(p.corridor_name ?? '').trim();
      if (!['Bus', 'BusOnly', 'Bus&Truck', 'T2', 'T3', 'T2&Truck', 'T3&Truck', 'Truck'].includes(p.svl_type)) continue;
      // BusOnly describes a lane, not necessarily the whole carriageway.
      // The AT guide explicitly confirms the whole bridge restriction.
      const policy = accessPolicies.find(rule => rule.roadName === roadName && rule.kind === p.svl_type);
      const wholeRoad = Boolean(policy);
      lanes.push({
        id: `at:svl:${p.OBJECTID}:${i}`, roadName, kind: p.svl_type,
        start: String(p.lane_start ?? '').trim(), end: String(p.lane_end ?? '').trim(),
        operatingDays: String(p.operating_day ?? '').trim(), operatingHours: String(p.operating_hours ?? '').trim(),
        schedule: parseTransitSchedule(p.operating_day, p.operating_hours), coordinates,
        directionKnown: Boolean(p.lane_start && p.lane_end && p.lane_start !== p.lane_end), wholeRoad,
        ...(wholeRoad ? { accessSource: policy.source } : {})
      });
    }
  }
  if (lanes.length < 200 || lanes.length > 2000 || !lanes.some(l => l.roadName === 'Symonds Street')) throw new Error('AT lane snapshot failed coverage validation');
  return {
    schemaVersion: 1, source: AT_TRANSIT_SOURCE, attribution: 'Auckland Transport',
    license: 'https://creativecommons.org/licenses/by/4.0/', checkedAt, sourceUpdatedAt, lanes, syncStatus: 'live'
  };
}

const nzTime = new Intl.DateTimeFormat('en-GB', { timeZone: 'Pacific/Auckland', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
export function transitActive(schedule: TransitSchedule, at: Date): boolean | null {
  if (!schedule.known) return null;
  const parts = Object.fromEntries(nzTime.formatToParts(at).map(p => [p.type, p.value]));
  const day = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexOf(parts.weekday) + 1;
  const minute = Number(parts.hour) * 60 + Number(parts.minute);
  return schedule.windows.some(([start, end]) => start < end
    ? schedule.days.includes(day) && minute >= start && minute < end
    : schedule.days.includes(day) && minute >= start || schedule.days.includes(day === 1 ? 7 : day - 1) && minute < end);
}

export function transitActiveDuring(schedule: TransitSchedule, from: Date, until: Date): boolean | null {
  if (!schedule.known) return null;
  if (transitActive(schedule, from) || transitActive(schedule, until)) return true;
  for (let t = Math.ceil(from.getTime() / 60000) * 60000;t < until.getTime();t += 60000) {
    if (transitActive(schedule, new Date(t))) return true;
  }
  return false;
}

/** Directed overlap, not a radius around a camera or a crossing street. */
export function matchTransitRoute(route: { coordinates: LonLat[]; durationSeconds: number; steps?: any[] }, lanes: TransitLane[]) {
  if (!lanes.length || route.coordinates.length < 2) return [];
  const cumulative = [0], cells = new Map<string, number[]>();
  const key = (x: number, y: number) => `${Math.floor(x * 1000)}:${Math.floor(y * 1000)}`;
  for (let i = 1;i < route.coordinates.length;i++) {
    const a = route.coordinates[i - 1], b = route.coordinates[i];
    cumulative.push(cumulative[i - 1] + distanceMeters(a, b));
    const x1 = Math.floor((Math.min(a[0], b[0]) - .0004) * 1000), x2 = Math.floor((Math.max(a[0], b[0]) + .0004) * 1000);
    const y1 = Math.floor((Math.min(a[1], b[1]) - .0003) * 1000), y2 = Math.floor((Math.max(a[1], b[1]) + .0003) * 1000);
    if ((x2 - x1 + 1) * (y2 - y1 + 1) > 1000) continue;
    for (let x = x1;x <= x2;x++)for (let y = y1;y <= y2;y++) { const k = `${x}:${y}`; const values = cells.get(k) || []; values.push(i); cells.set(k, values); }
  }
  const result: { lane: TransitLane; startMeters: number; endMeters: number }[] = [];
  for (const lane of lanes) {
    let start = Infinity, end = -Infinity;
    for (let i = 1;i < lane.coordinates.length;i++) {
      const a = lane.coordinates[i - 1], b = lane.coordinates[i], length = distanceMeters(a, b);
      const count = Math.max(1, Math.ceil(length / 15));
      for (let j = 0;j <= count;j++) {
        const p: LonLat = [a[0] + (b[0] - a[0]) * j / count, a[1] + (b[1] - a[1]) * j / count];
        const scale = 111320 * Math.cos(p[1] * Math.PI / 180);
        const lx = (b[0] - a[0]) * scale, ly = (b[1] - a[1]) * 111320;
        let nearest: { offset: number; along: number } | null = null;
        for (const index of cells.get(key(...p)) || []) {
          const u = route.coordinates[index - 1], v = route.coordinates[index];
          const dx = (v[0] - u[0]) * scale, dy = (v[1] - u[1]) * 111320, square = dx * dx + dy * dy;
          if (!square || !length) continue;
          const cosine = (lx * dx + ly * dy) / Math.sqrt((lx * lx + ly * ly) * square);
          if (lane.directionKnown ? cosine < .82 : Math.abs(cosine) < .82) continue;
          const px = (p[0] - u[0]) * scale, py = (p[1] - u[1]) * 111320;
          const t = Math.max(0, Math.min(1, (px * dx + py * dy) / square));
          const offset = Math.hypot(px - t * dx, py - t * dy);
          if (offset > 22 || nearest && offset >= nearest.offset) continue;
          nearest = { offset, along: cumulative[index - 1] + t * (cumulative[index] - cumulative[index - 1]) };
        }
        if (nearest) { start = Math.min(start, nearest.along); end = Math.max(end, nearest.along); }
      }
    }
    if (end - start >= 25) result.push({ lane, startMeters: start, endMeters: end });
  }
  return result.sort((a, b) => a.startMeters - b.startMeters);
}

export function transitRoadBlocks(route: { coordinates: LonLat[]; durationSeconds: number; steps?: any[] }, snapshot: TransitSnapshot, at = new Date()) {
  const length = route.coordinates.slice(1).reduce((n, p, i) => n + distanceMeters(route.coordinates[i], p), 0);
  const names = new Set((route.steps || []).map(s => String(s.name || s.roadName || '').toLowerCase()));
  names.delete('');
  return matchTransitRoute(route, snapshot.lanes.filter(l => l.wholeRoad && l.directionKnown && (!names.size || names.has(l.roadName.toLowerCase()))))
    .filter(m => transitActiveDuring(m.lane.schedule,
      new Date(at.getTime() + route.durationSeconds * m.startMeters / Math.max(1, length) * 1000),
      new Date(at.getTime() + route.durationSeconds * m.endMeters / Math.max(1, length) * 1000)) === true);
}

export async function readTransitSnapshot(env: TransitEnv, cached = true): Promise<TransitSnapshot> {
  const cacheKey = 'https://waybi.co/__edge-cache/transit-lanes/v1';
  const existing = cached ? await readPublicEdgeJson<TransitSnapshot>(cacheKey) : null;
  if (existing?.schemaVersion === 1 && existing.lanes?.length >= 200) return existing;
  let stored: TransitSnapshot | undefined;
  try {
    stored = await env.CAMERA_DATA?.get(KEY, 'json');
  } catch {
    // Keep navigation available if KV is unavailable or its quota is reached.
  }
  const snapshot = stored?.schemaVersion === 1 && stored.lanes?.length >= 200 ? stored : seed as TransitSnapshot;
  if (cached) await writePublicEdgeJson(cacheKey, snapshot, 86400);
  return snapshot;
}

/** Cron owns writes. Visitors never initiate upstream requests or KV puts. */
export async function refreshTransitSnapshot(env: TransitEnv, fetcher: typeof fetch = fetch, now = new Date()): Promise<TransitSnapshot> {
  const previous = await readTransitSnapshot(env, false);
  if (now.getTime() - Date.parse(previous.checkedAt) < TRANSIT_REFRESH_MS) return previous;
  try {
    const meta = await fetcher(`${AT_TRANSIT_SOURCE}?f=json`, { signal: AbortSignal.timeout(15000) }).then(r => { if (!r.ok) throw new Error('AT metadata unavailable'); return r.json<any>(); });
    const query = new URL(`${AT_TRANSIT_SOURCE}/query`);
    query.search = new URLSearchParams({ f: 'geojson', where: '1=1', outFields: '*', outSR: '4326', orderByFields: 'OBJECTID', resultRecordCount: '1000' }).toString();
    const payload = await fetcher(query, { signal: AbortSignal.timeout(20000) }).then(r => { if (!r.ok) throw new Error('AT lane data unavailable'); return r.json<any>(); });
    const edited = meta.editingInfo?.lastEditDate;
    const next = normalizeTransitFeatures(payload, now.toISOString(), edited ? new Date(edited).toISOString() : null);
    await env.CAMERA_DATA?.put(KEY, JSON.stringify(next)); return next;
  } catch {
    // Retain verified geometry and unknown schedules; retry on next week's cron.
    const retained = { ...previous, checkedAt: now.toISOString(), syncStatus: 'stale' };
    await env.CAMERA_DATA?.put(KEY, JSON.stringify(retained)); return retained;
  }
}
