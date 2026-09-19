// ============================================================================
// tools/sim-baseline.mjs —— 阶段 2：长跑数值回归基线
//
// 做法：固定随机种子，跑 N 个月（默认 10 年），每月记录一组关键指标，
// 同时做「非法数值扫描」与「账面恒等式」两类不变量检查。
// 首次运行写入基线；之后运行逐月比对，任何一位数变化都会指出「第几个月、哪个指标」。
//
// 说明：原引擎是 Lua 5.1 的 RNG，wasmoon 是 Lua 5.4，两者的随机序列本就不同，
// 所以这份基线**不能**用来证明「与原版数值一致」，它的用途是：
//   ① 证明模拟是确定性的（同种子两次跑完全一致）
//   ② 作为回归网——任何改动导致数值漂移都会立刻暴露
//
// 用法：
//   node tools/sim-baseline.mjs             # 比对（无基线则自动创建）
//   node tools/sim-baseline.mjs --update    # 重新生成基线
//   node tools/sim-baseline.mjs --months=240
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
const UPDATE = args.includes('--update');
const monthsArg = args.find((a) => a.startsWith('--months='));
const MONTHS = monthsArg ? Number(monthsArg.split('=')[1]) : 120;
const SEED = 20260101;
const CAPITAL = 80000;

const OUT_DIR = path.join(WEB_ROOT, '.out');
const BASELINE_PATH = path.join(OUT_DIR, 'sim-baseline.json');
const SAVE_DIR = path.join(WEB_ROOT, '.saves');

let passed = 0;
let failed = 0;

