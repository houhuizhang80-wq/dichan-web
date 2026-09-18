---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- SalesScreen.lua - 第五层: 营销销售(5-Tab 重写)
-- Tab1: 定价开盘  Tab2: 营销蓄客  Tab3: 渠道管理  Tab4: 签约回款  Tab5: 客户服务
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local MK = GD.Marketing

local M = {}
M._selectedProject = 1
M._activeTab = 1
M._expandedLists = M._expandedLists or {}

-- ============================================================================
-- 辅助: 通过id在常量表中查找
-- ============================================================================
local function FindById(tbl, id)
    for _, item in ipairs(tbl) do
        if item.id == id then return item end
    end
    return tbl[1]
end

-- ============================================================================
-- 辅助: 选项按钮行
-- ============================================================================
local function OptionButtons(options, currentId, labelFn, onSelect)
    local btns = {}
    for _, opt in ipairs(options) do
        local sel = (opt.id == currentId)
        table.insert(btns, UI.Button {
            text = labelFn(opt),
            fontSize = T.FontSmall,
            backgroundColor = sel and T.PrimaryLight or T.BgInput,
            fontColor = sel and T.Primary or T.TextPrimary,
            borderRadius = 6,
            paddingHorizontal = 10,
            height = 30,
            onClick = function() onSelect(opt.id) end,
        })
    end
    return UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = btns}
end

