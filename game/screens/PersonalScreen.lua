---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- PersonalScreen.lua - 个人财务中心 (9-Tab 完整版)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local InvestmentTab = require("screens/personal/InvestmentTab")

local PS = GD.Personal   -- Personal 模块
local GV = GD.Governance -- Governance 模块

local M = {}
M._activeTab = 1
M._cashFlowCompanyId = M._cashFlowCompanyId or nil
M._creditBankId = M._creditBankId or "national"
-- 1=资产总览 2=投资理财 3=个人房产 4=个人贷款
-- 5=生活消费 6=薪酬往来 7=个人税务 8=成就里程碑 9=家庭

function M.Create(navigate)
    local p = GD.player
    if not p then
        GD.player = PS.InitPlayerData(0)
        p = GD.player
    end

    -- 确保所有玩家字段在渲染前完整初始化（防止旧存档缺字段导致崩溃）
    PS.EnsurePlayerFields(p)

    local tabNames = {"资产总览", "投资理财", "个人房产", "个人贷款", "生活消费", "薪酬往来", "个人税务", "成就", "家庭"}
    local tabFns = {
        M._TabOverview, function() return InvestmentTab.Create(navigate) end, M._TabProperty, M._TabLoan,
        M._TabLifestyle, M._TabCashFlow, M._TabTax, M._TabMilestones, M._TabFamily,
    }

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 14,
        children = {
            C.SectionTitle {text = "个人财务"},

            C.TabBar {
                tabs = tabNames,
                active = M._activeTab,
                onChange = function(idx)
                    M._activeTab = idx
                    navigate("personal")
                end,
            },

            tabFns[M._activeTab](navigate, p),

            UI.Panel {height = 20},
        }
    }
end

-- ============================================================================
-- Tab1: 资产总览
-- ============================================================================
function M._TabOverview(navigate, p)
    PS.CalcNetWorth(GD)
    local summary = PS.GetInvestmentSummary(GD)
    local hasActiveCompany = GD.HasActiveOperatingCompany and GD.HasActiveOperatingCompany()
    local gov = hasActiveCompany and GD.company and GD.company.governance or nil
    local founderRatio = hasActiveCompany and gov and (gov.founderRatio or 0) or 0
    local controlLevel = GV.GetControlLevel(founderRatio)

    local companyVal = 0
    if hasActiveCompany and gov then
        companyVal = (gov.lastValuation or 0) > 0 and gov.lastValuation or (GD.company.totalAssets or 0)
    elseif hasActiveCompany then
        companyVal = GD.company.totalAssets or 0
    end
    local equityValue = math.floor(companyVal * founderRatio)

    -- 房产总值
    local propValue = 0
    for _, prop in ipairs(p.properties or {}) do propValue = propValue + prop.currentValue end

    -- 负债总额
    local totalDebt = 0
    for _, loan in ipairs(p.personalLoans or {}) do totalDebt = totalDebt + loan.remaining end

    -- 持有品总值
    local lifestyleValue = 0
    for _, it in ipairs(p.lifestyleItems or {}) do lifestyleValue = lifestyleValue + math.floor(it.price * 0.6) end

    local companyCash = hasActiveCompany and (GD.company.cash or 0) or 0
    local activeProjects = hasActiveCompany and (GD.projects or {}) or {}
    local activeFixedAssets = hasActiveCompany and (GD.fixedAssets or {}) or {}

    -- 项目状态映射
    local statusMap = {
        permits = "报建", design = "设计", construction = "施工",
        presale = "预售", delivery = "交付", completed = "竣工",
        operations = "运营", mature = "成熟", settlement = "结算",
    }
    local devCatMap = {sale = "销售型", hold = "持有型", agency = "代建型"}

    -- 构建每个项目的详情卡片
    local projectCards = {}
    local totalPmIncome = 0  -- 物业费月总收入
    for i, proj in ipairs(activeProjects) do
        local pm = proj.propertyMgmt
        local sales = proj.sales or {}
        local assets = proj.assets or {}
        local soldUnits = sales.soldUnits or 0
        local totalUnits = sales.totalUnits or 0
        local soldArea = sales.soldArea or 0
        local revenue = sales.revenue or 0

        local stLabel = statusMap[proj.status] or proj.status
        local catLabel = devCatMap[proj.devCategory or "sale"] or ""

        -- 状态 badge 颜色
        local statusVariant = "info"
        if proj.status == "completed" or proj.status == "mature" then statusVariant = "success"
        elseif proj.status == "construction" then statusVariant = "warning"
        elseif proj.status == "presale" or proj.status == "delivery" or proj.status == "pending_settlement" or proj.status == "pending_completion" then statusVariant = "primary" end

        local rows = {
            -- 头部：项目名 + 状态
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
                            UI.Label {text = proj.name, fontSize = T.FontBody, fontColor = T.TextPrimary, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                            UI.Label {text = catLabel .. " | " .. (proj.land and proj.land.location or ""), fontSize = T.FontCaption, fontColor = T.TextMuted, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                        },
                    },
                    C.Badge {text = stLabel, variant = statusVariant},
                },
            },
            UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2},
        }

        -- 销售进度
        if totalUnits > 0 then
            local sellPct = math.floor(soldUnits / totalUnits * 100)
            table.insert(rows, C.InfoRow {label = "销售进度", value = soldUnits .. "/" .. totalUnits .. "套 (" .. sellPct .. "%)", color = T.Accent})
            table.insert(rows, C.InfoRow {label = "销售面积", value = string.format("%.0f/%.0f m²", soldArea, sales.totalArea or 0)})
            table.insert(rows, C.InfoRow {label = "累计回款", value = C.FormatMoney(revenue), color = T.Success})
        end

        -- 自持运营
        local holdArea = proj.unitPlan and proj.unitPlan.holdArea or 0
        if holdArea > 0 and assets.rentable and not proj._fixedAssetConverted then
            table.insert(rows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
            table.insert(rows, C.InfoRow {label = "自持面积", value = string.format("%.0f m²", holdArea)})
            table.insert(rows, C.InfoRow {label = "出租率", value = string.format("%d%%", assets.occupancyRate or 0), color = T.Info})
            table.insert(rows, C.InfoRow {label = "月租收入", value = C.FormatMoney(assets.monthlyRentIncome or 0), color = T.Success})
        end

        -- 物业费
        if pm and pm.enabled and soldArea > 0 then
            totalPmIncome = totalPmIncome + (pm.monthlyIncome or 0)
            local lvl = GD.PROPERTY_SERVICE_LEVELS[pm.serviceLevelIdx] or GD.PROPERTY_SERVICE_LEVELS[1]
            local netPm = (pm.monthlyIncome or 0) - (pm.monthlyOperateCost or 0)
            table.insert(rows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
            table.insert(rows, C.InfoRow {label = "物业服务", value = lvl.name, color = T.Info})
            table.insert(rows, C.InfoRow {label = "物业费单价", value = string.format("%.1f 元/m²/月", pm.feePerSqm)})
            table.insert(rows, C.InfoRow {label = "缴费率", value = string.format("%d%%", pm.collectionRate), color = pm.collectionRate >= 80 and T.Success or T.Warning})
            table.insert(rows, C.InfoRow {label = "月物业净收入", value = C.FormatMoney(netPm), color = netPm >= 0 and T.Success or T.Danger})
            table.insert(rows, C.InfoRow {label = "业主满意度", value = string.format("%d%%", pm.satisfactionRate), color = pm.satisfactionRate >= 70 and T.Success or T.Danger})
        elseif pm and not pm.enabled and soldUnits > 0 and (proj.status == "delivery" or proj.status == "pending_settlement" or proj.status == "pending_completion" or proj.status == "completed" or proj.status == "operations" or proj.status == "mature") then
            table.insert(rows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
            table.insert(rows, C.InfoRow {label = "物业费", value = "未开通", color = T.TextMuted})
        end

        -- 成本概要
        local cost = proj.cost
        if cost then
            table.insert(rows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
            table.insert(rows, C.InfoRow {label = "总投入", value = C.FormatMoney(cost.totalSpent or 0), color = T.Warning})
        end

        table.insert(projectCards, C.Card {children = rows})
    end

    -- 固定资产卡片
    local faCards = {}
    for _, fa in ipairs(activeFixedAssets) do
        table.insert(faCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "space-between",
                alignItems = "flex-start",
                gap = 8,
                width = "100%",
                children = {
                    UI.Label {text = fa.projectName or fa.name or "固定资产", fontSize = T.FontBody, fontColor = T.TextPrimary, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
                    C.Badge {text = fa.isListedForRent and "出租中" or "持有", variant = fa.isListedForRent and "success" or "info"},
                },
            },
            C.InfoRow {label = "账面价值", value = C.FormatMoney(fa.bookValue or fa.originalValue or 0), color = T.Accent},
            C.InfoRow {label = "市场价值", value = C.FormatMoney(fa.marketValue or fa.currentValue or 0), color = T.Info},
            (fa.monthlyRent or 0) > 0 and C.InfoRow {label = "月租收入", value = C.FormatMoney(fa.monthlyRent or 0), color = T.Success} or nil,
            fa.mortgageRemaining and fa.mortgageRemaining > 0 and C.InfoRow {label = "贷款余额", value = C.FormatMoney(fa.mortgageRemaining), color = T.Danger} or nil,
        }})
    end

    -- 汇总所有子组件
    local children = {
        -- 核心指标
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "个人净资产", value = C.FormatMoney(p.netWorth), color = T.Accent, minWidth = 100},
                C.StatCard {title = "公司现金", value = C.FormatMoney(companyCash), color = hasActiveCompany and T.Success or T.TextMuted, minWidth = 90},
            }
        },

        -- 资产构成
        C.Card {children = {
            C.SectionTitle {text = "资产构成", color = T.Info},
            C.InfoRow {label = "个人现金", value = C.FormatMoney(p.cash), color = T.Success},
            C.InfoRow {label = "投资资产", value = C.FormatMoney(summary.total), color = T.Info},
            C.InfoRow {label = "个人房产", value = C.FormatMoney(propValue), color = T.Accent},
            C.InfoRow {label = "持股价值", value = C.FormatMoney(equityValue), color = T.Warning},
            UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
            C.InfoRow {label = "持股比例", value = string.format("%.1f%%", founderRatio * 100), color = T.Accent},
            C.InfoRow {label = "控制权", value = controlLevel.name, color = T[controlLevel.color] or T.TextPrimary},
            C.InfoRow {label = "个人负债", value = C.FormatMoney(totalDebt), color = totalDebt > 0 and T.Danger or T.TextMuted},
        }},
    }

    local portfolioRows = {
        C.SectionTitle {text = "我的公司组合", color = T.Accent},
        C.InfoRow {label = "可用个人现金", value = C.FormatMoney(p.cash or 0), color = T.Success},
        UI.Label {
            text = hasActiveCompany and "可在保留当前公司经营状态的同时，用个人现金在其他城市继续创办新公司。" or "当前没有正在经营的公司，但游戏不会结束；可继续在任意城市创办新公司。",
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
        },
        C.ActionButton {text = hasActiveCompany and "前往城市另设公司" or "注册新公司", width = "100%", onClick = function() navigate("companyCreate") end},
        C.SecondaryButton {text = "进入城市中心", width = "100%", onClick = function() navigate("city") end},
    }
    local portfolio = GD.GetCompanyPortfolioSummary and GD.GetCompanyPortfolioSummary() or {}
    if #portfolio > 0 then
        for _, rec in ipairs(portfolio) do
            local isActive = GD.activeCompanyId and tostring(GD.activeCompanyId) == tostring(rec.id)
            local statusText = "已退出"
            local statusVariant = "info"
            if rec.status == "operating" then
                if (rec.founderRatio or 0) < 0.50 then
                    statusText = "仅分红权"
                    statusVariant = "warning"
                else
                    statusText = isActive and "当前经营" or "可切换"
                    statusVariant = isActive and "success" or "info"
                end
            elseif rec.status == "sold" then
                statusText = "已出售"
                statusVariant = "warning"
            elseif rec.status == "bankrupt" then
                statusText = "已破产"
                statusVariant = "danger"
            end
            local company = rec.state and rec.state.company or {}
            local govRec = company.governance
            local companyValue = math.max(govRec and (govRec.lastValuation or 0) or 0, rec.totalAssets or company.totalAssets or 0)
            local stakeValue = math.floor(companyValue * (rec.founderRatio or 0))
            local ownershipLabel = "个人持股"
            if GD.GroupSystem then ownershipLabel = GD.GroupSystem.GetCompanyOwnershipLabel(GD, rec.id) end
            local recRows = {
                UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = rec.name or "未命名公司", fontSize = T.FontBody, fontColor = T.TextPrimary},
                        UI.Label {text = (rec.city or "未知城市") .. " | " .. (rec.createdYear or GD.year) .. "年创办", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    C.Badge {text = statusText, variant = statusVariant},
                }},
                C.InfoRow {label = "公司现金", value = C.FormatMoney(rec.cash or 0), color = (rec.cash or 0) >= 0 and T.Success or T.Danger},
                C.InfoRow {label = "总资产/负债", value = C.FormatMoney(rec.totalAssets or 0) .. " / " .. C.FormatMoney(rec.totalDebt or 0), color = T.Info},
                C.InfoRow {label = "项目数", value = tostring(rec.projectCount or 0), color = T.TextSecondary},
                C.InfoRow {label = ownershipLabel, value = string.format("%.1f%%", (rec.founderRatio or 0) * 100), color = (rec.founderRatio or 0) > 0 and T.Accent or T.TextMuted},
                C.InfoRow {label = ownershipLabel == "集团持股" and "集团持股价值" or "持股价值", value = C.FormatMoney(stakeValue), color = stakeValue > 0 and T.Warning or T.TextMuted},
            }
            if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 and not isActive then
                table.insert(recRows, C.ActionButton {
                    text = "切换经营这家公司",
                    width = "100%",
                    onClick = function()
                        local ok, msg = GD.SwitchCompany(rec.id)
                        GD.AddEvent(msg or (ok and "公司切换成功" or "公司切换失败"), ok and "success" or "warning")
                        navigate(ok and "dashboard" or "personal")
                    end,
                })
            end
            table.insert(portfolioRows, C.Card {children = recRows})
        end
    end
    table.insert(children, C.Card {children = portfolioRows})

    if #portfolio > 0 then
        local saleCards = {}
        local saleOptions = {
            {label = "出售10%持股", pct = 0.10, color = T.Info},
            {label = "出售25%持股", pct = 0.25, color = T.Warning},
            {label = "出售50%持股", pct = 0.50, color = T.Danger},
            {label = "出售全部持股", pct = 1.00, color = T.Danger},
        }
        for _, rec in ipairs(portfolio) do
            local capturedRec = rec
            local recordCompany = rec.state and rec.state.company or {}
            local recordGov = recordCompany.governance
            local recordRatio = rec.founderRatio or 0
            local recordValue = math.max(
                recordGov and (recordGov.lastValuation or 0) or 0,
                rec.totalAssets or recordCompany.totalAssets or 0
            )
            local recordStakeValue = math.floor(recordValue * recordRatio)
            local recordButtons = {}
            for _, opt in ipairs(saleOptions) do
                table.insert(recordButtons, C.ActionButton {
                    text = opt.label,
                    bgColor = opt.color,
                    width = "48%",
                    height = 36,
                    onClick = function()
                        local ok, msg = GV.SellFounderSharesForCompany(GD, capturedRec.id, opt.pct)
                        GD.AddEvent(msg or (ok and "股份出售成功" or "股份出售失败"), ok and "success" or "warning")
                        navigate("personal")
                    end,
                })
            end
            table.insert(saleCards, C.Card {children = {
                UI.Panel {
                    flexDirection = "row", flexWrap = "wrap", justifyContent = "space-between",
                    alignItems = "center", gap = 8, width = "100%",
                    children = {
                        UI.Label {
                            text = capturedRec.name or "未命名公司",
                            fontSize = T.FontBody, fontColor = T.TextPrimary,
                            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
                            whiteSpace = "normal", maxLines = 2,
                        },
                        C.Badge {
                            text = recordRatio >= 0.50 and "可操作" or "仅分红权",
                            variant = recordRatio >= 0.50 and "success" or "warning",
                        },
                    },
                },
                C.InfoRow {label = "当前持股", value = string.format("%.1f%%", recordRatio * 100), color = T.Accent},
                C.InfoRow {label = "持股价值", value = C.FormatMoney(recordStakeValue), color = T.Warning},
                UI.Label {
                    text = recordRatio >= 0.50
                        and "出售后持股低于50%将失去公司控制权，仅保留分红权。"
                        or "当前持股低于50%，已失去控制权，仅可获得后续分红。",
                    fontSize = T.FontCaption, fontColor = T.TextMuted,
                    whiteSpace = "normal", maxLines = 2,
                },
                UI.Panel {flexDirection = "row", flexWrap = "wrap", gap = 8, width = "100%", children = recordButtons},
            }})
        end
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "个人持股出售", color = T.Warning},
            UI.Label {
                text = "按公司分别出售个人持有的股份；出售全部后该公司从列表中移除，持股低于50%仍保留公司记录和分红权，但不能进入经营操作。",
                fontSize = T.FontCaption, fontColor = T.TextMuted,
                whiteSpace = "normal", maxLines = 3,
            },
            UI.Panel {width = "100%", gap = 10, children = saleCards},
        }})
    elseif GD.player then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "继续创业", color = T.Success},
            C.InfoRow {label = "可用个人现金", value = C.FormatMoney(p.cash or 0), color = T.Success},
            UI.Label {
                text = "当前没有正在经营的公司；个人资产、家庭与历史公司记录仍保留，可在任意城市继续注册新公司。",
                fontSize = T.FontCaption,
                fontColor = T.TextMuted,
            },
            C.ActionButton {text = "注册新公司", width = "100%", onClick = function() navigate("companyCreate") end},
        }})
    end

    -- 项目运营概况（已移除）

    -- 固定资产
    if #faCards > 0 then
        table.insert(children, C.SectionTitle {text = "固定资产 (" .. #activeFixedAssets .. ")", color = T.Info})
        for _, card in ipairs(faCards) do table.insert(children, card) end
    end

    -- 收入概览
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "本年收入", color = T.Success},
        C.InfoRow {label = "年度总收入", value = C.FormatMoney(p.yearlyIncome), color = T.Accent},
        C.InfoRow {label = "  工资收入", value = C.FormatMoney(p.yearlySalary), color = T.Success},
        C.InfoRow {label = "  分红收入", value = C.FormatMoney(p.yearlyDividends), color = T.Info},
        C.InfoRow {label = "  投资收益", value = C.FormatMoney(p.yearlyInvestReturn),
            color = p.yearlyInvestReturn >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "  租金收入", value = C.FormatMoney(p.totalRentIncome or 0), color = T.Info},
        totalPmIncome > 0 and C.InfoRow {label = "  物业费收入", value = C.FormatMoney(totalPmIncome), color = T.Info} or nil,
    }})

    -- 累计数据
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "累计数据"},
        C.InfoRow {label = "累计总收入", value = C.FormatMoney(p.totalIncome)},
        C.InfoRow {label = "累计消费支出", value = C.FormatMoney(p.totalSpending or 0), color = T.Warning},
        C.InfoRow {label = "累计个人税款", value = C.FormatMoney(p.totalTax or 0), color = T.Danger},
    }})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab2: 投资理财（保留原有逻辑）
