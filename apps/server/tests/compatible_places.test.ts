import test from 'node:test';
import assert from 'node:assert/strict';
import { handlePlaces } from '../src/places.ts';

test('reverse geocoding accepts overseas locations without NZ restriction', async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async () => Response.json({address: {country_code:'jp',
    road:'Shinjuku Street',city:'Tokyo'},display_name:'Tokyo, Japan'});
  try {
    const result = await handlePlaces(new Request('https://example.test/api/reverse?at=139.7,35.69'), {});
    assert.equal(result.status,200);
    const data = await result.json();
    assert.match(data.label,/Tokyo/);
    assert.equal(data.countryCode,'JP');
  } finally {globalThis.fetch=previous;}
});

test('Mapbox-compatible suggestions bypass configured Google Places', async () => {
  const previous = globalThis.fetch;
  const urls = [];
  globalThis.fetch = async (url) => {
    urls.push(String(url));
    return Response.json({results: [{
      place_id: 'nz-place', name: 'Cafe', country_code: 'nz',
      address_line1: 'Queen Street', formatted: 'Cafe, Queen Street',
      lat: -36.85, lon: 174.76,
    }]});
  };
  try {
    const response = await handlePlaces(new Request(
      'https://example.test/api/suggest?q=Cafe&provider=geoapify'),
      { GOOGLE_ROUTES_API_KEY: 'google-key', GEOAPIFY_API_KEY: 'geo-key' });
    assert.equal(response.status, 200);
    assert.equal((await response.json())[0].provider, 'geoapify');
    assert.equal(new URL(urls[0]).hostname, 'api.geoapify.com');
  } finally { globalThis.fetch = previous; }
});

test('independent Explore requests NZ categories and retains honest metadata', async () => {
  const previous = globalThis.fetch;
  let requestUrl;
  globalThis.fetch = async (url) => {
    requestUrl = new URL(url);
    return Response.json({features: [{
      properties: { place_id: 'cafe', name: 'Cafe', lat: -36.85, lon: 174.76,
        categories: ['catering.cafe'], formatted: 'Cafe, Auckland' },
    }]});
  };
  try {
    const response = await handlePlaces(new Request(
      'https://example.test/api/explore?at=174.76,-36.85&category=coffee&provider=geoapify'),
      { GOOGLE_ROUTES_API_KEY: 'google-key', GEOAPIFY_API_KEY: 'geo-key' });
    const places = await response.json();
    assert.equal(response.status, 200);
    assert.equal(requestUrl.pathname, '/v2/places');
    assert.equal(requestUrl.searchParams.get('categories'), 'catering.cafe');
    assert.equal(requestUrl.searchParams.get('filter'), 'circle:174.76,-36.85,12000');
    assert.equal(places[0].provider, 'geoapify');
    assert.equal(places[0].rating, null);
    assert.equal(places[0].photoName, '');
  } finally { globalThis.fetch = previous; }
});

test('independent search never falls back to Google when unconfigured', async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async () => { throw Error('No upstream call expected'); };
  try {
    const env = { GOOGLE_ROUTES_API_KEY: 'google-key' };
    const suggest = await handlePlaces(new Request(
      'https://example.test/api/suggest?q=Cafe&provider=geoapify'), env);
    const explore = await handlePlaces(new Request(
      'https://example.test/api/explore?at=174.76,-36.85&provider=geoapify'), env);
    assert.equal(suggest.status, 503);
    assert.equal(explore.status, 503);
  } finally { globalThis.fetch = previous; }
});

test('independent Explore handles upstream failure and invalid coordinates', async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async () => { throw Error('timeout'); };
  try {
    const env = { GEOAPIFY_API_KEY: 'geo-key' };
    const invalid = await handlePlaces(new Request(
      'https://example.test/api/explore?at=181,91&provider=geoapify'), env);
    assert.equal(invalid.status, 400);
    const response = await handlePlaces(new Request(
      'https://example.test/api/explore?at=174.76,-36.85&provider=geoapify'), env);
    assert.equal(response.status, 502);
  } finally { globalThis.fetch = previous; }
});