-- ============================================================================
-- Tab1: 定价开盘
-- ============================================================================
local function BuildPricingTab(p, s, mk, navigate)
    local city = GD.GetCityData(p.land and p.land.city or nil)
    local DT0 = require("DevTypes")
    local typeDef0 = DT0.TYPES[p.devTypeId]
    -- 建议开盘价：锚定城市房价与产品类型，利润率由土地价格侧控制
    local tgtMargin = typeDef0 and typeDef0.targetMargin or 0.35
    local floorPrice = p.land and p.land.floorPrice or 0
    local suggestPrice = math.floor(DT0.GetExpectedPrice(
        p.devTypeId,
        city.avgPrice,
        p.plotLocation or (p.land and p.land.plotLocation) or "suburb",
        p.standardId or "basic",
        floorPrice
    ) * (GD.economy.priceIndex / 100))
    local goRate = s.totalUnits > 0 and math.floor(s.soldUnits / s.totalUnits * 100) or 0

    -- 定价区域：已定价后锁定，不再随市场变动
    local priceAlreadySet = (s.basePrice > 0)
    local pricingCardChildren = {
        C.SectionTitle {text = "定价策略"},
        C.InfoRow {label = "产品基准价", value = suggestPrice .. " 元/平"},
        UI.Panel {height = 4},
    }

    if priceAlreadySet then
        -- ======== 已定价：显示锁定价格，不再显示市场按钮 ========
        local diffPct = math.floor((s.basePrice / suggestPrice - 1) * 100)
        local diffStr = diffPct == 0 and "与基准持平" or (diffPct > 0 and ("高于基准" .. diffPct .. "%") or ("低于基准" .. math.abs(diffPct) .. "%"))
        local approvedPrice = tonumber(s.approvedOpeningPrice) or 0
        if approvedPrice <= 0 then approvedPrice = s.basePrice end
        table.insert(pricingCardChildren, C.InfoRow {label = "批准开盘价（速度基准）", value = approvedPrice .. " 元/平", color = T.Success})
        table.insert(pricingCardChildren, C.InfoRow {label = "当前售价", value = s.basePrice .. " 元/平", color = T.Accent})
        table.insert(pricingCardChildren, C.InfoRow {label = "目标利润率", value = math.floor(tgtMargin * 100) .. "%", color = T.Info})
        table.insert(pricingCardChildren, UI.Label {text = diffStr .. "  |  可直接涨价或降价调整", fontSize = T.FontCaption, fontColor = T.TextMuted})
    else
        -- ======== 未定价：显示基于市场均价的定价按钮 ========
        table.insert(pricingCardChildren, UI.Label {text = "选择定价:", fontSize = T.FontSmall, fontColor = T.TextSecondary})
        local priceMultipliers = {0.85, 0.90, 1.0, 1.10, 1.20}
        local priceBtns = {}
        for _, mult in ipairs(priceMultipliers) do
            local price = math.floor(suggestPrice * mult)
            local diff = math.floor((mult - 1) * 100)
            local label = price .. "元/平"
            if diff ~= 0 then label = label .. " (" .. (diff > 0 and "+" or "") .. diff .. "%)" end
            table.insert(priceBtns, UI.Button {
                text = label, fontSize = T.FontSmall,
                backgroundColor = T.BgInput,
                fontColor = T.TextPrimary,
                borderRadius = 6, paddingHorizontal = 10, height = 30,
                onClick = function()
                    s.basePrice = price
                    if (s.packageBasePrice or 0) <= 0 then
                        s.packageBasePrice = price
                    end
                    -- 记录批准开盘价（涨价控制基准）- 开盘前可自由改价，始终同步
                    s.approvedOpeningPrice = price
                    GD.AddEvent("【" .. p.name .. "】定价 " .. price .. " 元/平（已锁定）", "info")
                    navigate("sales")
                end,
            })
        end
        table.insert(pricingCardChildren, UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = priceBtns})
    end

    -- 申请调价区域（仅已定价后显示）
    local repriceChildren = {}
    if priceAlreadySet then
        table.insert(repriceChildren, C.SectionTitle {text = "调价"})
        local downPrice = math.floor(s.basePrice * 0.95)
        local upPrice = math.floor(s.basePrice * 1.05)

        -- 以批准开盘价计算实际档位；价格超过50%才停售，回调后自动恢复。
        local priceState = MK.GetPriceSpeedState(s)
        local currentIncrease = priceState.delta
        local pctStr = string.format("%.1f%%", currentIncrease * 100)
        local statusText = "当前相对批准开盘价 " .. pctStr
        local statusColor = T.TextMuted
        if priceState.blocked then
            statusText = statusText .. "，超过+50%，已停止销售"
            statusColor = T.Danger
        elseif priceState.steps > 0 then
            local directionText = currentIncrease > 0 and "涨价" or "降价"
            statusText = statusText .. "，" .. directionText .. "速度档" .. priceState.steps
                .. "，销售速度×" .. string.format("%.2f", priceState.multiplier)
            statusColor = currentIncrease > 0 and T.Warning or T.Success
        end
        table.insert(repriceChildren, UI.Label {text = statusText, fontSize = T.FontCaption, fontColor = statusColor, marginBottom = 4})
        table.insert(repriceChildren, UI.Label {text = "每涨5%速度×0.80；每降5%速度×1.20；涨价超过50%停售", fontSize = T.FontCaption, fontColor = T.TextMuted})
        table.insert(repriceChildren, UI.Panel {flexDirection = "column", gap = 8, marginTop = 4, children = {
            C.ActionButton {
                text = "涨价5% → " .. upPrice .. "元/平",
                onClick = function()
                    MK.RequestReprice(p, upPrice, GD, "up")
                    navigate("sales")
                end,
            },
            C.ActionButton {
                text = "降价5% → " .. downPrice .. "元/平",
                onClick = function()
                    MK.RequestReprice(p, downPrice, GD, "down")
                    navigate("sales")
                end,
            },
        }})
        -- 价格历史
        if #mk.pricing.priceHistory > 0 then
            table.insert(repriceChildren, UI.Panel {height = 4})
            for i = #mk.pricing.priceHistory, math.max(1, #mk.pricing.priceHistory - 2), -1 do
                local h = mk.pricing.priceHistory[i]
                table.insert(repriceChildren, C.InfoRow {
                    label = "第" .. (h.month or 0) .. "月",
                    value = (h.price or 0) .. "元/平 " .. (h.reason or ""),
                    color = T.TextMuted,
                })
            end
        end
    end

    -- 开盘方式
    local openingChildren = {
        C.SectionTitle {text = "开盘方式"},
    }
    if mk.opening.opened then
        local opt = FindById(MK.OPENING_METHODS, mk.opening.method)
        table.insert(openingChildren, C.InfoRow {label = "已选方式", value = opt.name, color = T.Success})
        table.insert(openingChildren, C.InfoRow {label = "转化率加成", value = "+" .. math.floor(opt.convBonus * 100) .. "%"})
        -- 黄牛
        if mk.opening.usedScalper then
            if mk.opening.scalperExposed then
                table.insert(openingChildren, C.Badge {text = "黄牛已曝光! 声誉-20", variant = "danger"})
            else
                table.insert(openingChildren, C.Badge {text = "黄牛暗箱进行中...", variant = "warning"})
            end
        elseif not mk.opening.scalperExposed then
            table.insert(openingChildren, C.SecondaryButton {
                text = "雇黄牛(+15%销量, 25%曝光风险)",
                onClick = function()
                    MK.HireScalper(p, GD)
                    navigate("sales")
                end,
            })
        end
    else
        for _, opt in ipairs(MK.OPENING_METHODS) do
            table.insert(openingChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                width = "100%", padding = 8, backgroundColor = T.BgInput, borderRadius = 6,
                children = {
                    UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, children = {
                        UI.Label {text = opt.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        UI.Label {text = opt.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    C.ActionButton {
                        text = "选择",
                        onClick = function()
                            MK.SetOpeningMethod(p, opt.id, GD)
                            navigate("sales")
                        end,
                    },
                },
            })
        end
    end

    -- 折扣体系
    local discountChildren = {
        C.SectionTitle {text = "折扣体系"},
        C.InfoRow {label = "综合折扣", value = string.format("%.0f折", mk.pricing.effectiveDiscount * 100), color = T.Accent},
    }
    for _, dt in ipairs(MK.DISCOUNT_TYPES) do
        local enabled = mk.pricing.discountsEnabled[dt.id]
        local label = dt.name
        if dt.id == "gm_special" then
            label = label .. " (" .. math.floor(mk.pricing.gmSpecialRate * 100) .. "折)"
        else
            label = label .. " (" .. math.floor(dt.rate * 100) .. "折)"
        end
        table.insert(discountChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%", paddingVertical = 4,
            children = {
                UI.Label {text = label, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                UI.Button {
                    text = enabled and "已启用" or "启用",
                    fontSize = T.FontCaption,
                    backgroundColor = enabled and T.Success or T.BgInput,
                    fontColor = enabled and T.TextPrimary or T.TextSecondary,
                    borderRadius = 6, paddingHorizontal = 10, height = 24,
                    onClick = function()
                        MK.ToggleDiscount(p, dt.id, not enabled)
                        navigate("sales")
                    end,
                },
            },
        })
    end

    -- 销售数据
    local salesDataChildren = {
        C.SectionTitle {text = "销售数据"},
        UI.Panel {flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "可售套数", value = s.totalUnits .. "套", minWidth = 80},
            C.StatCard {title = "已售", value = s.soldUnits .. "套", color = T.Success, minWidth = 80},
            C.StatCard {title = "去化率", value = goRate .. "%", color = goRate > 60 and T.Success or T.Warning, minWidth = 80},
        }},
    }
    if p.unitPlan.holdUnits > 0 and not p._fixedAssetConverted then
        table.insert(salesDataChildren, C.InfoRow {label = "自持套数(不参与销售)", value = p.unitPlan.holdUnits .. "套", color = T.TextMuted})
    end

    return UI.Panel {width = "100%", gap = 10, children = {
        C.Card {children = pricingCardChildren},
        #repriceChildren > 0 and C.Card {children = repriceChildren} or nil,
        C.Card {children = openingChildren},
        C.Card {children = discountChildren},
        C.Card {children = salesDataChildren},
        C.Card {children = {
            C.SectionTitle {text = "月度数据"},
            C.InfoRow {label = "月来访量", value = s.monthlyVisits .. "组"},
            C.InfoRow {label = "转化率", value = string.format("%.1f%%", s.conversionRate * 100)},
            C.InfoRow {label = "累计回款", value = C.FormatMoney(s.revenue), color = T.Success},
            C.InfoRow {label = "累计营销支出", value = C.FormatMoney(s.totalMarketingCost or 0), color = T.Warning},
        }},
        C.ProgressCard {title = "整体去化进度", progress = goRate, barColor = T.Accent},
    }}
end