-- ============================================================================
function M._TabInvestment(navigate, p)
    local summary = PS.GetInvestmentSummary(GD)
    M._customInputs = M._customInputs or {}

    -- 宏观经济数据(用于计算调整后利率)
    local macro = GD.economy and GD.economy.macro or nil
    local cycle = GD.economy and GD.economy.cycle or "stable"

    -- 计算预估月收益(使用宏观调整后利率)
    local estMonthlyReturn = 0
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = p.investments[pid]
        local held = inv and inv.amount or 0
        if held > 0 then
            local adjRate = PS._calcMacroAdjustedRate(pid, macro, cycle)
            estMonthlyReturn = estMonthlyReturn + math.floor(held * adjRate)
        end
    end

    local productCards = {}
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local product = PS.INVESTMENT_PRODUCTS[pid]
        local inv = p.investments[pid]
        local held = inv and inv.amount or 0
        -- 宏观调整后的年化利率
        local adjMonthly = PS._calcMacroAdjustedRate(pid, macro, cycle)
        local adjAnnual = adjMonthly * 12
        local rateChange = adjAnnual - product.annualRate
        local monthlyEst = held > 0 and math.floor(held * adjMonthly) or 0

        -- 利率显示: 基准 → 调整后(箭头+变化)
        local rateText = string.format("%.1f%%", adjAnnual * 100)
        local rateVariant = "info"
        if rateChange > 0.005 then
            rateText = rateText .. "↑"
            rateVariant = "success"
        elseif rateChange < -0.005 then
            rateText = rateText .. "↓"
            rateVariant = "danger"
        end

        -- 锁定期显示
        local lockText = nil
        if pid == "trust" and inv.lockMonths and inv.lockMonths > 0 then
            lockText = "锁定中(" .. inv.lockMonths .. "月)"
        elseif pid == "peFund" and inv.lockMonths and inv.lockMonths > 0 then
            lockText = "锁定中(" .. inv.lockMonths .. "月)"
        end

        local cardItems = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = product.icon, fontSize = T.FontSubtitle},
                        UI.Label {text = product.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    }},
                    C.Badge {text = rateText, variant = rateVariant},
                }
            },
            UI.Label {text = product.desc, fontSize = T.FontSmall, fontColor = T.TextMuted},
            C.InfoRow {label = "持有金额", value = C.FormatMoney(held), color = held > 0 and T.Accent or T.TextMuted},
            held > 0 and C.InfoRow {label = "预估月收益", value = C.FormatMoney(monthlyEst), color = monthlyEst >= 0 and T.Success or T.Danger} or nil,
            lockText and C.InfoRow {label = "状态", value = lockText, color = T.Warning} or nil,
            C.InfoRow {label = "流动性", value = product.liquidity},
            C.InfoRow {label = "风险系数", value = product.risk == 0 and "无风险" or string.format("%.1f%%", product.risk * 100),
                color = product.risk == 0 and T.Success or (product.risk <= 0.05 and T.Info or T.Warning)},
        }

        if product.minAmount > 0 then
            table.insert(cardItems, C.InfoRow {label = "最低投资", value = C.FormatMoney(product.minAmount), color = T.TextMuted})
        end

        if pid == "trust" and inv and (inv.lockMonths or 0) > 0 then
            table.insert(cardItems, C.InfoRow {label = "锁定剩余", value = inv.lockMonths .. "个月", color = T.Danger})
        end

        -- 买入按钮
        local buyRow = {}
        local buyAmounts = {100, 500, 1000}
        if pid == "trust" then buyAmounts = {5000, 10000} end
        for _, amt in ipairs(buyAmounts) do
            if amt >= product.minAmount then
                local captureAmt = amt
                local capturePid = pid
                local canAfford = p.cash >= amt
                table.insert(buyRow, UI.Button {
                    text = "买入" .. C.FormatMoney(captureAmt),
                    fontSize = T.FontCaption,
                    backgroundColor = canAfford and T.PrimaryLight or T.DisabledBg,
                    fontColor = canAfford and T.Primary or T.TextMuted,
                    borderRadius = 4, paddingHorizontal = 8, height = 28,
                    onClick = function()
                        local ok, msg = PS.Invest(GD, capturePid, captureAmt)
                        if not ok then GD.AddEvent(msg or "买入失败", "danger") end
                        navigate("personal")
                    end,
                })
            end
        end
        -- 自定义金额买入
        do
            local customKey = "investCustom_" .. pid
            local capturePid = pid
            table.insert(buyRow, UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center",
                children = {
                    UI.TextField {
                        placeholder = "自定义(万)",
                        width = 80, height = 28, fontSize = T.FontCaption,
                        borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                        backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                        value = M._customInputs[customKey] or "",
                        onChange = function(self, text)
                            M._customInputs[customKey] = text
                        end,
                    },
                    UI.Button {
                        text = "买入",
                        fontSize = T.FontCaption,
                        backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                        borderRadius = 4, paddingHorizontal = 8, height = 28,
                        onClick = function()
                            local amt = tonumber(M._customInputs[customKey] or "")
                            if not amt or amt <= 0 then
                                GD.AddEvent("请输入有效金额", "danger")
                                return
                            end
                            local ok, msg = PS.Invest(GD, capturePid, math.floor(amt))
                            if not ok then GD.AddEvent(msg or "买入失败", "danger") end
                            M._customInputs[customKey] = ""
                            navigate("personal")
                        end,
                    },
                },
            })
        end

        table.insert(cardItems, UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 4,
            children = buyRow,
        })

        -- 赎回按钮
        if held > 0 then
            local canRedeem = true
            local lockMsg = nil
            if pid == "trust" and inv and (inv.lockMonths or 0) > 0 then
                canRedeem = false
                lockMsg = "锁定中(" .. inv.lockMonths .. "月)"
            end
            local redeemRow = {}
            local redeemAmounts = {100, 500}
            if pid == "trust" then redeemAmounts = {5000} end
            for _, amt in ipairs(redeemAmounts) do
                if held >= amt then
                    local captureAmt = amt
                    local capturePid = pid
                    table.insert(redeemRow, UI.Button {
                        text = "赎回" .. C.FormatMoney(captureAmt),
                        fontSize = T.FontCaption,
                        backgroundColor = canRedeem and T.BgCard or T.DisabledBg,
                        fontColor = canRedeem and T.TextSecondary or T.TextMuted,
                        borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                        paddingHorizontal = 8, height = 28,
                        onClick = function()
                            local ok, msg = PS.Redeem(GD, capturePid, captureAmt)
                            if not ok then GD.AddEvent(msg or "赎回失败", "danger") end
                            navigate("personal")
                        end,
                    })
                end
            end
            -- 全部赎回
            do
                local capturePid = pid
                local captureHeld = held
                table.insert(redeemRow, UI.Button {
                    text = "全部赎回",
                    fontSize = T.FontCaption,
                    backgroundColor = canRedeem and T.Warning or T.DisabledBg,
                    fontColor = canRedeem and T.TextOnDark or T.TextMuted,
                    borderRadius = 4, paddingHorizontal = 8, height = 28,
                    onClick = function()
                        local ok, msg = PS.Redeem(GD, capturePid, captureHeld)
                        if not ok then GD.AddEvent(msg or "赎回失败", "danger") end
                        navigate("personal")
                    end,
                })
            end
            if lockMsg then
                table.insert(redeemRow, UI.Label {text = lockMsg, fontSize = T.FontCaption, fontColor = T.Danger})
            end
            table.insert(cardItems, UI.Panel {
                flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 2,
                children = redeemRow,
            })
        end

        table.insert(productCards, C.Card {children = cardItems})
    end

    -- 投资历史记录（最近20条）
    local historyRows = {}
    local history = p.investmentHistory or {}
    local startIdx = math.max(1, #history - 19)
    for i = #history, startIdx, -1 do
        local h = history[i]
        local prodName = PS.INVESTMENT_PRODUCTS[h.type] and PS.INVESTMENT_PRODUCTS[h.type].name or h.type
        local actionText = h.action == "buy" and "买入" or "赎回"
        local actionColor = h.action == "buy" and T.Info or T.Warning
        table.insert(historyRows, UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            alignItems = "center", width = "100%", paddingVertical = 3,
            children = {
                UI.Label {text = string.format("第%d年%d月", h.year or 0, h.month or 0),
                    fontSize = T.FontCaption, fontColor = T.TextMuted, width = 80},
                UI.Label {text = actionText .. " " .. prodName,
                    fontSize = T.FontCaption, fontColor = actionColor, flexShrink = 1},
                UI.Label {text = C.FormatMoney(h.amount),
                    fontSize = T.FontCaption, fontColor = T.TextPrimary},
            }
        })
    end

    local children = {
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "可投现金", value = C.FormatMoney(p.cash), color = T.Success, minWidth = 90},
                C.StatCard {title = "投资总额", value = C.FormatMoney(summary.total), color = T.Info, minWidth = 90},
                C.StatCard {title = "预估月收益", value = C.FormatMoney(estMonthlyReturn), color = T.Accent, minWidth = 90},
                C.StatCard {title = "累计收益", value = C.FormatMoney(p.totalInvestReturn),
                    color = p.totalInvestReturn >= 0 and T.Success or T.Danger, minWidth = 90},
            }
        },

        -- 投资组合饼图式概览
        summary.total > 0 and C.Card {children = (function()
            local rows = {C.SectionTitle {text = "持仓分布", color = T.Accent}}
            for _, sp in ipairs(summary.products) do
                if sp.amount > 0 then
                    local pct = math.floor(sp.amount / summary.total * 100)
                    table.insert(rows, C.InfoRow {
                        label = sp.icon .. " " .. sp.name,
                        value = C.FormatMoney(sp.amount) .. " (" .. pct .. "%)",
                        color = T.TextPrimary,
                    })
                end
            end
            return rows
        end)()} or nil,

        C.SectionTitle {text = "投资产品", color = T.Info},
        UI.Panel {width = "100%", gap = 8, children = productCards},
    }

    -- 投资历史
    if #historyRows > 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "交易记录（近20条）", color = T.TextMuted},
            UI.Panel {width = "100%", gap = 2, children = historyRows},
        }})
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab3: 个人房产
-- ============================================================================
function M._TabProperty(navigate, p)
    local props = p.properties or {}
    local totalValue, totalRent = 0, 0
    for _, prop in ipairs(props) do
        totalValue = totalValue + prop.currentValue
        if prop.renting then totalRent = totalRent + math.floor(prop.monthlyRent * (prop.currentValue / prop.purchasePrice)) end
    end

    -- 已持有房产
    local ownedCards = {}
    for i, prop in ipairs(props) do
        local captureIdx = i
        local profit = prop.currentValue - prop.purchasePrice
        local profitPct = prop.purchasePrice > 0 and math.floor(profit / prop.purchasePrice * 100) or 0
        local actualRent = math.floor(prop.monthlyRent * (prop.currentValue / prop.purchasePrice))

        table.insert(ownedCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = prop.icon, fontSize = T.FontSubtitle},
                        UI.Label {text = prop.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    }},
                    C.Badge {text = prop.renting and "出租中" or "自住", variant = prop.renting and "success" or "info"},
                }
            },
            C.InfoRow {label = "买入价", value = C.FormatMoney(prop.purchasePrice)},
            C.InfoRow {label = "当前估值", value = C.FormatMoney(prop.currentValue), color = T.Accent},
            C.InfoRow {label = "浮盈", value = (profit >= 0 and "+" or "") .. C.FormatMoney(profit) .. " (" .. profitPct .. "%)",
                color = profit >= 0 and T.Success or T.Danger},
            C.InfoRow {label = "月租金", value = C.FormatMoney(actualRent) .. "/月", color = T.Info},
            UI.Panel {
                flexDirection = "row", gap = 6, width = "100%", marginTop = 4,
                children = {
                    UI.Button {
                        text = prop.renting and "停止出租" or "出租",
                        fontSize = T.FontCaption,
                        backgroundColor = prop.renting and T.BgCard or T.Success,
                        fontColor = prop.renting and T.TextSecondary or T.TextPrimary,
                        borderRadius = 4, paddingHorizontal = 10, height = 28,
                        borderWidth = prop.renting and 1 or 0, borderColor = T.Border,
                        onClick = function()
                            PS.ToggleRent(GD, captureIdx)
                            navigate("personal")
                        end,
                    },
                    UI.Button {
                        text = "卖出 " .. C.FormatMoney(prop.currentValue),
                        fontSize = T.FontCaption,
                        backgroundColor = T.Warning, fontColor = T.TextOnDark,
                        borderRadius = 4, paddingHorizontal = 10, height = 28,
                        onClick = function()
                            PS.SellProperty(GD, captureIdx)
                            navigate("personal")
                        end,
                    },
                }
            },
        }})
    end

    -- 房源目录
    local catalogCards = {}
    for i, cat in ipairs(PS.PROPERTY_CATALOG) do
        local captureIdx = i
        local downPay = math.floor(cat.price * 0.3)
        table.insert(catalogCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = cat.icon, fontSize = T.FontSubtitle},
                        UI.Label {text = cat.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    }},
                    UI.Label {text = C.FormatMoney(cat.price), fontSize = T.FontBody, fontColor = T.Accent},
                }
            },
            C.InfoRow {label = "月租金", value = C.FormatMoney(cat.rent) .. "/月"},
            C.InfoRow {label = "年增值率", value = string.format("%.0f%%", cat.appreciation * 100)},
            C.InfoRow {label = "首付(30%)", value = C.FormatMoney(downPay)},
            UI.Panel {
                flexDirection = "row", gap = 6, width = "100%", marginTop = 4, flexWrap = "wrap",
                children = {
                    UI.Button {
                        text = "全款购买",
                        fontSize = T.FontCaption,
                        backgroundColor = p.cash >= cat.price and T.PrimaryLight or T.DisabledBg,
                        fontColor = p.cash >= cat.price and T.Primary or T.TextMuted,
                        borderRadius = 4, paddingHorizontal = 10, height = 28,
                        onClick = function()
                            local ok, msg = PS.BuyProperty(GD, captureIdx, false)
                            if not ok then GD.AddEvent(msg or "购买失败", "danger") end
                            navigate("personal")
                        end,
                    },
                    UI.Button {
                        text = "按揭购买(首付" .. C.FormatMoney(downPay) .. ")",
                        fontSize = T.FontCaption,
                        backgroundColor = p.cash >= downPay and T.PrimaryLight or T.DisabledBg,
                        fontColor = p.cash >= downPay and T.Primary or T.TextMuted,
                        borderRadius = 4, paddingHorizontal = 10, height = 28,
                        onClick = function()
                            local ok, msg = PS.BuyProperty(GD, captureIdx, true)
                            if not ok then GD.AddEvent(msg or "购买失败", "danger") end
                            navigate("personal")
                        end,
                    },
                    p.cash < downPay and UI.Label {
                        text = "现金不足" .. C.FormatMoney(p.cash), fontSize = T.FontCaption, fontColor = T.TextMuted,
                    } or nil,
                }
            },
        }})
    end


    -- 汇总子组件
    local children = {
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "房产总值", value = C.FormatMoney(totalValue), color = T.Accent, minWidth = 90},
                C.StatCard {title = "月租收入", value = C.FormatMoney(totalRent), color = T.Success, minWidth = 90},
                C.StatCard {title = "持有数量", value = #props .. "套", color = T.Info, minWidth = 70},
            }
        },
    }

    if #ownedCards > 0 then
        table.insert(children, C.SectionTitle {text = "我的房产 (" .. #props .. "套)", color = T.Accent})
        table.insert(children, UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "一键出租全部房产", bgColor = T.Success, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for i, prop in ipairs(props) do
                        if not prop.renting then
                            local ok = PS.ToggleRent(GD, i)
                            if ok then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键出租个人房产完成：" .. count .. "套", count > 0 and "success" or "info")
                    navigate("personal")
                end,
            },
            C.SecondaryButton {
                text = "一键停租全部房产", height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for i, prop in ipairs(props) do
                        if prop.renting then
                            local ok = PS.ToggleRent(GD, i)
                            if ok then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键停租个人房产完成：" .. count .. "套", count > 0 and "success" or "info")
                    navigate("personal")
                end,
            },
        }})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = ownedCards})
    end


    table.insert(children, C.SectionTitle {text = "房源市场", color = T.Info})
    table.insert(children, UI.Panel {width = "100%", gap = 8, children = catalogCards})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab4: 个人贷款
