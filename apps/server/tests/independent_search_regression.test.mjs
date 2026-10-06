import test from 'node:test';
import assert from 'node:assert/strict';

import { searchIndependentGlobal } from '../src/search/independent_global_search.mjs';
import { mergeAndRankSearchResults } from '../src/search/search_orchestrator.mjs';

const verissimoNeighbors = [
  {
    id: '34',
    provider: 'regional:test-addresses',
    sourceName: 'Official test addresses',
    name: '34 Verissimo Drive',
    address: '34 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
    label: '34 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
    isPoi: false,
    latitude: -36.9882,
    longitude: 174.7887,
  },
  {
    id: '46',
    provider: 'regional:test-addresses',
    sourceName: 'Official test addresses',
    name: '46 Verissimo Drive',
    address: '46 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
    label: '46 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
    isPoi: false,
    latitude: -36.9909,
    longitude: 174.7897,
  },
];

test('partial 42 veri produces a selectable exact/interpolated address without Google', async () => {
  const previous = globalThis.fetch;
  const hosts = [];
  globalThis.fetch = async (url) => {
    hosts.push(new URL(url).hostname);
    throw new Error('global providers should not be needed for the official-address fast path');
  };

  try {
    const started = Date.now();
    const results = await Promise.race([
      searchIndependentGlobal({
        query: '42 veri',
        point: [174.79, -36.98],
        language: 'en',
        env: {
          GEOAPIFY_API_KEY: 'unused-on-fast-path',
          TOMTOM_SEARCH_API_KEY: 'unused-on-fast-path',
          GOOGLE_ROUTES_API_KEY: 'must-never-be-used-for-search',
        },
        enrichmentsPromise: Promise.resolve(verissimoNeighbors),
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('independent address typeahead exceeded 450 ms')), 450),
      ),
    ]);

    assert.ok(Date.now() - started < 450);
    assert.equal(results[0].name, '42 Verissimo Drive');
    assert.equal(results[0].provider, 'derived:address-interpolation');
    assert.equal(results[0].interpolated, true);
    assert.ok(Number.isFinite(results[0].latitude));
    assert.ok(Number.isFinite(results[0].longitude));
    assert.ok(!hosts.includes('places.googleapis.com'));
  } finally {
    globalThis.fetch = previous;
  }
});

test('street-only results collapse same-locality duplicates but retain different localities', () => {
  const merged = mergeAndRankSearchResults(
    [
      [
        {
          id: 'osm-1', provider: 'osm', name: 'Verissimo Drive',
          address: 'Māngere, Auckland 2022, New Zealand',
          label: 'Verissimo Drive, Māngere, Auckland 2022, New Zealand',
          isPoi: false, latitude: -36.989, longitude: 174.789,
        },
        {
          id: 'tomtom-1', provider: 'tomtom', name: 'Verissimo Drive',
          address: 'Māngere, Auckland 2022, New Zealand',
          label: 'Verissimo Drive, Māngere, Auckland 2022, New Zealand',
          isPoi: false, latitude: -36.9891, longitude: 174.7891,
        },
        {
          id: 'other-locality', provider: 'osm', name: 'Verissimo Drive',
          address: 'Another City, Example Region, New Zealand',
          label: 'Verissimo Drive, Another City, Example Region, New Zealand',
          isPoi: false, latitude: -38.0, longitude: 176.0,
        },
      ],
    ],
    'Verissimo Drive',
    [174.79, -36.98],
    12,
  );

  const mangere = merged.filter((item) => /Māngere/i.test(item.address));
  assert.equal(mangere.length, 1, 'same street/locality must not render as indistinguishable duplicates');
  assert.ok(merged.some((item) => /Another City/i.test(item.address)));
  assert.ok(merged.every((item) => item.address && item.address !== item.name));
});

test('concurrent identical independent searches share one upstream request and then hit cache', async () => {
  const previous = globalThis.fetch;
  let tomtomCalls = 0;
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    if (parsed.hostname !== 'api.tomtom.com') {
      throw new Error('unexpected upstream ' + parsed.hostname);
    }
    tomtomCalls++;
    await new Promise((resolve) => setTimeout(resolve, 35));
    return Response.json({
      results: [
        {
          id: 'tt-cache-test',
          type: 'Point Address',
          address: {
            streetNumber: '987',
            streetName: 'Concurrency Test Road',
            freeformAddress: '987 Concurrency Test Road, Test City',
            municipality: 'Test City',
            country: 'New Zealand',
          },
          position: { lat: -36.9, lon: 174.8 },
        },
      ],
    });
  };

  try {
    const args = {
      query: '987 Concurrency Test Road',
      point: [174.8, -36.9],
      language: 'en',
      env: { TOMTOM_SEARCH_API_KEY: 'test-key' },
      enrichmentsPromise: Promise.resolve([]),
    };
    const [first, second] = await Promise.all([
      searchIndependentGlobal(args),
      searchIndependentGlobal(args),
    ]);
    assert.equal(tomtomCalls, 1, 'in-flight duplicate requests must coalesce');
    assert.equal(first[0].name, '987 Concurrency Test Road');
    assert.deepEqual(second, first);

    const cached = await searchIndependentGlobal(args);
    assert.equal(tomtomCalls, 1, 'resolved result must be served from search cache');
    assert.deepEqual(cached, first);
  } finally {
    globalThis.fetch = previous;
  }
});
