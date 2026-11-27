import { defineConfig, loadEnv, type Plugin } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';
import { renderMarketing } from './src/marketing-content';

/**
 * Renders the English marketing page into index.html at build (and dev) time,
 * so the first paint is the final page and crawlers see the same H1 as users.
 */
function prerenderMarketing(appStoreUrl: string | undefined): Plugin {
  return {
    name: 'waybi-prerender-marketing',
    transformIndexHtml: {
      order: 'pre',
      handler(html) {
        if (!html.includes('<!--marketing-prerender-->')) throw new Error('index.html is missing the marketing prerender marker');
        return html.replace('<!--marketing-prerender-->', renderMarketing('en', { appStoreUrl, year: new Date().getFullYear() }));
      }
    }
  };
}

/** Navigations the service worker may answer with the cached app shell. */
export const APP_SHELL_ROUTES = [/^\/app(?:\/.*)?$/, /^\/dashboard\/?$/];

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  return {
    server: { port: 5173, proxy: { '/api': 'http://localhost:8787' } },
    build: {
      rollupOptions: {
        output: {
          // MapLibre and PMTiles change rarely and are large: keep them in their own
          // long-cached chunk, loaded only by the map (never by marketing pages).
          manualChunks(id) {
            if (/node_modules\/(?:\.pnpm\/)?(?:maplibre-gl|pmtiles)/.test(id)) return 'maplibre';
            return undefined;
          }
        }
      }
    },
    plugins: [prerenderMarketing(env.VITE_APP_STORE_URL), VitePWA({
      // The map registers the worker itself (src/pwa.ts); marketing and static
      // pages never do, so visiting them downloads no app bundle.
      injectRegister: false,
      // A new version waits until the user accepts the in-app prompt, so a page
      // in use (possibly mid-navigation) is never swapped underneath them.
      registerType: 'prompt',
      includeAssets: [],
      manifest: {
        name: 'Waybi · Maps & Navigation',
        short_name: 'Waybi',
        description: 'Search places, plan routes and view New Zealand fixed safety-camera information with Waybi on the web.',
        lang: 'en-NZ',
        categories: ['navigation', 'travel'],
        theme_color: '#152510',
        background_color: '#152510',
        display: 'standalone',
        start_url: '/app',
        scope: '/',
        orientation: 'portrait',
        icons: [
          { src: '/brand/waybi-icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/brand/waybi-icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/brand/waybi-icon.png', sizes: '1024x1024', type: 'image/png', purpose: 'any' }
        ]
      },
      workbox: {
        // Only the app shell: no static pages, marketing or dashboard chunks, or artwork.
        globPatterns: ['index.html', 'assets/*.{js,css}', 'favicon.svg'],
        globIgnores: ['**/marketing-*', '**/dashboard-*', '**/status-page-*'],
        maximumFileSizeToCacheInBytes: 3 * 1024 * 1024,
        cleanupOutdatedCaches: true,
        // "/" is not answered from the precache: the marketing page always comes from the network.
        directoryIndex: null,
        navigateFallback: '/index.html',
        navigateFallbackAllowlist: APP_SHELL_ROUTES,
        // Never for the API or for files (/map-licenses.txt, /llms.txt, …).
        navigateFallbackDenylist: [/^\/api\//, /\/[^/?]+\.[a-z0-9]+$/i],
        runtimeCaching: [
          { urlPattern: ({ url }) => url.pathname === '/api/cameras', handler: 'NetworkFirst', options: { cacheName: 'kiwi-camera-data', networkTimeoutSeconds: 5, expiration: { maxEntries: 2, maxAgeSeconds: 86400 } } },
          // Global fallback tiles, glyphs and sprites (the NZ archive uses range requests and is not cached).
          { urlPattern: ({ url }) => url.hostname === 'tiles.openfreemap.org', handler: 'CacheFirst', options: { cacheName: 'waybi-global-tiles', expiration: { maxEntries: 800, maxAgeSeconds: 7 * 86400 }, cacheableResponse: { statuses: [0, 200] } } },
          { urlPattern: ({ url }) => url.hostname === 'fonts.googleapis.com', handler: 'StaleWhileRevalidate', options: { cacheName: 'waybi-font-css', expiration: { maxEntries: 4 } } },
          { urlPattern: ({ url }) => url.hostname === 'fonts.gstatic.com', handler: 'CacheFirst', options: { cacheName: 'waybi-fonts', expiration: { maxEntries: 8, maxAgeSeconds: 365 * 86400 }, cacheableResponse: { statuses: [0, 200] } } }
        ]
      }
    })]
  };
});
