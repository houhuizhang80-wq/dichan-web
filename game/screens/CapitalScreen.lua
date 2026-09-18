---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- CapitalScreen.lua - 第七层: 资本运作 (5-Tab 金融系统 v10)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local CompanySelector = require("CompanySelector")

local FN = require("Finance")  -- 直接 require，避免加载顺序导致 GD.Finance 为 nil
local PC = require("ProjectCapacity")

local M = {}
M._activeTab = 1  -- 1=融资中心 2=三条红线 3=税务筹划 4=并购与IPO
M._financingScope = "company"
M._groupExpandedProduct = nil
M._groupInputAmount = ""
M._groupInputDuration = "36"
M._groupRepayMethod = "interest_monthly"

function M.OpenGroupFinancing()
    M._activeTab = 1
    M._financingScope = "group"
    M._groupExpandedProduct = nil
end

-- 缓存：并购目标（切换到Tab5时生成一次，避免每次刷新都随机）
M._cachedMATargets = nil

-- 融资申请表单状态
M._expandedProduct = nil  -- 当前展开的产品id
M._inputAmount = ""       -- 手动输入的金额（万元）
M._inputDuration = ""     -- 手动输入的期限（月）
M._selectedRepay = "interest_monthly"  -- 还款方式

function M.ResetCompanyState()
    M._cachedMATargets = nil
    M._expandedProduct = nil
    M._inputAmount = ""
    M._inputDuration = ""
    M._selectedRepay = "interest_monthly"
    M._financingScope = "company"
    M._groupExpandedProduct = nil
    M._groupInputAmount = ""
    M._groupInputDuration = "36"
    M._groupRepayMethod = "interest_monthly"
    M._finSubTab = 1
    M._expandedDeposit = nil
    M._depositInputAmount = ""
    M._fixedAssetExpandedId = nil
    M._fixedAssetRenovIdx = 1
    M._mortgageExpandedIdx = nil
    M._mortgageInputAmount = ""
    M._mortgageInputMonths = "36"
    M._selectedMortgageAssets = {}
    M._selectedMortgageRepayments = {}
    M._projMortgageExpandedId = nil
    M._projMortgageInputAmount = ""
    M._projMortgageInputMonths = "36"
end

function M.Create(navigate)
    local co = GD.company

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 14,
        children = {
            C.SectionTitle {text = "资本运作"},
            CompanySelector.Build {
                navigate = navigate,
                returnScreen = "capital",
                onSwitched = M.ResetCompanyState,
            },

            C.TabBar {
                tabs = {"融资中心", "三条红线", "税务筹划", "财务报表"},
                active = M._activeTab,
                onChange = function(idx)
                    M._activeTab = idx
                    navigate("capital")
                end,
            },

            M._activeTab == 1 and M._TabFinancing(navigate, co) or
            M._activeTab == 2 and M._TabRedLines(navigate, co) or
            M._activeTab == 3 and M._TabTax(navigate, co) or
            M._TabFinancialReport(navigate, co),

            UI.Panel {height = 20},
        }
    }
end

-- ============================================================================
-- Tab1: 融资中心 — 存款 + 贷款（简化版）
-- ============================================================================

-- 融资中心子标签: 1=存款, 2=贷款
M._finSubTab = M._finSubTab or 1
-- 存款表单状态
M._expandedDeposit = nil      -- 展开的存款类型id
M._depositInputAmount = ""    -- 存款金额输入

-- 融资中心显示的贷款产品（按用户指定的5种）
local LOAN_PRODUCT_IDS = {"bank_dev", "trust", "corp_bond", "bridge", "coinvest"}

function M._TabFinancing(navigate, co)
    local groupSystem = GD.GroupSystem
    local groupActive = groupSystem and groupSystem.IsActive(GD)
    if M._financingScope == "group" and groupActive then
        return M._BuildGroupFinancingSection(navigate)
    end

    local fin = GD.finance or {}
    local debtRatio = co.totalAssets > 0 and (co.totalDebt / co.totalAssets) or 0

    -- 子标签切换：存款 / 贷款 / 资产抵押 / 项目抵押
    local subTabNames = {"存款", "贷款", "资产抵押", "项目抵押"}
    local subTabBtns = {}
    for idx, name in ipairs(subTabNames) do
        local captureIdx = idx
        table.insert(subTabBtns, UI.Button {
            text = name,
            fontSize = T.FontSmall,
            backgroundColor = M._finSubTab == captureIdx and T.Primary or T.Surface,
            fontColor = M._finSubTab == captureIdx and T.TextOnDark or T.TextSecondary,
            borderRadius = 0,
            height = 38,
            flexGrow = 1,
            onClick = function() M._finSubTab = captureIdx; navigate("capital") end,
        })
    end
    local subTabBar = UI.Panel {
        flexDirection = "row", gap = 0, width = "100%", marginBottom = 4,
        children = subTabBtns,
    }

    local content
    if M._finSubTab == 1 then
        content = M._BuildDepositSection(navigate, co, fin)
    elseif M._finSubTab == 2 then
        content = M._BuildLoanSection(navigate, co, fin)
    elseif M._finSubTab == 3 then
        content = M._BuildFixedAssetMortgageSection(navigate, co)
    else
        content = M._BuildProjectMortgageSection(navigate, co)
    end

    local groupButton = nil
    if groupActive then
        groupButton = C.SecondaryButton {
            text = "切换至集团融资",
            width = "100%",
            onClick = function()
                M._financingScope = "group"
                navigate("capital")
            end,
        }
    end

    local financingChildren = {}
    if groupButton then
        financingChildren[#financingChildren + 1] = groupButton
    end
    financingChildren[#financingChildren + 1] = UI.Panel {
        flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
        children = {
            C.StatCard {
                title = "现金",
                value = C.FormatMoney(co.cash),
                color = T.Success,
                minWidth = 90,
                padding = 8,
                gap = 2,
                valueFontSize = T.FontSubtitle,
                titleMaxLines = 1,
                valueMaxLines = 1,
            },
            C.StatCard {
                title = "总负债",
                value = C.FormatMoney(co.totalDebt),
                color = T.Warning,
                minWidth = 90,
                padding = 8,
                gap = 2,
                valueFontSize = T.FontSubtitle,
                titleMaxLines = 1,
                valueMaxLines = 1,
            },
            C.StatCard {
                title = "负债率",
                value = string.format("%.0f%%", debtRatio * 100),
                color = debtRatio > 0.7 and T.Danger or T.Success,
                minWidth = 90,
                padding = 8,
                gap = 2,
                valueFontSize = T.FontSubtitle,
                titleMaxLines = 1,
                valueMaxLines = 1,
            },
        }
    }
    financingChildren[#financingChildren + 1] = subTabBar
    financingChildren[#financingChildren + 1] = content

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = financingChildren,
    }
end

function M._BuildGroupFinancingSection(navigate)
    local GS = GD.GroupSystem
    local group = GS.EnsureFields(GD)
    local summary = GS.GetSummary(GD)
    local productCards = {}

    for _, productId in ipairs(GS.LOAN_PRODUCT_ORDER or {}) do
        local offer = GS.GetLoanOffer(GD, productId)
        local product = offer and offer.product
        if product then
            local capturedProductId = productId
            local expanded = M._groupExpandedProduct == productId
            local rows = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    justifyContent = "space-between",
                    alignItems = "flex-start",
                    gap = 8,
                    children = {
                        UI.Panel {
                            flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2,
                            children = {
                                UI.Label {
                                    text = product.name,
                                    fontSize = T.FontBody,
                                    fontColor = T.TextPrimary,
                                    whiteSpace = "normal", maxLines = 2,
                                },
                                UI.Label {
                                    text = product.desc,
                                    fontSize = T.FontCaption,
                                    fontColor = T.TextMuted,
                                    whiteSpace = "normal", maxLines = 3,
                                },
                            },
                        },
                        C.Badge {text = offer.maxLoan > 0 and "可申请" or "暂无额度", variant = offer.maxLoan > 0 and "success" or "warning"},
                    },
                },
                C.InfoRow {label = "年利率", value = string.format("%.2f%%", product.rate), color = T.Warning},
                C.InfoRow {label = "可贷额度", value = C.FormatMoney(offer.maxLoan), color = offer.maxLoan > 0 and T.Success or T.TextMuted},
                C.InfoRow {label = "期限范围", value = tostring(product.durationRange[1]) .. "~" .. tostring(product.durationRange[2]) .. "个月"},
            }

            if not expanded then
                table.insert(rows, C.ActionButton {
                    text = offer.maxLoan > 0 and "申请集团贷款" or "暂无可贷额度",
                    width = "100%",
                    disabled = offer.maxLoan <= 0,
                    onClick = offer.maxLoan > 0 and function()
                        M._groupExpandedProduct = capturedProductId
                        M._groupInputAmount = tostring(math.max(1, math.floor(offer.maxLoan * 0.5)))
                        M._groupInputDuration = tostring(product.months)
                        M._groupRepayMethod = "interest_monthly"
                        navigate("capital")
                    end or nil,
                })
            else
                table.insert(rows, UI.Panel {
                    width = "100%", gap = 8, padding = 10,
                    backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "贷款金额（万元）", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._groupInputAmount, width = "100%", height = 40,
                            keyboardType = "number", placeholder = "最高" .. C.FormatMoney(offer.maxLoan),
                            onChange = function(_, value) M._groupInputAmount = value end,
                        },
                        UI.Label {text = "贷款期限（月）", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._groupInputDuration, width = "100%", height = 40,
                            keyboardType = "number", placeholder = tostring(product.months),
                            onChange = function(_, value) M._groupInputDuration = value end,
                        },
                        UI.Panel {
                            width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap",
                            children = {
                                UI.Button {
                                    text = "按月付息", height = 34, flexGrow = 1,
                                    backgroundColor = M._groupRepayMethod == "interest_monthly" and T.Primary or T.Surface,
                                    fontColor = M._groupRepayMethod == "interest_monthly" and T.TextOnDark or T.TextSecondary,
                                    onClick = function() M._groupRepayMethod = "interest_monthly"; navigate("capital") end,
                                },
                                UI.Button {
                                    text = "到期还本付息", height = 34, flexGrow = 1,
                                    backgroundColor = M._groupRepayMethod == "bullet" and T.Primary or T.Surface,
                                    fontColor = M._groupRepayMethod == "bullet" and T.TextOnDark or T.TextSecondary,
                                    onClick = function() M._groupRepayMethod = "bullet"; navigate("capital") end,
                                },
                            },
                        },
                        UI.Panel {
                            width = "100%", flexDirection = "row", gap = 8,
                            children = {
                                C.SecondaryButton {
                                    text = "取消", width = "35%",
                                    onClick = function() M._groupExpandedProduct = nil; navigate("capital") end,
                                },
                                C.ActionButton {
                                    text = "确认申请", width = "65%",
                                    onClick = function()
                                        local ok, msg = GS.ApplyLoan(
                                            GD,
                                            capturedProductId,
                                            tonumber(M._groupInputAmount) or 0,
                                            tonumber(M._groupInputDuration) or product.months,
                                            M._groupRepayMethod
                                        )
                                        GD.AddEvent(msg or (ok and "集团贷款申请成功" or "集团贷款申请失败"), ok and "success" or "warning")
                                        if ok then M._groupExpandedProduct = nil end
                                        navigate("capital")
                                    end,
                                },
                            },
                        },
                    },
                })
            end
            productCards[#productCards + 1] = C.Card {children = rows}
        end
    end

    local loanCards = {}
    for index, loan in ipairs(group.loans or {}) do
        local capturedIndex = index
        loanCards[#loanCards + 1] = C.Card {children = {
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap",
                justifyContent = "space-between", alignItems = "flex-start", gap = 8,
                children = {
                    UI.Label {
                        text = loan.name or "集团贷款", fontSize = T.FontBody, fontColor = T.TextPrimary,
                        flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
                        whiteSpace = "normal", maxLines = 2,
                    },
                    C.Badge {text = tostring(loan.remainMonths or 0) .. "个月到期", variant = (loan.remainMonths or 0) <= 6 and "warning" or "info"},
                },
            },
            C.InfoRow {label = "贷款本金", value = C.FormatMoney(loan.amount or 0)},
            C.InfoRow {label = "累计利息", value = C.FormatMoney(loan.accruedInterest or 0), color = T.Warning},
            C.InfoRow {label = "提前还款", value = C.FormatMoney(GS.GetEarlyRepayAmount(loan)), color = T.Danger},
            C.SecondaryButton {
                text = "提前还清",
                width = "100%",
                onClick = function()
                    local ok, msg = GS.EarlyRepayLoan(GD, capturedIndex)
                    GD.AddEvent(msg or (ok and "集团贷款已还清" or "集团还款失败"), ok and "success" or "warning")
                    navigate("capital")
                end,
            },
        }}
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            C.SecondaryButton {
                text = "返回公司融资",
                width = "100%",
                onClick = function() M._financingScope = "company"; navigate("capital") end,
            },
            C.SectionTitle {text = (group.name or "集团") .. "融资中心", color = T.Accent},
            UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 10, children = {
                C.StatCard {title = "集团现金", value = C.FormatMoney(summary.cash), color = T.Success},
                C.StatCard {title = "集团总负债", value = C.FormatMoney(summary.totalDebt), color = summary.totalDebt > 0 and T.Warning or T.Success},
                C.StatCard {title = "集团净资产", value = C.FormatMoney(summary.netAssets), color = summary.netAssets >= 0 and T.Info or T.Danger},
            }},
            C.SectionTitle {text = "集团贷款产品", color = T.Info},
            UI.Panel {width = "100%", gap = 10, children = productCards},
            C.SectionTitle {text = "集团当前贷款（" .. tostring(#(group.loans or {})) .. "笔）"},
            #loanCards > 0 and UI.Panel {width = "100%", gap = 10, children = loanCards}
                or UI.Label {text = "集团暂无贷款", fontSize = T.FontSmall, fontColor = T.TextMuted},
        },
    }
