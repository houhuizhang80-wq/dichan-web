-- 探测：个人理财 / 股市 / 集团 的数据形状
local GD = require("GameData")
local PS = require("Personal")
local SM = require("StockMarket")
local GS = require("GroupSystem")

local out = {}
local function add(...) out[#out + 1] = table.concat({ ... }, " ") end

-- 个人理财
PS.EnsurePlayerFields(GD.player)
local inv = GD.player.investments or {}
local keys = {}
for k in pairs(inv) do keys[#keys + 1] = k end
table.sort(keys)
add("[个人投资] 键:", table.concat(keys, ","))
local s = PS.GetInvestmentSummary(GD)
if type(s) == "table" then
  local names = {}
  for _, item in ipairs(s) do
    names[#names + 1] = tostring(item.id or item.key or item.name) .. ":" .. tostring(item.name)
  end
  add("[个人投资] 产品:", table.concat(names, " | "))
end
add("[个人投资] 现金:", tostring(GD.player.cash))

-- 股市
local ok, err = pcall(SM.Init, GD)
add("[股市] SM.Init ->", tostring(ok), tostring(err))
local sm = GD.stockMarket
if type(sm) == "table" then
  local k2 = {}
  for k in pairs(sm) do k2[#k2 + 1] = tostring(k) end
  table.sort(k2)
  add("[股市] 顶层键:", table.concat(k2, ","))
  local list = sm.stocks or sm.list or sm
  if type(list) == "table" then
    local n = 0
    for _, st in ipairs(list) do
      n = n + 1
      if n <= 4 then
        add("[股市] 股票", n, ":", tostring(st.code), tostring(st.name), "price=", tostring(st.price))
      end
    end
    add("[股市] 股票数:", tostring(n))
  end
end

-- 集团
local okF, errF = pcall(GS.EnsureFields, GD)
add("[集团] EnsureFields ->", tostring(okF), tostring(errF))
local form = GS.GetFormationCompanies(GD)
add("[集团] 可组建公司数:", tostring(type(form) == "table" and #form or -1))
if type(form) == "table" then
  for i = 1, math.min(3, #form) do
    add("[集团] 候选", i, ":", tostring(form[i].id), tostring(form[i].name), "ratio=", tostring(form[i].founderRatio))
  end
end
add("[集团] 已激活:", tostring(GS.IsActive(GD)))

return table.concat(out, "\n")
