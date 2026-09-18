// ============================================================================
// tools/systems.mjs —— 阶段 3：长线系统等价验证
//
// 每个场景独立启动一台全新 Lua 虚拟机（避免场景间状态污染），
// 用真实游戏接口推进，断言「状态迁移正确 + 关键数值合理 + 对应屏幕能渲染」。
//
// 用法：node tools/systems.mjs [场景id...] [--verbose]
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
const VERBOSE = args.includes('--verbose');
const only = args.filter((a) => !a.startsWith('--'));
const SAVE_DIR = path.join(WEB_ROOT, '.saves');

const SOURCES = loadSources(buildModuleMap());

// ---------------------------------------------------------------------------
// 通用前置：开一局 + 固定种子 + 注入测试资金
// ---------------------------------------------------------------------------
const BOOTSTRAP = `
local GD = require("GameData")
math.randomseed(20260101)
if not GD.gameStarted then
  GD.InitCompany("长线测试地产", "private", "balanced", 2000, GD.cities[1].name)
end
GD.company.cash = 200000
GD.player.cash = 200000
GD.company.totalAssets = 200000
GD.paused = false
`;

// 拿一块地并立项（测试夹具，等价于 AuctionScreen.FinishAuction 的落地部分）
const ACQUIRE_AND_START = `
local DT = require("DevTypes")
local function acquireAndStart()
  local g = 0
  while #GD.landMarket == 0 and g < 400 do GD.DailyTick(); g = g + 1 end
  local land = GD.landMarket[1]
  local price = tonumber(land.startPrice) or 0
  GD.company.cash = GD.company.cash - price
  land.price = price
  land.status = "sold"
  land.acquiredMonth = GD.totalMonths
  land.ownerType = "player_company"
  land.ownerCompanyId = GD.activeCompanyId
  table.insert(GD.landReserve, land)
  table.remove(GD.landMarket, 1)
  local types = DT.GetTypesForLandUse(land.landUse)
  local devTypeId = types and types[1] and (types[1].id or types[1].key)
  local ok, msg = GD.StartDevelopment(land.id, devTypeId, nil, "basic")
  return GD.projects[#GD.projects], ok, msg
end
`;

// 自动 CEO：推进到指定状态
const AUTO_CEO = `
local GD = require("GameData")
local function autoCEO(stopStatus, maxDays)
  local guard = 0
  while guard < (maxDays or 4000) do
    local p = GD.projects[1]
    if not p then break end
    if p.status == stopStatus then break end
    if GD.AutoConfirmScheme then pcall(GD.AutoConfirmScheme, p) end
    if GD.AutoConfirmCostCap then pcall(GD.AutoConfirmCostCap, p) end
    if p.sales and p.sales.canPresale and not p.sales.canSell then pcall(GD.StartPresale, p) end
    if p.status == "pending_settlement" then pcall(GD.SettleProject, p) end
    if p.status == "pending_completion" then pcall(GD.ConfirmCompletion, p) end
    GD.DailyTick()
    guard = guard + 1
  end
  return GD.projects[1], guard
end
`;

