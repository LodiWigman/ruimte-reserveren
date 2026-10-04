import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
const html=await readFile('index.html','utf8'),xlsx=await readFile('node_modules/.cache/han-test/xlsx.js','utf8');
const locales={en:await readFile('node_modules/.cache/han-test/clerk-en.js','utf8'),nl:await readFile('node_modules/.cache/han-test/clerk-nl.js','utf8')};
const browser=await chromium.launch({headless:true,...(process.env.TEST_BROWSER_CHANNEL?{channel:process.env.TEST_BROWSER_CHANNEL}:{})});
try{
  const page=await browser.newPage();
  await page.addInitScript(()=>{
    window.supabase={createClient:()=>({rpc:async()=>{throw Error('Unexpected API call');}})};
    window.Clerk={user:null,load:async()=>{},addListener:()=>window.__ready=true};
  });
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(url==='https://han.test/')return route.fulfill({contentType:'text/html',body:html});
    if(url.includes('xlsx.full.min.js'))return route.fulfill({contentType:'application/javascript',body:xlsx,headers:{'access-control-allow-origin':'*'}});
    if(url.includes('@clerk/localizations@'))return route.fulfill({contentType:'application/javascript',body:url.includes('/en-US/')?locales.en:locales.nl});
    return route.fulfill({contentType:'application/javascript',body:''});
  });
  await page.goto('https://han.test/');await page.waitForFunction(()=>window.__ready);
  const results=await page.evaluate(async()=>{
    const results=[];
    const make=(rows,options={})=>{
      const book=XLSX.utils.book_new();XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet(rows),'Planning');
      return XLSX.write(book,{type:'array',bookType:'xlsx',compression:true,...options});
    };
    const data=make([['naam','datum','start','einde'],['Import test',48214,0.375,10/24]]);
    const valid=await parseExcel(new File([data],'normal.xlsx'));
    results.push({name:'valid xlsx parses under CSP with integrity-verified worker',pass:valid[0].start==='09:00'&&valid[0].einde==='10:00'});
    const legacy=make([['naam','datum'],['Legacy',48214]],{bookType:'biff8'});
    results.push({name:'valid legacy OLE xls is supported',pass:(await parseExcel(new File([legacy],'normal.xls')))[0].naam==='Legacy'});
    const deny=async(name,bytes,ext='xlsx')=>{
      try{await parseExcel(new File([bytes],'probe.'+ext));results.push({name,pass:false});}catch{results.push({name,pass:true});}
    };
    await deny('HTML renamed to xls rejected','<html><table><tr><td>Fake</td></tr></table></html>','xls');
    await deny('text renamed to xlsx rejected','not an Excel archive');
    await deny('compressed upload above 5 MiB rejected',new Uint8Array(5*1024*1024+1));
    const over=make([['naam'],...Array.from({length:521},(_,i)=>['Row '+i])]);
    await deny('more than 520 records rejected before preview',over);
    const wide=make([Array.from({length:33},(_,i)=>'column'+i),Array(33).fill('data')]);
    await deny('more than 32 columns rejected',wide);
    const copy=data.slice(0),view=new DataView(copy);let central=-1;
    for(let i=0;i<copy.byteLength-46;i++)if(view.getUint32(i,true)===0x02014b50){central=i;break;}
    if(central<0)throw Error('Invalid test fixture');
    view.setUint32(central+24,21*1024*1024,true);
    await deny('advertised uncompressed size above 20 MiB rejected',copy);
    const dishonest=data.slice(0);new DataView(dishonest).setUint32(central+24,0,true);
    await deny('actual inflation exceeding declared size rejected',dishonest);
    const encrypted=data.slice(0),encryptedView=new DataView(encrypted);
    encryptedView.setUint16(central+8,encryptedView.getUint16(central+8,true)|1,true);
    await deny('encrypted archive rejected',encrypted);
    const replaceWorkbookXml=(xml,encoding='utf8',compression=true)=>{
      const archive=XLSX.CFB.read(new Uint8Array(data),{type:'array'});
      let content=new TextEncoder().encode(xml);
      if(encoding==='utf16le'||encoding==='utf16be'){
        const little=encoding==='utf16le';content=new Uint8Array(2+xml.length*2);
        content[0]=little?255:254;content[1]=little?254:255;
        const view=new DataView(content.buffer);
        for(let i=0;i<xml.length;i++)view.setUint16(2+i*2,xml.charCodeAt(i),little);
      }
      const entry=archive.FileIndex[archive.FullPaths.indexOf('Root Entry/xl/workbook.xml')];
      entry.content=content;entry.size=content.length;
      return XLSX.CFB.write(archive,{type:'array',fileType:'zip',compression});
    };
    const originalArchive=XLSX.CFB.read(new Uint8Array(data),{type:'array'});
    const workbook=originalArchive.FileIndex[originalArchive.FullPaths.indexOf('Root Entry/xl/workbook.xml')];
    const originalXml=new TextDecoder().decode(workbook.content);
    const repacked=replaceWorkbookXml(originalXml);
    results.push({name:'repacked XML fixture is a valid spreadsheet',pass:(await parseExcel(new File([repacked],'repacked.xlsx'))).length===1});
    const external='<!DOCTYPE workbook [<!ENTITY probe SYSTEM "https://entity-probe.invalid/sentinel">]>';
    for(const encoding of ['utf8','utf16le','utf16be']){
      const malicious=external+originalXml.replace(/<\?xml[^?]*\?>/,'');
      await deny('external XML entity rejected in '+encoding,replaceWorkbookXml(malicious,encoding));
    }
    await deny('entity declaration rejected in stored ZIP entry',replaceWorkbookXml('<!ENTITY probe "sentinel">'+originalXml,'utf8',false));
    return results;
  });
  await writeFile('test-results/security-imports.json',JSON.stringify({results},null,2));
  for(const row of results){console.log((row.pass?'PASS ':'FAIL ')+row.name);assert.equal(row.pass,true,row.name);}
}finally{await browser.close();}
