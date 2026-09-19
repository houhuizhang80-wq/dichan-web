// ============================================================================
// sw.js —— Service Worker：把整个游戏（外壳 + Lua 源码 + 字体 + wasm + 音频）
// 预缓存下来，之后完全离线可用。
//
// 模块清单在 install 时从 /__modules.json 拉取（开发服务器提供）；
// 生产环境可以把清单内联进来，或改成构建期生成。
// ============================================================================

const CACHE = 'dichan-v1';

// 应用外壳
const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './css/app.css',
  './css/fonts.css',
  './js/main.js',
  './js/host.js',
  './js/bridge.js',
  './js/audit.js',
  './vendor/wasmoon/index.js',
  './vendor/wasmoon/glue.wasm',
  './vendor/fonts/NotoSansSC.woff2',
  './vendor/fonts/FusionPixelProp.woff2',
  './vendor/fonts/FusionPixelPropBold.woff2',
  './vendor/fonts/FusionPixelMono.woff2',
  './vendor/icons/icon-192.png',
  './vendor/icons/icon-512.png',
];

async function moduleUrls() {
  try {
    const res = await fetch('./__modules.json', { cache: 'no-store' });
    if (!res.ok) return [];
    const { modules } = await res.json();
    return Object.values(modules);
  } catch {
    return [];
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // 外壳必须成功；单个模块失败不阻塞安装
    await cache.addAll(SHELL).catch(() => {});
    const urls = await moduleUrls();
    await Promise.all(urls.map((u) => cache.add(u).catch(() => {})));
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  const path = url.pathname;

  // 代码类资源走「网络优先」：开发时改了 Lua/JS 立刻生效，
  // 离线时再退回缓存。否则 cache-first 会让浏览器一直吃旧代码，调试会非常迷惑。
  const isCode = path.endsWith('/__modules.json')
    || path.startsWith('/game/')
    || path.startsWith('/lua/')
    || /\.(js|mjs|css|html|lua|json|webmanifest)$/.test(path);

  if (isCode) {
    event.respondWith((async () => {
      try {
        const res = await fetch(req);
        if (res && res.ok && res.type === 'basic') {
          const cache = await caches.open(CACHE);
          cache.put(req, res.clone());
        }
        return res;
      } catch (e) {
        const cached = await caches.match(req, { ignoreSearch: true });
        if (cached) return cached;
        const shell = await caches.match('./index.html');
        if (shell) return shell;
        throw e;
      }
    })());
    return;
  }

  // 静态大资源（wasm / 字体 / 图标 / 音频）走「缓存优先」
  event.respondWith((async () => {
    const cached = await caches.match(req, { ignoreSearch: true });
    if (cached) return cached;
    try {
      const res = await fetch(req);
      if (res && res.ok && res.type === 'basic') {
        const cache = await caches.open(CACHE);
        cache.put(req, res.clone());
      }
      return res;
    } catch (e) {
      const shell = await caches.match('./index.html');
      if (shell) return shell;
      throw e;
    }
  })());
});
