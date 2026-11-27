// Test stand-in for vite-plugin-pwa's virtual module (vitest does not load the PWA plugin).
export function registerSW() {
  return async () => {};
}
