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
    'https://waybi.co/safety-camera-navigation/?from=legacy'
  );
});

test('legacy API requests proxy through the Waybi service binding', async () => {
  let forwarded;
  const env = {
    WAYBI: {
      async fetch(request) {
        forwarded = request;
        return new Response('ok', { status: 200 });
      }
    }
  };
  const response = await legacyWorker.fetch(
    new Request('https://kiwi-lens.nzs.workers.dev/api/health?legacy=1'),
    env
  );

  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'ok');
  assert.equal(forwarded.url, 'https://waybi.co/api/health?legacy=1');
});
