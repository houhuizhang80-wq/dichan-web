-- ============================================================================
-- GroupDashboard.lua - 总览页集团创建与管理面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local GV = require("Governance")

local M = {}

M._groupName = ""
M._groupCapital = ""
M._selectedCompanies = {}
M._injectAmounts = {}
M._personalInjectionAmount = ""
M._personalTransferAmount = ""
M._expandedMemberId = nil
M._showExecutives = false

local function refresh(navigate, screenId)
    navigate(screenId or M._refreshScreenId or "dashboard")
end

local function actionResult(ok, message)
    GD.AddEvent(message or (ok and "集团操作成功" or "集团操作失败"), ok and "success" or "warning")
end

local function countSelected()
    local count = 0
    for _, selected in pairs(M._selectedCompanies) do
        if selected then count = count + 1 end
    end
    return count
end

local function buildFormationPanel(navigate, companies)
    local GS = GD.GroupSystem
    local eligible = GS.GetFormationCompanies(GD)
    if #eligible < 2 then
        return C.Card {children = {
            C.SectionTitle {text = "集团功能", color = T.Accent},
            C.Badge {text = "尚未解锁", variant = "warning"},
            UI.Label {
                text = "个人名下至少两家仍持股的经营公司后，可选择其中两家或以上组建集团。集团成立后，个人持有集团股权，集团持有下属公司股权。",
                fontSize = T.FontSmall, fontColor = T.TextSecondary,
                whiteSpace = "normal", maxLines = 4,
            },
            C.InfoRow {label = "当前持股公司", value = tostring(#eligible) .. "/2家", color = T.Warning},
            C.ActionButton {text = "前往城市成立公司", width = "100%", onClick = function() navigate("city") end},
        }}
    end

    if M._groupName == "" then M._groupName = "地产控股集团" end
    if M._groupCapital == "" then
        local personalCash = GD.player and (GD.player.cash or 0) or 0
        M._groupCapital = tostring(math.max(1, math.floor(personalCash * 0.20)))
    end

    local companyChecks = {}
    for _, record in ipairs(eligible) do
        local capturedRecord = record
        companyChecks[#companyChecks + 1] = UI.Checkbox {
            checked = M._selectedCompanies[tostring(record.id)] == true,
            label = (record.name or "未命名公司") .. " · " .. (record.city or "未登记城市")
                .. " · 持股" .. string.format("%.1f%%", (record.founderRatio or 0) * 100),
            onChange = function(_, checked)
                M._selectedCompanies[tostring(capturedRecord.id)] = checked and true or nil
                refresh(navigate)
            end,
        }
    end

    local selectedCount = countSelected()
    local capital = math.floor(tonumber(M._groupCapital) or 0)
    local personalCash = GD.player and (GD.player.cash or 0) or 0
    local canForm = selectedCount >= 2 and capital > 0 and capital <= personalCash

    return C.Card {children = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                C.SectionTitle {text = "组建地产集团", color = T.Accent, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0},
                C.Badge {text = "已解锁", variant = "success"},
            },
        },
        UI.Label {
            text = "选择至少两家个人仍有控制权的公司，由个人现金出资集团注册资本。成立后公司原有持股比例转由集团持有。",
            fontSize = T.FontSmall, fontColor = T.TextSecondary,
            whiteSpace = "normal", maxLines = 4,
        },
        UI.Label {text = "集团名称", fontSize = T.FontCaption, fontColor = T.TextMuted},
        UI.TextField {
            value = M._groupName, width = "100%", height = 40,
            placeholder = "请输入2~20字集团名称", maxLength = 20,
            onChange = function(_, value) M._groupName = value end,
        },
        UI.Label {text = "集团注册资本（万元）", fontSize = T.FontCaption, fontColor = T.TextMuted},
        UI.TextField {
            value = M._groupCapital, width = "100%", height = 40,
            keyboardType = "number", placeholder = "个人现金出资",
            onChange = function(_, value) M._groupCapital = value end,
        },
        C.InfoRow {label = "个人可用现金", value = C.FormatMoney(personalCash), color = capital <= personalCash and T.Success or T.Danger},
        C.SectionTitle {text = "选择首批子公司（已选" .. tostring(selectedCount) .. "家）", color = T.Info},
        UI.Panel {width = "100%", gap = 8, children = companyChecks},
        C.ActionButton {
            text = canForm and "确认组建集团" or (selectedCount < 2 and "至少选择两家公司" or "请检查注册资本"),
            width = "100%", disabled = not canForm,
            onClick = canForm and function()
                local ids = {}
                for companyId, selected in pairs(M._selectedCompanies) do
                    if selected then ids[#ids + 1] = companyId end
                end
                local ok, message = GS.FormGroup(GD, M._groupName, capital, ids)
                actionResult(ok, message)
                if ok then
                    M._selectedCompanies = {}
                    M._groupCapital = ""
                end
                refresh(navigate)
            end or nil,
        },
    }}
