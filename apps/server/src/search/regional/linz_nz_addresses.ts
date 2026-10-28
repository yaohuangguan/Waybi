import type { ProviderPayload } from "./../../types.ts";
import { addressLocalityTerms, normalizeAddressText } from '../numbered_street_query.ts';
const ENDPOINT =
  'https://services.arcgis.com/xdsHIIxuCWByZiCB/arcgis/rest/services/LINZ_NZ_Addresses/FeatureServer/0/query';

function sql(value) {
  return String(value).replaceAll("'", "''");
}

function titleWords(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/(^|[\s/'’-])(\p{L})/gu, (_match, prefix, letter) =>
      prefix + letter.toUpperCase()
    ).replace(/\bMc([a-z])/g, (_match, letter) => `Mc${letter.toUpperCase()}`);
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
    const road = [parsed.roadName, parsed.roadType].filter(Boolean).join(' ');
    const asciiRoad = titleWords(road.normalize('NFKD').replace(/\p{M}/gu, '').replaceAll('’', "'"));
    // Keep indexed fields unwrapped. UPPER(full_address_ascii) scans millions
    // of national records and was routinely timing out before yielding any.
    const filters = [parsed.roadType
      ? `full_road_name_ascii='${sql(asciiRoad)}'`
      : `full_road_name_ascii LIKE '${sql(asciiRoad)}%'`];
    if (parsed.number) {
      const house = Number(parsed.number.split('/').at(-1).match(/^\d+/)?.[0]);
      if (Number.isSafeInteger(house)) filters.push(`address_number=${house}`);
      filters.push(`UPPER(full_address_number)='${sql(parsed.number.toUpperCase())}'`);
    }
    for (const term of addressLocalityTerms(parsed).flatMap(term => term.split(' '))) {
      filters.push(`(${['suburb_locality_ascii', 'town_city_ascii', 'territorial_authority_ascii']
        .map(field => `UPPER(${field}) LIKE '%${sql(term.toUpperCase())}%'`).join(' OR ')})`);
    }
    url.searchParams.set('where', filters.join(' AND '));
    url.searchParams.set(
      'outFields',
      'OBJECTID,address_id,road_id,full_address,full_address_ascii,full_road_name_ascii,road_name_ascii,' +
        'suburb_locality,suburb_locality_ascii,town_city,town_city_ascii,territorial_authority_ascii'
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

    const body = await response.json<ProviderPayload>();
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

      const fullAddress = titleWords(String(props.full_address || props.full_address_ascii || '').split(',')[0]);
      if (!fullAddress) return [];
      const roadName = titleWords(props.road_name_ascii || '');
      const suburb = titleWords(props.suburb_locality || props.suburb_locality_ascii || '');
      const city = titleWords(props.town_city || props.town_city_ascii || '');
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
          _streetId: String(props.road_id || normalizeAddressText([suburb, city, authority].join(' '))),
        },
      ];
    });
    if (!parsed.number && results.length) {
      const road = [parsed.roadName, parsed.roadType]
        .filter(Boolean)
        .map(titleWords)
        .join(' ');
      const streets = new Map<string, typeof results>();
      for (const place of results) streets.set(place._streetId, [...(streets.get(place._streetId) || []), place]);
      return [...streets].map(([id, addresses]) => {
        const point = addresses[Math.floor(addresses.length / 2)];
        const locality = point._streetLocality || 'New Zealand';
        return {
        id: `linz-nz-street:${id}:${road.toLowerCase()}`,
        provider: 'regional:linz-nz-addresses',
        sourceName: 'Toitū Te Whenua LINZ',
        name: road,
        address: locality,
        label: [road, locality].filter(Boolean).join(', '),
        isPoi: false,
        resultType: 'street',
        latitude: point.latitude,
        longitude: point.longitude,
      }; });
    }
    return results.map(({ _streetLocality, _streetId, ...place }) => place);
  },
};
