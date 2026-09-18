-- ============================================================================
-- Marketing.lua - 营销销售优化模块 (8.1~8.5)
-- 前期营销(蓄客) / 价格策略 / 开盘方式 / 渠道管理 / 回款管理
-- ============================================================================
local MK = {}
local RE = require("RandomEvents")
local GDI = require("GroupSystem").Diversification

-- ============================================================================
-- 8.1 前期营销(蓄客期) 常量
-- ============================================================================
MK.SHOWROOM_OPTIONS = {
    {id = "none",   name = "不设展厅", cost = 0,   visitBonus = 0},
    {id = "basic",  name = "简易展厅", cost = 50,  visitBonus = 0.15},
    {id = "luxury", name = "豪华展厅", cost = 200, visitBonus = 0.35},
}

MK.MEDIA_AD_LEVELS = {
    {id = "none", name = "不投放",   monthlyCost = 0,   visitBonus = 0},
    {id = "low",  name = "基础投放", monthlyCost = 30,  visitBonus = 0.10},
    {id = "mid",  name = "中度投放", monthlyCost = 80,  visitBonus = 0.20},
    {id = "high", name = "强势投放", monthlyCost = 200, visitBonus = 0.35},
}

MK.SELF_MEDIA_OPTIONS = {
    {id = "none",   name = "不运营",   monthlyCost = 0,  visitRange = {0, 0}},
    {id = "basic",  name = "基础运营", monthlyCost = 10, visitRange = {0.05, 0.20}},
    {id = "active", name = "积极运营", monthlyCost = 30, visitRange = {0.10, 0.40}},
}

MK.DEPOSIT_THRESHOLDS = {
    {id = "none", name = "不设验资", amount = 0,   sincerity = 0.5,  volumeMult = 1.0},
    {id = "50w",  name = "50万",    amount = 50,  sincerity = 0.6,  volumeMult = 1.0},
    {id = "100w", name = "100万",   amount = 100, sincerity = 0.75, volumeMult = 0.75},
    {id = "200w", name = "200万",   amount = 200, sincerity = 0.85, volumeMult = 0.50},
    {id = "500w", name = "500万",   amount = 500, sincerity = 0.95, volumeMult = 0.25},
}

-- ============================================================================
-- 8.2 价格策略 常量
-- ============================================================================
MK.DISCOUNT_TYPES = {
    {id = "subscription", name = "认筹折扣", rate = 0.98},
    {id = "opening",      name = "开盘折扣", rate = 0.97},
    {id = "sign_early",   name = "按时签约", rate = 0.99},
    {id = "full_pay",     name = "全款折扣", rate = 0.95},
    {id = "gm_special",   name = "总经理特批", rate = 1.0},  -- 玩家自设
}

MK.REPRICE_THRESHOLD = 0.03   -- 月去化率<3%可申请降价
MK.REPRICE_COOLDOWN  = 1      -- 调价备案耗时1个月
MK.PRICE_SPEED_STEP = 0.05
MK.PRICE_SPEED_RISE_LIMIT = 0.50
MK.PRICE_SPEED_RISE_FACTOR = 0.80
MK.PRICE_SPEED_DROP_FACTOR = 1.20

-- ============================================================================
-- 8.3 开盘方式 常量
-- ============================================================================
MK.OPENING_METHODS = {
    {id = "offline", name = "线下集中开盘", convBonus = 0.10, costMult = 1.2, desc = "转化率高，成本较高"},
    {id = "online",  name = "线上选房",     convBonus = 0.03, costMult = 0.8, desc = "低成本，转化率略低"},
    {id = "lottery", name = "公证摇号",     convBonus = 0.05, costMult = 1.0, desc = "公平公正，速度较慢", monthDelay = 1},
}

MK.SCALPER_OPTION = {
    reputationPenalty = -20,
    exposureProbability = 0.25,
    salesBoostPct = 0.15,
}

-- ============================================================================
-- 8.4 渠道管理 常量
-- ============================================================================
MK.CHANNEL_DETAILS = {
    selfSales    = {name = "自建团队",      baseCommission = 0,     visitBonus = 0,    canDisable = false},
    agency       = {name = "代理公司",      baseCommission = 0.015, visitBonus = 0.20, canDisable = true},
    distribution = {name = "贝壳/我爱我家", baseCommission = 0.025, visitBonus = 0.30, canDisable = true,
                    kidnappingThreshold = 6, kidnappingIncrement = 0.005, kidnappingCap = 0.05},
    referral     = {name = "全民经纪人",    baseCommission = 0.01,  visitBonus = 0.15, canDisable = true},
}

-- ============================================================================
-- 8.5 回款管理 常量
-- ============================================================================
MK.SIGN_STAGES = {
    {id = "draft",          name = "草签",     durationMonths = 0, dropRate = 0.02},
    {id = "formal",         name = "网签",     durationMonths = 1, dropRate = 0.01},
    {id = "mortgage_apply", name = "按揭申请", durationMonths = 1, dropRate = 0.03},
    {id = "mortgage_done",  name = "放款到账", durationMonths = 2, dropRate = 0.02},
}

MK.BANKS = {
    {id = "bank_a", name = "工川银行", rate = 4.1, speedMult = 1.0, quotaPct = 1.0},
    {id = "bank_b", name = "建川银行", rate = 4.0, speedMult = 0.9, quotaPct = 0.9},
    {id = "bank_c", name = "招远银行", rate = 4.3, speedMult = 1.2, quotaPct = 0.8},
    {id = "bank_d", name = "民和银行", rate = 4.5, speedMult = 1.3, quotaPct = 0.7},
}

MK.OVERDUE_CHASE_SUCCESS = 0.70
MK.OVERDUE_REFUND_RATE   = 0.30