end

local function buildExecutiveSection(navigate, group)
    local GS = GD.GroupSystem
    ---@type Widget[]
    local rows = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                C.SectionTitle {text = "集团高管", color = T.Info, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0},
                C.SecondaryButton {
                    text = M._showExecutives and "收起" or "管理高管", width = 96, height = 34,
                    onClick = function() M._showExecutives = not M._showExecutives; refresh(navigate) end,
                },
            },
        },
    }
    if not M._showExecutives then
        local count = 0
        for _ in pairs(group.executives or {}) do count = count + 1 end
        rows[#rows + 1] = C.InfoRow {label = "集团在职高管", value = tostring(count) .. "人", color = count > 0 and T.Success or T.TextMuted}
        rows[#rows + 1] = UI.Label {
            text = group.executives and group.executives.ceo
                and "集团CEO已接管全部下属公司的月度经营与审批报告。"
                or "聘用集团CEO后，将按各子公司经营策略启用全权经营。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 3,
        }
        return UI.Panel {width = "100%", gap = 6, children = rows}
    end

    for _, role in ipairs(GV.EXECUTIVE_ROLES or {}) do
        local capturedRole = role
        local employed = group.executives and group.executives[role.id]
        rows[#rows + 1] = UI.Panel {
            width = "100%", padding = 10, gap = 5,
            backgroundColor = T.Surface, borderRadius = T.CardRadius,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row", flexWrap = "wrap",
                    justifyContent = "space-between", alignItems = "flex-start", gap = 8,
                    children = {
                        UI.Label {
                            text = role.name, fontSize = T.FontBody, fontColor = T.TextPrimary,
                            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
                            whiteSpace = "normal", maxLines = 2,
                        },
                        C.Badge {text = employed and "在职" or "空缺", variant = employed and "success" or "info"},
                    },
                },
                UI.Label {text = role.desc, fontSize = T.FontCaption, fontColor = T.TextMuted, whiteSpace = "normal", maxLines = 3},
                C.InfoRow {label = "年薪 / 签约奖金", value = C.FormatMoney(role.salary or 0) .. " / " .. C.FormatMoney(role.bonus or 0)},
                employed and C.SecondaryButton {
                    text = "解聘", width = "100%",
                    onClick = function()
                        local ok, message = GS.FireExecutive(GD, capturedRole.id)
                        actionResult(ok, message)
                        refresh(navigate)
                    end,
                } or C.ActionButton {
                    text = "聘用", width = "100%",
                    onClick = function()
                        local ok, message = GS.HireExecutive(GD, capturedRole.id)
                        actionResult(ok, message)
                        refresh(navigate)
                    end,
                },
            },
        }
    end
    return UI.Panel {width = "100%", gap = 8, children = rows}
end