-- ============================================================================
function M._TabLoan(navigate, p)
    M._customInputs = M._customInputs or {}
    local loans = p.personalLoans or {}
    local totalDebt, totalMonthly = 0, 0
    local totalInterestBurden = 0  -- 剩余总利息估算
    local overdueCount = 0
    for _, loan in ipairs(loans) do
        totalDebt = totalDebt + loan.remaining
        totalMonthly = totalMonthly + loan.monthlyPay
        -- 估算剩余利息 = 月供×剩余月数 - 剩余本金
        local remainInterest = math.max(0, loan.monthlyPay * loan.remainMonths - loan.remaining)
        totalInterestBurden = totalInterestBurden + remainInterest
        if (loan._overdue or 0) > 0 then overdueCount = overdueCount + 1 end
    end

    local inheritanceTax = PS.GetInheritanceTaxStatus(GD)
    local inheritanceLoanTotal = 0
    for _, loan in ipairs(loans) do
        if loan.type == "inheritanceTaxMortgage" then
            inheritanceLoanTotal = inheritanceLoanTotal + math.max(0, loan.remaining or 0)
        end
    end

    -- 已有贷款卡片
    local loanCards = {}
    for i, loan in ipairs(loans) do
        local captureIdx = i
        local paidPct = loan.amount > 0 and math.floor((1 - loan.remaining / loan.amount) * 100) or 0
        local paidAmount = loan.amount - loan.remaining
        local totalCost = loan.monthlyPay * loan.totalMonths
        local totalInterest = math.max(0, totalCost - loan.amount)
        local remainInterest = math.max(0, loan.monthlyPay * loan.remainMonths - loan.remaining)

        table.insert(loanCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = loan.icon or (loan.type == "mortgage" and "🏠" or (loan.type == "carLoan" and "🚗" or (loan.type == "inheritanceTaxMortgage" and "税" or "💳"))), fontSize = T.FontSubtitle},
                        UI.Label {text = loan.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    }},
                    C.Badge {
                        text = loan.remainMonths .. "月",
                        variant = loan.remainMonths <= 12 and "success" or (loan.remainMonths <= 36 and "info" or "warning"),
                    },
                }
            },
            C.InfoRow {label = "贷款总额", value = C.FormatMoney(loan.amount)},
            C.InfoRow {label = "已还本金", value = C.FormatMoney(paidAmount), color = T.Success},
            C.InfoRow {label = "剩余本金", value = C.FormatMoney(loan.remaining), color = T.Warning},
            C.InfoRow {label = "月供", value = C.FormatMoney(loan.monthlyPay), color = T.Danger},
            C.InfoRow {label = "年利率", value = string.format("%.1f%%", loan.rate)},
            C.InfoRow {label = "总利息(估)", value = C.FormatMoney(totalInterest), color = T.TextMuted},
            C.InfoRow {label = "剩余利息(估)", value = C.FormatMoney(remainInterest), color = T.Warning},
            C.ProgressCard {
                title = "还款进度 " .. paidPct .. "%",
                progress = paidPct,
                barColor = paidPct >= 80 and T.Success or T.Accent,
            },
            (loan._overdue or 0) > 0 and UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = "⚠️", fontSize = T.FontBody},
                    UI.Label {
                        text = "逾期" .. loan._overdue .. "次！请保持现金充足",
                        fontSize = T.FontCaption, fontColor = T.Danger,
                    },
                },
            } or nil,
            UI.Button {
                text = "提前还清 " .. C.FormatMoney(loan.remaining),
                fontSize = T.FontCaption,
                backgroundColor = p.cash >= loan.remaining and T.Success or T.DisabledBg,
                fontColor = p.cash >= loan.remaining and T.TextOnDark or T.TextMuted,
                borderRadius = 4, paddingHorizontal = 10, height = 28, marginTop = 4,
                onClick = function()
                    local ok, msg = PS.EarlyRepayPersonalLoan(GD, captureIdx)
                    if not ok then GD.AddEvent(msg or "还款失败", "danger") end
                    navigate("personal")
                end,
            },
        }})
    end

    -- 消费贷申请
    local consumeAmounts = {50, 100, 200, 500}
    local consumeBtns = {}
    for _, amt in ipairs(consumeAmounts) do
        local captureAmt = amt
        local monthlyEst = math.floor(captureAmt * (8.0 / 100 / 12 + 1 / 36))
        table.insert(consumeBtns, UI.Button {
            text = C.FormatMoney(captureAmt) .. "/36月(月供" .. monthlyEst .. "万)",
            fontSize = T.FontCaption,
            backgroundColor = T.PrimaryLight, fontColor = T.Primary,
            borderRadius = 4, paddingHorizontal = 10, height = 28,
            onClick = function()
                local ok, msg = PS.ApplyPersonalLoan(GD, "consumeLoan", captureAmt, 36)
                if not ok then GD.AddEvent(msg or "申请失败", "danger") end
                navigate("personal")
            end,
        })
    end
    -- 自定义金额消费贷
    table.insert(consumeBtns, UI.Panel {
        flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            UI.TextField {
                placeholder = "金额(万)",
                width = 70, height = 28, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["consumeLoan"] or "",
                onChange = function(self, text) M._customInputs["consumeLoan"] = text end,
            },
            UI.Button {
                text = "申请/36月",
                fontSize = T.FontCaption,
                backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                borderRadius = 4, paddingHorizontal = 8, height = 28,
                onClick = function()
                    local amt = tonumber(M._customInputs["consumeLoan"] or "")
                    if not amt or amt <= 0 then
                        GD.AddEvent("请输入有效金额", "danger"); return
                    end
                    local ok, msg = PS.ApplyPersonalLoan(GD, "consumeLoan", math.floor(amt), 36)
                    if not ok then GD.AddEvent(msg or "申请失败", "danger") end
                    M._customInputs["consumeLoan"] = ""
                    navigate("personal")
                end,
            },
        },
    })

    -- 购车贷款申请
    local carLoanAmounts = {30, 200, 800}
    local carLoanBtns = {}
    for _, amt in ipairs(carLoanAmounts) do
        local captureAmt = amt
        local monthlyEst = math.floor(captureAmt * (5.5 / 100 / 12 + 1 / 60))
        table.insert(carLoanBtns, UI.Button {
            text = C.FormatMoney(captureAmt) .. "/60月(月供" .. monthlyEst .. "万)",
            fontSize = T.FontCaption,
            backgroundColor = T.PrimaryLight, fontColor = T.Primary,
            borderRadius = 4, paddingHorizontal = 10, height = 28,
            onClick = function()
                local ok, msg = PS.ApplyPersonalLoan(GD, "carLoan", captureAmt, 60)
                if not ok then GD.AddEvent(msg or "申请失败", "danger") end
                navigate("personal")
            end,
        })
    end
    -- 自定义金额购车贷
    table.insert(carLoanBtns, UI.Panel {
        flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            UI.TextField {
                placeholder = "金额(万)",
                width = 70, height = 28, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["carLoan"] or "",
                onChange = function(self, text) M._customInputs["carLoan"] = text end,
            },
            UI.TextField {
                placeholder = "期(月)",
                width = 60, height = 28, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["carLoanTerm"] or "",
                onChange = function(self, text) M._customInputs["carLoanTerm"] = text end,
            },
            UI.Button {
                text = "申请",
                fontSize = T.FontCaption,
                backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                borderRadius = 4, paddingHorizontal = 8, height = 28,
                onClick = function()
                    local amt = tonumber(M._customInputs["carLoan"] or "")
                    local term = tonumber(M._customInputs["carLoanTerm"] or "") or 60
                    if not amt or amt <= 0 then
                        GD.AddEvent("请输入有效金额", "danger"); return
                    end
                    if term < 1 or term > 60 then
                        GD.AddEvent("期限须在1~60月", "danger"); return
                    end
                    local ok, msg = PS.ApplyPersonalLoan(GD, "carLoan", math.floor(amt), math.floor(term))
                    if not ok then GD.AddEvent(msg or "申请失败", "danger") end
                    M._customInputs["carLoan"] = ""
                    M._customInputs["carLoanTerm"] = ""
                    navigate("personal")
                end,
            },
        },
    })

    local creditSummary = PS.GetPersonalCreditSummary(GD)
    local creditBankCards = {}
    local selectedCreditBank = nil
    for _, bank in ipairs(PS.PERSONAL_CREDIT_BANKS or {}) do
        if bank.id == M._creditBankId then selectedCreditBank = bank end
        local capturedBank = bank
        local isSelected = bank.id == M._creditBankId
        table.insert(creditBankCards, UI.Button {
            text = bank.name .. " " .. string.format("%.1f%%", bank.rate),
            fontSize = T.FontCaption,
            backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isSelected and T.Primary or T.TabInactiveFont,
            borderWidth = 1,
            borderColor = isSelected and T.Primary or T.TabInactiveBorder,
            borderRadius = 4, paddingHorizontal = 8, height = 30,
            onClick = function()
                M._creditBankId = capturedBank.id
                navigate("personal")
            end,
        })
    end
    selectedCreditBank = selectedCreditBank or PS.PERSONAL_CREDIT_BANKS[1]

    local function applyCreditLoan(amount)
        local months = tonumber(M._customInputs["personalCreditTerm"] or "") or 60
        local ok, msg = PS.ApplyPersonalCreditLoan(
            GD,
            M._creditBankId,
            math.floor(tonumber(amount) or 0),
            math.floor(months)
        )
        if not ok then GD.AddEvent(msg or "申请失败", "danger") end
        M._customInputs["personalCreditAmount"] = ""
        navigate("personal")
    end

    local creditApplyControls = {
        UI.TextField {
            placeholder = "贷款金额(万)",
            width = 100, height = 30, fontSize = T.FontCaption,
            borderRadius = 4, borderWidth = 1, borderColor = T.Border,
            backgroundColor = T.BgCard, fontColor = T.TextPrimary,
            value = M._customInputs["personalCreditAmount"] or "",
            onChange = function(self, text) M._customInputs["personalCreditAmount"] = text end,
        },
        UI.TextField {
            placeholder = "期限(月，最高60)",
            width = 110, height = 30, fontSize = T.FontCaption,
            borderRadius = 4, borderWidth = 1, borderColor = T.Border,
            backgroundColor = T.BgCard, fontColor = T.TextPrimary,
            value = M._customInputs["personalCreditTerm"] or "60",
            onChange = function(self, text) M._customInputs["personalCreditTerm"] = text end,
        },
        UI.Button {
            text = "申请信用贷款",
            fontSize = T.FontCaption,
            backgroundColor = creditSummary.availableCredit > 0 and T.PrimaryLight or T.DisabledBg,
            fontColor = creditSummary.availableCredit > 0 and T.Primary or T.TextMuted,
            borderRadius = 4, paddingHorizontal = 10, height = 30,
            onClick = function()
                local amount = tonumber(M._customInputs["personalCreditAmount"] or "")
                if not amount or amount <= 0 then
                    GD.AddEvent("请输入有效贷款金额", "danger")
                    return
                end
                applyCreditLoan(amount)
            end,
        },
        UI.Button {
            text = "申请全部剩余额度",
            fontSize = T.FontCaption,
            backgroundColor = creditSummary.availableCredit > 0 and T.Success or T.DisabledBg,
            fontColor = creditSummary.availableCredit > 0 and T.TextOnDark or T.TextMuted,
            borderRadius = 4, paddingHorizontal = 10, height = 30,
            onClick = function() applyCreditLoan(creditSummary.availableCredit) end,
        },
    }

    -- 负债健康度评估
    local monthlyIncome = math.max(1, p.salary + math.floor((p.yearlyInvestReturn or 0) / 12))
    local debtRatio = totalMonthly > 0 and math.floor(totalMonthly / monthlyIncome * 100) or 0
    local healthLevel = "优秀"
    local healthColor = T.Success
    if debtRatio > 80 then healthLevel = "危险"; healthColor = T.Danger
    elseif debtRatio > 50 then healthLevel = "警告"; healthColor = T.Warning
    elseif debtRatio > 30 then healthLevel = "一般"; healthColor = T.Info end

    local children = {
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "总负债", value = C.FormatMoney(totalDebt), color = totalDebt > 0 and T.Danger or T.Success, minWidth = 80},
                C.StatCard {title = "月供合计", value = C.FormatMoney(totalMonthly), color = T.Warning, minWidth = 80},
                C.StatCard {title = "剩余利息", value = C.FormatMoney(totalInterestBurden), color = T.Info, minWidth = 80},
                C.StatCard {title = "贷款笔数", value = #loans .. "笔", color = T.Info, minWidth = 60},
            }
        },
    }

    -- 贷款状态与遗产税待缴卡片
    if inheritanceTax.active or inheritanceLoanTotal > 0 then
        local taxChildren = {
            C.SectionTitle {text = "遗产税个人处理", color = T.Warning},
        }
        if inheritanceTax.active then
            table.insert(taxChildren, C.InfoRow {
                label = "待缴遗产税",
                value = C.FormatMoney(inheritanceTax.remaining),
                color = inheritanceTax.overdue and T.Danger or T.Warning,
            })
            table.insert(taxChildren, C.InfoRow {
                label = inheritanceTax.overdue and "状态" or "剩余宽限期",
                value = inheritanceTax.overdue
                    and "已逾期，系统将自动办理抵押贷款"
                    or (tostring(inheritanceTax.monthsLeft) .. "个月"),
                color = inheritanceTax.overdue and T.Danger or T.Info,
            })
            table.insert(taxChildren, UI.Button {
                text = "使用个人现金缴纳遗产税",
                backgroundColor = p.cash >= inheritanceTax.remaining and T.Success or T.DisabledBg,
                fontColor = p.cash >= inheritanceTax.remaining and T.TextOnDark or T.TextMuted,
                borderRadius = 4, paddingHorizontal = 10, height = 32,
                onClick = function()
                    local ok, msg = PS.PayInheritanceTax(GD)
                    if not ok then GD.AddEvent(msg or "缴税失败", "danger") end
                    navigate("personal")
                end,
            })
        end
        if inheritanceLoanTotal > 0 then
            table.insert(taxChildren, C.InfoRow {
                label = "遗产税抵押贷款余额",
                value = C.FormatMoney(inheritanceLoanTotal),
                color = T.Danger,
            })
            table.insert(taxChildren, UI.Button {
                text = "提前还清全部遗产税抵押贷款",
                backgroundColor = p.cash >= inheritanceLoanTotal and T.Success or T.DisabledBg,
                fontColor = p.cash >= inheritanceLoanTotal and T.TextOnDark or T.TextMuted,
                borderRadius = 4, paddingHorizontal = 10, height = 32,
                onClick = function()
                    local ok, msg = PS.EarlyRepayInheritanceTaxLoans(GD)
                    if not ok then GD.AddEvent(msg or "还款失败", "danger") end
                    navigate("personal")
                end,
            })
        end
        table.insert(children, C.Card {children = taxChildren})
    end

    -- 负债健康度卡片
    if #loans > 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "负债健康度", color = healthColor},
            C.InfoRow {label = "月收入(估)", value = C.FormatMoney(monthlyIncome)},
            C.InfoRow {label = "月供/收入比", value = debtRatio .. "%", color = healthColor},
            C.InfoRow {label = "健康等级", value = healthLevel, color = healthColor},
            overdueCount > 0 and C.InfoRow {label = "逾期贷款", value = overdueCount .. "笔", color = T.Danger} or nil,
            UI.Label {
                text = debtRatio > 50 and "月供占收入超过50%，建议提前还贷或增加收入" or "负债率健康，请保持良好还款习惯",
                fontSize = T.FontCaption, fontColor = debtRatio > 50 and T.Warning or T.TextMuted, marginTop = 4,
            },
        }})
    end

    if #loanCards > 0 then
        table.insert(children, C.SectionTitle {text = "我的贷款 (" .. #loans .. "笔)", color = T.Warning})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = loanCards})
    end

    table.insert(children, C.SectionTitle {text = "个人信用贷款", color = T.Accent})
    table.insert(children, C.Card {children = {
        UI.Label {
            text = "按个人净资产的70%授信；已使用的个人信用贷款余额会占用额度。不同银行年利率为3.0%~5.0%。",
            fontSize = T.FontSmall, fontColor = T.TextMuted,
            whiteSpace = "normal", maxLines = 3,
        },
        C.InfoRow {label = "个人净资产", value = C.FormatMoney(creditSummary.netWorth), color = T.Info},
        C.InfoRow {label = "总授信额度", value = C.FormatMoney(creditSummary.creditLimit), color = T.Accent},
        C.InfoRow {label = "已用信用额度", value = C.FormatMoney(creditSummary.usedCredit), color = T.Warning},
        C.InfoRow {label = "剩余可贷额度", value = C.FormatMoney(creditSummary.availableCredit), color = T.Success},
        selectedCreditBank and C.InfoRow {
            label = "当前银行",
            value = selectedCreditBank.name .. " · 年利率" .. string.format("%.1f%%", selectedCreditBank.rate),
            color = T.Primary,
        } or nil,
        UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 6,
            children = creditBankCards,
        },
        UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 6,
            children = creditApplyControls,
        },
    }})

    table.insert(children, C.SectionTitle {text = "申请消费贷款", color = T.Info})
    table.insert(children, C.Card {children = {
        UI.Label {text = "💳 无抵押信用贷，最高500万，年利率8.0%，最长36期", fontSize = T.FontSmall, fontColor = T.TextMuted},
        UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 6,
            children = consumeBtns,
        },
    }})

    table.insert(children, C.SectionTitle {text = "申请购车贷款", color = T.Info})
    table.insert(children, C.Card {children = {
        UI.Label {text = "🚗 购车分期，年利率5.5%，最长60期，可自定义期限", fontSize = T.FontSmall, fontColor = T.TextMuted},
        UI.Panel {
            flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 6,
            children = carLoanBtns,
        },
    }})

    -- 贷款产品对比
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "贷款产品对比"},
        UI.Panel {
            width = "100%", gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", width = "100%", paddingVertical = 4,
                    backgroundColor = T.PrimaryLight, borderRadius = 4, paddingHorizontal = 6,
                    children = {
                        UI.Label {text = "类型", fontSize = T.FontCaption, fontColor = T.Primary, width = "30%"},
                        UI.Label {text = "利率", fontSize = T.FontCaption, fontColor = T.Primary, width = "20%"},
                        UI.Label {text = "期限", fontSize = T.FontCaption, fontColor = T.Primary, width = "25%"},
                        UI.Label {text = "限额", fontSize = T.FontCaption, fontColor = T.Primary, width = "25%"},
                    }
                },
                UI.Panel {
                    flexDirection = "row", width = "100%", paddingVertical = 4, paddingHorizontal = 6,
                    children = {
                        UI.Label {text = "信 个人信用贷", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "30%"},
                        UI.Label {text = "3.0%~5.0%", fontSize = T.FontCaption, fontColor = T.Success, width = "20%"},
                        UI.Label {text = "1~60月", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                        UI.Label {text = "净资产70%", fontSize = T.FontCaption, fontColor = T.Accent, width = "25%"},
                    }
                },
                UI.Panel {
                    flexDirection = "row", width = "100%", paddingVertical = 4, paddingHorizontal = 6,
                    children = {
                        UI.Label {text = "🏠 住房按揭", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "30%"},
                        UI.Label {text = "4.2%", fontSize = T.FontCaption, fontColor = T.Success, width = "20%"},
                        UI.Label {text = "360月", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                        UI.Label {text = "购房自动", fontSize = T.FontCaption, fontColor = T.TextMuted, width = "25%"},
                    }
                },
                UI.Panel {
                    flexDirection = "row", width = "100%", paddingVertical = 4, paddingHorizontal = 6,
                    children = {
                        UI.Label {text = "🚗 购车贷款", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "30%"},
                        UI.Label {text = "5.5%", fontSize = T.FontCaption, fontColor = T.Info, width = "20%"},
                        UI.Label {text = "1~60月", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                        UI.Label {text = "无限制", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                    }
                },
                UI.Panel {
                    flexDirection = "row", width = "100%", paddingVertical = 4, paddingHorizontal = 6,
                    children = {
                        UI.Label {text = "💳 消费贷款", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "30%"},
                        UI.Label {text = "8.0%", fontSize = T.FontCaption, fontColor = T.Warning, width = "20%"},
                        UI.Label {text = "36月", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                        UI.Label {text = "500万", fontSize = T.FontCaption, fontColor = T.TextSecondary, width = "25%"},
                    }
                },
            }
        },
        UI.Label {text = "月供不足时将记录逾期，请保持个人现金充足", fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 6},
    }})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab5: 生活消费
