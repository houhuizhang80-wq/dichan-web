// ============================================================================
// tools/save-test.mjs —— 阶段 4：存档系统深度验证
//   ① 8 个手动槽位逐个存/读，核对状态一致
//   ② 自动存档 + 退出前存档
//   ③ 存档损坏时的 .bak 回退
//   ④ 云存档在无 clientCloud 时的优雅降级
//   ⑤ 存档体积与关键字段完整性
// 用法：node tools/save-test.mjs
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { WEB_ROOT, buildModuleMap, loadSources } from './modules.mjs';
import { createFakeDOM } from './fakedom.mjs';
import { bootGame } from '../js/host.js';

const require = createRequire(import.meta.url);
const { LuaFactory } = require('wasmoon');

const SAVE_DIR = path.join(WEB_ROOT, '.saves');
const FILE_DIR = path.join(SAVE_DIR, 'saves');

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

// 清掉上一次的存档，保证从干净状态开始
fs.rmSync(FILE_DIR, { recursive: true, force: true });

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
const luaRun = (code) => app.lua.doStringSync(code);

console.log('\n=== 地产风云 · 网页移植阶段 4 · 存档系统验证 ===\n');

console.log('[准备] 开一局并造出有内容的存档');
check('初始化公司 + 拿地 + 立项 + 推进 18 个月', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local DT = require("DevTypes")
    math.randomseed(20260101)
    GD.InitCompany("存档测试地产", "private", "balanced", 2000, GD.cities[1].name)
    GD.company.cash = 120000
    GD.player.cash = 120000
    GD.company.totalAssets = 120000
    GD.paused = false

    local g = 0
    while #GD.landMarket == 0 and g < 400 do GD.DailyTick(); g = g + 1 end
    local land = GD.landMarket[1]
    GD.company.cash = GD.company.cash - (tonumber(land.startPrice) or 0)
    land.price = tonumber(land.startPrice) or 0
    land.status = "sold"
    land.acquiredMonth = GD.totalMonths
    land.ownerType = "player_company"
    land.ownerCompanyId = GD.activeCompanyId
    table.insert(GD.landReserve, land)
    table.remove(GD.landMarket, 1)
    local types = DT.GetTypesForLandUse(land.landUse)
    GD.StartDevelopment(land.id, types[1].id or types[1].key, nil, "basic")

    local target = GD.totalMonths + 18
    local guard = 0
    while GD.totalMonths < target and guard < 1200 do
      local p = GD.projects[1]
      if p then
        if GD.AutoConfirmScheme then pcall(GD.AutoConfirmScheme, p) end
        if GD.AutoConfirmCostCap then pcall(GD.AutoConfirmCostCap, p) end
        if p.sales and p.sales.canPresale and not p.sales.canSell then pcall(GD.StartPresale, p) end
      end
      GD.DailyTick(); guard = guard + 1
    end
    GD.paused = true
    local p = GD.projects[1]
    return string.format("%s | %d年%d月 | 项目=%s(%s) | 现金=%.0f | 事件=%d",
      GD.company.name, GD.year, GD.month, tostring(p and p.name), tostring(p and p.status),
      GD.company.cash, #(GD.events or {}))
  `);
  assert(r.includes('项目='), '前置失败: ' + r);
  return r;
});

console.log('\n[1] 8 个手动槽位');
check('逐个写入 8 个槽位', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local okCount, failMsg = 0, nil
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
      local ok, err = GD.SaveToSlot(i)
      if ok then okCount = okCount + 1 else failMsg = tostring(err) end
    end
    return tostring(okCount) .. "/" .. tostring(GD.MANUAL_SAVE_SLOT_COUNT) .. "|" .. tostring(failMsg or "")
  `);
  assert(String(r).startsWith('8/8'), '存档失败: ' + r);
  const files = fs.readdirSync(FILE_DIR).filter((f) => /^slot_\d+\.json$/.test(f));
  assert(files.length === 8, `磁盘上只有 ${files.length} 个槽位文件`);
  const sizes = files.map((f) => fs.statSync(path.join(FILE_DIR, f)).size);
  return `8 个文件，${(Math.min(...sizes) / 1024).toFixed(1)}~${(Math.max(...sizes) / 1024).toFixed(1)} KB`;
});

