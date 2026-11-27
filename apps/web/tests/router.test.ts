import { expect, it, vi } from 'vitest';
import { canonicalAppUrl, checkoutState, resolveSurface } from '../src/routes';

it('maps every path to a real surface instead of a marketing soft 404', () => {
  expect(resolveSurface('/')).toBe('marketing');
  expect(resolveSurface('/index.html')).toBe('marketing');
  expect(resolveSurface('/app')).toBe('app');
  expect(resolveSurface('/app/')).toBe('app');
  expect(resolveSurface('/app/settings')).toBe('app');
  expect(resolveSurface('/application')).toBe('not-found');
  expect(resolveSurface('/dashboard/')).toBe('dashboard');
  expect(resolveSurface('/subscribe')).toBe('subscribe');
  expect(resolveSurface('/subscribe/')).toBe('subscribe');
  expect(resolveSurface('/about')).toBe('not-found');
  expect(resolveSurface('/nonexistent-page')).toBe('not-found');
});

it('normalises /app/<anything> to /app and reads the checkout state', () => {
  expect(canonicalAppUrl({ pathname: '/app', search: '?q=1', hash: '' })).toBeNull();
  expect(canonicalAppUrl({ pathname: '/app/', search: '', hash: '' })).toBeNull();
  expect(canonicalAppUrl({ pathname: '/app/settings', search: '?q=1', hash: '#x' })).toBe('/app?q=1#x');
  expect(checkoutState('?checkout=success&session_id=cs_1')).toBe('success');
  expect(checkoutState('?checkout=cancelled&plan=plus')).toBe('cancelled');
  expect(checkoutState('')).toBe('manage');
});

it('router shows the Stripe success state on /subscribe, not the marketing home', async () => {
  history.replaceState(null, '', '/subscribe?checkout=success&session_id=cs_test');
  document.head.innerHTML = '<meta name="robots" content="index,follow"><link rel="canonical" href="https://waybi.co/">';
  document.body.innerHTML = '<div id="app" hidden></div><div id="marketing-root"><h1>Find your way.</h1></div>';
  await import('../src/router');
  await vi.waitFor(() => expect(document.querySelector('h1')?.textContent).toContain('you’re all set'));
  expect(document.getElementById('marketing-root')).toBeNull();
  expect(document.querySelector('meta[name="robots"]')?.getAttribute('content')).toBe('noindex,follow');
  expect(document.querySelector('link[rel="canonical"]')).toBeNull();
});

it('router shows a not-found state for unknown paths', async () => {
  history.replaceState(null, '', '/totally/unknown');
  document.body.innerHTML = '<div id="app" hidden></div><div id="marketing-root"><h1>Find your way.</h1></div>';
  await import('../src/router');
  await vi.waitFor(() => expect(document.querySelector('h1')?.textContent).toBe('This road ends here.'));
  expect([...document.querySelectorAll('a')].map(a => a.getAttribute('href'))).toEqual(expect.arrayContaining(['/', '/app']));
});

it('router keeps the prerendered marketing page and only binds behaviour', async () => {
  history.replaceState(null, '', '/');
  const { renderMarketing } = await import('../src/marketing-content');
  document.body.innerHTML = `<div id="app" hidden></div><div id="marketing-root" class="marketing" data-language="en">${renderMarketing('en')}</div>`;
  const heading = document.querySelector('h1');
  await import('../src/router');
  await vi.waitFor(() => expect(document.body.dataset.surface).toBe('marketing'));
  // Same node: no repaint of the first paint.
  expect(document.querySelector('h1')).toBe(heading);
  expect(document.getElementById('app')).toBeNull();
  expect(document.querySelectorAll('h1')).toHaveLength(1);
});

it('marketing re-renders in Chinese when that language was saved on another surface', async () => {
  history.replaceState(null, '', '/');
  localStorage.setItem('kiwi-language', 'zh');
  const { renderMarketing } = await import('../src/marketing-content');
  document.body.innerHTML = `<div id="marketing-root" class="marketing" data-language="en">${renderMarketing('en')}</div>`;
  await import('../src/marketing');
  expect(document.documentElement.lang).toBe('zh-CN');
  expect(document.querySelector('h1')?.textContent).toContain('出发有方向');
  expect(localStorage.getItem('waybi-ui-language')).toBe('zh');
});
