-- ============================================================================
-- CompanySelector.lua - 可复用的公司上下文切换器
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

--- 构建当前页面可用的公司选择器。
--- @param options table {navigate=function, returnScreen=string, onSwitched=function|nil, description=string|nil}
--- @return table UI元素
function M.Build(options)
    options = options or {}
    local navigate = options.navigate
    local returnScreen = options.returnScreen or "dashboard"
    local onSwitched = options.onSwitched
    local description = options.description or "所有融资、治理和资产操作仅作用于当前选中的公司。"
    local companies = GD.GetCompanyPortfolioSummary and GD.GetCompanyPortfolioSummary() or {}
    local eligible = {}

    for _, rec in ipairs(companies) do
        if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 then
            table.insert(eligible, rec)
        end
    end

    local currentName = (GD.company and GD.company.name) or "未选择公司"
    local children = {
        C.SectionTitle {text = "当前操作公司：" .. currentName},
        UI.Label {
            text = description,
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
        },
    }

    if #eligible == 0 then
        table.insert(children, UI.Label {
            text = "暂无可经营公司，请先在城市中心成立公司。",
            fontSize = T.FontSmall,
            fontColor = T.Warning,
        })
        return C.Card {children = children}
    end

    for _, rec in ipairs(eligible) do
        local isCurrent = GD.activeCompanyId and tostring(GD.activeCompanyId) == tostring(rec.id)
        local capturedRec = rec
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            padding = 8,
            backgroundColor = isCurrent and T.PrimaryLight or T.Surface,
            borderWidth = T.DividerWidth,
            borderColor = isCurrent and T.PrimaryBorder or T.Border,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexBasis = 0,
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = capturedRec.name or "未命名公司",
                            fontSize = T.FontSmall,
                            fontColor = isCurrent and T.Primary or T.TextPrimary,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = (capturedRec.city or "未登记城市") .. " | 持股" .. string.format("%.1f%%", (capturedRec.founderRatio or 0) * 100),
                            fontSize = T.FontCaption,
                            fontColor = T.TextSecondary,
                        },
                    },
                },
                isCurrent and C.Badge {text = "当前", variant = "success"} or C.SecondaryButton {
                    text = "切换",
                    height = 32,
                    paddingH = 10,
                    onClick = function()
                        local ok, msg = GD.SwitchCompany(capturedRec.id)
                        if ok then
                            if onSwitched then onSwitched() end
                            GD.AddEvent(msg or ("已切换到" .. (capturedRec.name or "该公司")), "success")
                            if navigate then navigate(returnScreen) end
                        else
                            GD.AddEvent(msg or "公司切换失败", "warning")
                            if navigate then navigate(returnScreen) end
                        end
                    end,
                },
            },
        })
    end

    return C.Card {children = children}
end

return M
