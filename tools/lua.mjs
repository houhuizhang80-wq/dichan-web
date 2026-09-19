// ============================================================================
// tools/lua.mjs —— 在真实游戏环境里跑一段 Lua 并打印结果（开发/探测用）
//
// 用法：
//   node tools/lua.mjs "return tostring(#require('DevTypes').GetAllTypes())"
//   node tools/lua.mjs --file=tools/snippets/probe.lua
//   node tools/lua.mjs --start "local GD=require('GameData') GD.InitCompany(...) return 1"
//       --start 会先开一局（默认 10 亿测试资金）再执行主脚本
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
const fileArg = args.find((a) => a.startsWith('--file='));
const withStart = args.includes('--start');
const monthsArg = args.find((a) => a.startsWith('--months='));
const months = monthsArg ? Number(monthsArg.split('=')[1]) : 0;
const code = fileArg
  ? fs.readFileSync(path.resolve(WEB_ROOT, fileArg.split('=')[1]), 'utf8')
  : args.filter((a) => !a.startsWith('--')).join(' ');

if (!code) {
  console.error('用法: node tools/lua.mjs "<lua 代码>" 或 --file=path/to/snippet.lua');
  process.exit(1);
}

const SAVE_DIR = path.join(WEB_ROOT, '.saves');
const dom = createFakeDOM();
const logs = [];

const app = await bootGame({
  LuaFactory,
  sources: loadSources(buildModuleMap()),
  doc: dom.doc,
  vfsAdapter: {
    read: (p) => { try { return fs.readFileSync(path.join(SAVE_DIR, p.replace(/[:*?"<>|]/g, '_')), 'utf8'); } catch { return null; } },
    write: () => {},
    exists: () => false,
    del: () => {},
    mkdir: () => {},
  },
  audio: { play: () => 1, setGain: () => {} },
  log: (m) => logs.push(m),
  initialScreen: 'start',
  raf: null,
});

if (withStart) {
  app.lua.doStringSync(`
    local GD = require("GameData")
    math.randomseed(20260101)
    GD.InitCompany("探测地产", "private", "balanced", 2000, GD.cities[1].name)
    GD.company.cash = 100000
    GD.player.cash = 100000
    GD.company.totalAssets = 100000
    GD.paused = true
    return true
  `);
}

if (months > 0) {
  app.lua.doStringSync(`
    local GD = require("GameData")
    GD.paused = false
    local target = GD.totalMonths + ${months}
    local guard = 0
    while GD.totalMonths < target and guard < 4000 do
      local r = GD.DailyTick(); guard = guard + 1
      if r == "gameover" then break end
    end
    GD.paused = true
    return true
  `);
}

const result = app.lua.doStringSync(code);
if (result !== undefined && result !== null) {
  if (typeof result === 'object') console.log(JSON.stringify(result, null, 2));
  else console.log(result);
}
if (logs.length) {
  console.log('\n--- Lua 日志 ---');
  logs.slice(-20).forEach((l) => console.log('  ' + l));
}
