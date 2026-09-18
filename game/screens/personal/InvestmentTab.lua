---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- InvestmentTab.lua - 个人理财产品页（可由 PersonalScreen 直接接入）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local InvestmentService = require("personal/InvestmentService")

local M = {}

-- 重建个人页面时保留编辑中的金额；不写入存档，避免未提交输入影响财务数据。
M._state = {
    strategyAmount = "",
    productAmounts = {},
}

local RISK_LABELS = {
    low = "低风险",
    medium = "中风险",
    high = "高风险",
}

local RISK_COLORS = {
    low = T.Success,
    medium = T.Warning,
    high = T.Danger,
}

local RECORD_LABELS = {
    buy = "买入",
    redeem = "赎回申请",
    settlement = "赎回到账",
    ["return"] = "产品收益",
    annual_topup = "年度收益补足",
    legacy = "历史交易",
}

local RECORD_COLORS = {
    buy = T.Info,
    redeem = T.Warning,
    settlement = T.Success,
    ["return"] = T.Success,
    annual_topup = T.Success,
    legacy = T.TextSecondary,
}

local function pct(value)
    return string.format("%.1f%%", math.max(0, tonumber(value) or 0) * 100)
end

local function money(value)
    return C.FormatMoney(tonumber(value) or 0)
end

local function period(year, month)
    return string.format("%d年%d月", tonumber(year) or 0, tonumber(month) or 0)
end

local function serialPeriod(serial)
    serial = tonumber(serial) or 0
    if serial <= 0 then return "待定" end
    local year = math.floor((serial - 1) / 12)
    local month = serial - year * 12
    return period(year, month)
end

local function addFeedback(navigate, ok, successMessage, failureMessage)
    GD.AddEvent(ok and successMessage or failureMessage, ok and "success" or "warning")
    navigate("personal")
end

local function numericInput(value)
    local amount = tonumber(value or "")
    if not amount or amount <= 0 then return nil end
    return math.floor(amount * 100) / 100
end

local function actionButton(props)
    return C.ActionButton {
        text = props.text,
        width = props.width,
        height = props.height or 34,
        bgColor = props.bgColor,
        fontColor = props.fontColor,
        disabled = props.disabled,
        onClick = props.onClick,
    }
end

