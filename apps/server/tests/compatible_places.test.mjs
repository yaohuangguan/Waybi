import test from 'node:test';
import assert from 'node:assert/strict';
import { handlePlaces } from '../src/places.mjs';

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
      'https://example.test/api/explore?at=1,2&provider=geoapify'), env);
    assert.equal(invalid.status, 400);
    const response = await handlePlaces(new Request(
      'https://example.test/api/explore?at=174.76,-36.85&provider=geoapify'), env);
    assert.equal(response.status, 502);
  } finally { globalThis.fetch = previous; }
});
