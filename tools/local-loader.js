(() => {
  if (location.protocol !== 'file:') return;
  window.MEOW_LOCAL_READY = new Promise((resolve, reject) => {
    if (!window.DecompressionStream) return reject(new Error('请使用新版 Chrome 或 Edge 打开游戏。'));
    const script = document.createElement('script');
    script.src = new URL('local-data.js', document.baseURI).href;
    script.onerror = () => reject(new Error('资源缺失，请完整解压游戏压缩包，再打开 index.html。'));
    script.onload = () => {
      try {
        const data = window.MEOW_LOCAL_DATA;
        const resources = new Map(Object.entries(data.files).map(([name, value]) => [new URL(name, document.baseURI).href, value]));
        const fetchOriginal = window.fetch.bind(window);
        window.fetch = (input, options) => {
          const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
          const entry = resources.get(url);
          if (!entry) return fetchOriginal(input, options);
          if (!entry.bytes) {
            const binary = atob(entry.gzip);
            entry.bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
            delete entry.gzip;
          }
          const stream = new Blob([entry.bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
          return Promise.resolve(new Response(stream, {status:200,headers:{'Content-Type':entry.mime,'Content-Length':String(entry.size)}}));
        };
        const worklets = new Map(Object.entries(data.worklets).map(([name, source]) => [new URL(name, document.baseURI).href,'data:text/javascript;charset=utf-8,'+encodeURIComponent(source)]));
        if (typeof Worklet !== 'undefined') {
          const original = Worklet.prototype.addModule;
          Worklet.prototype.addModule = function(url,options) { return original.call(this,worklets.get(new URL(String(url),document.baseURI).href)||url,options); };
        }
        delete window.MEOW_LOCAL_DATA;
        resolve();
      } catch(error) { reject(error); }
    };
    document.head.appendChild(script);
  });
})();