test('independent search keeps proximity bias without country locking', async () => {
  const previous = globalThis.fetch;
  const urls = [];
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    urls.push(parsed);
    if (urls.length === 1) return Response.json({ results: [] });
    return Response.json({ results: [{
      place_id: 'shijiazhuang',
      name: '石家庄市',
      country_code: 'cn',
      formatted: '石家庄市, 河北省, 中国',
      result_type: 'city',
      lat: 38.0428,
      lon: 114.5149,
    }]});
  };
  try {
    const response = await handlePlaces(new Request(
      'https://example.test/api/suggest?q=%E7%9F%B3%E5%AE%B6%E5%BA%84&lang=zh&provider=geoapify&near=174.76,-36.85'),
      { GEOAPIFY_API_KEY: 'geo-key' });
    assert.equal(response.status, 200);
    const [place] = await response.json();
    assert.equal(place.name, '石家庄市, 河北省, 中国');
    assert.equal(place.latitude, 38.0428);
    assert.equal(urls.length, 2);
    assert.equal(urls[0].searchParams.get('filter'), null);
    assert.equal(urls[0].searchParams.get('bias'), 'proximity:174.76,-36.85');
    assert.equal(urls[1].searchParams.get('filter'), null);
    assert.equal(urls[1].searchParams.get('bias'), null);
  } finally { globalThis.fetch = previous; }
});

test('Independent global search uses Geoapify and never crosses into Google', async () => {
  const previous = globalThis.fetch;
  const hosts = [];
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    hosts.push(parsed.hostname);
    assert.equal(parsed.hostname, 'api.geoapify.com');
    return Response.json({ results: [{
      place_id: 'tokyo-station',
      name: 'Tokyo Station',
      formatted: 'Tokyo Station, Marunouchi, Chiyoda, Tokyo, Japan',
      address_line1: 'Tokyo Station',
      address_line2: 'Marunouchi, Chiyoda, Tokyo, Japan',
      categories: ['public_transport.train'],
      result_type: 'amenity',
      lat: 35.681236,
      lon: 139.767125,
    }] });
  };
  try {
    const response = await handlePlaces(new Request(
      'https://example.test/api/suggest?q=Tokyo%20Station&provider=independent&near=139.76,35.68'),
      {
        GOOGLE_ROUTES_API_KEY: 'google-key-that-must-not-be-used',
        GEOAPIFY_API_KEY: 'geo-key',
      });
    assert.equal(response.status, 200);
    const [place] = await response.json();
    assert.equal(place.provider, 'geoapify');
    assert.equal(place.name, 'Tokyo Station');
    assert.deepEqual(hosts, ['api.geoapify.com']);
  } finally { globalThis.fetch = previous; }
});

test('Independent global search falls back to Photon without Google', async () => {
  const previous = globalThis.fetch;
  const hosts = [];
  globalThis.fetch = async (url) => {
    const parsed = new URL(url);
    hosts.push(parsed.hostname);
    if (parsed.hostname === 'api.geoapify.com') {
      return new Response('upstream unavailable', { status: 503 });
    }
    assert.equal(parsed.hostname, 'photon.komoot.io');
    return Response.json({ features: [{
      properties: {
        osm_type: 'N',
        osm_id: 123,
        name: 'Sydney Opera House',
        osm_key: 'tourism',
        osm_value: 'attraction',
        city: 'Sydney',
        state: 'New South Wales',
        country: 'Australia',
      },
      geometry: { coordinates: [151.2153, -33.8568] },
    }] });
  };
  try {
    const response = await handlePlaces(new Request(
      'https://example.test/api/suggest?q=Sydney%20Opera%20House&provider=independent&near=151.20,-33.86'),
      {
        GOOGLE_ROUTES_API_KEY: 'google-key-that-must-not-be-used',
        GEOAPIFY_API_KEY: 'geo-key',
      });
    assert.equal(response.status, 200);
    const [place] = await response.json();
    assert.equal(place.provider, 'osm');
    assert.equal(place.name, 'Sydney Opera House');
    assert.deepEqual(hosts, ['api.geoapify.com', 'photon.komoot.io']);
  } finally { globalThis.fetch = previous; }
});
