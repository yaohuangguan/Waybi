import { mergeAndRankSearchResults, needsAddressEnrichment } from './search_orchestrator.mjs';

function text(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function mapGeoapifyPlaces(data) {
  return (data?.results || [])
    .filter((place) => Number.isFinite(place?.lat) && Number.isFinite(place?.lon))
    .map((place) => {
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
      const formatted = text(place.formatted) || [place.address_line1, place.address_line2]
        .map(text)
        .filter(Boolean)
        .join(', ');
      const namedPlace = Boolean(
        place.name &&
        place.address_line1 &&
        place.name !== place.address_line1 &&
        formatted.startsWith(place.name)
      );
      const isPoi = categoryPoi || (namedPlace && !addressTypes.has(place.result_type));
      const address = [place.address_line1, place.address_line2]
        .map(text)
        .filter(Boolean)
        .join(', ') || formatted;
      return {
        id: place.place_id || place.datasource?.raw?.osm_id || formatted,
        provider: 'geoapify',
        name: isPoi ? (text(place.name) || text(place.address_line1) || formatted) : formatted,
        address: isPoi ? address : formatted,
        label: formatted,
        isPoi,
        resultType: place.result_type || '',
        latitude: Number(place.lat),
        longitude: Number(place.lon)
      };
    });
}

function mapPhotonPlaces(data) {
  return (data?.features || []).flatMap((feature) => {
    const props = feature?.properties || {};
    const coordinates = feature?.geometry?.coordinates;
    if (!Array.isArray(coordinates) ||
        !Number.isFinite(coordinates[0]) ||
        !Number.isFinite(coordinates[1])) return [];
    const street = [props.housenumber, props.street]
      .map(text)
      .filter(Boolean)
      .join(' ');
    const name = text(props.name) || street || text(props.city) || text(props.country) || 'Place';
    const parts = [
      street,
      props.district,
      props.locality,
      props.city,
      props.state,
      props.postcode,
      props.country
    ].map(text).filter(Boolean);
    const seen = new Set();
    const address = parts.filter((part) => {
      const key = part.toLocaleLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    }).join(', ');
    const isPoi = ['shop', 'amenity', 'tourism', 'leisure', 'office', 'craft']
      .includes(String(props.osm_key || ''));
    return [{
      id: `${props.osm_type || ''}:${props.osm_id || ''}`,
      provider: 'osm',
      name,
      address,
      label: address || name,
      isPoi,
      resultType: props.osm_value || '',
      latitude: Number(coordinates[1]),
      longitude: Number(coordinates[0])
    }];
  });
}

async function fetchGeoapify({ query, point, language, apiKey, trackUsage }) {
  if (!apiKey) return [];
  const url = new URL('https://api.geoapify.com/v1/geocode/autocomplete');
  url.searchParams.set('text', query);
  url.searchParams.set('lang', language === 'zh' ? 'zh' : 'en');
  url.searchParams.set('limit', '10');
  url.searchParams.set('format', 'json');
  url.searchParams.set('apiKey', apiKey);
  if (point) url.searchParams.set('bias', `proximity:${point.join(',')}`);
  trackUsage('geoapify', 'autocomplete', 1);
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3500) });
    if (!response.ok) return [];
    return mapGeoapifyPlaces(await response.json());
  } catch {
    return [];
  }
}

async function fetchPhoton({ query, point, language, trackUsage }) {
  const url = new URL('https://photon.komoot.io/api/');
  url.searchParams.set('q', query);
  url.searchParams.set('limit', '10');
  url.searchParams.set('lang', language === 'zh' ? 'en' : language || 'en');
  if (point) {
    url.searchParams.set('lon', String(point[0]));
    url.searchParams.set('lat', String(point[1]));
    url.searchParams.set('location_bias_scale', '0.18');
  }
  trackUsage('osm', 'photon_autocomplete', 1);
  try {
    const response = await fetch(url, {
      headers: {
        'user-agent': 'Waybi/1.0 (+https://waybi.co)',
        accept: 'application/json'
      },
      signal: AbortSignal.timeout(3000)
    });
    if (!response.ok) return [];
    return mapPhotonPlaces(await response.json());
  } catch {
    return [];
  }
}

/// Search stack used by Waybi's Independent map. It deliberately never calls
/// Google Places: coordinates from every returned provider are safe to render,
/// route to and navigate to on Waybi's own map.
export async function searchIndependentGlobal({
  query,
  point,
  language = 'en',
  env,
  trackUsage = () => {},
  enrichmentsPromise = Promise.resolve([])
}) {
  const geoPromise = fetchGeoapify({
    query,
    point,
    language,
    apiKey: env?.GEOAPIFY_API_KEY,
    trackUsage
  });
  const [geoapify, enrichments] = await Promise.all([
    geoPromise,
    enrichmentsPromise.catch(() => [])
  ]);

  // Geoapify is the primary worldwide autocomplete/address source. Regional
  // official data is merged in when available. Photon is a global open-data
  // fallback only when the primary stack is sparse or misses address detail.
  if (geoapify.length && !needsAddressEnrichment(geoapify, query)) {
    return mergeAndRankSearchResults([enrichments, geoapify], query, point, 12);
  }

  const photon = await fetchPhoton({ query, point, language, trackUsage });
  return mergeAndRankSearchResults(
    [enrichments, geoapify, photon],
    query,
    point,
    12
  );
}
