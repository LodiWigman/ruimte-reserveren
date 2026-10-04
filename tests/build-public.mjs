// Deploy an allowlist, never SQL, test data, source-control files or local backups.
import {mkdir,copyFile,readdir} from 'node:fs/promises';
import {verifyRelease,publicFiles as files} from './release-check.mjs';
await verifyRelease();
await mkdir('dist',{recursive:true});
for(const name of await readdir('dist'))if(!files.includes(name))throw Error('Unexpected existing public file: '+name);
for(const name of files)await copyFile(name,'dist/'+name);
console.log('Public output contains only the website and logo.');
