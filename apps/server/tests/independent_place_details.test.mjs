import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { independentPlaceDetails } from '../src/independent_place_details.mjs';
globalThis.crypto ??= webcrypto;

const input = () => new URL('https://waybi.test/api/independent-place-details?at=174.7622,-36.8485&name=Sky%20Tower&type=attraction&address=Victoria%20Street%20West%2C%20Auckland');
const result = body => new Response(JSON.stringify(body));
const wiki = title => ({ query: { pages: [{ title, pageimage: 'Sky Tower.jpg',
  coordinates: [{ primary: true, lat: -36.8485, lon: 174.7622 }], pageprops: {} }] } });
const commons = license => ({ query: { pages: [{ title: 'File:Sky Tower.jpg', imageinfo: [{
  thumburl: 'https://upload.wikimedia.org/example.jpg', descriptionurl: 'https://commons.wikimedia.org/wiki/File:Sky_Tower.jpg',
  extmetadata: { Artist: { value: 'Example photographer' }, LicenseShortName: { value: license },
    LicenseUrl: { value: 'https://creativecommons.org/licenses/by-sa/4.0/' } },
}] }] } });

test('exact place photo preserves licence, type and address; cache contains only photos', async () => {
  const cache = new Map(); let calls = 0;
  const env = { CAMERA_DATA: { get: async key => cache.has(key) ? JSON.parse(cache.get(key)) : null,
    put: async (key, value) => cache.set(key, value) } };
  const fetcher = async url => { calls++; return result(url.hostname === 'en.wikipedia.org' ? wiki('Sky Tower') : commons('CC BY-SA 4.0')); };
  const first = await (await independentPlaceDetails(input(), env, fetcher)).json();
  assert.equal(first.primaryType, 'attraction');
  assert.equal(first.address, 'Victoria Street West, Auckland');
  assert.equal(first.photos.length, 1);
  assert.match(first.photos[0].attribution, /Example photographer · CC BY-SA 4.0/);
  assert.match(first.photos[0].sourceUrl, /^https:\/\/commons.wikimedia.org\//);
  const secondInput = input(); secondInput.searchParams.set('address', 'Updated full address');
  const second = await (await independentPlaceDetails(secondInput, env, fetcher)).json();
  assert.equal(second.address, 'Updated full address');
  assert.equal(calls, 2);
});

test('nearby landmark photos are never attached to a different selected place', async () => {
  const data = await (await independentPlaceDetails(input(), {}, async () => result(wiki('Different landmark')))).json();
  assert.deepEqual(data.photos, []);
});

test('non-free media and failed upstreams leave a usable place card', async () => {
  const denied = await (await independentPlaceDetails(input(), {}, async url => result(url.hostname === 'en.wikipedia.org' ? wiki('Sky Tower') : commons('All rights reserved')))).json();
  assert.deepEqual(denied.photos, []);
  const offline = await (await independentPlaceDetails(input(), {}, async () => { throw Error('offline'); })).json();
  assert.equal(offline.name, 'Sky Tower');
  assert.deepEqual(offline.photos, []);
});

test('invalid coordinates never reach a photo provider', async () => {
  const url = input(); url.searchParams.set('at', '0,0');
  const response = await independentPlaceDetails(url, {}, () => { throw Error('must not fetch'); });
  assert.equal(response.status, 400);
});

test('selected OSM object media is used only with matching identity and coordinates', async () => {
  const url = input(); url.searchParams.set('id', 'N:555');
  let latitude = -36.8485;
  const fetcher = async endpoint => {
    if (endpoint.hostname === 'www.openstreetmap.org') return result({ elements: [{
      type: 'node', id: 555, lat: latitude, lon: 174.7622,
      tags: { name: 'Sky Tower', wikimedia_commons: 'File:Sky Tower.jpg' },
    }] });
    if (endpoint.hostname === 'en.wikipedia.org') return result({ query: { pages: [] } });
    return result(commons('CC BY-SA 4.0'));
  };
  const matched = await (await independentPlaceDetails(url, {}, fetcher)).json();
  assert.equal(matched.photos.length, 1);
  latitude = -41.28;
  const unrelated = await (await independentPlaceDetails(url, {}, fetcher)).json();
  assert.deepEqual(unrelated.photos, []);
});