function check(name, fn) {
  try {
    const detail = fn();
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
// 模拟脚本（在 Lua 里跑完整 N 个月，逐月采样）
//
// 为了拿到有意义的轨迹，脚本里带一个「自动 CEO」：
//   · 每 6 个月拿一块最便宜的地并立项
//   · 每月用游戏自己的接口推进设计/预售/结算/竣工/清盘
// 其中「拿地落地」这一步是测试夹具（等价于 AuctionScreen.FinishAuction 里
// 玩家竞得后的那几行状态写入），其余全部走真实游戏接口。
// ---------------------------------------------------------------------------
const SIM_SCRIPT = `
local GD = require("GameData")
local DT = require("DevTypes")

math.randomseed(${SEED})
GD.InitCompany("回归测试地产", "private", "balanced", 2000, GD.cities[1].name)
GD.company.cash = ${CAPITAL}
GD.player.cash = ${CAPITAL}
GD.company.totalAssets = ${CAPITAL}
GD.paused = false

local N = ${MONTHS}
local traj = {}
local badValues = {}
local visited = {}
local stats = { acquired = 0, started = 0, presold = 0, settled = 0, completed = 0, cleared = 0 }

local function scan(v, path, depth)
  if depth > 5 then return end
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      badValues[#badValues + 1] = path .. "=" .. tostring(v)
    end
  elseif t == "table" then
    if visited[v] then return end
    visited[v] = true
    for k, val in pairs(v) do
      scan(val, path .. "." .. tostring(k), depth + 1)
    end
  end
end

local function sumProject(field)
  local total = 0
  for _, p in ipairs(GD.projects or {}) do
    if field == "progress" then
      total = total + ((p.construction and p.construction.progress) or 0)
    elseif field == "sold" then
      total = total + ((p.sales and p.sales.soldUnits) or 0)
    end
  end
  return total
end

--- 测试夹具：以起拍价拿下一块地（等价于 AuctionScreen.FinishAuction 的落地部分）
local function testAcquire(land, idx)
  local price = tonumber(land.startPrice) or 0
  if price <= 0 or (GD.company.cash or 0) < price then return false end
  GD.company.cash = GD.company.cash - price
  land.price = price
  land.status = "sold"
  land.acquiredMonth = GD.totalMonths
  land.ownerType = "player_company"
  land.ownerCompanyId = GD.activeCompanyId
  table.insert(GD.landReserve, land)
  table.remove(GD.landMarket, idx)
  stats.acquired = stats.acquired + 1
  return true
end

local function autoCEO()
  -- 1) 立项：每 6 个月，现金充裕且在建不超过 3 个时拿地开工
  if GD.totalMonths % 6 == 0 and #(GD.projects or {}) < 3 and (GD.company.cash or 0) > 25000 then
    local best, bi
    for i, l in ipairs(GD.landMarket or {}) do
      if not best or (tonumber(l.startPrice) or math.huge) < (tonumber(best.startPrice) or math.huge) then
        best, bi = l, i
      end
    end
    if best and (tonumber(best.startPrice) or 0) < (GD.company.cash or 0) * 0.35 then
      if testAcquire(best, bi) then
        local types = DT.GetTypesForLandUse(best.landUse)
        local devTypeId = types and types[1] and (types[1].id or types[1].key)
        if devTypeId then
          local ok = pcall(GD.StartDevelopment, best.id, devTypeId, nil, "basic")
          if ok then stats.started = stats.started + 1 end
        end
      end
    end
  end

  -- 2) 每月推进每个项目
  for _, p in ipairs(GD.projects or {}) do
    if GD.AutoConfirmScheme then pcall(GD.AutoConfirmScheme, p) end
    if GD.AutoConfirmCostCap then pcall(GD.AutoConfirmCostCap, p) end
    if p.sales and p.sales.canPresale and not p.sales.canSell then
      local ok = pcall(GD.StartPresale, p)
      if ok then stats.presold = stats.presold + 1 end
    end
    if p.status == "pending_settlement" then
      local ok = pcall(GD.SettleProject, p)
      if ok then stats.settled = stats.settled + 1 end
    end
    if p.status == "pending_completion" then
      local ok = pcall(GD.ConfirmCompletion, p)
      if ok then stats.completed = stats.completed + 1 end
    end
    if (p.status == "completed" or p.status == "mature") and not p.salesCleared then
      pcall(GD.ManualClearance, p)
      pcall(GD.ConfirmClearanceTax, p)
      stats.cleared = stats.cleared + 1
    end
  end
end

local startMonth = GD.totalMonths
local guard = 0
while GD.totalMonths - startMonth < N and guard < N * 40 do
  autoCEO()
  local r = GD.DailyTick()
  guard = guard + 1
  if r == "gameover" then break end

  local idx = GD.totalMonths - startMonth
  if traj[idx] == nil then
    traj[idx] = {
      m = GD.totalMonths,
      y = GD.year, mo = GD.month,
      cash = GD.company.cash,
      assets = GD.company.totalAssets,
      debt = GD.company.totalDebt,
      pcash = GD.player.cash,
      credit = GD.company.creditScore,
      qual = GD.company.qualification,
      projects = #(GD.projects or {}),
      market = #(GD.landMarket or {}),
      reserve = #(GD.landReserve or {}),
      loans = #(GD.loans or {}),
      events = #(GD.events or {}),
      priceIndex = GD.economy and GD.economy.priceIndex or 0,
      progress = sumProject("progress"),
      sold = sumProject("sold"),
    }
  end
end

scan(GD.company, "company", 0)
scan(GD.player, "player", 0)
scan(GD.projects, "projects", 0)

local c = GD.company
return {
  months = GD.totalMonths - startMonth,
  gameOver = c.isGameOver == true,
  gameOverReason = tostring(c.gameOverReason or ""),
  final = {
    cash = c.cash, assets = c.totalAssets, debt = c.totalDebt,
    pcash = GD.player.cash, credit = c.creditScore, qual = c.qualification,
    projects = #(GD.projects or {}), events = #(GD.events or {}),
  },
  stats = stats,
  badCount = #badValues,
  badList = table.concat(badValues, ","):sub(1, 300),
  traj = traj,
}
`;

// ---------------------------------------------------------------------------
const dom = createFakeDOM();
const logs = [];

const app = await bootGame({
  LuaFactory,
  sources: loadSources(buildModuleMap()),
  doc: dom.doc,
  vfsAdapter: createNodeAdapter(),
  audio: { play: () => 1, setGain: () => {} },
  log: (m) => logs.push(m),
  initialScreen: 'start',
  raf: null,
});

console.log(`\n=== 地产风云 · 网页移植阶段 2 · 长跑数值回归（${MONTHS} 个月 / 种子 ${SEED}）===\n`);

const t0 = Date.now();
const result = app.lua.doStringSync(SIM_SCRIPT);
const elapsed = Date.now() - t0;

const traj = [];
for (let i = 1; i <= result.months; i++) {
  if (result.traj[i]) traj.push(result.traj[i]);
}

console.log(`[运行] ${result.months} 个月，耗时 ${(elapsed / 1000).toFixed(1)}s，`
  + `${traj.length} 个采样点，${(result.months / (elapsed / 1000)).toFixed(1)} 月/秒\n`);

console.log('[1] 不变量检查');
check('模拟过程中没有 NaN / Inf', () => {
  assert(result.badCount === 0, `发现 ${result.badCount} 个非法数值: ${result.badList}`);
  return '0 个非法数值';
});

check('公司未破产', () => {
  assert(!result.gameOver, '游戏结束: ' + result.gameOverReason);
  return '存活';
});

check('模拟确实在运转（拿地/立项/预售/交付都有发生）', () => {
  const s = result.stats || {};
  assert(s.acquired > 0, '一次拿地都没发生');
  assert(s.started > 0, '一个项目都没立项');
  assert(s.presold > 0, '一次预售都没开始');
  assert(s.completed > 0, '一个项目都没竣工');
  return `拿地 ${s.acquired} / 立项 ${s.started} / 预售 ${s.presold} / 结算 ${s.settled} / 竣工 ${s.completed} / 清盘 ${s.cleared}`;
});

check('现金没有失控（始终不超过总资产的 2 倍 + 1 亿）', () => {
  let bad = null;
  for (const t of traj) {
    const bound = Math.abs(t.assets) * 2 + 10000;
    if (Math.abs(t.cash) > bound) {
      bad = `第 ${t.m} 月现金 ${Math.round(t.cash)} 超出上限 ${Math.round(bound)}`;
      break;
    }
  }
  // 注意：assert 的第二个参数会被立即求值，所以这里先算好字符串再传
  assert(!bad, bad || '');
  return '通过';
});

check('总资产单月跌幅不超过 50%（不存在无因腰斩）', () => {
  let worst = 0;
  let worstMonth = 0;
  for (let i = 1; i < traj.length; i++) {
    const prev = traj[i - 1].assets;
    if (prev <= 0) continue;
    const drop = (prev - traj[i].assets) / prev;
    if (drop > worst) { worst = drop; worstMonth = traj[i].m; }
  }
  assert(worst <= 0.5, `第 ${worstMonth} 月总资产跌了 ${(worst * 100).toFixed(1)}%`);
  return `最大单月跌幅 ${(worst * 100).toFixed(1)}%（第 ${worstMonth} 月）`;
});

check('所有月份的关键数值都是有限数', () => {
  for (const t of traj) {
    for (const k of ['cash', 'assets', 'debt', 'pcash', 'credit', 'priceIndex', 'progress', 'sold']) {
      assert(Number.isFinite(t[k]), `第 ${t.m} 月 ${k}=${t[k]}`);
    }
  }
  return `${traj.length} × 8 个数值`;
});

check('资产不为负、负债不为负', () => {
  for (const t of traj) {
    assert(t.assets >= -1e-6, `第 ${t.m} 月总资产为负: ${t.assets}`);
    assert(t.debt >= -1e-6, `第 ${t.m} 月负债为负: ${t.debt}`);
  }
  return '通过';
});

// ---------------------------------------------------------------------------
console.log('\n[2] 与基线比对');
const current = {
  seed: SEED,
  months: MONTHS,
  capital: CAPITAL,
  engine: 'wasmoon/Lua5.4',
  final: result.final,
  stats: result.stats,
  traj,
};

if (!fs.existsSync(BASELINE_PATH)) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(BASELINE_PATH, JSON.stringify(current, null, 2));
  console.log(`  · 首次运行，已创建基线: ${BASELINE_PATH}`);
} else if (UPDATE) {
  fs.writeFileSync(BASELINE_PATH, JSON.stringify(current, null, 2));
  console.log(`  · 已按 --update 重写基线: ${BASELINE_PATH}`);
} else {
  const base = JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8'));
  check(`逐月比对 ${base.traj.length} 个采样点`, () => {
    const n = Math.min(base.traj.length, traj.length);
    assert(base.traj.length === traj.length,
      `采样点数不一致: 基线 ${base.traj.length} vs 本次 ${traj.length}`);
    for (let i = 0; i < n; i++) {
      const b = base.traj[i];
      const c = traj[i];
      for (const k of Object.keys(b)) {
        const bv = b[k];
        const cv = c[k];
        if (typeof bv === 'number' && typeof cv === 'number') {
          if (Math.abs(bv - cv) > Math.max(1e-6, Math.abs(bv) * 1e-9)) {
            throw new Error(`第 ${b.m} 月（第 ${i + 1} 个采样点）指标 ${k} 漂移: ${bv} → ${cv}`);
          }
        } else if (bv !== cv) {
          throw new Error(`第 ${b.m} 月指标 ${k} 变化: ${bv} → ${cv}`);
        }
      }
    }
    return '完全一致（模拟确定性成立）';
  });
  check('最终状态一致', () => {
    for (const k of Object.keys(base.final)) {
      const bv = base.final[k];
      const cv = current.final[k];
      if (typeof bv === 'number') {
        assert(Math.abs(bv - cv) < 1e-6, `final.${k}: ${bv} → ${cv}`);
      } else {
        assert(bv === cv, `final.${k}: ${bv} → ${cv}`);
      }
    }
    return Object.entries(base.final).map(([k, v]) => `${k}=${typeof v === 'number' ? Math.round(v) : v}`).join(' ');
  });
}

// ---------------------------------------------------------------------------
console.log('\n[3] 长跑业务概览');
const first = traj[0];
const last = traj[traj.length - 1];
console.log(`  起始: ${first.y}年${String(first.mo).padStart(2, '0')}月  现金 ${Math.round(first.cash)} 万  资产 ${Math.round(first.assets)} 万`);
console.log(`  结束: ${last.y}年${String(last.mo).padStart(2, '0')}月  现金 ${Math.round(last.cash)} 万  资产 ${Math.round(last.assets)} 万  负债 ${Math.round(last.debt)} 万`);
const cashMin = Math.min(...traj.map((t) => t.cash));
const cashMax = Math.max(...traj.map((t) => t.cash));
console.log(`  现金区间: ${Math.round(cashMin)} ~ ${Math.round(cashMax)} 万`);
console.log(`  项目数: ${last.projects}  土地储备: ${last.reserve}  土地市场: ${last.market}  贷款: ${last.loans}`);
console.log(`  资质等级: ${last.qual}  信用分: ${last.credit}  房价指数: ${last.priceIndex.toFixed(1)}`);
console.log(`  事件数: ${last.events}`);

console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项 ===`);
console.log(`基线文件: ${BASELINE_PATH}\n`);
process.exit(failed > 0 ? 1 : 0);
