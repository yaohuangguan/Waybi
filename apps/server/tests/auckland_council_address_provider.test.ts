import test from 'node:test';
import assert from 'node:assert/strict';
import { parseNumberedStreetQuery } from '../src/search/numbered_street_query.ts';
import { aucklandCouncilAddressProvider } from '../src/search/regional/auckland_council.ts';

test('Auckland Council is an optional regional adapter with a namespaced provider id', async () => {
  const parsed = parseNumberedStreetQuery('42 Verissimo Drive');
  assert.equal(
    aucklandCouncilAddressProvider.supports({ near: [174.79, -36.98], parsed }),
    true
  );
  assert.equal(
    aucklandCouncilAddressProvider.supports({ near: [151.21, -33.87], parsed }),
    false
  );
  const fetcher = async () => new Response(JSON.stringify({
    features: [
      { properties: { OBJECTID: 1, FullNumber: '12', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '12 VERISSIMO DRIVE MANGERE AUCKLAND 2022' }, geometry: { coordinates: [174.791, -36.982] } },
      { properties: { OBJECTID: 2, FullNumber: '46', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '46 VERISSIMO DRIVE MANGERE 2022' }, geometry: { coordinates: [174.787, -36.991] } },
      { properties: { OBJECTID: 3, FullNumber: '34', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '34 VERISSIMO DRIVE MANGERE 2022' }, geometry: { coordinates: [174.788, -36.989] } }
    ]
  }), { headers: { 'content-type': 'application/json' } });
  const results = await aucklandCouncilAddressProvider.search({ parsed, fetcher });
  assert.deepEqual(results.map((item) => item.name), [
    '46 Verissimo Drive', '34 Verissimo Drive', '12 Verissimo Drive'
  ]);
  assert.ok(results.every((item) => item.provider === 'regional:auckland-council'));
});

test('partial numbered street input uses a safe street-prefix lookup for autocomplete', async () => {
  const parsed = parseNumberedStreetQuery('42 veri');
  let where = '';
  const fetcher = async (url) => {
    where = url.searchParams.get('where') || '';
    return new Response(JSON.stringify({
      features: [
        { properties: { OBJECTID: 46, FullNumber: '46', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '46 VERISSIMO DRIVE MANGERE AUCKLAND 2022' }, geometry: { coordinates: [174.787, -36.991] } },
        { properties: { OBJECTID: 34, FullNumber: '34', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '34 VERISSIMO DRIVE MANGERE AUCKLAND 2022' }, geometry: { coordinates: [174.788, -36.989] } }
      ]
    }), { headers: { 'content-type': 'application/json' } });
  };
  const results = await aucklandCouncilAddressProvider.search({ parsed, fetcher });
  assert.match(where, /LIKE 'VERI%'/);
  assert.deepEqual(results.map((item) => item.name), ['46 Verissimo Drive', '34 Verissimo Drive']);
});

test('street-only Auckland query collapses official addresses into one street result', async () => {
  const fetcher = async () => Response.json({
    features: [
      { properties: { OBJECTID: 1, FullNumber: '34', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '34 VERISSIMO DRIVE MANGERE AUCKLAND 2022', Locality: 'MANGERE' }, geometry: { coordinates: [174.7887, -36.9882] } },
      { properties: { OBJECTID: 2, FullNumber: '46', RoadName: 'VERISSIMO', RoadType: 'DRIVE', FullAddress: '46 VERISSIMO DRIVE MANGERE AUCKLAND 2022', Locality: 'MANGERE' }, geometry: { coordinates: [174.7897, -36.9909] } },
    ]
  });
  const results = await aucklandCouncilAddressProvider.search({
    parsed: { number: null, roadName: 'Verissimo', roadType: 'DRIVE' },
    fetcher,
  });
  assert.equal(results.length, 1);
  assert.equal(results[0].name, 'Verissimo Drive');
  assert.match(results[0].address, /Mangere, Auckland 2022, New Zealand/i);
});
