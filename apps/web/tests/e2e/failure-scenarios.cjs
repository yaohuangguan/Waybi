#!/usr/bin/env node
/**
 * Browser failure-scenario checks for the Waybi web map (Playwright, Chromium).
 *
 *   pnpm build:web                        # from the repository root
 *   pnpm --filter @waybi/web test:e2e     # starts `vite preview` and runs every scenario
 *
 * The API is mocked with page.route(), so no Worker is needed. Set BASE to run
 * against an already running server instead (service-worker checks need
 * http://localhost or https). ONLY=reroute,offline limits the scenarios.
 * Requires the `playwright` package and a Chromium build (`npx playwright install chromium`).
 */
const { spawn } = require('node:child_process');
const path = require('node:path');
let chromium;
try { ({ chromium } = require('playwright')); } catch {
  console.error('Playwright is not installed. Install it (npm i -g playwright && npx playwright install chromium) and retry.');
  process.exit(2);
}

const WEB = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.PORT || 4179);
const ONLY = (process.env.ONLY || '').split(',').filter(Boolean);
const AUCKLAND = { latitude: -36.8485, longitude: 174.7633, accuracy: 10 };
const PLACE = { id: 'domain', label: 'Auckland Domain, Parnell', latitude: -36.8604, longitude: 174.7772 };
const ROUTE = {
  id: 'drive', mode: 'drive', provider: 'waybi', durationSeconds: 360, staticDurationSeconds: null, trafficDelaySeconds: null,
  distanceMeters: 2400, description: 'Direct', labels: [], warnings: [], encodedPolyline: null, routeToken: null,
  coordinates: [[174.7633, -36.8485], [174.7680, -36.8530], [174.7772, -36.8604]],
  traffic: { normal: 0, slow: 0, trafficJam: 0 }, trafficIntervals: [], transit: [],
  steps: [{ location: [174.7680, -36.8530], name: 'Grafton Road', instruction: 'Turn right onto Grafton Road', maneuver: 'turn', modifier: 'right', distance: 1200, duration: 180 },
    { location: [174.7772, -36.8604], name: 'Domain Drive', instruction: 'Arrive', maneuver: 'arrive', distance: 1200, duration: 180 }]
};
const json = (route, body, status = 200, headers = {}) => route.fulfill({ status, contentType: 'application/json', headers, body: JSON.stringify(body) });

let failures = 0;
function check(condition, label, detail = '') {
  console.log(`  ${condition ? 'ok  ' : 'FAIL'} ${label}${detail ? ` — ${detail}` : ''}`);
  if (!condition) failures++;
}

async function startPreview() {
  if (process.env.BASE) return { base: process.env.BASE.replace(/\/$/, ''), stop() {} };
  const vite = path.join(WEB, 'node_modules', '.bin', process.platform === 'win32' ? 'vite.cmd' : 'vite');
  const child = spawn(vite, ['preview', '--port', String(PORT), '--strictPort', '--host', 'localhost'], { cwd: WEB, stdio: 'ignore' });
  const base = `http://localhost:${PORT}`;
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(base + '/')).ok) return { base, stop: () => child.kill() }; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  child.kill();
  throw new Error('vite preview did not start (did you run `pnpm build:web`?)');
}

/** Default API mocks; `overrides` can replace any endpoint handler. */
async function mockApi(page, overrides = {}) {
  const calls = {};
  await page.route('**/api/**', async (route) => {
    const url = new URL(route.request().url());
    const name = url.pathname.replace('/api/', '');
    calls[name] = (calls[name] || 0) + 1;
    if (overrides[name]) return overrides[name](route, url);
    if (name.startsWith('auth/')) return json(route, { error: 'Not signed in' }, 401);
    if (name === 'suggest' || name === 'search') return json(route, url.searchParams.get('q') === 'parking' ? [] : [PLACE]);
    if (name === 'route-options') return json(route, { provider: 'waybi', trafficAvailable: false, stopsApplied: 0, options: [ROUTE] });
    if (name === 'cameras') return json(route, { cameras: [], sourceUpdatedAt: '2026-10-01', checkedAt: null, syncStatus: 'live' });
    if (name === 'reverse') return json(route, { label: 'Auckland Central' });
    if (name === 'speed-limit') return json(route, { speedLimitKph: 50 });
    if (name === 'parking') return json(route, { places: [] });
    return json(route, {});
  });
  return calls;
}

