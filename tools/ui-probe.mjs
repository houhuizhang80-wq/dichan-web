// ============================================================================
// tools/ui-probe.mjs —— 打印各屏幕的可点击文案，用于编排全链路点击脚本
// 用法：node tools/ui-probe.mjs [屏幕名...]
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { WEB_ROOT, buildModuleMap, loadSources } from './modules.mjs';
import { createFakeDOM } from './fakedom.mjs';
import { bootGame } from '../js/host.js';

const require = createRequire(import.meta.url);
const { LuaFactory } = require('wasmoon');

const args = process.argv.slice(2);
const monthsArg = args.find((a) => a.startsWith('--months='));
const months = monthsArg ? Number(monthsArg.split('=')[1]) : 0;
const clicksArg = args.filter((a) => a.startsWith('--click=')).map((a) => a.split('=')[1]);
const screens = args.filter((a) => !a.startsWith('--')).length
  ? args.filter((a) => !a.startsWith('--'))
  : ['city', 'invest', 'auction', 'project', 'sales', 'asset', 'capital'];

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

app.lua.doStringSync(`
  local GD = require("GameData")
  GD.InitCompany("探针地产", "private", "balanced", 2000, GD.cities[1].name)
  GD.paused = true
  return true
`);

if (months > 0) {
  app.lua.doStringSync(`
    local GD = require("GameData")
    GD.paused = false
    local target = GD.totalMonths + ${months}
    local guard = 0
    while GD.totalMonths < target and guard < 4000 do
      local r = GD.DailyTick()
      guard = guard + 1
      if r == "gameover" then break end
    end
    GD.paused = true
    return true
  `);
  const st = app.lua.global.get('__webStats')();
  console.log(`（已推进 ${months} 个月 → ${st.year}年${st.month}月）`);
}

for (const screen of screens) {
  app.lua.global.get('__webNavigate')(screen);
  for (const text of clicksArg) {
    const el = dom.findByText(text);
    if (!el) {
      console.log(`  ✘ 找不到可点击文案「${text}」`);
      continue;
    }
    el.dispatch('click');
    console.log(`  ▶ 点击「${text}」`);
  }
  const clickables = dom.clickables();
  const texts = dom.texts();
  console.log(`\n===== ${screen} （${dom.count()} 节点，${clickables.length} 个可点击）=====`);
  console.log('可点击文案:');
  for (const el of clickables) {
    const t = (el._text || '').replace(/\s+/g, ' ').trim();
    const inner = (el.children || []).map((c) => c.textContent).join('/');
    console.log(`  · ${JSON.stringify(t || inner).slice(0, 70)}`);
  }
  console.log('页面文本（前 40 条）:');
  console.log('  ' + texts.slice(0, 40).map((t) => t.replace(/\s+/g, ' ').slice(0, 40)).join(' | '));
}

fs.writeFileSync(path.join(WEB_ROOT, '.out', 'ui-probe.txt'),
  screens.map((s) => s).join(','));
console.log('\n（完整输出见上）');
