import { expect, it, vi } from 'vitest';
import { initAutocomplete, placeLabel } from '../src/autocomplete';

it('keeps independent POI names beside their street addresses', () => {
  const place = { id: 1, name:'Auckland Museum', label:'Museum Circuit, Auckland', address:'Museum Circuit, Auckland', isPoi:true, latitude:-36.86, longitude:174.77 };
  expect(placeLabel(place)).toBe('Auckland Museum, Museum Circuit, Auckland');
  expect(placeLabel({...place, label:'Auckland Museum, Auckland', address:'Auckland Museum, Auckland'})).toBe('Auckland Museum, Auckland');
  expect(placeLabel({...place, isPoi:false})).toBe('Museum Circuit, Auckland');
});

function setup(recent: any[] = []) {
  document.body.innerHTML='<input id="origin"><input id="destination"><div id="results" hidden></div>';
  const origin=document.querySelector<HTMLInputElement>('#origin')!;
  const destination=document.querySelector<HTMLInputElement>('#destination')!;
  const results=document.querySelector<HTMLElement>('#results')!;
  const select=vi.fn();
  initAutocomplete({origin,destination,results,language:()=> 'en',recent:()=>recent,select});
  return {origin,destination,results,select};
}
function input(node: HTMLInputElement, value: string) {
  node.value=value;
  node.dispatchEvent(new Event('input'));
}
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
it('falls back once when suggestions are unconfigured and tolerates network failure', async () => {
  vi.useFakeTimers();
  const fetcher=vi.fn().mockResolvedValueOnce(new Response('',{status:503})).mockResolvedValueOnce(Response.json([])).mockRejectedValueOnce(new Error('offline'));
  vi.stubGlobal('fetch',fetcher);
  const ui=setup();
  input(ui.destination,'airport');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher.mock.calls[1][0]).toContain('/api/search?');
  input(ui.destination,'whitaker');
  await vi.advanceTimersByTimeAsync(450);
  expect(fetcher.mock.calls[2][0]).toContain('/api/search?');
  expect(ui.results.hidden).toBe(true);
  input(ui.destination,'a');
  expect(ui.results.hidden).toBe(true);
});
