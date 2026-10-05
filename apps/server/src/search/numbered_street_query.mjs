const ROAD_TYPE_ALIASES = new Map([
  ['RD', 'ROAD'], ['ROAD', 'ROAD'], ['ST', 'STREET'], ['STREET', 'STREET'],
  ['DR', 'DRIVE'], ['DRIVE', 'DRIVE'], ['AVE', 'AVENUE'], ['AVENUE', 'AVENUE'],
  ['LN', 'LANE'], ['LANE', 'LANE'], ['PL', 'PLACE'], ['PLACE', 'PLACE'],
  ['CRES', 'CRESCENT'], ['CRESCENT', 'CRESCENT'], ['TCE', 'TERRACE'], ['TERRACE', 'TERRACE'],
  ['CT', 'COURT'], ['COURT', 'COURT'], ['CL', 'CLOSE'], ['CLOSE', 'CLOSE'],
  ['PDE', 'PARADE'], ['PARADE', 'PARADE'], ['HWY', 'HIGHWAY'], ['HIGHWAY', 'HIGHWAY'],
  ['WAY', 'WAY']
]);

export function parseStreetQuery(query) {
  const match = String(query || '').trim().match(
    /^(?:(\d+[A-Za-z]?(?:\s*\/\s*\d+[A-Za-z]?)?)\s+)?([^,]+)(?:,.*)?$/u
  );
  if (!match) return null;
  const number = match[1]?.replace(/\s+/g, '') || null;
  const words = match[2].trim().split(/\s+/).filter(Boolean);
  if (!words.length) return null;
  const last = words.at(-1).toUpperCase().replace(/\./g, '');
  const roadType = ROAD_TYPE_ALIASES.get(last) || null;
  if (roadType) words.pop();
  const roadName = words.join(' ').trim();
  if (!roadName || (!number && !roadType)) return null;
  return { number, roadName, roadType };
}

export function parseNumberedStreetQuery(query) {
  const parsed = parseStreetQuery(query);
  return parsed?.number ? parsed : null;
}
