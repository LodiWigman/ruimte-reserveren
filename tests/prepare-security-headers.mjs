// Generate verifiable static-host headers from the exact release bytes.
// --check never edits files and fails if the policy or integrity hashes are stale.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const check=process.argv.includes('--check');
const original=await readFile('index.html','utf8');
const lockedIntegrity=JSON.parse(await readFile('docs/security/browser-integrity.json','utf8'));
for(const [name,expected] of Object.entries(lockedIntegrity)){
  const bytes=await readFile('node_modules/.cache/han-test/'+name+'.js');
  if('sha384-'+createHash('sha384').update(bytes).digest('base64')!==expected)throw Error('Unreviewed browser dependency bytes: '+name);
}
let html=original;
for(const [url,file] of [
  ['https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js','supabase'],
  ['https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js','xlsx']
]){
  const bytes=await readFile('node_modules/.cache/han-test/'+file+'.js');
  const integrity=lockedIntegrity[file];
  html=html.replace(new RegExp('<script src="'+url.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'"[^>]*>'),`<script src="${url}" integrity="${integrity}" crossorigin="anonymous">`);
}
const script=html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
if(!script)throw Error('Exactly identified application script required');
if(/\s+on[a-z]+=["']/.test(html))throw Error('Inline handlers are forbidden');
const hash='sha256-'+createHash('sha256').update(script.replace(/\r\n/g,'\n')).digest('base64');
const clerkKey=html.match(/const CLERK_PUBLISHABLE_KEY = '([^']+)'/)[1];
const clerkDomain=Buffer.from(clerkKey.split('_')[2],'base64').toString().replace(/\$$/,'');
if(!/^[a-z0-9.-]+$/.test(clerkDomain))throw Error('Invalid Clerk hostname');
const csp=[
  "default-src 'none'", "base-uri 'none'", "object-src 'none'", "frame-ancestors 'none'", "form-action 'self'",
  `script-src '${hash}' https://${clerkDomain} https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js https://cdn.jsdelivr.net/npm/@clerk/localizations@4.20.0/ https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js https://challenges.cloudflare.com https://*.protect.clerk.com`,
  "script-src-attr 'none'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: https://img.clerk.com",
  `connect-src 'self' https://${clerkDomain} https://oappvdfjyvbmvqrjvnmv.supabase.co https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js https://clerk-telemetry.com https://*.clerk-telemetry.com https://*.protect.clerk.com`,
  "frame-src https://challenges.cloudflare.com https://*.protect.clerk.com",
  "worker-src 'self' blob:", "manifest-src 'self'", 'upgrade-insecure-requests'
].join('; ');
// A meta policy protects static copies too, except frame-ancestors (header only).
const meta='<meta http-equiv="Content-Security-Policy" content="'+csp.replace("; frame-ancestors 'none'",'')+'">';
html=html.includes('<meta http-equiv="Content-Security-Policy"')?html.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/,meta):html.replace('<meta charset="UTF-8">','<meta charset="UTF-8">\n'+meta+'\n<meta name="referrer" content="no-referrer">');
const config={
  $schema:'https://openapi.vercel.sh/vercel.json',
  buildCommand:'node tests/build-public.mjs',outputDirectory:'dist',
  headers:[{source:'/(.*)',headers:[
    {key:'Content-Security-Policy',value:csp},
    {key:'Strict-Transport-Security',value:'max-age=31536000; includeSubDomains'},
    {key:'X-Content-Type-Options',value:'nosniff'},
    {key:'Referrer-Policy',value:'no-referrer'},
    {key:'X-Frame-Options',value:'DENY'},
    {key:'Permissions-Policy',value:'camera=(), microphone=(), geolocation=(), payment=()'},
    {key:'Cache-Control',value:'no-store'}
  ]}]
};
const configText=JSON.stringify(config,null,2)+'\n';
if(check){
  if(html!==original||await readFile('vercel.json','utf8')!==configText)throw Error('Security policy is stale; regenerate and re-test');
}else{
  await writeFile('index.html',html);await writeFile('vercel.json',configText);
}
console.log('Security headers and integrity hashes '+(check?'verified':'prepared')+'. Real hosting and Clerk integration still require verification.');
