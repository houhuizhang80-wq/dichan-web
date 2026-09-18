// ============================================================================
// tools/browser-extra.mjs —— 阶段 4：真实浏览器里的存档持久化 / 性能基准 / PWA
//
//   ① 存档持久化：同一份浏览器 profile 连续加载两次页面，
//      第一次写存档，第二次读存档，验证 localStorage 真的跨刷新保留
//   ② 性能基准：?perf=1 在页面内量测 HandleUpdate 与屏幕切换耗时
//   ③ PWA：manifest / sw.js 的 MIME，Service Worker 注册与预缓存内容
//
// 注意：这里**不能**用 --virtual-time-budget —— 它会把 performance.now() 冻住，
// 量出来全是 0。所以改成「页面把结果 POST 回开发服务器，验收脚本轮询文件」。
//
// 用法：node tools/browser-extra.mjs
// ============================================================================

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = path.join(WEB_ROOT, '.out');
const REPORT_DIR = path.join(OUT_DIR, 'reports');
const PORT = Number(process.env.PORT || 5176);
const BASE = `http://127.0.0.1:${PORT}`;

const BROWSERS = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
];

const findBrowser = () => BROWSERS.find((p) => fs.existsSync(p)) || null;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    const detail = await fn();
    passed++;
    console.log(`  \x1b[32m✔\x1b[0m ${name}${detail ? '  ' + detail : ''}`);
  } catch (e) {
    failed++;
    console.log(`  \x1b[31m✘\x1b[0m ${name}\n      ${e && e.message ? e.message : e}`);
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || '断言失败');
}

async function waitForServer(timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(BASE + '/__modules.json');
      if (r.ok) return;
    } catch { /* 等待 */ }
    await sleep(200);
  }
  throw new Error('开发服务器启动超时');
}

const browser = findBrowser();
if (!browser) {
  console.error('未找到 Edge/Chrome，跳过浏览器验收');
  process.exit(0);
}

fs.mkdirSync(REPORT_DIR, { recursive: true });
const profile = path.join(OUT_DIR, 'edge-profile-extra');
fs.rmSync(profile, { recursive: true, force: true });

const server = spawn(process.execPath, [path.join(WEB_ROOT, 'serve.mjs')], {
  cwd: WEB_ROOT,
  env: { ...process.env, PORT: String(PORT) },
  stdio: ['ignore', 'ignore', 'pipe'],
});

/** 打开页面并等它把结果 POST 回来（不开 virtual-time，量测才是真的） */
async function runAndCollect(urlPath, reportName, timeoutMs = 240000) {
  const file = path.join(REPORT_DIR, reportName + '.json');
  fs.rmSync(file, { force: true });

  const child = spawn(browser, [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--no-first-run',
    '--disable-extensions',
    `--user-data-dir=${profile}`,
    '--window-size=900,1000',
    `${BASE}${urlPath}`,
  ], { stdio: ['ignore', 'ignore', 'ignore'] });

  const deadline = Date.now() + timeoutMs;
  try {
    while (Date.now() < deadline) {
      if (fs.existsSync(file)) {
        await sleep(150);
        return JSON.parse(fs.readFileSync(file, 'utf8'));
      }
      await sleep(250);
    }
    throw new Error(`等待报告超时（${reportName}）`);
  } finally {
    child.kill();
    await sleep(300);
  }
}

