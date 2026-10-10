import test from 'node:test';
import assert from 'node:assert/strict';
import { rankPlaces } from '../src/place_search_rank.ts';
import { maySearchGeographicName } from '../src/search/place_intent.ts';

test('exact city names outrank nearby spaced namesakes, streets and businesses worldwide', () => {
  for (const [query, city, nearby] of [
    ['christchurch', 'Christchurch, Canterbury, New Zealand', 'Christ Church'],
    ['wellington', 'Wellington', 'Wellington Street'],
    ['tokyo', 'Tōkyō', 'Tokyo Restaurant'],
    ['北京', '北京', '北京烤鸭'],
    ['上海', '上海市', '上海小吃'],
    ['new york', 'New York', 'New York Pizza'],
  ]) {
    const results = rankPlaces([
      { name: nearby, resultType: 'restaurant', isPoi: true, latitude: -36.85, longitude: 174.76 },
      { name: city, resultType: 'city', isPoi: false, latitude: 35, longitude: 139 },
    ], query, [174.76, -36.85]);
    assert.equal(results[0].name, city, query);
    assert.equal(rankPlaces(results.reverse(), query, null)[0].name, city);
  }
});

test('an explicit church/business name and category retain local intent', () => {
  const places = [
    { name: 'Christchurch', resultType: 'city', isPoi: false, latitude: -43.53, longitude: 172.64 },
    { name: 'Christ Church Ellerslie', resultType: 'place_of_worship', isPoi: true, latitude: -36.89, longitude: 174.81 },
  ];
  assert.equal(rankPlaces(places, 'Christ Church Ellerslie', [174.76, -36.85])[0].name, places[1].name);
  for (const query of ['church', 'cafes', 'Auckland Airport', '42 veri', '附近超市', 'Wellington Street']) {
    assert.equal(maySearchGeographicName(query), false, query);
  }
  assert.equal(maySearchGeographicName('St Albans'), true);
});

test('same-name cities use proximity and explicit geographic qualifiers', () => {
  const places = [
    { name: 'Wellington', address: 'Florida, United States', countryCode: 'US', resultType: 'city', latitude: 26.65, longitude: -80.26 },
    { name: 'Wellington', address: 'New Zealand', countryCode: 'NZ', resultType: 'city', latitude: -41.29, longitude: 174.78 },
  ];
  assert.equal(rankPlaces(places, 'Wellington', [174.76, -36.85])[0].countryCode, 'NZ');
  assert.equal(rankPlaces(places, 'Wellington US', [174.76, -36.85])[0].countryCode, 'US');
});

test('a city centre outranks the wider administrative region with the same name', () => {
  const results = rankPlaces([
    { name: '上海市', resultType: 'state', latitude: 31, longitude: 121 },
    { name: '上海市', resultType: 'city', latitude: 31.23, longitude: 121.47 },
  ], '上海', [174.76, -36.85]);
  assert.equal(results[0].resultType, 'city');
});

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
