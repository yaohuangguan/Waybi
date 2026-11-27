import { expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

const mocks=vi.hoisted(()=>({
  map: new Proxy({} as Record<string,any>,{get(target,key:string){return target[key]??=vi.fn().mockResolvedValue(undefined);}}),
}));
vi.mock('../src/waybi-map',()=>({WaybiMapAdapter: class {constructor(){return mocks.map;}}}));

function page() {
  const html=readFileSync('index.html','utf8');
  document.body.innerHTML=html.match(/<body[^>]*>([\s\S]*?)<\/body>/)![1].replace(/<script[\s\S]*?<\/script>/g,'');
}
it('accepts a valid overseas GPS fix and rejects invalid coordinates', async () => {
  vi.useFakeTimers(); page();
  let watch: PositionCallback | undefined;
  Object.defineProperty(navigator, 'geolocation', {configurable:true,value:{
    getCurrentPosition:(success:PositionCallback)=>success({coords:{latitude:-33.8688,longitude:151.2093,heading:null,speed:0,accuracy:5},timestamp:Date.now()} as GeolocationPosition),
    watchPosition:(success:PositionCallback)=>{watch=success;return 1;},clearWatch:vi.fn(),
  }});
  vi.stubGlobal('fetch',vi.fn().mockRejectedValue(new Error('offline')));
  await import('../src/main'); await vi.advanceTimersByTimeAsync(0);
  document.querySelector<HTMLButtonElement>('#gpsBadge')!.click();
  await vi.advanceTimersByTimeAsync(0);
  expect(mocks.map.setPosition).toHaveBeenCalledWith([151.2093,-33.8688],null);
  mocks.map.setPosition.mockClear();
  watch?.({coords:{latitude:100,longitude:151.2093,heading:null,speed:0,accuracy:5},timestamp:Date.now()} as GeolocationPosition);
  expect(mocks.map.setPosition).not.toHaveBeenCalled();
  vi.clearAllTimers();
});
it('real navigator boots offline, retains saved cameras and exposes settings without GPS', async () => {
  vi.useFakeTimers();
  page();
  localStorage.setItem('kiwi-cameras',JSON.stringify({cameras:[{id:'saved',name:'Saved camera',type:'Fixed speed camera',latitude:-36.8,longitude:174.7}],sourceUpdatedAt:'2026-10-01',checkedAt:null,syncStatus:'stale'}));
  vi.stubGlobal('fetch',vi.fn().mockRejectedValue(new Error('offline')));
  await import('../src/main');
  await vi.advanceTimersByTimeAsync(0);
  expect(document.querySelector('#dataStatus')?.textContent).toContain('cached');
  document.querySelector<HTMLButtonElement>('#settingsButton')!.click();
  expect(document.querySelector<HTMLElement>('#settingsOverlay')?.hidden).toBe(false);
  document.querySelector<HTMLButtonElement>('#zhButton')!.click();
  expect(document.documentElement.lang).toBe('zh-CN');
  expect(localStorage.getItem('waybi-ui-language')).toBe('zh');
  document.querySelector<HTMLButtonElement>('#closeSettings')!.click();
  expect(document.querySelector<HTMLElement>('#settingsOverlay')?.hidden).toBe(true);
  document.querySelector<HTMLButtonElement>('#gpsBadge')!.click();
  expect(document.querySelector('#gpsBadge')?.textContent).not.toBe('');
  document.querySelector<HTMLButtonElement>('#dataButton')!.click();
  expect(document.querySelector<HTMLElement>('#dataOverlay')?.hidden).toBe(false);
  document.querySelector<HTMLButtonElement>('#closeData')!.click();
  expect(document.querySelector<HTMLElement>('#dataOverlay')?.hidden).toBe(true);
  vi.clearAllTimers();
});
it('real navigator gets location, plans a selected place, starts and ends a trip', async () => {
  vi.useFakeTimers();
  page();
  let watch: PositionCallback | undefined;
  const coords={latitude:-36.8485,longitude:174.7633,heading:0,speed:0,accuracy:5,altitude:null,altitudeAccuracy:null};
  Object.defineProperty(navigator,'geolocation',{configurable:true,value:{
    getCurrentPosition:(success:PositionCallback)=>success({coords,timestamp:Date.now()} as GeolocationPosition),
    watchPosition:(success:PositionCallback)=>{watch=success;return 1;},clearWatch:vi.fn()
  }});
  const route={id:'drive',mode:'drive',provider:'waybi',durationSeconds:300,staticDurationSeconds:null,trafficDelaySeconds:null,distanceMeters:1000,description:'Direct',labels:[],warnings:[],coordinates:[[174.7633,-36.8485],[174.77,-36.84]],encodedPolyline:null,routeToken:null,traffic:{normal:0,slow:0,trafficJam:0},trafficIntervals:[],steps:[{location:[174.7633,-36.8485],name:'Queen Street',instruction:'Continue',maneuver:'depart',distance:1000,duration:300}],transit:[]};
  mocks.map.searchParking.mockResolvedValue([]);
  vi.stubGlobal('fetch',vi.fn(async (input:any)=>{
    const path=String(input);
    if(path.includes('/api/auth/'))return Response.json({},{status:401});
    if(path.includes('/api/suggest')||path.includes('/api/search?'))return Response.json([{id:1,label:'Airport',latitude:-36.84,longitude:174.77}]);
    if(path.includes('/api/route-options'))return Response.json({provider:'waybi',trafficAvailable:false,stopsApplied:0,options:[route]});
    if(path.includes('/api/speed-limit'))return Response.json({speedLimitKph:50});
    if(path.includes('/api/cameras'))return Response.json({cameras:[],sourceUpdatedAt:'2026-10-01',checkedAt:null,syncStatus:'stale'});
    return Response.json([]);
  }));
  await import('../src/main');
  await vi.advanceTimersByTimeAsync(0);
  document.querySelector<HTMLButtonElement>('#gpsBadge')!.click();
  await vi.advanceTimersByTimeAsync(0);
  const input=document.querySelector<HTMLInputElement>('#destinationInput')!;
  input.value='Airport';input.dispatchEvent(new Event('input'));
  await vi.advanceTimersByTimeAsync(450);
  document.querySelector<HTMLButtonElement>('#searchResults button')!.click();
  await vi.advanceTimersByTimeAsync(0);
  expect(document.querySelector('#tripTitle')?.textContent).toContain('Airport');
  expect(mocks.map.renderRoute).toHaveBeenCalled();
  document.querySelector<HTMLButtonElement>('#driveButton')!.click();
  await vi.advanceTimersByTimeAsync(0);
  expect(document.body.dataset.mode).toBe('navigation');
  watch?.({coords:{...coords,latitude:-36.847,longitude:174.764,speed:10},timestamp:Date.now()} as GeolocationPosition);
  await vi.advanceTimersByTimeAsync(0);
  document.querySelector<HTMLButtonElement>('#navVoiceChip')!.click();
  document.querySelector<HTMLButtonElement>('#navLanesChip')!.click();
  document.querySelector<HTMLButtonElement>('#navOverviewChip')!.click();
  document.querySelector<HTMLButtonElement>('#driveButton')!.click();
  await vi.advanceTimersByTimeAsync(0);
  expect(document.body.dataset.mode).toBe('explore');
  // Ending right after starting is not a "journey complete · 0 m".
  expect(document.querySelector<HTMLElement>('#journeySummaryOverlay')?.hidden).toBe(true);
  expect(document.querySelector('#toast')?.textContent).toBe('Navigation ended.');
  vi.clearAllTimers();
});

it('keeps navigating on the last route when a reroute fails, retries with backoff and ends only on request', async () => {
  vi.useFakeTimers();
  page();
  let watch: PositionCallback | undefined;
  const coords={latitude:-36.8485,longitude:174.7633,heading:0,speed:0,accuracy:5,altitude:null,altitudeAccuracy:null};
  Object.defineProperty(navigator,'geolocation',{configurable:true,value:{
    getCurrentPosition:(success:PositionCallback)=>success({coords,timestamp:Date.now()} as GeolocationPosition),
    watchPosition:(success:PositionCallback)=>{watch=success;return 1;},clearWatch:vi.fn()
  }});
  const route={id:'drive',mode:'drive',provider:'waybi',durationSeconds:300,staticDurationSeconds:null,trafficDelaySeconds:null,distanceMeters:1000,description:'Direct',labels:[],warnings:[],coordinates:[[174.7633,-36.8485],[174.77,-36.84]],encodedPolyline:null,routeToken:null,traffic:{normal:0,slow:0,trafficJam:0},trafficIntervals:[],steps:[{location:[174.77,-36.84],name:'Queen Street',instruction:'Arrive',maneuver:'arrive',distance:1000,duration:300}],transit:[]};
  mocks.map.searchParking.mockResolvedValue([]);
  let failRoutes=false; let routeCalls=0;
  vi.stubGlobal('fetch',vi.fn(async (input:any)=>{
    const path=String(input);
    if(path.includes('/api/auth/'))return Response.json({},{status:401});
    if(path.includes('/api/suggest')||path.includes('/api/search?'))return Response.json([{id:1,label:'Airport',latitude:-36.84,longitude:174.77}]);
    if(path.includes('/api/route-options')){routeCalls++; return failRoutes?Response.json({error:'Upstream timeout'},{status:503}):Response.json({provider:'waybi',trafficAvailable:false,stopsApplied:0,options:[route]});}
    if(path.includes('/api/cameras'))return Response.json({cameras:[],sourceUpdatedAt:'2026-10-01',checkedAt:null,syncStatus:'stale'});
    return Response.json([]);
  }));
  await import('../src/main');
  await vi.advanceTimersByTimeAsync(0);
  document.querySelector<HTMLButtonElement>('#gpsBadge')!.click();
  await vi.advanceTimersByTimeAsync(0);
  const input=document.querySelector<HTMLInputElement>('#destinationInput')!;
  input.value='Airport';input.dispatchEvent(new Event('input'));
  await vi.advanceTimersByTimeAsync(450);
  document.querySelector<HTMLButtonElement>('#searchResults button')!.click();
  await vi.advanceTimersByTimeAsync(0);
  document.querySelector<HTMLButtonElement>('#driveButton')!.click();
  await vi.advanceTimersByTimeAsync(0);
  expect(document.body.dataset.mode).toBe('navigation');
  failRoutes=true; const before=routeCalls;
  // ~400 m off the route, with fresh GPS fixes every 800 ms.
  for (let i=0;i<5;i++) {
    watch?.({coords:{...coords,latitude:-36.8485,longitude:174.7588+i*0.00001},timestamp:Date.now()} as GeolocationPosition);
    await vi.advanceTimersByTimeAsync(800);
  }
  expect(document.body.dataset.mode).toBe('navigation');
  expect(document.querySelector<HTMLElement>('#journeySummaryOverlay')?.hidden).toBe(true);
  const status=document.querySelector<HTMLElement>('#navStatus')!;
  expect(status.hidden).toBe(false);
  expect(status.textContent).toContain('following your last route');
  // First attempt + one backoff retry at ~2 s: not one request per GPS fix.
  expect(routeCalls-before).toBeLessThanOrEqual(2);
  await vi.advanceTimersByTimeAsync(4100);
  expect(routeCalls-before).toBe(3);
  expect(document.body.dataset.mode).toBe('navigation');
  // Recovery: the next retry succeeds and clears the status.
  failRoutes=false;
  await vi.advanceTimersByTimeAsync(8100);
  expect(status.hidden).toBe(true);
  document.querySelector<HTMLButtonElement>('#navEndButton')!.click();
  expect(document.body.dataset.mode).toBe('explore');
  vi.clearAllTimers();
});
