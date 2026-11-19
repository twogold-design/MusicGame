const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),http=require('node:http');
const {pathToFileURL}=require('node:url'),{chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),web=path.join(root,'build/web');
const server=http.createServer((req,res)=>{const file=path.join(web,new URL(req.url,'http://localhost').pathname);if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm'})[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);});
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime/counter-browser'),{executablePath:process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},hasTouch:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('404'))errors.push(m.text());});page.on('request',r=>{if(/^https?:/.test(r.url())&&!r.url().includes('127.0.0.1'))external.push(r.url());});
 const screen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 const at=t=>page.waitForFunction(t=>window.meowState?.screen!=='combat_play'||window.meowState.combat.elapsed+(performance.now()-window.meowState.stamp)/1000>=t,t,{timeout:10000});
 await page.goto(pathToFileURL(path.join(root,'index.html')).href);await screen('combat_intro');
 await page.screenshot({path:path.join(root,'artifacts/counter-intro.png')});
 if(!(await page.evaluate(()=>window.meowState.easy))){await page.mouse.click(920,780);await page.waitForTimeout(120);}
 await page.keyboard.press('Enter');await screen('combat_play');
 const chart=await page.evaluate(()=>window.meowState.combat.cues);assert.equal(chart.length,64);
 for(let i=0;i<chart.length;i++){
  const cue=chart[i];await at(cue.time-.065);assert.equal(await page.evaluate(()=>window.meowState.screen),'combat_play');
  if(cue.type==='release')await page.keyboard.up('Space');
  else if(cue.type==='hold')await page.keyboard.down('Space');
  else await page.keyboard.press('Space');
  await at(cue.time+.08);
  if(i===3){await page.keyboard.press('Escape');await screen('combat_pause');const time=await page.evaluate(()=>window.meowState.combat.elapsed);await page.waitForTimeout(200);assert.equal(await page.evaluate(()=>window.meowState.combat.elapsed),time);await page.keyboard.press('Escape');await screen('combat_play');}
  if(i===13){await page.screenshot({path:path.join(root,'artifacts/counter-hold.png')});await page.keyboard.press('Escape');await screen('combat_pause');await page.keyboard.up('Space');await page.waitForTimeout(200);await page.keyboard.press('Escape');await screen('combat_play');await page.keyboard.down('Space');}
  if(i===6||i===48)await page.screenshot({path:path.join(root,'artifacts',i===6?'counter-action.png':'counter-finale.png')});
 }
 await screen('combat_result');const result=await page.evaluate(()=>window.meowState.combat);
 await page.screenshot({path:path.join(root,'artifacts/counter-result.png')});
 assert(result.won&&result.bossDefeated);assert.equal(result.resolved,64);assert.equal(result.heavyHits,4);assert.equal(result.missed,0);assert.equal(result.wrong,0);assert.equal(result.hp,8);
 // Same action via touch, with no aim position or movement controls.
 await page.mouse.click(560,650);await screen('combat_play');await at(1.935);await page.touchscreen.tap(1100,550);await at(2.18);assert.equal(await page.evaluate(()=>window.meowState.combat.resolved),1);
 await at(8.435);const cdp=await context.newCDPSession(page);await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:1100,y:550,id:0}]});await at(8.935);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await at(9.18);assert.equal(await page.evaluate(()=>window.meowState.combat.heavyHits),1);
 await page.keyboard.press('Escape');await screen('combat_pause');await page.mouse.click(820,530);await screen('menu');
 await page.mouse.click(305,558);await screen('adv_intro');
 await new Promise(r=>server.listen(8833,'127.0.0.1',r));
 await page.setViewportSize({width:900,height:450});await page.goto('http://127.0.0.1:8833/index.html');await screen('combat_intro');
 await page.touchscreen.tap(90+600*.5,780*.5);await screen('combat_play');await at(1.935);await page.touchscreen.tap(90+510*.5,740*.5);await at(2.18);assert.equal(await page.evaluate(()=>window.meowState.combat.resolved),1);
 await page.screenshot({path:path.join(root,'artifacts/counter-mobile.png')});
 await page.setViewportSize({width:450,height:900});assert(await page.locator('#rotate').isVisible());
 await page.setViewportSize({width:1440,height:900});await page.goto(pathToFileURL(path.join(root,'.runtime/counter-package/index.html')).href);await screen('combat_intro');await page.keyboard.press('Enter');await screen('combat_play');await at(1.935);await page.mouse.click(200,200);await at(2.18);assert.equal(await page.evaluate(()=>window.meowState.combat.resolved),1);
 await context.close();await new Promise(r=>server.close(r));assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'dist/manifest.json'),'utf8').replace(/^\uFEFF/,''));assert(manifest.web_bytes<200000000&&manifest.zip_bytes<200000000);
 fs.writeFileSync(path.join(root,'artifacts/counter-browser-results.json'),JSON.stringify({result,pause:true,holdPauseRecovery:true,touchTap:true,touchHold:true,http:true,mobile:true,portrait:true,extractedZip:true,errors,external,webBytes:manifest.web_bytes,zipBytes:manifest.zip_bytes},null,2));
 console.log('PASS one-button full64, hold/release4, pause/recovery, touch, HTTP, extracted ZIP',JSON.stringify({...result,cues:undefined}));
})().catch(e=>{console.error(e);server.close();process.exit(1);});
