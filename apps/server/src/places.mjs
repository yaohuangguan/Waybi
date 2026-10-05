import { independentExplore } from './independent_explore.mjs';
import { geoapifyExplore } from './compatible_places.mjs';
import { parseLonLat } from './geo.mjs';
import { rankPlaces } from './place_search_rank.mjs';
import { loadSearchEnrichments, mergeAndRankSearchResults, needsAddressEnrichment } from './search/search_orchestrator.mjs';
import { searchIndependentGlobal } from './search/independent_global_search.mjs';
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'access-control-allow-origin': '*' }
  });
}

function geoPoint(value) { return parseLonLat(value); }

function placesApiKey(env) {
  return env.GOOGLE_PLACES_SERVER_API_KEY || env.GOOGLE_ROUTES_API_KEY;
}

function partialNumberedStreetPrefix(query) {
  const match = String(query).trim().match(/^\d+[A-Za-z]?(?:[-/]\d+[A-Za-z]?)?\s+([\p{L}\p{M}]{2,5})$/u);
  return match ? match[1] : '';
}

function localizedText(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  return typeof value.text === 'string' ? value.text : '';
}

const GOOGLE_ADDRESS_TYPES = new Set([
  'street_address', 'premise', 'subpremise', 'route', 'postal_code',
  'intersection', 'plus_code'
]);

export function googlePlaceIsPoi(place, query = '') {
  const types = Array.isArray(place?.types) ? place.types : [];
  if (types.some((type) => GOOGLE_ADDRESS_TYPES.has(type))) return false;
  const formatted = String(place?.formattedAddress || '').trim().toLowerCase();
  const requestedHouse = String(query).trim().match(/^\d+[A-Za-z]?(?:[-/]\d+[A-Za-z]?)?\s+/)?.[0]?.trim().toLowerCase();
  return !(requestedHouse && formatted.startsWith(requestedHouse + ' '));
}


function isGeoapifyPoi(place) {
  if (!place?.name) return false;
  const categories = Array.isArray(place.categories) ? place.categories : [];
  const poiPrefixes = [
    'accommodation', 'activity', 'amenity', 'catering', 'commercial',
    'education', 'entertainment', 'healthcare', 'leisure', 'office',
    'parking', 'pet', 'public_transport', 'religion', 'service', 'sport',
    'tourism'
  ];
  const categoryPoi = categories.some((category) =>
    poiPrefixes.some((prefix) => category === prefix || category.startsWith(prefix + '.'))
  );
  const addressTypes = new Set([
    'street', 'postcode', 'district', 'suburb', 'city', 'county', 'state', 'country'
  ]);
  const namedPlace = Boolean(
    place.address_line1 &&
    place.name !== place.address_line1 &&
    String(place.formatted || '').startsWith(place.name)
  );
  return categoryPoi || (namedPlace && !addressTypes.has(place.result_type));
}

