// Bouwt uitsluitend een lokaal reviewbaar SQL-bestand; voert niets uit.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const admin=await readFile('SQL/admin.local.sql','utf8');
const match=admin.match(/VALUES\s*\(\s*'(user_[A-Za-z0-9]+)'/);
if(!match)throw new Error('Gecontroleerde lokale admininrichting ontbreekt.');
const preflight=`DO $$ BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE role='admin')<>1
     OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE role='admin' AND id='${match[1]}') THEN
    RAISE EXCEPTION 'Admincontrole wijkt af: stop en controleer opnieuw';
  END IF;
END $$;\n`;
const files=['SQL/reset-eenmalig.sql','SQL/basis.sql','SQL/startgegevens.sql'];
const body='-- NIET UITVOEREN ZONDER LAATSTE GOEDKEURING. Eén transactie via apply_migration.\n'+preflight+(await Promise.all(files.map(f=>readFile(f,'utf8')))).join('\n')+'\n'+admin;
// Eén statement houdt de heropbouw atomair, ook onafhankelijk van de API-wrapper.
const sql='DO $han_release$ BEGIN\n'+body+'\nEND $han_release$;';
await mkdir('SQL/generated',{recursive:true});
await writeFile('SQL/generated/han-clerk-rebuild.sql',sql);
console.log('Lokaal migratiebestand voorbereid; SHA256 '+createHash('sha256').update(sql).digest('hex'));
