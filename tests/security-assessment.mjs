// Bounded adversarial assessment. Only a disposable local database is touched.
// The old live baseline remains visible; release regressions must be PROTECTED.
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {startDatabase,applyBasis,applyConnectr,asUser} from './db-harness.mjs';
const env=await startDatabase(),db=env.db,results=[];
async function check(name,fn,kind='PROTECTED'){
  try{await fn();results.push({name,result:kind});console.log(kind+' '+name);}
  catch(error){results.push({name,result:'UNEXPECTED',error:error.message});console.error('UNEXPECTED '+name+': '+error.message);}
}
async function rpc(user,name,args={}){
  const keys=Object.keys(args);
  return (await asUser(db,user,`SELECT public.${name}(${keys.map((key,i)=>key+' => $'+(i+1)).join(',')}) AS result`,Object.values(args).map(v=>v&&typeof v==='object'?JSON.stringify(v):v))).rows[0].result;
}
const item={name:'Forged name',room_id:'W0.03',date:'2035-01-01',start_time:'09:00',end_time:'10:00',organization:'Sensitive organisation',occasion:'Test',description:'Private booking description'};
try{
  await applyBasis(db);
  await db.query("INSERT INTO public.profiles(id,display_name,role) VALUES ('user_admin','Admin Person','admin'),('user_victim','Victim Person','intern'),('user_attacker','External Person','extern')");
  await db.query("INSERT INTO public.support_messages(user_id,message) VALUES('user_victim','Legacy anonymous message')");
  await check('LIVE BASELINE: app admin can read the author ID in the legacy support table',async()=>{
    const rows=(await asUser(db,'user_admin','SELECT user_id FROM public.support_messages')).rows;
    assert.equal(rows[0].user_id,'user_victim');
  },'OBSERVED');
  await applyConnectr(db);
  for(const id of ['admin','victim','attacker'])await rpc('user_'+id,'han_save_profile',{first_name:id,last_name:'Person'});
  const booking=(await rpc('user_admin','han_admin_book',{items:[item],owner_id:'user_victim'})).ids[0];
  const caseId=await rpc('user_victim','han_create_case',{category:'complaint',anonymous:true,message:'Confidential anonymous message',contact_email:'private@example.invalid'});
  const otherCase=await rpc('user_attacker','han_create_case',{category:'question',anonymous:false,message:'External own question'});
  await check('anonymous callers cannot read application tables or invoke API functions',async()=>{
    for(const table of ['profiles','rooms','reserveringen','reserveringsverzoeken','role_requests'])await assert.rejects(()=>asUser(db,'anonymous','SELECT * FROM public.'+table),/permission denied/);
    await assert.rejects(()=>rpc('anonymous','han_cases'),/permission denied/);
  });
  await check('ordinary accounts and app admins cannot read or write private tables directly',async()=>{
    for(const user of ['user_attacker','user_admin'])for(const table of ['support_messages','case_messages','case_reads','notifications','transfers','write_budgets','audit_events','revoked_sessions','blocked_accounts','trusted_auth']){
      await assert.rejects(()=>asUser(db,user,'SELECT * FROM han_private.'+table),/permission denied/);
    }
  });
  await check('direct profile promotion and table writes are denied',async()=>{
    await assert.rejects(()=>asUser(db,'user_attacker',"UPDATE public.profiles SET role='admin' WHERE id='user_attacker'"),/permission denied/);
    await assert.rejects(()=>asUser(db,'user_attacker','DELETE FROM public.reserveringen WHERE id=$1',[booking]),/permission denied/);
  });
  await check('user-editable role metadata does not grant admin rights',async()=>{
    await db.query('BEGIN');
    try{
      await db.query('SET LOCAL ROLE authenticated');
      await db.query("SELECT set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:'user_attacker',sid:'sess_userattacker',role:'authenticated',iss:'https://alert-bat-50.clerk.accounts.dev',azp:'https://ruimte-reserveren.vercel.app',user_metadata:{role:'admin'},app_metadata:{role:'admin'}})]);
      await assert.rejects(()=>db.query("SELECT public.han_find_accounts('Person')"),/Alleen admins/);
    }finally{await db.query('ROLLBACK');}
  });
  await check('forged JSON owner, role, status and creator are ignored',async()=>{
    await rpc('user_attacker','han_create_bookings',{items:[{...item,date:'2035-02-01',user_id:'user_victim',created_by:'user_admin',status:'approved',role:'admin',name_override:true}]});
    const row=(await db.query("SELECT * FROM public.reserveringsverzoeken WHERE date='2035-02-01'")).rows[0];
    assert.equal(row.user_id,'user_attacker');assert.equal(row.created_by,'user_attacker');assert.equal(row.status,'pending');assert.equal(row.name,'attacker Person');
  });
  await check('guessed booking ID cannot be read, edited, cancelled or transferred by another user',async()=>{
    assert.equal((await asUser(db,'user_attacker','SELECT * FROM public.reserveringen WHERE id=$1',[booking])).rowCount,0);
    await assert.rejects(()=>rpc('user_attacker','han_edit',{kind:'booking',item_id:booking,scope:'single',item,expected_items:[]}),/Geen toegang/);
    await assert.rejects(()=>rpc('user_attacker','han_cancel',{kind:'booking',item_id:booking,scope:'series'}),/Geen toegang/);
    await assert.rejects(()=>rpc('user_attacker','han_preview_transfer',{kind:'booking',item_id:booking,scope:'single',new_owner:'user_attacker'}),/Alleen admins/);
    await assert.rejects(()=>rpc('user_attacker','han_admin_book',{items:[item],owner_id:'user_victim'}),/Alleen admins/);
  });
  await check('guessed case ID cannot be read, replied to, marked read or managed',async()=>{
    for(const [name,args] of [
      ['han_case_thread',{item_id:caseId}],['han_reply_case',{item_id:caseId,message:'Forged reply',expected_version:1}],
      ['han_case_read',{item_id:caseId,last_message:1}],['han_manage_case',{item_id:caseId,expected_version:1,new_status:'afgehandeld',category:'tip'}]
    ])await assert.rejects(()=>rpc('user_attacker',name,args),/CASE_UNAVAILABLE|Alleen admins/);
    await assert.rejects(()=>rpc('user_attacker','han_cases',{admin_view:true}),/Alleen admins/);
  });
  await check('anonymous author ID, name and supplied email absent from all app-admin conversation projections',async()=>{
    const data=JSON.stringify([await rpc('user_admin','han_cases',{admin_view:true}),await rpc('user_admin','han_case_thread',{item_id:caseId}),await rpc('user_admin','han_notifications')]);
    assert.doesNotMatch(data,/user_victim|victim Person|private@example.invalid/);
  });
  await check('cross-case message IDs cannot be used to mark another thread read',async()=>{
    const thread=await rpc('user_attacker','han_case_thread',{item_id:otherCase});
    await assert.rejects(()=>rpc('user_victim','han_case_read',{item_id:caseId,last_message:thread.messages[0].id}),/MESSAGE_UNAVAILABLE/);
  });
  await check('null or forged versions and transfer fingerprints cannot bypass conflict checks',async()=>{
    await assert.rejects(()=>rpc('user_admin','han_transfer',{kind:'booking',item_id:booking,scope:'single',new_owner:'user_attacker',fingerprint:null}),/STALE_ITEM/);
    await assert.rejects(()=>rpc('user_admin','han_edit',{kind:'booking',item_id:booking,scope:'single',item,expected_items:null}),/STALE_ITEM/);
    await assert.rejects(()=>rpc('user_victim','han_reply_case',{item_id:caseId,message:'No version supplied',expected_version:null}),/STALE_ITEM/);
  });
  await check('SQL metacharacters stay data and do not modify schema or roles',async()=>{
    await rpc('user_attacker','han_save_profile',{first_name:"Robert'); DROP TABLE public.profiles;--",last_name:'Literal'});
    assert.equal((await db.query("SELECT role FROM public.profiles WHERE id='user_attacker'")).rows[0].role,'extern');
    assert.equal((await db.query('SELECT count(*)::int AS n FROM public.profiles')).rows[0].n,3);
    assert.deepEqual(await rpc('user_admin','han_find_accounts',{search_text:"' OR 1=1 --"}),[]);
  });
  await check('NULL payloads and oversized batches rejected',async()=>{
    for(const items of [null,{},[],Array(521).fill(item)])await assert.rejects(()=>rpc('user_attacker','han_create_bookings',{items}));
    await assert.rejects(()=>rpc('user_attacker','han_create_case',{category:'tip',anonymous:null,message:'Invalid anonymity'}));
    await assert.rejects(()=>rpc('user_attacker','han_create_case',{category:'tip',anonymous:true,message:'x'.repeat(5001)}));
  });
  await check('retired support API cannot overwrite existing conversations',async()=>{
    await assert.rejects(()=>rpc('user_admin','han_handle_support',{item_id:caseId,new_status:'afgehandeld',note:'Overwrite'}),/APP_REFRESH_REQUIRED/);
    await assert.rejects(()=>rpc('user_attacker','han_support',{message:'Old endpoint'}),/APP_REFRESH_REQUIRED/);
  });
  await check('all private write helpers and all anonymous API execution are denied',async()=>{
    const {rows}=await db.query("SELECT n.nspname,p.proname,p.oid::regprocedure::text AS signature,has_function_privilege('anon',p.oid,'EXECUTE') AS anon,has_function_privilege('authenticated',p.oid,'EXECUTE') AS member FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='han_private' OR (n.nspname='public' AND (p.proname LIKE 'han_%' OR p.proname='import_reserveringen'))");
    for(const row of rows){assert.equal(row.anon,false,row.signature);if(row.nspname==='han_private'&&!['role','uid'].includes(row.proname))assert.equal(row.member,false,row.signature);}
  });
  await check('occupancy hides other owners identity; owner and admin retain it',async()=>{
    const data=await rpc('user_attacker','han_occupancy',{from_date:item.date,to_date:item.date});
    assert.equal(data[0].name,null);assert.equal(data[0].organization,null);assert.equal(data[0].id,null);
    for(const user of ['user_victim','user_admin']){
      const visible=await rpc(user,'han_occupancy',{from_date:item.date,to_date:item.date});
      assert.equal(visible[0].name,'victim Person');assert.equal(visible[0].organization,'Sensitive organisation');
    }
  });
  await check('per-account case quota rejects excess writes atomically without affecting other users',async()=>{
    for(let i=0;i<19;i++)await rpc('user_attacker','han_create_case',{category:'tip',anonymous:true,message:'Bounded local quota probe '+i});
    const before=(await db.query('SELECT count(*)::int AS n FROM han_private.case_messages')).rows[0].n;
    await assert.rejects(()=>rpc('user_attacker','han_create_case',{category:'tip',anonymous:true,message:'Quota must deny this'}),e=>e.code==='PT429');
    assert.equal((await db.query('SELECT count(*)::int AS n FROM han_private.case_messages')).rows[0].n,before);
    await rpc('user_victim','han_create_case',{category:'tip',anonymous:true,message:'Different user still allowed'});
  });
  await check('previous owner cannot see later status through old transfer notification',async()=>{
    const row=(await db.query("SELECT to_jsonb(r) AS r FROM public.reserveringsverzoeken r WHERE date='2035-02-01'")).rows[0].r;
    const args={kind:'request',item_id:row.id,scope:'single',new_owner:'user_victim'};
    const preview=await rpc('user_admin','han_preview_transfer',args);await rpc('user_admin','han_transfer',{...args,fingerprint:preview.fingerprint});
    const updated=(await db.query('SELECT to_jsonb(r) AS r FROM public.reserveringsverzoeken r WHERE id=$1',[row.id])).rows[0].r;
    await rpc('user_admin','han_decide_request',{item_id:row.id,scope:'single',approve:false,expected_items:[{id:row.id,updated_at:updated.updated_at}]});
    const note=(await rpc('user_attacker','han_notifications')).items.find(n=>n.item_id===row.id&&n.event_type==='transfer_out');
    assert.equal(note.accessible,false);assert.equal(note.current_status,null);
    const ownerNotes=await rpc('user_victim','han_notifications');
    assert.ok(ownerNotes.items.some(n=>n.item_id===row.id&&n.current_status==='rejected'));
  });
  await check('audit records actor and state changes without free text; app admins cannot alter logs',async()=>{
    const audit=(await db.query('SELECT * FROM han_private.audit_events ORDER BY id')).rows;
    assert.ok(audit.some(r=>r.actor_id==='user_admin'&&r.resource==='public.reserveringsverzoeken'&&r.after_state.status==='rejected'));
    assert.doesNotMatch(JSON.stringify(audit),/Confidential anonymous|Sensitive organisation|private@example.invalid|Bounded local/);
    for(const sql of ['DELETE FROM han_private.audit_events','UPDATE han_private.audit_events SET actor_id=NULL'])await assert.rejects(()=>asUser(db,'user_admin',sql),/permission denied/);
  });
  await check('concurrent submissions cannot overrun the last remaining quota slot',async()=>{
    await db.query("UPDATE han_private.write_budgets SET hour_units=19,day_units=19 WHERE user_id='user_attacker' AND operation='case_create'");
    const clients=await Promise.all([env.connect(),env.connect()]);
    try{
      const results=await Promise.allSettled(clients.map(client=>asUser(client,'user_attacker',"SELECT public.han_create_case('tip',true,'Concurrent budget test')")));
      assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
      assert.equal(results.filter(r=>r.status==='rejected'&&r.reason.code==='PT429').length,1);
      const row=(await db.query("SELECT * FROM han_private.write_budgets WHERE user_id='user_attacker' AND operation='case_create'")).rows[0];
      assert.equal(row.hour_units,20);
    }finally{await Promise.all(clients.map(c=>c.end()));}
  });
  await check('hour reset preserves daily limit; expiry of both windows restores allowance',async()=>{
    await db.query("UPDATE han_private.write_budgets SET hour_start=now()-interval '2 hours',day_units=100 WHERE user_id='user_attacker' AND operation='case_create'");
    await assert.rejects(()=>rpc('user_attacker','han_create_case',{category:'tip',anonymous:true,message:'Daily quota must deny this'}),e=>e.code==='PT429');
    await db.query("UPDATE han_private.write_budgets SET day_start=now()-interval '2 days' WHERE user_id='user_attacker' AND operation='case_create'");
    await rpc('user_attacker','han_create_case',{category:'tip',anonymous:true,message:'Expired budget permits submission'});
    const row=(await db.query("SELECT hour_units,day_units FROM han_private.write_budgets WHERE user_id='user_attacker' AND operation='case_create'")).rows[0];
    assert.equal(row.hour_units,1);assert.equal(row.day_units,1);
  });
  await check('series exceeding remaining budget creates no partial bookings, audit or notifications',async()=>{
    await db.query("UPDATE han_private.write_budgets SET hour_units=2079 WHERE user_id='user_admin' AND operation='booking_write'");
    const before=(await db.query('SELECT count(*)::int AS n FROM han_private.audit_events')).rows[0].n;
    await assert.rejects(()=>rpc('user_admin','han_admin_book',{items:[{...item,date:'2039-01-01'},{...item,date:'2039-01-02'}],owner_id:'user_victim'}),e=>e.code==='PT429');
    assert.equal((await db.query("SELECT count(*)::int AS n FROM public.reserveringen WHERE date>='2039-01-01'")).rows[0].n,0);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM han_private.audit_events')).rows[0].n,before);
  });
  await check('logout revokes the session for API and direct table reads',async()=>{
    await rpc('user_attacker','han_end_session');
    await assert.rejects(()=>rpc('user_attacker','han_cases'),/profiel ontbreekt/);
    assert.equal((await asUser(db,'user_attacker','SELECT * FROM public.reserveringsverzoeken')).rowCount,0);
    await assert.rejects(()=>rpc('user_attacker','han_ensure_profile',{display_name:null}),/Geen geldige Clerk/);
    assert.ok(Array.isArray(await rpc('user_victim','han_cases')));
    const fresh=await asUser(db,'user_attacker','SELECT public.han_cases() AS cases',[],'sess_freshlogin');
    assert.ok(Array.isArray(fresh.rows[0].cases),'a newly authenticated session has independent access');
  });
  await check('missing session ID, wrong issuer or unauthorized origin fail closed',async()=>{
    const claims={sub:'user_admin',sid:'sess_useradmin',role:'authenticated',iss:'https://alert-bat-50.clerk.accounts.dev',azp:'https://ruimte-reserveren.vercel.app'};
    for(const change of [{sid:null},{iss:'https://untrusted.invalid'},{azp:'https://lodiwigman.github.io'},{azp:null}]){
      await db.query('BEGIN');
      try{
        await db.query('SET LOCAL ROLE authenticated');
        await db.query("SELECT set_config('request.jwt.claims',$1,true)",[JSON.stringify({...claims,...change})]);
        assert.equal((await db.query('SELECT * FROM public.profiles')).rowCount,0);
        await assert.rejects(()=>db.query("SELECT public.han_find_accounts('Person')"),/Alleen admins/);
      }finally{await db.query('ROLLBACK');}
    }
  });
  await check('only an admin can block another account; all sessions then lose access',async()=>{
    await assert.rejects(()=>rpc('user_victim','han_block_account',{account_id:'user_admin'}),/Alleen admins/);
    await assert.rejects(()=>rpc('user_admin','han_block_account',{account_id:'user_admin'}),/ACCOUNT_UNAVAILABLE/);
    await rpc('user_admin','han_block_account',{account_id:'user_victim'});
    await assert.rejects(()=>rpc('user_victim','han_cases'),/profiel ontbreekt/);
    assert.equal((await asUser(db,'user_victim','SELECT * FROM public.profiles')).rowCount,0);
    assert.equal((await asUser(db,'user_victim','SELECT * FROM public.profiles',[],'sess_anotherdevice')).rowCount,0);
    await assert.rejects(()=>rpc('user_victim','han_ensure_profile',{display_name:null}),/Geen geldige Clerk/);
  });
}finally{
  await env.stop();await mkdir('test-results',{recursive:true});
  await writeFile('test-results/security-hardening.json',JSON.stringify({date:'2026-10-01',results},null,2));
}
// The embedded database shutdown may alter process.exitCode; fail after cleanup.
if(results.some(r=>r.result==='UNEXPECTED'))process.exit(1);
