---@diagnostic disable: param-type-mismatch, assign-type-mismatch
-- ============================================================================
-- CityResearchPanel.lua - 城市详情中的投资、金融与代建研究面板
-- 负责跨标签状态、城市头部、标签导航与各子系统调度。
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local InvestmentTabs = require("screens/CityResearchInvestmentTabs")
local FinancialTab = require("screens/CityResearchFinancialTab")
local BOTTab = require("screens/CityResearchBOTTab")

local M = {}

-- Keep city research UI state independent from InvestScreen so old investment tabs
-- cannot affect city research after navigation.
M._citySubTab = M._citySubTab or 1
M._cityBankTab = M._cityBankTab or 1
M._creditDepositInput = M._creditDepositInput or ""
M._creditLoanInput = M._creditLoanInput or ""
M._bankInjectInput = M._bankInjectInput or ""
M._expandSections = M._expandSections or {}

local FOLD_LIMIT = 3

local function appendFoldButton(rows, totalCount, sectionKey, navigate)
    if totalCount > FOLD_LIMIT then
        local isExpanded = M._expandSections[sectionKey]
        local hiddenCount = totalCount - FOLD_LIMIT
        table.insert(rows, UI.Button {
            text = isExpanded and "▲ 收起" or ("▼ 展开全部 " .. totalCount .. " 条（还有" .. hiddenCount .. "条）"),
            fontSize = T.FontCaption, fontColor = T.Primary,
            backgroundColor = T.Transparent, height = 28, width = "100%",
            onClick = function()
                M._expandSections[sectionKey] = not isExpanded
                navigate("city")
            end,
        })
    end
end

local function shouldShowItem(idx, sectionKey)
    if idx <= FOLD_LIMIT then return true end
    return M._expandSections[sectionKey] == true
end

function M.Build(city, navigate)
    local subTab = M._citySubTab or 1
    local subTabNames = {"投资", "地方债券", "赞助", "城市信用合作社", "投资代建"}
    local cityName = city.name
    local function FM(v) return C.FormatMoney(v or 0) end

    local hasActiveCompany = GD.HasActiveOperatingCompany and GD.HasActiveOperatingCompany()
    local isHome = hasActiveCompany and GD.company and city.name == GD.company.city
    local supplyMetrics = GD.GetCityLandSupplyMetrics and GD.GetCityLandSupplyMetrics(city) or {}
    local supplyPlan = GD.GetCityLandSupplyPlan and GD.GetCityLandSupplyPlan(city) or nil
    local supplyText = "待发布"
    if supplyPlan then
        if supplyPlan.status == "planned" then
            supplyText = "计划" .. tostring(supplyPlan.plannedCount or 0) .. "宗，" .. tostring(math.max(0, (supplyPlan.releaseMonth or 0) - (GD.totalMonths or 0))) .. "个月后拍卖"
        elseif supplyPlan.status == "released" then
            supplyText = "已释放" .. tostring(supplyPlan.releasedCount or 0) .. "宗"
        end
    end
    local scoreColor = city.potential > 80 and T.Success or (city.potential > 60 and T.Accent or T.Warning)
    local cityHeader = UI.Panel {
        width = "100%", padding = 12, gap = 8,
        backgroundColor = isHome and T.PrimaryDark or T.BgCard,
        borderRadius = T.CardRadius,
        borderWidth = isHome and 1 or 0, borderColor = T.Accent,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = {
                        UI.Label {text = city.name, fontSize = T.FontTitle, fontColor = T.TextPrimary},
                        isHome and C.Badge {text = "本部", variant = "info"} or UI.Panel {width = 0, height = 0},
                        C.Badge {text = "T" .. (city.tier or 1) .. "城市", variant = "warning"},
                    }},
                    UI.Panel {alignItems = "flex-end", gap = 2, children = {
                        UI.Label {text = "综合潜力 " .. city.potential .. "分", fontSize = T.FontBody, fontColor = scoreColor},
                        UI.Label {text = "均价 " .. city.avgPrice .. " 元/㎡", fontSize = T.FontSmall, fontColor = T.Accent},
                    }},
                },
            },
            UI.Panel {
                flexDirection = "row", gap = 12, flexWrap = "wrap", width = "100%",
                children = {
                    C.InfoRow {label = "GDP", value = city.gdp .. "亿"},
                    C.InfoRow {label = "人口", value = city.population .. "万"},
                    C.InfoRow {label = "增长率", value = math.floor(city.growth * 100) .. "%"},
                    C.InfoRow {label = "库存", value = city.inventory .. "月"},
                    C.InfoRow {label = "基础设施承载", value = tostring(supplyMetrics.infrastructureCapacity or 0) .. "万"},
                    C.InfoRow {label = "供地计划", value = supplyText},
                    C.InfoRow {label = "竞争强度", value = math.floor(city.compete * 100) .. "%"},
                    C.InfoRow {label = "政策", value = city.policy},
                },
            },
        },
    }

    local tabBtns = {}
    for i, name in ipairs(subTabNames) do
        local capturedI = i
        table.insert(tabBtns, UI.Button {
            text = name,
            fontSize = T.FontSmall,
            backgroundColor = subTab == capturedI and T.PrimaryLight or T.TabInactiveBg,
            fontColor = subTab == capturedI and T.Primary or T.TabInactiveFont,
            borderRadius = 4,
            paddingHorizontal = 10, height = 28,
            onClick = function()
                M._citySubTab = capturedI
                navigate("city")
            end,
        })
    end
    local tabBar = UI.Panel {
        flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%",
        children = tabBtns,
    }

    local context = {
        city = city,
        cityName = cityName,
        navigate = navigate,
        FM = FM,
        state = M,
        appendFoldButton = appendFoldButton,
        shouldShowItem = shouldShowItem,
    }
    local subContent
    if not hasActiveCompany then
        subContent = C.Card {children = {
            C.SectionTitle {text = "成立公司后解锁城市经营", color = T.Warning},
            UI.Label {
                text = "城市基础数据可直接查看；投资、地方债券、赞助、信用合作社和投资代建需要先在任一城市成立地产公司。",
                fontSize = T.FontSmall,
                fontColor = T.TextMuted,
            },
        }}
    elseif subTab == 1 then
        subContent = InvestmentTabs.BuildInvest(context)
    elseif subTab == 2 then
        subContent = InvestmentTabs.BuildBond(context)
    elseif subTab == 3 then
        subContent = InvestmentTabs.BuildSponsor(context)
    elseif subTab == 4 then
        subContent = FinancialTab.Build(context)
    elseif subTab == 5 then
        subContent = BOTTab.Build(context)
    else
        subContent = InvestmentTabs.BuildInvest(context)
    end

    return UI.Panel {
        width = "100%", gap = 10,
        children = {cityHeader, tabBar, subContent},
    }
end

return M