end

-- ============================================================================
-- 存款区域
-- ============================================================================
function M._BuildDepositSection(navigate, co, fin)
    -- === 存款产品列表 ===
    local depositCards = {}
    for _, dtype in ipairs(FN.DEPOSIT_TYPES) do
        local captureDtype = dtype
        local isExpanded = (M._expandedDeposit == dtype.id)
        local cardItems = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = dtype.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {
                        text = string.format("年利率 %.2f%%", dtype.rate),
                        variant = dtype.rate >= 2.0 and "success" or "info",
                    },
                }
            },
        }
        if dtype.minAmount > 0 then
            table.insert(cardItems, C.InfoRow {label = "起存金额", value = C.FormatMoney(dtype.minAmount)})
        end
        if dtype.minMonths > 0 then
            local termLabel = dtype.minMonths >= 12 and (math.floor(dtype.minMonths / 12) .. "年") or (dtype.minMonths .. "个月")
            table.insert(cardItems, C.InfoRow {label = "存期", value = termLabel})
        else
            table.insert(cardItems, C.InfoRow {label = "存期", value = "随存随取"})
        end

        if not isExpanded then
            table.insert(cardItems, C.ActionButton {
                text = "存入",
                onClick = function()
                    M._expandedDeposit = captureDtype.id
                    M._depositInputAmount = ""
                    navigate("capital")
                end,
            })
        else
            -- 展开的存款表单
            local formChildren = {}
            table.insert(formChildren, UI.Panel {
                width = "100%", gap = 4,
                children = {
                    UI.Label {text = "存入金额（万元）  可用现金: " .. C.FormatMoney(co.cash), fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.TextField {
                        value = M._depositInputAmount,
                        placeholder = "请输入存款金额",
                        fontSize = T.FontBody,
                        width = "100%", height = 40,
                        borderRadius = T.ButtonRadius,
                        borderWidth = 1, borderColor = T.Border,
                        paddingHorizontal = 10,
                        keyboardType = "number",
                        onChange = function(self, text) M._depositInputAmount = text end,
                    },
                }
            })

            -- 快捷金额按钮
            local quickBtns = {}
            local quickAmounts = {500, 1000, 2000, 5000, 10000}
            for _, amt in ipairs(quickAmounts) do
                local captureAmt = amt
                if captureAmt <= co.cash then
                    table.insert(quickBtns, UI.Button {
                        text = C.FormatMoney(captureAmt),
                        fontSize = T.FontCaption,
                        backgroundColor = T.Surface, fontColor = T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 8, height = 30,
                        onClick = function()
                            M._depositInputAmount = tostring(captureAmt)
                            navigate("capital")
                        end,
                    })
                end
            end
            if #quickBtns > 0 then
                table.insert(formChildren, UI.Panel {
                    flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap",
                    children = quickBtns,
                })
            end

            -- 预估收益
            local inputAmt = tonumber(M._depositInputAmount) or 0
            if inputAmt > 0 then
                local months = dtype.minMonths > 0 and dtype.minMonths or 12
                local estInterest = math.floor(inputAmt * dtype.rate / 100 / 12 * months * 100) / 100
                table.insert(formChildren, UI.Panel {
                    width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                    padding = 8, marginTop = 4, gap = 2,
                    children = {
                        C.InfoRow {label = "预估" .. (dtype.minMonths > 0 and "到期" or "年") .. "利息", value = C.FormatMoney(estInterest), color = T.Success},
                    }
                })
            end

            -- 确认/取消
            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
                children = {
                    UI.Button {
                        text = "取消", fontSize = T.FontBody,
                        backgroundColor = T.Surface, fontColor = T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                        onClick = function() M._expandedDeposit = nil; navigate("capital") end,
                    },
                    UI.Button {
                        text = "确认存入", fontSize = T.FontBody,
                        backgroundColor = T.Primary, fontColor = T.TextOnDark,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                        onClick = function()
                            local amt = tonumber(M._depositInputAmount) or 0
                            if amt <= 0 then
                                GD.AddEvent("请输入有效的存款金额", "warning")
                                navigate("capital"); return
                            end
                            local ok = FN.MakeDeposit(GD, captureDtype.id, amt)
                            M._expandedDeposit = nil
                            navigate("capital")
                        end,
                    },
                }
            })

            table.insert(cardItems, UI.Panel {
                width = "100%", gap = 6, marginTop = 6,
                padding = 8, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                children = formChildren,
            })
        end
        table.insert(depositCards, C.Card {children = cardItems})
    end

    -- === 当前存款列表 ===
    local currentDepositRows = {}
    -- 活期余额
    local demandBal = fin.demandBalance or 0
    if demandBal > 0 then
        table.insert(currentDepositRows, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                    children = {
                        UI.Label {text = "活期存款", fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {text = "随时可取", variant = "success"},
                    }
                },
                C.InfoRow {label = "余额", value = C.FormatMoney(demandBal), color = T.Success},
                C.InfoRow {label = "年利率", value = string.format("%.2f%%", FN.DEPOSIT_TYPES[1].rate)},
                C.SecondaryButton {
                    text = "全部取出 (" .. C.FormatMoney(demandBal) .. ")",
                    onClick = function()
                        FN.WithdrawDeposit(GD, 0)
                        navigate("capital")
                    end,
                },
            }
        })
    end

    -- 定期存款列表
    local deposits = fin.deposits or {}
    for i, dep in ipairs(deposits) do
        local captureIdx = i
        local elapsed = (GD.totalMonths or 0) - dep.startMonth
        local remaining = math.max(0, dep.months - elapsed)
        local estInterest = math.floor(dep.amount * dep.rate / 100 / 12 * dep.months * 100) / 100
        local earnedInterest = math.floor(dep.amount * dep.rate / 100 / 12 * elapsed * 100) / 100
        table.insert(currentDepositRows, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                    children = {
                        UI.Label {text = dep.name or dep.type, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {
                            text = remaining > 0 and (remaining .. "个月到期") or "已到期",
                            variant = remaining <= 1 and "success" or "info",
                        },
                    }
                },
                C.InfoRow {label = "本金", value = C.FormatMoney(dep.amount)},
                C.InfoRow {label = "年利率", value = string.format("%.2f%%", dep.rate)},
                C.InfoRow {label = "已存期", value = elapsed .. "/" .. dep.months .. "个月"},
                C.InfoRow {label = "到期利息", value = C.FormatMoney(estInterest), color = T.Success},
                C.SecondaryButton {
                    text = "提前取出（利息作废）",
                    onClick = function()
                        FN.WithdrawDeposit(GD, captureIdx)
                        navigate("capital")
                    end,
                },
            }
        })
    end

    -- 累计利息
    local totalInterest = fin.totalInterest or 0

    return UI.Panel {
        width = "100%", gap = 10,
        children = {
            -- 存款概览
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "活期余额", value = C.FormatMoney(demandBal), color = T.Accent},
                    C.StatCard {title = "定期存款", value = #deposits .. "笔", color = T.Info},
                    C.StatCard {title = "累计利息", value = C.FormatMoney(totalInterest), color = T.Success},
                }
            },

            -- 存款产品
            C.SectionTitle {text = "存款产品", color = T.Info},
            UI.Panel {width = "100%", gap = 8, children = depositCards},

            -- 当前存款
            C.SectionTitle {text = "当前存款 (" .. (#deposits + (demandBal > 0 and 1 or 0)) .. "笔)"},
            #currentDepositRows > 0
                and UI.Panel {width = "100%", gap = 8, children = currentDepositRows}
                or UI.Label {text = "暂无存款", fontSize = T.FontSmall, fontColor = T.TextMuted},
        }
    }
end

