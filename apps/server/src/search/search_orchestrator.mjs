import { rankPlaces } from '../place_search_rank.mjs';
import { searchRegionalAddressEnrichments } from './regional_address_registry.mjs';
import { parseNumberedStreetQuery, parseStreetQuery } from './numbered_street_query.mjs';


function normalizedText(value) {
  return String(value || '')
    .toLocaleLowerCase()
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function leadingHouseNumber(value) {
  const match = String(value || '').trim().match(/^(?:\d+\/)?(\d+)[A-Za-z]?\b/u);
  return match ? Number(match[1]) : null;
}

function sameRequestedStreet(place, parsed) {
  const wanted = normalizedText([parsed.roadName, parsed.roadType].filter(Boolean).join(' '));
  if (!wanted) return false;
  const values = [place?.name, place?.address, place?.label]
    .map(normalizedText)
    .filter(Boolean);
  return values.some((value) => {
    const withoutNumber = value.replace(/^(?:\d+\/)?\d+[a-z]?\s+/u, '');
    return withoutNumber.startsWith(wanted);
  });
}

export function interpolateNumberedAddress(places, query) {
  const parsed = parseNumberedStreetQuery(query);
  if (!parsed) return null;
  const wantedNumber = Number(parsed.number.split('/').at(-1).match(/^\d+/)?.[0]);
  if (!Number.isFinite(wantedNumber)) return null;

  const exact = (places || []).find((place) => {
    if (!sameRequestedStreet(place, parsed)) return false;
    const number = leadingHouseNumber(place?.name) ?? leadingHouseNumber(place?.address);
    return number === wantedNumber;
  });
  if (exact) return null;

  const candidates = (places || [])
    .filter((place) => sameRequestedStreet(place, parsed))
    .map((place) => ({
      place,
      number: leadingHouseNumber(place?.name) ?? leadingHouseNumber(place?.address),
    }))
    .filter(({ place, number }) =>
      Number.isFinite(number) &&
      Number.isFinite(Number(place?.latitude)) &&
      Number.isFinite(Number(place?.longitude))
    )
    .sort((a, b) => a.number - b.number);

  let lower = null;
  let upper = null;
  for (const candidate of candidates) {
    if (candidate.number < wantedNumber) lower = candidate;
    if (candidate.number > wantedNumber) {
      upper = candidate;
      break;
    }
  }
  if (!lower || !upper || upper.number === lower.number) return null;
  // Do not invent coordinates from wildly separated address ranges.
  if (upper.number - lower.number > 40) return null;

  const t = (wantedNumber - lower.number) / (upper.number - lower.number);
  const latitude = Number(lower.place.latitude) +
    (Number(upper.place.latitude) - Number(lower.place.latitude)) * t;
  const longitude = Number(lower.place.longitude) +
    (Number(upper.place.longitude) - Number(lower.place.longitude)) * t;
  const candidateRoad = String(lower.place.name || '')
    .replace(/^(?:\d+\/)?\d+[A-Za-z]?\s+/u, '')
    .trim();
  const requestedRoad = [parsed.roadName, parsed.roadType]
    .filter(Boolean)
    .map((part) => String(part).toLowerCase().replace(/(^|\s)([a-z])/g, (_m, p, c) => p + c.toUpperCase()))
    .join(' ');
  const road = parsed.roadType ? requestedRoad : (candidateRoad || requestedRoad);
  const name = `${parsed.number} ${road}`.trim();
  const localitySource = String(lower.place.address || upper.place.address || '');
  const localityParts = localitySource.split(',').map((part) => part.trim()).filter(Boolean);
  if (localityParts.length && /^\d/u.test(localityParts[0])) localityParts.shift();
  const address = [name, ...localityParts].join(', ');
  return {
    id: `interpolated:${normalizedText(name)}:${latitude.toFixed(6)},${longitude.toFixed(6)}`,
    provider: 'derived:address-interpolation',
    sourceName: 'Waybi address interpolation',
    name,
    address,
    label: address,
    isPoi: false,
    latitude,
    longitude,
    interpolated: true,
  };
}

export function needsAddressEnrichment(places, query) {
  const parsed = parseNumberedStreetQuery(query);
  if (!parsed) return false;
  const wanted = normalizedText(
    [parsed.number, parsed.roadName, parsed.roadType].filter(Boolean).join(' ')
  );
  if (!wanted) return false;
  return !(places || []).some((place) => {
    const candidates = [place?.name, place?.address, place?.label]
      .map(normalizedText)
      .filter(Boolean);
    return candidates.some((candidate) => candidate.startsWith(wanted));
  });
}

function normalizedAddressKey(place) {
  return String(place?.address || place?.label || place?.name || '')
    .toLocaleLowerCase()
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

export function dedupeSearchResults(places) {
  const seenIds = new Set();
  const seenAddresses = new Set();
  return (places || []).filter((place) => {
    if (!place) return false;
    const id = place.id ? `${place.provider || ''}:${place.id}` : '';
    const address = normalizedAddressKey(place);
    if (id && seenIds.has(id)) return false;
    if (address && seenAddresses.has(address)) return false;
    if (id) seenIds.add(id);
    if (address) seenAddresses.add(address);
    return true;
  });
}

export function mergeAndRankSearchResults(groups, query, near, limit = 12) {
  let merged = dedupeSearchResults(groups.flatMap((group) => group || []));
  const interpolated = interpolateNumberedAddress(merged, query);
  if (interpolated) merged = [interpolated, ...merged];
  return rankPlaces(merged, query, near).slice(0, limit);
}

export async function loadSearchEnrichments(query, near, fetcher = fetch) {
  return searchRegionalAddressEnrichments(query, near, fetcher);
}
