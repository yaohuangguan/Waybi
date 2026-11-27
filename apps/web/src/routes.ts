export type Surface = 'marketing' | 'app' | 'dashboard' | 'subscribe' | 'not-found';

/**
 * Maps a path to the surface the shared index.html should show. The Worker
 * serves index.html for /, /app/* and /dashboard/*; anything else only reaches
 * the router through an old service-worker fallback or the dev server, and
 * must not render the marketing home as a soft 404.
 */
export function resolveSurface(pathname: string): Surface {
  const path = pathname.replace(/\/+$/, '') || '/';
  if (path === '/' || path === '/index.html') return 'marketing';
  if (path === '/app' || path.startsWith('/app/')) return 'app';
  if (path === '/dashboard' || path.startsWith('/dashboard/')) return 'dashboard';
  if (path === '/subscribe') return 'subscribe';
  return 'not-found';
}

/** /app/<anything> shows the map at its canonical address, keeping query and hash. */
export function canonicalAppUrl(location: { pathname: string; search: string; hash: string }) {
  const path = location.pathname.replace(/\/+$/, '');
  return path === '/app' ? null : `/app${location.search}${location.hash}`;
}

export type CheckoutState = 'success' | 'cancelled' | 'manage';
export function checkoutState(search: string): CheckoutState {
  const value = new URLSearchParams(search).get('checkout');
  return value === 'success' ? 'success' : value === 'cancelled' ? 'cancelled' : 'manage';
}