-- ============================================================================
-- Tab2: 营销蓄客
-- ============================================================================
local function BuildAccumulationTab(p, s, mk, navigate)
    local acc = mk.accumulation

    return UI.Panel {width = "100%", gap = 10, children = {
        -- 蓄客状态
        C.Card {children = {
            C.SectionTitle {text = "蓄客状态"},
            C.InfoRow {label = "蓄客月数", value = acc.accumulationMonths .. "个月"},
            C.InfoRow {label = "认筹人数", value = acc.subscribers .. "组"},
            C.InfoRow {label = "认筹比", value = s.totalUnits > 0 and string.format("%.2f", acc.subscribers / s.totalUnits) or "0.00",
                color = (acc.subscribers / math.max(1, s.totalUnits)) >= 1 and T.Success or T.Warning},
            UI.Label {text = "认筹比≥1.0为健康，<1.0说明定价可能过高", fontSize = T.FontCaption, fontColor = T.TextMuted},
        }},
        -- 城市展厅
        C.Card {children = {
            C.SectionTitle {text = "城市展厅"},
            C.InfoRow {label = "当前展厅", value = FindById(MK.SHOWROOM_OPTIONS, acc.showroom).name, color = T.Accent},
            C.InfoRow {label = "展厅累计投入", value = C.FormatMoney(acc.showroomCost), color = T.TextMuted},
            UI.Panel {height = 4},
            OptionButtons(MK.SHOWROOM_OPTIONS, acc.showroom, function(opt)
                return opt.cost > 0 and (opt.name .. " " .. opt.cost .. "万") or opt.name
            end, function(id)
                local ok, msg = MK.SetShowroom(p, id)
                if ok then GD.AddEvent("【" .. p.name .. "】" .. msg, "info") end
                navigate("sales")
            end),
        }},
        -- 媒体广告
        C.Card {children = {
            C.SectionTitle {text = "媒体广告"},
            C.InfoRow {label = "当前投放", value = FindById(MK.MEDIA_AD_LEVELS, acc.mediaAdLevel).name, color = T.Accent},
            UI.Panel {height = 4},
            OptionButtons(MK.MEDIA_AD_LEVELS, acc.mediaAdLevel, function(opt)
                return opt.monthlyCost > 0 and (opt.name .. " " .. opt.monthlyCost .. "万/月") or opt.name
            end, function(id)
                local ok, msg = MK.SetMediaAd(p, id)
                if ok then GD.AddEvent("【" .. p.name .. "】" .. msg, "info") end
                navigate("sales")
            end),
        }},
        -- 自媒体运营
        C.Card {children = {
            C.SectionTitle {text = "自媒体运营"},
            C.InfoRow {label = "当前级别", value = FindById(MK.SELF_MEDIA_OPTIONS, acc.selfMediaLevel).name, color = T.Accent},
            UI.Panel {height = 4},
            OptionButtons(MK.SELF_MEDIA_OPTIONS, acc.selfMediaLevel, function(opt)
                return opt.monthlyCost > 0 and (opt.name .. " " .. opt.monthlyCost .. "万/月") or opt.name
            end, function(id)
                local ok, msg = MK.SetSelfMedia(p, id)
                if ok then GD.AddEvent("【" .. p.name .. "】" .. msg, "info") end
                navigate("sales")
            end),
        }},
        -- 验资门槛
        C.Card {children = {
            C.SectionTitle {text = "验资门槛"},
            C.InfoRow {label = "当前门槛", value = FindById(MK.DEPOSIT_THRESHOLDS, acc.depositThreshold).name, color = T.Accent},
            UI.Label {text = "门槛越高诚意越强(转化高)，但客户量减少", fontSize = T.FontCaption, fontColor = T.TextMuted},
            UI.Panel {height = 4},
            OptionButtons(MK.DEPOSIT_THRESHOLDS, acc.depositThreshold, function(opt)
                return opt.amount > 0 and (opt.name .. " (诚意" .. math.floor(opt.sincerity * 100) .. "%)") or opt.name
            end, function(id)
                local ok, msg = MK.SetDepositThreshold(p, id)
                if ok then GD.AddEvent("【" .. p.name .. "】" .. msg, "info") end
                navigate("sales")
            end),
        }},
    }}
end

