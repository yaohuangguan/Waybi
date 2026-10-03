import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  server: { port: 5173, proxy: { '/api': 'http://localhost:8787' } },
  plugins: [VitePWA({
    registerType: 'autoUpdate',
    includeAssets: ['brand/waybi-icon.png', 'brand/waybi-lockup.svg'],
    manifest: {
      name: 'Waybi · New Zealand Navigation',
      short_name: 'Waybi',
      description: 'New Zealand navigation with route planning, traffic-aware guidance, fixed safety-camera reminders, parking discovery and bilingual guidance.',
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
      runtimeCaching: [
        { urlPattern: ({ url }) => url.pathname === '/api/cameras', handler: 'NetworkFirst', options: { cacheName: 'kiwi-camera-data', networkTimeoutSeconds: 5, expiration: { maxEntries: 2, maxAgeSeconds: 86400 } } },
        { urlPattern: ({ url }) => url.hostname.endsWith('tile.openstreetmap.org'), handler: 'CacheFirst', options: { cacheName: 'kiwi-map-tiles', expiration: { maxEntries: 500, maxAgeSeconds: 604800 } } }
      ]
    }
  })]
});
