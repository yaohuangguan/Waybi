import {
  mergeAndRankSearchResults,
  needsAddressEnrichment,
} from './search_orchestrator.mjs';

const SEARCH_CACHE_TTL_MS = 5 * 60 * 1000;
const SEARCH_CACHE_MAX = 160;
const searchCache = new Map();
const searchPending = new Map();

function cacheKey(query, point, language) {
  return [
    String(query || '').trim().toLocaleLowerCase(),
    language || 'en',
    point ? Number(point[0]).toFixed(2) : '',
    point ? Number(point[1]).toFixed(2) : '',
  ].join('|');
}

function readCache(key) {
  const cached = searchCache.get(key);
  if (!cached) return null;
  if (Date.now() - cached.at > SEARCH_CACHE_TTL_MS) {
    searchCache.delete(key);
    return null;
  }
  return cached.results;
}

function writeCache(key, results) {
  if (!Array.isArray(results) || !results.length) return results;
  if (searchCache.size >= SEARCH_CACHE_MAX) {
    searchCache.delete(searchCache.keys().next().value);
  }
  searchCache.set(key, { at: Date.now(), results });
  return results;
}

function text(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function mapGeoapifyPlaces(data) {
  return (data?.results || [])
    .filter((place) => Number.isFinite(place?.lat) && Number.isFinite(place?.lon))
    .map((place) => {
      const categories = Array.isArray(place.categories) ? place.categories : [];
      const poiPrefixes = [
        'accommodation',
        'activity',
        'amenity',
        'catering',
        'commercial',
        'education',
        'entertainment',
        'healthcare',
        'leisure',
        'office',
        'parking',
        'pet',
        'public_transport',
        'religion',
        'service',
        'sport',
        'tourism',
      ];
      const categoryPoi = categories.some((category) =>
        poiPrefixes.some(
          (prefix) => category === prefix || category.startsWith(prefix + '.')
        )
      );
      const addressTypes = new Set([
        'street',
        'postcode',
        'district',
        'suburb',
        'city',
        'county',
        'state',
        'country',
      ]);
      const formatted =
        text(place.formatted) ||
        [place.address_line1, place.address_line2]
          .map(text)
          .filter(Boolean)
          .join(', ');
      const namedPlace = Boolean(
        place.name &&
          place.address_line1 &&
          place.name !== place.address_line1 &&
          formatted.startsWith(place.name)
      );
      const isPoi =
        categoryPoi || (namedPlace && !addressTypes.has(place.result_type));
      const address =
        [place.address_line1, place.address_line2]
          .map(text)
          .filter(Boolean)
          .join(', ') || formatted;
      return {
        id: place.place_id || place.datasource?.raw?.osm_id || formatted,
        provider: 'geoapify',
        sourceName: 'Geoapify',
        name: isPoi
          ? text(place.name) || text(place.address_line1) || formatted
          : formatted,
        address: isPoi ? address : formatted,
        label: formatted,
        isPoi,
        resultType: place.result_type || '',
        latitude: Number(place.lat),
        longitude: Number(place.lon),
      };
    });
}

function mapTomTomPlaces(data) {
  return (data?.results || []).flatMap((place) => {
    const latitude = Number(place?.position?.lat);
    const longitude = Number(place?.position?.lon);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return [];

    const freeform = text(place?.address?.freeformAddress);
    const streetNumber = text(place?.address?.streetNumber);
    const streetName = text(place?.address?.streetName);
    const streetAddress = [streetNumber, streetName].filter(Boolean).join(' ');
    const locality = [
      place?.address?.municipalitySubdivision,
      place?.address?.municipality,
      place?.address?.countrySecondarySubdivision,
      place?.address?.countrySubdivision,
      place?.address?.postalCode,
      place?.address?.country,
    ]
      .map(text)
      .filter(Boolean)
      .join(', ');
    const address = freeform || [streetAddress, locality].filter(Boolean).join(', ');
    const poiName = text(place?.poi?.name);
    const type = String(place?.type || '');
    const isPoi = type === 'POI' || Boolean(poiName);
    const name = isPoi ? poiName || address : streetAddress || address;

    if (!name) return [];
    return [
      {
        id: place.id || address,
        provider: 'tomtom',
        sourceName: 'TomTom',
        name,
        address,
        label: address || name,
        isPoi,
        resultType: type,
        latitude,
        longitude,
      },
    ];
  });
}

function ifStreetAddress(isStreetOnly, street) {
  return isStreetOnly ? '' : street;
}

function mapPhotonPlaces(data) {
  return (data?.features || []).flatMap((feature) => {
    const props = feature?.properties || {};
    const coordinates = feature?.geometry?.coordinates;
    if (
      !Array.isArray(coordinates) ||
      !Number.isFinite(coordinates[0]) ||
      !Number.isFinite(coordinates[1])
    ) {
      return [];
    }
    const street = [props.housenumber, props.street]
      .map(text)
      .filter(Boolean)
      .join(' ');
    const name =
      text(props.name) || street || text(props.city) || text(props.country) || 'Place';
    const isStreetOnly =
      String(props.osm_key || '') === 'highway' && !text(props.housenumber);
    const parts = [
      ifStreetAddress(isStreetOnly, street),
      props.district,
      props.locality,
      props.city,
      props.state,
      props.postcode,
      props.country,
    ]
      .map(text)
      .filter(Boolean);
    const seen = new Set();
    const address = parts
      .filter((part) => {
        const key = part.toLocaleLowerCase();
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .join(', ');
    const isPoi = ['shop', 'amenity', 'tourism', 'leisure', 'office', 'craft'].includes(
      String(props.osm_key || '')
    );
    return [
      {
        id: isStreetOnly
          ? `street:${name.toLocaleLowerCase()}:${text(props.city).toLocaleLowerCase()}`
          : `${props.osm_type || ''}:${props.osm_id || ''}`,
        provider: 'osm',
        sourceName: 'OpenStreetMap',
        name,
        address,
        label: address || name,
        isPoi,
        resultType: props.osm_value || '',
        latitude: Number(coordinates[1]),
        longitude: Number(coordinates[0]),
      },
    ];
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
    const response = await fetch(url, { signal: AbortSignal.timeout(1800) });
    if (!response.ok) return [];
    return mapGeoapifyPlaces(await response.json());
  } catch {
    return [];
  }
}

async function fetchTomTom({ query, point, language, apiKey, trackUsage }) {
  if (!apiKey) return [];
  const url = new URL(
    `https://api.tomtom.com/search/2/search/${encodeURIComponent(query)}.json`
  );
  url.searchParams.set('key', apiKey);
  url.searchParams.set('limit', '10');
  url.searchParams.set('typeahead', 'true');
  url.searchParams.set('language', language === 'zh' ? 'zh-CN' : 'en-US');
  if (point) {
    url.searchParams.set('lat', String(point[1]));
    url.searchParams.set('lon', String(point[0]));
  }
  trackUsage('tomtom', 'search', 1);
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(1600) });
    if (!response.ok) return [];
    return mapTomTomPlaces(await response.json());
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
        accept: 'application/json',
      },
      signal: AbortSignal.timeout(1400),
    });
    if (!response.ok) return [];
    return mapPhotonPlaces(await response.json());
  } catch {
    return [];
  }
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Search stack used by Waybi's Independent map. It deliberately never calls
/// Google Places: every returned coordinate is safe to render, route to and
/// navigate to on Waybi's own map.
///
/// Fast path: Geoapify + TomTom + applicable official regional/national address
/// adapters run concurrently. We return as soon as that first wave settles or
/// reaches a short UI deadline. Photon is only a last-resort open-data fallback.
async function searchIndependentGlobalUncached({
  query,
  point,
  language = 'en',
  env,
  trackUsage = () => {},
  enrichmentsPromise = Promise.resolve([]),
}) {
  let geoapify = [];
  let tomtom = [];
  let enrichments = [];

  const geoPromise = fetchGeoapify({
    query,
    point,
    language,
    apiKey: env?.GEOAPIFY_API_KEY,
    trackUsage,
  }).then((results) => {
    geoapify = results;
    return results;
  });

  const tomtomPromise = fetchTomTom({
    query,
    point,
    language,
    apiKey: env?.TOMTOM_SEARCH_API_KEY || env?.TOMTOM_TRAFFIC_API_KEY,
    trackUsage,
  }).then((results) => {
    tomtom = results;
    return results;
  });

  const regionalPromise = Promise.resolve(enrichmentsPromise)
    .catch(() => [])
    .then((results) => {
      enrichments = results;
      return results;
    });

  // Official regional/national address data is often the fastest and most
  // precise source for street input. Give it a very short head start: if it
  // can already produce an exact (or safely interpolated) address/street, do
  // not hold typeahead open waiting for slower worldwide providers.
  await Promise.race([regionalPromise, wait(280)]);
  let regionalOnly = mergeAndRankSearchResults(
    [enrichments],
    query,
    point,
    12
  );
  if (regionalOnly.length && !needsAddressEnrichment(regionalOnly, query)) {
    return regionalOnly;
  }

  const firstWave = [regionalPromise, geoPromise, tomtomPromise];
  await Promise.race([Promise.allSettled(firstWave), wait(520)]);

  let merged = mergeAndRankSearchResults(
    [enrichments, tomtom, geoapify],
    query,
    point,
    12
  );
  if (merged.length && !needsAddressEnrichment(merged, query)) {
    return merged;
  }

  // Give exact/numbered addresses a little more time for an authoritative
  // national adapter or commercial geocoder, without blocking typeahead for
  // multiple seconds.
  await Promise.race([Promise.allSettled(firstWave), wait(720)]);
  merged = mergeAndRankSearchResults(
    [enrichments, tomtom, geoapify],
    query,
    point,
    12
  );
  if (merged.length) return merged;

  const photon = await fetchPhoton({ query, point, language, trackUsage });
  return mergeAndRankSearchResults([photon], query, point, 12);
}

export function searchIndependentGlobal(args) {
  const key = cacheKey(args.query, args.point, args.language);
  const cached = readCache(key);
  if (cached) return Promise.resolve(cached);

  const existing = searchPending.get(key);
  if (existing) return existing;

  const pending = searchIndependentGlobalUncached(args)
    .then((results) => writeCache(key, results))
    .finally(() => searchPending.delete(key));
  searchPending.set(key, pending);
  return pending;
}

