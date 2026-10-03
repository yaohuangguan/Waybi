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