-- ============================================================================
-- 贷款区域
-- ============================================================================
function M._BuildLoanSection(navigate, co, fin)
    -- === 贷款产品列表（只显示5种指定产品）===
    local available = FN.GetAvailableProducts(GD)
    local productCards = {}

    for _, prodId in ipairs(LOAN_PRODUCT_IDS) do
        -- 从 available 中查找该产品
        local item = nil
        for _, a in ipairs(available) do
            if a.id == prodId then item = a; break end
        end
        if not item then
            -- 如果 GetAvailableProducts 没返回此产品，手动构建一个不可用条目
            local prod = FN.PRODUCTS[prodId]
            if prod then
                item = {id = prodId, product = prod, eligible = false, reason = "不满足申请条件", effectiveRate = (prod.rateRange[1] + prod.rateRange[2]) / 2, maxLoan = 0}
            end
        end
        if not item then goto continue end

        local prod = item.product
        local captureItem = item
        local rateStr = prod.rateRange[1] == prod.rateRange[2]
            and string.format("%.0f%%", prod.rateRange[1])
            or string.format("%.1f%%~%.1f%%", prod.rateRange[1], prod.rateRange[2])

        local cardItems = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = (prod.icon or "") .. " " .. prod.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {
                        text = item.eligible and "可申请" or "不可用",
                        variant = item.eligible and "success" or "warning",
                    },
                }
            },
        }
        if prod.isCoinvest then
            table.insert(cardItems, C.InfoRow {label = "利率", value = "无息", color = T.Success})
            table.insert(cardItems, C.InfoRow {label = "类型", value = "员工跟投（绑定项目收益分配）"})
        else
            table.insert(cardItems, C.InfoRow {label = "利率区间", value = rateStr, color = T.Warning})
            table.insert(cardItems, C.InfoRow {label = "实际利率", value = string.format("%.2f%%", item.effectiveRate), color = T.TextSecondary})
            if prod.months > 0 then
                table.insert(cardItems, C.InfoRow {label = "默认期限", value = prod.months .. "个月"})
            end
            if item.eligible then
                table.insert(cardItems, C.InfoRow {label = "可贷额度", value = C.FormatMoney(item.maxLoan), color = T.Success})
            end
        end
        if not item.eligible and item.reason then
            table.insert(cardItems, UI.Label {text = item.reason, fontSize = T.FontCaption, fontColor = T.Danger})
        end

        -- 申请按钮/表单
        if item.eligible then
            if prod.isCoinvest then
                -- 员工跟投：显示可跟投项目列表
                local coinvestAmt = math.floor(co.totalAssets * prod.maxRatio * 0.5)
                if coinvestAmt < 100 then coinvestAmt = 100 end
                local investedSet = {}
                if fin and fin.coinvestments then
                    for _, ci in ipairs(fin.coinvestments) do
                        if not ci.settled then investedSet[ci.projectId] = true end
                    end
                end
                local hasEligible = false
                for _, p in ipairs(GD.projects) do
                    if (p.status == "construction" or p.status == "presale") and not investedSet[p.id] then
                        hasEligible = true
                        local capProjId = p.id
                        local capProjName = p.name
                        table.insert(cardItems, UI.Button {
                            text = "跟投【" .. capProjName .. "】" .. C.FormatMoney(coinvestAmt),
                            fontSize = T.FontSmall,
                            backgroundColor = T.Primary, fontColor = T.TextOnDark,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 12, height = 36,
                            width = "100%", marginTop = 4,
                            onClick = function()
                                local ok, msg = FN.ApplyFinancing(GD, captureItem.id, coinvestAmt, capProjId)
                                if not ok then GD.AddEvent(msg or "跟投失败", "danger") end
                                navigate("capital")
                            end,
                        })
                    end
                end
                if not hasEligible then
                    table.insert(cardItems, UI.Label {
                        text = "无可跟投项目（需有在建/预售项目且未跟投）",
                        fontSize = T.FontCaption, fontColor = T.TextMuted,
                    })
                end
            else
                -- 常规贷款
                local isExpanded = (M._expandedProduct == captureItem.id)
                local maxL = item.maxLoan
                local dr = prod.durationRange or {1, 60}

                if not isExpanded then
                    table.insert(cardItems, C.ActionButton {
                        text = "申请贷款",
                        onClick = function()
                            M._expandedProduct = captureItem.id
                            M._inputAmount = tostring(math.floor(maxL * 0.5 / 100) * 100)
                            M._inputDuration = tostring(prod.months)
                            M._selectedRepay = "interest_monthly"
                            navigate("capital")
                        end,
                    })
                else
                    -- 展开的贷款申请表单
                    local formChildren = {}
                    -- 金额输入
                    table.insert(formChildren, UI.Panel {
                        width = "100%", gap = 4,
                        children = {
                            UI.Label {text = "贷款金额（万元）  上限: " .. C.FormatMoney(maxL), fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.TextField {
                                value = M._inputAmount, placeholder = "请输入金额",
                                fontSize = T.FontBody, width = "100%", height = 40,
                                borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                                paddingHorizontal = 10, keyboardType = "number",
                                onChange = function(self, text) M._inputAmount = text end,
                            },
                        }
                    })
                    -- 快捷金额
                    local quickAmts = {}
                    for _, pct in ipairs({0.3, 0.5, 0.8, 1.0}) do
                        local qAmt = math.floor(maxL * pct / 100) * 100
                        if qAmt < 100 then qAmt = 100 end
                        local captureQAmt = qAmt
                        table.insert(quickAmts, UI.Button {
                            text = math.floor(pct * 100) .. "%", fontSize = T.FontCaption,
                            backgroundColor = T.Surface, fontColor = T.TextSecondary,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 8, height = 30,
                            onClick = function() M._inputAmount = tostring(captureQAmt); navigate("capital") end,
                        })
                    end
                    table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickAmts})

                    -- 期限
                    table.insert(formChildren, UI.Panel {
                        width = "100%", gap = 4, marginTop = 6,
                        children = {
                            UI.Label {text = "贷款期限（月）  范围: " .. dr[1] .. "~" .. dr[2] .. "个月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.TextField {
                                value = M._inputDuration, placeholder = "请输入期限",
                                fontSize = T.FontBody, width = "100%", height = 40,
                                borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                                paddingHorizontal = 10, keyboardType = "number",
                                onChange = function(self, text) M._inputDuration = text end,
                            },
                        }
                    })
                    -- 快捷期限
                    local quickDurs = {}
                    local durOpts = dr[2] > 60 and {12, 24, 36, 60, 120} or {6, 12, 24, 36, 60}
                    for _, d in ipairs(durOpts) do
                        if d >= dr[1] and d <= dr[2] then
                            local captureD = d
                            local label = d >= 12 and (math.floor(d / 12) .. "年") or (d .. "月")
                            table.insert(quickDurs, UI.Button {
                                text = label, fontSize = T.FontCaption,
                                backgroundColor = (M._inputDuration == tostring(captureD)) and T.PrimaryLight or T.Surface,
                                fontColor = (M._inputDuration == tostring(captureD)) and T.Primary or T.TextSecondary,
                                borderRadius = T.ButtonRadius, paddingHorizontal = 10, height = 30,
                                onClick = function() M._inputDuration = tostring(captureD); navigate("capital") end,
                            })
                        end
                    end
                    if #quickDurs > 0 then
                        table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickDurs})
                    end

                    -- 还款方式
                    table.insert(formChildren, UI.Panel {
                        width = "100%", gap = 4, marginTop = 6,
                        children = {
                            UI.Label {text = "还款方式", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.Panel {
                                flexDirection = "row", gap = 8, width = "100%",
                                children = (function()
                                    local btns = {}
                                    for _, rm in ipairs(FN.REPAY_METHODS) do
                                        local captureRM = rm
                                        local isSel = (M._selectedRepay == rm.id)
                                        table.insert(btns, UI.Button {
                                            text = rm.name, fontSize = T.FontSmall,
                                            backgroundColor = isSel and T.Primary or T.Surface,
                                            fontColor = isSel and T.TextOnDark or T.TextSecondary,
                                            borderRadius = T.ButtonRadius, paddingHorizontal = 12, height = 34, flexGrow = 1,
                                            onClick = function() M._selectedRepay = captureRM.id; navigate("capital") end,
                                        })
                                    end
                                    return btns
                                end)(),
                            },
                        }
                    })

                    -- 预估
                    local inputAmt = tonumber(M._inputAmount) or 0
                    local inputDur = tonumber(M._inputDuration) or prod.months
                    if inputAmt > 0 and inputDur > 0 then
                        local totalInterest = math.floor(inputAmt * item.effectiveRate / 100 / 12 * inputDur)
                        local monthlyInterest = math.floor(inputAmt * item.effectiveRate / 100 / 12)
                        table.insert(formChildren, UI.Panel {
                            width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                            padding = 8, marginTop = 4, gap = 2,
                            children = {
                                C.InfoRow {label = "预估月利息", value = C.FormatMoney(monthlyInterest), color = T.Warning},
                                C.InfoRow {label = "预估总利息", value = C.FormatMoney(totalInterest), color = T.Danger},
                                C.InfoRow {label = "到期总还款", value = C.FormatMoney(inputAmt + totalInterest), color = T.TextPrimary},
                            }
                        })
                    end

                    -- 确认/取消
                    table.insert(formChildren, UI.Panel {
                        flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
                        children = {
                            UI.Button {
                                text = "取消", fontSize = T.FontBody,
                                backgroundColor = T.Surface, fontColor = T.TextSecondary,
                                borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                                onClick = function() M._expandedProduct = nil; navigate("capital") end,
                            },
                            UI.Button {
                                text = "确认申请", fontSize = T.FontBody,
                                backgroundColor = T.Primary, fontColor = T.TextOnDark,
                                borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                                onClick = function()
                                    local amt = tonumber(M._inputAmount) or 0
                                    local dur = tonumber(M._inputDuration) or prod.months
                                    if amt <= 0 then
                                        GD.AddEvent("请输入有效的贷款金额", "warning")
                                        navigate("capital"); return
                                    end
                                    if amt > maxL then amt = maxL; GD.AddEvent("金额已调整为最大可贷额度", "info") end
                                    local ok, msg = FN.ApplyFinancing(GD, captureItem.id, amt, nil, dur, M._selectedRepay)
                                    if not ok then GD.AddEvent(msg or "贷款申请失败", "danger") end
                                    M._expandedProduct = nil
                                    navigate("capital")
                                end,
                            },
                        }
                    })

                    table.insert(cardItems, UI.Panel {
                        width = "100%", gap = 6, marginTop = 6,
                        padding = 8, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                        children = formChildren,
                    })
                end
            end
        end
        table.insert(productCards, C.Card {children = cardItems})
        ::continue::
    end

    -- === 当前贷款列表 ===
    local loanRows = {}
    for i, loan in ipairs(GD.loans or {}) do
        local captureIdx = i
        local monthInterest = math.floor(loan.amount * loan.rate / 100 / 12)
        local isBullet = (loan.repayMethod == "bullet")
        local repayLabel = isBullet and "到期还本付息" or "按月付息到期还本"
        local accruedInterest = loan.accruedInterest or 0

        local loanInfoRows = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = loan.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {
                        text = loan.remainMonths .. "个月到期",
                        variant = loan.remainMonths <= 6 and "danger" or "info",
                    },
                }
            },
            C.InfoRow {label = "贷款金额", value = C.FormatMoney(loan.amount)},
            C.InfoRow {label = "利率", value = string.format("%.2f%%", loan.rate)},
            C.InfoRow {label = "还款方式", value = repayLabel, color = T.Info},
        }
        if isBullet then
            table.insert(loanInfoRows, C.InfoRow {label = "月利息(累计中)", value = C.FormatMoney(monthInterest), color = T.TextMuted})
            table.insert(loanInfoRows, C.InfoRow {label = "已累计利息", value = C.FormatMoney(math.floor(accruedInterest)), color = T.Warning})
            table.insert(loanInfoRows, C.InfoRow {label = "到期应还", value = C.FormatMoney(loan.amount + math.floor(accruedInterest + monthInterest * loan.remainMonths)), color = T.Danger})
        else
            table.insert(loanInfoRows, C.InfoRow {label = "月利息", value = C.FormatMoney(monthInterest), color = T.Warning})
        end
        table.insert(loanInfoRows, C.InfoRow {label = "剩余期限", value = loan.remainMonths .. "/" .. loan.totalMonths .. "个月"})
        local repayTotal = isBullet and (loan.amount + math.floor(accruedInterest)) or loan.amount
        table.insert(loanInfoRows, C.SecondaryButton {
            text = "提前还款 (" .. C.FormatMoney(repayTotal) .. ")",
            onClick = function()
                local ok, msg = FN.EarlyRepay(GD, captureIdx)
                if not ok then GD.AddEvent(msg or "还款失败", "danger") end
                navigate("capital")
            end,
        })
        table.insert(loanRows, C.Card {children = loanInfoRows})
    end

    -- 贷款统计
    local totalLoanAmount = 0
    local totalMonthlyInterest = 0
    for _, loan in ipairs(GD.loans or {}) do
        totalLoanAmount = totalLoanAmount + loan.amount
        totalMonthlyInterest = totalMonthlyInterest + math.floor(loan.amount * loan.rate / 100 / 12)
    end

    return UI.Panel {
        width = "100%", gap = 10,
        children = {
            -- 贷款概览
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "贷款总额", value = C.FormatMoney(totalLoanAmount), color = T.Warning},
                    C.StatCard {title = "贷款笔数", value = #GD.loans .. "笔", color = T.Info},
                    C.StatCard {title = "月利息支出", value = C.FormatMoney(totalMonthlyInterest), color = T.Danger},
                }
            },

            -- 贷款产品
            C.SectionTitle {text = "贷款产品 (" .. #LOAN_PRODUCT_IDS .. "款)", color = T.Info},
            UI.Panel {width = "100%", gap = 8, children = productCards},

            -- 当前贷款
            C.SectionTitle {text = "当前贷款 (" .. #GD.loans .. "笔)"},
            #loanRows > 0
                and UI.Panel {width = "100%", gap = 8, children = loanRows}
                or UI.Label {text = "暂无贷款", fontSize = T.FontSmall, fontColor = T.TextMuted},
        }
    }
end

-- ============================================================================
-- 固定资产抵押贷款区域（融资中心子标签3）
-- ============================================================================

-- 固定资产入账：装修选择面板状态
M._fixedAssetExpandedId = nil   -- 当前展开装修面板的项目id
M._fixedAssetRenovIdx = 1      -- 选中的装修等级索引(1~4)

-- 抵押表单状态
M._mortgageExpandedIdx = nil
M._mortgageInputAmount = ""
M._mortgageInputMonths = "36"
M._selectedMortgageAssets = M._selectedMortgageAssets or {}
M._selectedMortgageRepayments = M._selectedMortgageRepayments or {}

