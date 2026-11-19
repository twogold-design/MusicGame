const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),http=require('node:http');
const {pathToFileURL}=require('node:url'),{chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),web=path.join(root,'build/web');
const server=http.createServer((req,res)=>{const file=path.join(web,new URL(req.url,'http://localhost').pathname);if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm'})[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);});
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime/demolition-browser'),{executablePath:process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},hasTouch:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('404'))errors.push(m.text());});page.on('request',r=>{if(/^https?:/.test(r.url())&&!r.url().includes('127.0.0.1'))external.push(r.url());});
 const screen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 const at=t=>page.waitForFunction(t=>window.meowState?.screen!=='combat_play'||window.meowState.combat.elapsed+(performance.now()-window.meowState.stamp)/1000>=t,t,{timeout:15000});
 await page.goto(process.env.DEMOLITION_ENTRY||pathToFileURL(path.join(root,'index.html')).href);await screen('combat_intro');
 await page.screenshot({path:path.join(root,'artifacts/demolition-intro.png')});
 await page.keyboard.press('Enter');await screen('combat_play');await page.screenshot({path:path.join(root,'artifacts/demolition-before.png')});
 const chart=await page.evaluate(()=>window.meowState.combat.cues);assert.equal(chart.length,64);let held=false;
 for(let i=0;i<chart.length;i++){
  const cue=chart[i];await at(cue.time-.065);assert.equal(await page.evaluate(()=>window.meowState.screen),'combat_play');
  if(held){await page.keyboard.up('Space');held=false;}
  else if(i%8===4&&chart[i+1]?.time-cue.time>.4){await page.keyboard.down('Space');held=true;}
  else await page.keyboard.press('Space');
  await at(cue.time+.09);
  if(i===3){await page.keyboard.press('Escape');await screen('combat_pause');const c=await page.evaluate(()=>window.meowState.combat);await page.waitForTimeout(200);assert.equal(await page.evaluate(()=>window.meowState.combat.elapsed),c.elapsed);await page.keyboard.press('Escape');await screen('combat_play');}
  if([7,27,49].includes(i))await page.screenshot({path:path.join(root,'artifacts',({7:'demolition-living.png',27:'demolition-office.png',49:'demolition-arcade.png'})[i])});
 }
 await screen('combat_result');const result=await page.evaluate(()=>window.meowState.combat);
 await page.screenshot({path:path.join(root,'artifacts/demolition-result.png')});
 console.log('PERFORMANCE',JSON.stringify({...result,cues:undefined,objects:undefined}));
 assert.equal(result.mode,'demolition');assert(result.won);assert.equal(result.resolved,64);assert.equal(result.missed,0);assert(result.broken>=20);assert(result.destruction>.65);assert(result.walls>0);assert(result.chainHits>0);assert(result.heavyHits>=7);assert(result.debris>100);
 // Touch selects and destroys a particular scene prop in a single gesture.
 await page.mouse.click(560,665);await screen('combat_play');const props=await page.evaluate(()=>window.meowState.combat.objects);const plant=props.find(o=>o.room===0&&o.kind==='plant');
 await at(1.935);await page.touchscreen.tap(plant.x,plant.y);await at(2.2);assert.equal(await page.evaluate(id=>window.meowState.combat.objects[id].alive,plant.id),false);
 await at(2.935);const cdp=await context.newCDPSession(page);await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:600,y:800,id:0}]});await at(3.435);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await at(3.7);assert.equal(await page.evaluate(()=>window.meowState.combat.heavyHits),1);
 await new Promise(r=>server.listen(8834,'127.0.0.1',r));await page.setViewportSize({width:900,height:450});await page.goto('http://127.0.0.1:8834/index.html');await screen('combat_intro');await page.touchscreen.tap(90+600*.5,780*.5);await screen('combat_play');await at(1.935);await page.touchscreen.tap(450,400);await at(2.2);assert((await page.evaluate(()=>window.meowState.combat.broken))>0);await page.screenshot({path:path.join(root,'artifacts/demolition-mobile.png')});
 await page.setViewportSize({width:450,height:900});assert(await page.locator('#rotate').isVisible());
 if(!process.env.DEMOLITION_SKIP_PACKAGE){await page.setViewportSize({width:1440,height:900});await page.goto(pathToFileURL(path.join(root,'.runtime/demolition-package/index.html')).href);await screen('combat_intro');await page.keyboard.press('Enter');await screen('combat_play');await at(1.935);await page.keyboard.press('Space');await at(2.2);assert.equal(await page.evaluate(()=>window.meowState.combat.mode),'demolition');assert((await page.evaluate(()=>window.meowState.combat.broken))>0);}
 await context.close();await new Promise(r=>server.close(r));assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'dist/manifest.json'),'utf8').replace(/^\uFEFF/,''));assert(manifest.web_bytes<200000000&&manifest.zip_bytes<200000000);
 fs.writeFileSync(path.join(root,'artifacts/demolition-browser-results.json'),JSON.stringify({result,pause:true,touchDirectSmash:true,touchHeavy:true,http:true,mobile:true,portrait:true,extractedZip:!process.env.DEMOLITION_SKIP_PACKAGE,errors,external,webBytes:manifest.web_bytes,zipBytes:manifest.zip_bytes},null,2));
 console.log('PASS demolition64, three rooms, persistent debris, walls, chains, touch, HTTP, ZIP',JSON.stringify({...result,cues:undefined,objects:undefined}));
})().catch(e=>{console.error(e);server.close();process.exit(1);});
