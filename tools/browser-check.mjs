// ============================================================================
// tools/browser-check.mjs —— 真实浏览器验收（Edge/Chrome 无头 + 截图）
// 逐屏截图到 .out/shots/<screen>.png，并给出体积统计（过小说明渲染为空）
// 用法：node tools/browser-check.mjs [屏幕1 屏幕2 ...]
// ============================================================================

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = path.join(WEB_ROOT, '.out', 'shots');
const PORT = Number(process.env.PORT || 5174);
const BASE = `http://127.0.0.1:${PORT}`;

const BROWSERS = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
];

const DEFAULT_SCREENS = [
  'start', 'changelog', 'companyCreate', 'city', 'dashboard', 'invest', 'auction',
  'project', 'sales', 'asset', 'capital', 'brand', 'personal', 'personalLife',
  'personalFinance', 'governance', 'group', 'international',
  'groupDiversification', 'settings', 'ledger',
];

const screens = process.argv.slice(2).length ? process.argv.slice(2) : DEFAULT_SCREENS;

function findBrowser() {
  for (const p of BROWSERS) if (fs.existsSync(p)) return p;
  return null;
}

async function waitForServer(timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(BASE + '/__modules.json');
      if (r.ok) return;
    } catch { /* 等待 */ }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('开发服务器启动超时');
}

function runBrowser(exe, args, timeoutMs = 60000) {
  return new Promise((resolve) => {
    const child = spawn(exe, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (d) => (stderr += d.toString()));
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stderr });
    });
  });
}

const browser = findBrowser();
if (!browser) {
  console.error('未找到 Edge/Chrome，跳过浏览器验收');
  process.exit(0);
}

console.log('\n=== 地产风云 · 网页移植阶段 0 · 真实浏览器验收 ===\n');
console.log('浏览器: ' + browser);

fs.mkdirSync(OUT_DIR, { recursive: true });
const profile = path.join(WEB_ROOT, '.out', 'edge-profile');

const server = spawn(process.execPath, [path.join(WEB_ROOT, 'serve.mjs')], {
  cwd: WEB_ROOT,
  env: { ...process.env, PORT: String(PORT) },
  stdio: ['ignore', 'ignore', 'pipe'],
});

let ok = 0;
let bad = 0;

try {
  await waitForServer();
  console.log(`服务器: ${BASE}\n`);

  for (const screen of screens) {
    const file = path.join(OUT_DIR, `${screen}.png`);
    if (fs.existsSync(file)) fs.unlinkSync(file);
    const url = `${BASE}/?autostart=1&nosw=1&screen=${encodeURIComponent(screen)}`;
    await runBrowser(browser, [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--hide-scrollbars',
      '--no-first-run',
      '--disable-extensions',
      `--user-data-dir=${profile}`,
      '--window-size=430,900',
      '--virtual-time-budget=25000',
      `--screenshot=${file}`,
      url,
    ]);
    const size = fs.existsSync(file) ? fs.statSync(file).size : 0;
    const good = size > 8000;
    if (good) ok++;
    else bad++;
    console.log(`  ${good ? '\x1b[32m✔\x1b[0m' : '\x1b[31m✘\x1b[0m'} ${screen.padEnd(22)} ${(size / 1024).toFixed(1)} KB`);
  }
} catch (e) {
  console.error('验收异常: ' + e.message);
  bad++;
} finally {
  server.kill();
}

console.log(`\n截图目录: ${OUT_DIR}`);
console.log(`=== 结果：成功 ${ok} 屏，疑似空白 ${bad} 屏 ===\n`);