function M._BuildFixedAssetMortgageSection(navigate, co)
    local summary = GD.GetFixedAssetSummary()

    -- === 1. 可入固定资产的项目列表 ===
    local convertCards = {}
    for _, p in ipairs(GD.projects) do
        if not p._fixedAssetConverted then
            local canConvert = (p.status == "completed" or p.status == "delivery" or p.status == "operations")
            local holdUnits = p.unitPlan and p.unitPlan.holdUnits or 0
            local isHoldType = (p.devCategory or "sale") == "hold"
            if canConvert and (holdUnits > 0 or isHoldType) then
                local captureP = p
                local holdArea = p.unitPlan and p.unitPlan.holdArea or 0
                if isHoldType and holdArea <= 0 then
                    holdArea = p.land and p.land.buildArea or 0
                end
                local monthlyRent = p.assets and p.assets.monthlyRentIncome or 0
                table.insert(convertCards, C.Card {
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            justifyContent = "space-between",
                            alignItems = "center",
                            width = "100%",
                            children = {
                                UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                                C.Badge {
                                    text = isHoldType and "持有型" or "自持",
                                    variant = "accent",
                                },
                            }
                        },
                        C.InfoRow {label = "自持面积", value = string.format("%.0f㎡", holdArea)},
                        C.InfoRow {label = "自持单元", value = tostring(holdUnits > 0 and holdUnits or "-")},
                        monthlyRent > 0 and C.InfoRow {
                            label = "月租金收入",
                            value = C.FormatMoney(monthlyRent),
                            color = T.Success,
                        } or nil,
                        -- 装修+缴税确认面板（展开式）
                        (function()
                            local isExpanded = (M._fixedAssetExpandedId == captureP.id)
                            if not isExpanded then
                                return C.ActionButton {
                                    text = "转入固定资产",
                                    onClick = function()
                                        M._fixedAssetExpandedId = captureP.id
                                        M._fixedAssetRenovIdx = 1
                                        navigate("capital")
                                    end,
                                }
                            end
                            -- 展开面板：装修选择 + 费用预览 + 确认
                            local selIdx = M._fixedAssetRenovIdx or 1
                            local preview = GD.PreviewFixedAssetConvert(captureP, selIdx)
                            if not preview then
                                return UI.Label {text = "无法计算入账信息", fontSize = T.FontCaption, fontColor = T.Danger}
                            end
                            local panelChildren = {}
                            -- 标题
                            table.insert(panelChildren, UI.Label {
                                text = "选择装修等级", fontSize = T.FontSubtitle, fontColor = T.Accent,
                            })
                            -- 装修等级选项
                            for li, lv in ipairs(GD.RENOVATION_LEVELS) do
                                local captureLi = li
                                local isSelected = (li == selIdx)
                                local lvPreview = GD.PreviewFixedAssetConvert(captureP, li)
                                local costText = lv.costPerSqm > 0
                                    and string.format("%d元/㎡ · 共%s", lv.costPerSqm, C.FormatMoney(lvPreview and lvPreview.renovCost or 0))
                                    or "免费"
                                table.insert(panelChildren, UI.Button {
                                    text = lv.name .. "  " .. costText,
                                    fontSize = T.FontCaption,
                                    backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                                    fontColor = isSelected and T.Primary or T.TabInactiveFont,
                                    borderRadius = T.ButtonRadius, width = "100%", height = 36,
                                    paddingHorizontal = 10, marginBottom = 2,
                                    borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                                    onClick = function()
                                        M._fixedAssetRenovIdx = captureLi
                                        navigate("capital")
                                    end,
                                })
                            end
                            -- 费用预览区
                            table.insert(panelChildren, UI.Panel {
                                width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                                padding = 8, marginTop = 6, gap = 2,
                                children = {
                                    C.InfoRow {label = "建设原值", value = C.FormatMoney(preview.originalValue)},
                                    C.InfoRow {label = "装修费用", value = C.FormatMoney(preview.renovCost),
                                        color = preview.renovCost > 0 and T.Warning or T.TextMuted},
                                    C.InfoRow {label = "入账原值（含装修）", value = C.FormatMoney(preview.bookOriginal)},
                                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 3},
                                    C.InfoRow {label = "市场估值上限", value = C.FormatMoney(preview.fullMarketValue), color = T.TextMuted},
                                    C.InfoRow {label = "装修后评估价", value = C.FormatMoney(preview.actualMarketValue), color = T.Accent},
                                    C.InfoRow {label = "增值额", value = C.FormatMoney(preview.taxableAppreciation),
                                        color = preview.taxableAppreciation > 0 and T.Info or T.TextMuted},
                                }
                            })
                            -- LAT税费明细
                            if preview.latTax > 0 then
                                local taxItems = {
                                    UI.Label {text = "土地增值税（四级超额累进）", fontSize = T.FontCaption, fontColor = T.Warning},
                                }
                                for _, d in ipairs(preview.latDetails) do
                                    table.insert(taxItems, C.InfoRow {
                                        label = "增值率" .. d.range .. " × " .. d.rate .. "%",
                                        value = C.FormatMoney(d.tax),
                                        color = T.Warning,
                                    })
                                end
                                table.insert(taxItems, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
                                table.insert(taxItems, C.InfoRow {
                                    label = "应缴税费（实际税率" .. preview.effectiveRate .. "%）",
                                    value = C.FormatMoney(preview.latTax), color = T.Danger,
                                })
                                table.insert(panelChildren, UI.Panel {
                                    width = "100%", backgroundColor = T.WarningBg, borderRadius = T.CardRadius,
                                    padding = 8, marginTop = 4, gap = 2, children = taxItems,
                                })
                            else
                                table.insert(panelChildren, UI.Label {
                                    text = "无增值，免征土地增值税", fontSize = T.FontCaption, fontColor = T.Success, marginTop = 4,
                                })
                            end
                            -- 总支出汇总
                            table.insert(panelChildren, UI.Panel {
                                width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                                padding = 8, marginTop = 4, gap = 2,
                                children = {
                                    C.InfoRow {label = "总支出", value = C.FormatMoney(preview.totalCost), color = T.Danger},
                                    C.InfoRow {label = "当前现金", value = C.FormatMoney(GD.company.cash),
                                        color = GD.company.cash >= preview.totalCost and T.Success or T.Danger},
                                }
                            })
                            -- 资金不足提示
                            local canAfford = GD.company.cash >= preview.totalCost
                            if not canAfford then
                                table.insert(panelChildren, UI.Label {
                                    text = "资金不足，还需" .. C.FormatMoney(preview.totalCost - GD.company.cash),
                                    fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 2,
                                })
                            end
                            -- 确认/取消按钮
                            table.insert(panelChildren, UI.Panel {
                                flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
                                children = {
                                    UI.Button {
                                        text = "取消", fontSize = T.FontBody,
                                        backgroundColor = T.Surface, fontColor = T.TextSecondary,
                                        borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                                        onClick = function()
                                            M._fixedAssetExpandedId = nil
                                            navigate("capital")
                                        end,
                                    },
                                    UI.Button {
                                        text = canAfford and "确认装修并入账" or "资金不足",
                                        fontSize = T.FontBody,
                                        backgroundColor = canAfford and T.Primary or T.TextMuted,
                                        fontColor = T.TextOnDark,
                                        borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                                        onClick = canAfford and function()
                                            local ok = GD.ConvertToFixedAsset(captureP, selIdx)
                                            M._fixedAssetExpandedId = nil
                                            navigate("capital")
                                        end or nil,
                                    },
                                }
                            })
                            return UI.Panel {
                                width = "100%", gap = 6, marginTop = 6,
                                padding = 10, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                                children = panelChildren,
                            }
                        end)(),
                    }
                })
            end
        end
    end

    -- === 2. 已有固定资产列表 ===
    local assetCards = {}
    for idx, fa in ipairs(GD.fixedAssets) do
        local captureIdx = idx
        local captureFa = fa
        local mortgageInfo = GD.GetFixedAssetMortgageInfo(idx)
        local mortgageLoan = nil
        local mortgageLoanIdx = nil
        for loanIdx, loan in ipairs(GD.loans or {}) do
            if loan.isFixedAssetMortgage and loan.fixedAssetIdx == idx then
                mortgageLoan = loan
                mortgageLoanIdx = loanIdx
                break
            end
        end

        local cardItems = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = fa.projectName, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {
                        text = fa.mortgaged and "已抵押" or "未抵押",
                        variant = fa.mortgaged and "warning" or "success",
                    },
                }
            },
            C.InfoRow {label = "原值", value = C.FormatMoney(fa.originalValue)},
            C.InfoRow {label = "账面净值", value = C.FormatMoney(fa.bookValue)},
            C.InfoRow {label = "评估市值", value = C.FormatMoney(fa.currentValue), color = T.Accent},
            C.InfoRow {label = "自持面积", value = string.format("%.0f㎡", fa.holdArea)},
        }
        if fa.monthlyRent > 0 then
            table.insert(cardItems, C.InfoRow {
                label = "月租金",
                value = C.FormatMoney(fa.monthlyRent) .. " (出租率" .. math.floor(fa.occupancyRate or 0) .. "%)",
                color = T.Success,
            })
        end
        if mortgageInfo.available then
            table.insert(cardItems, UI.Checkbox {
                checked = M._selectedMortgageAssets[captureIdx] == true,
                label = "选择此资产批量抵押",
                onChange = function(_, checked)
                    M._selectedMortgageAssets[captureIdx] = checked and true or nil
                    navigate("capital")
                end,
            })
        elseif mortgageLoan and mortgageLoanIdx then
            local repayAmount = FN.GetEarlyRepayAmount(mortgageLoan)
            table.insert(cardItems, UI.Checkbox {
                checked = M._selectedMortgageRepayments[captureIdx] == true,
                label = "选择还清此抵押贷款（" .. C.FormatMoney(repayAmount) .. "）",
                onChange = function(_, checked)
                    M._selectedMortgageRepayments[captureIdx] = checked and true or nil
                    navigate("capital")
                end,
            })
        end
        -- 抵押操作
        if mortgageInfo.available then
            table.insert(cardItems, UI.Panel {height = 6})
            table.insert(cardItems, C.InfoRow {
                label = "可贷额度",
                value = C.FormatMoney(mortgageInfo.maxAmount) .. " (抵押率" .. math.floor(mortgageInfo.maxRatio * 100) .. "%)",
                color = T.Success,
            })
            table.insert(cardItems, C.InfoRow {
                label = "贷款利率",
                value = string.format("%.1f%%", mortgageInfo.rate) .. "（固定）",
                color = T.Warning,
            })
            table.insert(cardItems, C.InfoRow {
                label = "贷款期限",
                value = "12~" .. mortgageInfo.maxMonths .. "个月",
            })

            local isExpanded = (M._mortgageExpandedIdx == captureIdx)
            if not isExpanded then
                table.insert(cardItems, C.ActionButton {
                    text = "申请抵押贷款",
                    onClick = function()
                        M._mortgageExpandedIdx = captureIdx
                        M._mortgageInputAmount = tostring(math.floor(mortgageInfo.maxAmount * 0.5 / 100) * 100)
                        M._mortgageInputMonths = "36"
                        navigate("capital")
                    end,
                })
            else
                -- 展开的抵押贷款申请表单
                local maxA = mortgageInfo.maxAmount
                local formChildren = {}
                -- 金额输入
                table.insert(formChildren, UI.Panel {
                    width = "100%", gap = 4,
                    children = {
                        UI.Label {text = "贷款金额（万元）  上限: " .. C.FormatMoney(maxA), fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._mortgageInputAmount, placeholder = "请输入金额",
                            fontSize = T.FontBody, width = "100%", height = 40,
                            borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                            paddingHorizontal = 10, keyboardType = "number",
                            onChange = function(self, text) M._mortgageInputAmount = text end,
                        },
                    }
                })
                -- 快捷金额
                local quickAmts = {}
                for _, pct in ipairs({0.3, 0.5, 0.8, 1.0}) do
                    local qAmt = math.floor(maxA * pct / 100) * 100
                    if qAmt < 100 then qAmt = 100 end
                    local captureQAmt = qAmt
                    table.insert(quickAmts, UI.Button {
                        text = math.floor(pct * 100) .. "%", fontSize = T.FontCaption,
                        backgroundColor = T.Surface, fontColor = T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 8, height = 30,
                        onClick = function() M._mortgageInputAmount = tostring(captureQAmt); navigate("capital") end,
                    })
                end
                table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickAmts})

                -- 期限输入
                table.insert(formChildren, UI.Panel {
                    width = "100%", gap = 4, marginTop = 6,
                    children = {
                        UI.Label {text = "贷款期限（月）  范围: 12~" .. mortgageInfo.maxMonths .. "个月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._mortgageInputMonths, placeholder = "请输入期限",
                            fontSize = T.FontBody, width = "100%", height = 40,
                            borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                            paddingHorizontal = 10, keyboardType = "number",
                            onChange = function(self, text) M._mortgageInputMonths = text end,
                        },
                    }
                })
                -- 快捷期限
                local quickDurs = {}
                for _, d in ipairs({12, 24, 36}) do
                    local captureD = d
                    local label = (d / 12) .. "年"
                    table.insert(quickDurs, UI.Button {
                        text = label, fontSize = T.FontCaption,
                        backgroundColor = (M._mortgageInputMonths == tostring(captureD)) and T.PrimaryLight or T.Surface,
                        fontColor = (M._mortgageInputMonths == tostring(captureD)) and T.Primary or T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 10, height = 30,
                        onClick = function() M._mortgageInputMonths = tostring(captureD); navigate("capital") end,
                    })
                end
                table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickDurs})

                -- 预估
                local inputAmt = tonumber(M._mortgageInputAmount) or 0
                local inputDur = tonumber(M._mortgageInputMonths) or 36
                if inputAmt > 0 and inputDur > 0 then
                    local monthlyInterest = math.floor(inputAmt * mortgageInfo.rate / 100 / 12)
                    local totalInterest = math.floor(inputAmt * mortgageInfo.rate / 100 / 12 * inputDur)
                    table.insert(formChildren, UI.Panel {
                        width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                        padding = 8, marginTop = 4, gap = 2,
                        children = {
                            C.InfoRow {label = "预估月利息", value = C.FormatMoney(monthlyInterest), color = T.Warning},
                            C.InfoRow {label = "预估总利息", value = C.FormatMoney(totalInterest), color = T.Danger},
                            C.InfoRow {label = "到期总还款", value = C.FormatMoney(inputAmt + totalInterest), color = T.TextPrimary},
                        }
                    })
                end

                -- 确认/取消
                table.insert(formChildren, UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
                    children = {
                        UI.Button {
                            text = "取消", fontSize = T.FontBody,
                            backgroundColor = T.Surface, fontColor = T.TextSecondary,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                            onClick = function() M._mortgageExpandedIdx = nil; navigate("capital") end,
                        },
                        UI.Button {
                            text = "确认申请", fontSize = T.FontBody,
                            backgroundColor = T.Primary, fontColor = T.TextOnDark,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                            onClick = function()
                                local amt = tonumber(M._mortgageInputAmount) or 0
                                local dur = tonumber(M._mortgageInputMonths) or 36
                                if amt <= 0 then
                                    GD.AddEvent("请输入有效的贷款金额", "warning")
                                    navigate("capital"); return
                                end
                                if amt > maxA then amt = maxA end
                                local ok = GD.ApplyFixedAssetMortgage(captureIdx, amt, dur)
                                if not ok then
                                    GD.AddEvent("抵押贷款申请失败", "danger")
                                end
                                M._mortgageExpandedIdx = nil
                                navigate("capital")
                            end,
                        },
                    }
                })
                table.insert(cardItems, UI.Panel {
                    width = "100%", gap = 6, marginTop = 6,
                    padding = 8, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                    children = formChildren,
                })
            end
        elseif fa.mortgaged and mortgageInfo.existingLoan then
            table.insert(cardItems, C.InfoRow {
                label = "抵押贷款余额",
                value = C.FormatMoney(mortgageInfo.existingLoan),
                color = T.Danger,
            })
        end
        table.insert(assetCards, C.Card {children = cardItems})
    end

    -- === 3. 组装 ===
    local children = {}

    -- 固定资产概览统计卡
    if summary.count > 0 then
        table.insert(children, C.SectionTitle {text = "固定资产概览", color = T.Accent})
        table.insert(children, UI.Panel {
            flexDirection = "row",
            gap = 10,
            width = "100%",
            flexWrap = "wrap",
            children = {
                C.StatCard {title = "固定资产数", value = tostring(summary.count), color = T.Info},
                C.StatCard {title = "账面总值", value = C.FormatMoney(summary.totalBook), color = T.Accent},
                C.StatCard {title = "评估总值", value = C.FormatMoney(summary.totalMarket), color = T.Success},
                summary.totalMonthlyRent > 0 and C.StatCard {
                    title = "月租金合计",
                    value = C.FormatMoney(summary.totalMonthlyRent),
                    color = T.Success,
                } or nil,
                summary.mortgagedCount > 0 and C.StatCard {
                    title = "已抵押",
                    value = summary.mortgagedCount .. "项",
                    color = T.Warning,
                } or nil,
            }
        })
    end

    -- 可转入固定资产的项目
    if #convertCards > 0 then
        table.insert(children, C.SectionTitle {text = "可转入固定资产 (" .. #convertCards .. "个项目)"})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = convertCards})
    end

    -- 已有固定资产
    if #assetCards > 0 then
        local eligibleAssetIndexes = {}
        local selectedAssetIndexes = {}
        local selectedMortgageAmount = 0
        local repayableAssetIndexes = {}
        local selectedLoanIndexes = {}
        local selectedRepayAmount = 0

        for idx, fa in ipairs(GD.fixedAssets) do
            local info = GD.GetFixedAssetMortgageInfo(idx)
            if info and info.available then
                table.insert(eligibleAssetIndexes, idx)
                if M._selectedMortgageAssets[idx] then
                    table.insert(selectedAssetIndexes, idx)
                    selectedMortgageAmount = selectedMortgageAmount + math.floor(info.maxAmount * 0.5 / 100) * 100
                end
            else
                M._selectedMortgageAssets[idx] = nil
            end

            local loanIdx = nil
            local loan = nil
            for i, item in ipairs(GD.loans or {}) do
                if item.isFixedAssetMortgage and item.fixedAssetIdx == idx then
                    loanIdx = i
                    loan = item
                    break
                end
            end
            if fa.mortgaged and loanIdx and loan then
                table.insert(repayableAssetIndexes, idx)
                if M._selectedMortgageRepayments[idx] then
                    table.insert(selectedLoanIndexes, loanIdx)
                    selectedRepayAmount = selectedRepayAmount + FN.GetEarlyRepayAmount(loan)
                end
            else
                M._selectedMortgageRepayments[idx] = nil
            end
        end

        if #eligibleAssetIndexes > 0 then
            table.insert(children, C.Card {children = {
                C.SectionTitle {text = "批量抵押贷款"},
                C.InfoRow {label = "已选资产", value = #selectedAssetIndexes .. "/" .. #eligibleAssetIndexes .. "项"},
                C.InfoRow {label = "贷款总额（50%额度）", value = C.FormatMoney(selectedMortgageAmount), color = T.Success},
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
                    children = {
                        C.SecondaryButton {
                            text = "全选未抵押资产",
                            onClick = function()
                                M._selectedMortgageAssets = {}
                                for _, idx in ipairs(eligibleAssetIndexes) do M._selectedMortgageAssets[idx] = true end
                                navigate("capital")
                            end,
                        },
                        C.SecondaryButton {
                            text = "清空选择",
                            onClick = function()
                                M._selectedMortgageAssets = {}
                                navigate("capital")
                            end,
                        },
                    },
                },
                C.ActionButton {
                    text = #selectedAssetIndexes > 0 and ("抵押所选" .. #selectedAssetIndexes .. "项") or "请先选择资产",
                    bgColor = #selectedAssetIndexes > 0 and T.Accent or T.TextMuted,
                    width = "100%",
                    onClick = #selectedAssetIndexes > 0 and function()
                        local successCount = 0
                        for _, idx in ipairs(selectedAssetIndexes) do
                            local info = GD.GetFixedAssetMortgageInfo(idx)
                            if info and info.available then
                                local amount = math.floor(info.maxAmount * 0.5 / 100) * 100
                                if amount >= 100 and GD.ApplyFixedAssetMortgage(idx, amount, 36) then
                                    successCount = successCount + 1
                                end
                            end
                        end
                        M._selectedMortgageAssets = {}
                        GD.AddEvent("批量抵押完成：成功" .. successCount .. "项", successCount > 0 and "success" or "warning")
                        navigate("capital")
                    end or nil,
                },
                UI.Label {text = "所选资产均按可贷额度50%、36个月固定利率申请", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }})
        end

        if #repayableAssetIndexes > 0 then
            table.insert(children, C.Card {children = {
                C.SectionTitle {text = "批量还清抵押贷款"},
                C.InfoRow {label = "已选贷款", value = #selectedLoanIndexes .. "/" .. #repayableAssetIndexes .. "笔"},
                C.InfoRow {label = "本次还款总额", value = C.FormatMoney(selectedRepayAmount), color = T.Danger},
                C.InfoRow {label = "公司现金", value = C.FormatMoney(co.cash), color = co.cash >= selectedRepayAmount and T.Success or T.Danger},
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
                    children = {
                        C.SecondaryButton {
                            text = "全选已抵押资产",
                            onClick = function()
                                M._selectedMortgageRepayments = {}
                                for _, idx in ipairs(repayableAssetIndexes) do M._selectedMortgageRepayments[idx] = true end
                                navigate("capital")
                            end,
                        },
                        C.SecondaryButton {
                            text = "清空选择",
                            onClick = function()
                                M._selectedMortgageRepayments = {}
                                navigate("capital")
                            end,
                        },
                    },
                },
                C.ActionButton {
                    text = #selectedLoanIndexes > 0 and ("一键还清所选" .. #selectedLoanIndexes .. "笔") or "请先选择贷款",
                    bgColor = #selectedLoanIndexes > 0 and T.Success or T.TextMuted,
                    width = "100%",
                    onClick = #selectedLoanIndexes > 0 and function()
                        local ok = GD.BatchEarlyRepayLoans(selectedLoanIndexes)
                        if ok then
                            M._selectedMortgageRepayments = {}
                        end
                        navigate("capital")
                    end or nil,
                },
                UI.Label {text = "批量还款会先核对总额；现金不足时整批不执行，成功后自动解除资产抵押", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }})
        end

        table.insert(children, C.SectionTitle {text = "固定资产清单 (" .. #assetCards .. "项)", color = T.Accent})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = assetCards})
    end

    -- 空状态
    if #convertCards == 0 and #assetCards == 0 then
        table.insert(children, C.SectionTitle {text = "固定资产"})
        table.insert(children, UI.Label {
            text = "暂无固定资产（自持项目竣工后可转入）",
            fontSize = T.FontSmall,
            fontColor = T.TextMuted,
        })
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = children,
    }
end

-- ============================================================================
-- 项目抵押贷款区域（融资中心子标签4）
-- ============================================================================

M._projMortgageExpandedId = nil
M._projMortgageInputAmount = ""
M._projMortgageInputMonths = "36"

function M._BuildProjectMortgageSection(navigate, co)
    -- 可抵押的项目列表（仅在建工程，已竣工/交付/售完的不显示）
    local projectCards = {}
    for _, p in ipairs(GD.projects) do
        -- 过滤已竣工/已交付/已售完/已转固定资产的项目
        if p.status == "completed" or p.status == "sold_off" or p.status == "delivery"
            or p.status == "operations" or p._fixedAssetConverted then
            goto continue_proj_mortgage
        end
        local info = GD.GetProjectLoanInfo(p)
        local captureP = p
        local captureInfo = info

        local cardItems = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {
                        text = info.available and "可抵押" or (p.status == "construction" and "已达上限" or p.status),
                        variant = info.available and "success" or "warning",
                    },
                }
            },
        }

        -- 项目基本信息
        local projValue = (p.cost and p.cost.landCost or 0) + (p.cost and p.cost.buildCost or 0)
        table.insert(cardItems, C.InfoRow {label = "项目状态", value = p.status == "construction" and "施工中" or (p.status or "-")})
        table.insert(cardItems, C.InfoRow {label = "项目价值", value = C.FormatMoney(projValue)})

        if info.available then
            table.insert(cardItems, C.InfoRow {
                label = "可贷额度",
                value = C.FormatMoney(info.availableAmount) .. " (抵押率" .. math.floor(info.maxRatio * 100) .. "%)",
                color = T.Success,
            })
            table.insert(cardItems, C.InfoRow {
                label = "贷款利率",
                value = string.format("%.1f%%", info.rate) .. "（固定）",
                color = T.Warning,
            })
            table.insert(cardItems, C.InfoRow {
                label = "贷款期限",
                value = "12~" .. info.maxMonths .. "个月",
            })
            if info.existingLoan > 0 then
                table.insert(cardItems, C.InfoRow {
                    label = "已有抵押",
                    value = C.FormatMoney(info.existingLoan),
                    color = T.Danger,
                })
            end

            local isExpanded = (M._projMortgageExpandedId == p.id)
            if not isExpanded then
                table.insert(cardItems, C.ActionButton {
                    text = "申请项目抵押贷款",
                    onClick = function()
                        M._projMortgageExpandedId = captureP.id
                        M._projMortgageInputAmount = tostring(math.floor(captureInfo.availableAmount * 0.5 / 100) * 100)
                        M._projMortgageInputMonths = "36"
                        navigate("capital")
                    end,
                })
            else
                -- 展开的申请表单
                local maxA = info.availableAmount
                local formChildren = {}
                -- 金额输入
                table.insert(formChildren, UI.Panel {
                    width = "100%", gap = 4,
                    children = {
                        UI.Label {text = "贷款金额（万元）  上限: " .. C.FormatMoney(maxA), fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._projMortgageInputAmount, placeholder = "请输入金额",
                            fontSize = T.FontBody, width = "100%", height = 40,
                            borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                            paddingHorizontal = 10, keyboardType = "number",
                            onChange = function(self, text) M._projMortgageInputAmount = text end,
                        },
                    }
                })
                -- 快捷金额
                local quickAmts = {}
                for _, pct in ipairs({0.3, 0.5, 0.8, 1.0}) do
                    local qAmt = math.floor(maxA * pct / 100) * 100
                    if qAmt < 100 then qAmt = 100 end
                    local captureQAmt = qAmt
                    table.insert(quickAmts, UI.Button {
                        text = math.floor(pct * 100) .. "%", fontSize = T.FontCaption,
                        backgroundColor = T.Surface, fontColor = T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 8, height = 30,
                        onClick = function() M._projMortgageInputAmount = tostring(captureQAmt); navigate("capital") end,
                    })
                end
                table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickAmts})

                -- 期限输入
                table.insert(formChildren, UI.Panel {
                    width = "100%", gap = 4, marginTop = 6,
                    children = {
                        UI.Label {text = "贷款期限（月）  范围: 12~" .. info.maxMonths .. "个月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = M._projMortgageInputMonths, placeholder = "请输入期限",
                            fontSize = T.FontBody, width = "100%", height = 40,
                            borderRadius = T.ButtonRadius, borderWidth = 1, borderColor = T.Border,
                            paddingHorizontal = 10, keyboardType = "number",
                            onChange = function(self, text) M._projMortgageInputMonths = text end,
                        },
                    }
                })
                -- 快捷期限
                local quickDurs = {}
                for _, d in ipairs({12, 24, 36}) do
                    local captureD = d
                    local label = (d / 12) .. "年"
                    table.insert(quickDurs, UI.Button {
                        text = label, fontSize = T.FontCaption,
                        backgroundColor = (M._projMortgageInputMonths == tostring(captureD)) and T.PrimaryLight or T.Surface,
                        fontColor = (M._projMortgageInputMonths == tostring(captureD)) and T.Primary or T.TextSecondary,
                        borderRadius = T.ButtonRadius, paddingHorizontal = 10, height = 30,
                        onClick = function() M._projMortgageInputMonths = tostring(captureD); navigate("capital") end,
                    })
                end
                table.insert(formChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = quickDurs})

                -- 预估
                local inputAmt = tonumber(M._projMortgageInputAmount) or 0
                local inputDur = tonumber(M._projMortgageInputMonths) or 36
                if inputAmt > 0 and inputDur > 0 then
                    local monthlyInterest = math.floor(inputAmt * info.rate / 100 / 12)
                    local totalInterest = math.floor(inputAmt * info.rate / 100 / 12 * inputDur)
                    table.insert(formChildren, UI.Panel {
                        width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
                        padding = 8, marginTop = 4, gap = 2,
                        children = {
                            C.InfoRow {label = "预估月利息", value = C.FormatMoney(monthlyInterest), color = T.Warning},
                            C.InfoRow {label = "预估总利息", value = C.FormatMoney(totalInterest), color = T.Danger},
                            C.InfoRow {label = "到期总还款", value = C.FormatMoney(inputAmt + totalInterest), color = T.TextPrimary},
                        }
                    })
                end

                -- 确认/取消
                table.insert(formChildren, UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
                    children = {
                        UI.Button {
                            text = "取消", fontSize = T.FontBody,
                            backgroundColor = T.Surface, fontColor = T.TextSecondary,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                            onClick = function() M._projMortgageExpandedId = nil; navigate("capital") end,
                        },
                        UI.Button {
                            text = "确认申请", fontSize = T.FontBody,
                            backgroundColor = T.Primary, fontColor = T.TextOnDark,
                            borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                            onClick = function()
                                local amt = tonumber(M._projMortgageInputAmount) or 0
                                local dur = tonumber(M._projMortgageInputMonths) or 36
                                if amt <= 0 then
                                    GD.AddEvent("请输入有效的贷款金额", "warning")
                                    navigate("capital"); return
                                end
                                if amt > maxA then amt = maxA end
                                local ok = GD.ApplyProjectMortgage(captureP, amt, dur)
                                if not ok then
                                    GD.AddEvent("项目抵押贷款申请失败", "danger")
                                end
                                M._projMortgageExpandedId = nil
                                navigate("capital")
                            end,
                        },
                    }
                })
                table.insert(cardItems, UI.Panel {
                    width = "100%", gap = 6, marginTop = 6,
                    padding = 8, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
                    children = formChildren,
                })
            end
        else
            -- 不可抵押：显示原因
            if info.reason then
                table.insert(cardItems, UI.Label {
                    text = info.reason,
                    fontSize = T.FontCaption, fontColor = T.TextMuted,
                })
            end
        end

        table.insert(projectCards, C.Card {children = cardItems})
        ::continue_proj_mortgage::
    end

    -- 现有项目抵押贷款列表
    local mortgageLoanRows = {}
    for i, loan in ipairs(GD.loans or {}) do
        if loan.isProjectMortgage then
            local captureIdx = i
            local monthInterest = math.floor(loan.amount * loan.rate / 100 / 12)
            table.insert(mortgageLoanRows, C.Card {
                children = {
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                        children = {
                            UI.Label {text = loan.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            C.Badge {
                                text = loan.remainMonths .. "个月到期",
                                variant = loan.remainMonths <= 6 and "danger" or "info",
                            },
                        }
                    },
                    C.InfoRow {label = "贷款金额", value = C.FormatMoney(loan.amount)},
                    C.InfoRow {label = "利率", value = string.format("%.1f%%", loan.rate)},
                    C.InfoRow {label = "月利息", value = C.FormatMoney(monthInterest), color = T.Warning},
                    C.InfoRow {label = "剩余期限", value = loan.remainMonths .. "/" .. loan.totalMonths .. "个月"},
                    C.SecondaryButton {
                        text = "提前还款 (" .. C.FormatMoney(loan.amount) .. ")",
                        onClick = function()
                            local ok, msg = FN.EarlyRepay(GD, captureIdx)
                            if not ok then GD.AddEvent(msg or "还款失败", "danger") end
                            navigate("capital")
                        end,
                    },
                }
            })
        end
    end

    local children = {}

    -- 说明
    table.insert(children, UI.Panel {
        width = "100%", backgroundColor = T.WarningBg, borderRadius = T.CardRadius, padding = 10,
        children = {
            UI.Label {
                text = "项目抵押贷款：仅限施工阶段的在建工程，抵押率70%，固定利率3%，期限1-3年。到期未还将强制拍卖项目。",
                fontSize = T.FontCaption, fontColor = T.AccentDark,
            },
        }
    })

    -- 可抵押项目
    if #projectCards > 0 then
        table.insert(children, C.SectionTitle {text = "项目列表 (" .. #GD.projects .. "个)", color = T.Info})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = projectCards})
    else
        table.insert(children, UI.Label {
            text = "暂无项目（请先取得土地并开工建设）",
            fontSize = T.FontSmall, fontColor = T.TextMuted,
        })
    end

    -- 现有项目抵押贷款
    if #mortgageLoanRows > 0 then
        table.insert(children, C.SectionTitle {text = "项目抵押贷款 (" .. #mortgageLoanRows .. "笔)"})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = mortgageLoanRows})
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab2: 资金管理 — 现金流 / 监管账户 / 存款
-- ============================================================================
function M._TabCashMgmt(navigate, co)
    local fin = GD.finance or {}
    local cf = fin.cashFlow or {}

    -- 现金流概览 — 基于净流量生成3个月滚动预测
    local netFlow = cf.netFlow or 0
    local forecastItems = {}
    for i = 1, 3 do
        local predicted = co.cash + netFlow * i
        table.insert(forecastItems, C.InfoRow {
            label = "第" .. i .. "个月预测",
            value = C.FormatMoney(predicted),
            color = predicted < FN.CASH_SAFETY_LINE and T.Danger or T.Success,
        })
    end

    -- 监管账户列表 — 显示项目名称
    local escrowCards = {}
    local escrowAccounts = fin.escrowAccounts or {}
    for pid, ea in pairs(escrowAccounts) do
        local capturePid = pid
        local captureEa = ea
        -- 查找项目名称
        local projectName = "项目#" .. tostring(pid)
        for _, p in ipairs(GD.projects) do
            if p.id == pid then projectName = p.name; break end
        end
        local escrowBalance = (ea.total or 0) - (ea.released or 0)
        local items = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = projectName, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = ea.frozen and "已冻结" or "正常", variant = ea.frozen and "danger" or "success"},
                }
            },
            C.InfoRow {label = "监管总额", value = C.FormatMoney(ea.total or 0)},
            C.InfoRow {label = "已释放", value = C.FormatMoney(ea.released or 0), color = T.Success},
            C.InfoRow {label = "可用余额", value = C.FormatMoney(escrowBalance), color = T.Info},
        }
        -- 挪用按钮（高风险操作）
        if not ea.frozen and escrowBalance > 0 then
            local misAmt = math.floor(escrowBalance * 0.3)
            if misAmt > 0 then
                table.insert(items, C.SecondaryButton {
                    text = "挪用 " .. C.FormatMoney(misAmt) .. " (风险!)",
                    onClick = function()
                        local ok, msg = FN.AttemptMisappropriation(GD, capturePid, misAmt)
                        if not ok then
                            GD.AddEvent(msg or "挪用失败", "danger")
                        end
                        navigate("capital")
                    end,
                })
            end
        end
        table.insert(escrowCards, C.Card {children = items})
    end

    -- 活期存款卡片
    local demandBalance = fin.demandBalance or 0
    local demandCard = C.Card {
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = "活期存款账户", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                    C.Badge {text = string.format("%.2f%%", FN.DEPOSIT_TYPES[1].rate), variant = "info"},
                }
            },
            C.InfoRow {label = "账户余额", value = C.FormatMoney(demandBalance), color = T.Success},
            -- 存入多档金额
            UI.Label {text = "存入金额", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginTop = 4},
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                width = "100%",
                flexWrap = "wrap",
                children = (function()
                    local btns = {}
                    for _, amt in ipairs(FN.DEPOSIT_AMOUNTS) do
                        local captureAmt = amt
                        local canAfford = co.cash >= amt
                        table.insert(btns, UI.Button {
                            text = C.FormatMoney(captureAmt),
                            fontSize = T.FontSmall,
                            backgroundColor = canAfford and T.PrimaryLight or T.DisabledBg,
                            fontColor = canAfford and T.Primary or T.TextMuted,
                            borderRadius = T.ButtonRadius,
                            paddingHorizontal = 12,
                            height = 32,
                            disabled = not canAfford,
                            onClick = function()
                                local ok, msg = FN.MakeDeposit(GD, "demand", captureAmt)
                                if not ok then GD.AddEvent(msg or "存款失败", "danger") end
                                navigate("capital")
                            end,
                        })
                    end
                    return btns
                end)(),
            },
            -- 取出按钮
            demandBalance > 0 and C.SecondaryButton {
                text = "全部取出 " .. C.FormatMoney(demandBalance),
                onClick = function()
                    local ok, msg = FN.WithdrawDeposit(GD, 0)
                    if not ok then GD.AddEvent(msg or "取款失败", "danger") end
                    navigate("capital")
                end,
            } or nil,
        }
    }

    -- 定期存款产品
    local fixedDepositCards = {}
    for i = 2, #FN.DEPOSIT_TYPES do  -- 跳过活期(index 1)
        local dt = FN.DEPOSIT_TYPES[i]
        local captureDt = dt
        table.insert(fixedDepositCards, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {text = dt.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {text = string.format("%.2f%%", dt.rate), variant = "info"},
                    }
                },
                C.InfoRow {label = "期限", value = dt.minMonths .. "个月"},
                C.InfoRow {label = "起存金额", value = C.FormatMoney(dt.minAmount)},
                -- 多档存款金额
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    width = "100%",
                    flexWrap = "wrap",
                    marginTop = 4,
                    children = (function()
                        local btns = {}
                        for _, amt in ipairs(FN.DEPOSIT_AMOUNTS) do
                            if amt >= dt.minAmount then
                                local captureAmt = amt
                                local canAfford = co.cash >= amt
                                table.insert(btns, UI.Button {
                                    text = C.FormatMoney(captureAmt),
                                    fontSize = T.FontSmall,
                                    backgroundColor = canAfford and T.PrimaryLight or T.DisabledBg,
                                    fontColor = canAfford and T.Primary or T.TextMuted,
                                    borderRadius = T.ButtonRadius,
                                    paddingHorizontal = 12,
                                    height = 32,
                                    disabled = not canAfford,
                                    onClick = function()
                                        local ok, msg = FN.MakeDeposit(GD, captureDt.id, captureAmt)
                                        if not ok then GD.AddEvent(msg or "存款失败", "danger") end
                                        navigate("capital")
                                    end,
                                })
                            end
                        end
                        return btns
                    end)(),
                },
            }
        })
    end

    -- 已有定期存款
    local existingDeposits = {}
    for i, d in ipairs(fin.deposits or {}) do
        local captureIdx = i
        local elapsed = (GD.totalMonths or 0) - d.startMonth
        local remaining = math.max(0, d.months - elapsed)
        local earnedInterest = math.floor(d.amount * d.rate / 100 / 12 * elapsed)
        table.insert(existingDeposits, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {text = d.name or d.type, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        UI.Label {
                            text = C.FormatMoney(d.amount),
                            fontSize = T.FontBody,
                            fontColor = T.Success,
                        },
                    }
                },
                C.InfoRow {label = "年利率", value = string.format("%.2f%%", d.rate)},
                C.InfoRow {label = "累计利息", value = C.FormatMoney(earnedInterest), color = T.Info},
                C.InfoRow {label = "剩余期限", value = remaining .. "个月"},
                C.ProgressCard {
                    title = "到期进度",
                    progress = d.months > 0 and math.min(100, elapsed / d.months * 100) or 0,
                    barColor = remaining <= 1 and T.Success or T.Accent,
                },
                C.SecondaryButton {
                    text = remaining <= 0 and "到期取出" or "提前取出(损失利息)",
                    onClick = function()
                        local ok, msg = FN.WithdrawDeposit(GD, captureIdx)
                        if not ok then GD.AddEvent(msg or "取款失败", "danger") end
                        navigate("capital")
                    end,
                },
            }
        })
    end

    -- 项目资金总览卡片
    local projectFundCards = {}
    local totalAllocated, totalSpent, totalRemaining = 0, 0, 0
    local activeProjects = {}
    for _, p in ipairs(GD.projects) do
        if p.status ~= "completed" then
            table.insert(activeProjects, p)
        end
    end

    for _, proj in ipairs(activeProjects) do
        local captureProj = proj
        local bs = PC.GetBudgetSummary(proj)
        totalAllocated = totalAllocated + bs.allocated
        totalSpent = totalSpent + bs.spent
        totalRemaining = totalRemaining + bs.remaining

        -- 状态标签
        local statusMap = {
            permits = "报建", design = "设计", construction = "施工",
            presale = "预售", completed = "竣工",
        }
        local statusText = statusMap[proj.status] or proj.status

        -- 预算使用率
        local usageRatio = bs.allocated > 0 and math.floor(bs.spent / bs.allocated * 100) or 0

        -- 建议拨付额
        local suggested = PC.CalcSuggestedAllocation(proj)

        local cardItems = {
            -- 项目名称 + 状态
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = proj.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = statusText, variant = "info"},
                },
            },
            C.InfoRow {label = "已拨付", value = C.FormatMoney(bs.allocated), color = T.Info},
            C.InfoRow {label = "已支出", value = C.FormatMoney(bs.spent), color = T.Warning},
            C.InfoRow {label = "账户余额", value = C.FormatMoney(bs.remaining), color = bs.remaining < 0 and T.Danger or T.Success},
        }

        -- 预算进度条
        if bs.allocated > 0 then
            table.insert(cardItems, C.ProgressCard {
                title = "预算使用",
                progress = math.min(100, usageRatio),
                barColor = usageRatio >= 90 and T.Danger or usageRatio >= 70 and T.Warning or T.Accent,
            })
        end

        -- 月消耗与剩余月数
        if bs.burnRate > 0 then
            table.insert(cardItems, C.InfoRow {
                label = "月消耗/可维持",
                value = C.FormatMoney(bs.burnRate) .. " · " .. bs.monthsLeft .. "个月",
                color = bs.monthsLeft <= 3 and T.Danger or T.TextSecondary,
            })
        end

        -- 拨款按钮组
        local allocBtns = {}
        local amounts = {500, 1000, 2000, 5000}
        for _, amt in ipairs(amounts) do
            local captureAmt = amt
            local canAfford = co.cash >= amt
            table.insert(allocBtns, UI.Button {
                text = C.FormatMoney(captureAmt),
                fontSize = T.FontSmall,
                backgroundColor = canAfford and T.PrimaryLight or T.DisabledBg,
                fontColor = canAfford and T.Primary or T.TextMuted,
                borderRadius = T.ButtonRadius,
                paddingHorizontal = 10,
                height = 30,
                disabled = not canAfford,
                onClick = function()
                    local ok, msg = PC.AllocateFund(co, captureProj, captureAmt)
                    if ok then
                        GD.AddEvent(captureProj.name .. " 拨付 " .. C.FormatMoney(captureAmt), "success")
                    else
                        GD.AddEvent(msg or "拨付失败", "danger")
                    end
                    navigate("capital")
                end,
            })
        end

        -- 智能推荐拨付
        if suggested > 0 and co.cash >= suggested then
            local captureSuggested = suggested
            table.insert(allocBtns, UI.Button {
                text = "推荐 " .. C.FormatMoney(captureSuggested),
                fontSize = T.FontSmall,
                backgroundColor = T.Success,
                fontColor = T.TextOnDark,
                borderRadius = T.ButtonRadius,
                paddingHorizontal = 10,
                height = 30,
                onClick = function()
                    local ok, msg = PC.AllocateFund(co, captureProj, captureSuggested)
                    if ok then
                        GD.AddEvent(captureProj.name .. " 拨付 " .. C.FormatMoney(captureSuggested) .. "(推荐)", "success")
                    else
                        GD.AddEvent(msg or "拨付失败", "danger")
                    end
                    navigate("capital")
                end,
            })
        end

        table.insert(cardItems, UI.Label {text = "拨付资金", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginTop = 4})
        table.insert(cardItems, UI.Panel {
            flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap",
            children = allocBtns,
        })

        table.insert(projectFundCards, C.Card {children = cardItems})
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- 现金概览
            UI.Panel {
                flexDirection = "row",
                gap = 10,
                width = "100%",
                flexWrap = "wrap",
                children = {
                    C.StatCard {title = "现金", value = C.FormatMoney(co.cash), color = co.cash < FN.CASH_SAFETY_LINE and T.Danger or T.Success},
                    C.StatCard {title = "月净流入", value = C.FormatMoney(cf.monthlyIn or 0), color = T.Info},
                    C.StatCard {title = "月净流出", value = C.FormatMoney(cf.monthlyOut or 0), color = T.Warning},
                }
            },

            -- 项目资金总览
            C.SectionTitle {text = "项目资金总览 (" .. #activeProjects .. "个在建)", color = T.Accent},
            #activeProjects > 0 and C.Card {
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                        children = {
                            C.StatCard {title = "总拨付", value = C.FormatMoney(totalAllocated), color = T.Info},
                            C.StatCard {title = "总支出", value = C.FormatMoney(totalSpent), color = T.Warning},
                            C.StatCard {title = "总余额", value = C.FormatMoney(totalRemaining), color = totalRemaining < 0 and T.Danger or T.Success},
                        },
                    },
                },
            } or nil,
            #activeProjects > 0
                and UI.Panel {width = "100%", gap = 8, children = projectFundCards}
                or UI.Label {text = "暂无在建项目", fontSize = T.FontSmall, fontColor = T.TextMuted},

            -- 现金流预测
            C.SectionTitle {text = "3个月滚动预测"},
            C.Card {
                children = #forecastItems > 0 and forecastItems or {
                    UI.Label {text = "暂无预测数据", fontSize = T.FontSmall, fontColor = T.TextMuted},
                }
            },
            (cf.belowSafety) and C.Card {
                children = {
                    UI.Label {text = "现金低于安全线(" .. C.FormatMoney(FN.CASH_SAFETY_LINE) .. ")，请尽快补充资金！", fontSize = T.FontSmall, fontColor = T.Danger},
                }
            } or nil,

            -- 活期存款
            C.SectionTitle {text = "活期存款", color = T.Success},
            demandCard,

            -- 定期存款产品
            C.SectionTitle {text = "定期存款产品", color = T.Info},
            UI.Panel {width = "100%", gap = 8, children = fixedDepositCards},

            -- 已有定期存款
            #existingDeposits > 0 and C.SectionTitle {text = "我的定期存款 (" .. #existingDeposits .. "笔)"} or nil,
            #existingDeposits > 0
                and UI.Panel {width = "100%", gap = 8, children = existingDeposits}
                or nil,

            -- 监管账户
            C.SectionTitle {text = "预售资金监管账户", color = T.Accent},
            #escrowCards > 0
                and UI.Panel {width = "100%", gap = 8, children = escrowCards}
                or UI.Label {text = "暂无监管账户(预售项目后自动生成)", fontSize = T.FontSmall, fontColor = T.TextMuted},

            -- 累计利息
            C.Card {
                children = {
                    C.InfoRow {label = "累计利息收入", value = C.FormatMoney(fin.totalInterest or 0), color = T.Success},
                }
            },
        }
    }
