// ============================================================================
// tools/snapshot.mjs —— 无浏览器快照：把 22 个屏幕渲染成静态 HTML，供人工审阅
//   .out/screens.html  每个屏幕一个 430×900 手机框（离线打开即可看布局映射效果）
//   .out/screens.json  每屏节点数 / 文本 / 报错
// 用法：node tools/snapshot.mjs
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { WEB_ROOT, buildModuleMap, loadSources } from './modules.mjs';
import { createFakeDOM, serialize } from './fakedom.mjs';
import { bootGame } from '../js/host.js';

const require = createRequire(import.meta.url);
const { LuaFactory } = require('wasmoon');

const OUT_DIR = path.join(WEB_ROOT, '.out');
const SCREENS = [
  'start', 'changelog', 'companyCreate', 'city', 'dashboard', 'invest', 'auction',
  'project', 'sales', 'asset', 'capital', 'brand', 'personal', 'personalLife',
  'personalFinance', 'governance', 'group', 'international',
  'groupDiversification', 'settings', 'ledger', 'inheritance',
];

const dom = createFakeDOM();
const logs = [];

const app = await bootGame({
  LuaFactory,
  sources: loadSources(buildModuleMap()),
  doc: dom.doc,
  vfsAdapter: {
    read: () => null, write: () => {}, exists: () => false, del: () => {}, mkdir: () => {},
  },
  audio: { play: () => 1, setGain: () => {} },
  log: (m) => logs.push(m),
  initialScreen: 'start',
  raf: null,
});

// ---------------------------------------------------------------------------
// 开一局游戏，让公司相关屏幕能真正渲染出内容
// ---------------------------------------------------------------------------
const startInfo = app.lua.doStringSync(`
  local GD = require("GameData")
  local city = GD.cities[1].name
  -- 个人初始资金固定 3000 万，注册资本不能超过它
  local ok, msg = GD.InitCompany("网页移植测试地产", "private", "balanced", 2000, city)
  GD.paused = true
  return tostring(ok) .. "|" .. tostring(city) .. "|" .. tostring(msg or "")
`);
console.log('开局：' + startInfo);

// ---------------------------------------------------------------------------
// 逐屏渲染
// ---------------------------------------------------------------------------
const results = [];
for (const screen of SCREENS) {
  const before = logs.length;
  const ok = app.lua.global.get('__webNavigate')(screen);
  const texts = dom.texts();
  const errIdx = texts.findIndex((t) => t.includes('页面加载出错') || t.includes('AppShell加载出错'));
  results.push({
    screen,
    ok,
    nodes: dom.count(),
    html: dom.serialize(),
    error: errIdx >= 0 ? (texts[errIdx + 1] || '').slice(0, 400) : null,
    logs: logs.slice(before),
    preview: texts.slice(0, 6),
  });
  const flag = errIdx >= 0 ? '✘' : '✔';
  console.log(
    `${flag} ${screen.padEnd(22)} ${String(dom.count()).padStart(5)} 节点  ` +
      (errIdx >= 0 ? 'ERROR: ' + results.at(-1).error : texts.slice(0, 3).join(' | ').slice(0, 60)),
  );
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------
fs.mkdirSync(OUT_DIR, { recursive: true });

const css = fs.readFileSync(path.join(WEB_ROOT, 'css', 'app.css'), 'utf8');
const frames = results
  .map(
    (r) => `
<section class="shot">
  <h2>${r.screen} <small>${r.nodes} 节点${r.error ? ' · 构建报错' : ''}</small></h2>
  ${r.error ? `<pre class="err">${r.error.replace(/</g, '&lt;')}</pre>` : ''}
  <div class="phone"><div class="app">${r.html}</div></div>
</section>`,
  )
  .join('\n');

fs.writeFileSync(
  path.join(OUT_DIR, 'screens.html'),
  `<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>地产风云 · 网页移植阶段0 屏幕快照</title>
<style>
${css}
body { overflow: auto; background:#202b36; padding: 24px; }
#stage, #app { display: none; }
.grid { display:flex; flex-wrap:wrap; gap:28px; align-items:flex-start; justify-content:center; }
.shot h2 { color:#eef2f6; font-size:15px; margin-bottom:8px; font-weight:600; }
.shot h2 small { color:#8fa3b5; font-weight:400; }
.phone { width:430px; height:900px; overflow:hidden; background:#eef2f6;
         border:1px solid rgba(255,255,255,.12); box-shadow:0 18px 60px rgba(0,0,0,.45); }
.phone .app { width:100%; height:100%; overflow:hidden; }
.err { color:#ff9d9d; background:#2a1c1c; padding:8px; font-size:12px; margin-bottom:8px;
       white-space:pre-wrap; max-width:430px; }
</style></head>
<body>
<h1 style="color:#eef2f6;font-size:18px;margin-bottom:16px">
  地产风云 · 网页移植阶段 0 · 屏幕快照（共 ${results.length} 屏）
</h1>
<div class="grid">
${frames}
</div>
</body></html>`,
);

fs.writeFileSync(
  path.join(OUT_DIR, 'screens.json'),
  JSON.stringify(
    results.map(({ html, ...rest }) => rest),
    null,
    2,
  ),
);

const bad = results.filter((r) => r.error);
console.log(`\n快照已写入：${path.join(OUT_DIR, 'screens.html')}`);
console.log(`节点统计：${path.join(OUT_DIR, 'screens.json')}`);
console.log(`成功 ${results.length - bad.length} 屏，报错 ${bad.length} 屏`);
if (bad.length) {
  console.log('\n报错明细：');
  bad.forEach((b) => console.log(`  ${b.screen}: ${b.error}`));
}
const errLogs = logs.filter((l) => l.includes('出错') || l.includes('失败'));
if (errLogs.length) {
  console.log('\nLua 侧报错日志：');
  errLogs.slice(0, 20).forEach((l) => console.log('  ' + l));
}
