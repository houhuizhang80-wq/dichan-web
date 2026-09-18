-- ============================================================================
-- CityScreen.lua - 城市入口：先进入城市，再查看/操作本城市公司
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local CityResearchPanel = require("screens/CityResearchPanel")

local M = {}
M._selectedCity = M._selectedCity or nil

function M.SetSelectedCity(cityName)
    M._selectedCity = cityName
end

function M.GetSelectedCity()
    return M._selectedCity
end

function M.SetDetailTab(tabId)
    M._cityDetailTab = tabId
end

local companyActionTabs = {
    {id = "invest", label = "投资拿地", desc = "土地市场、储备开发、投资测算"},
    {id = "project", label = "项目开发", desc = "设计、工程、结算、竣工"},
    {id = "sales", label = "营销销售", desc = "定价、销售、清盘"},
    {id = "asset", label = "资产运营", desc = "自持物业、固定资产、出租"},
    {id = "capital", label = "资本融资", desc = "贷款、融资、抵押"},
    {id = "governance", label = "公司治理", desc = "股权、高管、自动经营"},
    {id = "ledger", label = "收支明细", desc = "月度账单与现金流"},
}

local function getCityCompanyRecords(cityName)
    local result = {}
    local portfolio = GD.GetCompanyPortfolioSummary and GD.GetCompanyPortfolioSummary() or {}
    for _, rec in ipairs(portfolio) do
        if rec.city == cityName then
            table.insert(result, rec)
        end
    end
    return result
end

local function getOperatingCompanyInCity(cityName)
    local records = getCityCompanyRecords(cityName)
    for _, rec in ipairs(records) do
        if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 then return rec end
    end
    return nil
end

local function openCompanyCreate(cityName, navigate)
    local existing = getOperatingCompanyInCity(cityName)
    if existing then
        GD.AddEvent(cityName .. "已有正在经营的地产公司“" .. (existing.name or "未命名公司") .. "”，每个城市最多成立一家", "warning")
        M._selectedCity = cityName
        M._cityDetailTab = "companies"
        navigate("city")
        return
    end
    M._selectedCity = cityName
    local CompanyCreateScreen = require("screens/CompanyCreateScreen")
    if CompanyCreateScreen.SetPresetCity then CompanyCreateScreen.SetPresetCity(cityName) end
    navigate("companyCreate")
end

local function switchCompanyAndGo(rec, screenId, navigate)
    if not rec or rec.status ~= "operating" or (rec.founderRatio or 0) < 0.50 then
        GD.AddEvent("该公司控制权不足50%，仅保留分红权，不能进入公司功能", "warning")
        navigate("city")
        return
    end
    local ok, msg = GD.SwitchCompany(rec.id)
    GD.AddEvent(msg or (ok and "已进入公司" or "公司切换失败"), ok and "success" or "warning")
    if ok then navigate(screenId) else navigate("city") end
end

local function buildCityCard(city, navigate)
    local cityCompanies = getCityCompanyRecords(city.name)
    local operatingCount, totalAssets, totalCash, totalDebt, projectCount = 0, 0, 0, 0, 0
    for _, rec in ipairs(cityCompanies) do
        if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 then operatingCount = operatingCount + 1 end
        totalAssets = totalAssets + (rec.totalAssets or 0)
        totalCash = totalCash + (rec.cash or 0)
        totalDebt = totalDebt + (rec.totalDebt or 0)
        projectCount = projectCount + (rec.projectCount or 0)
    end

    return C.Card {children = {
        UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            justifyContent = "space-between",
            alignItems = "flex-start",
            gap = 8,
            width = "100%",
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexBasis = 0,
                    flexShrink = 1,
                    minWidth = 0,
                    gap = 2,
                    children = {
                        UI.Label {text = city.name, fontSize = T.FontSubtitle, fontColor = T.Accent, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                        UI.Label {text = "均价" .. (city.avgPrice or 0) .. "元/㎡ | 潜力" .. (city.potential or 0), fontSize = T.FontCaption, fontColor = T.TextMuted, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                    },
                },
                C.Badge {text = operatingCount .. "家公司", variant = operatingCount > 0 and "success" or "info"},
            },
        },
        C.InfoRow {label = "本城公司总资产", value = C.FormatMoney(totalAssets), color = T.Accent},
        C.InfoRow {label = "现金/负债", value = C.FormatMoney(totalCash) .. " / " .. C.FormatMoney(totalDebt), color = totalDebt > 0 and T.Warning or T.Success},
        C.InfoRow {label = "项目数", value = tostring(projectCount), color = T.TextSecondary},
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "进入城市",
                width = "48%",
                onClick = function()
                    M._selectedCity = city.name
                    navigate("city")
                end,
            },
            C.SecondaryButton {
                text = operatingCount > 0 and "本城已有公司" or "在此成立公司",
                width = "48%",
                onClick = function() openCompanyCreate(city.name, navigate) end,
            },
        }},
    }}
end

