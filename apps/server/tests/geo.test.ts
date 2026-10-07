import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLonLat, parseNzLonLat, validCoordinate } from '../src/geo.ts';

test('global coordinates accept valid world locations', () => {
  assert.deepEqual(parseLonLat('-74.006,40.7128'), [-74.006, 40.7128]);
  assert.deepEqual(parseLonLat('139.6917,35.6895'), [139.6917, 35.6895]);
  assert.equal(validCoordinate(-36.85, 174.76), true);
});

test('invalid world coordinates are rejected while NZ parsing stays explicit', () => {
  assert.equal(parseLonLat('181,0'), null);
  assert.equal(parseLonLat('0,91'), null);
  assert.deepEqual(parseNzLonLat('174.76,-36.85'), [174.76, -36.85]);
  assert.equal(parseNzLonLat('-74.006,40.7128'), null);
});
