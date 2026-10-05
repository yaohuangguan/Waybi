import test from 'node:test';
import assert from 'node:assert/strict';
import { rankPlaces } from '../src/place_search_rank.mjs';

test('nearby matching POIs outrank remote namesakes', () => {
  const near = [174.7633, -36.8485];
  const ranked = rankPlaces([
    { name: '福地', address: 'Gifu, Japan', latitude: 35.4, longitude: 136.7 },
    { name: '福地亚洲超市', address: 'Auckland, New Zealand', latitude: -36.91, longitude: 174.80 },
  ], '福地', near);
  assert.equal(ranked[0].name, '福地亚洲超市');
  assert.ok(ranked[0].distanceMeters < ranked[1].distanceMeters);
});

test('global results remain available when no nearby candidate exists', () => {
  const ranked = rankPlaces([
    { name: 'Tokyo', address: 'Tokyo, Japan', latitude: 35.6762, longitude: 139.6503 },
    { name: 'Tokyo Station', address: 'Tokyo, Japan', latitude: 35.6812, longitude: 139.7671 },
  ], 'Tokyo', [174.7633, -36.8485]);
  assert.equal(ranked[0].name, 'Tokyo');
});

test('house-number address relevance beats nearby street-only fragments', () => {
  const near = [174.79, -36.99];
  const ranked = rankPlaces([
    { name: 'Verissimo Drive', address: 'Māngere, Auckland 2022, New Zealand', latitude: -36.988, longitude: 174.789 },
    { name: '42 Verissimo Drive', address: '42 Verissimo Drive, Māngere, Auckland 2022, New Zealand', latitude: -36.9918, longitude: 174.7899 },
  ], '42 Verissimo Drive', near);
  assert.equal(ranked[0].name, '42 Verissimo Drive');
});


test('partial numbered-address suggestions prefer closest house numbers before GPS distance', () => {
  const near = [174.79, -36.98];
  const ranked = rankPlaces([
    { name: '5 Verissimo Drive', address: '5 Verissimo Drive, Mangere', latitude: -36.9801, longitude: 174.7901 },
    { name: '46 Verissimo Drive', address: '46 Verissimo Drive, Mangere', latitude: -36.991, longitude: 174.787 },
    { name: '34 Verissimo Drive', address: '34 Verissimo Drive, Mangere', latitude: -36.989, longitude: 174.788 },
  ], '42 veri', near);
  assert.deepEqual(ranked.map((item) => item.name), [
    '46 Verissimo Drive', '34 Verissimo Drive', '5 Verissimo Drive'
  ]);
});