local function buildMemberCard(navigate, member)
    local GS = GD.GroupSystem
    local record = nil
    for _, companyRecord in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        if tostring(companyRecord.id) == tostring(member.companyId) then record = companyRecord; break end
    end
    if not record then return nil end

    local companyId = tostring(member.companyId)
    local expanded = M._expandedMemberId == companyId
    local strategyId = GD.group.companyStrategies[companyId] or "steady"
    local strategy = GS.STRATEGIES[strategyId] or GS.STRATEGIES.steady
    local rows = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2, children = {
                    UI.Label {text = record.name or member.name or "未命名公司", fontSize = T.FontBody, fontColor = T.TextPrimary, whiteSpace = "normal", maxLines = 2},
                    UI.Label {text = record.city or member.city or "未登记城市", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                C.Badge {text = (member.ownershipRatio or 0) >= 0.999999 and "集团全资" or "集团控股", variant = "success"},
            },
        },
        C.InfoRow {label = "集团持股", value = string.format("%.1f%%", (member.ownershipRatio or 0) * 100), color = T.Accent},
        C.InfoRow {label = "经营策略", value = strategy.name, color = T.Info},
        C.InfoRow {label = "公司现金", value = C.FormatMoney(record.cash or 0), color = (record.cash or 0) >= 0 and T.Success or T.Danger},
        C.SecondaryButton {
            text = expanded and "收起管理" or "管理子公司", width = "100%",
            onClick = function()
                M._expandedMemberId = expanded and nil or companyId
                refresh(navigate)
            end,
        },
    }

    if expanded then
        local strategyButtons = {}
        for _, candidateId in ipairs(GS.STRATEGY_ORDER or {}) do
            local capturedStrategyId = candidateId
            local candidate = GS.STRATEGIES[candidateId]
            strategyButtons[#strategyButtons + 1] = UI.Button {
                text = candidate.name, height = 34,
                backgroundColor = candidateId == strategyId and T.Primary or T.Surface,
                fontColor = candidateId == strategyId and T.TextOnDark or T.TextSecondary,
                flexGrow = 1,
                onClick = function()
                    local ok, message = GS.SetCompanyStrategy(GD, member.companyId, capturedStrategyId)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            }
        end
        local injectAmount = M._injectAmounts[companyId] or ""
        ---@type Widget[]
        local managementChildren = {
            UI.Label {text = "经营策略", fontSize = T.FontCaption, fontColor = T.TextMuted},
            UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = strategyButtons},
            UI.Label {text = strategy.desc, fontSize = T.FontCaption, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 3},
        }
        if (member.ownershipRatio or 0) >= 0.999999 then
            managementChildren[#managementChildren + 1] = UI.Label {text = "集团注资（万元）", fontSize = T.FontCaption, fontColor = T.TextMuted}
            managementChildren[#managementChildren + 1] = UI.TextField {
                value = injectAmount, width = "100%", height = 38,
                keyboardType = "number", placeholder = "从集团账户向全资子公司注资",
                onChange = function(_, value) M._injectAmounts[companyId] = value end,
            }
            managementChildren[#managementChildren + 1] = C.ActionButton {
                text = "确认集团注资", width = "100%",
                onClick = function()
                    local ok, message = GS.InjectCapital(GD, member.companyId, tonumber(M._injectAmounts[companyId]) or 0)
                    actionResult(ok, message)
                    if ok then M._injectAmounts[companyId] = "" end
                    refresh(navigate)
                end,
            }
        end
        managementChildren[#managementChildren + 1] = UI.Label {
            text = "出售所得直接进入集团账户；持股低于50%后集团失去经营权，出售全部后退出集团。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 3,
        }
        managementChildren[#managementChildren + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = {
            C.SecondaryButton {
                text = "出售10%", width = "31%", height = 34,
                onClick = function()
                    local ok, message = GV.SellFounderSharesForCompany(GD, member.companyId, 0.10)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            },
            C.SecondaryButton {
                text = "出售25%", width = "31%", height = 34,
                onClick = function()
                    local ok, message = GV.SellFounderSharesForCompany(GD, member.companyId, 0.25)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            },
            C.SecondaryButton {
                text = "出售全部", width = "31%", height = 34,
                onClick = function()
                    local ok, message = GV.SellFounderSharesForCompany(GD, member.companyId, 1.0)
                    actionResult(ok, message)
                    refresh(navigate)
                end,
            },
        }}
        rows[#rows + 1] = UI.Panel {
            width = "100%", padding = 10, gap = 8,
            backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
            children = managementChildren,
        }
    end
    return C.Card {children = rows}
end

