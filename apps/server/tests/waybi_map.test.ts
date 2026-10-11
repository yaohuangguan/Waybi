import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { normalizeNearby, selectNearby, commonsPhoto, independentExplore } from '../src/independent_explore.ts';
import { mockEdgeCache } from './mock_edge_cache.ts';
import { createRoadGraph, matchTrafficGeometry } from '../src/traffic_geometry.ts';
import { withRoadGeometry } from '../src/traffic_flow.ts';
import { trafficTileConfig, handleTrafficTile } from '../src/traffic_tiles.ts';
import { PbfWriter } from 'pbf';
import { decodeTilePlaces, nearbyTilePlaces } from '../src/vector_places.ts';

const point = [174.7633, -36.8485];
const elements = Array.from({ length: 12 }, (_, i) => ({ type: 'node', id: i, lat: point[1], lon: point[0] + i / 10000,
  tags: { name: `Cafe ${i}`, amenity: 'cafe' } })).concat([
  { type: 'way', id: 20, center: { lat: -36.85, lon: 174.765 }, tags: { name: 'Park', 'name:zh': '公园', leisure: 'park' } },
  { type: 'node', id: 21, lat: -36.851, lon: 174.767, tags: { name: 'Museum', tourism: 'museum' } },
  { type: 'node', id: 22, lat: -36.852, lon: 174.768, tags: { name: 'Restaurant', amenity: 'restaurant' } },
  { type: 'node', id: 23, lat: -36.853, lon: 174.769, tags: { name: 'Books', shop: 'books' } },
  { type: 'node', id: 24, lat: -41, lon: 174, tags: { name: 'Far away', amenity: 'cafe' } },
]);
test('nearby discovery balances categories, enforces radius and localizes names', () => {
  const places = normalizeNearby(elements, point, 'zh');
  const result = selectNearby(places, point);
  assert.deepEqual(result.slice(0, 5).map(p => p.primaryType), ['activities', 'parks', 'food', 'coffee', 'shopping']);
  assert.equal(result.find(p => p.primaryType === 'parks').name, '公园');
  assert.ok(!result.some(p => p.name === 'Far away'));
  assert.ok(selectNearby(places, point, 'parks').every(p => p.primaryType === 'parks'));
  assert.equal(selectNearby(places, point, 'for-you', 'Books').length, 1);
});
test('photo metadata rejects unlicensed images and arbitrary external URLs', () => {
  const page = { imageinfo: [{ thumburl: 'https://upload.wikimedia.org/example.jpg', descriptionurl: 'https://commons.wikimedia.org/wiki/File:Example.jpg',
    extmetadata: { LicenseShortName: { value: 'CC BY-SA 4.0' }, LicenseUrl: { value: 'https://creativecommons.org/licenses/by-sa/4.0/' }, Artist: { value: '<a href="bad">Photographer</a>' } } }] };
  const photo = commonsPhoto(page); assert.equal(photo.photoCredit.author, 'Photographer');
  page.imageinfo[0].extmetadata.LicenseShortName.value = 'CC BY-SA 3.0 nz';
  page.imageinfo[0].extmetadata.LicenseUrl.value = 'https://creativecommons.org/licenses/by-sa/3.0/nz/deed.en';
  assert.equal(commonsPhoto(page).photoCredit.license, 'CC BY-SA 3.0 nz');
  page.imageinfo[0].extmetadata.LicenseShortName.value = 'CC BY-NC-SA 3.0'; assert.equal(commonsPhoto(page), null);
  page.imageinfo[0].extmetadata.LicenseShortName.value = 'All rights reserved'; assert.equal(commonsPhoto(page), null);
  page.imageinfo[0].extmetadata.LicenseShortName.value = 'CC BY-SA 4.0'; page.imageinfo[0].thumburl = 'http://localhost/private'; assert.equal(commonsPhoto(page), null);
});