check('GetSlotInfo 能读出摘要', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local okCount, sample = 0, ""
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
      local info = GD.GetSlotInfo(i)
      if info then
        okCount = okCount + 1
        if i == 1 then sample = info.name .. " / " .. info.date .. " / " .. string.format("%.0f", info.cash) end
      end
    end
    return tostring(okCount) .. "|" .. sample
  `);
  const [n, sample] = String(r).split('|');
  assert(Number(n) === 8, `只有 ${n} 个槽位可读`);
  return `8 个可读，示例「${sample}」`;
});

check('GetLatestSlotInfoWithAuto 能选出最新存档', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local info = GD.GetLatestSlotInfoWithAuto()
    if not info then return "nil" end
    return tostring(info.slot) .. "|" .. tostring(info.name) .. "|" .. tostring(info.date)
  `);
  assert(r !== 'nil', '没有找到最新存档');
  return r;
});

console.log('\n[2] 状态一致性：存档 → 改变状态 → 读档 → 比对');
check('读档后关键状态完全还原', () => {
  const r = luaRun(`
    local GD = require("GameData")
    -- 先记录原始状态
    local function snapshot()
      local parts = {
        GD.company.name, tostring(GD.company.cash), tostring(GD.company.totalAssets),
        tostring(GD.company.totalDebt), tostring(GD.year), tostring(GD.month),
        tostring(#(GD.projects or {})), tostring(#(GD.landReserve or {})),
        -- 注意：v5 存档只保留最近 20 条事件（buildSaveData 里 math.min(20, #GD.events)），
        -- 所以比对时也要按 20 截断，否则会被当成"不一致"
        tostring(math.min(#(GD.events or {}), 20)), tostring(GD.totalMonths),
      }
      local p = GD.projects[1]
      if p then
        parts[#parts + 1] = tostring(p.name)
        parts[#parts + 1] = tostring(p.status)
        parts[#parts + 1] = string.format("%.4f", p.construction and p.construction.progress or 0)
      end
      return table.concat(parts, "|")
    end

    GD.SaveToSlot(1)
    local before = snapshot()

    -- 故意破坏当前状态
    GD.company.cash = -999999
    GD.company.name = "被改坏的公司"
    GD.year = 2099
    GD.month = 12
    GD.totalMonths = GD.totalMonths + 500
    if GD.projects[1] then GD.projects[1].status = "broken" end

    local ok, err = GD.LoadFromSlot(1)
    if not ok then return "load-failed:" .. tostring(err) end
    local after = snapshot()
    if before ~= after then
      return "MISMATCH\\nbefore=" .. before .. "\\nafter =" .. after
    end
    return "ok|" .. after:sub(1, 120)
  `);
  assert(String(r).startsWith('ok|'), '状态不一致: ' + r);
  return String(r).slice(3);
});

console.log('\n[3] 自动存档');
check('AutoSave + GetAutoSaveInfo + LoadAutoSave', () => {
  const r = luaRun(`
    local GD = require("GameData")
    GD.company.cash = 88888
    GD.AutoSave()
    local info = GD.GetAutoSaveInfo()
    if not info then return "no-autosave-info" end
    GD.company.cash = 1
    local ok, err = GD.LoadAutoSave()
    if not ok then return "load-failed:" .. tostring(err) end
    return "ok|" .. string.format("%.0f", GD.company.cash) .. "|" .. tostring(info.date or "")
  `);
  assert(String(r).startsWith('ok|88888'), '自动存档往返失败: ' + r);
  const files = fs.readdirSync(FILE_DIR).filter((f) => f.includes('auto'));
  return `${String(r).slice(3)}（auto 文件: ${files.join(',') || '无'}）`;
});

console.log('\n[4] 损坏恢复');
check('主存档被破坏时回退到 .bak', () => {
  const slotPath = path.join(FILE_DIR, 'slot_3.json');
  const bakPath = `${slotPath}.bak`;

  // 先存一次（状态 A，现金 123456），改掉现金后再存一次（状态 B，现金 654321）。
  // 覆盖时会把状态 A 备份成 .bak；随后破坏主文件，读档应该拿回状态 A。
  const r0 = luaRun(`
    local GD = require("GameData")
    GD.company.cash = 123456
    local okA = select(1, GD.SaveToSlot(3))
    GD.company.cash = 654321
    local okB = select(1, GD.SaveToSlot(3))
    return tostring(okA) .. "|" .. tostring(okB)
  `);
  assert(String(r0) === 'true|true', '两次存档失败: ' + r0);
  assert(fs.existsSync(slotPath), 'slot_3.json 不存在');
  assert(fs.existsSync(bakPath), 'slot_3.json.bak 不存在（覆盖时未生成备份）');

  // 主文件写坏，读档必须回退到 .bak（也就是现金应为 123456，而不是 654321）
  fs.writeFileSync(slotPath, '{ 这不是合法 JSON');
  const r = luaRun(`
    local GD = require("GameData")
    local ok, err = GD.LoadFromSlot(3)
    return tostring(ok) .. "|" .. tostring(err or "") .. "|" .. string.format("%.0f", GD.company.cash or -1)
  `);
  assert(String(r).startsWith('true|'), '未能从备份恢复: ' + r);
  assert(String(r).endsWith('|123456'), `恢复的是错误的内容（期望备份里的 123456）: ${r}`);
  return `${String(r)}（主文件损坏 → 自动回退 .bak）`;
});