-- ============================================================================
-- Tab3: 渠道管理
-- ============================================================================
local function BuildChannelTab(p, s, mk, navigate)
    local ch = s.activeChannels or {}

    -- 渠道列表
    local channelKeys = {"selfSales", "agency", "distribution", "referral"}
    local cItems = {}
    for _, key in ipairs(channelKeys) do
        local detail = MK.CHANNEL_DETAILS[key]
        local isActive = ch[key]
        local commRate = mk.channels.currentCommissions[key] or detail.baseCommission

        local rowChildren = {
            UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, children = {
                UI.Label {text = detail.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                UI.Label {
                    text = detail.baseCommission > 0
                        and ("佣金" .. string.format("%.1f%%", commRate * 100) .. "  来访+" .. math.floor(detail.visitBonus * 100) .. "%")
                        or "无佣金成本",
                    fontSize = T.FontCaption, fontColor = T.TextMuted,
                },
            }},
        }
        -- 绑架提示
        if key == "distribution" and isActive and mk.channels.distributionMonths >= 6 then
            table.insert(rowChildren, C.Badge {text = "佣金上浮中", variant = "danger"})
        end

        if detail.canDisable then
            table.insert(rowChildren, UI.Button {
                text = isActive and "关闭" or "启用",
                fontSize = T.FontSmall,
                backgroundColor = isActive and T.Danger or T.Success,
                fontColor = T.TextOnDark,
                borderRadius = 6, paddingHorizontal = 12, height = 28,
                onClick = function()
                    GD.ToggleChannel(p, key, not isActive)
                    navigate("sales")
                end,
            })
        else
            table.insert(rowChildren, C.Badge {text = "默认启用", variant = "success"})
        end

        table.insert(cItems, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%", padding = 10,
            backgroundColor = isActive and T.BgCard or T.TabInactiveBg,
            borderRadius = 6, gap = 8,
            children = rowChildren,
        })
    end

    -- 营销预算
    local budgetOptions = {0, 50, 100, 200, 500}
    local budgetBtns = {}
    for _, b in ipairs(budgetOptions) do
        local isSel = (s.marketingBudget == b)
        table.insert(budgetBtns, UI.Button {
            text = b == 0 and "不投入" or (b .. "万/月"),
            fontSize = T.FontSmall,
            backgroundColor = isSel and T.PrimaryLight or T.BgInput,
            fontColor = isSel and T.Primary or T.TextSecondary,
            borderRadius = 6, paddingHorizontal = 10, height = 28,
            onClick = function()
                GD.SetMarketingBudget(p, b)
                navigate("sales")
            end,
        })
    end

    -- 促销活动
    local promoNames = {discount = "限时折扣", gift = "购房赠礼", event = "营销活动", none = "无"}
    local promoDescs = {
        none = "不开展促销活动",
        discount = "转化率+5%，持续3个月",
        gift = "来访+15%，转化率+3%，持续3个月",
        event = "来访+25%，持续3个月",
    }
    local promoOptions = {"none", "discount", "gift", "event"}
    local promoBtns = {}
    for _, pt in ipairs(promoOptions) do
        local isSel = (s.promotionType == pt)
        local btnLabel = promoNames[pt]
        if pt ~= "none" and isSel and s.promotionMonthsLeft > 0 then
            btnLabel = btnLabel .. "(" .. s.promotionMonthsLeft .. "月)"
        end
        table.insert(promoBtns, UI.Button {
            text = btnLabel, fontSize = T.FontSmall,
            backgroundColor = isSel and (pt == "none" and T.BgInput or T.PrimaryLight) or T.BgInput,
            fontColor = isSel and (pt == "none" and T.TextSecondary or T.Primary) or T.TextSecondary,
            borderRadius = 6, paddingHorizontal = 10, height = 28,
            onClick = function()
                GD.SetPromotion(p, pt, 3)
                navigate("sales")
            end,
        })
    end

    -- 绑架提醒
    local kidnappingChildren = {}
    if mk.channels.distributionMonths >= 6 then
        local delta = mk.channels.currentCommissions.distribution - MK.CHANNEL_DETAILS.distribution.baseCommission
        table.insert(kidnappingChildren, C.SectionTitle {text = "渠道绑架预警", color = T.Danger})
        table.insert(kidnappingChildren, C.InfoRow {
            label = "分销合作月数", value = mk.channels.distributionMonths .. "个月", color = T.Danger,
        })
        table.insert(kidnappingChildren, C.InfoRow {
            label = "佣金上浮", value = string.format("+%.1f%%", delta * 100), color = T.Danger,
        })
        table.insert(kidnappingChildren, UI.Label {
            text = "关闭分销渠道可重置佣金，但会损失来访量",
            fontSize = T.FontCaption, fontColor = T.Warning,
        })
    end

    local tabChildren = {
        C.Card {children = {
            C.SectionTitle {text = "销售渠道"},
            UI.Panel {width = "100%", gap = 6, children = cItems},
        }},
        C.Card {children = {
            C.SectionTitle {text = "营销预算"},
            C.InfoRow {label = "当前月预算", value = s.marketingBudget > 0 and (s.marketingBudget .. "万/月") or "未投入", color = s.marketingBudget > 0 and T.Accent or T.TextMuted},
            C.InfoRow {label = "效果", value = s.marketingBudget > 0 and ("来访量+" .. math.floor(s.marketingBudget / 100 * 10) .. "%") or "无加成", color = s.marketingBudget > 0 and T.Success or T.TextMuted},
            UI.Panel {height = 4},
            UI.Label {text = "设置月度预算:", fontSize = T.FontSmall, fontColor = T.TextSecondary},
            UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = budgetBtns},
        }},
        C.Card {children = {
            C.SectionTitle {text = "促销活动"},
            C.InfoRow {label = "当前活动", value = promoNames[s.promotionType] or "无", color = s.promotionType ~= "none" and T.Accent or T.TextMuted},
            UI.Label {text = promoDescs[s.promotionType] or "", fontSize = T.FontCaption, fontColor = T.TextMuted},
            UI.Panel {height = 4},
            UI.Label {text = "选择促销类型:", fontSize = T.FontSmall, fontColor = T.TextSecondary},
            UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = promoBtns},
        }},
    }
    if #kidnappingChildren > 0 then
        table.insert(tabChildren, C.Card {children = kidnappingChildren})
    end
    table.insert(tabChildren, C.Card {children = {
        C.SectionTitle {text = "费用统计"},
        C.InfoRow {label = "月营销预算", value = C.FormatMoney(s.marketingBudget), color = T.Warning},
        C.InfoRow {label = "累计营销支出", value = C.FormatMoney(s.totalMarketingCost or 0), color = T.Danger},
        C.InfoRow {label = "项目营销成本占比", value = p.cost.totalCost > 0 and (math.floor(p.cost.marketingCost / p.cost.totalCost * 100) .. "%") or "0%"},
    }})
    return UI.Panel {width = "100%", gap = 10, children = tabChildren}
end

-- ============================================================================
-- Tab4: 签约回款
-- ============================================================================
local function BuildCollectionTab(p, s, mk, navigate)
    local coll = mk.collection
    local bank = FindById(MK.BANKS, coll.selectedBank)

    -- 签约队列
    local queueChildren = {
        C.SectionTitle {text = "签约流水线"},
    }
    if #coll.signingQueue == 0 then
        table.insert(queueChildren, UI.Label {text = "暂无签约中的客户", fontSize = T.FontSmall, fontColor = T.TextMuted})
    else
        for i, batch in ipairs(coll.signingQueue) do
            local stage = MK.SIGN_STAGES[batch.stageIdx]
            local stageName = stage and stage.name or "已完成"
            table.insert(queueChildren, C.InfoRow {
                label = "批次" .. i .. " (" .. batch.unitCount .. "套)",
                value = stageName .. " " .. batch.elapsed .. "/" .. (stage and stage.durationMonths or 0) .. "月",
                color = T.Info,
            })
        end
    end

    -- 银行选择
    local bankChildren = {
        C.SectionTitle {text = "合作银行"},
    }
    for _, b in ipairs(MK.BANKS) do
        local sel = (b.id == coll.selectedBank)
        table.insert(bankChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%", padding = 8, backgroundColor = sel and T.PrimaryLight or T.BgInput,
            borderRadius = 6,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, children = {
                    UI.Label {text = b.name, fontSize = T.FontBody, fontColor = sel and T.Primary or T.TextPrimary},
                    UI.Label {
                        text = "利率" .. b.rate .. "% | 速度×" .. b.speedMult .. " | 额度" .. math.floor(b.quotaPct * 100) .. "%",
                        fontSize = T.FontCaption, fontColor = T.TextMuted,
                    },
                }},
                sel and C.Badge {text = "当前", variant = "success"} or UI.Button {
                    text = "选择", fontSize = T.FontCaption,
                    backgroundColor = T.BgCard, fontColor = T.TextSecondary,
                    borderRadius = 6, paddingHorizontal = 10, height = 24,
                    onClick = function()
                        MK.SelectBank(p, b.id)
                        navigate("sales")
                    end,
                },
            },
        })
    end

    -- 逾期催收
    local overdueChildren = {
        C.SectionTitle {text = "逾期催收"},
        C.InfoRow {label = "逾期客户", value = coll.overdueCount .. "组", color = coll.overdueCount > 0 and T.Danger or T.TextMuted},
        C.InfoRow {label = "已退房", value = coll.refundedUnits .. "套", color = T.TextMuted},
    }
    if coll.overdueCount > 0 then
        table.insert(overdueChildren, C.ActionButton {
            text = "催收(" .. math.floor(MK.OVERDUE_CHASE_SUCCESS * 100) .. "%成功率)",
            onClick = function()
                MK.ChaseOverdue(p, GD)
                navigate("sales")
            end,
        })
    end

    return UI.Panel {width = "100%", gap = 10, children = {
        C.Card {children = {
            C.SectionTitle {text = "回款概况"},
            UI.Panel {flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap", children = {
                C.StatCard {title = "累计回款", value = C.FormatMoney(coll.collectedAmount), color = T.Success, minWidth = 80},
                C.StatCard {title = "签约中", value = #coll.signingQueue .. "批", minWidth = 80},
                C.StatCard {title = "逾期", value = coll.overdueCount .. "组", color = coll.overdueCount > 0 and T.Danger or T.TextMuted, minWidth = 80},
            }},
        }},
        C.Card {children = queueChildren},
        C.Card {children = bankChildren},
        C.Card {children = overdueChildren},
    }}