test('recommendations bring real photos forward while keeping nearby categories balanced', () => {
  const places = normalizeNearby(elements, point);
  places.find(p => p.primaryType === 'activities').photoUrl = 'https://upload.wikimedia.org/real.jpg';
  places.push({ ...places[0], placeId: 'photo-cafe', name: 'Photographed cafe', longitude: point[0] + .01, photoUrl: 'https://upload.wikimedia.org/cafe.jpg' });
  const result = selectNearby(places, point);
  assert.deepEqual(result.slice(0, 5).map(p => p.primaryType), ['activities', 'parks', 'food', 'coffee', 'shopping']);
  assert.equal(result[3].name, 'Photographed cafe');
  assert.equal(selectNearby(places, point, 'coffee')[0].name, 'Cafe 0');
});

function pointTile() {
  const writer = new PbfWriter();
  writer.writeMessage(3, (_, layer) => {
    layer.writeStringField(1, 'poi');
    layer.writeMessage(2, (_, feature) => {
      feature.writeVarintField(1, 42);
      feature.writePackedVarint(2, [0, 0, 1, 1, 2, 2, 3, 3]);
      feature.writeVarintField(3, 1);
      feature.writePackedVarint(4, [9, 4096, 4096]);
    }, null);
    for (const key of ['class', 'subclass', 'name', 'name:zh']) layer.writeStringField(3, key);
    for (const value of ['attraction', 'museum', 'Sky Tower', '天空塔']) {
      layer.writeMessage(4, (text, field) => field.writeStringField(1, text), value);
    }
    layer.writeVarintField(5, 4096);
    layer.writeVarintField(15, 2);
  }, null);
  return writer.finish();
}

test('open map POIs decode MVT point coordinates and localized names at zoom 14', async () => {
  const bytes = pointTile();
  const [place] = decodeTilePlaces(bytes, 16145, 9998, 14, 'zh');
  assert.equal(place.name, '天空塔');
  assert.equal(place.englishName, 'Sky Tower');
  assert.equal(place.primaryType, 'activities');
  assert.ok(Math.abs(place.longitude - ((16145.5 / 16384) * 360 - 180)) < 1e-8);
  assert.ok(place.latitude < -36 && place.latitude > -37);
  assert.equal(place.photoUrl, null);
  let tiles = 0;
  const fetcher = async target => {
    if (String(target).endsWith('/planet')) return Response.json({ tiles: ['https://tiles.openfreemap.org/planet/test/{z}/{x}/{y}.pbf'] });
    assert.ok(String(target).includes('/14/'));
    if (++tiles === 1) throw new Error('One tile unavailable');
    return new Response(bytes);
  };
  assert.ok((await nearbyTilePlaces(point, 'zh', fetcher)).length > 0);
  assert.equal(tiles, 4);
});
test('independent Explore uses public edge cache, never KV writes, and no Google calls', async () => {
  const edge = mockEdgeCache();
  const urls = [], env = { CAMERA_DATA: { get: async () => { throw Error('KV read forbidden'); }, put: async () => { throw Error('KV write forbidden'); } } };
  try {
    const fetcher = async url => {
      urls.push(String(url));
      if (String(url).includes('overpass')) return Response.json({ elements });
      return Response.json({ query: { pages: [] } });
    };
    const url = new URL('https://example.test/api/explore?at=174.7633,-36.8485&lang=zh');
    assert.equal((await independentExplore(url, env, fetcher)).status, 200);
    assert.equal(edge.entries.size, 2, 'store fresh and fallback copies in edge cache');
    const calls = urls.length; url.searchParams.set('category', 'parks');
    const parks = await (await independentExplore(url, env, fetcher)).json();
    assert.equal(urls.length, calls); assert.equal(parks[0].name, '公园');
    assert.ok(!urls.some(url => url.includes('google')));
    assert.equal((await independentExplore(new URL('https://example.test/?at=181,91'), env, fetcher)).status, 400);
  } finally { edge.restore(); }
});
const way = (nodes, coordinates, oneway = 'yes') => ({ type: 'way', nodes, tags: { oneway }, geometry: coordinates.map(p => ({ lon: p[0], lat: p[1] })) });

