const ROAD_TYPE_ALIASES = new Map([
  ['RD', 'ROAD'], ['ROAD', 'ROAD'], ['ST', 'STREET'], ['STREET', 'STREET'],
  ['DR', 'DRIVE'], ['DRIVE', 'DRIVE'], ['AVE', 'AVENUE'], ['AVENUE', 'AVENUE'],
  ['LN', 'LANE'], ['LANE', 'LANE'], ['PL', 'PLACE'], ['PLACE', 'PLACE'],
  ['CRES', 'CRESCENT'], ['CRESCENT', 'CRESCENT'], ['TCE', 'TERRACE'], ['TERRACE', 'TERRACE'],
  ['CT', 'COURT'], ['COURT', 'COURT'], ['CL', 'CLOSE'], ['CLOSE', 'CLOSE'],
  ['PDE', 'PARADE'], ['PARADE', 'PARADE'], ['HWY', 'HIGHWAY'], ['HIGHWAY', 'HIGHWAY'],
  ['WAY', 'WAY']
]);

export function parseNumberedStreetQuery(query) {
  const match = String(query || '').trim().match(
    /^(\d+[A-Za-z]?(?:\s*\/\s*\d+[A-Za-z]?)?)\s+([^,]+)(?:,.*)?$/u
  );
  if (!match) return null;
  const number = match[1].replace(/\s+/g, '');
  const words = match[2].trim().split(/\s+/).filter(Boolean);
  if (!words.length) return null;
  let typeIndex = words.findLastIndex(word => ROAD_TYPE_ALIASES.has(word.toUpperCase().replace(/\./g, '')));
  if (typeIndex >= 0 && typeIndex < words.length - 1 && /^(?:north|south|east|west|n|s|e|w)$/i.test(words.slice(typeIndex + 1).join(' '))) typeIndex = -1;
  const roadType = typeIndex >= 0 ? ROAD_TYPE_ALIASES.get(words[typeIndex].toUpperCase().replace(/\./g, '')) : null;
  const inlineLocality = roadType ? words.splice(typeIndex).slice(1).join(' ') : '';
  const roadName = words.join(' ').trim();
  if (!roadName) return null;
  const locality = [inlineLocality, ...String(query).split(',').slice(1)].map(part => part.trim()).filter(Boolean).join(', ');
  return { number, roadName, roadType, ...(locality ? { locality } : {}) };
}


export function parseStreetQuery(query) {
  const raw = String(query || '').trim().split(',')[0].trim();
  if (!raw || /^\d/u.test(raw)) return null;
  const words = raw.split(/\s+/).filter(Boolean);
  if (words.length < 2) return null;
  const typeIndex = words.length - 1;
  const roadType = typeIndex >= 0 ? ROAD_TYPE_ALIASES.get(words[typeIndex].toUpperCase().replace(/\./g, '')) : null;
  if (!roadType) return null;
  const inlineLocality = words.splice(typeIndex).slice(1).join(' ');
  const roadName = words.join(' ').trim();
  const locality = [inlineLocality, ...String(query).split(',').slice(1)].map(part => part.trim()).filter(Boolean).join(', ');
  return roadName ? { number: null, roadName, roadType, ...(locality ? { locality } : {}) } : null;
}

export function normalizeAddressText(value) {
  return String(value || '').normalize('NFKD').replace(/\p{M}/gu, '')
    .toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

export function addressLocalityTerms(parsed) {
  return String(parsed?.locality || '').split(',').map(part => normalizeAddressText(part)
    .replace(/\b(?:\d{4,6}|new zealand|nz)\b/g, '').trim()).filter(Boolean);
}

export function matchesAddressLocality(place, parsed) {
  const address = ` ${normalizeAddressText([place.address, place.label].filter(Boolean).join(' '))} `;
  return addressLocalityTerms(parsed).every(term => address.includes(` ${term} `));
}
