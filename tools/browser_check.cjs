const path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime','browser-test'),{
  executablePath:process.env.MEOW_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
  viewport:{width:1440,height:900},args:['--no-sandbox','--disable-dev-shm-usage','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required','--disable-crash-reporter','--disable-breakpad'],
 });
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
 page.on('request',r=>{if(/^https?:/.test(r.url()))external.push(r.url());});
 const waitScreen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 await page.goto(process.env.MEOW_ENTRY_URL||pathToFileURL(path.join(root,'index.html')).href);
 await waitScreen('menu');
 await page.screenshot({path:path.join(root,'artifacts','01-menu.png')});
 console.log('MENU',await page.evaluate(()=>window.meowState));
 if(process.env.MEOW_SMOKE_ONLY){ await context.close(); assert.deepEqual(errors,[]); return; }
 await page.mouse.click(1100,50);await waitScreen('adv_intro');
 for(const key of ['d','f','j','k'])await page.keyboard.press(key);
 await page.screenshot({path:path.join(root,'artifacts','02-tutorial.png')});
 await page.mouse.click(1310,50);await waitScreen('menu');
 await page.mouse.click(1230,50);await waitScreen('settings');
 const before=await page.evaluate(()=>window.meowState.offset);
 await page.mouse.click(1007,526);await page.waitForTimeout(150);
 assert.equal(await page.evaluate(()=>window.meowState.offset),before+10);
 await page.mouse.click(790,526);await page.waitForTimeout(150);
 await page.mouse.click(720,782);await waitScreen('menu');
 // Select a known track and mode, preserving other stored preferences.
 await page.mouse.click(240,730);
 if(!(await page.evaluate(()=>window.meowState.easy)))await page.mouse.click(440,488);
 await page.mouse.click(130,558);await waitScreen('play');
 await page.waitForTimeout(1000);await page.keyboard.press('Escape');await waitScreen('pause');
 const paused=await page.evaluate(()=>window.meowState.time);
 await page.waitForTimeout(600);assert.equal(await page.evaluate(()=>window.meowState.time),paused);
 await page.screenshot({path:path.join(root,'artifacts','03-pause.png')});
 await page.keyboard.press('Escape');await waitScreen('play');
 const chart=JSON.parse(fs.readFileSync(path.join(root,'assets/charts/sunset_easy.json')));
 const timeline=[];
 for(const n of chart.notes){timeline.push({t:n.time,l:n.lane,down:true});timeline.push({t:n.time+(n.duration||0.055),l:n.lane,down:false});}
 timeline.sort((a,b)=>a.t-b.t||Number(a.down)-Number(b.down));
 let captured=false,fever=false;
 for(const e of timeline){
  await page.waitForFunction(t=>window.meowState?.screen==='play' && window.meowState.time+(performance.now()-window.meowState.stamp)/1000>=t,e.t,{timeout:6000});
  if(e.down)await page.keyboard.down(['d','f','j','k'][e.l]);else await page.keyboard.up(['d','f','j','k'][e.l]);
  if(e.t>15&&!captured){await page.screenshot({path:path.join(root,'artifacts','04-gameplay.png')});captured=true;console.log('PLAY',await page.evaluate(()=>window.meowState));}
  fever ||= await page.evaluate(()=>window.meowState.fever);
 }
 await waitScreen('result');
 const result=await page.evaluate(()=>window.meowState);
 console.log('RESULT',result,'feverSeen',fever);
 assert(result.score>50000);assert.equal(result.resolved,result.total);assert(fever);
 await page.screenshot({path:path.join(root,'artifacts','05-result.png')});
 await page.mouse.click(984,770);await waitScreen('play');
 assert.equal(await page.evaluate(()=>window.meowState.selected),1);
 await page.waitForTimeout(700);await page.keyboard.press('Escape');await waitScreen('pause');
 await page.mouse.click(820,507);await waitScreen('menu');
 await page.reload();await waitScreen('menu');
 await page.mouse.click(1170,731);await page.mouse.click(130,558);await waitScreen('play');
 assert.equal(await page.evaluate(()=>window.meowState.selected),2);
 await page.waitForTimeout(800);await page.keyboard.press('Escape');await waitScreen('pause');
 await context.close();
 fs.writeFileSync(path.join(root,'artifacts','browser-results.json'),JSON.stringify({result,feverSeen:fever,externalRequests:external,errors},null,2));
 assert.deepEqual(external,[]);assert.deepEqual(errors,[]);
 console.log('PASS: offline entry, tutorial, settings, pause, real-key full song, fever, results, next song, reload, all tracks.');
})().catch(e=>{console.error(e);process.exitCode=1;});
