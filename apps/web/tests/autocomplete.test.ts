import { afterEach, expect, it, vi } from 'vitest';
import { initAutocomplete, placeLabel, SUGGEST_COOLDOWN_MS } from '../src/autocomplete';
import { rateLimits } from '../src/api';

afterEach(() => rateLimits.clear());

it('keeps independent POI names beside their street addresses', () => {
  const place = { id: 1, name:'Auckland Museum', label:'Museum Circuit, Auckland', address:'Museum Circuit, Auckland', isPoi:true, latitude:-36.86, longitude:174.77 };
  expect(placeLabel(place)).toBe('Auckland Museum, Museum Circuit, Auckland');
  expect(placeLabel({...place, label:'Auckland Museum, Auckland', address:'Auckland Museum, Auckland'})).toBe('Auckland Museum, Auckland');
  expect(placeLabel({...place, isPoi:false})).toBe('Museum Circuit, Auckland');
});

function setup(recent: any[] = [], now?: () => number) {
  document.body.innerHTML='<input id="origin"><input id="destination"><div id="results" hidden></div>';
  const origin=document.querySelector<HTMLInputElement>('#origin')!;
  const destination=document.querySelector<HTMLInputElement>('#destination')!;
  const results=document.querySelector<HTMLElement>('#results')!;
  const select=vi.fn();
  const handle=initAutocomplete({origin,destination,results,language:()=> 'en',recent:()=>recent,select,now});
  return {origin,destination,results,select,handle};
}
function input(node: HTMLInputElement, value: string) {
  node.value=value;
  node.dispatchEvent(new Event('input'));
}
const key = (node: HTMLElement, k: string) => node.dispatchEvent(new KeyboardEvent('keydown',{key:k,bubbles:true,cancelable:true}));
const options = (results: HTMLElement) => Array.from(results.querySelectorAll<HTMLElement>('[role="option"]'));

it('offers recent destinations and safely renders untrusted labels', () => {
  const ui=setup([{label:'<img src=x onerror=alert(1)>',latitude:-37,longitude:174}]);
  ui.destination.dispatchEvent(new Event('focus'));
  expect(ui.results.hidden).toBe(false);
  expect(ui.results.querySelector('img')).toBeNull();
  (ui.results.querySelector('button')!).click();
  expect(ui.select).toHaveBeenCalledWith('destination',expect.objectContaining({latitude:-37}));
  expect(ui.results.hidden).toBe(true);
});

it('debounces search, rejects late queries and selects the correct input target', async () => {
  vi.useFakeTimers();
  const resolvers: ((value:Response)=>void)[]=[];
  vi.stubGlobal('fetch',vi.fn(()=>new Promise<Response>(resolve=>resolvers.push(resolve))));
  const ui=setup();
  input(ui.origin,'airport');
  await vi.advanceTimersByTimeAsync(450);
  input(ui.origin,'hospital');
  await vi.advanceTimersByTimeAsync(450);
  resolvers[1](Response.json([{id:'new',label:'Hospital',latitude:-37,longitude:174}]));
  await vi.advanceTimersByTimeAsync(0);
  resolvers[0](Response.json([{id:'old',label:'Airport',latitude:-38,longitude:175}]));
  await vi.advanceTimersByTimeAsync(0);
  expect(ui.results.textContent).toContain('Hospital');
  expect(ui.results.textContent).not.toContain('Airport');
  ui.results.querySelector('button')!.click();
  expect(ui.select).toHaveBeenCalledWith('origin',expect.objectContaining({id:'new'}));
});

it('lets an Enter search cancel the pending suggestion debounce and ignore late suggestions', async () => {
  vi.useFakeTimers();
  const resolvers: ((value:Response)=>void)[]=[];
  const fetcher=vi.fn(()=>new Promise<Response>(resolve=>resolvers.push(resolve)));
  vi.stubGlobal('fetch',fetcher);
  const ui=setup();
  // Pending debounce: Enter (begin) means no suggestion request is ever sent.
  input(ui.destination,'Sky Tower');
  ui.handle.begin(ui.destination);
  await vi.advanceTimersByTimeAsync(1000);
  expect(fetcher).not.toHaveBeenCalled();
  // In-flight suggestion: its late answer must not replace the search results.
  input(ui.destination,'Sky Towers');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher).toHaveBeenCalledTimes(1);
  const token=ui.handle.begin(ui.destination);
  ui.handle.renderPlaces(ui.destination,[{id:'s',label:'SEARCH RESULT',latitude:-36.85,longitude:174.76}],vi.fn());
  resolvers[0](Response.json([{id:'a',label:'STALE SUGGESTION',latitude:-36.85,longitude:174.76}]));
  await vi.advanceTimersByTimeAsync(0);
  expect(ui.handle.isCurrent(token)).toBe(true);
  expect(ui.results.textContent).toContain('SEARCH RESULT');
  expect(ui.results.textContent).not.toContain('STALE SUGGESTION');
});

