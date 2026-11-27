import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { parseStops } from '../src/worker.ts';
import { handlePlaces, placePhotoUrl } from '../src/places.ts';
import { guardApiRequest, rateLimitRule } from '../src/abuse_guard.ts';
import { googleDailyLimit, reserveGoogleUnits } from '../src/google_budget.ts';
import { reserveNzRoutingQuota, nzRoutingClientShare } from '../src/nz_routing_quota.ts';
import { scheduleNominatim, __test as nominatim } from '../src/nominatim.ts';
import { classifyError, HttpError, UpstreamError } from '../src/http_errors.ts';
import { migratedD1 } from './d1_fixture.ts';

const ctx = { waitUntil() {} };

test('place photo names accept only the exact places/{id}/photos/{id} resource', () => {
  const url = placePhotoUrl('places/ChIJabc-123_x/photos/AeY_photo-9', 'server-key')!;
  assert.equal(url.origin + url.pathname, 'https://places.googleapis.com/v1/places/ChIJabc-123_x/photos/AeY_photo-9/media');
  assert.deepEqual([...url.searchParams.keys()].sort(), ['key', 'maxWidthPx']);
  for (const name of [
    'places/X?fields=*&x=/photos/y',
    'places/X/photos/y?key=other',
    'places/../photos/y',
    'places/X/photos/y/../../places:searchText',
    'places/X%2F/photos/y',
    'places/X/photos/y#frag',
    'places/X/photos/',
    'places/X/photos/y&maxHeightPx=1',
  ]) assert.equal(placePhotoUrl(name, 'server-key'), null, name);
});

test('the place-photo endpoint rejects injected names before attaching the server key', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => assert.fail('no Google request for an invalid photo name');
  try {
    const response = await handlePlaces(new Request('https://waybi.test/api/place-photo?name=' +
      encodeURIComponent('places/X?fields=*&x=/photos/y')), { GOOGLE_PLACES_SERVER_API_KEY: 'server-key' });
    assert.equal(response!.status, 400);
  } finally { globalThis.fetch = originalFetch; }
});

test('paid and shared-quota endpoints are rate limited per client IP with a JSON 429', async () => {
  const keys: string[] = [];
  let allow = true;
  const limiter = { async limit({ key }) { keys.push(key); return { success: allow }; } };
  const env = { RATE_LIMIT_SEARCH: limiter, RATE_LIMIT_PLACES: limiter, RATE_LIMIT_ROUTING: limiter,
    RATE_LIMIT_SPEED_LIMIT: limiter, RATE_LIMIT_AUTH: limiter, RATE_LIMIT_FEEDBACK: limiter };
  const headers = { 'cf-connecting-ip': '203.0.113.9' };
  for (const [path, method] of [
    ['/api/suggest?q=ab', 'GET'], ['/api/search?q=ab', 'GET'], ['/api/explore?at=1,1', 'GET'],
    ['/api/place-details?placeId=abcdefgh', 'GET'], ['/api/place-photo?name=x', 'GET'],
    ['/api/route-options?from=1,1&to=2,2', 'GET'], ['/api/route?from=1,1&to=2,2', 'GET'],
    ['/api/speed-limit?at=1,1', 'GET'], ['/api/navigation-feedback', 'POST'], ['/api/auth/login', 'POST'],
    ['/api/auth/register', 'POST'], ['/api/auth/email/request', 'POST'],
  ]) assert.ok(rateLimitRule(new URL('https://w.test' + path).pathname, method), path);
  assert.equal(rateLimitRule('/api/cameras', 'GET'), null);

  assert.equal(await guardApiRequest(new Request('https://w.test/api/suggest?q=ab', { headers }), env), null);
  assert.equal(keys.at(-1), 'search:203.0.113.9');
  allow = false;
  const limited = await worker.fetch(new Request('https://w.test/api/route-options?from=174.7,-36.8&to=174.8,-36.9', { headers }), env, ctx);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('retry-after'), '60');
  assert.deepEqual(await limited.json(), { error: 'Too many requests. Please retry shortly.', code: 'RATE_LIMITED', retryAfter: 60 });
  // A missing binding (tests, local dev) or a limiter outage never blocks requests.
  assert.equal(await guardApiRequest(new Request('https://w.test/api/suggest?q=ab'), {}), null);
  const broken = { RATE_LIMIT_SEARCH: { async limit() { throw new Error('limiter down'); } } };
  assert.equal(await guardApiRequest(new Request('https://w.test/api/suggest?q=ab'), broken), null);
});