-- ============================================================================
-- 初始化
-- ============================================================================
function MK.InitMarketingData()
    return {
        -- 8.1 蓄客
        accumulation = {
            showroom = "none",
            showroomCost = 0,
            mediaAdLevel = "none",
            selfMediaLevel = "none",
            depositThreshold = "none",
            subscribers = 0,
            subscriptionRatio = 0,
            accumulationMonths = 0,
        },
        -- 8.2 价格策略
        pricing = {
            discountsEnabled = {
                subscription = false,
                opening = false,
                sign_early = false,
                full_pay = false,
                gm_special = false,
            },
            gmSpecialRate = 0.95,
            effectiveDiscount = 1.0,
            repricing = false,
            repriceCooldown = 0,
            priceHistory = {},
        },
        -- 8.3 开盘
        opening = {
            method = "none",
            opened = false,
            openedMonth = 0,
            usedScalper = false,
            scalperExposed = false,
            reputationPenalty = 0,
        },
        -- 8.4 渠道扩展
        channels = {
            distributionMonths = 0,
            currentCommissions = {
                agency = 0.015,
                distribution = 0.025,
                referral = 0.01,
            },
        },
        -- 8.5 回款
        collection = {
            selectedBank = "bank_a",
            signingQueue = {},
            overdueCount = 0,
            refundedUnits = 0,
            collectedAmount = 0,
        },
    }
end

-- ============================================================================
-- 向后兼容
-- ============================================================================
function MK.EnsureMarketingFields(sales)
    if not sales then return end
    -- 旧字段补全
    if sales.marketingBudget == nil then sales.marketingBudget = 0 end
    if sales.totalMarketingCost == nil then sales.totalMarketingCost = 0 end
    local approvedOpeningPrice = tonumber(sales.approvedOpeningPrice) or 0
    local currentPrice = tonumber(sales.basePrice) or 0
    if approvedOpeningPrice <= 0 and currentPrice > 0 then
        sales.approvedOpeningPrice = currentPrice
    end
    if not sales.activeChannels then
        sales.activeChannels = {selfSales = true, agency = false, distribution = false, referral = false}
    end
    if sales.promotionType == nil then sales.promotionType = "none" end
    if sales.promotionMonthsLeft == nil then sales.promotionMonthsLeft = 0 end
    -- 新 marketing 子结构
    if not sales.marketing then
        sales.marketing = MK.InitMarketingData()
    end
    local mk = sales.marketing
    if not mk.accumulation then mk.accumulation = MK.InitMarketingData().accumulation end
    if not mk.pricing then mk.pricing = MK.InitMarketingData().pricing end
    if not mk.opening then mk.opening = MK.InitMarketingData().opening end
    if not mk.channels then mk.channels = MK.InitMarketingData().channels end
    if not mk.collection then mk.collection = MK.InitMarketingData().collection end
    if not mk.pricing.discountsEnabled then mk.pricing.discountsEnabled = MK.InitMarketingData().pricing.discountsEnabled end
    if not mk.channels.currentCommissions then mk.channels.currentCommissions = MK.InitMarketingData().channels.currentCommissions end
    sales.revenue = sales.revenue or 0
    sales.monthRevenue = sales.monthRevenue or 0
    sales.monthEscrowDeposit = sales.monthEscrowDeposit or 0
    sales.monthFreeRevenue = sales.monthFreeRevenue or 0
    sales.monthContractedRevenue = sales.monthContractedRevenue or 0
    sales.monthlyBlockedByPrice = false
    sales._priceIncreaseBlocked = false
    sales._priceIncreasePenalty = 0
    sales._priceSpeedMultiplier = 1.0
    sales._priceIncreaseSteps = 0
    for _, batch in ipairs(mk.collection.signingQueue or {}) do
        if not batch.unitRevenue then
            local remainingUnits = sales.totalUnits or 0
            local avgArea = (sales.totalArea or 0) / math.max(1, remainingUnits)
            local effDiscount = (mk.pricing and mk.pricing.effectiveDiscount) or (sales.discount or 1.0)
            batch.unitRevenue = avgArea * (sales.basePrice or 0) * effDiscount / 10000
        end
        batch.contractedRevenue = batch.contractedRevenue or ((batch.unitCount or 0) * (batch.unitRevenue or 0))
    end
end

-- ============================================================================
-- 私有辅助函数
-- ============================================================================

--- 查找常量表项
---@param tbl table
---@param id string
---@return table|nil
local function _FindById(tbl, id)
    for _, item in ipairs(tbl) do
        if item.id == id then return item end
    end
    return tbl[1]  -- fallback to first
end

--- 获取项目对应的产品基准价（元/㎡）：住宅按产品档次，商业/写字楼按住宅约2倍
---@param project table
---@param GD table
---@return number
local function _GetProjectMarketPrice(project, GD)
    local city = GD.GetCityData(project and project.land and project.land.city or nil)
    local DT = require("DevTypes")
    local floorPrice = project and project.land and project.land.floorPrice or 0
    return math.floor(DT.GetExpectedPrice(
        project and project.devTypeId or "rigid_residential",
        city.avgPrice,
        project and (project.plotLocation or (project.land and project.land.plotLocation)) or "suburb",
        project and project.standardId or "basic",
        floorPrice
    ) * (GD.economy.priceIndex / 100))
end

