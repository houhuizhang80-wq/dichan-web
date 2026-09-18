---@diagnostic disable: param-type-mismatch, assign-type-mismatch
-- ============================================================================
-- InvestScreen.lua - 投资发展中心 (7大功能模块，全面可玩)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local LA = GD.LandAcquisition
local FN = GD.Finance
local BR = GD.Brand

local DT = require("DevTypes")
local SM = require("StockMarket")
local CompanySelector = require("CompanySelector")

local M = {}
M._activeTab = M._activeTab or 1
M._selectedLandId = nil
M._selectedLandCity = M._selectedLandCity or nil
M._landMarketShowCityList = M._landMarketShowCityList or false
M._channelFilter = M._channelFilter or "all"
M._secondaryOffer = nil
M._secondaryAskPrices = M._secondaryAskPrices or {}
M._selectedDevTypes = M._selectedDevTypes or {}
M._customProjectNames = M._customProjectNames or {}  -- {[landId] = "自定义名"}
M._selectedStandards = M._selectedStandards or {}    -- {[landId] = "basic"/"quality"/"premium"}
-- 自定义金额输入
-- 折叠展开状态
-- 竞争对手互动状态
M._compInteract = M._compInteract or nil   -- {compIdx, action}
M._compBorrowAmt = M._compBorrowAmt or 2000
M._compCoopLand = M._compCoopLand or nil
M._compCoopShare = M._compCoopShare or 50
-- 并购/IPO 状态
M._maTargets = M._maTargets or nil

local function isCompanyCityLand(land)
    local companyCity = GD.company and GD.company.city or ""
    return companyCity == "" or (land and land.city == companyCity)
end

local function canAcquireLand(land)
    local companyCity = GD.company and GD.company.city or ""
    if companyCity == "" then
        return false, "当前没有经营中的地产公司"
    end
    if not land or land.city ~= companyCity then
        return false, "当前公司注册地为" .. companyCity .. "，只能在本城市拿地"
    end
    return true
end

M._ipoChecked = false
-- 股市状态
M._stockBuyAmounts = M._stockBuyAmounts or {}  -- {[code] = amount万}
M._stockSellShares = M._stockSellShares or {}  -- {[code] = shares}
M._stockView = M._stockView or "market"  -- "market" | "holdings" | "history"

function M.ResetCompanyState()
    M._compInteract = nil
    M._compBorrowAmt = 2000
    M._compCoopLand = nil
    M._compCoopShare = 50
    M._maTargets = nil
    M._ipoChecked = false
    M._stockBuyAmounts = {}
    M._stockSellShares = {}
    M._stockView = "market"
    M._secondaryOffer = nil
    M._secondaryAskPrices = {}
    print("[InvestScreen] 已清理前一公司的投资页临时状态")
end

-- ============================================================================
-- 竞争对手互动后端逻辑 (前端内联，因 GameData 没有此模块)
-- ============================================================================
local function CompCalcRelation(comp)
    -- 关系值：基于历史互动，初始中立50
    comp._relation = comp._relation or 50
    return comp._relation
end

local function CompBorrow(comp, amount)
    local rel = CompCalcRelation(comp)
    if rel < 30 then return false, "关系太差，对方拒绝借款" end
    if amount > comp.cash * 0.3 then return false, "借款额度超过对方可承受范围(最多" .. C.FormatMoney(math.floor(comp.cash * 0.3)) .. ")" end
    -- 基于公司资产状况评估借款额度上限
    local totalAssets = GD.company.totalAssets or 0
    local totalDebt = GD.company.totalDebt or 0
    local netAssets = totalAssets - totalDebt
    local assetBasedLimit = math.max(0, math.floor(netAssets * 0.5))  -- 净资产的50%为借款上限
    if assetBasedLimit <= 0 then return false, "公司净资产为负，无法获得借款" end
    -- 计算已有同业借款总额
    local existingLoans = 0
    if GD._compLoans then
        for _, loan in ipairs(GD._compLoans) do
            existingLoans = existingLoans + loan.amount
        end
    end
    local remainingLimit = assetBasedLimit - existingLoans
    if amount > remainingLimit then
        return false, "借款额度超过资产评估上限(剩余额度" .. C.FormatMoney(math.max(0, remainingLimit)) .. "，净资产" .. C.FormatMoney(netAssets) .. ")"
    end
    -- 利率基于关系：关系越好利率越低
    local rate = 12 - (rel - 30) * 0.1  -- 30关系=12%, 80关系=7%
    rate = math.max(5, math.min(15, rate))
    comp.cash = comp.cash - amount
    GD.company.cash = GD.company.cash + amount
    comp._relation = math.max(0, (comp._relation or 50) - 5)
    -- 记录借款
    if not GD._compLoans then GD._compLoans = {} end
    table.insert(GD._compLoans, {
        lender = comp.name, amount = amount, rate = rate,
        remainMonths = 12, totalMonths = 12, monthlyInterest = math.floor(amount * rate / 100 / 12),
    })
    GD.AddEvent("向" .. comp.name .. "借款" .. C.FormatMoney(amount) .. "，年利率" .. string.format("%.1f%%", rate), "success")
    return true, "借款成功，年利率" .. string.format("%.1f%%", rate) .. "，12个月到期"
end

local function CompRepayLoan(loanIdx)
    if not GD._compLoans then return false, "无借款" end
    local loan = GD._compLoans[loanIdx]
    if not loan then return false, "借款不存在" end
    if GD.company.cash < loan.amount then return false, "现金不足以偿还本金" end
    GD.company.cash = GD.company.cash - loan.amount
    -- 找到对手加回资金和关系
    for _, comp in ipairs(GD.competitors) do
        if comp.name == loan.lender then
            comp.cash = comp.cash + loan.amount
            comp._relation = math.min(100, (comp._relation or 50) + 8)
            break
        end
    end
    GD.AddEvent("提前还清" .. loan.lender .. "借款" .. C.FormatMoney(loan.amount), "info")
    table.remove(GD._compLoans, loanIdx)
    return true, "还款成功"
end

local function CompCoopDevelop(comp, land, playerShare)
    local canAcquire, acquireReason = canAcquireLand(land)
    if not canAcquire then return false, acquireReason end
    local rel = CompCalcRelation(comp)
    if rel < 40 then return false, "关系不足(需≥40)，对方不愿合作" end
    local compShare = 100 - playerShare
    local totalCost = land.price or land.startPrice
    local playerCost = math.floor(totalCost * playerShare / 100)
    local compCost = totalCost - playerCost
    if GD.company.cash < playerCost then return false, "你的资金不足(需" .. C.FormatMoney(playerCost) .. ")" end
    if comp.cash < compCost then return false, comp.name .. "资金不足(需" .. C.FormatMoney(compCost) .. ")" end

    GD.company.cash = GD.company.cash - playerCost
    comp.cash = comp.cash - compCost
    comp._relation = math.min(100, (comp._relation or 50) + 10)

    -- 从市场移除地块
    for i, l in ipairs(GD.landMarket) do
        if l.id == land.id then table.remove(GD.landMarket, i); break end
    end
    land.price = totalCost
    land._coopPartner = comp.name
    land._coopPlayerShare = playerShare
    land.acquiredMonth = GD.totalMonths
    table.insert(GD.landReserve, land)
    GD.AddEvent("与" .. comp.name .. "合作获取" .. land.location .. "(你" .. playerShare .. "%/对方" .. compShare .. "%)", "success")
    return true, "土地已加入储备，请在土地储备中启动开发"
end

