-- 探测：租金落到哪个账目分类；国际业务容量与净资产
local GD = require("GameData")
local DT = require("DevTypes")
local INS = require("InternationalSystem")
local GS = require("GroupSystem")

local out = {}
local function add(...) out[#out + 1] = table.concat({ ... }, " ") end

-- ---------- 自持固定资产：租金入账分类 ----------
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
local p = GD.StartDevelopment(land.id, types[1].id or types[1].key, nil, "basic")
p = GD.projects[#GD.projects]
GD.ConfirmPlanning(p)
local total = p.sales.totalUnits
local hold = math.max(1, math.floor(total / 3))
GD.PlanUnits(p, total - hold, hold)

local guard = 0
while guard < 4000 do
  if GD.AutoConfirmScheme then pcall(GD.AutoConfirmScheme, p) end
  if GD.AutoConfirmCostCap then pcall(GD.AutoConfirmCostCap, p) end
  if p.sales.canPresale and not p.sales.canSell then pcall(GD.StartPresale, p) end
  if p.status == "pending_settlement" then pcall(GD.SettleProject, p) end
  if p.status == "pending_completion" then pcall(GD.ConfirmCompletion, p) end
  if p.status == "delivery" then break end
  GD.DailyTick(); guard = guard + 1
end
GD.ConvertToFixedAsset(p, 1)
GD.ListFixedAssetForRent(1, "enterprise")
local fa = GD.fixedAssets[1]
add("[自持] fa.monthlyRent=", tostring(fa.monthlyRent), "rentStatus=", tostring(fa.rentStatus),
    "tenant=", tostring(fa.tenantType), "occupancy=", tostring(fa.occupancyRate))

local beforeLedger = #(GD.ledger or {})
local beforeCash = GD.company.cash
for _ = 1, 12 do
  local t = GD.totalMonths + 1
  local gg = 0
  while GD.totalMonths < t and gg < 40 do GD.DailyTick(); gg = gg + 1 end
end
add("[自持] 12 月后现金变化=", string.format("%.0f", GD.company.cash - beforeCash))
local cats = {}
for i = beforeLedger + 1, #(GD.ledger or {}) do
  local e = GD.ledger[i]
  cats[tostring(e.category)] = (cats[tostring(e.category)] or 0) + 1
end
local catList = {}
for k, v in pairs(cats) do catList[#catList + 1] = k .. "×" .. v end
table.sort(catList)
add("[自持] 新增账目分类:", table.concat(catList, ", "))
local fa2 = GD.fixedAssets[1]
add("[自持] fa2.rentStatus=", tostring(fa2.rentStatus), "tenant=", tostring(fa2.tenantType),
    "monthlyRent=", tostring(fa2.monthlyRent), "currentValue=", tostring(fa2.currentValue))

-- ---------- 国际：容量与净资产 ----------
GD.InitCompany("海外二号", "private", "balanced", 1000, GD.cities[2].name)
GS.EnsureFields(GD)
local ids = {}
for _, c in ipairs(GS.GetFormationCompanies(GD)) do ids[#ids + 1] = c.id end
GS.FormGroup(GD, "海外集团", 500, ids)
GD.group.cash = 200000
INS.EnsureFields(GD)
add("[国际] RegisterDivision=", tostring(select(1, INS.RegisterDivision(GD, 20000))))
add("[国际] capacity=", tostring(INS.GetCapacity(GD)))
add("[国际] UpgradeCapacity=", tostring(select(1, INS.UpgradeCapacity(GD))))
add("[国际] capacity=", tostring(INS.GetCapacity(GD)))
local countries = INS.GetCountries(GD)
local cid = countries[1].id or countries[1].code
INS.StartDueDiligence(GD, cid, "market")
for _ = 1, 6 do
  local t = GD.totalMonths + 1
  local gg = 0
  while GD.totalMonths < t and gg < 40 do GD.DailyTick(); gg = gg + 1 end
end
for _, call in ipairs({
  { "直投土地", INS.InvestDirectLand, cid, 5000, "hold" },
  { "并购资产", INS.BuyExistingAsset, cid, 5000, "office" },
  { "合资公司", INS.CreateJointVenture, cid, 5000, "海外伙伴", 40 },
  { "基金", INS.InvestFund, cid, 5000, "core" },
}) do
  local name, fn = call[1], call[2]
  local ok, msg = fn(GD, call[3], call[4], call[5])
  add("[国际]", name, "->", tostring(ok), tostring(msg or ""))
end
local data = GD.international or {}
local kk = {}
for k in pairs(data) do kk[#kk + 1] = tostring(k) end
table.sort(kk)
add("[国际] international 键:", table.concat(kk, ","))
add("[国际] assets=", tostring(#(data.assets or {})), "funds=", tostring(#(data.funds or {})),
    "projects=", tostring(#(data.projects or {})), "jvs=", tostring(#(data.jointVentures or {})))
add("[国际] NAV=", tostring(INS.GetNetAssetValue(GD)))
local s = INS.GetSummary(GD)
if type(s) == "table" then
  local sk = {}
  for k in pairs(s) do sk[#sk + 1] = k .. "=" .. tostring(s[k]) end
  table.sort(sk)
  add("[国际] summary:", table.concat(sk, ", "):sub(1, 300))
end

return table.concat(out, "\n")