export async function handlePlaces(request, env, trackUsage = () => {}) {
  const url = new URL(request.url);
  if (url.pathname === '/api/suggest') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const query = (url.searchParams.get('q') || '').trim();
    if (query.length < 2 || query.length > 120) {
      return json({ error: 'Query must be 2–120 characters' }, 400);
    }

    const point = geoPoint(url.searchParams.get('near'));
    const enrichmentPromise = loadSearchEnrichments(query, point).catch(() => []);
    // While a user is still typing a numbered street prefix (for example
    // "42 veri"), a regional official-address adapter can often answer in
    // ~200 ms. Return that useful typeahead immediately instead of making the
    // UI wait for a slower global provider. Outside an adapter service area
    // this resolves empty and the normal global path continues unchanged.
    if (point && partialNumberedStreetPrefix(query)) {
      const fastEnrichments = await Promise.race([
        enrichmentPromise,
        new Promise((resolve) => setTimeout(() => resolve([]), 320))
      ]);
      if (fastEnrichments.length) {
        return json(mergeAndRankSearchResults([fastEnrichments], query, point, 12));
      }
    }
    const prefersChinese = url.searchParams.get('lang') === 'zh' || /[\u3400-\u9fff\uf900-\ufaff]/u.test(query);
    const requestedProvider = url.searchParams.get('provider') || '';
    if (requestedProvider === 'independent') {
      const results = await searchIndependentGlobal({
        query,
        point,
        language: prefersChinese ? 'zh' : 'en',
        env,
        trackUsage,
        enrichmentsPromise: enrichmentPromise
      });
      if (results.length) return json(results);
      return json({ error: 'Independent place search unavailable' }, 502);
    }
    const googleKey = placesApiKey(env);
    if (googleKey && requestedProvider !== 'geoapify') {
      const body = {
        textQuery: query,
        languageCode: prefersChinese ? 'zh-CN' : 'en',
        pageSize: 12
      };
      if (point) {
        body.locationBias = {
          circle: {
            center: { latitude: point[1], longitude: point[0] },
            radius: 50000
          }
        };
      }
      trackUsage('google', 'places_text_search', 1);
      const google = await fetch('https://places.googleapis.com/v1/places:searchText', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'X-Goog-Api-Key': googleKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.primaryTypeDisplayName,places.types'
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10000)
      });
      const mapGooglePlaces = (data) => (data.places || []).map((place) => ({
        id: place.id || place.formattedAddress || '',
        provider: 'google',
        name: localizedText(place.displayName) || place.formattedAddress || query,
        address: place.formattedAddress || '',
        label: place.formattedAddress || localizedText(place.displayName) || query,
        isPoi: googlePlaceIsPoi(place, query),
        resultType: localizedText(place.primaryTypeDisplayName),
        latitude: Number(place.location?.latitude),
        longitude: Number(place.location?.longitude)
      })).filter((place) => Number.isFinite(place.latitude) && Number.isFinite(place.longitude));
      let local = [];
      if (google.ok) {
        local = mapGooglePlaces(await google.json());
        if (local.length) {
          if (!needsAddressEnrichment(local, query)) {
            return json(mergeAndRankSearchResults([local], query, point, 12));
          }
          const enrichments = await enrichmentPromise;
          return json(
            mergeAndRankSearchResults([enrichments, local], query, point, 12)
          );
        }
      }

      trackUsage('google', 'places_text_search', 1);
      const globalGoogle = await fetch('https://places.googleapis.com/v1/places:searchText', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'X-Goog-Api-Key': googleKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.primaryTypeDisplayName,places.types'
        },
        body: JSON.stringify({
          textQuery: query,
          languageCode: prefersChinese ? 'zh-CN' : 'en',
          pageSize: 12
        }),
        signal: AbortSignal.timeout(10000)
      });
      if (globalGoogle.ok) {
        const global = mapGooglePlaces(await globalGoogle.json());
        const enrichments = await enrichmentPromise;
        const merged = mergeAndRankSearchResults(
          [enrichments, local, global], query, point, 12
        );
        if (merged.length) return json(merged);
      }
      if (local.length) {
        if (!needsAddressEnrichment(local, query)) {
          return json(mergeAndRankSearchResults([local], query, point, 12));
        }
        const enrichments = await enrichmentPromise;
        return json(mergeAndRankSearchResults([enrichments, local], query, point, 12));
      }
    }

    if (!env.GEOAPIFY_API_KEY) {
      const enrichments = await enrichmentPromise;
      if (enrichments.length) {
        return json(mergeAndRankSearchResults([enrichments], query, point, 12));
      }
      return json({ error: 'Place search is not configured' }, 503);
    }
    const mapGeoapifyPlaces = (data) => (data.results || []).filter((place) =>
      Number.isFinite(place.lat) && Number.isFinite(place.lon)
    ).map((place) => {
      const isPoi = isGeoapifyPoi(place);
      const fullAddress = place.formatted || [place.address_line1, place.address_line2].filter(Boolean).join(', ');
      const streetAddress = [place.address_line1, place.address_line2].filter(Boolean).join(', ');
      const name = isPoi
        ? (place.name || place.address_line1 || fullAddress)
        : fullAddress;
      return {
        id: place.place_id || place.datasource?.raw?.osm_id || fullAddress,
        provider: 'geoapify',
        name,
        address: isPoi ? (streetAddress || fullAddress) : fullAddress,
        label: fullAddress,
        isPoi,
        resultType: place.result_type || '',
        latitude: place.lat,
        longitude: place.lon
      };
    });
    const buildGeoapifyUrl = ({ localFirst }) => {
      const provider = new URL('https://api.geoapify.com/v1/geocode/autocomplete');
      provider.searchParams.set('text', query);
      provider.searchParams.set('lang', prefersChinese ? 'zh' : 'en');
      provider.searchParams.set('limit', '6');
      provider.searchParams.set('format', 'json');
      provider.searchParams.set('apiKey', env.GEOAPIFY_API_KEY);
      if (localFirst && point) {
        provider.searchParams.set('bias', `proximity:${point.join(',')}`);
      }
      return provider;
    };

    trackUsage('geoapify', 'autocomplete', 1);
    const localUpstream = await fetch(buildGeoapifyUrl({ localFirst: true }), {
      signal: AbortSignal.timeout(10000)
    });
    if (localUpstream.ok) {
      const local = mapGeoapifyPlaces(await localUpstream.json());
      if (local.length) {
        if (!needsAddressEnrichment(local, query)) {
          return json(mergeAndRankSearchResults([local], query, point, 12));
        }
        const enrichments = await enrichmentPromise;
        return json(mergeAndRankSearchResults([enrichments, local], query, point, 12));
      }
    }

    trackUsage('geoapify', 'autocomplete', 1);
    const globalUpstream = await fetch(buildGeoapifyUrl({ localFirst: false }), {
      signal: AbortSignal.timeout(10000)
    });
    if (!globalUpstream.ok) return json({ error: 'Address autocomplete unavailable' }, 502);
    const enrichments = await enrichmentPromise;
    return json(
      mergeAndRankSearchResults(
        [enrichments, mapGeoapifyPlaces(await globalUpstream.json())],
        query,
        point,
        12
      )
    );
  }
  if (url.pathname === '/api/explore') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    if (url.searchParams.get('provider') === 'osm') return independentExplore(url, env);
    if (url.searchParams.get('provider') === 'geoapify') {
      return geoapifyExplore(url, env);
    }
    const apiKey = placesApiKey(env);
    if (!apiKey) return json({ error: 'Google Places server key is not configured' }, 503);
    const point = geoPoint(url.searchParams.get('at'));
    if (!point) return json({ error: 'Valid coordinates required' }, 400);
    const query = (url.searchParams.get('q') || '').trim();
    const category = (url.searchParams.get('category') || 'for-you').trim();
    const languageCode = url.searchParams.get('lang') === 'zh' ? 'zh-CN' : 'en';
    const categoryTypes = {
      'for-you': ['tourist_attraction', 'museum', 'art_gallery', 'park', 'cafe', 'restaurant', 'shopping_mall'],
      food: ['restaurant', 'cafe', 'bakery', 'bar'],
      coffee: ['cafe', 'bakery'],
      activities: ['tourist_attraction', 'museum', 'art_gallery', 'amusement_center', 'bowling_alley', 'movie_theater'],
      shopping: ['shopping_mall', 'department_store', 'clothing_store', 'book_store'],
      parks: ['park']
    };
    const fieldMask = [
      'places.id', 'places.displayName', 'places.formattedAddress',
      'places.primaryTypeDisplayName,places.types', 'places.rating', 'places.userRatingCount',
      'places.priceLevel', 'places.currentOpeningHours.openNow',
      'places.photos', 'places.location', 'places.types'
    ].join(',');
    let provider;
    let body;
    if (query.length >= 2) {
      provider = 'https://places.googleapis.com/v1/places:searchText';
      body = {
        textQuery: query,
        languageCode,
        maxResultCount: 18,
        locationBias: {
          circle: {
            center: { latitude: point[1], longitude: point[0] },
            radius: 12000
          }
        }
      };
    } else {
      provider = 'https://places.googleapis.com/v1/places:searchNearby';
      body = {
        languageCode,
        maxResultCount: 18,
        includedTypes: categoryTypes[category] || categoryTypes['for-you'],
        rankPreference: 'POPULARITY',
        locationRestriction: {
          circle: {
            center: { latitude: point[1], longitude: point[0] },
            radius: 10000
          }
        }
      };
    }
    trackUsage('google', query.length >= 2 ? 'places_text_search' : 'places_nearby_search', 1);
    const upstream = await fetch(provider, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': fieldMask
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(12000)
    });
    if (!upstream.ok) {
      return json({ error: 'Google Places explore HTTP ' + upstream.status }, 502);
    }
    const data = await upstream.json();
    return json((data.places || []).map((place) => ({
      placeId: place.id || '',
      name: localizedText(place.displayName) || 'Nearby place',
      address: place.formattedAddress || '',
      primaryType: localizedText(place.primaryTypeDisplayName),
      rating: Number.isFinite(place.rating) ? place.rating : null,
      userRatingCount: Number.isFinite(place.userRatingCount) ? place.userRatingCount : null,
      priceLevel: place.priceLevel || null,
      openNow: typeof place.currentOpeningHours?.openNow === 'boolean'
        ? place.currentOpeningHours.openNow
        : null,
      latitude: Number(place.location?.latitude),
      longitude: Number(place.location?.longitude),
      photoName: place.photos?.find((photo) => photo?.name)?.name || '',
      photoAttribution: (place.photos?.[0]?.authorAttributions || [])
        .map((author) => author.displayName)
        .filter(Boolean)
        .join(', ')
    })).filter((place) =>
      place.placeId &&
      Number.isFinite(place.latitude) &&
      Number.isFinite(place.longitude)
    ));
  }

  if (url.pathname === '/api/place-details') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const apiKey = placesApiKey(env);
    if (!apiKey) return json({ error: 'Google Places server key is not configured' }, 503);
    const placeId = (url.searchParams.get('placeId') || '').trim();
    if (!/^[A-Za-z0-9_-]{8,300}$/.test(placeId)) return json({ error: 'Valid Google Place ID required' }, 400);
    const provider = new URL(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`);
    provider.searchParams.set('languageCode', url.searchParams.get('lang') === 'zh' ? 'zh-CN' : 'en');
    const fieldMask = [
      'id', 'displayName', 'formattedAddress', 'primaryTypeDisplayName', 'rating',
      'userRatingCount', 'businessStatus', 'priceLevel', 'nationalPhoneNumber',
      'websiteUri', 'googleMapsUri', 'editorialSummary', 'regularOpeningHours',
      'photos', 'reviews'
    ].join(',');
    trackUsage('google', 'place_details', 1);
    const upstream = await fetch(provider, {
      headers: { 'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': fieldMask },
      signal: AbortSignal.timeout(12000)
    });
    if (!upstream.ok) return json({ error: `Google Places HTTP ${upstream.status}` }, upstream.status === 404 ? 404 : 502);
    const place = await upstream.json();
    return json({
      placeId: place.id || placeId,
      name: localizedText(place.displayName) || 'Selected place',
      address: place.formattedAddress || '',
      primaryType: localizedText(place.primaryTypeDisplayName),
      rating: Number.isFinite(place.rating) ? place.rating : null,
      userRatingCount: Number.isFinite(place.userRatingCount) ? place.userRatingCount : null,
      businessStatus: place.businessStatus || null,
      priceLevel: place.priceLevel || null,
      phone: place.nationalPhoneNumber || '',
      websiteUri: place.websiteUri || '',
      googleMapsUri: place.googleMapsUri || '',
      editorialSummary: localizedText(place.editorialSummary),
      openingHours: place.regularOpeningHours?.weekdayDescriptions || [],
      photos: (place.photos || []).slice(0, 8).filter((photo) => photo?.name).map((photo) => ({
        name: photo.name,
        attribution: (photo.authorAttributions || []).map((author) => author.displayName).filter(Boolean).join(', ')
      })),
      reviews: (place.reviews || []).slice(0, 5).map((review) => ({
        author: review.authorAttribution?.displayName || 'Google user',
        authorPhoto: review.authorAttribution?.photoUri || null,
        rating: Number.isFinite(review.rating) ? review.rating : null,
        text: localizedText(review.text) || localizedText(review.originalText),
        relativeTime: review.relativePublishTimeDescription || '',
        googleMapsUri: review.googleMapsUri || null
      }))
    });
  }
  if (url.pathname === '/api/place-photo') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const apiKey = placesApiKey(env);
    if (!apiKey) return json({ error: 'Google Places server key is not configured' }, 503);
    const name = (url.searchParams.get('name') || '').trim();
    if (!/^places\/[^/]+\/photos\/[^/]+$/.test(name)) return json({ error: 'Valid photo name required' }, 400);
    const provider = new URL(`https://places.googleapis.com/v1/${name}/media`);
    provider.searchParams.set('maxWidthPx', '1200');
    provider.searchParams.set('key', apiKey);
    trackUsage('google', 'place_photo', 1);
    const upstream = await fetch(provider, { redirect: 'follow', signal: AbortSignal.timeout(12000) });
    if (!upstream.ok) return json({ error: `Google Place Photo HTTP ${upstream.status}` }, 502);
    return new Response(upstream.body, {
      status: 200,
      headers: {
        'content-type': upstream.headers.get('content-type') || 'image/jpeg',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*'
      }
    });
  }
  if (url.pathname === '/api/reverse') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const point = geoPoint(url.searchParams.get('at'));
    if (!point) return json({ error: 'Valid coordinates required' }, 400);
    const provider = new URL('https://nominatim.openstreetmap.org/reverse');
    provider.searchParams.set('format', 'jsonv2');
    provider.searchParams.set('lat', String(point[1]));
    provider.searchParams.set('lon', String(point[0]));
    provider.searchParams.set('zoom', '14');
    provider.searchParams.set('addressdetails', '1');
    const upstream = await fetch(provider, {
      headers: { 'user-agent': 'Waybi/0.1 (https://github.com/yaohuangguan/Waybi)',
        referer: 'https://github.com/yaohuangguan/Waybi', accept: 'application/json' },
      signal: AbortSignal.timeout(10000)
    });
    if (!upstream.ok) return json({ error: 'Current-place lookup unavailable' }, 502);
    const data = await upstream.json();
    const address = data.address || {};
    return json({ label: [address.road || address.suburb || address.neighbourhood,
      address.suburb || address.city || address.town || address.village,
      address.city || address.town || address.region].filter(Boolean).filter((item, index, values) => values.indexOf(item) === index).join(', ') || data.display_name,
      countryCode: typeof address.country_code === 'string' && /^[a-z]{2}$/i.test(address.country_code) ? address.country_code.toUpperCase() : null });
  }
  return null;
}
