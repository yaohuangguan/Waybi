import test from 'node:test';
import assert from 'node:assert/strict';
import { linzNzAddressProvider } from '../src/search/regional/linz_nz_addresses.mjs';
import { searchIndependentGlobal } from '../src/search/independent_global_search.mjs';

test('LINZ national provider resolves an exact numbered address and keeps coordinates', async () => {
  const fetcher = async (url) => {
    assert.match(
      url.searchParams.get('where') || '',
      /42 VERISSIMO DRIVE/
    );
    return Response.json({
      features: [
        {
          properties: {
            OBJECTID: 1,
            address_id: 4242,
            full_address_ascii: '42 VERISSIMO DRIVE MANGERE AUCKLAND 2022',
            road_name_ascii: 'VERISSIMO DRIVE',
            suburb_locality_ascii: 'MANGERE',
            town_city_ascii: 'AUCKLAND',
            territorial_authority_ascii: 'AUCKLAND',
          },
          geometry: { coordinates: [174.789, -36.989] },
        },
      ],
    });
  };

  const results = await linzNzAddressProvider.search({
    parsed: { number: '42', roadName: 'Verissimo', roadType: 'DRIVE' },
    fetcher,
  });

  assert.equal(results.length, 1);
  assert.equal(results[0].provider, 'regional:linz-nz-addresses');
  assert.match(results[0].name, /^42 Verissimo Drive/i);
  assert.equal(results[0].latitude, -36.989);
  assert.equal(results[0].longitude, 174.789);
});

test('LINZ national provider never runs outside New Zealand', () => {
  assert.equal(
    linzNzAddressProvider.supports({
      near: [139.767, 35.681],
      parsed: { number: '1', roadName: 'Chiyoda', roadType: null },
    }),
    false
  );
});

test('Independent worldwide search accepts TomTom results without Google', async () => {
  const previous = globalThis.fetch;
  const hosts = [];
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    hosts.push(parsed.hostname);
    if (parsed.hostname === 'api.geoapify.com') {
      return new Response('unavailable', { status: 503 });
    }
    if (parsed.hostname === 'api.tomtom.com') {
      return Response.json({
        results: [
          {
            id: 'tt-42',
            type: 'Point Address',
            address: {
              streetNumber: '42',
              streetName: 'Verissimo Drive',
              freeformAddress: '42 Verissimo Drive, Māngere, Auckland 2022',
              municipality: 'Auckland',
              country: 'New Zealand',
            },
            position: { lat: -36.989, lon: 174.789 },
          },
        ],
      });
    }
    throw new Error('unexpected upstream ' + parsed.hostname);
  };

  try {
    const results = await searchIndependentGlobal({
      query: '42 Verissimo Drive',
      point: [174.79, -36.98],
      language: 'en',
      env: {
        GEOAPIFY_API_KEY: 'geo',
        TOMTOM_SEARCH_API_KEY: 'tomtom',
        GOOGLE_ROUTES_API_KEY: 'must-not-be-used',
      },
      enrichmentsPromise: Promise.resolve([]),
    });
    assert.equal(results[0].provider, 'tomtom');
    assert.match(results[0].name, /^42 Verissimo Drive/i);
    assert.ok(hosts.includes('api.tomtom.com'));
    assert.ok(!hosts.includes('places.googleapis.com'));
  } finally {
    globalThis.fetch = previous;
  }
});
