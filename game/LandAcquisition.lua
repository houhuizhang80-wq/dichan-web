---@diagnostic disable: return-type-mismatch
-- ============================================================================
-- LandAcquisition.lua - 土地获取与投资决策系统
-- 从 GameData.lua 抽取土地生成/投资测算/AI竞价逻辑，并扩展多渠道、尽调、敏感性分析
-- ============================================================================

local DT = require("DevTypes")
local LA = {}

-- ============================================================================
-- 常量
-- ============================================================================

--- 土地获取渠道
LA.CHANNELS = {
    PUBLIC_AUCTION  = "public_auction",   -- 招拍挂（政府公开出让）
    NEGOTIATION     = "negotiation",      -- 勾地协议（提前锁定）
    JUDICIAL        = "judicial",         -- 法拍平台（司法拍卖）
    SECONDARY       = "secondary",        -- 二手土地（开发商转让）
}

LA.CHANNEL_NAMES = {
    public_auction = "招拍挂",
    negotiation    = "勾地协议",
    judicial       = "法拍平台",
    secondary      = "二手土地",
}

--- 尽职调查项目
LA.SURVEY_TYPES = {
    SITE       = "site",        -- 现状勘察
    RADON      = "radon",       -- 土壤氡检测
    PIPELINE   = "pipeline",    -- 地下管线勘探
    RELIC      = "relic",       -- 文物勘探
}

--- 尽调配置: 费用(万元)、工期(月)、风险描述
LA.SURVEY_CONFIG = {
    site     = { cost = 5,  months = 1, name = "现状勘察",     desc = "排查高压线/坟墓/违建",    riskDesc = "发现违建需拆除" },
    radon    = { cost = 8,  months = 1, name = "土壤氡检测",   desc = "检测土壤氡含量是否超标",  riskDesc = "氡超标需治理" },
    pipeline = { cost = 15, months = 2, name = "地下管线勘探", desc = "燃气/电力/通信管线排查",  riskDesc = "管线迁改增加成本" },
    relic    = { cost = 20, months = 3, name = "文物勘探",     desc = "考古勘探排查文物风险",    riskDesc = "发现古墓将暂停施工" },
}

--- 区位数据（与原 GenerateLand 保持一致）
local LOCATIONS = {
    { name = "城东新区",   factor = 0.9  },
    { name = "城南CBD",    factor = 1.3  },
    { name = "城西科技园", factor = 1.1  },
    { name = "城北新城",   factor = 0.85 },
    { name = "老城区",     factor = 1.0  },
    { name = "高新区",     factor = 1.2  },
    { name = "滨江区",     factor = 1.15 },
    { name = "经开区",     factor = 0.95 },
}

--- 土地生成时的税后净利率分布（按销售总额口径）。
--- 25% 地块目标为亏损，避免所有项目天然盈利；其余地块以微利和正常利润为主。
local LAND_PROFIT_BUCKETS = {
    { maxRoll = 9,  minMargin = -0.20, maxMargin = -0.08 },
    { maxRoll = 24, minMargin = -0.08, maxMargin = 0.00 },
    { maxRoll = 64, minMargin = 0.00,  maxMargin = 0.12 },
    { maxRoll = 89, minMargin = 0.12,  maxMargin = 0.22 },
    { maxRoll = 99, minMargin = 0.22,  maxMargin = 0.30 },
}

local function rollTargetNetMargin()
    local roll = math.random(0, 99)
    for _, bucket in ipairs(LAND_PROFIT_BUCKETS) do
        if roll <= bucket.maxRoll then
            return bucket.minMargin + math.random() * (bucket.maxMargin - bucket.minMargin)
        end
    end
    return 0
end

--- 地价总价区间限制（万元）
--- 最低500万，最高200亿元；高容积率大地块不能再被20亿元旧上限压成暴利项目。
local LAND_PRICE_LIMITS = {
    [3] = { min = 500, max = 2000000 },
}

local function getDefaultDevTypeForUseType(useType)
    if useType == "商业" then return "office_building" end
    return "rigid_residential"
end

-- ============================================================================
-- 内部工具函数
-- ============================================================================

--- 生成土地ID
---@param year number
---@param month number
---@param channel string
---@return string
local function makeLandId(year, month, channel)
    local prefix = "L"
    if channel == LA.CHANNELS.JUDICIAL then prefix = "LJ"
    elseif channel == LA.CHANNELS.NEGOTIATION then prefix = "LN"
    elseif channel == LA.CHANNELS.SECONDARY then prefix = "LS"
    end
    return prefix .. year .. string.format("%02d", month) .. "-" .. math.random(100, 999)
end

--- 早期地价折扣已停用：售价锚定后，利润率统一由反推地价控制
---@param totalMonths number
---@return number
local function calcEarlyFactor(totalMonths)
    return 1.0
end

--- 生成配建要求列表
---@param policy table  GD.policy.land
---@return table
local function generateRequirements(policy)
    local reqs = {}
    local mandatoryBuild = policy.mandatoryBuild or 0
    if math.random() > (0.5 - mandatoryBuild * 0.1) then
        table.insert(reqs, "配建幼儿园")
    end
    -- 已移除自持商业强制要求，玩家可自由选择销售/自持比例
    if math.random() > (0.8 - mandatoryBuild * 0.15) then
        local holdPct = math.max(5, math.floor(5 + mandatoryBuild * 3))
        table.insert(reqs, "配建保障房" .. holdPct .. "%")
    end
    local maxPremiumRate = policy.maxPremiumRate or 999
    if maxPremiumRate < 100 then
        table.insert(reqs, "限溢价率" .. math.floor(maxPremiumRate) .. "%")
    end
    return reqs
end