local function productCard(navigate, product)
    local locked = (product.lockMonths or 0) > 0
    local amountKey = product.id
    local held = product.amount or 0
    local lockText = locked and ("锁定剩余 " .. product.lockMonths .. " 月") or "可赎回"
    local liquidityText = (product.liquidityMonths or 0) <= 0
        and "即时到账"
        or (product.liquidityMonths .. "个月后到账")

    local function buyCustom()
        local amount = numericInput(M._state.productAmounts[amountKey])
        if not amount then
            GD.AddEvent("请输入有效买入金额", "warning")
            navigate("personal")
            return
        end
        local ok, result = InvestmentService.Buy(GD, product.id, amount)
        if ok then M._state.productAmounts[amountKey] = "" end
        addFeedback(navigate, ok,
            product.name .. "买入 " .. money(amount) .. " 成功",
            type(result) == "string" and result or "买入失败")
    end

    local function redeem(amount, all)
        local ok, result = InvestmentService.Redeem(GD, product.id, amount)
        local successText = result and result.pending
            and (product.name .. "赎回 " .. money(amount) .. " 已申请，预计" .. (result.dueMonth or 0) .. "个月后到账")
            or (product.name .. (all and "全部赎回" or "赎回") .. " " .. money(amount) .. " 已到账")
        addFeedback(navigate, ok, successText, type(result) == "string" and result or "赎回失败")
    end

    local buyDisabled = false
    local redeemDisabled = held <= 0 or locked
    return C.Card {children = {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {gap = 2, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, children = {
                    UI.Label {text = product.name, fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold", flexShrink = 1, minWidth = 0, maxLines = 1},
                    UI.Label {text = product.desc or "", fontSize = T.FontCaption, fontColor = T.TextMuted, maxLines = 2, flexShrink = 1, minWidth = 0, whiteSpace = "normal"},
                }},
                C.Badge {text = RISK_LABELS[product.riskTier] or "未知风险", variant = product.riskTier == "low" and "success" or (product.riskTier == "medium" and "warning" or "danger")},
            },
        },
        C.InfoRow {label = "目标年化", value = pct(product.targetRate) .. "（硬限1%~3%）", color = T.Accent},
        C.InfoRow {label = "预测年化", value = pct(product.projectedAnnualRate) .. "（硬限1%~3%）", color = T.Info},
        C.InfoRow {label = "当前持仓", value = money(held), color = held > 0 and T.Accent or T.TextMuted},
        C.InfoRow {label = "今年收益", value = money(product.yearlyReturn), color = (product.yearlyReturn or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "最低买入", value = money(product.minAmount), color = T.TextSecondary},
        C.InfoRow {label = "流动性", value = liquidityText, color = (product.liquidityMonths or 0) <= 0 and T.Success or T.Warning},
        C.InfoRow {label = "锁定月数", value = lockText, color = locked and T.Danger or T.TextSecondary},
        UI.Panel {width = "100%", flexDirection = "row", gap = 8, alignItems = "center", flexWrap = "wrap", children = {
            UI.TextField {
                placeholder = "自定义金额（万）",
                flexGrow = 1,
                flexBasis = 140,
                minWidth = 0,
                value = M._state.productAmounts[amountKey] or "",
                onChange = function(_, text) M._state.productAmounts[amountKey] = text end,
            },
            actionButton {text = "买入", disabled = buyDisabled, onClick = buyCustom},
        }},
        UI.Panel {width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap", children = {
            actionButton {
                text = locked and "锁定中" or "赎回",
                bgColor = locked and T.DisabledBg or T.Warning,
                fontColor = locked and T.TextMuted or T.TextOnDark,
                disabled = redeemDisabled,
                onClick = function() redeem(math.min(held, math.max(product.minAmount or 0, held * 0.25)), false) end,
            },
            actionButton {
                text = locked and "锁定中" or "全额赎回",
                bgColor = locked and T.DisabledBg or T.Danger,
                fontColor = locked and T.TextMuted or T.TextOnDark,
                disabled = redeemDisabled,
                onClick = function() redeem(held, true) end,
            },
        }},
    }}
end

