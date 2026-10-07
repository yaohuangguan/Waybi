import type { ProviderPayload } from "./types.ts";
import { validCoordinate } from './geo.ts';

const categoryMap = {
  'for-you': 'tourism,leisure.park,catering',
  food: 'catering.restaurant,catering.fast_food',
  coffee: 'catering.cafe',
  activities: 'tourism,entertainment',
  shopping: 'commercial',
  parks: 'leisure.park',
};
export async function geoapifyExplore(url, env) {
  const headers = { 'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store', 'access-control-allow-origin': '*' };
  const result = (body, status = 200) =>
      new Response(JSON.stringify(body), { status, headers });
  if (!env.GEOAPIFY_API_KEY) {
    return result({ error: 'Map-compatible places are not configured' }, 503);
  }
  const [lon, lat] = (url.searchParams.get('at') || '').split(',').map(Number);
  if (!validCoordinate(lat, lon)) {
    return result({ error: 'Valid coordinates required' }, 400);
  }
  const query = (url.searchParams.get('q') || '').trim();
  if (query.length > 120) return result({ error: 'Query is too long' }, 400);
  const textSearch = query.length >= 2;
  const upstream = new URL(textSearch
      ? 'https://api.geoapify.com/v1/geocode/search'
      : 'https://api.geoapify.com/v2/places');
  upstream.searchParams.set('apiKey', env.GEOAPIFY_API_KEY);
  upstream.searchParams.set('lang', url.searchParams.get('lang') === 'zh' ? 'zh' : 'en');
  upstream.searchParams.set('limit', '20');
  upstream.searchParams.set('bias', 'proximity:' + lon + ',' + lat);
  if (textSearch) {
    upstream.searchParams.set('text', query);
  } else {
    upstream.searchParams.set('categories',
        categoryMap[url.searchParams.get('category')] || categoryMap['for-you']);
    upstream.searchParams.set('filter', 'circle:' + lon + ',' + lat + ',12000');
  }
  try {
    const response = await fetch(upstream, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) return result({ error: 'Nearby places unavailable' }, 502);
    const data = await response.json<ProviderPayload>();
    const places = (data.features || []).map((feature) => {
      const p = feature.properties || {};
      return {
        provider: 'geoapify', placeId: p.place_id || '',
        name: p.name || p.address_line1 || p.formatted || 'Nearby place',
        address: p.formatted || [p.address_line1, p.address_line2].filter(Boolean).join(', '),
        primaryType: (p.categories || []).join(', '),
        latitude: p.lat ?? feature.geometry?.coordinates?.[1],
        longitude: p.lon ?? feature.geometry?.coordinates?.[0],
        rating: null, userRatingCount: null, openNow: null,
        priceLevel: null, photoName: '', photoAttribution: '',
      };
    }).filter((p) => p.placeId && Number.isFinite(p.latitude) &&
        Number.isFinite(p.longitude));
    return result(places);
  } catch {
    return result({ error: 'Nearby places unavailable' }, 502);
  }
}
