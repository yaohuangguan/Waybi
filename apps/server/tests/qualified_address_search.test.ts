import test from 'node:test';
import assert from 'node:assert/strict';
import { parseNumberedStreetQuery, parseStreetQuery } from '../src/search/numbered_street_query.ts';
import { linzNzAddressProvider } from '../src/search/regional/linz_nz_addresses.ts';
import { aucklandCouncilAddressProvider } from '../src/search/regional/auckland_council.ts';
import { mergeAndRankSearchResults, needsAddressEnrichment, interpolateNumberedAddress } from '../src/search/search_orchestrator.ts';

test('full addresses retain suburb, city and postal code with or without commas', () => {
  for (const query of ['16 Queen Street, Ōtāhuhu, Auckland 1062', '16 Queen St Ōtāhuhu, Auckland 1062']) {
    const parsed = parseNumberedStreetQuery(query);
    assert.deepEqual(parsed, {number:'16',roadName:'Queen',roadType:'STREET',locality:'Ōtāhuhu, Auckland 1062'});
  }
  assert.equal(parseNumberedStreetQuery('2/16 Queen St, Ōtāhuhu').number, '2/16');
  assert.equal(parseStreetQuery('Queen Street, Ōtāhuhu, Auckland 1062').locality, 'Ōtāhuhu, Auckland 1062');
});

const place = (number, locality, lat = -36.94) => ({id:`${number}:${locality}`,provider:'regional:test',name:`${number} Queen Street`,address:`${number} Queen Street, ${locality}, Auckland, New Zealand`,latitude:lat,longitude:174.84});
test('a wrong-town exact house is not a useful match and cannot suppress enrichment', () => {
  const q='16 Queen Street, Ōtāhuhu, Auckland 1062';
  const wrong=place(16,'Pukekohe');
  const right=place(16,'Otahuhu');
  assert.equal(needsAddressEnrichment([wrong],q),true);
  assert.equal(needsAddressEnrichment([right],q),false);
  assert.deepEqual(mergeAndRankSearchResults([[wrong,right]],q,[174.90,-37.2]).map(p=>p.id),[right.id]);
  assert.deepEqual(mergeAndRankSearchResults([[wrong]],q,[174.9,-37.2]),[]);
  assert.equal(interpolateNumberedAddress([place(14,'Pukekohe'),place(18,'Pukekohe')],q),null);
});

test('LINZ constrains locality before the record cap and uses the complete road-name field', async () => {
  const parsed=parseStreetQuery('Queen Street, Ōtāhuhu, Auckland 1062');
  let where='';
  const results=await linzNzAddressProvider.search({parsed,fetcher:async url=>{
    const u=new URL(url);where=u.searchParams.get('where');
    assert.match(where,/full_road_name_ascii='Queen Street'/);
    assert.match(where,/suburb_locality_ascii.*OTAHUHU/);
    assert.match(where,/town_city_ascii.*AUCKLAND/);
    return Response.json({features:[{properties:{address_id:1,road_id:5,full_address:'16 Queen Street',suburb_locality:'Ōtāhuhu',town_city:'Auckland'},geometry:{coordinates:[174.84,-36.94]}}]});
  }});
  assert.equal(results.length,1);assert.equal(results[0].latitude,-36.94);
  assert.match(results[0].address,/Auckland/i);assert.equal(results[0].resultType,'street');
});

test('Council adds suburb and postcode filters before limiting long repeated streets', async () => {
  for (const query of ['16 Queen Street, Ōtāhuhu, Auckland 1062', '16 Queen Street Ōtāhuhu Auckland 1062 New Zealand']) {
  assert.equal(needsAddressEnrichment([place(16,'Otahuhu')],query),false);
  await aucklandCouncilAddressProvider.search({parsed:parseNumberedStreetQuery(query),fetcher:async url=>{
    const where=new URL(url).searchParams.get('where');
    assert.match(where,/Locality\)='ŌTĀHUHU'/);assert.match(where,/Locality\)='OTAHUHU'/);
    assert.match(where,/FullAddress LIKE '%1062'/);
    return Response.json({features:[]});
  }});
  }
});

test('LINZ preserves indexed Mc names and escaped apostrophes', async () => {
  for(const [query,expected] of [['16 mckenzie street','McKenzie Street'],["16 o’connell street","O''Connell Street"]]) {
    await linzNzAddressProvider.search({parsed:parseNumberedStreetQuery(query),fetcher:async url=>{
      assert.ok(new URL(url).searchParams.get('where').includes(`full_road_name_ascii='${expected}'`));
      return Response.json({features:[]});
    }});
  }
});

test('a street coordinate never averages Queen Streets in different towns', async () => {
  const features=[
    {properties:{address_id:1,road_id:10,full_address_ascii:'16 Queen Street',suburb_locality_ascii:'Otahuhu',town_city_ascii:'Auckland'},geometry:{coordinates:[174.84,-36.94]}},
    {properties:{address_id:2,road_id:20,full_address_ascii:'16 Queen Street',suburb_locality_ascii:'Pukekohe',town_city_ascii:'Auckland'},geometry:{coordinates:[174.90,-37.20]}},
  ];
  const results=await linzNzAddressProvider.search({parsed:parseStreetQuery('Queen Street'),fetcher:async()=>Response.json({features})});
  assert.equal(results.length,2);assert.notEqual(results[0].id,results[1].id);
  assert.deepEqual(results.map(p=>[p.longitude,p.latitude]),[[174.84,-36.94],[174.90,-37.20]]);
});

test('unit numbers keep their slash in the authoritative address query', async () => {
  await linzNzAddressProvider.search({parsed:parseNumberedStreetQuery('2/16 Queen Street, Ōtāhuhu'),fetcher:async url=>{
    assert.match(new URL(url).searchParams.get('where'),/full_address_number\)='2\/16'/);
    assert.match(new URL(url).searchParams.get('where'),/address_number=16/);
    return Response.json({features:[]});
  }});
});
