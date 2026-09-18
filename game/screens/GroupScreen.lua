-- ============================================================================
-- GroupScreen.lua - 独立集团中心
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local GroupDashboard = require("GroupDashboard")

local M = {}

function M.Create(navigate)
    local companies = GD.GetCompanyPortfolioSummary and GD.GetCompanyPortfolioSummary() or {}
    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 14,
        children = {
            C.SectionTitle {text = "集团中心", color = T.Accent},
            UI.Label {
                text = "集中管理集团成员、集团资本、总部高管、产业布局、股权和年度分红。",
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                whiteSpace = "normal",
                maxLines = 3,
            },
            GroupDashboard.Build(navigate, companies, "group"),
            UI.Panel {height = 20},
        },
    }
end

return M
