import { expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

it('dashboard remains usable as a guest and loads a saved profile', async () => {
  vi.stubGlobal('fetch',vi.fn().mockResolvedValue(Response.json({user:{id:'u',email:'driver@example.test'},language:'zh',voiceEnabled:false,recentDestinations:[],savedPlaces:[],routeHistory:[],reviews:[]})));
  await import('../src/dashboard');
  await vi.waitFor(()=>expect(document.querySelector('#dashboardStatusText')?.textContent).toBe('已同步'));
  expect(document.documentElement.lang).toBe('zh-CN');
  expect(document.querySelector<HTMLElement>('#dashboardContent')?.hidden).toBe(false);
  expect(document.body.textContent).toContain('driver@example.test');
});
it('marketing localizes, closes its accessible menu, and rejects an unsafe store link', async () => {
  vi.stubEnv('VITE_APP_STORE_URL','https://apps.apple.com.evil.test/id123');
  await import('../src/marketing');
  expect(document.querySelector('a.store-button')).toBeNull();
  expect(document.querySelector<HTMLButtonElement>('.store-button')?.disabled).toBe(true);
  document.querySelector<HTMLButtonElement>('.menu')!.click();
  expect(document.querySelector('.menu')?.getAttribute('aria-expanded')).toBe('true');
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));
  expect(document.querySelector('.menu')?.getAttribute('aria-expanded')).toBe('false');
  document.querySelector<HTMLButtonElement>('.language')!.click();
  expect(localStorage.getItem('waybi-language')).toBe('zh');
  expect(document.documentElement.lang).toBe('zh-CN');
});
it('marketing allows an official store listing and closes the menu on navigation', async () => {
  vi.stubEnv('VITE_APP_STORE_URL','https://apps.apple.com/nz/app/waybi/id123456');
  await import('../src/marketing');
  expect(document.querySelector<HTMLAnchorElement>('a.store-button')?.href).toContain('apps.apple.com/');
  document.querySelector<HTMLButtonElement>('.menu')!.click();
  document.querySelector<HTMLAnchorElement>('.nav a')!.click();
  expect(document.querySelector('.menu')?.getAttribute('aria-expanded')).toBe('false');
});
it('router displays a recoverable page when the selected surface cannot load', async () => {
  vi.doMock('../src/marketing',()=>{throw new Error('offline bundle');});
  vi.spyOn(console,'error').mockImplementation(()=>{});
  history.replaceState(null,'','/');
  document.body.innerHTML='<div id="app" hidden></div>';
  await import('../src/router');
  await vi.waitFor(()=>expect(document.body.textContent).toContain('Waybi could not load'));
  expect(document.querySelector<HTMLAnchorElement>('a')?.getAttribute('href')).toBe('/');
  vi.doUnmock('../src/marketing');
});
it('the navigator HTML contains every bound control and accessible modal targets', () => {
  const html=readFileSync('index.html','utf8');
  const source=readFileSync('src/main.ts','utf8');
  const ids=[...source.matchAll(/\$\('([^']+)'\)/g)].map(m=>m[1]);
  const missing=[...new Set(ids)].filter(id=>!html.includes('id="'+id+'"'));
  expect(missing).toEqual([]);
});
