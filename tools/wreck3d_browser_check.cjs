const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const root = path.resolve(__dirname, '..');
const web = path.join(root, 'build/web');
const packageEntry = pathToFileURL(path.join(root, '.runtime/wreck3d-package/index.html')).href;
const artifactDir = path.join(root, 'artifacts');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const file = path.join(web, new URL(req.url, 'http://localhost').pathname);
  if (!file.startsWith(web + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404).end();
    return;
  }
  res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
  fs.createReadStream(file).pipe(res);
});

async function run() {
  fs.mkdirSync(artifactDir, { recursive: true });
  const context = await chromium.launchPersistentContext(path.join(root, '.runtime/wreck3d-browser'), {
    executablePath: process.env.CHROME_BIN || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
    viewport: { width: 1440, height: 900 },
    hasTouch: true,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-crash-reporter', '--disable-breakpad'],
  });
  const page = await context.newPage();
  const errors = [];
  const external = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && !message.text().includes('404')) errors.push(message.text());
  });
  page.on('request', request => {
    if (/^https?:/.test(request.url()) && !request.url().includes('127.0.0.1')) external.push(request.url());
  });

  const screen = name => page.waitForFunction(name => window.meowState?.screen === name, name, { timeout: 90000 });
  const state = () => page.evaluate(() => window.meowState.combat);
  const waitFor = (key, value) => page.waitForFunction(
    ([key, value]) => window.meowState?.combat?.[key] === value, [key, value],
  );
  const atBeat = time => page.waitForFunction(time => {
    const sinceReport = Math.min(0.12, (performance.now() - window.meowState.stamp) / 1000);
    return window.meowState.combat.rhythmTime + sinceReport >= time - 0.018;
  }, time);
  const nextBeat = time => Math.ceil(time * 2) / 2;
  const shot = name => page.screenshot({ path: path.join(artifactDir, name) });

  try {
    await page.goto(process.env.WRECK3D_ENTRY || pathToFileURL(path.join(root, 'index.html')).href);
    await screen('combat_intro');
    await shot('wreck3d-intro.png');
    await page.mouse.click(720, 768);
    await screen('combat_play');
    const first = await state();
    assert.equal(first.mode, 'wreck3d');
    assert(first.worldMeshes > 200);
    await page.keyboard.press('Space');
    await waitFor('hits', 1);
    assert((await state()).objects.some(prop => prop.hp < first.objects[prop.id].hp));
    await page.waitForTimeout(160);

    const dummy = first.objects.find(prop => prop.title === '插队大叔');
    assert(dummy);
    const comboStart = nextBeat(Math.max(2.0, (await state()).rhythmTime + 0.30));
    await atBeat(comboStart);
    await page.mouse.click(dummy.x, dummy.y);
    await waitFor('slaps', 1);
    assert.equal((await state()).doubleTarget, dummy.id);
    assert.equal((await state()).nameTag, dummy.title);
    await atBeat(comboStart + 0.25);
    await page.keyboard.press('Space');
    await waitFor('doubleHits', 1);
    assert.equal((await state()).slaps, 2);
    assert.equal((await state()).nameTag, dummy.title);
    await shot('wreck3d-slap.png');

    const safe = first.objects.find(prop => prop.kind === 'safe');
    await page.mouse.move(safe.x, safe.y);
    await page.mouse.down();
    await waitFor('charge', 1);
    assert.equal((await state()).target, safe.id);
    await atBeat(nextBeat((await state()).rhythmTime + 0.18));
    await page.mouse.up();
    await waitFor('timedHeavies', 1);
    assert((await state()).objects[safe.id].hp < safe.hp);
    assert.equal((await state()).shopIdentity, first.shopIdentity);

    await page.keyboard.press('Escape');
    await screen('combat_pause');
    const paused = (await state()).elapsed;
    await page.waitForTimeout(250);
    assert.equal((await state()).elapsed, paused);
    await page.keyboard.press('Escape');
    await screen('combat_play');
    await shot('wreck3d-before.png');

    await page.mouse.click(1324, 50);
    await screen('combat_result');
    assert((await state()).won);
    await shot('wreck3d-result.png');
    await page.keyboard.press('Enter');
    await screen('combat_play');
    const restart = await state();
    assert.notEqual(restart.shopIdentity, first.shopIdentity);
    assert.equal(restart.slaps, 0);
    assert.equal(restart.hits, 0);
    assert.equal(restart.onBeat, 0);
    await page.keyboard.press('Tab');
    await waitFor('target', (restart.target + 1) % restart.objects.length);

    const touchTarget = restart.objects.find(prop => prop.id === dummy.id);
    await page.touchscreen.tap(touchTarget.x, touchTarget.y);
    await waitFor('slaps', 1);
    const touchSafe = restart.objects[safe.id];
    await page.waitForTimeout(160);
    const cdp = await context.newCDPSession(page);
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchStart', touchPoints: [{ x: touchSafe.x, y: touchSafe.y, id: 0 }],
    });
    await waitFor('charge', 1);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await waitFor('heavyHits', 1);
    assert((await state()).objects[safe.id].hp < safe.hp);

    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    await page.setViewportSize({ width: 900, height: 450 });
    await page.goto('http://127.0.0.1:' + server.address().port + '/index.html');
    await screen('combat_intro');
    await page.touchscreen.tap(450, 384);
    await screen('combat_play');
    const mobileDummy = (await state()).objects.find(prop => prop.id === dummy.id);
    await page.touchscreen.tap(90 + mobileDummy.x * 0.5, mobileDummy.y * 0.5);
    await waitFor('slaps', 1);
    await shot('wreck3d-mobile.png');
    await page.setViewportSize({ width: 450, height: 900 });
    assert(await page.locator('#rotate').isVisible());

    if (!process.env.WRECK3D_SKIP_PACKAGE) {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(packageEntry);
      await screen('combat_intro');
      await page.keyboard.press('Enter');
      await screen('combat_play');
      await page.keyboard.press('Space');
      await waitFor('hits', 1);
    }

    assert.deepEqual(errors, []);
    assert.deepEqual(external, []);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'dist/manifest.json'), 'utf8').replace(/^\uFEFF/, ''));
    assert(manifest.web_bytes < 200000000 && manifest.zip_bytes < 200000000);
    console.log('PASS offline entry, beat tap, offbeat double, NPC name, held strike, pause, finish, restart, touch and HTTP');
  } finally {
    await context.close();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}

run().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
