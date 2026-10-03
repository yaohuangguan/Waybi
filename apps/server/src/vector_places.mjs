import { VectorTile } from '@mapbox/vector-tile';
import { PbfReader } from 'pbf';

export function tilePoiCategory(properties) {
  const type = properties.subclass || properties.class;
  if (type === 'cafe') return 'coffee';
  if (['restaurant', 'fast_food', 'food_court', 'bar', 'pub', 'bakery'].includes(type)) return 'food';
  if (['park', 'garden', 'nature_reserve', 'recreation_ground'].includes(type)) return 'parks';
  if (['attraction', 'museum', 'gallery', 'viewpoint', 'zoo', 'cinema', 'theatre', 'arts_centre', 'sports_centre', 'swimming_pool'].includes(type)) return 'activities';
  if (['shop', 'grocery', 'clothing_store'].includes(properties.class) || ['mall', 'department_store', 'books', 'clothes', 'supermarket'].includes(type)) return 'shopping';
  return null;
}

export function decodeTilePlaces(bytes, x, y, z, language) {
  const layer = new VectorTile(new PbfReader(bytes)).layers.poi;
  if (!layer) return [];
  const places = [];
  for (let i = 0; i < layer.length; i++) {
    const feature = layer.feature(i), tags = feature.properties;
    const primaryType = tilePoiCategory(tags);
    const name = language === 'zh' ? tags['name:zh'] || tags['name:zh-Hans'] || tags.name : tags.name || tags['name:en'];
    if (!name || !primaryType || feature.type !== 1) continue;
    const [longitude, latitude] = feature.toGeoJSON(x, y, z).geometry.coordinates;
    places.push({
      placeId: `omt:poi:${feature.id ?? `${x}:${y}:${i}`}`, provider: 'osm',
      name, englishName: tags['name:en'] || tags.name, primaryType, address: '',
      latitude, longitude, photoUrl: null, photoAttribution: '', photoCredit: null,
    });
  }
  return places;
}

// Reuse the exact open-data basemap. Four fixed tiles bound each cold query;
// the daily POI pool avoids decoding tiles again for category/search changes.
export async function nearbyTilePlaces(point, language, fetcher = fetch) {
  const metadata = await fetcher('https://tiles.openfreemap.org/planet', { signal: AbortSignal.timeout(5000) });
  if (!metadata.ok) throw new Error('Map metadata unavailable');
  const template = (await metadata.json()).tiles?.[0];
  if (!template || !template.startsWith('https://tiles.openfreemap.org/planet/')) throw new Error('Invalid open map tiles');
  const z = 14, n = 2 ** z;
  const tx = (point[0] + 180) / 360 * n;
  const ty = (1 - Math.asinh(Math.tan(point[1] * Math.PI / 180)) / Math.PI) / 2 * n;
  const left = Math.floor(tx) - (tx % 1 < .5 ? 1 : 0);
  const top = Math.floor(ty) - (ty % 1 < .5 ? 1 : 0);
  const results = await Promise.allSettled([0, 1, 2, 3].map(async offset => {
    const x = left + offset % 2, y = top + Math.floor(offset / 2);
    const url = template.replace('{z}', String(z)).replace('{x}', String(x)).replace('{y}', String(y));
    const response = await fetcher(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error('Open map tile unavailable');
    const bytes = await response.arrayBuffer();
    if (bytes.byteLength > 4 * 1024 * 1024) throw new Error('Map tile exceeds limit');
    return decodeTilePlaces(new Uint8Array(bytes), x, y, z, language);
  }));
  const seen = new Set();
  const places = results.flatMap(result => result.status === 'fulfilled' ? result.value : [])
    .filter(place => {
      const key = `${place.name.toLowerCase()}:${Math.round(place.latitude * 1000)}:${Math.round(place.longitude * 1000)}`;
      if (seen.has(key)) return false;
      seen.add(key); return true;
    });
  if (!places.length) throw new Error('No nearby tile places');
  return places;
}