--- 根据批准开盘价推导价格对应的销售速度状态。
--- 每完整涨价5%，速度乘0.8；每完整降价5%，速度乘1.2；超过涨价50%停售。
local function _GetPriceSpeedState(s)
    local anchor = tonumber(s.approvedOpeningPrice) or 0
    local current = tonumber(s.basePrice) or 0
    local state = {
        validAnchor = anchor > 0 and current > 0,
        blocked = false,
        delta = 0,
        steps = 0,
        multiplier = 1.0,
    }
    if not state.validAnchor then
        return state
    end

    local delta = (current - anchor) / anchor
    state.delta = delta
    if delta > MK.PRICE_SPEED_RISE_LIMIT then
        state.blocked = true
        state.multiplier = 0
        state.steps = math.floor(delta / MK.PRICE_SPEED_STEP + 1e-9)
        return state
    end

    state.steps = math.floor(math.abs(delta) / MK.PRICE_SPEED_STEP + 1e-9)
    if delta > 0 then
        state.multiplier = MK.PRICE_SPEED_RISE_FACTOR ^ state.steps
    elseif delta < 0 then
        state.multiplier = MK.PRICE_SPEED_DROP_FACTOR ^ state.steps
    end
    return state
end

local function _ApplyPriceSpeedState(s)
    local state = _GetPriceSpeedState(s)
    s._priceIncreaseBlocked = state.blocked
    s._priceIncreasePenalty = state.blocked and 1.0 or 0
    s._priceSpeedMultiplier = state.multiplier
    s._priceIncreaseSteps = state.steps
    s.monthlyBlockedByPrice = state.blocked
    return state
end

function MK.GetPriceSpeedState(sales)
    if not sales then
        return {
            validAnchor = false,
            blocked = false,
            delta = 0,
            steps = 0,
            multiplier = 1.0,
        }
    end
    return _GetPriceSpeedState(sales)
end

-- Phase 1: 限价政策与批准开盘价销售速度规则。
local function _ApplyPricePolicy(s, GD, project)
    local priceCeilingRatio = GD.policy.transaction.priceCeilingRatio or 999
    local marketAvg = _GetProjectMarketPrice(project, GD)
    s._policyPenalty = 0
    if priceCeilingRatio < 10 then
        local ceiling = marketAvg * priceCeilingRatio
        if s.basePrice > ceiling then
            s._policyPenalty = math.min(0.5, (s.basePrice - ceiling) / ceiling)
        end
    end
    _ApplyPriceSpeedState(s)
end

--- Phase 2: 蓄客期更新(认筹人数增长)
local function _UpdateAccumulation(mk, s)
    local acc = mk.accumulation
    if not mk.opening.opened then
        acc.accumulationMonths = acc.accumulationMonths + 1
    end
    -- 认筹人数: 基于来访 × 验资诚意度
    local dep = _FindById(MK.DEPOSIT_THRESHOLDS, acc.depositThreshold)
    local sincerity = dep.sincerity or 0.5
    local volumeMult = dep.volumeMult or 1.0
    -- 每月新增认筹 = 来访量 × 诚意度 × 验资量系数
    local newSubs = math.floor(s.monthlyVisits * sincerity * volumeMult * 0.3)
    acc.subscribers = acc.subscribers + newSubs
    acc.subscriptionRatio = s.totalUnits > 0 and (acc.subscribers / s.totalUnits) or 0
end

--- Phase 3: 来访量计算(含新增蓄客加成)
local function _CalcMonthlyVisits(s, mk, project, GD)
    local baseVisits = math.random(25, 55)
    local acc = mk.accumulation

    -- 限购抑制
    local purchaseLimitLocal = GD.policy.transaction.purchaseLimitLocal or 999
    local purchaseLimitNonLocal = GD.policy.transaction.purchaseLimitNonLocal or 999
    local purchaseLimitMult = 1.0
    if purchaseLimitLocal <= 1 then purchaseLimitMult = purchaseLimitMult * 0.85 end
    if purchaseLimitNonLocal <= 0 then purchaseLimitMult = purchaseLimitMult * 0.80
    elseif purchaseLimitNonLocal <= 1 then purchaseLimitMult = purchaseLimitMult * 0.90 end

    -- 销售团队加成
    local salesTeamCount = 0
    for _, emp in ipairs(GD.company.employees) do
        if emp.dept == "营销策划部" then salesTeamCount = salesTeamCount + 1 end
    end
    local salesBonus = 1 + salesTeamCount * 0.15
    -- 项目总监销售加成
    local PC = require("ProjectCapacity")
    local dirBonus = PC.GetDirectorBonuses(GD.company, project.id)
    salesBonus = salesBonus + (dirBonus.salesBonus or 0) / 100

    -- 营销预算加成
    local budgetBonus = 1 + (s.marketingBudget / 100) * 0.10

    -- 渠道加成
    local channelBonus = 1.0
    local ch = s.activeChannels or {}
    if ch.agency then channelBonus = channelBonus + 0.20 end
    if ch.distribution then channelBonus = channelBonus + 0.30 end
    if ch.referral and s.soldUnits > 0 then channelBonus = channelBonus + 0.15 end

    -- 促销来访加成
    local promoVisitBonus = 1.0
    if s.promotionType ~= "none" and s.promotionMonthsLeft > 0 then
        if s.promotionType == "gift" then promoVisitBonus = 1.15
        elseif s.promotionType == "event" then promoVisitBonus = 1.25 end
    end

    -- 设计品质加成
    local designQualityMult = 1.0
    local d = project.design
    if d and d.scheme.confirmed then
        designQualityMult = designQualityMult + (d.scheme.schemeScore - 60) * 0.005
    end
    if d and d.style ~= "" and GD.STYLE_CONFIG and GD.STYLE_CONFIG[d.style] then
        designQualityMult = designQualityMult * GD.STYLE_CONFIG[d.style].demandMult
    end
    designQualityMult = math.max(0.7, designQualityMult)

    -- === 新增: 展厅加成 ===
    local showroomOpt = _FindById(MK.SHOWROOM_OPTIONS, acc.showroom)
    local showroomBonus = 1 + (showroomOpt.visitBonus or 0)

    -- === 新增: 媒体广告加成 ===
    local mediaOpt = _FindById(MK.MEDIA_AD_LEVELS, acc.mediaAdLevel)
    local mediaBonus = 1 + (mediaOpt.visitBonus or 0)

    -- === 新增: 自媒体加成(随机范围) ===
    local selfMediaOpt = _FindById(MK.SELF_MEDIA_OPTIONS, acc.selfMediaLevel)
    local smRange = selfMediaOpt.visitRange or {0, 0}
    local selfMediaBonus = 1 + smRange[1] + math.random() * (smRange[2] - smRange[1])

    -- 品牌口碑来访加成：score 50=无加成，80=+15%，100=+25%；低于40则-10%~-20%
    local brandScore = GD.brand and GD.brand.score or 50
    local brandVisitMult = 1.0
    if brandScore >= 50 then
        brandVisitMult = 1.0 + (brandScore - 50) * 0.005  -- 每分+0.5%
    else
        brandVisitMult = 1.0 - (50 - brandScore) * 0.004  -- 每分-0.4%
    end

    local diversificationSynergy = GDI.GetProjectSynergy(GD, project)
    local groupDemandMult = 1 + (diversificationSynergy.salesDemandBonus or 0)

    s.monthlyVisits = math.floor(baseVisits
        * GD.economy.demandMultiplier
        * salesBonus * budgetBonus * channelBonus * promoVisitBonus
        * purchaseLimitMult * designQualityMult
        * showroomBonus * mediaBonus * selfMediaBonus
        * brandVisitMult * groupDemandMult)

    -- 竣工后加速清盘：交付期/现房销售期大幅提高来访量，确保12个月内售完
    if project.status == "delivery" or project.isExistingHomeSale then
        local remaining = s.totalUnits - s.soldUnits
        if remaining > 0 then
            -- 保底来访量 = 剩余套数 / 8（配合高转化率，确保12个月清盘）
            local minVisits = math.ceil(remaining / 8)
            -- 竣工现房加成：来访量 ×3
            s.monthlyVisits = math.max(s.monthlyVisits * 3, minVisits)
        end
    end
