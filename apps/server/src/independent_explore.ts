import type { ProviderPayload } from "./types.ts";
import { validCoordinate } from './geo.ts';
import { readPublicEdgeJson, writePublicEdgeJson } from './public_edge_cache.ts';
const UA = 'Waybi/1.0 (https://github.com/yaohuangguan/Waybi)';
const RADIUS = 8000;
const GROUPS = ['activities', 'parks', 'food', 'coffee', 'shopping'];
const plain = value => String(value || '').replace(/<[^>]*>/g, '').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").trim();
const response = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*', 'cache-control': 'public, max-age=300' },
});
const distance = (a, b) => {
  const rad = Math.PI / 180, lat = (b[1] - a[1]) * rad, lon = (b[0] - a[0]) * rad;
  const h = Math.sin(lat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(lon / 2) ** 2;
  return 12742000 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
};
export function placeCategory(tags) {
  if (['cafe'].includes(tags.amenity)) return 'coffee';
  if (['restaurant', 'fast_food', 'food_court', 'bar', 'pub'].includes(tags.amenity) || tags.shop === 'bakery') return 'food';
  if (['park', 'garden', 'nature_reserve'].includes(tags.leisure)) return 'parks';
  if (tags.tourism || ['cinema', 'theatre', 'arts_centre'].includes(tags.amenity) || ['sports_centre', 'swimming_pool'].includes(tags.leisure)) return 'activities';
  if (tags.shop) return 'shopping';
  return null;
}
export function normalizeNearby(elements, point, language = 'en') {
  const seen = new Set();
  return (elements || []).flatMap(e => {
    const t = e.tags || {}, category = placeCategory(t);
    const name = language === 'zh' ? t['name:zh'] || t.name : t.name || t['name:en'];
    const latitude = Number(e.lat ?? e.center?.lat), longitude = Number(e.lon ?? e.center?.lon);
    if (!name || !category || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return [];
    const metres = distance(point, [longitude, latitude]);
    if (metres > RADIUS) return [];
    const dedupe = `${name.toLowerCase()}:${Math.round(latitude * 1000)}:${Math.round(longitude * 1000)}`;
    if (seen.has(dedupe)) return []; seen.add(dedupe);
    return [{ placeId: `osm:${e.type}:${e.id}`, provider: 'osm', name, primaryType: category,
      address: [t['addr:housenumber'], t['addr:street'], t['addr:suburb'] || t['addr:city']].filter(Boolean).join(' '),
      latitude, longitude, distance: metres, wikidata: /^Q\d+$/.test(t.wikidata || '') ? t.wikidata : '',
      wikipedia: t.wikipedia || '', commons: t.wikimedia_commons?.startsWith('File:') ? t.wikimedia_commons : '',
      photoUrl: null, photoAttribution: '', photoCredit: null }];
  });
}
export function selectNearby(places, point, category = 'for-you', query = '') {
  const search = query.trim().toLocaleLowerCase();
  const sorted = places.map(p => ({ ...p, distance: distance(point, [p.longitude, p.latitude]) }))
    .filter(p => p.distance <= RADIUS && (!search || `${p.name} ${p.address}`.toLocaleLowerCase().includes(search)))
    .sort((a, b) => a.distance - b.distance);
  if (category !== 'for-you') return sorted.filter(p => p.primaryType === category).slice(0, 20);
  // Round robin keeps dense cafe clusters from crowding out parks and sights.
  const queues = GROUPS.map(group => sorted.filter(p => p.primaryType === group)
    .sort((a, b) => Number(Boolean(b.photoUrl)) - Number(Boolean(a.photoUrl)) || a.distance - b.distance));
  const selected = [];
  while (selected.length < 20 && queues.some(q => q.length)) {
    for (const queue of queues) if (queue.length && selected.length < 20) selected.push(queue.shift());
  }
  return selected;
}
async function getJson(url, fetcher: typeof fetch) {
  const r = await fetcher(url, { headers: { 'user-agent': UA, accept: 'application/json' }, signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`Place media HTTP ${r.status}`);
  return r.json<ProviderPayload>();
}
function api(host, params) {
  const url = new URL(`https://${host}/w/api.php`);
  url.search = new URLSearchParams({ action: 'query', format: 'json', formatversion: '2', ...params }).toString(); return url;
}
export function commonsPhoto(page) {
  const image = page.imageinfo?.[0], meta = image?.extmetadata || {};
  const license = plain(meta.LicenseShortName?.value);
  const licenseUrl = meta.LicenseUrl?.value || '';
  const url = image?.thumburl || image?.url || '';
  // Only known freely reusable licenses and Wikimedia-hosted media are allowed.
  if (!/^(CC BY(?:-SA)? \d\.\d(?: [a-z]{2})?|CC0(?: 1\.0)?|Public domain)$/i.test(license) || !/^https:\/\/upload\.wikimedia\.org\//.test(url)) return null;
  if (license.startsWith('CC BY') && !/^https:\/\/creativecommons\.org\//.test(licenseUrl)) return null;
  const author = plain(meta.Artist?.value || meta.Credit?.value) || 'Wikimedia Commons';
  return { photoUrl: url, photoAttribution: `${author} · ${license}`,
    photoCredit: { author, license, licenseUrl, sourceUrl: image.descriptionurl || '', source: 'Wikimedia Commons' } };
}
export async function enrichPlacePhotos(places, point, fetcher: typeof fetch, { radius = RADIUS, includeLandmarks = true } = {}) {
  const files = new Map();
  for (const p of places) if (p.commons) files.set(p.placeId, p.commons);
  const ids = [...new Set(places.map(p => p.wikidata).filter(Boolean))].slice(0, 50);
  const entityTask = ids.length ? getJson(new URL(`https://www.wikidata.org/w/api.php?${new URLSearchParams({ action: 'wbgetentities', format: 'json', ids: ids.join('|'), props: 'claims' })}`), fetcher)
    .then(data => {
      for (const p of places) {
        const file = data.entities?.[p.wikidata]?.claims?.P18?.find(c => c.rank !== 'deprecated')?.mainsnak?.datavalue?.value;
        if (typeof file === 'string') files.set(p.placeId, `File:${file}`);
      }
    }) : Promise.resolve();
  const wikiTask = getJson(api('en.wikipedia.org', {
    generator: 'geosearch', ggscoord: `${point[1]}|${point[0]}`, ggsradius: String(radius), ggslimit: '30', ggsnamespace: '0',
    prop: 'pageimages|coordinates|pageprops|pageterms', wbptterms: 'label|alias', piprop: 'name', colimit: 'max',
  }), fetcher).then(data => {
    for (const page of data.query?.pages || []) {
      if (!page.pageimage) continue;
      const coordinate = page.coordinates?.find(c => c.primary) || page.coordinates?.[0];
      const normalized = name => String(name || '').split(/[,(]/)[0].toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
      const matches = places.filter(p => (p.wikidata && p.wikidata === page.pageprops?.wikibase_item) || p.wikipedia === `en:${page.title}` ||
        (coordinate && normalized(p.englishName || p.name).length > 4 &&
          [page.title, ...(page.terms?.label || []), ...(page.terms?.alias || [])].some(name => normalized(p.englishName || p.name) === normalized(name)) &&
          distance([p.longitude, p.latitude], [coordinate.lon, coordinate.lat]) < 150));
      for (const p of matches) files.set(p.placeId, `File:${page.pageimage}`);
      // Geotagged, photographed landmarks expand discovery beyond businesses.
      if (includeLandmarks && !matches.length && coordinate && !page.pageprops?.disambiguation && distance(point, [coordinate.lon, coordinate.lat]) <= radius) {
        const place = { placeId: `wikipedia:en:${page.pageid}`, provider: 'osm', name: page.title, address: '', primaryType: 'activities',
          latitude: coordinate.lat, longitude: coordinate.lon, photoUrl: null, photoAttribution: '', photoCredit: null };
        places.push(place); files.set(place.placeId, `File:${page.pageimage}`);
      }
    }
  });
  await Promise.allSettled([entityTask, wikiTask]);
  const titles = [...new Set(files.values())].slice(0, 50);
  if (!titles.length) return;
  const data = await getJson(api('commons.wikimedia.org', { titles: titles.join('|'), prop: 'imageinfo', iiprop: 'url|extmetadata', iiurlwidth: '640' }), fetcher);
  const photos = new Map((data.query?.pages || []).map(page => [page.title.replaceAll('_', ' '), commonsPhoto(page)]));
  for (const p of places) {
    const photo = photos.get(files.get(p.placeId)?.replaceAll('_', ' ')); if (photo) Object.assign(p, photo);
  }
  // Supplemental Wikipedia entries must have a usable real photo.
  for (let i = places.length - 1; i >= 0; i--) if (places[i].placeId.startsWith('wikipedia:') && !places[i].photoUrl) places.splice(i, 1);
}
async function loadNearby(env, point, language, origin: string, fetcher: typeof fetch) {
  const cell = point.map(n => Math.round(n * 100) / 100);
  // The input is rounded and public; this cache never contains personal data.
  const key = `${origin}/__edge-cache/explore/v3/${cell.join(',')}/${language}`;
  const cached = await readPublicEdgeJson<unknown>(key);
  if (Array.isArray(cached)) return cached;
  const around = `(around:${RADIUS},${cell[1]},${cell[0]})`;
  const selectors = ['[amenity~"^(cafe|restaurant|fast_food|food_court|bar|pub|cinema|theatre|arts_centre)$"]',
    '[leisure~"^(park|garden|nature_reserve|sports_centre|swimming_pool)$"]', '[tourism~"^(attraction|museum|gallery|viewpoint|zoo)$"]',
    '[shop~"^(mall|department_store|books|clothes|bakery|supermarket)$"]'];
  const query = `[out:json][timeout:20];(${selectors.map(s => `nwr${s}[name]${around};`).join('')});out center tags;`;
  let raw, lastError, places;
  try { places = await nearbyTilePlaces(cell, language, fetcher); } catch (error) { lastError = error; }
  for (const host of places ? [] : ['overpass.private.coffee', 'overpass-api.de']) {
    try {
      const r = await fetcher(`https://${host}/api/interpreter`, { method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': UA },
        body: new URLSearchParams({ data: query }), signal: AbortSignal.timeout(12000) });
      if (!r.ok) throw new Error(`Nearby places HTTP ${r.status}`);
      raw = await r.json<ProviderPayload>();
      if (raw.remark) throw new Error('Nearby query was incomplete');
      break;
    } catch (error) { raw = null; lastError = error; }
  }
  if (!places && !raw) {
    const previous = await readPublicEdgeJson<unknown>(`${key}/previous`);
    if (Array.isArray(previous) && previous.length) return previous;
    throw lastError;
  }
  places ??= normalizeNearby(raw.elements, cell, language);
  // Bound response/cache size while keeping a useful pool for each category.
  const pool = GROUPS.flatMap(group => selectNearby(places, cell, group).slice(0, 20));
  await enrichPlacePhotos(pool, cell, fetcher).catch(() => {});
  if (pool.length) {
    await writePublicEdgeJson(key, pool, 86400);
    await writePublicEdgeJson(`${key}/previous`, pool, 2592000);
  }
  return pool;
}
export async function independentExplore(url, env, fetcher: typeof fetch = fetch) {
  const point = (url.searchParams.get('at') || '').split(',').map(Number);
  if (point.length !== 2 || !validCoordinate(point[1], point[0])) return response({ error: 'Valid coordinates required' }, 400);
  const category = url.searchParams.get('category') || 'for-you', query = (url.searchParams.get('q') || '').trim();
  if (!['for-you', ...GROUPS].includes(category) || query.length > 120) return response({ error: 'Invalid category or query' }, 400);
  try {
    const places = await loadNearby(env, point, url.searchParams.get('lang') === 'zh' ? 'zh' : 'en', url.origin, fetcher);
    return response(selectNearby(places, point, category, query));
  } catch (error) {
    console.warn('Waybi explore upstream unavailable:', error.message);
    return response({ error: 'Nearby places are temporarily unavailable' }, 503);
  }
}
import { nearbyTilePlaces } from './vector_places.ts';