--- 生成一块基础地块数据（不含渠道信息）
---@param city table      城市数据
---@param economy table   经济数据
---@param policy table    GD.policy
---@param totalMonths number
---@param year number
---@param month number
---@return table land
local function generateBaseLand(city, economy, policy, totalMonths, year, month)
    local useTypes = { "住宅", "商业" }
    local useType = useTypes[math.random(1, #useTypes)]
    local loc = LOCATIONS[math.random(1, #LOCATIONS)]

    -- 地块面积 & 容积率
    local isEarlyTier3 = (city.tier == 3 and totalMonths < 120)
    local area, far
    if isEarlyTier3 and math.random() < 0.7 then
        area = math.random(5, 30) * 1000
        far = ({ 1.2, 1.5, 2.0, 2.5 })[math.random(1, 4)]
    else
        area = math.random(3, 20) * 10000
        far = ({ 1.5, 2.0, 2.5, 3.0, 3.5 })[math.random(1, 5)]
    end
    local buildArea = math.floor(area * far)

    -- 楼面地价：按销售总额口径的目标税后净利率反推，让地价成为主要利润控制阀。
    local defaultDevType = getDefaultDevTypeForUseType(useType)
    local typeDef = DT.GetType(defaultDevType)
    local plotLocation = loc.factor >= 1.1 and "core" or "suburb"
    local targetPrice = DT.GetExpectedPrice(defaultDevType, city.avgPrice, plotLocation, "basic", nil)
    targetPrice = targetPrice * (economy.priceIndex / 100)
    local saleAreaRatio = 0.85
    local projectedRevenuePerBuildSqm = targetPrice * saleAreaRatio
    local buildCostPerSqm = DT.GetBuildCost(defaultDevType, city.avgPrice, plotLocation, "basic", nil)
    local designCostPerSqm = buildCostPerSqm * ((typeDef and typeDef.designCostRatio) or 0.05)
    local marketingCostPerSqm = projectedRevenuePerBuildSqm * 0.03
    local targetNetMargin = rollTargetNetMargin()
    local targetNetProfitPerBuildSqm = projectedRevenuePerBuildSqm * targetNetMargin
    local targetGrossProfitPerBuildSqm = targetNetProfitPerBuildSqm > 0
        and (targetNetProfitPerBuildSqm / 0.80) or targetNetProfitPerBuildSqm
    local targetCostPerBuildSqm = projectedRevenuePerBuildSqm - targetGrossProfitPerBuildSqm
    local nonLandCostPerSqm = buildCostPerSqm + designCostPerSqm + marketingCostPerSqm
    -- 土地融资成本按总工期另行计入项目成本；此处预留地价4%，避免生成地价系统性偏高。
    local floorPrice = (targetCostPerBuildSqm - nonLandCostPerSqm) / 1.04
    floorPrice = math.max(targetPrice * 0.08, floorPrice)
    floorPrice = floorPrice * calcEarlyFactor(totalMonths)

    local totalPrice = math.floor(floorPrice * buildArea / 10000)
    -- 按城市等级限制总价区间
    local priceLimits = LAND_PRICE_LIMITS[city.tier] or LAND_PRICE_LIMITS[3]
    totalPrice = math.max(priceLimits.min, math.min(priceLimits.max, totalPrice))
    floorPrice = buildArea > 0 and (totalPrice * 10000 / buildArea) or floorPrice

    local land = {
        id = makeLandId(year, month, LA.CHANNELS.PUBLIC_AUCTION),
        city = city.name,
        location = loc.name,
        useType = useType,
        area = area,
        far = far,
        buildArea = buildArea,
        floorPrice = math.floor(floorPrice),
        plotLocation = plotLocation,
        density = math.random(20, 35),
        greenRate = math.random(25, 40),
        heightLimit = ({ 60, 80, 100, 150, 0 })[math.random(1, 5)],
        startPrice = totalPrice,
        targetNetMargin = targetNetMargin,
        deposit = math.floor(totalPrice * 0.2),
        requirements = generateRequirements(policy.land),
        status = "available",
        listedYear = year,
        listedMonth = month,
        channel = LA.CHANNELS.PUBLIC_AUCTION,
        channelData = {},          -- 渠道专属数据（Phase 2 填充）
        dueDiligence = {           -- 尽调状态
            completed = {},        -- 已完成项: {type, cost, months, result}
            skipped = {},          -- 已跳过项: {type}
            totalCost = 0,         -- 已花费尽调费用(万元)
            totalMonths = 0,       -- 已花费尽调时间(月)
            risks = {},            -- 已发现的风险: {type, desc, costImpact}
        },
    }
    return land
end

-- ============================================================================
-- 公开API: 招拍挂生成（等价于原 GD.GenerateLand）
-- ============================================================================

--- 生成招拍挂土地（政府公开出让）
--- 完全保持原 GD.GenerateLand 的行为，仅为每块地添加 channel/channelData/dueDiligence 字段
---@param ctx table  { city, economy, policy, totalMonths, year, month, landMarket }
function LA.GeneratePublicAuction(ctx, minimumCount)
    local city = ctx.city
    if not city then return 0 end

    local supplyPace = ctx.policy.land.supplyPace or 1.0
    local isEarlyTier3 = (city.tier == 3 and ctx.totalMonths < 120)

    local count = math.random(1, 2)
    if isEarlyTier3 then count = math.random(2, 3) end
    if supplyPace > 1.2 and math.random() < 0.5 then count = count + 1
    elseif supplyPace < 0.8 and count > 1 and math.random() < 0.5 then count = count - 1 end
    if ctx.strictCount then
        count = math.max(0, math.floor(tonumber(minimumCount) or 0))
    else
        count = math.max(count, math.max(0, math.floor(tonumber(minimumCount) or 0)))
    end

    for _ = 1, count do
        local land = generateBaseLand(city, ctx.economy, ctx.policy, ctx.totalMonths, ctx.year, ctx.month)
        land.channel = LA.CHANNELS.PUBLIC_AUCTION
        land.id = makeLandId(ctx.year, ctx.month, LA.CHANNELS.PUBLIC_AUCTION)
        table.insert(ctx.landMarket, land)
    end

    return count
end

-- ============================================================================
-- 公开API: 投资测算（等价于原 GD.CalcInvestment + 尽调成本）
-- ============================================================================

--- 计算地块投资测算
--- 保持原 GD.CalcInvestment 的全部输出字段，新增 ddCost（尽调成本）
---@param land table
---@param city table
---@param economy table
---@param traitEffects table|nil  GD.company.traitEffects（可选）
---@return table|nil
function LA.CalcInvestment(land, city, economy, traitEffects)
    if not city or not land then return nil end
    local buildArea = land.buildArea
    local sellArea = math.floor(buildArea * 0.85)

    -- 建安成本(元/平) — 根据土地用途选择默认开发类型估算
    local defaultDevType = getDefaultDevTypeForUseType(land.useType)
    local plotLocation = land.plotLocation or "suburb"
    local unitBuildCost = DT.GetBuildCost(defaultDevType, city.avgPrice, plotLocation, "basic",
        traitEffects and traitEffects.buildCostBonus or 0)
    local buildCost = math.floor(buildArea * unitBuildCost / 10000)
    local typeDef = DT.GetType(defaultDevType)
    local designCostRatio = (typeDef and typeDef.designCostRatio) or 0.05
    local designCost = math.floor(buildCost * designCostRatio)
    local financeCost = math.floor(land.startPrice * 0.04)

    -- 尽调成本（Phase 1: 从已完成尽调中累加）
    local ddCost = 0
    if land.dueDiligence then
        ddCost = land.dueDiligence.totalCost or 0
        for _, risk in ipairs(land.dueDiligence.risks or {}) do
            ddCost = ddCost + (risk.costImpact or 0)
        end
    end

    -- 预计售价：锚定城市房价，地价仅影响利润率
    local floorPrice = land.floorPrice or 0
    local estPrice = DT.GetExpectedPrice(defaultDevType, city.avgPrice, plotLocation, "basic", floorPrice)
    estPrice = math.floor(estPrice * (economy.priceIndex / 100))
    local totalRevenue = math.floor(sellArea * estPrice / 10000)
    local marketingCost = math.floor(totalRevenue * 0.03)
    local totalCostBeforeTax = land.startPrice + buildCost + designCost + marketingCost + financeCost + ddCost
    local grossProfit = totalRevenue - totalCostBeforeTax
    local incomeTax = grossProfit > 0 and math.floor(grossProfit * 0.20) or 0
    local totalCost = totalCostBeforeTax + incomeTax
    local profit = totalRevenue - totalCost
    local profitRate = totalRevenue > 0 and math.floor(profit / totalRevenue * 100) or 0
    local roi = totalCost > 0 and math.floor(profit / totalCost * 100) or 0

    -- 预计工期(月)
    local estMonths = math.max(18, math.floor(buildArea / 10000 * 2))
    -- 去化周期(月)
    local sellMonths = math.max(6, math.min(60,
        math.floor(sellArea / 100 / math.max(1, math.floor(30 * economy.demandMultiplier * 0.15)))))

    return {
        landCost = land.startPrice,
        buildCost = buildCost,
        designCost = designCost,
        marketingCost = marketingCost,
        financeCost = financeCost,
        taxCost = incomeTax,
        incomeTax = incomeTax,
        totalCostBeforeTax = totalCostBeforeTax,
        ddCost = ddCost,                   -- 新增: 尽调+风险成本
        totalCost = totalCost,
        estPrice = math.floor(estPrice),
        totalRevenue = totalRevenue,
        profit = profit,
        profitRate = profitRate,
        roi = roi,
        sellArea = sellArea,
        totalUnits = math.floor(sellArea / 100),
        estMonths = estMonths,
        sellMonths = sellMonths,
        floorPrice = land.floorPrice or 0,
        priceLandRatio = (land.floorPrice or 0) > 0
            and math.floor((land.floorPrice or 0) / estPrice * 100) or 0,
    }
end

-- ============================================================================
-- 公开API: AI竞价逻辑（等价于原 GD.GetAIBid + 渠道感知）
-- ============================================================================

--- AI竞价决策
---@param land table
---@param currentPrice number
---@param competitor table  { aggressive, ... }
---@return number|nil  出价金额或nil（放弃）
function LA.GetAIBid(land, currentPrice, competitor)
    local valueRatio = land.startPrice / currentPrice
    local willBid = math.random() < (competitor.aggressive * valueRatio)
    if not willBid then return nil end
    local increment = ({ 100, 200, 500, 500, 1000 })[math.random(1, 5)]
    return currentPrice + increment
end

-- ============================================================================
-- 公开API: 勾地协议生成（提前锁定地块）
-- ============================================================================

--- 生成勾地协议土地
--- 特点：需预付诚意金(5-10% 地价)，价格略低于招拍挂，有排他期
---@param ctx table  同 GeneratePublicAuction 的 ctx
function LA.GenerateNegotiation(ctx)
    local city = ctx.city
    if not city then return end
    -- 勾地不受供地节奏影响，所有城市都有机会
    -- 概率出现: 每次调用30%概率生成1块
    if math.random() > 0.30 then return end

    local land = generateBaseLand(city, ctx.economy, ctx.policy, ctx.totalMonths, ctx.year, ctx.month)
    land.channel = LA.CHANNELS.NEGOTIATION
    land.id = makeLandId(ctx.year, ctx.month, LA.CHANNELS.NEGOTIATION)
    -- 勾地价格比公开市场低5%-15%
    local discount = 0.85 + math.random() * 0.10
    land.floorPrice = math.floor(land.floorPrice * discount)
    land.startPrice = math.floor(land.startPrice * discount)
    land.deposit = math.floor(land.startPrice * 0.2)
    -- 渠道专属数据
    local earnestRate = 0.05 + math.random() * 0.05  -- 5%-10%
    land.channelData = {
        earnestMoney = math.floor(land.startPrice * earnestRate),  -- 诚意金(万元)
        earnestRate = math.floor(earnestRate * 100),                -- 诚意金比例%
        exclusivePeriod = math.random(2, 4),                       -- 排他期(月)
        negotiatedDiscount = math.floor((1 - discount) * 100),     -- 折扣率%
        earnestPaid = false,                                       -- 是否已支付诚意金
    }
    land.status = "negotiable"  -- 不同于 available，需先付诚意金
    table.insert(ctx.landMarket, land)
end

-- ============================================================================
-- 公开API: 法拍平台生成（司法拍卖不良资产）
-- ============================================================================

--- 生成法拍土地
--- 特点：起拍价为市场价60%-80%，可能有瑕疵（产权纠纷、债务），竞价更激烈
---@param ctx table  同 GeneratePublicAuction 的 ctx
function LA.GenerateJudicial(ctx)
    local city = ctx.city
    if not city then return end
    -- 经济下行期法拍更多（衰退/萧条期概率翻倍）
    local baseProbability = 0.15
    local cycle = ctx.economy.cycle or "boom"
    if cycle == "recession" or cycle == "depression" then
        baseProbability = 0.35
    end
    if math.random() > baseProbability then return end

    local land = generateBaseLand(city, ctx.economy, ctx.policy, ctx.totalMonths, ctx.year, ctx.month)
    land.channel = LA.CHANNELS.JUDICIAL
    land.id = makeLandId(ctx.year, ctx.month, LA.CHANNELS.JUDICIAL)
    -- 法拍起拍价: 市场价60%-80%
    local judicialDiscount = 0.60 + math.random() * 0.20
    land.floorPrice = math.floor(land.floorPrice * judicialDiscount)
    land.startPrice = math.floor(land.startPrice * judicialDiscount)
    land.deposit = math.floor(land.startPrice * 0.2)
    -- 法拍风险
    local risks = {}
    local riskPool = {
        { type = "lien",      desc = "存在抵押权未注销", costPct = 0.03 },
        { type = "dispute",   desc = "产权存在纠纷",     costPct = 0.05 },
        { type = "debt",      desc = "原业主拖欠税费",   costPct = 0.02 },
        { type = "occupant",  desc = "存在占用人需清退", costPct = 0.01 },
        { type = "pollution", desc = "疑似土壤污染",     costPct = 0.04 },
    }
    -- 每块法拍地 1-2 个潜在风险
    local riskCount = math.random(1, 2)
    local shuffled = {}
    for _, r in ipairs(riskPool) do table.insert(shuffled, r) end
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    for i = 1, math.min(riskCount, #shuffled) do
        table.insert(risks, {
            type = shuffled[i].type,
            desc = shuffled[i].desc,
            costImpact = math.floor(land.startPrice * shuffled[i].costPct),
            discovered = false,  -- 尽调后才暴露
        })
    end
    land.channelData = {
        judicialDiscount = math.floor((1 - judicialDiscount) * 100),  -- 折扣率%
        hiddenRisks = risks,         -- 潜在风险(尽调可发现)
        courtName = "第" .. math.random(1, 5) .. "中级人民法院",
        caseNumber = "(" .. ctx.year .. ")执" .. math.random(1000, 9999) .. "号",
        auctionRound = math.random(1, 2),  -- 第几次拍卖
    }
    table.insert(ctx.landMarket, land)
end

-- ============================================================================
-- 公开API: 二手土地生成（开发商转让未开发地块）
-- ============================================================================

--- 生成二手土地
--- 特点：无需竞拍，直接议价；卖方开价含溢价；可能附带已有规划
---@param ctx table  同 GeneratePublicAuction 的 ctx
function LA.GenerateSecondary(ctx)
    local city = ctx.city
    if not city then return end
    -- 概率出现: 20%，繁荣期更少（开发商不缺钱），衰退期更多
    local baseProbability = 0.20
    local cycle = ctx.economy.cycle or "boom"
    if cycle == "boom" then baseProbability = 0.10
    elseif cycle == "recession" or cycle == "depression" then baseProbability = 0.35
    end
    if math.random() > baseProbability then return end

    local land = generateBaseLand(city, ctx.economy, ctx.policy, ctx.totalMonths, ctx.year, ctx.month)
    land.channel = LA.CHANNELS.SECONDARY
    land.id = makeLandId(ctx.year, ctx.month, LA.CHANNELS.SECONDARY)
    -- 二手土地: 卖方加价5%-20%（急售时可能平价甚至打折）
    local urgency = math.random()  -- 0=不急, 1=急售
    local markup
    if urgency < 0.3 then
        markup = 1.10 + math.random() * 0.10   -- 10%-20% 溢价
    elseif urgency < 0.7 then
        markup = 1.0 + math.random() * 0.05    -- 0%-5% 溢价
    else
        markup = 0.90 + math.random() * 0.10   -- 急售: -10%~0% 折扣
    end
    land.floorPrice = math.floor(land.floorPrice * markup)
    land.startPrice = math.floor(land.startPrice * markup)
    land.deposit = math.floor(land.startPrice * 0.1)  -- 二手定金较低
    -- 卖方信息
    local sellers = { "恒通地产", "中岚控股", "蓝川发展", "阳川城", "泰川集团", "华川安居" }
    land.channelData = {
        sellerType = "npc",
        sellerName = sellers[math.random(1, #sellers)],
        askingPrice = land.startPrice,                      -- 卖方报价(万元)
        negotiable = urgency > 0.4,                         -- 是否可议价
        urgency = urgency < 0.3 and "low" or (urgency < 0.7 and "medium" or "high"),
        holdingYears = math.random(1, 5),                   -- 持有年限
        remainingPermitYears = math.max(30, 70 - math.random(0, 20)), -- 剩余使用年限
        existingPlan = math.random() < 0.4,                 -- 是否有已批规划
    }
    land.status = "for_sale"  -- 二手在售状态
    table.insert(ctx.landMarket, land)
end

-- ============================================================================
-- 公开API: 编排器 — 每次供地周期综合生成多渠道土地
-- ============================================================================

--- 综合调度所有渠道的土地生成
--- 替代原来的 GD.GenerateLand()，在 MonthlyTick 中调用
---@param ctx table  { city, economy, policy, totalMonths, year, month, landMarket }
function LA.GenerateAllChannels(ctx, minimumPublicCount)
    -- 1. 招拍挂（基础渠道，始终生成）
    local publicCount = LA.GeneratePublicAuction(ctx, minimumPublicCount)
    -- 2. 勾地协议（概率触发）
    LA.GenerateNegotiation(ctx)
    -- 3. 法拍（经济下行时概率更高）
    LA.GenerateJudicial(ctx)
    -- 4. 二手转让（经济周期敏感）
    LA.GenerateSecondary(ctx)
    -- 总量限制：9个城市至少保留27块，市场容量放宽到80块
    while #ctx.landMarket > 80 do
        table.remove(ctx.landMarket, 1)
    end
    return publicCount
end

-- ============================================================================
-- 公开API: 勾地操作（支付诚意金锁定）
-- ============================================================================

--- 玩家支付诚意金锁定勾地
---@param land table  必须是 channel=negotiation 的地块
---@param companyCash number  当前公司现金
---@return boolean success
---@return string message
function LA.PayEarnest(land, companyCash, companyCity)
    if companyCity and companyCity ~= "" and land.city ~= companyCity then
        return false, "当前公司注册地为" .. companyCity .. "，只能在本城市拿地"
    end
    if land.channel ~= LA.CHANNELS.NEGOTIATION then
        return false, "该地块不是勾地协议类型"
    end
    local cd = land.channelData
    if cd.earnestPaid then
        return false, "已支付诚意金"
    end
    if companyCash < cd.earnestMoney then
        return false, "现金不足，需要" .. cd.earnestMoney .. "万元诚意金"
    end
    cd.earnestPaid = true
    land.status = "locked"  -- 锁定状态，进入排他期
    return true, "成功支付诚意金" .. cd.earnestMoney .. "万元，排他期" .. cd.exclusivePeriod .. "个月"
end

--- 勾地确认摘牌（排他期内完成交易）
---@param land table
---@return boolean success
---@return string message
function LA.ConfirmNegotiation(land, companyCity)
    if companyCity and companyCity ~= "" and land.city ~= companyCity then
        return false, "当前公司注册地为" .. companyCity .. "，只能在本城市拿地"
    end
    if land.channel ~= LA.CHANNELS.NEGOTIATION then
        return false, "该地块不是勾地协议类型"
    end
    if not land.channelData.earnestPaid then
        return false, "尚未支付诚意金"
    end
    land.status = "acquired"
    return true, "勾地成功，" .. land.location .. "地块已摘牌"
end

function LA.EvaluateSecondaryOffer(land, offerPrice)
    if not land or land.channel ~= LA.CHANNELS.SECONDARY then
        return false, "该地块不是二手转让类型", nil
    end
    local cd = land.channelData or {}
    local askingPrice = tonumber(cd.askingPrice) or tonumber(land.startPrice) or 0
    offerPrice = math.floor(tonumber(offerPrice) or 0)
    if askingPrice <= 0 or offerPrice <= 0 then
        return false, "报价必须大于0", nil
    end
    if offerPrice < askingPrice * 0.80 then
        return false, "出价过低，卖方拒绝（最低接受报价的80%）", nil
    end
    if offerPrice >= askingPrice then
        return true, "卖方接受报价，成交价" .. offerPrice .. "万元", offerPrice
    end
    local acceptProb = 0.3
    if cd.urgency == "high" then acceptProb = 0.7
    elseif cd.urgency == "medium" then acceptProb = 0.5 end
    local ratio = offerPrice / askingPrice
    acceptProb = acceptProb + (ratio - 0.8) * 2
    if math.random() < acceptProb then
        local finalPrice = math.floor((offerPrice + askingPrice) / 2)
        return true, "议价成功，成交价" .. finalPrice .. "万元", finalPrice
    end
    return false, "卖方暂不接受该价格，可再次出价", nil
end

--- 二手土地议价购买
---@param land table
---@param offerPrice number  出价(万元)
---@return boolean success
---@return string message
---@return number|nil finalPrice  成交价
function LA.NegotiateSecondary(land, offerPrice, companyCity)
    if companyCity and companyCity ~= "" and land.city ~= companyCity then
        return false, "当前公司注册地为" .. companyCity .. "，只能在本城市拿地", nil
    end
    local accepted, message, finalPrice = LA.EvaluateSecondaryOffer(land, offerPrice)
    if accepted then
        land.status = "acquired"
        land.startPrice = finalPrice
    end
    return accepted, message, finalPrice
end

-- ============================================================================
-- 公开API: 尽职调查执行系统
-- ============================================================================

--- 尽调风险发现表 — 每种调查类型可能发现的风险
local SURVEY_RISK_POOL = {
    site = {
        { desc = "发现高压线穿越地块",   costPct = 0.02 },
        { desc = "存在违章建筑需拆除",   costPct = 0.03 },
        { desc = "地块边界与现状不符",   costPct = 0.01 },
        { desc = "周边存在嫌恶设施",     costPct = 0.005 },
    },
    radon = {
        { desc = "土壤氡含量超标需治理", costPct = 0.04 },
        { desc = "局部区域氡偏高需监测", costPct = 0.01 },
    },
    pipeline = {
        { desc = "发现未标注燃气管线",   costPct = 0.03 },
        { desc = "电力管线需迁改",       costPct = 0.05 },
        { desc = "通信管线布局复杂",     costPct = 0.02 },
    },
    relic = {
        { desc = "发现古代墓葬需保护",   costPct = 0.08, monthsDelay = 6 },
        { desc = "出土文物需考古清理",   costPct = 0.06, monthsDelay = 4 },
        { desc = "发现历史遗址痕迹",     costPct = 0.03, monthsDelay = 2 },
    },
}

--- 启动一项尽职调查
---@param land table
---@param surveyType string  LA.SURVEY_TYPES 中的值
---@param companyCash number 当前公司现金(万元)
---@return boolean success
---@return string message
---@return number|nil cost  扣除的费用
function LA.StartSurvey(land, surveyType, companyCash)
    local cfg = LA.SURVEY_CONFIG[surveyType]
    if not cfg then
        return false, "未知的调查类型: " .. tostring(surveyType), nil
    end
    local dd = land.dueDiligence
    if not dd then
        return false, "地块缺少尽调数据", nil
    end
    -- 检查是否已完成或正在进行
    for _, c in ipairs(dd.completed) do
        if c.type == surveyType then
            return false, cfg.name .. "已完成", nil
        end
    end
    for _, s in ipairs(dd.skipped) do
        if s.type == surveyType then
            return false, cfg.name .. "已跳过，无法重新启动", nil
        end
    end
    if dd.inProgress and dd.inProgress.type == surveyType then
        return false, cfg.name .. "正在进行中", nil
    end
    if dd.inProgress then
        return false, "已有调查正在进行（" .. LA.SURVEY_CONFIG[dd.inProgress.type].name .. "），请等待完成", nil
    end
    -- 检查费用
    if companyCash < cfg.cost then
        return false, "现金不足，" .. cfg.name .. "需要" .. cfg.cost .. "万元", nil
    end
    -- 启动调查
    dd.inProgress = {
        type = surveyType,
        cost = cfg.cost,
        monthsRemaining = cfg.months,
        startedAt = nil,  -- 由外部设 totalMonths
    }
    dd.totalCost = dd.totalCost + cfg.cost
    return true, cfg.name .. "已启动，预计" .. cfg.months .. "个月完成，费用" .. cfg.cost .. "万元", cfg.cost
end

--- 推进尽调进度（每月调用一次）
--- 返回是否有调查刚完成
---@param land table
---@return boolean justCompleted
---@return string|nil completedType
---@return table|nil discoveredRisks  本次发现的风险列表
function LA.TickSurvey(land)
    local dd = land.dueDiligence
    if not dd or not dd.inProgress then
        return false, nil, nil
    end
    local ip = dd.inProgress
    ip.monthsRemaining = ip.monthsRemaining - 1
    dd.totalMonths = dd.totalMonths + 1
    if ip.monthsRemaining > 0 then
        return false, nil, nil
    end
    -- 调查完成 —— 生成结果
    local surveyType = ip.type
    local cfg = LA.SURVEY_CONFIG[surveyType]
    local discoveredRisks = {}
    -- 基础风险发现概率 30%（法拍地块提高到 60%）
    local riskChance = 0.30
    if land.channel == LA.CHANNELS.JUDICIAL then
        riskChance = 0.60
    end
    local pool = SURVEY_RISK_POOL[surveyType] or {}
    for _, r in ipairs(pool) do
        if math.random() < riskChance then
            local risk = {
                type = surveyType,
                desc = r.desc,
                costImpact = math.floor(land.startPrice * r.costPct),
                monthsDelay = r.monthsDelay or 0,
                discovered = true,
            }
            table.insert(discoveredRisks, risk)
            table.insert(dd.risks, risk)
        end
    end
    -- 法拍地块: 同时揭示 channelData.hiddenRisks 中对应类型
    if land.channel == LA.CHANNELS.JUDICIAL and land.channelData and land.channelData.hiddenRisks then
        for _, hr in ipairs(land.channelData.hiddenRisks) do
            if not hr.discovered and math.random() < 0.5 then
                hr.discovered = true
                table.insert(dd.risks, {
                    type = "judicial_" .. hr.type,
                    desc = hr.desc,
                    costImpact = hr.costImpact,
                    monthsDelay = 0,
                    discovered = true,
                })
                table.insert(discoveredRisks, dd.risks[#dd.risks])
            end
        end
    end
    -- 记录完成
    table.insert(dd.completed, {
        type = surveyType,
        cost = ip.cost,
        months = cfg.months,
        risksFound = #discoveredRisks,
        result = #discoveredRisks > 0 and "发现风险" or "未发现异常",
    })
    dd.inProgress = nil
    return true, surveyType, discoveredRisks
end

--- 跳过一项尽职调查（不花钱但保留未知风险）
---@param land table
---@param surveyType string
---@return boolean success
---@return string message
function LA.SkipSurvey(land, surveyType)
    local cfg = LA.SURVEY_CONFIG[surveyType]
    if not cfg then
        return false, "未知的调查类型"
    end
    local dd = land.dueDiligence
    if not dd then return false, "地块缺少尽调数据" end
    for _, c in ipairs(dd.completed) do
        if c.type == surveyType then return false, cfg.name .. "已完成，无需跳过" end
    end
    for _, s in ipairs(dd.skipped) do
        if s.type == surveyType then return false, cfg.name .. "已跳过" end
    end
    if dd.inProgress and dd.inProgress.type == surveyType then
        return false, cfg.name .. "正在进行中，无法跳过"
    end
    table.insert(dd.skipped, { type = surveyType })
    return true, "已跳过" .. cfg.name .. "（潜在风险将在施工阶段暴露）"
end

--- 获取某地块尽调整体状态（供UI展示）
---@param land table
---@return table status
function LA.GetSurveyStatus(land)
    local dd = land.dueDiligence
    if not dd then
        return { totalItems = 4, completedCount = 0, skippedCount = 0, inProgress = nil, risks = {}, totalCost = 0 }
    end
    local allTypes = { "site", "radon", "pipeline", "relic" }
    local items = {}
    for _, st in ipairs(allTypes) do
        local cfg = LA.SURVEY_CONFIG[st]
        local state = "pending"
        local result = nil
        for _, c in ipairs(dd.completed) do
            if c.type == st then state = "completed"; result = c.result; break end
        end
        if state == "pending" then
            for _, s in ipairs(dd.skipped) do
                if s.type == st then state = "skipped"; break end
            end
        end
        if state == "pending" and dd.inProgress and dd.inProgress.type == st then
            state = "in_progress"
        end
        table.insert(items, {
            type = st,
            name = cfg.name,
            desc = cfg.desc,
            cost = cfg.cost,
            months = cfg.months,
            state = state,
            result = result,
            monthsRemaining = (state == "in_progress" and dd.inProgress) and dd.inProgress.monthsRemaining or nil,
        })
    end
    return {
        totalItems = 4,
        completedCount = #dd.completed,
        skippedCount = #(dd.skipped or {}),
        inProgress = dd.inProgress,
        items = items,
        risks = dd.risks or {},
        totalCost = dd.totalCost or 0,
        totalMonths = dd.totalMonths or 0,
    }
end

--- 计算未完成尽调带来的隐性风险成本（用于CreateProject时附加）
--- 跳过的调查项会在施工期间以概率暴露风险，此函数估算期望成本
---@param land table
---@return number extraCost  隐性风险期望成本(万元)
---@return number extraMonths  潜在延期月数
---@return table  hiddenRiskDescs  风险描述列表
function LA.CalcHiddenRiskCost(land)
    local dd = land.dueDiligence
    if not dd then return 0, 0, {} end
    local extraCost = 0
    local extraMonths = 0
    local descs = {}
    -- 跳过的调查: 40%概率在施工期暴露（此处做期望值估算）
    for _, s in ipairs(dd.skipped or {}) do
        local pool = SURVEY_RISK_POOL[s.type] or {}
        for _, r in ipairs(pool) do
            local expectedCost = math.floor(land.startPrice * r.costPct * 0.40)
            extraCost = extraCost + expectedCost
            extraMonths = extraMonths + (r.monthsDelay or 0) * 0.40
            table.insert(descs, LA.SURVEY_CONFIG[s.type].name .. ": " .. r.desc .. "（隐性风险）")
        end
    end
    -- 法拍未揭示的隐藏风险
    if land.channel == LA.CHANNELS.JUDICIAL and land.channelData and land.channelData.hiddenRisks then
        for _, hr in ipairs(land.channelData.hiddenRisks) do
            if not hr.discovered then
                extraCost = extraCost + (hr.costImpact or 0)
                table.insert(descs, "法拍隐藏: " .. hr.desc)
            end
        end
    end
    return extraCost, math.floor(extraMonths), descs
end

-- ============================================================================
-- 公开API: 竞拍熔断机制 + 法拍竞拍变体（Phase 4）
-- ============================================================================

--- 熔断阈值: 溢价率超过此值触发熔断（转为"一次性报价"制）
LA.CIRCUIT_BREAKER_PREMIUM = 0.30   -- 30% 溢价率

--- 检查是否触发熔断
---@param land table
---@param currentPrice number  当前最高出价
---@return boolean triggered
---@return number premiumRate  当前溢价率
function LA.CheckCircuitBreaker(land, currentPrice)
    local base = land.startPrice
    if not base or base <= 0 then return false, 0 end
    local premiumRate = (currentPrice - base) / base
    return premiumRate >= LA.CIRCUIT_BREAKER_PREMIUM, premiumRate
end

--- 熔断后一次性报价决策: 每个竞拍者提交密封报价
---@param land table
---@param aiPlayers table  当前活跃AI列表 { {name, maxPrice, active, aggressive}, ... }
---@param playerBid number  玩家密封出价
---@return table result  { winner, winnerBid, allBids = {{name, bid}...}, isPlayer }
function LA.SealedBidRound(land, aiPlayers, playerBid)
    local bids = {}
    -- 玩家出价
    table.insert(bids, { name = "__player__", bid = playerBid })
    -- AI出价: 在当前价和maxPrice之间选择一个值
    for _, ai in ipairs(aiPlayers) do
        if ai.active then
            -- AI报价策略: 基于 aggressive 和 maxPrice
            local basePrice = land.startPrice * (1 + LA.CIRCUIT_BREAKER_PREMIUM)
            local aiBid = basePrice + (ai.maxPrice - basePrice) * (0.5 + math.random() * 0.5 * ai.aggressive)
            aiBid = math.min(aiBid, ai.maxPrice)
            aiBid = math.floor(aiBid)
            table.insert(bids, { name = ai.name, bid = aiBid })
        end
    end
    -- 排序找最高出价
    table.sort(bids, function(a, b) return a.bid > b.bid end)
    local winner = bids[1]
    return {
        winner = winner.name == "__player__" and nil or winner.name,
        winnerBid = winner.bid,
        isPlayer = winner.name == "__player__",
        allBids = bids,
    }
end

--- 法拍竞拍参数: 与招拍挂不同的规则
---@param land table
---@return table params  { increment, priceCap, maxRounds, aiCountMin, aiCountMax, aiMaxPriceRange }
function LA.GetJudicialAuctionParams(land)
    -- 法拍特点:
    -- 1. 加价幅度更大(起拍价的3%, 最低20万)
    -- 2. 上限更高(起拍价的3倍, 因为本身就折价)
    -- 3. 轮次可能更多(法拍竞争激烈)
    -- 4. AI数量可能更多(低价吸引更多买家)
    local inc = math.max(20, math.min(800, math.floor(land.startPrice * 0.03)))
    local auctionRound = (land.channelData and land.channelData.auctionRound) or 1
    local capMultiplier = 3.0
    if auctionRound >= 2 then
        -- 二拍上限略低, 竞争也少
        capMultiplier = 2.5
    end
    return {
        increment = inc,
        priceCap = math.floor(land.startPrice * capMultiplier),
        maxRounds = math.random(4, 8),
        aiCountMin = 3,
        aiCountMax = 5,
        aiMaxPriceRange = { 20, 80 },  -- AI最高出价 = startPrice * (1 + 20%~80%)
        auctionRound = auctionRound,
    }
end

--- 获取默认(招拍挂)竞拍参数
---@param land table
---@return table params
function LA.GetDefaultAuctionParams(land)
    local inc = math.max(10, math.min(500, math.floor(land.startPrice * 0.02)))
    return {
        increment = inc,
        priceCap = math.floor(land.startPrice * 2),
        maxRounds = math.random(3, 6),
        aiCountMin = 2,
        aiCountMax = 3,
        aiMaxPriceRange = { 10, 60 },
        auctionRound = 0,
    }
end

--- 根据渠道获取竞拍参数
---@param land table
---@return table params
function LA.GetAuctionParams(land)
    if land.channel == LA.CHANNELS.JUDICIAL then
        return LA.GetJudicialAuctionParams(land)
    end
    return LA.GetDefaultAuctionParams(land)
end

-- ============================================================================
-- 公开API: 敏感性分析（Phase 7）
-- 三种估值方法 + 5×5 敏感性矩阵
-- ============================================================================

--- 方法一：市场比较法 — 基于周边可比案例推算土地合理价格
--- 模拟3-5个可比案例，用区位/用途/时间修正系数推算
---@param land table
---@param city table
---@param economy table
---@return table result { comparables, adjustedAvg, deviation, conclusion }
function LA.MarketComparison(land, city, economy)
    if not land or not city then return nil end

    -- 模拟可比案例（基于地块自身数据 + 随机波动）
    local baseFloorPrice = land.floorPrice or 5000
    local comparables = {}
    local caseCount = math.random(3, 5)

    local caseNames = {
        "同区域住宅用地(%d年%d月成交)",
        "相邻板块商住地(%d年%d月成交)",
        "同城同类型地块(%d年%d月成交)",
        "隔壁区域近期成交(%d年%d月成交)",
        "同片区上年度成交(%d年%d月成交)",
    }
    local totalAdjusted = 0

    for i = 1, caseCount do
        -- 可比案例成交价：在基准价±30%波动
        local rawPrice = baseFloorPrice * (0.70 + math.random() * 0.60)
        -- 修正系数
        local locationAdj = 0.90 + math.random() * 0.20   -- 区位修正 0.90~1.10
        local useTypeAdj  = 0.95 + math.random() * 0.10   -- 用途修正 0.95~1.05
        local timeAdj     = 0.92 + math.random() * 0.16   -- 时间修正 0.92~1.08
        local areaAdj     = 0.95 + math.random() * 0.10   -- 面积修正 0.95~1.05

        local adjustedPrice = math.floor(rawPrice * locationAdj * useTypeAdj * timeAdj * areaAdj)
        totalAdjusted = totalAdjusted + adjustedPrice

        local monthsAgo = math.random(1, 18)
        -- 用land.month推算案例时间（模拟数据，无需精确）
        local landMonth = land.month or 1
        local landYear  = land.year or 2001
        local totalM = (landYear - 2001) * 12 + landMonth
        local elapsed = math.max(0, totalM - monthsAgo)
        local caseYear = math.floor(elapsed / 12) + 2001
        local caseMonth = (elapsed % 12) + 1

        table.insert(comparables, {
            name = string.format(caseNames[((i-1) % #caseNames) + 1], caseYear, caseMonth),
            rawPrice = math.floor(rawPrice),
            locationAdj = math.floor(locationAdj * 100),
            useTypeAdj = math.floor(useTypeAdj * 100),
            timeAdj = math.floor(timeAdj * 100),
            areaAdj = math.floor(areaAdj * 100),
            adjustedPrice = adjustedPrice,
        })
    end

    local adjustedAvg = math.floor(totalAdjusted / caseCount)
    local deviation = baseFloorPrice > 0
        and math.floor((adjustedAvg - baseFloorPrice) / baseFloorPrice * 100) or 0

    local conclusion
    if deviation > 10 then
        conclusion = "市场比较法估值高于当前地价" .. deviation .. "%，地块可能被低估，建议积极获取"
    elseif deviation < -10 then
        conclusion = "市场比较法估值低于当前地价" .. math.abs(deviation) .. "%，地块可能被高估，建议谨慎"
    else
        conclusion = "市场比较法估值与当前地价偏差" .. math.abs(deviation) .. "%，价格基本合理"
    end

    return {
        method = "市场比较法",
        comparables = comparables,
        adjustedAvg = adjustedAvg,
        currentFloorPrice = baseFloorPrice,
        deviation = deviation,
        conclusion = conclusion,
    }
end

--- 方法二：假设开发法（剩余法）— 从预期售价倒推合理地价
--- 公式: 合理地价 = 预期销售收入 - 建安成本 - 期间费用 - 目标利润 - 税费
---@param land table
---@param city table
---@param economy table
---@param traitEffects table|nil
---@return table result
function LA.ResidualMethod(land, city, economy, traitEffects)
    if not land or not city then return nil end

    local buildArea = land.buildArea or 0
    local sellArea = math.floor(buildArea * 0.85)

    -- 建安成本（使用DT独立基础值）
    local defaultDevType = getDefaultDevTypeForUseType(land.useType)
    local plotLocation = land.plotLocation or "suburb"
    local unitBuildCost = DT.GetBuildCost(defaultDevType, city.avgPrice, plotLocation, "basic",
        traitEffects and traitEffects.buildCostBonus or 0)
    local buildCost = math.floor(buildArea * unitBuildCost / 10000)

    -- 预期售价：锚定城市房价，地价仅影响利润率
    local floorPrice = land.floorPrice or 0
    local estPrice = DT.GetExpectedPrice(defaultDevType, city.avgPrice, plotLocation, "basic", floorPrice)
    estPrice = math.floor(estPrice * (economy.priceIndex / 100))
    local totalRevenue = math.floor(sellArea * estPrice / 10000) -- 万元

    -- 期间费用
    local designCost = math.floor(buildCost * 0.05)
    local marketingCost = math.floor(buildCost * 0.03)
    local managementCost = math.floor(buildCost * 0.02)

    -- 目标利润率（行业基准 8%-15%）
    local targetProfitRate = 0.10  -- 10%
    local targetProfit = math.floor(totalRevenue * targetProfitRate)

    -- 税费
    local taxCost = math.floor(totalRevenue * 0.05)

    -- 倒推合理地价
    local residualLandValue = totalRevenue - buildCost - designCost - marketingCost
        - managementCost - targetProfit - taxCost
    residualLandValue = math.max(0, residualLandValue)

    -- 楼面地价
    local residualFloorPrice = buildArea > 0 and math.floor(residualLandValue * 10000 / buildArea) or 0

    local currentLandPrice = land.startPrice or 0
    local premiumOrDiscount = currentLandPrice > 0
        and math.floor((currentLandPrice - residualLandValue) / residualLandValue * 100) or 0

    local conclusion
    if premiumOrDiscount > 15 then
        conclusion = "当前地价高出合理地价" .. premiumOrDiscount .. "%，利润空间压缩，风险较高"
    elseif premiumOrDiscount < -10 then
        conclusion = "当前地价低于合理地价" .. math.abs(premiumOrDiscount) .. "%，存在超额利润空间"
    else
        conclusion = "当前地价与假设开发法估值偏差" .. math.abs(premiumOrDiscount) .. "%，属合理范围"
    end

    return {
        method = "假设开发法",
        totalRevenue = totalRevenue,
        buildCost = buildCost,
        designCost = designCost,
        marketingCost = marketingCost,
        managementCost = managementCost,
        targetProfitRate = math.floor(targetProfitRate * 100),
        targetProfit = targetProfit,
        taxCost = taxCost,
        residualLandValue = residualLandValue,
        residualFloorPrice = residualFloorPrice,
        currentLandPrice = currentLandPrice,
        currentFloorPrice = land.floorPrice or 0,
        premiumOrDiscount = premiumOrDiscount,
        conclusion = conclusion,
    }
end

--- 方法三：敏感性矩阵 — 售价×成本的5×5利润率矩阵
--- 横轴: 售价变动 (-20%, -10%, 基准, +10%, +20%)
--- 纵轴: 成本变动 (-10%, -5%, 基准, +5%, +10%)
---@param land table
---@param city table
---@param economy table
---@return table result { matrix, priceLabels, costLabels, baseProfit, baseRate }
function LA.SensitivityMatrix(land, city, economy)
    if not land or not city then return nil end

    -- 基准测算
    local baseCalc = LA.CalcInvestment(land, city, economy)
    if not baseCalc then return nil end

    local baseRevenue = baseCalc.totalRevenue
    local baseCost = baseCalc.totalCost
    local baseProfit = baseCalc.profit
    local baseRate = baseCalc.profitRate

    -- 售价变动幅度
    local priceFactors = { -0.20, -0.10, 0, 0.10, 0.20 }
    local priceLabels  = { "-20%", "-10%", "基准", "+10%", "+20%" }

    -- 成本变动幅度
    local costFactors = { -0.10, -0.05, 0, 0.05, 0.10 }
    local costLabels  = { "-10%", "-5%", "基准", "+5%", "+10%" }

    -- 5×5 矩阵: matrix[costRow][priceCol]
    local matrix = {}
    for ci = 1, 5 do
        matrix[ci] = {}
        local adjCost = math.floor(baseCost * (1 + costFactors[ci]))
        for pi = 1, 5 do
            local adjRevenue = math.floor(baseRevenue * (1 + priceFactors[pi]))
            local profit = adjRevenue - adjCost
            local rate = adjRevenue > 0 and math.floor(profit / adjRevenue * 100) or 0
            matrix[ci][pi] = {
                profit = profit,
                rate = rate,
                revenue = adjRevenue,
                cost = adjCost,
            }
        end
    end

    -- 盈亏平衡售价变动（在基准成本下，售价需变动多少才达到盈亏平衡）
    local breakEvenPriceDelta = baseCost > 0 and baseRevenue > 0
        and math.floor((baseCost / baseRevenue - 1) * 100) or 0

    return {
        method = "敏感性矩阵",
        matrix = matrix,
        priceLabels = priceLabels,
        costLabels = costLabels,
        priceFactors = priceFactors,
        costFactors = costFactors,
        baseProfit = baseProfit,
        baseRate = baseRate,
        baseRevenue = baseRevenue,
        baseCost = baseCost,
        breakEvenPriceDelta = breakEvenPriceDelta,
    }
end

--- 综合估值报告 — 三法合一
---@param land table
---@param city table
---@param economy table
---@param traitEffects table|nil
---@return table report
function LA.FullValuationReport(land, city, economy, traitEffects)
    return {
        marketComparison = LA.MarketComparison(land, city, economy),
        residualMethod = LA.ResidualMethod(land, city, economy, traitEffects),
        sensitivityMatrix = LA.SensitivityMatrix(land, city, economy),
    }
end

-- ============================================================================
-- 公开API: 联合拿地 + 反悔机制（Phase 5）
-- ============================================================================

--- 联合拿地: 查找可合作的AI伙伴
---@param land table
---@param competitors table  GD.competitors
---@return table partners  可选合作方列表 { {name, shareRatio, maxInvest, willingness}, ... }
function LA.FindJointBidPartners(land, competitors)
    local partners = {}
    for _, comp in ipairs(competitors) do
        -- AI合作意愿: aggressive 越低的越愿意合作(保守型)
        local willingness = 1.0 - comp.aggressive * 0.5
        -- 大地块更需要合作
        if land.startPrice > 50000 then
            willingness = willingness + 0.2
        end
        -- 法拍地块AI更谨慎
        if land.channel == LA.CHANNELS.JUDICIAL then
            willingness = willingness - 0.2
        end
        willingness = math.max(0, math.min(1, willingness))
        if willingness > 0.3 then
            -- 合作方出资比例: 30%-49%（玩家始终控股）
            local shareRatio = 0.30 + math.random() * 0.19
            local maxInvest = math.floor(land.startPrice * shareRatio * 1.5)
            table.insert(partners, {
                name = comp.name,
                shareRatio = math.floor(shareRatio * 100),  -- 百分比整数
                maxInvest = maxInvest,
                willingness = math.floor(willingness * 100),
            })
        end
    end
    -- 按意愿排序
    table.sort(partners, function(a, b) return a.willingness > b.willingness end)
    return partners
end

--- 联合拿地: 确认合作并计算出资分配
---@param land table
---@param partnerName string  合作方名称
---@param partnerSharePct number  合作方股权比例(整数%, 如 35 表示 35%)
---@param totalPrice number  总成交价
---@return table result  { playerShare, partnerShare, playerCost, partnerCost }
function LA.CalcJointBidShares(land, partnerName, partnerSharePct, totalPrice)
    local partnerRatio = partnerSharePct / 100
    local playerRatio = 1 - partnerRatio
    return {
        partnerName = partnerName,
        partnerSharePct = partnerSharePct,
        playerSharePct = 100 - partnerSharePct,
        playerCost = math.floor(totalPrice * playerRatio),
        partnerCost = math.floor(totalPrice * partnerRatio),
        -- 利润也按比例分成
        profitSplit = {
            player = playerRatio,
            partner = partnerRatio,
        }
    }
end

--- 反悔（放弃已竞得地块）: 计算罚金
---@param land table
---@param wonPrice number  竞拍成交价
---@return number penalty  罚金（保证金没收 + 额外违约金）
---@return string message
function LA.CalcForfeitPenalty(land, wonPrice)
    local deposit = land.deposit or math.floor(wonPrice * 0.2)
    -- 额外违约金: 成交价的 2%
    local extraPenalty = math.floor(wonPrice * 0.02)
    local total = deposit + extraPenalty
    local msg = "没收保证金" .. deposit .. "万 + 违约金" .. extraPenalty .. "万 = " .. total .. "万元"
    return total, msg
end

-- ============================================================================
-- 公开API: 为旧存档地块补充新字段（向后兼容）
-- ============================================================================

--- 给缺少新字段的地块补充默认值
---@param land table
function LA.EnsureLandFields(land)
    if not land then return end
    if not land.channel then
        land.channel = LA.CHANNELS.PUBLIC_AUCTION
    end
    if not land.channelData then
        land.channelData = {}
    end
    if not land.dueDiligence then
        land.dueDiligence = {
            completed = {},
            skipped = {},
            totalCost = 0,
            totalMonths = 0,
            risks = {},
        }
    end
    if land.status == nil then
        local acquiredPrice = tonumber(land.price) or 0
        land.status = acquiredPrice > 0 and "sold" or "available"
    end
    if land.listedYear == nil then land.listedYear = 0 end
    if land.listedMonth == nil then land.listedMonth = 1 end
    if land.acquiredMonth == nil and land.status == "sold" then
        land.acquiredMonth = 0
    end
end

return LA
