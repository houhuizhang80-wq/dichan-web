---@diagnostic disable: param-type-mismatch, assign-type-mismatch, unnecessary-if, need-check-nil, undefined-field

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

function M.BuildInvest(ctx)
    local cityName = ctx.cityName
    local navigate = ctx.navigate
    local FM = ctx.FM
            local invData = GD.GetCityInvest(cityName)
            local holdings = invData.holdings
            local items = {}

            -- ---- 已投资统计面板 ----
            local totalInvested, totalIncome, activeCount = 0, 0, 0
            for _, h in ipairs(holdings) do
                if h.active then
                    totalInvested = totalInvested + (h.amount or 0)
                    totalIncome = totalIncome + (h.totalIncome or 0)
                    activeCount = activeCount + 1
                end
            end
            table.insert(items, C.SectionTitle {text = "已投资持仓统计"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "持仓数量", value = activeCount .. "笔", color = T.Accent},
                        C.StatCard {title = "总投入", value = FM(totalInvested), color = T.Warning},
                        C.StatCard {title = "累计收益", value = FM(totalIncome), color = T.Success},
                    }},
                    -- 持仓明细列表
                    (function()
                        if #holdings == 0 then
                            return UI.Label {text = "暂无持仓，请在下方进行投资", fontSize = T.FontSmall, fontColor = T.TextMuted}
                        end
                        local rows = {}
                        for _, h in ipairs(holdings) do
                            if h.active then
                                local capturedH = h
                                local rowColor = h.type == "equity" and T.Accent or (h.type == "commodity" and T.Warning or (h.type == "sme" and T.Primary or T.Info))
                                table.insert(rows, UI.Panel {
                                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                                    alignItems = "center", paddingVertical = 4,
                                    borderBottomWidth = 1, borderColor = T.BgBase,
                                    children = {
                                        UI.Panel {gap = 2, flexShrink = 1, children = {
                                            UI.Label {text = h.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                            UI.Label {text = h.typeLabel .. " · 年化" .. string.format("%.1f", (h.monthlyReturn or 0) * 12) .. "%", fontSize = 10, fontColor = T.TextMuted},
                                        }},
                                        UI.Panel {alignItems = "flex-end", gap = 2, children = {
                                            UI.Label {text = FM(h.amount), fontSize = T.FontSmall, fontColor = rowColor},
                                            UI.Label {text = "已收益 " .. FM(h.totalIncome), fontSize = 10, fontColor = T.Success},
                                        }},
                                    },
                                })
                            end
                        end
                        return UI.Panel {width = "100%", gap = 0, children = rows}
                    end)(),
                },
            })

            -- ---- 新增投资操作 ----
            -- 本地企业股权
            table.insert(items, C.SectionTitle {text = "本地企业股权"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "投资当地优质企业股权，月度分红收益持续入账", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "年化回报", value = "8~12%", color = T.Success},
                        C.StatCard {title = "月分红", value = "按月入账", color = T.Info},
                        C.StatCard {title = "流动性", value = "低", color = T.Warning},
                    }},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "入股优质企业 500万", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 500 then
                                GD.SpendPersonalCityCash(500)
                                table.insert(holdings, {active=true, name=cityName.."本地企业股权(500万)", typeLabel="企业股权", type="equity", amount=500, monthlyReturn=0.67, totalIncome=0})
                                GD.AddEvent("投资"..cityName.."本地企业股权500万，年化约8%", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "入股优质企业 2000万", bgColor = T.Primary, onClick = function()
                            if GD.GetPersonalCityCash() >= 2000 then
                                GD.SpendPersonalCityCash(2000)
                                table.insert(holdings, {active=true, name=cityName.."本地企业股权(2000万)", typeLabel="企业股权", type="equity", amount=2000, monthlyReturn=0.83, totalIncome=0})
                                GD.AddEvent("投资"..cityName.."本地企业股权2000万，年化约10%", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })

            -- 贵金属及大宗商品
            table.insert(items, C.SectionTitle {text = "贵金属及大宗商品现货"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "黄金、白银等大宗商品对冲通胀，月均浮动收益", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "黄金年化", value = "约5%", color = T.Accent},
                        C.StatCard {title = "白银年化", value = "约6%", color = T.TextMuted},
                        C.StatCard {title = "铜年化", value = "约4%", color = T.Warning},
                    }},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "买入黄金 100kg (4500万)", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 4500 then
                                GD.SpendPersonalCityCash(4500)
                                table.insert(holdings, {active=true, name="黄金现货100kg", typeLabel="贵金属", type="commodity", amount=4500, monthlyReturn=0.42, totalIncome=0})
                                GD.AddEvent("买入黄金100kg，成本4500万，年化约5%", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "买入白银 1吨 (580万)", bgColor = T.Info, onClick = function()
                            if GD.GetPersonalCityCash() >= 580 then
                                GD.SpendPersonalCityCash(580)
                                table.insert(holdings, {active=true, name="白银现货1吨", typeLabel="贵金属", type="commodity", amount=580, monthlyReturn=0.5, totalIncome=0})
                                GD.AddEvent("买入白银1吨，成本580万，年化约6%", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })

            -- 小微企业收购
            table.insert(items, C.SectionTitle {text = "小微企业股权收购"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "收购当地小微企业，参与经营管理，超额回报持续分红", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "收购餐饮连锁 300万", bgColor = T.Primary, onClick = function()
                            if GD.GetPersonalCityCash() >= 300 then
                                GD.SpendPersonalCityCash(300)
                                table.insert(holdings, {active=true, name=cityName.."餐饮连锁", typeLabel="小微收购", type="sme", amount=300, monthlyReturn=1.0, totalIncome=0})
                                GD.AddEvent("收购"..cityName.."餐饮连锁300万，年化约12%", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "收购科技初创 500万", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 500 then
                                GD.SpendPersonalCityCash(500)
                                table.insert(holdings, {active=true, name=cityName.."科技初创", typeLabel="小微收购", type="sme", amount=500, monthlyReturn=1.25, totalIncome=0})
                                GD.AddEvent("收购"..cityName.."科技初创500万，年化约15%", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })

            -- 影视项目
            table.insert(items, C.SectionTitle {text = "影视项目投资"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "投资影视项目，分享票房及版权收益，同步提升个人声望", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "预期回报", value = "-50~+300%", color = T.Warning},
                        C.StatCard {title = "投资周期", value = "1~3年", color = T.Info},
                        C.StatCard {title = "声望加成", value = "+声望", color = T.Success},
                    }},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "投资院线电影 1000万", bgColor = T.Primary, onClick = function()
                            if GD.GetPersonalCityCash() >= 1000 then
                                GD.SpendPersonalCityCash(1000)
                                GD.player.prestige = (GD.player.prestige or 0) + 5
                                table.insert(holdings, {active=true, name=cityName.."院线电影", typeLabel="影视投资", type="film", amount=1000, monthlyReturn=0, totalIncome=0})
                                GD.AddEvent("投资"..cityName.."院线电影1000万，个人声望+5", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "投资网络剧 300万", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 300 then
                                GD.SpendPersonalCityCash(300)
                                GD.player.prestige = (GD.player.prestige or 0) + 2
                                table.insert(holdings, {active=true, name=cityName.."网络剧", typeLabel="影视投资", type="film", amount=300, monthlyReturn=0, totalIncome=0})
                                GD.AddEvent("投资"..cityName.."网络剧300万，个人声望+2", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })

            return UI.Panel {width = "100%", gap = 10, children = items}
end

-- ===== 子标签2: 地方债券 =====
function M.BuildBond(ctx)
    local cityName = ctx.cityName
    local navigate = ctx.navigate
    local FM = ctx.FM
            local bondData = GD.GetCityBond(cityName)
            local bonds = bondData.holdings
            local items = {}

            -- ---- 已投资债券统计 ----
            local totalPrincipal, totalEarned, activeBonds = 0, 0, 0
            for _, b in ipairs(bonds) do
                if b.active then
                    totalPrincipal = totalPrincipal + (b.principal or 0)
                    totalEarned = totalEarned + (b.interestEarned or 0)
                    activeBonds = activeBonds + 1
                end
            end
            table.insert(items, C.SectionTitle {text = "债券持仓统计"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "持有债券", value = activeBonds .. "只", color = T.Accent},
                        C.StatCard {title = "本金合计", value = FM(totalPrincipal), color = T.Warning},
                        C.StatCard {title = "累计票息", value = FM(totalEarned), color = T.Success},
                    }},
                    (function()
                        if activeBonds == 0 then
                            return UI.Label {text = "暂无持仓债券，请在下方购入", fontSize = T.FontSmall, fontColor = T.TextMuted}
                        end
                        local rows = {}
                        for _, b in ipairs(bonds) do
                            if b.active then
                                local remain = b.remainMonths or b.termMonths
                                local remainText = remain and (math.floor(remain/12) .. "年" .. (remain%12) .. "月到期") or "持有中"
                                table.insert(rows, UI.Panel {
                                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                                    alignItems = "center", paddingVertical = 4,
                                    borderBottomWidth = 1, borderColor = T.BgBase,
                                    children = {
                                        UI.Panel {gap = 2, flexShrink = 1, children = {
                                            UI.Label {text = b.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                            UI.Label {text = b.typeLabel .. " · 年化" .. b.annualRate .. "% · " .. remainText, fontSize = 10, fontColor = T.TextMuted},
                                        }},
                                        UI.Panel {alignItems = "flex-end", gap = 2, children = {
                                            UI.Label {text = FM(b.principal), fontSize = T.FontSmall, fontColor = T.Info},
                                            UI.Label {text = "已收票息 " .. FM(b.interestEarned), fontSize = 10, fontColor = T.Success},
                                        }},
                                    },
                                })
                            end
                        end
                        return UI.Panel {width = "100%", gap = 0, children = rows}
                    end)(),
                },
            })

            -- ---- 政府债 / 城投债 ----
            table.insert(items, C.SectionTitle {text = "政府债券 / 城投债"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "购买"..cityName.."地方政府债券及城投债，收益稳定，逐月收息到账", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "3年期利率", value = "3.5%", color = T.Info},
                        C.StatCard {title = "5年期利率", value = "4.2%", color = T.Info},
                        C.StatCard {title = "10年期利率", value = "5.0%", color = T.Accent},
                    }},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "购入城投债 1000万(3年)", bgColor = T.Info, onClick = function()
                            if GD.GetPersonalCityCash() >= 1000 then
                                GD.SpendPersonalCityCash(1000)
                                table.insert(bonds, {active=true, name=cityName.."城投债(1000万)", typeLabel="城投债", principal=1000, annualRate=3.5, termMonths=36, remainMonths=36, interestEarned=0})
                                GD.AddEvent("购入"..cityName.."城投债1000万，3年期3.5%，按月收息", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "购入政府债 5000万(5年)", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 5000 then
                                GD.SpendPersonalCityCash(5000)
                                table.insert(bonds, {active=true, name=cityName.."政府债(5000万)", typeLabel="政府债", principal=5000, annualRate=4.2, termMonths=60, remainMonths=60, interestEarned=0})
                                GD.AddEvent("购入"..cityName.."政府债券5000万，5年期4.2%，按月收息", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "购入政府债 10000万(10年)", bgColor = T.Primary, onClick = function()
                            if GD.GetPersonalCityCash() >= 10000 then
                                GD.SpendPersonalCityCash(10000)
                                table.insert(bonds, {active=true, name=cityName.."政府债(1亿)", typeLabel="政府债", principal=10000, annualRate=5.0, termMonths=120, remainMonths=120, interestEarned=0})
                                GD.AddEvent("购入"..cityName.."政府债券1亿元，10年期5.0%，按月收息", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })

            -- ---- 企业短期融资券 ----
            table.insert(items, C.SectionTitle {text = "企业短期融资券"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 6, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Label {text = "投资本地优质企业发行的短期融资券，流动性强，收益高于政府债", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "6个月利率", value = "5.5%", color = T.Accent},
                        C.StatCard {title = "12个月利率", value = "6.8%", color = T.Warning},
                        C.StatCard {title = "信用评级", value = "AA", color = T.Success},
                    }},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", children = {
                        C.ActionButton {text = "认购融资券 500万(6月)", bgColor = T.Accent, onClick = function()
                            if GD.GetPersonalCityCash() >= 500 then
                                GD.SpendPersonalCityCash(500)
                                table.insert(bonds, {active=true, name=cityName.."企业融资券(500万)", typeLabel="短期融资券", principal=500, annualRate=5.5, termMonths=6, remainMonths=6, interestEarned=0})
                                GD.AddEvent("认购"..cityName.."企业融资券500万，6个月5.5%", "success")
                                navigate("city")
                            end
                        end},
                        C.ActionButton {text = "认购融资券 2000万(12月)", bgColor = T.Warning, onClick = function()
                            if GD.GetPersonalCityCash() >= 2000 then
                                GD.SpendPersonalCityCash(2000)
                                table.insert(bonds, {active=true, name=cityName.."企业融资券(2000万)", typeLabel="短期融资券", principal=2000, annualRate=6.8, termMonths=12, remainMonths=12, interestEarned=0})
                                GD.AddEvent("认购"..cityName.."企业融资券2000万，12个月6.8%", "success")
                                navigate("city")
                            end
                        end},
                    }},
                },
            })
            return UI.Panel {width = "100%", gap = 10, children = items}
