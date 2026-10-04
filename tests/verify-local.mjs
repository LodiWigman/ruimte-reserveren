// Run database suites sequentially: the disposable server uses one fixed port.
import {spawn} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {releaseFiles} from './release-check.mjs';
const checks=['frontend','database','workflows','reset','connectr','security-assessment','browser','validation','security-browser','security-imports','prepare-security-headers'];
const results=[];
await mkdir('test-results',{recursive:true});
for(const name of checks){
  console.log('START '+name);
  const args=['tests/'+name+'.mjs',...(name==='prepare-security-headers'?['--check']:[])];
  let output='';
  const result=await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,args,{env:process.env,windowsHide:true});
    child.stdout.on('data',chunk=>{output+=chunk;});
    child.stderr.on('data',chunk=>{output+=chunk;});
    child.on('error',reject);
    child.on('close',(code,signal)=>resolve({name,code,signal}));
  });
  await writeFile('test-results/verify-'+name+'.log',output);
  results.push(result);
  console.log((result.code===0?'PASS ':'FAIL ')+name+'\n'+output.trim().split('\n').slice(-5).join('\n'));
  if(result.code!==0)break;
}
const sourceHashes={};
for(const file of releaseFiles)sourceHashes[file]=createHash('sha256').update(await readFile(file)).digest('hex');
await writeFile('test-results/local-verification.json',JSON.stringify({testedAt:new Date().toISOString(),results,sourceHashes},null,2)+'\n');
if(results.length!==checks.length||results.some(r=>r.code!==0))process.exit(1);
