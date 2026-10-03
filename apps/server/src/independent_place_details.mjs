import { enrichPlacePhotos } from './independent_explore.mjs';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*', 'cache-control': 'no-store' },
});

export async function independentPlaceDetails(url, env, fetcher = fetch) {
  const point = (url.searchParams.get('at') || '').split(',').map(Number);
  const name = (url.searchParams.get('name') || '').trim();
  const address = (url.searchParams.get('address') || '').trim();
  const primaryType = (url.searchParams.get('type') || '').trim();
  if (point.length !== 2 || !(point[0] > 166 && point[0] < 179 && point[1] > -48 && point[1] < -34) ||
      !name || name.length > 160 || address.length > 500 || primaryType.length > 80) {
    return json({ error: 'Valid NZ place coordinates and name required' }, 400);
  }
  const placeId = url.searchParams.get('id') || '';
  const result = { placeId, name, address, primaryType, photos: [] };
  // Address results remain useful immediately without a speculative nearby photo.
  if (/^\d+[a-z]?\s/i.test(name)) return json(result);
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(name.toLowerCase()));
  const key = `waybi:place-photos:v1:${point.map(n => n.toFixed(5)).join(',')}:${Array.from(new Uint8Array(digest)).map(n => n.toString(16).padStart(2, '0')).join('')}`;
  const cached = await env.CAMERA_DATA?.get(key, 'json');
  if (Array.isArray(cached)) return json({ ...result, photos: cached });
  const place = { placeId, name, latitude: point[1], longitude: point[0] };
  try {
    await enrichPlacePhotos([place], point, fetcher, { radius: 500, includeLandmarks: false });
    if (place.photoUrl) result.photos.push({
      name: '', url: place.photoUrl, attribution: place.photoAttribution,
      sourceUrl: place.photoCredit?.sourceUrl || '',
      licenseUrl: place.photoCredit?.licenseUrl || '',
    });
    await env.CAMERA_DATA?.put(key, JSON.stringify(result.photos), { expirationTtl: result.photos.length ? 86400 : 3600 });
  } catch (_) {
    // Photo availability never prevents opening or navigating to a place.
  }
  return json(result);
}
