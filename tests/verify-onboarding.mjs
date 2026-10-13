// Task-scoped verification. Never contacts the production database.
import {spawnSync} from 'node:child_process';
const tests=['frontend','database','workflows','reset','connectr','overview-cases','help-database','browser','validation','help-browser','security-browser','security-imports','release-build'];
const from=process.argv.find(arg=>arg.startsWith('--from='))?.slice(7);
if(from&&!tests.includes(from))throw Error('Unknown verification suite');
const selected=from?tests.slice(tests.indexOf(from)):process.argv.includes('--browser-only')?tests.slice(tests.indexOf('browser')):tests;
const preview=spawnSync(process.execPath,['tests/help-preview.mjs','--build-only'],{stdio:'inherit',windowsHide:true});
if(preview.status!==0)process.exit(preview.status||1);
for(const name of selected){
  console.log('\nVERIFY '+name);
  const result=spawnSync(process.execPath,['tests/'+name+'.mjs'],{stdio:'inherit',windowsHide:true,env:process.env});
  if(result.status!==0)process.exit(result.status||1);
}
console.log('ONBOARDING VERIFICATION PASSED');