-- ============================================================================
function M._TabLifestyle(navigate, p)
    local owned = p.lifestyleItems or {}
    local monthlyCost = 0
    for _, it in ipairs(owned) do monthlyCost = monthlyCost + (it.monthly or 0) end

    -- 声望来源分类统计
    local prestigeByCategory = {car = 0, luxury = 0, travel = 0, social = 0, charity = 0, health = 0, education = 0}
    local categoryNames = {car = "座驾", luxury = "奢侈品", travel = "旅行", social = "社交圈层", charity = "公益慈善", health = "健康管理", education = "教育进修"}
    local categoryIcons = {car = "🚗", luxury = "💎", travel = "🌍", social = "◈", charity = "❤️", health = "✚", education = "▣"}
    local totalPrestigeFromItems = 0
    for _, it in ipairs(owned) do
        local cat = it.category or "luxury"
        prestigeByCategory[cat] = (prestigeByCategory[cat] or 0) + (it.prestige or 0)
        totalPrestigeFromItems = totalPrestigeFromItems + (it.prestige or 0)
    end

    -- 已拥有物品（增加购入时间和资产价值）
    local ownedCards = {}
    local totalOwnedValue = 0
    for i, it in ipairs(owned) do
        local captureIdx = i
        local sellPrice = math.floor(it.price * 0.6)
        totalOwnedValue = totalOwnedValue + sellPrice
        local holdMonths = (GD.totalMonths or 0) - (it.purchaseMonth or 0)
        local holdText = holdMonths > 0 and ("已持有" .. holdMonths .. "个月") or "刚购入"

        table.insert(ownedCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = it.icon, fontSize = T.FontSubtitle},
                        UI.Panel {gap = 2, children = {
                            UI.Label {text = it.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            UI.Label {text = holdText, fontSize = T.FontCaption, fontColor = T.TextMuted},
                        }},
                    }},
                    it.monthly > 0 and C.Badge {text = C.FormatMoney(it.monthly) .. "/月", variant = "warning"} or nil,
                }
            },
            C.InfoRow {label = "购入价", value = C.FormatMoney(it.price)},
            C.InfoRow {label = "当前残值", value = C.FormatMoney(sellPrice), color = T.Info},
            C.InfoRow {label = "声望加成", value = "+" .. it.prestige, color = T.Warning},
            it.monthly > 0 and C.InfoRow {
                label = "累计维护费",
                value = C.FormatMoney(it.monthly * holdMonths),
                color = T.TextMuted,
            } or nil,
            C.SecondaryButton {
                text = "卖出(回收" .. C.FormatMoney(sellPrice) .. ")",
                onClick = function()
                    PS.SellLifestyle(GD, captureIdx)
                    navigate("personal")
                end,
            },
        }})
    end

    -- 按类别分组商品
    local categories = {
        {key = "car",       title = "座驾",     icon = "🚗"},
        {key = "luxury",    title = "奢侈藏品", icon = "💎"},
        {key = "travel",    title = "享乐体验", icon = "🌍"},
        {key = "social",    title = "圈层社交", icon = "◈"},
        {key = "charity",   title = "公益慈善", icon = "❤️"},
        {key = "health",    title = "健康管理", icon = "✚"},
        {key = "education", title = "教育进修", icon = "▣"},
    }
    local shopSections = {}
    for _, cat in ipairs(categories) do
        local items = {}
        for i, item in ipairs(PS.LIFESTYLE_ITEMS) do
            if item.category == cat.key then
                local captureIdx = i
                local alreadyOwned = false
                if not item.consumable then
                    for _, ow in ipairs(owned) do
                        if ow.id == item.id then alreadyOwned = true; break end
                    end
                end
                local effects = {"声望+" .. item.prestige}
                if item.monthly > 0 then table.insert(effects, "月养" .. C.FormatMoney(item.monthly)) end
                if item.healthBoost then table.insert(effects, "健康+" .. item.healthBoost) end
                if item.abilityBoost then table.insert(effects, "能力+" .. item.abilityBoost) end
                if item.identity then table.insert(effects, item.identity) end
                local effectText = C.FormatMoney(item.price) .. " · " .. table.concat(effects, " · ")
                local canBuy = p.cash >= item.price and not alreadyOwned
                table.insert(items, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center", width = "100%",
                    paddingVertical = 6,
                    children = {
                        UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", flexShrink = 1, children = {
                            UI.Label {text = item.icon, fontSize = T.FontBody},
                            UI.Panel {gap = 2, flexShrink = 1, children = {
                                UI.Label {text = item.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                UI.Label {text = effectText,
                                    fontSize = T.FontCaption, fontColor = T.TextMuted},
                            }},
                        }},
                        alreadyOwned and C.Badge {text = "已拥有", variant = "info"} or
                        UI.Button {
                            text = (item.consumable and "体验" or "购买") .. " " .. C.FormatMoney(item.price),
                            fontSize = T.FontCaption,
                            backgroundColor = canBuy and T.PrimaryLight or T.DisabledBg,
                            fontColor = canBuy and T.Primary or T.TextMuted,
                            borderRadius = 4, paddingHorizontal = 10, height = 26,
                            onClick = function()
                                local ok, msg = PS.BuyLifestyle(GD, captureIdx)
                                if not ok then GD.AddEvent(msg or "购买失败", "danger") end
                                navigate("personal")
                            end,
                        },
                    }
                })
            end
        end
        if #items > 0 then
            table.insert(shopSections, C.Card {children = {
                C.SectionTitle {text = cat.icon .. " " .. cat.title, color = T.Info},
                UI.Panel {width = "100%", gap = 2, children = items},
            }})
        end
    end

    local identity = PS.GetSocialIdentity(p)
    local titleCount = 0
    for _ in pairs(p.socialTitles or {}) do titleCount = titleCount + 1 end

    -- 组装子组件列表
    local children = {
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "声望", value = tostring(p.prestige or 0), color = T.Warning, minWidth = 60},
                C.StatCard {title = "月维护费", value = C.FormatMoney(monthlyCost), color = monthlyCost > 0 and T.Danger or T.TextMuted, minWidth = 80},
                C.StatCard {title = "累计消费", value = C.FormatMoney(p.totalSpending or 0), color = T.Info, minWidth = 80},
                C.StatCard {title = "资产残值", value = C.FormatMoney(totalOwnedValue), color = T.Accent, minWidth = 80},
            }
        },
    }

    -- 社会身份卡片
    local titleTexts = {}
    for title in pairs(p.socialTitles or {}) do table.insert(titleTexts, title) end
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "社会身份", color = T.Warning},
        C.InfoRow {label = "当前身份", value = identity.title, color = T.Warning},
        C.InfoRow {label = "身份说明", value = identity.desc, color = T.TextSecondary},
        C.InfoRow {label = "公益捐助", value = C.FormatMoney(p.totalCharity or 0), color = T.Success},
        C.InfoRow {label = "圈层头衔", value = titleCount > 0 and table.concat(titleTexts, " / ") or "暂无", color = titleCount > 0 and T.Info or T.TextMuted},
        UI.Label {
            text = "通过享乐消费、圈层会籍、教育进修和公益慈善提升声望；高声望和高捐助可换取更高社会身份。",
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
        },
    }})

    -- 声望来源分布卡片
    if totalPrestigeFromItems > 0 then
        local prestigeRows = {}
        for _, cat in ipairs(categories) do
            local catPrestige = prestigeByCategory[cat.key] or 0
            if catPrestige > 0 then
                local pct = math.floor(catPrestige / math.max(1, p.prestige or 1) * 100)
                table.insert(prestigeRows, C.InfoRow {
                    label = cat.icon .. " " .. cat.title,
                    value = "+" .. catPrestige .. " (" .. pct .. "%)",
                    color = T.Warning,
                })
            end
        end
        -- 消费型声望（旅行/慈善消耗后声望保留但物品不在持有列表）
        local consumablePrestige = (p.prestige or 0) - totalPrestigeFromItems
        if consumablePrestige > 0 then
            local pct = math.floor(consumablePrestige / math.max(1, p.prestige or 1) * 100)
            table.insert(prestigeRows, C.InfoRow {
                label = "🎯 消费型体验",
                value = "+" .. consumablePrestige .. " (" .. pct .. "%)",
                color = T.Info,
            })
        end
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "声望来源分布", color = T.Warning},
            table.unpack(prestigeRows),
        }})
    end

    -- 消费统计卡片
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "消费数据", color = T.Info},
        C.InfoRow {label = "持有物品数", value = #owned .. "件"},
        C.InfoRow {label = "累计消费总额", value = C.FormatMoney(p.totalSpending or 0), color = T.Accent},
        C.InfoRow {label = "慈善捐赠(累计)", value = C.FormatMoney(p.totalCharity or 0), color = T.Success},
        C.InfoRow {label = "慈善捐赠(本年)", value = C.FormatMoney(p.yearlyCharity or 0), color = T.Info},
        monthlyCost > 0 and C.InfoRow {
            label = "年维护费预估",
            value = C.FormatMoney(monthlyCost * 12),
            color = T.Warning,
        } or nil,
    }})

    if #ownedCards > 0 then
        table.insert(children, C.SectionTitle {text = "我的藏品 (" .. #owned .. "件)", color = T.Accent})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = ownedCards})
    end

    table.insert(children, C.SectionTitle {text = "消费商城", color = T.Info})
    table.insert(children, UI.Panel {width = "100%", gap = 8, children = shopSections})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab6: 薪酬与资金往来
-- ============================================================================
function M._TabCashFlow(navigate, p)
    M._customInputs = M._customInputs or {}
    local companyOptions = PS.GetCompanyFinanceOptions(GD)
    local selectedCompany = nil
    for _, option in ipairs(companyOptions) do
        if tostring(option.id) == tostring(M._cashFlowCompanyId) then
            selectedCompany = option
            break
        end
    end
    if not selectedCompany and GD.activeCompanyId then
        for _, option in ipairs(companyOptions) do
            if tostring(option.id) == tostring(GD.activeCompanyId) then
                selectedCompany = option
                break
            end
        end
    end
    selectedCompany = selectedCompany or companyOptions[1]
    M._cashFlowCompanyId = selectedCompany and selectedCompany.id or nil

    local hasCompany = selectedCompany ~= nil
    local companyCash = selectedCompany and (selectedCompany.cash or 0) or 0
    local companyMonthlyRevenue = selectedCompany and (selectedCompany.monthlyRevenue or 0) or 0
    local selectedSalary = selectedCompany and (selectedCompany.salary or 0) or 0
    local founderRatio = selectedCompany and (selectedCompany.founderRatio or 0) or 0
    local canSetSalary = hasCompany and founderRatio > 0.50
    local isWhollyOwned = hasCompany and founderRatio >= 0.999999
    local maxSalary = math.floor(companyMonthlyRevenue * PS.MAX_SALARY_RATIO)
    if maxSalary < 1 then maxSalary = 50 end

    local companySelectorItems = {}
    for _, option in ipairs(companyOptions) do
        local capturedOption = option
        local isSelected = selectedCompany and tostring(selectedCompany.id) == tostring(option.id)
        table.insert(companySelectorItems, UI.Button {
            text = option.name .. " · 持股" .. string.format("%.1f%%", (option.founderRatio or 0) * 100),
            fontSize = T.FontCaption,
            backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isSelected and T.Primary or T.TabInactiveFont,
            borderWidth = 1,
            borderColor = isSelected and T.Primary or T.TabInactiveBorder,
            borderRadius = 4, paddingHorizontal = 8, height = 32,
            onClick = function()
                M._cashFlowCompanyId = capturedOption.id
                M._customInputs["salary"] = ""
                M._customInputs["inject"] = ""
                M._customInputs["withdraw"] = ""
                navigate("personal")
            end,
        })
    end

    -- === 累计收入统计 ===
    local totalSalary = p.totalSalary or 0
    local totalDividends = p.totalDividends or 0
    local totalInvestReturn = p.totalInvestReturn or 0
    local totalRentIncome = p.totalRentIncome or 0
    local totalIncome = p.totalIncome or 0
    -- 月度收入明细
    local yearlySalary = p.yearlySalary or 0
    local yearlyDividends = p.yearlyDividends or 0
    local yearlyInvestReturn = p.yearlyInvestReturn or 0
    local yearlyIncome = p.yearlyIncome or 0

    -- === 收入构成分析 ===
    local incomeComponents = {
        {name = "工资收入", icon = "💼", total = totalSalary, yearly = yearlySalary, color = T.Accent},
        {name = "分红收入", icon = "💰", total = totalDividends, yearly = yearlyDividends, color = T.Success},
        {name = "投资收益", icon = "📈", total = totalInvestReturn, yearly = yearlyInvestReturn, color = T.Info},
        {name = "租金收入", icon = "🏠", total = totalRentIncome, yearly = 0, color = T.Warning},
    }

    -- 收入占比（基于累计总收入）
    local incomeBreakdownRows = {}
    for _, comp in ipairs(incomeComponents) do
        local pct = totalIncome > 0 and (comp.total / totalIncome * 100) or 0
        local barWidth = totalIncome > 0 and math.max(2, math.floor(comp.total / totalIncome * 100)) or 0
        table.insert(incomeBreakdownRows, UI.Panel {
            width = "100%", gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", width = "100%",
                    children = {
                        UI.Label { text = comp.icon .. " " .. comp.name, fontSize = T.FontSmall, fontColor = T.TextSecondary },
                        UI.Label { text = string.format("%s (%.1f%%)", C.FormatMoney(comp.total), pct), fontSize = T.FontSmall, fontColor = comp.color },
                    },
                },
                UI.Panel {
                    width = "100%", height = 6, borderRadius = 3, backgroundColor = T.TrackBg,
                    children = {
                        UI.Panel { width = barWidth .. "%", height = 6, borderRadius = 3, backgroundColor = comp.color },
                    },
                },
            },
        })
    end

    -- === 月度收支摘要 ===
    local monthlyIncome = (p.salary or 0)
    -- 预估月投资收益(使用宏观调整后利率)
    local estMonthlyInvest = 0
    local macroRef = GD.economy and GD.economy.macro or nil
    local cycleRef = GD.economy and GD.economy.cycle or "stable"
    for pid, inv in pairs(p.investments or {}) do
        local prod = PS.INVESTMENT_PRODUCTS[pid]
        if prod and (inv.amount or 0) > 0 then
            local adjRate = PS._calcMacroAdjustedRate(pid, macroRef, cycleRef)
            estMonthlyInvest = estMonthlyInvest + inv.amount * adjRate
        end
    end
    -- 月租金收入
    local monthlyRent = 0
    for _, prop in ipairs(p.properties or {}) do
        if prop.renting then monthlyRent = monthlyRent + (prop.monthlyRent or 0) end
    end
    -- 月贷款支出
    local monthlyLoanPayment = 0
    for _, loan in ipairs(p.personalLoans or {}) do
        monthlyLoanPayment = monthlyLoanPayment + (loan.monthlyPay or 0)
    end
    -- 月生活消费
    local monthlyLifestyle = 0
    for _, item in ipairs(p.lifestyleItems or {}) do
        monthlyLifestyle = monthlyLifestyle + (item.monthly or 0)
    end
    local totalMonthlyIn = monthlyIncome + estMonthlyInvest + monthlyRent
    local totalMonthlyOut = monthlyLoanPayment + monthlyLifestyle
    local monthlyNet = totalMonthlyIn - totalMonthlyOut

    -- === 薪酬按钮 ===
    local salaryPresets = {0, 10, 30, 50, 100, 200, 500}
    local salaryBtns = {}
    for _, amt in ipairs(salaryPresets) do
        local isActive = (selectedSalary == amt)
        local overLimit = amt > maxSalary
        local captureAmt = amt
        table.insert(salaryBtns, UI.Button {
            text = amt == 0 and "不领薪" or (amt .. "万/月"),
            fontSize = T.FontCaption,
            backgroundColor = isActive and T.PrimaryLight or ((overLimit or not canSetSalary) and T.DisabledBg or T.TabInactiveBg),
            fontColor = isActive and T.Primary or ((overLimit or not canSetSalary) and T.TextMuted or T.TabInactiveFont),
            borderRadius = 4, borderWidth = 1,
            borderColor = isActive and T.PrimaryLight or T.TabInactiveBorder,
            paddingHorizontal = 10, height = 30,
            onClick = function()
                if not canSetSalary then GD.AddEvent("个人持股须大于50%才能设置该公司薪酬", "warning"); return end
                local ok, msg = PS.SetSalary(GD, captureAmt, selectedCompany.id)
                if not ok then GD.AddEvent(msg or "设置失败", "danger") end
                navigate("personal")
            end,
        })
    end
    table.insert(salaryBtns, UI.Panel {
        flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            UI.TextField {
                placeholder = "自定义(万/月)",
                width = 90, height = 30, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["salary"] or "",
                onChange = function(self, text) M._customInputs["salary"] = text end,
            },
            UI.Button {
                text = "设定",
                fontSize = T.FontCaption,
                backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                borderRadius = 4, paddingHorizontal = 8, height = 30,
                onClick = function()
                    if not canSetSalary then GD.AddEvent("个人持股须大于50%才能设置该公司薪酬", "warning"); return end
                    local amt = tonumber(M._customInputs["salary"] or "")
                    if not amt then GD.AddEvent("请输入有效金额", "danger"); return end
                    local ok, msg = PS.SetSalary(GD, math.floor(amt), selectedCompany.id)
                    if not ok then GD.AddEvent(msg or "设置失败", "danger") end
                    M._customInputs["salary"] = ""
                    navigate("personal")
                end,
            },
        },
    })

    -- === 注资按钮 ===
    local injectPresets = {100, 500, 1000, 5000}
    local injectBtns = {}
    for _, amt in ipairs(injectPresets) do
        local captureAmt = amt
        local canAfford = isWhollyOwned and p.cash >= amt
        table.insert(injectBtns, UI.Button {
            text = "注资" .. C.FormatMoney(captureAmt),
            fontSize = T.FontCaption,
            backgroundColor = canAfford and T.PrimaryLight or T.DisabledBg,
            fontColor = canAfford and T.Primary or T.TextMuted,
            borderRadius = 4, paddingHorizontal = 10, height = 30,
            onClick = function()
                if not isWhollyOwned then GD.AddEvent("只有个人持股100%的全资公司才能直接注资", "warning"); return end
                local ok, msg = PS.InjectCapital(GD, captureAmt, selectedCompany.id)
                if not ok then GD.AddEvent(msg or "注资失败", "danger") end
                navigate("personal")
            end,
        })
    end
    table.insert(injectBtns, UI.Panel {
        flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            UI.TextField {
                placeholder = "金额(万)",
                width = 80, height = 30, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["inject"] or "",
                onChange = function(self, text) M._customInputs["inject"] = text end,
            },
            UI.Button {
                text = "注资",
                fontSize = T.FontCaption,
                backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                borderRadius = 4, paddingHorizontal = 8, height = 30,
                onClick = function()
                    if not isWhollyOwned then GD.AddEvent("只有个人持股100%的全资公司才能直接注资", "warning"); return end
                    local amt = tonumber(M._customInputs["inject"] or "")
                    if not amt or amt <= 0 then GD.AddEvent("请输入有效金额", "danger"); return end
                    local ok, msg = PS.InjectCapital(GD, math.floor(amt), selectedCompany.id)
                    if not ok then GD.AddEvent(msg or "注资失败", "danger") end
                    M._customInputs["inject"] = ""
                    navigate("personal")
                end,
            },
        },
    })

    -- === 提取按钮 ===
    local withdrawPresets = {100, 500, 1000, 5000}
    local withdrawBtns = {}
    for _, amt in ipairs(withdrawPresets) do
        local captureAmt = amt
        local canWithdraw = isWhollyOwned and companyCash >= amt
        table.insert(withdrawBtns, UI.Button {
            text = "提取" .. C.FormatMoney(captureAmt),
            fontSize = T.FontCaption,
            backgroundColor = canWithdraw and T.Success or T.DisabledBg,
            fontColor = canWithdraw and T.TextOnDark or T.TextMuted,
            borderRadius = 4, paddingHorizontal = 10, height = 30,
            onClick = function()
                if not isWhollyOwned then GD.AddEvent("只有个人持股100%的全资公司才能提取资金", "warning"); return end
                local ok, msg = PS.WithdrawFromCompany(GD, captureAmt, selectedCompany.id)
                if not ok then GD.AddEvent(msg or "提取失败", "danger") end
                navigate("personal")
            end,
        })
    end
    table.insert(withdrawBtns, UI.Panel {
        flexDirection = "row", gap = 4, alignItems = "center",
        children = {
            UI.TextField {
                placeholder = "金额(万)",
                width = 80, height = 30, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs["withdraw"] or "",
                onChange = function(self, text) M._customInputs["withdraw"] = text end,
            },
            UI.Button {
                text = "提取",
                fontSize = T.FontCaption,
                backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                borderRadius = 4, paddingHorizontal = 8, height = 30,
                onClick = function()
                    if not isWhollyOwned then GD.AddEvent("只有个人持股100%的全资公司才能提取资金", "warning"); return end
                    local amt = tonumber(M._customInputs["withdraw"] or "")
                    if not amt or amt <= 0 then GD.AddEvent("请输入有效金额", "danger"); return end
                    local ok, msg = PS.WithdrawFromCompany(GD, math.floor(amt), selectedCompany.id)
                    if not ok then GD.AddEvent(msg or "提取失败", "danger") end
                    M._customInputs["withdraw"] = ""
                    navigate("personal")
                end,
            },
        },
    })

    -- === 构建页面 ===
    local children = {
        -- 顶部统计卡片（4列）
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "个人现金", value = C.FormatMoney(p.cash), color = T.Success, minWidth = 90},
                C.StatCard {title = "当前月薪", value = p.salary > 0 and (p.salary .. "万/月") or "未设定", color = T.Accent, minWidth = 90},
                C.StatCard {title = "累计总收入", value = C.FormatMoney(totalIncome), color = T.Info, minWidth = 90},
                C.StatCard {title = "月净现金流", value = C.FormatMoney(monthlyNet), color = monthlyNet >= 0 and T.Success or T.Danger, minWidth = 90},
            }
        },

        C.Card {children = {
            C.SectionTitle {text = "选择操作公司", color = T.Accent},
            UI.Label {
                text = "薪酬设置要求个人持股大于50%；向公司注资和从公司提取仅限个人持股100%的全资公司。",
                fontSize = T.FontSmall, fontColor = T.TextMuted,
                whiteSpace = "normal", maxLines = 3,
            },
            selectedCompany and C.InfoRow {
                label = "当前选择",
                value = selectedCompany.name .. " · " .. selectedCompany.city,
                color = T.Primary,
            } or nil,
            selectedCompany and C.InfoRow {
                label = "个人持股",
                value = string.format("%.1f%%", founderRatio * 100),
                color = isWhollyOwned and T.Success or (canSetSalary and T.Info or T.Warning),
            } or nil,
            UI.Panel {
                flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 4,
                children = companySelectorItems,
            },
            #companyOptions == 0 and UI.Label {
                text = "暂无仍持股的已成立公司",
                fontSize = T.FontSmall, fontColor = T.Warning,
            } or nil,
        }},

        -- 月度收支摘要
        C.Card {children = {
            C.SectionTitle {text = "月度收支摘要", color = T.Info},
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginBottom = 4,
                children = {
                    UI.Label { text = "收入项", fontSize = T.FontSmall, fontColor = T.Success },
                    UI.Label { text = "金额(万/月)", fontSize = T.FontSmall, fontColor = T.TextMuted },
                },
            },
            C.InfoRow {label = "💼 工资收入", value = C.FormatMoney(monthlyIncome), color = T.Accent},
            C.InfoRow {label = "📈 预估投资收益", value = C.FormatMoney(math.floor(estMonthlyInvest * 100) / 100), color = T.Info},
            C.InfoRow {label = "🏠 租金收入", value = C.FormatMoney(monthlyRent), color = T.Warning},
            UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 },
            C.InfoRow {label = "合计月收入", value = C.FormatMoney(math.floor(totalMonthlyIn * 100) / 100), color = T.Success},
            UI.Panel { width = "100%", height = 8 },
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginBottom = 4,
                children = {
                    UI.Label { text = "支出项", fontSize = T.FontSmall, fontColor = T.Danger },
                    UI.Label { text = "金额(万/月)", fontSize = T.FontSmall, fontColor = T.TextMuted },
                },
            },
            C.InfoRow {label = "🏦 贷款月供", value = C.FormatMoney(monthlyLoanPayment), color = T.Danger},
            C.InfoRow {label = "🛍 生活消费", value = C.FormatMoney(monthlyLifestyle), color = T.Warning},
            UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 },
            C.InfoRow {label = "合计月支出", value = C.FormatMoney(math.floor(totalMonthlyOut * 100) / 100), color = T.Danger},
            UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 },
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                backgroundColor = monthlyNet >= 0 and T.SuccessBg or T.DangerBg,
                borderRadius = 6, paddingHorizontal = 10, paddingVertical = 6,
                children = {
                    UI.Label { text = "月净现金流", fontSize = T.FontBody, fontColor = T.TextPrimary },
                    UI.Label {
                        text = (monthlyNet >= 0 and "+" or "") .. C.FormatMoney(math.floor(monthlyNet * 100) / 100),
                        fontSize = T.FontBody, fontColor = monthlyNet >= 0 and T.Success or T.Danger,
                    },
                },
            },
        }},

        -- 薪酬设置
        C.Card {children = {
            C.SectionTitle {text = "💼 薪酬设置", color = T.Accent},
            UI.Label {
                text = string.format("月薪上限: %s（公司月营收的5%%）", C.FormatMoney(maxSalary)),
                fontSize = T.FontSmall, fontColor = T.TextMuted,
            },
            C.InfoRow {label = "当前月薪", value = selectedSalary > 0 and (selectedSalary .. "万/月") or "未设定", color = T.Accent},
            C.InfoRow {label = "公司现金", value = C.FormatMoney(companyCash), color = hasCompany and T.Info or T.TextMuted},
            UI.Panel {
                flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 4,
                children = salaryBtns,
            },
            UI.Label {
                text = canSetSalary
                    and "工资从所选公司现金支出，每月自动发放到个人账户"
                    or "当前公司个人持股不超过50%，不能设置薪酬",
                fontSize = T.FontCaption,
                fontColor = canSetSalary and T.TextMuted or T.Warning,
                marginTop = 4,
            },
        }},

        -- 向公司注资
        C.Card {children = {
            C.SectionTitle {text = "💸 向公司注资", color = T.Warning},
            UI.Label {
                text = isWhollyOwned
                    and "将个人现金注入所选全资公司，增加公司运营资金"
                    or "当前公司不是个人持股100%的全资公司，不能直接注资",
                fontSize = T.FontSmall,
                fontColor = isWhollyOwned and T.TextMuted or T.Warning,
            },
            C.InfoRow {label = "个人可用现金", value = C.FormatMoney(p.cash), color = T.Success},
            UI.Panel {
                flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 4,
                children = injectBtns,
            },
        }},

        -- 从公司提取
        C.Card {children = {
            C.SectionTitle {text = "🏧 从公司提取", color = T.Success},
            UI.Label {
                text = isWhollyOwned
                    and "从所选全资公司账户提取资金到个人账户"
                    or "当前公司不是个人持股100%的全资公司，不能提取资金",
                fontSize = T.FontSmall,
                fontColor = isWhollyOwned and T.TextMuted or T.Warning,
            },
            C.InfoRow {label = "公司可用现金", value = C.FormatMoney(companyCash), color = hasCompany and T.Info or T.TextMuted},
            UI.Panel {
                flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 4,
                children = withdrawBtns,
            },
        }},
    }

    -- 收入构成分析卡片
    if totalIncome > 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "收入构成分析", color = T.Accent},
            UI.Label {
                text = "累计总收入: " .. C.FormatMoney(totalIncome),
                fontSize = T.FontSmall, fontColor = T.TextMuted, marginBottom = 6,
            },
            table.unpack(incomeBreakdownRows),
        }})
    end

    -- 年度收入对比（本年 vs 累计）
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "年度收入明细"},
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%", marginBottom = 4,
            children = {
                UI.Label { text = "收入项", fontSize = T.FontSmall, fontColor = T.TextMuted },
                UI.Label { text = "本年 / 累计", fontSize = T.FontSmall, fontColor = T.TextMuted },
            },
        },
        C.InfoRow {label = "💼 工资", value = C.FormatMoney(yearlySalary) .. " / " .. C.FormatMoney(totalSalary), color = T.Accent},
        C.InfoRow {label = "💰 分红", value = C.FormatMoney(yearlyDividends) .. " / " .. C.FormatMoney(totalDividends), color = T.Success},
        C.InfoRow {label = "📈 投资收益", value = C.FormatMoney(yearlyInvestReturn) .. " / " .. C.FormatMoney(totalInvestReturn), color = T.Info},
        C.InfoRow {label = "🏠 租金", value = "-- / " .. C.FormatMoney(totalRentIncome), color = T.Warning},
        UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 },
        C.InfoRow {label = "合计", value = C.FormatMoney(yearlyIncome) .. " / " .. C.FormatMoney(totalIncome), color = T.TextPrimary},
    }})

    -- 资金流向说明
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "资金流向说明"},
        C.InfoRow {label = "公司 -> 个人", value = "工资、分红、提取"},
        C.InfoRow {label = "个人 -> 公司", value = "注资"},
        C.InfoRow {label = "个人 -> 市场", value = "投资、购房、消费"},
        C.InfoRow {label = "市场 -> 个人", value = "投资收益、租金、卖出"},
    }})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab7: 个人税务
