import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startDatabase,applyBasis,asUser} from './db-harness.mjs';
const env=await startDatabase(),db=env.db;
let passed=0;
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
const rpcOn=async(client,user,name,args={})=>{
  if(['han_edit','han_decide_request'].includes(name)&&!('expected_items' in args)){
    const table=args.kind==='booking'?'reserveringen':'reserveringsverzoeken';
    const {rows}=await client.query(`SELECT to_jsonb(r) AS item FROM public.${table} r WHERE id=$1`,[args.item_id]);
    args={...args,expected_items:rows.map(r=>({id:r.item.id,updated_at:r.item.updated_at}))};
  }
  const keys=Object.keys(args);
  return (await asUser(client,user,`SELECT public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) AS result`,
    Object.values(args).map(v=>v!==null&&typeof v==='object'?JSON.stringify(v):v))).rows[0].result;
};
const rpc=(user,name,args)=>rpcOn(db,user,name,args);
const item=(date='2034-01-02')=>({name:'Untrusted browser name',room_id:'W0.03',date,start_time:'09:00',end_time:'11:00',organization:'HAN',occasion:'Meeting'});
const get=async(sql,args=[])=> (await db.query(sql,args)).rows;
try{
  await applyBasis(db);
  await db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_admin','old.admin','admin'),('user_admin2','Other admin','admin'),('user_extern','legacy.mail','extern'),('user_intern','Internal person','intern'),('user_other','Other person','extern')");
  await db.query("INSERT INTO public.support_messages(user_id,message,admin_note,handled_by,handled_at,status) VALUES('user_extern','Original legacy message','Existing reply','user_admin','2026-09-21T10:00:00Z','afgehandeld')");
  await db.query("INSERT INTO public.support_messages(user_id,message,admin_note,status) VALUES('user_extern','Second legacy message','Reply without recorded sender or time','afgehandeld')");
  await db.query("INSERT INTO public.reserveringen(user_id,name,room_id,date,start_time,end_time) VALUES('user_extern','Historic name','W0.03','2020-01-01','09:00','10:00'),('user_extern','Legacy future name','W0.03','2033-01-01','09:00','10:00')");
  await test('failed Connectr migration rolls back schema and keeps all existing data',async()=>{
    const sql=await readFile('SQL/migrations/20260929192403_connectr_profiles_conversations.sql','utf8');
    await assert.rejects(()=>db.query(sql.replace(/COMMIT;\s*$/,'SELECT deliberately_missing_function(); COMMIT;')),/deliberately_missing_function/);
    await db.query('ROLLBACK');
    assert.equal((await get('SELECT count(*)::int AS n FROM public.support_messages'))[0].n,2);
    assert.equal((await get("SELECT to_regclass('han_private.notifications') AS table_name"))[0].table_name,null);
  });
  await test('migration preserves legacy rows, reply, timestamps and status',async()=>{
    await db.query(await readFile('SQL/migrations/20260929192403_connectr_profiles_conversations.sql','utf8'));
    const [c]=await get("SELECT * FROM han_private.support_messages WHERE message='Original legacy message'");
    assert.equal(c.status,'afgehandeld');assert.equal(c.archived_at,null);assert.equal(c.category,'unclassified');
    const rows=await get('SELECT * FROM han_private.case_messages ORDER BY id');
    assert.equal(rows.length,4);
    const reply=rows.find(r=>r.body==='Existing reply');assert.equal(reply.created_at.toISOString(),'2026-09-21T10:00:00.000Z');
    const unknown=rows.find(r=>r.body==='Reply without recorded sender or time');assert.equal(unknown.created_at,null);assert.equal(unknown.author_id,null);
    assert.equal((await get('SELECT * FROM public.reserveringen')).length,2);
  });
  await test('profile completion required; email-like legacy names do not count',async()=>{
    await assert.rejects(()=>rpc('user_extern','han_create_bookings',{items:[item()]}),/PROFILE_REQUIRED/);
    assert.equal((await rpc('user_fresh','han_ensure_profile',{display_name:'guessed.from.email'})).display_name,null);
    await assert.rejects(()=>rpc('user_fresh','han_save_profile',{first_name:'',last_name:'Test'}),/NAME_INVALID/);
    for(const [id,first,last] of [['admin','Ada','Admin'],['admin2','Bert','Admin'],['extern','Eva','Extern'],['intern','Iris','Intern'],['other','Omar','Other']]){
      await rpc('user_'+id,'han_save_profile',{first_name:first,last_name:last});
    }
    const rows=await get('SELECT name FROM public.reserveringen ORDER BY date');
    assert.deepEqual(rows.map(r=>r.name),['Historic name','Eva Extern']);
  });
  await test('private tables and helper functions inaccessible even to app admins',async()=>{
    for(const table of ['support_messages','case_messages','case_reads','notifications','transfers']){
      await assert.rejects(()=>asUser(db,'user_admin','SELECT * FROM han_private.'+table),/permission denied/);
      assert.equal((await get("SELECT relrowsecurity FROM pg_class WHERE oid=$1::regclass",['han_private.'+table]))[0].relrowsecurity,true);
    }
    await assert.rejects(()=>rpc('anonymous','han_cases'),/permission denied/);
    await assert.rejects(()=>asUser(db,'user_admin',"SELECT han_private.case_summary(c) FROM han_private.support_messages c"),/permission denied/);
  });
  let booking,guest;
  await test('admin books for existing account, directly confirmed and correctly owned',async()=>{
    booking=(await rpc('user_admin','han_admin_book',{items:[item()],owner_id:'user_extern'})).ids[0];
    const [b]=await get('SELECT * FROM public.reserveringen WHERE id=$1',[booking]);
    assert.equal(b.user_id,'user_extern');assert.equal(b.created_by,'user_admin');assert.equal(b.name,'Eva Extern');
    assert.equal((await asUser(db,'user_extern','SELECT * FROM public.reserveringen WHERE id=$1',[booking])).rowCount,1);
    assert.ok((await rpc('user_extern','han_notifications')).items.some(n=>n.event_type==='booking_by_admin'));
    await assert.rejects(()=>rpc('user_other','han_admin_book',{items:[item('2034-02-01')],owner_id:'user_extern'}),/Alleen admins/);
  });
  await test('guest name survives admin rename; creator and owner remain distinct after transfer',async()=>{
    guest=(await rpc('user_admin','han_admin_book',{items:[item('2034-02-01')],guest_name:'Guest Person'})).ids[0];
    await rpc('user_admin','han_save_profile',{first_name:'Ada',last_name:'Adminnew'});
    assert.equal((await get('SELECT name FROM public.reserveringen WHERE id=$1',[guest]))[0].name,'Guest Person');
    const args={kind:'booking',item_id:guest,scope:'single',new_owner:'user_other'};
    const preview=await rpc('user_admin','han_preview_transfer',args);
    assert.equal(await rpc('user_admin','han_transfer',{...args,fingerprint:preview.fingerprint}),1);
    const [b]=await get('SELECT * FROM public.reserveringen WHERE id=$1',[guest]);
    assert.equal(b.user_id,'user_other');assert.equal(b.name,'Omar Other');assert.equal(b.created_by,'user_admin');assert.equal(b.name_override,false);
    assert.equal((await get('SELECT * FROM han_private.transfers WHERE item_id=$1',[guest])).length,1);
  });
  await test('external shortening stays confirmed; expansion becomes pending request',async()=>{
    await rpc('user_extern','han_edit',{kind:'booking',item_id:booking,scope:'single',item:{...item(),start_time:'09:30',end_time:'10:30'}});
    assert.equal((await get('SELECT * FROM public.reserveringen WHERE id=$1',[booking])).length,1);
    await rpc('user_extern','han_edit',{kind:'booking',item_id:booking,scope:'single',item:{...item(),end_time:'12:00'}});
    assert.equal((await get('SELECT * FROM public.reserveringen WHERE id=$1',[booking])).length,0);
    const [r]=await get("SELECT * FROM public.reserveringsverzoeken WHERE date='2034-01-02'");assert.equal(r.status,'pending');assert.equal(r.user_id,'user_extern');assert.equal(r.name,'Eva Extern');
  });
  await test('transfer open request retains pending; loses old personal access; rejects stale preview',async()=>{
    const [r]=await get("SELECT * FROM public.reserveringsverzoeken WHERE date='2034-01-02'");
    const args={kind:'request',item_id:r.id,scope:'single',new_owner:'user_other'};
    const preview=await rpc('user_admin','han_preview_transfer',args);
    await rpc('user_admin','han_transfer',{...args,fingerprint:preview.fingerprint});
    assert.equal((await get('SELECT status FROM public.reserveringsverzoeken WHERE id=$1',[r.id]))[0].status,'pending');
    assert.equal((await asUser(db,'user_extern','SELECT * FROM public.reserveringsverzoeken WHERE id=$1',[r.id])).rowCount,0);
    assert.equal((await asUser(db,'user_other','SELECT * FROM public.reserveringsverzoeken WHERE id=$1',[r.id])).rowCount,1);
    await assert.rejects(()=>rpc('user_admin','han_transfer',{...args,fingerprint:preview.fingerprint}),/STALE_ITEM/);
    await assert.rejects(()=>rpc('user_extern','han_edit',{kind:'request',item_id:r.id,scope:'single',item:item()}),/Geen toegang/);
    assert.ok((await rpc('user_extern','han_notifications')).items.some(n=>n.event_type==='transfer_out'&&!n.accessible));
    assert.ok((await rpc('user_other','han_notifications')).items.some(n=>n.event_type==='transfer_in'));
    await rpc('user_admin','han_decide_request',{item_id:r.id,scope:'single',approve:true});
    assert.ok((await rpc('user_other','han_notifications')).items.some(n=>n.event_type==='request_approved'&&n.accessible));
  });
  await test('series transfer moves only selected and later occurrences; stale concurrent admin denied',async()=>{
    const ids=(await rpc('user_admin','han_admin_book',{items:[item('2035-01-01'),item('2035-01-02'),item('2035-01-03')],owner_id:'user_extern'})).ids;
    const args={kind:'booking',item_id:ids[1],scope:'series',new_owner:'user_intern'};
    const preview=await rpc('user_admin','han_preview_transfer',args);assert.equal(preview.count,2);
    const a=await env.connect(),b=await env.connect();
    try{
      const outcomes=await Promise.allSettled([rpcOn(a,'user_admin','han_transfer',{...args,fingerprint:preview.fingerprint}),rpcOn(b,'user_admin2','han_transfer',{...args,fingerprint:preview.fingerprint})]);
      assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
    }finally{await a.end();await b.end();}
    assert.equal((await get('SELECT user_id FROM public.reserveringen WHERE id=$1',[ids[0]]))[0].user_id,'user_extern');
    assert.equal((await get('SELECT user_id FROM public.reserveringen WHERE id=$1',[ids[2]]))[0].user_id,'user_intern');
  });
  let anonymous,named;
  await test('anonymous identity absent from lists, thread, replies and admin notifications',async()=>{
    anonymous=await rpc('user_extern','han_create_case',{category:'complaint',anonymous:true,message:'Anonymous original body',contact_email:'hidden@test.invalid'});
    let data=await rpc('user_admin','han_case_thread',{item_id:anonymous});
    assert.equal(data.case.contact_email,null);assert.equal(data.case.name,null);
    await rpc('user_admin','han_reply_case',{item_id:anonymous,message:'Admin first reply',expected_version:data.case.version});
    data=await rpc('user_extern','han_case_thread',{item_id:anonymous});
    assert.equal(data.messages[1].author_name,'Ada Adminnew');
    await rpc('user_extern','han_save_profile',{first_name:'Changed',last_name:'Identity'});
    await rpc('user_extern','han_reply_case',{item_id:anonymous,message:'User follow-up',expected_version:data.case.version});
    const exposed=JSON.stringify([await rpc('user_admin','han_cases',{admin_view:true}),await rpc('user_admin','han_case_thread',{item_id:anonymous}),await rpc('user_admin','han_notifications')]);
    assert.doesNotMatch(exposed,/user_extern|Changed Identity|Eva Extern|hidden@test.invalid/);
    await assert.rejects(()=>rpc('user_other','han_case_thread',{item_id:anonymous}),/CASE_UNAVAILABLE/);
  });
  await test('named case contact visible only to admins; independent unread and saved notifications',async()=>{
    named=await rpc('user_other','han_create_case',{category:'question',anonymous:false,message:'Named question here',contact_email:'contact@test.invalid'});
    const adminThread=await rpc('user_admin','han_case_thread',{item_id:named});
    assert.equal(adminThread.case.name,'Omar Other');assert.equal(adminThread.case.contact_email,'contact@test.invalid');
    assert.equal((await rpc('user_other','han_case_thread',{item_id:named})).case.contact_email,null);
    await rpc('user_admin','han_case_read',{item_id:named,last_message:adminThread.messages.at(-1).id});
    assert.equal((await rpc('user_admin','han_case_thread',{item_id:named})).case.unread,0);
    assert.ok((await rpc('user_admin2','han_case_thread',{item_id:named})).case.unread>0);
    const notifications=await rpc('user_admin2','han_notifications');
    const n=notifications.items.find(n=>n.item_id===named);assert.equal(n.read_at,null);
    await rpc('user_admin2','han_read_notification',{notification_id:n.id});
    assert.ok((await rpc('user_admin2','han_notifications')).items.find(i=>i.id===n.id).read_at);
    await assert.rejects(()=>rpc('user_other','han_read_notification',{notification_id:n.id}),/NOTIFICATION_UNAVAILABLE/);
  });
  await test('shared conversation, resolve/reopen/archive; no messages accepted in archive',async()=>{
    let thread=await rpc('user_admin','han_case_thread',{item_id:named});
    await rpc('user_admin','han_reply_case',{item_id:named,message:'First admin answer',expected_version:thread.case.version});
    thread=await rpc('user_admin2','han_case_thread',{item_id:named});
    assert.equal(thread.messages.at(-1).body,'First admin answer');
    await rpc('user_admin2','han_manage_case',{item_id:named,expected_version:thread.case.version,new_status:'afgehandeld',category:'question'});
    thread=await rpc('user_other','han_case_thread',{item_id:named});
    await rpc('user_other','han_reply_case',{item_id:named,message:'Please reopen',expected_version:thread.case.version});
    thread=await rpc('user_admin','han_case_thread',{item_id:named});assert.equal(thread.case.status,'open');
    await assert.rejects(()=>rpc('user_admin','han_manage_case',{item_id:named,expected_version:thread.case.version,new_status:'afgehandeld',category:'question',action:'archive'}),/ARCHIVE_RESOLVED_ONLY/);
    await rpc('user_admin','han_manage_case',{item_id:named,expected_version:thread.case.version,new_status:'afgehandeld',category:'question'});
    thread=await rpc('user_admin','han_case_thread',{item_id:named});
    await rpc('user_admin','han_manage_case',{item_id:named,expected_version:thread.case.version,new_status:'afgehandeld',category:'question',action:'archive'});
    thread=await rpc('user_other','han_case_thread',{item_id:named});
    await assert.rejects(()=>rpc('user_other','han_reply_case',{item_id:named,message:'Blocked',expected_version:thread.case.version}),/CASE_ARCHIVED/);
    assert.equal((await rpc('user_admin2','han_cases',{admin_view:true})).some(c=>c.id===named),false);
    assert.equal((await rpc('user_other','han_cases',{archived:true})).length,1);
    assert.equal((await rpc('user_extern','han_cases',{archived:true})).length,0);
    await rpc('user_admin2','han_manage_case',{item_id:named,expected_version:thread.case.version,new_status:'open',category:'question',action:'reopen'});
    assert.equal((await rpc('user_other','han_case_thread',{item_id:named})).messages.length,3);
  });
  await test('role request uses profile; own approval prohibited; rejection notifies owner',async()=>{
    const id=await rpc('user_intern','han_role_request',{full_name:'Forged name',job_title:'Coordinator',motivation:'Help planning',requested_role:'admin'});
    assert.equal((await get('SELECT full_name FROM public.role_requests WHERE id=$1',[id]))[0].full_name,'Iris Intern');
    await rpc('user_admin','han_decide_role',{item_id:id,approve:false});
    assert.ok((await rpc('user_intern','han_notifications')).items.some(n=>n.event_type==='role_rejected'));
    const own=await rpc('user_intern','han_role_request',{full_name:'Iris Intern',job_title:'Coordinator',motivation:'Help planning',requested_role:'admin'});
    await db.query("UPDATE public.profiles SET role='admin' WHERE id='user_intern'");
    await assert.rejects(()=>rpc('user_intern','han_decide_role',{item_id:own,approve:true}),/geen eigen rolverzoek/);
    await db.query("UPDATE public.profiles SET role='intern' WHERE id='user_intern'");
  });
  await test('admin edits reject stale snapshots and do not overwrite another admin',async()=>{
    const id=(await rpc('user_admin','han_admin_book',{items:[item('2037-01-01')],owner_id:'user_other'})).ids[0];
    const [row]=await get('SELECT to_jsonb(b) AS b FROM public.reserveringen b WHERE id=$1',[id]);
    const args={kind:'booking',item_id:id,scope:'single',item:{...item('2037-01-01'),description:'First admin edit'},expected_items:[{id,updated_at:row.b.updated_at}]};
    await rpc('user_admin','han_edit',args);
    await assert.rejects(()=>rpc('user_admin2','han_edit',{...args,item:{...args.item,description:'Stale second edit'}}),/STALE_ITEM/);
    assert.equal((await get('SELECT description FROM public.reserveringen WHERE id=$1',[id]))[0].description,'First admin edit');
    assert.ok((await rpc('user_other','han_notifications')).items.some(n=>n.item_id===id&&n.event_type==='booking_changed'));
    await rpc('user_admin','han_cancel',{kind:'booking',item_id:id,scope:'single'});
    assert.ok((await rpc('user_other','han_notifications')).items.some(n=>n.item_id===id&&n.event_type==='booking_cancelled'&&!n.accessible));
  });
  await test('reading a previously fetched thread keeps a newer reply unread',async()=>{
    const id=await rpc('user_other','han_create_case',{category:'tip',anonymous:true,message:'Read race scenario'});
    const old=await rpc('user_admin','han_case_thread',{item_id:id});
    await rpc('user_other','han_reply_case',{item_id:id,message:'A newer message',expected_version:old.case.version});
    const read=await rpc('user_admin','han_case_read',{item_id:id,last_message:old.messages.at(-1).id});
    assert.equal(read.unread,1);
    const notes=(await rpc('user_admin','han_notifications')).items.filter(n=>n.item_id===id);
    assert.equal(notes.filter(n=>!n.read_at).length,1);
    assert.equal(notes.find(n=>!n.read_at).event_type,'case_user_reply');
  });
  await test('approval rejects a request changed since the admin last viewed it',async()=>{
    await rpc('user_other','han_create_bookings',{items:[item('2037-04-01')]});
    const [row]=await get("SELECT to_jsonb(r) AS r FROM public.reserveringsverzoeken r WHERE date='2037-04-01'");
    const args={item_id:row.r.id,scope:'single',approve:true,expected_items:[{id:row.r.id,updated_at:row.r.updated_at}]};
    await rpc('user_admin2','han_edit',{kind:'request',item_id:row.r.id,scope:'single',item:{...item('2037-04-01'),description:'Changed by the other admin'}});
    await assert.rejects(()=>rpc('user_admin','han_decide_request',args),/STALE_ITEM/);
    assert.equal((await get('SELECT status FROM public.reserveringsverzoeken WHERE id=$1',[row.r.id]))[0].status,'pending');
    await rpc('user_admin','han_decide_request',{item_id:row.r.id,scope:'single',approve:true});
  });
  await test('no own-action notifications; account search is admin-only and returns checked IDs',async()=>{
    const id=(await rpc('user_admin','han_admin_book',{items:[item('2037-03-01')],owner_id:'user_admin'})).ids[0];
    assert.equal((await rpc('user_admin','han_notifications')).items.some(n=>n.item_id===id),false);
    await assert.rejects(()=>rpc('user_other','han_find_accounts',{search_text:'Admin'}),/Alleen admins/);
    const matches=await rpc('user_admin','han_find_accounts',{search_text:'user_admin2'});
    assert.equal(matches.length,1);assert.equal(matches[0].id,'user_admin2');assert.equal(matches[0].complete,true);
  });
  await test('API function grants deny anonymous callers and all private write helpers',async()=>{
    const rows=await get("SELECT p.oid::regprocedure::text AS signature,n.nspname,p.proname,has_function_privilege('anon',p.oid,'execute') AS anon,has_function_privilege('authenticated',p.oid,'execute') AS member FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='han_private' OR (n.nspname='public' AND p.proname LIKE 'han_%')");
    for(const row of rows){assert.equal(row.anon,false,row.signature);if(row.nspname==='han_private'&&!['uid','role'].includes(row.proname))assert.equal(row.member,false,row.signature);}
  });
  console.log(`CONNECTR: ${passed} scenario's geslaagd`);
}finally{await env.stop();}
