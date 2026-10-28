import { reserveGoogleSearch, sendGoogleSearchAlerts } from './google_search_budget.ts';

const scriptJson = (value) => JSON.stringify(value).replaceAll('<','\\u003c');
export function googlePlacePickerHtml(query: string, language: string, key: string, near: number[] | null) {
  const zh = language === 'zh';
  const config = scriptJson({query,zh,key,near});
  return `<!doctype html><html lang="${zh?'zh-CN':'en'}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>Waybi Search</title>
<style>body{margin:0;background:#f8fbef;color:#23351d;font:17px -apple-system,BlinkMacSystemFont,sans-serif}header{padding:18px 16px 12px;position:sticky;top:0;background:#f8fbef;z-index:2}form{display:flex;gap:8px}input{min-width:0;flex:1;border:1px solid #cad7bb;border-radius:15px;padding:14px;font:inherit;background:white}button{border:0;border-radius:14px;padding:12px;background:#d0f58a;color:#23351d;font:inherit}#status{padding:12px 18px;color:#64705b;font-size:14px}#results{margin:0 10px}footer{padding:20px 16px}footer button{background:white;border:1px solid #cad7bb;width:100%}gmp-place-search{width:100%;color-scheme:light;--gmp-mat-color-primary:#496b32;--gmp-mat-color-on-surface:#23351d;--gmp-mat-color-surface:#fff}</style>
<header><form id="form"><input id="query" autocomplete="street-address" enterkeyhint="search" aria-label="${zh?'地址或地点':'Address or place'}" placeholder="${zh?'地址、商店或地点':'Address, business or place'}"><button>${zh?'搜索':'Search'}</button></form></header><div id="status"></div><main id="results"></main><footer><button id="free">${zh?'使用免费地址搜索':'Use alternative search'}</button></footer>
<script>
const config=${config};
const input=document.getElementById('query'),status=document.getElementById('status');input.value=config.query;
let busy=false,finished=false,timeout,generation=0;
function finish(result){if(finished)return;finished=true;clearTimeout(timeout);result.nonce=location.hash.slice(1);const body=JSON.stringify(result);if(window.webkit?.messageHandlers?.waybiPlaces)window.webkit.messageHandlers.waybiPlaces.postMessage(body);else if(window.WaybiPlaces)window.WaybiPlaces.postMessage(body);else{document.body.dataset.result=body;status.textContent=config.zh?'地点已选定，请返回 Waybi':'Place selected. Return to Waybi';}}
function fallback(){finish({status:'fallback',query:input.value.trim()});}
document.getElementById('free').onclick=fallback;
window.gm_authFailure=fallback;
let sdk;
function loadSdk(){return sdk??=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://maps.googleapis.com/maps/api/js?key='+encodeURIComponent(config.key)+'&loading=async&libraries=places&v=weekly&language='+(config.zh?'zh-CN':'en')+'&callback=waybiMapsReady';s.onerror=reject;window.waybiMapsReady=resolve;document.head.append(s);});}
async function search(){
 const query=input.value.trim();if(query.length<2||query.length>120||busy||finished)return;
 busy=true;const current=++generation;clearTimeout(timeout);status.textContent=config.zh?'正在搜索…':'Searching…';
 timeout=setTimeout(fallback,18000);
 try{
  const response=await fetch('/api/search/google/reserve',{method:'POST',headers:{'x-waybi-client':'web'}});
  const allowance=await response.json();if(!response.ok||!allowance.allowed){fallback();return;}
  await loadSdk();await google.maps.importLibrary('places');if(finished||current!==generation)return;
  const list=document.createElement('gmp-place-search');list.setAttribute('selectable','');
  const request=document.createElement('gmp-place-text-search-request');request.setAttribute('text-query',query);request.setAttribute('max-result-count','10');
  if(config.near)request.locationBias={center:{lat:config.near[1],lng:config.near[0]},radius:50000};
  const content=document.createElement('template');content.setAttribute('slot','details-item');content.content.append(document.createElement('gmp-place-name'),document.createElement('gmp-place-address'));
  list.append(request,content,document.createElement('gmp-place-attribution'));
  list.addEventListener('gmp-load',()=>{if(current!==generation)return;clearTimeout(timeout);if(!list.places?.length){fallback();return;}status.textContent='';busy=false;});
  list.addEventListener('gmp-error',()=>{if(current===generation)fallback();});
  list.addEventListener('gmp-select',event=>{if(current!==generation)return;const place=event.place;const lat=place?.location?.lat(),lng=place?.location?.lng();if(!place?.id||!Number.isFinite(lat)||!Number.isFinite(lng)){fallback();return;}finish({status:'selected',id:place.id,latitude:lat,longitude:lng,query});});
  document.getElementById('results').replaceChildren(list);
 }catch(_){if(current===generation)fallback();}
 finally{if(current===generation)busy=false;}
}
document.getElementById('form').onsubmit=event=>{event.preventDefault();search();};
if(!config.key)fallback();else if(input.value.trim().length>=2)search();else input.focus();
</script></html>`;
}

export async function handleGooglePlacePicker(request: Request, env: any, ctx?: Pick<ExecutionContext,'waitUntil'>) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/search/google')) return null;
  const enabled = env.WAYBI_GOOGLE_SEARCH_ENABLED === 'true' && !!env.WAYBI_GOOGLE_PLACES_UI_KEY && !!env.USER_DB && !!env.WAYBI_RESEND_API_KEY;
  if (url.pathname === '/api/search/google/reserve') {
    if (request.method !== 'POST' || request.headers.get('origin') !== url.origin || request.headers.get('x-waybi-client') !== 'web') return new Response(null,{status:403});
    const result = enabled ? await reserveGoogleSearch(env.USER_DB) : {allowed:false,reason:'disabled'};
    if (enabled) ctx?.waitUntil(sendGoogleSearchAlerts(env));
    return Response.json(result,{headers:{'cache-control':'no-store'}});
  }
  if (url.pathname !== '/api/search/google' || request.method !== 'GET') return new Response(null,{status:404});
  const query = (url.searchParams.get('q') || '').slice(0,120);
  const pair = (url.searchParams.get('near') || '').split(',').map(Number);
  const near = pair.length===2 && pair.every(Number.isFinite) && Math.abs(pair[0])<=180 && Math.abs(pair[1])<=90 ? pair : null;
  return new Response(googlePlacePickerHtml(query,url.searchParams.get('lang') || 'en',enabled?env.WAYBI_GOOGLE_PLACES_UI_KEY:'',near),{headers:{
    'content-type':'text/html; charset=utf-8','cache-control':'no-store','x-robots-tag':'noindex, nofollow',
    'referrer-policy':'strict-origin-when-cross-origin','x-content-type-options':'nosniff',
  }});
}
