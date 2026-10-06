import test from 'node:test';
import assert from 'node:assert/strict';
import { parseNumberedStreetQuery } from '../src/search/numbered_street_query.mjs';
import { searchRegionalAddressEnrichments } from '../src/search/regional_address_registry.mjs';

test('numbered street parsing is global and region-agnostic', () => {
  assert.deepEqual(parseNumberedStreetQuery('42 Verissimo Drive'), {
    number: '42', roadName: 'Verissimo', roadType: 'DRIVE'
  });
  assert.deepEqual(parseNumberedStreetQuery('221B Baker Street, London'), {
    number: '221B', roadName: 'Baker', roadType: 'STREET'
  });
  assert.equal(parseNumberedStreetQuery('Tokyo Station'), null);
});

test('regional enrichment never runs outside an adapter service area', async () => {
  let calls = 0;
  const results = await searchRegionalAddressEnrichments(
    '42 Verissimo Drive',
    [139.767, 35.681],
    async () => { calls += 1; throw new Error('must not run'); }
  );
  assert.deepEqual(results, []);
  assert.equal(calls, 0);
});

test('street-only queries are eligible for regional street enrichment', async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    if (parsed.hostname.includes('arcgis.com')) {
      return Response.json({
        features: [
          {
            properties: {
              OBJECTID: 1,
              address_id: 1,
              full_address_ascii: '34 VERISSIMO DRIVE MANGERE AUCKLAND 2022',
              road_name_ascii: 'VERISSIMO DRIVE',
              suburb_locality_ascii: 'MANGERE',
              town_city_ascii: 'AUCKLAND',
              territorial_authority_ascii: 'AUCKLAND',
            },
            geometry: { coordinates: [174.7887, -36.9882] },
          },
          {
            properties: {
              OBJECTID: 2,
              address_id: 2,
              full_address_ascii: '46 VERISSIMO DRIVE MANGERE AUCKLAND 2022',
              road_name_ascii: 'VERISSIMO DRIVE',
              suburb_locality_ascii: 'MANGERE',
              town_city_ascii: 'AUCKLAND',
              territorial_authority_ascii: 'AUCKLAND',
            },
            geometry: { coordinates: [174.7897, -36.9909] },
          },
        ],
      });
    }
    throw new Error('unexpected upstream ' + parsed.hostname);
  };
  try {
    const { searchRegionalAddressEnrichments } = await import('../src/search/regional_address_registry.mjs');
    const results = await searchRegionalAddressEnrichments('Verissimo Drive', [174.79, -36.98]);
    assert.equal(results.length, 1);
    assert.equal(results[0].name, 'Verissimo Drive');
    assert.match(results[0].address, /Mangere/i);
  } finally {
    globalThis.fetch = previous;
  }
});
