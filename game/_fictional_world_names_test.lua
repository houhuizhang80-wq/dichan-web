---@diagnostic disable: assign-type-mismatch, missing-fields
local GD = require("GameData")
local SM = require("StockMarket")
local INS = require("InternationalSystem")
local MK = require("Marketing")

local function assertEq(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function cityNames()
    local names = {}
    for _, city in ipairs(GD.cities) do
        names[#names + 1] = city.name
        names[city.name] = true
    end
    return names
end

local function run()
    local names = cityNames()
    assertEq(names["兰德市"] == true, true, "lander city")
    assertEq(names["齐隆市"] == true, true, "qilong city")
    assertEq(names["罗江市"] == true, true, "luojiang city")
    assertEq(names["华尔市"] == true, true, "huaer city")
    assertEq(names["山花市"] == true, true, "shanhua city")
    assertEq(names["西北市"] == true, true, "xibei city")
    assertEq(names["鹿鸣市"] == true, true, "luming city")
    assertEq(names["许州市"] == true, true, "xuzhou fictional")
    assertEq(names["会齐市"] == true, true, "huiqi city")
    assertEq(#GD.cities, 9, "nine cities")
    assertEq(names["长沙"] == true, false, "no changsha")
    assertEq(names["惠州"] == true, false, "no huizhou")

    GD.company = GD.company or {}
    GD.company.city = "长沙"
    GD.company.regionalCompanies = {{name = "长沙区域公司", city = "昆明"}}
    GD.companyPortfolio = {
        nextId = 2,
        activeId = "co_1",
        companies = {
            {
                id = "co_1",
                name = "长沙置业",
                city = "长沙",
                state = {
                    company = {city = "长沙", governance = {pendingCeoReport = {proposals = {presale = {projectCity = "徐州"}}}}},
                    landReserve = {{city = "洛阳", name = "洛阳地块"}},
                    projects = {{name = "贵阳项目", land = {city = "贵阳"}}},
                    stockMarket = {companies = {{code = "SH000002", name = "万科地产"}}},
                },
            },
        },
    }
    GD.landMarket = {{city = "南宁", name = "南宁地块", channelData = {sellerName = "华夏幸福"}, offers = {{buyer = "恒大地产"}}}}
    GD.landReserve = {{city = "兰州"}}
    GD.projects = {{name = "烟台项目", land = {city = "烟台"}}}
    GD.landSupplyPlans = {["长沙"] = {city = "长沙", plannedCount = 1}}
    GD.landSupplyAnnual = {["惠州"] = {["2026"] = 1}}
    GD.player = {
        cityOperations = {
            invest = {["徐州"] = {holdings = {{name = "徐州本地企业股权"}}}},
            bond = {},
            sponsor = {},
            credit = {},
            bank = {},
            bot = {},
        },
    }
    GD.competitors = {
        {name = "融创中国", type = "全国民企", cash = 400000, aggressive = 0.7, style = "激进", tier = "A"},
        {name = "瑞安建设", type = "港资企业", cash = 30000, aggressive = 0.3, style = "保守", tier = "C"},
    }
    GD.stockMarket = {companies = {{code = "SH000002", name = "万科地产"}, {code = "SH600519", name = "贵州茅台"}}}
    GD.events = {{text = "在长沙拿地成功"}}

    GD.NormalizeFictionalWorldNames()

    assertEq(GD.company.city, "兰德市", "company city")
    assertEq(GD.company.regionalCompanies[1].city, "齐隆市", "regional city")
    assertEq(GD.companyPortfolio.companies[1].city, "兰德市", "portfolio city")
    assertEq(GD.companyPortfolio.companies[1].state.company.city, "兰德市", "snapshot city")
    assertEq(GD.companyPortfolio.companies[1].state.landReserve[1].city, "罗江市", "reserve city")
    assertEq(GD.companyPortfolio.companies[1].state.projects[1].land.city, "华尔市", "project city")
    assertEq(GD.landMarket[1].city, "山花市", "market city")
    assertEq(GD.landMarket[1].channelData.sellerName, "华川安居", "seller name")
    assertEq(GD.landMarket[1].offers[1].buyer, "恒远地产", "buyer name")
    assertEq(GD.landReserve[1].city, "西北市", "active reserve")
    assertEq(GD.projects[1].land.city, "鹿鸣市", "active project")
    assertEq(GD.landSupplyPlans["兰德市"] ~= nil, true, "supply plan key")
    assertEq(GD.landSupplyPlans["长沙"] == nil, true, "old supply plan removed")
    assertEq(GD.landSupplyAnnual["会齐市"]["2026"], 1, "annual supply key")
    assertEq(GD.player.cityOperations.invest["许州市"] ~= nil, true, "city ops key")
    assertEq(GD.player.cityOperations.invest["许州市"].holdings[1].name, "许州市本地企业股权", "holding name")
    assertEq(GD.competitors[1].name, "融盛控股", "competitor 1")
    assertEq(GD.competitors[2].name, "瑞澜建设", "competitor 2")
    assertEq(GD.stockMarket.companies[1].name, "万川地产", "stock 1")
    assertEq(GD.stockMarket.companies[2].name, "川源酒业", "stock 2")
    assertEq(GD.events[1].text, "在兰德市拿地成功", "event text")
    assertEq(GD.companyPortfolio.companies[1].state.company.governance.pendingCeoReport.proposals.presale.projectCity, "许州市", "ceo report city")

    SM.SyncMarketConfig(GD)
    assertEq(GD.stockMarket.companies[1].name, "万川地产", "sync stock name")
    assertEq(INS.COUNTRIES[1].name, "西澜联邦", "intl us")
    assertEq(INS.COUNTRIES[2].name, "沙洲联合酋长国", "intl uae")
    assertEq(INS.COUNTRIES[3].name, "东瀛岛国", "intl japan")
    assertEq(INS.COUNTRIES[4].name, "狮城联邦", "intl singapore")
    assertEq(MK.BANKS[1].name, "工川银行", "bank a")
    assertEq(MK.BANKS[3].name, "招远银行", "bank c")

    print("[FICTIONAL-WORLD-TEST] PASS assertions=35")
end

function Start()
    local ok, err = pcall(run)
    if not ok then
        print("[FICTIONAL-WORLD-TEST] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, tostring(err))
    end
    engine:Exit()
end