-- ============================================================================
function M._TabTax(navigate, p)
    local yearlyIncome = p.yearlyIncome or 0
    local taxSummary = PS.GetPersonalTaxSummary(GD, yearlyIncome)
    local adjustedIncome = taxSummary.taxableIncome
    local adjustedTax = taxSummary.taxDue
    local deductions = taxSummary.acceptedDeductions
    local savedTax = taxSummary.taxSaved
    local isSettled = p.lastTaxSettlementYear == GD.year

    local deductionItems = {}
    for _, item in ipairs((taxSummary.advice and taxSummary.advice.advice) or {}) do
        if (item.acceptedDeduction or 0) > 0 then
            table.insert(deductionItems, C.InfoRow {
                label = item.name,
                value = C.FormatMoney(item.acceptedDeduction),
                color = T.Success,
            })
        end
    end

    -- 税率速算表：每一档仅对落入该区间的收入部分按对应税率计税
    local bracketRows = {}
    for index, bracket in ipairs(PS.TAX_BRACKETS) do
        local nextBracket = PS.TAX_BRACKETS[index + 1]
        local rangeText = nextBracket
            and (C.FormatMoney(bracket.threshold) .. "~" .. C.FormatMoney(nextBracket.threshold))
            or (C.FormatMoney(bracket.threshold) .. "以上")
        table.insert(bracketRows, C.InfoRow {
            label = rangeText,
            value = string.format("%.0f%%", bracket.rate * 100),
        })
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "本年应税收入", value = C.FormatMoney(yearlyIncome), color = T.Info, minWidth = 100},
                    C.StatCard {title = isSettled and "本年已缴" or "预计应缴", value = C.FormatMoney(adjustedTax), color = T.Danger, minWidth = 90},
                    C.StatCard {title = "累计已缴", value = C.FormatMoney(p.totalTax or 0), color = T.Warning, minWidth = 90},
                }
            },

            (function()
                local rows = {
                    C.SectionTitle {text = "本年度税务测算", color = T.Warning},
                    C.InfoRow {label = "年度总收入", value = C.FormatMoney(yearlyIncome)},
                    C.InfoRow {label = "  工资", value = C.FormatMoney(p.yearlySalary)},
                    C.InfoRow {label = "  分红", value = C.FormatMoney(p.yearlyDividends)},
                    C.InfoRow {label = "  投资收益", value = C.FormatMoney(math.max(0, p.yearlyInvestReturn))},
                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                    C.InfoRow {label = "税前应税", value = C.FormatMoney(yearlyIncome), color = T.TextPrimary},
                }
                if #deductionItems > 0 then
                    table.insert(rows, C.SectionTitle {text = "减免项目", color = T.Success})
                    for _, di in ipairs(deductionItems) do table.insert(rows, di) end
                end
                if deductions > 0 then
                    table.insert(rows, C.InfoRow {label = "总减免", value = C.FormatMoney(deductions), color = T.Success})
                end
                table.insert(rows, C.InfoRow {label = "应纳税所得额", value = C.FormatMoney(adjustedIncome), color = T.Warning})
                table.insert(rows, C.InfoRow {
                    label = isSettled and "本年已自动扣缴" or "预计应缴个人所得税",
                    value = C.FormatMoney(adjustedTax),
                    color = T.Danger,
                })
                if savedTax > 0 then
                    table.insert(rows, C.InfoRow {label = "节税", value = C.FormatMoney(savedTax), color = T.Success})
                end
                table.insert(rows, UI.Label {
                    text = isSettled
                        and (tostring(GD.year) .. "年度个税已按超额累进区间自动从个人账户扣缴")
                        or "每年12月收入全部入账后，按超额累进区间自动从个人账户扣缴",
                    fontSize = T.FontCaption,
                    fontColor = isSettled and T.Success or T.TextMuted,
                    marginTop = 4,
                })
                return C.Card {children = rows}
            end)(),

            -- 合法税前扣除说明
            C.Card {children = {
                C.SectionTitle {text = "合法税前扣除", color = T.Success},
                UI.Label {
                    text = "公益捐赠、教育、医疗、赡养老人与住房贷款利息等已登记且符合上限的凭证，会在12月汇算时自动抵扣应税收入。",
                    fontSize = T.FontSmall,
                    fontColor = T.TextSecondary,
                    whiteSpace = "normal",
                    maxLines = 3,
                },
            }},

            -- 税率表
            (function()
                local rows = { C.SectionTitle {text = "个人所得税税率表（超额累进）"} }
                for _, br in ipairs(bracketRows) do table.insert(rows, br) end
                return C.Card {children = rows}
            end)(),
        }
    }