test('Google daily budget is atomic, configurable and fails closed on a D1 error', async () => {
  const { sqlite, db } = migratedD1();
  try {
    const env = { USER_DB: db, WAYBI_GOOGLE_DAILY_BUDGET: '{"place_details":3}' };
    assert.equal(googleDailyLimit(env, 'place_details'), 3);
    assert.equal(googleDailyLimit({}, 'routes_compute'), 500);
    const now = new Date('2026-11-26T10:00:00Z');
    const results = await Promise.all(Array.from({ length: 6 }, () => reserveGoogleUnits(env, 'place_details', 1, now)));
    assert.equal(results.filter(Boolean).length, 3);
    assert.equal(await reserveGoogleUnits(env, 'place_details', 1, new Date('2026-11-27T00:00:01Z')), true, 'resets at UTC midnight');
    assert.equal(await reserveGoogleUnits({ USER_DB: db }, 'routes_compute', 501, now), false, 'units count, not calls');
    const failing = { USER_DB: { prepare() { throw new Error('D1 unavailable'); } } };
    assert.equal(await reserveGoogleUnits(failing, 'place_details'), false);
    const summary = sqlite.prepare("SELECT provider FROM api_usage_daily WHERE sku = 'google:place_details'").get() as any;
    assert.equal(summary.provider, '__waybi_quotas', 'budget rows stay out of Cost Guard spend reports');
  } finally { sqlite.close(); }
});

test('an exhausted Google budget falls back to independent providers or a 503, never a Google call', async () => {
  const { sqlite, db } = migratedD1();
  const originalFetch = globalThis.fetch;
  const hosts: string[] = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input instanceof Request ? input.url : input));
    hosts.push(url.hostname);
    if (url.hostname === 'photon.komoot.io') {
      return Response.json({ features: [{ properties: { name: 'Sky Tower', osm_key: 'tourism', osm_value: 'attraction',
        osm_type: 'N', osm_id: 1, city: 'Auckland', country: 'New Zealand', countrycode: 'NZ' },
      geometry: { coordinates: [174.7622, -36.8485] } }] });
    }
    if (url.hostname === 'routing.openstreetmap.de') {
      return Response.json({ code: 'Ok', routes: [{ distance: 1000, duration: 100,
        geometry: { coordinates: [[174.7, -36.8], [174.8, -36.9]] }, legs: [{ steps: [] }] }] });
    }
    return Response.json({ elements: [] });
  };
  try {
    const env = { USER_DB: db, GOOGLE_PLACES_SERVER_API_KEY: 'k', GOOGLE_ROUTES_API_KEY: 'k',
      WAYBI_GOOGLE_DAILY_BUDGET: JSON.stringify({ places_text_search: 0, places_nearby_search: 0,
        place_details: 0, place_photo: 0, routes_compute: 0 }) };
    const suggest = await handlePlaces(new Request('https://w.test/api/suggest?q=Sky%20Tower&near=174.76,-36.85'), env);
    assert.equal(suggest!.status, 200);
    assert.equal((await suggest!.json())[0].name, 'Sky Tower');
    for (const path of ['/api/place-details?placeId=ChIJabcdefgh', '/api/place-photo?name=places/abc/photos/def']) {
      const response = await handlePlaces(new Request('https://w.test' + path), env);
      assert.equal(response!.status, 503);
      assert.equal((await response!.json()).code, 'GOOGLE_BUDGET_EXHAUSTED');
      assert.ok(Number(response!.headers.get('retry-after')) > 0);
    }
    const route = await worker.fetch(new Request('https://w.test/api/route-options?from=174.7,-36.8&to=174.8,-36.9&mode=drive'), env, ctx);
    assert.equal(route.status, 200);
    assert.notEqual((await route.json()).provider, 'google');
    assert.ok(!hosts.some((host) => host.endsWith('googleapis.com')), hosts.join(','));
  } finally { globalThis.fetch = originalFetch; sqlite.close(); }
});