try {
  await waitForServer();
  console.log('\n=== 地产风云 · 网页移植阶段 4 · 浏览器持久化 / 性能 / PWA ===\n');
  console.log(`服务器: ${BASE}\n`);

  // -------------------------------------------------------------------------
  console.log('[1] 存档持久化（跨页面刷新，同一份 profile）');
  let writeResult = null;
  await check('第一次加载：写入存档槽位 1', async () => {
    const rep = await runAndCollect('/?savecheck=1&nosw=1', 'save-report', 120000);
    writeResult = rep.result;
    assert(String(rep.result).startsWith('true|'), '存档失败: ' + rep.result);
    return String(rep.result);
  });

  await check('第二次加载：读到上一次写的存档（localStorage 生效）', async () => {
    assert(writeResult, '前一步没有写入成功');
    const rep = await runAndCollect('/?savecheck=2&nosw=1', 'save-report', 120000);
    assert(rep.result !== 'no-save', '刷新后存档丢失');
    assert(String(rep.result).startsWith('持久化测试地产|424242'), '读到的存档内容不对: ' + rep.result);
    return String(rep.result);
  });

  // -------------------------------------------------------------------------
  console.log('\n[2] 性能基准（真实时钟，页面内量测）');
  await check('模拟步进与屏幕切换耗时', async () => {
    const rep = await runAndCollect('/?perf=1&nosw=1', 'perf-report', 300000);
    fs.writeFileSync(path.join(OUT_DIR, 'perf.json'), JSON.stringify(rep, null, 2));

    const t = rep.tick;
    const n = rep.navigate;
    console.log(`      游戏时间推进到: ${rep.screen}`);
    console.log(`      HandleUpdate ×${t.samples}: p50=${t.p50}ms  p95=${t.p95}ms  p99=${t.p99}ms  max=${t.max}ms  mean=${t.mean}ms`);
    console.log(`        超过一帧(16.7ms)的次数: ${t.over16ms} / ${t.samples}`);
    console.log(`      Navigate ×${n.samples}: p50=${n.p50}ms  p95=${n.p95}ms  max=${n.max}ms`);
    console.log(`        最慢的屏: ${n.slowest.join('  ')}`);

    assert(t.samples >= 1000, '采样数不足');
    assert(t.p95 < 16.7, `HandleUpdate p95=${t.p95}ms 超过一帧预算（60fps）`);
    assert(n.p95 < 100, `Navigate p95=${n.p95}ms 太慢`);
    return `tick p50=${t.p50}ms/p95=${t.p95}ms · nav p50=${n.p50}ms/p95=${n.p95}ms`;
  });

  // -------------------------------------------------------------------------
  console.log('\n[3] PWA');
  await check('manifest 与 sw.js 可访问且 MIME 正确', async () => {
    const mf = await fetch(BASE + '/manifest.webmanifest');
    assert(mf.ok, 'manifest HTTP ' + mf.status);
    const mime = mf.headers.get('content-type');
    assert(mime.includes('manifest+json'), 'manifest MIME 异常: ' + mime);
    const mfJson = await mf.json();
    assert(mfJson.icons && mfJson.icons.length >= 2, 'manifest 缺少图标');
    assert(mfJson.display === 'standalone', 'display 应为 standalone');

    const sw = await fetch(BASE + '/sw.js');
    assert(sw.ok, 'sw.js HTTP ' + sw.status);
    assert(sw.headers.get('content-type').includes('javascript'), 'sw.js MIME 异常');

    for (const icon of mfJson.icons) {
      const r = await fetch(new URL(icon.src, BASE + '/').href);
      assert(r.ok, `图标 ${icon.src} HTTP ${r.status}`);
    }
    return `${mfJson.icons.length} 个图标，MIME 正确`;
  });

  await check('Service Worker 注册并预缓存游戏资源', async () => {
    const rep = await runAndCollect('/?swcheck=1', 'sw-report', 180000);
    fs.writeFileSync(path.join(OUT_DIR, 'sw.json'), JSON.stringify(rep, null, 2));
    assert(rep.supported, '浏览器不支持 Service Worker');
    assert(!rep.error, 'SW 报错: ' + rep.error);
    assert(rep.active, 'SW 未激活');
    assert(rep.cachedCount > 20, `预缓存条目过少: ${rep.cachedCount}`);
    assert(rep.hasWasm, '未缓存 glue.wasm');
    assert(rep.hasFont, '未缓存字体');
    assert(rep.hasLua, '未缓存游戏 Lua 源码');
    return `scope=${rep.scope} 缓存 ${rep.cachedCount} 项（wasm/字体/Lua 均已缓存）`;
  });
} catch (e) {
  failed++;
  console.log(`  \x1b[31m✘\x1b[0m 验收异常: ${e && e.message ? e.message : e}`);
} finally {
  server.kill();
}

console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项 ===`);
console.log(`报告: ${path.join(OUT_DIR, 'perf.json')} / sw.json\n`);
process.exit(failed > 0 ? 1 : 0);
