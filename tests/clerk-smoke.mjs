// Real public Clerk UI, fresh browser context, no account or credential submission.
// Only the document is replaced locally; production website/database are not changed.
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
const html=await readFile('index.html','utf8');
const config=JSON.parse(await readFile('vercel.json','utf8'));
const headers=Object.fromEntries(config.headers[0].headers.map(h=>[h.key,h.value]));
const browser=await chromium.launch({headless:true,channel:process.env.TEST_BROWSER_CHANNEL||'msedge'});
const errors=[],failures=[],results=[];
try{
  const page=await browser.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  page.on('requestfailed',request=>{const url=new URL(request.url());failures.push({url:url.origin+url.pathname,error:request.failure()?.errorText});});
  await page.addInitScript(()=>{
    window.__releaseCsp=[];
    document.addEventListener('securitypolicyviolation',event=>window.__releaseCsp.push({directive:event.effectiveDirective,blocked:event.blockedURI.split('?')[0]}));
  });
  await page.route('https://ruimte-reserveren.vercel.app/',route=>route.fulfill({contentType:'text/html',headers,body:html}));
  await page.route('https://ruimte-reserveren.vercel.app/han-logo.svg',async route=>route.fulfill({contentType:'image/svg+xml',body:await readFile('han-logo.svg')}));
  await page.route('https://*.supabase.co/**',route=>route.abort());
  await page.goto('https://ruimte-reserveren.vercel.app/');
  await page.waitForFunction(()=>window.Clerk?.loaded,{},{timeout:60000});
  assert.equal(await page.evaluate(()=>window.Clerk.user),null);
  await page.evaluate(()=>window.Clerk.openSignIn());
  await page.locator('.cl-signIn-root input').first().waitFor({state:'visible',timeout:30000});
  results.push('Real Dutch sign-in UI loads with the release CSP');
  await page.evaluate(async()=>{window.Clerk.closeSignIn();await setLanguage('en');window.Clerk.openSignUp();});
  await page.locator('.cl-signUp-root input').first().waitFor({state:'visible',timeout:30000});
  assert.match(await page.locator('.cl-signUp-root').innerText(),/Create your account|Sign up/i);
  results.push('Real English sign-up UI loads after language change');
  const csp=await page.evaluate(()=>window.__releaseCsp);
  assert.deepEqual(csp,[],'Unexpected CSP blocks in the real Clerk UI');
  assert.deepEqual(errors,[],'Unexpected browser errors');
  await mkdir('test-results',{recursive:true});
  await writeFile('test-results/clerk-smoke.json',JSON.stringify({testedAt:new Date().toISOString(),results,errors,failures,csp,scope:'Public UI only. No sign-in, registration, session-token or production database tests.'},null,2));
  console.log(JSON.stringify({results,failures},null,2));
}catch(error){
  console.error(JSON.stringify({errors,failures}));throw error;
}finally{await browser.close();}
