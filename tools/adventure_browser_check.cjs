const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'..'),dirs=[[0,-1,'ArrowUp'],[1,0,'ArrowRight'],[0,1,'ArrowDown'],[-1,0,'ArrowLeft']];
const key=p=>p.join(',');
function route(s,goal,avoid){
 const walls=new Set(s.walls.map(key)),seen=new Set([key(s.player)]),queue=[{p:s.player,path:[]}];
 for(let i=0;i<queue.length;i++){
  const n=queue[i];if(key(n.p)===key(goal))return n.path;
  for(const d of dirs){const p=[n.p[0]+d[0],n.p[1]+d[1]],k=key(p);if(p[0]<0||p[0]>8||p[1]<0||p[1]>6||walls.has(k)||seen.has(k)||(n.path.length===0&&avoid.has(k)))continue;seen.add(k);queue.push({p,path:[...n.path,d]});}
 }return null;
}
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime/adventure-browser'),{executablePath:process.env.CHROME_BIN||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},hasTouch:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const page=await context.newPage(),errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 page.on('request',r=>{if(/^https?:/.test(r.url()))external.push(r.url());});
 const screen=s=>page.waitForFunction(s=>window.meowState?.screen===s,s,{timeout:60000});
 await page.goto(pathToFileURL(path.join(root,'index.html')).href);await screen('menu');
 await page.screenshot({path:path.join(root,'artifacts/adventure-menu.png')});
 if(!(await page.evaluate(()=>window.meowState.easy)))await page.mouse.click(440,488);
 await page.mouse.click(180,490);await screen('adv_intro');
 await page.screenshot({path:path.join(root,'artifacts/adventure-intro.png')});
 await page.keyboard.press('Enter');await screen('adv_play');
 await page.waitForTimeout(1200);await page.keyboard.press('Escape');await screen('adv_pause');
 const paused=await page.evaluate(()=>window.meowState.adventure.elapsed);await page.waitForTimeout(450);assert.equal(await page.evaluate(()=>window.meowState.adventure.elapsed),paused);
 await page.keyboard.press('Escape');await screen('adv_play');
 await page.waitForFunction(()=>window.meowState.adventure.beat>=0);
 await page.screenshot({path:path.join(root,'artifacts/adventure-start.png')});
 const milestones=new Set();let victory=null;
 for(let tick=0;tick<190;tick++){
  let state=await page.evaluate(()=>window.meowState);
  if(state.screen==='adv_result'){victory=state.adventure;break;}
  const s=state.adventure,avoid=new Set(s.nextBots.map(key));
  if(s.beat+1===s.nextStrike)for(const cell of s.danger)avoid.add(key(cell));
  let goal;
  if(s.bank>=9)goal=[4,0];else if(s.bag>=3||s.bag+s.bank>=9)goal=[4,3];else{
   const options=s.pickups.map(t=>({t,route:route(s,[t.x,t.y],avoid)})).filter(v=>v.route?.length);
   options.sort((a,b)=>a.route.length/a.t.value-b.route.length/b.t.value);
   goal=options.length?[options[0].t.x,options[0].t.y]:[4,3];
  }
  let moves=route(s,goal,avoid);
  if(!moves?.length&&avoid.has(key(s.player)))for(const d of dirs){const p=[s.player[0]+d[0],s.player[1]+d[1]];const r=route(s,p,avoid);if(r?.length===1){moves=r;break;}}
  const target=(s.beat+5)*s.beatLength-0.10;
  await page.waitForFunction(t=>window.meowState.screen!=='adv_play'||window.meowState.adventure.elapsed+(performance.now()-window.meowState.stamp)/1000>=t,target,{timeout:4000});
  if((await page.evaluate(()=>window.meowState.screen))!=='adv_play')continue;
  await page.keyboard.press(moves?.length?moves[0][2]:'Space');
  await page.waitForFunction(b=>window.meowState.screen!=='adv_play'||window.meowState.adventure.beat>b,s.beat,{timeout:4000});
  state=await page.evaluate(()=>window.meowState);
  if(!milestones.has(state.adventure.repaired)&&state.adventure.repaired>0){
   milestones.add(state.adventure.repaired);
   await page.screenshot({path:path.join(root,'artifacts/adventure-layer-'+state.adventure.repaired+'.png')});
   console.log('LAYER',JSON.stringify({beat:state.adventure.beat,bank:state.adventure.bank,hearts:state.adventure.hearts,elapsed:state.adventure.elapsed}));
  }
 }
 assert(victory?.won,'The real-input adventure must reach the exit with all music restored');
 assert.equal(victory.bank,9);assert.equal(victory.repaired,3);assert(victory.moves>10);assert(milestones.has(3));
 await page.screenshot({path:path.join(root,'artifacts/adventure-victory.png')});
 const firstSeed=victory.seed;await page.mouse.click(580,648);await screen('adv_play');assert.notEqual(await page.evaluate(()=>window.meowState.adventure.seed),firstSeed);
 // Touch navigation and dash control with the actual game canvas.
 await page.waitForFunction(()=>window.meowState.adventure.beat>=0);
 await page.touchscreen.tap(1220,560);await page.waitForTimeout(900);
 assert.equal((await page.evaluate(()=>window.meowState.adventure.player))[1],5);
 await page.touchscreen.tap(1210,470);await page.waitForTimeout(150);assert.equal(await page.evaluate(()=>window.meowState.adventure.dash),true);
 await page.touchscreen.tap(1220,560);await page.waitForTimeout(900);
 assert.equal((await page.evaluate(()=>window.meowState.adventure.player))[1],3);
 await page.keyboard.press('Escape');await screen('adv_pause');await page.mouse.click(820,510);await screen('menu');
 await page.mouse.click(130,558);await screen('play');await page.waitForTimeout(3200);await page.keyboard.press('Escape');await screen('pause');
 await context.close();
 fs.writeFileSync(path.join(root,'artifacts/adventure-browser-results.json'),JSON.stringify({victory,milestones:[...milestones],pause:true,touchMovement:true,touchDash:true,newMap:true,classicMode:true,errors,external},null,2));
 assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 console.log('PASS: real-key full adventure victory, three audio layers, new map, pause, touch move/dash, classic mode, offline. Score',victory.score);
})().catch(e=>{console.error(e);process.exitCode=1;});
