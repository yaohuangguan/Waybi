import type { LonLat, ProviderPayload, UsageRecorder } from '../types.ts';
import {
  AMAP_ATTRIBUTION, AMAP_PROVIDER, amapConfigured, amapGet, amapText,
} from '../amap_client.ts';
import type { AmapApi, AmapRequestOptions } from '../amap_client.ts';
import { gcjParameter, isMainlandChina, parseGcjPoint } from '../china_geo.ts';
import { distanceMeters } from '../geo.ts';
import { rankPlaces } from '../place_search_rank.ts';
import { dedupeSearchResults } from './search_orchestrator.ts';
import { readPublicEdgeJson, writePublicEdgeJson } from '../public_edge_cache.ts';

/**
 * Place search and reverse geocoding inside mainland China, where the open
 * OpenStreetMap stack is too sparse: OSM knows one "盛世春天" in all of China,
 * 494 km from a driver in Shijiazhuang, while Amap knows the compound down the
 * road. Every Amap coordinate is GCJ-02 and is converted to WGS-84 here, so
 * results line up with Waybi's base map and GPS. OSM stays a deduplicated
 * fallback when Amap returns too few results, fails, or is out of budget.
 */
export const AMAP_SEARCH_TIMEOUT_MS = 5000;
/** Fewer located Amap results than this triggers the next source. */
export const MIN_AMAP_RESULTS = 3;
const RESULT_LIMIT = 12;

export interface AmapArea { citycode: string; adcode: string; city: string; district: string }

export function amapSearchApplies(env: any, point: LonLat | null): boolean {
  return Boolean(point) && isMainlandChina(point[0], point[1]) && amapConfigured(env);
}

const GEOGRAPHIC_TYPECODES: Record<string, string> = {
  190101: 'country', 190102: 'province', 190103: 'city', 190104: 'city', 190105: 'county',
  190106: 'town', 190107: 'suburb', 190108: 'village', 190109: 'village',
};

/** Province, city and district joined the Chinese way (largest first),
 * without repeating a municipality ("北京市北京市") or a prefix already
 * contained in the next part. */
export function amapAddress(...parts: unknown[]): string {
  let address = '';
  for (const part of parts.map(amapText).filter(Boolean)) {
    if (address.includes(part)) continue;
    // "…长安区" + "长安区建设北大街" overlaps; append only the new remainder.
    let overlap = Math.min(address.length, part.length);
    while (overlap > 0 && !address.endsWith(part.slice(0, overlap))) overlap--;
    address += part.slice(overlap);
  }
  return address;
}

function placeFrom(item: ProviderPayload, address: string, extra: Record<string, unknown> = {}) {
  const location = parseGcjPoint(item?.location);
  const name = amapText(item?.name);
  if (!location || !name || !isFinitePoint(location)) return null;
  const typecode = amapText(item?.typecode).split('|')[0];
  const geographic = GEOGRAPHIC_TYPECODES[typecode];
  const road = typecode.startsWith('1903') || typecode.startsWith('1904');
  const id = amapText(item?.id);
  return {
    id: id || `${name}@${location[0].toFixed(5)},${location[1].toFixed(5)}`,
    provider: AMAP_PROVIDER,
    sourceName: '高德地图',
    attribution: AMAP_ATTRIBUTION,
    name,
    address,
    label: address ? `${name}, ${address}` : name,
    isPoi: !geographic && !road,
    resultType: geographic || (road ? 'road' : amapText(item?.type).split(';').at(-1) || typecode),
    countryCode: 'CN',
    latitude: location[1],
    longitude: location[0],
    ...extra,
  };
}

function isFinitePoint(point: LonLat) {
  return Number.isFinite(point[0]) && Number.isFinite(point[1]);
}

export function mapAmapTips(payload: ProviderPayload) {
  const tips = Array.isArray(payload?.tips) ? payload.tips : [];
  return tips.flatMap((tip) => {
    const place = placeFrom(tip, amapAddress(tip?.district, tip?.address));
    return place ? [place] : [];
  });
}

export function mapAmapPois(payload: ProviderPayload) {
  const pois = Array.isArray(payload?.pois) ? payload.pois : [];
  return pois.flatMap((poi) => {
    const place = placeFrom(poi, amapAddress(poi?.pname, poi?.cityname, poi?.adname, poi?.address));
    return place ? [place] : [];
  });
}

function compactName(value: unknown) {
  return String(value || '').normalize('NFKC').toLocaleLowerCase().replace(/[\p{P}\p{S}\s]+/gu, '');
}

