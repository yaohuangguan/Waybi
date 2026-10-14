import test from 'node:test';
import assert from 'node:assert/strict';
import { configuredOsrmRoute, fetchOsrmFallback } from '../src/osrm_fallback.ts';
import { routeOptions } from '../src/routes.ts';

const from: [number,number] = [174.76,-36.85];
const to: [number,number] = [174.79,-36.87];
const sample = { code:'Ok', routes:[{
  duration:80, distance:900, geometry:{coordinates:[from,to]}, legs:[{steps:[]}]
}] };

test('managed OSRM routes across driving, walking and cycling; credential only for owned provider',()=>{
  const env={WAYBI_OSRM_URL:'https://router.example.test/osrm/',WAYBI_OSRM_TOKEN:'test-secret'};
  for (const [mode,profile] of [['DRIVE','driving'],['WALK','walking'],['BICYCLE','cycling']]) {
    const req=configuredOsrmRoute(env,[from,to],mode);
    assert.equal(req.kind,'managed');
    assert.equal(req.url.hostname,'router.example.test');
    assert.ok(req.url.pathname.includes('/osrm/route/v1/'+profile+'/'));
    assert.equal(req.headers.authorization,'Bearer test-secret');
  }
  const community=configuredOsrmRoute({},[from,to],'DRIVE');
  assert.equal(community.kind,'public');
  assert.equal(community.headers.authorization,undefined);
  assert.equal(community.url.hostname,'routing.openstreetmap.de');
});

test('public emergency cutoff and unsafe remote URLs fail closed',()=>{
  for (const url of ['http://example.com','https://bob:pass@example.com',
    'https://example.com?auth=secret','https://example.com#fragment']) {
    assert.throws(()=>configuredOsrmRoute({WAYBI_OSRM_URL:url},[from,to],'DRIVE'));
  }
  assert.throws(()=>configuredOsrmRoute({WAYBI_DISABLE_PUBLIC_ROUTING:'true'},[from,to],'DRIVE'),/temporarily unavailable/);
});

test('in-flight route requests are coalesced with short caching',async()=>{
  let called=0;
  const fetcher=async (_url: any, _init: any)=>{
    called++;
    return Response.json(sample);
  };
  const env={WAYBI_OSRM_URL:'https://router.example.test'};
  const [a,b]=await Promise.all([
    fetchOsrmFallback(env,[from,to],'DRIVE',{},fetcher),
    fetchOsrmFallback(env,[from,to],'DRIVE',{},fetcher),
  ]);
  assert.equal(called,1);
  assert.deepEqual(a,b);
  const c=await fetchOsrmFallback(env,[from,to],'DRIVE',{},fetcher);
  assert.equal(called,1);
  assert.deepEqual(a,c);
});

test('provider failures do not produce a fabricated success route',async()=>{
  const bad=async()=>new Response('unavailable',{status:503});
  await assert.rejects(fetchOsrmFallback({WAYBI_OSRM_URL:'https://bad.example'},[from,to],'DRIVE',{},bad),/503/);
});

test('routeOptions uses configured managed OSRM without mobile client change',async()=>{
  const original=globalThis.fetch;
  let destination='';
  globalThis.fetch=async(url)=>{
    destination=String(url);
    return Response.json(sample);
  };
  try {
    const actual=await routeOptions(from,to,{WAYBI_OSRM_URL:'https://router.example.test'},
      [],['DRIVE'],()=>{},{forceIndependent:true});
    assert.equal(actual.provider,'independent');
    assert.equal(actual.options.length,1);
    assert.equal(new URL(destination).hostname,'router.example.test');
  } finally {globalThis.fetch=original;}
});

test('public cutoff rejects detours rather than sending exclusions to an unlicensed server',async()=>{
  const previous=globalThis.fetch;
  let upstream=0;
  globalThis.fetch=async()=>{upstream++;return Response.json(sample);};
  try {
    await assert.rejects(routeOptions(from,to,
      {WAYBI_DISABLE_PUBLIC_ROUTING:'true'},[],['DRIVE'],()=>{},
      {forceIndependent:true,exclusions:[{lon:174.77,lat:-36.86,heading:90}]}),
      /No routes available/);
    assert.equal(upstream,0);
  } finally {globalThis.fetch=previous;}
});