end

--- Phase 4: 转化率计算
local function _CalcConversionRate(s, mk, project, GD)
    local brandPremium = GD.company.traitEffects.brandPremium or 0
    local brandPremiumRate = GD.brand and GD.brand.premiumRate or 0  -- 口碑溢价
    local totalBrandPremium = brandPremium + brandPremiumRate
    local effectivePrice = s.basePrice * (1 + totalBrandPremium)
    local marketPrice = _GetProjectMarketPrice(project, GD)
    local priceRatio = marketPrice / math.max(1, effectivePrice)
    local baseRate = 0.10

    -- 销售团队
    local salesTeamCount = 0
    for _, emp in ipairs(GD.company.employees) do
        if emp.dept == "营销策划部" then salesTeamCount = salesTeamCount + 1 end
    end
    local convBonus = salesTeamCount * 0.025

    -- 品牌（特质+口碑综合）
    local brandConvBonus = totalBrandPremium * 0.08

    -- 促销转化加成
    local promoConvBonus = 0
    if s.promotionType ~= "none" and s.promotionMonthsLeft > 0 then
        if s.promotionType == "discount" then promoConvBonus = 0.05
        elseif s.promotionType == "gift" then promoConvBonus = 0.03 end
    end

    -- 设计品质
    local designConvBonus = 0
    local d = project.design
    if d and d.scheme.confirmed then
        designConvBonus = (d.scheme.schemeScore - 60) * 0.001
    end

    -- === 新增: 开盘方式加成 ===
    local openingConvBonus = 0
    if mk.opening.opened then
        local method = _FindById(MK.OPENING_METHODS, mk.opening.method)
        if method then openingConvBonus = method.convBonus or 0 end
    end

    -- === 新增: 黄牛加成(若已雇佣且未曝光) ===
    local scalperBonus = 0
    if mk.opening.usedScalper and not mk.opening.scalperExposed then
        scalperBonus = MK.SCALPER_OPTION.salesBoostPct
    end

    -- 限价政策惩罚：价格超过限价时降低转化率（代替直接修改basePrice）
    local policyPenalty = s._policyPenalty or 0

    s.conversionRate = math.min(0.45, math.max(0.04,
        (baseRate * priceRatio * GD.economy.demandMultiplier
        + convBonus + promoConvBonus + brandConvBonus + designConvBonus
        + openingConvBonus + scalperBonus) * (1 - policyPenalty)))

    -- 竣工后加速清盘：交付期/现房销售期大幅提高转化率
    if project.status == "delivery" or project.isExistingHomeSale then
        -- 现房销售转化率至少 25%，最高 60%
        s.conversionRate = math.min(0.60, math.max(0.25, s.conversionRate * 2.5))
    end
end

--- Phase 5: 计算综合折扣
local function _CalcEffectiveDiscount(mk)
    local p = mk.pricing
    local discount = 1.0
    for _, dt in ipairs(MK.DISCOUNT_TYPES) do
        if p.discountsEnabled[dt.id] then
            if dt.id == "gm_special" then
                discount = discount * (p.gmSpecialRate or 0.95)
            else
                discount = discount * dt.rate
            end
        end
    end
    p.effectiveDiscount = math.max(0.80, discount)  -- 下限8折
end