check('存档文件损坏且无备份时优雅失败（不崩溃）', () => {
  const slotPath = path.join(FILE_DIR, 'slot_4.json');
  const bakPath = `${slotPath}.bak`;
  const good = fs.readFileSync(slotPath, 'utf8');
  const goodBak = fs.existsSync(bakPath) ? fs.readFileSync(bakPath, 'utf8') : null;
  fs.writeFileSync(slotPath, 'garbage');
  if (goodBak !== null) fs.rmSync(bakPath);

  const r = luaRun(`
    local GD = require("GameData")
    local ok, err = GD.LoadFromSlot(4)
    return tostring(ok) .. "|" .. tostring(err or "")
  `);
  assert(String(r).startsWith('false|'), '应该返回 false 而不是抛异常: ' + r);

  fs.writeFileSync(slotPath, good);
  if (goodBak !== null) fs.writeFileSync(bakPath, goodBak);
  return String(r);
});

check('读取不存在的槽位不崩溃', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local ok, err = GD.LoadFromSlot(99)
    local info = GD.GetSlotInfo(99)
    return tostring(ok) .. "|" .. tostring(err or "") .. "|info=" .. tostring(info)
  `);
  assert(String(r).startsWith('false|'), '应返回 false: ' + r);
  assert(String(r).includes('info=nil'), '不存在槽位应返回 nil 摘要: ' + r);
  return String(r).slice(0, 80);
});

console.log('\n[5] 云存档降级');
check('无 clientCloud 时云存档返回明确错误', () => {
  const r = luaRun(`
    local GD = require("GameData")
    local msg = "none"
    local ok = GD.SaveToCloudSlot(1, function(success, reason) msg = tostring(reason or success) end)
    local msg2 = "none"
    local ok2 = GD.GetCloudSlotInfos(function(infos, reason) msg2 = tostring(reason or "ok") end)
    return tostring(ok) .. "|" .. msg .. "|" .. tostring(ok2) .. "|" .. msg2
  `);
  assert(String(r).startsWith('false|'), '应返回 false: ' + r);
  assert(String(r).includes('未连接云存档'), '错误信息应说明平台未连接云存档: ' + r);
  return String(r);
});

console.log('\n[6] 存档内容完整性');
check('存档 JSON 含全部关键字段且可解析', () => {
  const raw = fs.readFileSync(path.join(FILE_DIR, 'slot_1.json'), 'utf8');
  const data = JSON.parse(raw);
  const required = [
    'version', 'savedAt', 'year', 'month', 'day', 'totalMonths', 'gameSpeed', 'gameStarted',
    'company', 'companyPortfolio', 'player', 'economy', 'projects', 'loans', 'finance',
    'landMarket', 'landReserve', 'competitors', 'fixedAssets', 'events',
  ];
  const missing = required.filter((k) => data[k] === undefined);
  assert(missing.length === 0, '缺少字段: ' + missing.join(','));
  assert(data.version === 5, '版本号应为 5，实际 ' + data.version);
  return `version=${data.version}，${Object.keys(data).length} 个顶层字段，${(raw.length / 1024).toFixed(1)} KB`;
});

check('存档体积在 localStorage 单键上限内（5 MB）', () => {
  const sizes = fs.readdirSync(FILE_DIR)
    .filter((f) => f.endsWith('.json'))
    .map((f) => fs.statSync(path.join(FILE_DIR, f)).size);
  const max = Math.max(...sizes);
  assert(max < 5 * 1024 * 1024, `最大存档 ${(max / 1024 / 1024).toFixed(2)} MB 超过 localStorage 单键上限`);
  return `最大 ${(max / 1024).toFixed(1)} KB（上限 5120 KB）`;
});

console.log(`\n=== 结果：通过 ${passed} 项，失败 ${failed} 项 ===`);
console.log(`存档目录: ${FILE_DIR}\n`);
process.exit(failed > 0 ? 1 : 0);
