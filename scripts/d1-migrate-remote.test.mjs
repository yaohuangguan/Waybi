import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const temp = mkdtempSync(path.join(tmpdir(), 'waybi-migration-test-'));
const migration = fileURLToPath(new URL('./d1-migrate-remote.mjs', import.meta.url));
const fakeSource = `console.log(JSON.stringify({
  args: process.argv.slice(2),
  token: process.env.CLOUDFLARE_API_TOKEN ?? null,
  hasD1Token: Object.hasOwn(process.env, 'CLOUDFLARE_D1_API_TOKEN')
})); process.exit(Number(process.env.WAYBI_TEST_EXIT ?? 0));`;
writeFileSync(path.join(temp, 'fake-pnpm.mjs'), fakeSource);
if (process.platform === 'win32') {
  writeFileSync(path.join(temp, 'pnpm.cmd'),
    `@"${process.execPath}" "%~dp0fake-pnpm.mjs" %*\r\n`);
} else {
  writeFileSync(path.join(temp, 'pnpm'), '#!/usr/bin/env node\n' + fakeSource, { mode: 0o755 });
}
after(() => {
  if (path.dirname(temp) !== tmpdir() || !path.basename(temp).startsWith('waybi-migration-test-')) {
    throw new Error('Unexpected test directory');
  }
  rmSync(temp, { recursive: true });
});

function invoke(overrides = {}) {
  const env = { ...process.env };
  // Preserve the environment's existing Path spelling on Windows.
  const pathKey = Object.keys(env).find(k => k.toUpperCase() === 'PATH') ?? 'PATH';
  env[pathKey] = temp + path.delimiter + (env[pathKey] ?? '');
  delete env.CLOUDFLARE_API_TOKEN;
  delete env.CLOUDFLARE_D1_API_TOKEN;
  Object.assign(env, overrides);
  return spawnSync(process.execPath, [migration], { env, encoding: 'utf8' });
}

test('D1 credential is scoped to the migration child and not exposed as a second credential', () => {
  const result = invoke({
    CLOUDFLARE_API_TOKEN: 'fake-worker-token',
    CLOUDFLARE_D1_API_TOKEN: 'fake-d1-token',
  });
  assert.equal(result.status, 0, result.stderr);
  const child = JSON.parse(result.stdout);
  assert.equal(child.token, 'fake-d1-token');
  assert.equal(child.hasD1Token, false);
  assert.deepEqual(child.args, [
    'exec', 'wrangler', 'd1', 'migrations', 'apply', 'waybi-users',
    '--remote', '--config', 'wrangler.jsonc',
  ]);
});

test('existing single-token deployments retain their configured credential', () => {
  const result = invoke({ CLOUDFLARE_API_TOKEN: 'fake-worker-token' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).token, 'fake-worker-token');
});

test('an unset or blank separate token preserves local OAuth', () => {
  for (const overrides of [{}, { CLOUDFLARE_D1_API_TOKEN: '  ' }]) {
    const result = invoke(overrides);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).token, null);
  }
});

test('failed migrations propagate failure so the deployment chain cannot continue', () => {
  const result = invoke({ WAYBI_TEST_EXIT: '23' });
  assert.equal(result.status, 23);
});