end

-- ============================================================================
-- Tab3: 三条红线 — 动态监控仪表盘 + 改善建议
-- ============================================================================
function M._TabRedLines(navigate, co)
    local fin = GD.finance or {}
    local rl = fin.redLine or {}
    local tierIdx = rl.tierIdx or 1
    local tierInfo = FN.RED_LINE_TIERS[tierIdx]
    local tierName = rl.tier or "绿档"
    local tierVariantMap = {["绿档"]="success", ["黄档"]="warning", ["橙档"]="warning", ["红档"]="danger"}
    local tierVariant = tierVariantMap[tierName] or "success"

    -- 三项指标
    local thresholds = FN.RED_LINE_THRESHOLDS
    local indicators = {
        {
            name = "剔除预收款后资产负债率",
            value = rl.assetLiability or 0,
            limit = thresholds.assetLiability,
            pass = (rl.assetLiability or 0) <= thresholds.assetLiability,
            desc = "≤" .. math.floor(thresholds.assetLiability * 100) .. "%",
            advice = "减少负债：提前还贷、减少新增贷款；增加资产：加快项目交付回款",
        },
        {
            name = "净负债率",
            value = rl.netDebt or 0,
            limit = thresholds.netDebt,
            pass = (rl.netDebt or 0) <= thresholds.netDebt,
            desc = "≤" .. math.floor(thresholds.netDebt * 100) .. "%",
            advice = "增加现金储备：加快销售回款、存款变现；降低有息负债：提前还贷",
        },
        {
            name = "现金短债比",
            value = rl.cashShortDebt or 999,
            limit = thresholds.cashShortDebt,
            pass = (rl.cashShortDebt or 999) >= thresholds.cashShortDebt,
            desc = "≥" .. string.format("%.0f", thresholds.cashShortDebt),
            advice = "增加现金：加速销售回款、申请长期贷款替换短期贷款",
        },
    }

    local indicatorCards = {}
    for _, ind in ipairs(indicators) do
        local displayVal
        if ind.name == "现金短债比" then
            displayVal = ind.value >= 99 and "N/A(无短债)" or string.format("%.2f", ind.value)
        else
            displayVal = string.format("%.1f%%", ind.value * 100)
        end

        -- 进度百分比（用于可视化）
        local progressPct = 0
        if ind.name == "现金短债比" then
            if ind.value < 99 then
                progressPct = math.min(100, ind.value / ind.limit * 100)
            else
                progressPct = 100
            end
        else
            progressPct = math.min(100, ind.value / ind.limit * 100)
        end

        local cardChildren = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = ind.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = ind.pass and "达标" or "超标", variant = ind.pass and "success" or "danger"},
                }
            },
            C.InfoRow {label = "当前值", value = displayVal, color = ind.pass and T.Success or T.Danger},
            C.InfoRow {label = "标准", value = ind.desc, color = T.TextMuted},
            -- 可视化进度条
            C.ProgressCard {
                title = "",
                progress = progressPct,
                barColor = ind.pass and T.Success or T.Danger,
                status = "",
            },
        }
        -- 超标时显示改善建议
        if not ind.pass then
            table.insert(cardChildren, UI.Panel {
                width = "100%",
                padding = 8,
                backgroundColor = T.DangerBg,
                borderRadius = 6,
                children = {
                    UI.Label {text = "改善建议: " .. ind.advice, fontSize = T.FontCaption, fontColor = T.Danger},
                }
            })
        end
        table.insert(indicatorCards, C.Card {children = cardChildren})
    end

    -- 档位说明表
    local tierDescCards = {}
    for _, tier in ipairs(FN.RED_LINE_TIERS) do
        local isCurrent = tier.name == tierName
        table.insert(tierDescCards, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            paddingVertical = 4,
            paddingHorizontal = 8,
            backgroundColor = isCurrent and T.PrimaryLight or {0,0,0,0},
            borderRadius = 4,
            children = {
                UI.Label {
                    text = (isCurrent and "> " or "  ") .. tier.name .. " (踩" .. tier.violations .. "线)",
                    fontSize = T.FontSmall,
                    fontColor = isCurrent and T.Primary or T.TextMuted,
                },
                UI.Label {
                    text = "债务增速≤" .. math.floor(tier.debtGrowthCap * 100) .. "%",
                    fontSize = T.FontSmall,
                    fontColor = isCurrent and T.Primary or T.TextMuted,
                },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- 档位总览
            C.Card {
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {text = "当前档位", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                            C.Badge {text = tierName, variant = tierVariant},
                        }
                    },
                    C.InfoRow {
                        label = "有息负债增速上限",
                        value = tierInfo and (math.floor(tierInfo.debtGrowthCap * 100) .. "%") or "15%",
                        color = tierName == "红档" and T.Danger or T.TextPrimary,
                    },
                    C.InfoRow {
                        label = "踩线数",
                        value = tostring(rl.violations or 0) .. " / 3",
                        color = (rl.violations or 0) > 0 and T.Warning or T.Success,
                    },
                }
            },

            -- 三项指标
            C.SectionTitle {text = "三条红线指标"},
            UI.Panel {width = "100%", gap = 8, children = indicatorCards},

            -- 档位对照表
            C.SectionTitle {text = "档位对照表"},
            C.Card {children = tierDescCards},

            -- 年初负债基准
            C.SectionTitle {text = "年度负债管控"},
            C.Card {
                children = {
                    C.InfoRow {label = "年初有息负债", value = C.FormatMoney(fin.yearStartDebt or co.totalDebt)},
                    C.InfoRow {label = "当前有息负债", value = C.FormatMoney(co.totalDebt), color = T.Warning},
                    C.InfoRow {
                        label = "年度增幅",
                        value = (function()
                            local base = fin.yearStartDebt or co.totalDebt
                            if base <= 0 then return "N/A" end
                            local growth = (co.totalDebt - base) / base * 100
                            return string.format("%+.1f%%", growth)
                        end)(),
                        color = T.TextSecondary,
                    },
                }
            },
        }
    }
