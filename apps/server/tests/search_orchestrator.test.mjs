import test from 'node:test';
import assert from 'node:assert/strict';
import { dedupeSearchResults, mergeAndRankSearchResults, needsAddressEnrichment } from '../src/search/search_orchestrator.mjs';

test('search orchestration merges global and regional results without city-specific branching', () => {
  const global = {
    id: 'g1', provider: 'google', name: '42 Example Street',
    address: '42 Example Street, Sample City', latitude: 1, longitude: 2
  };
  const duplicateRegional = {
    id: 'r1', provider: 'regional:sample-official', name: '42 Example Street',
    address: '42 Example Street, Sample City', latitude: 1, longitude: 2
  };
  const other = {
    id: 'g2', provider: 'google', name: 'Example Street',
    address: 'Example Street, Sample City', latitude: 1.001, longitude: 2
  };
  assert.equal(dedupeSearchResults([duplicateRegional, global, other]).length, 2);
  const ranked = mergeAndRankSearchResults(
    [[duplicateRegional], [global, other]], '42 Example Street', [2, 1], 12
  );
  assert.equal(ranked.length, 2);
  assert.match(ranked[0].address, /^42 Example Street/);
});


test('regional address enrichment is skipped when global search already has an exact house/street match', () => {
  assert.equal(needsAddressEnrichment([
    { name: '42 Verissimo Drive', address: '42 Verissimo Drive, Māngere, Auckland 2022' }
  ], '42 Verissimo Drive'), false);
  assert.equal(needsAddressEnrichment([
    { name: 'Verissimo Drive', address: 'Māngere, Auckland' }
  ], '42 Verissimo Drive'), true);
  assert.equal(needsAddressEnrichment([], 'Auckland Airport'), false);
});


test('interpolated address remains enrichment-needed when exact global lookup may exist', () => {
  assert.equal(needsAddressEnrichment([
    {
      name: '42 Verissimo Drive',
      address: '42 Verissimo Drive, Māngere, Auckland 2022',
      approximate: true,
    }
  ], '42 Verissimo Drive'), true);
});
