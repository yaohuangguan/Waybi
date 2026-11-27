import { registerSW } from 'virtual:pwa-register';

/**
 * Registers the offline worker from the map only. When a new version is
 * waiting, `onUpdate` is told; calling the returned `apply()` activates it
 * (skipWaiting) and reloads once, so the page never mixes old and new files.
 */
export function registerUpdates(onUpdate: (apply: () => void) => void) {
  if (!('serviceWorker' in navigator)) return;
  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() { onUpdate(() => void updateSW(true)); },
    onRegisteredSW(_url, registration) {
      // Long-lived PWA sessions still notice deployments.
      if (registration) window.setInterval(() => void registration.update().catch(() => {}), 60 * 60 * 1000);
    }
  });
}
