// Historical API hosts forward to the single production database in moviegoer24.
export default {
  async fetch(request) {
    const incoming = new URL(request.url);
    const target = new URL(request.url);
    target.protocol = 'https:';
    target.hostname = 'waybi.co';
    target.port = '';
    if (!incoming.pathname.startsWith('/api/')) {
      return Response.redirect(target.toString(), 301);
    }
    const headers = new Headers(request.headers);
    if (headers.get('origin') === incoming.origin) {
      headers.set('origin', target.origin);
    }
    return fetch(new Request(target, new Request(request, { headers })), { redirect: 'manual' });
  },
};
