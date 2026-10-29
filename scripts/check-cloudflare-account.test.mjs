import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkCloudflareAccount } from './check-cloudflare-account.mjs';

const config = { account_id: 'target-account', d1_databases: [{ binding: 'USER_DB', database_id: 'target-db' }] };
const env = { CLOUDFLARE_API_TOKEN: 'worker-test-token', CLOUDFLARE_D1_API_TOKEN: 'database-test-token' };

test('checks both publishing and D1 credentials against the configured destination', async () => {
  const observed = [];
  await checkCloudflareAccount(config, env, async (url, options) => {
    observed.push([url, options.headers.Authorization]);
    return Response.json({ success: true, result: url.endsWith('/target-account') ? { id: 'target-account' } : { uuid: 'target-db' } });
  });
  assert.deepEqual(observed, [
    ['https://api.cloudflare.com/client/v4/accounts/target-account', 'Bearer worker-test-token'],
    ['https://api.cloudflare.com/client/v4/accounts/target-account/d1/database/target-db', 'Bearer database-test-token'],
  ]);
});

test('stops on an old-account credential before attempting a database operation', async () => {
  let calls = 0;
  await assert.rejects(checkCloudflareAccount(config, env, async () => {
    calls++;
    return Response.json({ success: false }, { status: 403 });
  }), /configured Cloudflare account/);
  assert.equal(calls, 1);
});

test('rejects a mismatched database and a non-JSON API failure', async () => {
  for (const response of [Response.json({ success: true, result: { uuid: 'old-db' } }), new Response('<html>Unavailable</html>', { status: 503 })]) {
    await assert.rejects(checkCloudflareAccount(config, env, async url => url.endsWith('/target-account')
      ? Response.json({ success: true, result: { id: 'target-account' } }) : response), /configured Cloudflare database/);
  }
});

test('missing publishing authorization fails without a network request', async () => {
  await assert.rejects(checkCloudflareAccount(config, {}, () => { throw Error('Unexpected network call'); }), /Missing Cloudflare/);
});