end

-- ============================================================================
-- Tab8: 成就与里程碑
-- ============================================================================
function M._TabMilestones(navigate, p)
    local unlocked = p.unlockedMilestones or {}
    local unlockedCount = 0
    for _ in pairs(unlocked) do unlockedCount = unlockedCount + 1 end
    local totalCount = #PS.MILESTONES

    local milestoneCards = {}
    for _, ms in ipairs(PS.MILESTONES) do
        local isUnlocked = unlocked[ms.id] ~= nil
        local unlockMonth = unlocked[ms.id]
        local unlockText = ""
        if isUnlocked and unlockMonth then
            local y = math.floor(unlockMonth / 12) + 1
            local m = (unlockMonth % 12) + 1
            unlockText = "第" .. y .. "年" .. m .. "月解锁"
        end

        table.insert(milestoneCards, UI.Panel {
            flexDirection = "row", gap = 10, alignItems = "center",
            width = "100%", paddingVertical = 8, paddingHorizontal = 10,
            backgroundColor = isUnlocked and T.SuccessBg or T.BgCard,
            borderRadius = 8,
            borderWidth = isUnlocked and 1 or 0,
            borderColor = isUnlocked and T.Success or nil,
            children = {
                UI.Label {
                    text = isUnlocked and ms.icon or "?",
                    fontSize = 24,
                    width = 36, textAlign = "center",
                },
                UI.Panel {gap = 2, flexShrink = 1, children = {
                    UI.Label {
                        text = isUnlocked and ms.name or "???",
                        fontSize = T.FontBody,
                        fontColor = isUnlocked and T.TextPrimary or T.TextMuted,
                    },
                    UI.Label {
                        text = isUnlocked and ms.desc or "继续游戏解锁...",
                        fontSize = T.FontCaption,
                        fontColor = isUnlocked and T.TextSecondary or T.TextMuted,
                    },
                    isUnlocked and unlockText ~= "" and UI.Label {
                        text = unlockText,
                        fontSize = T.FontCaption, fontColor = T.Success,
                    } or nil,
                }},
            }
        })
    end

    -- 进度
    local progressPct = totalCount > 0 and math.floor(unlockedCount / totalCount * 100) or 0

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "已解锁", value = unlockedCount .. "/" .. totalCount, color = T.Success, minWidth = 90},
                    C.StatCard {title = "声望", value = tostring(p.prestige or 0), color = T.Warning, minWidth = 70},
                    C.StatCard {title = "完成度", value = progressPct .. "%", color = T.Accent, minWidth = 70},
                }
            },

            C.ProgressCard {
                title = "成就进度",
                progress = progressPct,
                barColor = progressPct >= 80 and T.Success or T.Accent,
            },

            C.SectionTitle {text = "里程碑列表", color = T.Accent},
            UI.Panel {width = "100%", gap = 6, children = milestoneCards},
        }
    }
