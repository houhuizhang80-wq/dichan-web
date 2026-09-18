---@diagnostic disable: param-type-mismatch, assign-type-mismatch, unnecessary-if, need-check-nil, undefined-field

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

function M.Build(ctx)
    local cityName = ctx.cityName
    local navigate = ctx.navigate
    local FM = ctx.FM
    local state = ctx.state
    local shouldShowItem = ctx.shouldShowItem
    local appendFoldButton = ctx.appendFoldButton
            local creditData = GD.GetCityCredit(cityName)
            local bankRec   = GD.GetCityBank(cityName)
            local bankTab   = state._cityBankTab or 1
            local bankStep  = bankRec.step or 0
            if bankTab == 3 and bankStep < 6 then
                bankTab = 2
                state._cityBankTab = 2
            end
            -- 3个子标签：信用合作社 / 商业银行筹建 / 开业后银行运营
            local bankTabNames = {"信用合作社", "商业银行筹建", "银行运营"}
            local bankTabBtns = {}
            for i, name in ipairs(bankTabNames) do
                local ci = i
                -- 银行运营标签只在开业后显示
                if ci == 3 and bankStep < 6 then
                    -- 灰色提示
                    table.insert(bankTabBtns, UI.Button {
                        text = name .. "(未开业)", fontSize = T.FontSmall,
                        backgroundColor = T.DisabledBg, fontColor = T.TextMuted,
                        borderRadius = 4, paddingHorizontal = 10, height = 26,
                        onClick = function() end,
                    })
                else
                    table.insert(bankTabBtns, UI.Button {
                        text = name, fontSize = T.FontSmall,
                        backgroundColor = bankTab == ci and T.PrimaryLight or T.TabInactiveBg,
                        fontColor = bankTab == ci and T.Primary or T.TabInactiveFont,
                        borderRadius = 4, paddingHorizontal = 10, height = 26,
                        onClick = function()
                            state._cityBankTab = ci
                            navigate("city")
                        end,
                    })
                end
            end
            local bankTabBar = UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", children = bankTabBtns}

            local bankContent
            if bankTab == 1 then
                -- ===== 信用合作社 =====
                local coopItems = {}

                -- 总览统计
                local totalDep, totalLoan, totalWealth = 0, 0, 0
                local totalDepInterest, totalLoanInterest, totalWealthIncome = 0, 0, 0
                for _, d in ipairs(creditData.deposits)    do if d.active then totalDep    = totalDep    + d.amount end end
                for _, l in ipairs(creditData.loans)       do if l.active then totalLoan   = totalLoan   + l.amount end end
                for _, w in ipairs(creditData.wealthFunds) do if w.active then totalWealth = totalWealth + w.amount; totalWealthIncome = totalWealthIncome + (w.incomeEarned or 0) end end
                totalDepInterest  = creditData.totalInterestEarned or 0
                totalLoanInterest = creditData.totalLoanPaid or 0
                local creditLoanLimit, creditLoanRemain, creditNetAssets, creditLoanUsed = GD.GetCityCreditLoanLimit()

                table.insert(coopItems, UI.Panel {
                    width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = cityName .. "城市信用合作社", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "存款余额", value = FM(totalDep), color = T.Success},
                            C.StatCard {title = "贷款余额", value = FM(totalLoan), color = T.Warning},
                            C.StatCard {title = "理财余额", value = FM(totalWealth), color = T.Accent},
                        }},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "累计存息收入", value = FM(totalDepInterest), color = T.Success},
                            C.StatCard {title = "累计贷款利息", value = FM(totalLoanInterest), color = T.Danger},
                            C.StatCard {title = "净利息收入", value = FM(totalDepInterest - totalLoanInterest), color = totalDepInterest >= totalLoanInterest and T.Success or T.Danger},
                        }},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "累计理财收益", value = FM(totalWealthIncome), color = T.Primary},
                        }},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "贷款额度", value = FM(creditLoanLimit), color = T.Info},
                            C.StatCard {title = "已用额度", value = FM(creditLoanUsed), color = T.Warning},
                            C.StatCard {title = "剩余额度", value = FM(creditLoanRemain), color = creditLoanRemain > 0 and T.Success or T.Danger},
                        }},
                        UI.Label {text = "授信按个人净资产与声望计算：净资产" .. FM(creditNetAssets) .. "，个人信用社贷款累计不得超过剩余额度。", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    },
                })

                -- 存款明细（含取出按钮）
                if #creditData.deposits > 0 then
                    table.insert(coopItems, C.SectionTitle {text = "存款明细"})
                    local depRows = {}
                    local depCount = 0
                    local depKey = "creditDep_" .. cityName
                    for dIdx, d in ipairs(creditData.deposits) do
                        if d.active then
                            depCount = depCount + 1
                            if shouldShowItem(depCount, depKey) then
                            local capturedDepIdx = dIdx
                            local capturedDepCity = cityName
                            table.insert(depRows, UI.Panel {
                                width = "100%", paddingVertical = 6, gap = 4,
                                borderBottomWidth = 1, borderColor = T.Border,
                                children = {
                                    UI.Panel {
                                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                                        alignItems = "center",
                                        children = {
                                            UI.Label {text = d.name, fontSize = T.FontSmall, fontColor = T.TextPrimary, flexShrink = 1},
                                            UI.Panel {alignItems = "flex-end", gap = 1, children = {
                                                UI.Label {text = FM(d.amount) .. " · " .. d.annualRate .. "%", fontSize = T.FontSmall, fontColor = T.Success},
                                                UI.Label {text = "已收息 " .. FM(d.interestEarned), fontSize = 10, fontColor = T.TextMuted},
                                            }},
                                        },
                                    },
                                    UI.Button {
                                        text = "取出存款 (" .. FM(d.amount) .. ")",
                                        fontSize = 11,
                                        backgroundColor = T.Success,
                                        fontColor = T.TextOnDark,
                                        borderRadius = T.ButtonRadius,
                                        height = 30,
                                        width = "100%",
                                        onClick = function()
                                            GD.player.cash = GD.player.cash + d.amount
                                            local cd = GD.GetCityCredit(capturedDepCity)
                                            cd.deposits[capturedDepIdx].active = false
                                            cd.totalDeposit = math.max(0, (cd.totalDeposit or 0) - d.amount)
                                            GD.AddEvent("取出" .. d.name .. "，回收本金" .. FM(d.amount) .. "（已收利息不退）", "success")
                                            navigate("city")
                                        end,
                                    },
                                },
                            })
                        end -- shouldShowItem
                        end
                    end
                    appendFoldButton(depRows, depCount, depKey, navigate)
                    table.insert(coopItems, UI.Panel {width = "100%", padding = 8, gap = 2, backgroundColor = T.BgCard, borderRadius = T.CardRadius, children = depRows})
                end

                -- 贷款明细
                if #creditData.loans > 0 then
                    table.insert(coopItems, C.SectionTitle {text = "贷款明细"})
                    local loanRows = {}
                    local loanCount = 0
                    local loanKey = "creditLoan_" .. cityName
                    for lIdx, l in ipairs(creditData.loans) do
                        if l.active then
                            loanCount = loanCount + 1
                            if shouldShowItem(loanCount, loanKey) then
                            local capturedIdx = lIdx
                            local capturedCity = cityName
                            table.insert(loanRows, UI.Panel {
                                width = "100%", paddingVertical = 6, gap = 4,
                                borderBottomWidth = 1, borderColor = T.Border,
                                children = {
                                    UI.Panel {
                                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                                        alignItems = "center",
                                        children = {
                                            UI.Label {text = l.name, fontSize = T.FontSmall, fontColor = T.TextPrimary, flexShrink = 1},
                                            UI.Panel {alignItems = "flex-end", gap = 1, children = {
                                                UI.Label {text = FM(l.amount) .. " · " .. l.annualRate .. "%", fontSize = T.FontSmall, fontColor = T.Warning},
                                                UI.Label {text = "已付息 " .. FM(l.interestPaid), fontSize = 10, fontColor = T.TextMuted},
                                            }},
                                        },
                                    },
                                    UI.Button {
                                        text = "提前还款 (" .. FM(l.remaining or l.amount) .. ")",
                                        fontSize = 11,
                                        backgroundColor = T.Danger,
                                        fontColor = T.TextOnDark,
                                        borderRadius = T.ButtonRadius,
                                        height = 30,
                                        width = "100%",
                                        onClick = function()
                                            local repayAmount = l.remaining or l.amount or 0
                                            if GD.player.cash < repayAmount then
                                                GD.AddEvent("个人现金不足，无法还款（需" .. FM(repayAmount) .. "）", "danger")
                                            else
                                                GD.player.cash = GD.player.cash - repayAmount
                                                local cd = GD.GetCityCredit(capturedCity)
                                                local loanRef = cd.loans[capturedIdx]
                                                local principal = loanRef.remaining or loanRef.amount or 0
                                                loanRef.active = false
                                                loanRef.remaining = 0
                                                cd.totalLoan = math.max(0, (cd.totalLoan or 0) - principal)
                                                GD.AddEvent("成功偿还" .. l.name .. "，扣款" .. FM(repayAmount), "success")
                                            end
                                            navigate("city")
                                        end,
                                    },
                                },
                            })
                            end -- shouldShowItem
                        end
                    end
                    appendFoldButton(loanRows, loanCount, loanKey, navigate)
                    table.insert(coopItems, UI.Panel {width = "100%", padding = 8, gap = 2, backgroundColor = T.BgCard, borderRadius = T.CardRadius, children = loanRows})
                end

                -- 理财明细
                if #creditData.wealthFunds > 0 then
                    table.insert(coopItems, C.SectionTitle {text = "理财明细"})
                    local wealthRows = {}
                    local wealthCount = 0
                    local wealthKey = "creditWealth_" .. cityName
                    for _, w in ipairs(creditData.wealthFunds) do
                        if w.active then
                            wealthCount = wealthCount + 1
                            if shouldShowItem(wealthCount, wealthKey) then
                            table.insert(wealthRows, UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                alignItems = "center", paddingVertical = 3,
                                children = {
                                    UI.Label {text = w.name, fontSize = T.FontSmall, fontColor = T.TextPrimary, flexShrink = 1},
                                    UI.Panel {alignItems = "flex-end", gap = 1, children = {
                                        UI.Label {text = FM(w.amount) .. " · " .. w.annualRate .. "%", fontSize = T.FontSmall, fontColor = T.Accent},
                                        UI.Label {text = "已收益 " .. FM(w.incomeEarned or 0), fontSize = 10, fontColor = T.TextMuted},
                                    }},
                                },
                            })
                            end -- shouldShowItem
                        end
                    end
                    appendFoldButton(wealthRows, wealthCount, wealthKey, navigate)
                    table.insert(coopItems, UI.Panel {width = "100%", padding = 8, gap = 2, backgroundColor = T.BgCard, borderRadius = T.CardRadius, children = wealthRows})
                end

                -- 新增存款
                table.insert(coopItems, C.SectionTitle {text = "新增存款"})
                table.insert(coopItems, UI.Panel {
                    width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "存入资金享受稳定利息，月度自动入账", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "存入1000万 (3.2%)", bgColor = T.Info, onClick = function()
                                if GD.player.cash >= 1000 then
                                    GD.player.cash = GD.player.cash - 1000
                                    creditData.totalDeposit = (creditData.totalDeposit or 0) + 1000
                                    table.insert(creditData.deposits, {active=true, name=cityName.."信用社存款(1000万)", amount=1000, annualRate=3.2, interestEarned=0})
                                    GD.AddEvent("向"..cityName.."信用合作社存款1000万，年化3.2%，月度入息", "success")
                                    navigate("city")
                                end
                            end},
                            C.ActionButton {text = "存入5000万 (3.5%)", bgColor = T.Accent, onClick = function()
                                if GD.player.cash >= 5000 then
                                    GD.player.cash = GD.player.cash - 5000
                                    creditData.totalDeposit = (creditData.totalDeposit or 0) + 5000
                                    table.insert(creditData.deposits, {active=true, name=cityName.."信用社存款(5000万)", amount=5000, annualRate=3.5, interestEarned=0})
                                    GD.AddEvent("向"..cityName.."信用合作社存款5000万，年化3.5%，月度入息", "success")
                                    navigate("city")
                                end
                            end},
                        }},
                        -- ★ 自定义金额输入
                        UI.Panel {
                            flexDirection = "row",
                            flexWrap = "wrap",
                            gap = 6,
                            alignItems = "center",
                            width = "100%",
                            children = {
                                UI.TextField {
                                    value = state._creditDepositInput,
                                    placeholder = "输入存款金额(万)...",
                                    fontSize = T.FontSmall,
                                    flexGrow = 1,
                                    flexBasis = 140,
                                    minWidth = 0,
                                    height = 32,
                                    onChange = function(self, v) state._creditDepositInput = v end,
                                },
                                C.ActionButton {text = "自定义存入 (3.5%)", bgColor = T.Primary, onClick = function()
                                    local amt = math.floor(tonumber(state._creditDepositInput) or 0)
                                    if amt <= 0 then GD.AddEvent("请输入有效金额", "warning"); navigate("city"); return end
                                    if GD.player.cash < amt then GD.AddEvent("个人现金不足", "warning"); navigate("city"); return end
                                    GD.player.cash = GD.player.cash - amt
                                    creditData.totalDeposit = (creditData.totalDeposit or 0) + amt
                                    table.insert(creditData.deposits, {active=true, name=cityName.."信用社存款("..GD.FormatMoney(amt)..")", amount=amt, annualRate=3.5, interestEarned=0})
                                    GD.AddEvent("向"..cityName.."信用合作社存款"..GD.FormatMoney(amt).."，年化3.5%", "success")
                                    state._creditDepositInput = ""
                                    navigate("city")
                                end},
                            },
                        },
                    },
                })

                -- 贷款业务
                table.insert(coopItems, C.SectionTitle {text = "申请贷款"})
                table.insert(coopItems, UI.Panel {
                    width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "向信用合作社申请个人低息贷款，按月从个人账户付息，额度按个人净资产与声望计算", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "贷款500万 (7.5%)", bgColor = creditLoanRemain >= 500 and T.Warning or T.DisabledBg, onClick = function()
                                local ok, msg = GD.ApplyCityCreditLoan(cityName, 500, 7.5)
                                if not ok then GD.AddEvent(msg or "贷款失败", "warning") end
                                navigate("city")
                            end},
                            C.ActionButton {text = "贷款2000万 (7.8%)", bgColor = creditLoanRemain >= 2000 and T.Danger or T.DisabledBg, onClick = function()
                                local ok, msg = GD.ApplyCityCreditLoan(cityName, 2000, 7.8)
                                if not ok then GD.AddEvent(msg or "贷款失败", "warning") end
                                navigate("city")
                            end},
                        }},
                        -- ★ 自定义贷款金额
                        UI.Panel {
                            flexDirection = "row",
                            flexWrap = "wrap",
                            gap = 6,
                            alignItems = "center",
                            width = "100%",
                            children = {
                                UI.TextField {
                                    value = state._creditLoanInput,
                                    placeholder = "输入贷款金额(万)...",
                                    fontSize = T.FontSmall,
                                    flexGrow = 1,
                                    flexBasis = 140,
                                    minWidth = 0,
                                    height = 32,
                                    onChange = function(self, v) state._creditLoanInput = v end,
                                },
                                C.ActionButton {text = "自定义贷款 (7.5%)", bgColor = T.Warning, onClick = function()
                                    local amt = math.floor(tonumber(state._creditLoanInput) or 0)
                                    local ok, msg = GD.ApplyCityCreditLoan(cityName, amt, 7.5)
                                    if ok then
                                        state._creditLoanInput = ""
                                    else
                                        GD.AddEvent(msg or "贷款失败", "warning")
                                    end
                                    navigate("city")
                                end},
                            },
                        },
                    },
                })

                -- 理财产品
                table.insert(coopItems, C.SectionTitle {text = "理财产品"})
                table.insert(coopItems, UI.Panel {
                    width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "购买货币基金及短期理财，灵活存取，月度收益到账", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "货币基金1000万 (4.2%)", bgColor = T.Success, onClick = function()
                                if GD.player.cash >= 1000 then
                                    GD.player.cash = GD.player.cash - 1000
                                    creditData.totalWealth = (creditData.totalWealth or 0) + 1000
                                    table.insert(creditData.wealthFunds, {active=true, name="货币基金(1000万)", amount=1000, annualRate=4.2, incomeEarned=0})
                                    GD.AddEvent("购买货币基金1000万，年化4.2%，月度收益入账", "success")
                                    navigate("city")
                                end
                            end},
                            C.ActionButton {text = "短期理财5000万 (4.8%)", bgColor = T.Accent, onClick = function()
                                if GD.player.cash >= 5000 then
                                    GD.player.cash = GD.player.cash - 5000
                                    creditData.totalWealth = (creditData.totalWealth or 0) + 5000
                                    table.insert(creditData.wealthFunds, {active=true, name="短期理财(5000万)", amount=5000, annualRate=4.8, incomeEarned=0})
                                    GD.AddEvent("购买短期理财5000万，年化4.8%，月度收益入账", "success")
                                    navigate("city")
                                end
                            end},
                        }},
                    },
                })
                bankContent = UI.Panel {width = "100%", gap = 10, children = coopItems}

            elseif bankTab == 2 then
                -- ===== 商业银行筹建 =====
                local bankItems = {}
                local currentStep = bankRec.step or 0

                table.insert(bankItems, UI.Panel {
                    width = "100%", padding = 12, gap = 8, backgroundColor = T.PrimaryDark, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = cityName .. "商业银行筹建中心", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        UI.Label {text = "发起成立本地商业银行，从筹备到正式开业构建完整金融服务体系", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "当前阶段", value = currentStep >= 6 and "已开业" or ("第"..currentStep.."步/共6步"), color = currentStep >= 6 and T.Success or T.Accent},
                            C.StatCard {title = "累计投入", value = FM(bankRec.totalInvested), color = T.Warning},
                            C.StatCard {title = "状态", value = currentStep >= 6 and "正式运营" or "筹建中", color = currentStep >= 6 and T.Success or T.Info},
                        }},
                    },
                })

                local bankSteps = {
                    {title = "第一步：发起筹建", desc = "提交银行筹建申请，组建发起人团队（至少5家法人机构）", cost = 500, action = "提交筹建申请"},
                    {title = "第二步：募集资本金", desc = "公开募集注册资本，最低注册资本10亿元（10000万）", cost = 10000, action = "开始资本募集"},
                    {title = "第三步：监管审批", desc = "向金融监管局提交开业申请，审批周期约12~18个月，提前布局", cost = 200, action = "提交开业申请"},
                    {title = "第四步：总部及网点建设", desc = "建设银行总部大楼及各区域支行网点（10~20个网点）", cost = 5000, action = "启动建设"},
                    {title = "第五步：人员招募", desc = "招募行长、风控总监、信贷官、财务总监等核心管理团队", cost = 800, action = "发布招聘"},
                    {title = "第六步：正式开业", desc = "完成所有筹备工作，正式宣布开业，启动核心存贷款业务", cost = 1000, action = "宣布开业"},
                }
                for stepIdx, step in ipairs(bankSteps) do
                    local capturedStep = step
                    local capturedIdx  = stepIdx
                    local isDone   = currentStep >= capturedIdx
                    local isCurrent = currentStep == capturedIdx - 1
                    local bgColor  = isDone and T.SuccessBg or (isCurrent and T.BgCard or T.BgBase)
                    local titleColor = isDone and T.Success or (isCurrent and T.Accent or T.TextMuted)
                    table.insert(bankItems, UI.Panel {
                        width = "100%", padding = 10, gap = 6, backgroundColor = bgColor, borderRadius = T.CardRadius,
                        borderWidth = isCurrent and 1 or 0, borderColor = T.Accent,
                        children = {
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = (isDone and "✓ " or "") .. capturedStep.title, fontSize = T.FontBody, fontColor = titleColor},
                                isDone and C.Badge {text = "已完成", variant = "success"} or C.Badge {text = FM(capturedStep.cost), variant = isCurrent and "warning" or "default"},
                            }},
                            UI.Label {text = capturedStep.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                            isCurrent and C.ActionButton {
                                text = capturedStep.action,
                                bgColor = T.Primary,
                                onClick = function()
                                    if GD.player.cash >= capturedStep.cost then
                                        GD.player.cash = GD.player.cash - capturedStep.cost
                                        bankRec.step = capturedIdx
                                        bankRec.totalInvested = (bankRec.totalInvested or 0) + capturedStep.cost
                                        if capturedIdx == 6 then
                                            -- 开业时将全部注册资本注入银行账户作为初始资金
                                            bankRec.bankCash = (bankRec.bankCash or 0) + (bankRec.totalInvested or 0)
                                            -- 给予初始存贷款种子，确保首月即产生利润
                                            local initDeposit = math.floor((bankRec.depositCap or 50000) * 0.05)  -- 初始5%存款
                                            local initLoan = math.floor(initDeposit * 0.65)  -- 贷存比65%
                                            bankRec.currentDeposits = (bankRec.currentDeposits or 0) + initDeposit
                                            bankRec.currentLoans = (bankRec.currentLoans or 0) + initLoan
                                            bankRec.bankCash = bankRec.bankCash + initDeposit - initLoan  -- 存款流入，贷款流出
                                            bankRec._capitalSeeded = true
                                            GD.AddEvent(cityName.."商业银行正式开业！金融版图再扩一城", "success")
                                            state._cityBankTab = 3
                                        else
                                            GD.AddEvent(cityName.."银行筹建："..capturedStep.title.."完成，投入"..FM(capturedStep.cost), "info")
                                        end
                                        navigate("city")
                                    else
                                        GD.AddEvent("个人现金不足，无法完成" .. capturedStep.title, "warning")
                                        navigate("city")
                                    end
                                end,
                            } or UI.Panel {height = 0, width = 0},
                        },
                    })
                end
                bankContent = UI.Panel {width = "100%", gap = 8, children = bankItems}

            else
                -- ===== 银行开业后运营 =====
                local opsItems = {}
                bankRec.currentDeposits  = bankRec.currentDeposits  or 0
                bankRec.currentLoans     = bankRec.currentLoans     or 0
                bankRec.totalWealthAUM   = bankRec.totalWealthAUM   or 0
                bankRec.depositCap       = bankRec.depositCap       or 50000
                bankRec.loanCap          = bankRec.loanCap          or 40000
                bankRec.deposit1yRate    = bankRec.deposit1yRate    or 2.0
                bankRec.depositDemandRate= bankRec.depositDemandRate or 1.2
                bankRec.deposit3yRate    = bankRec.deposit3yRate    or 2.8
                bankRec.loanEnterpriseRate= bankRec.loanEnterpriseRate or 4.9
                bankRec.loanPersonalRate = bankRec.loanPersonalRate or 5.8
                bankRec.wealthProducts   = bankRec.wealthProducts   or {}
                bankRec.shareholders     = bankRec.shareholders     or {}
                bankRec.totalShares      = bankRec.totalShares      or 10000
                bankRec.myShares         = bankRec.myShares         or 10000
                bankRec.totalWealthFee   = bankRec.totalWealthFee   or 0
                bankRec.totalLoanInterest= bankRec.totalLoanInterest or 0
                bankRec.totalDepositInterest = bankRec.totalDepositInterest or 0
                bankRec.monthlyDividend  = bankRec.monthlyDividend or 0
                bankRec.monthlyNetProfit = bankRec.monthlyNetProfit or bankRec.monthlyProfit or 0
                bankRec.retainedEarnings = bankRec.retainedEarnings or bankRec.totalProfit or 0
                bankRec.totalProfit      = bankRec.retainedEarnings
                -- 银行独立账户：老存档兼容，以已投入总额作为初始余额
                bankRec.bankCash = bankRec.bankCash or (bankRec.totalInvested or 0)

                -- ── 辅助：我方持股%
                local myPct = math.floor(bankRec.myShares / math.max(1, bankRec.totalShares) * 100)
                -- ── 辅助：贷存比
                local ldrPct = bankRec.currentDeposits > 0
                    and math.floor(bankRec.currentLoans / bankRec.currentDeposits * 100) or 0
                -- ── 辅助：净息差
                local nim = bankRec.currentDeposits > 0
                    and string.format("%.2f", bankRec.loanEnterpriseRate - bankRec.deposit1yRate) or "--"

                -- 银行总资产按真实资产端计算：现金准备金 + 贷款资产
                local bankTotalAssets = math.max(0, (bankRec.bankCash or 0) + (bankRec.currentLoans or 0))
                -- 最低准备金按吸收存款的10%计提
                local minReserve = math.floor(math.max(0, bankRec.currentDeposits or 0) * 0.10)
                -- ── 辅助：可用于放贷的余额（bankCash - 准备金）
                local lendableBalance = math.max(0, bankRec.bankCash - minReserve)
                -- ── 辅助：存贷差（存款 - 贷款，正数=资金富余，负数=贷款超出存款，靠自有资本支撑）
                local depLoanDiff = bankRec.currentDeposits - bankRec.currentLoans
                -- ── 辅助：账户是否触达准备金下限
                local atReserveLimit = bankRec.bankCash <= minReserve + 100
                local function expandBankCapacity(kind, amount, cost, label)
                    local paidByPersonal = 0
                    if bankRec.bankCash < cost then
                        paidByPersonal = cost - bankRec.bankCash
                        if GD.player.cash < paidByPersonal then
                            GD.AddEvent(cityName .. "商业银行扩容" .. label .. "资金不足，银行账户+个人现金仍缺" .. FM(paidByPersonal - GD.player.cash), "warning")
                            navigate("city")
                            return
                        end
                        GD.player.cash = GD.player.cash - paidByPersonal
                        bankRec.bankCash = bankRec.bankCash + paidByPersonal
                        bankRec.capacityExpansionPaidByPersonal = (bankRec.capacityExpansionPaidByPersonal or 0) + paidByPersonal
                    end
                    bankRec.bankCash = bankRec.bankCash - cost
                    if kind == "deposit" then
                        bankRec.depositCap = (bankRec.depositCap or 0) + amount
                        GD.AddEvent(cityName .. "商业银行存款上限扩容+" .. label .. "，成本" .. FM(cost) .. (paidByPersonal > 0 and "（个人补足" .. FM(paidByPersonal) .. "）" or ""), "success")
                    else
                        bankRec.loanCap = (bankRec.loanCap or 0) + amount
                        GD.AddEvent(cityName .. "商业银行贷款上限扩容+" .. label .. "，成本" .. FM(cost) .. (paidByPersonal > 0 and "（个人补足" .. FM(paidByPersonal) .. "）" or ""), "success")
                    end
                    navigate("city")
                end

                -- ── 运营概览 ──
                table.insert(opsItems, UI.Panel {
                    width = "100%", padding = 12, gap = 8, backgroundColor = T.PrimaryDark, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = cityName .. "商业银行 · 运营中心", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        -- 银行账户余额
                        UI.Panel {
                            width = "100%", flexDirection = "row", justifyContent = "space-between",
                            alignItems = "center", padding = 8,
                            backgroundColor = T.BgBase, borderRadius = 6,
                            children = {
                                UI.Panel {gap = 2, children = {
                                    UI.Label {text = "银行账户余额", fontSize = T.FontBody, fontColor = T.TextSecondary},
                                    UI.Label {
                                        text = "最低准备金：" .. FM(minReserve) .. "  可放贷：" .. FM(lendableBalance),
                                        fontSize = 10,
                                        fontColor = atReserveLimit and T.Danger or T.TextMuted,
                                    },
                                }},
                                UI.Label {text = FM(bankRec.bankCash), fontSize = T.FontTitle, fontColor = atReserveLimit and T.Danger or T.Success},
                            },
                        },
                        atReserveLimit and UI.Label {
                            text = "⚠ 账户余额已触及准备金下限，贷款暂停新增",
                            fontSize = T.FontSmall, fontColor = T.Danger,
                        } or UI.Label {text = "", fontSize = 1},
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "银行总资产", value = FM(bankTotalAssets), color = T.Primary},
                            C.StatCard {title = "吸收存款", value = FM(bankRec.currentDeposits), color = T.Info},
                            C.StatCard {title = "放贷规模", value = FM(bankRec.currentLoans), color = T.Warning},
                        }},
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "存贷差", value = FM(depLoanDiff), color = depLoanDiff >= 0 and T.Info or T.Warning},
                            C.StatCard {title = "上月净利润", value = FM(bankRec.monthlyNetProfit or bankRec.monthlyProfit), color = (bankRec.monthlyNetProfit or bankRec.monthlyProfit or 0) >= 0 and T.Success or T.Danger},
                            C.StatCard {title = "净息差", value = nim .. "%", color = T.Primary},
                        }},
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "贷存比", value = ldrPct .. "%", color = ldrPct > 80 and T.Danger or T.Info},
                            C.StatCard {title = "我方持股", value = myPct .. "%", color = T.Accent},
                            C.StatCard {title = "理财AUM", value = FM(bankRec.totalWealthAUM), color = T.Accent},
                        }},
                    },
                })

                -- ================================================================
                -- 一、吸收存款（市场驱动，银行设利率和上限）
                -- ================================================================
                table.insert(opsItems, C.SectionTitle {text = "一、吸收存款"})
                local depUtil = bankRec.depositCap > 0 and math.floor(bankRec.currentDeposits / bankRec.depositCap * 100) or 0
                table.insert(opsItems, UI.Panel {
                    width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        -- 说明
                        UI.Label {text = "客户根据银行利率自行存款，利率越高吸纳越快，受存款上限约束", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        -- 存款状况
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "当前存款", value = FM(bankRec.currentDeposits), color = T.Info},
                            C.StatCard {title = "存款上限", value = FM(bankRec.depositCap), color = T.TextMuted},
                            C.StatCard {title = "利用率", value = depUtil .. "%", color = depUtil > 90 and T.Warning or T.Success},
                        }},
                        -- 利率设置
                        UI.Label {text = "▸ 存款利率设置（市场基准：活期0.5% / 1年2.0% / 3年2.8%）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {gap = 6, width = "100%", children = {
                            -- 活期
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = "活期利率：" .. string.format("%.1f", bankRec.depositDemandRate) .. "%", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    C.ActionButton {text = "-0.1%", bgColor = T.DangerBg, onClick = function()
                                        bankRec.depositDemandRate = math.max(0.1, (bankRec.depositDemandRate or 1.2) - 0.1)
                                        bankRec.depositDemandRate = math.floor(bankRec.depositDemandRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                    C.ActionButton {text = "+0.1%", bgColor = T.SuccessBg, onClick = function()
                                        bankRec.depositDemandRate = math.min(3.0, (bankRec.depositDemandRate or 1.2) + 0.1)
                                        bankRec.depositDemandRate = math.floor(bankRec.depositDemandRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                }},
                            }},
                            -- 1年定期
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = "1年定期：" .. string.format("%.1f", bankRec.deposit1yRate) .. "%", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    C.ActionButton {text = "-0.1%", bgColor = T.DangerBg, onClick = function()
                                        bankRec.deposit1yRate = math.max(0.5, (bankRec.deposit1yRate or 2.0) - 0.1)
                                        bankRec.deposit1yRate = math.floor(bankRec.deposit1yRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                    C.ActionButton {text = "+0.1%", bgColor = T.SuccessBg, onClick = function()
                                        bankRec.deposit1yRate = math.min(4.5, (bankRec.deposit1yRate or 2.0) + 0.1)
                                        bankRec.deposit1yRate = math.floor(bankRec.deposit1yRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                }},
                            }},
                            -- 3年定期
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = "3年定期：" .. string.format("%.1f", bankRec.deposit3yRate) .. "%", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    C.ActionButton {text = "-0.1%", bgColor = T.DangerBg, onClick = function()
                                        bankRec.deposit3yRate = math.max(1.0, (bankRec.deposit3yRate or 2.8) - 0.1)
                                        bankRec.deposit3yRate = math.floor(bankRec.deposit3yRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                    C.ActionButton {text = "+0.1%", bgColor = T.SuccessBg, onClick = function()
                                        bankRec.deposit3yRate = math.min(5.5, (bankRec.deposit3yRate or 2.8) + 0.1)
                                        bankRec.deposit3yRate = math.floor(bankRec.deposit3yRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                }},
                            }},
                        }},
                        -- 存款上限扩容
                        UI.Label {text = "▸ 存款上限扩容（扩大分支机构网络）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "扩容+5亿(" .. FM(5000) .. ")", bgColor = T.Info, onClick = function()
                                expandBankCapacity("deposit", 50000, 5000, "5亿")
                            end},
                            C.ActionButton {text = "扩容+20亿(" .. FM(15000) .. ")", bgColor = T.Primary, onClick = function()
                                expandBankCapacity("deposit", 200000, 15000, "20亿")
                            end},
                            C.ActionButton {text = "扩容+50亿(" .. FM(35000) .. ")", bgColor = T.Accent, onClick = function()
                                expandBankCapacity("deposit", 500000, 35000, "50亿")
                            end},
                            C.ActionButton {text = "扩容+100亿(" .. FM(60000) .. ")", bgColor = T.Warning, onClick = function()
                                expandBankCapacity("deposit", 1000000, 60000, "100亿")
                            end},
                            C.ActionButton {text = "扩容+1000亿(" .. FM(500000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("deposit", 10000000, 500000, "1000亿")
                            end},
                            C.ActionButton {text = "扩容+10000亿(" .. FM(5000000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("deposit", 100000000, 5000000, "10000亿")
                            end},
                            C.ActionButton {text = "扩容+50000亿(" .. FM(25000000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("deposit", 500000000, 25000000, "50000亿")
                            end},
                        }},
                    },
                })

                -- ================================================================
                -- 二、发放贷款（市场驱动，银行设利率和上限）
                -- ================================================================
                table.insert(opsItems, C.SectionTitle {text = "二、发放贷款"})
                local loanUtil = bankRec.loanCap > 0 and math.floor(bankRec.currentLoans / bankRec.loanCap * 100) or 0
                table.insert(opsItems, UI.Panel {
                    width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "客户根据利率自行申请贷款，利率越低需求越大；贷款受贷存比(≤75%)和贷款上限双重约束", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "当前贷款", value = FM(bankRec.currentLoans), color = T.Warning},
                            C.StatCard {title = "贷款上限", value = FM(bankRec.loanCap), color = T.TextMuted},
                            C.StatCard {title = "利用率", value = loanUtil .. "%", color = loanUtil > 85 and T.Danger or T.Success},
                        }},
                        -- 贷款利率设置
                        UI.Label {text = "▸ 贷款利率设置（市场基准：企业4.8% / 个人5.5%）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {gap = 6, width = "100%", children = {
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = "企业贷款：" .. string.format("%.1f", bankRec.loanEnterpriseRate) .. "%", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    C.ActionButton {text = "-0.1%", bgColor = T.DangerBg, onClick = function()
                                        bankRec.loanEnterpriseRate = math.max(2.0, (bankRec.loanEnterpriseRate or 4.9) - 0.1)
                                        bankRec.loanEnterpriseRate = math.floor(bankRec.loanEnterpriseRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                    C.ActionButton {text = "+0.1%", bgColor = T.SuccessBg, onClick = function()
                                        bankRec.loanEnterpriseRate = math.min(9.0, (bankRec.loanEnterpriseRate or 4.9) + 0.1)
                                        bankRec.loanEnterpriseRate = math.floor(bankRec.loanEnterpriseRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                }},
                            }},
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Label {text = "个人贷款：" .. string.format("%.1f", bankRec.loanPersonalRate) .. "%", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    C.ActionButton {text = "-0.1%", bgColor = T.DangerBg, onClick = function()
                                        bankRec.loanPersonalRate = math.max(2.5, (bankRec.loanPersonalRate or 5.8) - 0.1)
                                        bankRec.loanPersonalRate = math.floor(bankRec.loanPersonalRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                    C.ActionButton {text = "+0.1%", bgColor = T.SuccessBg, onClick = function()
                                        bankRec.loanPersonalRate = math.min(12.0, (bankRec.loanPersonalRate or 5.8) + 0.1)
                                        bankRec.loanPersonalRate = math.floor(bankRec.loanPersonalRate * 10 + 0.5) / 10
                                        navigate("city")
                                    end},
                                }},
                            }},
                        }},
                        -- 贷款上限扩容
                        UI.Label {text = "▸ 贷款上限扩容（增加风控额度）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "提升额度+5亿(" .. FM(5000) .. ")", bgColor = T.Info, onClick = function()
                                expandBankCapacity("loan", 50000, 5000, "5亿")
                            end},
                            C.ActionButton {text = "提升额度+20亿(" .. FM(15000) .. ")", bgColor = T.Primary, onClick = function()
                                expandBankCapacity("loan", 200000, 15000, "20亿")
                            end},
                            C.ActionButton {text = "提升额度+50亿(" .. FM(35000) .. ")", bgColor = T.Accent, onClick = function()
                                expandBankCapacity("loan", 500000, 35000, "50亿")
                            end},
                            C.ActionButton {text = "提升额度+100亿(" .. FM(60000) .. ")", bgColor = T.Warning, onClick = function()
                                expandBankCapacity("loan", 1000000, 60000, "100亿")
                            end},
                            C.ActionButton {text = "提升额度+1000亿(" .. FM(500000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("loan", 10000000, 500000, "1000亿")
                            end},
                            C.ActionButton {text = "提升额度+10000亿(" .. FM(5000000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("loan", 100000000, 5000000, "10000亿")
                            end},
                            C.ActionButton {text = "提升额度+50000亿(" .. FM(25000000) .. ")", bgColor = T.Danger, onClick = function()
                                expandBankCapacity("loan", 500000000, 25000000, "50000亿")
                            end},
                        }},
                    },
                })

                -- ================================================================
                -- 三、财富管理（银行发行产品，客户自行认购）
                -- ================================================================
                table.insert(opsItems, C.SectionTitle {text = "三、财富管理"})
                -- 已发行产品列表
                local activeWP = 0
                for _, wp in ipairs(bankRec.wealthProducts) do if wp.active then activeWP = activeWP + 1 end end
                table.insert(opsItems, UI.Panel {
                    width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Label {text = "银行发行理财产品，客户根据收益率自主认购，银行收取管理费", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                            C.StatCard {title = "在售产品", value = activeWP .. "款", color = T.Accent},
                            C.StatCard {title = "认购规模", value = FM(bankRec.totalWealthAUM), color = T.Success},
                            C.StatCard {title = "累计管理费", value = FM(bankRec.totalWealthFee), color = T.Primary},
                        }},
                        -- 已发行产品明细
                        (function()
                            if activeWP == 0 then
                                return UI.Label {text = "尚未发行任何理财产品", fontSize = T.FontSmall, fontColor = T.TextMuted}
                            end
                            local wpRows = {}
                            local visibleCount = 0
                            local wpKey = "bankWP_" .. cityName
                            for _, wp in ipairs(bankRec.wealthProducts) do
                                if wp.active then
                                    visibleCount = visibleCount + 1
                                    if shouldShowItem(visibleCount, wpKey) then
                                        local aumPct = wp.targetSize > 0 and math.floor((wp.currentAUM or 0) / wp.targetSize * 100) or 0
                                        table.insert(wpRows, UI.Panel {
                                            width = "100%", flexDirection = "row", justifyContent = "space-between",
                                            alignItems = "center", paddingVertical = 4,
                                            borderBottomWidth = 1, borderColor = T.BgBase,
                                            children = {
                                                UI.Panel {gap = 1, flexShrink = 1, children = {
                                                    UI.Label {text = wp.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                                    UI.Label {text = "收益率" .. wp.yield .. "% · 规模" .. FM(wp.targetSize) .. " · 认购" .. aumPct .. "%", fontSize = 10, fontColor = T.TextMuted},
                                                }},
                                                UI.Panel {alignItems = "flex-end", gap = 1, children = {
                                                    UI.Label {text = FM(wp.currentAUM or 0), fontSize = T.FontSmall, fontColor = T.Success},
                                                    UI.Label {text = "管理费收入 " .. FM(wp.totalFee or 0), fontSize = 10, fontColor = T.TextMuted},
                                                }},
                                            },
                                        })
                                    end
                                end
                            end
                            appendFoldButton(wpRows, visibleCount, wpKey, navigate)
                            return UI.Panel {width = "100%", gap = 2, children = wpRows}
                        end)(),
                        -- 发行新产品
                        UI.Label {text = "▸ 发行新理财产品", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        (function()
                            -- 理财总规模上限 = 银行总资产 × 50%
                            local wealthCap = math.floor(bankTotalAssets * 0.5)
                            local currentTotalTarget = 0
                            for _, wp in ipairs(bankRec.wealthProducts) do
                                if wp.active then currentTotalTarget = currentTotalTarget + (wp.targetSize or 0) end
                            end
                            local capRemain = math.max(0, wealthCap - currentTotalTarget)
                            local capInfo = UI.Label {
                                text = "理财规模上限：总资产50% = " .. FM(wealthCap) .. "  |  已用 " .. FM(currentTotalTarget) .. "  |  剩余 " .. FM(capRemain),
                                fontSize = 10, fontColor = capRemain < 10000 and T.Warning or T.TextMuted,
                            }
                            local function canIssue(size)
                                return currentTotalTarget + size <= wealthCap
                            end
                            local function issueProduct(name, yield, feeRate, size)
                                local wp = {active=true, name=name, yield=yield, feeRate=feeRate, targetSize=size, currentAUM=0, totalFee=0}
                                table.insert(bankRec.wealthProducts, wp)
                                currentTotalTarget = currentTotalTarget + size
                            end
                            local function batchIssue(targetAmount, label)
                                local remain = math.min(targetAmount, math.max(0, wealthCap - currentTotalTarget))
                                if remain <= 0 then
                                    GD.AddEvent(cityName .. "商业银行理财额度已满，无法批量发行", "warning")
                                    navigate("city")
                                    return
                                end
                                local created = 0
                                local templates = {
                                    {"短期理财90天", 3.8, 0.3, 40000},
                                    {"中期理财365天", 4.5, 0.5, 80000},
                                    {"私人银行专属产品", 5.8, 1.0, 100000},
                                    {"权益型基金产品", 7.2, 1.5, 120000},
                                }
                                local loopGuard = 0
                                while remain > 0 and loopGuard < 200 do
                                    loopGuard = loopGuard + 1
                                    local tpl = templates[(created % #templates) + 1]
                                    local size = math.min(tpl[4], remain)
                                    if size < 10000 and created > 0 then break end
                                    issueProduct(tpl[1] .. "#" .. tostring(activeWP + created + 1), tpl[2], tpl[3], size)
                                    remain = remain - size
                                    created = created + 1
                                end
                                if created > 0 then
                                    GD.AddEvent(cityName .. "商业银行批量发行" .. created .. "款理财产品（" .. label .. "）", "success")
                                end
                                navigate("city")
                            end
                            return UI.Panel {gap = 6, width = "100%", children = {
                                capInfo,
                                UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                                    C.ActionButton {text = "批量发行10亿", bgColor = capRemain > 0 and T.Primary or T.DisabledBg, onClick = function()
                                        batchIssue(100000, "10亿")
                                    end},
                                    C.ActionButton {text = "批量发行50亿", bgColor = capRemain > 0 and T.Accent or T.DisabledBg, onClick = function()
                                        batchIssue(500000, "50亿")
                                    end},
                                    C.ActionButton {text = "一键填满额度", bgColor = capRemain > 0 and T.Warning or T.DisabledBg, onClick = function()
                                        batchIssue(capRemain, "填满剩余额度")
                                    end},
                                }},
                                UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                                    C.ActionButton {
                                        text = "短期理财90天(3.8%)",
                                        bgColor = canIssue(20000) and T.Info or T.DisabledBg,
                                        onClick = function()
                                            if canIssue(20000) then
                                                local wp = {active=true, name="短期理财90天", yield=3.8, feeRate=0.3, targetSize=20000, currentAUM=0, totalFee=0}
                                                table.insert(bankRec.wealthProducts, wp)
                                                GD.AddEvent(cityName.."商业银行发行短期理财产品，预期收益3.8%，目标规模2亿", "success")
                                                navigate("city")
                                            end
                                        end},
                                    C.ActionButton {
                                        text = "中期理财1年(4.5%)",
                                        bgColor = canIssue(50000) and T.Accent or T.DisabledBg,
                                        onClick = function()
                                            if canIssue(50000) then
                                                local wp = {active=true, name="中期理财365天", yield=4.5, feeRate=0.5, targetSize=50000, currentAUM=0, totalFee=0}
                                                table.insert(bankRec.wealthProducts, wp)
                                                GD.AddEvent(cityName.."商业银行发行中期理财产品，预期收益4.5%，目标规模5亿", "success")
                                                navigate("city")
                                            end
                                        end},
                                    C.ActionButton {
                                        text = "私行专属(5.8%)",
                                        bgColor = canIssue(30000) and T.Primary or T.DisabledBg,
                                        onClick = function()
                                            if canIssue(30000) then
                                                local wp = {active=true, name="私人银行专属产品", yield=5.8, feeRate=1.0, targetSize=30000, currentAUM=0, totalFee=0}
                                                table.insert(bankRec.wealthProducts, wp)
                                                GD.AddEvent(cityName.."商业银行发行私行专属理财，预期收益5.8%，管理费1%", "success")
                                                navigate("city")
                                            end
                                        end},
                                    C.ActionButton {
                                        text = "权益基金(7.2%)",
                                        bgColor = canIssue(40000) and T.Warning or T.DisabledBg,
                                        onClick = function()
                                            if canIssue(40000) then
                                                local wp = {active=true, name="权益型基金产品", yield=7.2, feeRate=1.5, targetSize=40000, currentAUM=0, totalFee=0}
                                                table.insert(bankRec.wealthProducts, wp)
                                                GD.AddEvent(cityName.."商业银行代销权益基金，预期收益7.2%，管理费1.5%", "success")
                                                navigate("city")
                                            end
                                        end},
                                }},
                            }}
                        end)(),
                    },
                })

                -- ================================================================
                -- 四、资本与股权运作
                -- ================================================================
                table.insert(opsItems, C.SectionTitle {text = "四、资本与股权运作"})
                -- 股东表格
                local shareholderRows = {}
                -- 我方持股行
                table.insert(shareholderRows, UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    paddingVertical = 5, paddingHorizontal = 8, backgroundColor = T.PrimaryDark, borderRadius = 4,
                    children = {
                        UI.Label {text = "● 个人持有", fontSize = T.FontSmall, fontColor = T.TextPrimary, flex = 1},
                        UI.Label {text = bankRec.myShares .. "万股", fontSize = T.FontSmall, fontColor = T.Accent, minWidth = 70, textAlign = "right"},
                        UI.Label {text = myPct .. "%", fontSize = T.FontBody, fontColor = T.Success, minWidth = 45, textAlign = "right"},
                    },
                })
                for _, sh in ipairs(bankRec.shareholders) do
                    local shPct = math.floor(sh.shares / math.max(1, bankRec.totalShares) * 100)
                    local capturedSh = sh
                    table.insert(shareholderRows, UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        paddingVertical = 5, paddingHorizontal = 8, backgroundColor = T.BgCard, borderRadius = 4,
                        children = {
                            UI.Label {text = "○ " .. capturedSh.name, fontSize = T.FontSmall, fontColor = T.TextSecondary, flex = 1},
                            UI.Label {text = capturedSh.shares .. "万股", fontSize = T.FontSmall, fontColor = T.TextMuted, minWidth = 70, textAlign = "right"},
                            UI.Label {text = shPct .. "%", fontSize = T.FontSmall, fontColor = T.Warning, minWidth = 45, textAlign = "right"},
                            (function()
                                -- 可收购：支付溢价30%买入该股东的股份
                                local buyPrice = math.floor(capturedSh.shares * 0.5)  -- 0.5万/股溢价估值
                                return C.ActionButton {text = "收购(" .. FM(buyPrice) .. ")", bgColor = T.DangerBg, onClick = function()
                                    if GD.player.cash >= buyPrice then
                                        GD.player.cash = GD.player.cash - buyPrice
                                        bankRec.myShares = bankRec.myShares + capturedSh.shares
                                        capturedSh.shares = 0
                                        capturedSh.active = false
                                        -- 清除持股为0的股东
                                        local newSH = {}
                                        for _, s in ipairs(bankRec.shareholders) do
                                            if (s.shares or 0) > 0 then table.insert(newSH, s) end
                                        end
                                        bankRec.shareholders = newSH
                                        GD.AddEvent("收购"..capturedSh.name.."在"..cityName.."商业银行持有的全部股份", "success")
                                        navigate("city")
                                    end
                                end}
                            end)(),
                        },
                    })
                end

                table.insert(opsItems, UI.Panel {
                    width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        -- 股东列表标题行
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", paddingHorizontal = 8, children = {
                            UI.Label {text = "股东名称", fontSize = T.FontCaption, fontColor = T.TextMuted, flex = 1},
                            UI.Label {text = "持股量", fontSize = T.FontCaption, fontColor = T.TextMuted, minWidth = 70, textAlign = "right"},
                            UI.Label {text = "占比", fontSize = T.FontCaption, fontColor = T.TextMuted, minWidth = 45, textAlign = "right"},
                        }},
                        UI.Panel {width = "100%", gap = 4, children = shareholderRows},

                        -- 增发融资（资金注入银行账户，不进个人账户）
                        UI.Label {text = "▸ 增发新股融资（稀释股权，资金注入银行账户）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "增发5% · 融资5000万", bgColor = T.Info, onClick = function()
                                local newShares = math.floor(bankRec.totalShares * 0.05)
                                bankRec.bankCash    = bankRec.bankCash + 5000
                                bankRec.totalShares = bankRec.totalShares + newShares
                                GD.AddEvent(cityName.."商业银行增发5%新股，融资5000万注入银行账户", "success")
                                navigate("city")
                            end},
                            C.ActionButton {text = "增发15% · 融资2亿", bgColor = T.Primary, onClick = function()
                                local newShares = math.floor(bankRec.totalShares * 0.15)
                                bankRec.bankCash    = bankRec.bankCash + 20000
                                bankRec.totalShares = bankRec.totalShares + newShares
                                GD.AddEvent(cityName.."商业银行增发15%新股，融资2亿注入银行账户", "success")
                                navigate("city")
                            end},
                        }},

                        -- 引入战略投资者（投资款 → 银行账户）
                        UI.Label {text = "▸ 引入战略投资者（随机生成，投资款注入银行账户）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                            C.ActionButton {text = "引入区域战略投资者", bgColor = T.Accent, onClick = function()
                                local pool = {
                                    cityName.."城市发展投资集团", cityName.."交通投资控股",
                                    "华川保险资管公司", "产业振兴投资基金",
                                    cityName.."国有资本运营", "汇川资产亚太基金",
                                    "安和私募股权基金", cityName.."经济开发投资",
                                }
                                math.randomseed(GD.totalMonths * 37 + #bankRec.shareholders * 13)
                                local investorName = pool[math.random(1, #pool)]
                                local investShares = math.floor(bankRec.totalShares * 0.08)
                                local investAmount = math.floor(investShares * 0.5)
                                bankRec.depositCap  = bankRec.depositCap + 30000
                                bankRec.totalShares = bankRec.totalShares + investShares
                                bankRec.bankCash    = bankRec.bankCash + investAmount   -- 资金 → 银行账户
                                table.insert(bankRec.shareholders, {name = investorName, shares = investShares})
                                GD.AddEvent(investorName .. "入股" .. cityName .. "商业银行(8%)，注资" .. FM(investAmount) .. "进入银行账户", "success")
                                navigate("city")
                            end},
                            C.ActionButton {text = "引入主权/险资投资者", bgColor = T.Warning, onClick = function()
                                local pool = {
                                    "主权财富基金", "社会保障基金",
                                    "人寿资产管理", "安和保险战略投资部",
                                    "能源电网财务公司", "开发性产业基金",
                                }
                                math.randomseed(GD.totalMonths * 53 + #bankRec.shareholders * 7 + 99)
                                local investorName = pool[math.random(1, #pool)]
                                local investShares = math.floor(bankRec.totalShares * 0.12)
                                local investAmount = math.floor(investShares * 0.8)
                                bankRec.depositCap  = bankRec.depositCap + 80000
                                bankRec.loanCap     = bankRec.loanCap    + 60000
                                bankRec.totalShares = bankRec.totalShares + investShares
                                bankRec.bankCash    = bankRec.bankCash + investAmount   -- 资金 → 银行账户
                                table.insert(bankRec.shareholders, {name = investorName, shares = investShares})
                                GD.AddEvent(investorName .. "战略入股" .. cityName .. "商业银行(12%)，注资" .. FM(investAmount) .. "进入银行账户", "success")
                                navigate("city")
                            end},
                        }},

                        -- 100%持股时可向银行注资
                        (myPct == 100) and UI.Panel {gap = 6, width = "100%", children = {
                            UI.Panel {width = "100%", height = 1, backgroundColor = T.BorderColor},
                            UI.Label {text = "▸ 股东注资（100%持股专属，从个人现金注入银行账户）", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                                C.ActionButton {text = "注资5000万", bgColor = T.Info, onClick = function()
                                    if GD.player.cash >= 5000 then
                                        GD.player.cash = GD.player.cash - 5000
                                        bankRec.bankCash = bankRec.bankCash + 5000
                                        GD.AddEvent("向" .. cityName .. "商业银行注资5000万，银行账户余额增加", "success")
                                        navigate("city")
                                    end
                                end},
                                C.ActionButton {text = "注资1亿", bgColor = T.Accent, onClick = function()
                                    if GD.player.cash >= 10000 then
                                        GD.player.cash = GD.player.cash - 10000
                                        bankRec.bankCash = bankRec.bankCash + 10000
                                        GD.AddEvent("向" .. cityName .. "商业银行注资1亿，银行账户余额增加", "success")
                                        navigate("city")
                                    end
                                end},
                            }},
                            -- ★ 自定义注资金额
                            UI.Panel {
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 6,
                                alignItems = "center",
                                width = "100%",
                                children = {
                                    UI.TextField {
                                        value = state._bankInjectInput,
                                        placeholder = "输入注资金额(万)...",
                                        fontSize = T.FontSmall,
                                        flexGrow = 1,
                                        flexBasis = 140,
                                        minWidth = 0,
                                        height = 32,
                                        onChange = function(self, v) state._bankInjectInput = v end,
                                    },
                                    C.ActionButton {text = "自定义注资", bgColor = T.Primary, onClick = function()
                                        local amt = math.floor(tonumber(state._bankInjectInput) or 0)
                                        if amt <= 0 then GD.AddEvent("请输入有效金额", "warning"); navigate("city"); return end
                                        if GD.player.cash < amt then GD.AddEvent("个人现金不足", "warning"); navigate("city"); return end
                                        GD.player.cash = GD.player.cash - amt
                                        bankRec.bankCash = bankRec.bankCash + amt
                                        GD.AddEvent("向" .. cityName .. "商业银行注资" .. FM(amt) .. "，银行账户余额增加", "success")
                                        state._bankInjectInput = ""
                                        navigate("city")
                                    end},
                                },
                            },
                        }} or nil,

                        -- ----------------------------------------------------------------
                        -- 五、利润分红
                        -- ----------------------------------------------------------------
                        UI.Panel {width = "100%", height = 1, backgroundColor = T.BorderColor, marginVertical = 4},
                        UI.Label {text = "五、利润分红", fontSize = T.FontBody, fontColor = T.TextPrimary},
                        (function()
                            local retained = bankRec.retainedEarnings or bankRec.totalProfit or 0
                            local cashAboveReserve = math.max(0, (bankRec.bankCash or 0) - minReserve)
                            local divBase = math.max(0, math.min(retained, cashAboveReserve))
                            return UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                                C.StatCard {title = "收益留存", value = FM(retained), color = T.Success},
                                C.StatCard {title = "准备金外现金", value = FM(cashAboveReserve), color = cashAboveReserve > 0 and T.Info or T.Danger},
                                C.StatCard {title = "可分红总额", value = FM(divBase), color = divBase > 0 and T.Accent or T.TextMuted},
                            }}
                        end)(),
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            C.StatCard {title = "上次净利润", value = FM(bankRec.monthlyProfit or 0), color = T.Success},
                            C.StatCard {title = "上次分红", value = FM(bankRec.monthlyDividend or 0), color = T.Warning},
                            C.StatCard {title = "我方持股比", value = myPct .. "%", color = T.Accent},
                        }},
                        UI.Label {text = "分红只能使用银行收益留存，且必须保留最低准备金；到账个人现金的金额按个人持股比例计算。", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        (function()
                            local retained = bankRec.retainedEarnings or bankRec.totalProfit or 0
                            local cashAboveReserve = math.max(0, (bankRec.bankCash or 0) - minReserve)
                            local divBase = math.max(0, math.min(retained, cashAboveReserve))
                            local function doDividend(pct)
                                local totalDiv = math.floor(divBase * pct)
                                local myDiv = math.floor(totalDiv * bankRec.myShares / math.max(1, bankRec.totalShares))
                                if totalDiv > 0 and myDiv > 0 then
                                    bankRec.bankCash = (bankRec.bankCash or 0) - totalDiv
                                    bankRec.retainedEarnings = math.max(0, (bankRec.retainedEarnings or bankRec.totalProfit or 0) - totalDiv)
                                    bankRec.totalProfit = bankRec.retainedEarnings
                                    bankRec.monthlyDividend = (bankRec.monthlyDividend or 0) + myDiv
                                    GD.CreditPersonalCityCash(myDiv, true)
                                    return myDiv, totalDiv
                                end
                                return 0, 0
                            end
                            local function makeDividendButton(text, pct, bgColor)
                                return C.ActionButton {text = text, bgColor = divBase > 0 and bgColor or T.DisabledBg, onClick = function()
                                    local got = doDividend(pct)
                                    if got > 0 then
                                        GD.AddEvent(cityName .. "商业银行" .. text .. "，到账" .. FM(got), "success")
                                    else
                                        GD.AddEvent(cityName .. "商业银行暂无可分红收益留存或准备金外现金", "warning")
                                    end
                                    navigate("city")
                                end}
                            end
                            return UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                                makeDividendButton("分红10%", 0.10, T.Info),
                                makeDividendButton("分红30%", 0.30, T.Accent),
                                makeDividendButton("分红50%", 0.50, T.Primary),
                                makeDividendButton("全额分红", 1.0, T.Warning),
                            }}
                        end)(),
                    },
                })

                bankContent = UI.Panel {width = "100%", gap = 10, children = opsItems}
            end

            return UI.Panel {width = "100%", gap = 10, children = {
                bankTabBar,
                bankContent,
            }}
end

return M
