import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export async function checkCloudflareAccount(config, env = process.env, fetcher = fetch) {
  const workerToken = env.CLOUDFLARE_API_TOKEN?.trim();
  const d1Token = env.CLOUDFLARE_D1_API_TOKEN?.trim() || workerToken;
  if (!workerToken) throw new Error('Missing Cloudflare deployment credential');
  const database = config.d1_databases.find(binding => binding.binding === 'USER_DB');
  const checks = [
    [`/accounts/${config.account_id}`, workerToken, 'id', config.account_id],
    [`/accounts/${config.account_id}/d1/database/${database.database_id}`, d1Token, 'uuid', database.database_id],
  ];
  for (const [path, token, key, expected] of checks) {
    const response = await fetcher(`https://api.cloudflare.com/client/v4${path}`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || payload?.success !== true || payload.result?.[key] !== expected) {
      throw new Error(`Deployment credentials cannot access the configured Cloudflare ${key === 'id' ? 'account' : 'database'}. Update the repository deployment credentials before publishing.`);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
    await checkCloudflareAccount(config);
    console.log(`Verified deployment account ${config.account_id} and USER_DB`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
