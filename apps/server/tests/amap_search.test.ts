import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import worker from '../src/worker.ts';
import { amapAddress, amapReverse, amapSearchApplies, duplicatesPrimary, mapAmapPois, resetAmapSearchCaches, searchMainlandChina } from '../src/search/amap_search.ts';
import { AmapUnavailableError, amapConfigured, amapGet, resetAmapBackoff } from '../src/amap_client.ts';
import { amapClientDailyLimit, amapDailyLimit, reserveAmapCall } from '../src/amap_budget.ts';
import { rateLimitRule } from '../src/abuse_guard.ts';
import { distanceMeters } from '../src/geo.ts';
import { migratedD1 } from './d1_fixture.ts';

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/amap/${name}.json`, import.meta.url), 'utf8'));
const KEY = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const SHIJIAZHUANG: [number, number] = [114.51, 38.04];
// Ground truth WGS-84 positions behind the GCJ-02 fixture coordinates.
const LOCAL_COMPOUND: [number, number] = [114.5206, 38.0602];
const LUOHE_COMPOUND: [number, number] = [114.0166, 33.5815];

function amapFetch(routes: Record<string, (url: URL) => unknown>, calls: URL[] = []) {
  return async (input: RequestInfo | URL) => {
    const url = new URL(String(input instanceof Request ? input.url : input));
    calls.push(url);
    const handler = routes[url.hostname === 'restapi.amap.com' ? url.pathname : url.hostname];
    if (!handler) throw new Error(`unexpected request to ${url.hostname}${url.pathname}`);
    return Response.json(handler(url));
  };
}

async function withFetch<T>(fetcher: typeof fetch, work: () => Promise<T>): Promise<T> {
  const previous = globalThis.fetch;
  globalThis.fetch = fetcher;
  resetAmapBackoff();
  resetAmapSearchCaches();
  try { return await work(); } finally { globalThis.fetch = previous; }
}

async function captureWarnings<T>(work: () => Promise<T>): Promise<{ value: T; lines: string[] }> {
  const previous = console.warn;
  const lines: string[] = [];
  console.warn = (...args) => { lines.push(args.map(String).join(' ')); };
  try { return { value: await work(), lines }; } finally { console.warn = previous; }
}

test('盛世春天 near Shijiazhuang: the local compound ranks first, converted to WGS-84', async () => {
  const calls: URL[] = [];
  const results = await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v3/assistant/inputtips': () => fixture('inputtips_shengshichuntian'),
  }, calls) as typeof fetch, async () => (await searchMainlandChina({
    query: '盛世春天', point: SHIJIAZHUANG, language: 'zh', env: { AMAP_WEB_KEY: KEY },
    osmFallback: async () => assert.fail('three located Amap results need no OSM fallback'),
  })).results);

  assert.equal(results[0].name, '盛世春天');
  assert.equal(results[0].provider, 'amap');
  assert.equal(results[0].attribution, '高德地图 / AutoNavi');
  assert.match(results[0].address, /^河北省石家庄市长安区/);
  assert.ok(distanceMeters([results[0].longitude, results[0].latitude], LOCAL_COMPOUND) < 1,
    'GCJ-02 offset removed: the pin is on the compound, not ~500 m away');
  assert.ok(results[0].distanceMeters > 1000 && results[0].distanceMeters < 5000);
  const far = results.find(place => place.address.includes('漯河'));
  assert.ok(far, 'the distant namesake is kept, just not first');
  assert.ok(results.indexOf(far) > 0);
  assert.ok(distanceMeters([far.longitude, far.latitude], LUOHE_COMPOUND) < 1);
  assert.ok(far.distanceMeters > 490_000 && far.distanceMeters < 500_000);
  // A query suggestion and a bus line have no coordinates and are dropped.
  assert.equal(results.length, 3);
  assert.ok(results.every(place => Number.isFinite(place.distanceMeters)));

  const tips = calls.find(url => url.pathname === '/v3/assistant/inputtips');
  assert.equal(tips.searchParams.get('keywords'), '盛世春天');
  assert.equal(tips.searchParams.get('city'), '0311', 'city from the cached reverse geocode');
  assert.equal(tips.searchParams.get('location'), '114.515993,38.040634', 'proximity is sent in GCJ-02');
  assert.equal(tips.searchParams.get('key'), KEY);
  assert.equal(calls.filter(url => url.pathname === '/v3/geocode/regeo').length, 1);
});

test('the city lookup is shared by later searches in the same area', async () => {
  const calls: URL[] = [];
  await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v3/assistant/inputtips': () => fixture('inputtips_shengshichuntian'),
  }, calls) as typeof fetch, async () => {
    for (const query of ['盛世', '盛世春', '盛世春天']) {
      await searchMainlandChina({ query, point: SHIJIAZHUANG, env: { AMAP_WEB_KEY: KEY } });
    }
  });
  assert.equal(calls.filter(url => url.pathname === '/v3/geocode/regeo').length, 1);
  assert.equal(calls.filter(url => url.pathname === '/v3/assistant/inputtips').length, 3);
});

test('few input tips add an around search; geographic results stay geographic', async () => {
  const calls: URL[] = [];
  const results = await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v3/assistant/inputtips': () => ({ status: '1', info: 'OK', infocode: '10000', count: '0', tips: [] }),
    '/v5/place/around': () => fixture('place_around_kfc'),
  }, calls) as typeof fetch, async () => (await searchMainlandChina({
    query: '肯德基', point: SHIJIAZHUANG, env: { AMAP_WEB_KEY: KEY }, osmFallback: async () => [],
  })).results);
  const around = calls.find(url => url.pathname === '/v5/place/around');
  assert.equal(around.searchParams.get('location'), '114.515993,38.040634');
  assert.equal(around.searchParams.get('radius'), '50000');
  assert.equal(calls.some(url => url.pathname === '/v5/place/text'), false, 'text search only when nothing was found');
  const kfc = results.find(place => place.name.startsWith('肯德基'));
  assert.equal(kfc.isPoi, true);
  assert.equal(kfc.address, '河北省石家庄市长安区中山东路188号');
  const city = results.find(place => place.name === '石家庄市');
  assert.equal(city.isPoi, false);
  assert.equal(city.resultType, 'city');
});

test('a submitted search uses keyword and around search together', async () => {
  const calls: URL[] = [];
  await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v5/place/around': () => fixture('place_around_kfc'),
    '/v5/place/text': () => fixture('place_around_kfc'),
  }, calls) as typeof fetch, () => searchMainlandChina({
    query: '肯德基', point: SHIJIAZHUANG, env: { AMAP_WEB_KEY: KEY }, mode: 'search',
  }));
  const text = calls.find(url => url.pathname === '/v5/place/text');
  assert.equal(text.searchParams.get('region'), '0311');
  assert.equal(calls.some(url => url.pathname === '/v3/assistant/inputtips'), false);
});

test('Amap status "0" errors fall back to OSM, back off, and never log the key', async () => {
  const calls: URL[] = [];
  const osm = [{ id: 'node:1', provider: 'osm', name: '盛世春天', address: '漯河市', isPoi: true,
    latitude: LUOHE_COMPOUND[1], longitude: LUOHE_COMPOUND[0] }];
  const { value, lines } = await captureWarnings(() => withFetch(amapFetch({
    '/v3/geocode/regeo': () => ({ status: '0', info: 'INVALID_USER_KEY', infocode: '10001' }),
    '/v3/assistant/inputtips': () => ({ status: '0', info: 'INVALID_USER_KEY', infocode: '10001' }),
  }, calls) as typeof fetch, async () => {
    const first = await searchMainlandChina({ query: '盛世春天', point: SHIJIAZHUANG, env: { AMAP_WEB_KEY: KEY }, osmFallback: async () => osm });
    const second = await searchMainlandChina({ query: '盛世春天', point: [114.6, 38.1], env: { AMAP_WEB_KEY: KEY }, osmFallback: async () => osm });
    return { first, second };
  }));
  assert.equal(value.first.results[0].provider, 'osm');
  assert.equal(value.first.usedOsmFallback, true);
  assert.equal(value.first.amapCount, 0);
  assert.equal(value.second.results[0].provider, 'osm');
  assert.equal(calls.length, 1, 'an invalid key stops further Amap calls in this isolate');
  const failure = JSON.parse(lines.find(line => line.includes('amap_request_failed')));
  assert.deepEqual([failure.reason, failure.infocode, failure.info], ['status', '10001', 'INVALID_USER_KEY']);
  assert.ok(lines.every(line => !line.includes(KEY) && !line.includes('restapi.amap.com')));
});

test('HTTP errors, timeouts and invalid JSON are typed failures', async () => {
  const env = { AMAP_WEB_KEY: KEY };
  for (const [fetcher, reason] of [
    [async () => new Response('busy', { status: 503 }), 'http'],
    [async () => { throw Object.assign(new Error('slow'), { name: 'TimeoutError' }); }, 'timeout'],
    [async () => { throw new TypeError('fetch failed'); }, 'network'],
    [async () => new Response('<html>', { status: 200 }), 'invalid_json'],
  ] as const) {
    resetAmapBackoff();
    const { value } = await captureWarnings(() => amapGet(env, 'inputtips', { keywords: 'x' }, { fetcher: fetcher as typeof fetch })
      .then(() => null, (error) => error));
    assert.ok(value instanceof AmapUnavailableError);
    assert.equal(value.reason, reason);
  }
  await assert.rejects(amapGet({}, 'inputtips', {}), (error: AmapUnavailableError) => error.reason === 'not_configured');
  assert.equal(amapConfigured({ AMAP_WEB_KEY: 'short' }), false);
});

test('a quota infocode backs off only that API', async () => {
  resetAmapBackoff();
  const env = { AMAP_WEB_KEY: KEY };
  const calls: string[] = [];
  const fetcher = (async (input) => {
    const url = new URL(String(input));
    calls.push(url.pathname);
    return url.pathname.includes('inputtips')
      ? Response.json({ status: '0', info: 'DAILY_QUERY_OVER_LIMIT', infocode: '10003' })
      : Response.json({ status: '1', info: 'OK', infocode: '10000', regeocode: {} });
  }) as typeof fetch;
  await captureWarnings(async () => {
    await assert.rejects(amapGet(env, 'inputtips', {}, { fetcher }));
    await assert.rejects(amapGet(env, 'inputtips', {}, { fetcher }), (error: AmapUnavailableError) => error.reason === 'backoff');
    await amapGet(env, 'regeo', {}, { fetcher });
  });
  assert.deepEqual(calls, ['/v3/assistant/inputtips', '/v3/geocode/regeo']);
  resetAmapBackoff();
});

test('daily Amap budgets are enforced in D1, per API and per client', async () => {
  const { db } = migratedD1();
  const now = new Date('2026-11-27T10:00:00Z');
  const env = { USER_DB: db, WAYBI_AMAP_DAILY_BUDGET: JSON.stringify({ inputtips: 4, client_share: 0.5 }) };
  assert.equal(amapDailyLimit(env, 'inputtips'), 4);
  assert.equal(amapDailyLimit(env, 'driving'), 2500);
  assert.equal(amapClientDailyLimit(env, 'inputtips'), 2);
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:a', now), 'reserved');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:a', now), 'reserved');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:a', now), 'client_share');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:b', now), 'reserved');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:c', now), 'reserved');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:d', now), 'exhausted');
  assert.equal(await reserveAmapCall(env, 'inputtips', 'ip:d', new Date('2026-11-28T00:00:01Z')), 'reserved', 'UTC day reset');
  const failing = { USER_DB: { prepare() { throw new Error('D1 down'); } } };
  const { value } = await captureWarnings(() => reserveAmapCall(failing, 'driving', null, now));
  assert.equal(value, 'unavailable', 'a D1 outage fails closed');
  assert.equal(await reserveAmapCall({ USER_DB: db, WAYBI_AMAP_DAILY_BUDGET: '{"regeo":0}' }, 'regeo', null, now), 'exhausted');
  const { value: invalid } = await captureWarnings(async () => amapDailyLimit({ WAYBI_AMAP_DAILY_BUDGET: 'not json' }, 'place_text'));
  assert.equal(invalid, 30, 'invalid JSON keeps the safe defaults');
});

test('an exhausted Amap search budget answers from the OSM stack without calling Amap', async () => {
  const { db } = migratedD1();
  const calls: URL[] = [];
  const env = { AMAP_WEB_KEY: KEY, USER_DB: db,
    WAYBI_AMAP_DAILY_BUDGET: JSON.stringify({ inputtips: 0, place_around: 0, place_text: 0 }) };
  const { value } = await captureWarnings(() => withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
  }, calls) as typeof fetch, () => searchMainlandChina({
    query: '盛世春天', point: SHIJIAZHUANG, env,
    osmFallback: async () => [{ id: 'w:2', provider: 'osm', name: '盛世春天', address: '漯河市', isPoi: true,
      latitude: LUOHE_COMPOUND[1], longitude: LUOHE_COMPOUND[0] }],
  })));
  assert.deepEqual(calls.map(url => url.pathname), ['/v3/geocode/regeo']);
  assert.equal(value.usedOsmFallback, true);
  assert.equal(value.results[0].provider, 'osm');
  assert.ok(value.results[0].distanceMeters > 490_000, 'distance is always reported so the app can warn');
});

test('OSM fallback results that duplicate an Amap place are dropped', () => {
  const amap = mapAmapPois(fixture('place_around_kfc'));
  const kfc = amap[0];
  assert.equal(duplicatesPrimary({ name: '肯德基', latitude: kfc.latitude + 0.0005, longitude: kfc.longitude }, amap), true);
  assert.equal(duplicatesPrimary({ name: 'Other', latitude: kfc.latitude + 0.0001, longitude: kfc.longitude }, amap), true);
  assert.equal(duplicatesPrimary({ name: '肯德基', latitude: kfc.latitude + 0.05, longitude: kfc.longitude }, amap), false);
  assert.equal(amapAddress('北京市', '北京市', '朝阳区', '朝阳区建国路'), '北京市朝阳区建国路');
  assert.equal(amapAddress([], '河北省石家庄市长安区', ''), '河北省石家庄市长安区');
});

test('Hong Kong, Macau and Taiwan keep the existing search stack', () => {
  const env = { AMAP_WEB_KEY: KEY };
  assert.equal(amapSearchApplies(env, SHIJIAZHUANG), true);
  assert.equal(amapSearchApplies({}, SHIJIAZHUANG), false, 'no key, no Amap');
  for (const point of [[114.1589, 22.284], [113.5439, 22.1987], [121.56, 25.03], [118.3171, 24.4321]] as [number, number][]) {
    assert.equal(amapSearchApplies(env, point), false, String(point));
  }
  assert.equal(amapSearchApplies(env, null), false);
});

test('worker /api/suggest in Shijiazhuang serves Amap; in Hong Kong it never calls Amap', async () => {
  const calls: URL[] = [];
  await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v3/assistant/inputtips': () => fixture('inputtips_shengshichuntian'),
    'photon.komoot.io': () => ({ features: [{ properties: { name: 'Mong Kok', osm_key: 'place', osm_value: 'suburb', osm_id: 7 },
      geometry: { coordinates: [114.1694, 22.3193] } }] }),
  }, calls) as typeof fetch, async () => {
    const usage: string[] = [];
    const china = await worker.fetch(new Request(
      'https://waybi.test/api/suggest?q=%E7%9B%9B%E4%B8%96%E6%98%A5%E5%A4%A9&near=114.51,38.04&provider=independent&lang=zh'),
      { AMAP_WEB_KEY: KEY }, { waitUntil(promise) { usage.push('usage'); return promise; } });
    assert.equal(china.status, 200);
    const body = await china.json();
    assert.equal(body[0].provider, 'amap');
    assert.ok(body[0].distanceMeters < 5000);
    assert.equal(calls.some(url => url.hostname === 'photon.komoot.io'), false);

    calls.length = 0;
    const hongKong = await worker.fetch(new Request(
      'https://waybi.test/api/suggest?q=Mong%20Kok&near=114.17,22.31&provider=independent&lang=en'),
      { AMAP_WEB_KEY: KEY }, { waitUntil() {} });
    assert.equal(hongKong.status, 200);
    assert.equal(calls.some(url => url.hostname === 'restapi.amap.com'), false);
  });
});

test('worker /api/search in mainland China runs a full Amap search', async () => {
  const calls: URL[] = [];
  await withFetch(amapFetch({
    '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang'),
    '/v5/place/around': () => fixture('place_around_kfc'),
    '/v5/place/text': () => fixture('place_around_kfc'),
  }, calls) as typeof fetch, async () => {
    const response = await worker.fetch(new Request('https://waybi.test/api/search?q=KFC%20test&near=114.51,38.04'),
      { AMAP_WEB_KEY: KEY }, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.equal((await response.json())[0].provider, 'amap');
    assert.equal(calls.some(url => url.hostname === 'nominatim.openstreetmap.org'), false);
  });
});

test('reverse geocoding in mainland China labels the place with Amap', async () => {
  const calls: URL[] = [];
  await withFetch(amapFetch({ '/v3/geocode/regeo': () => fixture('regeo_shijiazhuang') }, calls) as typeof fetch, async () => {
    const response = await worker.fetch(new Request('https://waybi.test/api/reverse?at=114.5163,38.0409&lang=zh'),
      { AMAP_WEB_KEY: KEY }, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      label: '石家庄市长安区建设北大街56号', countryCode: 'CN', provider: 'amap', attribution: '高德地图 / AutoNavi',
    });
    const regeo = calls.find(url => url.pathname === '/v3/geocode/regeo');
    assert.notEqual(regeo.searchParams.get('location'), '114.5163,38.0409', 'sent as GCJ-02');
    const english = await amapReverse({ AMAP_WEB_KEY: KEY }, [114.5163, 38.0409], 'en');
    assert.equal(english.label, '建设北大街56号, 长安区, 石家庄市');
  });
});

test('reverse geocoding falls back to OSM when Amap fails', async () => {
  const calls: URL[] = [];
  await captureWarnings(() => withFetch(amapFetch({
    '/v3/geocode/regeo': () => ({ status: '0', info: 'SERVICE_NOT_AVAILABLE', infocode: '10002' }),
    'nominatim.openstreetmap.org': () => ({ display_name: 'Chang\'an, Shijiazhuang', address: { road: 'Jianshe North Street', city: 'Shijiazhuang', country_code: 'cn' } }),
  }, calls) as typeof fetch, async () => {
    const response = await worker.fetch(new Request('https://waybi.test/api/reverse?at=114.52,38.05&lang=en'),
      { AMAP_WEB_KEY: KEY }, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).countryCode, 'CN');
    assert.ok(calls.some(url => url.hostname === 'nominatim.openstreetmap.org'));
  }));
});

test('every Amap-backed endpoint is behind the existing per-client rate limiter', () => {
  for (const path of ['/api/suggest', '/api/search', '/api/reverse']) {
    assert.equal(rateLimitRule(path, 'GET')?.binding, 'RATE_LIMIT_SEARCH');
  }
  for (const path of ['/api/route-options', '/api/route']) {
    assert.equal(rateLimitRule(path, 'GET')?.binding, 'RATE_LIMIT_ROUTING');
  }
});
