// A disposable preview of the actual app, with all services replaced by local fixtures.
// Not part of the hosting allowlist. No network connection to Clerk or Supabase.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
const logo=await readFile('han-logo.svg');
let html=await readFile('index.html','utf8');
const mock=String.raw`
let previewRole='visitor';
const previewProgress=new Map();
const previewRooms=[{id:'W0.03',name:'Vergaderruimte',capacity:12,notes:'Scherm en whiteboard',active:true},{id:'W0.07',name:'Projectruimte',capacity:8,notes:'Samenwerken en overleggen',active:true}];
function previewProfile(){return {id:'user_demo'+previewRole,display_name:'Demo Gebruiker',first_name:'Demo',last_name:'Gebruiker',name_confirmed_at:'2026-01-01',role:previewRole};}
window.supabase={createClient:()=>({
  from(table){let after=false;const query={select(){return query;},eq(){return query;},gte(){return query;},gt(){after=true;return query;},order(){return query;},limit(){return query;},single(){return query;},then(resolve){return Promise.resolve({data:table==='profiles'?previewProfile():table==='rooms'&&!after?previewRooms:[],error:null}).then(resolve);}};return query;},
  async rpc(name,args={}){
    let data=[];
    if(name==='han_ensure_profile'||name==='han_end_session')data=true;
    else if(name==='han_notifications')data={items:[],unread:0};
    else if(name==='han_help_progress')data=[...(previewProgress.get(previewRole)||[])];
    else if(name==='han_help_mark'){if(!previewProgress.has(previewRole))previewProgress.set(previewRole,new Set());previewProgress.get(previewRole).add(args.guide_key);data=true;}
    else if(name==='han_availability')data=args.items.map(()=>({conflict:false}));
    else if(!['han_cases','han_occupancy'].includes(name))return {data:null,error:{message:'Dit is een voorbeeld. Er wordt niets opgeslagen. / Preview only. Nothing is saved.'}};
    return {data,error:null};
  }
})};
`;
const setup=String.raw`
setClerkLanguage=async()=>{};
initClerk=async()=>{
  window.Clerk={user:null,session:{getToken:async()=>null},openSignIn:()=>previewSelect('extern'),openSignUp:()=>previewSelect('extern'),signOut:()=>previewSelect('visitor')};
  await handleClerkUser(null);
};
async function previewSelect(role){
  previewRole=role;helpGuestSeenThisVisit=false;
  document.getElementById('preview-role').value=role;
  window.Clerk.user=role==='visitor'?null:{id:'user_demo'+role};
  await handleClerkUser(window.Clerk.user);
}
document.addEventListener('DOMContentLoaded',()=>{
  document.getElementById('preview-role').addEventListener('change',event=>previewSelect(event.target.value));
  document.getElementById('preview-replay').addEventListener('click',()=>openHelpIntro());
});
`;
html=html.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/,'<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; img-src data:; connect-src \'none\'; base-uri \'none\'; form-action \'none\'">');
html=html.replace(/<script src="[^"]+"[^>]*><\/script>/g,'').replace(/<link[^>]+>/g,'');
html=html.replaceAll('src="han-logo.svg"','src="data:image/svg+xml;base64,'+logo.toString('base64')+'"');
html=html.replace('<script>','<script>\n'+mock+'\n').replace('</script>',setup+'\n</script>');
html=html.replace('<body>','<body><aside style="padding:12px 20px;background:#fff0c2;display:flex;align-items:center;gap:12px;flex-wrap:wrap"><strong>Lokaal voorbeeld · fictieve gegevens</strong><label for="preview-role">Bekijk als</label><select id="preview-role"><option value="visitor">Nieuwe bezoeker</option><option value="extern">Extern</option><option value="intern">Intern</option><option value="admin">Admin</option></select><button type="button" id="preview-replay" class="edit-btn">Introductie opnieuw</button><span>Er worden geen echte reserveringen gemaakt.</span></aside>');
await mkdir('test-results/help',{recursive:true});await writeFile('test-results/help/preview.html',html);
if(process.argv.includes('--build-only'))console.log('Preview saved to test-results/help/preview.html');
else createServer((req,res)=>{
  if(req.url!=='/'&&req.url!=='/preview.html'){res.writeHead(404);res.end();return;}
  res.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});res.end(html);
}).listen(4178,'127.0.0.1',()=>console.log('Local preview: http://127.0.0.1:4178/'));
