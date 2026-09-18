-- 探测：股票代码 / 租户类型 / 集团组建条件
local GD = require("GameData")
local SM = require("StockMarket")
local GS = require("GroupSystem")

local out = {}
local function add(...) out[#out + 1] = table.concat({ ... }, " ") end

-- 股票
SM.Init(GD)
local comps = GD.stockMarket and GD.stockMarket.companies
add("[股市] companies 类型:", type(comps), "数量:", tostring(type(comps) == "table" and #comps or -1))
if type(comps) == "table" then
  local n = 0
  for k, c in pairs(comps) do
    n = n + 1
    if n <= 6 then
      add("[股市]", tostring(k), "->", tostring(c.code), tostring(c.name), "price=", tostring(c.price),
          "shares=", tostring(c.totalShares))
    end
  end
end
local okB, rB = pcall(SM.Buy, GD, comps and comps[1] and comps[1].code or "TEST", 1000)
add("[股市] Buy ->", tostring(okB), tostring(rB))
add("[股市] holdings=", tostring(GD.stockMarket and #(GD.stockMarket.holdings or {})))

-- 租户类型（固定资产出租用）
local TT = nil
for _, name in ipairs({ "TENANT_TYPES", "RENTAL_TENANT_TYPES", "TENANTS" }) do
  if GD[name] then TT = GD[name]; add("[租户] 找到 GD." .. name) end
end
if TT then
  local n = 0
  for k, v in pairs(TT) do
    n = n + 1
    if n <= 5 then add("[租户]", tostring(k), tostring(type(v) == "table" and (v.id or v.name) or v)) end
  end
  add("[租户] 数量:", tostring(n))
end

-- 集团：再造一家公司后看候选
local city2 = GD.cities[2] and GD.cities[2].name
local ok2, msg2 = GD.InitCompany("二号地产", "private", "balanced", 1000, city2)
add("[集团] 第二家公司 ->", tostring(ok2), tostring(msg2))
local form = GS.GetFormationCompanies(GD)
add("[集团] 可组建公司数:", tostring(type(form) == "table" and #form or -1))
if type(form) == "table" then
  for i = 1, math.min(4, #form) do
    add("[集团] 候选", i, ":", tostring(form[i].id), tostring(form[i].name))
  end
end
local ids = {}
for _, c in ipairs(form or {}) do ids[#ids + 1] = c.id end
local okF, rF, rF2 = pcall(GS.FormGroup, GD, "探测集团", 500, ids)
add("[集团] FormGroup ->", tostring(okF), tostring(rF), tostring(rF2))
add("[集团] 激活=", tostring(GS.IsActive(GD)), "cash=", tostring(GD.group and GD.group.cash))

return table.concat(out, "\n")