--- Phase 6: 执行销售成交
local function _ExecuteSales(s, mk, project, GD)
    -- 涨价超过50%时唯一允许的停售；价格回到50%以内后由统一状态自动恢复。
    if s._priceIncreaseBlocked then
        s.monthlyVisits = 0
        s.conversionRate = 0
        s.monthlyBlockedByPrice = true
        return 0
    end
    s.monthlyBlockedByPrice = false

    local rawSold = math.floor(s.monthlyVisits * s.conversionRate)
    local sold = math.floor(rawSold * (s._priceSpeedMultiplier or 1.0))
    if rawSold > 0 and (s._priceSpeedMultiplier or 1.0) > 0 and sold <= 0 then
        sold = 1
    end

    -- 非价格事件只能降低速度，不能把未停售项目变成事实停售。
    local slowdownFactor = RE.GetSalesSlowdownFactor(project)
    if slowdownFactor > 0 then
        local beforeSlowdown = sold
        local effectiveSlowdown = math.min(0.85, slowdownFactor)
        sold = math.floor(sold * (1 - effectiveSlowdown))
        if beforeSlowdown > 0 and sold <= 0 then
            sold = 1
        end
    end

    -- 销售中有有效客户时保底成交，价格超过50%停售除外。
    if sold <= 0 and rawSold <= 0 and s.monthlyVisits > 0 and s.conversionRate > 0 then
        sold = 1
    end

    sold = math.min(sold, s.totalUnits - s.soldUnits)
    s.soldUnits = s.soldUnits + sold

    -- 签约金额计算：此处只确认销售/签约，不直接入账。
    -- 真实现金回款在签约流水线完成后统一入公司现金或监管账户，避免“凭空销售”。
    local avgArea = s.totalArea / math.max(1, s.totalUnits)
    local effDiscount = mk.pricing.effectiveDiscount
    local unitRevenue = avgArea * s.basePrice * effDiscount / 10000  -- 万元/套
    local contractedRevenue = sold * unitRevenue
    s.monthContractedRevenue = contractedRevenue

    s.soldArea = math.floor(s.soldUnits * avgArea)

    -- 更新 sales.discount 保持旧字段同步
    s.discount = effDiscount

    -- 将成交推入签约流水线，后续阶段完成才形成实际回款
    if sold > 0 then
        table.insert(mk.collection.signingQueue, {
            unitCount = sold,
            unitRevenue = unitRevenue,
            contractedRevenue = contractedRevenue,
            stageIdx = 1,
            elapsed = 0,
            monthEntered = GD.totalMonths or 0,
        })
    end

    return sold
end

--- Phase 7: 渠道绑架检测
local function _UpdateChannelKidnapping(mk, s)
    local ch = s.activeChannels or {}
    local chData = mk.channels
    if ch.distribution then
        chData.distributionMonths = chData.distributionMonths + 1
        local detail = MK.CHANNEL_DETAILS.distribution
        if chData.distributionMonths > detail.kidnappingThreshold then
            local extra = (chData.distributionMonths - detail.kidnappingThreshold) * detail.kidnappingIncrement
            chData.currentCommissions.distribution = math.min(detail.kidnappingCap, detail.baseCommission + extra)
        else
            chData.currentCommissions.distribution = detail.baseCommission
        end
    else
        chData.distributionMonths = 0
        chData.currentCommissions.distribution = MK.CHANNEL_DETAILS.distribution.baseCommission
    end
end

--- Phase 8: 营销费用扣除
local function _DeductMarketingCosts(s, mk, project, GD, sold)
    local acc = mk.accumulation
    s.monthMarketingCost = 0  -- 重置本月营销费用（供ledger读取）

    -- 月度营销预算
    if s.marketingBudget > 0 then
        GD.company.cash = GD.company.cash - s.marketingBudget
        GD.company.monthlyExpense = GD.company.monthlyExpense + s.marketingBudget
        s.totalMarketingCost = s.totalMarketingCost + s.marketingBudget
        s.monthMarketingCost = s.monthMarketingCost + s.marketingBudget
        project.cost.marketingCost = project.cost.marketingCost + s.marketingBudget
        project.cost.totalCost = (project.cost.totalCost or 0) + s.marketingBudget
    end

    -- 媒体广告月费
    local mediaOpt = _FindById(MK.MEDIA_AD_LEVELS, acc.mediaAdLevel)
    if mediaOpt.monthlyCost > 0 then
        GD.company.cash = GD.company.cash - mediaOpt.monthlyCost
        GD.company.monthlyExpense = GD.company.monthlyExpense + mediaOpt.monthlyCost
        s.totalMarketingCost = s.totalMarketingCost + mediaOpt.monthlyCost
        s.monthMarketingCost = s.monthMarketingCost + mediaOpt.monthlyCost
        project.cost.marketingCost = project.cost.marketingCost + mediaOpt.monthlyCost
        project.cost.totalCost = (project.cost.totalCost or 0) + mediaOpt.monthlyCost
    end

    -- 自媒体月费
    local selfMediaOpt = _FindById(MK.SELF_MEDIA_OPTIONS, acc.selfMediaLevel)
    if selfMediaOpt.monthlyCost > 0 then
        GD.company.cash = GD.company.cash - selfMediaOpt.monthlyCost
        GD.company.monthlyExpense = GD.company.monthlyExpense + selfMediaOpt.monthlyCost
        s.totalMarketingCost = s.totalMarketingCost + selfMediaOpt.monthlyCost
        s.monthMarketingCost = s.monthMarketingCost + selfMediaOpt.monthlyCost
        project.cost.marketingCost = project.cost.marketingCost + selfMediaOpt.monthlyCost
        project.cost.totalCost = (project.cost.totalCost or 0) + selfMediaOpt.monthlyCost
    end

    -- 渠道佣金(使用动态佣金率)
    if sold > 0 then
        local avgArea = s.totalArea / math.max(1, s.totalUnits)
        local effDiscount = mk.pricing.effectiveDiscount
        local monthRevenue = sold * (avgArea * s.basePrice * effDiscount / 10000)
        local ch = s.activeChannels or {}
        local commissions = mk.channels.currentCommissions
        local channelCommission = 0
        if ch.agency then channelCommission = channelCommission + monthRevenue * commissions.agency end
        if ch.distribution then channelCommission = channelCommission + monthRevenue * commissions.distribution end
        if ch.referral then channelCommission = channelCommission + monthRevenue * commissions.referral end
        if channelCommission > 0 then
            channelCommission = math.floor(channelCommission * 100) / 100
            GD.company.cash = GD.company.cash - channelCommission
            GD.company.monthlyExpense = GD.company.monthlyExpense + channelCommission
            s.totalMarketingCost = s.totalMarketingCost + channelCommission
            s.monthMarketingCost = s.monthMarketingCost + channelCommission
            project.cost.marketingCost = project.cost.marketingCost + channelCommission
            project.cost.totalCost = (project.cost.totalCost or 0) + channelCommission
        end
    end
