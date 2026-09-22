import EmbeddedPostgres from 'embedded-postgres';
import {mkdir, readFile} from 'node:fs/promises';
import path from 'node:path';
import {Client} from 'pg';
import {randomBytes} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

export async function startDatabase() {
  const directory=path.resolve('.test-data',`run-${Date.now()}`);
  await mkdir(directory,{recursive:true});
  const password=randomBytes(24).toString('hex');
  const server=new EmbeddedPostgres({databaseDir:directory,port:55439,user:'postgres',password,
    persistent:true,postgresFlags:['-h','127.0.0.1'],onLog:()=>{},onError:()=>{}});
  await server.initialise();
  await server.start();
  const connect=async()=>{const c=new Client({host:'127.0.0.1',port:55439,user:'postgres',password,database:'postgres'});await c.connect();return c;};
  const db=await connect();
  await db.query(`CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
      'SELECT coalesce(nullif(current_setting(''request.jwt.claims'',true),''''),''{}'')::jsonb';
    GRANT USAGE ON SCHEMA auth TO anon,authenticated; GRANT EXECUTE ON FUNCTION auth.jwt() TO anon,authenticated;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;`);
  const binaryModule=await import(new URL('./binary.js',import.meta.resolve('embedded-postgres')));
  const binaries=await binaryModule.default();
  return {db,connect,stop:async()=>{
    await db.end();
    await promisify(execFile)(path.join(path.dirname(binaries.postgres),process.platform==='win32'?'pg_ctl.exe':'pg_ctl'),['stop','-D',directory,'-m','fast','-t','10'],{windowsHide:true});
    server.process=undefined;
  },server};
}

export async function applyBasis(db) {
  await db.query('BEGIN');
  try {
    await db.query(await readFile('SQL/basis.sql','utf8'));
    await db.query(await readFile('SQL/startgegevens.sql','utf8'));
    await db.query('COMMIT');
  } catch(error) {await db.query('ROLLBACK');throw error;}
}

export async function asUser(db,user,sql,params=[]) {
  await db.query('BEGIN');
  try {
    await db.query(`SET LOCAL ROLE ${user==='anonymous'?'anon':'authenticated'}`);
    await db.query("SELECT set_config('request.jwt.claims',$1,true)",[JSON.stringify(user==='anonymous'?{}:{sub:user,role:'authenticated'})]);
    const result=await db.query(sql,params);
    await db.query('COMMIT');
    return result;
  } catch(error) {await db.query('ROLLBACK');throw error;}
}
