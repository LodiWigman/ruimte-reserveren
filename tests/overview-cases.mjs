import assert from 'node:assert/strict';
import {startDatabase,applyBasis,applyConnectr,applyOverviewUpdates,asUser} from './db-harness.mjs';
const env=await startDatabase(),db=env.db;
let passed=0;
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
const rpc=async(user,name,args={})=>{
  const keys=Object.keys(args);
  return (await asUser(db,user,`SELECT public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) AS result`,Object.values(args).map(v=>v&&typeof v==='object'?JSON.stringify(v):v))).rows[0].result;
};
const item=(day='2037-01-01')=>({room_id:'W0.03',date:day,start_time:'09:00',end_time:'10:00',organization:'HAN research',occasion:'Meeting',name:'Import Name'});
try{
  await applyBasis(db);
  await db.query("INSERT INTO public.profiles(id,role) VALUES('user_admin','admin'),('user_intern','intern'),('user_extern','extern'),('user_other','extern')");
  await db.query("INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time) VALUES('user_intern','Legacy Name','W0.03','2036-01-01','09:00','10:00')");
  await applyConnectr(db);
  for(const role of ['admin','intern','extern','other'])await rpc('user_'+role,'han_save_profile',{first_name:role,last_name:'Tester'});
  const oldCase=await rpc('user_extern','han_create_case',{category:'complaint',anonymous:true,message:'Existing complaint'});
  await applyOverviewUpdates(db);
  await test('migration retains old reservation and case IDs without inventing organisations',async()=>{
    assert.equal((await db.query("SELECT organization FROM public.reserveringen WHERE date='2036-01-01'")).rows[0].organization,null);
    assert.equal((await rpc('user_extern','han_case_thread',{item_id:oldCase})).case.id,oldCase);
  });
  await test('every role must provide a nonblank organisation at the API boundary',async()=>{
    for(const role of ['admin','intern','extern'])for(const organization of [null,'','  ','\t\n']){
      await assert.rejects(()=>rpc('user_'+role,'han_create_bookings',{items:[{...item(),organization}]}),/Organisatie\/afdeling.*verplicht/);
    }
    await assert.rejects(()=>rpc('user_admin','han_admin_book',{items:[{...item(),organization:''}],guest_name:'Guest User'}),/Organisatie\/afdeling is verplicht/);
    await assert.rejects(()=>rpc('user_admin','import_reserveringen',{import_items:[{...item(),import_index:1,organization:''}]}),/Organisatie\/afdeling is verplicht/);
    assert.equal((await rpc('user_intern','han_create_bookings',{items:[item()]})).confirmed,1);
    assert.equal((await rpc('user_extern','han_create_bookings',{items:[item()]})).requested,1);
    assert.equal((await rpc('user_admin','han_availability',{items:[{room_id:'W0.03',date:'2037-02-01',start_time:'09:00',end_time:'10:00'}]}))[0].conflict,false);
  });
  await test('internals see organisation but do not gain other users names or item IDs',async()=>{
    const args={from_date:'2037-01-01',to_date:'2037-01-01'};
    const internal=await rpc('user_intern','han_occupancy',args);
    const request=internal.find(r=>r.status==='pending');
    assert.equal(request.organization,'HAN research');assert.equal(request.id,null);assert.equal(request.name,null);
    const outsider=await rpc('user_other','han_occupancy',args);
    for(const row of outsider){assert.equal(row.organization,null);assert.equal(row.name,null);assert.equal(row.id,null);}
    await assert.rejects(()=>rpc('anonymous','han_occupancy',args),/permission denied/);
  });
  await test('case access and archive operation remain restricted',async()=>{
    await assert.rejects(()=>rpc('user_other','han_case_thread',{item_id:oldCase}),/CASE_UNAVAILABLE/);
    await assert.rejects(()=>rpc('user_extern','han_manage_case',{item_id:oldCase,expected_version:1,new_status:'afgehandeld',category:'complaint',action:'archive'}),/Alleen admins/);
    await assert.rejects(()=>rpc('user_admin','han_manage_case',{item_id:oldCase,expected_version:1,new_status:'afgehandeld',category:'complaint',action:'archive'}),/ARCHIVE_RESOLVED_ONLY/);
  });
  let version;
  await test('a failed notification rolls back archival and its version change',async()=>{
    let c=(await rpc('user_admin','han_case_thread',{item_id:oldCase})).case;
    await rpc('user_admin','han_manage_case',{item_id:oldCase,expected_version:c.version,new_status:'afgehandeld',category:'complaint'});
    c=(await rpc('user_admin','han_case_thread',{item_id:oldCase})).case;version=c.version;
    await db.query("CREATE FUNCTION public.fail_archive_notice() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.event_type='case_archived' THEN RAISE EXCEPTION 'TEST_NOTIFICATION_FAILURE'; END IF; RETURN NEW; END $$; CREATE TRIGGER fail_archive_notice BEFORE INSERT ON han_private.notifications FOR EACH ROW EXECUTE FUNCTION public.fail_archive_notice()");
    await assert.rejects(()=>rpc('user_admin','han_manage_case',{item_id:oldCase,expected_version:version,new_status:'afgehandeld',category:'complaint',action:'archive'}),/TEST_NOTIFICATION_FAILURE/);
    c=(await rpc('user_admin','han_case_thread',{item_id:oldCase})).case;
    assert.equal(c.archived_at,null);assert.equal(c.version,version);
    await db.query('DROP TRIGGER fail_archive_notice ON han_private.notifications; DROP FUNCTION public.fail_archive_notice()');
  });
  await test('archive persists exactly one notice across retries and stays readable to its owner',async()=>{
    const args={item_id:oldCase,expected_version:version,new_status:'afgehandeld',category:'complaint',action:'archive'};
    assert.equal(await rpc('user_admin','han_manage_case',args),1);
    await assert.rejects(()=>rpc('user_admin','han_manage_case',args),/STALE_ITEM/);
    const notices=(await rpc('user_extern','han_notifications')).items.filter(n=>n.event_type==='case_archived');
    assert.equal(notices.length,1);assert.equal(notices[0].item_id,oldCase);assert.equal(notices[0].details.category,'complaint');assert.equal(notices[0].accessible,true);
    assert.equal((await rpc('user_extern','han_cases',{archived:true}))[0].id,oldCase);
    assert.equal((await rpc('user_other','han_notifications')).items.length,0);
  });
  await test('admin submitters receive their own archive notification too',async()=>{
    const id=await rpc('user_admin','han_create_case',{category:'tip',anonymous:false,message:'Admin tip'});
    let c=(await rpc('user_admin','han_case_thread',{item_id:id})).case;
    await rpc('user_admin','han_manage_case',{item_id:id,expected_version:c.version,new_status:'afgehandeld',category:'tip'});
    c=(await rpc('user_admin','han_case_thread',{item_id:id})).case;
    await rpc('user_admin','han_manage_case',{item_id:id,expected_version:c.version,new_status:'afgehandeld',category:'tip',action:'archive'});
    assert.equal((await rpc('user_admin','han_notifications')).items.filter(n=>n.event_type==='case_archived'&&n.item_id===id).length,1);
  });
  console.log(`OVERVIEW/CASES: ${passed} scenario's geslaagd`);
}finally{await env.stop();}