async function openApp(browser, base, options = {}) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, geolocation: AUCKLAND, permissions: ['geolocation'], serviceWorkers: 'block', locale: 'en-NZ', ...options.context });
  const page = await context.newPage();
  page.on('pageerror', (error) => console.log('  page error:', String(error).slice(0, 160)));
  const calls = options.mock === false ? {} : await mockApi(page, options.overrides);
  await page.goto(base + '/app');
  await page.waitForSelector('#destinationInput');
  await page.waitForTimeout(800);
  return { context, page, calls };
}

async function planToDomain(page) {
  await page.click('#gpsBadge');
  await page.waitForTimeout(500);
  await page.fill('#destinationInput', 'Auckland Domain');
  await page.waitForSelector('#searchResults [role=option]', { timeout: 5000 });
  await page.click('#searchResults [role=option]');
  await page.waitForFunction(() => !document.getElementById('driveButton').disabled, null, { timeout: 5000 });
}

const scenarios = {
  async reroute(browser, base) {
    console.log('API 503 while rerouting during navigation');
    let failRoutes = false;
    const { context, page, calls } = await openApp(browser, base, { overrides: {
      'route-options': (route) => failRoutes ? json(route, { error: 'Internal error', code: 'UPSTREAM', requestId: 'r1' }, 503) : json(route, { provider: 'waybi', trafficAvailable: false, stopsApplied: 0, options: [ROUTE] })
    } });
    await planToDomain(page);
    await page.click('#driveButton');
    await page.waitForFunction(() => document.body.dataset.mode === 'navigation');
    failRoutes = true;
    const before = calls['route-options'] || 0;
    // A missed turn ~400 m west with GPS fixes every 800 ms.
    for (let i = 0; i < 5; i++) {
      await context.setGeolocation({ latitude: -36.8485, longitude: 174.7588 + i * 0.00001, accuracy: 10 });
      await page.waitForTimeout(800);
    }
    const state = await page.evaluate(() => ({
      mode: document.body.dataset.mode,
      status: document.getElementById('navStatus').hidden ? '' : document.getElementById('navStatus').textContent,
      summary: document.getElementById('journeySummaryDialog').open,
      toast: document.getElementById('toast').hidden ? '' : document.getElementById('toast').textContent
    }));
    check(state.mode === 'navigation', 'navigation keeps running');
    check(/following your last route/.test(state.status), 'non-blocking reroute status is shown', state.status);
    check(!state.summary, 'no journey summary appears');
    check(!/Internal error/.test(state.toast + state.status), 'raw 5xx text is not shown');
    const requests = (calls['route-options'] || 0) - before;
    check(requests >= 1 && requests <= 3, 'reroutes back off instead of firing on every GPS fix', `${requests} requests in 4 s`);
    await page.click('#navEndButton');
    check(await page.evaluate(() => document.body.dataset.mode) === 'explore', 'navigation ends only when the user asks');
    await context.close();
  },

  async offline(browser, base) {
    console.log('Offline search');
    const { context, page } = await openApp(browser, base, { mock: false });
    await page.route('**/api/**', (route) => route.abort('internetdisconnected'));
    await page.fill('#destinationInput', 'Sky Tower');
    await page.waitForTimeout(900);
    const suggestion = await page.evaluate(() => ({ hidden: document.getElementById('searchResults').hidden, text: document.getElementById('searchResults').textContent }));
    check(!suggestion.hidden && /offline/i.test(suggestion.text), 'offline suggestions explain themselves', suggestion.text.slice(0, 80));
    await page.press('#destinationInput', 'Enter');
    await page.waitForTimeout(600);
    const result = await page.evaluate(() => ({ hidden: document.getElementById('searchResults').hidden, text: document.getElementById('searchResults').textContent, retry: !!document.querySelector('#searchResults .search-retry') }));
    check(!result.hidden && /offline/i.test(result.text), 'Enter search shows offline feedback', result.text.slice(0, 80));
    check(result.retry, 'a Retry button is offered');
    await context.close();
  },

  async ratelimit(browser, base) {
    console.log('429 with retry-after on search');
    const { context, page, calls } = await openApp(browser, base, { overrides: {
      suggest: (route) => json(route, { error: 'Too many requests', code: 'RATE_LIMITED' }, 429, { 'retry-after': '30' }),
      search: (route) => json(route, { error: 'Too many requests', code: 'RATE_LIMITED' }, 429, { 'retry-after': '30' })
    } });
    for (const query of ['Sky Tower', 'Sky Towers', 'Sky Tower Auckland']) { await page.fill('#destinationInput', query); await page.waitForTimeout(600); }
    await page.press('#destinationInput', 'Enter');
    await page.waitForTimeout(400);
    const text = await page.textContent('#searchResults');
    check((calls.suggest || 0) + (calls.search || 0) === 1, 'no requests are sent before retry-after', `${(calls.suggest || 0) + (calls.search || 0)} requests`);
    check(/busy|paused/i.test(text), 'the user sees a busy message', text.slice(0, 80));
    const toast = await page.evaluate(() => document.getElementById('toast').hidden ? '' : document.getElementById('toast').textContent);
    check(!/busy|rate|429|failed/i.test(toast), 'no error toasts', toast);
    await context.close();
  },

  async race(browser, base) {
    console.log('Enter search vs. pending suggestion');
    const { context, page } = await openApp(browser, base, { overrides: {
      suggest: async (route) => { await new Promise((r) => setTimeout(r, 300)); return json(route, [{ ...PLACE, id: 'stale', label: 'STALE SUGGESTION' }]); },
      search: (route) => json(route, [{ ...PLACE, id: 'search', label: 'SEARCH RESULT' }])
    } });
    await page.click('#destinationInput');
    await page.keyboard.type('Sky Tower', { delay: 20 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1900);
    const text = await page.textContent('#searchResults');
    check(/SEARCH RESULT/.test(text) && !/STALE/.test(text), 'late suggestions never replace Enter results', text.slice(0, 60));
    await context.close();
  },

  async language(browser, base) {
    console.log('Language switch keeps the route');
    const { context, page } = await openApp(browser, base);
    await planToDomain(page);
    const navigations = [];
    page.on('framenavigated', (frame) => { if (frame === page.mainFrame()) navigations.push(frame.url()); });
    const before = await page.evaluate(() => document.getElementById('destinationInput').value);
    await page.click('#settingsButton');
    await page.click('#zhButton');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    const after = await page.evaluate(() => ({
      destination: document.getElementById('destinationInput').value, eyebrow: document.getElementById('tripEyebrow').textContent,
      start: document.getElementById('driveLabel').textContent, enabled: !document.getElementById('driveButton').disabled,
      lang: document.documentElement.lang, key: localStorage.getItem('waybi-ui-language')
    }));
    check(navigations.length === 0, 'the page is not reloaded');
    check(after.destination === before && after.enabled, 'destination and route are kept', after.destination);
    check(after.eyebrow === '路线已就绪' && after.lang === 'zh-CN', 'the UI is Chinese', `${after.eyebrow} / ${after.start}`);
    check(after.key === 'zh', 'the shared language key is written');
    await context.close();
  },

  async serviceworker(browser, base) {
    console.log('Service worker scope and fallback');
    if (!/^(https:|http:\/\/localhost)/.test(base)) { console.log('  skipped: needs https or http://localhost'); return; }
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();
    await page.route('**/api/**', (route) => json(route, route.request().url().includes('/auth/') ? {} : [], route.request().url().includes('/auth/') ? 401 : 200));
    await page.goto(base + '/');
    await page.waitForTimeout(1500);
    check(await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length === 0), 'marketing pages do not install the service worker');
    await page.goto(base + '/app');
    await page.evaluate(async () => { await navigator.serviceWorker.ready; });
    await page.reload();
    await page.waitForTimeout(1500);
    check(await page.evaluate(() => !!navigator.serviceWorker.controller), 'the map installs and uses the service worker');
    for (const file of ['/map-licenses.txt', '/llms.txt']) {
      const response = await page.goto(base + file);
      const type = response.headers()['content-type'] || '';
      check(/text\/plain/.test(type) && !response.fromServiceWorker(), `${file} is not replaced by the app shell`, type);
    }
    await page.goto(base + '/nonexistent-page');
    await page.waitForTimeout(800);
    const heading = await page.textContent('h1');
    check(!/Find your way/.test(heading), 'unknown URLs are not the marketing home', heading.trim().slice(0, 40));
    const app = await page.goto(base + '/app/settings');
    await page.waitForTimeout(800);
    check(app.fromServiceWorker() && await page.evaluate(() => location.pathname === '/app'), '/app/* opens the map from the cached shell');
    await context.close();
  }
};

(async () => {
  const server = await startPreview();
  const browser = await chromium.launch();
  try {
    for (const [name, run] of Object.entries(scenarios)) {
      if (ONLY.length && !ONLY.includes(name)) continue;
      try { await run(browser, server.base); } catch (error) { failures++; console.log(`  FAIL ${name} threw: ${String(error).slice(0, 200)}`); }
    }
  } finally {
    await browser.close();
    server.stop();
  }
  console.log(failures ? `\n${failures} check(s) failed` : '\nAll failure scenarios passed');
  process.exit(failures ? 1 : 0);
})();
