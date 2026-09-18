---@diagnostic disable: assign-type-mismatch, param-type-mismatch
-- ============================================================================
-- AuctionScreen.lua - 土地竞拍（Phase 5: 熔断 + 法拍 + 联合拿地 + 反悔）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local InvestScreen = require("screens/InvestScreen")
local LA = GD.LandAcquisition
local DT = require("DevTypes")

local M = {}

-- 竞拍状态(持久化在模块级)
M._state = nil
M._customProjectName = ""  -- 自定义项目名称
M._expandedLists = M._expandedLists or {}

function M.InitAuction(land)
    -- 使用 LA 获取渠道专属竞拍参数
    local params = LA.GetAuctionParams(land)

    M._state = {
        land = land,
        currentPrice = land.startPrice,
        myLastBid = 0,
        highestBidder = "起拍",
        log = {{bidder = "系统", text = "竞拍开始！起拍价 " .. C.FormatMoney(land.startPrice)}},
        finished = false,
        won = false,
        round = 0,
        maxRounds = params.maxRounds,
        priceCap = params.priceCap,
        aiPlayers = {},
        increment = params.increment,
        -- Phase 4 新增
        circuitBroken = false,     -- 是否已触发熔断
        sealedBidMode = false,     -- 是否处于密封报价模式
        sealedResult = nil,        -- 密封报价结果
        isJudicial = land.channel == LA.CHANNELS.JUDICIAL,
        auctionRound = params.auctionRound,
        -- Phase 5 新增
        jointBid = nil,            -- 联合拿地信息 { partnerName, partnerSharePct }
        availablePartners = LA.FindJointBidPartners(land, GD.competitors),
        forfeitAllowed = true,     -- 竞拍成功后允许反悔
        forfeited = false,         -- 是否已反悔
    }

    -- 法拍特殊提示
    if M._state.isJudicial then
        local cd = land.channelData or {}
        local roundText = cd.auctionRound == 1 and "首拍" or "二拍"
        table.insert(M._state.log, 1, {
            bidder = "系统",
            text = "【法拍】" .. (cd.courtName or "") .. " " .. (cd.caseNumber or "") .. " (" .. roundText .. ")",
        })
        table.insert(M._state.log, 1, {
            bidder = "系统",
            text = "⚠ 法拍地块可能存在隐性风险，建议完成尽职调查后再竞拍",
        })
    end

    -- 熔断阈值提示
    table.insert(M._state.log, 1, {
        bidder = "系统",
        text = "溢价率超过" .. math.floor(LA.CIRCUIT_BREAKER_PREMIUM * 100) .. "%将触发熔断，转为密封报价",
    })

    -- 随机选AI参与者
    local count = math.random(params.aiCountMin, params.aiCountMax)
    local pool = {}
    for i, comp in ipairs(GD.competitors) do pool[i] = comp end
    for i = 1, math.min(count, #pool) do
        local idx = math.random(1, #pool)
        local range = params.aiMaxPriceRange
        local aiMax = math.floor(land.startPrice * (1 + math.random(range[1], range[2]) / 100))
        aiMax = math.min(aiMax, M._state.priceCap)
        table.insert(M._state.aiPlayers, {
            name = pool[idx].name,
            aggressive = pool[idx].aggressive,
            maxPrice = aiMax,
            active = true,
        })
        table.remove(pool, idx)
    end
end

function M.PlayerBid(amount, navigate)
    local s = M._state
    if s.finished then return end

    if s.highestBidder == GD.company.name then
        amount = s.currentPrice
    end

    s.round = s.round + 1
    s.currentPrice = amount
    s.myLastBid = amount
    s.highestBidder = GD.company.name
    table.insert(s.log, 1, {bidder = GD.company.name, text = "第" .. s.round .. "轮 | " .. GD.company.name .. " 出价 " .. C.FormatMoney(amount)})

    -- 检查熔断
    local triggered, premiumRate = LA.CheckCircuitBreaker(s.land, amount)
    if triggered and not s.circuitBroken then
        s.circuitBroken = true
        s.sealedBidMode = true
        table.insert(s.log, 1, {
            bidder = "系统",
            text = "⚡ 熔断触发！溢价率达" .. math.floor(premiumRate * 100) .. "%，转为密封报价模式",
        })
        navigate("auction")
        return
    end

    -- AI轮次响应
    for _, ai in ipairs(s.aiPlayers) do
        if ai.active then
            if amount >= ai.maxPrice or amount >= s.priceCap then
                ai.active = false
                table.insert(s.log, 1, {bidder = ai.name, text = ai.name .. " 放弃竞拍"})
            elseif math.random() < ai.aggressive then
                local aiBid = amount + s.increment * math.random(1, 2)
                aiBid = math.min(aiBid, ai.maxPrice)
                aiBid = math.min(aiBid, s.priceCap)
                if aiBid <= amount then
                    ai.active = false
                    table.insert(s.log, 1, {bidder = ai.name, text = ai.name .. " 放弃竞拍"})
                else
                    s.currentPrice = aiBid
                    s.highestBidder = ai.name
                    table.insert(s.log, 1, {bidder = ai.name, text = ai.name .. " 出价 " .. C.FormatMoney(aiBid)})

                    -- AI出价后也可能触发熔断
                    local aiTriggered, aiPremium = LA.CheckCircuitBreaker(s.land, aiBid)
                    if aiTriggered and not s.circuitBroken then
                        s.circuitBroken = true
                        s.sealedBidMode = true
                        table.insert(s.log, 1, {
                            bidder = "系统",
                            text = "⚡ 熔断触发！溢价率达" .. math.floor(aiPremium * 100) .. "%，转为密封报价模式",
                        })
                        navigate("auction")
                        return
                    end
                end
            else
                ai.active = false
                table.insert(s.log, 1, {bidder = ai.name, text = ai.name .. " 放弃竞拍"})
            end
        end
    end

    -- 检查是否结束
    local allQuit = true
    for _, ai in ipairs(s.aiPlayers) do
        if ai.active then allQuit = false; break end
    end

    local roundEnd = s.round >= s.maxRounds

    if (allQuit or roundEnd) and s.highestBidder ~= "起拍" then
        M.FinishAuction(s)
    end

    navigate("auction")
end

--- 密封报价提交
function M.SubmitSealedBid(playerBid, navigate)
    local s = M._state
    if s.finished then return end

    local result = LA.SealedBidRound(s.land, s.aiPlayers, playerBid)
    s.sealedResult = result
    s.sealedBidMode = false

    -- 记录所有报价
    table.insert(s.log, 1, {bidder = "系统", text = "=== 密封报价结果 ==="})
    for i, b in ipairs(result.allBids) do
        local name = b.name == "__player__" and GD.company.name or b.name
        table.insert(s.log, 1, {
            bidder = name,
            text = "第" .. i .. "名: " .. name .. " 报价 " .. C.FormatMoney(b.bid),
        })
    end

    -- 设置竞拍结果
    s.currentPrice = result.winnerBid
    if result.isPlayer then
        s.highestBidder = GD.company.name
        s.myLastBid = playerBid
    else
        s.highestBidder = result.winner
    end

    M.FinishAuction(s)
    navigate("auction")
end

--- 结算竞拍
function M.FinishAuction(s)
    s.finished = true
    if s.highestBidder == GD.company.name then
        s.won = true
        local wonPrice = s.myLastBid

        -- 联合拿地: 只扣玩家份额
        if s.jointBid then
            local shares = LA.CalcJointBidShares(s.land, s.jointBid.partnerName, s.jointBid.partnerSharePct, wonPrice)
            s.jointBidShares = shares
            GD.company.cash = GD.company.cash - shares.playerCost
            table.insert(s.log, 1, {bidder = "系统", text = "联合拿地！" .. GD.company.name .. " 出资" .. C.FormatMoney(shares.playerCost) .. "(" .. shares.playerSharePct .. "%)，" .. shares.partnerName .. " 出资" .. C.FormatMoney(shares.partnerCost) .. "(" .. shares.partnerSharePct .. "%)"})
        else
            GD.company.cash = GD.company.cash - wonPrice
        end

        table.insert(s.log, 1, {bidder = "系统", text = "恭喜！" .. GD.company.name .. " 以 " .. C.FormatMoney(wonPrice) .. " 竞得地块！"})

        s.land.price = wonPrice
        s.land.status = "sold"
        -- 保存联合拿地信息到地块
        if s.jointBid then
            s.land.jointBid = s.jointBidShares
        end
        s.land.acquiredMonth = GD.totalMonths
        s.land.ownerType = "player_company"
        s.land.ownerCompanyId = GD.activeCompanyId
        table.insert(GD.landReserve, s.land)
        for i, l in ipairs(GD.landMarket) do
            if l.id == s.land.id then table.remove(GD.landMarket, i); break end
        end

        if s.jointBid then
            GD.AddEvent("联合竞得 " .. s.land.location .. " 地块，成交价 " .. C.FormatMoney(wonPrice) .. "（与" .. s.jointBid.partnerName .. "合作），已加入储备", "success")
        else
            GD.AddEvent("成功竞得 " .. s.land.location .. " 地块，成交价 " .. C.FormatMoney(wonPrice) .. "，已加入储备", "success")
        end
        table.insert(s.log, 1, {bidder = "系统", text = "请确认收购或选择反悔（将损失保证金+违约金）"})
    else
        table.insert(s.log, 1, {bidder = "系统", text = s.highestBidder .. " 以 " .. C.FormatMoney(s.currentPrice) .. " 竞得地块"})
        s.land.status = "sold"
        for i, l in ipairs(GD.landMarket) do
            if l.id == s.land.id then table.remove(GD.landMarket, i); break end
        end
        GD.AddEvent(s.highestBidder .. " 竞得 " .. s.land.location .. " 地块", "info")
    end
end

--- 确认收购（土地留在储备，稍后在储备页面启动开发）
function M.ConfirmAcquisition(navigate)
    local s = M._state
    if not s or not s.won then return end
    GD.AddEvent("确认收购 " .. s.land.location .. " 地块，请在土地储备中启动开发", "success")
    M._customProjectName = ""
    M._state = nil
    navigate("invest")
end

--- 反悔（放弃已竞得地块）
function M.ForfeitAuction(navigate)
    local s = M._state
    if not s or not s.won then return end

    local penalty, msg = LA.CalcForfeitPenalty(s.land, s.myLastBid)

    -- 退还已支付的地价（但扣罚金）
    local refund
    if s.jointBid and s.jointBidShares then
        refund = s.jointBidShares.playerCost - penalty
    else
        refund = s.myLastBid - penalty
    end
    GD.company.cash = GD.company.cash + math.max(0, refund)

    -- 地块退回市场
    s.land.status = "available"
    s.land.price = nil
    s.land.jointBid = nil
    -- 从储备移回市场
    for i, l in ipairs(GD.landReserve) do
        if l.id == s.land.id then table.remove(GD.landReserve, i); break end
    end
    table.insert(GD.landMarket, s.land)

    GD.AddEvent("反悔放弃 " .. s.land.location .. " 地块，" .. msg, "warning")
    M._state = nil
    navigate("invest")
end

function M.Create(navigate)
    -- 初始化竞拍
    if not M._state then
        local landId = InvestScreen._auctionLandId
        local land
        for _, l in ipairs(GD.landMarket) do
            if l.id == landId then land = l; break end
        end
        if not land then
            return UI.Panel {
                width = "100%", height = "100%",
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {text = "未找到地块信息", fontSize = T.FontBody, fontColor = T.Danger},
                    C.SecondaryButton {text = "返回", onClick = function() navigate("invest") end},
                }
            }
        end
        local companyCity = GD.company and GD.company.city or ""
        if companyCity ~= "" and land.city ~= companyCity then
            return UI.Panel {
                width = "100%", height = "100%",
                justifyContent = "center", alignItems = "center", gap = 10,
                children = {
                    UI.Label {text = "不能竞拍外城地块", fontSize = T.FontBody, fontColor = T.Danger},
                    UI.Label {text = "当前公司注册地为" .. companyCity .. "，只能在本城市拿地。", fontSize = T.FontSmall, fontColor = T.TextMuted},
                    C.SecondaryButton {text = "返回", onClick = function() navigate("invest") end},
                }
            }
        end
        M.InitAuction(land)
    end

    local s = M._state
    local land = s.land

    -- 竞拍日志
    local logItems = {}
    local auctionLogExpanded = M._expandedLists.auctionLog == true
    for i = 1, #s.log do
        if C.ShouldShowListItem(i, auctionLogExpanded, 15) then
            local entry = s.log[i]
            local isSystem = entry.bidder == "系统"
            local isMe = entry.bidder == GD.company.name
            local isCircuit = isSystem and string.find(entry.text, "熔断")
            table.insert(logItems, UI.Panel {
                flexDirection = "row",
                gap = 6,
                width = "100%",
                paddingVertical = 3,
                children = {
                    UI.Panel {
                        width = 6, height = 6,
                        backgroundColor = isCircuit and T.Warning or (isSystem and T.Info or (isMe and T.Accent or T.TextMuted)),
                        borderRadius = 3,
                        marginTop = 5,
                    },
                    UI.Label {
                        text = entry.text,
                        fontSize = T.FontSmall,
                        fontColor = isCircuit and T.Warning or (isMe and T.Accent or (isSystem and T.Info or T.TextSecondary)),
                        flexGrow = 1,
                        flexBasis = 0,
                    },
                }
            })
        end
    end
    table.insert(logItems, C.FoldButton {
        total = #s.log,
        limit = 15,
        expanded = auctionLogExpanded,
        onClick = function()
            M._expandedLists.auctionLog = not auctionLogExpanded
            navigate("auction")
        end,
    })

    -- AI参与者状态
    local aiCards = {}
    for _, ai in ipairs(s.aiPlayers) do
        table.insert(aiCards, UI.Panel {
            flexDirection = "row",
            gap = 6,
            alignItems = "center",
            children = {
                UI.Panel {width=8, height=8, backgroundColor=ai.active and T.Success or T.Danger, borderRadius=4},
                UI.Label {
                    text = ai.name,
                    fontSize = T.FontSmall,
                    fontColor = ai.active and T.TextPrimary or T.TextMuted,
                },
                UI.Label {
                    text = ai.active and "竞拍中" or "已退出",
                    fontSize = T.FontCaption,
                    fontColor = ai.active and T.Success or T.Danger,
                },
            }
        })
    end

    -- 当前溢价率
    local _, premiumRate = LA.CheckCircuitBreaker(land, s.currentPrice)
    local premiumPct = math.floor(premiumRate * 100)
    local premiumColor = T.Success
    if premiumPct >= 20 then premiumColor = T.Warning end
    if premiumPct >= 30 then premiumColor = T.Danger end

    -- ========================================================================
    -- 组装最终UI (使用 table.insert 避免 nil-hole)
    -- ========================================================================
    local pageChildren = {}

    -- 返回按钮 + 标题
    local titleChildren = {
        C.SecondaryButton {
            text = "< 返回",
            height = 30,
            paddingH = 12,
            onClick = function()
                M._state = nil
                navigate("invest")
            end,
        },
    }
    if s.isJudicial then
        table.insert(titleChildren, C.Badge {text = "法拍", variant = "warning"})
    end
    table.insert(titleChildren, UI.Label {text = "土地竞拍会", fontSize = T.FontTitle, fontColor = T.TextPrimary})
    if not s.sealedBidMode then
        table.insert(titleChildren, UI.Label {
            text = "第" .. s.round .. "/" .. s.maxRounds .. "轮",
            fontSize = T.FontSmall,
            fontColor = T.TextMuted,
        })
    end
    if s.circuitBroken then
        table.insert(titleChildren, C.Badge {text = "已熔断", variant = "danger"})
    end
    table.insert(pageChildren, UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = titleChildren,
    })

    -- 地块信息 + 法拍专属信息
    local landInfoChildren = {
        UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            width = "100%",
            children = {
                UI.Label {text = land.id .. " | " .. land.city .. " · " .. land.location, fontSize = T.FontBody, fontColor = T.TextSecondary},
                C.Badge {text = land.useType, variant = "accent"},
            }
        },
        UI.Panel {
            flexDirection = "row",
            gap = 10,
            width = "100%",
            children = {
                UI.Label {text = "建面 " .. string.format("%.1f万平", land.buildArea/10000), fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = "容积率 " .. land.far, fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = "起拍 " .. C.FormatMoney(land.startPrice), fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = "上限 " .. C.FormatMoney(s.priceCap), fontSize = T.FontSmall, fontColor = T.Warning},
            }
        },
    }
    -- 法拍专属: 法院信息 + 风险提示
    if s.isJudicial and land.channelData then
        local cd = land.channelData
        table.insert(landInfoChildren, UI.Panel {
            width = "100%",
            backgroundColor = T.WarningBg,
            borderRadius = 4,
            padding = 6,
            marginTop = 4,
            gap = 2,
            children = {
                UI.Label {
                    text = "法院: " .. (cd.courtName or "未知") .. " | 案号: " .. (cd.caseNumber or "未知"),
                    fontSize = T.FontCaption,
                    fontColor = T.Warning,
                },
                UI.Label {
                    text = "拍卖轮次: " .. (cd.auctionRound == 1 and "首拍" or "二拍") .. " | 折扣: " .. (cd.judicialDiscount or 0) .. "%",
                    fontSize = T.FontCaption,
                    fontColor = T.Warning,
                },
                UI.Label {
                    text = "⚠ 法拍地块可能存在抵押/纠纷/污染等隐性风险",
                    fontSize = T.FontCaption,
                    fontColor = T.Danger,
                },
            }
        })
    end
    -- 溢价率指示
    table.insert(landInfoChildren, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        width = "100%",
        marginTop = 4,
        children = {
            UI.Label {text = "溢价率", fontSize = T.FontSmall, fontColor = T.TextMuted},
            UI.Label {
                text = premiumPct .. "% / " .. math.floor(LA.CIRCUIT_BREAKER_PREMIUM * 100) .. "% 熔断线",
                fontSize = T.FontSmall,
                fontColor = premiumColor,
            },
        }
    })
    -- 溢价进度条
    local barFill = math.min(1.0, premiumRate / LA.CIRCUIT_BREAKER_PREMIUM)
    table.insert(landInfoChildren, UI.Panel {
        width = "100%",
        height = 6,
        backgroundColor = T.CardBorder,
        borderRadius = 3,
        children = {
            UI.Panel {
                width = math.floor(barFill * 100) .. "%",
                height = "100%",
                backgroundColor = premiumColor,
                borderRadius = 3,
            },
        }
    })
    table.insert(pageChildren, C.Card {children = landInfoChildren})

    -- ========================================================================
    -- 密封报价模式 UI
    -- ========================================================================
    if s.sealedBidMode and not s.finished then
        local minSealedBid = s.currentPrice + s.increment
        local sealedOptions = {}
        -- 提供3个报价档位: 保守/平衡/激进
        local sealedBids = {
            { label = "保守", amount = math.floor(minSealedBid * 1.00) },
            { label = "平衡", amount = math.floor(minSealedBid * 1.10) },
            { label = "激进", amount = math.floor(minSealedBid * 1.25) },
        }
        for _, opt in ipairs(sealedBids) do
            local canAfford = GD.company.cash >= opt.amount
            local underCap = opt.amount <= s.priceCap
            table.insert(sealedOptions, C.ActionButton {
                text = opt.label .. " " .. C.FormatMoney(opt.amount),
                height = 42,
                paddingH = 14,
                disabled = not canAfford or not underCap,
                onClick = function()
                    M.SubmitSealedBid(opt.amount, navigate)
                end,
            })
        end

        table.insert(pageChildren, C.Card {
            children = {
                C.SectionTitle {text = "密封报价 (一次性出价)"},
                UI.Label {
                    text = "熔断已触发！所有竞拍者同时提交最终报价，最高价者获胜。",
                    fontSize = T.FontSmall,
                    fontColor = T.Warning,
                    marginBottom = 6,
                },
                UI.Label {
                    text = "当前价格基准: " .. C.FormatMoney(s.currentPrice) .. " | 最低报价: " .. C.FormatMoney(minSealedBid),
                    fontSize = T.FontSmall,
                    fontColor = T.TextSecondary,
                    marginBottom = 8,
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 8,
                    width = "100%",
                    flexWrap = "wrap",
                    children = sealedOptions,
                },
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    width = "100%",
                    marginTop = 10,
                    children = {
                        C.SecondaryButton {
                            text = "放弃竞拍",
                            onClick = function()
                                M._state = nil
                                GD.AddEvent("熔断后放弃竞拍 " .. land.location .. " 地块", "info")
                                navigate("invest")
                            end,
                        },
                    }
                },
            }
        })

    -- ========================================================================
    -- 密封报价结果展示
    -- ========================================================================
    elseif s.sealedResult and s.finished then
        local resultChildren = {
            C.SectionTitle {text = "密封报价结果"},
        }
        for i, b in ipairs(s.sealedResult.allBids) do
            local name = b.name == "__player__" and GD.company.name or b.name
            local isWinner = i == 1
            table.insert(resultChildren, UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                width = "100%",
                padding = 6,
                backgroundColor = isWinner and T.SuccessBg or nil,
                borderRadius = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 6, alignItems = "center",
                        children = {
                            UI.Label {text = "#" .. i, fontSize = T.FontSmall, fontColor = T.TextMuted, width = 20},
                            UI.Label {text = name, fontSize = T.FontBody, fontColor = isWinner and T.Success or T.TextPrimary},
                            isWinner and C.Badge {text = "最高", variant = "success"} or nil,
                        }
                    },
                    UI.Label {
                        text = C.FormatMoney(b.bid),
                        fontSize = T.FontBody,
                        fontColor = isWinner and T.Success or T.TextSecondary,
                    },
                }
            })
        end
        table.insert(pageChildren, C.Card {children = resultChildren})

    -- ========================================================================
    -- 普通竞拍模式：最高出价 + 出价按钮
    -- ========================================================================
    else
        -- 当前最高出价
        local priceCardChildren = {
            UI.Label {text = "当前最高出价", fontSize = T.FontSmall, fontColor = T.TextSecondary, textAlign = "center", width = "100%"},
            UI.Label {
                text = C.FormatMoney(s.currentPrice),
                fontSize = T.FontHuge,
                fontColor = s.won and T.Success or T.Accent,
                textAlign = "center",
                width = "100%",
            },
            UI.Label {
                text = "出价方: " .. s.highestBidder,
                fontSize = T.FontBody,
                fontColor = s.highestBidder == GD.company.name and T.Accent or T.TextSecondary,
                textAlign = "center",
                width = "100%",
            },
        }
        -- 联合拿地时显示费用分担
        if s.jointBid then
            table.insert(priceCardChildren, UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                gap = 12,
                width = "100%",
                marginTop = 4,
                children = {
                    C.Badge {text = "联合拿地", variant = "accent"},
                    UI.Label {
                        text = "你 " .. (100 - s.jointBid.partnerSharePct) .. "% | " .. s.jointBid.partnerName .. " " .. s.jointBid.partnerSharePct .. "%",
                        fontSize = T.FontSmall,
                        fontColor = T.Info,
                    },
                }
            })
        end
        if s.finished then
            if s.won then
                local finishText = "恭喜！竞拍成功！请确认收购或反悔"
                table.insert(priceCardChildren, UI.Label {
                    text = finishText,
                    fontSize = T.FontSubtitle,
                    fontColor = T.Success,
                    textAlign = "center",
                    width = "100%",
                    marginTop = 8,
                })
                -- 联合拿地费用明细
                if s.jointBidShares then
                    local sh = s.jointBidShares
                    table.insert(priceCardChildren, UI.Panel {
                        width = "100%",
                        backgroundColor = T.SuccessBg,
                        borderRadius = 4,
                        padding = 8,
                        marginTop = 6,
                        gap = 4,
                        children = {
                            C.InfoRow {label = "总成交价", value = C.FormatMoney(sh.playerCost + sh.partnerCost)},
                            C.InfoRow {label = GD.company.name .. " (" .. sh.playerSharePct .. "%)", value = C.FormatMoney(sh.playerCost)},
                            C.InfoRow {label = sh.partnerName .. " (" .. sh.partnerSharePct .. "%)", value = C.FormatMoney(sh.partnerCost)},
                        }
                    })
                end
            else
                table.insert(priceCardChildren, UI.Label {
                    text = "竞拍结束 - " .. s.highestBidder .. " 竞得",
                    fontSize = T.FontSubtitle,
                    fontColor = T.Danger,
                    textAlign = "center",
                    width = "100%",
                    marginTop = 8,
                })
            end
        end
        table.insert(pageChildren, C.Card {children = priceCardChildren})

        -- ==============================================================
        -- 联合拿地: 合作伙伴选择面板 (仅竞拍进行中且尚未选择伙伴)
        -- ==============================================================
        if not s.finished and not s.jointBid and s.availablePartners and #s.availablePartners > 0 then
            local partnerCards = {}
            for _, p in ipairs(s.availablePartners) do
                table.insert(partnerCards, UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    padding = 8,
                    backgroundColor = T.InfoBg,
                    borderRadius = 4,
                    children = {
                        UI.Panel {
                            gap = 2,
                            flexGrow = 1,
                            flexBasis = 0,
                            children = {
                                UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                                UI.Label {
                                    text = "出资 " .. math.floor(p.shareRatio) .. "% | 合作意愿 " .. math.floor(p.willingness * 100) .. "%",
                                    fontSize = T.FontCaption,
                                    fontColor = T.TextMuted,
                                },
                            }
                        },
                        C.SecondaryButton {
                            text = "选择合作",
                            height = 28,
                            paddingH = 10,
                            onClick = function()
                                s.jointBid = { partnerName = p.name, partnerSharePct = math.floor(p.shareRatio) }
                                table.insert(s.log, 1, {
                                    bidder = "系统",
                                    text = "已选择 " .. p.name .. " 作为联合拿地伙伴（出资" .. math.floor(p.shareRatio) .. "%）",
                                })
                                navigate("auction")
                            end,
                        },
                    }
                })
            end
            table.insert(pageChildren, C.Card {
                children = {
                    C.SectionTitle {text = "联合拿地 (可选)"},
                    UI.Label {
                        text = "选择合作伙伴共同出资，降低资金压力。合作方将按出资比例分享利润。",
                        fontSize = T.FontSmall,
                        fontColor = T.TextSecondary,
                        marginBottom = 6,
                    },
                    UI.Panel {gap = 6, width = "100%", children = partnerCards},
                }
            })
        end

        -- 已选择联合拿地伙伴时显示提示
        if not s.finished and s.jointBid then
            table.insert(pageChildren, UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                width = "100%",
                backgroundColor = T.SuccessBg,
                borderRadius = 6,
                padding = 8,
                children = {
                    C.Badge {text = "联合拿地", variant = "success"},
                    UI.Label {
                        text = "与 " .. s.jointBid.partnerName .. " 合作（对方出资" .. s.jointBid.partnerSharePct .. "%）",
                        fontSize = T.FontSmall,
                        fontColor = T.Success,
                        flexGrow = 1,
                        flexBasis = 0,
                    },
                    C.SecondaryButton {
                        text = "取消",
                        height = 26,
                        paddingH = 8,
                        onClick = function()
                            table.insert(s.log, 1, {
                                bidder = "系统",
                                text = "已取消与 " .. s.jointBid.partnerName .. " 的联合拿地",
                            })
                            s.jointBid = nil
                            navigate("auction")
                        end,
                    },
                }
            })
        end

        -- 出价区域 (仅竞拍进行中)
        if not s.finished then
            local isMyTurn = s.highestBidder ~= GD.company.name
            local increments = {s.increment, s.increment * 2, s.increment * 3}
            local bidOptions = {}
            for _, inc in ipairs(increments) do
                local newPrice = isMyTurn and (s.currentPrice + inc) or s.currentPrice
                local playerCost = newPrice
                if s.jointBid then
                    playerCost = math.floor(newPrice * (100 - (s.jointBid.partnerSharePct or 0)) / 100)
                end
                local canAfford = GD.company.cash >= playerCost
                local underCap = newPrice <= s.priceCap
                table.insert(bidOptions, C.ActionButton {
                    text = isMyTurn and ("+" .. C.FormatMoney(inc) .. " (" .. C.FormatMoney(newPrice) .. ")") or "推进AI响应",
                    height = 38,
                    paddingH = 10,
                    disabled = not canAfford or not underCap,
                    onClick = function()
                        M.PlayerBid(newPrice, navigate)
                    end,
                })
            end

            local bidCardChildren = {
                C.SectionTitle {text = "出价 (加价幅度 " .. C.FormatMoney(s.increment) .. "起)"},
            }
            -- 状态提示
            local statusHint
            if s.highestBidder == GD.company.name then
                statusHint = "你是当前最高出价方，点击任意加价按钮将触发下一轮AI响应"
            elseif s.highestBidder == "起拍" then
                statusHint = "竞拍开始，请出价！"
            else
                statusHint = s.highestBidder .. " 领先，请加价或放弃"
            end
            table.insert(bidCardChildren, UI.Label {
                text = statusHint,
                fontSize = T.FontSmall,
                fontColor = T.Info,
                marginBottom = 4,
            })
            table.insert(bidCardChildren, UI.Panel {
                flexDirection = "row",
                gap = 8,
                width = "100%",
                flexWrap = "wrap",
                children = bidOptions,
            })
            table.insert(bidCardChildren, UI.Panel {
                flexDirection = "row",
                justifyContent = "flex-end",
                width = "100%",
                marginTop = 8,
                children = {
                    C.SecondaryButton {
                        text = "放弃竞拍",
                        onClick = function()
                            M._state = nil
                            GD.AddEvent("放弃竞拍 " .. land.location .. " 地块", "info")
                            navigate("invest")
                        end,
                    },
                }
            })
            table.insert(pageChildren, C.Card {children = bidCardChildren})
        end
    end

    -- 参与者
    local participantChildren = {
        C.SectionTitle {text = "竞拍参与者"},
        UI.Panel {
            flexDirection = "row",
            gap = 6,
            alignItems = "center",
            children = {
                UI.Panel {width=8, height=8, backgroundColor=T.Accent, borderRadius=4},
                UI.Label {text = GD.company.name .. " (你)", fontSize = T.FontSmall, fontColor = T.Accent},
                UI.Label {text = "资金 " .. C.FormatMoney(GD.company.cash), fontSize = T.FontCaption, fontColor = T.TextMuted},
            }
        },
    }
    -- 联合拿地伙伴标注
    if s.jointBid then
        table.insert(participantChildren, UI.Panel {
            flexDirection = "row",
            gap = 6,
            alignItems = "center",
            marginLeft = 14,
            children = {
                UI.Label {text = "└ 合作:", fontSize = T.FontCaption, fontColor = T.TextMuted},
                UI.Label {text = s.jointBid.partnerName, fontSize = T.FontSmall, fontColor = T.Success},
                UI.Label {text = "(" .. s.jointBid.partnerSharePct .. "%出资)", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }
        })
    end
    table.insert(participantChildren, UI.Panel {gap = 4, width = "100%", children = aiCards})
    table.insert(pageChildren, C.Card {children = participantChildren})

    -- 竞拍完成后按钮
    if s.finished then
        if s.won and not s.forfeited then
            -- 计算反悔罚金
            local penalty, penaltyMsg = LA.CalcForfeitPenalty(s.land, s.myLastBid)
            local confirmChildren = {
                C.SectionTitle {text = "竞拍结果确认"},
                UI.Label {
                    text = "你已竞得该地块，请选择：",
                    fontSize = T.FontBody,
                    fontColor = T.TextSecondary,
                    marginBottom = 8,
                },
            }
            -- 联合拿地费用提醒
            if s.jointBidShares then
                table.insert(confirmChildren, UI.Label {
                    text = "你的实际出资: " .. C.FormatMoney(s.jointBidShares.playerCost) .. " (" .. s.jointBidShares.playerSharePct .. "%)",
                    fontSize = T.FontSmall,
                    fontColor = T.Info,
                    marginBottom = 6,
                })
            end
            table.insert(confirmChildren, UI.Label {
                text = "确认后地块将进入土地储备，可在储备页面选择开发类型并启动开发。",
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                marginBottom = 8,
            })
            table.insert(confirmChildren, UI.Panel {
                flexDirection = "row",
                gap = 10,
                width = "100%",
                justifyContent = "center",
                children = {
                    C.ActionButton {
                        text = "确认收购",
                        height = 42,
                        paddingH = 16,
                        onClick = function()
                            M.ConfirmAcquisition(navigate)
                        end,
                    },
                    C.SecondaryButton {
                        text = "反悔 (罚金" .. C.FormatMoney(penalty) .. ")",
                        height = 42,
                        paddingH = 16,
                        onClick = function()
                            M.ForfeitAuction(navigate)
                        end,
                    },
                }
            })
            table.insert(confirmChildren, UI.Label {
                text = "反悔将损失保证金+违约金共" .. C.FormatMoney(penalty) .. "，地块退回市场",
                fontSize = T.FontCaption,
                fontColor = T.Danger,
                textAlign = "center",
                width = "100%",
                marginTop = 6,
            })
            table.insert(pageChildren, C.Card {children = confirmChildren})
        else
            -- 未竞得或已反悔：返回按钮
            table.insert(pageChildren, UI.Panel {
                width = "100%",
                alignItems = "center",
                children = {
                    C.ActionButton {
                        text = "返回投资中心",
                        width = "60%",
                        onClick = function()
                            M._state = nil
                            navigate("invest")
                        end,
                    },
                }
            })
        end
    end

    -- 竞拍日志
    table.insert(pageChildren, C.Card {
        children = {
            C.SectionTitle {text = "竞拍记录"},
            UI.Panel {width = "100%", gap = 0, children = logItems},
        }
    })

    table.insert(pageChildren, UI.Panel {height = 20})

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 12,
        children = pageChildren,
    }
end

return M
