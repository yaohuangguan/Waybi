/** Minimal Cloudflare Cache API simulation for public map metadata tests. */
export function mockEdgeCache() {
  const old = globalThis.caches;
  const entries = new Map<string, Response>();
  const keyOf = (key: Request | string) => typeof key === 'string' ? key : key.url;
  globalThis.caches = {
    default: {
      async match(key: Request | string) { return entries.get(keyOf(key))?.clone(); },
      async put(key: Request | string, response: Response) {
        entries.set(keyOf(key), response.clone());
      },
    },
  } as unknown as CacheStorage;
  return {
    entries,
    restore() {
      if (old) globalThis.caches = old;
      else delete (globalThis as unknown as { caches?: CacheStorage }).caches;
    }
  };
}