/** An OSM fallback result that describes a place Amap already returned. */
export function duplicatesPrimary(place: any, primary: any[]): boolean {
  const point: LonLat = [Number(place.longitude), Number(place.latitude)];
  const name = compactName(place.name);
  return primary.some((candidate) => {
    const metres = distanceMeters(point, [Number(candidate.longitude), Number(candidate.latitude)]);
    if (metres <= 30) return true;
    const other = compactName(candidate.name);
    return metres <= 300 && Boolean(name) && Boolean(other) && (name.includes(other) || other.includes(name));
  });
}

interface SearchArgs {
  query: string;
  point: LonLat;
  language?: string;
  env: any;
  trackUsage?: UsageRecorder;
  clientKey?: string | null;
  fetcher?: typeof fetch;
  /** 'suggest' is typeahead (input tips first); 'search' is a submitted query. */
  mode?: 'suggest' | 'search';
  /** The existing OSM stack, consulted only when Amap returns too few. */
  osmFallback?: () => Promise<any[]>;
}

function requestOptions(args: SearchArgs, timeoutMs = AMAP_SEARCH_TIMEOUT_MS): AmapRequestOptions {
  return { timeoutMs, clientKey: args.clientKey, trackUsage: args.trackUsage, fetcher: args.fetcher };
}

async function attempt<T>(work: () => Promise<T>, fallback: T): Promise<T> {
  try { return await work(); } catch { return fallback; }
}

const AREA_TTL_MS = 24 * 60 * 60 * 1000;
const AREA_MISS_TTL_MS = 10 * 60 * 1000;
const areaCache = new Map<string, { at: number; area: AmapArea | null }>();
const areaPending = new Map<string, Promise<AmapArea | null>>();

/** Test hook. */
export function resetAmapSearchCaches() { areaCache.clear(); areaPending.clear(); reverseCache.clear(); }

/**
 * The city around a point, for Amap's `city`/`region` proximity parameters.
 * Shared by every search in a ~5 km cell for a day (memory, then the PoP's
 * edge cache), so typing never pays for a reverse geocode per keystroke.
 */
export async function amapAreaForPoint(env: any, point: LonLat, options: AmapRequestOptions = {}): Promise<AmapArea | null> {
  const cell: LonLat = [Math.round(point[0] * 20) / 20, Math.round(point[1] * 20) / 20];
  const key = `${cell[0].toFixed(2)},${cell[1].toFixed(2)}`;
  const cached = areaCache.get(key);
  if (cached && Date.now() - cached.at < (cached.area ? AREA_TTL_MS : AREA_MISS_TTL_MS)) return cached.area;
  const pending = areaPending.get(key);
  if (pending) return pending;
  const load = (async () => {
    const edgeKey = `https://waybi.co/__edge-cache/amap-area/v1/${key}`;
    const edge = await readPublicEdgeJson<AmapArea>(edgeKey);
    if (edge?.citycode || edge?.adcode) return edge;
    const payload = await attempt(() => amapGet(env, 'regeo', { location: gcjParameter(cell), extensions: 'base' }, options), null);
    const component = payload?.regeocode?.addressComponent;
    const area = component ? {
      citycode: amapText(component.citycode), adcode: amapText(component.adcode),
      city: amapText(component.city) || amapText(component.province), district: amapText(component.district),
    } : null;
    if (area && (area.citycode || area.adcode)) {
      await writePublicEdgeJson(edgeKey, area, AREA_TTL_MS / 1000);
      return area;
    }
    return null;
  })().then((area) => {
    if (areaCache.size >= 256) areaCache.delete(areaCache.keys().next().value);
    areaCache.set(key, { at: Date.now(), area });
    return area;
  }).finally(() => areaPending.delete(key));
  areaPending.set(key, load);
  return load;
}

async function inputTips(args: SearchArgs, area: AmapArea | null) {
  const payload = await amapGet(args.env, 'inputtips', {
    keywords: args.query,
    // Amap applies `location` only together with `city`; `citylimit=false`
    // keeps exact namesakes elsewhere available, ranked after local ones.
    location: gcjParameter(args.point),
    city: area?.citycode || area?.adcode,
    citylimit: 'false',
    datatype: 'all',
  }, requestOptions(args));
  return mapAmapTips(payload);
}

async function aroundSearch(args: SearchArgs) {
  const payload = await amapGet(args.env, 'place_around', {
    keywords: args.query,
    location: gcjParameter(args.point),
    radius: '50000',
    sortrule: 'weight',
    page_size: '15',
  }, requestOptions(args));
  return mapAmapPois(payload);
}

