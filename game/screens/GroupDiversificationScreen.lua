-- ============================================================================
-- GroupDiversificationScreen.lua - 集团多元化产业经营中心
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}
M._activeSector = 1
M._expandedIndustryId = nil
M._manualInputs = {}

local function inputValue(industryId, key, fallback)
    local values = M._manualInputs[industryId]
    if not values then
        values = {}
        M._manualInputs[industryId] = values
    end
    if values[key] == nil then values[key] = fallback or "" end
    return values[key]
end

local function numericInput(industryId, key, fallback)
    return math.floor(tonumber(inputValue(industryId, key, fallback)) or 0)
end

local function refresh(navigate)
    navigate("groupDiversification")
end

local function actionResult(ok, message)
    GD.AddEvent(message or (ok and "集团产业操作成功" or "集团产业操作失败"), ok and "success" or "warning")
end

local function formatPercent(value)
    return string.format("%.1f%%", (value or 0) * 100)
end

local function riskVariant(def)
    if (def.riskRate or 0) >= 0.035 then return "danger", "高风险" end
    if (def.riskRate or 0) >= 0.022 then return "warning", "中风险" end
    return "success", "低风险"
end

local function buildRequirements(requirements)
    local rows = {}
    for _, req in ipairs(requirements or {}) do
        rows[#rows + 1] = C.InfoRow {
            label = req.label,
            value = req.text,
            color = req.met and T.Success or T.Warning,
        }
    end
    return rows
end

