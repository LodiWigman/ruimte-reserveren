// Offline browser + echte lokale PostgreSQL. Alleen de Clerk-sessie en HTTP-
// vertaling naar SQL zijn testdubbels; index.html en Supabase SDK zijn ongewijzigd.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {startDatabase,applyBasis,asUser} from './db-harness.mjs';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE).href:'playwright');
const env=await startDatabase();
await applyBasis(env.db);
await env.db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_admin','Beheerder','admin'),('user_intern','Interne gebruiker','intern'),('user_extern','Externe gebruiker','extern')");
const html=await readFile('index.html','utf8');
const sdk=await readFile(process.env.SUPABASE_TEST_SDK||'node_modules/.cache/han-test/supabase.js','utf8');
const xlsx=await readFile(process.env.XLSX_TEST_SDK||'node_modules/.cache/han-test/xlsx.js','utf8');
await mkdir('test-results',{recursive:true});
const browser=await chromium.launch({headless:true,...(process.env.TEST_BROWSER_CHANNEL?{channel:process.env.TEST_BROWSER_CHANNEL}:{})});
let passed=0;
const clients=new Set();
async function api(route){
  const request=route.request(),url=new URL(request.url()),token=request.headers().authorization?.replace('Bearer ','');
  const user=['user_admin','user_intern','user_extern'].includes(token)?token:'anonymous';
  const client=await env.connect();clients.add(client);
  try{
    let data;
    if(url.pathname.includes('/rpc/')){
      const name=url.pathname.split('/').pop(),args=request.postDataJSON()||{},keys=Object.keys(args);
      if(!/^(han_[a-z_]+|import_reserveringen)$/.test(name)||keys.some(k=>!/^\w+$/.test(k)))throw new Error('Onverwachte test-API');
      data=(await asUser(client,user,`SELECT public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) AS result`,Object.values(args).map(v=>v&&typeof v==='object'?JSON.stringify(v):v))).rows[0].result;
    }else{
      const table=url.pathname.split('/').pop(),values=[],where=[];
      if(!['profiles','rooms','reserveringen','reserveringsverzoeken','role_requests','support_messages'].includes(table))throw new Error('Onbekende tabel');
      for(const [key,value]of url.searchParams){
        if(['select','order','limit','offset'].includes(key))continue;
        if(!/^\w+$/.test(key))throw new Error('Ongeldig veld');
        const dot=value.indexOf('.'),op={eq:'=',gte:'>=',gt:'>'}[value.slice(0,dot)];
        if(!op)throw new Error('Onbekend filter');values.push(value.slice(dot+1));where.push('t.'+key+op+'$'+values.length);
      }
      const limit=Math.min(Number(url.searchParams.get('limit')||1000),1000);
      const sql=`SELECT to_jsonb(t) AS row FROM public.${table} t ${where.length?'WHERE '+where.join(' AND '):''} ORDER BY id LIMIT ${limit}`;
      data=(await asUser(client,user,sql,values)).rows.map(r=>r.row);
      if(request.headers().accept?.includes('vnd.pgrst.object')){if(data.length!==1)throw new Error('Niet precies één rij');data=data[0];}
    }
    await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify(data)});
  }catch(error){await route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:error.message,code:error.code})});}
  finally{await client.end();clients.delete(client);}
}
try{
  for(const viewport of [{width:1365,height:1000},{width:390,height:844}]){
    const page=await browser.newPage({viewport});const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('dialog',dialog=>dialog.accept());
    await page.route('**/*',async route=>{
      const url=route.request().url();
      if(url==='https://han.test/')return route.fulfill({contentType:'text/html',body:html});
      if(url.includes('/rest/v1/'))return api(route);
      if(url.includes('supabase-js@'))return route.fulfill({contentType:'application/javascript',body:sdk});
      if(url.includes('xlsx.full.min.js'))return route.fulfill({contentType:'application/javascript',body:xlsx});
      if(url.includes('/clerk.browser.js'))return route.fulfill({contentType:'application/javascript',body:`window.Clerk={user:null,session:{getToken:async()=>window.__testUser?.id||null},load:async()=>{},addListener:fn=>window.__clerkListener=fn,openSignIn:()=>{},openSignUp:()=>{},signOut:async()=>{window.__testUser=null;window.Clerk.user=null;window.__clerkListener({user:null});}};`});
      return route.fulfill({contentType:'application/javascript',body:''});
    });
    await page.goto('https://han.test/');
    await page.waitForFunction(()=>window.__clerkListener);
    assert.match(await page.locator('#rooms-grid').innerText(),/Log in/);
    const login=async role=>{
      await page.evaluate(async role=>{
        window.__testUser={id:'user_'+role,fullName:role,primaryEmailAddress:{emailAddress:role+'@test.invalid'}};
        window.Clerk.user=window.__testUser;await handleClerkUser(window.__testUser);
      },role);
      await page.waitForFunction(()=>document.querySelectorAll('.room-row').length===17);
    };
    const fill=async(date)=>{
      await page.getByRole('button',{name:'Reserveren',exact:true}).click();
      await page.locator('#f-name').fill('Test reservering');await page.locator('#f-room').selectOption('W0.03');
      await page.locator('#f-date').fill(date);await page.locator('#f-start').fill('09:00');await page.locator('#f-end').fill('10:00');
      await page.locator('#f-persons').fill('2');
    };
    const day=viewport.width===390?'2031-02-01':'2031-01-01';
    await login('extern');
    assert.equal(await page.locator('#beheer-tab-btn').isVisible(),false);
    await fill(day);
    await page.locator('#f-organization').fill('Test organisatie');await page.locator('#f-occasion').fill('Overleg');await page.locator('#f-motivation').fill('Toelichting test');
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('1 verzoek'));
    await page.getByRole('button',{name:'Vragen/klachten',exact:true}).click();await page.locator('#support-message').fill('Testvraag vanuit de browser');await page.locator('#support-submit-btn').click();
    await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('bericht is ingediend'));
    await login('admin');await page.getByRole('button',{name:'Beheer',exact:true}).click();
    await page.locator('#admin-booking-requests .approve-btn').first().click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('verzoek(en) verwerkt'));
    const support=page.locator('#admin-support-messages .request-card').first();
    await support.locator('textarea').fill('Antwoord vanuit de browser');await support.getByRole('button',{name:'Reactie opslaan'}).click();
    await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('Reactie opgeslagen'));
    const importDay=viewport.width===390?'2031-02-10':'2031-01-10';
    const csv=Buffer.from('naam;ruimte;datum;start;einde;omschrijving\nImport test;W0.03;'+importDay+';09:00;10:00;"regel 1\nregel 2"\n');
    await page.locator('#import-file').setInputFiles({name:'test.csv',mimeType:'text/csv',buffer:csv});
    await page.waitForFunction(()=>!document.querySelector('#import-confirm-btn').disabled);
    await page.locator('#import-confirm-btn').click();
    await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('1 reserveringen geïmporteerd'));
    await page.locator('#import-file').setInputFiles({name:'test.csv',mimeType:'text/csv',buffer:csv});
    await page.waitForFunction(()=>document.querySelector('#import-preview').textContent.includes('conflict met bestaande reservering'));
    assert.equal(await page.locator('#import-confirm-btn').isDisabled(),true);
    const excel=await page.evaluate(async()=>{
      const workbook=XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(workbook,XLSX.utils.aoa_to_sheet([['naam','ruimte','datum','start','einde'],['Excel test','W0.03',48214,0.375,10/24]]),'Planning');
      const blob=new File([XLSX.write(workbook,{type:'array',bookType:'xlsx'})],'test.xlsx');
      return parseExcel(blob);
    });
    assert.equal(excel[0].start,'09:00');assert.equal(excel[0].einde,'10:00');assert.match(excel[0].datum,/^2032-/);
    await page.evaluate(()=>window.scrollTo(0,0));
    await page.screenshot({path:`test-results/admin-${viewport.width}.png`,fullPage:true});
    await login('intern');await fill(day);
    await page.locator('#f-date').fill(viewport.width===390?'2031-02-02':'2031-01-02');
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('1 bevestigd'));
    await page.getByRole('button',{name:'Mijn verzoeken/reserveringen',exact:true}).click();
    await page.locator('#my-bookings-list .edit-btn').first().click();await page.locator('#f-start').fill('11:00');await page.locator('#f-end').fill('12:00');
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('Wijzigingen opgeslagen'));
    await page.getByRole('button',{name:'Overzicht',exact:true}).click();
    await page.screenshot({path:`test-results/overzicht-${viewport.width}.png`,fullPage:true});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'geen horizontale overflow');
    // Nieuwe schermhandelingen via echte knoppen, met de lokale database als autoriteit.
    await login('extern');
    await page.getByRole('button',{name:'Intern/admin rol aanvraag',exact:true}).click();
    assert.deepEqual(await page.locator('#rr-role option').allTextContents(),['Intern','Admin']);
    await page.locator('#rr-role').selectOption('admin');await page.locator('#rr-job').fill('Locatiebeheer');await page.locator('#rr-motivation').fill('Ondersteunt de planning');
    await page.locator('#role-submit-btn').click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('Rolverzoek opgeslagen'));
    await page.getByRole('button',{name:'Mijn verzoeken/reserveringen',exact:true}).click();
    const roleCard=page.locator('.role-request-card').filter({hasText:'Rolverzoek: Admin'});
    await roleCard.getByRole('button',{name:'Wijzigen',exact:true}).click();await page.locator('#rr-role').selectOption('intern');
    await page.locator('#role-submit-btn').click();await page.waitForFunction(()=>document.querySelector('#role-form-title').textContent==='Intern/admin rol aanvraag');
    await page.getByRole('button',{name:'Mijn verzoeken/reserveringen',exact:true}).click();
    await page.locator('.role-request-card').filter({hasText:'Rolverzoek: Intern'}).getByRole('button',{name:'Intrekken',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('.role-request-card'));
    const seriesDay=viewport.width===390?'2031-06-01':'2031-05-01';
    const seriesLast=seriesDay.slice(0,8)+'03';
    await fill(seriesDay);
    await page.locator('#f-organization').fill('');await page.locator('#f-occasion').fill('');
    await page.clock.install();
    await page.locator('#submit-btn').click();
    assert.match(await page.locator('#app-notice').innerText(),/organisatie\/afdeling/);
    assert.equal(await page.locator('#app-notice').evaluate(el=>getComputedStyle(el).position),'fixed');
    assert.ok((await page.locator('#app-notice').boundingBox()).y<40,'melding blijft boven in viewport');
    await page.clock.runFor(5100);assert.equal(await page.locator('#app-notice').isVisible(),false);
    await page.locator('#f-organization').fill('Planning & evenementen');await page.locator('#f-occasion').fill('Reekscontrole');
    await page.locator('#f-motivation').fill('');await page.locator('#f-recur-toggle').check();
    await page.locator('#f-recur-unit').selectOption('dag');await page.locator('#f-recur-until').fill(seriesLast);
    assert.match(await page.locator('#recurrence-preview').innerText(),/3 momenten/);
    await page.waitForFunction(()=>document.querySelector('#conflict-warning').textContent.includes('nu vrij'));
    assert.equal(await page.locator('#conflict-warning').evaluate(el=>el.classList.contains('subnote')),true);
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('3 verzoek'));
    assert.match(await page.locator('#app-notice').innerText(),/Controleer je verzoek\/reservatie in het overzicht/);
    await page.getByRole('button',{name:'Mijn verzoeken/reserveringen',exact:true}).click();
    const mySeries=page.locator('#my-bookings-list .series-group').filter({hasText:seriesDay});
    assert.equal(await mySeries.count(),1);assert.equal(await mySeries.locator('.booking-card').count(),3);
    assert.equal(await mySeries.getAttribute('open'),null);await mySeries.locator('summary').click();
    await page.screenshot({path:`test-results/reeks-${viewport.width}.png`,fullPage:true});
    await page.getByRole('button',{name:'Overzicht',exact:true}).click();await page.locator('#date-picker').fill(seriesDay);
    await page.waitForFunction(()=>document.querySelector('.booking-block.mine')?.textContent==='Mijn verzoek');
    await page.locator('.booking-block.mine').click();
    assert.equal(await page.locator('#booking-dialog').isVisible(),true);
    await page.locator('#f-desc').fill('Aangepast vanuit het overzicht');await page.locator('#edit-scope').selectOption('series');
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>!document.querySelector('#booking-dialog').open);
    await login('admin');await page.getByRole('button',{name:'Beheer',exact:true}).click();
    const adminSeries=page.locator('#admin-booking-requests .series-group').filter({hasText:seriesDay});
    await adminSeries.locator('summary').click();await adminSeries.getByRole('button',{name:'Deze en volgende goedkeuren',exact:true}).first().click();
    await page.waitForFunction(()=>document.querySelector('#app-notice').textContent.includes('3 verzoek(en) verwerkt'));
    assert.equal(await page.locator('#admin-booking-requests .series-group').filter({hasText:seriesDay}).count(),0);
    assert.equal(await page.locator('#all-bookings-admin .series-group').filter({hasText:seriesDay}).count(),1);
    await page.getByRole('button',{name:'Overzicht',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.booking-block')?.textContent==='Gereserveerd');
    await page.locator('.booking-block').first().click();assert.equal(await page.locator('#booking-dialog').isVisible(),true);
    await page.locator('#f-desc').fill('Adminwijziging');await page.locator('#edit-scope').selectOption('series');await page.locator('#submit-btn').click();
    await page.waitForFunction(()=>!document.querySelector('#booking-dialog').open);
    await login('intern');await page.getByRole('button',{name:'Intern/admin rol aanvraag',exact:true}).click();
    assert.deepEqual(await page.locator('#rr-role option').allTextContents(),['Admin']);
    await page.getByRole('button',{name:'Overzicht',exact:true}).click();await page.locator('.booking-block').first().click();
    assert.match(await page.locator('#details-content').innerText(),/Planning & evenementen/);
    assert.equal(await page.locator('#booking-dialog').isVisible(),false);
    await page.locator('#details-dialog').getByRole('button',{name:'Sluiten',exact:true}).click();
    await login('extern');await page.getByRole('button',{name:'Overzicht',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.booking-block.mine')?.textContent==='Mijn reservatie');
    await page.locator('.booking-block.mine').first().click();
    assert.equal(await page.locator('#external-edit-note').isVisible(),true);
    await page.locator('#f-start').fill('09:15');await page.locator('#submit-btn').click();
    await page.waitForFunction(()=>!document.querySelector('#booking-dialog').open);
    assert.match(await page.locator('#app-notice').innerText(),/Wijzigingen opgeslagen/);
    await page.locator('.booking-block.mine').first().click();await page.locator('#f-end').fill('11:00');
    await page.locator('#booking-dialog').evaluate(el=>el.scrollTop=0);
    await page.screenshot({path:`test-results/wijzigen-${viewport.width}.png`});
    await page.locator('#submit-btn').click();await page.waitForFunction(()=>!document.querySelector('#booking-dialog').open);
    assert.match(await page.locator('#app-notice').innerText(),/nieuw verzoek/);
    await page.waitForFunction(()=>document.querySelector('.booking-block.mine')?.textContent==='Mijn verzoek');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'nieuwe tabs passen op mobiel');
    await page.evaluate(()=>{
      rooms.push({id:"bad');window.__xss=true;//",name:'Veilige tekst',active:true});populateRoomSelect();renderOverview();
    });
    await page.locator('.room-row .reserve-btn-small').last().click();
    assert.equal(await page.evaluate(()=>window.__xss===true),false,'ruimtenaam/-ID breekt niet uit eventhandler');
    await page.getByRole('button',{name:'Uitloggen',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#rooms-grid').textContent.includes('Log in'));
    assert.deepEqual(errors,[]);passed++;console.log('PASS desktop/mobiel '+viewport.width+': bestaande flows plus rolverzoek wijzigen/intrekken, 5-secondenmelding, optionele motivatie, inclusieve reeks, gegroepeerde lijsten, overzichtvensters, organisatorgegevens, extern inkorten/opnieuw aanvragen, admin bewerken en layout');
    // Wacht op lopende API-routes voordat hun databaseverbindingen worden gesloten.
    await page.unrouteAll({behavior:'wait'});
    await page.close();
  }
  console.log(`BROWSER: ${passed} viewportscenario's geslaagd; alle netwerkverzoeken lokaal afgehandeld`);
}finally{await browser.close();for(const c of clients)await c.end();await env.stop();}
