import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startDatabase} from './db-harness.mjs';
const env=await startDatabase();
try {
  await env.db.query(await readFile('tests/legacy-schema.sql','utf8'));
  await env.db.query("CREATE TABLE auth.keep_me(value text); INSERT INTO auth.keep_me VALUES('systeem behouden')");
  await env.db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_testadmin','Beheerder','admin'); INSERT INTO public.rooms(id,name) VALUES('oud','Oude ruimte')");
  const sql=await readFile('SQL/reset-eenmalig.sql','utf8');
  const basis=await readFile('SQL/basis.sql','utf8');
  const seed=await readFile('SQL/startgegevens.sql','utf8');
  await env.db.query('BEGIN');
  await env.db.query(sql+basis+seed);
  await env.db.query('ROLLBACK');
  assert.equal((await env.db.query('SELECT id FROM public.profiles')).rows[0].id,'user_testadmin');
  assert.equal((await env.db.query('SELECT id FROM public.rooms')).rows[0].id,'oud');
  console.log('PASS afgebroken reset herstelt oude inrichting en gegevens');
  await env.db.query('BEGIN');
  await env.db.query(sql+basis+seed);
  await env.db.query("INSERT INTO public.profiles(id,display_name,role) VALUES('user_testadmin','Beheerder','admin')");
  await env.db.query('COMMIT');
  assert.equal(Number((await env.db.query('SELECT count(*) FROM public.rooms')).rows[0].count),18);
  assert.equal((await env.db.query('SELECT role FROM public.profiles')).rows[0].role,'admin');
  assert.equal((await env.db.query('SELECT value FROM auth.keep_me')).rows[0].value,'systeem behouden');
  assert.equal(Number((await env.db.query("SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'approve_%'")).rows[0].count),0);
  console.log('PASS reset van live-structuur, nieuwe basis, adminherstel; systeemtabel behouden');
} finally {await env.stop();}
