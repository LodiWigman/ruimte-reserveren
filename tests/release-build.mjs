// Verify the deployable output and fail-closed build behavior in an isolated copy.
import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile,copyFile,readdir} from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=path.resolve('.test-data','release-build-'+Date.now());
const files=['index.html','han-logo.svg','vercel.json','docs/security/browser-integrity.json','tests/build-public.mjs','tests/release-check.mjs'];
for(const file of files){await mkdir(path.dirname(path.join(root,file)),{recursive:true});await copyFile(file,path.join(root,file));}
const build=()=>spawnSync(process.execPath,['tests/build-public.mjs'],{cwd:root,encoding:'utf8',windowsHide:true});
let result=build();assert.equal(result.status,0,result.stderr);
assert.deepEqual((await readdir(path.join(root,'dist'))).sort(),['han-logo.svg','index.html']);
for(const file of ['index.html','han-logo.svg'])assert.deepEqual(await readFile(path.join(root,'dist',file)),await readFile(file));
const original=await readFile(path.join(root,'index.html'),'utf8');
await writeFile(path.join(root,'index.html'),original.replace('const DAY_START=7','const DAY_START=8'));
result=build();assert.equal(result.status,1);assert.match(result.stderr,/CSP does not match/);
await writeFile(path.join(root,'index.html'),original.replace('integrity="sha384-','integrity="sha384-changed'));
result=build();assert.equal(result.status,1);assert.match(result.stderr,/dependency integrity/);
await writeFile(path.join(root,'index.html'),original);
await writeFile(path.join(root,'dist','private.sql'),'non-sensitive test marker');
result=build();assert.equal(result.status,1);assert.match(result.stderr,/Unexpected existing public file/);
const results=['Build succeeds with accepted Clerk development configuration','Only website and logo are deployed, with identical bytes','Changed application or dependency integrity stops the build','Unexpected private output file stops the build'];
await mkdir('test-results',{recursive:true});
await writeFile('test-results/release-build.json',JSON.stringify({testedAt:new Date().toISOString(),results},null,2));
console.log(results.map(value=>'PASS '+value).join('\n'));
