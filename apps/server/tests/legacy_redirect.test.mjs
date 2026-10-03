import test from 'node:test';
import assert from 'node:assert/strict';
import legacyWorker from '../src/legacy_redirect.mjs';

test('legacy public URLs permanently redirect to the matching Waybi URL', async () => {
  const response = await legacyWorker.fetch(
    new Request('https://kiwi-lens.nzs.workers.dev/safety-camera-navigation/?from=legacy')
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get('location'),
    'https://waybi.nzs.workers.dev/safety-camera-navigation/?from=legacy'
  );
});