local function buildCompanyCard(rec, navigate)
    local isActive = GD.activeCompanyId and tostring(GD.activeCompanyId) == tostring(rec.id)
    local statusText = "已退出"
    local statusVariant = "warning"
    if rec.status == "operating" then
        if (rec.founderRatio or 0) < 0.50 then
            statusText = "仅分红权"
            statusVariant = "warning"
        else
            statusText = isActive and "当前经营" or "可进入"
            statusVariant = isActive and "success" or "info"
        end
    elseif rec.status == "bankrupt" then
        statusText = "已破产"
        statusVariant = "danger"
    elseif rec.status == "sold" then
        statusText = "已出售"
        statusVariant = "warning"
    end

    local actionButtons = {}
    if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 then
        for _, action in ipairs(companyActionTabs) do
            table.insert(actionButtons, C.SecondaryButton {
                text = action.label,
                width = "48%",
                height = 34,
                onClick = function() switchCompanyAndGo(rec, action.id, navigate) end,
            })
        end
    else
        table.insert(actionButtons, UI.Label {
            text = (rec.founderRatio or 0) > 0
                and "个人持股低于50%，仅保留分红权，不能进入公司操作。"
                or "该公司已退出，仅保留历史记录。",
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
            whiteSpace = "normal",
            maxLines = 2,
        })
    end

    return C.Card {children = {
        UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            justifyContent = "space-between",
            alignItems = "flex-start",
            gap = 8,
            width = "100%",
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexBasis = 0,
                    flexShrink = 1,
                    minWidth = 0,
                    gap = 2,
                    children = {
                        UI.Label {text = rec.name or "未命名公司", fontSize = T.FontSubtitle, fontColor = T.TextPrimary, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                        UI.Label {text = (rec.createdYear or GD.year) .. "年创办 | 持股" .. string.format("%.1f%%", (rec.founderRatio or 0) * 100), fontSize = T.FontCaption, fontColor = T.TextMuted, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                    },
                },
                C.Badge {text = statusText, variant = statusVariant},
            },
        },
        C.InfoRow {label = "现金", value = C.FormatMoney(rec.cash or 0), color = (rec.cash or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "总资产/负债", value = C.FormatMoney(rec.totalAssets or 0) .. " / " .. C.FormatMoney(rec.totalDebt or 0), color = T.Info},
        C.InfoRow {label = "月利润", value = C.FormatMoney(rec.monthlyProfit or 0), color = (rec.monthlyProfit or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "项目数", value = tostring(rec.projectCount or 0), color = T.TextSecondary},
        UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = actionButtons},
    }}
end

function M.Create(navigate)
    local selectedCity = M._selectedCity
    if selectedCity then
        local cityData = nil
        for _, city in ipairs(GD.cities or {}) do
            if city.name == selectedCity then cityData = city; break end
        end
        if not cityData then M._selectedCity = nil; return M.Create(navigate) end

        local cityDetailTab = M._cityDetailTab or "research"
        local detailTabNames = {"城市研究", "本城公司"}
        local detailTabButtons = {}
        for i, label in ipairs(detailTabNames) do
            local tabId = i == 1 and "research" or "companies"
            table.insert(detailTabButtons, UI.Button {
                text = label,
                fontSize = T.FontSmall,
                backgroundColor = cityDetailTab == tabId and T.PrimaryLight or T.TabInactiveBg,
                fontColor = cityDetailTab == tabId and T.Primary or T.TabInactiveFont,
                paddingHorizontal = 12,
                height = 30,
                onClick = function()
                    M._cityDetailTab = tabId
                    navigate("city")
                end,
            })
        end

        local children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "flex-start",
                gap = 8,
                width = "100%",
                flexWrap = "wrap",
                children = {
                    C.SecondaryButton {text = "返回城市列表", height = 30, paddingH = 10, onClick = function()
                        M._selectedCity = nil
                        M._cityDetailTab = "research"
                        navigate("city")
                    end},
                    C.SectionTitle {
                        text = selectedCity .. "城市中心",
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        minWidth = 0,
                    },
                },
            },
            C.Card {children = {
                C.InfoRow {label = "城市均价", value = tostring(cityData.avgPrice or 0) .. "元/㎡", color = T.Accent},
                C.InfoRow {label = "政策", value = cityData.policy or "", color = T.Info},
                C.InfoRow {label = "库存周期", value = tostring(cityData.inventory or 0) .. "个月", color = T.Warning},
                C.ActionButton {
                    text = getOperatingCompanyInCity(selectedCity) and (selectedCity .. "已有地产公司") or ("在" .. selectedCity .. "成立新公司"),
                    width = "100%",
                    onClick = function() openCompanyCreate(selectedCity, navigate) end,
                },
            }},
            UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = detailTabButtons},
        }

        if cityDetailTab == "research" then
            table.insert(children, CityResearchPanel.Build(cityData, navigate))
        else
            table.insert(children, C.SectionTitle {text = "本城公司"})
            local companies = getCityCompanyRecords(selectedCity)
            if #companies == 0 then
                table.insert(children, C.Card {children = {
                    C.SectionTitle {text = "本城暂无公司", color = T.Warning},
                    UI.Label {text = "公司只能在注册城市开发项目。请先在本城市成立公司，再进入公司操作投资、项目、销售、资产和治理功能。", fontSize = T.FontSmall, fontColor = T.TextMuted},
                }})
            else
                for _, rec in ipairs(companies) do table.insert(children, buildCompanyCard(rec, navigate)) end
            end
        end

        return UI.ScrollView {id = "screenScrollView", width = "100%", height = "100%", scrollY = true, padding = T.PagePadding, gap = 12, children = children}
    end

    local children = {C.SectionTitle {text = "城市中心"}}
    table.insert(children, C.Card {children = {
        UI.Label {text = "先进入城市，再查看该城市下的公司。公司只能在注册城市内拿地和开发项目，跨城市需在对应城市另设公司。", fontSize = T.FontSmall, fontColor = T.TextSecondary},
    }})
    for _, city in ipairs(GD.cities or {}) do table.insert(children, buildCityCard(city, navigate)) end
    table.insert(children, UI.Panel {height = 20})
    return UI.ScrollView {id = "screenScrollView", width = "100%", height = "100%", scrollY = true, padding = T.PagePadding, gap = 12, children = children}
end

return M
