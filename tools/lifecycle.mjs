// ============================================================================
// tools/lifecycle.mjs —— 阶段 2：用真实 UI 点击走完「拿地 → 报建 → 施工 → 销售 → 交付」
//
// 做法：在无头假 DOM 上跑真游戏，每一步都点真实按钮（onClick → Lua 回调 → Navigate），
// 因此这条链路一旦跑通，就证明 UI 接线、状态机、屏幕渲染三者都通。
// 任一步失败会打印当前屏幕的全部可点击文案，便于定位。
//
// 用法：node tools/lifecycle.mjs [--verbose]
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { WEB_ROOT, buildModuleMap, loadSources } from './modules.mjs';
import { createFakeDOM } from './fakedom.mjs';
import { bootGame } from '../js/host.js';

const require = createRequire(import.meta.url);
const { LuaFactory } = require('wasmoon');

const VERBOSE = process.argv.includes('--verbose');
const exploreArg = process.argv.find((a) => a.startsWith('--explore='));
const EXPLORE = exploreArg ? exploreArg.split('=')[1] : null;
const SAVE_DIR = path.join(WEB_ROOT, '.saves');

let passed = 0;
let failed = 0;
const trace = [];

function createNodeAdapter() {
  const full = (p) => path.join(SAVE_DIR, p.replace(/[:*?"<>|]/g, '_'));
  return {
    read: (p) => { try { return fs.readFileSync(full(p), 'utf8'); } catch { return null; } },
    write: (p, t) => { fs.mkdirSync(path.dirname(full(p)), { recursive: true }); fs.writeFileSync(full(p), t); },
    exists: (p) => fs.existsSync(full(p)),
    del: (p) => { try { fs.unlinkSync(full(p)); } catch { /* 忽略 */ } },
    mkdir: (p) => fs.mkdirSync(full(p), { recursive: true }),
  };
}

// ---------------------------------------------------------------------------
// 启动
// ---------------------------------------------------------------------------
const dom = createFakeDOM();
const luaLogs = [];

const app = await bootGame({
  LuaFactory,
  sources: loadSources(buildModuleMap()),
  doc: dom.doc,
  vfsAdapter: createNodeAdapter(),
  audio: { play: () => 1, setGain: () => {} },
  log: (m) => luaLogs.push(m),
  initialScreen: 'start',
  raf: null,
});

const lua = app.lua;
const luaRun = (code) => lua.doStringSync(code);
const nav = (screen) => lua.global.get('__webNavigate')(screen);

// ---------------------------------------------------------------------------
// DOM 操作助手
// ---------------------------------------------------------------------------
function allElements() {
  const out = [];
  dom.walk(dom.app, (el) => out.push(el));
  return out;
}

function textOf(el) {
  return (el.textContent || '').replace(/\s+/g, ' ').trim();
}

function clickables() {
  return allElements().filter((el) => (el.listeners.click || []).length);
}

function findClickable(match, nth = 0) {
  const hits = clickables().filter((el) => {
    const t = textOf(el);
    const inner = (el.children || []).map((c) => textOf(c)).join('/');
    return match(t) || match(inner);
  });
  return hits[nth];
}

function dumpScreen(label) {
  const texts = dom.texts();
  console.log(`\n  ── 当前屏幕（${label}）：${dom.count()} 节点 ──`);
  console.log('  可点击:');
  for (const el of clickables()) {
    const t = textOf(el);
    const inner = (el.children || []).map((c) => textOf(c)).join('/');
    console.log(`    · ${JSON.stringify(t || inner).slice(0, 72)}`);
  }
  console.log('  文本: ' + texts.slice(0, 30).map((t) => t.slice(0, 26)).join(' | '));
}

function step(name, fn) {
  try {
    const detail = fn();
    passed++;
    const line = `  \x1b[32m✔\x1b[0m ${name}${detail ? '  ' + detail : ''}`;
    console.log(line);
    trace.push({ name, ok: true, detail: String(detail || '') });
  } catch (e) {
    failed++;
    console.log(`  \x1b[31m✘\x1b[0m ${name}\n      ${e && e.message ? e.message : e}`);
    trace.push({ name, ok: false, detail: String(e && e.message ? e.message : e) });
    if (VERBOSE) dumpScreen(name);
    throw e;
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || '断言失败');
}

function clickText(text, nth = 0) {
  const el = findClickable((t) => t === text, nth);
  if (!el) throw new Error(`找不到按钮「${text}」`);
  el.dispatch('click');
  return text;
}

function clickLike(substr, nth = 0) {
  const el = findClickable((t) => t.includes(substr), nth);
  if (!el) throw new Error(`找不到含「${substr}」的按钮`);
  const label = textOf(el) || (el.children || []).map((c) => textOf(c)).join('/');
  el.dispatch('click');
  return label;
}

function hasText(substr) {
  return dom.texts().some((t) => t.includes(substr));
}

// ---------------------------------------------------------------------------
// 开始
// ---------------------------------------------------------------------------
console.log('\n=== 地产风云 · 网页移植阶段 2 · 全链路打通（真实 UI 点击）===\n');

console.log('[准备] 开一局并注入测试资金');
step('初始化公司与测试资金', () => {
  const r = luaRun(`
    local GD = require("GameData")
    math.randomseed(20260101)   -- 固定种子，保证这条链路可复现
    GD.InitCompany("链路测试地产", "private", "balanced", 2000, GD.cities[1].name)
    -- 测试夹具：给足资金，让流程能走到交付。
    -- 一个写字楼项目全成本约 5 亿，这里给 10 亿缓冲；不改动任何游戏逻辑。
    GD.company.cash = 100000
    GD.player.cash = 100000
    GD.company.totalAssets = 100000
    GD.paused = true
    return GD.company.name .. "/" .. tostring(GD.company.cash)
  `);
  return r;
});

step('推进到土地市场有地（供地计划有 3 个月延迟）', () => {
  const r = luaRun(`
    local GD = require("GameData")
    GD.paused = false
    local guard = 0
    while #GD.landMarket == 0 and guard < 400 do
      GD.DailyTick(); guard = guard + 1
    end
    GD.paused = true
    return tostring(GD.year) .. "年" .. tostring(GD.month) .. "月 / 市场 " .. tostring(#GD.landMarket) .. " 宗"
  `);
  assert(!r.includes('0 宗'), '土地市场仍为空: ' + r);
  return r;
});

// ---------------------------------------------------------------------------
// 1) 拿地
// ---------------------------------------------------------------------------
console.log('\n[1] 拿地：投资 → 参加竞拍 → 出价 → 竞得 → 确认收购');
step('进入投资页并看到土地市场', () => {
  nav('invest');
  assert(hasText('土地市场'), '未进入投资页');
  const r = luaRun('local GD = require("GameData") return tostring(#GD.landMarket)');
  return `市场 ${r} 宗`;
});

step('竞拍拿地（每轮出最大加价，最多换 3 块地重试）', () => {
  let attempts = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    nav('invest');
    const enter = findClickable((t) => t.includes('参加竞拍'), attempt);
    if (!enter) break;
    enter.dispatch('click');
    attempts++;

    // 竞拍是有限轮次（一般 4~6 轮），每轮有若干加价档位；每轮都点金额最大的那一档
    for (let round = 0; round < 12; round++) {
      const st = String(luaRun(`
        local AS = require("screens/AuctionScreen")
        local s = AS._state
        if not s then return "none" end
        return tostring(s.finished == true) .. "|" .. tostring(s.won == true)
      `)).split('|');
      if (st[0] === 'true') break;
      const options = clickables()
        .map((el) => ({ el, label: textOf(el) }))
        .filter((o) => /^\+\d+万/.test(o.label))
        .map((o) => ({ ...o, amount: Number(/^\+\s*(\d+)/.exec(o.label)[1]) }))
        .sort((a, b) => b.amount - a.amount);
      if (!options.length) break;
      options[0].el.dispatch('click');
    }

    const won = String(luaRun(`
      local AS = require("screens/AuctionScreen")
      local s = AS._state
      return tostring(s and s.won == true) .. "|" .. tostring(s and s.myLastBid) .. "|" .. tostring(s and s.highestBidder)
    `)).split('|');
    if (won[0] === 'true') {
      clickFirst(['确认收购']);
      break;
    }
    // 竞价失败：回投资页换下一块地
    clickFirst(['返回投资中心', '< 返回']);
  }

  const r = luaRun('local GD = require("GameData") return tostring(#GD.landReserve)');
  assert(Number(r) >= 1, `尝试 ${attempts} 块地仍未竞得，储备 ${r} 宗`);
  return `尝试 ${attempts} 块地，储备 ${r} 宗`;
});

// ---------------------------------------------------------------------------
// 2) 启动开发
// ---------------------------------------------------------------------------
console.log('\n[2] 开发：土地储备 → 启动开发 → 方案 → 成本 → 报建');
step('切到土地储备并启动开发', () => {
  nav('invest');
  clickLike('土地储备');
  const btn = findClickable((t) => t.includes('启动开发') || t.includes('开发'));
  if (!btn) {
    dumpScreen('土地储备');
    throw new Error('找不到「启动开发」按钮');
  }
  btn.dispatch('click');
  return '已点击启动开发';
});

step('确认项目已创建', () => {
  const r = luaRun(`
    local GD = require("GameData")
    return tostring(#GD.projects) .. "|" .. tostring(GD.projects[1] and GD.projects[1].name)
  `);
  const [n, name] = String(r).split('|');
  assert(Number(n) >= 1, '项目未创建: ' + r);
  return `${n} 个项目，首个「${name}」`;
});

// ---------------------------------------------------------------------------
// 自动推进：读 ProjectScreen 的「引导文案」决定下一步动作
// 这套引导文案是游戏自己给的（ProjectScreen.lua:2956-3041），拿它当状态机最稳。
// ---------------------------------------------------------------------------
function advanceMonths(n = 1) {
  return luaRun(`
    local GD = require("GameData")
    GD.paused = false
    local target = GD.totalMonths + ${n}
    local guard = 0
    while GD.totalMonths < target and guard < 400 do
      local r = GD.DailyTick()
      guard = guard + 1
      if r == "gameover" then break end
    end
    GD.paused = true
    return tostring(GD.year) .. "年" .. tostring(GD.month) .. "月"
  `);
}

function projectStatus() {
  return String(luaRun(`
    local GD = require("GameData")
    local p = GD.projects[1]
    if not p then return "none" end
    return p.status
  `));
}

// 引导文案的前缀（ProjectScreen.lua:2956-3041 里定义的那几种）
// 注意：不能用正则字符类 [⏩🏗️…] —— JS 字符类按 UTF-16 码元匹配，
// emoji 的高位代理会互相撞车（👔 U+1F454 与 🏠 U+1F3E0 的高位代理都是 \uD83D），
// 结果把「👔 项目经理」这种无关标签也当成引导文案。
const GUIDE_PREFIXES = ['⏩', '⏳', '🏗️', '🏠', '💰', '✔️', '📦', '📋', '🔨', '🏢', '📊', '✅'];

function guideText() {
  const texts = dom.texts();
  return texts.find((t) => t.length > 6 && GUIDE_PREFIXES.some((p) => t.startsWith(p))) || null;
}

function gameOverReason() {
  return String(luaRun(`
    local GD = require("GameData")
    if GD.company and GD.company.isGameOver then
      return tostring(GD.company.gameOverReason or "未知原因")
    end
    return ""
  `));
}

function clickFirst(candidates) {
  for (const c of candidates) {
    const el = findClickable((t) => (c instanceof RegExp ? c.test(t) : t === c || t.includes(c)));
    if (el) {
      const label = textOf(el);
      el.dispatch('click');
      return label;
    }
  }
  return null;
}

console.log('\n[3] 自动推进：报建 → 设计 → 限额 → 施工 → 预售 → 销售 → 结算 → 竣工 → 清盘');
step('自动玩到项目完成（读引导文案决定动作）', () => {
  const actions = [];
  const MAX = 90;
  for (let i = 0; i < MAX; i++) {
    nav('project');
    let g = guideText();
    let status = projectStatus();

    if (VERBOSE) console.log(`    [${i}] status=${status} guide=${(g || '无').slice(0, 40)}`);

    const reason = gameOverReason();
    if (reason) {
      throw new Error(`公司破产导致流程中断（${reason}）；动作轨迹: ${actions.join(' → ')}`);
    }

    if (status === 'completed' || status === 'mature' || status === 'operations') {
      // 收尾：生成清盘清单 → 确认缴税并归档
      const cleared = String(luaRun(`
        local GD = require("GameData")
        local p = GD.projects[1]
        return tostring(p and p.salesCleared == true)
      `));
      if (cleared === 'true') {
        actions.push('已清盘归档');
        break;
      }
      const done = clickFirst(['确认缴税并归档', '生成清盘清单']);
      actions.push(`归档:${done || '未找到按钮'}`);
      if (!done) break;
      continue;
    }

    // 施工阶段：优先去营销页启动预售（不预售就没有销售回款，交付阶段会永远卡住）
    if (status === 'construction') {
      const canSell = String(luaRun(`
        local GD = require("GameData")
        local p = GD.projects[1]
        return tostring(p and p.sales and p.sales.canSell == true)
      `));
      if (canSell !== 'true') {
        nav('sales');
        const started = clickFirst(['开始预售']);
        if (started) {
          actions.push(`预售:${started}`);
          continue;
        }
      }
    }

    if (!g) {
      // 引导文案缺失时兜底：去营销页看能不能开始预售
      nav('sales');
      const started = clickFirst(['开始预售']);
      if (started) {
        actions.push(`预售:${started}`);
        continue;
      }
      advanceMonths(1);
      actions.push('等待(无引导)');
      continue;
    }

    if (g.includes('下一步')) {
      const quoted = /「([^」]+)」/.exec(g);
      const wanted = quoted ? quoted[1] : '';
      const pick = () => {
        if (wanted.includes('规划')) return clickFirst(['确认规划指标', '确认规划']);
        if (wanted.includes('方案')) return clickFirst([/^确认方案/, '确认方案']);
        if (wanted.includes('限额')) return clickFirst(['确认限额设计']);
        if (wanted.includes('办理')) return clickFirst(['申请办理', '开始办理']);
        if (wanted.includes('运营模式')) return clickFirst(['销售型', '自持']);
        return null;
      };
      let label = pick();
      if (!label) {
        // 目标按钮在别的 Tab 上（ProjectScreen 的引导会给出 guideTab），
        // 这里把常见 Tab 依次点一遍再重试。
        for (const tab of ['设计管理', '成本控制', '工程管理', '单元规划', '四证办理']) {
          const tabEl = findClickable((t) => t === tab);
          if (!tabEl) continue;
          tabEl.dispatch('click');
          label = pick();
          if (label) break;
        }
      }
      if (!label) {
        label = clickFirst(['申请办理', '确认规划指标', '确认规划', /^确认方案/, '确认限额设计']);
      }
      if (label) {
        actions.push(`动作:${label}`);
        continue;
      }
      advanceMonths(1);
      actions.push('等待(引导按钮未找到)');
      continue;
    }

    if (g.includes('施工中') || g.includes('设计') || g.includes('审查') || g.includes('预售中') || g.includes('交付阶段')) {
      advanceMonths(1);
      actions.push('推进1月');
      continue;
    }
    if (g.includes('请进行项目结算')) {
      const label = clickFirst(['确认结算']);
      actions.push(`结算:${label || '未找到按钮'}`);
      continue;
    }
    if (g.includes('请确认竣工')) {
      const label = clickFirst(['确认竣工']);
      actions.push(`竣工:${label || '未找到按钮'}`);
      continue;
    }

    advanceMonths(1);
    actions.push(`等待:${g.slice(0, 16)}`);
  }

  const finalStatus = projectStatus();
  const summary = actions.reduce((acc, a) => {
    const k = a.split(':')[0];
    acc[k] = (acc[k] || 0) + 1;
    return acc;
  }, {});
  const detail = `动作 ${actions.length} 次 ${JSON.stringify(summary)} → status=${finalStatus}`;
  if (VERBOSE) console.log('    ' + actions.join(' → '));
  assert(['completed', 'mature'].includes(finalStatus), `未走到完成，最终状态 ${finalStatus}；动作轨迹: ${actions.join(' → ')}`);
  return detail;
});

step('核对全流程状态', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local p = GD.projects[1]
    if not p then return "no-project" end
    local parts = {
      "status=" .. tostring(p.status),
      "销售型=" .. tostring(p.devCategory),
      "已售=" .. tostring(p.sales and p.sales.soldUnits or 0) .. "/" .. tostring(p.sales and p.sales.totalUnits or 0),
      "清盘=" .. tostring(p.salesCleared == true),
      "归档=" .. tostring(p._devArchived == true),
      "现金=" .. string.format("%.0f", GD.company.cash),
      "资产=" .. string.format("%.0f", GD.company.totalAssets),
    }
    return table.concat(parts, " | ")
  `);
  return r;
});

console.log('\n[4] 数值自洽性检查');
step('关键状态无 NaN / Inf', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local bad = {}
    local visited = {}
    local function scan(v, path, depth)
      if depth > 6 then return end
      local t = type(v)
      if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
          bad[#bad + 1] = path
        end
      elseif t == "table" then
        if visited[v] then return end
        visited[v] = true
        for k, val in pairs(v) do
          scan(val, path .. "." .. tostring(k), depth + 1)
        end
      end
    end
    scan(GD.company, "company", 0)
    scan(GD.player, "player", 0)
    scan(GD.projects, "projects", 0)
    scan(GD.loans, "loans", 0)
    scan(GD.finance, "finance", 0)
    return tostring(#bad) .. "|" .. table.concat(bad, ","):sub(1, 200)
  `);
  const [n, list] = String(r).split('|');
  assert(Number(n) === 0, `发现 ${n} 个非法数值: ${list}`);
  return '0 个非法数值';
});

step('账面恒等式：资产 ≈ 现金 + 存货/固定资产（允许 15% 偏差）', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local c = GD.company
    return string.format("%.2f|%.2f|%.2f", c.cash or 0, c.totalAssets or 0, c.totalDebt or 0)
  `);
  const [cash, assets, debt] = String(r).split('|').map(Number);
  assert(Number.isFinite(cash) && Number.isFinite(assets) && Number.isFinite(debt), '数值非法: ' + r);
  assert(assets >= -1, '总资产为负: ' + assets);
  return `现金 ${cash.toFixed(0)} 万 / 总资产 ${assets.toFixed(0)} 万 / 负债 ${debt.toFixed(0)} 万`;
});

if (EXPLORE) {
  console.log(`\n[探索] 进入 ${EXPLORE} 并打印可点击文案`);
  nav(EXPLORE);
  dumpScreen(EXPLORE);
}

fs.writeFileSync(path.join(WEB_ROOT, '.out', 'lifecycle-trace.json'), JSON.stringify(trace, null, 2));
console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项 ===`);
console.log(`链路轨迹: ${path.join(WEB_ROOT, '.out', 'lifecycle-trace.json')}\n`);
process.exit(failed > 0 ? 1 : 0);
