import test from 'node:test';
import assert from 'node:assert/strict';
import { parseNumberedStreetQuery, parseStreetQuery } from '../src/search/numbered_street_query.mjs';
import { searchRegionalAddressEnrichments } from '../src/search/regional_address_registry.mjs';

test('numbered street parsing is global and region-agnostic', () => {
  assert.deepEqual(parseNumberedStreetQuery('42 Verissimo Drive'), {
    number: '42', roadName: 'Verissimo', roadType: 'DRIVE'
  });
  assert.deepEqual(parseNumberedStreetQuery('221B Baker Street, London'), {
    number: '221B', roadName: 'Baker', roadType: 'STREET'
  });
  assert.equal(parseNumberedStreetQuery('Tokyo Station'), null);
  assert.deepEqual(parseStreetQuery('Verissimo Drive'), {
    number: null, roadName: 'Verissimo', roadType: 'DRIVE'
  });
  assert.equal(parseStreetQuery('Tokyo Station'), null);
});

test('regional enrichment never runs outside an adapter service area', async () => {
  let calls = 0;
  const results = await searchRegionalAddressEnrichments(
    '42 Verissimo Drive',
    [139.767, 35.681],
    async () => { calls += 1; throw new Error('must not run'); }
  );
  assert.deepEqual(results, []);
  assert.equal(calls, 0);
});
