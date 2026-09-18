-- ============================================================================
-- DashboardScreen.lua - 公司组合总览
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

local function getStatus(rec)
    if rec.status == "operating" then
        if (rec.founderRatio or 0) < 0.50 then
            return "仅分红权", "warning"
        end
        local isCurrent = GD.activeCompanyId and tostring(GD.activeCompanyId) == tostring(rec.id)
        return isCurrent and "当前经营" or "经营中", isCurrent and "success" or "info"
    end
    if rec.status == "bankrupt" then return "已破产", "danger" end
    if rec.status == "sold" then return "已出售", "warning" end
    return "已退出", "warning"
end

local function buildCompanyCard(rec, navigate)
    local statusText, statusVariant = getStatus(rec)
    local isOperating = rec.status == "operating" and (rec.founderRatio or 0) >= 0.50
    local ownershipLabel = "个人持股"
    if GD.GroupSystem then
        ownershipLabel = GD.GroupSystem.GetCompanyOwnershipLabel(GD, rec.id)
    end
    local children = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            justifyContent = "space-between",
            alignItems = "flex-start",
            gap = 8,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexBasis = 0,
                    flexShrink = 1,
                    minWidth = 0,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = rec.name or "未命名公司",
                            fontSize = T.FontSubtitle,
                            fontColor = T.TextPrimary,
                            flexShrink = 1,
                            minWidth = 0,
                            whiteSpace = "normal",
                            maxLines = 2,
                            verticalAlign = "top",
                        },
                        UI.Label {
                            text = rec.city or "未登记城市",
                            fontSize = T.FontCaption,
                            fontColor = T.TextMuted,
                            flexShrink = 1,
                            minWidth = 0,
                            whiteSpace = "normal",
                            maxLines = 2,
                            verticalAlign = "top",
                        },
                    },
                },
                C.Badge {text = statusText, variant = statusVariant},
            },
        },
        C.InfoRow {label = "公司现金", value = C.FormatMoney(rec.cash or 0), color = (rec.cash or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "公司负债", value = C.FormatMoney(rec.totalDebt or 0), color = (rec.totalDebt or 0) > 0 and T.Warning or T.Success},
        C.InfoRow {label = "资产总额", value = C.FormatMoney(rec.totalAssets or 0), color = T.Info},
        C.InfoRow {label = "月利润", value = C.FormatMoney(rec.monthlyProfit or 0), color = (rec.monthlyProfit or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = ownershipLabel, value = string.format("%.1f%%", (rec.founderRatio or 0) * 100), color = T.Accent},
    }

    if isOperating then
        local capturedRec = rec
        table.insert(children, C.ActionButton {
            text = "进入公司",
            width = "100%",
            onClick = function()
                local ok, msg = GD.SwitchCompany(capturedRec.id)
                if ok then
                    local CityScreen = require("screens/CityScreen")
                    CityScreen.SetSelectedCity(capturedRec.city)
                    CityScreen.SetDetailTab("companies")
                    GD.AddEvent(msg or ("已进入" .. (capturedRec.name or "该公司")), "success")
                    navigate("city")
                else
                    GD.AddEvent(msg or "公司切换失败", "warning")
                    navigate("dashboard")
                end
            end,
        })
    end

    return C.Card {children = children}
end

function M.Create(navigate)
    local companies = GD.GetCompanyPortfolioSummary and GD.GetCompanyPortfolioSummary() or {}
    local totalCash, totalAssets, totalDebt, totalProfit = 0, 0, 0, 0
    local operatingCount = 0

    for _, rec in ipairs(companies) do
        totalCash = totalCash + (rec.cash or 0)
        totalAssets = totalAssets + (rec.totalAssets or 0)
        totalDebt = totalDebt + (rec.totalDebt or 0)
        totalProfit = totalProfit + (rec.monthlyProfit or 0)
        if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 then
            operatingCount = operatingCount + 1
        end
    end

    local children = {
        C.SectionTitle {text = "公司组合总览"},
        C.Card {children = {
            UI.Label {
                text = "总览只汇总个人名下全部公司。需要开发项目、销售或管理单家公司时，请先进入对应城市的本城公司。",
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                whiteSpace = "normal",
                maxLines = 3,
                verticalAlign = "top",
            },
            C.ActionButton {text = "进入城市中心", width = "100%", onClick = function() navigate("city") end},
        }},
        UI.Panel {flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "成立公司", value = tostring(#companies) .. "家", color = T.Info},
            C.StatCard {title = "经营公司", value = tostring(operatingCount) .. "家", color = T.Accent},
            C.StatCard {title = "组合现金", value = C.FormatMoney(totalCash), color = T.Success},
        }},
        UI.Panel {flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "总资产", value = C.FormatMoney(totalAssets), color = T.Info},
            C.StatCard {title = "总负债", value = C.FormatMoney(totalDebt), color = totalDebt > 0 and T.Warning or T.Success},
            C.StatCard {title = "月利润", value = C.FormatMoney(totalProfit), color = totalProfit >= 0 and T.Success or T.Danger},
        }},
        C.SectionTitle {text = "公司列表"},
    }

    if #companies == 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "尚未成立公司", color = T.Warning},
            UI.Label {text = "请从城市中心选择城市并成立第一家地产公司。", fontSize = T.FontSmall, fontColor = T.TextMuted},
            C.ActionButton {text = "去城市中心", width = "100%", onClick = function() navigate("city") end},
        }})
    else
        for _, rec in ipairs(companies) do
            table.insert(children, buildCompanyCard(rec, navigate))
        end
    end

    table.insert(children, UI.Panel {height = 20})
    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 14,
        children = children,
    }
end

return M
