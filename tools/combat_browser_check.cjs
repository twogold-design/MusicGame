const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime/combat-browser'),{executablePath:process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},hasTouch:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('request',r=>{if(/^https?:/.test(r.url()))external.push(r.url());});
 const screen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 const at=t=>page.waitForFunction(t=>window.meowState?.screen!=='combat_play'||window.meowState.combat.elapsed+(performance.now()-window.meowState.stamp)/1000>=t,t,{timeout:6000});
 await page.goto(pathToFileURL(path.join(root,'index.html')).href);await screen('combat_intro');
 await page.screenshot({path:path.join(root,'artifacts/combat-intro.png')});
 if(!(await page.evaluate(()=>window.meowState.easy))){await page.mouse.click(960,802);await page.waitForTimeout(150);}
 await page.keyboard.press('Enter');await screen('combat_play');
 await page.waitForTimeout(700);await page.keyboard.press('Escape');await screen('combat_pause');
 const paused=await page.evaluate(()=>window.meowState.combat.elapsed);
 await page.keyboard.down('d');await page.waitForTimeout(300);assert.equal(await page.evaluate(()=>window.meowState.combat.elapsed),paused);
 await page.keyboard.press('Escape');await screen('combat_play');await page.waitForTimeout(180);
 assert(Math.abs((await page.evaluate(()=>window.meowState.combat.player))[0]-720)<1);await page.keyboard.up('d');
 let previous=null, sawBoss=false,sawOverdrive=false;
 for(let beat=0;beat<60;beat++){
  await at(2+beat*.5+.025);
  const state=await page.evaluate(()=>window.meowState);
  if(state.screen==='combat_result')break;
  const c=state.combat;
  sawBoss ||= c.enemies.some(e=>e.boss);
  sawOverdrive ||= c.overdrives>0;
  const target=c.enemies.find(e=>e.boss)||c.enemies.reduce((best,e)=>!best||Math.hypot(e.x-c.player[0],e.y-c.player[1])<Math.hypot(best.x-c.player[0],best.y-c.player[1])?e:best,null);
  await page.mouse.click(target?.x||1110,target?.y||430);
  // Move around a central orbit instead of blindly running along incoming fire.
  const desired=[720+160*Math.cos(beat*.40),480+115*Math.sin(beat*.40)];
  const move=[];
  if(Math.abs(desired[0]-c.player[0])>18)move.push(desired[0]>c.player[0]?'d':'a');
  if(Math.abs(desired[1]-c.player[1])>18)move.push(desired[1]>c.player[1]?'s':'w');
  for(const key of move)await page.keyboard.down(key);
  if(beat%8===4)await page.keyboard.press('Space');
  if(beat===0){await at(2.32);await page.mouse.click(1100,430);}
  if(beat===18||beat===44)await page.screenshot({path:path.join(root,'artifacts',beat===18?'combat-action.png':'combat-boss.png')});
  await page.waitForTimeout(150);
  for(const key of move)await page.keyboard.up(key);
 }
 if(previous)await page.keyboard.up(previous);
 await screen('combat_result');
 const result=await page.evaluate(()=>window.meowState.combat);
 await page.screenshot({path:path.join(root,'artifacts/combat-result.png')});
 console.log('RESULT',JSON.stringify(result));
 assert(result.won);assert(result.perfect>35);assert(result.normal>=1);assert(result.kills>=5);assert(result.dashes>=3);assert(result.bossDefeated);assert(sawBoss&&sawOverdrive);
 await page.mouse.click(570,650);await screen('combat_play');
 await at(2.2);
 const before=await page.evaluate(()=>window.meowState.combat.player);
 const cdp=await context.newCDPSession(page);
 await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:185,y:650,id:0}]});
 await page.waitForTimeout(300);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 await page.waitForTimeout(150);assert((await page.evaluate(()=>window.meowState.combat.player))[0]>before[0]+50);
 await page.touchscreen.tap(1300,550);await page.waitForTimeout(150);
 assert((await page.evaluate(()=>window.meowState.combat.perfect+window.meowState.combat.normal))>0);
 await page.touchscreen.tap(1300,660);await page.waitForTimeout(150);assert.equal(await page.evaluate(()=>window.meowState.combat.dashes),1);
 await page.keyboard.press('Escape');await screen('combat_pause');await page.mouse.click(820,518);await screen('menu');
 await page.mouse.click(305,558);await screen('adv_intro');await page.keyboard.press('Enter');await screen('adv_play');await page.keyboard.press('Escape');await screen('adv_pause');await page.mouse.click(820,510);await screen('menu');
 await page.mouse.click(130,558);await screen('play');await page.keyboard.press('Escape');await screen('pause');
 await context.close();assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 fs.writeFileSync(path.join(root,'artifacts/combat-browser-results.json'),JSON.stringify({result,sawBoss,sawOverdrive,pause:true,touchMove:true,touchFire:true,touchDash:true,oldModes:true,errors,external},null,2));
 console.log('PASS full 30s real-input combat: rhythm, free movement, dash, overdrive, boss, pause, touch, old modes, offline.');
})().catch(e=>{console.error(e);process.exit(1);});