end

local function IdentityEditCard(navigate, key, title, currentName, currentGender, onApply)
    M._customInputs = M._customInputs or {}
    local nameKey = key .. "Name"
    local genderKey = key .. "Gender"
    if M._customInputs[genderKey] == nil then M._customInputs[genderKey] = currentGender or "" end
    local genderValue = M._customInputs[genderKey] or currentGender or ""
    local genderText = currentGender == "male" and "男" or (currentGender == "female" and "女" or "未设置")
    return C.Card {children = {
        UI.Label {text = title .. "（当前：" .. tostring(currentName or "未命名") .. " / " .. genderText .. "）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
        UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", alignItems = "center", children = {
            UI.TextField {
                placeholder = "新姓名（留空则只改性别）",
                width = 160, height = 32, fontSize = T.FontCaption,
                borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                value = M._customInputs[nameKey] or "",
                onChange = function(self, text) M._customInputs[nameKey] = text end,
            },
            C.ActionButton {text = "设为男", bgColor = genderValue == "male" and T.Primary or T.Info, onClick = function()
                M._customInputs[genderKey] = "male"
                if navigate then navigate("personal") end
            end},
            C.ActionButton {text = "设为女", bgColor = genderValue == "female" and T.Primary or T.Accent, onClick = function()
                M._customInputs[genderKey] = "female"
                if navigate then navigate("personal") end
            end},
            C.ActionButton {text = "保存", bgColor = T.Success, onClick = function()
                local ok, msg = onApply(M._customInputs[nameKey] or "", M._customInputs[genderKey] or currentGender)
                if ok then
                    M._customInputs[nameKey] = ""
                elseif msg then
                    GD.AddEvent(msg, "warning")
                end
                if navigate then navigate("personal") end
            end},
        }},
    }}
end