end

--- Phase 9: 签约流水线推进 + 逾期处理
local function _UpdateCollectionPipeline(mk, s, GD, project)
    local coll = mk.collection
    local bank = _FindById(MK.BANKS, coll.selectedBank)
    local speedMult = bank and bank.speedMult or 1.0
    s.monthRevenue = 0
    s.monthEscrowDeposit = 0
    s.monthFreeRevenue = 0

    local function settleBatch(batch)
        local unitRevenue = batch.unitRevenue
        if not unitRevenue then
            local avgArea = s.totalArea / math.max(1, s.totalUnits)
            local effDiscount = mk.pricing.effectiveDiscount
            unitRevenue = avgArea * s.basePrice * effDiscount / 10000
        end
        local batchRevenue = batch.unitCount * unitRevenue
        if batchRevenue <= 0 then return 0 end

        coll.collectedAmount = coll.collectedAmount + batchRevenue
        s.revenue = (s.revenue or 0) + batchRevenue
        s.monthRevenue = (s.monthRevenue or 0) + batchRevenue

        if project and project.regionalCompanyIdx then
            local rc = GD.company.regionalCompanies[project.regionalCompanyIdx]
            if rc then rc.pnl = (rc.pnl or 0) + batchRevenue end
        end

        local presaleFundRatio = (GD.policy and GD.policy.regulation and GD.policy.regulation.presaleFundRatio) or 0.25
        if GD.finance and GD.Finance then
            local escrowAmount = batchRevenue * presaleFundRatio
            local freeAmount = batchRevenue - escrowAmount
            if freeAmount > 0 then
                GD.company.cash = GD.company.cash + freeAmount
                GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + freeAmount
            end
            if escrowAmount > 0 and project then
                GD.Finance.DepositToEscrow(GD, project.id or project.name, escrowAmount)
            end
            s.monthEscrowDeposit = (s.monthEscrowDeposit or 0) + escrowAmount
            s.monthFreeRevenue = (s.monthFreeRevenue or 0) + freeAmount
        else
            local availableRatio = math.max(0.5, 1.0 - presaleFundRatio)
            local freeAmount = batchRevenue * availableRatio
            GD.company.cash = GD.company.cash + freeAmount
            GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + freeAmount
            s.monthFreeRevenue = (s.monthFreeRevenue or 0) + freeAmount
        end
        return batchRevenue
    end

    local newQueue = {}
    for _, batch in ipairs(coll.signingQueue) do
        local stage = MK.SIGN_STAGES[batch.stageIdx]
        if not stage then
            settleBatch(batch)
        else
            batch.elapsed = batch.elapsed + 1
            local reqDuration = math.max(0, math.ceil(stage.durationMonths / speedMult))
            if batch.elapsed >= reqDuration then
                -- 阶段完成前检查掉单
                local dropRate = stage.dropRate or 0
                local dropped = 0
                if dropRate > 0 and batch.unitCount > 1 then
                    dropped = math.floor(batch.unitCount * dropRate)
                    if dropped > 0 then
                        batch.unitCount = batch.unitCount - dropped
                        coll.overdueCount = coll.overdueCount + dropped
                    end
                end
                -- 推进到下一阶段
                batch.stageIdx = batch.stageIdx + 1
                batch.elapsed = 0
                -- 如果超出所有阶段, 立即回款
                if batch.stageIdx > #MK.SIGN_STAGES then
                    settleBatch(batch)
                else
                    if batch.unitCount > 0 then
                        table.insert(newQueue, batch)
                    end
                end
            else
                if batch.unitCount > 0 then
                    table.insert(newQueue, batch)
                end
            end
        end
    end
    coll.signingQueue = newQueue
end

--- Phase 10: 促销倒计时
local function _UpdatePromotionCountdown(s, project, GD)
    if s.promotionType ~= "none" and s.promotionMonthsLeft > 0 then
        s.promotionMonthsLeft = s.promotionMonthsLeft - 1
        if s.promotionMonthsLeft <= 0 then
            s.promotionType = "none"
            GD.AddEvent("【" .. project.name .. "】促销活动到期结束", "info")
        end
    end
end

--- Phase 11: 调价冷却
local function _UpdateRepriceCooldown(mk)
    local p = mk.pricing
    if p.repricing and p.repriceCooldown > 0 then
        p.repriceCooldown = p.repriceCooldown - 1
        if p.repriceCooldown <= 0 then
            p.repricing = false
        end
    end
end

--- Phase 12: 黄牛曝光检测(开盘当月执行一次)
local function _CheckScalperExposure(mk, GD, project)
    if mk.opening.usedScalper and not mk.opening.scalperExposed then
        if mk.opening.openedMonth == (GD.totalMonths or 0) then
            if math.random() < MK.SCALPER_OPTION.exposureProbability then
                mk.opening.scalperExposed = true
                mk.opening.reputationPenalty = MK.SCALPER_OPTION.reputationPenalty
                GD.company.reputation = (GD.company.reputation or 100) + MK.SCALPER_OPTION.reputationPenalty
                GD.AddEvent("【" .. project.name .. "】黄牛操盘被媒体曝光! 声誉-20!", "danger")
            end
        end
    end
