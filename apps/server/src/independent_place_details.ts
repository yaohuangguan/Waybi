import type { ProviderPayload } from "./types.ts";
import type { PlacePhotoCandidate } from './types.ts';
import { validCoordinate } from './geo.ts';
import { enrichPlacePhotos } from './independent_explore.ts';
import { readPublicEdgeJson, writePublicEdgeJson } from './public_edge_cache.ts';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*', 'cache-control': 'no-store' },
});

async function selectedMediaTags(placeId, point, name, fetcher: typeof fetch) {
  const match = /^(?:osm:)?(node|way|relation|N|W|R):([1-9]\d{0,12})$/.exec(placeId);
  if (!match) return {};
  const type = ({ N: 'node', W: 'way', R: 'relation' })[match[1]] || match[1];
  try {
    const response = await fetcher(new URL(`https://www.openstreetmap.org/api/0.6/${type}/${match[2]}.json`), {
      headers: { 'user-agent': 'Waybi/1.0 (https://github.com/yaohuangguan/Waybi)', accept: 'application/json' },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return {};
    const element = (await response.json<ProviderPayload>()).elements?.find(e => String(e.id) === match[2] && e.type === type);
    const tags = element?.tags || {};
    const names = [tags.name, tags['name:en'], tags['name:zh'], tags.alt_name, tags.short_name]
      .filter(Boolean).flatMap(n => n.split(';')).map(n => n.trim().toLowerCase());
    if (!names.includes(name.toLowerCase())) return {};
    if (type === 'node' && (!Number.isFinite(element.lat) || !Number.isFinite(element.lon) ||
        Math.hypot(element.lat - point[1], (element.lon - point[0]) * Math.cos(point[1] * Math.PI / 180)) > .0014)) return {};
    return { wikidata: /^Q\d+$/.test(tags.wikidata || '') ? tags.wikidata : '',
      wikipedia: tags.wikipedia || '', commons: tags.wikimedia_commons?.startsWith('File:') ? tags.wikimedia_commons : '' };
  } catch (_) { return {}; }
}

export async function independentPlaceDetails(url, env, fetcher: typeof fetch = fetch) {
  const point = (url.searchParams.get('at') || '').split(',').map(Number);
  const name = (url.searchParams.get('name') || '').trim();
  const address = (url.searchParams.get('address') || '').trim();
  const primaryType = (url.searchParams.get('type') || '').trim();
  if (point.length !== 2 || !validCoordinate(point[1], point[0]) ||
      !name || name.length > 160 || address.length > 500 || primaryType.length > 80) {
    return json({ error: 'Valid place coordinates and name required' }, 400);
  }
  const placeId = url.searchParams.get('id') || '';
  const result = { placeId, name, address, primaryType, photos: [] };
  // Address results remain useful immediately without a speculative nearby photo.
  if (/^\d+[a-z]?\s/i.test(name)) return json(result);
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(name.toLowerCase()));
  const key = `${url.origin}/__edge-cache/place-photos/v3/${point.map(n => n.toFixed(5)).join(',')}/${Array.from(new Uint8Array(digest)).map(n => n.toString(16).padStart(2, '0')).join('')}`;
  const cached = await readPublicEdgeJson<unknown>(key);
  if (Array.isArray(cached)) return json({ ...result, photos: cached });
  const place: PlacePhotoCandidate = { placeId, name, latitude: point[1], longitude: point[0] };
  try {
    Object.assign(place, await selectedMediaTags(placeId, point, name, fetcher));
    await enrichPlacePhotos([place], point, fetcher, { radius: 500, includeLandmarks: false });
    if (place.photoUrl) result.photos.push({
      name: '', url: place.photoUrl, attribution: place.photoAttribution,
      sourceUrl: place.photoCredit?.sourceUrl || '',
      licenseUrl: place.photoCredit?.licenseUrl || '',
    });
    await writePublicEdgeJson(key, result.photos, result.photos.length ? 86400 : 3600);
  } catch (_) {
    // Photo availability never prevents opening or navigating to a place.
  }
  return json(result);
}