end

-- ============================================================================
-- Tab5: 客户服务
-- ============================================================================
local function BuildServiceTab(p, s, navigate)
    local delivered = (p.status == "delivery" or p.status == "pending_settlement" or p.status == "pending_completion" or p.status == "completed")

    local deliveryChildren = {
        C.SectionTitle {text = "交付状态"},
        C.InfoRow {label = "项目状态", value = delivered and "可交付" or "建设中", color = delivered and T.Success or T.Info},
    }
    if delivered then
        table.insert(deliveryChildren, C.InfoRow {label = "待交付套数", value = s.soldUnits .. "套"})
    else
        table.insert(deliveryChildren, UI.Label {text = "项目竣工后方可交付", fontSize = T.FontSmall, fontColor = T.TextMuted})
    end

    -- 销售团队
    local teamCount = 0
    for _, emp in ipairs(GD.company.employees) do
        if emp.dept == "营销策划部" then teamCount = teamCount + 1 end
    end
    local teamChildren = {
        C.SectionTitle {text = "销售团队"},
        C.InfoRow {label = "营销人员", value = teamCount .. "人", color = teamCount > 0 and T.Success or T.TextMuted},
        C.InfoRow {label = "来访量加成", value = teamCount > 0 and ("+" .. (teamCount * 15) .. "%") or "无"},
        C.InfoRow {label = "转化率加成", value = teamCount > 0 and ("+" .. (teamCount * 2) .. "%") or "无"},
    }
    if teamCount == 0 then
        table.insert(teamChildren, UI.Label {text = "提示: 在人力资源中招聘营销策划部员工可提升效率", fontSize = T.FontCaption, fontColor = T.Warning, marginTop = 4})
    end

    return UI.Panel {width = "100%", gap = 10, children = {
        C.Card {children = deliveryChildren},
        C.Card {children = {
            C.SectionTitle {text = "客户满意度"},
            C.ProgressCard {
                title = "综合满意度",
                progress = math.min(100, math.max(0, p.construction.quality - 5)),
                barColor = p.construction.quality >= 80 and T.Success or T.Warning,
            },
        }},
        C.Card {children = teamChildren},
    }}
end

-- ============================================================================
-- 辅助: 获取项目销售状态标签
-- ============================================================================
local function GetSalesStatusTag(p)
    local priceState = MK.GetPriceSpeedState(p.sales)
    if priceState.blocked then
        return "涨价超过50%·已停售", T.Danger
    elseif p.sales.allUnitsSold then
        return "已售罄·待清盘", T.Danger
    elseif p.status == "completed" or p.status == "delivery" then
        if p.sales.isExistingHomeSale and p.sales.canSell then
            return "现房销售中", T.Success
        elseif p.sales.canSell then
            return "尾盘销售中", T.Success
        else
            return "已竣工", T.Warning
        end
    elseif p.status == "pending_settlement" or p.status == "pending_completion" then
        if p.sales.canSell then
            return "预售中·待结算", T.Warning
        else
            return "待结算", T.Warning
        end
    elseif p.sales.canSell then
        -- 只要开启了销售，无论项目处于什么阶段，都显示销售中
        if p.status == "presale" then
            return "预售中", T.Success
        else
            return "销售中", T.Success
        end
    elseif p.sales.canPresale then
        return "可开始预售", T.Warning
    elseif p.status == "construction" then
        return "施工中", T.Info
    else
        return "筹备中", T.TextMuted
    end
end

-- ============================================================================
-- 预售准备卡片（达到预售条件但尚未开始预售的项目）
-- ============================================================================
local function BuildPresaleReadyCard(p, navigate)
    local DT = require("DevTypes")
    local devType = DT.TYPES[p.devTypeId] or {name = "未知"}
    local buildProg = p.construction and p.construction.progress or 0
    local city = GD.GetCityData(p.land and p.land.city or nil)
    -- 建议售价：锚定城市房价与产品类型
    local floorPrice = p.land and p.land.floorPrice or 0
    local suggestPrice = math.floor(DT.GetExpectedPrice(
        p.devTypeId,
        city.avgPrice,
        p.plotLocation or (p.land and p.land.plotLocation) or "suburb",
        p.standardId or "basic",
        floorPrice
    ) * (GD.economy.priceIndex / 100))

    return C.Card {
        children = {
            -- 项目头
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                width = "100%",
                children = {
                    UI.Panel {gap = 2, flexShrink = 1, children = {
                        UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold"},
                        UI.Label {text = devType.name, fontSize = T.FontSmall, fontColor = T.TextMuted},
                    }},
                    C.Badge {text = "可开始预售", color = T.Warning},
                },
            },
            UI.Panel {height = 6},
            -- 关键信息
            C.InfoRow {label = "施工进度", value = math.floor(buildProg) .. "%", color = T.Info},
            C.InfoRow {label = "建筑面积", value = string.format("%.0f", p.land.buildArea or 0) .. " m²"},
            C.InfoRow {label = "建议售价", value = suggestPrice .. " 元/平", color = T.Accent},
            UI.Panel {height = 8},
            -- 开始预售按钮
            UI.Button {
                text = "开始预售",
                fontSize = T.FontBody,
                fontWeight = "bold",
                backgroundColor = T.Warning,
                fontColor = T.TextOnDark,
                borderRadius = 8,
                paddingHorizontal = 24,
                paddingVertical = 12,
                width = "100%",
                onClick = function()
                    local ok, msg = GD.StartPresale(p)
                    if ok then
                        GD.AddEvent("【" .. p.name .. "】开始预售!", "success")
                    else
                        GD.AddEvent(msg or "无法开始预售", "warning")
                    end
                    navigate("sales")
                end,
            },
            UI.Label {
                text = "点击后将自动完成定价和单元规划，正式进入预售阶段",
                fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 4,
            },
        },
    }
