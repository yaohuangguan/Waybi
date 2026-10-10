/** Keep word boundaries: Christchurch and Christ Church have different intent. */
export function normalizedPlaceName(value: unknown): string {
  return String(value || '').normalize('NFKD').replace(/\p{M}/gu, '')
    .toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

const geographicTypes = new Set([
  'city', 'town', 'village', 'municipality', 'locality', 'province', 'state',
  'country', 'county', 'district', 'suburb', 'quarter', 'neighbourhood',
  'administrative_area_level_1', 'administrative_area_level_2',
  'postal_town', 'sublocality',
]);

export function isGeographicPlace(place): boolean {
  return place?.isPoi !== true && geographicTypes.has(
    String(place?.resultType || '').toLowerCase(),
  );
}

// A name alone may refer to a distant settlement. Explicit street, address and
// category searches keep their existing local fast path. No city list is used.
export function maySearchGeographicName(query: string): boolean {
  const name = normalizedPlaceName(query);
  if (!name || /\d/u.test(name) || name.split(' ').length > 5) return false;
  return !/(?:^|\s)(?:near|nearby|nearest|cafe|cafes|coffee|restaurant|restaurants|church|churches|cathedral|supermarket|supermarkets|hotel|hotels|airport|station|museum|house|mall|parking|petrol|gas|pharmacy|hospital|school)(?:\s|$)/u.test(name)
    && !/\s(?:street|st|road|rd|drive|dr|avenue|ave|lane|ln|highway|motorway)$/u.test(name)
    && !/(附近|餐厅|咖啡|超市|酒店|机场|车站|停车|加油|医院|教堂)/u.test(name);
}

export function matchesGeographicName(place, query: string): boolean {
  if (!isGeographicPlace(place) || !maySearchGeographicName(query)) return false;
  let name = normalizedPlaceName(String(place.name || '').split(',')[0]);
  const wanted = normalizedPlaceName(query);
  if (['city', 'municipality', 'locality'].includes(String(place.resultType).toLowerCase()) && /\p{Script=Han}市$/u.test(name)) {
    name = name.slice(0, -1);
    if (wanted === name + '市') return true;
  }
  if (!name) return false;
  if (name === wanted) return true;
  // An explicit region/country qualifier must agree with the candidate.
  if (!wanted.startsWith(name + ' ')) return false;
  const context = new Set(normalizedPlaceName(
    `${place.address || ''} ${place.countryCode || ''}`,
  ).split(' '));
  return wanted.slice(name.length + 1).split(' ').every(token => context.has(token));
}