test('one client cannot drain the shared NZ routing daily quota', async () => {
  const { sqlite, db } = migratedD1();
  try {
    assert.equal(nzRoutingClientShare(3000), 300);
    assert.equal(nzRoutingClientShare(3000, '50'), 50);
    assert.equal(nzRoutingClientShare(100), 20);
    const now = new Date('2026-11-26T10:00:00Z');
    const greedy = await Promise.allSettled(Array.from({ length: 30 }, () =>
      reserveNzRoutingQuota(db, '100', now, { key: 'ip:greedy', limit: '10' })));
    assert.equal(greedy.filter((r) => r.status === 'fulfilled').length, 10);
    assert.match(String((greedy.find((r) => r.status === 'rejected') as PromiseRejectedResult).reason), /client share/);
    await reserveNzRoutingQuota(db, '100', now, { key: 'ip:other', limit: '10' });
    const global = sqlite.prepare("SELECT calls FROM api_usage_daily WHERE provider = 'waybi-valhalla'").get() as any;
    assert.equal(global.calls, 11, 'rejected client attempts do not consume the shared quota');
  } finally { sqlite.close(); }
});

test('malformed stops are rejected instead of silently dropped', async () => {
  assert.deepEqual(parseStops(null), []);
  assert.deepEqual(parseStops('174.7,-36.8;174.8,-36.9'), [[174.7, -36.8], [174.8, -36.9]]);
  for (const value of ['174.7,-36.8;bad', '174.7,-36.8;;174.8,-36.9', '999,0', ';']) assert.equal(parseStops(value), null, value);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => assert.fail('no routing call for invalid stops');
  try {
    for (const path of ['/api/route-options', '/api/route']) {
      const response = await worker.fetch(new Request(`https://w.test${path}?from=174.7,-36.8&to=174.9,-36.9&stops=174.8,-36.85;oops`), {}, ctx);
      assert.equal(response.status, 400, path);
    }
  } finally { globalThis.fetch = originalFetch; }
});

test('API errors get a request id and a generic body; client encoding errors are 400', async () => {
  assert.equal(classifyError(new URIError('URI malformed')).status, 400);
  assert.equal(classifyError(new UpstreamError('Nominatim HTTP 500')).status, 502);
  assert.equal(classifyError(new HttpError(503, 'Busy', { code: 'BUSY' })).message, 'Busy');
  const secret = classifyError(new Error('D1_ERROR: UNIQUE constraint failed: users.email'));
  assert.deepEqual([secret.status, secret.message], [500, 'Internal error']);

  const originalError = console.error;
  const logged: string[] = [];
  console.error = (line) => { logged.push(String(line)); };
  try {
    const env = { USER_DB: { prepare() { throw new Error('D1_ERROR: no such table: route_watches_secret'); } } };
    const response = await worker.fetch(new Request('https://w.test/api/route-watches', {
      headers: { cookie: `waybi_session=${'a'.repeat(64)}` } }), env, ctx);
    assert.equal(response.status, 500);
    const body = await response.json();
    assert.equal(body.error, 'Internal error');
    assert.match(body.requestId, /^[0-9a-f-]{36}$/);
    assert.equal(response.headers.get('x-request-id'), body.requestId);
    assert.ok(!JSON.stringify(body).includes('route_watches_secret'));
    const entry = JSON.parse(logged.at(-1)!);
    assert.equal(entry.requestId, body.requestId);
    assert.equal(entry.event, 'api_error');
    assert.match(entry.message, /route_watches_secret/);
  } finally { console.error = originalError; }
});

test('Nominatim calls are serialized at one per second per isolate and a deep queue is refused', async () => {
  nominatim.reset();
  const started: number[] = [];
  const tasks = Array.from({ length: 3 }, () => scheduleNominatim(async () => { started.push(Date.now()); return true; }));
  await Promise.all(tasks);
  for (let i = 1; i < started.length; i++) {
    assert.ok(started[i] - started[i - 1] >= nominatim.MIN_INTERVAL_MS - 5, `gap ${started[i] - started[i - 1]}ms`);
  }
  nominatim.reset(20);
  const flood = Array.from({ length: nominatim.MAX_QUEUED + 2 }, () => scheduleNominatim(async () => true));
  const settled = await Promise.allSettled(flood);
  const refused = settled.filter((r) => r.status === 'rejected') as PromiseRejectedResult[];
  assert.equal(refused.length, 2);
  assert.equal(refused[0].reason.status, 503);
  nominatim.reset();
});
