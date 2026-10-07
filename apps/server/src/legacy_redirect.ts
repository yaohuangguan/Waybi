const WAYBI_ORIGIN = 'https://waybi.co';

export default {
  async fetch(request: Request, env) {
    const source = new URL(request.url);
    const target = new URL(source.pathname + source.search, WAYBI_ORIGIN);

    if (source.pathname === '/api' || source.pathname.startsWith('/api/')) {
      if (!env?.WAYBI?.fetch) {
        return Response.redirect(target.toString(), 308);
      }
      return env.WAYBI.fetch(new Request(target, request));
    }

    return Response.redirect(target.toString(), 308);
  }
};
