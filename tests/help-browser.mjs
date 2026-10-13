// Actual page + pinned SDK, isolated service responses. RLS is tested separately against PostgreSQL.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {chromium} from 'playwright';
const html=await readFile('index.html','utf8');
const assets={};for(const name of ['supabase','xlsx','clerk-en','clerk-nl'])assets[name]=await readFile('node_modules/.cache/han-test/'+name+'.js','utf8');
const logo=await readFile('han-logo.svg','utf8');
const browser=await chromium.launch({headless:true,...(process.env.TEST_BROWSER_CHANNEL?{channel:process.env.TEST_BROWSER_CHANNEL}:{})});
const progress=new Map(),profiles=new Map(),writes=[],errors=[];
let storageFails=false,delayedRead=null,releaseRead=null;
const profile=(id,role='extern',complete=true)=>({id,role,display_name:'Demo Gebruiker',first_name:'Demo',last_name:'Gebruiker',name_confirmed_at:complete?'2026-01-01':null});
const room={id:'W0.03',name:'Vergaderruimte',capacity:12,active:true,notes:''};
async function newPage(id=null,{role='extern',complete=true,mobile=false,lang='nl',visitorSeen=false,blockedStorage=false,waitForHelp=true}={}){
  if(id&&!profiles.has(id))profiles.set(id,profile(id,role,complete));
  const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1365,height:1000}});
  const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(({id,lang,visitorSeen,blockedStorage})=>{
    localStorage.setItem('han-language',lang);
    if(visitorSeen)localStorage.setItem('han-help:visitor',JSON.stringify({seen:['v1:welcome']}));
    window.__initialUser=id;
    if(blockedStorage)Storage.prototype.setItem=()=>{throw new Error('Storage blocked');};
  },{id,lang,visitorSeen,blockedStorage});
  await page.route('**/*',async route=>{
    const req=route.request(),url=new URL(req.url());
    const json=(data,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});
    if(url.href==='https://han.test/')return route.fulfill({contentType:'text/html',body:html});
    if(url.pathname==='/han-logo.svg')return route.fulfill({contentType:'image/svg+xml',body:logo});
    if(url.pathname.includes('/rest/v1/')){
      const user=req.headers().authorization?.replace('Bearer ',''),name=url.pathname.split('/').pop(),args=req.postDataJSON()||{};
      if(name.startsWith('han_help')&&storageFails)return json({message:'Storage temporarily unavailable'},503);
      if(name==='han_help_progress'){
        const result=[...(progress.get(user)||[])];
        if(delayedRead===user){delayedRead=null;await new Promise(resolve=>{releaseRead=resolve;});}
        return json(result);
      }
      if(name==='han_help_mark'){if(!progress.has(user))progress.set(user,new Set());progress.get(user).add(args.guide_key);writes.push({user,...args});return json(true);}
      if(name==='profiles')return json(profiles.get(user));
      if(name==='rooms')return json(url.searchParams.has('id')?[]:[room]);
      if(name==='han_ensure_profile'||name==='han_end_session')return json(true);
      if(name==='han_notifications')return json({items:[],unread:0});
      if(name==='han_save_profile'){const p=profiles.get(user);p.name_confirmed_at='2026-01-01';p.first_name=args.first_name;p.last_name=args.last_name;return json(p);}
      if(name==='han_availability')return json(args.items.map(()=>({conflict:false})));
      if(name==='han_create_bookings'){writes.push({booking:args,user});return json({confirmed:profiles.get(user).role==='extern'?0:args.items.length,requested:profiles.get(user).role==='extern'?args.items.length:0});}
      return json([]);
    }
    if(url.href.includes('supabase-js@'))return route.fulfill({contentType:'application/javascript',body:assets.supabase});
    if(url.href.includes('xlsx.full.min.js'))return route.fulfill({contentType:'application/javascript',body:assets.xlsx});
    if(url.href.includes('@clerk/localizations@'))return route.fulfill({contentType:'application/javascript',body:url.href.includes('/en-US/')?assets['clerk-en']:assets['clerk-nl']});
    if(url.href.includes('/clerk.browser.js'))return route.fulfill({contentType:'application/javascript',body:`window.Clerk={user:window.__initialUser?{id:window.__initialUser}:null,load:async()=>{},__internal_updateProps:async()=>{},session:{getToken:async()=>window.Clerk.user?.id||null},addListener:fn=>{window.__listener=fn;},openSignIn:()=>{window.__authOpened='login';},openSignUp:()=>{window.__authOpened='signup';},signOut:async()=>{window.Clerk.user=null;await handleClerkUser(null);}};`});
    return route.fulfill({contentType:'application/javascript',body:''});
  });
  await page.goto('https://han.test/');await page.waitForFunction(()=>window.__listener);
  if(waitForHelp)await page.waitForFunction(()=>helpState.ready);
  return page;
}
async function skip(page){await page.locator('#help-dialog').waitFor({state:'visible'});await page.locator('#help-skip').click();await page.locator('#help-dialog').waitFor({state:'hidden'});}
async function tab(page,name){await page.locator('.tabs button[data-onclick="switchTab(\''+name+'\')"]').click();}
async function changeRole(page,user,role){profiles.get(user).role=role;await page.evaluate(async()=>{await loadProfile();updateAuthUi();helpRoleChanged();});}
async function switchAccount(page,id,role='extern'){
  if(!profiles.has(id))profiles.set(id,profile(id,role));
  await page.evaluate(async id=>{window.Clerk.user={id};await handleClerkUser(window.Clerk.user);},id);
  await page.waitForFunction(()=>helpState.ready);
}
function passed(text){console.log('PASS '+text);}
await mkdir('test-results/help',{recursive:true});
try{
  const guest=await newPage();await guest.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await guest.locator('#help-title').innerText(),/Welkom/);
  assert.equal(await guest.evaluate(()=>document.activeElement.id),'help-title');
  for(let i=0;i<12;i++){await guest.keyboard.press('Tab');assert.equal(await guest.evaluate(()=>!!document.activeElement.closest('#help-dialog')),true);}
  await guest.screenshot({path:'test-results/help/01-welkom.png'});
  await guest.keyboard.press('Escape');await guest.reload();await guest.waitForFunction(()=>helpState.ready);
  assert.equal(await guest.locator('#help-dialog').isVisible(),false);
  await guest.locator('#help-button').click();await guest.getByRole('button',{name:'Introductie opnieuw bekijken'}).click();
  await guest.getByRole('button',{name:'Volgende',exact:true}).click();assert.match(await guest.locator('#help-copy').innerText(),/Verzoek indienen → Beoordeling/);
  await guest.getByRole('button',{name:'Vorige',exact:true}).click();assert.match(await guest.locator('#help-title').innerText(),/Welkom/);
  await skip(guest);await switchAccount(guest,'user_fresh');
  await guest.waitForTimeout(400);assert.equal(await guest.locator('#help-dialog').isVisible(),false,'no repeated external introduction after visitor guide');
  await switchAccount(guest,'user_nextperson');await guest.locator('#help-dialog').waitFor({state:'visible'});await skip(guest);
  passed('visitor guide, keyboard focus, Escape, replay and no duplicate after sign-in');

  const external=await newPage('user_external');await skip(external);
  for(const name of ['overzicht','reserveren','mijn','rollen','vragen']){
    await tab(external,name);assert.equal(await external.locator('.section.active .help-card').count(),1);
    await external.getByRole('button',{name:'Laat zien',exact:true}).click();
    for(let i=0;i<2;i++)await external.getByRole('button',{name:'Volgende',exact:true}).click();
    await external.locator('#help-dialog').getByRole('button',{name:'Begrepen',exact:true}).click();
    assert.equal(await external.locator('.section.active .help-card').count(),0);
    assert.equal(await external.evaluate(()=>document.activeElement.id),'help-button','focus returns to Help when the completed card disappears');
  }
  assert.equal(writes.some(w=>w.booking),false,'tutorials do not book anything');
  assert.equal(await external.locator('#beheer-tab-btn').isVisible(),false);
  await tab(external,'reserveren');await external.locator('#f-organization').fill('Bewaren tijdens uitleg');
  await external.locator('#f-room').selectOption(room.id);await external.locator('#f-occasion').fill('Overleg');
  await external.locator('#help-button').click();await external.getByRole('button',{name:'Uitleg over dit tabblad'}).click();await skip(external);
  assert.equal(await external.locator('#f-organization').inputValue(),'Bewaren tijdens uitleg');
  await external.locator('#f-recur-toggle').check();assert.equal(await external.locator('#recurrence-help').isVisible(),true);
  await external.locator('#f-recur-toggle').uncheck();
  await external.locator('#submit-btn').click();await external.locator('#booking-outcome').waitFor({state:'visible'});
  assert.match(await external.locator('#booking-outcome').innerText(),/0 bevestigd; 1 verzoek/);
  await external.locator('#booking-outcome button').click();assert.equal(await external.locator('#tab-mijn').isVisible(),true);
  passed('all external tabs, read-only tours, retained form data, recurrence explanation and booking outcome');

  await external.waitForFunction(()=>Object.keys(helpState.pending).length===0);
  const otherDevice=await newPage('user_external');await otherDevice.waitForTimeout(400);
  assert.equal(await otherDevice.locator('#help-dialog').isVisible(),false);assert.equal(await otherDevice.locator('.help-card').count(),0);
  await tab(otherDevice,'reserveren');await otherDevice.locator('#f-desc').fill('Concept behouden');
  await changeRole(otherDevice,'user_external','intern');await otherDevice.waitForTimeout(400);
  assert.equal(await otherDevice.locator('#help-dialog').isVisible(),false,'role upgrade does not interrupt input');
  assert.equal(await otherDevice.locator('#f-desc').inputValue(),'Concept behouden');
  await tab(otherDevice,'overzicht');await otherDevice.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await otherDevice.locator('#help-title').innerText(),/interne rol/);await skip(otherDevice);
  assert.equal(await otherDevice.locator('.help-card').count(),0,'unchanged overview help stays acknowledged after role change');
  await changeRole(otherDevice,'user_external','admin');await otherDevice.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await otherDevice.locator('#help-title').innerText(),/adminrol/);await skip(otherDevice);
  await tab(otherDevice,'vragen');assert.equal(await otherDevice.locator('.help-card').count(),0,'unchanged questions help does not repeat');
  passed('cross-device progress and external → internal → admin without interrupting drafts');

  const admin=await newPage('user_admin',{role:'admin'});await admin.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await admin.locator('#help-title').innerText(),/adminrol/);await skip(admin);await tab(admin,'beheer');
  assert.equal(await admin.locator('.help-admin').count(),6);
  await admin.locator('.help-admin').nth(4).locator('summary').click();assert.match(await admin.locator('.help-admin').nth(4).innerText(),/niets uit het bestand/);
  await admin.screenshot({path:'test-results/help/02-beheer.png',fullPage:true});
  await admin.getByRole('button',{name:'Laat zien',exact:true}).click();await skip(admin);
  await switchAccount(admin,'user_other');await admin.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await admin.locator('#help-title').innerText(),/externe gebruiker/);assert.equal(await admin.locator('#beheer-tab-btn').isVisible(),false);
  passed('direct admin, six management explanations and isolated account switch');

  const incomplete=await newPage('user_incomplete',{complete:false});assert.equal(await incomplete.locator('#profile-dialog').isVisible(),true);
  await incomplete.waitForTimeout(350);assert.equal(await incomplete.locator('#help-dialog').isVisible(),false);
  await incomplete.locator('#profile-first').fill('Demo');await incomplete.locator('#profile-last').fill('Naam');await incomplete.locator('#profile-save').click();
  await incomplete.locator('#help-dialog').waitFor({state:'visible'});await skip(incomplete);
  passed('required profile precedes introduction');

  storageFails=true;const offline=await newPage('user_offline',{blockedStorage:true});await skip(offline);
  await tab(offline,'reserveren');assert.equal(await offline.locator('#f-room').isEnabled(),true);
  await offline.locator('#f-room').selectOption(room.id);await offline.locator('#f-organization').fill('Demo');await offline.locator('#f-occasion').fill('Test');await offline.locator('#submit-btn').click();
  await offline.locator('#booking-outcome').waitFor({state:'visible'});
  storageFails=false;await offline.evaluate(()=>flushHelpProgress());await offline.waitForFunction(()=>Object.keys(helpState.pending).length===0);
  passed('remote and browser storage failures do not block a booking; retry syncs pending progress');

  // An old account read arriving after an account switch must not alter the new state.
  delayedRead='user_late';const latePromise=newPage('user_late');
  while(!releaseRead)await new Promise(resolve=>setTimeout(resolve,20));
  const late=await latePromise;await switchAccount(late,'user_latenew');releaseRead();
  await late.waitForTimeout(100);assert.equal(await late.evaluate(()=>helpState.user),'user_latenew');
  passed('late progress response stays bound to its account');
  delayedRead='user_slow';releaseRead=null;
  const slow=await newPage('user_slow',{waitForHelp:false});
  await tab(slow,'reserveren');await slow.locator('#f-organization').fill('Niet onderbreken');
  assert.equal(await slow.locator('.help-card').count(),0);
  releaseRead();await slow.waitForFunction(()=>helpState.ready);
  assert.equal(await slow.locator('.help-card').count(),0);assert.equal(await slow.locator('#help-dialog').isVisible(),false);
  assert.equal(await slow.locator('#f-organization').inputValue(),'Niet onderbreken');
  passed('slow progress loading cannot insert help halfway through filling a form');

  const mobile=await newPage('user_mobile',{role:'intern',mobile:true,lang:'en'});await mobile.locator('#help-dialog').waitFor({state:'visible'});
  assert.equal(await mobile.locator('#help-title').innerText(),'You have an internal role');
  await mobile.screenshot({path:'test-results/help/03-mobile-en.png'});await skip(mobile);
  await tab(mobile,'reserveren');await mobile.getByRole('button',{name:'Show me',exact:true}).click();
  assert.equal(await mobile.locator('#help-title').innerText(),'Choose a room, date and time');
  const bounds=await mobile.locator('#help-dialog').boundingBox();assert.ok(bounds.x>=0&&bounds.x+bounds.width<=390&&bounds.y+bounds.height<=845);
  await mobile.screenshot({path:'test-results/help/04-mobile-tour.png'});await skip(mobile);
  await mobile.locator('#lang-nl').click();assert.equal(await mobile.locator('#help-button').textContent(),'Hulp');
  assert.equal(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  passed('English mobile guide, tour bounds, language change and no horizontal overflow');
  const english=await newPage('user_english',{lang:'en'});await skip(english);
  for(const [name,title] of [['overzicht','How to read the overview'],['reserveren','Request or book a room'],['mijn','Manage your requests and bookings'],['rollen','Request the right role'],['vragen','Send a question, complaint or tip']]){
    await tab(english,name);assert.equal(await english.locator('.section.active .help-card h2').textContent(),title);
    await english.getByRole('button',{name:'Show me',exact:true}).click();await skip(english);
  }
  await switchAccount(english,'user_englishadmin','admin');await skip(english);await tab(english,'beheer');
  assert.equal(await english.locator('.section.active .help-card h2').textContent(),'Getting started with administration');
  assert.equal(await english.getByText('Help with this section',{exact:true}).count(),6);
  passed('all six tabs and administration help in English as well as Dutch');
  const preview=await browser.newPage();
  const previewHtml=await readFile('test-results/help/preview.html','utf8'),previewRequests=[];
  preview.on('pageerror',e=>errors.push(e.message));
  await preview.route('**/*',route=>{
    if(route.request().url()==='https://preview.test/')return route.fulfill({contentType:'text/html',body:previewHtml});
    previewRequests.push(route.request().url());return route.abort();
  });
  await preview.goto('https://preview.test/');await preview.waitForFunction(()=>helpState.ready);await skip(preview);
  await preview.locator('#preview-role').selectOption('admin');await preview.locator('#help-dialog').waitFor({state:'visible'});
  assert.match(await preview.locator('#help-title').innerText(),/adminrol/);await skip(preview);await tab(preview,'beheer');
  assert.equal(await preview.locator('.help-admin').count(),6);assert.deepEqual(previewRequests,[]);
  await preview.screenshot({path:'test-results/help/05-preview.png',fullPage:true});
  passed('standalone interactive preview, role picker and zero external network requests');
  assert.deepEqual(errors,[]);console.log('HELP BROWSER: all scenarios passed');
}finally{releaseRead?.();await browser.close();}
