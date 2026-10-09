/**
 * Rebuild the offline Christchurch/Wellington MAP-ONLY corridor candidates.
 * Council road centre-lines are not legal bus-lane boundaries.
 * No result from this script is eligible for navigation warnings or road blocks.
 */
import { writeFile } from 'node:fs/promises';

const CCC = 'https://gis.ccc.govt.nz/server/rest/services/OpenData/Road/FeatureServer/7';
const WCC = 'https://gis.wcc.govt.nz/arcgis/rest/services/Transportation/Roads/MapServer/0';
const candidates = [
  {
    city: 'Christchurch', roadName: 'Cranford Street', gis: CCC, field: 'FullRoadName',
    authority: 'Christchurch City Council',
    rule: 'Published weekday peak lanes: southbound 07:00–09:00; northbound 16:00–18:00. Lane endpoints still require verification.',
    ruleZh: '市议会公布：工作日南行 07:00–09:00、北行 16:00–18:00。具体车道起止位置仍待核实。',
    ruleUrl: 'https://letstalk.ccc.govt.nz/waipapa-papanui-innes-central-community-board/cranford-street-bus-lanes-be-implemented',
  },
  {
    city: 'Christchurch', roadName: 'Papanui Road', gis: CCC, field: 'FullRoadName',
    authority: 'Christchurch City Council',
    rule: 'Officially identified as a bus lane corridor; exact hours, direction and lane limits require verification.',
    ruleZh: '市议会确认此道路存在公交车道；精确时段、方向和车道范围仍待核实。',
    ruleUrl: 'https://ccc.govt.nz/assets/Documents/Transport/Cycling/map/WEB-INF7542-Christchurch-Bike-Map-2025.pdf',
  },
  {
    city: 'Wellington', roadName: 'Adelaide Road', gis: WCC, field: 'full_road_name',
    authority: 'Wellington City Council',
    rule: 'Council describes 24/7 bus lanes in both directions. Exact lane limits require verification.',
    ruleZh: '市议会确认双向部分路段全天公交车道。具体路段范围仍待核实。',
    ruleUrl: 'https://www.transportprojects.org.nz/current/newtown-to-city/project-details',
  },
  {
    city: 'Wellington', roadName: 'Kent Terrace', gis: WCC, field: 'full_road_name',
    authority: 'Wellington City Council',
    rule: 'Council reports 07:00–09:00 and 16:00–18:00 Monday–Friday on the Newtown–City corridor. Check section-specific signs.',
    ruleZh: '市议会公布 Newtown–City 走廊部分公交车道工作日 07:00–09:00、16:00–18:00；具体路段请查看现场标志。',
    ruleUrl: 'https://www.transportprojects.org.nz/current/newtown-to-city/project-details',
  },
  {
    city: 'Wellington', roadName: 'Cambridge Terrace', gis: WCC, field: 'full_road_name',
    authority: 'Wellington City Council',
    rule: 'Council reports 07:00–09:00 and 16:00–18:00 Monday–Friday on the Newtown–City corridor. Check section-specific signs.',
    ruleZh: '市议会公布 Newtown–City 走廊部分公交车道工作日 07:00–09:00、16:00–18:00；具体路段请查看现场标志。',
    ruleUrl: 'https://www.transportprojects.org.nz/current/newtown-to-city/project-details',
  },
];
const collections = [];
for (const item of candidates) {
  const query = new URL(item.gis + '/query');
  query.search = new URLSearchParams({
    f: 'geojson', where: item.field + " = '" + item.roadName.replaceAll("'", "''") + "'",
    outFields: item.field, outSR: '4326', returnGeometry: 'true', resultRecordCount: '1000',
  }).toString();
  const response = await fetch(query, { signal: AbortSignal.timeout(15000), headers: { 'User-Agent': 'Waybi open data validation' } });
  if (!response.ok) throw new Error(item.roadName + ' HTTP ' + response.status);
  const json = await response.json();
  if (json.error || !Array.isArray(json.features) || json.features.length === 0 || json.exceededTransferLimit) {
    throw new Error('Missing or truncated council centreline ' + item.roadName);
  }
  const segments = [];
  for (const f of json.features) {
    const geo = f.geometry;
    const paths = geo?.type === 'LineString' ? [geo.coordinates]
      : geo?.type === 'MultiLineString' ? geo.coordinates : [];
    for (const part of paths) {
      const path = part.map(p => [Number(p[0].toFixed(6)), Number(p[1].toFixed(6))]);
      if (path.length < 2) continue;
      const valid = path.every(([lon,lat]) => item.city === 'Christchurch'
        ? lon >= 172.5 && lon <= 172.8 && lat >= -43.65 && lat <= -43.40
        : lon >= 174.69 && lon <= 174.88 && lat >= -41.39 && lat <= -41.23);
      if (!valid) throw new Error('Unexpected centreline geometry for ' + item.roadName);
      segments.push(path);
    }
  }
  if (!segments.length || segments.length > 150) throw new Error('Suspicious segment count for ' + item.roadName);
  // Native layer uses road centre-lines solely to illustrate known corridors;
  // NEVER assign a confident per-segment bus restriction from this geometry.
  const slug = item.roadName.toLowerCase().replace(/[^a-z]+/g, '-').replace(/-$/,'');
  const city = item.city.toLowerCase();
  segments.sort((a,b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  for (let index=0;index<segments.length;index++) {
    collections.push({
      id: city + ':' + slug + ':' + index,
      city: item.city, roadName: item.roadName, authority: item.authority,
      ruleSummary: item.rule, ruleSummaryZh: item.ruleZh, ruleSource: item.ruleUrl,
      geometrySource: item.gis,
      precision: 'corridor-only',
      coordinates: segments[index],
    });
  }
  console.log(item.city, item.roadName, 'road-centreline pieces:',segments.length);
}
if (collections.length < 45 || collections.length > 115) throw new Error('Candidate coverage unexpectedly changed');
const output = {
  schemaVersion: 1, datasetType: 'map-review-corridors-not-navigation-restrictions',
  geometryDisclaimer: 'Official road centreline approximations; not surveyed bus lane limits.',
  checkedAt: new Date().toISOString(),
  attribution: 'Contains road centreline data from Christchurch City Council and Wellington City Council; official published transport information is linked per corridor.',
  corridors: collections,
};
const target = new URL('../apps/mobile/assets/data/transit-corridors-review.json', import.meta.url);
await writeFile(target, JSON.stringify(output) + '\n');
console.log(JSON.stringify({ candidates: collections.length, roads:candidates.length, bytes: Buffer.byteLength(JSON.stringify(output)) }));
