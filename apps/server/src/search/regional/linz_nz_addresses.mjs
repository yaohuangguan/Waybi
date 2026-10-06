const ENDPOINT =
  'https://services.arcgis.com/xdsHIIxuCWByZiCB/arcgis/rest/services/LINZ_NZ_Addresses/FeatureServer/0/query';

function sql(value) {
  return String(value).replaceAll("'", "''");
}

function titleWords(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/(^|[\s/-])([a-z])/g, (_match, prefix, letter) =>
      prefix + letter.toUpperCase()
    );
}

function inServiceArea(near) {
  if (!near) return false;
  const [lon, lat] = near;
  return lon >= 165.5 && lon <= 179.9 && lat >= -48.0 && lat <= -33.0;
}

function requestedPrefix(parsed) {
  return [parsed.number, parsed.roadName, parsed.roadType]
    .filter(Boolean)
    .join(' ')
    .trim()
    .toUpperCase();
}

export const linzNzAddressProvider = {
  id: 'linz-nz-addresses',
  provider: 'regional:linz-nz-addresses',
  supports({ near, parsed }) {
    return Boolean(parsed && inServiceArea(near));
  },

  async search({ parsed, fetcher = fetch }) {
    const prefix = requestedPrefix(parsed);
    if (!prefix) return [];

    const url = new URL(ENDPOINT);
    // LINZ is the national authoritative physical-address dataset. Query the
    // complete address prefix so partial input such as "42 veri" and a full
    // address such as "42 Verissimo Drive" use the same fast path.
    url.searchParams.set(
      'where',
      parsed.number
        ? `UPPER(full_address_ascii) LIKE '${sql(prefix)}%'`
        : `UPPER(road_name_ascii)='${sql([parsed.roadName, parsed.roadType].filter(Boolean).join(' ').toUpperCase())}'`
    );
    url.searchParams.set(
      'outFields',
      'OBJECTID,address_id,full_address_ascii,road_name_ascii,' +
        'suburb_locality_ascii,town_city_ascii,territorial_authority_ascii'
    );
    url.searchParams.set('returnGeometry', 'true');
    url.searchParams.set('outSR', '4326');
    url.searchParams.set('f', 'geojson');
    url.searchParams.set('resultRecordCount', '20');

    const response = await fetcher(url, {
      headers: {
        'user-agent': 'Waybi/1.0 (+https://waybi.co)',
        accept: 'application/json',
      },
      signal: AbortSignal.timeout(1800),
    });
    if (!response.ok) return [];

    const body = await response.json();
    const features = Array.isArray(body.features) ? body.features : [];
    const results = features.flatMap((feature) => {
      const props = feature?.properties || {};
      const coordinates = feature?.geometry?.coordinates;
      if (
        !Array.isArray(coordinates) ||
        !Number.isFinite(coordinates[0]) ||
        !Number.isFinite(coordinates[1])
      ) {
        return [];
      }

      const fullAddress = titleWords(props.full_address_ascii || '');
      if (!fullAddress) return [];
      const roadName = titleWords(props.road_name_ascii || '');
      const suburb = titleWords(props.suburb_locality_ascii || '');
      const city = titleWords(props.town_city_ascii || '');
      const authority = titleWords(props.territorial_authority_ascii || '');
      const displayAddress = [
        fullAddress,
        suburb && !fullAddress.toLowerCase().includes(suburb.toLowerCase())
          ? suburb
          : '',
        city && !fullAddress.toLowerCase().includes(city.toLowerCase())
          ? city
          : '',
        authority &&
        !fullAddress.toLowerCase().includes(authority.toLowerCase()) &&
        authority.toLowerCase() !== city.toLowerCase()
          ? authority
          : '',
        'New Zealand',
      ]
        .filter(Boolean)
        .join(', ');

      const leading = fullAddress.match(/^\d+[A-Za-z]?(?:\/\d+[A-Za-z]?)?\s+/u);
      const name = leading
        ? fullAddress
        : [parsed.number, roadName || parsed.roadName, parsed.roadType]
            .filter(Boolean)
            .join(' ');

      return [
        {
          id: `linz-nz-address:${props.address_id || props.OBJECTID}`,
          provider: 'regional:linz-nz-addresses',
          sourceName: 'Toitū Te Whenua LINZ',
          name,
          address: displayAddress,
          label: displayAddress,
          isPoi: false,
          latitude: Number(coordinates[1]),
          longitude: Number(coordinates[0]),
          _streetLocality: [suburb, city, authority, 'New Zealand']
            .filter((value, index, values) => value && values.indexOf(value) === index)
            .join(', '),
        },
      ];
    });
    if (!parsed.number && results.length) {
      const latitude = results.reduce((sum, place) => sum + place.latitude, 0) / results.length;
      const longitude = results.reduce((sum, place) => sum + place.longitude, 0) / results.length;
      const road = [parsed.roadName, parsed.roadType]
        .filter(Boolean)
        .map(titleWords)
        .join(' ');
      const locality = results[0]._streetLocality || 'New Zealand';
      return [{
        id: `linz-nz-street:${road.toLowerCase()}`,
        provider: 'regional:linz-nz-addresses',
        sourceName: 'Toitū Te Whenua LINZ',
        name: road,
        address: locality,
        label: [road, locality].filter(Boolean).join(', '),
        isPoi: false,
        latitude,
        longitude,
      }];
    }
    return results.map(({ _streetLocality, ...place }) => place);
  },
};