it('implements the ARIA combobox keyboard pattern', async () => {
  vi.useFakeTimers();
  vi.stubGlobal('fetch',vi.fn(async()=>Response.json([
    {id:1,label:'One',latitude:-36,longitude:174},{id:2,label:'Two',latitude:-36,longitude:174},{id:3,label:'Three',latitude:-36,longitude:174}
  ])));
  const ui=setup();
  expect(ui.destination.getAttribute('role')).toBe('combobox');
  expect(ui.destination.getAttribute('aria-expanded')).toBe('false');
  const listbox=ui.results.querySelector('[role="listbox"]')!;
  expect(ui.destination.getAttribute('aria-controls')).toBe(listbox.id);
  input(ui.destination,'one');
  await vi.advanceTimersByTimeAsync(450);
  expect(ui.destination.getAttribute('aria-expanded')).toBe('true');
  expect(options(ui.results)).toHaveLength(3);
  key(ui.destination,'ArrowDown');
  expect(ui.destination.getAttribute('aria-activedescendant')).toBe(options(ui.results)[0]!.id);
  key(ui.destination,'ArrowUp');
  expect(ui.destination.getAttribute('aria-activedescendant')).toBe(options(ui.results)[2]!.id);
  expect(options(ui.results)[2]!.getAttribute('aria-selected')).toBe('true');
  key(ui.destination,'Enter');
  expect(ui.select).toHaveBeenCalledWith('destination',expect.objectContaining({label:'Three'}));
  expect(ui.results.hidden).toBe(true);
  expect(ui.destination.getAttribute('aria-expanded')).toBe('false');
  input(ui.destination,'two');
  await vi.advanceTimersByTimeAsync(450);
  expect(ui.results.hidden).toBe(false);
  key(ui.destination,'Escape');
  expect(ui.results.hidden).toBe(true);
});

it('pauses suggest after a 503 instead of disabling it, and explains offline failures', async () => {
  vi.useFakeTimers();
  let clock=0;
  const fetcher=vi.fn()
    .mockResolvedValueOnce(new Response('',{status:503}))
    .mockResolvedValueOnce(Response.json([]))
    .mockResolvedValueOnce(Response.json([]))
    .mockRejectedValueOnce(new TypeError('Failed to fetch'))
    .mockResolvedValueOnce(Response.json([{id:1,label:'Back',latitude:-36,longitude:174}]));
  vi.stubGlobal('fetch',fetcher);
  const ui=setup([],()=>clock);
  input(ui.destination,'airport');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher.mock.calls[0][0]).toContain('/api/suggest?');
  expect(fetcher.mock.calls[1][0]).toContain('/api/search?');
  // During the cooldown the heavier search is used, with a longer debounce.
  input(ui.destination,'whitaker');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher).toHaveBeenCalledTimes(2);
  await vi.advanceTimersByTimeAsync(350);
  expect(fetcher.mock.calls[2][0]).toContain('/api/search?');
  // Offline: tell the user rather than silently hiding the list.
  input(ui.destination,'offline place');
  await vi.advanceTimersByTimeAsync(800);
  expect(ui.results.hidden).toBe(false);
  expect(ui.results.textContent).toContain('offline');
  // After the cooldown, suggest is tried again.
  clock=SUGGEST_COOLDOWN_MS+1;
  input(ui.destination,'back again');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher.mock.calls[4][0]).toContain('/api/suggest?');
  expect(ui.results.textContent).toContain('Back');
  input(ui.destination,'a');
  expect(ui.results.hidden).toBe(true);
});

it('respects 429 retry-after without retrying on every keystroke', async () => {
  vi.useFakeTimers();
  const fetcher=vi.fn(async()=>new Response('{}',{status:429,headers:{'retry-after':'30'}}));
  vi.stubGlobal('fetch',fetcher);
  const ui=setup();
  input(ui.destination,'sky tower');
  await vi.advanceTimersByTimeAsync(450);
  expect(ui.results.textContent).toContain('paused');
  input(ui.destination,'sky towers');
  await vi.advanceTimersByTimeAsync(450);
  input(ui.destination,'sky towers a');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher).toHaveBeenCalledTimes(1);
});