end

-- ============================================================================
-- Tab4: 税务筹划 — 精确税务计算 + 风险等级 + 可激活方案
-- ============================================================================
function M._TabTax(navigate, co)
    local fin = GD.finance or {}
    local taxData = fin.tax or {}

    -- 税负总计
    local totalTaxPaid = (taxData.projectTaxPaid or 0) + (taxData.rentalTaxPaid or 0)

    -- 筹划方案
    local planCards = {}
    for _, plan in ipairs(FN.TAX_PLANS) do
        local planId = plan.id
        local isActive = false
        for _, ap in ipairs(taxData.activePlans or {}) do
            if ap == planId then isActive = true; break end
        end
        local capturePlanId = planId

        local cardItems = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {text = plan.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            C.Badge {text = "风险:" .. plan.risk, variant = plan.riskVariant or "info"},
                        }
                    },
                    C.Badge {
                        text = isActive and "已启用" or "未启用",
                        variant = isActive and "success" or "info",
                    },
                }
            },
            UI.Label {text = plan.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary},
            C.InfoRow {label = "节税比例", value = string.format("%.0f%%", plan.savingsRate * 100)},
            C.InfoRow {label = "实施成本", value = C.FormatMoney(plan.cost), color = T.Warning},
        }
        if isActive then
            table.insert(cardItems, UI.Label {
                text = "方案已在运行中",
                fontSize = T.FontCaption,
                fontColor = T.Success,
            })
        else
            table.insert(cardItems, C.ActionButton {
                text = "启用方案 (费用" .. C.FormatMoney(plan.cost) .. ")",
                onClick = function()
                    local ok, msg = FN.ApplyTaxPlan(GD, capturePlanId)
                    if not ok then
                        GD.AddEvent(msg or "启用失败", "danger")
                    end
                    navigate("capital")
                end,
            })
        end
        table.insert(planCards, C.Card {children = cardItems})
    end

    -- 已启用方案摘要
    local activePlanNames = {}
    for _, ap in ipairs(taxData.activePlans or {}) do
        for _, plan in ipairs(FN.TAX_PLANS) do
            if plan.id == ap then
                table.insert(activePlanNames, plan.name)
                break
            end
        end
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- 税务概览
            UI.Panel {
                flexDirection = "row",
                gap = 10,
                width = "100%",
                flexWrap = "wrap",
                children = {
                    C.StatCard {title = "累计纳税", value = C.FormatMoney(totalTaxPaid), color = T.Danger},
                    C.StatCard {title = "项目结算税", value = C.FormatMoney(taxData.projectTaxPaid or 0), color = T.Warning},
                    C.StatCard {title = "租金税", value = C.FormatMoney(taxData.rentalTaxPaid or 0), color = T.Warning},
                }
            },

            -- 税务明细
            C.SectionTitle {text = "税务明细"},
            C.Card {
                children = {
                    C.InfoRow {label = "项目结算税累计", value = C.FormatMoney(taxData.projectTaxPaid or 0), color = T.Warning},
                    UI.Label {text = "  项目清盘时缴纳：毛利润×20%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 6},
                    C.InfoRow {label = "租金税累计", value = C.FormatMoney(taxData.rentalTaxPaid or 0), color = T.Warning},
                    C.InfoRow {label = "当月租金税", value = C.FormatMoney(taxData.monthlyRentalTax or 0), color = T.TextMuted},
                    UI.Label {text = "  自持物业每月缴纳：租金收入×10%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }
            },

            -- 已启用方案
            #activePlanNames > 0 and C.Card {
                children = {
                    UI.Label {text = "已启用方案: " .. table.concat(activePlanNames, "、"), fontSize = T.FontSmall, fontColor = T.Success},
                }
            } or nil,

            -- 筹划方案
            C.SectionTitle {text = "税务筹划方案", color = T.Info},
            UI.Label {text = "启用筹划方案可降低项目结算税的有效税率", fontSize = T.FontSmall, fontColor = T.TextMuted},
            UI.Panel {width = "100%", gap = 8, children = planCards},
        }
    }