end

-- ============================================================================
-- 施工进度项目卡片（四证完成、尚未达到预售条件）
-- ============================================================================
local function BuildProgressCard(p, navigate)
    local statusText, statusColor = GetSalesStatusTag(p)
    local DT = require("DevTypes")
    local devType = DT.TYPES[p.devTypeId] or {name = "未知"}
    local buildProg = p.construction and p.construction.progress or 0
    local presaleHint = ""
    if devType.presaleThreshold then
        presaleHint = "施工进度达" .. math.floor(devType.presaleThreshold * 100) .. "%可预售"
    end

    return C.Card {
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {gap = 2, flexShrink = 1, children = {
                        UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold"},
                        UI.Label {text = devType.name, fontSize = T.FontSmall, fontColor = T.TextMuted},
                    }},
                    C.Badge {text = statusText, color = statusColor},
                },
            },
            UI.Panel {height = 6},
            C.ProgressCard {
                title = "施工进度", progress = math.floor(buildProg),
                barColor = buildProg >= 100 and T.Success or T.Info,
            },
            presaleHint ~= "" and UI.Label {text = presaleHint, fontSize = T.FontCaption, fontColor = T.TextMuted} or nil,
        }
    }
end

-- ============================================================================
-- 主入口
-- ============================================================================
function M.GetVisibleProjects()
    -- 项目分类:
    -- 1. presaleReadyProjects: canPresale=true 但 canSell=false（达到条件，等待玩家开始预售）
    -- 2. sellingProjects: canSell=true（正在销售中，含售罄待清盘）
    -- 3. progressProjects: 四证齐全、施工中但未达预售条件
    local presaleReadyProjects = {}
    local sellingProjects = {}
    local progressProjects = {}

    for _, p in ipairs(GD.projects) do
        if p.salesCleared then
            -- 已清盘，跳过
        elseif (p.devCategory or "sale") ~= "sale" then
            -- 非销售类项目，跳过
        elseif p.unitPlan and p.unitPlan.planned and (p.unitPlan.sellUnits or 0) == 0 then
            -- 全部自持，不显示在销售页面
        elseif p.sales.allUnitsSold and not p.salesCleared then
            -- 售罄待清盘
            table.insert(sellingProjects, p)
        elseif p.sales.canSell then
            -- 正在销售
            table.insert(sellingProjects, p)
        elseif p.sales.canPresale and not p.sales.canSell then
            -- 达到预售条件，等待开始
            table.insert(presaleReadyProjects, p)
        elseif p.permits and p.permits.allApproved then
            -- 四证齐全、施工中
            table.insert(progressProjects, p)
        end
    end

    return presaleReadyProjects, sellingProjects, progressProjects
end

function M.OpenProject(project, navigate)
    local presaleReadyProjects, sellingProjects, progressProjects = M.GetVisibleProjects()
    for index, candidate in ipairs(sellingProjects) do
        if candidate == project or (project.id ~= nil and tostring(candidate.id) == tostring(project.id)) then
            M._selectedProject = index
            M._activeTab = 1
            print("[SalesPreview] 打开销售项目: " .. tostring(project.name or project.id or index))
            navigate("sales")
            return true
        end
    end
    for _, candidate in ipairs(presaleReadyProjects) do
        if candidate == project or (project.id ~= nil and tostring(candidate.id) == tostring(project.id)) then
            M._expandedLists.presaleReadyProjects = true
            print("[SalesPreview] 打开待预售项目: " .. tostring(project.name or project.id or "未命名项目"))
            navigate("sales")
            return true
        end
    end
    for _, candidate in ipairs(progressProjects) do
        if candidate == project or (project.id ~= nil and tostring(candidate.id) == tostring(project.id)) then
            M._expandedLists.progressProjects = true
            print("[SalesPreview] 打开施工中销售项目: " .. tostring(project.name or project.id or "未命名项目"))
            navigate("sales")
            return true
        end
    end
    GD.AddEvent("该项目当前没有可查看的销售页面", "warning")
    navigate("sales")
    return false
end

