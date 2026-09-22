import assert from 'node:assert/strict';
import {startDatabase,applyBasis,asUser} from './db-harness.mjs';
const env=await startDatabase(),db=env.db;
let passed=0;
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
const query=(user,sql,args)=>asUser(db,user,sql,args);
const rpc=async(user,name,args)=>{const keys=Object.keys(args);return (await query(user,`SELECT public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) AS result`,Object.values(args).map(v=>typeof v==='object'&&v!==null?JSON.stringify(v):v))).rows[0].result;};
const denied=async(fn,pattern)=>{await assert.rejects(fn,pattern);};
const item=(date='2030-01-07',start='09:00',room='W0.03')=>({name:'Test persoon',room_id:room,date,start_time:start,end_time:start==='09:00'?'10:00':'12:00',persons:2,description:'Privé omschrijving',organization:'HAN',occasion:'Overleg',motivation:'Test bijeenkomst'});
const count=async(table,where='true')=>Number((await db.query(`SELECT count(*) FROM public.${table} WHERE ${where}`)).rows[0].count);
try {
  await test('volledige lege opbouw + 18 ruimtes',async()=>{await applyBasis(db);assert.equal(await count('rooms'),18);assert.equal(await count('rooms','active'),17);});
  for(const id of ['user_admin','user_intern','user_extern','user_other'])await rpc(id,'han_ensure_profile',{display_name:id});
  await db.query("UPDATE public.profiles SET role=CASE id WHEN 'user_admin' THEN 'admin' WHEN 'user_intern' THEN 'intern' ELSE 'extern' END");
  await test('alle tabellen RLS + geen directe schrijfgrants',async()=>{
    const rows=(await db.query("SELECT relname,relrowsecurity FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind='r'")).rows;
    assert.equal(rows.length,6);assert.ok(rows.every(r=>r.relrowsecurity));
    for(const r of rows)for(const privilege of ['INSERT','UPDATE','DELETE','TRUNCATE'])assert.equal((await db.query('SELECT has_table_privilege($1,$2,$3) AS allowed',['authenticated','public.'+r.relname,privilege])).rows[0].allowed,false);
  });
  await test('uitgelogd: alle API-functies en tabellen ontoegankelijk',async()=>{
    await denied(()=>query('anonymous','SELECT * FROM public.rooms'),/permission denied/);
    const f=(await db.query("SELECT oid::regprocedure::text AS name FROM pg_proc WHERE pronamespace='public'::regnamespace AND (proname LIKE 'han_%' OR proname='import_reserveringen')")).rows;
    for(const row of f)assert.equal((await db.query('SELECT has_function_privilege($1,$2,$3) AS allowed',['anon',row.name,'EXECUTE'])).rows[0].allowed,false);
  });
  await test('veilige profielaanmaak en geen zelfpromotie',async()=>{
    assert.equal((await rpc('user_new','han_ensure_profile',{display_name:'Nieuwe gebruiker'})).role,'extern');
    assert.equal((await rpc('user_admin','han_ensure_profile',{display_name:'Nieuwe naam'})).role,'admin');
    await denied(()=>query('user_new',"UPDATE public.profiles SET role='admin' WHERE id='user_new'"),/permission denied/);
    await denied(()=>query('user_other',"INSERT INTO public.profiles(id,role) VALUES('user_forge','admin')"),/permission denied/);
    await denied(()=>query('user_new','SELECT han_private.add_booking($1,$2,NULL)',[JSON.stringify(item()),'user_admin']),/permission denied/);
  });
  await test('extern wordt verzoek, aangeleverde eigenaar/status genegeerd',async()=>{
    assert.deepEqual(await rpc('user_extern','han_create_bookings',{items:[{...item(),user_id:'user_admin',status:'approved',role:'admin'}]}),{confirmed:0,requested:1});
    const row=(await db.query('SELECT * FROM public.reserveringsverzoeken')).rows[0];assert.equal(row.user_id,'user_extern');assert.equal(row.status,'pending');
  });
  const request=(await db.query('SELECT id FROM public.reserveringsverzoeken')).rows[0].id;
  await test('intern reserveert direct; overlap wordt verzoek',async()=>{
    assert.equal((await rpc('user_intern','han_create_bookings',{items:[item('2030-01-08')]})).confirmed,1);
    assert.equal((await rpc('user_intern','han_create_bookings',{items:[item('2030-01-08')]})).requested,1);
  });
  const booking=(await db.query('SELECT id FROM public.reserveringen')).rows[0].id;
  await test('details van anderen onleesbaar, bezetting bevat uitsluitend minimale velden',async()=>{
    assert.equal((await query('user_other','SELECT * FROM public.reserveringen')).rowCount,0);
    assert.equal((await query('user_other','SELECT * FROM public.reserveringsverzoeken')).rowCount,0);
    const rows=await rpc('user_other','han_occupancy',{from_date:'2030-01-07',to_date:'2030-01-08'});
    assert.ok(rows.length);assert.deepEqual(Object.keys(rows[0]).sort(),['date','end_time','room_id','start_time','status']);
    assert.equal((await query('user_admin','SELECT * FROM public.reserveringen')).rowCount,1);
  });
  await test('andermans wijzigen/annuleren en beheerfuncties geweigerd',async()=>{
    await denied(()=>rpc('user_other','han_cancel',{kind:'booking',item_id:booking}),/Geen toegang/);
    await denied(()=>rpc('user_other','han_edit',{kind:'request',item_id:request,scope:'single',item:item()}),/Geen toegang/);
    await denied(()=>rpc('user_extern','han_decide_request',{item_id:request,scope:'single',approve:true}),/Alleen admins/);
    await denied(()=>rpc('user_intern','import_reserveringen',{import_items:[item()]}),/Alleen admins/);
    await denied(()=>rpc('user_intern','han_save_rooms',{items:[{id:'bad',name:'bad',active:true}]}),/Alleen admins/);
    await denied(()=>rpc('user_extern','han_decide_role',{item_id:request,approve:true}),/Alleen admins/);
  });
  await test('eigen open verzoek wijzigen, goedkeuren en nogmaals behandelen faalt',async()=>{
    assert.equal(await rpc('user_extern','han_edit',{kind:'request',item_id:request,scope:'single',item:item('2030-01-09')}),1);
    assert.equal(await rpc('user_admin','han_decide_request',{item_id:request,scope:'single',approve:true}),1);
    await denied(()=>rpc('user_admin','han_decide_request',{item_id:request,scope:'single',approve:true}),/niet gevonden of al behandeld/);
    await denied(()=>rpc('user_extern','han_edit',{kind:'request',item_id:request,scope:'single',item:item()}),/niet gevonden of al behandeld/);
  });
  await test('intern wijzigt eigen reservering; admin wijzigt geen andermans bevestigde reservering',async()=>{
    assert.equal(await rpc('user_intern','han_edit',{kind:'booking',item_id:booking,scope:'single',item:item('2030-01-10')}),1);
    await denied(()=>rpc('user_admin','han_edit',{kind:'booking',item_id:booking,scope:'single',item:item()}),/Alleen eigen/);
  });
  await test('nul gewijzigde rijen is een fout',async()=>{
    await rpc('user_intern','han_cancel',{kind:'booking',item_id:booking});
    await denied(()=>rpc('user_intern','han_cancel',{kind:'booking',item_id:booking}),/niet gevonden/);
    await denied(()=>rpc('user_admin','han_save_rooms',{items:[{original_id:'ontbreekt',name:'Test',active:true}]}),/niet gevonden/);
  });
  await test('rolverzoek atomair en slechts extern naar intern',async()=>{
    const id=await rpc('user_other','han_role_request',{full_name:'Andere gebruiker',job_title:'Docent',motivation:'Werkt bij HAN'});
    await denied(()=>rpc('user_other','han_role_request',{full_name:'Andere gebruiker',job_title:'Docent',motivation:'Werkt bij HAN'}),/duplicate key/);
    assert.equal(await rpc('user_admin','han_decide_role',{item_id:id,approve:true}),1);
    assert.equal((await query('user_other','SELECT role FROM public.profiles')).rows[0].role,'intern');
    await denied(()=>rpc('user_admin','han_decide_role',{item_id:id,approve:true}),/niet gevonden/);
  });
  await test('geen gedeeltelijke reeks bij mislukte goedkeuring',async()=>{
    await rpc('user_extern','han_create_bookings',{items:[item('2030-02-01'),item('2030-02-02')]});
    await rpc('user_intern','han_create_bookings',{items:[item('2030-02-02')]});
    const id=(await db.query("SELECT id FROM public.reserveringsverzoeken WHERE date='2030-02-01'")).rows[0].id;
    await denied(()=>rpc('user_admin','han_decide_request',{item_id:id,scope:'series',approve:true}),/exclusion constraint/);
    assert.equal(await count('reserveringen',"date='2030-02-01'"),0);
    assert.equal(await count('reserveringsverzoeken',"date BETWEEN '2030-02-01' AND '2030-02-02' AND status='pending'"),2);
    assert.equal(await rpc('user_admin','han_decide_request',{item_id:id,scope:'series',approve:false}),2);
  });
  await test('geen gedeeltelijke reekswijziging; omzetten en deze-en-volgende',async()=>{
    await rpc('user_intern','han_create_bookings',{items:[item('2030-03-01'),item('2030-03-02'),item('2030-03-03')]});
    await rpc('user_admin','han_create_bookings',{items:[item('2030-03-03','11:00')]});
    const id=(await db.query("SELECT id FROM public.reserveringen WHERE date='2030-03-02'")).rows[0].id;
    await denied(()=>rpc('user_intern','han_edit',{kind:'booking',item_id:id,scope:'series',item:item('2030-03-02','11:00')}),/exclusion constraint/);
    assert.equal(await count('reserveringen',"date='2030-03-02' AND start_time='09:00'"),1);
    assert.equal(await rpc('user_intern','han_edit',{kind:'booking',item_id:id,scope:'series',item:item('2030-03-02','11:00'),convert_to_request:true}),2);
    assert.equal(await count('reserveringen',"date='2030-03-01'"),1);
    assert.equal(await count('reserveringsverzoeken',"date BETWEEN '2030-03-02' AND '2030-03-03'"),2);
  });
  await test('alleen deze en volgende annuleren bewaart eerdere gebeurtenis',async()=>{
    await rpc('user_intern','han_create_bookings',{items:[item('2030-04-01'),item('2030-04-02'),item('2030-04-03')]});
    const id=(await db.query("SELECT id FROM public.reserveringen WHERE date='2030-04-02'")).rows[0].id;
    assert.equal(await rpc('user_intern','han_cancel',{kind:'booking',item_id:id,scope:'series'}),2);
    assert.equal(await count('reserveringen',"date='2030-04-01'"),1);
  });
  await test('import atomair, reeksverband en dubbel importeren',async()=>{
    const items=[{...item('2030-05-01'),recurrence_id:'outlook-series',import_index:1},{...item('2030-05-02'),recurrence_id:'outlook-series',import_index:2}];
    assert.equal((await rpc('user_admin','import_reserveringen',{import_items:items})).length,2);
    const series=(await db.query("SELECT count(DISTINCT recurrence_id) AS n FROM public.reserveringen WHERE date BETWEEN '2030-05-01' AND '2030-05-02'")).rows[0];assert.equal(Number(series.n),1);
    await denied(()=>rpc('user_admin','import_reserveringen',{import_items:[{...item('2030-05-03'),import_index:3},...items]}),/exclusion constraint/);
    assert.equal(await count('reserveringen',"date='2030-05-03'"),0);
  });
  await test('datums, minuten, aantallen, inactieve ruimte, DST en lege invoer',async()=>{
    for(const bad of [{...item(),date:'2030-02-30'},{...item(),start_time:'25:00'},{...item(),end_time:'09:00'},{...item(),persons:1.5},item('2030-01-01','09:00','W0.02'),{...item(),date:'2030-03-31',start_time:'02:15',end_time:'03:15'},{...item(),date:'2030-10-27',start_time:'02:15',end_time:'03:15'}])await denied(()=>rpc('user_intern','han_create_bookings',{items:[bad]}));
    await denied(()=>rpc('user_intern','han_create_bookings',{items:[]}));
    await denied(()=>rpc('user_extern','han_create_bookings',{items:[{...item(),motivation:null}]}),/verplicht/);
  });
  await test('support privacy en beheerreactie',async()=>{
    const id=await rpc('user_extern','han_support',{message:'Een testvraag voor de beheerder'});
    assert.equal((await query('user_other','SELECT * FROM public.support_messages')).rowCount,0);
    await denied(()=>rpc('user_extern','han_handle_support',{item_id:id,new_status:'afgehandeld',note:'Test'}),/Alleen admins/);
    assert.equal(await rpc('user_admin','han_handle_support',{item_id:id,new_status:'afgehandeld',note:'Beantwoord'}),1);
    assert.equal((await query('user_extern','SELECT admin_note FROM public.support_messages')).rows[0].admin_note,'Beantwoord');
  });
  await test('gelijktijdig reserveren geeft precies één boeking en één verzoek',async()=>{
    const a=await env.connect(),b=await env.connect();
    try{
      const results=await Promise.all([asUser(a,'user_intern','SELECT public.han_create_bookings($1) AS result',[JSON.stringify([item('2030-06-01')])]),asUser(b,'user_other','SELECT public.han_create_bookings($1) AS result',[JSON.stringify([item('2030-06-01')])])]);
      assert.equal(results.reduce((sum,r)=>sum+r.rows[0].result.confirmed,0),1);
      assert.equal(results.reduce((sum,r)=>sum+r.rows[0].result.requested,0),1);
    }finally{await a.end();await b.end();}
  });
  console.log(`DATABASE: ${passed} scenario's geslaagd op PostgreSQL ${(await db.query('SHOW server_version')).rows[0].server_version}`);
} finally {await env.stop();}
