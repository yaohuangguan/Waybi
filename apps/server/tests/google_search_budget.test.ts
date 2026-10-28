import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {reserveGoogleSearch,googleSearchPeriods,sendGoogleSearchAlerts} from '../src/google_search_budget.ts';
import {handleGooglePlacePicker,googlePlacePickerHtml} from '../src/google_place_picker.ts';

const now=new Date('2026-10-29T12:00:00Z');
function database(){
  const sql=new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('../../../migrations/0018_google_search_budget.sql',import.meta.url),'utf8'));
  const db={prepare(query){const stmt=sql.prepare(query);return{bind(...args){return{first:async()=>stmt.get(...args),run:async()=>stmt.run(...args),all:async()=>({results:stmt.all(...args)})};},all:async()=>({results:stmt.all()})};}};
  return{sql,db};
}
test('the 9990th slot is allowed once under a burst, then every request falls back',async()=>{
  const{sql,db}=database();sql.exec("INSERT INTO google_search_budget VALUES('2026-10',9989,'2026-10-29',10)");
  const results=await Promise.all(Array.from({length:40},()=>reserveGoogleSearch(db,now)));
  assert.equal(results.filter(r=>r.allowed).length,1);
  assert.equal(sql.prepare('SELECT calls FROM google_search_budget').get().calls,9990);
  assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM google_search_alerts').get().n,1);
  assert.equal(results.filter(r=>!r.allowed).every(r=>r.reason==='monthly_limit'),true);
});
test('quota is shared across days and resets in the billing month, including Pacific midnight',async()=>{
  const{sql,db}=database();sql.exec("INSERT INTO google_search_budget VALUES('2026-10',5000,'2026-10-28',4000)");
  const result=await reserveGoogleSearch(db,now);assert.equal(result.allowed,true);assert.equal(result.monthly,5001);assert.equal(result.daily,1);
  assert.equal(googleSearchPeriods(new Date('2026-11-01T06:59:00Z')).month,'2026-10');
  assert.equal(googleSearchPeriods(new Date('2026-11-01T07:00:00Z')).month,'2026-11');
  assert.equal((await reserveGoogleSearch(db,new Date('2026-11-01T07:00:00Z'))).monthly,1);
});
test('missing or failed storage never permits a paid request',async()=>{
  assert.equal((await reserveGoogleSearch(null,now)).allowed,false);
  assert.equal((await reserveGoogleSearch({prepare(){throw Error('offline');}},now)).allowed,false);
});
test('one owner alert is sent with a stable idempotency key and no address query',async()=>{
  const{sql,db}=database();sql.exec("INSERT INTO google_search_alerts(period) VALUES('2026-10')");
  const sent=[];const env={USER_DB:db,WAYBI_RESEND_API_KEY:'test-mail'};
  const fetcher=async(url,init)=>{sent.push({url,init,body:JSON.parse(init.body)});return Response.json({id:'test-message'});};
  await Promise.all([sendGoogleSearchAlerts(env,now,fetcher),sendGoogleSearchAlerts(env,now,fetcher)]);
  await sendGoogleSearchAlerts(env,now,fetcher);assert.equal(sent.length,1);
  assert.equal(sent[0].init.headers['Idempotency-Key'],'waybi-google-search-budget-2026-10');
  assert.deepEqual(sent[0].body.to,['moviegoer24@gmail.com']);assert.match(sent[0].body.text,/9990/);
  assert.equal(sql.prepare('SELECT status FROM google_search_alerts').get().status,'sent');
});
test('transient alerts back off and permanent credential failures do not retry',async()=>{
  const{sql,db}=database();sql.exec("INSERT INTO google_search_alerts(period) VALUES('2026-10')");
  const env={USER_DB:db,WAYBI_RESEND_API_KEY:'test'};let calls=0;
  await sendGoogleSearchAlerts(env,now,async()=>{calls++;return new Response(null,{status:503});});
  await sendGoogleSearchAlerts(env,now,async()=>{calls++;throw Error('Must back off');});assert.equal(calls,1);
  await sendGoogleSearchAlerts(env,new Date(now.getTime()+180000),async()=>{calls++;return new Response(null,{status:401});});
  assert.equal(sql.prepare('SELECT status FROM google_search_alerts').get().status,'failed');
});
test('picker refuses cross-origin quota consumption and emits no server secrets',async()=>{
  const{db}=database();const env={USER_DB:db,WAYBI_GOOGLE_SEARCH_ENABLED:'true',WAYBI_GOOGLE_PLACES_UI_KEY:'test-browser-key',WAYBI_RESEND_API_KEY:'never-render-mail-secret'};
  const bad=await handleGooglePlacePicker(new Request('https://waybi.co/api/search/google/reserve',{method:'POST',headers:{origin:'https://attacker.test','x-waybi-client':'web'}}),env);
  assert.equal(bad.status,403);
  const ok=await handleGooglePlacePicker(new Request('https://waybi.co/api/search/google/reserve',{method:'POST',headers:{origin:'https://waybi.co','x-waybi-client':'web'}}),env);
  assert.equal((await ok.json()).allowed,true);
  const page=await handleGooglePlacePicker(new Request('https://waybi.co/api/search/google?q='+encodeURIComponent('</script><script>alert(1)</script>')),env);
  const html=await page.text();assert.equal(html.includes('never-render-mail-secret'),false);
  assert.equal(html.includes('</script><script>alert(1)'),false);assert.match(html,/gmp-place-attribution/);
  assert.match(html,/fetch\('\/api\/search\/google\/reserve'/);
  assert.ok(html.indexOf('await response.json()')<html.indexOf('await loadSdk()'));
  assert.equal((await handleGooglePlacePicker(new Request('https://waybi.co/api/search/google/reserve',{method:'POST',headers:{origin:'https://waybi.co','x-waybi-client':'web'}}),{...env,WAYBI_RESEND_API_KEY:''})).status,200);
  assert.match(googlePlacePickerHtml('cafe','en','',null),/if\(!config.key\)fallback/);
});

test('a stale outbox reader cannot skip backoff or exceed six attempts',async()=>{
  const{sql,db}=database();sql.exec("INSERT INTO google_search_alerts(period,next_attempt) VALUES('2026-10',9999999999999)");
  // A worker selected this row before another worker set its retry delay.
  const stale={prepare(query){if(query.startsWith('SELECT period'))return{bind(){return{all:async()=>({results:[{period:'2026-10'}]})};}};return db.prepare(query);}};
  let calls=0;
  const env={USER_DB:stale,WAYBI_RESEND_API_KEY:'test'};
  const fetcher=async()=>{calls++;return new Response(null,{status:503});};
  await sendGoogleSearchAlerts(env,now,fetcher);assert.equal(calls,0);
  sql.exec('UPDATE google_search_alerts SET next_attempt=0,attempts=6');
  await sendGoogleSearchAlerts(env,now,fetcher);assert.equal(calls,0);
});
