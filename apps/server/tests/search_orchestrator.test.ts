import test from 'node:test';
import assert from 'node:assert/strict';
import { dedupeSearchResults, mergeAndRankSearchResults, needsAddressEnrichment, interpolateNumberedAddress } from '../src/search/search_orchestrator.ts';

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

test('interpolates a missing exact house number from bracketing same-street addresses', async () => {
  const { mergeAndRankSearchResults } = await import('../src/search/search_orchestrator.ts');
  const results = mergeAndRankSearchResults([[
    {
      id: '34', provider: 'regional:test', name: '34 Verissimo Drive',
      address: '34 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      label: '34 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      isPoi: false, latitude: -36.9882, longitude: 174.7887,
    },
    {
      id: '46', provider: 'regional:test', name: '46 Verissimo Drive',
      address: '46 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      label: '46 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      isPoi: false, latitude: -36.9909, longitude: 174.7897,
    },
  ]], '42 Verissimo Drive', [174.79, -36.98], 12);

  assert.equal(results[0].name, '42 Verissimo Drive');
  assert.equal(results[0].provider, 'derived:address-interpolation');
  assert.equal(results[0].interpolated, true);
  assert.match(results[0].address, /Mangere, Auckland 2022, New Zealand/);
});

test('partial numbered street interpolation uses the canonical candidate street name', async () => {
  const { mergeAndRankSearchResults } = await import('../src/search/search_orchestrator.ts');
  const results = mergeAndRankSearchResults([[
    {
      id: '34', provider: 'regional:test', name: '34 Verissimo Drive',
      address: '34 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      label: '34 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      isPoi: false, latitude: -36.9882, longitude: 174.7887,
    },
    {
      id: '46', provider: 'regional:test', name: '46 Verissimo Drive',
      address: '46 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      label: '46 Verissimo Drive, Mangere, Auckland 2022, New Zealand',
      isPoi: false, latitude: -36.9909, longitude: 174.7897,
    },
  ]], '42 veri', [174.79, -36.98], 12);

  assert.equal(results[0].name, '42 Verissimo Drive');
});

test('a real exact address replaces an earlier derived result regardless of provider ordering', () => {
  const common = { name: '42 Example Drive', address: '42 Example Drive, Example City', latitude: -36.9, longitude: 174.8 };
  const derived = { ...common, id: 'derived', provider: 'derived:address-interpolation', interpolated: true };
  const exact = { ...common, id: 'official', provider: 'regional:official', latitude: -36.9001 };
  const results = mergeAndRankSearchResults([[derived], [exact]], '42 Example Drive', [174.8, -36.9]);
  assert.equal(results.length, 1);
  assert.equal(results[0].id, 'official');
  assert.equal(needsAddressEnrichment([derived], '42 Example Drive'), true);
});

test('does not combine same-named roads in different towns or interpolate from an earlier estimate', () => {
  const lower = { name: '34 Example Drive', latitude: -36.9, longitude: 174.8 };
  const upper = { name: '46 Example Drive', latitude: -38, longitude: 175.8 };
  assert.equal(interpolateNumberedAddress([lower, upper], '42 Example Drive'), null);
  assert.equal(interpolateNumberedAddress([lower, { ...upper, latitude: -36.9001, longitude: 174.8001, interpolated: true }], '42 Example Drive'), null);
});
