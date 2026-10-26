const tokenEndpoint = 'https://oauth2.googleapis.com/token';
const encoder = new TextEncoder();

interface ServiceAccount {
  type: string;
  client_email: string;
  private_key: string;
  private_key_id: string;
}

// One credential/audience pair per isolate. Neither keys nor tokens enter KV,
// logs, URLs, route responses, or the app. Refresh before Google's expiry.
let cached: { credentials: string; audience: string; token: string; expires: number } | undefined;
let pending: { credentials: string; audience: string; promise: Promise<string> } | undefined;

function base64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function decodePayload(token: string) {
  const part = token.split('.')[1];
  if (!part || token.split('.').length !== 3) throw new Error('Invalid Cloud Run identity token');
  const encoded = part.replaceAll('-', '+').replaceAll('_', '/');
  return JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')));
}

export async function cloudRunIdentityToken(
  credentials: string, audience: string, signal: AbortSignal, fetcher: typeof fetch = fetch,
): Promise<string> {
  const url = new URL(audience);
  // Never send an IAM token to a custom redirect, local endpoint, or arbitrary
  // origin. Use the canonical service URL (without /route or a traffic tag).
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.run.app') || url.origin !== audience) {
    throw new Error('Cloud Run requires a canonical HTTPS run.app service URL');
  }
  if (cached?.credentials === credentials && cached.audience === audience && cached.expires > Date.now() + 60000) {
    return cached.token;
  }
  if (pending?.credentials === credentials && pending.audience === audience) return pending.promise;
  const promise = exchange(credentials, audience, signal, fetcher);
  const entry = { credentials, audience, promise };
  pending = entry;
  try { return await promise; }
  finally { if (pending === entry) pending = undefined; }
}

async function exchange(credentials: string, audience: string, signal: AbortSignal, fetcher: typeof fetch) {
  let account: ServiceAccount;
  try { account = JSON.parse(credentials); }
  catch { throw new Error('Invalid Cloud Run service account secret'); }
  if (account.type !== 'service_account' || !account.client_email?.endsWith('.iam.gserviceaccount.com') ||
      !account.private_key?.startsWith('-----BEGIN PRIVATE KEY-----') || !account.private_key_id) {
    throw new Error('Invalid Cloud Run service account secret');
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: account.private_key_id })));
  const payload = base64url(encoder.encode(JSON.stringify({ iss: account.client_email, sub: account.client_email,
    aud: tokenEndpoint, iat: now, exp: now + 3600, target_audience: audience })));
  const pem = account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), char => char.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const unsigned = `${header}.${payload}`;
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned)));
  // Workers supports manual/follow, unlike Node's additional error mode.
  // Manual returns 3xx to the status check without forwarding credentials.
  const response = await fetcher(tokenEndpoint, { method: 'POST', redirect: 'manual', signal,
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${base64url(signature)}` }).toString() });
  if (!response.ok) throw new Error(`Cloud Run identity exchange HTTP ${response.status}`);
  const result = await response.json<{ id_token?: string }>();
  if (typeof result.id_token !== 'string') throw new Error('Cloud Run identity exchange returned no token');
  // This token comes directly from Google's fixed HTTPS endpoint. Cloud Run
  // verifies its signature; these checks prevent caching an unusable response.
  const claims = decodePayload(result.id_token);
  if (claims.aud !== audience || !['https://accounts.google.com', 'accounts.google.com'].includes(claims.iss) ||
      !Number.isFinite(claims.exp) || claims.exp * 1000 <= Date.now() + 60000) {
    throw new Error('Invalid Cloud Run identity token claims');
  }
  cached = { credentials, audience, token: result.id_token, expires: claims.exp * 1000 };
  return result.id_token;
}
