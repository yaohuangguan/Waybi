import type { ProviderPayload } from "./../../types.ts";
const ENDPOINT = 'https://mapspublic.aucklandcouncil.govt.nz/arcgis3/rest/services/NonCouncil/UnitaryPlanManagementLayers/MapServer/4/query';

function sql(value) {
  return String(value).replaceAll("'", "''");
}

function titleWords(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/(^|[\s/-])([a-z])/g, (_match, prefix, letter) => prefix + letter.toUpperCase());
}

function inServiceArea(near) {
  if (!near) return false;
  const [lon, lat] = near;
  return lon >= 174.2 && lon <= 175.4 && lat >= -37.4 && lat <= -36.2;
}

export const aucklandCouncilAddressProvider = {
  id: 'auckland-council',
  provider: 'regional:auckland-council',
  supports({ near, parsed }) {
    return Boolean(parsed && inServiceArea(near));
  },
  async search({ parsed, fetcher = fetch }) {
    const url = new URL(ENDPOINT);
    const normalizedRoad = parsed.roadName.toUpperCase().trim();
    const roadPrefix = !parsed.roadType
      ? normalizedRoad.replace(/\s+(?:R|RO|RD|S|ST|D|DR|A|AV|L|LN|P|PL|C|CR|T|TC|H|HW|W)$/u, '').trim()
      : normalizedRoad;
    const safeRoad = sql(roadPrefix || normalizedRoad);
    const filters = [
      parsed.roadType
        ? `UPPER(RoadName)='${safeRoad}'`
        : `UPPER(RoadName) LIKE '${safeRoad}%'`
    ];
    if (parsed.roadType) filters.push(`UPPER(RoadType)='${sql(parsed.roadType)}'`);
    url.searchParams.set('where', filters.join(' AND '));
    url.searchParams.set(
      'outFields',
      'OBJECTID,FullNumber,RoadName,RoadType,FullAddress,Locality,FullAddress_macron'
    );
    url.searchParams.set('returnGeometry', 'true');
    url.searchParams.set('outSR', '4326');
    url.searchParams.set('f', 'geojson');
    url.searchParams.set('resultRecordCount', '40');
    const response = await fetcher(url, {
      headers: {
        'user-agent': 'Waybi/1.0 (+https://waybi.co)',
        accept: 'application/json'
      },
      signal: AbortSignal.timeout(2200)
    });
    if (!response.ok) return [];
    const body = await response.json<ProviderPayload>();
    const features = Array.isArray(body.features) ? body.features : [];
    const wantedNumber = parsed.number
      ? Number(parsed.number.split('/').at(-1).match(/^\d+/)?.[0])
      : NaN;
    const results = features.flatMap((feature) => {
      const props = feature?.properties || {};
      const coordinates = feature?.geometry?.coordinates;
      if (!Array.isArray(coordinates) ||
          !Number.isFinite(coordinates[0]) ||
          !Number.isFinite(coordinates[1])) return [];
      const fullNumber = String(props.FullNumber || '').trim();
      if (!fullNumber) return [];
      const road = [titleWords(props.RoadName), titleWords(props.RoadType)]
        .filter(Boolean)
        .join(' ');
      const name = `${fullNumber} ${road}`.trim();
      const rawFull = String(props.FullAddress_macron || props.FullAddress || name);
      const postcode = rawFull.match(/\b(\d{4})\s*$/)?.[1] || '';
      const locality = titleWords(props.Locality || '');
      const full = [
        name,
        locality,
        ['Auckland', postcode].filter(Boolean).join(' '),
        'New Zealand'
      ].filter(Boolean).join(', ');
      return [{
        id: `auckland-council:${props.OBJECTID}`,
        provider: 'regional:auckland-council',
        sourceName: 'Auckland Council',
        name,
        address: full,
        label: full,
        isPoi: false,
        latitude: Number(coordinates[1]),
        longitude: Number(coordinates[0]),
        _numberDistance: Number.isFinite(wantedNumber)
          ? Math.abs(
              Number(fullNumber.split('/').at(-1).match(/^\d+/)?.[0]) - wantedNumber
            )
          : 0
      }];
    });
    results.sort((a, b) => a._numberDistance - b._numberDistance);
    if (!parsed.number && results.length) {
      const first = results[0];
      const latitude = results.reduce((sum, place) => sum + place.latitude, 0) / results.length;
      const longitude = results.reduce((sum, place) => sum + place.longitude, 0) / results.length;
      const road = first.name.replace(/^\S+\s+/u, '');
      const locality = first.address.split(',').slice(1).join(',').trim();
      return [{
        id: `auckland-council:street:${road.toLowerCase()}`,
        provider: 'regional:auckland-council',
        sourceName: 'Auckland Council',
        name: road,
        address: locality,
        label: [road, locality].filter(Boolean).join(', '),
        isPoi: false,
        latitude,
        longitude,
      }];
    }
    return results.slice(0, 12).map(({ _numberDistance, ...place }) => place);
  }
};