async function textSearch(args: SearchArgs, area: AmapArea | null) {
  const payload = await amapGet(args.env, 'place_text', {
    keywords: args.query,
    region: area?.citycode || area?.adcode,
    city_limit: 'false',
    page_size: '15',
  }, requestOptions(args));
  return mapAmapPois(payload);
}

function rankWithin(places: any[], query: string, point: LonLat) {
  return rankPlaces(dedupeSearchResults(places), query, point);
}

export interface MainlandSearchResult {
  results: any[];
  amapCount: number;
  usedOsmFallback: boolean;
  sources: AmapApi[];
}

/**
 * Amap first, ranked by relevance and proximity (a nearby exact-name compound
 * beats a distant namesake; every result carries `distanceMeters`). Search
 * quota is scarce (5,000 free calls a month), so each further Amap API is only
 * asked when the previous one returned fewer than MIN_AMAP_RESULTS places.
 */
export async function searchMainlandChina(args: SearchArgs): Promise<MainlandSearchResult> {
  const query = args.query.trim().slice(0, 80);
  const scoped = { ...args, query };
  const sources: AmapApi[] = [];
  const area = await amapAreaForPoint(args.env, args.point, requestOptions(args));
  let amap: any[] = [];
  const add = (api: AmapApi, places: any[]) => {
    if (places.length) sources.push(api);
    amap = dedupeSearchResults([...amap, ...places]);
  };
  if ((args.mode ?? 'suggest') === 'suggest') {
    add('inputtips', await attempt(() => inputTips(scoped, area), []));
    if (amap.length < MIN_AMAP_RESULTS) add('place_around', await attempt(() => aroundSearch(scoped), []));
    if (!amap.length) add('place_text', await attempt(() => textSearch(scoped, area), []));
  } else {
    const [around, text] = await Promise.all([
      attempt(() => aroundSearch(scoped), []),
      attempt(() => textSearch(scoped, area), []),
    ]);
    add('place_around', around);
    add('place_text', text);
  }
  let ranked = rankWithin(amap, query, args.point);
  let usedOsmFallback = false;
  if (ranked.length < MIN_AMAP_RESULTS && args.osmFallback) {
    const osm = await attempt(args.osmFallback, []);
    const extra = osm.filter((place) => place?.provider !== AMAP_PROVIDER && !duplicatesPrimary(place, amap));
    if (extra.length) {
      usedOsmFallback = true;
      // One ranking, Amap listed first so it wins exact ties: a local OSM
      // match still beats a distant Amap one, a distant OSM namesake never
      // outranks a local Amap place.
      ranked = rankWithin([...amap, ...extra], query, args.point);
    }
  }
  return { results: ranked.slice(0, RESULT_LIMIT), amapCount: amap.length, usedOsmFallback, sources };
}

const REVERSE_TTL_MS = 24 * 60 * 60 * 1000;
const reverseCache = new Map<string, { at: number; body: Record<string, unknown> }>();

/** `/api/reverse` in mainland China: the "current location" and long-press
 * labels. Coordinates are rounded to ~11 m before lookup and caching. */
export async function amapReverse(env: any, point: LonLat, language = 'en', options: AmapRequestOptions = {}) {
  const rounded: LonLat = [Math.round(point[0] * 1e4) / 1e4, Math.round(point[1] * 1e4) / 1e4];
  const key = `${language}|${rounded[0].toFixed(4)},${rounded[1].toFixed(4)}`;
  const cached = reverseCache.get(key);
  if (cached && Date.now() - cached.at < REVERSE_TTL_MS) return cached.body;
  const payload = await amapGet(env, 'regeo', { location: gcjParameter(rounded), extensions: 'base' },
    { timeoutMs: AMAP_SEARCH_TIMEOUT_MS, ...options });
  const regeocode = payload?.regeocode || {};
  const component = regeocode.addressComponent || {};
  const street = [amapText(component.streetNumber?.street), amapText(component.streetNumber?.number)].join('');
  const city = amapText(component.city) || amapText(component.province);
  const parts = [street || amapText(component.neighborhood?.name) || amapText(component.township),
    amapText(component.district), city].filter((part, index, all) => part && all.indexOf(part) === index);
  const label = language === 'zh' ? [...parts].reverse().join('') : parts.join(', ');
  const body = {
    label: label || amapText(regeocode.formatted_address),
    countryCode: 'CN',
    provider: AMAP_PROVIDER,
    attribution: AMAP_ATTRIBUTION,
  };
  if (!body.label) return null;
  if (reverseCache.size >= 512) reverseCache.delete(reverseCache.keys().next().value);
  reverseCache.set(key, { at: Date.now(), body });
  return body;
}