local function buildManualOperations(navigate, GDI, industryId, def, business)
    local GIO = GDI.Operations
    local summary = GIO.GetSummary(def, business)
    ---@type Widget[]
    local rows = {
        C.Badge {text = "手动经营公司", variant = "info"},
        C.InfoRow {label = "公司名称", value = summary.companyName},
        C.InfoRow {label = "公司现金 / 债务", value = C.FormatMoney(summary.companyCash) .. " / " .. C.FormatMoney(summary.companyDebt), color = summary.companyCash >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "留存收益 / 声誉", value = C.FormatMoney(summary.retainedEarnings) .. " / " .. string.format("%.0f/100", summary.reputation), color = summary.reputation >= 60 and T.Success or T.Warning},
        C.InfoRow {label = summary.teamName, value = tostring(summary.staffTeams) .. "支"},
        C.InfoRow {label = summary.capacityName, value = tostring(summary.capacity) .. "（利用率" .. formatPercent(summary.utilization or 0) .. "）"},
    }
    if summary.usesInventory then rows[#rows + 1] = C.InfoRow {label = summary.inventoryName, value = C.FormatMoney(summary.inventory)} end
    rows[#rows + 1] = C.InfoRow {label = "商机 / 执行中订单", value = tostring(summary.opportunities) .. " / " .. tostring(summary.activeOrders), color = T.Info}
    rows[#rows + 1] = UI.Label {text = summary.ready and "已满足接单条件" or summary.readyReason, fontSize = T.FontCaption, fontColor = summary.ready and T.Success or T.Warning, whiteSpace = "normal", maxLines = 3}
    rows[#rows + 1] = C.SectionTitle {text = "经营方案", color = T.Info}
    for _, category in ipairs({"market", "pricing", "quality", "capacity"}) do
        local buttons = {}
        for _, optionId in ipairs(GIO.PLAN_ORDER[category]) do
            local captured = optionId
            local option = GIO.PLAN_OPTIONS[category][optionId]
            buttons[#buttons + 1] = UI.Button {
                text = option.name, height = 34, flexGrow = 1,
                backgroundColor = business.plan[category] == optionId and T.Primary or T.Surface,
                fontColor = business.plan[category] == optionId and T.TextOnDark or T.TextSecondary,
                onClick = function()
                    local ok, message = GIO.SetPlan(GD, def, business, category, captured)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            }
        end
        rows[#rows + 1] = UI.Label {text = ({market = "市场", pricing = "定价", quality = "品质", capacity = "产能"})[category], fontSize = T.FontCaption, fontColor = T.TextMuted}
        rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 5, children = buttons}
    end
    rows[#rows + 1] = C.SectionTitle {text = "经营动作", color = T.Accent}
    rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = {
        C.SecondaryButton {text = "招聘团队", flexGrow = 1, onClick = function() local ok, message = GIO.AdjustStaff(GD, def, business, 1); actionResult(ok, message); refresh(navigate) end},
        C.SecondaryButton {text = "减员团队", flexGrow = 1, onClick = function() local ok, message = GIO.AdjustStaff(GD, def, business, -1); actionResult(ok, message); refresh(navigate) end},
        C.SecondaryButton {text = "扩建设施", flexGrow = 1, onClick = function() local ok, message = GIO.ExpandCapacity(GD, def, business); actionResult(ok, message); refresh(navigate) end},
    }}
    if summary.usesInventory then
        rows[#rows + 1] = UI.TextField {value = inputValue(industryId, "inventory", "100"), width = "100%", height = 38, keyboardType = "number", placeholder = "采购数量", onChange = function(_, value) M._manualInputs[industryId].inventory = value end}
        rows[#rows + 1] = C.SecondaryButton {text = "采购库存", width = "100%", onClick = function() local ok, message = GIO.ProcureInventory(GD, def, business, numericInput(industryId, "inventory", 100)); actionResult(ok, message); refresh(navigate) end}
    end
    rows[#rows + 1] = C.ActionButton {text = "开发市场并生成商机", width = "100%", onClick = function() local ok, message = GIO.DevelopMarket(GD, def, business); actionResult(ok, message); refresh(navigate) end}
    if #business.opportunities > 0 then
        rows[#rows + 1] = C.SectionTitle {text = "待决策商机", color = T.Info}
        for _, opportunity in ipairs(business.opportunities) do
            local captured = opportunity.id
            rows[#rows + 1] = C.Card {padding = 8, children = {
                UI.Label {text = opportunity.title .. " · " .. opportunity.client, fontSize = T.FontSmall, fontColor = T.TextPrimary, whiteSpace = "normal", maxLines = 2},
                C.InfoRow {label = "合同额 / 期限", value = C.FormatMoney(opportunity.contractValue) .. " / " .. tostring(opportunity.duration) .. "月"},
                UI.Panel {width = "100%", flexDirection = "row", gap = 6, children = {
                    C.ActionButton {text = "承接", flexGrow = 1, onClick = function() local ok, message = GIO.AcceptOpportunity(GD, def, business, captured); actionResult(ok, message); refresh(navigate) end},
                    C.SecondaryButton {text = "拒绝", flexGrow = 1, onClick = function() local ok, message = GIO.RejectOpportunity(GD, def, business, captured); actionResult(ok, message); refresh(navigate) end},
                }},
            }}
        end
    end
    if #business.orders > 0 then
        rows[#rows + 1] = C.SectionTitle {text = "执行中订单", color = T.Info}
        for _, order in ipairs(business.orders) do
            if order.status == "active" then rows[#rows + 1] = C.InfoRow {label = order.title, value = tostring(math.floor((order.progress or 0) * 100)) .. "% · " .. tostring(order.remainMonths or 0) .. "月"} end
        end
    end
    rows[#rows + 1] = C.SectionTitle {text = "集团资本安排", color = T.Warning}
    rows[#rows + 1] = UI.TextField {value = inputValue(industryId, "capital", "1000"), width = "100%", height = 38, keyboardType = "number", placeholder = "集团注资金额", onChange = function(_, value) M._manualInputs[industryId].capital = value end}
    rows[#rows + 1] = C.SecondaryButton {text = "集团手动注资", width = "100%", onClick = function() local ok, message = GIO.InjectCapital(GD, def, business, numericInput(industryId, "capital", 1000)); actionResult(ok, message); refresh(navigate) end}
    rows[#rows + 1] = UI.TextField {value = inputValue(industryId, "dividend", "100"), width = "100%", height = 38, keyboardType = "number", placeholder = "上缴集团分红金额", onChange = function(_, value) M._manualInputs[industryId].dividend = value end}
    rows[#rows + 1] = C.SecondaryButton {text = "产业公司手动分红", width = "100%", onClick = function() local ok, message = GIO.DistributeDividend(GD, def, business, numericInput(industryId, "dividend", 100)); actionResult(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.SectionTitle {text = "产业公司融资", color = T.Info}
    rows[#rows + 1] = C.InfoRow {label = "当前可贷额度", value = C.FormatMoney(summary.loanRoom), color = T.Info}
    rows[#rows + 1] = UI.TextField {value = inputValue(industryId, "loan", "500"), width = "100%", height = 38, keyboardType = "number", placeholder = "贷款金额", onChange = function(_, value) M._manualInputs[industryId].loan = value end}
    rows[#rows + 1] = C.SecondaryButton {text = "申请36个月产业经营贷款", width = "100%", onClick = function() local ok, message = GIO.ApplyLoan(GD, def, business, numericInput(industryId, "loan", 500), 36); actionResult(ok, message); refresh(navigate) end}
    for loanIndex, loan in ipairs(business.loans or {}) do
        local capturedIndex = loanIndex
        rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, alignItems = "center", children = {
            UI.Label {text = loan.name .. " · 余额" .. C.FormatMoney(loan.amount or 0), fontSize = T.FontCaption, fontColor = T.TextSecondary, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
            C.SecondaryButton {text = "提前结清", width = 96, onClick = function() local ok, message = GIO.EarlyRepayLoan(GD, def, business, capturedIndex); actionResult(ok, message); refresh(navigate) end},
        }}
    end
    rows[#rows + 1] = C.SectionTitle {text = "最近交易流水", color = T.Info}
    local txStart = math.max(1, #(business.transactions or {}) - 5)
    if #(business.transactions or {}) == 0 then
        rows[#rows + 1] = UI.Label {text = "暂无产业公司交易", fontSize = T.FontCaption, fontColor = T.TextMuted}
    else
        for index = #business.transactions, txStart, -1 do
            local tx = business.transactions[index]
            rows[#rows + 1] = C.InfoRow {label = tx.category or "经营交易", value = (tx.type == "expense" and "-" or "+") .. C.FormatMoney(tx.amount or 0), color = tx.type == "expense" and T.Danger or T.Success}
        end
    end
    rows[#rows + 1] = C.SectionTitle {text = "公司更名", color = T.Info}
    rows[#rows + 1] = UI.TextField {value = inputValue(industryId, "name", business.companyName), width = "100%", height = 38, placeholder = "产业公司名称", onChange = function(_, value) M._manualInputs[industryId].name = value end}
    rows[#rows + 1] = C.SecondaryButton {text = "保存公司名称", width = "100%", onClick = function() local ok, message = GIO.RenameCompany(GD, def, business, inputValue(industryId, "name", business.companyName)); actionResult(ok, message); refresh(navigate) end}
    return UI.Panel {width = "100%", padding = 10, gap = 7, backgroundColor = T.BgElevated, borderRadius = T.CardRadius, children = rows}
end

local function buildIndustryCard(navigate, GDI, industryId, def, data, snapshot)
    local business = data.businesses[industryId]
    local established = business ~= nil
    local expanded = M._expandedIndustryId == industryId
    local unlocked, unlockMessage, requirements = GDI.GetUnlockStatus(GD, industryId, snapshot)
    local variant, riskText = riskVariant(def)
    local projected = established and GDI.GetProjectedMonthlyResult(GD, industryId, snapshot) or nil
    ---@type Widget[]
    local rows = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2,
                    children = {
                        UI.Label {
                            text = def.name, fontSize = T.FontBody, fontColor = T.TextPrimary,
                            flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2,
                        },
                        UI.Label {
                            text = def.desc, fontSize = T.FontCaption, fontColor = T.TextMuted,
                            flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 4,
                        },
                    },
                },
                C.Badge {
                    text = established and ("Lv." .. tostring(business.level)) or (unlocked and "可创办" or "未解锁"),
                    variant = established and "success" or (unlocked and "info" or "warning"),
                },
            },
        },
        C.InfoRow {label = "首期投资", value = C.FormatMoney(def.investment), color = T.Accent},
        C.InfoRow {label = "经营风险", value = riskText, color = variant == "danger" and T.Danger or (variant == "warning" and T.Warning or T.Success)},
    }

    if established then
        rows[#rows + 1] = C.InfoRow {label = "累计投入 / 产业资产", value = C.FormatMoney(business.invested or 0) .. " / " .. C.FormatMoney(business.assetValue or 0)}
        rows[#rows + 1] = C.InfoRow {
            label = "上月收入 / 成本",
            value = C.FormatMoney(business.lastRevenue or 0) .. " / " .. C.FormatMoney(business.lastExpense or 0),
        }
        rows[#rows + 1] = C.InfoRow {
            label = "上月利润",
            value = C.FormatMoney(business.lastProfit or 0),
            color = (business.lastProfit or 0) >= 0 and T.Success or T.Danger,
        }
        rows[#rows + 1] = C.InfoRow {
            label = "当前策略",
            value = (GDI.STRATEGIES[business.strategy] or GDI.STRATEGIES.steady).name,
            color = T.Info,
        }
        if business.activeRisk then
            rows[#rows + 1] = UI.Panel {
                width = "100%", padding = 10, gap = 4,
                backgroundColor = T.DangerSoft or T.BgElevated,
                borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "风险事件：" .. (business.activeRisk.name or "经营风险"), fontSize = T.FontSmall, fontColor = T.Danger, fontWeight = "bold"},
                    C.InfoRow {label = "剩余影响", value = tostring(business.activeRisk.monthsLeft or 0) .. "个月"},
                    C.InfoRow {label = "处置成本", value = C.FormatMoney(business.activeRisk.resolveCost or 0), color = T.Warning},
                    C.ActionButton {
                        text = "立即专项处置", width = "100%",
                        onClick = function()
                            local ok, message
                            if business.settlementMode == "manual_company" then
                                ok, message = GDI.Operations.ResolveRisk(GD, def, business)
                            else
                                ok, message = GDI.ResolveBusinessRisk(GD, industryId)
                            end
                            actionResult(ok, message)
                            refresh(navigate)
                        end,
                    },
                },
            }
        end
    else
        rows[#rows + 1] = UI.Label {
            text = unlockMessage, fontSize = T.FontCaption,
            fontColor = unlocked and T.Success or T.Warning,
            whiteSpace = "normal", maxLines = 5,
        }
    end

    rows[#rows + 1] = C.SecondaryButton {
        text = expanded and "收起详情" or "查看经营详情", width = "100%",
        onClick = function()
            M._expandedIndustryId = expanded and nil or industryId
            refresh(navigate)
        end,
    }

    if expanded then
        ---@type Widget[]
        local detailRows = {}
        if established then
            if business.settlementMode == "manual_company" then
                detailRows[#detailRows + 1] = buildManualOperations(navigate, GDI, industryId, def, business)
            else
            ---@type Widget[]
            local strategyButtons = {}
            for _, strategyId in ipairs(GDI.STRATEGY_ORDER) do
                local capturedStrategyId = strategyId
                local strategy = GDI.STRATEGIES[strategyId]
                local active = business.strategy == strategyId
                strategyButtons[#strategyButtons + 1] = UI.Button {
                    text = strategy.name, height = 34,
                    backgroundColor = active and T.Primary or T.Surface,
                    fontColor = active and T.TextOnDark or T.TextSecondary,
                    flexGrow = 1,
                    onClick = function()
                        local ok, message = GDI.SetStrategy(GD, industryId, capturedStrategyId)
                        actionResult(ok, message)
                        refresh(navigate)
                    end,
                }
            end
            detailRows[#detailRows + 1] = C.SectionTitle {text = "经营决策", color = T.Info}
            detailRows[#detailRows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = strategyButtons}
            detailRows[#detailRows + 1] = UI.Label {
                text = (GDI.STRATEGIES[business.strategy] or GDI.STRATEGIES.steady).desc,
                fontSize = T.FontCaption, fontColor = T.TextMuted, whiteSpace = "normal", maxLines = 3,
            }
            if projected then
                detailRows[#detailRows + 1] = C.InfoRow {label = "预计月收入", value = C.FormatMoney(projected.revenue), color = T.Info}
                detailRows[#detailRows + 1] = C.InfoRow {label = "预计月利润", value = C.FormatMoney(projected.profit), color = projected.profit >= 0 and T.Success or T.Danger}
            end
            if business.level < def.maxLevel then
                local upgradeCost = GDI.GetUpgradeCost(industryId, business.level)
                detailRows[#detailRows + 1] = C.InfoRow {label = "升级至Lv." .. tostring(business.level + 1), value = C.FormatMoney(upgradeCost), color = T.Accent}
                detailRows[#detailRows + 1] = C.ActionButton {
                    text = "扩大产业规模", width = "100%",
                    disabled = (GD.group.cash or 0) < upgradeCost,
                    onClick = function()
                        local ok, message = GDI.Upgrade(GD, industryId)
                        actionResult(ok, message)
                        refresh(navigate)
                    end,
                }
            else
                detailRows[#detailRows + 1] = C.Badge {text = "已达最高等级", variant = "success"}
            end
            end
        else
            detailRows[#detailRows + 1] = C.SectionTitle {text = "创办条件", color = T.Info}
            local requirementRows = buildRequirements(requirements)
            for _, row in ipairs(requirementRows) do detailRows[#detailRows + 1] = row end
            detailRows[#detailRows + 1] = C.ActionButton {
                text = unlocked and "从集团账户投资创办" or "尚未满足创办条件",
                width = "100%", disabled = not unlocked or (GD.group.cash or 0) < def.investment,
                onClick = function()
                    local ok, message = GDI.Establish(GD, industryId)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            }
        end
        rows[#rows + 1] = UI.Panel {
            width = "100%", padding = 10, gap = 7,
            backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
            children = detailRows,
        }
    end

    return C.Card {children = rows}
end

function M.Create(navigate)
    local GS = GD.GroupSystem
    local GDI = GS and GS.Diversification
    if not GS or not GDI or not GS.IsActive(GD) then
        return UI.ScrollView {
            id = "screenScrollView", width = "100%", height = "100%", scrollY = true,
            padding = T.PagePadding, gap = 12,
            children = {
                C.SectionTitle {text = "集团产业经营"},
                C.Card {children = {
                    C.Badge {text = "尚未解锁", variant = "warning"},
                    UI.Label {text = "请先在公司总览中组建集团，再开展多元化产业布局。", fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 3},
                    C.ActionButton {text = "返回集团中心", width = "100%", onClick = function() navigate("group") end},
                }},
            },
        }
    end

    local data = GDI.EnsureFields(GD)
    local snapshot = GDI.BuildOperatingSnapshot(GD)
    local summary = GDI.GetSummary(GD, snapshot)
    local tabs = {}
    for _, sectorId in ipairs(GDI.SECTOR_ORDER) do tabs[#tabs + 1] = GDI.SECTORS[sectorId].shortName end
    M._activeSector = math.max(1, math.min(#tabs, M._activeSector or 1))
    local activeSectorId = GDI.SECTOR_ORDER[M._activeSector]
    local sector = GDI.SECTORS[activeSectorId]

    local children = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2, children = {
                    C.SectionTitle {text = "集团产业经营", color = T.Accent},
                    UI.Label {text = GD.group.name or "地产集团", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                C.SecondaryButton {text = "返回集团中心", width = 92, height = 34, onClick = function() navigate("group") end},
            },
        },
        UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 10, children = {
            C.StatCard {title = "产业资产", value = C.FormatMoney(summary.industryAssetValue), color = T.Info},
            C.StatCard {title = "上月产业利润", value = C.FormatMoney(summary.lastMonthlyProfit), color = summary.lastMonthlyProfit >= 0 and T.Success or T.Danger},
            C.StatCard {title = "集团风控", value = tostring(math.floor(summary.riskControl)) .. "/100", color = summary.riskControl >= 60 and T.Success or T.Warning},
        }},
        C.InfoRow {label = "集团现金", value = C.FormatMoney(GD.group.cash or 0), color = (GD.group.cash or 0) >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "已布局产业", value = tostring(summary.activeCount) .. "/" .. tostring(#GDI.INDUSTRY_ORDER) .. "条", color = T.Accent},
        C.InfoRow {label = "手动经营公司", value = tostring(summary.manualCompanyCount or 0) .. "家", color = T.Info},
        C.InfoRow {label = "稳定租金资产", value = C.FormatMoney(summary.rentalAssetValue), color = T.Info},
        C.InfoRow {label = "经营中风险", value = tostring(summary.activeRiskCount) .. "项", color = summary.activeRiskCount > 0 and T.Warning or T.Success},
    }

    if summary.hasLiquidityCrisis then
        children[#children + 1] = C.Card {children = {
            UI.Label {text = "集团流动性危机", fontSize = T.FontSubtitle, fontColor = T.Danger, fontWeight = "bold"},
            UI.Label {
                text = "原因：" .. tostring(summary.liquidityCrisis.reason or "资金覆盖不足") .. "。危机期间产业收入受损，并产生紧急融资成本。",
                fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 4,
            },
            C.ActionButton {
                text = "检查并执行流动性重整", width = "100%",
                onClick = function()
                    local ok, message = GDI.ResolveLiquidityCrisis(GD)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            },
        }}
    end

    children[#children + 1] = C.Card {children = {
        C.SectionTitle {text = "集团风控体系", color = T.Warning},
        UI.Label {
            text = "风控水平提高金融赛道解锁能力，并降低全部产业的风险概率。风控投入只从集团账户支付。",
            fontSize = T.FontCaption, fontColor = T.TextMuted, whiteSpace = "normal", maxLines = 3,
        },
        C.InfoRow {label = "当前风控", value = tostring(math.floor(data.riskControl)) .. "/100", color = data.riskControl >= 60 and T.Success or T.Warning},
        C.ActionButton {
            text = "投入集团风控建设", width = "100%", disabled = data.riskControl >= 100,
            onClick = function()
                local ok, message = GDI.StrengthenRiskControl(GD)
                actionResult(ok, message)
                refresh(navigate)
            end,
        },
    }}

    children[#children + 1] = C.TabBar {
        tabs = tabs, active = M._activeSector,
        onChange = function(index)
            M._activeSector = index
            M._expandedIndustryId = nil
            refresh(navigate)
        end,
    }
    children[#children + 1] = C.Card {children = {
        C.SectionTitle {text = sector.name, color = T.Accent},
        UI.Label {text = sector.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 3},
        C.InfoRow {label = "本板块已布局", value = tostring(summary.sectorCounts[activeSectorId] or 0) .. "/" .. tostring(#GDI.GetSectorIndustries(activeSectorId)) .. "条", color = T.Info},
    }}

    for _, item in ipairs(GDI.GetSectorIndustries(activeSectorId)) do
        children[#children + 1] = buildIndustryCard(navigate, GDI, item.id, item.def, data, snapshot)
    end
    children[#children + 1] = UI.Panel {height = 24, width = "100%"}

    return UI.ScrollView {
        id = "screenScrollView", width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 12, children = children,
    }
end

return M
