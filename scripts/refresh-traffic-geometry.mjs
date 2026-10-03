import { mkdir, writeFile } from 'node:fs/promises';
import { fetchNztaTrafficFlow } from '../apps/server/src/traffic_flow.mjs';
import { createRoadGraph, matchTrafficGeometry } from '../apps/server/src/traffic_geometry.mjs';

const flow = await fetchNztaTrafficFlow();
const points = flow.segments.flatMap(s => [s.start, s.end]);
const south = Math.min(...points.map(p => p.latitude)) - .015;
const north = Math.max(...points.map(p => p.latitude)) + .015;
const west = Math.min(...points.map(p => p.longitude)) - .015;
const east = Math.max(...points.map(p => p.longitude)) + .015;
// Bound this maintenance job to the present Auckland feed. It never runs on
// individual map interactions or live requests to the shared Overpass server.
if (north - south > 1 || east - west > 1) throw new Error('Feed extent changed: refresh regions explicitly');
const query = `[out:json][timeout:30];way["highway"~"^(motorway|trunk|primary|secondary)$"](${south},${west},${north},${east});out geom;`;
const response = await fetch('https://overpass-api.de/api/interpreter', {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'Waybi/1.0 (https://github.com/yaohuangguan/Waybi)' },
  body: new URLSearchParams({ data: query }), signal: AbortSignal.timeout(45000),
});
if (!response.ok) throw new Error(`Road network HTTP ${response.status}`);
const roads = await response.json();
if (roads.remark) throw new Error(roads.remark);
const graph = createRoadGraph(roads.elements || []);
const segments = {};
for (const segment of flow.segments) {
  const start = [segment.start.longitude, segment.start.latitude];
  const end = [segment.end.longitude, segment.end.latitude];
  const coordinates = matchTrafficGeometry(graph, start, end);
  if (coordinates) segments[segment.id] = { start, end, coordinates: coordinates.map(p => p.map(n => Number(n.toFixed(7)))) };
}
if (Object.keys(segments).length < flow.segments.length * .7) throw new Error('Insufficient matching coverage; existing geometry retained');
await mkdir(new URL('../apps/server/data/', import.meta.url), { recursive: true });
await writeFile(new URL('../apps/server/data/traffic-road-geometry.json', import.meta.url), JSON.stringify({
  generatedAt: new Date().toISOString(), source: 'OpenStreetMap', sourceUrl: 'https://www.openstreetmap.org/copyright',
  license: 'ODbL-1.0', segments,
}) + '\n');
console.log(`Matched ${Object.keys(segments).length}/${flow.segments.length} traffic sections to directed road geometry.`);