local function buildActivePanel(navigate)
    local GS = GD.GroupSystem
    local group = GS.NormalizeMembership(GD)
    local summary = GS.GetSummary(GD)
    local diversification = GS.Diversification
    local diversificationSummary = diversification and diversification.GetSummary(GD) or nil
    local rows = {
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between", alignItems = "flex-start", gap = 8,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2, children = {
                    C.SectionTitle {text = group.name or "地产集团", color = T.Accent},
                    UI.Label {text = "个人持有集团" .. string.format("%.1f%%", (group.personalShareRatio or 1) * 100) .. "股权", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                C.Badge {text = "集团运营中", variant = "success"},
            },
        },
        UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 10, children = {
            C.StatCard {title = "集团现金", value = C.FormatMoney(summary.cash), color = T.Success},
            C.StatCard {title = "股权价值", value = C.FormatMoney(summary.equityValue), color = T.Info},
            C.StatCard {title = "集团净资产", value = C.FormatMoney(summary.netAssets), color = summary.netAssets >= 0 and T.Accent or T.Danger},
        }},
        C.InfoRow {label = "集团注册资本", value = C.FormatMoney(group.registeredCapital or 0)},
        C.InfoRow {label = "集团贷款", value = C.FormatMoney(group.totalDebt or 0), color = (group.totalDebt or 0) > 0 and T.Warning or T.Success},
        C.InfoRow {label = "下属公司", value = tostring(summary.activeMembers) .. "家（全资" .. tostring(summary.whollyOwned) .. "家）", color = T.Info},
        C.InfoRow {label = "上月总部收支", value = C.FormatMoney(group.lastMonthlyIncome or 0) .. " / " .. C.FormatMoney(group.lastMonthlyExpense or 0)},
        C.InfoRow {label = "总部留存收益", value = C.FormatMoney(group.retainedEarnings or 0), color = T.Success},
        C.SectionTitle {text = "多元化产业布局", color = T.Accent},
        UI.Label {
            text = "从集团账户投资六大板块，产业利润归集团；建材、设计、物业、能源等协同通过真实业务支出作用于成员公司。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 4,
        },
        C.InfoRow {
            label = "已布局产业 / 产业资产",
            value = diversificationSummary and (tostring(diversificationSummary.activeCount) .. "条 / " .. C.FormatMoney(diversificationSummary.industryAssetValue)) or "0条 / 0万",
            color = T.Info,
        },
        C.InfoRow {
            label = "上月产业利润",
            value = C.FormatMoney(diversificationSummary and diversificationSummary.lastMonthlyProfit or 0),
            color = diversificationSummary and diversificationSummary.lastMonthlyProfit >= 0 and T.Success or T.Danger,
        },
        C.InfoRow {
            label = "产业风控 / 风险",
            value = diversificationSummary and (tostring(math.floor(diversificationSummary.riskControl)) .. "/100 · " .. tostring(diversificationSummary.activeRiskCount) .. "项") or "50/100 · 0项",
            color = diversificationSummary and diversificationSummary.hasLiquidityCrisis and T.Danger or T.Warning,
        },
        C.ActionButton {
            text = diversificationSummary and diversificationSummary.hasLiquidityCrisis and "进入产业中心处理危机" or "进入集团产业经营",
            width = "100%",
            onClick = function() navigate("groupDiversification") end,
        },
        C.SectionTitle {text = "个人与集团资金往来", color = T.Info},
        UI.Label {
            text = "个人注资增加集团注册资本；集团转给个人视为股东分红，只能使用集团现金与留存收益中的个人可分配份额，并计入个人当年分红收入。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 4,
        },
        C.InfoRow {label = "个人可用现金", value = C.FormatMoney(GD.player and (GD.player.cash or 0) or 0), color = T.Success},
        C.InfoRow {label = "个人可分配额度", value = C.FormatMoney(GS.GetPersonalTransferLimit(GD)), color = T.Info},
        UI.TextField {
            value = M._personalInjectionAmount, width = "100%", height = 38,
            keyboardType = "number", placeholder = "输入个人向集团注资金额（万元）",
            onChange = function(_, value) M._personalInjectionAmount = value end,
            onSubmit = function(_, value)
                M._personalInjectionAmount = value
                local ok, message = GS.InjectPersonalCapital(GD, tonumber(value) or 0)
                actionResult(ok, message)
                if ok then M._personalInjectionAmount = "" end
                refresh(navigate)
            end,
        },
        C.ActionButton {
            text = "个人向集团注资", width = "100%",
            onClick = function()
                local ok, message = GS.InjectPersonalCapital(GD, tonumber(M._personalInjectionAmount) or 0)
                actionResult(ok, message)
                if ok then M._personalInjectionAmount = "" end
                refresh(navigate)
            end,
        },
        UI.TextField {
            value = M._personalTransferAmount, width = "100%", height = 38,
            keyboardType = "number", placeholder = "输入集团向个人分红金额（万元）",
            onChange = function(_, value) M._personalTransferAmount = value end,
            onSubmit = function(_, value)
                M._personalTransferAmount = value
                local ok, message = GS.TransferToPersonal(GD, tonumber(value) or 0)
                actionResult(ok, message)
                if ok then M._personalTransferAmount = "" end
                refresh(navigate)
            end,
        },
        C.SecondaryButton {
            text = "集团向个人分红", width = "100%",
            onClick = function()
                local ok, message = GS.TransferToPersonal(GD, tonumber(M._personalTransferAmount) or 0)
                actionResult(ok, message)
                if ok then M._personalTransferAmount = "" end
                refresh(navigate)
            end,
        },
        UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, children = {
            C.ActionButton {
                text = "集团融资", width = "48%",
                onClick = function()
                    local CapitalScreen = require("screens/CapitalScreen")
                    CapitalScreen.OpenGroupFinancing()
                    navigate("capital")
                end,
            },
            C.SecondaryButton {text = "成立新子公司", width = "48%", onClick = function() navigate("companyCreate") end},
        }},
        C.SectionTitle {text = "集团分红策略", color = T.Warning},
        UI.Label {
            text = "下属公司分红和公司股权出售所得先进入集团账户；集团每年12月再按设置比例向个人股东分红。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 3,
        },
        UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6, children = (function()
            local buttons = {}
            for _, rate in ipairs({0.25, 0.50, 0.75}) do
                local capturedRate = rate
                buttons[#buttons + 1] = UI.Button {
                    text = tostring(math.floor(rate * 100)) .. "%", height = 34, flexGrow = 1,
                    backgroundColor = math.abs((group.dividendRate or 0) - rate) < 0.001 and T.Primary or T.Surface,
                    fontColor = math.abs((group.dividendRate or 0) - rate) < 0.001 and T.TextOnDark or T.TextSecondary,
                    onClick = function() GS.SetDividendRate(GD, capturedRate); refresh(navigate) end,
                }
            end
            return buttons
        end)()},
        buildExecutiveSection(navigate, group),
        C.SectionTitle {text = "下属公司", color = T.Accent},
    }

    for _, member in ipairs(group.members or {}) do
        if member.active ~= false and (member.ownershipRatio or 0) > 0 then
            local card = buildMemberCard(navigate, member)
            if card then rows[#rows + 1] = card end
        end
    end

    local eligible = GS.GetEligibleCompanies(GD)
    if #eligible > 0 then
        rows[#rows + 1] = C.SectionTitle {text = "纳入现有公司", color = T.Info}
        for _, record in ipairs(eligible) do
            local capturedRecord = record
            rows[#rows + 1] = UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap",
                justifyContent = "space-between", alignItems = "flex-start", gap = 8,
                children = {
                    UI.Label {
                        text = (record.name or "未命名公司") .. " · " .. (record.city or "未登记城市"),
                        fontSize = T.FontSmall, fontColor = T.TextPrimary,
                        flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
                        whiteSpace = "normal", maxLines = 2,
                    },
                    C.SecondaryButton {
                        text = "纳入集团", width = 96, height = 34,
                        onClick = function()
                            local ok, message = GS.AddMemberCompany(GD, capturedRecord.id)
                            actionResult(ok, message)
                            refresh(navigate)
                        end,
                    },
                },
            }
        end
    end

    return C.Card {children = rows}
end

function M.Build(navigate, companies, refreshScreenId)
    local GS = GD.GroupSystem
    M._refreshScreenId = refreshScreenId or "dashboard"
    if not GS or not GS.IsActive(GD) then
        return buildFormationPanel(navigate, companies or {})
    end
    return buildActivePanel(navigate)
end

return M
