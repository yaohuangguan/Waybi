import { spawnSync } from 'node:child_process';

// Override credentials only for the migration child, never for Worker deploys.
const env = { ...process.env };
const d1Token = env.CLOUDFLARE_D1_API_TOKEN?.trim();
if (d1Token) env.CLOUDFLARE_API_TOKEN = d1Token;
delete env.CLOUDFLARE_D1_API_TOKEN;

// Windows needs cmd to launch pnpm.cmd; every command argument here is fixed.
const result = spawnSync(
  process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm',
  [
    'exec', 'wrangler', 'd1', 'migrations', 'apply', 'waybi-users',
    '--remote', '--config', 'wrangler.jsonc',
  ],
  { env, stdio: 'inherit', shell: process.platform === 'win32' },
);
if (result.error) {
  console.error('Unable to start the D1 migration command.');
}
process.exit(result.status ?? 1);
