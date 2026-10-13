// Existing regression suites exercise returning users; first-use coverage lives in help-browser.mjs.
export async function returningUser(page){
  await page.addInitScript(()=>{
    localStorage.setItem('han-help:visitor',JSON.stringify({seen:['v1:welcome']}));
    for(const account of ['admin','intern','extern','missing'])localStorage.setItem('han-help:user_'+account,JSON.stringify({seen:['v1:intro:extern','v1:intro:intern','v1:intro:admin']}));
  });
}