test('discovery retries upstream and retains previous edge snapshot during outages', async () => {
  const edge = mockEdgeCache();
  try {
    let attempts = 0;
    const env = { CAMERA_DATA: { put: async () => { throw Error('No KV puts'); } } };
    const url = new URL('https://example.test/api/explore?at=174.7633,-36.8485');
    const fallback = async target => {
      if (String(target).includes('overpass')) {
        attempts++;
        return attempts === 1 ? new Response('Busy', { status: 429 }) : Response.json({ elements });
      }
      return Response.json({ query: { pages: [] } });
    };
    assert.equal((await independentExplore(url, env, fallback)).status, 200);
    assert.equal(attempts, 2);
    for (const key of edge.entries.keys()) if (!key.endsWith('/previous')) edge.entries.delete(key);
    const previous = await (await independentExplore(url, env, async () => { throw new Error('Offline'); })).json();
    assert.ok(previous.length > 0);
  } finally { edge.restore(); }
});
test('road matching follows curves and respects one-way disconnected carriageways', () => {
  const coords = [[174.7, -36.8], [174.701, -36.799], [174.702, -36.8], [174.703, -36.8]];
  const network = createRoadGraph([way([1, 2, 3, 4], coords)]);
  const shape = matchTrafficGeometry(network, coords[0], coords[3], 20);
  assert.ok(shape.some(p => p[1] > -36.7995));
  assert.equal(matchTrafficGeometry(network, coords[3], coords[0], 20), null);
  const disconnected = createRoadGraph([way([1, 2], coords.slice(0, 2)), way([3, 4], coords.slice(2))]);
  assert.equal(matchTrafficGeometry(disconnected, coords[0], coords[3], 20), null);
});
test('traffic only trusts matching endpoints; stale flow becomes unknown', () => {
  const roads = JSON.parse(readFileSync(new URL('../data/traffic-road-geometry.json', import.meta.url)));
  const [id, shape] = Object.entries(roads.segments)[0];
  const segment = { id, level: 'free', start: { longitude: shape.start[0], latitude: shape.start[1] }, end: { longitude: shape.end[0], latitude: shape.end[1] } };
  const state = { segments: [segment], sourceUpdatedAt: '2026-10-03T01:00:00Z', syncStatus: 'live' };
  assert.equal(withRoadGeometry(state, {}, new Date('2026-10-03T01:01:00Z')).segments[0].geometryQuality, 'road-matched');
  const old = withRoadGeometry(state, {}, new Date('2026-10-03T02:00:00Z')); assert.equal(old.syncStatus, 'stale'); assert.equal(old.segments[0].level, 'unknown');
  segment.start.longitude += .01; assert.equal(withRoadGeometry(state).segments[0].geometry, null);
});
function budgetDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE traffic_tile_budget (month TEXT PRIMARY KEY, requests INTEGER NOT NULL DEFAULT 0)');
  return { prepare: sql => ({ bind: (...values) => ({ first: async () => db.prepare(sql).get(...values) ?? null }) }) };
}
test('optional street traffic requires explicit configuration and caps upstream requests atomically', async () => {
  assert.equal(trafficTileConfig({ TOMTOM_TRAFFIC_API_KEY: 'secret' }), null);
  const env = { TRAFFIC_TILES_ENABLED: 'true', TOMTOM_TRAFFIC_API_KEY: 'secret', TRAFFIC_TILES_MONTHLY_BUDGET: '1', USER_DB: budgetDb() };
  const request = new Request('https://example.test/api/map/traffic/tiles/12/4036/2499.png');
  let calls = 0;
  const fetcher = async url => { calls++; assert.equal(new URL(url).hostname, 'api.tomtom.com'); return new Response(new Uint8Array([1]), { headers: { 'content-type': 'image/png' } }); };
  assert.equal((await handleTrafficTile(request, env, fetcher)).status, 200);
  assert.equal((await handleTrafficTile(request, env, fetcher)).status, 429); assert.equal(calls, 1);
  assert.equal((await handleTrafficTile(new Request('https://example.test/api/map/traffic/tiles/22/1/1.png'), env, fetcher)).status, 400);
  assert.equal((await handleTrafficTile(request, {}, fetcher)).status, 503);
});
