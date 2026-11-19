const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),meta=JSON.parse(fs.readFileSync(path.join(root,'assets/audio/groove/metadata.json')));
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime/groove-browser'),{executablePath:process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},hasTouch:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('request',r=>{if(/^https?:/.test(r.url()))external.push(r.url());});
 const screen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 const at=t=>page.waitForFunction(t=>window.meowState?.screen!=='combat_play'||window.meowState.combat.elapsed+(performance.now()-window.meowState.stamp)/1000>=t,t,{timeout:6000});
 await page.goto(process.env.GROOVE_ENTRY||pathToFileURL(path.join(root,'index.html')).href);await screen('combat_intro');
 await page.screenshot({path:path.join(root,'artifacts/groove-intro.png')});
 if(!(await page.evaluate(()=>window.meowState.easy))){await page.mouse.click(960,802);await page.waitForTimeout(180);}
 await page.keyboard.press('Enter');await screen('combat_play');
 await page.waitForTimeout(700);await page.keyboard.press('Escape');await screen('combat_pause');
 const paused=await page.evaluate(()=>window.meowState.combat.elapsed);
 await page.keyboard.down('d');await page.waitForTimeout(250);assert.equal(await page.evaluate(()=>window.meowState.combat.elapsed),paused);
 await page.keyboard.press('Escape');await screen('combat_play');await page.waitForTimeout(180);
 assert(Math.abs((await page.evaluate(()=>window.meowState.combat.player))[0]-720)<1);await page.keyboard.up('d');
 const chart=await page.evaluate(()=>window.meowState.combat.cues);
 assert.equal(chart.length,64);assert.equal(chart.filter(c=>c.type==='dash').length,13);
 let sawBoss=false,sawOverdrive=false;
 for(let i=0;i<chart.length;i++){
  const cue=chart[i];await at(cue.time-.075);
  const state=await page.evaluate(()=>window.meowState);if(state.screen!=='combat_play')break;
  const c=state.combat;
  sawBoss ||= c.enemies.some(e=>e.boss);sawOverdrive ||= c.overdrives>0;
  const target=c.enemies.find(e=>e.boss)||c.enemies.reduce((best,e)=>!best||Math.hypot(e.x-c.player[0],e.y-c.player[1])<Math.hypot(best.x-c.player[0],best.y-c.player[1])?e:best,null);
  if(i===0)await page.keyboard.press('Space'); // Wrong action produces no dash.
  const desired=[720+160*Math.cos(i*.40),480+115*Math.sin(i*.40)],move=[];
  if(Math.abs(desired[0]-c.player[0])>18)move.push(desired[0]>c.player[0]?'d':'a');
  if(Math.abs(desired[1]-c.player[1])>18)move.push(desired[1]>c.player[1]?'s':'w');
  for(const key of move)await page.keyboard.down(key);
  if(cue.type==='dash')await page.keyboard.press('Space');
  else await page.mouse.click(target?.x||1110,target?.y||430);
  await at(cue.time+.065);
  if(i===0){await at(2.25);await page.mouse.click(1110,430);} // Deliberate offbeat has no weak bullet.
  if(i===20||i===46)await page.screenshot({path:path.join(root,'artifacts',i===20?'groove-action.png':'groove-boss.png')});
  for(const key of move)await page.keyboard.up(key);
 }
 await screen('combat_result');
 const result=await page.evaluate(()=>window.meowState.combat);
 await page.screenshot({path:path.join(root,'artifacts/groove-result.png')});
 console.log('RESULT',JSON.stringify({...result,cues:undefined,enemies:undefined}));
 assert(result.won);assert.equal(result.resolved,64);assert.equal(result.perfect,51);assert.equal(result.dashes,13);assert.equal(result.missed,0);assert(result.wrong>=2);assert(result.bossDefeated);assert(sawBoss&&sawOverdrive);
 await page.mouse.click(570,650);await screen('combat_play');
 await at(2.25);const before=await page.evaluate(()=>window.meowState.combat.player);
 const cdp=await context.newCDPSession(page);
 await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:185,y:650,id:0}]});await page.waitForTimeout(300);
 await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await page.waitForTimeout(100);
 assert((await page.evaluate(()=>window.meowState.combat.player))[0]>before[0]+50);
 await at(2.94);await page.touchscreen.tap(1300,550);await at(3.2);
 assert((await page.evaluate(()=>window.meowState.combat.perfect))>0);
 await at(6.94);await page.touchscreen.tap(1300,660);await at(7.2);
 assert.equal(await page.evaluate(()=>window.meowState.combat.dashes),1);
 await page.keyboard.press('Escape');await screen('combat_pause');await page.mouse.click(820,518);await screen('menu');
 await page.mouse.click(305,558);await screen('adv_intro');await page.keyboard.press('Enter');await screen('adv_play');await page.keyboard.press('Escape');await screen('adv_pause');await page.mouse.click(820,510);await screen('menu');
 await page.mouse.click(130,558);await screen('play');await page.keyboard.press('Escape');await screen('pause');
 await context.close();assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 fs.writeFileSync(path.join(root,'artifacts/groove-browser-results.json'),JSON.stringify({result,sawBoss,sawOverdrive,pause:true,touchMove:true,touchFire:true,touchDash:true,oldModes:true,errors,external},null,2));
 console.log('PASS full groove: 64 chart actions, buffered shots, mandatory dashes, half beats, melodic input, boss, pause, touch, old modes, offline.');
})().catch(e=>{console.error(e);process.exit(1);});
