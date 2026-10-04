// Bounded XSS probes against the unchanged local page; no live service is contacted.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';

const html=await readFile('index.html','utf8');
const locales={en:await readFile('node_modules/.cache/han-test/clerk-en.js','utf8'),nl:await readFile('node_modules/.cache/han-test/clerk-nl.js','utf8')};
const browser=await chromium.launch({headless:true,...(process.env.TEST_BROWSER_CHANNEL?{channel:process.env.TEST_BROWSER_CHANNEL}:{})});
try {
  const page=await browser.newPage();
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    window.__securityXss=0;
    window.supabase={createClient:()=>({rpc:()=>{throw new Error('Unexpected API request in security render test');}})};
    window.Clerk={user:null,load:async()=>{},addListener:()=>{window.__ready=true;}};
  });
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(url==='https://han.test/')return route.fulfill({contentType:'text/html',body:html});
    if(url.includes('@clerk/localizations@'))return route.fulfill({contentType:'application/javascript',body:url.includes('/en-US/')?locales.en:locales.nl});
    return route.fulfill({contentType:'application/javascript',body:''});
  });
  await page.goto('https://han.test/');
  await page.waitForFunction(()=>window.__ready);
  const results=await page.evaluate(async()=>{
    currentUser={id:'user_security'};currentProfile={role:'admin'};isAdmin=true;
    const probes=[
      '<img src=x onerror="window.__securityXss++">',
      '<svg onload="window.__securityXss++"></svg>',
      '\"><img src=x onerror="window.__securityXss++">',
      "');window.__securityXss++;//",
      '</textarea><img src=x onerror="window.__securityXss++">'
    ];
    const outcomes=[];
    for(const payload of probes){
      const caseData={id:'00000000-0000-4000-8000-000000000001',category:'question',anonymous:false,name:payload,message:payload,contact_email:payload,status:'open',created_at:'2035-01-01T09:00:00Z',unread:1,messages:[{author_role:'admin',author_name:payload,body:payload,created_at:'2035-01-01T10:00:00Z'}]};
      const booking={id:'00000000-0000-4000-8000-000000000002',roomId:'W0.03',roomName:payload,name:payload,organization:payload,desc:payload,date:'2035-01-01',start:'09:00',end:'10:00',status:'confirmed',persons:1};
      document.getElementById('my-support-messages').innerHTML=renderSupportCard(caseData);
      document.getElementById('my-bookings-list').innerHTML=renderBookingCard(booking)+renderRequestCard({...booking,status:'pending',motivation:payload,occasion:payload});
      activeCase=caseData;renderCase();
      adminRoleRequests=[{id:booking.id,full_name:payload,job_title:payload,motivation:payload,requested_role:'intern'}];renderAdminRoleRequests();
      adminBookingRequests=[{...booking,status:'pending',motivation:payload,occasion:payload}];renderAdminBookingRequests();
      rooms=[{id:payload,name:payload,notes:payload,capacity:1}];currentDate=new Date('2035-01-01T00:00:00');
      occupancy=[{...booking,roomId:payload,mine:false}];publicRequests=[];renderOverview();renderAdminRooms();
      // Exercise the inline JavaScript context generated for a database room ID.
      let selectedRoom=null;quickReserve=id=>{selectedRoom=id;};
      document.querySelector('#rooms-grid .reserve-btn-small').click();
      document.querySelector('#rooms-grid .booking-block').dispatchEvent(new MouseEvent('mouseenter',{bubbles:true}));
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      const targets=['my-support-messages','my-bookings-list','case-thread','case-original','admin-role-requests','admin-booking-requests','rooms-grid','admin-rooms-list'];
      outcomes.push({payload,executed:window.__securityXss,injectedElements:targets.reduce((count,id)=>count+document.getElementById(id).querySelectorAll('img,svg,script,iframe').length,0),roomArgumentPreserved:selectedRoom===payload,caseTextPreserved:document.getElementById('case-original').textContent===payload});
    }
    return outcomes;
  });
  for(const row of results){assert.equal(row.executed,0);assert.equal(row.injectedElements,0);assert.equal(row.roomArgumentPreserved,true);assert.equal(row.caseTextPreserved,true);}
  const boundary=await page.evaluate(async()=>{
    const violations=[];document.addEventListener('securitypolicyviolation',event=>violations.push(event.effectiveDirective));
    const hostile=document.createElement('button');hostile.setAttribute('onclick','window.__securityXss++');document.body.append(hostile);hostile.click();
    const script=document.createElement('script');script.textContent='window.__securityXss++';document.body.append(script);
    let rejected=0;
    for(const expression of ['constructor("alert(1)")','window.alert(1)','quickReserve("safe");alert(1)','quickReserve((window.__securityXss++))']){
      try{parseUiActions(expression,hostile,new Event('click'));}catch{rejected++;}
    }
    await new Promise(resolve=>setTimeout(resolve,100));
    const sensitive=['auth-user-label','my-bookings-list','admin-role-requests','case-original','case-thread','notification-list','details-content','profile-help'];
    for(const id of sensitive)document.getElementById(id).textContent='Private marker';
    document.getElementById('profile-first').value='Private marker';document.getElementById('case-reply').value='Private marker';
    currentUser={id:'user_security'};currentProfile={role:'admin'};isAdmin=true;
    const originalSignOut=window.Clerk.signOut;
    window.Clerk.signOut=async()=>{throw Error('Offline');};
    // The stub simulates an offline database as a rejected promise.
    supabaseClient.rpc=async()=>{throw Error('Offline');};
    await signOut();window.Clerk.signOut=originalSignOut;
    return {executed:window.__securityXss,violations,rejected,
      cleared:sensitive.every(id=>!document.getElementById(id).textContent.includes('Private marker'))&&document.getElementById('profile-first').value===''&&document.getElementById('case-reply').value==='',
      unknownError:explainError({message:'SELECT secret FROM private_table; token=secret'}),
      languageSwitch:parseUiActions("setLanguage('en')",hostile,new Event('click'))[0].args[0]};
  });
  assert.equal(boundary.executed,0);assert.equal(boundary.rejected,4);assert.equal(boundary.cleared,true);
  assert.ok(boundary.violations.includes('script-src-attr'));assert.ok(boundary.violations.includes('script-src-elem'));
  assert.doesNotMatch(boundary.unknownError,/SELECT|secret|private_table/);assert.equal(boundary.languageSwitch,'en');
  assert.deepEqual(errors,[]);
  await writeFile('test-results/security-browser.json',JSON.stringify({scope:'local render/CSP/session-cleanup probes; mocked auth and no live API',results,boundary,errors},null,2));
  console.log('PROTECTED: 5 XSS variants, CSP blocks actual inline injection, action allowlist rejects code, hidden personal data cleared on offline logout, unknown errors sanitized.');
}finally{await browser.close();}
