import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign, createVerify, createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { handleAccount } from '../src/auth.ts';
import { appleAuthConfig, verifyAppleIdentity, nonceHash, appleClientSecret,
  sealAppleToken, openAppleToken, refreshAppleAuthorizations } from '../src/apple_auth.ts';

const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 });
const ec = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const envKeys = { APPLE_AUTH_TEAM_ID: 'TESTTEAM00', APPLE_AUTH_KEY_ID: 'TESTKEY000',
  APPLE_AUTH_PRIVATE_KEY: ec.privateKey.export({type:'pkcs8',format:'pem'}).toString(), APPLE_AUTH_TOKEN_KEY: 'a'.repeat(64) };
const jwk = {...rsa.publicKey.export({format:'jwk'}),kid:'apple-test',alg:'RS256',use:'sig'};
const rawNonce = 'n'.repeat(64);
const nonce = createHash('sha256').update(rawNonce).digest('hex');
function jwt(overrides = {}) {
  const head = Buffer.from(JSON.stringify({alg:'RS256',kid:'apple-test'})).toString('base64url');
  const body = Buffer.from(JSON.stringify({iss:'https://appleid.apple.com',aud:'co.waybi.ios',
    sub:'apple-user',email:'relay@privaterelay.appleid.com',email_verified:'true',nonce,
    iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,...overrides})).toString('base64url');
  const data = head+'.'+body;
  return data+'.'+createSign('RSA-SHA256').update(data).sign(rsa.privateKey).toString('base64url');
}
function database() {
  const sql = new DatabaseSync(':memory:'); sql.exec('PRAGMA foreign_keys=ON');
  const root = new URL('../../../migrations/',import.meta.url);
  for(const f of readdirSync(root).filter(f=>/^\d+.*\.sql$/.test(f)).sort())sql.exec(readFileSync(new URL(f,root),'utf8'));
  const db:any={prepare(query:string){return {bind(...values:any[]){return {sql:query,values,
    async first(){return sql.prepare(query).get(...values)||null;},
    async all(){return {results:sql.prepare(query).all(...values)};},
    async run(){return sql.prepare(query).run(...values);}
  };}};},async batch(items:any[]){sql.exec('BEGIN');try{const results=items.map(s=>sql.prepare(s.sql).run(...s.values));sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}}};
  return {sql,env:{USER_DB:db,...envKeys}};
}
function call(path:string, body:any, token?:string) {
  return new Request('https://waybi.co/api/auth/'+path,{method:'POST',headers:{'content-type':'application/json',
    'x-waybi-client':'mobile',...(token?{cookie:'waybi_session='+token}:{})},body:JSON.stringify(body)});
}
function authorize(code='first', identity=jwt()){return {identityToken:identity,authorizationCode:code,rawNonce};}
function mockApple(identity=jwt()) {
  const used=new Set<string>(); let revokeOk=true, withdrawn=false, exchanges=0, keyCalls=0;
  const fetcher:typeof fetch=async(url,init)=>{
    const u=String(url);
    if(u.endsWith('/auth/keys')){keyCalls++;return Response.json({keys:[jwk]});}
    assert.equal(init?.headers['content-type'],'application/x-www-form-urlencoded');
    const fields=new URLSearchParams(init.body as URLSearchParams);
    const secret=fields.get('client_secret').split('.');
    assert.equal(JSON.parse(Buffer.from(secret[1],'base64url').toString()).sub,'co.waybi.ios');
    assert.equal(createVerify('SHA256').update(secret[0]+'.'+secret[1]).verify({key:ec.publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(secret[2],'base64url')),true);
    if(u.endsWith('/auth/revoke'))return new Response(null,{status:revokeOk?200:503});
    assert.equal(u,'https://appleid.apple.com/auth/token');
    if(fields.get('grant_type')==='refresh_token')return withdrawn?Response.json({error:'invalid_grant'},{status:400}):Response.json({access_token:'access'});
    exchanges++;const code=fields.get('code');
    if(used.has(code))return Response.json({error:'invalid_grant'},{status:400});
    used.add(code);return Response.json({id_token:identity,refresh_token:'private-refresh-token'});
  };
  return {fetcher,setRevoke(ok:boolean){revokeOk=ok;},withdraw(){withdrawn=true;},get exchanges(){return exchanges;},get keyCalls(){return keyCalls;}};
}
test('Apple identity verifies signature, issuer, audience, expiry and nonce; client secret is ES256',async()=>{
  const mock=mockApple();assert.equal(await nonceHash(rawNonce),nonce);
  assert.equal((await verifyAppleIdentity(jwt(),'co.waybi.ios',nonce,{fetcher:mock.fetcher})).sub,'apple-user');
  for(const claims of [{aud:'other'},{iss:'https://attacker.test'},{exp:0},{nonce:'wrong'},{iat:Date.now()/1000+120}])
    await assert.rejects(verifyAppleIdentity(jwt(claims),'co.waybi.ios',nonce,{fetcher:mock.fetcher}));
  const valid=jwt(); const parts=valid.split('.');
  parts[1]=Buffer.from(JSON.stringify({...JSON.parse(Buffer.from(parts[1],'base64url').toString()),sub:'attacker'})).toString('base64url');
  await assert.rejects(verifyAppleIdentity(parts.join('.'),'co.waybi.ios',nonce,{fetcher:mock.fetcher}));
  const missing=jwt().split('.');
  missing[0]=Buffer.from(JSON.stringify({alg:'RS256',kid:'unknown-key'})).toString('base64url');
  for(let i=0;i<3;i++)await assert.rejects(verifyAppleIdentity(missing.join('.'),'co.waybi.ios',nonce,{fetcher:mock.fetcher}));
  assert.equal(mock.keyCalls,1,'unknown key ids must not repeatedly fetch Apple keys');
  const secret=await appleClientSecret(envKeys);
  assert.equal(JSON.parse(Buffer.from(secret.split('.')[0],'base64url').toString()).alg,'ES256');
  assert.equal(appleAuthConfig({}).ready,false);
});
test('Apple refresh credentials are authenticated-encrypted and reject a different storage key',async()=>{
  const sealed=await sealAppleToken(envKeys,'private-refresh-token');
  assert.equal(sealed.includes('private-refresh-token'),false);
  assert.equal(await openAppleToken(envKeys,sealed),'private-refresh-token');
  await assert.rejects(openAppleToken({...envKeys,APPLE_AUTH_TOKEN_KEY:'b'.repeat(64)},sealed));
});
test('Apple signup, repeated login, code replay rejection and deletion revocation are end to end',async()=>{
  const {sql,env}=database(),mock=mockApple(),previous=globalThis.fetch;globalThis.fetch=mock.fetcher;
  try{
    const response=await handleAccount(call('apple',authorize()),env);assert.equal(response.status,200);
    const profile:any=await response.json();assert.deepEqual(profile.user.providers,['apple']);
    const cookie=response.headers.get('set-cookie').match(/waybi_session=([a-f0-9]{64})/)[1];
    const stored:any=sql.prepare('SELECT * FROM apple_identities').get();
    assert.equal(await openAppleToken(env,stored.refresh_token),'private-refresh-token');
    assert.equal((await handleAccount(call('apple',authorize()),env)).status,401);
    assert.equal((await handleAccount(call('apple',authorize('second')),env)).status,200);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM users').get().c,1);
    mock.setRevoke(false);
    assert.equal((await handleAccount(call('delete',{email:profile.user.email,confirmation:'DELETE'},cookie),env)).status,503);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM users').get().c,1);
    mock.setRevoke(true);
    assert.equal((await handleAccount(call('delete',{email:profile.user.email,confirmation:'DELETE'},cookie),env)).status,200);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM apple_identities').get().c,0);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM sessions').get().c,0);
  }finally{globalThis.fetch=previous;sql.close();}
});
test('Apple verified email never takes over an existing account; private-relay linking requires a session',async()=>{
  const {sql,env}=database(),previous=globalThis.fetch;
  sql.prepare('INSERT INTO users VALUES(?,?,?,?,?)').run('owner','relay@privaterelay.appleid.com','','',0);
  sql.prepare('INSERT INTO profiles(user_id,language,voice_enabled) VALUES(?,?,?)').run('owner','en',1);
  const token='c'.repeat(64);
  sql.prepare('INSERT INTO sessions VALUES(?,?,?)').run(createHash('sha256').update(token).digest('hex'),'owner',Date.now()+60000);
  try{
    globalThis.fetch=mockApple().fetcher;
    assert.equal((await handleAccount(call('apple',authorize()),env)).status,409);
    assert.equal((await handleAccount(call('apple/link',authorize('link')),env)).status,401);
    const hidden=jwt({email:'different@privaterelay.appleid.com'});
    globalThis.fetch=mockApple(hidden).fetcher;
    assert.equal((await handleAccount(call('apple/link',authorize('link',hidden),token),env)).status,200);
    assert.equal(sql.prepare('SELECT user_id FROM apple_identities').get().user_id,'owner');
    sql.prepare('UPDATE apple_identities SET checked_at=0').run();
    await refreshAppleAuthorizations(env,Date.now(),async()=>Response.json({error:'temporarily_unavailable'},{status:503}));
    assert.equal(sql.prepare('SELECT count(*) AS c FROM sessions').get().c,1,'an outage must not revoke sessions');
    assert.equal(sql.prepare('SELECT revoked_at FROM apple_identities').get().revoked_at,null);
    const withdrawn=mockApple();withdrawn.withdraw();
    await refreshAppleAuthorizations(env,Date.now(),withdrawn.fetcher);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM sessions').get().c,0);
    assert.ok(sql.prepare('SELECT revoked_at FROM apple_identities').get().revoked_at);
    assert.equal(sql.prepare('SELECT count(*) AS c FROM users').get().c,1);
  }finally{globalThis.fetch=previous;sql.close();}
});
