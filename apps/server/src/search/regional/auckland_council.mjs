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

function numericHouseNumber(value) {
  const match = String(value || '').split('/').at(-1)?.match(/^\d+/);
  return match ? Number(match[0]) : null;
}

function squaredDistance(near, place) {
  if (!near) return 0;
  const latScale = Math.cos((near[1] * Math.PI) / 180);
  const dx = (place.longitude - near[0]) * latScale;
  const dy = place.latitude - near[1];
  return dx * dx + dy * dy;
}

function displayParts(entry, name = entry.name) {
  return [
    name,
    entry.locality,
    ['Auckland', entry.postcode].filter(Boolean).join(' '),
    'New Zealand'
  ].filter(Boolean);
}

function interpolateRequestedAddress(entries, parsed) {
  const target = numericHouseNumber(parsed.number);
  if (!Number.isFinite(target)) return null;

  const numbered = entries
    .map((entry) => ({ ...entry, numericNumber: numericHouseNumber(entry.fullNumber) }))
    .filter((entry) => Number.isFinite(entry.numericNumber));

  const exact = numbered.find((entry) =>
    String(entry.fullNumber).toLowerCase() === String(parsed.number).toLowerCase()
  );
  if (exact) return exact;

  const sameParity = numbered.filter((entry) => entry.numericNumber % 2 === target % 2);
  const pool = sameParity.length >= 2 ? sameParity : numbered;
  const lower = pool
    .filter((entry) => entry.numericNumber < target)
    .sort((a, b) => b.numericNumber - a.numericNumber)[0];
  const upper = pool
    .filter((entry) => entry.numericNumber > target)
    .sort((a, b) => a.numericNumber - b.numericNumber)[0];
  if (!lower || !upper) return null;

  const span = upper.numericNumber - lower.numericNumber;
  if (span <= 0 || span > 40) return null;
  const ratio = (target - lower.numericNumber) / span;
  const latitude = lower.latitude + (upper.latitude - lower.latitude) * ratio;
  const longitude = lower.longitude + (upper.longitude - lower.longitude) * ratio;
  const road = lower.road || upper.road;
  const name = `${parsed.number} ${road}`.trim();
  const basis = ratio <= .5 ? lower : upper;
  return {
    id: `auckland-council:interpolated:${road.toLowerCase().replace(/\s+/g, '-') }:${parsed.number}`,
    provider: 'regional:auckland-council',
    sourceName: 'Auckland Council',
    name,
    address: displayParts(basis, name).join(', '),
    label: displayParts(basis, name).join(', '),
    isPoi: false,
    resultType: 'interpolated_address',
    approximate: true,
    latitude,
    longitude,
    fullNumber: parsed.number,
    numericNumber: target,
    road,
    locality: basis.locality,
    postcode: basis.postcode,
  };
}

function collapseToStreet(entries, near) {
  const grouped = new Map();
  for (const entry of entries) {
    const key = [entry.road.toLowerCase(), entry.locality.toLowerCase(), entry.postcode].join('|');
    const current = grouped.get(key);
    if (!current || squaredDistance(near, entry) < squaredDistance(near, current)) {
      grouped.set(key, entry);
    }
  }
  return [...grouped.values()].map((entry) => {
    const name = entry.road;
    const address = displayParts(entry, name).join(', ');
    return {
      id: `auckland-council:street:${entry.road.toLowerCase().replace(/\s+/g, '-') }:${entry.locality.toLowerCase().replace(/\s+/g, '-')}`,
      provider: 'regional:auckland-council',
      sourceName: 'Auckland Council',
      name,
      address,
      label: address,
      isPoi: false,
      resultType: 'street',
      latitude: entry.latitude,
      longitude: entry.longitude,
    };
  });
}

export const aucklandCouncilAddressProvider = {
  id: 'auckland-council',
  provider: 'regional:auckland-council',
  supports({ near, parsed }) {
    return Boolean(parsed && inServiceArea(near));
  },
  async search({ parsed, near, fetcher = fetch }) {
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
    url.searchParams.set('resultRecordCount', '60');
    const response = await fetcher(url, {
      headers: {
        'user-agent': 'Waybi/1.0 (+https://waybi.co)',
        accept: 'application/json'
      },
      signal: AbortSignal.timeout(1200)
    });
    if (!response.ok) return [];
    const body = await response.json();
    const features = Array.isArray(body.features) ? body.features : [];
    const wantedNumber = parsed.number ? numericHouseNumber(parsed.number) : null;
    const entries = features.flatMap((feature) => {
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
      const address = displayParts({ locality, postcode }, name).join(', ');
      return [{
        id: `auckland-council:${props.OBJECTID}`,
        provider: 'regional:auckland-council',
        sourceName: 'Auckland Council',
        name,
        address,
        label: address,
        isPoi: false,
        resultType: 'address',
        latitude: Number(coordinates[1]),
        longitude: Number(coordinates[0]),
        fullNumber,
        road,
        locality,
        postcode,
        _numberDistance: Number.isFinite(wantedNumber)
          ? Math.abs((numericHouseNumber(fullNumber) ?? wantedNumber) - wantedNumber)
          : 0
      }];
    });

    if (!parsed.number) {
      return collapseToStreet(entries, near).slice(0, 6);
    }

    const interpolated = interpolateRequestedAddress(entries, parsed);
    entries.sort((a, b) =>
      a._numberDistance - b._numberDistance ||
      squaredDistance(near, a) - squaredDistance(near, b)
    );

    const ordered = interpolated && interpolated.approximate
      ? [interpolated, ...entries]
      : entries;
    return ordered.slice(0, 12).map(({ _numberDistance, ...place }) => place);
  }
};
