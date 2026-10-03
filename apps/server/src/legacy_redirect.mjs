const WAYBI_ORIGIN = 'https://waybi.nzs.workers.dev';

export default {
  async fetch(request) {
    const source = new URL(request.url);
    const target = new URL(source.pathname + source.search, WAYBI_ORIGIN);

    if (source.pathname === '/api' || source.pathname.startsWith('/api/')) {
      return fetch(new Request(target, request));
    }

    return Response.redirect(target.toString(), 308);
  }
};