end

-- ============================================================================
-- 月度更新主函数
-- ============================================================================
function MK.MonthlyUpdate(project, GD)
    if not project.sales.canSell then
        return {soldThisMonth = 0, collectedThisMonth = 0}
    end
    -- 自动修复：如果已可售但尚未定价，自动按产品基准价定价
    if project.sales.basePrice <= 0 then
        local suggestPrice = _GetProjectMarketPrice(project, GD)
        project.sales.basePrice = suggestPrice
        GD.AddEvent("【" .. project.name .. "】自动定价：" .. suggestPrice .. "元/平", "info")
    end
    -- 自动修复：如果已可售但尚未完成单元规划，自动全部设为可售
    if not project.unitPlan.planned then
        local totalArea = project.land.buildArea or 10000
        local avgUnitArea = 100
        local totalUnits = math.max(1, math.floor(totalArea / avgUnitArea))
        project.unitPlan.planned = true
        project.unitPlan.sellUnits = totalUnits
        project.unitPlan.holdUnits = 0
        project.sales.totalUnits = totalUnits
        GD.AddEvent("【" .. project.name .. "】自动完成单元规划：" .. totalUnits .. "套", "info")
    end
    local s = project.sales
    MK.EnsureMarketingFields(s)
    local mk = s.marketing
    s.monthRevenue = 0
    s.monthEscrowDeposit = 0
    s.monthFreeRevenue = 0
    s.monthContractedRevenue = 0

    local sold = 0
    if s.soldUnits < s.totalUnits then
        -- Phase 1: 限价政策
        _ApplyPricePolicy(s, GD, project)

        -- Phase 3: 来访量(需在蓄客更新前算，因为蓄客使用上月来访)
        _CalcMonthlyVisits(s, mk, project, GD)

        -- Phase 2: 蓄客更新(使用当月来访量)
        _UpdateAccumulation(mk, s)

        -- Phase 4: 转化率
        _CalcConversionRate(s, mk, project, GD)

        -- Phase 5: 综合折扣
        _CalcEffectiveDiscount(mk)

        -- Phase 5.5: 随机销售降速事件检测
        RE.CheckSalesSlowdownEvents(project, GD)

        -- Phase 6: 执行销售（只生成签约批次，不直接入账）
        sold = _ExecuteSales(s, mk, project, GD)

        -- Phase 7: 渠道绑架
        _UpdateChannelKidnapping(mk, s)

        -- Phase 8: 费用扣除
        _DeductMarketingCosts(s, mk, project, GD, sold)
    end

    -- Phase 9: 签约流水线。即使已售罄，也继续推进回款到账。
    local prevCollected = mk.collection.collectedAmount
    _UpdateCollectionPipeline(mk, s, GD, project)
    local collectedThisMonth = mk.collection.collectedAmount - prevCollected

    -- Phase 10: 促销倒计时
    _UpdatePromotionCountdown(s, project, GD)

    -- Phase 11: 调价冷却
    _UpdateRepriceCooldown(mk)

    -- Phase 12: 黄牛检测
    _CheckScalperExposure(mk, GD, project)

    -- Phase 13: 随机销售降速事件倒计时
    RE.UpdateSalesSlowdowns(project, GD)

    return {soldThisMonth = sold, collectedThisMonth = collectedThisMonth}
end

-- ============================================================================
-- 玩家操作函数 — 8.1 蓄客
-- ============================================================================
function MK.SetShowroom(project, optionId)
    MK.EnsureMarketingFields(project.sales)
    local acc = project.sales.marketing.accumulation
    local opt = _FindById(MK.SHOWROOM_OPTIONS, optionId)
    if not opt then return false, "无效展厅选项" end
    if acc.showroom == optionId then
        return true, "展厅已设置为: " .. opt.name
    end
    if opt.cost > 0 then
        acc.showroomCost = acc.showroomCost + opt.cost
    end
    acc.showroom = optionId
    return true, "展厅已设置为: " .. opt.name
end

function MK.SetMediaAd(project, levelId)
    MK.EnsureMarketingFields(project.sales)
    local acc = project.sales.marketing.accumulation
    local opt = _FindById(MK.MEDIA_AD_LEVELS, levelId)
    if not opt then return false, "无效投放级别" end
    acc.mediaAdLevel = levelId
    return true, "媒体广告调整为: " .. opt.name
end

function MK.SetSelfMedia(project, levelId)
    MK.EnsureMarketingFields(project.sales)
    local acc = project.sales.marketing.accumulation
    local opt = _FindById(MK.SELF_MEDIA_OPTIONS, levelId)
    if not opt then return false, "无效运营级别" end
    acc.selfMediaLevel = levelId
    return true, "自媒体运营调整为: " .. opt.name
end

function MK.SetDepositThreshold(project, thresholdId)
    MK.EnsureMarketingFields(project.sales)
    local acc = project.sales.marketing.accumulation
    local opt = _FindById(MK.DEPOSIT_THRESHOLDS, thresholdId)
    if not opt then return false, "无效验资门槛" end
    acc.depositThreshold = thresholdId
    return true, "验资门槛设为: " .. opt.name
end

-- ============================================================================
-- 玩家操作函数 — 8.2 价格策略
-- ============================================================================
function MK.ToggleDiscount(project, discountId, enabled)
    MK.EnsureMarketingFields(project.sales)
    local p = project.sales.marketing.pricing
    if p.discountsEnabled[discountId] == nil then return false, "无效折扣类型" end
    p.discountsEnabled[discountId] = enabled
    -- 重新计算综合折扣
    _CalcEffectiveDiscount(project.sales.marketing)
    return true
end

