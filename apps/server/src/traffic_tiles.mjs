// Optional street traffic adapter. No account/key/budget => no upstream calls.
export function trafficTileConfig(env) {
  const budget = Math.min(200000, Math.max(0, Math.floor(Number(env.TRAFFIC_TILES_MONTHLY_BUDGET) || 0)));
  return env.TRAFFIC_TILES_ENABLED === 'true' && env.TOMTOM_TRAFFIC_API_KEY && budget > 0 && env.USER_DB
    ? { provider: 'tomtom', tileTemplate: '/api/map/traffic/tiles/{z}/{x}/{y}.png', attribution: '© TomTom', monthlyBudget: budget }
    : null;
}
export async function handleTrafficTile(request, env, fetcher = fetch, cache = globalThis.caches?.default) {
  const url = new URL(request.url), match = /^\/api\/map\/traffic\/tiles\/(\d+)\/(\d+)\/(\d+)\.png$/.exec(url.pathname);
  if (request.method !== 'GET') return new Response('Method not allowed', { status: 405 });
  if (!match) return new Response('Invalid tile', { status: 400 });
  const [z, x, y] = match.slice(1).map(Number), n = 2 ** z;
  if (z < 6 || z > 19 || x >= n || y >= n) return new Response('Invalid tile', { status: 400 });
  const config = trafficTileConfig(env);
  if (!config) return new Response('Street traffic is not configured', { status: 503 });
  const key = new Request(`${url.origin}${url.pathname}`);
  const cached = await cache?.match(key); if (cached) return cached;
  // Atomic, account-wide monthly cap. Missing migration fails closed.
  try {
    const reservation = await env.USER_DB.prepare(`
      INSERT INTO traffic_tile_budget (month, requests) VALUES (?, 1)
      ON CONFLICT(month) DO UPDATE SET requests = requests + 1
      WHERE requests < ? RETURNING requests
    `).bind(new Date().toISOString().slice(0, 7), config.monthlyBudget).first();
    if (!reservation) return new Response('Traffic allowance reached', { status: 429 });
  } catch { return new Response('Traffic allowance is unavailable', { status: 503 }); }
  const upstream = new URL(`https://api.tomtom.com/traffic/map/4/tile/flow/relative0/${z}/${x}/${y}.png`);
  upstream.search = new URLSearchParams({ key: env.TOMTOM_TRAFFIC_API_KEY, tileSize: '256', thickness: '3' });
  let result;
  try { result = await fetcher(upstream, { signal: AbortSignal.timeout(8000) }); }
  catch { return new Response('Traffic source unavailable', { status: 502 }); }
  if (!result.ok || !result.headers.get('content-type')?.includes('image/png')) return new Response('Traffic source unavailable', { status: 502 });
  const tile = new Response(await result.arrayBuffer(), { headers: {
    'content-type': 'image/png', 'cache-control': 'public, max-age=60', 'access-control-allow-origin': '*',
  } });
  await cache?.put(key, tile.clone()); return tile;
}
