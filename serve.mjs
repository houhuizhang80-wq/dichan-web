// ============================================================================
// serve.mjs —— 阶段 0 本地开发服务器
//   /            -> 本目录（index.html / js / css / lua / vendor）
//   /game/*      -> ../地产风云/src/*（原始 Lua 工程，只读）
//   /__modules.json -> 模块名 -> URL 清单
// 用法：node serve.mjs   （默认 http://127.0.0.1:5173）
// ============================================================================

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WEB_ROOT, GAME_ROOT, buildModuleUrls } from './tools/modules.mjs';

const PORT = Number(process.env.PORT || 5173);
// 默认绑 0.0.0.0：本机和局域网手机都能访问。
// 只给本机用可以设 HOST=127.0.0.1。
const HOST = process.env.HOST || '0.0.0.0';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.lua': 'text/plain; charset=utf-8',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.ogg': 'audio/ogg',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.md': 'text/markdown; charset=utf-8',
};

function send(res, code, body, type) {
  res.writeHead(code, { 'Content-Type': type || 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(body);
}

function sendFile(res, file) {
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, 'Not Found: ' + file);
    send(res, 200, data, MIME[path.extname(file).toLowerCase()] || 'application/octet-stream');
  });
}

/** 防止路径穿越 */
function resolveInside(root, urlPath) {
  const target = path.resolve(root, '.' + decodeURIComponent(urlPath));
  const rel = path.relative(root, target);
  if (rel.startsWith('..') || path.isAbsolute(rel)) return null;
  return target;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const pathname = url.pathname;

  // 页面内测试结果回传通道：POST /__report?name=perf
  // （无头浏览器不开 virtual-time 时无法用 --dump-dom 取结果，所以走这个）
  if (pathname === '/__report' && req.method === 'POST') {
    const name = (url.searchParams.get('name') || 'report').replace(/[^\w.-]/g, '_');
    const dir = path.join(WEB_ROOT, '.out', 'reports');
    fs.mkdirSync(dir, { recursive: true });
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      fs.writeFileSync(path.join(dir, name + '.json'), body);
      send(res, 200, JSON.stringify({ ok: true, name }), MIME['.json']);
    });
    return;
  }

  if (pathname === '/__modules.json') {
    return send(res, 200, JSON.stringify({ modules: buildModuleUrls() }), MIME['.json']);
  }

  if (pathname === '/' || pathname === '/index.html') {
    return sendFile(res, path.join(WEB_ROOT, 'index.html'));
  }

  if (pathname.startsWith('/game/')) {
    const file = resolveInside(GAME_ROOT, pathname.slice('/game'.length));
    if (!file) return send(res, 403, 'Forbidden');
    return sendFile(res, file);
  }

  const file = resolveInside(WEB_ROOT, pathname);
  if (!file) return send(res, 403, 'Forbidden');
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) {
    return sendFile(res, path.join(file, 'index.html'));
  }
  return sendFile(res, file);
});

/** 列出所有可用的局域网地址，方便手机直接打开 */
function lanUrls(port) {
  const out = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) out.push({ name, url: `http://${a.address}:${port}/` });
    }
  }
  return out;
}

server.listen(PORT, HOST, () => {
  console.log(`[web] 地产风云 · 网页移植`);
  console.log(`[web] 本机    : http://127.0.0.1:${PORT}/`);
  const lan = lanUrls(PORT);
  if (lan.length) {
    console.log(`[web] 局域网（手机同一 WiFi 下直接打开）:`);
    for (const { name, url } of lan) console.log(`[web]   ${url}   (${name})`);
    console.log(`[web]   提示：手机访问若打不开，多半是 Windows 防火墙没放行，`);
    console.log(`[web]        管理员 PowerShell 执行一次：`);
    console.log(`[web]        New-NetFirewallRule -DisplayName "dichan-web ${PORT}" -Direction Inbound -Protocol TCP -LocalPort ${PORT} -Action Allow`);
  }
  console.log(`[web] 游戏源码: ${GAME_ROOT}`);
  console.log(`[web] 垫片目录: ${path.join(WEB_ROOT, 'lua')}`);
  console.log(`[web] 注意：局域网 http 下 Service Worker 不会注册（需要 https 或 localhost），`);
  console.log(`[web]      所以手机上能玩但没有离线缓存，这是浏览器的安全策略。`);
});