function MK.SetGmSpecialRate(project, rate)
    MK.EnsureMarketingFields(project.sales)
    rate = math.max(0.90, math.min(0.99, rate))
    project.sales.marketing.pricing.gmSpecialRate = rate
    _CalcEffectiveDiscount(project.sales.marketing)
    return true, "总经理特批折扣设为: " .. math.floor(rate * 100) .. "折"
end

function MK.RequestReprice(project, newPrice, GD, direction)
    MK.EnsureMarketingFields(project.sales)
    local mk = project.sales.marketing
    local s = project.sales
    direction = direction or "down"

    -- 批准开盘价是永久销售速度锚点，调价只能修改当前售价。
    s.basePrice = math.max(0, math.floor(tonumber(newPrice) or 0))
    _ApplyPriceSpeedState(s)
    mk.pricing.repricing = false
    mk.pricing.repriceCooldown = 0
    local reasonText = direction == "up" and "涨价" or "降价"
    table.insert(mk.pricing.priceHistory, {
        month = GD.totalMonths or 0,
        price = s.basePrice,
        reason = reasonText,
    })
    GD.AddEvent("【" .. project.name .. "】" .. reasonText .. "，新价格 " .. s.basePrice .. " 元/平", "info")
    return true
end

-- ============================================================================
-- 玩家操作函数 — 8.3 开盘方式
-- ============================================================================
function MK.SetOpeningMethod(project, methodId, GD)
    MK.EnsureMarketingFields(project.sales)
    local mk = project.sales.marketing
    if mk.opening.opened then return false, "已开盘，不可更改" end
    local opt = _FindById(MK.OPENING_METHODS, methodId)
    if not opt then return false, "无效开盘方式" end
    mk.opening.method = methodId
    mk.opening.opened = true
    mk.opening.openedMonth = GD.totalMonths or 0
    GD.AddEvent("【" .. project.name .. "】选择" .. opt.name .. "开盘!", "success")
    return true
end

function MK.HireScalper(project, GD)
    MK.EnsureMarketingFields(project.sales)
    local mk = project.sales.marketing
    if mk.opening.usedScalper then return false, "已雇佣黄牛" end
    if not mk.opening.opened then return false, "需先选择开盘方式" end
    mk.opening.usedScalper = true
    GD.AddEvent("【" .. project.name .. "】雇佣黄牛暗箱操作...有25%概率曝光!", "warning")
    return true
end

-- ============================================================================
-- 玩家操作函数 — 8.4 渠道管理(从 GD 迁移)
-- ============================================================================
function MK.SetMarketingBudget(project, budget)
    budget = math.max(0, math.floor(budget))
    project.sales.marketingBudget = budget
end

function MK.ToggleChannel(project, channelKey, enabled, GD)
    local ch = project.sales.activeChannels
    if ch[channelKey] == nil then return false, "无效渠道" end
    if channelKey == "selfSales" then return false, "自销团队不可关闭" end
    ch[channelKey] = enabled
    -- 关闭分销重置绑架计数
    if channelKey == "distribution" and not enabled then
        MK.EnsureMarketingFields(project.sales)
        project.sales.marketing.channels.distributionMonths = 0
        project.sales.marketing.channels.currentCommissions.distribution = MK.CHANNEL_DETAILS.distribution.baseCommission
    end
    local names = {agency = "代理公司", distribution = "分销渠道", referral = "全民营销"}
    local label = enabled and "开启" or "关闭"
    GD.AddEvent("【" .. project.name .. "】" .. label .. "渠道: " .. (names[channelKey] or channelKey), "info")
    return true
end

function MK.SetPromotion(project, promoType, months, GD)
    local s = project.sales
    if promoType == "none" then
        s.promotionType = "none"
        s.promotionMonthsLeft = 0
        GD.AddEvent("【" .. project.name .. "】取消促销活动", "info")
    else
        local names = {discount = "限时折扣", gift = "购房赠礼", event = "营销活动"}
        s.promotionType = promoType
        s.promotionMonthsLeft = months or 3
        GD.AddEvent("【" .. project.name .. "】启动促销: " .. (names[promoType] or promoType) .. " (" .. s.promotionMonthsLeft .. "个月)", "success")
    end
end

-- ============================================================================
-- 玩家操作函数 — 8.5 回款管理
-- ============================================================================
function MK.SelectBank(project, bankId)
    MK.EnsureMarketingFields(project.sales)
    local opt = _FindById(MK.BANKS, bankId)
    if not opt then return false, "无效银行" end
    project.sales.marketing.collection.selectedBank = bankId
    return true, "合作银行选择: " .. opt.name
end

function MK.ChaseOverdue(project, GD)
    MK.EnsureMarketingFields(project.sales)
    local coll = project.sales.marketing.collection
    if coll.overdueCount <= 0 then return false, "无逾期客户" end
    local chased = coll.overdueCount
    local recovered = math.floor(chased * MK.OVERDUE_CHASE_SUCCESS)
    local refunded = chased - recovered
    coll.overdueCount = 0
    if recovered > 0 then
        -- 催回客户重新进入签约
        table.insert(coll.signingQueue, {
            unitCount = recovered,
            stageIdx = 3,  -- 从按揭申请重新开始
            elapsed = 0,
            monthEntered = GD.totalMonths or 0,
        })
    end
    if refunded > 0 then
        coll.refundedUnits = coll.refundedUnits + refunded
        project.sales.soldUnits = math.max(0, project.sales.soldUnits - refunded)
        GD.AddEvent("【" .. project.name .. "】催收完成: " .. recovered .. "户恢复, " .. refunded .. "户退房", "warning")
    else
        GD.AddEvent("【" .. project.name .. "】催收完成: 全部" .. recovered .. "户恢复签约", "success")
    end
    return true
end

return MK
