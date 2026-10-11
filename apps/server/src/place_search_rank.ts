import { distanceMeters } from './geo.ts';
import { GEOGRAPHIC_REGIONAL_RADIUS_METERS, matchesGeographicName } from './search/place_intent.ts';

function compact(value) {
  return String(value || '')
    .normalize('NFKC')
    .toLocaleLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');
}


function houseNumber(value) {
  const match = String(value || '').trim().match(/^(?:\d+\/)?(\d+)[A-Za-z]?\b/u);
  return match ? Number(match[1]) : null;
}

function relevance(place, query) {
  const q = compact(query);
  if (!q) return 0;
  const name = compact(place.name);
  const address = compact(place.address || place.label);
  if (name === q) return 5;
  if (name.startsWith(q) || q.startsWith(name)) return 4;
  if (name.includes(q)) return 3;
  if (address.includes(q)) return 2;
  return 1;
}

export function rankPlaces(results, query, near) {
  if (!Array.isArray(results)) return [];
  const wantedHouse = houseNumber(query);
  return results.map((place, index) => {
    const point: [number, number] = [Number(place.longitude), Number(place.latitude)];
    const distance = near && point.every(Number.isFinite) ? distanceMeters(near, point) : Infinity;
    const candidateHouse = houseNumber(place.name) ?? houseNumber(place.address || place.label);
    const houseDelta = wantedHouse != null && candidateHouse != null
      ? Math.abs(candidateHouse - wantedHouse)
      : Infinity;
    return {
      place,
      index,
      distance,
      houseDelta,
      geographic: matchesGeographicName(place, query),
      exactness: place?.approximate === true || place?.interpolated === true ? 0 : 1,
      relevance: relevance(place, query)
    };
  }).sort((a, b) => {
    // An exact geographic name expresses a destination before proximity.
    // Local businesses/categories still use local-first ranking below.
    const geographic = Number(b.geographic) - Number(a.geographic);
    if (geographic) return geographic;
    // A municipality's centre is a better destination than the centre of its
    // surrounding province. Same-name cities/towns still use proximity.
    if (a.geographic && b.geographic) {
      const settlement = place => ['city', 'town', 'municipality', 'postal_town', 'locality'].includes(place.resultType);
      const destination = Number(settlement(b.place)) - Number(settlement(a.place));
      if (destination) return destination;
      const aRegional = a.distance <= GEOGRAPHIC_REGIONAL_RADIUS_METERS;
      const bRegional = b.distance <= GEOGRAPHIC_REGIONAL_RADIUS_METERS;
      if (aRegional !== bRegional) return Number(bRegional) - Number(aRegional);
      // For overseas namesakes, retain the global provider's relevance and
      // prominence order. A small US Paris is closer to NZ than Paris, France.
      if (!aRegional && !bRegional) return a.index - b.index;
    }
    const aLocal = a.distance <= 80000 ? 1 : 0;
    const bLocal = b.distance <= 80000 ? 1 : 0;
    if (aLocal !== bLocal) return bLocal - aLocal;
    if (a.relevance !== b.relevance) return b.relevance - a.relevance;
    if (a.exactness !== b.exactness) return b.exactness - a.exactness;
    // For numbered-address autocomplete, nearby matching street candidates
    // should be ordered by house-number closeness before GPS distance. This
    // avoids showing 5/12/3 ahead of 46/34 for a query like "42 veri".
    if (a.houseDelta !== b.houseDelta) return a.houseDelta - b.houseDelta;
    if (a.distance !== b.distance) return a.distance - b.distance;
    return a.index - b.index;
  }).map(({ place, distance }) => ({
    ...place,
    ...(Number.isFinite(distance) ? { distanceMeters: Math.round(distance) } : {})
  }));
}
