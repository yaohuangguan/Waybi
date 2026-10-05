import { rankPlaces } from '../place_search_rank.mjs';
import { searchRegionalAddressEnrichments } from './regional_address_registry.mjs';
import { parseNumberedStreetQuery } from './numbered_street_query.mjs';


function normalizedText(value) {
  return String(value || '')
    .toLocaleLowerCase()
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

export function needsAddressEnrichment(places, query) {
  const parsed = parseNumberedStreetQuery(query);
  if (!parsed) return false;
  const wanted = normalizedText(
    [parsed.number, parsed.roadName, parsed.roadType].filter(Boolean).join(' ')
  );
  if (!wanted) return false;
  return !(places || []).some((place) => {
    if (place?.approximate === true) return false;
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
  const merged = dedupeSearchResults(groups.flatMap((group) => group || []));
  return rankPlaces(merged, query, near).slice(0, limit);
}

export async function loadSearchEnrichments(query, near, fetcher = fetch) {
  return searchRegionalAddressEnrichments(query, near, fetcher);
}
