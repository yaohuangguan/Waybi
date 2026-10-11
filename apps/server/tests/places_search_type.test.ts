import test from 'node:test';
import assert from 'node:assert/strict';
import { googlePlaceIsPoi } from '../src/places.ts';

test('Google address types are not presented as POIs', () => {
  assert.equal(googlePlaceIsPoi({ types: ['street_address'], formattedAddress: '42 Verissimo Drive, Auckland' }, '42 Verissimo Drive'), false);
  assert.equal(googlePlaceIsPoi({ types: ['premise'], formattedAddress: '42 Verissimo Drive, Auckland' }, '42 Verissimo Drive'), false);
});

test('named destinations remain POIs', () => {
  assert.equal(googlePlaceIsPoi({ types: ['airport'], formattedAddress: 'Ray Emery Drive, Auckland' }, 'Auckland Airport'), true);
});

test('Google geographic types remain geographic independent of display language', () => {
  assert.equal(googlePlaceIsPoi({ types: ['locality', 'political'] }), false);
  assert.equal(googlePlaceIsPoi({ types: ['administrative_area_level_1', 'political'] }), false);
});