-- ============================================================================
-- Tab 9: 家庭
-- ============================================================================
function M._TabFamily(navigate, p)
    M._customInputs = M._customInputs or {}

    local fam = p.family
    if not fam then
        fam = PS.InitFamilyData()
        p.family = fam
    end

    local cards = {}

    -- ══════════════════════════════════════════════════════════════════════════
    -- 1) 生命周期面板（能力/效率/生活方式）
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "生命周期", color = T.Accent})

    local healthPct = p.founderHealth or 95
    local healthColor = healthPct >= 70 and T.Success or (healthPct >= 40 and T.Warning or T.Danger)
    local ageText = tostring(p.founderAge or 30) .. "岁"
    local genText = "第" .. tostring(p.generation or 1) .. "代"
    local statusText = p.founderAlive and "在任" or "已故"
    local abilityVal = math.floor(p.founderAbility or 50)
    local efficiency, expBonus = PS.GetAbilityEfficiency(p.founderAge or 18)
    -- 健康对效率的影响
    if healthPct < 60 then
        efficiency = efficiency * (0.5 + healthPct / 120)
    end
    local effPct = math.floor(efficiency * 100)
    local effColor = effPct >= 90 and T.Success or (effPct >= 60 and T.Warning or T.Danger)

    local curMode = p.lifestyleMode or "balanced"
    local modeCfg = PS.LIFESTYLE_MODES[curMode]

    table.insert(cards, C.InfoCard {title = "掌门人状态", rows = {
        {label = "当前掌门", value = p.founderName or p.successorName or "创始人"},
        {label = "性别", value = p.founderGender == "male" and "男" or "女"},
        {label = "世代", value = genText},
        {label = "年龄", value = ageText},
        {label = "状态", value = statusText},
        {label = "健康度", value = tostring(healthPct) .. "/100", color = healthColor},
        {label = "综合能力", value = tostring(abilityVal) .. "/100"},
        {label = "决策效率", value = tostring(effPct) .. "%", color = effColor},
        {label = "生活方式", value = (modeCfg and modeCfg.icon or "") .. " " .. (modeCfg and modeCfg.name or "平衡")},
    }})
    table.insert(cards, IdentityEditCard(navigate, "founderIdentity", "修改掌门人姓名/性别", p.founderName or p.successorName or "创始人", p.founderGender, function(name, gender)
        return PS.UpdateFounderIdentity(GD, name, gender)
    end))

    table.insert(cards, C.ProgressCard {
        title = "健康值",
        progress = healthPct,
        barColor = healthColor,
    })

    -- 荣誉董事长
    if p.honoraryChairman then
        local hc = p.honoraryChairman
        table.insert(cards, C.InfoCard {title = "荣誉董事长", rows = {
            {label = "姓名", value = hc.name or "前掌门"},
            {label = "退休年龄", value = tostring(hc.age or 0) .. "岁"},
            {label = "退休年份", value = "第" .. tostring(hc.retiredYear or 0) .. "年"},
            {label = "声望加成", value = "+15"},
        }})
    end

    -- 生活方式切换
    table.insert(cards, UI.Panel {
        width = "100%", gap = 4,
        children = {
            UI.Label {text = "生活方式切换", fontSize = T.FontSmall, fontColor = T.TextSecondary},
            UI.Label {text = modeCfg and modeCfg.desc or "", fontSize = T.FontSmall, fontColor = T.TextSecondary},
        }
    })
    local lifestyleBtns = {}
    for _, modeKey in ipairs({"healthy", "workaholic", "balanced"}) do
        local cfg = PS.LIFESTYLE_MODES[modeKey]
        local isActive = curMode == modeKey
        table.insert(lifestyleBtns, C.ActionButton {
            text = cfg.icon .. " " .. cfg.name,
            variant = isActive and "primary" or "secondary",
            flex = 1, minWidth = 90,
            onClick = function()
                PS.SetLifestyleMode(GD, modeKey)
                if navigate then navigate("personal") end
            end
        })
    end
    table.insert(cards, UI.Panel {
        width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap",
        children = lifestyleBtns,
    })

    -- 继承人预览（55岁以上）
    if (p.founderAge or 0) >= 55 and fam then
        local heirName = "暂无"
        local bestAbility = -1
        for _, child in ipairs(fam.children or {}) do
            local ability = child.ability or 30
            if ability > bestAbility then
                bestAbility = ability
                heirName = child.name .. "（" .. child.age .. "岁，能力" .. math.floor(ability) .. "）"
            end
        end
        local heirColor = heirName == "暂无" and T.Danger or T.Success
        table.insert(cards, UI.Panel {
            width = "100%", padding = 10, backgroundColor = T.CardBg, borderRadius = T.Radius,
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {text = "法定继承人", fontSize = T.FontBody, fontColor = T.TextSecondary},
                UI.Label {text = heirName, fontSize = T.FontBody, fontColor = heirColor, fontWeight = "bold"},
            }
        })
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 2) 婚姻状态
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "婚姻", color = T.Info})

    if fam.married and fam.spouse then
        local sp = fam.spouse
        local spouseRows = {
            {label = "状态", value = "已婚"},
            {label = "配偶", value = sp.name or "未知"},
            {label = "性别", value = sp.gender == "male" and "男" or "女"},
            {label = "年龄", value = tostring(sp.age or 0) .. "岁"},
            {label = "职业", value = sp.job or "无"},
            {label = "月收入", value = string.format("%.1f万", sp.monthlyIncome or 0)},
        }
        if sp.personality then table.insert(spouseRows, {label = "性格", value = sp.personality}) end
        if sp.appearance then table.insert(spouseRows, {label = "外貌", value = sp.appearance}) end
        table.insert(cards, C.InfoCard {title = "婚姻状态", rows = spouseRows})
        table.insert(cards, IdentityEditCard(navigate, "spouseIdentity", "修改配偶姓名/性别", sp.name or "配偶", sp.gender, function(name, gender)
            return PS.UpdateSpouseIdentity(GD, name, gender)
        end))
        table.insert(cards, C.ActionButton {
            text = "离婚", variant = "danger", width = "100%",
            onClick = function()
                PS.Divorce(GD)
                if navigate then navigate("personal") end
            end
        })
    else
        table.insert(cards, C.InfoCard {title = "婚姻状态", rows = {{label = "状态", value = "未婚"}}})
        local candidates = fam.datingCandidates
        if candidates and #candidates > 0 then
            table.insert(cards, C.SectionTitle {text = "相亲候选人", color = T.Accent})
            for i, cand in ipairs(candidates) do
                local starStr = string.rep("★", cand.familyBackground or 3) .. string.rep("☆", 5 - (cand.familyBackground or 3))
                table.insert(cards, C.InfoCard {
                    title = cand.name .. "（" .. (cand.gender == "male" and "男" or "女") .. "）",
                    rows = {
                        {label = "年龄", value = tostring(cand.age) .. "岁"},
                        {label = "职业", value = cand.job or "无"},
                        {label = "月收入", value = string.format("%.1f万", cand.monthlyIncome or 0)},
                        {label = "性格", value = cand.personality or "未知"},
                        {label = "外貌", value = cand.appearance or "未知"},
                        {label = "家境", value = starStr},
                        {label = "缘分值", value = tostring(cand.chemistry or 0) .. "/100"},
                    }
                })
                table.insert(cards, C.ActionButton {
                    text = "选择 " .. cand.name, variant = "primary", width = "100%",
                    onClick = function()
                        PS.MarryCandidate(GD, i)
                        if navigate then navigate("personal") end
                    end
                })
            end
            table.insert(cards, C.ActionButton {
                text = "重新相亲（花费" .. PS.BLIND_DATE_COST .. "万）", variant = "secondary", width = "100%",
                onClick = function()
                    PS.BlindDate(GD)
                    if navigate then navigate("personal") end
                end
            })
        else
            table.insert(cards, C.ActionButton {
                text = "去相亲（花费" .. PS.BLIND_DATE_COST .. "万）", variant = "primary", width = "100%",
                onClick = function()
                    PS.BlindDate(GD)
                    if navigate then navigate("personal") end
                end
            })
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 3) 子女区域（含培养项目）
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "子女", color = T.Accent})

    local children = fam.children or {}
    if #children > 0 then
        for i, child in ipairs(children) do
            local stage = PS.GetEducationStage(child.age)
            local genderText = child.gender == "male" and "男" or "女"
            local adoptTag = child.adopted and " [养]" or ""
            local childAbility = math.floor(child.ability or 30)
            local curTraining = child.training
            local trainName = "无"
            if curTraining and PS.CHILD_TRAINING[curTraining] then
                trainName = PS.CHILD_TRAINING[curTraining].icon .. " " .. PS.CHILD_TRAINING[curTraining].name
            end

            local childRows = {
                {label = "性别", value = genderText},
                {label = "年龄", value = tostring(child.age) .. "岁"},
                {label = "能力值", value = tostring(childAbility) .. "/100"},
                {label = "教育阶段", value = stage.name},
                {label = "月教育支出", value = string.format("%.1f万", stage.monthlyCost)},
                {label = "当前培养", value = trainName},
            }
            if (child.age or 0) >= 18 then
                table.insert(childRows, {label = "婚姻", value = child.married and "已成家" or "未婚", color = child.married and T.Success or T.TextMuted})
            end
            if child.spouse then
                table.insert(childRows, {label = "配偶", value = (child.spouse.name or "未知") .. "（" .. tostring(child.spouse.age or 0) .. "岁）"})
                table.insert(childRows, {label = "配偶职业", value = child.spouse.job or "无"})
            end
            if child.children and #child.children > 0 then
                local grandNames = {}
                for _, grandchild in ipairs(child.children) do
                    table.insert(grandNames, (grandchild.name or "第三代") .. "(" .. tostring(grandchild.age or 0) .. "岁)")
                end
                table.insert(childRows, {label = "子女", value = table.concat(grandNames, "、"), color = T.Success})
            end

            table.insert(cards, C.InfoCard {
                title = child.name .. "（" .. genderText .. "）" .. adoptTag,
                rows = childRows
            })
            table.insert(cards, IdentityEditCard(navigate, "childIdentity" .. i, "修改子女姓名/性别", child.name or "子女", child.gender, function(name, gender)
                return PS.UpdateChildIdentity(GD, i, name, gender)
            end))
            if child.spouse then
                table.insert(cards, IdentityEditCard(navigate, "childSpouseIdentity" .. i, "修改子女配偶姓名/性别", child.spouse.name or "子女配偶", child.spouse.gender, function(name, gender)
                    return PS.UpdateChildSpouseIdentity(GD, i, name, gender)
                end))
            end
            if child.children and #child.children > 0 then
                for gi, grandchild in ipairs(child.children) do
                    table.insert(cards, IdentityEditCard(navigate, "grandchildIdentity" .. i .. "_" .. gi, "修改第三代姓名/性别", grandchild.name or "第三代", grandchild.gender, function(name, gender)
                        return PS.UpdateGrandchildIdentity(GD, i, gi, name, gender)
                    end))
                end
            end

            -- 培养项目选择按钮
            local trainBtns = {}
            for _, tKey in ipairs({"tutor", "training", "internship", "startup"}) do
                local tCfg = PS.CHILD_TRAINING[tKey]
                if tCfg then
                    local isActive = curTraining == tKey
                    local canUse = true
                    local btnText = tCfg.icon .. " " .. tCfg.name
                    if tCfg.minAge and child.age < tCfg.minAge then
                        canUse = false
                        btnText = btnText .. "(" .. tCfg.minAge .. "岁)"
                    end
                    table.insert(trainBtns, C.ActionButton {
                        text = btnText,
                        variant = isActive and "primary" or "secondary",
                        minWidth = 80, flex = 1,
                        disabled = not canUse,
                        onClick = function()
                            if isActive then
                                PS.SetChildTraining(GD, i, nil)  -- 取消
                            else
                                PS.SetChildTraining(GD, i, tKey)
                            end
                            if navigate then navigate("personal") end
                        end
                    })
                end
            end
            table.insert(cards, UI.Panel {
                width = "100%", flexDirection = "row", gap = 4, flexWrap = "wrap",
                children = trainBtns,
            })
        end
    else
        table.insert(cards, UI.Panel {
            width = "100%", padding = 12, backgroundColor = T.CardBg, borderRadius = T.Radius,
            children = {
                UI.Label {text = "暂无子女", fontSize = T.FontBody, fontColor = T.TextMuted, textAlign = "center", width = "100%"},
            }
        })
    end

    -- 生育/收养按钮
    if #children < 3 and fam.married then
        table.insert(cards, C.ActionButton {
            text = "生育子女（当前" .. #children .. "/3）", variant = "primary", width = "100%",
            onClick = function() PS.HaveChild(GD); if navigate then navigate("personal") end end
        })
    elseif not fam.married then
        table.insert(cards, UI.Panel {
            width = "100%", padding = 8,
            children = {UI.Label {text = "需先结婚才能生育", fontSize = T.FontSmall, fontColor = T.TextMuted, textAlign = "center", width = "100%"}}
        })
    end
    if #children < 3 then
        table.insert(cards, C.ActionButton {
            text = "收养子女（当前" .. #children .. "/3）", variant = "secondary", width = "100%",
            onClick = function() PS.AdoptChild(GD, false); if navigate then navigate("personal") end end
        })
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 4) 赡养父母
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "赡养父母", color = T.Warning})

    local ec = fam.elderCare
    if ec then
        local parentHealthColor2 = (ec.parentHealth or 80) >= 60 and T.Success or ((ec.parentHealth or 80) >= 30 and T.Warning or T.Danger)
        table.insert(cards, C.InfoCard {
            title = "父母状况",
            rows = {
                {label = "赡养状态", value = (ec.enabled and "赡养中" or "未赡养")},
                {label = "父母健康度", value = tostring(ec.parentHealth or 80) .. "/100", color = parentHealthColor2},
                {label = "月赡养费", value = string.format("%.1f万", ec.monthlyExpense or 1.5)},
            }
        })
        local elderBtns = {}
        for _, amt in ipairs({0.5, 1.0, 1.5, 2.0, 3.0, 5.0}) do
            local isActive = math.abs((ec.monthlyExpense or 1.5) - amt) < 0.01
            table.insert(elderBtns, C.ActionButton {
                text = string.format("%.1f万", amt),
                variant = isActive and "primary" or "secondary",
                minWidth = 55,
                onClick = function() PS.SetElderCare(GD, amt); if navigate then navigate("personal") end end
            })
        end
        table.insert(cards, UI.Panel {
            width = "100%", gap = 4,
            children = {
                UI.Label {text = "调整月赡养费", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                UI.Panel {width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap", children = elderBtns},
            }
        })
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 5) 传承系统
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "传承系统", color = T.Danger})

    local succMode = fam.successionMode
    local gradualPct = fam.gradualTransferPct or 0
    local hasChild = #children > 0
    local hasWill = p.will and p.will.hasWill or false

    table.insert(cards, C.InfoCard {
        title = "传承状态",
        rows = {
            {label = "传承模式", value = succMode == "gradual" and "渐进式（10%×10次）" or (succMode == "onetime" and "一次性" or "未设置")},
            {label = "渐进进度", value = tostring(gradualPct) .. "%/100%"},
            {label = "遗嘱", value = hasWill and "已立（遗产税10%）" or "未立（遗产税10%）"},
            {label = "继承子女", value = hasChild and "有（任意年龄可继承）" or "无", color = hasChild and T.Success or T.Danger},
        }
    })

    if gradualPct > 0 and gradualPct < 100 then
        table.insert(cards, C.ProgressCard {
            title = "渐进传承进度",
            progress = gradualPct,
            barColor = T.Accent,
        })
    end

    -- 传承操作按钮
    if hasChild then
        local succBtns = {}
        -- 设置渐进模式
        if succMode ~= "gradual" then
            table.insert(succBtns, C.ActionButton {
                text = "选择渐进传承（税率10%）", variant = "secondary", flex = 1, minWidth = 130,
                onClick = function()
                    local ok, msg = PS.SetSuccessionMode(GD, "gradual")
                    if not ok and msg then GD.AddEvent(msg, "warning") end
                    if navigate then navigate("personal") end
                end
            })
        end
        -- 执行渐进转移
        if succMode == "gradual" and gradualPct < 100 then
            table.insert(succBtns, C.ActionButton {
                text = "执行转移（+10%）", variant = "primary", flex = 1, minWidth = 130,
                onClick = function()
                    local ok, msg = PS.DoGradualTransfer(GD)
                    if not ok and msg then GD.AddEvent(msg, "warning") end
                    if navigate then navigate("personal") end
                end
            })
        end
        -- 一次性传承
        table.insert(succBtns, C.ActionButton {
            text = "一次性传承（遗产税10%）", variant = "danger", flex = 1, minWidth = 130,
            onClick = function()
                local ok, msg = PS.DoOnetimeSuccession(GD)
                if not ok and msg then GD.AddEvent(msg, "warning") end
                if navigate then navigate("personal") end
            end
        })
        table.insert(cards, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap",
            children = succBtns,
        })
    else
        table.insert(cards, UI.Panel {
            width = "100%", padding = 8,
            children = {UI.Label {text = "需有子女才可设立传承，子女任意年龄均可继承", fontSize = T.FontSmall, fontColor = T.TextMuted, textAlign = "center", width = "100%"}}
        })
    end

    -- 遗嘱
    if not hasWill then
        table.insert(cards, C.ActionButton {
            text = "立遗嘱（子女任意年龄可继承，遗产税固定10%）", variant = "secondary", width = "100%",
            onClick = function()
                local beneficiaries = {}
                local share = #children > 0 and math.floor(100 / #children) or 0
                local remain = 100
                for i, child in ipairs(children) do
                    local childShare = (i == #children) and remain or share
                    table.insert(beneficiaries, {name = child.name, share = childShare})
                    remain = remain - childShare
                end
                PS.CreateWill(GD, beneficiaries)
                if navigate then navigate("personal") end
            end
        })
    else
        table.insert(cards, UI.Panel {
            width = "100%", padding = 8, backgroundColor = T.CardBg, borderRadius = T.Radius,
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {text = "遗嘱状态", fontSize = T.FontBody, fontColor = T.TextSecondary},
                UI.Label {text = "已立（第" .. tostring(p.will.createdYear or 0) .. "年）", fontSize = T.FontBody, fontColor = T.Success, fontWeight = "bold"},
            }
        })
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 6) 家族办公室
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "家族办公室", color = T.Success})

    local fo = p.familyOffice
    local netWorth = p.netWorth or 0
    local canEstablish = netWorth >= PS.FAMILY_OFFICE_THRESHOLD

    if fo then
        -- 已开设
        local managerText = "能力" .. tostring(fo.managerAbility or 60) .. " / 月薪" .. tostring(fo.managerSalary or 5) .. "万"
        local allocText = ""
        for cls, pct in pairs(fo.allocation or {}) do
            local clsCfg = PS.FO_ASSET_CLASSES[cls]
            if clsCfg and pct > 0 then
                allocText = allocText .. clsCfg.icon .. clsCfg.name .. pct .. "% "
            end
        end
        local annualRate = fo.annualReturnRate
        if annualRate == nil and (fo.yearlyReturn or 0) > 0 then
            local openingAssets = math.max(1, (fo.totalAssets or 0) - (fo.yearlyReturn or 0))
            annualRate = math.min(PS.FO_MAX_ANNUAL_RETURN, (fo.yearlyReturn or 0) / openingAssets)
        end
        annualRate = math.max(PS.FO_MIN_ANNUAL_RETURN, math.min(PS.FO_MAX_ANNUAL_RETURN, annualRate or PS.FO_MIN_ANNUAL_RETURN))
        table.insert(cards, C.InfoCard {
            title = "家族办公室概览",
            rows = {
                {label = "托管资产", value = string.format("%.0f万", fo.totalAssets or 0)},
                {label = "年度收益", value = string.format("%.1f万", fo.yearlyReturn or 0), color = (fo.yearlyReturn or 0) >= 0 and T.Success or T.Danger},
                {label = "年化收益率", value = string.format("%.2f%%（上限3%%）", annualRate * 100), color = T.Success},
                {label = "累计收益", value = string.format("%.1f万", fo.totalReturn or 0)},
                {label = "经理人", value = managerText},
                {label = "家族宪章", value = fo.charter and ("已制定 - 第" .. tostring(fo.charterYear or 0) .. "年") or "未制定"},
            }
        })

        -- 资产配置展示
        if allocText ~= "" then
            table.insert(cards, UI.Panel {
                width = "100%", padding = 8, backgroundColor = T.CardBg, borderRadius = T.Radius,
                children = {
                    UI.Label {text = "资产配置：" .. allocText, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })
        end

        -- 资金操作按钮
        table.insert(cards, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap",
            children = {
                C.ActionButton {
                    text = "注入500万", variant = "primary", flex = 1, minWidth = 90,
                    onClick = function() PS.FO_InjectFunds(GD, 500); if navigate then navigate("personal") end end
                },
                C.ActionButton {
                    text = "注入2000万", variant = "primary", flex = 1, minWidth = 90,
                    onClick = function() PS.FO_InjectFunds(GD, 2000); if navigate then navigate("personal") end end
                },
                C.ActionButton {
                    text = "提取500万", variant = "secondary", flex = 1, minWidth = 90,
                    onClick = function()
                        local ok, msg = PS.FO_WithdrawFunds(GD, 500)
                        if not ok and msg then GD.AddEvent(msg, "warning") end
                        if navigate then navigate("personal") end
                    end
                },
                C.ActionButton {
                    text = "全额转出", variant = "danger", flex = 1, minWidth = 90,
                    onClick = function()
                        local amt = math.floor((fo.totalAssets or 0) + 0.5)
                        if amt <= 0 then
                            GD.AddEvent("家族办公室暂无可提取资金", "warning")
                        else
                            local ok, msg = PS.FO_WithdrawFunds(GD, amt)
                            if not ok and msg then GD.AddEvent(msg, "warning") end
                        end
                        if navigate then navigate("personal") end
                    end
                },
            }
        })

        table.insert(cards, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap", alignItems = "center",
            children = {
                UI.Label {text = "自定义转入", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                UI.TextField {
                    placeholder = "金额(万)",
                    width = 110, height = 32, fontSize = T.FontCaption,
                    borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                    backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                    value = M._customInputs["foInject"] or "",
                    onChange = function(self, text) M._customInputs["foInject"] = text end,
                },
                C.ActionButton {
                    text = "转入", variant = "primary", minWidth = 80,
                    onClick = function()
                        local amt = math.floor(tonumber(M._customInputs["foInject"] or "") or 0)
                        if amt <= 0 then
                            GD.AddEvent("请输入有效转入金额", "warning")
                        else
                            local ok, msg = PS.FO_InjectFunds(GD, amt)
                            if ok then
                                M._customInputs["foInject"] = ""
                            elseif msg then
                                GD.AddEvent(msg, "warning")
                            end
                        end
                        if navigate then navigate("personal") end
                    end
                },
                UI.Label {text = "自定义提取", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                UI.TextField {
                    placeholder = "金额(万)",
                    width = 110, height = 32, fontSize = T.FontCaption,
                    borderRadius = 4, borderWidth = 1, borderColor = T.Border,
                    backgroundColor = T.BgCard, fontColor = T.TextPrimary,
                    value = M._customInputs["foWithdraw"] or "",
                    onChange = function(self, text) M._customInputs["foWithdraw"] = text end,
                },
                C.ActionButton {
                    text = "提取", variant = "secondary", minWidth = 80,
                    onClick = function()
                        local amt = math.floor(tonumber(M._customInputs["foWithdraw"] or "") or 0)
                        if amt <= 0 then
                            GD.AddEvent("请输入有效提取金额", "warning")
                        else
                            local ok, msg = PS.FO_WithdrawFunds(GD, amt)
                            if ok then
                                M._customInputs["foWithdraw"] = ""
                            elseif msg then
                                GD.AddEvent(msg, "warning")
                            end
                        end
                        if navigate then navigate("personal") end
                    end
                },
            }
        })

        -- 经理人升级
        table.insert(cards, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap",
            children = {
                C.ActionButton {
                    text = "聘用70级经理人", variant = "secondary", flex = 1, minWidth = 120,
                    onClick = function() PS.FO_HireManager(GD, 70); if navigate then navigate("personal") end end
                },
                C.ActionButton {
                    text = "聘用90级经理人", variant = "secondary", flex = 1, minWidth = 120,
                    onClick = function() PS.FO_HireManager(GD, 90); if navigate then navigate("personal") end end
                },
            }
        })

        -- 资产配置调整
        table.insert(cards, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, flexWrap = "wrap",
            children = {
                C.ActionButton {
                    text = "稳健型(债60股20)", variant = "secondary", flex = 1, minWidth = 120,
                    onClick = function()
                        PS.FO_SetAllocation(GD, {stocks = 20, bonds = 60, realestate = 10, pe = 10})
                        if navigate then navigate("personal") end
                    end
                },
                C.ActionButton {
                    text = "进取型(股50PE20)", variant = "secondary", flex = 1, minWidth = 120,
                    onClick = function()
                        PS.FO_SetAllocation(GD, {stocks = 50, bonds = 10, realestate = 20, pe = 20})
                        if navigate then navigate("personal") end
                    end
                },
            }
        })

        -- 家族宪章
        if not fo.charter then
            table.insert(cards, C.ActionButton {
                text = "制定家族宪章（律师费50万，声望+10）", variant = "secondary", width = "100%",
                onClick = function() PS.FO_CreateCharter(GD); if navigate then navigate("personal") end end
            })
        end

        -- 慈善基金会
        if fo.charity and fo.charity.enabled then
            table.insert(cards, C.InfoCard {
                title = "慈善基金会",
                rows = {
                    {label = "名称", value = fo.charity.foundation or "基金会"},
                    {label = "年度捐赠", value = string.format("%.0f万", fo.charity.yearlyDonation or 0)},
                    {label = "累计捐赠", value = string.format("%.0f万", fo.charity.totalDonation or 0)},
                    {label = "税务减免", value = string.format("%.1f万", fo.charity.taxDeduction or 0)},
                }
            })
        else
            table.insert(cards, C.ActionButton {
                text = "设立慈善基金会（100万，声望+20）", variant = "secondary", width = "100%",
                onClick = function()
                    PS.FO_CreateCharity(GD, nil, 100)
                    if navigate then navigate("personal") end
                end
            })
        end
    else
        -- 未开设
        local thresholdText = string.format("%.0f万", PS.FAMILY_OFFICE_THRESHOLD)
        if canEstablish then
            table.insert(cards, C.InfoCard {
                title = "家族办公室",
                rows = {
                    {label = "状态", value = "可开设", color = T.Success},
                    {label = "开设条件", value = "净资产≥" .. thresholdText .. "（已满足）"},
                }
            })
            table.insert(cards, C.ActionButton {
                text = "开设家族办公室", variant = "primary", width = "100%",
                onClick = function() PS.InitFamilyOffice(GD); if navigate then navigate("personal") end end
            })
        else
            table.insert(cards, C.InfoCard {
                title = "家族办公室",
                rows = {
                    {label = "状态", value = "未解锁", color = T.TextMuted},
                    {label = "开设条件", value = "净资产≥" .. thresholdText},
                    {label = "当前净资产", value = string.format("%.0f万", netWorth)},
                }
            })
        end
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- 7) 家庭财务汇总
    -- ══════════════════════════════════════════════════════════════════════════
    table.insert(cards, C.SectionTitle {text = "家庭财务", color = T.Info})

    local spouseIncome = (fam.married and fam.spouse) and (fam.spouse.monthlyIncome or 0) or 0
    local childCost = 0
    for _, child in ipairs(children) do
        local stage = PS.GetEducationStage(child.age)
        childCost = childCost + stage.monthlyCost
    end
    local baseLiving = fam.married and 2.0 or 1.0

    table.insert(cards, UI.Panel {
        width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap",
        children = {
            C.StatCard {title = "月基本生活", value = string.format("%.1f万", baseLiving), color = T.TextPrimary, minWidth = 90},
            C.StatCard {title = "月子女教育", value = string.format("%.1f万", childCost), color = T.Warning, minWidth = 90},
            C.StatCard {title = "月赡养支出", value = string.format("%.1f万", (ec and ec.monthlyExpense or 0)), color = T.Danger, minWidth = 90},
            C.StatCard {title = "配偶月收入", value = string.format("%.1f万", spouseIncome), color = T.Success, minWidth = 90},
            C.StatCard {title = "月净开销", value = string.format("%.1f万", fam.monthlyFamilyExpense or 0), color = T.Accent, minWidth = 90},
        }
    })

    table.insert(cards, C.InfoCard {
        title = "累计支出",
        rows = {
            {label = "家庭总支出", value = string.format("%.1f万", fam.totalFamilyExpense or 0)},
            {label = "子女总支出", value = string.format("%.1f万", fam.totalChildExpense or 0)},
            {label = "赡养总支出", value = string.format("%.1f万", fam.totalElderExpense or 0)},
            {label = "培养总支出", value = string.format("%.1f万", fam.totalTrainingExpense or 0)},
            {label = "婚礼花费", value = string.format("%.1f万", fam.weddingCost or 0)},
        }
    })

    return UI.Panel {
        width = "100%", gap = 12,
        children = cards,
    }
end

return M