function M.Create(navigate)
    local presaleReadyProjects, sellingProjects, progressProjects = M.GetVisibleProjects()

    local totalVisible = #presaleReadyProjects + #sellingProjects + #progressProjects

    -- 空状态
    if totalVisible == 0 then
        return UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center", gap = 16,
            children = {
                UI.Label {text = "暂无可售项目", fontSize = T.FontTitle, fontColor = T.TextMuted},
                UI.Label {text = "项目取得四证并达到预售条件后将显示在此", fontSize = T.FontBody, fontColor = T.TextMuted},
                C.ActionButton {text = "查看项目进度", onClick = function() navigate("project") end},
            }
        }
    end

    local scrollChildren = {
        C.SectionTitle {text = "营销销售中心"},
    }

    -- ========== 区域1: 可开始预售的项目 ==========
    if #presaleReadyProjects > 0 then
        table.insert(scrollChildren, UI.Label {
            text = "可开始预售 (" .. #presaleReadyProjects .. ")",
            fontSize = T.FontBody, fontColor = T.Warning, fontWeight = "bold",
        })
        local presaleExpanded = M._expandedLists.presaleReadyProjects == true
        for idx, pp in ipairs(presaleReadyProjects) do
            if C.ShouldShowListItem(idx, presaleExpanded, 6) then
                table.insert(scrollChildren, BuildPresaleReadyCard(pp, navigate))
            end
        end
        table.insert(scrollChildren, C.FoldButton {
            total = #presaleReadyProjects,
            limit = 6,
            expanded = presaleExpanded,
            onClick = function()
                M._expandedLists.presaleReadyProjects = not presaleExpanded
                navigate("sales")
            end,
        })
        if #sellingProjects > 0 or #progressProjects > 0 then
            table.insert(scrollChildren, UI.Panel {height = 8})
        end
    end

    -- ========== 区域2: 正在销售中的项目（5-Tab 详细管理） ==========
    if #sellingProjects > 0 then
        table.insert(scrollChildren, UI.Label {
            text = "销售中项目 (" .. #sellingProjects .. ")",
            fontSize = T.FontBody, fontColor = T.Success, fontWeight = "bold",
        })

        local projIdx = math.min(M._selectedProject, #sellingProjects)
        local p = sellingProjects[projIdx]
        local s = p.sales
        local tabIdx = M._activeTab

        -- 确保营销子结构存在
        MK.EnsureMarketingFields(s)
        local mk = s.marketing

        -- Tab 内容
        local tabContent
        if tabIdx == 1 then tabContent = BuildPricingTab(p, s, mk, navigate)
        elseif tabIdx == 2 then tabContent = BuildAccumulationTab(p, s, mk, navigate)
        elseif tabIdx == 3 then tabContent = BuildChannelTab(p, s, mk, navigate)
        elseif tabIdx == 4 then tabContent = BuildCollectionTab(p, s, mk, navigate)
        else tabContent = BuildServiceTab(p, s, navigate)
        end

        -- 项目选择器（多个销售项目时显示切换）
        if #sellingProjects > 1 then
            local projNames = {}
            for _, proj in ipairs(sellingProjects) do
                local tag, _ = GetSalesStatusTag(proj)
                table.insert(projNames, proj.name .. " [" .. tag .. "]")
            end
            table.insert(scrollChildren, C.TabBar {
                tabs = projNames, active = projIdx,
                onChange = function(idx) M._selectedProject = idx; M._activeTab = 1; navigate("sales") end,
            })
        else
            local statusTag, statusColor = GetSalesStatusTag(p)
            table.insert(scrollChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {text = p.name, fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold"},
                    C.Badge {text = statusTag, color = statusColor},
                },
            })
        end

        -- 仅在工程结算并确认竣工后，允许将预售后剩余现房按八折出售；出售后仍按正常税率清盘。
        do
            local packageAmount, packageDetail = GD.PreviewProjectPackageSale(p)
            local canPackageSell = GD.CanPackageSellProject(p)
            if packageAmount > 0 and canPackageSell then
                local infoRows = {
                    C.SectionTitle {text = "竣工现房八折出售"},
                    C.InfoRow {label = "预售后剩余现房货值", value = GD.FormatMoney(packageDetail.unsoldRevenue or 0), color = T.Info},
                    C.InfoRow {label = "八折一次性到账", value = GD.FormatMoney(packageAmount), color = T.Success},
                }
                if (packageDetail.holdRevenue or 0) > 0 then
                    table.insert(infoRows, C.InfoRow {label = "自持物业价值（不出售）", value = GD.FormatMoney(packageDetail.holdRevenue), color = T.TextMuted})
                end
                if (packageDetail.pendingRevenue or 0) > 0 then
                    table.insert(infoRows, C.InfoRow {label = "另有预售未回款合同", value = GD.FormatMoney(packageDetail.pendingRevenue), color = T.Warning})
                end
                table.insert(infoRows, UI.Label {text = "仅限完成工程结算并确认竣工后的剩余现房；按首次定价/批准开盘价八折出售，预售已签约合同仍按原价回款。八折收入计入项目销售收入，出售后必须生成清盘清单并按正常项目所得税率缴税。", fontSize = T.FontSmall, fontColor = T.TextMuted, whiteSpace = "normal"})
                table.insert(infoRows, C.ActionButton {text = "八折出售剩余现房", bgColor = T.Danger, width = "100%", onClick = function()
                    local ok, msg = GD.PackageSellProjectToThirdParty(p)
                    if not ok then GD.AddEvent(msg or "八折出售失败", "warning") end
                    M._selectedProject = 1
                    navigate("sales")
                end})
                table.insert(scrollChildren, C.Card {children = infoRows})
            end
        end

        -- 售罄清盘按钮 + 结算清单
        if p.sales.allUnitsSold and not p.salesCleared then
            local sheet = p.clearanceSheet

            if sheet and not sheet.taxPaid then
                -- ======== 已生成结算清单，显示明细 + 缴税按钮 ========
                local costItems = {
                    C.SectionTitle {text = "项目结算清单"},
                    -- 收入
                    C.InfoRow {label = "销售收入", value = GD.FormatMoney(sheet.revenue), color = T.Success},
                    C.InfoRow {label = "售出/总套数", value = sheet.soldUnits .. "/" .. sheet.totalUnits .. "套"},
                }
                -- 自持部分市场价值
                if (sheet.holdRevenue or 0) > 0 then
                    table.insert(costItems, C.InfoRow {
                        label = "自持价值(销售)",
                        value = GD.FormatMoney(sheet.holdRevenue) .. " (" .. (sheet.holdUnits or 0) .. "套)",
                        color = T.Info,
                    })
                    table.insert(costItems, C.InfoRow {
                        label = "总收入(含自持)",
                        value = GD.FormatMoney(sheet.totalRevenue or sheet.revenue),
                        color = T.Success,
                    })
                end
                table.insert(costItems, UI.Panel {height = 4})
                table.insert(costItems, UI.Label {text = "成本明细", fontSize = T.FontSmall, fontColor = T.TextMuted, fontWeight = "bold"})
                table.insert(costItems, C.InfoRow {label = "土地成本", value = GD.FormatMoney(sheet.landCost)})
                table.insert(costItems, C.InfoRow {label = "建设成本", value = GD.FormatMoney(sheet.buildCost)})

                if (sheet.designCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "设计费用", value = GD.FormatMoney(sheet.designCost)})
                end
                if (sheet.marketingCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "营销费用", value = GD.FormatMoney(sheet.marketingCost)})
                end
                if (sheet.financeCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "融资成本", value = GD.FormatMoney(sheet.financeCost)})
                end
                if (sheet.ddCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "尽调费用", value = GD.FormatMoney(sheet.ddCost)})
                end
                if (sheet.riskCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "风险成本", value = GD.FormatMoney(sheet.riskCost)})
                end
                if (sheet.otherCost or 0) > 0 then
                    table.insert(costItems, C.InfoRow {label = "其他成本", value = GD.FormatMoney(sheet.otherCost)})
                end

                table.insert(costItems, C.InfoRow {label = "成本合计", value = GD.FormatMoney(sheet.totalCostBeforeTax), color = T.Danger})
                table.insert(costItems, UI.Panel {height = 4})

                -- 税费（仅项目所得税）
                table.insert(costItems, UI.Label {text = "税费", fontSize = T.FontSmall, fontColor = T.TextMuted, fontWeight = "bold"})
                table.insert(costItems, C.InfoRow {
                    label = "项目所得税(" .. math.floor((sheet.incomeTaxRate or 0.20) * 100) .. "%)",
                    value = GD.FormatMoney(sheet.incomeTax),
                })
                table.insert(costItems, UI.Panel {height = 4})

                -- 利润
                table.insert(costItems, UI.Label {text = "利润", fontSize = T.FontSmall, fontColor = T.TextMuted, fontWeight = "bold"})
                table.insert(costItems, C.InfoRow {
                    label = "税前利润",
                    value = GD.FormatMoney(sheet.grossProfit),
                    color = sheet.grossProfit >= 0 and T.Success or T.Danger,
                })
                table.insert(costItems, C.InfoRow {
                    label = "税后净利润",
                    value = GD.FormatMoney(sheet.netProfitAfterTax),
                    color = sheet.netProfitAfterTax >= 0 and T.Success or T.Danger,
                })
                -- 利润率显示
                local totalRev = sheet.totalRevenue or sheet.revenue
                if totalRev > 0 then
                    local profitRate = math.floor(sheet.grossProfit / totalRev * 100)
                    table.insert(costItems, C.InfoRow {
                        label = "税前利润率",
                        value = profitRate .. "%",
                        color = profitRate >= 30 and T.Success or T.Warning,
                    })
                end

                -- 联合拿地分红预览（税后）
                if p.jointBid then
                    local jb = p.jointBid
                    local totalCost = sheet.totalCostBeforeTax + sheet.incomeTax
                    local partnerInvest = jb.partnerLandCost or 0
                    local partnerRatio = totalCost > 0 and (partnerInvest / totalCost) or 0

                    table.insert(costItems, UI.Panel {height = 4})
                    table.insert(costItems, UI.Label {text = "合作方分成（税后）", fontSize = T.FontSmall, fontColor = T.TextMuted, fontWeight = "bold"})
                    table.insert(costItems, C.InfoRow {label = "合作方", value = jb.partnerName})
                    table.insert(costItems, C.InfoRow {label = "合作方投入", value = GD.FormatMoney(partnerInvest)})
                    table.insert(costItems, C.InfoRow {label = "投入占比", value = string.format("%.1f%%", partnerRatio * 100)})
                    if sheet.netProfitAfterTax > 0 then
                        local partnerDiv = math.floor(sheet.netProfitAfterTax * partnerRatio)
                        table.insert(costItems, C.InfoRow {label = "合作方应分红", value = GD.FormatMoney(partnerDiv), color = T.Warning})
                    else
                        local partnerLoss = math.floor(math.abs(sheet.netProfitAfterTax) * partnerRatio)
                        table.insert(costItems, C.InfoRow {label = "合作方承担亏损", value = GD.FormatMoney(partnerLoss), color = T.Danger})
                    end
                end

                -- 缴税确认按钮
                table.insert(costItems, UI.Panel {height = 8})
                table.insert(costItems, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel {gap = 2, flexShrink = 1, children = {
                            UI.Label {text = "需缴纳税费: " .. GD.FormatMoney(sheet.incomeTax), fontSize = T.FontBody, fontColor = T.Danger, fontWeight = "bold"},
                            UI.Label {text = "确认缴税后完成清盘结算", fontSize = T.FontSmall, fontColor = T.TextMuted},
                        }},
                        UI.Button {
                            text = "确认缴税并清盘", fontSize = T.FontSmall,
                            backgroundColor = T.Danger, fontColor = T.TextOnDark,
                            borderRadius = 6, paddingHorizontal = 16, height = 36,
                            onClick = function()
                                GD.ConfirmClearanceTax(p)
                                M._selectedProject = 1
                                navigate("sales")
                            end,
                        },
                    },
                })

                table.insert(scrollChildren, C.Card {children = costItems})
            else
                -- ======== 尚未生成结算清单，显示"生成结算清单"按钮 ========
                -- 联合拿地简要预览
                if p.jointBid then
                    local jb = p.jointBid
                    local totalCost = p.cost and p.cost.totalCost or 0
                    local revenue = p.sales and p.sales.revenue or 0
                    local partnerInvest = jb.partnerLandCost or 0
                    local partnerRatio = totalCost > 0 and (partnerInvest / totalCost) or 0

                    table.insert(scrollChildren, C.Card {children = {
                        C.SectionTitle {text = "联合拿地信息"},
                        C.InfoRow {label = "合作方", value = jb.partnerName},
                        C.InfoRow {label = "合作方投入占比", value = string.format("%.1f%%", partnerRatio * 100)},
                    }})
                end

                table.insert(scrollChildren, C.Card {
                    children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            children = {
                                UI.Panel {gap = 2, flexShrink = 1, children = {
                                    UI.Label {text = "所有房源已售罄", fontSize = T.FontBody, fontColor = T.Danger, fontWeight = "bold"},
                                    UI.Label {text = "点击生成结算清单，查看各项成本与税费明细", fontSize = T.FontSmall, fontColor = T.TextMuted},
                                }},
                                UI.Button {
                                    text = "生成结算清单", fontSize = T.FontSmall,
                                    backgroundColor = T.Warning, fontColor = T.TextOnDark,
                                    borderRadius = 6, paddingHorizontal = 16, height = 36,
                                    onClick = function()
                                        GD.ManualClearance(p)
                                        navigate("sales")
                                    end,
                                },
                            },
                        },
                    },
                })
            end
        end

        -- 5-Tab 详情
        table.insert(scrollChildren, C.TabBar {
            tabs = {"定价开盘", "营销蓄客", "渠道管理", "签约回款", "客户服务"},
            active = tabIdx,
            onChange = function(idx) M._activeTab = idx; navigate("sales") end,
        })
        table.insert(scrollChildren, tabContent)

        if #progressProjects > 0 then
            table.insert(scrollChildren, UI.Panel {height = 8})
        end
    end

    -- ========== 区域3: 施工中项目（尚未达到预售条件） ==========
    if #progressProjects > 0 then
        table.insert(scrollChildren, UI.Label {
            text = "施工中项目 (" .. #progressProjects .. ")",
            fontSize = T.FontBody, fontColor = T.TextMuted, fontWeight = "bold",
        })
        local progressExpanded = M._expandedLists.progressProjects == true
        for idx, pp in ipairs(progressProjects) do
            if C.ShouldShowListItem(idx, progressExpanded, 6) then
                table.insert(scrollChildren, BuildProgressCard(pp, navigate))
            end
        end
        table.insert(scrollChildren, C.FoldButton {
            total = #progressProjects,
            limit = 6,
            expanded = progressExpanded,
            onClick = function()
                M._expandedLists.progressProjects = not progressExpanded
                navigate("sales")
            end,
        })
    end

    table.insert(scrollChildren, UI.Panel {height = 20})

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 12,
        children = scrollChildren,
    }
end

return M
