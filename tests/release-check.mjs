// Lightweight build verification. Clerk development is intentionally supported.
// Publishing still requires the user's separate final approval.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
export const publicFiles=['index.html','han-logo.svg'];
export const releaseFiles=[...publicFiles,'vercel.json','package.json','pnpm-lock.yaml',
  'SQL/basis.sql','SQL/migrations/20260922151039_reservation_workflows.sql',
  'SQL/migrations/20260929192403_connectr_profiles_conversations.sql',
  'tests/security-assessment.mjs','tests/security-browser.mjs','tests/security-imports.mjs',
  'tests/browser.mjs','tests/db-harness.mjs','tests/build-public.mjs','tests/release-check.mjs',
  'tests/release-build.mjs','tests/verify-local.mjs','tests/prepare-security-headers.mjs',
  'docs/security/browser-integrity.json','docs/security/CONTROLES.md'];

export async function verifyRelease(root=process.cwd()){
  const html=await readFile(path.join(root,'index.html'),'utf8');
  const config=JSON.parse(await readFile(path.join(root,'vercel.json'),'utf8'));
  const integrity=JSON.parse(await readFile(path.join(root,'docs/security/browser-integrity.json'),'utf8'));
  const headers=Object.fromEntries(config.headers.find(rule=>rule.source==='/(.*)').headers.map(h=>[h.key.toLowerCase(),h.value]));
  const policy=headers['content-security-policy'];
  const script=html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
  if(!script)throw Error('Application script missing');
  const hash='sha256-'+createHash('sha256').update(script.replace(/\r\n/g,'\n')).digest('base64');
  if(!policy?.includes("'"+hash+"'"))throw Error('CSP does not match the current application');
  const meta=html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1];
  if(meta!==policy.replace("; frame-ancestors 'none'",''))throw Error('HTML and hosting policies differ');
  for(const directive of ["default-src 'none'","object-src 'none'","base-uri 'none'","frame-ancestors 'none'","script-src-attr 'none'"]){
    if(!policy.split('; ').includes(directive))throw Error('Missing protection: '+directive);
  }
  const scripts=policy.split('; ').find(value=>value.startsWith('script-src '));
  if(/'unsafe-(inline|eval)'/.test(scripts)||/\s+on[a-z]+=["']/.test(html))throw Error('Unsafe script execution enabled');
  for(const [name,url] of [
    ['supabase','https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js'],
    ['xlsx','https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js']
  ]){
    if(!html.includes(`<script src="${url}" integrity="${integrity[name]}" crossorigin="anonymous">`))throw Error('Missing dependency integrity: '+name);
  }
  if(headers['x-content-type-options']!=='nosniff'||headers['cache-control']!=='no-store'||headers['referrer-policy']!=='no-referrer')throw Error('Required hosting headers missing');
  if(config.outputDirectory!=='dist'||config.buildCommand!=='node tests/build-public.mjs')throw Error('Unexpected publication configuration');
  const logo=await readFile(path.join(root,'han-logo.svg'),'utf8');
  if(!logo.includes('<svg'))throw Error('Website logo missing');
  return {status:'passed',clerkMode:html.includes("CLERK_PUBLISHABLE_KEY = 'pk_test_")?'development':'production',publicFiles};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  console.log(JSON.stringify(await verifyRelease(),null,2));
}
