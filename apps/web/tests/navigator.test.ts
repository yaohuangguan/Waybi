import { expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

const mocks=vi.hoisted(()=>({
  map: new Proxy({} as Record<string,any>,{get(target,key:string){return target[key]??=vi.fn().mockResolvedValue(undefined);}}),
}));
vi.mock('../src/google-map',()=>({GoogleMapAdapter: class {constructor(){return mocks.map;}}}));
vi.mock('../src/google-routes',()=>({computeGoogleRoute:vi.fn(),computeGoogleRoutes:vi.fn(),enrichRouteLanes:(route:any)=>route}));
import { computeGoogleRoutes } from '../src/google-routes';

function page() {
  const html=readFileSync('index.html','utf8');
  document.body.innerHTML=html.match(/<body[^>]*>([\s\S]*?)<\/body>/)![1].replace(/<script[\s\S]*?<\/script>/g,'');
}
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
  expect(localStorage.getItem('kiwi-language')).toBe('zh');
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
  const googleRoutes=await import('../src/google-routes');
  vi.mocked(googleRoutes.computeGoogleRoutes).mockResolvedValue([{coordinates:route.coordinates,distance:1000,duration:300,steps:route.steps}] as any);
  vi.stubGlobal('fetch',vi.fn(async (input:any)=>{
    const path=String(input);
    if(path.includes('/api/auth/'))return Response.json({},{status:401});
    if(path.includes('/api/config'))return Response.json({googleMapsApiKey:'test-only',googleMapId:null});
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
  expect(document.querySelector<HTMLElement>('#journeySummaryOverlay')?.hidden).toBe(false);
  document.querySelector<HTMLButtonElement>('#journeySummaryOverlay button')!.click();
  expect(document.querySelector<HTMLElement>('#journeySummaryOverlay')?.hidden).toBe(true);
  vi.clearAllTimers();
});
