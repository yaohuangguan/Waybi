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

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  return {
    server: { port: 5173, proxy: { '/api': 'http://localhost:8787' } },
    plugins: [prerenderMarketing(env.VITE_APP_STORE_URL), VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['brand/waybi-icon.png', 'brand/waybi-lockup.svg'],
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
        icons: [{ src: '/brand/waybi-icon.png', sizes: '1024x1024', type: 'image/png', purpose: 'any' }]
      },
      workbox: {
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/(?:zh\/)?(?:privacy|terms|support)(?:\/|$)/],
        runtimeCaching: [
          { urlPattern: ({ url }) => url.pathname === '/api/cameras', handler: 'NetworkFirst', options: { cacheName: 'kiwi-camera-data', networkTimeoutSeconds: 5, expiration: { maxEntries: 2, maxAgeSeconds: 86400 } } },
          { urlPattern: ({ url }) => url.hostname.endsWith('tile.openstreetmap.org'), handler: 'CacheFirst', options: { cacheName: 'kiwi-map-tiles', expiration: { maxEntries: 500, maxAgeSeconds: 604800 } } }
        ]
      }
    })]
  };
});
