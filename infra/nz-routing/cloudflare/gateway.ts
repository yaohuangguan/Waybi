function authorized(request: Request, token: string): boolean {
  const actual = request.headers.get('authorization') ?? '';
  const expected = `Bearer ${token}`;
  let mismatch = actual.length ^ expected.length;
  for (let index = 0; index < expected.length; index++) {
    mismatch |= expected.charCodeAt(index) ^ (actual.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

export async function engineGateway(request: Request, token: string | undefined,
  fetchEngine: (request: Request) => Promise<Response>): Promise<Response> {
  // The existing Worker calls this endpoint; phones never receive its key.
  if (!token) return new Response('Routing not configured', { status: 503 });
  if (!authorized(request, token)) return new Response('Unauthorized', { status: 401 });
  const path = new URL(request.url).pathname;
  if (!(path === '/route' && request.method === 'POST') && !(path === '/status' && request.method === 'GET')) {
    return new Response('Not found', { status: 404 });
  }
  let body: string | undefined;
  if (path === '/route') {
    if (Number(request.headers.get('content-length')) > 64_000) return new Response('Too large', { status: 413 });
    const reader = request.body?.getReader();
    if (!reader) return new Response('Missing route', { status: 400 });
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        length += chunk.value.length;
        if (length > 64_000) { await reader.cancel(); return new Response('Too large', { status: 413 }); }
        chunks.push(chunk.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    body = new TextDecoder().decode(bytes);
    try {
      const route = JSON.parse(body);
      if (!Array.isArray(route.locations) || route.locations.length < 2 || route.locations.length > 10 ||
          !route.locations.every((point: { lat: number; lon: number }) => Number.isFinite(point.lat) &&
            Number.isFinite(point.lon) && point.lat >= -48 && point.lat <= -34 && point.lon >= 166 && point.lon <= 179) ||
          !['auto', 'pedestrian', 'bicycle'].includes(route.costing) ||
          route.format !== 'osrm' || route.shape_format !== 'geojson') return new Response('Invalid NZ route', { status: 400 });
    } catch { return new Response('Invalid route', { status: 400 }); }
  }
  const result = await fetchEngine(new Request(`http://container${path}`, {
    method: request.method, headers: { 'content-type': 'application/json' }, body,
  }));
  return new Response(result.body, { status: result.status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
}
