/**
 * Public, reproducible map metadata belongs in the local Cloudflare cache, not
 * in Workers KV's account-wide 1,000 writes/day free-tier budget.
 *
 * Cache API entries can be evicted and are not replicated between PoPs. Never
 * use this for user records, route safety decisions or the authoritative feed.
 */
function edgeCache(): Cache | null {
  try { return typeof caches === 'undefined' ? null : (caches as CacheStorage & { default?: Cache }).default ?? null; }
  catch { return null; }
}

export async function readPublicEdgeJson<T>(url: string): Promise<T | null> {
  const cache = edgeCache();
  if (!cache) return null;
  try {
    const entry = await cache.match(new Request(url));
    return entry?.ok ? await entry.json() as T : null;
  } catch { return null; }
}

export async function writePublicEdgeJson(url: string, data: unknown, seconds: number): Promise<void> {
  const cache = edgeCache();
  if (!cache) return;
  try {
    await cache.put(new Request(url), new Response(JSON.stringify(data), {
      headers: { 'content-type': 'application/json', 'cache-control': `public, max-age=${seconds}` }
    }));
  } catch (error) {
    // Cache eviction or unavailable Cache API must never break place discovery.
    console.warn('Public edge cache write unavailable:', String(error));
  }
}
