import test from 'node:test';
import assert from 'node:assert/strict';
import { SuggestionCache, suggestionCacheKey } from '../src/search/suggestion_cache.ts';
import { handlePlaces } from '../src/places.ts';

const results = [{ name: '42 Example Drive', latitude: -36.9, longitude: 174.8 }];

test('50 simultaneous address lookups use one upstream and independently readable responses', async () => {
  let calls = 0;
  const cache = new SuggestionCache(() => undefined);
  const load = async () => {
    calls++;
    await new Promise(resolve => setTimeout(resolve, 15));
    return Response.json(results);
  };
  const responses = await Promise.all(Array.from({ length: 50 }, () => cache.load('same address', load)));
  assert.equal(calls, 1);
  for (const response of responses) assert.deepEqual(await response.json(), results);
  assert.equal((await cache.load('same address', load)).headers.get('x-waybi-search-cache'), 'MEMORY');
  assert.equal(calls, 1);
});

test('query normalization preserves country/search-area and language boundaries', () => {
  const key = suggestionCacheKey(' 42 VERI ', [174.7633, -36.8576], 'en');
  assert.equal(key, suggestionCacheKey('42 veri', [174.764, -36.856], 'en'));
  assert.notEqual(key, suggestionCacheKey('42 veri', [151.2, -33.8], 'en'));
  assert.notEqual(key, suggestionCacheKey('42 veri', [174.7633, -36.8576], 'zh'));
});

test('empty results and upstream failures retry immediately; successful results expire', async () => {
  let time = 0;
  let calls = 0;
  const cache = new SuggestionCache(() => undefined, () => time);
  const load = async () => {
    calls++;
    return calls === 1 ? new Response('unavailable', { status: 502 }) :
      Response.json(calls === 2 ? [] : results);
  };
  assert.equal((await cache.load('address', load)).status, 502);
  assert.deepEqual(await (await cache.load('address', load)).json(), []);
  assert.deepEqual(await (await cache.load('address', load)).json(), results);
  await cache.load('address', load);
  assert.equal(calls, 3);
  time += 300001;
  await cache.load('address', load);
  assert.equal(calls, 4);
});

test('another Worker isolate can reuse the edge result without revealing the query in its cache URL', async () => {
  const store = new Map<string, Response>();
  const edge = {
    async match(request: Request) { return store.get(request.url)?.clone(); },
    async put(request: Request, response: Response) { store.set(request.url, response.clone()); },
  } as unknown as Cache;
  const first = new SuggestionCache(() => edge);
  await first.load('private-looking address|en|174.76|-36.86', async () => Response.json(results));
  assert.equal(store.size, 1);
  assert.ok(![...store.keys()][0].includes('address'));
  assert.equal([...store.values()][0].headers.get('cache-control'), 'public, max-age=300');
  const second = new SuggestionCache(() => edge);
  const response = await second.load('private-looking address|en|174.76|-36.86', async () => {
    throw new Error('must use completed edge result');
  });
  assert.equal(response.headers.get('x-waybi-search-cache'), 'EDGE');
  assert.deepEqual(await response.json(), results);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('cache outages cannot block an otherwise successful search', async () => {
  const cache = new SuggestionCache(() => ({ async match() { throw new Error('cache offline'); } }) as unknown as Cache);
  assert.deepEqual(await (await cache.load('address', async () => Response.json(results))).json(), results);
});

test('the public independent endpoint coalesces official adapters too and its repeat lookup makes no upstream calls', async () => {
  const previous = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    calls.push(url.hostname);
    await new Promise(resolve => setTimeout(resolve, 10));
    if (url.hostname === 'services.arcgis.com') return Response.json({ features: [] });
    assert.equal(url.hostname, 'mapspublic.aucklandcouncil.govt.nz');
    return Response.json({ features: [80, 84].map((number, index) => ({
      properties: { OBJECTID: number, FullNumber: String(number), RoadName: 'CACHE TEST', RoadType: 'DRIVE', Locality: 'MANGERE' },
      geometry: { coordinates: [174.8, -36.9 - index * .001] },
    })) });
  };
  try {
    const request = new Request('https://waybi.co/api/suggest?provider=independent&q=82%20Cache%20Test%20Drive&near=174.76,-36.86');
    const responses = await Promise.all(Array.from({ length: 50 }, () => handlePlaces(request, {})));
    for (const response of responses) {
      assert.equal(response.status, 200);
      assert.equal((await response.json())[0].name, '82 Cache Test Drive');
    }
    assert.equal(calls.length, 2);
    const cached = await handlePlaces(request, {});
    assert.equal(cached.headers.get('x-waybi-search-cache'), 'MEMORY');
    assert.equal(calls.length, 2);
  } finally { globalThis.fetch = previous; }
});