local function strategySection(navigate, summary)
    local selectedId = summary.strategyId or "balanced"
    local buttons = {}
    for _, strategyId in ipairs({"conservative", "balanced", "growth"}) do
        local strategy = InvestmentService.STRATEGIES[strategyId]
        local isSelected = selectedId == strategyId
        buttons[#buttons + 1] = actionButton {
            text = strategy.name,
            bgColor = isSelected and T.Primary or T.BgCard,
            fontColor = isSelected and T.TextOnPrimary or T.TextSecondary,
            onClick = function()
                local ok, result = InvestmentService.SetStrategy(GD, strategyId)
                addFeedback(navigate, ok, "已切换至" .. strategy.name .. "策略", type(result) == "string" and result or "策略切换失败")
            end,
        }
    end

    local active = InvestmentService.STRATEGIES[selectedId] or InvestmentService.STRATEGIES.balanced
    local weights = {}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local product = InvestmentService.PRODUCTS[pid]
        weights[#weights + 1] = product.name .. " " .. pct(active.weights[pid])
    end

    local function executeStrategy()
        local amount = numericInput(M._state.strategyAmount)
        if not amount then
            GD.AddEvent("请输入有效策略金额", "warning")
            navigate("personal")
            return
        end
        local ok, result = InvestmentService.ExecuteStrategy(GD, amount)
        if ok then M._state.strategyAmount = "" end
        local invested = type(result) == "table" and result.invested or 0
        addFeedback(navigate, ok,
            active.name .. "策略已买入 " .. money(invested),
            type(result) == "string" and result or "策略买入失败")
    end

    return C.Card {children = {
        C.SectionTitle {text = "策略配置", color = T.Accent},
        UI.Label {text = "选择策略后可按比例批量买入；小于产品最低门槛的零钱将留在现金。", fontSize = T.FontCaption, fontColor = T.TextMuted},
        UI.Panel {width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap", children = buttons},
        UI.Label {text = "当前比例：" .. table.concat(weights, " / "), fontSize = T.FontCaption, fontColor = T.TextSecondary, maxLines = 3},
        UI.Panel {width = "100%", flexDirection = "row", gap = 8, alignItems = "center", flexWrap = "wrap", children = {
            UI.TextField {
                placeholder = "策略金额（万）",
                width = 160,
                value = M._state.strategyAmount or "",
                onChange = function(_, text) M._state.strategyAmount = text end,
            },
            actionButton {text = "按策略买入", onClick = executeStrategy},
            actionButton {
                text = "一键再平衡", bgColor = T.Info,
                onClick = function()
                    local ok, result = InvestmentService.Rebalance(GD)
                    local pending = type(result) == "table" and result.pendingCash or 0
                    addFeedback(navigate, ok,
                        "再平衡已执行" .. (pending > 0 and "，" .. money(pending) .. "待清算" or ""),
                        type(result) == "string" and result or "再平衡失败")
                end,
            },
        }},
    }}
end

local function pendingSection(state)
    local rows = {C.SectionTitle {text = "待清算赎回", color = T.Warning}}
    if #(state.pendingRedemptions or {}) == 0 then
        rows[#rows + 1] = UI.Label {text = "暂无待到账赎回。", fontSize = T.FontBody, fontColor = T.TextMuted}
    else
        for _, item in ipairs(state.pendingRedemptions) do
            local product = InvestmentService.PRODUCTS[item.productId]
            rows[#rows + 1] = C.InfoRow {
                label = (product and product.name or item.productId) .. " · " .. serialPeriod(item.dueSerial) .. "到账",
                value = money(item.amount), color = T.Warning,
            }
        end
    end
    return C.Card {children = rows}
end

local function reportSection(report)
    local rows = {C.SectionTitle {text = "年度报告", color = T.Info}}
    local current = report.current
    if current then
        rows[#rows + 1] = C.InfoRow {label = (current.year or 0) .. "年本金", value = money(current.totalPrincipal), color = T.TextPrimary}
        rows[#rows + 1] = C.InfoRow {label = "本年产品收益", value = money(current.totalReturn), color = (current.totalReturn or 0) >= 0 and T.Success or T.Danger}
        rows[#rows + 1] = C.InfoRow {label = "实时年化", value = pct(current.actualRate) .. "（年度结算钳制1%~3%）", color = T.Accent}
    end
    local history = report.history or {}
    if #history > 0 then
        local latest = history[#history]
        rows[#rows + 1] = UI.Panel {width = "100%", height = 1, backgroundColor = T.Border}
        rows[#rows + 1] = C.InfoRow {label = "最近已结算 " .. (latest.year or 0) .. " 年", value = money(latest.totalReturn), color = T.Success}
        rows[#rows + 1] = C.InfoRow {label = "结算年化", value = pct(latest.actualRate), color = T.Info}
    end
    return C.Card {children = rows}
end

local function transactionSection(transactions)
    local rows = {C.SectionTitle {text = "最近交易 / 收益 / 到账流水", color = T.TextSecondary}}
    local limit = math.min(12, #transactions)
    if limit == 0 then
        rows[#rows + 1] = UI.Label {text = "暂无产品流水。", fontSize = T.FontBody, fontColor = T.TextMuted}
    end
    for index = 1, limit do
        local record = transactions[index]
        local product = InvestmentService.PRODUCTS[record.productId]
        local kind = record.kind or "legacy"
        rows[#rows + 1] = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", paddingVertical = 3,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 1, children = {
                    UI.Label {text = (RECORD_LABELS[kind] or kind) .. " · " .. (product and product.name or record.productId or "理财产品"), fontSize = T.FontCaption, fontColor = RECORD_COLORS[kind] or T.TextSecondary},
                    UI.Label {text = period(record.year, record.month), fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Label {text = money(record.amount), fontSize = T.FontCaption, fontColor = RECORD_COLORS[kind] or T.TextPrimary},
            },
        }
    end
    return C.Card {children = rows}
end

--- 创建个人理财产品页面。
---@param navigate fun(screenId: string)
---@return table
function M.Create(navigate)
    local player = GD.player
    if not player then
        return C.Card {children = {
            C.SectionTitle {text = "个人理财", color = T.Warning},
            UI.Label {text = "个人档案尚未初始化。", fontSize = T.FontBody, fontColor = T.TextMuted},
        }}
    end

    local state = InvestmentService.Ensure(player)
    local summary = InvestmentService.GetSummary(GD)
    local detail = InvestmentService.GetDetail(GD)
    local diversification = detail.diversification or InvestmentService.GetDiversification(GD)
    local report = InvestmentService.GetAnnualReport(GD)
    local productCards = {}
    for _, product in ipairs(detail.products or {}) do
        productCards[#productCards + 1] = productCard(navigate, product)
    end

    local tierWeights = diversification.tierWeights or {low = 0, medium = 0, high = 0}
    local concentrationProduct = InvestmentService.PRODUCTS[diversification.topProduct]
    local concentrationName = concentrationProduct and concentrationProduct.name or "暂无"

    return UI.Panel {width = "100%", gap = 12, children = {
        UI.Panel {width = "100%", flexDirection = "row", gap = 10, flexWrap = "wrap", children = {
            C.StatCard {title = "可用现金", value = money(summary.availableCash), color = T.Success, minWidth = 100},
            C.StatCard {title = "持仓总额", value = money(summary.total), color = T.Accent, minWidth = 100},
            C.StatCard {title = "待到账", value = money(summary.pendingRedemptions), color = T.Warning, minWidth = 100},
            C.StatCard {title = "今年产品收益", value = money(summary.yearlyProductReturn), color = (summary.yearlyProductReturn or 0) >= 0 and T.Success or T.Danger, minWidth = 110},
            C.StatCard {title = "累计产品收益", value = money(summary.totalProductReturn), color = (summary.totalProductReturn or 0) >= 0 and T.Success or T.Danger, minWidth = 110},
        }},
        C.Card {children = {
            C.SectionTitle {text = "收益规则", color = T.Warning},
            UI.Label {text = "所有个人理财产品的目标年化、预测年化与年度结算收益均受 1%~3% 硬限制；不会以更高收益换取隐藏风险。", fontSize = T.FontBody, fontColor = T.TextPrimary, maxLines = 3},
        }},
        C.Card {children = {
            C.SectionTitle {text = "组合健康度", color = T.Info},
            C.InfoRow {label = "组合评分", value = (diversification.score or 0) .. " 分 · " .. (diversification.level or "无持仓"), color = T.Accent},
            C.InfoRow {label = "低风险比例", value = pct(tierWeights.low), color = RISK_COLORS.low},
            C.InfoRow {label = "中风险比例", value = pct(tierWeights.medium), color = RISK_COLORS.medium},
            C.InfoRow {label = "高风险比例", value = pct(tierWeights.high), color = RISK_COLORS.high},
            C.InfoRow {label = "最大集中度", value = pct(diversification.concentration) .. " · " .. concentrationName, color = (diversification.concentration or 0) > 0.6 and T.Warning or T.Success},
        }},
        strategySection(navigate, summary),
        C.SectionTitle {text = "8 类理财产品", color = T.Accent},
        UI.Panel {width = "100%", gap = 10, children = productCards},
        pendingSection(state),
        reportSection(report),
        transactionSection(InvestmentService.GetTransactions(GD)),
    }}
end

return M