local function CompPoach(comp)
    local rel = CompCalcRelation(comp)
    local cost = math.floor(200 + (100 - rel) * 5)  -- 关系越差费用越高
    if GD.company.cash < cost then return false, "挖人费用不足(需" .. C.FormatMoney(cost) .. ")" end
    local success = math.random() < (0.3 + rel * 0.005)  -- 关系好成功率更高
    GD.company.cash = GD.company.cash - cost
    comp._relation = math.max(0, (comp._relation or 50) - 15)
    if success then
        -- 随机增益
        local bonuses = {
            {text = "营销人才", effect = function() GD.company.traitEffects.salesSpeedBonus = (GD.company.traitEffects.salesSpeedBonus or 0) + 0.05 end},
            {text = "工程人才", effect = function() GD.company.traitEffects.buildCostBonus = (GD.company.traitEffects.buildCostBonus or 0) - 0.02 end},
            {text = "设计人才", effect = function() GD.company.traitEffects.designBonus = (GD.company.traitEffects.designBonus or 0) + 0.03 end},
        }
        local bonus = bonuses[math.random(1, #bonuses)]
        bonus.effect()
        GD.AddEvent("从" .. comp.name .. "挖到" .. bonus.text .. "，获得永久增益！", "success")
        return true, "成功挖到" .. bonus.text
    else
        GD.AddEvent("挖人失败，" .. comp.name .. "关系恶化", "warning")
        return false, "挖人失败，浪费了" .. C.FormatMoney(cost) .. "公关费"
    end
end

local function CompAlliance(comp)
    local rel = CompCalcRelation(comp)
    if rel < 60 then return false, "关系不足(需≥60)，对方不愿结盟" end
    local cost = 500
    if GD.company.cash < cost then return false, "结盟费用不足(需500万)" end
    GD.company.cash = GD.company.cash - cost
    comp._relation = math.min(100, (comp._relation or 50) + 20)
    comp._alliance = true
    -- 结盟增益：竞拍时对方不参与
    GD.AddEvent("与" .. comp.name .. "签订战略联盟(竞拍不再对抗+共享信息)", "success")
    return true, "联盟成功！竞拍时" .. comp.name .. "将不再出价"
end

local function CompGift(comp, amount)
    if GD.company.cash < amount then return false, "资金不足" end
    GD.company.cash = GD.company.cash - amount
    local relGain = math.floor(amount / 100)  -- 每100万加1点关系
    relGain = math.min(20, math.max(1, relGain))
    comp._relation = math.min(100, (comp._relation or 50) + relGain)
    GD.AddEvent("向" .. comp.name .. "赠送" .. C.FormatMoney(amount) .. "公关礼金(关系+" .. relGain .. ")", "info")
    return true, "关系+" .. relGain
end

local function CompSabotage(comp)
    local cost = 300
    if GD.company.cash < cost then return false, "资金不足(需300万)" end
    GD.company.cash = GD.company.cash - cost
    local success = math.random() < 0.4
    if success then
        comp.cash = math.max(1000, comp.cash - comp.cash * 0.1)
        comp._relation = math.max(0, (comp._relation or 50) - 25)
        GD.company.creditScore = math.max(0, GD.company.creditScore - 3)
        GD.AddEvent("商业竞争手段生效，" .. comp.name .. "受损10%资金(你的信用-3)", "warning")
        return true, "竞争手段奏效"
    else
        comp._relation = math.max(0, (comp._relation or 50) - 10)
        GD.company.creditScore = math.max(0, GD.company.creditScore - 5)
        GD.AddEvent("商业竞争失败，被" .. comp.name .. "发现(信用-5)", "danger")
        return false, "操作失败，信用受损"
    end
end


local function buildOperationCompanySelector(navigate)
    return CompanySelector.Build {
        navigate = navigate,
        returnScreen = "invest",
        onSwitched = M.ResetCompanyState,
        description = "竞争对手、股市和资产交易操作仅作用于当前选中的公司。",
    }
end

function M.Create(navigate)
    local activeTab = math.max(1, math.min(7, math.floor(tonumber(M._activeTab) or 1)))
    M._activeTab = activeTab

    -- ===== Tab1: 土地市场 =====
    local function buildLandMarket()
        local function isMarketLand(land)
            return GD.IsMarketLand and GD.IsMarketLand(land) or land.status == "available"
                or land.status == "negotiable"
                or land.status == "locked"
                or land.status == "for_sale"
        end

        local function getDisplayPrice(land)
            local ch = land.channel or LA.CHANNELS.PUBLIC_AUCTION
            local cd = land.channelData or {}
            if ch == LA.CHANNELS.SECONDARY then
                return tonumber(cd.askingPrice or land.startPrice or land.price) or 0
            end
            return tonumber(land.startPrice or land.price) or 0
        end

        local selectedCity = M._selectedLandCity
        -- 从城市公司进入时，自动选择该公司所在城市；显式返回城市列表时不得再次自动选回公司城市
        if not selectedCity and not M._landMarketShowCityList and GD.company and GD.company.city then
            selectedCity = GD.company.city
            M._selectedLandCity = selectedCity
        end
        if not selectedCity then
            local cityChildren = {
                C.SectionTitle {text = "选择土地市场城市"},
                UI.Label {
                    text = "选择城市后查看该城市全部在售土地，土地将按价格从低到高排列。",
                    fontSize = T.FontSmall,
                    fontColor = T.TextSecondary,
                    whiteSpace = "normal",
                    maxLines = 2,
                },
            }

            for _, city in ipairs(GD.cities or {}) do
                local capturedCity = city
                local landCount = 0
                local lowestPrice = nil
                for _, land in ipairs(GD.landMarket or {}) do
                    if land.city == city.name and isMarketLand(land) then
                        local price = getDisplayPrice(land)
                        landCount = landCount + 1
                        if lowestPrice == nil or price < lowestPrice then lowestPrice = price end
                    end
                end
                table.insert(cityChildren, C.Card {children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "flex-start",
                        gap = 8,
                        children = {
                            UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, gap = 2, children = {
                                UI.Label {text = city.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                                UI.Label {
                                    text = "城市均价 " .. tostring(city.avgPrice or 0) .. "元/㎡ · " .. tostring(landCount) .. "宗土地",
                                    fontSize = T.FontCaption,
                                    fontColor = T.TextSecondary,
                                    whiteSpace = "normal",
                                    maxLines = 2,
                                },
                            }},
                            C.Badge {
                                text = landCount > 0 and ("最低" .. C.FormatMoney(lowestPrice or 0)) or "暂无土地",
                                variant = landCount > 0 and "success" or "warning",
                                maxWidth = "48%",
                            },
                        },
                    },
                    C.ActionButton {
                        text = "进入" .. city.name .. "土地市场",
                        width = "100%",
                        onClick = function()
                            M._selectedLandCity = capturedCity.name
                            M._landMarketShowCityList = false
                            M._channelFilter = "all"
                            print("[InvestScreen] 进入土地市场城市：" .. capturedCity.name)
                            navigate("invest")
                        end,
                    },
                }})
            end

            return UI.Panel {width = "100%", gap = 10, children = cityChildren}
        end

        local filter = M._channelFilter or "all"
        local channelFilters = {
            {key = "all",             label = "全部"},
            {key = "public_auction",  label = "招拍挂"},
            {key = "negotiation",     label = "勾地"},
            {key = "judicial",        label = "法拍"},
            {key = "secondary",       label = "二手"},
        }
        local filterBtns = {}
        for _, f in ipairs(channelFilters) do
            local capturedKey = f.key
            local isActive = (filter == capturedKey)
            table.insert(filterBtns, UI.Button {
                text = f.label, fontSize = T.FontSmall,
                backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
                fontColor = isActive and T.Primary or T.TabInactiveFont,
                borderRadius = 4, paddingHorizontal = 12, height = 28,
                onClick = function()
                    M._channelFilter = capturedKey
                    navigate("invest")
                end,
            })
        end

        local filtered = {}
        for _, land in ipairs(GD.landMarket) do
            local ch = land.channel or LA.CHANNELS.PUBLIC_AUCTION
            local show = land.city == selectedCity and ((filter == "all") or (ch == filter))
            if show and isMarketLand(land) then
                table.insert(filtered, land)
            end
        end
        table.sort(filtered, function(a, b)
            local priceA = getDisplayPrice(a)
            local priceB = getDisplayPrice(b)
            if priceA == priceB then return tostring(a.id or "") < tostring(b.id or "") end
            return priceA < priceB
        end)

        local chCounts = {public_auction=0, negotiation=0, judicial=0, secondary=0}
        for _, land in ipairs(GD.landMarket) do
            local ch = land.channel or LA.CHANNELS.PUBLIC_AUCTION
            if land.city == selectedCity and isMarketLand(land) then
                chCounts[ch] = (chCounts[ch] or 0) + 1
            end
        end

        local pageChildren = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    C.SecondaryButton {
                        text = "返回城市列表",
                        height = 30,
                        paddingH = 10,
                        onClick = function()
                            M._selectedLandCity = nil
                            M._landMarketShowCityList = true
                            M._channelFilter = "all"
                            print("[InvestScreen] 返回土地市场城市列表")
                            navigate("invest")
                        end,
                    },
                    UI.Label {
                        text = selectedCity .. "土地市场",
                        fontSize = T.FontSubtitle,
                        fontColor = T.TextPrimary,
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        minWidth = 0,
                    },
                    C.Badge {text = "价格升序", variant = "info"},
                },
            },
        }
        -- 资金概览
        table.insert(pageChildren, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%",
            children = {
                C.StatCard {title = "可用资金", value = C.FormatMoney(GD.company.cash), color = T.Success},
                C.StatCard {title = "招拍挂", value = chCounts.public_auction .. "宗", color = T.Accent},
                C.StatCard {title = "勾地", value = chCounts.negotiation .. "宗", color = T.Info},
                C.StatCard {title = "法拍/二手", value = (chCounts.judicial + chCounts.secondary) .. "宗", color = T.Warning},
            }
        })
        table.insert(pageChildren, UI.Panel {
            flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap",
            children = filterBtns,
        })

        if #filtered == 0 then
            table.insert(pageChildren, UI.Label {
                text = "当前无可用地块，等待下次土地出让",
                fontSize = T.FontBody, fontColor = T.TextMuted, textAlign = "center", marginTop = 30,
            })
        end

        for _, land in ipairs(filtered) do
            local capturedLand = land
            local ch = land.channel or LA.CHANNELS.PUBLIC_AUCTION
            local chName = LA.CHANNEL_NAMES[ch] or "招拍挂"
            local reqText = (land.requirements and #land.requirements > 0) and table.concat(land.requirements, "、") or "无特殊要求"
            local calc = GD.CalcInvestment(land)
            local profitRate = calc and calc.profitRate or 0
            local floorPrice = land.floorPrice or 0
            local canAcquire, acquireReason = canAcquireLand(land)

            local cardChildren = {}

            -- 头部
            local headerBadges = {
                UI.Label {text = land.id, fontSize = T.FontCaption, fontColor = T.TextMuted},
                C.Badge {text = chName, variant = ch == "judicial" and "warning" or (ch == "secondary" and "success" or (ch == "negotiation" and "info" or "accent"))},
                C.Badge {text = land.useType, variant = "accent"},
            }
            if land.status == "locked" then
                table.insert(headerBadges, C.Badge {text = "已锁定", variant = "success"})
            elseif land.status == "for_sale" then
                table.insert(headerBadges, C.Badge {text = "在售", variant = "info"})
            end
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = headerBadges},
                    UI.Label {text = (land.city or "未知") .. " · " .. (land.location or ""), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })

            -- 基础参数
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap",
                children = {
                    UI.Label {text = "占地 " .. string.format("%.1f", (land.area or 0)/10000) .. "万㎡", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = "容积率 " .. (land.far or "—"), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = "建面 " .. string.format("%.1f", (land.buildArea or 0)/10000) .. "万㎡", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = "楼面价 " .. floorPrice .. "元/㎡", fontSize = T.FontSmall, fontColor = T.Accent},
                    UI.Label {text = "限高 " .. ((land.heightLimit or 0) > 0 and (land.heightLimit .. "m") or "不限"), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })
            table.insert(cardChildren, UI.Label {text = "配建: " .. reqText, fontSize = T.FontCaption, fontColor = T.TextMuted})
            if not canAcquire then
                table.insert(cardChildren, UI.Label {
                    text = "仅展示：" .. acquireReason .. "。请在" .. (land.city or "该城市") .. "成立并切换至本城公司后操作。",
                    fontSize = T.FontCaption,
                    fontColor = T.Warning,
                })
            end

            -- 渠道专属信息
            local cd = land.channelData or {}
            if ch == LA.CHANNELS.NEGOTIATION then
                local earnestStatus = cd.earnestPaid and "已缴纳" or "待缴纳"
                table.insert(cardChildren, UI.Panel {
                    width = "100%", backgroundColor = T.InfoBg, borderRadius = 4, padding = 6, gap = 2, marginTop = 4,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                            UI.Label {text = "诚意金: " .. C.FormatMoney(cd.earnestMoney or 0), fontSize = T.FontCaption, fontColor = T.Info},
                            UI.Label {text = earnestStatus, fontSize = T.FontCaption, fontColor = cd.earnestPaid and T.Success or T.Warning},
                        }},
                        UI.Label {text = "排他期: " .. (cd.exclusivePeriod or 0) .. "个月 | 政府条件: " .. (cd.govCondition or "—"), fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }
                })
            elseif ch == LA.CHANNELS.JUDICIAL then
                local roundText = cd.auctionRound == 1 and "首拍" or "二拍"
                table.insert(cardChildren, UI.Panel {
                    width = "100%", backgroundColor = T.WarningBg, borderRadius = 4, padding = 6, gap = 2, marginTop = 4,
                    children = {
                        UI.Label {text = (cd.courtName or "") .. " | " .. (cd.caseNumber or ""), fontSize = T.FontCaption, fontColor = T.Warning},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            UI.Label {text = roundText, fontSize = T.FontCaption, fontColor = T.Warning},
                            UI.Label {text = "折扣 " .. (cd.judicialDiscount or 0) .. "%", fontSize = T.FontCaption, fontColor = T.Success},
                        }},
                        UI.Label {text = "可能存在隐性风险(抵押/纠纷/污染)，建议尽调", fontSize = T.FontCaption, fontColor = T.Danger},
                    }
                })
            elseif ch == LA.CHANNELS.SECONDARY then
                local urgencyNames = {low = "不急售", medium = "正常", high = "急售"}
                local urgencyColors = {low = T.TextMuted, medium = T.Info, high = T.Success}
                local urg = cd.urgency or "medium"
                table.insert(cardChildren, UI.Panel {
                    width = "100%", backgroundColor = T.SuccessBg, borderRadius = 4, padding = 6, gap = 2, marginTop = 4,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                            UI.Label {text = "卖方: " .. (cd.sellerName or "未知"), fontSize = T.FontCaption, fontColor = T.TextPrimary},
                            UI.Label {text = urgencyNames[urg] or "正常", fontSize = T.FontCaption, fontColor = urgencyColors[urg] or T.Info},
                        }},
                        UI.Panel {flexDirection = "row", gap = 8, width = "100%", children = {
                            UI.Label {text = "报价: " .. C.FormatMoney(cd.askingPrice or land.startPrice), fontSize = T.FontCaption, fontColor = T.Accent},
                            UI.Label {text = cd.negotiable and "可议价" or "一口价", fontSize = T.FontCaption, fontColor = cd.negotiable and T.Success or T.Warning},
                        }},
                    }
                })
            end

            -- 价格/指标行
            local priceLabel = ch == LA.CHANNELS.SECONDARY and "卖方报价" or "起拍价"
            local priceValue = ch == LA.CHANNELS.SECONDARY and (cd.askingPrice or land.startPrice) or land.startPrice
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 4,
                children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = priceLabel, fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = C.FormatMoney(priceValue), fontSize = T.FontSubtitle, fontColor = T.Accent},
                    }},
                    UI.Panel {gap = 2, alignItems = "center", children = {
                        UI.Label {text = "地房比", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = (calc and calc.priceLandRatio or 0) .. "%", fontSize = T.FontSubtitle, fontColor = T.TextSecondary},
                    }},
                    UI.Panel {gap = 2, alignItems = "center", children = {
                        UI.Label {text = "预估净利率", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {
                            text = profitRate .. "%", fontSize = T.FontSubtitle,
                            fontColor = profitRate > 10 and T.Success or (profitRate > 0 and T.Warning or T.Danger),
                        },
                    }},
                }
            })

            -- 开发类型选择器（精简版）
            local landUseKey = DT.USE_TYPE_TO_LAND_USE[land.useType] or "mixed"
            local availableTypes = DT.GetTypesForLandUse(landUseKey)
            local selectedTypeId = M._selectedDevTypes[land.id]
            if not selectedTypeId then
                selectedTypeId = availableTypes[1] and availableTypes[1].id or "rigid_residential"
                M._selectedDevTypes[land.id] = selectedTypeId
            end
            local selectedTypeDef = DT.GetType(selectedTypeId)

            do
                local typeBtns = {}
                for _, t in ipairs(availableTypes) do
                    local capturedTid = t.id
                    local isSelected = (t.id == selectedTypeId)
                    table.insert(typeBtns, UI.Panel {
                        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                        backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                        borderRadius = 4,
                        borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                        onClick = function()
                            M._selectedDevTypes[capturedLand.id] = capturedTid
                            navigate("invest")
                        end,
                        children = {
                            UI.Label {text = ((t.icon and t.icon ~= "" and (t.icon .. " ") or "") .. t.shortName), fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                        },
                    })
                end

                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 6, padding = 8, gap = 4,
                    backgroundColor = T.InfoBg, borderRadius = 6,
                    children = {
                        UI.Label {text = "开发类型", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = typeBtns},
                        selectedTypeDef and UI.Panel {flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap", marginTop = 2, children = (function()
                            local cityData = GD.GetCityData(capturedLand.city)
                            local cityAvg = cityData and cityData.avgPrice or 15000
                            local estBuildCost = DT.GetBuildCost(
                                selectedTypeDef.id,
                                cityAvg,
                                capturedLand.plotLocation or "suburb",
                                "basic"
                            )
                            return {
                                UI.Label {text = selectedTypeDef.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                UI.Label {text = "建安≈" .. estBuildCost .. "元/㎡", fontSize = T.FontCaption, fontColor = T.TextMuted},
                                UI.Label {text = "工期" .. selectedTypeDef.totalMonths .. "月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                                UI.Label {text = "利润目标" .. math.floor((selectedTypeDef.targetMargin or 0)*100) .. "%", fontSize = T.FontCaption, fontColor = T.Accent},
                            }
                        end)()} or UI.Panel {height = 0},
                    },
                })
            end

            -- 项目命名输入框
            do
                local autoName = land.location .. (selectedTypeDef and selectedTypeDef.shortName or "刚需") .. "项目"
                local curName = M._customProjectNames[land.id]
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 4, padding = 8, gap = 4,
                    backgroundColor = T.InfoBg, borderRadius = 6,
                    children = {
                        UI.Label {text = "项目名称", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = curName and curName ~= "" and curName or autoName,
                            placeholder = "输入项目名称...",
                            maxLength = 20,
                            fontSize = T.FontSmall,
                            onChange = function(self, v) M._customProjectNames[capturedLand.id] = v end,
                        },
                    },
                })
            end

            -- 操作按钮
            local actionBtns = {}
            table.insert(actionBtns, C.SecondaryButton {
                text = "投资测算", height = 32, paddingH = 10,
                onClick = function() M._selectedLandId = capturedLand.id; M._activeTab = 3; navigate("invest") end,
            })

            if ch == LA.CHANNELS.PUBLIC_AUCTION or ch == LA.CHANNELS.JUDICIAL then
                table.insert(actionBtns, C.ActionButton {
                    text = ch == LA.CHANNELS.JUDICIAL and "参加法拍" or "参加竞拍",
                    height = 32, paddingH = 14,
                    disabled = not canAcquire or GD.company.cash < (land.deposit or land.startPrice or 0),
                    onClick = function()
                        local ok, msg = canAcquireLand(capturedLand)
                        if not ok then
                            GD.AddEvent(msg, "warning")
                            navigate("invest")
                            return
                        end
                        M._auctionLandId = capturedLand.id
                        navigate("auction")
                    end,
                })
            elseif ch == LA.CHANNELS.NEGOTIATION then
                if not cd.earnestPaid then
                    table.insert(actionBtns, C.ActionButton {
                        text = "缴纳诚意金", height = 32, paddingH = 14,
                        disabled = not canAcquire or GD.company.cash < (cd.earnestMoney or 0),
                        onClick = function()
                            local allowed, reason = canAcquireLand(capturedLand)
                            if not allowed then GD.AddEvent(reason, "warning"); navigate("invest"); return end
                            local ok, msg = LA.PayEarnest(capturedLand, GD.company.cash, GD.company.city)
                            if ok then GD.company.cash = GD.company.cash - (cd.earnestMoney or 0); GD.AddEvent(msg, "success")
                            else GD.AddEvent(msg, "warning") end
                            navigate("invest")
                        end,
                    })
                else
                    table.insert(actionBtns, C.ActionButton {
                        text = "确认摘牌", height = 32, paddingH = 14,
                        disabled = not canAcquire or GD.company.cash < land.startPrice,
                        onClick = function()
                            local allowed, reason = canAcquireLand(capturedLand)
                            if not allowed then GD.AddEvent(reason, "warning"); navigate("invest"); return end
                            local ok, msg = LA.ConfirmNegotiation(capturedLand, GD.company.city)
                            if ok then
                                GD.company.cash = GD.company.cash - capturedLand.startPrice
                                capturedLand.price = capturedLand.startPrice
                                for i, l in ipairs(GD.landMarket) do if l.id == capturedLand.id then table.remove(GD.landMarket, i); break end end
                                capturedLand.acquiredMonth = GD.totalMonths
                                capturedLand.ownerType = "player_company"
                                capturedLand.ownerCompanyId = GD.activeCompanyId
                                table.insert(GD.landReserve, capturedLand)
                                GD.AddEvent(msg .. "，土地已加入储备", "success")
                            else GD.AddEvent(msg, "warning") end
                            navigate("invest")
                        end,
                    })
                end
            elseif ch == LA.CHANNELS.SECONDARY then
                local isNegotiating = M._secondaryOffer and M._secondaryOffer.landId == land.id
                if isNegotiating then
                    local askP = cd.askingPrice or land.startPrice
                    local offerAmounts = {math.floor(askP*0.85), math.floor(askP*0.90), math.floor(askP*0.95), askP}
                    local offerLabels = {"85折", "9折", "95折", "全价"}
                    for oi, amt in ipairs(offerAmounts) do
                        local capturedAmt = amt
                        table.insert(actionBtns, C.ActionButton {
                            text = offerLabels[oi] .. " " .. C.FormatMoney(amt), height = 28, paddingH = 8,
                            disabled = not canAcquire or GD.company.cash < amt,
                            onClick = function()
                                local allowed, reason = canAcquireLand(capturedLand)
                                if not allowed then GD.AddEvent(reason, "warning"); M._secondaryOffer = nil; navigate("invest"); return end
                                local sellerIsPlayerCompany = capturedLand.channelData
                                    and capturedLand.channelData.sellerType == "player_company"
                                local ok, msg, finalPrice
                                if sellerIsPlayerCompany then
                                    ok, msg, finalPrice = GD.BuySecondaryLand(
                                        capturedLand.id,
                                        capturedAmt,
                                        GD.activeCompanyId
                                    )
                                else
                                    ok, msg, finalPrice = LA.NegotiateSecondary(capturedLand, capturedAmt, GD.company.city)
                                end
                                if ok and finalPrice then
                                    if not sellerIsPlayerCompany then
                                        GD.company.cash = GD.company.cash - finalPrice
                                        capturedLand.price = finalPrice
                                        for i, l in ipairs(GD.landMarket) do if l.id == capturedLand.id then table.remove(GD.landMarket, i); break end end
                                        capturedLand.acquiredMonth = GD.totalMonths
                                        capturedLand.ownerType = "player_company"
                                        capturedLand.ownerCompanyId = GD.activeCompanyId
                                        table.insert(GD.landReserve, capturedLand)
                                    end
                                    GD.AddEvent("二手地块 " .. capturedLand.location .. " " .. msg .. "，已加入储备", "success")
                                else GD.AddEvent("议价失败: " .. (msg or ""), "warning") end
                                M._secondaryOffer = nil; navigate("invest")
                            end,
                        })
                    end
                    table.insert(actionBtns, C.SecondaryButton {text = "取消", height = 28, paddingH = 8,
                        onClick = function() M._secondaryOffer = nil; navigate("invest") end})
                else
                    table.insert(actionBtns, C.ActionButton {
                        text = "发起议价", height = 32, paddingH = 14,
                        disabled = not canAcquire,
                        onClick = function()
                            local allowed, reason = canAcquireLand(capturedLand)
                            if not allowed then GD.AddEvent(reason, "warning"); navigate("invest"); return end
                            M._secondaryOffer = {landId = capturedLand.id}
                            navigate("invest")
                        end,
                    })
                end
            end

            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", justifyContent = "flex-end", gap = 6, width = "100%", marginTop = 6, flexWrap = "wrap",
                children = actionBtns,
            })
            table.insert(pageChildren, C.Card {children = cardChildren})
        end
        return UI.Panel {width = "100%", gap = 12, children = pageChildren}
    end

    -- ===== Tab2: 土地储备 =====
    local function buildLandReserve()
        local reserveCards = {}
        local availableLands = {}
        local totalArea, totalBuildArea, totalValue = 0, 0, 0
        for _, land in ipairs(GD.landReserve) do
            if isCompanyCityLand(land) then
                local hasProj = false
                for _, p in ipairs(GD.projects) do
                    if p.land and p.land.id == land.id then hasProj = true; break end
                end
                if not hasProj then
                    table.insert(availableLands, land)
                    totalArea = totalArea + (land.area or 0)
                    totalBuildArea = totalBuildArea + (land.buildArea or 0)
                    totalValue = totalValue + (land.price or land.startPrice or 0)
                end
            end
        end
        local undevelopedCount = #availableLands

        table.insert(reserveCards, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%",
            children = {
                C.StatCard {title = "储备宗数", value = #availableLands .. "宗", color = T.Accent},
                C.StatCard {title = "待开发", value = undevelopedCount .. "宗", color = undevelopedCount > 0 and T.Warning or T.Success},
                C.StatCard {title = "总建面", value = string.format("%.1f万㎡", totalBuildArea/10000), color = T.Info},
                C.StatCard {title = "总地价", value = C.FormatMoney(totalValue), color = T.Warning},
            }
        })

        if #availableLands == 0 then
            table.insert(reserveCards, UI.Label {
                text = "暂无可开发土地储备，请通过土地市场获取土地", fontSize = T.FontBody, fontColor = T.TextMuted, textAlign = "center", marginTop = 30,
            })
        end

        for _, land in ipairs(availableLands) do
            local capturedLand = land
            local price = land.price or land.startPrice or 0
            -- 查找关联项目 - 跳过已开发地块
            local hasDevelopment = false
            for _, p in ipairs(GD.projects) do
                if p.land and p.land.id == land.id then hasDevelopment = true; break end
            end
            if hasDevelopment then goto continue_land end

            local coopText = land._coopPartner and ("合作方: " .. land._coopPartner .. " (你" .. (land._coopPlayerShare or 50) .. "%)") or nil

            -- 闲置信息
            local idleInfo = GD.GetLandIdleInfo(land)
            local idleColor = T.TextMuted
            do
                if idleInfo.isExpired then idleColor = T.Danger
                elseif idleInfo.isWarning then idleColor = T.Warning
                end
            end

            -- 可选开发类型
            local landUseKey = DT.USE_TYPE_TO_LAND_USE[land.useType] or "mixed"
            local availableTypes = DT.GetTypesForLandUse(landUseKey)
            local selectedTypeId = M._selectedDevTypes[land.id]
            if not selectedTypeId then
                selectedTypeId = availableTypes[1] and availableTypes[1].id or "rigid_residential"
                M._selectedDevTypes[land.id] = selectedTypeId
            end

            local cardChildren = {}

            -- 顶部：ID + Badge + 位置
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = {
                        UI.Label {text = land.id, fontSize = T.FontCaption, fontColor = T.TextMuted},
                        C.Badge {text = land.useType or "住宅", variant = "accent"},
                        coopText and C.Badge {text = "合作", variant = "info"} or UI.Panel {height = 0},
                    }},
                    UI.Label {text = land.location or "", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })

            -- 基础信息行
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", gap = 10, width = "100%",
                children = {
                    UI.Label {text = "占地 " .. string.format("%.1f万㎡", (land.area or 0)/10000), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = "容积率 " .. (land.far or "—"), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = "建面 " .. string.format("%.1f万㎡", (land.buildArea or 0)/10000), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })

            -- 合作方信息
            if coopText then
                table.insert(cardChildren, UI.Label {text = coopText, fontSize = T.FontCaption, fontColor = T.Info})
            end

            -- 地价 + 地块位置
            local plotLocLabel = (land.plotLocation == "core") and "核心区" or "郊区"
            local plotLocColor = (land.plotLocation == "core") and T.Accent or T.TextSecondary
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = "成交地价", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = C.FormatMoney(price), fontSize = T.FontBody, fontColor = T.Accent},
                    }},
                    UI.Panel {gap = 2, alignItems = "flex-end", children = {
                        UI.Label {text = "地块位置", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = plotLocLabel, fontSize = T.FontBody, fontColor = plotLocColor},
                    }},
                }
            })

            -- === 以下为交互区域（仅未开发地块） ===
            do
                -- 闲置倒计时
                local remainMonths = GD.IDLE_LAND_LIMIT - idleInfo.idleMonths
                local idleText = "已闲置 " .. idleInfo.idleMonths .. "/" .. GD.IDLE_LAND_LIMIT .. " 个月"
                if remainMonths <= 3 and remainMonths > 0 then
                    idleText = idleText .. "（仅剩 " .. remainMonths .. " 个月！）"
                elseif remainMonths <= 0 then
                    idleText = idleText .. "（即将被收回！）"
                end
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 6, padding = 6,
                    backgroundColor = idleInfo.isWarning and T.WarningBg or T.BgElevated,
                    borderRadius = 4, borderWidth = idleInfo.isWarning and 1 or 0,
                    borderColor = idleInfo.isWarning and T.Warning or T.Border,
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label {text = "⏰", fontSize = T.FontBody},
                        UI.Label {text = idleText, fontSize = T.FontSmall, fontColor = idleColor},
                    },
                })

                -- 本公司未开发土地可挂牌为二手地；已绑定项目、联合拿地或抵押土地由后端拒绝。
                local askInput = M._secondaryAskPrices[capturedLand.id]
                    or tostring(math.floor(price))
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 6, padding = 8, gap = 5,
                    backgroundColor = T.InfoBg, borderRadius = 6,
                    children = {
                        UI.Label {text = "二手转让（仅未开发土地）", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = askInput,
                            placeholder = "输入挂牌价（万元）",
                            fontSize = T.FontSmall,
                            onChange = function(self, value)
                                M._secondaryAskPrices[capturedLand.id] = value
                            end,
                        },
                        C.SecondaryButton {
                            text = "挂牌转让",
                            width = "100%",
                            onClick = function()
                                local ok, msg = GD.ListLandForSecondarySale(
                                    capturedLand.id,
                                    tonumber(M._secondaryAskPrices[capturedLand.id]) or price
                                )
                                GD.AddEvent(msg or "二手土地挂牌失败", ok and "success" or "warning")
                                if ok then M._secondaryAskPrices[capturedLand.id] = nil end
                                navigate("invest")
                            end,
                        },
                    },
                })

                -- 开发类型选择按钮
                local typeBtns = {}
                for _, t in ipairs(availableTypes) do
                    if not t or not t.id then goto continue_type end
                    local capturedTid = t.id
                    local isSelected = (t.id == selectedTypeId)
                    table.insert(typeBtns, UI.Panel {
                        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                        backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                        borderRadius = 4,
                        borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                        onClick = function()
                            M._selectedDevTypes[capturedLand.id] = capturedTid
                            navigate("invest")
                        end,
                        children = {
                            UI.Label {text = ((t.icon and t.icon ~= "" and (t.icon .. " ") or "") .. (t.shortName or t.name or t.id)), fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                        },
                    })
                    ::continue_type::
                end
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 6, padding = 8, gap = 4,
                    backgroundColor = T.InfoBg, borderRadius = 6,
                    children = {
                        UI.Label {text = "开发类型", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = typeBtns},
                    },
                })

                -- 开发标准选择
                local selectedStdId = M._selectedStandards[land.id] or "basic"
                local stdBtns = {}
                for _, stdKey in ipairs({"basic", "quality", "premium"}) do
                    local std = DT.STANDARDS[stdKey]
                    if not std then goto continue_std end
                    local capturedStdKey = stdKey
                    local isStdSel = (stdKey == selectedStdId)
                    local stdLabel = std.icon .. " " .. std.name
                    if std.costMult > 1 then
                        stdLabel = stdLabel .. " (成本+" .. math.floor((std.costMult - 1) * 100) .. "%)"
                    end
                    table.insert(stdBtns, UI.Panel {
                        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                        backgroundColor = isStdSel and T.PrimaryLight or T.BgElevated,
                        borderRadius = 4,
                        borderWidth = 1, borderColor = isStdSel and T.PrimaryBorder or T.Border,
                        onClick = function()
                            M._selectedStandards[capturedLand.id] = capturedStdKey
                            navigate("invest")
                        end,
                        children = {
                            UI.Label {text = stdLabel, fontSize = T.FontCaption, fontColor = isStdSel and T.Primary or T.TextSecondary},
                        },
                    })
                    ::continue_std::
                end
                local stdInfo = DT.GetStandard(selectedStdId)
                local stdDesc = {}
                if stdInfo.reputationPerRound > 0 then table.insert(stdDesc, "口碑+" .. stdInfo.reputationPerRound .. "/年") end
                if stdInfo.priceMult > 1 then table.insert(stdDesc, "售价+" .. math.floor((stdInfo.priceMult - 1) * 100) .. "%") end
                if stdInfo.qualityRisk > 0 then table.insert(stdDesc, "质量风险" .. math.floor(stdInfo.qualityRisk * 100) .. "%") end
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 4, padding = 8, gap = 4,
                    backgroundColor = T.BgElevated, borderRadius = 6,
                    borderWidth = 1, borderColor = T.Border,
                    children = {
                        UI.Label {text = "开发标准", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = stdBtns},
                        #stdDesc > 0 and UI.Label {text = table.concat(stdDesc, " | "), fontSize = T.FontCaption, fontColor = T.Info} or UI.Panel {height = 0},
                    },
                })

                -- 项目名称输入
                local curName = M._customProjectNames and M._customProjectNames[land.id]
                local selectedDef = DT.GetType(selectedTypeId)
                local autoName = (land.location or land.city or "新") .. (selectedDef and selectedDef.shortName or "") .. "项目"
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 4, padding = 8, gap = 4,
                    backgroundColor = T.BgElevated, borderRadius = 6,
                    children = {
                        UI.Label {text = "项目名称（可选）", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.TextField {
                            value = curName and curName ~= "" and curName or autoName,
                            placeholder = "输入项目名称...",
                            maxLength = 20,
                            fontSize = T.FontSmall,
                            onChange = function(self, v) M._customProjectNames[capturedLand.id] = v end,
                        },
                    },
                })

                -- 确认开发按钮
                table.insert(cardChildren, UI.Panel {
                    marginTop = 6,
                    paddingLeft = 16, paddingRight = 16,
                    paddingTop = 8, paddingBottom = 8,
                    backgroundColor = T.Accent,
                    borderRadius = T.ButtonRadius,
                    alignItems = "center", justifyContent = "center",
                    onClick = function()
                        local devType = M._selectedDevTypes[capturedLand.id]
                        local stdId = M._selectedStandards[capturedLand.id] or "basic"
                        local pName = M._customProjectNames and M._customProjectNames[capturedLand.id]
                        local ok, msg = GD.StartDevelopment(capturedLand.id, devType, pName and pName ~= "" and pName or nil, stdId)
                        if ok then
                            GD.AddEvent(msg or "开发已启动", "success")
                            if M._customProjectNames then M._customProjectNames[capturedLand.id] = nil end
                            M._selectedStandards[capturedLand.id] = nil
                        else
                            GD.AddEvent("无法启动开发: " .. (msg or "未知错误"), "warning")
                        end
                        navigate("invest")
                    end,
                    children = {
                        UI.Label { text = "确认开发", fontSize = T.FontBody, fontColor = T.TextOnDark },
                    },
                })
            end

            table.insert(reserveCards, C.Card { children = cardChildren })
            ::continue_land::
        end
        return UI.Panel {width = "100%", gap = 10, children = reserveCards}
    end

    -- ===== Tab3: 投资测算 =====
    local function buildInvestCalc()
        local children = {}
        local landOptions = {}
        local selectedLand = nil
        for _, land in ipairs(GD.landMarket) do
            if isCompanyCityLand(land) and land.status == "available" then
                table.insert(landOptions, land)
                if land.id == M._selectedLandId then selectedLand = land end
            end
        end
        for _, land in ipairs(GD.landReserve) do
            if isCompanyCityLand(land) then
                table.insert(landOptions, land)
                if land.id == M._selectedLandId then selectedLand = land end
            end
        end

        if #landOptions == 0 then
            return UI.Label {text = "暂无可分析的地块", fontSize = T.FontBody, fontColor = T.TextMuted, textAlign = "center", marginTop = 30}
        end
        if not selectedLand then selectedLand = landOptions[1]; M._selectedLandId = selectedLand.id end

        -- 地块选择
        local selectBtns = {}
        for _, land in ipairs(landOptions) do
            local capturedId = land.id
            local isSel = (land.id == M._selectedLandId)
            table.insert(selectBtns, UI.Button {
                text = (land.id or "") .. " " .. (land.location or ""), fontSize = T.FontCaption,
                backgroundColor = isSel and T.PrimaryLight or T.BgCard,
                fontColor = isSel and T.Primary or T.TextPrimary,
                borderRadius = 4, paddingHorizontal = 10, height = 28,
                onClick = function() M._selectedLandId = capturedId; navigate("invest") end,
            })
        end
        table.insert(children, UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = selectBtns})

        if selectedLand then
            -- 尽职调查
            if LA then
                local surveyStatus = LA.GetSurveyStatus(selectedLand)
                local ddChildren = {}
                table.insert(ddChildren, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                    children = {
                        C.SectionTitle {text = "尽职调查"},
                        UI.Label {text = surveyStatus.completedCount .. "/4 完成  费用 " .. C.FormatMoney(surveyStatus.totalCost), fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }
                })
                for _, item in ipairs(surveyStatus.items) do
                    local capturedItem = item
                    local stateText, stateColor
                    if item.state == "completed" then
                        stateText = item.result or "已完成"
                        stateColor = (item.result and item.result:find("风险")) and T.Warning or T.Success
                    elseif item.state == "in_progress" then
                        stateText = "进行中(剩余" .. (item.monthsRemaining or "?") .. "月)"
                        stateColor = T.Info
                    elseif item.state == "skipped" then stateText = "已跳过"; stateColor = T.TextMuted
                    else stateText = "待执行"; stateColor = T.TextSecondary end

                    local actionChildren = {}
                    if item.state == "pending" then
                        table.insert(actionChildren, C.ActionButton {
                            text = "启动 " .. C.FormatMoney(item.cost), height = 26, paddingH = 10,
                            disabled = GD.company.cash < item.cost or (surveyStatus.inProgress ~= nil),
                            onClick = function()
                                local ok, msg, cost = LA.StartSurvey(selectedLand, capturedItem.type, GD.company.cash)
                                if ok and cost then GD.company.cash = GD.company.cash - cost; GD.AddEvent("启动尽调: " .. capturedItem.name, "info") end
                                navigate("invest")
                            end,
                        })
                        table.insert(actionChildren, C.SecondaryButton {text = "跳过", height = 26, paddingH = 8,
                            onClick = function() LA.SkipSurvey(selectedLand, capturedItem.type); navigate("invest") end})
                    end
                    table.insert(ddChildren, UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", paddingVertical = 4,
                        children = {
                            UI.Panel {gap = 1, flexShrink = 1, children = {
                                UI.Panel {flexDirection = "row", gap = 6, children = {
                                    UI.Label {text = item.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                    UI.Label {text = item.months .. "月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                                }},
                                UI.Label {text = stateText, fontSize = T.FontCaption, fontColor = stateColor},
                            }},
                            UI.Panel {flexDirection = "row", gap = 6, children = actionChildren},
                        }
                    })
                end
                if #surveyStatus.risks > 0 then
                    table.insert(ddChildren, UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=4})
                    table.insert(ddChildren, UI.Label {text = "已发现风险:", fontSize = T.FontSmall, fontColor = T.Warning})
                    for _, risk in ipairs(surveyStatus.risks) do
                        table.insert(ddChildren, UI.Label {text = "- " .. risk.desc .. " (+" .. C.FormatMoney(risk.costImpact) .. ")", fontSize = T.FontCaption, fontColor = T.Danger})
                    end
                end
                table.insert(children, C.Card {children = ddChildren})
            end

            -- 测算结果
            local calc = GD.CalcInvestment(selectedLand)
            if calc then
                table.insert(children, C.SectionTitle {text = (selectedLand.id or "") .. " " .. (selectedLand.location or "") .. " 测算", color = T.Accent})
                -- 关键指标卡片
                table.insert(children, UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%",
                    children = {
                        C.StatCard {title = "净利率", value = calc.profitRate .. "%", color = calc.profitRate > 10 and T.Success or T.Danger},
                        C.StatCard {title = "投资回报率", value = calc.roi .. "%", color = calc.roi > 15 and T.Success or T.Warning},
                        C.StatCard {title = "工期", value = calc.estMonths .. "月", color = T.Info},
                        C.StatCard {title = "去化周期", value = calc.sellMonths .. "月", color = calc.sellMonths < 18 and T.Success or T.Warning},
                    }
                })
                -- 成本/收入
                table.insert(children, C.Card {children = {
                    C.SectionTitle {text = "成本构成"},
                    C.InfoRow {label = "土地成本", value = C.FormatMoney(calc.landCost), color = T.Accent},
                    C.InfoRow {label = "建安成本", value = C.FormatMoney(calc.buildCost)},
                    C.InfoRow {label = "设计费", value = C.FormatMoney(calc.designCost)},
                    C.InfoRow {label = "营销费", value = C.FormatMoney(calc.marketingCost)},
                    C.InfoRow {label = "财务成本", value = C.FormatMoney(calc.financeCost)},
                    C.InfoRow {label = "税费", value = C.FormatMoney(calc.taxCost)},
                    UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=4},
                    C.InfoRow {label = "总成本", value = C.FormatMoney(calc.totalCost), color = T.Warning},
                }})
                table.insert(children, C.Card {children = {
                    C.SectionTitle {text = "收入预测"},
                    C.InfoRow {label = "可售面积", value = string.format("%.1f万㎡ (%d套)", calc.sellArea/10000, calc.totalUnits)},
                    C.InfoRow {label = "预估售价", value = calc.estPrice .. " 元/㎡", color = T.Accent},
                    C.InfoRow {label = "地房比", value = calc.priceLandRatio .. "%", color = calc.priceLandRatio < 40 and T.Success or T.Warning},
                    UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=4},
                    C.InfoRow {label = "预估总收入", value = C.FormatMoney(calc.totalRevenue), color = T.Success},
                    C.InfoRow {label = "预估利润", value = C.FormatMoney(calc.profit), color = calc.profit > 0 and T.Success or T.Danger},
                }})

                -- 敏感性分析
                local city = GD.GetCityData()
                if city and LA then
                    table.insert(children, C.SectionTitle {text = "敏感性分析", color = T.Accent})
                    local mc = LA.MarketComparison(selectedLand, city, GD.economy)
                    if mc then
                        table.insert(children, C.Card {children = {
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                                UI.Label {text = "市场比较法", fontSize = T.FontSubtitle, fontColor = T.Accent},
                                UI.Label {text = "偏差 " .. (mc.deviation >= 0 and "+" or "") .. mc.deviation .. "%", fontSize = T.FontBody,
                                    fontColor = mc.deviation > 10 and T.Success or (mc.deviation < -10 and T.Danger or T.TextSecondary)},
                            }},
                            C.InfoRow {label = "比较法均价", value = mc.adjustedAvg .. " 元/㎡", color = T.Accent},
                            C.InfoRow {label = "当前楼面价", value = mc.currentFloorPrice .. " 元/㎡"},
                            UI.Label {text = mc.conclusion, fontSize = T.FontSmall, fontColor = mc.deviation > 10 and T.Success or T.Info},
                        }})
                    end
                    local rm = LA.ResidualMethod(selectedLand, city, GD.economy, GD.company.traitEffects)
                    if rm then
                        table.insert(children, C.Card {children = {
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                                UI.Label {text = "假设开发法", fontSize = T.FontSubtitle, fontColor = T.Accent},
                                UI.Label {text = "偏差 " .. (rm.premiumOrDiscount >= 0 and "+" or "") .. rm.premiumOrDiscount .. "%", fontSize = T.FontBody,
                                    fontColor = rm.premiumOrDiscount > 15 and T.Danger or (rm.premiumOrDiscount < -10 and T.Success or T.TextSecondary)},
                            }},
                            C.InfoRow {label = "合理地价", value = C.FormatMoney(rm.residualLandValue), color = T.Accent},
                            C.InfoRow {label = "合理楼面价", value = rm.residualFloorPrice .. " 元/㎡"},
                            UI.Label {text = rm.conclusion, fontSize = T.FontSmall, fontColor = rm.premiumOrDiscount > 15 and T.Danger or T.Info},
                        }})
                    end
                    -- 5x5 矩阵
                    local sm = LA.SensitivityMatrix(selectedLand, city, GD.economy)
                    if sm then
                        local smRows = {}
                        table.insert(smRows, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                                UI.Label {text = "敏感性矩阵(利润率%)", fontSize = T.FontSubtitle, fontColor = T.Accent},
                                UI.Label {text = "基准 " .. sm.baseRate .. "%", fontSize = T.FontSmall, fontColor = sm.baseRate > 0 and T.Success or T.Danger},
                            }
                        })
                        local headerCells = {UI.Label {text = "成本\\售价", fontSize = T.FontCaption, fontColor = T.TextMuted, width = 52, textAlign = "center"}}
                        for pi = 1, 5 do
                            table.insert(headerCells, UI.Label {text = sm.priceLabels[pi], fontSize = T.FontCaption, fontColor = pi == 3 and T.Accent or T.TextMuted, width = 44, textAlign = "center"})
                        end
                        table.insert(smRows, UI.Panel {flexDirection = "row", width = "100%", paddingVertical = 4, backgroundColor = T.InfoBg, children = headerCells})
                        for ci = 1, 5 do
                            local rowCells = {UI.Label {text = sm.costLabels[ci], fontSize = T.FontCaption, fontColor = ci == 3 and T.Accent or T.TextMuted, width = 52, textAlign = "center"}}
                            for pi = 1, 5 do
                                local cell = sm.matrix[ci][pi]
                                local cellColor = cell.rate > 15 and T.Success or (cell.rate > 5 and T.Success or (cell.rate > 0 and T.Warning or T.Danger))
                                local isBase = (ci == 3 and pi == 3)
                                table.insert(rowCells, UI.Panel {
                                    width = 44, height = 28, justifyContent = "center", alignItems = "center",
                                    backgroundColor = isBase and T.PrimaryLight or nil, borderRadius = isBase and 4 or 0,
                                    children = {UI.Label {text = cell.rate .. "%", fontSize = T.FontCaption, fontColor = cellColor}},
                                })
                            end
                            table.insert(smRows, UI.Panel {flexDirection = "row", width = "100%", paddingVertical = 1, children = rowCells})
                        end
                        local beText = sm.breakEvenPriceDelta >= 0 and ("售价可承受下跌" .. sm.breakEvenPriceDelta .. "%") or ("需售价上涨" .. math.abs(sm.breakEvenPriceDelta) .. "%")
                        table.insert(smRows, UI.Panel {flexDirection = "row", gap = 6, width = "100%", marginTop = 4, children = {
                            C.Badge {text = "盈亏平衡", variant = sm.breakEvenPriceDelta >= 0 and "success" or "danger"},
                            UI.Label {text = beText, fontSize = T.FontSmall, fontColor = sm.breakEvenPriceDelta >= 0 and T.Success or T.Danger},
                        }})
                        table.insert(children, C.Card {children = smRows})
                    end
                end
            end
        end
        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- ===== Tab4: 市场趋势 =====
    local function buildMarketTrend()
        local children = {}
        local city = GD.GetCityData()
        if not city then return UI.Label {text = "无城市数据", fontSize = T.FontBody, fontColor = T.TextMuted} end

        local cycleNames = {boom="繁荣期", recession="衰退期", depression="萧条期", recovery="复苏期"}
        local cycleColors = {boom=T.Success, recession=T.Warning, depression=T.Danger, recovery=T.Info}
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%",
            children = {
                C.StatCard {title = "经济周期", value = cycleNames[GD.economy.cycle] or "—", color = cycleColors[GD.economy.cycle] or T.TextMuted},
                C.StatCard {title = "房价指数", value = string.format("%.0f", GD.economy.priceIndex), color = GD.economy.priceIndex > 100 and T.Success or T.Danger},
                C.StatCard {title = "基准利率", value = string.format("%.2f%%", GD.economy.interestRate), color = T.Accent},
                C.StatCard {title = "需求倍数", value = string.format("%.1fx", GD.economy.demandMultiplier), color = GD.economy.demandMultiplier > 1 and T.Success or T.Danger},
            }
        })

        -- 房价走势
        local trend = GD.GetMarketTrend()
        if #trend > 0 then
            table.insert(children, C.SectionTitle {text = city.name .. " 近12月房价走势"})
            local maxP, minP = 0, 999999999
            for _, d in ipairs(trend) do
                if d.price > maxP then maxP = d.price end
                if d.price < minP then minP = d.price end
            end
            local range = math.max(1, maxP - minP)
            local barChildren = {}
            for _, d in ipairs(trend) do
                local pct = math.floor((d.price - minP) / range * 60) + 20
                table.insert(barChildren, UI.Panel {
                    alignItems = "center", gap = 2, flexGrow = 1, flexBasis = 0,
                    children = {
                        UI.Label {text = math.floor(d.price/1000) .. "k", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Panel {width = "80%", height = pct, backgroundColor = d.price >= city.avgPrice and T.Success or T.Warning, borderRadius = 2},
                        UI.Label {text = d.label, fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }
                })
            end
            table.insert(children, C.Card {children = {
                UI.Panel {flexDirection = "row", gap = 2, width = "100%", height = 120, alignItems = "flex-end", children = barChildren},
                UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 6, children = {
                    UI.Label {text = "最低: " .. minP .. "元/㎡", fontSize = T.FontCaption, fontColor = T.Danger},
                    UI.Label {text = "当前: " .. city.avgPrice .. "元/㎡", fontSize = T.FontCaption, fontColor = T.Accent},
                    UI.Label {text = "最高: " .. maxP .. "元/㎡", fontSize = T.FontCaption, fontColor = T.Success},
                }},
            }})
        end

        -- 政策环境
        table.insert(children, C.SectionTitle {text = "政策环境分析"})
        table.insert(children, C.Card {children = {
            C.InfoRow {label = "当前政策", value = city.policy, color = city.policyStrength >= 4 and T.Danger or T.Success},
            C.InfoRow {label = "政策力度", value = city.policyStrength .. "/5", color = city.policyStrength >= 4 and T.Danger or T.Success},
            C.InfoRow {label = "库存去化", value = city.inventory .. "个月", color = city.inventory > 18 and T.Danger or T.Success},
            C.InfoRow {label = "人口增长", value = string.format("%.1f%%", city.growth * 100), color = city.growth > 0.03 and T.Success or T.TextMuted},
            C.InfoRow {label = "市场竞争度", value = math.floor(city.compete * 100) .. "%", color = city.compete > 0.6 and T.Danger or T.Success},
        }})

        -- 投资建议
        local advice, adviceColor = "稳健投资", T.Info
        if GD.economy.cycle == "boom" and city.inventory < 12 then advice = "积极拿地，市场供不应求"; adviceColor = T.Success
        elseif GD.economy.cycle == "depression" then advice = "谨慎投资，逢低吸纳优质地块"; adviceColor = T.Warning
        elseif city.inventory > 20 then advice = "库存过高，暂缓拿地"; adviceColor = T.Danger
        elseif GD.economy.cycle == "recovery" then advice = "复苏期机会，择优拿地"; adviceColor = T.Info end
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "投资建议"},
            UI.Label {text = advice, fontSize = T.FontSubtitle, fontColor = adviceColor},
        }})

        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- ===== Tab5: 竞争对手 (全面增强 + 股权投资 + 引入股东) =====
    local function buildCompetitors()
        local children = {
            buildOperationCompanySelector(navigate),
        }

        -- 我司对比概览
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "我司资金", value = C.FormatMoney(GD.company.cash), color = T.Success},
                C.StatCard {title = "资质", value = GD.GetQualName(), color = T.Accent},
                C.StatCard {title = "信用分", value = math.floor(GD.company.creditScore) .. "分", color = GD.company.creditScore >= 80 and T.Success or T.Warning},
            }
        })

        -- ========== 股权投资组合概览 ==========
        if GD.NormalizeEquityInvestments then GD.NormalizeEquityInvestments() end
        if #GD.equityInvestments > 0 then
            local invCards = {}
            table.insert(invCards, C.SectionTitle {text = "我的股权投资组合", color = T.Accent})
            local totalInvested, totalDiv, totalCurrentValue = 0, 0, 0
            for ii, inv in ipairs(GD.equityInvestments) do
                local capturedII = ii
                local comp = GD.competitors[inv.compIdx]
                local currentVal = (GD.GetEquityInvestmentCurrentValue and GD.GetEquityInvestmentCurrentValue(inv, comp)) or (comp and math.floor(comp.cash * 2.5 * inv.equityRatio) or 0)
                local profit = currentVal - inv.investAmount
                totalInvested = totalInvested + inv.investAmount
                totalDiv = totalDiv + inv.totalDividends
                totalCurrentValue = totalCurrentValue + currentVal
                table.insert(invCards, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    width = "100%", paddingVertical = 4, borderBottomWidth = 1, borderColor = T.Border,
                    children = {
                        UI.Panel {gap = 2, flexShrink = 1, children = {
                            UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                                UI.Label {text = inv.compName, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                C.Badge {text = string.format("%.1f%%", inv.equityRatio * 100), variant = "accent"},
                            }},
                            UI.Label {
                                text = "投入" .. C.FormatMoney(inv.investAmount)
                                    .. " | 现值" .. C.FormatMoney(currentVal)
                                    .. " | 累计分红" .. C.FormatMoney(inv.totalDividends),
                                fontSize = T.FontCaption, fontColor = T.TextMuted,
                            },
                        }},
                        C.SecondaryButton {
                            text = "退出", height = 26, paddingH = 8,
                            onClick = function()
                                GD.ExitEquityInvestment(capturedII)
                                navigate("invest")
                            end,
                        },
                    }
                })
            end
            -- 汇总行
            local totalProfit = totalCurrentValue - totalInvested
            table.insert(invCards, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 6,
                children = {
                    UI.Label {text = "汇总: 投入" .. C.FormatMoney(totalInvested) .. " | 现值" .. C.FormatMoney(totalCurrentValue), fontSize = T.FontSmall, fontColor = T.TextPrimary},
                    UI.Label {text = (totalProfit >= 0 and "浮盈" or "浮亏") .. C.FormatMoney(math.abs(totalProfit)) .. " | 累计分红" .. C.FormatMoney(totalDiv), fontSize = T.FontSmall, fontColor = totalProfit >= 0 and T.Success or T.Danger},
                }
            })
            table.insert(children, C.Card {children = invCards})
        end

        -- ========== 同业借款列表 ==========
        if GD._compLoans and #GD._compLoans > 0 then
            local loanCards = {}
            table.insert(loanCards, C.SectionTitle {text = "同业借款(未还)", color = T.Warning})
            for li, loan in ipairs(GD._compLoans) do
                local capturedLi = li
                table.insert(loanCards, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    width = "100%", paddingVertical = 4,
                    children = {
                        UI.Panel {gap = 1, flexShrink = 1, children = {
                            UI.Label {text = loan.lender .. " | " .. C.FormatMoney(loan.amount) .. " | 利率" .. string.format("%.1f%%", loan.rate), fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            UI.Label {text = "剩余" .. loan.remainMonths .. "月 | 月息" .. C.FormatMoney(loan.monthlyInterest), fontSize = T.FontCaption, fontColor = T.TextMuted},
                        }},
                        C.ActionButton {
                            text = "提前还清", height = 26, paddingH = 10,
                            disabled = GD.company.cash < loan.amount,
                            onClick = function()
                                CompRepayLoan(capturedLi)
                                navigate("invest")
                            end,
                        },
                    }
                })
            end
            table.insert(children, C.Card {children = loanCards})
        end

        -- ========== 竞争对手列表(10家) ==========
        local competitors = GD.competitors or {}
        table.insert(children, C.SectionTitle {text = "行业竞争情报 (共" .. #competitors .. "家)"})
        local reports = GD.GetCompetitorReport()

        -- tier颜色映射
        local tierColors = {S = T.Danger, A = T.Warning, B = T.Info, C = T.Success, D = T.TextMuted}
        local tierLabels = {S = "巨头", A = "大型", B = "中型", C = "区域", D = "小型"}

        for ci, r in ipairs(reports) do
            local capturedCi = ci
            local comp = competitors[ci]
            if not comp then break end
            local rel = CompCalcRelation(comp)
            local relColor = rel >= 60 and T.Success or (rel >= 40 and T.Accent or (rel >= 20 and T.Warning or T.Danger))
            local relText = rel >= 80 and "亲密" or (rel >= 60 and "友好" or (rel >= 40 and "中立" or (rel >= 20 and "冷淡" or "敌对")))
            local compTier = r.tier or "C"

            -- 已持有该公司的股权比例
            local myEquity = 0
            for _, inv in ipairs(GD.equityInvestments) do
                if inv.compIdx == ci then myEquity = myEquity + inv.equityRatio end
            end

            local cardItems = {}

            -- 基本信息行(增加tier标签)
            table.insert(cardItems, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", flexShrink = 1, children = {
                        UI.Panel {
                            width = 22, height = 22, borderRadius = 4,
                            backgroundColor = tierColors[compTier] or T.Border,
                            justifyContent = "center", alignItems = "center",
                            children = {UI.Label {text = compTier, fontSize = 11, fontColor = T.TextPrimary}},
                        },
                        UI.Label {text = r.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        C.Badge {text = r.type, variant = "info"},
                        C.Badge {text = r.style, variant = r.style == "激进" and "danger" or (r.style == "保守" and "success" or "info")},
                    }},
                    UI.Label {text = C.FormatMoney(r.cash), fontSize = T.FontBody, fontColor = T.Accent},
                }
            })

            -- 关系与动态 + 已持股标记
            table.insert(cardItems, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = {
                        UI.Label {text = "关系: " .. relText .. "(" .. rel .. ")", fontSize = T.FontSmall, fontColor = relColor},
                        comp._alliance and C.Badge {text = "联盟中", variant = "success"} or UI.Panel {height = 0},
                        myEquity > 0 and C.Badge {text = "持股" .. string.format("%.1f%%", myEquity * 100), variant = "accent"} or UI.Panel {height = 0},
                    }},
                    UI.Label {text = "动态: " .. r.action, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                }
            })

            -- 实力条(按tier调整满值)
            local maxCash = ({S=1200000, A=600000, B=300000, C=100000, D=30000})[compTier] or 100000
            table.insert(cardItems, C.ProgressCard {
                title = tierLabels[compTier] .. "实力",
                progress = math.min(100, math.floor(r.cash / maxCash * 100)),
                barColor = tierColors[compTier] or T.Info,
            })

            -- 关系进度条
            table.insert(cardItems, UI.Panel {
                width = "100%", height = 6, backgroundColor = T.BgInput, borderRadius = 3,
                children = {UI.Panel {width = rel .. "%", height = "100%", backgroundColor = relColor, borderRadius = 3}},
            })

            -- ======== 股权投资区(新增) ========
            local equityBtns = {}
            -- 计算可投金额选项(按对手规模)
            local investOptions = {}
            local compVal = comp.cash * 2.5
            if compVal >= 500 then table.insert(investOptions, math.max(100, math.floor(compVal * 0.02))) end  -- 2%
            if compVal >= 2000 then table.insert(investOptions, math.floor(compVal * 0.05)) end  -- 5%
            if compVal >= 5000 then table.insert(investOptions, math.floor(compVal * 0.10)) end  -- 10%

            if myEquity < 0.30 then
                for _, iAmt in ipairs(investOptions) do
                    local capturedIA = iAmt
                    local estRatio = iAmt / (compVal + iAmt)
                    table.insert(equityBtns, C.ActionButton {
                        text = "投资" .. C.FormatMoney(capturedIA) .. "(~" .. string.format("%.1f%%", estRatio * 100) .. ")",
                        height = 28, paddingH = 8,
                        disabled = GD.company.cash < capturedIA,
                        onClick = function()
                            local ok, msg = GD.InvestEquity(capturedCi, capturedIA)
                            GD.AddEvent(msg, ok and "success" or "warning")
                            navigate("invest")
                        end,
                    })
                end
            else
                table.insert(equityBtns, UI.Label {text = "已达持股上限30%", fontSize = T.FontCaption, fontColor = T.Warning})
            end

            table.insert(cardItems, UI.Panel {
                width = "100%", marginTop = 4, padding = 8, gap = 6,
                backgroundColor = T.InfoBg, borderRadius = 6,
                children = {
                    UI.Label {text = "股权投资 (年底获分红)", fontSize = T.FontCaption, fontColor = T.Info},
                    UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = equityBtns},
                }
            })

            -- ======== 引入股东区(新增) ========
            local shBtns = {}
            if rel >= 50 then
                local gov = GD.company.governance
                local companyVal = gov and math.max(GD.company.cash * 2, gov.lastValuation) or (GD.company.cash * 2)
                -- 入股金额选项
                local shAmounts = {}
                if comp.cash >= 500 then table.insert(shAmounts, 500) end
                if comp.cash >= 2000 then table.insert(shAmounts, 2000) end
                if comp.cash >= 5000 then table.insert(shAmounts, 5000) end
                if comp.cash >= 10000 then table.insert(shAmounts, 10000) end

                for _, sAmt in ipairs(shAmounts) do
                    local capturedSA = sAmt
                    local estDilution = sAmt / (companyVal + sAmt)
                    table.insert(shBtns, C.SecondaryButton {
                        text = "引入" .. C.FormatMoney(capturedSA) .. "(稀释~" .. string.format("%.1f%%", estDilution * 100) .. ")",
                        height = 28, paddingH = 8,
                        onClick = function()
                            local ok, msg = GD.IntroduceShareholder(capturedCi, capturedSA)
                            GD.AddEvent(msg, ok and "success" or "warning")
                            navigate("invest")
                        end,
                    })
                end
            else
                table.insert(shBtns, UI.Label {text = "关系≥50才能引入股东", fontSize = T.FontCaption, fontColor = T.TextMuted})
            end

            table.insert(cardItems, UI.Panel {
                width = "100%", padding = 8, gap = 6,
                backgroundColor = T.InfoBg, borderRadius = 6,
                children = {
                    UI.Label {text = "引入股东 (对方入股我司)", fontSize = T.FontCaption, fontColor = T.Accent},
                    UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = shBtns},
                }
            })

            -- ======== 资金往来 ========
            local interactBtns = {}
            local giftAmounts = {100, 300, 500}
            for _, gAmt in ipairs(giftAmounts) do
                local capturedGA = gAmt
                table.insert(interactBtns, C.SecondaryButton {
                    text = "送礼" .. capturedGA .. "万", height = 28, paddingH = 8,
                    onClick = function()
                        CompGift(comp, capturedGA)
                        navigate("invest")
                    end,
                })
            end

            local maxBorrow = math.floor(comp.cash * 0.3)
            if maxBorrow > 0 and rel >= 30 then
                local borrowAmounts = {}
                if maxBorrow >= 500 then table.insert(borrowAmounts, 500) end
                if maxBorrow >= 1000 then table.insert(borrowAmounts, 1000) end
                if maxBorrow >= 2000 then table.insert(borrowAmounts, 2000) end
                if maxBorrow >= 5000 then table.insert(borrowAmounts, 5000) end
                for _, bAmt in ipairs(borrowAmounts) do
                    local capturedBA = bAmt
                    table.insert(interactBtns, C.ActionButton {
                        text = "借" .. C.FormatMoney(capturedBA), height = 28, paddingH = 8,
                        onClick = function()
                            local ok, msg = CompBorrow(comp, capturedBA)
                            GD.AddEvent(msg, ok and "success" or "warning")
                            navigate("invest")
                        end,
                    })
                end
            elseif rel < 30 then
                table.insert(interactBtns, UI.Label {text = "关系≥30才能借款", fontSize = T.FontCaption, fontColor = T.TextMuted})
            end

            table.insert(cardItems, UI.Panel {
                width = "100%", padding = 8, gap = 6,
                backgroundColor = T.InfoBg, borderRadius = 6,
                children = {
                    UI.Label {text = "资金往来", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = interactBtns},
                }
            })

            -- ======== 合作开发 ========
            local coopBtns = {}
            if rel >= 40 then
                local coopLands = {}
                for _, land in ipairs(GD.landMarket) do
                    if isCompanyCityLand(land) and (land.status == "available" or land.status == "negotiable") then
                        table.insert(coopLands, land)
                        if #coopLands >= 3 then break end
                    end
                end
                if #coopLands > 0 then
                    for _, cl in ipairs(coopLands) do
                        local capturedCl = cl
                        local totalCost = cl.price or cl.startPrice
                        local playerCost = math.floor(totalCost * 0.5)
                        table.insert(coopBtns, C.ActionButton {
                            text = cl.location .. " (你50% " .. C.FormatMoney(playerCost) .. ")",
                            height = 28, paddingH = 8,
                            disabled = GD.company.cash < playerCost or comp.cash < (totalCost - playerCost),
                            onClick = function()
                                local ok, msg = CompCoopDevelop(comp, capturedCl, 50)
                                GD.AddEvent(msg, ok and "success" or "warning")
                                navigate("invest")
                            end,
                        })
                    end
                else
                    table.insert(coopBtns, UI.Label {text = "无可合作地块", fontSize = T.FontCaption, fontColor = T.TextMuted})
                end
            else
                table.insert(coopBtns, UI.Label {text = "关系≥40才能合作开发", fontSize = T.FontCaption, fontColor = T.TextMuted})
            end

            table.insert(cardItems, UI.Panel {
                width = "100%", padding = 8, gap = 6,
                backgroundColor = T.SuccessBg, borderRadius = 6,
                children = {
                    UI.Label {text = "合作开发", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = coopBtns},
                }
            })

            -- ======== 战略操作 ========
            local stratBtns = {}
            table.insert(stratBtns, C.SecondaryButton {
                text = "挖人(~" .. math.floor(200 + (100 - rel) * 5) .. "万)", height = 28, paddingH = 8,
                onClick = function()
                    local ok, msg = CompPoach(comp)
                    GD.AddEvent(msg, ok and "success" or "warning")
                    navigate("invest")
                end,
            })
            if not comp._alliance then
                table.insert(stratBtns, C.ActionButton {
                    text = "结盟(500万,需关系≥60)", height = 28, paddingH = 8,
                    disabled = rel < 60 or GD.company.cash < 500,
                    onClick = function()
                        local ok, msg = CompAlliance(comp)
                        GD.AddEvent(msg, ok and "success" or "warning")
                        navigate("invest")
                    end,
                })
            else
                table.insert(stratBtns, C.Badge {text = "已结盟", variant = "success"})
            end
            table.insert(stratBtns, C.SecondaryButton {
                text = "商业竞争(300万)", height = 28, paddingH = 8,
                onClick = function()
                    local ok, msg = CompSabotage(comp)
                    GD.AddEvent(msg, ok and "success" or (ok == false and "warning" or "danger"))
                    navigate("invest")
                end,
            })

            table.insert(cardItems, UI.Panel {
                width = "100%", padding = 8, gap = 6,
                backgroundColor = T.InfoBg, borderRadius = 6,
                children = {
                    UI.Label {text = "战略操作", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Panel {flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", children = stratBtns},
                }
            })

            table.insert(children, C.Card {children = cardItems})
        end

        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- 项目管线 + 并购/IPO（供其他投资功能调用，未单列页签）
    local function buildProjectPipeline()
        local children = {}

        -- 容量指示器
        local PCM = GD.ProjectCapacity
        local capacity = PCM.CalcCapacity(GD.company)
        local activeCount = PCM.CountActiveProjects(GD.projects)
        local canCreate = PCM.CanCreateProject(GD.company, GD.projects)
        local capColor = activeCount >= capacity and T.Danger or (activeCount >= capacity - 1 and T.Warning or T.Success)
        table.insert(children, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = "项目容量", fontSize = T.FontBody, fontColor = T.TextPrimary},
                    UI.Label {text = activeCount .. " / " .. capacity, fontSize = T.FontSubtitle, fontColor = capColor},
                },
            },
            UI.Panel {
                flexDirection = "row", gap = 4, marginTop = 6,
                children = (function()
                    local dots = {}
                    for i = 1, capacity do
                        table.insert(dots, UI.Panel {width = 16, height = 16, borderRadius = 8, backgroundColor = i <= activeCount and T.Accent or T.Border})
                    end
                    return dots
                end)(),
            },
            UI.Label {
                text = canCreate and "可新建项目" or "容量已满(扩建区域公司或指派项目总监)",
                fontSize = T.FontSmall, fontColor = canCreate and T.Success or T.Warning, marginTop = 4,
            },
        }})

        -- 汇总统计
        if #GD.projects > 0 then
            local totalInvest, totalRevenue = 0, 0
            local statusCounts = {}
            for _, p in ipairs(GD.projects) do
                statusCounts[p.status] = (statusCounts[p.status] or 0) + 1
                totalInvest = totalInvest + p.cost.totalCost
                totalRevenue = totalRevenue + p.sales.revenue
            end
            table.insert(children, UI.Panel {
                flexDirection = "row", gap = 8, width = "100%",
                children = {
                    C.StatCard {title = "总项目数", value = #GD.projects .. "个", color = T.Accent},
                    C.StatCard {title = "总投资", value = C.FormatMoney(totalInvest), color = T.Warning},
                    C.StatCard {title = "总回款", value = C.FormatMoney(totalRevenue), color = T.Success},
                }
            })

            -- 项目列表
            table.insert(children, C.SectionTitle {text = "项目进度列表"})
            for _, p in ipairs(GD.projects) do
                local progress = 0
                local phaseText = ""
                if p.status == "permits" then
                    local done = 0
                    for _, permit in ipairs(p.permits) do if permit.status == "done" then done = done + 1 end end
                    progress = math.floor(done / #p.permits * 100)
                    phaseText = "办证中(" .. done .. "/" .. #p.permits .. ")"
                elseif p.status == "completed" then progress = 100; phaseText = "已完成"
                else
                    progress = p.construction.progress
                    phaseText = p.status
                end
                local sellPct = p.sales.totalUnits > 0 and math.floor(p.sales.soldUnits / p.sales.totalUnits * 100) or 0

                table.insert(children, C.Card {children = {
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                        UI.Label {text = p.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        C.Badge {text = phaseText, variant = p.status == "completed" and "success" or "accent"},
                    }},
                    C.ProgressCard {title = "工程进度", progress = progress, barColor = T.Info},
                    C.ProgressCard {title = "销售进度", progress = sellPct, status = p.sales.soldUnits .. "/" .. p.sales.totalUnits .. "套", barColor = T.Success},
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                        UI.Label {text = "投资 " .. C.FormatMoney(p.cost.totalCost), fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = "回款 " .. C.FormatMoney(p.sales.revenue), fontSize = T.FontCaption, fontColor = T.Success},
                    }},
                }})
            end
        else
            table.insert(children, UI.Label {text = "暂无在管项目，请先获取土地", fontSize = T.FontBody, fontColor = T.TextMuted, textAlign = "center", marginTop = 20})
        end

        -- ===== 并购 =====
        table.insert(children, UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=8})
        table.insert(children, C.SectionTitle {text = "并购机会", color = T.Accent})

        if not M._maTargets then
            table.insert(children, C.ActionButton {
                text = "搜索并购标的", height = 36, paddingH = 16,
                onClick = function()
                    M._maTargets = FN.GenerateMATargets(GD)
                    navigate("invest")
                end,
            })
        else
            table.insert(children, C.SecondaryButton {
                text = "刷新标的", height = 30, paddingH = 12,
                onClick = function() M._maTargets = FN.GenerateMATargets(GD); navigate("invest") end,
            })
            for mi, target in ipairs(M._maTargets) do
                local capturedTarget = target
                local affordable = GD.company.cash >= target.price
                table.insert(children, C.Card {children = {
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                        UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                            UI.Label {text = target.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                            C.Badge {text = target.type, variant = "accent"},
                        }},
                        UI.Label {text = C.FormatMoney(target.price), fontSize = T.FontBody, fontColor = affordable and T.Accent or T.Danger},
                    }},
                    UI.Label {text = target.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
                        UI.Label {text = "资产价值 " .. C.FormatMoney(target.assetValue), fontSize = T.FontCaption, fontColor = T.TextMuted},
                        target.monthlyIncome > 0 and UI.Label {text = "月收入+" .. C.FormatMoney(target.monthlyIncome), fontSize = T.FontCaption, fontColor = T.Success} or UI.Panel{height=0},
                        target.costReduction > 0 and UI.Label {text = "成本-" .. math.floor(target.costReduction*100) .. "%", fontSize = T.FontCaption, fontColor = T.Success} or UI.Panel{height=0},
                        target.qualBoost > 0 and UI.Label {text = "资质+1", fontSize = T.FontCaption, fontColor = T.Accent} or UI.Panel{height=0},
                    }},
                    C.ActionButton {
                        text = affordable and "收购" or "资金不足", height = 32, paddingH = 16,
                        disabled = not affordable,
                        onClick = function()
                            FN.ExecuteMA(GD, capturedTarget)
                            -- 从列表移除
                            for i, t in ipairs(M._maTargets) do
                                if t.name == capturedTarget.name then table.remove(M._maTargets, i); break end
                            end
                            navigate("invest")
                        end,
                    },
                }})
            end
        end

        -- 并购历史
        if GD.maHistory and #GD.maHistory > 0 then
            table.insert(children, C.SectionTitle {text = "并购记录"})
            for _, ma in ipairs(GD.maHistory) do
                table.insert(children, C.InfoRow {label = ma.name .. "(" .. ma.type .. ")", value = C.FormatMoney(ma.price) .. " | 第" .. ma.year .. "年"})
            end
        end

        -- ===== IPO =====
        table.insert(children, UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=8})
        table.insert(children, C.SectionTitle {text = "IPO上市", color = T.Accent})

        if GD.company.isListed then
            table.insert(children, C.Card {children = {
                UI.Label {text = "公司已上市!", fontSize = T.FontSubtitle, fontColor = T.Success},
                C.InfoRow {label = "市值", value = C.FormatMoney(GD.company.marketCap or 0), color = T.Accent},
            }})
        else
            local conditions, allPass = FN.CheckIPOConditions(GD)
            local condCards = {}
            for _, cond in ipairs(conditions) do
                table.insert(condCards, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", width = "100%", paddingVertical = 3,
                    children = {
                        UI.Label {text = cond.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        UI.Label {text = cond.ok and "通过" or "未达标", fontSize = T.FontSmall, fontColor = cond.ok and T.Success or T.Danger},
                    }
                })
            end
            table.insert(condCards, UI.Panel {width="100%", height=1, backgroundColor=T.Border, marginVertical=4})
            table.insert(condCards, C.ActionButton {
                text = allPass and "申请IPO上市" or "条件不足", height = 36, paddingH = 20,
                disabled = not allPass,
                onClick = function()
                    FN.ExecuteIPO(GD)
                    navigate("invest")
                end,
            })
            table.insert(children, C.Card {children = condCards})
        end

        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- ===== Tab6: 股票市场 =====
    local function buildStockMarket()
        if not GD.stockMarket then SM.Init(GD) end
        local sm = GD.stockMarket
        local children = {
            buildOperationCompanySelector(navigate),
        }

        -- 持仓汇总：零金额不显示，避免空数据产生孤立的“0万”
        local summary = SM.GetPortfolioSummary(GD)
        local profitColor = summary.totalProfit >= 0 and T.Success or T.Danger
        local summaryCards = {}
        if (summary.totalValue or 0) ~= 0 then
            table.insert(summaryCards, C.StatCard {title = "持仓市值", value = C.FormatMoney(summary.totalValue), color = T.Accent})
        end
        if (summary.totalCost or 0) ~= 0 then
            table.insert(summaryCards, C.StatCard {title = "持仓成本", value = C.FormatMoney(summary.totalCost), color = T.Info})
        end
        if (summary.totalProfit or 0) ~= 0 then
            table.insert(summaryCards, C.StatCard {title = "浮动盈亏", value = (summary.totalProfit >= 0 and "+" or "") .. C.FormatMoney(summary.totalProfit), color = profitColor})
        end
        if (summary.totalDividends or 0) ~= 0 then
            table.insert(summaryCards, C.StatCard {title = "已收分红", value = C.FormatMoney(summary.totalDividends), color = T.Warning})
        end
        if #summaryCards > 0 then
            table.insert(children, UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
                children = summaryCards,
            })
        end

        -- 子视图切换
        local viewNames = {"行情", "持仓", "交易记录"}
        local viewKeys = {"market", "holdings", "history"}
        local viewIdx = 1
        for i, k in ipairs(viewKeys) do if k == M._stockView then viewIdx = i end end
        table.insert(children, C.TabBar {
            tabs = viewNames, active = viewIdx,
            onChange = function(idx) M._stockView = viewKeys[idx]; navigate("invest") end,
        })

        if M._stockView == "market" then
            -- 行情列表
            table.insert(children, C.SectionTitle {text = "A股/港股行情 (" .. #sm.companies .. "家)"})
            for _, stock in ipairs(sm.companies) do
                local chgColor = stock.changePercent > 0 and T.Danger or (stock.changePercent < 0 and T.Success or T.TextSecondary)
                local chgSign = stock.changePercent > 0 and "+" or ""
                local holding = sm.holdings and sm.holdings[stock.code]
                local holdingText = holding and holding.shares > 0 and ("持仓" .. holding.shares .. "股") or ""

                -- 买入金额输入
                local buyKey = stock.code
                local buyAmt = M._stockBuyAmounts[buyKey] or 100
                local dividendStatus = stock.lastDividendStatus or "年度结算"
                local lossProb = stock.lossProbability or 0.6

                local rows = {
                    -- 股票名称 + 持仓标记
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                        children = {
                            UI.Label {text = stock.name .. " (" .. stock.code .. ")", fontSize = 15, fontWeight = "bold", fontColor = chgColor},
                            holdingText ~= "" and C.Badge {text = holdingText, variant = "accent"} or nil,
                        }
                    },
                    -- 紧凑横排：行业 + 市盈率 + 参考分红率 + 亏损风险
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap",
                        children = {
                            UI.Label {text = stock.industry, fontSize = 11, fontColor = T.TextSecondary, marginRight = 8},
                            UI.Label {text = "PE:" .. string.format("%.1f", stock.pe), fontSize = 11, fontColor = T.TextSecondary, marginRight = 8},
                            UI.Label {text = "参考年化分红:" .. string.format("%.2f%%", (stock.dividendRate or 0) * 100), fontSize = 11, fontColor = T.TextSecondary, marginRight = 8},
                            UI.Label {text = "亏损风险:" .. string.format("%.0f%%", lossProb * 100), fontSize = 11, fontColor = T.Warning},
                        }
                    },
                    -- 现价 + 涨跌幅紧凑横排
                    UI.Panel {
                        flexDirection = "row", gap = 12, width = "100%", alignItems = "center", marginTop = 2,
                        children = {
                            UI.Label {text = string.format("%.2f元", stock.currentPrice), fontSize = 16, fontWeight = "bold", fontColor = chgColor},
                            UI.Label {text = chgSign .. string.format("%.2f%%", stock.changePercent), fontSize = 14, fontColor = chgColor},
                        }
                    },
                    -- 上季度价格区间参考（基于最近3个月实际价格）
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", alignItems = "center",
                        children = (function()
                            local hist = stock.priceHistory or {}
                            local n = #hist
                            local quarterPrices = {}
                            for i = math.max(1, n - 2), n do
                                if hist[i] then table.insert(quarterPrices, hist[i]) end
                            end
                            local qMin, qMax = stock.currentPrice, stock.currentPrice
                            for _, p in ipairs(quarterPrices) do
                                if p < qMin then qMin = p end
                                if p > qMax then qMax = p end
                            end
                            return {
                                UI.Label {text = "上季度区间:", fontSize = 10, fontColor = T.TextMuted},
                                UI.Label {
                                    text = string.format("%.2f ~ %.2f元", qMin, qMax),
                                    fontSize = 10, fontColor = T.TextSecondary,
                                },
                                UI.Label {text = "波动率:" .. string.format("%.0f%%", stock.volatility * 100), fontSize = 10, fontColor = T.Warning, marginLeft = 8},
                            }
                        end)(),
                    },
                }

                if holdingText ~= "" then
                    table.insert(rows, C.InfoRow {label = "持仓", value = holdingText, color = T.Accent})
                    table.insert(rows, C.InfoRow {label = "已收分红", value = C.FormatMoney(holding.totalDividends or 0), color = T.Warning})
                    table.insert(rows, C.InfoRow {label = "上次分红", value = dividendStatus, color = T.TextSecondary})
                end

                -- 买入操作（手动输入份额/金额）
                local capturedCode = stock.code
                local captureBuyKey = buyKey
                -- 计算100股所需金额
                local per100Cost = math.ceil(stock.currentPrice * 100 / 10000 * 100) / 100
                table.insert(rows, UI.Panel {
                    width = "100%", gap = 4, marginTop = 6,
                    children = {
                        UI.Label {text = "买入金额（万元） 100股≈" .. string.format("%.2f万", per100Cost), fontSize = 11, fontColor = T.TextMuted},
                        UI.Panel {
                            flexDirection = "row", gap = 6, width = "100%", alignItems = "center",
                            children = {
                                UI.TextField {
                                    value = tostring(buyAmt),
                                    placeholder = "输入金额(万)",
                                    fontSize = 14,
                                    flex = 1,
                                    height = 36,
                                    borderRadius = 6,
                                    borderWidth = 1,
                                    borderColor = T.Border,
                                    paddingHorizontal = 8,
                                    keyboardType = "number",
                                    onChange = function(self, text)
                                        local num = tonumber(text)
                                        if num and num > 0 then
                                            M._stockBuyAmounts[captureBuyKey] = num
                                        end
                                    end,
                                },
                                C.ActionButton {
                                    text = "买入", bgColor = T.Danger, fontColor = T.TextOnDark,
                                    height = 36, paddingH = 16,
                                    onClick = function()
                                        local amt = M._stockBuyAmounts[captureBuyKey] or 100
                                        local ok, msg = SM.Buy(GD, capturedCode, amt)
                                        if ok then GD.AddEvent(msg, "success")
                                        else GD.AddEvent(msg, "warning") end
                                        navigate("invest")
                                    end,
                                },
                            }
                        },
                        -- 快捷金额按钮
                        UI.Panel {
                            flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap",
                            children = {
                                UI.Button {text = "10万", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockBuyAmounts[captureBuyKey] = 10; navigate("invest") end},
                                UI.Button {text = "50万", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockBuyAmounts[captureBuyKey] = 50; navigate("invest") end},
                                UI.Button {text = "100万", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockBuyAmounts[captureBuyKey] = 100; navigate("invest") end},
                                UI.Button {text = "500万", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockBuyAmounts[captureBuyKey] = 500; navigate("invest") end},
                                UI.Button {text = "1000万", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockBuyAmounts[captureBuyKey] = 1000; navigate("invest") end},
                            }
                        },
                    }
                })

                -- 卖出操作（仅持仓时显示，手动输入股数）
                if holding and holding.shares > 0 then
                    local capturedSellCode = stock.code
                    local capturedShares = holding.shares
                    local sellKey = capturedSellCode
                    local sellAmt = M._stockSellShares[sellKey] or 100
                    table.insert(rows, UI.Panel {
                        width = "100%", gap = 4, marginTop = 6,
                        children = {
                            UI.Label {text = "卖出股数（持有" .. capturedShares .. "股）", fontSize = 11, fontColor = T.TextMuted},
                            UI.Panel {
                                flexDirection = "row", gap = 6, width = "100%", alignItems = "center",
                                children = {
                                    UI.TextField {
                                        value = tostring(sellAmt),
                                        placeholder = "输入股数",
                                        fontSize = 14, flex = 1, height = 36,
                                        borderRadius = 6, borderWidth = 1, borderColor = T.Border,
                                        paddingHorizontal = 8, keyboardType = "number",
                                        onChange = function(self, text)
                                            local num = tonumber(text)
                                            if num and num > 0 then
                                                M._stockSellShares[sellKey] = math.floor(num)
                                            end
                                        end,
                                    },
                                    C.ActionButton {
                                        text = "卖出", bgColor = T.Warning, fontColor = T.TextOnDark,
                                        height = 36, paddingH = 16,
                                        onClick = function()
                                            local shares = M._stockSellShares[sellKey] or 100
                                            local ok, msg = SM.Sell(GD, capturedSellCode, shares)
                                            if ok then GD.AddEvent(msg, "success")
                                            else GD.AddEvent(msg, "warning") end
                                            M._stockSellShares[sellKey] = nil
                                            navigate("invest")
                                        end,
                                    },
                                }
                            },
                            -- 快捷卖出按钮
                            UI.Panel {
                                flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap",
                                children = {
                                    UI.Button {text = "100股", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[sellKey] = 100; navigate("invest") end},
                                    UI.Button {text = "500股", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[sellKey] = 500; navigate("invest") end},
                                    UI.Button {text = "1000股", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[sellKey] = 1000; navigate("invest") end},
                                    UI.Button {text = "1/2仓", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[sellKey] = math.floor(capturedShares / 2 / 100) * 100; navigate("invest") end},
                                    UI.Button {text = "全部", fontSize = 11, backgroundColor = T.Warning, fontColor = T.TextOnDark, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[sellKey] = capturedShares; navigate("invest") end},
                                },
                            },
                        }
                    })
                end

                table.insert(children, C.Card {
                    children = rows,
                })
            end

        elseif M._stockView == "holdings" then
            -- 持仓列表
            table.insert(children, C.SectionTitle {text = "我的持仓"})
            local hasHolding = false
            if sm.holdings then
                for code, holding in pairs(sm.holdings) do
                    if holding.shares > 0 then
                        hasHolding = true
                        local stockInfo
                        for _, s in ipairs(sm.companies) do
                            if s.code == code then stockInfo = s; break end
                        end
                        if stockInfo then
                            local marketVal = holding.shares * stockInfo.currentPrice / 10000
                            local costVal = holding.shares * holding.avgCost / 10000
                            local profit = marketVal - costVal
                            local profitPct = costVal > 0 and (profit / costVal * 100) or 0
                            local pColor = profit >= 0 and T.Success or T.Danger

                            local capturedSCode = code
                            local capturedSShares = holding.shares
                            table.insert(children, C.Card {
                                title = stockInfo.name .. " (" .. code .. ")",
                                children = {
                                    -- 紧凑横排：股数 + 成本 + 现价
                                    UI.Panel {
                                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap",
                                        children = {
                                            UI.Label {text = holding.shares .. "股", fontSize = 12, fontColor = T.TextPrimary, marginRight = 8},
                                            UI.Label {text = "成本:" .. string.format("%.2f", holding.avgCost), fontSize = 11, fontColor = T.TextSecondary, marginRight = 8},
                                            UI.Label {text = "现价:" .. string.format("%.2f", stockInfo.currentPrice), fontSize = 11, fontColor = T.TextSecondary},
                                        }
                                    },
                                    C.InfoRow {label = "市值", value = C.FormatMoney(math.floor(marketVal * 100) / 100)},
                                    C.InfoRow {label = "盈亏", value = (profit >= 0 and "+" or "") .. C.FormatMoney(math.floor(profit * 100) / 100), color = pColor},
                                    C.InfoRow {label = "收益率", value = string.format("%.1f%%", profitPct), color = pColor},
                                    C.InfoRow {label = "已收分红", value = C.FormatMoney(holding.totalDividends or 0)},
                                    -- 手动输入卖出股数
                                    UI.Label {text = "卖出股数", fontSize = 11, fontColor = T.TextMuted, marginTop = 6},
                                    UI.Panel {
                                        flexDirection = "row", gap = 6, width = "100%", alignItems = "center",
                                        children = {
                                            UI.TextField {
                                                value = tostring(M._stockSellShares[capturedSCode] or 100),
                                                placeholder = "输入股数",
                                                fontSize = 14, flex = 1, height = 36,
                                                borderRadius = 6, borderWidth = 1, borderColor = T.Border,
                                                paddingHorizontal = 8, keyboardType = "number",
                                                onChange = function(self, text)
                                                    local num = tonumber(text)
                                                    if num and num > 0 then
                                                        M._stockSellShares[capturedSCode] = math.floor(num)
                                                    end
                                                end,
                                            },
                                            C.ActionButton {
                                                text = "卖出", bgColor = T.Warning, fontColor = T.TextOnDark,
                                                height = 36, paddingH = 16,
                                                onClick = function()
                                                    local shares = M._stockSellShares[capturedSCode] or 100
                                                    local ok, msg = SM.Sell(GD, capturedSCode, shares)
                                                    if ok then GD.AddEvent(msg, "success") else GD.AddEvent(msg, "warning") end
                                                    M._stockSellShares[capturedSCode] = nil
                                                    navigate("invest")
                                                end,
                                            },
                                        }
                                    },
                                    UI.Panel {
                                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap",
                                        children = {
                                            UI.Button {text = "100股", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[capturedSCode] = 100; navigate("invest") end},
                                            UI.Button {text = "500股", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[capturedSCode] = 500; navigate("invest") end},
                                            UI.Button {text = "1/2仓", fontSize = 11, backgroundColor = T.Surface, fontColor = T.TextSecondary, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[capturedSCode] = math.floor(capturedSShares / 2 / 100) * 100; navigate("invest") end},
                                            UI.Button {text = "全部", fontSize = 11, backgroundColor = T.Warning, fontColor = T.TextOnDark, borderRadius = 4, paddingHorizontal = 8, height = 26, onClick = function() M._stockSellShares[capturedSCode] = capturedSShares; navigate("invest") end},
                                        },
                                    },
                                }
                            })
                        end
                    end
                end
            end
            if not hasHolding then
                table.insert(children, C.Card {children = {
                    UI.Label {text = "暂无持仓，请在行情页面买入股票", fontSize = 14, fontColor = T.TextSecondary},
                }})
            end

        elseif M._stockView == "history" then
            -- 交易记录
            table.insert(children, C.SectionTitle {text = "交易记录"})
            local hist = sm.history or {}
            if #hist == 0 then
                table.insert(children, C.Card {children = {
                    UI.Label {text = "暂无交易记录", fontSize = 14, fontColor = T.TextSecondary},
                }})
            else
                -- 显示最近20条，倒序
                local startIdx = math.max(1, #hist - 19)
                for i = #hist, startIdx, -1 do
                    local tx = hist[i]
                    local isBuy = tx.type == "buy"
                    local txColor = isBuy and T.Danger or T.Success
                    local txLabel = isBuy and "买入" or "卖出"
                    local profitText = ""
                    if not isBuy and tx.profit then
                        profitText = tx.profit >= 0 and (" 盈利" .. C.FormatMoney(math.floor(tx.profit * 100) / 100)) or (" 亏损" .. C.FormatMoney(math.floor(math.abs(tx.profit) * 100) / 100))
                    end
                    table.insert(children, C.Card {children = {
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", width = "100%",
                            children = {
                                UI.Label {text = txLabel .. " " .. tx.name, fontSize = 14, fontWeight = "bold", fontColor = txColor},
                                UI.Label {text = (tx.year or "") .. "年" .. (tx.mon or "") .. "月", fontSize = 12, fontColor = T.TextSecondary},
                            }
                        },
                        C.InfoRow {label = "价格", value = string.format("%.2f元", tx.price)},
                        C.InfoRow {label = "数量", value = tx.shares .. "股"},
                        C.InfoRow {label = "金额", value = C.FormatMoney(math.floor(tx.amount * 100) / 100)},
                        profitText ~= "" and UI.Label {text = profitText, fontSize = 13, fontColor = (tx.profit or 0) >= 0 and T.Success or T.Danger} or nil,
                    }})
                end
            end
        end

        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- ===== Tab7: 资产交易中心 =====
    local function buildAssetMarket()
        -- 确保市场已初始化
        if not GD.assetMarket then
            GD.assetMarket = {listings = {}, lastRefreshMonth = 0, nextId = 1}
        end
        local am = GD.assetMarket
        am.listings = am.listings or {}
        local children = {
            buildOperationCompanySelector(navigate),
        }

        -- 概览统计
        local availCount = 0
        for _, li in ipairs(am.listings) do
            if li.status == "available" then availCount = availCount + 1 end
        end
        local faCount = #GD.fixedAssets
        local faTotal = 0
        local faRent = 0
        for _, fa in ipairs(GD.fixedAssets) do
            faTotal = faTotal + (fa.currentValue or fa.originalValue or 0)
            faRent = faRent + (fa.monthlyRent or 0)
        end

        local assetSummaryCards = {
            C.StatCard {title = "在售物业", value = tostring(availCount) .. "处", color = T.Accent, flex = 1},
            C.StatCard {title = "持有资产", value = tostring(faCount) .. "项", color = T.Info, flex = 1},
        }
        if faTotal ~= 0 then
            table.insert(assetSummaryCards, C.StatCard {title = "资产总值", value = C.FormatMoney(faTotal), color = T.Success, flex = 1})
        end
        if faRent ~= 0 then
            table.insert(assetSummaryCards, C.StatCard {title = "月租金收入", value = C.FormatMoney(faRent), color = T.Warning, flex = 1})
        end
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
            children = assetSummaryCards,
        })

        -- 刷新提示
        local nextRefresh = 3 - ((GD.totalMonths - (am.lastRefreshMonth or 0)) % 3)
        if nextRefresh > 3 then nextRefresh = 3 end
        table.insert(children, UI.Panel {
            width = "100%", padding = 8, borderRadius = 6,
            backgroundColor = T.SurfaceSecondary or T.Surface,
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {text = "市场每季度刷新一批物业", fontSize = 12, fontColor = T.TextMuted},
                UI.Label {text = nextRefresh .. "个月后刷新", fontSize = 12, fontColor = T.Accent},
            }
        })

        -- 可购买物业列表
        table.insert(children, C.SectionTitle {text = "可购买商业物业"})

        local hasAvailable = false
        for _, listing in ipairs(am.listings) do
            if listing.status == "available" then
                hasAvailable = true
                local capLi = listing  -- 闭包捕获
                local yieldColor = (listing.rentYield or 0) >= 6 and T.Success or T.TextSecondary
                table.insert(children, C.Card {children = {
                    -- 标题行：名称 + 类型标签
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {text = listing.name, fontSize = 15, fontWeight = "bold", fontColor = T.TextPrimary, flexShrink = 1},
                            C.Badge {text = listing.type, variant = "info"},
                        }
                    },
                    -- 卖方信息
                    UI.Label {text = "卖方: " .. (listing.seller or ""), fontSize = 11, fontColor = T.TextMuted, marginTop = 2},
                    -- 核心指标紧凑横排
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", marginTop = 6,
                        children = {
                            UI.Label {text = "面积:" .. listing.area .. "㎡", fontSize = 12, fontColor = T.TextSecondary, marginRight = 6},
                            UI.Label {text = "总价:" .. C.FormatMoney(listing.price), fontSize = 12, fontColor = T.Danger, fontWeight = "bold", marginRight = 6},
                            UI.Label {text = "月租:" .. C.FormatMoney(listing.monthlyRent), fontSize = 12, fontColor = T.Success, marginRight = 6},
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", marginTop = 2,
                        children = {
                            UI.Label {text = "租金回报率:" .. string.format("%.1f%%", listing.rentYield or 0), fontSize = 12, fontColor = yieldColor, marginRight = 6},
                            UI.Label {text = "出租率:" .. string.format("%.0f%%", (listing.occupancy or 0) * 100), fontSize = 12, fontColor = T.TextSecondary},
                        }
                    },
                    -- 购买按钮
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "flex-end", marginTop = 6,
                        children = {
                            C.ActionButton {
                                text = "购入 " .. C.FormatMoney(listing.price),
                                height = 32, paddingH = 16,
                                disabled = GD.company.cash < listing.price,
                                onClick = function()
                                    local ok, msg = GD.BuyMarketAsset(capLi.id)
                                    if not ok then
                                        GD.AddEvent("购买失败: " .. (msg or ""), "danger")
                                    end
                                    navigate("invest")
                                end,
                            },
                        }
                    },
                }})
            end
        end

        if not hasAvailable then
            table.insert(children, UI.Panel {
                width = "100%", padding = 24, justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {text = "当前无在售物业", fontSize = 14, fontColor = T.TextMuted},
                    UI.Label {text = "市场每3个月刷新一批新物业", fontSize = 12, fontColor = T.TextMuted},
                }
            })
        end

        -- 已持有固定资产简报（来自市场购买的）
        local marketAssets = {}
        for _, fa in ipairs(GD.fixedAssets) do
            if fa.isMarketPurchase then
                table.insert(marketAssets, fa)
            end
        end
        if #marketAssets > 0 then
            table.insert(children, C.SectionTitle {text = "已购入资产(" .. #marketAssets .. "项)", color = T.Success})
            for _, fa in ipairs(marketAssets) do
                local profitRate = fa.originalValue > 0 and ((fa.currentValue - fa.originalValue) / fa.originalValue * 100) or 0
                local profitColor = profitRate >= 0 and T.Success or T.Danger
                table.insert(children, C.Card {children = {
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {text = fa.projectName or "商业资产", fontSize = 14, fontWeight = "bold", fontColor = T.TextPrimary, flexShrink = 1},
                            C.Badge {text = fa.assetType or "商业", variant = "success"},
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", marginTop = 4,
                        children = {
                            UI.Label {text = "原价:" .. C.FormatMoney(fa.originalValue), fontSize = 12, fontColor = T.TextSecondary, marginRight = 6},
                            UI.Label {text = "现值:" .. C.FormatMoney(fa.currentValue), fontSize = 12, fontColor = profitColor, marginRight = 6},
                            UI.Label {text = string.format("%.1f%%", profitRate), fontSize = 12, fontColor = profitColor},
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4, width = "100%", flexWrap = "wrap", marginTop = 2,
                        children = {
                            UI.Label {text = "面积:" .. (fa.holdArea or 0) .. "㎡", fontSize = 12, fontColor = T.TextSecondary, marginRight = 6},
                            UI.Label {text = "月租:" .. C.FormatMoney(fa.monthlyRent or 0), fontSize = 12, fontColor = T.Success, marginRight = 6},
                            fa.mortgaged and C.Badge {text = "已抵押", variant = "warning"} or nil,
                        }
                    },
                }})
            end
        end

        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- Tab内容
    local tabContent
    if activeTab == 1 then tabContent = buildLandMarket()
    elseif activeTab == 2 then tabContent = buildLandReserve()
    elseif activeTab == 3 then tabContent = buildInvestCalc()
    elseif activeTab == 4 then tabContent = buildMarketTrend()
    elseif activeTab == 5 then tabContent = buildCompetitors()
    elseif activeTab == 6 then tabContent = buildStockMarket()
    elseif activeTab == 7 then tabContent = buildAssetMarket()
    else tabContent = buildLandMarket() end

    -- 资产交易中心物业数量
    local amCount = 0
    if GD.assetMarket and GD.assetMarket.listings then
        for _, li in ipairs(GD.assetMarket.listings) do
            if li.status == "available" then amCount = amCount + 1 end
        end
    end

    local availableLandReserveCount = 0
    for _, land in ipairs(GD.landReserve or {}) do
        if isCompanyCityLand(land) then
            local hasProj = false
            for _, p in ipairs(GD.projects or {}) do
                if p.land and p.land.id == land.id then hasProj = true; break end
            end
            if not hasProj then availableLandReserveCount = availableLandReserveCount + 1 end
        end
    end

    local landMarketCount = 0
    for _, land in ipairs(GD.landMarket or {}) do
        if land.status == "available" or land.status == "negotiable" or land.status == "locked" or land.status == "for_sale" then
            landMarketCount = landMarketCount + 1
        end
    end

    local tabNames = {
        "土地市场(" .. landMarketCount .. ")",
        "土地储备(" .. availableLandReserveCount .. ")",
        "投资测算",
        "市场趋势",
        "竞争对手(" .. (GD.competitors and #GD.competitors or 0) .. ")",
        "股市",
        "资产交易" .. (amCount > 0 and ("(" .. amCount .. ")") or ""),
    }

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 12,
        children = {
            C.SectionTitle {text = "投资发展中心"},
            C.TabBar {
                tabs = tabNames, active = activeTab,
                onChange = function(idx) M._activeTab = idx; navigate("invest") end,
            },
            tabContent,
            UI.Panel {height = 20},
        }
    }
end

return M