end

-- ===== 子标签3: 赞助 =====
function M.BuildSponsor(ctx)
    local cityName = ctx.cityName
    local navigate = ctx.navigate
    local FM = ctx.FM
            local sponsorRecord = GD.GetCitySponsor(cityName)
            local items = {}

            -- ---- 已赞助项目统计 ----
            table.insert(items, C.SectionTitle {text = "已赞助项目统计"})
            table.insert(items, UI.Panel {
                width = "100%", padding = 10, gap = 8, backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                        C.StatCard {title = "赞助次数", value = #sponsorRecord.history .. "次", color = T.Accent},
                        C.StatCard {title = "总投入", value = FM(sponsorRecord.totalSpent), color = T.Warning},
                        C.StatCard {title = "累计声望获益", value = "+" .. (sponsorRecord.totalBrand or 0) .. "分", color = T.Success},
                    }},
                    (function()
                        if #sponsorRecord.history == 0 then
                            return UI.Label {text = "暂无赞助记录，请在下方选择活动赞助", fontSize = T.FontSmall, fontColor = T.TextMuted}
                        end
                        local rows = {}
                        -- 显示最近5条记录
                        local startIdx = math.max(1, #sponsorRecord.history - 4)
                        for i = startIdx, #sponsorRecord.history do
                            local rec = sponsorRecord.history[i]
                            table.insert(rows, UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                alignItems = "center", paddingVertical = 3,
                                borderBottomWidth = 1, borderColor = T.BgBase,
                                children = {
                                    UI.Panel {gap = 1, flexShrink = 1, children = {
                                        UI.Label {text = rec.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                        UI.Label {text = rec.year.."年"..rec.month.."月", fontSize = 10, fontColor = T.TextMuted},
                                    }},
                                    UI.Panel {alignItems = "flex-end", gap = 1, children = {
                                        UI.Label {text = FM(rec.cost), fontSize = T.FontSmall, fontColor = T.Warning},
                                        UI.Label {text = "声望 +" .. rec.brandGain, fontSize = 10, fontColor = T.Success},
                                    }},
                                },
                            })
                        end
                        return UI.Panel {width = "100%", gap = 0, children = rows}
                    end)(),
                },
            })

            -- ---- 可赞助活动 ----
            table.insert(items, C.SectionTitle {text = "可赞助活动"})
            local sponsorOpts = {
                {name = "城市马拉松赛事", cost = 200, brandGain = 3, desc = "赞助年度城市马拉松，覆盖全城媒体曝光"},
                {name = "文化艺术节", cost = 500, brandGain = 6, desc = "冠名城市文化艺术节，树立品牌文化形象"},
                {name = "青少年足球联赛", cost = 150, brandGain = 2, desc = "赞助青少年足球联赛，塑造公益品牌形象"},
                {name = "城市高峰论坛", cost = 800, brandGain = 8, desc = "赞助行业高峰论坛，深度绑定政商资源"},
                {name = "公益慈善晚宴", cost = 100, brandGain = 1, desc = "参与慈善晚宴赞助，提升社会责任形象"},
                {name = "国际美食文化节", cost = 350, brandGain = 4, desc = "冠名国际美食文化节，扩大品牌曝光"},
                {name = "科创大赛", cost = 600, brandGain = 7, desc = "冠名科技创新大赛，塑造品牌科技感"},
            }
            for _, opt in ipairs(sponsorOpts) do
                local capturedOpt = opt
                table.insert(items, UI.Panel {
                    width = "100%", padding = 10, gap = 6,
                    backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Label {text = capturedOpt.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                                C.Badge {text = "声望+" .. capturedOpt.brandGain, variant = "success"},
                                C.Badge {text = FM(capturedOpt.cost), variant = "warning"},
                            }},
                        }},
                        UI.Label {text = capturedOpt.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        C.ActionButton {text = "立即赞助", bgColor = T.Success, onClick = function()
                            if GD.GetPersonalCityCash() >= capturedOpt.cost then
                                GD.SpendPersonalCityCash(capturedOpt.cost)
                                GD.player.prestige = (GD.player.prestige or 0) + capturedOpt.brandGain
                                sponsorRecord.totalSpent = (sponsorRecord.totalSpent or 0) + capturedOpt.cost
                                sponsorRecord.totalBrand = (sponsorRecord.totalBrand or 0) + capturedOpt.brandGain
                                table.insert(sponsorRecord.history, {
                                    name = capturedOpt.name, cost = capturedOpt.cost, brandGain = capturedOpt.brandGain,
                                    year = GD.year, month = GD.month,
                                })
                                GD.AddEvent("赞助"..cityName.."《"..capturedOpt.name.."》，个人声望+"..capturedOpt.brandGain, "success")
                                navigate("city")
                            end
                        end},
                    },
                })
            end
            return UI.Panel {width = "100%", gap = 10, children = items}
end

return M
