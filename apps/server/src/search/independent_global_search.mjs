import { mergeAndRankSearchResults, needsAddressEnrichment } from './search_orchestrator.mjs';
import { parseNumberedStreetQuery } from './numbered_street_query.mjs';

function text(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function firstNonEmpty(promises, timeoutMs) {
  return new Promise((resolve) => {
    if (!promises.length) {
      resolve([]);
      return;
    }
    let remaining = promises.length;
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      resolve([]);
    }, timeoutMs);
    for (const promise of promises) {
      Promise.resolve(promise).then((items) => {
        if (settled) return;
        if (Array.isArray(items) && items.length) {
          settled = true;
          clearTimeout(timer);
          resolve(items);
          return;
        }
        remaining -= 1;
        if (remaining === 0) {
          settled = true;
          clearTimeout(timer);
          resolve([]);
        }
      }).catch(() => {
        if (settled) return;
        remaining -= 1;
        if (remaining === 0) {
          settled = true;
          clearTimeout(timer);
          resolve([]);
        }
      });
    }
  });
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

function mapHerePlaces(data) {
  return (data?.items || []).flatMap((item) => {
    const latitude = Number(item?.position?.lat);
    const longitude = Number(item?.position?.lng);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return [];
    const label = text(item?.address?.label) || text(item?.title);
    const resultType = text(item?.resultType);
    const isPoi = resultType === 'place';
    const name = isPoi ? (text(item?.title) || label) : label;
    return [{
      id: text(item?.id) || label,
      provider: 'here',
      name,
      address: label,
      label,
      isPoi,
      resultType,
      latitude,
      longitude
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
    const response = await fetch(url, { signal: AbortSignal.timeout(1400) });
    if (!response.ok) return [];
    return mapGeoapifyPlaces(await response.json());
  } catch {
    return [];
  }
}

async function fetchHere({ query, point, language, apiKey, trackUsage }) {
  if (!apiKey) return [];
  const numberedAddress = Boolean(parseNumberedStreetQuery(query));
  const url = new URL(
    numberedAddress
      ? 'https://geocode.search.hereapi.com/v1/geocode'
      : 'https://discover.search.hereapi.com/v1/discover'
  );
  url.searchParams.set('q', query);
  url.searchParams.set('limit', '10');
  url.searchParams.set('lang', language === 'zh' ? 'zh-CN' : 'en');
  url.searchParams.set('apiKey', apiKey);
  if (point) url.searchParams.set('at', `${point[1]},${point[0]}`);
  trackUsage('here', numberedAddress ? 'geocode' : 'discover', 1);
  try {
    const response = await fetch(url, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(1400)
    });
    if (!response.ok) return [];
    return mapHerePlaces(await response.json());
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
      signal: AbortSignal.timeout(1600)
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
  const herePromise = fetchHere({
    query,
    point,
    language,
    apiKey: env?.HERE_API_KEY,
    trackUsage
  });
  const enrichments = await enrichmentsPromise.catch(() => []);

  // Return the first useful global provider quickly for typeahead. The slower
  // provider continues in the background and is only awaited when the fast
  // result is empty or lacks requested address detail.
  const firstGlobal = await firstNonEmpty([herePromise, geoPromise], 700);
  if (firstGlobal.length && !needsAddressEnrichment(firstGlobal, query)) {
    return mergeAndRankSearchResults(
      [enrichments, firstGlobal],
      query,
      point,
      12
    );
  }

  const [geoapify, here] = await Promise.all([geoPromise, herePromise]);
  const global = mergeAndRankSearchResults(
    [enrichments, here, geoapify],
    query,
    point,
    12
  );
  if (global.length && !needsAddressEnrichment(global, query)) {
    return global;
  }

  const photon = await fetchPhoton({ query, point, language, trackUsage });
  return mergeAndRankSearchResults(
    [enrichments, here, geoapify, photon],
    query,
    point,
    12
  );
}
