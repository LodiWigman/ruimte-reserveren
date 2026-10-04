// Six bounded read-only requests. No real account, password, row or write RPC is used.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
const html=await readFile('index.html','utf8');
const base=html.match(/const SUPABASE_URL = '([^']+)'/)[1];
const key=html.match(/const SUPABASE_ANON_KEY = '([^']+)'/)[1];
assert.equal(base,'https://oappvdfjyvbmvqrjvnmv.supabase.co');
const results=[];
const record=async(name,url,options,allowed)=>{
  const response=await fetch(url,{...options,signal:AbortSignal.timeout(15000)});
  // Do not retain any response body; even unexpected responses cannot collect user rows.
  await response.body?.cancel();
  results.push({name,status:response.status,expected:allowed.includes(response.status)});
};
await record('No API key: zero-row profile request',base+'/rest/v1/profiles?select=id&limit=0',{},[401]);
await record('Public key cannot read profiles',base+'/rest/v1/profiles?select=id&limit=0',{headers:{apikey:key}},[401,403]);
const segment=data=>Buffer.from(JSON.stringify(data)).toString('base64url');
const claims={sub:'user_securityProbe',sid:'sess_securityProbe',role:'authenticated',iss:'https://alert-bat-50.clerk.accounts.dev',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+60};
for(const algorithm of ['none','HS256','RS256']){
  const token=segment({alg:algorithm,typ:'JWT'})+'.'+segment(claims)+'.'+(algorithm==='none'?'':'invalidsignature');
  await record('Invalid '+algorithm+' token denied',base+'/rest/v1/profiles?select=id&limit=0',{headers:{apikey:key,authorization:'Bearer '+token}},[401,403]);
}
await record('Unauthenticated read-only occupancy RPC denied',base+'/rest/v1/rpc/han_occupancy',{
  method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({from_date:'2099-01-01',to_date:'2099-01-01'})
},[401,403]);
await mkdir('test-results',{recursive:true});
await writeFile('test-results/public-security-probes.json',JSON.stringify({date:new Date().toISOString(),scope:'Only denial with missing or invalid credentials. Not proof of correct valid-token expiry, issuer or revocation.',results},null,2));
for(const row of results)console.log((row.expected?'DENIED':'UNEXPECTED')+' '+row.status+' '+row.name);
if(results.some(r=>!r.expected))process.exitCode=1;
