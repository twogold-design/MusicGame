const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
const root=path.resolve(__dirname,'..'), web=path.join(root,'build','web');
const bundle={files:{},worklets:{}};
for(const name of ['index.wasm','index.pck']) {
  const b=fs.readFileSync(path.join(web,name));
  bundle.files[name]={size:b.length,mime:name.endsWith('.wasm')?'application/wasm':'application/octet-stream',gzip:zlib.gzipSync(b,{level:9}).toString('base64')};
}
for(const name of ['index.audio.worklet.js','index.audio.position.worklet.js']) if(fs.existsSync(path.join(web,name))) bundle.worklets[name]=fs.readFileSync(path.join(web,name),'utf8');
fs.writeFileSync(path.join(web,'local-data.js'),'window.MEOW_LOCAL_DATA='+JSON.stringify(bundle)+';\n');
fs.copyFileSync(path.join(__dirname,'local-loader.js'),path.join(web,'local-loader.js'));
const jsPath=path.join(web,'index.js');
let js=fs.readFileSync(jsPath,'utf8');
const hook='function _godot_js_pwa_cb(p_update_cb){';
if(!js.includes(hook)) throw Error('Godot local-file service-worker hook changed');
js=js.replace(hook,hook+'if(location.protocol==="file:")return;');
fs.writeFileSync(jsPath,js);
const htmlPath=path.join(web,'index.html');
let html=fs.readFileSync(htmlPath,'utf8');
html=html.replace('<html lang="en">','<html lang="zh-CN">').replace('<script src="index.js"></script>','<script src="local-loader.js"></script><script src="index.js"></script>');
html=html.replace('(function () {','(async function () {').replace('const missing = Engine.getMissingFeatures({',"try { await window.MEOW_LOCAL_READY; } catch(error) { displayFailureNotice(error); return; }\nconst missing = Engine.getMissingFeatures({");
html=html.replace("setStatusMode('hidden');","const ready = () => { if(window.meowReady) setStatusMode('hidden'); else requestAnimationFrame(ready); }; ready();");
html=html.replace('</head>',`<style>body,#status{background:#0c0f19}#status-splash{display:none!important}#status:before{content:'MEOW BEAT';font:800 40px system-ui;color:#dbff79;letter-spacing:5px;margin-bottom:25px}#status:after{content:'喵喵打碟俱乐部 · 正在准备今晚的音乐…';font:16px system-ui;color:#919bb3;margin-top:24px}#status-progress{position:relative;bottom:auto;width:300px;height:7px;accent-color:#dbff79}canvas{touch-action:none}body{touch-action:none}#rotate{display:none;position:fixed;inset:0;background:#0c0f19f5;color:#dbff79;z-index:50;text-align:center;place-content:center;font:700 25px system-ui;padding:30px}#rotate small{display:block;font:16px system-ui;color:#919bb3;margin-top:18px}@media(orientation:portrait) and (max-width:850px){#rotate{display:grid}}</style></head>`);
html=html.replace('<body>','<body><div id="rotate">↻ 横屏一下，让舞池更大<small>请旋转手机，使用双手跟上节拍</small></div>');
fs.writeFileSync(htmlPath,html);
console.log('Offline web resources ready.');
