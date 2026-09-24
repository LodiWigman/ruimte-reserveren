import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startDatabase,asUser} from './db-harness.mjs';
const env=await startDatabase(),db=env.db;
let passed=0;
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
const rpc=async(user,name,args)=>{
  const keys=Object.keys(args);
  return (await asUser(db,user,`SELECT public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) AS result`,Object.values(args).map(v=>v&&typeof v==='object'?JSON.stringify(v):v))).rows[0].result;
};
const item=(date,extra={})=>({name:'Organisator',organization:'HAN afdeling',occasion:'Overleg',motivation:null,description:null,room_id:'W0.03',date,start_time:'09:00',end_time:'11:00',persons:2,...extra});
const rows=async(table,where='true',args=[]) => (await db.query(`SELECT * FROM public.${table} WHERE ${where}`,args)).rows;
const approved=async(date,extra={})=>{
  await rpc('user_extern','han_create_bookings',{items:[item(date,extra)]});
  const request=(await rows('reserveringsverzoeken','date=$1 AND status=\'pending\'',[date]))[0];
  await rpc('user_admin','han_decide_request',{item_id:request.id,scope:'single',approve:true});
  return (await rows('reserveringen','date=$1',[date]))[0];
};
try{
  await db.query(await readFile('tests/fixtures/basis-before-workflows.sql','utf8'));
  await db.query(await readFile('SQL/startgegevens.sql','utf8'));
  await db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_admin','Beheerder','admin'),('user_extern','Extern','extern'),('user_other','Ander','extern'),('user_intern','Intern','intern')");
  const oldBooking=await approved('2032-01-01',{motivation:'Bestaande toelichting'});
  await rpc('user_intern','han_create_bookings',{items:[item('2032-01-02')]});
  const oldRole=await rpc('user_other','han_role_request',{full_name:'Ander persoon',job_title:'Medewerker',motivation:'Werk bij HAN'});
  const migration=await readFile('SQL/migrations/20260922151039_reservation_workflows.sql','utf8');
  await test('migratie kan volledig worden teruggedraaid zonder gegevensverlies',async()=>{
    await db.query('BEGIN');await db.query(migration);await db.query('ROLLBACK');
    assert.equal((await rows('reserveringsverzoeken',"status='approved'")).length,1);
    assert.equal((await rows('reserveringen','id=$1',[oldBooking.id])).length,1);
    assert.equal((await db.query("SELECT count(*) FROM information_schema.columns WHERE table_name='reserveringen' AND column_name='organization'")).rows[0].count,'0');
  });
  await test('migratie bewaart reserveringen en rollen, draagt metadata over en ruimt goedgekeurde verzoeken op',async()=>{
    await db.query('BEGIN');await db.query(migration);await db.query('COMMIT');
    const restored=(await rows('reserveringen','id=$1',[oldBooking.id]))[0];
    assert.equal(restored.organization,'HAN afdeling');assert.equal(restored.motivation,'Bestaande toelichting');
    assert.equal((await rows('reserveringen')).length,2);assert.equal((await rows('reserveringsverzoeken')).length,0);
    assert.equal((await rows('role_requests','id=$1',[oldRole]))[0].requested_role,'intern');
    assert.equal((await rows('profiles',"role='admin'")).length,1);assert.equal((await rows('rooms')).length,18);
  });
  await test('goedkeuring verwijdert verzoek en bewaart organisatie zonder verplichte motivatie',async()=>{
    const b=await approved('2032-02-01');assert.equal(b.organization,'HAN afdeling');assert.equal(b.motivation,null);
    assert.equal((await rows('reserveringsverzoeken',"date='2032-02-01'")).length,0);
  });
  await test('extern mag inkorten en omschrijving wijzigen zonder nieuwe goedkeuring',async()=>{
    const b=await approved('2032-02-02');
    await rpc('user_extern','han_edit',{kind:'booking',item_id:b.id,scope:'single',item:item('2032-02-02',{start_time:'09:30',end_time:'10:30',description:'Kort overleg'})});
    const actual=(await rows('reserveringen','id=$1',[b.id]))[0];assert.equal(actual.start_time,'09:30:00');assert.equal(actual.description,'Kort overleg');
    assert.equal((await rows('reserveringsverzoeken',"date='2032-02-02'")).length,0);
  });
  await test('extern krijgt bij eerder/later/andere datum/ruimte altijd een nieuw verzoek, ook met false-vlag',async()=>{
    const changes=[{start_time:'08:30'},{end_time:'11:30'},{date:'2032-03-20'},{room_id:'W0.07'}];
    for(let i=0;i<changes.length;i++){
      const date='2032-03-0'+(i+1),b=await approved(date),next=item(date,changes[i]);
      await rpc('user_extern','han_edit',{kind:'booking',item_id:b.id,scope:'single',item:next,convert_to_request:false});
      assert.equal((await rows('reserveringen','id=$1',[b.id])).length,0);
      const request=(await rows('reserveringsverzoeken','date=$1 AND room_id=$2',[next.date,next.room_id]))[0];
      assert.equal(request.status,'pending');assert.equal(request.user_id,'user_extern');assert.equal(request.conflict,false);
    }
  });
  await test('bezettingsgegevens tonen eigenaarlabel en alleen bedoelde organisatorvelden',async()=>{
    const other=await rpc('user_other','han_occupancy',{from_date:'2032-02-01',to_date:'2032-02-02'});
    assert.ok(other.every(x=>x.id===null&&!x.mine&&x.name==='Organisator'&&x.organization==='HAN afdeling'));
    assert.ok(other.every(x=>!('motivation' in x)&&!('description' in x)&&!('user_id' in x)));
    const own=await rpc('user_extern','han_occupancy',{from_date:'2032-02-01',to_date:'2032-02-02'});assert.ok(own.every(x=>x.id&&x.mine));
    const admin=await rpc('user_admin','han_occupancy',{from_date:'2032-02-01',to_date:'2032-02-02'});assert.ok(admin.every(x=>x.id&&!x.mine));
    const pending=await rpc('user_other','han_occupancy',{from_date:'2032-03-01',to_date:'2032-03-04'});assert.ok(pending.every(x=>x.id===null&&x.name===null&&x.organization===null));
  });
  await test('nieuwe rolverzoeken wijzigen/intrekken, eigenaarschap en admin-goedkeuring',async()=>{
    await assert.rejects(()=>rpc('user_extern','han_edit_role_request',{item_id:oldRole,full_name:'Ander',job_title:'Docent',motivation:'Toelichting',requested_role:'admin'}),/eigen rolverzoek/);
    await assert.rejects(()=>rpc('user_extern','han_cancel_role_request',{item_id:oldRole}),/eigen rolverzoek/);
    await rpc('user_other','han_edit_role_request',{item_id:oldRole,full_name:'Ander persoon',job_title:'Docent',motivation:'Beheert locaties',requested_role:'admin'});
    assert.equal((await rows('profiles',"id='user_other'"))[0].role,'extern');
    await assert.rejects(()=>rpc('user_other','han_decide_role',{item_id:oldRole,approve:true}),/Alleen admins/);
    await rpc('user_admin','han_decide_role',{item_id:oldRole,approve:true});assert.equal((await rows('profiles',"id='user_other'"))[0].role,'admin');
    await assert.rejects(()=>rpc('user_other','han_cancel_role_request',{item_id:oldRole}),/eigen rolverzoek/);
    const args={full_name:'Externe persoon',job_title:'Docent',motivation:'Werk bij HAN',requested_role:'admin'};
    const id=await rpc('user_extern','han_role_request',args);
    await assert.rejects(()=>rpc('user_extern','han_role_request',args),/duplicate key/);
    await rpc('user_extern','han_cancel_role_request',{item_id:id});
    await assert.rejects(()=>rpc('user_extern','han_cancel_role_request',{item_id:id}),/eigen rolverzoek/);
    await assert.rejects(()=>rpc('user_intern','han_role_request',{...args,requested_role:'intern'}),/niet aanvragen/);
    await assert.rejects(()=>rpc('user_extern','han_role_request',{...args,requested_role:'owner'}),/niet aanvragen/);
    const internal=await rpc('user_intern','han_role_request',args);
    await rpc('user_admin','han_decide_role',{item_id:internal,approve:false});assert.equal((await rows('profiles',"id='user_intern'"))[0].role,'intern');
  });
  await test('extern reeks wijzigen is atomair; eerdere momenten blijven behouden',async()=>{
    const dates=['2032-04-01','2032-04-02','2032-04-03'];
    await rpc('user_extern','han_create_bookings',{items:dates.map(d=>item(d))});
    let first=(await rows('reserveringsverzoeken','date=$1',[dates[0]]))[0];
    await rpc('user_admin','han_decide_request',{item_id:first.id,scope:'series',approve:true});
    first=(await rows('reserveringen','date=$1',[dates[1]]))[0];
    await assert.rejects(()=>rpc('user_extern','han_edit',{kind:'booking',item_id:first.id,scope:'series',item:item(dates[1],{end_time:'12:00',persons:1.5})}));
    assert.equal((await rows('reserveringen',"date BETWEEN '2032-04-01' AND '2032-04-03'")).length,3);
    assert.equal((await rows('reserveringsverzoeken',"date BETWEEN '2032-04-01' AND '2032-04-03'")).length,0);
    await rpc('user_extern','han_edit',{kind:'booking',item_id:first.id,scope:'series',item:item(dates[1],{end_time:'12:00'})});
    assert.equal((await rows('reserveringen',"date BETWEEN '2032-04-01' AND '2032-04-03'")).length,1);
    const requests=await rows('reserveringsverzoeken',"date BETWEEN '2032-04-01' AND '2032-04-03'");
    assert.equal(requests.length,2);assert.equal(requests[0].recurrence_id,requests[1].recurrence_id);
    assert.ok(requests.every(r=>!r.conflict));
  });
  await test('admin kan reservering van extern direct wijzigen zonder eigenaar te veranderen',async()=>{
    const b=await approved('2032-05-01');
    await rpc('user_admin','han_edit',{kind:'booking',item_id:b.id,scope:'single',item:item('2032-05-02',{end_time:'12:00',user_id:'user_admin'})});
    assert.equal((await rows('reserveringen','id=$1',[b.id]))[0].user_id,'user_extern');
    await assert.rejects(()=>rpc('user_intern','han_edit',{kind:'booking',item_id:b.id,scope:'single',item:item('2032-05-03')}),/Geen toegang/);
  });
  await test('nieuwe functiegrants laten geen anonieme toegang of rechtstreekse writes toe',async()=>{
    for(const role of ['anon','authenticated'])for(const table of ['profiles','reserveringen','role_requests'])assert.equal((await db.query("SELECT has_table_privilege($1,$2,'UPDATE') AS allowed",[role,'public.'+table])).rows[0].allowed,false);
    const functions=(await db.query("SELECT oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'han_%'")).rows;
    for(const f of functions)assert.equal((await db.query("SELECT has_function_privilege('anon',$1,'EXECUTE') AS allowed",[f.oid])).rows[0].allowed,false);
  });
  console.log(`WORKFLOWS: ${passed} scenario's geslaagd`);
}finally{await env.stop();}
