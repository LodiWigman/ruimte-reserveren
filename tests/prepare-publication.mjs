// Freeze the prepared release and reuse successful tests only for unchanged sources.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {verifyRelease} from './release-check.mjs';
const baseline=JSON.parse(await readFile('docs/security/VERIFICATIE-2026-10-01.json','utf8'));
if(baseline.results.length!==11||baseline.results.some(r=>r.code!==0))throw Error('Successful baseline tests missing');
const reusedSources=['index.html','han-logo.svg','vercel.json','SQL/basis.sql',
  'SQL/migrations/20260922151039_reservation_workflows.sql',
  'SQL/migrations/20260929192403_connectr_profiles_conversations.sql',
  'tests/security-assessment.mjs','tests/security-browser.mjs','tests/security-imports.mjs',
  'tests/browser.mjs','tests/db-harness.mjs','tests/prepare-security-headers.mjs','docs/security/browser-integrity.json'];
for(const file of reusedSources){
  const hash=createHash('sha256').update(await readFile(file)).digest('hex');
  if(hash!==baseline.sourceHashes[file])throw Error('Relevant source changed: retest '+file);
}
const build=JSON.parse(await readFile('test-results/release-build.json','utf8'));
const clerk=JSON.parse(await readFile('test-results/clerk-smoke.json','utf8'));
if(build.results.length!==4||clerk.results.length!==2||clerk.errors.length||clerk.csp.length||clerk.failures.length)throw Error('Release-specific checks incomplete');
const files=[
  'index.html','han-logo.svg','vercel.json','package.json','pnpm-lock.yaml','.gitignore','README.md',
  'SQL/README.md','SQL/verify.sql','SQL/migrations/README.md',
  'SQL/migrations/20260929192403_connectr_profiles_conversations.sql',
  'tests/browser.mjs','tests/db-harness.mjs','tests/frontend.mjs','tests/setup-browser.mjs',
  'tests/connectr.mjs','tests/validation.mjs','tests/translation-audit.mjs',
  'tests/security-assessment.mjs','tests/security-browser.mjs','tests/security-imports.mjs',
  'tests/prepare-security-headers.mjs','tests/release-check.mjs','tests/release-build.mjs',
  'tests/build-public.mjs','tests/clerk-smoke.mjs','tests/verify-local.mjs','tests/prepare-publication.mjs',
  'tests/public-security-probes.mjs',
  'docs/CONNECTR-OPLEVERING.md','docs/BEVEILIGINGSBEOORDELING-2026-10-01.md',
  'docs/PUBLICATIEKLAAR-2026-10-01.md',
  'docs/security/CONTROLES.md','docs/security/browser-integrity.json',
  'docs/security/VERIFICATIE-2026-10-01.json','docs/security/PUBLICATIEBLOKKADE-2026-10-01.json'
];
const sourceHashes={};
for(const file of files){
  const bytes=await readFile(file);
  sourceHashes[file]={sha256:createHash('sha256').update(bytes).digest('hex'),
    sha256LF:createHash('sha256').update(bytes.toString('utf8').replace(/\r\n/g,'\n')).digest('hex')};
}
const result={preparedAt:new Date().toISOString(),approval:'approved by user',
  destination:{url:'https://ruimte-reserveren.vercel.app/',repository:'LodiWigman/ruimte-reserveren',branch:'main',baseline:'75ab09f61c4dd534550db8380603d70b12e91804',supabaseProject:'oappvdfjyvbmvqrjvnmv',migration:'connectr_profiles_conversations'},
  decisions:{clerkDevelopmentAccepted:true,mandatoryUserMfa:false},
  check:await verifyRelease(),reusedTests:{testedAt:baseline.testedAt,suites:baseline.results.length,unchangedSources:reusedSources},
  newChecks:{build,clerk},
  remainingLiveSteps:['Verified protected backup before migration','Clerk registration name settings','Migration and data-preservation checks','Vercel headers/output checks','Real authenticated user smoke test'],
  sourceHashes,
  publicationFiles:[...files,'docs/security/RELEASE-VERIFICATIE-2026-10-01.json']};
await writeFile('docs/security/RELEASE-VERIFICATIE-2026-10-01.json',JSON.stringify(result,null,2)+'\n');
console.log('Prepared '+files.length+' reviewed files, plus this manifest. Prior 11 test suites reused for unchanged application/database code. Publication approved by user.');