// ---------------------------------------------------------------------------
// 场景定义
// ---------------------------------------------------------------------------
const SCENARIOS = [
  {
    id: 'fixed-asset',
    title: '自持固定资产运营',
    note: '竣工项目留一部分自持 → 转固定资产 → 装修 → 出租 → 物业费/服务升级',
    setup: `${BOOTSTRAP}${ACQUIRE_AND_START}
      local p = acquireAndStart()
      GD.ConfirmPlanning(p)
      local total = p.sales.totalUnits
      local hold = math.max(1, math.floor(total / 3))
      GD.PlanUnits(p, total - hold, hold)
      return "项目=" .. p.name .. " 总套数=" .. total .. " 自持=" .. hold .. " 自持面积=" .. tostring(p.unitPlan.holdArea)
    `,
    steps: [
      {
        desc: '推进到竣工（自动确认设计 + 预售）',
        lua: `${AUTO_CEO}
          local p, days = autoCEO("delivery", 4000)
          return tostring(p and p.status) .. "|" .. tostring(days) .. "|" .. tostring(p and p.sales and p.sales.soldUnits)
        `,
        expect: /^delivery\|/,
      },
      {
        desc: '转为固定资产（自持部分）',
        lua: `
          local GD = require("GameData")
          local p = GD.projects[1]
          local ok, msg = GD.ConvertToFixedAsset(p, 1)
          local fa = GD.fixedAssets and GD.fixedAssets[1]
          return tostring(ok) .. "|" .. tostring(#(GD.fixedAssets or {})) .. "|" ..
                 tostring(fa and fa.holdArea) .. "|" .. tostring(fa and fa.monthlyRent)
        `,
        expect: /^true\|1\|[1-9]/,
      },
      {
        desc: '固定资产装修升级',
        lua: `
          local GD = require("GameData")
          local ok, msg = GD.RenovateFixedAsset(1, 2)
          local fa = GD.fixedAssets[1]
          return tostring(ok) .. "|" .. tostring(fa and fa.renovLevel) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '挂牌出租（企业租户）',
        lua: `
          local GD = require("GameData")
          local ok, msg = GD.ListFixedAssetForRent(1, "enterprise")
          return tostring(ok) .. "|" .. tostring(#(GD.rentalListings or {})) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '推进 12 个月，租金与物业运营产生收入',
        lua: `
          local GD = require("GameData")
          local target = GD.totalMonths + 12
          local g = 0
          while GD.totalMonths < target and g < 800 do GD.DailyTick(); g = g + 1 end
          local fa = GD.fixedAssets[1]
          local sum = GD.GetFixedAssetSummary()
          return string.format("出租率%.0f%% 月租合计%.2f 资产估值%.0f 现金%.0f",
            fa.occupancyRate or 0, (sum and sum.totalMonthlyRent) or 0,
            fa.currentValue or 0, GD.company.cash)
        `,
        expect: /月租合计[1-9]/,
      },
      {
        desc: '物业费与服务等级可调',
        lua: `
          local GD = require("GameData")
          local ok1 = select(1, GD.SetPropertyFeeRate(1, 3.5))
          local ok2 = select(1, GD.UpgradePropertyService(1, 2))
          local ok3 = select(1, GD.SetPropertyStaff(1, 20))
          return tostring(ok1) .. tostring(ok2) .. tostring(ok3)
        `,
        expect: /^true/,
      },
      { desc: '资产运营页渲染', screen: 'asset', expectText: '资产' },
    ],
  },

  {
    id: 'personal-invest',
    title: '个人理财',
    note: '八类投资产品买入 → 月收益 → 赎回；含策略组合与再平衡',
    setup: `${BOOTSTRAP}
      local PS = require("Personal")
      PS.EnsurePlayerFields(GD.player)
      return "个人现金=" .. tostring(GD.player.cash)
    `,
    steps: [
      {
        desc: '买入八类投资产品',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local products = { "deposit", "moneyFund", "bond", "indexFund", "stock", "trust", "peFund", "reits" }
          local okCount, detail = 0, {}
          for _, pid in ipairs(products) do
            local ok, msg = PS.Invest(GD, pid, 5000)
            if ok then okCount = okCount + 1 else detail[#detail + 1] = pid .. ":" .. tostring(msg) end
          end
          return tostring(okCount) .. "/8|" .. table.concat(detail, ",")
        `,
        expect: /^[1-8]\/8/,
      },
      {
        desc: '推进 24 个月，投资产生收益',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local target = GD.totalMonths + 24
          local g = 0
          while GD.totalMonths < target and g < 1600 do GD.DailyTick(); g = g + 1 end
          local total = 0
          for k, v in pairs(GD.player.investments or {}) do
            -- 注意：return 是 Lua 关键字，必须用 v["return"] 而不是 v.return
            total = total + (v.amount or 0) + (v["return"] or 0)
          end
          local summary = PS.CalcNetWorth(GD)
          return string.format("%.0f|%.0f", total, summary or 0)
        `,
        expect: /^[1-9]\d*/,
      },
      {
        desc: '赎回货币基金',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local before = GD.player.cash
          local ok, msg = PS.Redeem(GD, "moneyFund", 1000)
          return tostring(ok) .. "|" .. string.format("%.0f", GD.player.cash - before) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '投资服务：策略组合 + 再平衡 + 年度报告',
        lua: `
          local GD = require("GameData")
          local IS = require("personal/InvestmentService")
          IS.Ensure(GD.player)
          local okS = select(1, IS.SetStrategy(GD, "balanced"))
          local okE = select(1, IS.ExecuteStrategy(GD, 2000))
          local okR = select(1, IS.Rebalance(GD))
          local rep = IS.GetAnnualReport(GD)
          local detail = IS.GetDetail(GD)
          local n = 0
          if type(detail) == "table" then for _ in pairs(detail) do n = n + 1 end end
          return tostring(okS) .. tostring(okE) .. tostring(okR) .. "|" .. n .. "|" .. type(rep)
        `,
        expect: /^true/,
      },
      {
        desc: '个人信用贷款',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local s = PS.GetPersonalCreditSummary(GD)
          local limit = type(s) == "table" and (s.limit or s.maxAmount or 0) or 0
          if limit <= 0 then return "no-limit|" .. tostring(limit) end
          local ok, msg = PS.ApplyPersonalCreditLoan(GD, nil, math.min(1000, limit), 24)
          return tostring(ok) .. "|" .. tostring(#(GD.player.loans or {})) .. "|" .. tostring(msg or "")
        `,
        expect: /^(true|no-limit)/,
      },
      { desc: '个人财务页渲染', screen: 'personalFinance', expectText: '个人' },
    ],
  },

  {
    id: 'personal-life',
    title: '个人生活与家庭',
    note: '购房（含按揭）→ 出租 → 生活方式消费 → 婚育 → 传承数据',
    setup: `${BOOTSTRAP}
      local PS = require("Personal")
      PS.EnsurePlayerFields(GD.player)
      return "个人现金=" .. tostring(GD.player.cash)
    `,
    steps: [
      {
        desc: '购买个人房产（用按揭）',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local ok, msg = PS.BuyProperty(GD, 1, true)
          local props = GD.player.properties or {}
          local p = props[#props]
          return tostring(ok) .. "|" .. tostring(#props) .. "|" .. tostring(p and p.name) .. "|" .. tostring(msg or "")
        `,
        expect: /^true\|[1-9]/,
      },
      {
        desc: '房产出租产生租金',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local ok = select(1, PS.ToggleRent(GD, #(GD.player.properties or {})))
          local before = GD.player.cash
          local target = GD.totalMonths + 6
          local g = 0
          while GD.totalMonths < target and g < 500 do GD.DailyTick(); g = g + 1 end
          return tostring(ok) .. "|" .. string.format("%.0f", GD.player.cash - before)
        `,
        expect: /^true/,
      },
      {
        desc: '购买生活方式资产',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local ok, msg = PS.BuyLifestyle(GD, 1)
          local n = #(GD.player.lifestyle or GD.player.lifestyleAssets or {})
          return tostring(ok) .. "|" .. tostring(n) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '个人社交身份与净资产计算',
        lua: `
          local GD = require("GameData")
          local PS = require("Personal")
          local id = PS.GetSocialIdentity(GD.player)
          local nw = PS.CalcNetWorth(GD)
          local tax = PS.GetPersonalTaxSummary(GD, 500)
          return tostring(type(id)) .. "|" .. string.format("%.0f", nw or 0) .. "|" .. tostring(type(tax))
        `,
        expect: /^table\|/,
      },
      { desc: '个人生活页渲染', screen: 'personalLife', expectText: '个人' },
    ],
  },

  {
    id: 'stock',
    title: '股市',
    note: '买入 → 月度行情与分红 → 卖出结算',
    setup: `${BOOTSTRAP}
      local SM = require("StockMarket")
      SM.Init(GD)
      local n = #(GD.stockMarket.companies or {})
      return "股票数=" .. tostring(n) .. " 首只=" .. tostring(GD.stockMarket.companies[1].code)
    `,
    steps: [
      {
        desc: '买入三只股票',
        lua: `
          local GD = require("GameData")
          local SM = require("StockMarket")
          local codes = {}
          for i = 1, 3 do codes[i] = GD.stockMarket.companies[i].code end
          local okCount = 0
          for _, code in ipairs(codes) do
            if select(1, SM.Buy(GD, code, 5000)) then okCount = okCount + 1 end
          end
          local sum = SM.GetPortfolioSummary(GD)
          local held = type(sum) == "table" and (sum.holdingCount or 0) or 0
          return tostring(okCount) .. "/3|" .. tostring(held) .. "|" .. table.concat(codes, ",")
        `,
        expect: /^3\/3\|3/,
      },
      {
        desc: '推进 24 个月，行情与分红结算',
        lua: `
          local GD = require("GameData")
          local SM = require("StockMarket")
          local target = GD.totalMonths + 24
          local g = 0
          while GD.totalMonths < target and g < 1600 do GD.DailyTick(); g = g + 1 end
          local sum = SM.GetPortfolioSummary(GD)
          local value = type(sum) == "table" and (sum.totalValue or 0) or 0
          local div = GD.stockMarket.totalDividends or 0
          local hist = #(GD.stockMarket.history or {})
          return string.format("%.0f|%.0f|%d", value, div, hist)
        `,
        expect: /^[1-9]\d*\|/,
      },
      {
        desc: '卖出全部持仓',
        lua: `
          local GD = require("GameData")
          local SM = require("StockMarket")
          local before = GD.player.cash
          local sold = 0
          for code, h in pairs(GD.stockMarket.holdings or {}) do
            local shares = h.shares or 0
            if shares > 0 and select(1, SM.Sell(GD, code, shares)) then sold = sold + 1 end
          end
          local sum = SM.GetPortfolioSummary(GD)
          return tostring(sold) .. "|" .. string.format("%.0f", GD.player.cash - before) ..
                 "|剩余持仓=" .. tostring(type(sum) == "table" and sum.holdingCount or -1)
        `,
        expect: /^3\|/,
      },
      { desc: '投资页渲染', screen: 'invest', expectText: '股市' },
    ],
  },

  {
    id: 'group',
    title: '集团',
    note: '组建集团 → 高管 → 注资/分红 → 集团贷款',
    setup: `${BOOTSTRAP}
      local GS = require("GroupSystem")
      GD.InitCompany("二号地产", "private", "balanced", 1000, GD.cities[2].name)
      GS.EnsureFields(GD)
      return "候选公司=" .. tostring(#GS.GetFormationCompanies(GD))
    `,
    steps: [
      {
        desc: '组建集团',
        lua: `
          local GD = require("GameData")
          local GS = require("GroupSystem")
          local ids = {}
          for _, c in ipairs(GS.GetFormationCompanies(GD)) do ids[#ids + 1] = c.id end
          local ok, msg = GS.FormGroup(GD, "测试控股集团", 500, ids)
          return tostring(ok) .. "|" .. tostring(GS.IsActive(GD)) .. "|" .. tostring(GD.group and GD.group.cash) .. "|" .. tostring(msg or "")
        `,
        expect: /^true\|true/,
      },
      {
        desc: '集团高管聘用',
        lua: `
          local GD = require("GameData")
          local GS = require("GroupSystem")
          local ok, msg = GS.HireExecutive(GD, "ceo")
          local n = 0
          if GD.group and GD.group.executives then
            for _ in pairs(GD.group.executives) do n = n + 1 end
          end
          return tostring(ok) .. "|" .. tostring(n) .. "|" .. tostring(msg or "")
        `,
        expect: /^(true|false)/,
      },
      {
        desc: '个人向集团注资',
        lua: `
          local GD = require("GameData")
          local GS = require("GroupSystem")
          local before = GD.group.cash
          local ok, msg = GS.InjectPersonalCapital(GD, 500)
          return tostring(ok) .. "|" .. string.format("%.0f", (GD.group.cash or 0) - before) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '集团向个人分红',
        lua: `
          local GD = require("GameData")
          local GS = require("GroupSystem")
          local limit = GS.GetPersonalTransferLimit(GD)
          local before = GD.player.cash
          local ok, msg = GS.TransferToPersonal(GD, math.min(200, tonumber(limit) or 0))
          return tostring(ok) .. "|" .. string.format("%.0f", GD.player.cash - before) .. "|limit=" .. tostring(limit)
        `,
        expect: /^(true|false)/,
      },
      {
        desc: '集团贷款与月度运转',
        lua: `
          local GD = require("GameData")
          local GS = require("GroupSystem")
          local okL, msgL = GS.ApplyLoan(GD, "group_credit", 3000, 24, "equal")
          local before = GD.group and GD.group.cash or 0
          local target = GD.totalMonths + 12
          local g = 0
          while GD.totalMonths < target and g < 800 do GD.DailyTick(); g = g + 1 end
          return tostring(okL) .. "|" .. tostring(msgL or "") .. "|" ..
                 string.format("%.0f", GD.group and GD.group.cash or 0) .. "|" .. tostring(#(GD.group and GD.group.loans or {}))
        `,
        expect: /^(true|false)/,
      },
      { desc: '集团页渲染', screen: 'group', expectText: '集团' },
    ],
  },

  {
    id: 'international',
    title: '国际业务',
    note: '（需先成立集团）注册海外事业部 → 尽调 → 四种业务 → 对冲/存款 → 月度收益',
    setup: `${BOOTSTRAP}
      local GS = require("GroupSystem")
      local INS = require("InternationalSystem")
      GD.InitCompany("海外测试二号", "private", "balanced", 1000, GD.cities[2].name)
      GS.EnsureFields(GD)
      local ids = {}
      for _, c in ipairs(GS.GetFormationCompanies(GD)) do ids[#ids + 1] = c.id end
      local okG, msgG = GS.FormGroup(GD, "海外测试集团", 500, ids)
      GD.group.cash = 80000   -- 测试夹具：注册海外事业部需要集团现金
      INS.EnsureFields(GD)
      local countries = INS.GetCountries(GD)
      return "集团=" .. tostring(GS.IsActive(GD)) .. "(" .. tostring(msgG or "") .. ") 国家数=" .. tostring(#countries)
    `,
    steps: [
      {
        desc: '注册海外事业部',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local ok, msg = INS.RegisterDivision(GD, 20000)
          local d = INS.GetDivisionSummary(GD)
          local cap = INS.GetCapacity(GD)
          return tostring(ok) .. "|" .. tostring(msg or "") .. "|capacity=" .. tostring(cap)
        `,
        expect: /^true/,
      },
      {
        desc: '目标国家尽调',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local countries = INS.GetCountries(GD)
          local cid = countries[1].id or countries[1].code
          local ok, msg = INS.StartDueDiligence(GD, cid, "market")
          local target = GD.totalMonths + 6
          local g = 0
          while GD.totalMonths < target and g < 500 do GD.DailyTick(); g = g + 1 end
          local st = INS.GetDueDiligenceStatus(GD, cid)
          return tostring(ok) .. "|" .. tostring(cid) .. "|" .. tostring(type(st)) .. "|" .. tostring(msg or "")
        `,
        expect: /^true/,
      },
      {
        desc: '集团向事业部注资并升级国际业务部容量',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local before = INS.GetCapacity(GD)
          local countries = INS.GetCountries(GD)
          local cid = countries[1].id or countries[1].code
          GD.group.cash = 120000            -- 测试夹具：保证集团有能力注资
          local okInj, msgInj = INS.InjectDivisionCapital(GD, 60000, cid)
          for _ = 1, 3 do pcall(INS.UpgradeCapacity, GD) end
          local d = INS.GetDivisionSummary(GD)
          return tostring(before) .. "→" .. tostring(INS.GetCapacity(GD)) ..
                 "|注资=" .. tostring(okInj) .. "|" .. tostring(msgInj or "")
        `,
        expect: /^2→[4-9]/,
      },
      {
        desc: '四种海外业务各投一笔',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local countries = INS.GetCountries(GD)
          local cid = countries[1].id or countries[1].code
          local results, okCount = {}, 0
          local function try(name, fn, ...)
            local called, ok, msg = pcall(fn, GD, ...)
            if called and ok then okCount = okCount + 1; results[#results + 1] = name .. "=ok"
            else results[#results + 1] = name .. "=" .. tostring(msg or "false") end
          end
          try("直投土地", INS.InvestDirectLand, cid, 5000, "hold")
          try("并购资产", INS.BuyExistingAsset, cid, 5000, "office")
          try("合资公司", INS.CreateJointVenture, cid, 5000, "海外伙伴", 40)
          try("基金", INS.InvestFund, cid, 5000, "core")
          local s = INS.GetSummary(GD)
          local invested = type(s) == "table" and (s.activeInvestedCny or 0) or 0
          return tostring(okCount) .. "/4|" .. table.concat(results, " / ") .. "|投入=" .. string.format("%.0f", invested)
        `,
        expect: /^4\/4\|/,
      },
      {
        desc: '汇率对冲 + 国际银行存款',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local countries = INS.GetCountries(GD)
          local cid = countries[1].id or countries[1].code
          local okH, msgH = pcall(INS.ApplyFXHedge, GD, cid, 2000, 12)
          local okD, msgD = pcall(INS.DepositToInternationalBank, GD, cid, 3000, "time", 12)
          local d = INS.GetDivisionSummary(GD)
          return tostring(okH) .. "|" .. tostring(okD) .. "|" .. tostring(msgD or "")
        `,
        expect: /^(true|false)/,
      },
      {
        desc: '推进 24 个月，海外资产产生收益',
        lua: `
          local GD = require("GameData")
          local INS = require("InternationalSystem")
          local before = INS.GetSummary(GD)
          local target = GD.totalMonths + 24
          local g = 0
          while GD.totalMonths < target and g < 1600 do GD.DailyTick(); g = g + 1 end
          local after = INS.GetSummary(GD)
          local nav = INS.GetNetAssetValue(GD)
          return string.format("净资产%.0f 投入%.0f→%.0f 累计利润%.0f",
            tonumber(nav.netAssets) or 0,
            tonumber(before.activeInvestedCny) or 0,
            tonumber(after.activeInvestedCny) or 0,
            tonumber(after.totalProfitCny or after.divisionRetainedEarningsCny) or 0)
        `,
        expect: /净资产[1-9]/,
      },
      { desc: '国际页渲染', screen: 'international', expectText: '国际' },
    ],
  },

  {
    id: 'governance',
    title: '公司治理',
    note: '股权融资稀释 → 董事会席位 → 高管 → 股东决议 → CEO 月度报告审批 → 全权托管',
    setup: `${BOOTSTRAP}
      local GV = require("Governance")
      GV.EnsureGovernanceFields(GD.company.governance, GD.company.founderName or "创始人")
      local s = GV.GetFinancingSummary(GD)
      local keys = {}
      if type(s) == "table" then for k in pairs(s) do keys[#keys + 1] = tostring(k) end end
      table.sort(keys)
      return "融资摘要键=" .. table.concat(keys, ",") .. " 创始人持股=" .. tostring(GV.GetFounderRatio(GD))
    `,
    steps: [
      {
        desc: '股权融资（引入资本、创始人稀释）',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          local before = GV.GetFounderRatio(GD)
          local rounds = { "seed", "angel", "a", "b", "preIPO" }
          local done, msg = 0, nil
          for _, rid in ipairs(rounds) do
            if GV.CanFinance(GD, rid) then
              local ok, m = GV.ExecuteFinancing(GD, rid, 10)
              if ok then done = done + 1 else msg = m end
            end
          end
          local after = GV.GetFounderRatio(GD)
          return string.format("轮次=%d|%.4f→%.4f|股东数=%d|%s", done, before, after,
                 GV.GetShareholderCount(GD), tostring(msg or ""))
        `,
        expect: /^轮次=[1-9]/,
      },
      {
        desc: '董事会席位分配与控制权等级',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          GV.AllocateBoardSeats(GD.company.governance)
          local gov = GD.company.governance
          local seats = gov.boardSeats or gov.board or {}
          local n = 0
          if type(seats) == "table" then for _ in pairs(seats) do n = n + 1 end end
          local ratio = GV.GetFounderRatio(GD)
          return "席位=" .. tostring(n) .. "|控制权=" .. tostring(GV.GetControlLevel(ratio)) ..
                 "|持股=" .. string.format("%.3f", ratio)
        `,
        expect: /控制权=/,
      },
      {
        desc: '聘用高管',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          local hired = 0
          for _, role in ipairs({ "ceo", "cfo", "cmo", "coo" }) do
            if select(1, GV.HireExecutive(GD, role)) then hired = hired + 1 end
          end
          local eff = GV.GetExecutiveEffects(GD)
          local n = 0
          if type(eff) == "table" then for _ in pairs(eff) do n = n + 1 end end
          return "聘用=" .. hired .. "|效果项=" .. n
        `,
        expect: /^聘用=[1-4]/,
      },
      {
        desc: '股东决议提案与表决',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          local passed, total = 0, 0
          for idx = 1, 5 do
            if GV.CanProposeResolution(GD, idx) then
              total = total + 1
              local ok = select(1, GV.ProposeResolution(GD, idx))
              if ok then passed = passed + 1 end
            end
          end
          return "可提案=" .. total .. "|通过=" .. passed
        `,
        expect: /^可提案=/,
      },
      {
        desc: '开启 CEO 月度报告并推进 6 个月，产生待审批报告',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          GV.SetCeoReportEnabled(GD, true)
          local target = GD.totalMonths + 6
          local g = 0
          while GD.totalMonths < target and g < 800 do GD.DailyTick(); g = g + 1 end
          local has = GV.HasPendingCeoReports(GD)
          local n = 0
          if GD._pendingCeoReportQueue then n = #GD._pendingCeoReportQueue end
          return "待审批=" .. tostring(has) .. "|队列=" .. n
        `,
        expect: /^待审批=(true|false)\|队列=\d+/,
      },
      {
        desc: '审批 CEO 报告（应用提案）',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          local q = GD._pendingCeoReportQueue
          if not q or #q == 0 then return "无待审批报告（该项目未启用 CEO 托管）" end
          local report = q[1]
          GV.GetCeoReportPendingDecisions(report)
          local okApply, errApply = pcall(GV.ApplyCeoReport, GD, report)
          return "应用=" .. tostring(okApply) .. "|" .. tostring(errApply or "")
        `,
        expect: /^(应用=true|无待审批报告)/,
      },
      {
        desc: '全权托管 + 分红率设置',
        lua: `
          local GD = require("GameData")
          local GV = require("Governance")
          local okM, msgM = GV.SetFullManagement(GD, true)
          local okD, msgD = GV.SetDividendRate(GD, 0.3)
          return "托管=" .. tostring(okM) .. "(" .. tostring(msgM or "") .. ")" ..
                 "|分红率=" .. tostring(okD) .. "(" .. tostring(msgD or "") .. ")" ..
                 "|生效=" .. tostring(GV.IsFullManagementEnabled(GD))
        `,
        expect: /^托管=(true|false)/,
      },
      { desc: '治理页渲染', screen: 'governance', expectText: '治理' },
    ],
  },

  {
    id: 'settings-save',
    title: '设置页存档接线',
    note: '在设置页用真实按钮完成「保存 → 刷新列表 → 读档」，验证 UI 到存档系统的接线',
    setup: `${BOOTSTRAP}
      local GD = require("GameData")
      GD.company.cash = 333333
      return "公司现金=" .. tostring(GD.company.cash)
    `,
    steps: [
      { desc: '打开设置页', screen: 'settings', expectText: '存档管理' },
      {
        desc: '点「保存」写入存档位 1',
        click: '保存',
        lua: `
          local GD = require("GameData")
          local info = GD.GetSlotInfo(1)
          if not info then return "no-save" end
          return tostring(info.name) .. "|" .. string.format("%.0f", info.cash)
        `,
        expect: /^长线测试地产\|333333/,
      },
      {
        desc: '重新打开设置页，存档位显示已存内容',
        screen: 'settings',
        expectText: '存档位 1',
      },
      {
        desc: '点「读取」恢复存档',
        click: '读取',
        lua: `
          local GD = require("GameData")
          GD.company.cash = 1
          local ok, err = GD.LoadFromSlot(1)
          return tostring(ok) .. "|" .. string.format("%.0f", GD.company.cash)
        `,
        expect: /^true\|333333/,
      },
    ],
  },
];

// ---------------------------------------------------------------------------
// 运行器
// ---------------------------------------------------------------------------
let totalPassed = 0;
let totalFailed = 0;
const summary = [];

function assert(cond, msg) {
  if (!cond) throw new Error(msg || '断言失败');
}

// 内存虚拟文件系统：存档读写要真的能落地，否则设置页的保存按钮点不动
function createMemoryAdapter() {
  const files = new Map();
  return {
    read: (p) => (files.has(p) ? files.get(p) : null),
    write: (p, t) => { files.set(p, t); },
    exists: (p) => files.has(p),
    del: (p) => { files.delete(p); },
    mkdir: () => {},
  };
}

async function runScenario(sc) {
  console.log(`\n${'='.repeat(72)}\n[${sc.id}] ${sc.title}\n  ${sc.note}\n${'='.repeat(72)}`);

  const dom = createFakeDOM();
  const logs = [];
  const app = await bootGame({
    LuaFactory,
    sources: SOURCES,
    doc: dom.doc,
    vfsAdapter: createMemoryAdapter(),
    audio: { play: () => 1, setGain: () => {} },
    log: (m) => logs.push(m),
    initialScreen: 'start',
    raf: null,
  });
  const lua = app.lua;
  const luaRun = (code) => lua.doStringSync(code);

  let passed = 0;
  let failed = 0;

  try {
    const setupResult = luaRun(sc.setup);
    console.log(`  前置: ${setupResult}`);
  } catch (e) {
    console.log(`  \x1b[31m✘\x1b[0m 前置失败: ${e.message}`);
    failed++;
  }

  for (const step of sc.steps) {
    try {
      if (step.screen) {
        lua.global.get('__webNavigate')(step.screen);
      }
      if (step.click) {
        for (const label of [].concat(step.click)) {
          const hit = dom.clickables().find((el) => {
            const t = (el.textContent || '').replace(/\s+/g, ' ').trim();
            const inner = (el.children || []).map((c) => (c.textContent || '').trim()).join('/');
            return t === label || t.includes(label) || inner.includes(label);
          });
          assert(hit, `找不到按钮「${label}」`);
          hit.dispatch('click');
        }
      }
      if (step.lua) {
        const r = luaRun(step.lua);
        if (step.expect && !step.expect.test(String(r))) {
          throw new Error(`结果「${String(r).slice(0, 120)}」不匹配 ${step.expect}`);
        }
        passed++;
        console.log(`  \x1b[32m✔\x1b[0m ${step.desc}${r !== undefined ? '  ' + String(r).slice(0, 90) : ''}`);
      } else if (step.screen) {
        const texts = dom.texts();
        const err = texts.find((t) => t.includes('页面加载出错'));
        assert(!err, '屏幕构建报错: ' + texts[texts.indexOf(err) + 1]);
        assert(dom.count() > 10, `节点数过少: ${dom.count()}`);
        if (step.expectText) {
          assert(texts.some((t) => t.includes(step.expectText)),
            `缺少预期文案「${step.expectText}」，实际前几条: ${texts.slice(0, 8).join(' | ')}`);
        }
        passed++;
        console.log(`  \x1b[32m✔\x1b[0m ${step.desc}  ${dom.count()} 节点 · ${texts.filter((t) => t.length > 1).slice(0, 3).join(' | ').slice(0, 60)}`);
      }
    } catch (e) {
      failed++;
      console.log(`  \x1b[31m✘\x1b[0m ${step.desc}\n      ${e && e.message ? e.message : e}`);
      if (VERBOSE) {
        const errs = logs.filter((l) => l.includes('出错') || l.includes('失败'));
        errs.slice(-6).forEach((l) => console.log('        ' + l));
      }
    }
  }

  totalPassed += passed;
  totalFailed += failed;
  summary.push({ id: sc.id, title: sc.title, passed, failed });
  console.log(`  → ${sc.id}: 通过 ${passed}，失败 ${failed}`);
}

const targets = only.length ? SCENARIOS.filter((s) => only.includes(s.id)) : SCENARIOS;
console.log(`\n=== 地产风云 · 网页移植阶段 3 · 长线系统等价验证（${targets.length} 个场景）===`);

for (const sc of targets) {
  await runScenario(sc);
}

console.log(`\n${'='.repeat(72)}\n汇总`);
for (const s of summary) {
  console.log(`  ${s.failed === 0 ? '\x1b[32m✔\x1b[0m' : '\x1b[31m✘\x1b[0m'} ${s.id.padEnd(18)} ${String(s.passed).padStart(2)} 通过 / ${s.failed} 失败  ${s.title}`);
}
console.log(`\n=== 结果：通过 ${totalPassed} 项，失败 ${totalFailed} 项 ===\n`);
process.exit(totalFailed > 0 ? 1 : 0);
