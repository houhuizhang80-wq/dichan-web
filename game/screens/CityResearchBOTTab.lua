---@diagnostic disable: param-type-mismatch, assign-type-mismatch, unnecessary-if, need-check-nil, undefined-field

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

function M.Build(ctx)
    local city = ctx.city
    local cityName = ctx.cityName
    local navigate = ctx.navigate
    local FM = ctx.FM
    local state = ctx.state
            local botData = GD.GetCityBOT(cityName)
            local myProjects = botData.projects
            local items = {}

            -- ---- 已投代建项目统计 ----
            local activeBOT, totalBOTIncome, totalBOTExpense, totalBOTInvest = 0, 0, 0, 0
            for _, p in ipairs(myProjects) do
                if p.active then
                    activeBOT = activeBOT + 1
                    local selfFund = p.selfFund or math.floor((p.buildCost or 0) * 0.3)
                    totalBOTIncome = totalBOTIncome + (p.totalIncome or 0)
                    totalBOTExpense = totalBOTExpense + (p.totalExpense or 0)
                    totalBOTInvest = totalBOTInvest + selfFund
                end
            end
            table.insert(items, C.SectionTitle {text = "已投BOT代建项目"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "在运项目", value = activeBOT .. "个", color = T.Accent},
                        C.StatCard {title = "自有投入", value = FM(totalBOTInvest), color = T.Warning},
                        C.StatCard {title = "投资净收益", value = FM(totalBOTIncome - totalBOTExpense - totalBOTInvest), color = T.Success},
                    }},
                    (function()
                        if activeBOT == 0 then
                            return UI.Label {text = "暂无在运BOT项目，请在下方投标", fontSize = T.FontSmall, fontColor = T.TextMuted}
                        end
                        local rows = {}
                        for _, p in ipairs(myProjects) do
                            if p.active then
                                local remainYears = math.floor((p.remainMonths or 0) / 12)
                                local selfFund = p.selfFund or math.floor((p.buildCost or 0) * 0.3)
                                local monthNet = p.monthNet or math.floor(selfFund * 0.06 / 12)
                                local investNet = (p.totalIncome or 0) - (p.totalExpense or 0) - selfFund
                                table.insert(rows, UI.Panel {
                                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                                    alignItems = "center", paddingVertical = 4,
                                    borderBottomWidth = 1, borderColor = T.BgBase,
                                    children = {
                                        UI.Panel {gap = 2, flexShrink = 1, children = {
                                            UI.Label {text = p.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                            UI.Label {text = "剩余" .. remainYears .. "年特许期 | 年净收益≤投入6%", fontSize = 10, fontColor = T.TextMuted},
                                        }},
                                        UI.Panel {alignItems = "flex-end", gap = 2, children = {
                                            UI.Label {text = "月净收 " .. FM(monthNet), fontSize = T.FontSmall, fontColor = monthNet >= 0 and T.Success or T.Danger},
                                            UI.Label {text = "投资净收益 " .. FM(investNet), fontSize = 10, fontColor = T.Accent},
                                        }},
                                    },
                                })
                            end
                        end
                        return UI.Panel {width = "100%", gap = 0, children = rows}
                    end)(),
                },
            })

            -- ---- BOT 说明 ----
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.PrimaryDark, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "BOT (Build-Operate-Transfer) 投资代建", fontSize = T.FontBody, fontColor = T.TextPrimary},
                    UI.Label {text = "投资建设城市基础设施，获取30年特许经营权；项目按个人自有资金30%、项目融资70%测算，经营现金流需偿还融资本金，年净收益封顶为个人自有投入的6%。", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "特许期", value = "30年", color = T.Accent},
                        C.StatCard {title = "自有资金", value = "30%", color = T.Warning},
                        C.StatCard {title = "收益模式", value = "月度到账", color = T.Success},
                    }},
                },
            })

            -- ---- 可投BOT项目（按城市潜力随机刷新） ----
            table.insert(items, C.SectionTitle {text = "可投标BOT项目"})

            -- 用城市潜力 + 月份生成局部伪随机序列，每季度刷新一次，不污染全局随机状态
            local refreshQuarter = math.floor((GD.totalMonths or 0) / 3)
            local randomState = (city.potential or 70) * 1000 + refreshQuarter
            local function nextRandom(maxValue)
                randomState = (randomState * 1103515245 + 12345) % 2147483648
                return (randomState % maxValue) + 1
            end

            -- BOT代建项目参数：运行期先偿还70%融资本金，再把个人实际年净收益封顶为自有投入×6%。
            local botPool = {
                {name="城市快速路(高架)", icon="🛣", buildCost=80000, annualToll=6000, annualMaint=800, annualAd=500, tax=1200, finInterest=3000, desc="建设城市快速高架路，全长约20km，日均车流量15万辆"},
                {name="跨江大桥", icon="🌉", buildCost=50000, annualToll=4500, annualMaint=600, annualAd=300, tax=900, finInterest=2000, desc="建设跨江大桥，全长约3km，连通城市南北两岸"},
                {name="智慧停车场群", icon="🅿", buildCost=5000, annualToll=480, annualMaint=80, annualAd=60, tax=100, finInterest=200, desc="建设智慧停车场群（10个地下停车场，合计5000车位）"},
                {name="城市地下隧道", icon="🚇", buildCost=120000, annualToll=8000, annualMaint=1200, annualAd=800, tax=1800, finInterest=5000, desc="建设城市核心地下快速通道，全长约8km"},
                {name="新能源充电网络", icon="⚡", buildCost=3000, annualToll=320, annualMaint=50, annualAd=60, tax=90, finInterest=120, desc="在全市建设500个快充站，运营充电服务费+广告"},
                {name="城市综合管廊", icon="🔧", buildCost=20000, annualToll=1800, annualMaint=300, annualAd=200, tax=360, finInterest=800, desc="建设城市地下综合管廊，出租管廊空间给电力、通讯等"},
                {name="公共自行车系统", icon="🚲", buildCost=800, annualToll=80, annualMaint=30, annualAd=20, tax=20, finInterest=32, desc="建设城市公共自行车系统（5000辆+500站点）"},
                {name="港口物流枢纽", icon="⚓", buildCost=200000, annualToll=20000, annualMaint=3000, annualAd=1000, tax=4000, finInterest=8000, desc="建设现代化港口物流枢纽，年吞吐量200万标箱"},
            }

            -- 按城市tier决定可见项目数量
            local visibleCount = 3 + math.floor((city.tier or 1) * 1.5)
            -- 随机选取
            local shuffled = {}
            for _, p in ipairs(botPool) do table.insert(shuffled, p) end
            for i = #shuffled, 2, -1 do
                local j = nextRandom(i)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end

            -- 检查已投标名单
            local investedNames = {}
            for _, p in ipairs(myProjects) do investedNames[p.name] = true end

            local botListKey = "botOptions_" .. cityName
            local botExpanded = state._expandSections[botListKey] == true
            local shownCount = 0
            for i = 1, #shuffled do
                if i <= visibleCount or botExpanded then
                    shownCount = shownCount + 1
                    local proj = shuffled[i]
                    local capturedProj = proj
                    local alreadyIn = investedNames[proj.name]

                local selfFund = math.floor(proj.buildCost * 0.3)
                local debtFund = proj.buildCost - selfFund
                local annualOperationNet = (proj.annualToll + proj.annualAd) - (proj.annualMaint + proj.tax + proj.finInterest)
                local annualPrincipal = math.ceil(debtFund / 30)
                local annualRawNet = annualOperationNet - annualPrincipal
                local annualNetCap = math.floor(selfFund * 0.06)
                local annualCappedNet = math.min(annualRawNet, annualNetCap)
                local monthNet = math.floor(annualCappedNet / 12)
                local netProfit30 = annualCappedNet * 30 - selfFund
                local annualRoi = selfFund > 0 and math.floor(annualCappedNet / selfFund * 1000) / 10 or 0

                table.insert(items, UI.Panel {
                    width = "100%", padding = 12, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    borderWidth = alreadyIn and 1 or 0, borderColor = T.Success,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Label {text = capturedProj.icon .. " " .. capturedProj.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                            alreadyIn and C.Badge {text = "已投标", variant = "success"} or
                            C.Badge {text = annualCappedNet > 0 and ("年化" .. string.format("%.1f", annualRoi) .. "%") or "谨慎测算", variant = annualCappedNet > 0 and "success" or "warning"},
                        }},
                        UI.Label {text = capturedProj.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", children = {
                            C.StatCard {title = "建设总投", value = FM(capturedProj.buildCost), color = T.Danger},
                            C.StatCard {title = "自有资金(30%)", value = FM(selfFund), color = T.Warning},
                            C.StatCard {title = "封顶月净收", value = FM(monthNet), color = monthNet >= 0 and T.Success or T.Danger},
                        }},
                        UI.Panel {
                            width = "100%", padding = 8,
                            backgroundColor = annualCappedNet > 0 and T.SuccessBg or T.DangerBg,
                            borderRadius = 6,
                            children = {
                                UI.Label {
                                    text = "30年投资净收益预估：" .. FM(netProfit30) .. "（年净收益≤自有投入6%，含融资本金摊还）",
                                    fontSize = T.FontBody, fontColor = T.TextPrimary,
                                },
                            }
                        },
                        alreadyIn and UI.Label {text = "已参与投标，项目运营中", fontSize = T.FontSmall, fontColor = T.Success} or
                        C.ActionButton {
                            text = "投标参与 (自有" .. FM(selfFund) .. " + 融资" .. FM(debtFund) .. ")",
                            bgColor = GD.GetPersonalCityCash() >= selfFund and T.Primary or T.DisabledBg,
                            onClick = function()
                                local duplicate = false
                                for _, project in ipairs(myProjects) do
                                    if project.active and project.name == capturedProj.name then
                                        duplicate = true
                                        break
                                    end
                                end
                                if duplicate then
                                    GD.AddEvent("已持有" .. cityName .. "《" .. capturedProj.name .. "》BOT项目", "warning")
                                    navigate("city")
                                    return
                                end
                                local paid = GD.SpendPersonalCityCash(selfFund)
                                if paid then
                                    table.insert(myProjects, {
                                        active = true, name = capturedProj.name,
                                        buildCost = capturedProj.buildCost,
                                        annualToll = capturedProj.annualToll, annualAd = capturedProj.annualAd,
                                        annualMaint = capturedProj.annualMaint, tax = capturedProj.tax,
                                        finInterest = capturedProj.finInterest,
                                        selfFund = selfFund,
                                        debtFund = debtFund,
                                        debtRemaining = debtFund,
                                        investAmount = selfFund,
                                        annualNetCap = annualNetCap,
                                        remainMonths = 360,  -- 30年
                                        totalIncome = 0, totalExpense = 0,
                                        totalOperationIncome = 0, totalOperationExpense = 0,
                                        totalPrincipalRepaid = 0,
                                        _botCashflowV2 = true,
                                    })
                                    GD.AddEvent("中标"..cityName.."《"..capturedProj.name.."》BOT，自有"..FM(selfFund).."，融资"..FM(debtFund).."，年净收益封顶"..FM(annualNetCap), "success")
                                    navigate("city")
                                end
                            end,
                        },
                    },
                })
                end
            end
            table.insert(items, C.FoldButton {
                total = #shuffled,
                limit = visibleCount,
                expanded = botExpanded,
                onClick = function()
                    state._expandSections[botListKey] = not botExpanded
                    navigate("city")
                end,
            })

            -- 刷新提示
            table.insert(items, UI.Panel {
                width = "100%", padding = 8, backgroundColor = T.BgBase, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "每季度自动刷新可投标项目，当前刷新批次：第" .. (refreshQuarter + 1) .. "期", fontSize = T.FontSmall, fontColor = T.TextMuted},
                },
            })

            return UI.Panel {width = "100%", gap = 10, children = items}
end

return M
