import {mkdir,writeFile} from 'node:fs/promises';
await mkdir('node_modules/.cache/han-test',{recursive:true});
for(const [name,url] of Object.entries({
  supabase:'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js',
  xlsx:'https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js',
  'clerk-en':'https://cdn.jsdelivr.net/npm/@clerk/localizations@4.20.0/en-US/+esm',
  'clerk-nl':'https://cdn.jsdelivr.net/npm/@clerk/localizations@4.20.0/nl-NL/+esm'
})){
  const response=await fetch(url);if(!response.ok)throw new Error('Download mislukt: '+url);
  await writeFile('node_modules/.cache/han-test/'+name+'.js',await response.text());
}
console.log('Vastgezette openbare scripts lokaal klaar voor offline browsertest.');
