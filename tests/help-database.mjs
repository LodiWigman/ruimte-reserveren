import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startDatabase,applyBasis,applyConnectr,applyOverviewUpdates,asUser} from './db-harness.mjs';
const env=await startDatabase();
try{
  await applyBasis(env.db);
  await env.db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_one','One','extern'),('user_two','Two','intern'),('user_admin','Admin','admin')");
  await applyConnectr(env.db);await applyOverviewUpdates(env.db);
  await env.db.query(await readFile('SQL/migrations/20261013122102_help_onboarding.sql','utf8'));
  const read=async user=>(await asUser(env.db,user,'SELECT public.han_help_progress() result')).rows[0].result;
  const mark=(user,key,status='completed')=>asUser(env.db,user,'SELECT public.han_help_mark($1,$2)',[key,status]);
  assert.deepEqual(await read('user_one'),[]);
  await mark('user_one','v1:intro:extern');
  await mark('user_one','v1:tab:overzicht:shared','skipped');
  await mark('user_one','v1:intro:extern','skipped');
  assert.deepEqual(await read('user_one'),['v1:intro:extern','v1:tab:overzicht:shared']);
  assert.deepEqual(await read('user_two'),[]);assert.deepEqual(await read('user_admin'),[]);
  assert.equal((await asUser(env.db,'user_admin','SELECT * FROM public.help_progress')).rowCount,0);
  await assert.rejects(asUser(env.db,'user_two',"INSERT INTO public.help_progress(user_id,guide_key,outcome) VALUES('user_one','v1:intro:admin','completed')"),/row-level security/);
  await assert.rejects(asUser(env.db,'user_one',"UPDATE public.help_progress SET user_id='user_two'"),/permission denied/);
  await assert.rejects(asUser(env.db,'user_one','DELETE FROM public.help_progress'),/permission denied/);
  await assert.rejects(mark('anonymous','v1:intro:extern'),/permission denied/);
  await assert.rejects(read('anonymous'),/permission denied/);
  await assert.rejects(mark('user_one','v1:intro:extern','anything'),/check constraint/);
  await assert.rejects(mark('user_one','arbitrary-unbounded-key'),/check constraint/);
  await assert.rejects(mark('user_one',null),/not-null constraint/);
  // Two devices add different acknowledgements without read/modify/write loss.
  const a=await env.connect(),b=await env.connect();
  try{await Promise.all([
    asUser(a,'user_one','SELECT public.han_help_mark($1,$2)',['v1:tab:mijn:extern','completed']),
    asUser(b,'user_one','SELECT public.han_help_mark($1,$2)',['v1:tab:vragen:extern','skipped'])
  ]);}finally{await a.end();await b.end();}
  assert.equal((await read('user_one')).length,4);
  // A forged acknowledgement cannot promote the account.
  await mark('user_one','v1:intro:admin');
  assert.equal((await env.db.query("SELECT role FROM public.profiles WHERE id='user_one'")).rows[0].role,'extern');
  await asUser(env.db,'user_one','SELECT public.han_end_session()');
  await assert.rejects(mark('user_one','v1:tab:beheer:admin'),/Log opnieuw in/);
  console.log('HELP DATABASE: own-account access, admin isolation, anonymous denial, validation, replay, concurrent devices, role separation and revoked sessions passed');
}finally{await env.stop();}
