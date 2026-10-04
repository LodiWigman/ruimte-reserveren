// Focused browser regression for native validation and programmatically reset fields.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {chromium} from 'playwright';
const html=await readFile('index.html','utf8');
const locales={en:await readFile('node_modules/.cache/han-test/clerk-en.js','utf8'),nl:await readFile('node_modules/.cache/han-test/clerk-nl.js','utf8')};
const browser=await chromium.launch({headless:true,...(process.env.TEST_BROWSER_CHANNEL?{channel:process.env.TEST_BROWSER_CHANNEL}:{})});
try{
  const page=await browser.newPage();
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    window.supabase={createClient:()=>({rpc:()=>{throw new Error('Unexpected write in validation test');}})};
    window.Clerk={user:null,load:async()=>{},addListener:()=>{window.__ready=true;}};
  });
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(url==='https://han.test/')return route.fulfill({contentType:'text/html',body:html});
    if(url.includes('@clerk/localizations@'))return route.fulfill({contentType:'application/javascript',body:url.includes('/en-US/')?locales.en:locales.nl});
    return route.fulfill({contentType:'application/javascript',body:''});
  });
  await page.goto('https://han.test/');await page.waitForFunction(()=>window.__ready);
  await page.evaluate(()=>{currentUser={id:'user_test',firstName:'',lastName:''};currentProfile={};openProfile();});
  await page.locator('#profile-save').click();
  assert.equal(await page.locator('#profile-first').evaluate(el=>el.validationMessage),'Vul dit verplichte veld in.');
  await page.evaluate(()=>setLanguage('en'));
  await page.locator('#profile-save').click();
  assert.equal(await page.locator('#profile-first').evaluate(el=>el.validationMessage),'Please fill in this required field.');
  await page.evaluate(()=>{currentProfile={first_name:'Test',last_name:'Person',name_confirmed_at:'2030-01-01',display_name:'Test Person'};openProfile();});
  assert.equal(await page.locator('#profile-first').evaluate(el=>el.validity.valid),true,'reopening clears obsolete custom errors');
  await page.locator('#profile-close').click();
  await page.evaluate(()=>{const contact=document.getElementById('support-contact');contact.value='invalid';contact.checkValidity();});
  assert.equal(await page.locator('#support-contact').evaluate(el=>el.validationMessage),'Enter a valid email address.');
  await page.evaluate(()=>{document.getElementById('support-anonymous').value='true';updateCaseIdentity();});
  assert.equal(await page.locator('#support-contact').evaluate(el=>el.validity.valid),true,'anonymous selection clears a hidden contact error');
  assert.deepEqual(errors,[]);
  console.log('VALIDATION: NL/EN verplichte velden, e-mailadres en herstel van veldvalidatie geslaagd');
}finally{await browser.close();}