end

-- ============================================================================
-- Tab4: 财务报表 — 资产负债表 + 利润表 + 年度纳税记录
-- ============================================================================
function M._TabFinancialReport(navigate, co)
    local fin = GD.finance or {}
    local taxData = fin.tax or {}

    -- ── 资产负债表数据 ──
    -- 资产端
    local cashBalance = co.cash or 0
    local totalLandValue = 0
    for _, l in ipairs(GD.landReserve or {}) do
        totalLandValue = totalLandValue + (l.price or l.startPrice or 0)
    end
    local depositBalance = 0
    local escrowBalance = 0
    if fin.deposits then
        for _, d in ipairs(fin.deposits) do
            depositBalance = depositBalance + (d.amount or 0)
        end
    end
    if fin.escrowAccounts then
        for _, ea in pairs(fin.escrowAccounts) do
            escrowBalance = escrowBalance + ((ea.total or 0) - (ea.released or 0))
        end
    end
    local fixedAssetValue = 0
    for _, fa in ipairs(GD.fixedAssets or {}) do
        fixedAssetValue = fixedAssetValue + (fa.bookValue or 0)
    end
    local constructionInProgress = co.constructionInProgress or 0
    local totalAssets = co.totalAssets or 0

    -- 负债端
    local totalDebt = co.totalDebt or 0
    local shortTermDebt = 0  -- 1年内到期
    local longTermDebt = 0   -- 1年以上
    for _, loan in ipairs(GD.loans or {}) do
        if loan.remainMonths <= 12 then
            shortTermDebt = shortTermDebt + loan.amount
        else
            longTermDebt = longTermDebt + loan.amount
        end
    end
    -- 所有者权益 = 总资产 - 总负债
    local equity = totalAssets - totalDebt

    -- ── 利润表数据 ──
    local monthlyRevenue = co.monthlyRevenue or 0
    local monthlyExpense = co.monthlyExpense or 0
    local monthlyProfit = co.monthlyProfit or 0
    local annualProfit = co.annualProfit or 0
    -- 估算年化收入/支出（基于当月）
    local estAnnualRevenue = monthlyRevenue * 12
    local estAnnualExpense = monthlyExpense * 12

    -- 月度税负
    local monthlyTax = taxData.monthlyTaxTotal or 0

    -- 净利润率
    local profitMargin = monthlyRevenue > 0 and (monthlyProfit / monthlyRevenue * 100) or 0

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- ===== 财务概览指标 =====
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "总资产", value = C.FormatMoney(totalAssets), color = T.Primary},
                    C.StatCard {title = "总负债", value = C.FormatMoney(totalDebt), color = T.Warning},
                    C.StatCard {title = "净资产", value = C.FormatMoney(equity), color = equity >= 0 and T.Success or T.Danger},
                }
            },

            -- ===== 资产负债表 =====
            C.SectionTitle {text = "资产负债表"},
            C.Card {
                children = {
                    -- 资产
                    UI.Label {text = "资产", fontSize = T.FontBody, fontColor = T.Primary, fontWeight = "bold"},
                    C.InfoRow {label = "  货币资金", value = C.FormatMoney(cashBalance)},
                    depositBalance > 0 and C.InfoRow {label = "  定期存款", value = C.FormatMoney(depositBalance)} or nil,
                    escrowBalance > 0 and C.InfoRow {label = "  监管账户", value = C.FormatMoney(escrowBalance)} or nil,
                    totalLandValue > 0 and C.InfoRow {label = "  土地储备", value = C.FormatMoney(totalLandValue)} or nil,
                    constructionInProgress > 0 and C.InfoRow {label = "  在建工程", value = C.FormatMoney(constructionInProgress)} or nil,
                    fixedAssetValue > 0 and C.InfoRow {label = "  固定资产(净值)", value = C.FormatMoney(fixedAssetValue)} or nil,
                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                    C.InfoRow {label = "  资产合计", value = C.FormatMoney(totalAssets), color = T.Primary},

                    UI.Panel {width = "100%", height = 8},

                    -- 负债
                    UI.Label {text = "负债", fontSize = T.FontBody, fontColor = T.Warning, fontWeight = "bold"},
                    shortTermDebt > 0 and C.InfoRow {label = "  短期借款(≤1年)", value = C.FormatMoney(shortTermDebt)} or nil,
                    longTermDebt > 0 and C.InfoRow {label = "  长期借款(>1年)", value = C.FormatMoney(longTermDebt)} or nil,
                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                    C.InfoRow {label = "  负债合计", value = C.FormatMoney(totalDebt), color = T.Warning},

                    UI.Panel {width = "100%", height = 8},

                    -- 所有者权益
                    UI.Label {text = "所有者权益", fontSize = T.FontBody, fontColor = T.Success, fontWeight = "bold"},
                    C.InfoRow {label = "  净资产(资产-负债)", value = C.FormatMoney(equity), color = equity >= 0 and T.Success or T.Danger},
                }
            },

            -- ===== 利润表（当月） =====
            C.SectionTitle {text = "利润表（当月）"},
            C.Card {
                children = {
                    C.InfoRow {label = "营业收入", value = C.FormatMoney(monthlyRevenue), color = T.Success},
                    C.InfoRow {label = "营业支出", value = C.FormatMoney(monthlyExpense), color = T.Warning},
                    C.InfoRow {label = "  其中: 税金及附加", value = C.FormatMoney(monthlyTax), color = T.TextMuted},
                    UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                    C.InfoRow {label = "当月净利润", value = C.FormatMoney(monthlyProfit), color = monthlyProfit >= 0 and T.Success or T.Danger},
                    C.InfoRow {label = "净利润率", value = string.format("%.1f%%", profitMargin), color = profitMargin >= 0 and T.Success or T.Danger},

                    UI.Panel {width = "100%", height = 8},

                    UI.Label {text = "年度累计", fontSize = T.FontSmall, fontColor = T.TextMuted, fontWeight = "bold"},
                    C.InfoRow {label = "本年累计净利润", value = C.FormatMoney(annualProfit), color = annualProfit >= 0 and T.Success or T.Danger},
                    C.InfoRow {label = "预估年化收入", value = C.FormatMoney(estAnnualRevenue), color = T.TextSecondary},
                    C.InfoRow {label = "预估年化支出", value = C.FormatMoney(estAnnualExpense), color = T.TextSecondary},
                }
            },


        }
    }
end

return M
