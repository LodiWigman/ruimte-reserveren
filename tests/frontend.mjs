import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const html=await readFile('index.html','utf8');
const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const elements=new Map();
const element=id=>{if(!elements.has(id))elements.set(id,{value:'',textContent:'',innerHTML:'',style:{},classList:{add(){},remove(){},toggle(){}},focus(){},dataset:{}});return elements.get(id);};
const client={rpc:async()=>({data:1,error:null})};
const context=vm.createContext({console,Intl,Date,crypto:webcrypto,setTimeout,clearTimeout,confirm:()=>true,
  window:{supabase:{createClient:()=>client}},document:{addEventListener(){},getElementById:element,querySelectorAll:()=>[],createElement:()=>({})}});
vm.runInContext(script,context);
const call=(name,...args)=>context[name](...args);
let passed=0;
function test(name,fn){fn();passed++;console.log('PASS '+name);}
const plain=value=>JSON.parse(JSON.stringify(value));
test('HTML-app JavaScript compileert',()=>assert.ok(context.submitBooking));
test('datums strikt, schrikkeldag en geen stilzwijgende correctie',()=>{
  assert.equal(call('parseImportDate','2032-02-29'),'2032-02-29');
  for(const date of ['2030-02-29','2030-02-30','2030-13-01','2030-01-01junk','01/02/30','January 1 2030'])assert.equal(call('parseImportDate',date),'');
  assert.equal(call('parseImportDate','31-1-2030'),'2030-01-31');
});
test('tijden strikt',()=>{
  for(const time of ['25:00','23:60','24:00','09:00:15','9:00junk'])assert.equal(call('parseImportTime',time),'');
  assert.equal(call('parseImportTime','9:05'),'09:05');
});
test('maandultimo en schrikkeljaar slaan ongeldige dagen over',()=>{
  assert.deepEqual(plain(call('recurrenceDates','2030-01-31',{unit:'maand',until:'2030-05-31'})),['2030-01-31','2030-03-31','2030-05-31']);
  assert.deepEqual(plain(call('recurrenceDates','2032-02-29',{unit:'jaar',until:'2036-03-01'})),['2032-02-29','2036-02-29']);
});
test('weekherhaling gebruikt kalenderdagen over DST',()=>{
  assert.deepEqual(plain(call('recurrenceDates','2030-03-25',{unit:'week',interval:2,until:'2030-04-09',days:[1,3]})),['2030-03-25','2030-03-27','2030-04-08']);
  assert.equal(call('dayDiff','2030-03-30','2030-04-01'),2);
});
test('herhalen tot en met neemt een passende einddag mee',()=>{
  assert.deepEqual(plain(call('recurrenceDates','2030-01-01',{unit:'dag',until:'2030-01-03'})),['2030-01-01','2030-01-02','2030-01-03']);
  assert.deepEqual(plain(call('recurrenceDates','2030-01-07',{unit:'week',until:'2030-01-14',days:[1]})),['2030-01-07','2030-01-14']);
});
test('reeksen groeperen per eigenaar en reeks; tekst blijft ge-escaped',()=>{
  const base={date:'2030-01-01',start:'09:00',name:'<script>Test</script>',roomName:'Ruimte',roomId:'W0.03',userId:'user_a',recurrenceId:'series_a'};
  const result=call('renderSeries',[{...base,id:'one'},{...base,id:'two',date:'2030-01-02'},{...base,id:'other',userId:'user_b'}],r=>'<p>'+r.id+'</p>');
  assert.equal((result.match(/<details /g)||[]).length,2);assert.match(result,/2 momenten/);assert.match(result,/&lt;script&gt;/);assert.doesNotMatch(result,/<script>/);
});
test('frontenduitleg over externe wijziging volgt datum, ruimte en alle geselecteerde tijden',()=>{
  vm.runInContext("editState={scope:'single',original:{id:'one',date:'2030-01-07',roomId:'W0.03',start:'09:00',end:'11:00',userId:'user_a',recurrenceId:'series'}};bookings=[editState.original,{...editState.original,id:'two',date:'2030-01-08',start:'10:00'}]",context);
  const form={date:'2030-01-07',roomId:'W0.03',start:'09:30',end:'10:30'};
  assert.equal(call('externalChangeNeedsApproval',form),false);
  for(const change of [{date:'2030-01-08'},{roomId:'W0.07'},{start:'08:30'},{end:'12:00'}])assert.equal(call('externalChangeNeedsApproval',{...form,...change}),true);
  vm.runInContext("editState.scope='series'",context);
  assert.equal(call('externalChangeNeedsApproval',form),true);
});
test('herhalingslimiet en ontbrekende einddatum',()=>{
  assert.throws(()=>call('recurrenceDates','2030-01-01',{unit:'dag',until:'2032-01-01'}),/520/);
  assert.throws(()=>call('recurrenceDates','2030-01-01',{unit:'dag'}),/einddatum/);
});
test('CSV met puntkomma, quotes, komma en ingebedde regeleinden',()=>{
  const rows=call('parseCsv','naam;omschrijving;datum\r\n"Naam, Persoon";"regel 1\r\nregel ""2""";2030-01-01\r\n');
  assert.equal(rows.length,1);assert.equal(rows[0].omschrijving,'regel 1\nregel "2"');
  assert.throws(()=>call('parseCsv','naam,datum\n"onaf'),/afgesloten/);
  assert.throws(()=>call('parseCsv','naam,datum\nA,B,C'),/aantal velden/);
});
const ics=(start,end,extra='')=>'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:test-series\r\nSUMMARY:Test afspraak\r\nLOCATION:W0.03\r\n'+start+'\r\n'+end+'\r\n'+extra+'\r\nEND:VEVENT\r\nEND:VCALENDAR';
test('UTC ICS wordt Nederlandse tijd',()=>{
  const rows=call('parseIcs',ics('DTSTART:20300701T090000Z','DTEND:20300701T100000Z'));
  assert.equal(rows[0].starttijd,'11:00');assert.equal(rows[0].eindtijd,'12:00');
});
test('lokale ICS-herhaling met DST, BYDAY en EXDATE behoudt reeks',()=>{
  const rows=call('parseIcs',ics('DTSTART;TZID=Europe/Amsterdam:20300325T090000','DTEND;TZID=Europe/Amsterdam:20300325T100000','RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE\r\nEXDATE;TZID=Europe/Amsterdam:20300327T090000'));
  assert.deepEqual(plain(rows.map(r=>r.datum)),['2030-03-25','2030-04-01','2030-04-03']);
  assert.ok(rows.every(r=>r.starttijd==='09:00'&&r.recurrence_id==='test-series'));
});
test('UTC-herhaling blijft op UTC bij DST-overgang',()=>{
  const rows=call('parseIcs',ics('DTSTART:20300330T090000Z','DTEND:20300330T100000Z','RRULE:FREQ=DAILY;COUNT=3'));
  assert.deepEqual(plain(rows.map(r=>r.starttijd)),['10:00','11:00','11:00']);
});
test('ICS UNTIL met seconden begrenst zonder een dag te verliezen',()=>{
  const rows=call('parseIcs',ics('DTSTART:20300701T090000Z','DTEND:20300701T100000Z','RRULE:FREQ=DAILY;UNTIL=20300703T235959Z'));
  assert.equal(rows.length,3);
});
test('niet-ondersteunde ICS wordt afgewezen, nooit deels ingelezen',()=>{
  for(const extra of ['RRULE:FREQ=MONTHLY;COUNT=3;BYSETPOS=1','RECURRENCE-ID:20300101T090000Z','RDATE:20300102T090000Z','RRULE:FREQ=DAILY'])assert.throws(()=>call('parseIcs',ics('DTSTART:20300101T090000Z','DTEND:20300101T100000Z',extra)));
  assert.throws(()=>call('parseIcs',ics('DTSTART:20300101T090000','DTEND:20300101T100000')),/tijdzone/i);
  assert.throws(()=>call('parseIcs',ics('DTSTART;VALUE=DATE:20300101','DTEND;VALUE=DATE:20300102')),/hele dagen/);
  assert.throws(()=>call('parseIcs',ics('DTSTART:20300101T090000Z','DTEND:20300102T100000Z')),/Meerdaagse/);
});
test('DST niet-bestaande en dubbele kloktijden afgewezen',()=>{
  assert.throws(()=>call('amsterdamInstant','2030-03-31','02:30'),/kloktijd/);
  assert.throws(()=>call('amsterdamInstant','2030-10-27','02:30'),/kloktijd/);
});
vm.runInContext("rooms=[{id:'W0.03',name:'Vergaderruimte',capacity:8},{id:'W1.03',name:'Projectruimte',capacity:12}]",context);
test('import normalisatie behoudt ICS reeks-ID',()=>{
  const rows=call('prepareImportRows',call('parseIcs',ics('DTSTART:20300701T090000Z','DTEND:20300701T100000Z','RRULE:FREQ=DAILY;COUNT=2')));
  assert.ok(rows[0].recurrenceId);assert.equal(rows[0].recurrenceId,rows[1].recurrenceId);assert.ok(rows.every(r=>r.valid));
});
test('dubbele regels, ambigue ruimte en te lange tekst worden gemeld',()=>{
  const row={naam:'Naam',ruimte:'W0.03',datum:'2030-01-01',start:'09:00',end:'10:00'};
  assert.ok(call('prepareImportRows',[row,row]).every(r=>!r.valid));
  assert.equal(call('resolveImportRoom','W0.03 of W1.03'),'');
  assert.equal(call('prepareImportRows',[{...row,naam:'x'.repeat(121)}])[0].valid,false);
});
test('nul RPC-resultaat veroorzaakt fout',()=>{});
client.rpc=async()=>({data:0,error:null});await assert.rejects(()=>call('rpc','test'),/Geen resultaat/);
const all=Array.from({length:1201},(_,i)=>({id:String(i).padStart(5,'0')}));
client.from=()=>{
  let after='';
  const q={select(){return q;},order(){return q;},limit(){return q;},gt(k,v){after=v;return q;},then(resolve){resolve({data:all.filter(r=>r.id>after).slice(0,300),error:null});}};
  return q;
};
assert.equal((await call('readAll','reserveringen')).length,1201);
passed++;console.log('PASS keyset-paginering leest alle 1201 rijen, ook bij serverlimiet lager dan 500');
console.log(`FRONTEND: ${passed} scenario's geslaagd`);
