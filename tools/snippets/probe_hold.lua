-- 探测：自持（固定资产）链路怎么走
local GD = require("GameData")
local DT = require("DevTypes")
local OP = require("Operations")

GD.paused = false
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
local startOk, startMsg = GD.StartDevelopment(land.id, devTypeId, nil, "basic")
local p = GD.projects[#GD.projects]

local out = {}
local function add(...) out[#out + 1] = table.concat({ ... }, " ") end

add("StartDevelopment ->", tostring(startOk), tostring(startMsg))
add("land.landUse=", tostring(land.landUse), "devTypeId=", tostring(devTypeId))
add("project=", tostring(p and p.name), "status=", tostring(p and p.status),
    "devCategory=", tostring(p and p.devCategory))
add("unitPlan.planned=", tostring(p and p.unitPlan and p.unitPlan.planned),
    "sellUnits=", tostring(p and p.unitPlan and p.unitPlan.sellUnits),
    "holdUnits=", tostring(p and p.unitPlan and p.unitPlan.holdUnits))

-- 规划单元：一半销售一半自持
local ok1, r1 = pcall(GD.PlanUnits, p, 100, 50)
add("PlanUnits(100,50) ->", tostring(ok1), tostring(r1))
add("after: sellUnits=", tostring(p.unitPlan and p.unitPlan.sellUnits),
    "holdUnits=", tostring(p.unitPlan and p.unitPlan.holdUnits),
    "holdArea=", tostring(p.unitPlan and p.unitPlan.holdArea),
    "planned=", tostring(p.unitPlan and p.unitPlan.planned))

-- 规划指标 / 方案 / 限额
local okP, rP = pcall(GD.ConfirmPlanning, p)
add("ConfirmPlanning ->", tostring(okP), tostring(rP))
add("确认规划后 totalUnits=", tostring(p.sales.totalUnits), "buildArea=", tostring(p.land.buildArea))

-- 单元规划：留 1/3 自持（PlanUnits 要求 sellUnits + holdUnits == totalUnits）
local total = p.sales.totalUnits
local hold = math.max(1, math.floor(total / 3))
local sell = total - hold
local ok1b, r1b = pcall(GD.PlanUnits, p, sell, hold)
add("PlanUnits(", tostring(sell), ",", tostring(hold), ") ->", tostring(ok1b), tostring(r1b))
add("after: sellUnits=", tostring(p.unitPlan.sellUnits),
    "holdUnits=", tostring(p.unitPlan.holdUnits),
    "holdArea=", tostring(p.unitPlan.holdArea),
    "planned=", tostring(p.unitPlan.planned))

local okS, rS = pcall(GD.AutoConfirmScheme, p)
add("AutoConfirmScheme ->", tostring(okS), tostring(rS))

local okC, rC = pcall(GD.AutoConfirmCostCap, p)
add("AutoConfirmCostCap ->", tostring(okC), tostring(rC))

add("design.planning.confirmed=", tostring(p.design.planning.confirmed),
    "scheme.confirmed=", tostring(p.design.scheme.confirmed),
    "costCap.confirmed=", tostring(p.design.costCap.confirmed))

-- 推进到竣工
GD.paused = false
local guard = 0
while guard < 3000 do
  if p.sales and p.sales.canPresale and not p.sales.canSell then pcall(GD.StartPresale, p) end
  if p.status == "pending_settlement" then pcall(GD.SettleProject, p) end
  if p.status == "pending_completion" then pcall(GD.ConfirmCompletion, p) end
  if p.status == "delivery" or p.status == "completed" then break end
  GD.DailyTick()
  guard = guard + 1
end
add("推进", tostring(guard), "月后 status=", tostring(p.status),
    "soldUnits=", tostring(p.sales and p.sales.soldUnits))

-- 转固
local okF, rF = pcall(GD.ConvertToFixedAsset, p, 1)
add("ConvertToFixedAsset ->", tostring(okF), tostring(rF))
add("fixedAssets=", tostring(#(GD.fixedAssets or {})))
local fa = GD.fixedAssets and GD.fixedAssets[1]
if fa then
  add("fa.name=", tostring(fa.name), "area=", tostring(fa.holdArea),
      "monthlyRent=", tostring(fa.monthlyRent), "value=", tostring(fa.currentValue))
end

return table.concat(out, "\n")
