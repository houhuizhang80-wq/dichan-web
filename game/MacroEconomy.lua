---@diagnostic disable: access-invisible
-- ============================================================================
-- MacroEconomy.lua - 宏观经济指标 + 房地产政策周期 + 黑天鹅事件库
-- ============================================================================

local ME = {}

-- ============================================================================
-- 2.1 宏观经济指标（实时波动）
-- ============================================================================

--- 创建默认宏观经济指标
function ME.CreateMacro()
    return {
        -- GDP与通胀
        gdpGrowth       = 8.0,     -- GDP增速(%), 2001年约8%
        cpi             = 1.5,     -- CPI同比(%), 温和通胀
        m2Growth        = 14.0,    -- M2增速(%), 广义货币
        -- 利率
        lpr5y           = 6.21,    -- 5年期LPR(%), 2001年基准约6.21%
        lprSpread       = 0,       -- 房贷利率加点(bp, 可负)
        -- 汇率
        exchangeRate    = 8.28,    -- CNY/USD, 2001年约8.28
        -- 居民杠杆
        householdLeverage = 12.0,  -- 居民杠杆率(%), 2001年仅约12%
        -- 房地产行业
        unsoldArea      = 12000,   -- 商品房待售面积(万平方米)
        reInvestment    = 6300,    -- 房地产开发投资额(亿元), 2001年约6344亿
        -- 衍生指标(自动计算)
        effectiveMortgageRate = 6.21,  -- 实际房贷利率 = lpr5y + spread
        realInterestRate = 4.71,       -- 实际利率 = lpr5y - cpi
        moneyLooseness  = 0,           -- 货币宽松度(-100~100, 正=宽松)

        -- ========== 新增宏观指标 ==========
        -- GDP总量与结构
        gdpLevel        = 109655,      -- GDP总量(亿元), 2001年约10.97万亿
        gdpPerCapita    = 8622,        -- 人均GDP(元), 2001年约8622
        fixedInvestRate = 36.0,        -- 固定资产投资增速(%)
        consumptionRate = 45.0,        -- 最终消费率(%)
        exportGrowth    = 7.0,         -- 出口增速(%)

        -- 劳动力与人口
        wageGrowth      = 12.0,        -- 城镇平均工资增速(%)
        urbanizationRate= 37.7,        -- 城镇化率(%), 2001年约37.7%
        populationGrowth= 0.70,        -- 人口自然增长率(%)
        unemploymentRate= 3.6,         -- 城镇调查失业率(%)
        laborForce      = 73025,       -- 就业人口(万人)

        -- 制造业与景气
        pmi             = 51.0,        -- 制造业PMI(50为荣枯线)
        ppi             = 0.5,         -- 工业生产者出厂价格指数(%)

        -- 房地产专项
        avgHousePrice   = 2170,        -- 商品房均价(元/㎡), 2001年约2170
        avgIncome       = 6860,        -- 城镇居民人均可支配年收入(元), 2001年约6860
        housingPriceToIncome = 6.5,    -- 房价收入比(全国平均, 以90㎡计)
        rentalYield     = 4.5,         -- 租金回报率(%)
        landPriceIndex  = 100,         -- 地价指数(基期=100)

        -- 居民部门
        savingsRate     = 38.0,        -- 居民储蓄率(%)
        consumerConfidence = 105,      -- 消费者信心指数(100=中性)

        -- 财政
        fiscalDeficitRate = 2.5,       -- 财政赤字率(%)
        govDebtToGdp    = 16.0,        -- 政府债务/GDP(%)
    }
end

--- 每月更新宏观经济指标
---@param macro table 宏观经济指标表
---@param cycle string 当前经济周期
---@param totalMonths number 游戏总月数
function ME.UpdateMacro(macro, cycle, totalMonths)
    -- 年份推算(2001+)
    local gameYear = 2001 + math.floor(totalMonths / 12)

    -- ---- GDP增速 ----
    -- 长期趋势: GDP增速从2001年8%逐步降至2024年5%
    local yearsSince = math.min(30, math.floor(totalMonths / 12))
    local trendGdp = 8.0 - yearsSince * 0.12 -- 每年降约0.12个百分点
    trendGdp = math.max(3.0, trendGdp)
    -- 周期波动
    local cycleGdp = ({boom = 1.2, recovery = 0.5, recession = -0.8, depression = -1.5})[cycle] or 0
    -- 随机噪声
    local noiseGdp = (math.random() - 0.5) * 0.6
    macro.gdpGrowth = math.max(-2.0, math.min(15.0,
        trendGdp + cycleGdp + noiseGdp))
    macro.gdpGrowth = math.floor(macro.gdpGrowth * 10) / 10

    -- ---- CPI ----
    local baseCpi = ({boom = 3.0, recovery = 1.8, recession = 1.0, depression = 0.2})[cycle] or 1.5
    local noiseCpi = (math.random() - 0.5) * 1.0
    macro.cpi = math.max(-1.0, math.min(8.0, baseCpi + noiseCpi))
    macro.cpi = math.floor(macro.cpi * 10) / 10

    -- ---- M2增速 ----
    -- 宽松期M2增长快，紧缩期慢
    local baseM2 = ({boom = 16.0, recovery = 14.0, recession = 10.0, depression = 8.0})[cycle] or 12.0
    -- 长期趋势: M2增速从14%降至8%
    local trendM2 = math.max(7.0, 14.0 - yearsSince * 0.25)
    local noiseM2 = (math.random() - 0.5) * 2.0
    macro.m2Growth = math.max(5.0, math.min(25.0, (baseM2 + trendM2) / 2 + noiseM2))
    macro.m2Growth = math.floor(macro.m2Growth * 10) / 10

    -- ---- LPR5Y ----
    -- 长期趋势: 从6.21%降到3.95%
    local trendLpr = math.max(3.5, 6.21 - yearsSince * 0.09)
    local cycleLpr = ({boom = 0.15, recovery = -0.05, recession = -0.10, depression = -0.20})[cycle] or 0
    local noiseLpr = (math.random() - 0.5) * 0.10
    macro.lpr5y = math.max(3.0, math.min(8.0, trendLpr + cycleLpr + noiseLpr))
    macro.lpr5y = math.floor(macro.lpr5y * 100) / 100

    -- ---- 房贷利率加点 ----
    -- 繁荣期加点高，萧条期可为负（打折）
    local targetSpread = ({boom = 50, recovery = 10, recession = -20, depression = -50})[cycle] or 0
    macro.lprSpread = macro.lprSpread + (targetSpread - macro.lprSpread) * 0.1
    macro.lprSpread = math.floor(macro.lprSpread)

    -- ---- 实际房贷利率 ----
    macro.effectiveMortgageRate = macro.lpr5y + macro.lprSpread / 100
    macro.effectiveMortgageRate = math.floor(macro.effectiveMortgageRate * 100) / 100

    -- ---- 实际利率 ----
    macro.realInterestRate = macro.lpr5y - macro.cpi
    macro.realInterestRate = math.floor(macro.realInterestRate * 100) / 100

    -- ---- 汇率 CNY/USD ----
    -- 长期趋势: 从8.28逐步升值到6.3(2014)再贬到7.2
    local trendFx
    if yearsSince <= 13 then
        trendFx = 8.28 - yearsSince * 0.15  -- 升值阶段
    else
        trendFx = 6.3 + (yearsSince - 13) * 0.06  -- 贬值阶段
    end
    trendFx = math.max(6.0, math.min(8.5, trendFx))
    local noiseFx = (math.random() - 0.5) * 0.10
    macro.exchangeRate = math.max(5.5, math.min(9.0, trendFx + noiseFx))
    macro.exchangeRate = math.floor(macro.exchangeRate * 100) / 100

    -- ---- 居民杠杆率 ----
    -- 长期趋势: 从12%升至62%(2023)
    local trendLev = math.min(70, 12 + yearsSince * 2.0)
    local cycleLev = ({boom = 1.0, recovery = 0.5, recession = -0.3, depression = -0.8})[cycle] or 0
    macro.householdLeverage = math.max(8, math.min(80, trendLev + cycleLev + (math.random() - 0.5) * 1.0))
    macro.householdLeverage = math.floor(macro.householdLeverage * 10) / 10

    -- ---- 待售面积(万平米) ----
    local baseUnsold = ({boom = -500, recovery = -200, recession = 800, depression = 1500})[cycle] or 0
    macro.unsoldArea = math.max(3000, math.min(80000,
        macro.unsoldArea + baseUnsold + (math.random() - 0.5) * 600))
    macro.unsoldArea = math.floor(macro.unsoldArea)

    -- ---- 房地产开发投资(亿元) ----
    -- 长期增长然后2021后下降
    local trendInvest
    if yearsSince <= 20 then
        trendInvest = 6300 * (1 + yearsSince * 0.12) -- 年增约12%
    else
        trendInvest = 6300 * (1 + 20 * 0.12) * (1 - (yearsSince - 20) * 0.05)
    end
    trendInvest = math.max(3000, trendInvest)
    local cycleInvest = ({boom = 0.05, recovery = 0.02, recession = -0.03, depression = -0.08})[cycle] or 0
    macro.reInvestment = math.floor(trendInvest * (1 + cycleInvest) + (math.random() - 0.5) * 500)
    macro.reInvestment = math.max(2000, macro.reInvestment)

    -- ---- 货币宽松度 ----
    macro.moneyLooseness = math.floor((macro.m2Growth - macro.gdpGrowth - macro.cpi) * 10)
    macro.moneyLooseness = math.max(-100, math.min(100, macro.moneyLooseness))

    -- ========== 新增指标更新 ==========

    -- ---- GDP总量 (GDP_t = GDP_{t-1} × (1 + g/100/12)) ----
    macro.gdpLevel = macro.gdpLevel * (1 + macro.gdpGrowth / 100 / 12)
    macro.gdpLevel = math.floor(macro.gdpLevel)

    -- ---- 人均GDP ----
    local population = 127627 + yearsSince * 500 -- 万人, 简化人口增长
    if yearsSince > 15 then population = 127627 + 15 * 500 + (yearsSince - 15) * 100 end -- 人口增长放缓
    if yearsSince > 22 then population = population - (yearsSince - 22) * 200 end -- 人口负增长
    macro.gdpPerCapita = math.floor(macro.gdpLevel * 10000 / population) -- 元/人
    macro.populationGrowth = yearsSince < 15 and 0.7 - yearsSince * 0.02
        or (yearsSince < 22 and 0.4 - (yearsSince - 15) * 0.05 or -0.1 - (yearsSince - 22) * 0.05)
    macro.populationGrowth = math.floor(math.max(-0.5, macro.populationGrowth) * 100) / 100

    -- ---- 固定资产投资增速 ----
    local baseInvest = math.max(3, 36 - yearsSince * 1.2) -- 从36%降至3%
    local cycleFixedInv = ({boom = 3, recovery = 1.5, recession = -2, depression = -5})[cycle] or 0
    macro.fixedInvestRate = math.max(-5, math.min(45, baseInvest + cycleFixedInv + (math.random() - 0.5) * 3))
    macro.fixedInvestRate = math.floor(macro.fixedInvestRate * 10) / 10

    -- ---- 消费率 ----
    local baseCons = math.min(60, 45 + yearsSince * 0.6) -- 消费率长期上升
    local cycleCons = ({boom = 2, recovery = 1, recession = -1.5, depression = -3})[cycle] or 0
    macro.consumptionRate = math.max(35, math.min(70, baseCons + cycleCons + (math.random() - 0.5) * 1))
    macro.consumptionRate = math.floor(macro.consumptionRate * 10) / 10

    -- ---- 出口增速 ----
    local baseExport = math.max(0, 7 + (yearsSince < 7 and yearsSince * 3 or 21 - yearsSince * 0.8))
    local cycleExport = ({boom = 5, recovery = 2, recession = -8, depression = -15})[cycle] or 0
    macro.exportGrowth = math.max(-20, math.min(35, baseExport + cycleExport + (math.random() - 0.5) * 5))
    macro.exportGrowth = math.floor(macro.exportGrowth * 10) / 10

    -- ---- 工资增速 (与GDP和CPI关联) ----
    local baseWage = macro.gdpGrowth + macro.cpi * 0.5 + 2
    local cycleWage = ({boom = 2, recovery = 1, recession = -2, depression = -4})[cycle] or 0
    macro.wageGrowth = math.max(-3, math.min(20, baseWage + cycleWage + (math.random() - 0.5) * 2))
    macro.wageGrowth = math.floor(macro.wageGrowth * 10) / 10

    -- ---- 城镇化率 (长期趋势: 37.7%→65%+) ----
    local urbanTrend = math.min(68, 37.7 + yearsSince * 1.3)
    if yearsSince > 20 then urbanTrend = math.min(72, 37.7 + 20 * 1.3 + (yearsSince - 20) * 0.3) end
    macro.urbanizationRate = math.max(macro.urbanizationRate, urbanTrend + (math.random() - 0.5) * 0.2)
    macro.urbanizationRate = math.floor(macro.urbanizationRate * 10) / 10

    -- ---- 失业率 ----
    local baseUnemp = ({boom = 3.2, recovery = 3.8, recession = 4.5, depression = 5.5})[cycle] or 4.0
    macro.unemploymentRate = math.max(2.5, math.min(8.0, baseUnemp + (math.random() - 0.5) * 0.5))
    macro.unemploymentRate = math.floor(macro.unemploymentRate * 10) / 10

    -- ---- PMI (荣枯线50) ----
    local basePmi = ({boom = 53, recovery = 51, recession = 48, depression = 45})[cycle] or 50
    macro.pmi = math.max(40, math.min(58, basePmi + (math.random() - 0.5) * 2))
    macro.pmi = math.floor(macro.pmi * 10) / 10

    -- ---- PPI ----
    local basePpi = ({boom = 4, recovery = 1, recession = -2, depression = -5})[cycle] or 0
    macro.ppi = math.max(-8, math.min(12, basePpi + (math.random() - 0.5) * 2))
    macro.ppi = math.floor(macro.ppi * 10) / 10

    -- ---- 房价均价 (元/㎡, 与经济周期和LPR相关) ----
    local priceTrend
    if yearsSince <= 20 then
        priceTrend = 2170 * math.pow(1.08, yearsSince) -- 年均涨8%
    else
        priceTrend = 2170 * math.pow(1.08, 20) * math.pow(1.01, yearsSince - 20) -- 之后仅涨1%
    end
    local priceMultCycle = ({boom = 1.05, recovery = 1.02, recession = 0.97, depression = 0.92})[cycle] or 1.0
    macro.avgHousePrice = math.floor(priceTrend * priceMultCycle * (1 + (math.random() - 0.5) * 0.03))

    -- ---- 人均可支配收入 (元/年) ----
    local incomeTrend = 6860 * math.pow(1 + macro.wageGrowth / 100, yearsSince / (yearsSince + 1)) -- 平滑
    incomeTrend = 6860
    for y = 1, yearsSince do
        local avgGrowth = math.max(3, 12 - y * 0.3)
        incomeTrend = incomeTrend * (1 + avgGrowth / 100)
    end
    macro.avgIncome = math.floor(incomeTrend)

    -- ---- 房价收入比 (以90㎡标准住宅计) ----
    if macro.avgIncome > 0 then
        local householdIncome = macro.avgIncome * 2 -- 双职工家庭
        macro.housingPriceToIncome = macro.avgHousePrice * 90 / householdIncome
        macro.housingPriceToIncome = math.floor(macro.housingPriceToIncome * 10) / 10
    end

    -- ---- 租金回报率 (租售比倒数年化) ----
    if macro.avgHousePrice > 0 then
        local monthlyRentPerSqm = macro.avgHousePrice / (12 * 50) * ({boom = 1.1, recovery = 1.0, recession = 0.9, depression = 0.8})[cycle]
        macro.rentalYield = monthlyRentPerSqm * 12 / macro.avgHousePrice * 100
        macro.rentalYield = math.floor(math.max(1.0, math.min(8.0, macro.rentalYield)) * 10) / 10
    end

    -- ---- 地价指数 (跟随房价但波动更大) ----
    local hpDelta = (priceMultCycle - 1.0) * 100 -- 房价月度变化百分比(约-8~+5)
    local landDelta = hpDelta * 1.5 -- 地价波动是房价的1.5倍
    macro.landPriceIndex = math.max(40, math.min(250, macro.landPriceIndex + landDelta))
    macro.landPriceIndex = math.floor(macro.landPriceIndex * 10) / 10

    -- ---- 居民储蓄率 (长期下降趋势) ----
    local baseSave = math.max(28, 38 - yearsSince * 0.4)
    local cycleSave = ({boom = -1, recovery = 0, recession = 2, depression = 3})[cycle] or 0
    macro.savingsRate = math.max(25, math.min(45, baseSave + cycleSave + (math.random() - 0.5) * 1))
    macro.savingsRate = math.floor(macro.savingsRate * 10) / 10

    -- ---- 消费者信心指数 ----
    local baseConf = ({boom = 115, recovery = 105, recession = 90, depression = 75})[cycle] or 100
    macro.consumerConfidence = math.max(60, math.min(130, baseConf + (math.random() - 0.5) * 5))
    macro.consumerConfidence = math.floor(macro.consumerConfidence * 10) / 10

    -- ---- 财政赤字率 ----
    local baseFiscal = ({boom = 1.5, recovery = 2.5, recession = 3.5, depression = 4.0})[cycle] or 2.5
    macro.fiscalDeficitRate = math.max(0.5, math.min(5.0, baseFiscal + (math.random() - 0.5) * 0.5))
    macro.fiscalDeficitRate = math.floor(macro.fiscalDeficitRate * 10) / 10

    -- ---- 政府债务/GDP ----
    macro.govDebtToGdp = math.min(80, 16 + yearsSince * 1.8 + (macro.fiscalDeficitRate - 2.5) * 0.5)
    macro.govDebtToGdp = math.floor(math.max(10, macro.govDebtToGdp) * 10) / 10
end

-- ============================================================================
-- 2.2 房地产政策周期（核心变量）
-- ============================================================================

--- 创建默认政策集
function ME.CreatePolicy()
    return {
        -- ========== 金融政策 ==========
        finance = {
            downPaymentFirst  = 0.30,   -- 首套首付比例 (20%-70%)
            downPaymentSecond = 0.40,   -- 二套首付比例 (30%-80%)
            mortgageRateCap   = 1.1,    -- 房贷利率上浮上限倍数(0.7~1.3, 1.0=基准)
            devLoanQuota      = 1.0,    -- 开发贷额度管控系数(0.5~1.5, 1=正常)
            devLoanTightness  = "normal", -- loose/normal/tight
        },
        -- ========== 土地政策 ==========
        land = {
            supplyPace        = 1.0,    -- 供地节奏系数(0.5~2.0, 1=正常)
            auctionMode       = "bid",  -- bid=招拍挂 / negotiate=勾地
            mandatoryBuild    = 0,      -- 配建保障房比例(0~0.30)
            holdRequirement   = 0,      -- 自持比例要求(0~0.30)
            maxPremiumRate    = 999,    -- 最高溢价率(%)(15~999, 999=不限)
        },
        -- ========== 交易政策 ==========
        transaction = {
            purchaseLimitLocal   = 999,  -- 本地户籍限购套数(1~999, 999=不限购)
            purchaseLimitNonLocal= 999,  -- 外地户籍限购套数(0~999)
            sellLockYears        = 0,    -- 限售年限(0~5, 0=无限售)
            priceCeilingRatio    = 999,  -- 限价上限(备案价/市场价%, 100~999, 999=无限价)
            priceFloorRatio      = 0,    -- 限价下限(备案价/市场价%, 0~100, 0=无限价)
            taxOnSecondary       = 0,    -- 二手房交易附加税率(0~0.05)
        },
        -- ========== 监管政策 ==========
        regulation = {
            presaleFundRatio  = 0.25,   -- 预售资金监管比例(0.20~0.50)
            redLine1Threshold = 0.70,   -- 三条红线: 剔除预收款的资产负债率阈值
            redLine2Threshold = 1.0,    -- 三条红线: 净负债率阈值
            redLine3Threshold = 1.0,    -- 三条红线: 现金短债比阈值
            qualInspection    = "normal", -- lax/normal/strict (质量监管力度)
        },
        -- ========== 政策综合强度 ==========
        overall = {
            tightness = 0,        -- -100(极度宽松) ~ 100(极度收紧)
            trend = "neutral",    -- loosening/neutral/tightening
            lastChangeMonth = 0,  -- 上次政策变动月份
        },
    }
end

--- 每月更新政策（渐进式变化）
---@param policy table 政策表
---@param cycle string 经济周期
---@param macro table 宏观指标
---@param totalMonths number 游戏月数
function ME.UpdatePolicy(policy, cycle, macro, totalMonths)
    local f = policy.finance
    local l = policy.land
    local t = policy.transaction
    local r = policy.regulation
    local o = policy.overall

    -- 政策不是每月变，约3-6个月一次调整
    if totalMonths - o.lastChangeMonth < 3 then return end
    if math.random() > 0.40 then return end  -- 40%概率在窗口期调整
    o.lastChangeMonth = totalMonths

    -- 判断政策方向
    local shouldTighten = (cycle == "boom" and macro.householdLeverage > 50)
        or (macro.cpi > 4.0)
        or (macro.gdpGrowth > 10)
    local shouldLoosen = (cycle == "depression")
        or (cycle == "recession" and macro.unsoldArea > 40000)
        or (macro.gdpGrowth < 4.0)

    if shouldTighten and not shouldLoosen then
        o.trend = "tightening"
        o.tightness = math.min(100, o.tightness + math.random(5, 15))
        ME._tightenPolicy(f, l, t, r)
    elseif shouldLoosen and not shouldTighten then
        o.trend = "loosening"
        o.tightness = math.max(-100, o.tightness - math.random(5, 15))
        ME._loosenPolicy(f, l, t, r)
    else
        o.trend = "neutral"
        -- 微幅随机波动
        if math.random() < 0.3 then
            if math.random() < 0.5 then
                ME._tightenPolicy(f, l, t, r, true)
            else
                ME._loosenPolicy(f, l, t, r, true)
            end
        end
    end
end

function ME._tightenPolicy(f, l, t, r, mild)
    local step = mild and 1 or 2
    -- 金融收紧
    f.downPaymentFirst = math.min(0.70, f.downPaymentFirst + 0.05 * step)
    f.downPaymentSecond = math.min(0.80, f.downPaymentSecond + 0.05 * step)
    f.mortgageRateCap = math.min(1.3, f.mortgageRateCap + 0.05 * step)
    f.devLoanQuota = math.max(0.5, f.devLoanQuota - 0.1 * step)
    f.devLoanTightness = mild and "normal" or "tight"
    -- 土地收紧
    l.supplyPace = math.max(0.5, l.supplyPace - 0.1 * step)
    l.mandatoryBuild = math.min(0.30, l.mandatoryBuild + 0.02 * step)
    l.holdRequirement = math.min(0.30, l.holdRequirement + 0.02 * step)
    if not mild then l.maxPremiumRate = math.max(15, l.maxPremiumRate - 20) end
    -- 交易收紧
    if not mild then
        t.purchaseLimitLocal = math.max(1, math.min(t.purchaseLimitLocal, 3))
        t.purchaseLimitNonLocal = math.max(0, math.min(t.purchaseLimitNonLocal, 1))
        t.sellLockYears = math.min(5, t.sellLockYears + 1)
        t.priceCeilingRatio = math.max(100, math.min(t.priceCeilingRatio, 115))
        t.priceFloorRatio = math.max(t.priceFloorRatio, 85)
    end
    -- 监管收紧
    r.presaleFundRatio = math.min(0.50, r.presaleFundRatio + 0.03 * step)
    r.qualInspection = mild and "normal" or "strict"
end

function ME._loosenPolicy(f, l, t, r, mild)
    local step = mild and 1 or 2
    -- 金融放松
    f.downPaymentFirst = math.max(0.15, f.downPaymentFirst - 0.05 * step)
    f.downPaymentSecond = math.max(0.25, f.downPaymentSecond - 0.05 * step)
    f.mortgageRateCap = math.max(0.7, f.mortgageRateCap - 0.05 * step)
    f.devLoanQuota = math.min(1.5, f.devLoanQuota + 0.1 * step)
    f.devLoanTightness = mild and "normal" or "loose"
    -- 土地放松
    l.supplyPace = math.min(2.0, l.supplyPace + 0.1 * step)
    l.mandatoryBuild = math.max(0, l.mandatoryBuild - 0.02 * step)
    l.holdRequirement = math.max(0, l.holdRequirement - 0.02 * step)
    l.maxPremiumRate = 999
    -- 交易放松
    if not mild then
        t.purchaseLimitLocal = 999
        t.purchaseLimitNonLocal = math.min(999, t.purchaseLimitNonLocal + 2)
        t.sellLockYears = math.max(0, t.sellLockYears - 1)
        t.priceCeilingRatio = 999
        t.priceFloorRatio = 0
    end
    -- 监管放松
    r.presaleFundRatio = math.max(0.20, r.presaleFundRatio - 0.03 * step)
    r.qualInspection = mild and "normal" or "lax"
end

--- 计算政策对需求的综合影响系数
function ME.GetPolicyDemandMultiplier(policy)
    local mult = 1.0
    local f = policy.finance
    local t = policy.transaction
    -- 首付影响: 首付越高需求越低
    if f.downPaymentFirst > 0.30 then
        mult = mult - (f.downPaymentFirst - 0.30) * 1.5  -- 每高10%，需求降15%
    elseif f.downPaymentFirst < 0.25 then
        mult = mult + (0.25 - f.downPaymentFirst) * 1.0
    end
    -- 利率上浮影响
    if f.mortgageRateCap > 1.1 then
        mult = mult - (f.mortgageRateCap - 1.1) * 0.5
    elseif f.mortgageRateCap < 0.9 then
        mult = mult + (0.9 - f.mortgageRateCap) * 0.8
    end
    -- 限购影响
    if t.purchaseLimitNonLocal == 0 then
        mult = mult - 0.15
    elseif t.purchaseLimitNonLocal <= 1 then
        mult = mult - 0.08
    end
    -- 限售影响
    if t.sellLockYears >= 3 then
        mult = mult - 0.08
    end
    -- 限价上限对高端盘影响
    if t.priceCeilingRatio < 120 then
        mult = mult - 0.05
    end
    return math.max(0.4, math.min(1.6, mult))
end

--- 计算政策对开发商融资的影响
function ME.GetPolicyFinanceMultiplier(policy)
    local f = policy.finance
    local mult = f.devLoanQuota
    -- 紧缩时额外惩罚
    if f.devLoanTightness == "tight" then
        mult = mult * 0.8
    elseif f.devLoanTightness == "loose" then
        mult = mult * 1.2
    end
    return math.max(0.3, math.min(2.0, mult))
end

-- ============================================================================
-- 2.3 黑天鹅事件库 (200+ 个事件)
-- ============================================================================

-- 事件模板格式:
-- { text=显示文本, type=info/success/warning/danger, cat=行业/区域/项目/政策/金融/国际,
--   duration=持续月数(0=即时), probability=基础概率权重,
--   condition=触发条件函数(可选), effect=效果函数 }

ME._blackSwanPool = {}

--- 初始化事件池(延迟构建,只调一次)
function ME.InitBlackSwanPool()
    if #ME._blackSwanPool > 0 then return end

    local pool = ME._blackSwanPool

    -- ======================================================================
    -- 行业性事件 (60个)
    -- ======================================================================

    -- 行业暴雷/信用
    local industryCredit = {
        {"大型房企资金链断裂，行业信心崩塌", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.75; m.householdLeverage = m.householdLeverage - 2 end, 3},
        {"龙头房企债务违约，信用债市场冻结", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.80; e.interestRate = e.interestRate + 0.3 end, 4},
        {"百强房企暴雷，多城楼盘停工", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.70 end, 6},
        {"房企理财产品暴雷，员工集体维权", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 2},
        {"房企美元债集体违约，海外评级下调", "warning", function(e,m) m.exchangeRate = m.exchangeRate + 0.15 end, 3},
        {"多家房企同时暴雷，银行收紧开发贷", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.78 end, 4},
        {"房企老板跑路，项目全面停工", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.85 end, 2},
        {"物业公司挪用维修基金事件曝光", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 1},
        {"知名房企创始人被调查，股价暴跌", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.88 end, 3},
        {"房企集体降薪裁员，行业人才流失", "warning", function(e,m) end, 2},
        {"房企供应商三角债危机爆发", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.92 end, 2},
        {"房企预售资金被违规挪用曝光", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.85 end, 3},
    }
    for _, v in ipairs(industryCredit) do
        table.insert(pool, {text=v[1], type=v[2], cat="行业", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- 行业正面事件
    local industryPositive = {
        {"行业白名单制度实施，优质房企获支持", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"房地产融资协调机制建立，市场信心修复", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 4},
        {"房企成功债务重组，行业触底回暖", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"保交楼基金设立，购房者信心恢复", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.12 end, 3},
        {"REITs扩容至住宅领域，资产退出渠道打通", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 4},
        {"装配式建筑补贴政策出台，建造成本下降", "info", function(e,m) end, 2},
        {"绿色建筑标准升级，带动改善需求", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 2},
        {"房企成功IPO上市，行业融资环境改善", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"房企与科技公司合作智慧社区，品牌溢价提升", "info", function(e,m) e.priceIndex = e.priceIndex + 1 end, 1},
        {"全国住宅品质提升年活动，改善需求释放", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"房地产行业去库存成效显著", "success", function(e,m) m.unsoldArea = m.unsoldArea * 0.9 end, 3},
        {"住房租赁市场规范化，长租公寓政策落地", "info", function(e,m) end, 2},
    }
    for _, v in ipairs(industryPositive) do
        table.insert(pool, {text=v[1], type=v[2], cat="行业", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- 行业中性/结构性事件
    local industryNeutral = {
        {"央企地产整合加速，竞争格局生变", "info", function(e,m) end, 2},
        {"代建模式兴起，轻资产转型趋势明显", "info", function(e,m) end, 1},
        {"房企多元化业务全面亏损，回归主业", "warning", function(e,m) end, 1},
        {"物业管理行业并购潮涌", "info", function(e,m) end, 1},
        {"精装修交付投诉激增，维权事件频发", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.97 end, 1},
        {"房企高管集体跳槽引发行业震动", "info", function(e,m) end, 1},
        {"第三方验房机构兴起，透明度提升", "info", function(e,m) end, 1},
        {"房企数字化转型成效显现", "info", function(e,m) end, 1},
        {"全国商品房质量大检查", "warning", function(e,m) end, 2},
        {"房企年报季暴露利润大幅下滑", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 1},
        {"建筑工人用工荒，施工成本上升", "warning", function(e,m) end, 2},
        {"房地产税立法进程引发热议", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.93 end, 3},
    }
    for _, v in ipairs(industryNeutral) do
        table.insert(pool, {text=v[1], type=v[2], cat="行业", effect=v[3], duration=v[4] or 1, weight=1})
    end

    -- ======================================================================
    -- 政策性事件 (50个)
    -- ======================================================================
    local policyEvents = {
        {"央行宣布全面降准50基点", "success", function(e,m) e.interestRate = math.max(3.0, e.interestRate - 0.25); m.m2Growth = m.m2Growth + 1.5 end, 3},
        {"LPR下调25个基点至历史新低", "success", function(e,m) m.lpr5y = math.max(3.0, m.lpr5y - 0.25); m.effectiveMortgageRate = m.lpr5y + m.lprSpread/100 end, 4},
        {"住建部认房不认贷政策全面推广", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.15 end, 4},
        {"多城限购全面松绑", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.20 end, 6},
        {"首付比例下调至历史最低15%", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.18 end, 4},
        {"存量房贷利率统一下调", "success", function(e,m) m.effectiveMortgageRate = math.max(3.0, m.effectiveMortgageRate - 0.3) end, 3},
        {"个税房贷利息专项扣除额度翻倍", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"多城放开落户限制，购房门槛降低", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"公积金贷款额度大幅上调", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 2},
        {"人才购房补贴政策出台", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.04 end, 2},
        {"棚改货币化安置重启", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.25; e.priceIndex = e.priceIndex + 3 end, 6},
        {"城中村改造三年攻坚计划启动", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 6},
        {"央行加息25基点应对通胀", "warning", function(e,m) e.interestRate = e.interestRate + 0.25; e.demandMultiplier = e.demandMultiplier * 0.92 end, 3},
        {"限购政策全面升级，外地户籍禁购", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.80 end, 6},
        {"二手房指导价政策全面推行", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.88 end, 4},
        {"三条红线政策正式实施", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 6},
        {"预售资金监管全面收紧至50%", "warning", function(e,m) end, 4},
        {"经营贷违规进入楼市被严查", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.93 end, 3},
        {"二手房停贷，市场流动性冻结", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.75 end, 3},
        {"学区房政策改革，多校划片推行", "warning", function(e,m) e.priceIndex = e.priceIndex - 2 end, 4},
        {"房产税试点城市扩围", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.88; e.priceIndex = e.priceIndex - 2 end, 6},
        {"共有产权房大规模供应", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 3},
        {"限售政策延长至5年", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 3},
        {"土地增值税清算加速", "warning", function(e,m) end, 2},
        {"新版商品房预售管理办法出台", "info", function(e,m) end, 2},
        {"住房保障法正式通过", "info", function(e,m) end, 3},
        {"城市更新条例发布实施", "info", function(e,m) end, 2},
        {"地方政府密集出台救市政策", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 3},
        {"取消商品房预售制度改为现房销售", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.85 end, 6},
        {"地方政府收购商品房做保障房", "success", function(e,m) m.unsoldArea = m.unsoldArea * 0.85; e.demandMultiplier = e.demandMultiplier * 1.05 end, 4},
    }
    for _, v in ipairs(policyEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="政策", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- ======================================================================
    -- 区域性事件 (40个)
    -- ======================================================================
    local regionalEvents = {
        {"某城市房价暴跌30%，引发断供潮", "danger", function(e,m) e.priceIndex = e.priceIndex - 5; e.demandMultiplier = e.demandMultiplier * 0.80 end, 4},
        {"某热点城市万人摇号抢房", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.15; e.priceIndex = e.priceIndex + 2 end, 2},
        {"某城市发布人才安居计划", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"某城市地铁新线路获批，沿线升值", "success", function(e,m) e.priceIndex = e.priceIndex + 2 end, 2},
        {"某城市名校签约入驻新区", "success", function(e,m) e.priceIndex = e.priceIndex + 1.5 end, 2},
        {"某城市产业园区招商成功，就业大增", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 3},
        {"某城市二手房挂牌量暴增50%", "warning", function(e,m) e.priceIndex = e.priceIndex - 2; e.demandMultiplier = e.demandMultiplier * 0.92 end, 3},
        {"某城市业主集体断供事件", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.82 end, 4},
        {"某城市土拍多地块流拍", "warning", function(e,m) e.priceIndex = e.priceIndex - 1 end, 2},
        {"某城市土拍地王再现", "info", function(e,m) e.priceIndex = e.priceIndex + 3 end, 1},
        {"某城市放开落户限制", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 4},
        {"某城市获批国家级中心城市", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.12; e.priceIndex = e.priceIndex + 3 end, 6},
        {"某城市遭遇大规模拆迁维权", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 2},
        {"某城市工厂搬迁释放大量用地", "info", function(e,m) end, 2},
        {"某城市楼盘集中维权潮", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 2},
        {"某城市实施购房补贴每套5万", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 3},
        {"某城市出台二孩家庭购房优惠", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.04 end, 2},
        {"某城市发现重大矿产资源", "success", function(e,m) e.priceIndex = e.priceIndex + 1 end, 2},
        {"某城市人口净流出超10万", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 4},
        {"某城市房价连涨12个月", "info", function(e,m) e.priceIndex = e.priceIndex + 2 end, 1},
        {"某城市集中供地制度推行", "info", function(e,m) end, 3},
        {"某城市实施差别化限购", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.96 end, 2},
        {"某城市发布新一轮住房发展规划", "info", function(e,m) end, 1},
        {"某城市商业地产过剩预警", "warning", function(e,m) end, 2},
        {"某城市旅游房产热销", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"某城市写字楼空置率突破30%", "warning", function(e,m) end, 3},
        {"某城市举办大型国际博览会", "success", function(e,m) e.priceIndex = e.priceIndex + 2; e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"某城市交通枢纽项目获批", "success", function(e,m) e.priceIndex = e.priceIndex + 1.5 end, 2},
        {"某城市老旧小区改造大规模推进", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 3},
        {"某城市片区规划调整引发争议", "warning", function(e,m) end, 1},
    }
    for _, v in ipairs(regionalEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="区域", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- ======================================================================
    -- 项目性事件 (40个)
    -- ======================================================================
    local projectEvents = {
        {"工地挖出古墓，停工等待考古鉴定", "danger", function(e,m) end, 18},
        {"工地发现地下溶洞，桩基方案需调整", "warning", function(e,m) end, 6},
        {"在建项目遭遇暴雨导致基坑坍塌", "danger", function(e,m) end, 3},
        {"工地脚手架倒塌事故", "danger", function(e,m) end, 2},
        {"项目被列为优秀工程获奖", "success", function(e,m) e.priceIndex = e.priceIndex + 0.5 end, 1},
        {"精装修材料甲醛超标被曝光", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.93 end, 3},
        {"项目周边新建垃圾焚烧厂引发抗议", "danger", function(e,m) e.priceIndex = e.priceIndex - 2 end, 4},
        {"项目获绿色建筑三星认证", "success", function(e,m) e.priceIndex = e.priceIndex + 1 end, 1},
        {"项目周边发现黑臭水体", "warning", function(e,m) e.priceIndex = e.priceIndex - 1 end, 2},
        {"施工噪音扰民被周边居民投诉", "warning", function(e,m) end, 1},
        {"项目样板间获设计大奖", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 1},
        {"项目地基发现未爆弹药需排除", "danger", function(e,m) end, 4},
        {"项目交付后电梯频繁故障", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.96 end, 2},
        {"项目附近新开大型商业综合体", "success", function(e,m) e.priceIndex = e.priceIndex + 1.5 end, 2},
        {"项目周边规划高架桥引发不满", "warning", function(e,m) e.priceIndex = e.priceIndex - 1 end, 3},
        {"项目获评省级文明工地", "info", function(e,m) end, 1},
        {"项目施工中发现文物古迹", "warning", function(e,m) end, 8},
        {"项目周边建设地铁站点", "success", function(e,m) e.priceIndex = e.priceIndex + 2 end, 3},
        {"台风导致在建项目严重受损", "danger", function(e,m) end, 3},
        {"项目消防验收不合格需整改", "warning", function(e,m) end, 2},
        {"项目人防验收一次通过", "info", function(e,m) end, 1},
        {"项目交付后渗水问题大面积爆发", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.92 end, 3},
        {"项目景观园林获住户一致好评", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.04 end, 1},
        {"项目周边学校划片调整", "warning", function(e,m) e.priceIndex = e.priceIndex - 1.5 end, 2},
        {"项目被列为智能建造示范项目", "success", function(e,m) end, 1},
        {"项目验收发现结构安全问题", "danger", function(e,m) end, 6},
        {"工地突发管涌事故", "danger", function(e,m) end, 2},
        {"项目邻近公园正式开放", "success", function(e,m) e.priceIndex = e.priceIndex + 1 end, 1},
        {"项目开盘日即售罄", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 1},
        {"项目周边化工厂爆炸事故", "danger", function(e,m) e.priceIndex = e.priceIndex - 5; e.demandMultiplier = e.demandMultiplier * 0.80 end, 6},
    }
    for _, v in ipairs(projectEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="项目", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- ======================================================================
    -- 金融/货币事件 (30个)
    -- ======================================================================
    local financeEvents = {
        {"股市暴跌引发财富效应逆转", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90; m.householdLeverage = m.householdLeverage - 1 end, 3},
        {"股市大涨带来财富效应外溢", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.10 end, 2},
        {"银行收紧房贷审批标准", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 3},
        {"多银行推出购房优惠利率", "success", function(e,m) m.effectiveMortgageRate = math.max(3.0, m.effectiveMortgageRate - 0.2) end, 2},
        {"影子银行监管风暴", "warning", function(e,m) e.interestRate = e.interestRate + 0.2 end, 4},
        {"资管新规过渡期结束", "info", function(e,m) end, 2},
        {"互联网金融暴雷潮波及购房者", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.92 end, 3},
        {"信托公司暂停房地产业务", "warning", function(e,m) end, 3},
        {"ABS融资渠道全面收紧", "warning", function(e,m) end, 3},
        {"银行理财收益下降，资金转向地产", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 2},
        {"个人住房抵押贷款证券化发行", "info", function(e,m) end, 1},
        {"央行窗口指导房贷总量管控", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.88 end, 3},
        {"消费贷严禁流入楼市专项检查", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.94 end, 2},
        {"地方债务风险引发银根紧缩", "warning", function(e,m) e.interestRate = e.interestRate + 0.15 end, 3},
        {"汇率大幅贬值引发资本外流", "danger", function(e,m) m.exchangeRate = m.exchangeRate + 0.3; e.demandMultiplier = e.demandMultiplier * 0.90 end, 3},
        {"人民币大幅升值，外资涌入地产", "success", function(e,m) m.exchangeRate = m.exchangeRate - 0.2; e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"热钱涌入房地产市场", "info", function(e,m) e.priceIndex = e.priceIndex + 2; e.demandMultiplier = e.demandMultiplier * 1.08 end, 2},
        {"金融去杠杆力度加大", "warning", function(e,m) m.householdLeverage = m.householdLeverage - 1.5 end, 4},
        {"数字人民币试点促进房产交易便利化", "info", function(e,m) end, 1},
        {"全面降准释放万亿流动性", "success", function(e,m) m.m2Growth = m.m2Growth + 2; e.demandMultiplier = e.demandMultiplier * 1.10 end, 3},
        {"MLF利率下调带动LPR走低", "success", function(e,m) m.lpr5y = math.max(3.0, m.lpr5y - 0.15) end, 3},
        {"银行坏账率攀升引发惜贷", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.92 end, 3},
        {"商业银行房贷集中度管理新规", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 4},
        {"离岸人民币汇率剧烈波动", "warning", function(e,m) m.exchangeRate = m.exchangeRate + 0.2 end, 1},
        {"央行开展逆回购操作稳定流动性", "info", function(e,m) end, 1},
    }
    for _, v in ipairs(financeEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="金融", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- ======================================================================
    -- 国际/宏观事件 (30个)
    -- ======================================================================
    local internationalEvents = {
        {"全球金融危机爆发，外需骤降", "danger", function(e,m) m.gdpGrowth = m.gdpGrowth - 3; e.demandMultiplier = e.demandMultiplier * 0.75; m.exchangeRate = m.exchangeRate + 0.3 end, 6},
        {"全球疫情爆发，经济停摆", "danger", function(e,m) m.gdpGrowth = m.gdpGrowth - 4; e.demandMultiplier = e.demandMultiplier * 0.70 end, 6},
        {"东西贸易摩擦升级", "warning", function(e,m) m.gdpGrowth = m.gdpGrowth - 0.5; m.exchangeRate = m.exchangeRate + 0.15 end, 4},
        {"国际油价暴涨至每桶120美元", "warning", function(e,m) m.cpi = m.cpi + 1.5 end, 3},
        {"全球芯片短缺波及智能家居行业", "info", function(e,m) end, 3},
        {"国际大宗商品价格暴涨", "warning", function(e,m) m.cpi = m.cpi + 1.0 end, 3},
        {"西澜央行激进加息，全球流动性收紧", "warning", function(e,m) m.exchangeRate = m.exchangeRate + 0.2; e.demandMultiplier = e.demandMultiplier * 0.95 end, 4},
        {"西澜央行宣布降息50基点", "success", function(e,m) m.exchangeRate = m.exchangeRate - 0.1 end, 2},
        {"国际评级机构下调本国房企评级", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 2},
        {"本国加入重要国际贸易协定", "success", function(e,m) m.gdpGrowth = m.gdpGrowth + 0.3 end, 3},
        {"全球供应链重构，制造业回流", "info", function(e,m) m.gdpGrowth = m.gdpGrowth + 0.2 end, 4},
        {"新兴市场货币危机蔓延", "warning", function(e,m) m.exchangeRate = m.exchangeRate + 0.15 end, 3},
        {"全球碳中和目标推动绿色地产", "info", function(e,m) end, 2},
        {"国际资本大举投资本国地产", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.08 end, 3},
        {"外资撤出本国房地产市场", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.93 end, 3},
        {"海外冲突引发能源价格飙升", "warning", function(e,m) m.cpi = m.cpi + 0.8 end, 4},
        {"全球通胀见顶回落", "success", function(e,m) m.cpi = math.max(0, m.cpi - 0.5) end, 3},
        {"亚洲金融风暴再现", "danger", function(e,m) m.gdpGrowth = m.gdpGrowth - 2; m.exchangeRate = m.exchangeRate + 0.5 end, 6},
        {"本国GDP跃升为全球第二大经济体", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 2},
        {"全球科技股泡沫破裂", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.93 end, 3},
        {"国际能源价格暴跌，通胀压力减轻", "info", function(e,m) m.cpi = math.max(0, m.cpi - 0.8) end, 2},
        {"跨境电商蓬勃发展，带动仓储物流需求", "info", function(e,m) end, 2},
        {"全球利率长期低位运行", "info", function(e,m) e.interestRate = math.max(3.0, e.interestRate - 0.1) end, 3},
        {"国际游资涌入本国房地产市场", "warning", function(e,m) e.priceIndex = e.priceIndex + 3 end, 2},
        {"本国出口大幅增长带动就业", "success", function(e,m) m.gdpGrowth = m.gdpGrowth + 0.5; e.demandMultiplier = e.demandMultiplier * 1.05 end, 3},
    }
    for _, v in ipairs(internationalEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="国际", effect=v[3], duration=v[4] or 2, weight=1})
    end

    -- ======================================================================
    -- 社会/人口/自然灾害事件 (30个)
    -- ======================================================================
    local socialEvents = {
        {"人口出生率创历史新低", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 6},
        {"全面放开三孩政策", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 3},
        {"延迟退休方案正式公布", "info", function(e,m) end, 1},
        {"大城市人口调控目标公布", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 4},
        {"农民工返乡创业潮涌现", "info", function(e,m) end, 2},
        {"城镇化率突破70%", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.02 end, 2},
        {"大学毕业生人数创新高", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 1},
        {"居民收入增速跑赢房价涨幅", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.08 end, 2},
        {"居民收入增速大幅下滑", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.88 end, 3},
        {"结婚率创历史新低", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.96 end, 4},
        {"离婚购房限制政策出台", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.97 end, 2},
        {"大地震导致建筑安全标准升级", "danger", function(e,m) end, 6},
        {"特大洪灾侵袭多个城市", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.85 end, 3},
        {"极端高温天气导致施工停止", "warning", function(e,m) end, 2},
        {"强台风登陆沿海城市", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.90 end, 2},
        {"城市内涝严重，地下室车库被淹", "warning", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.95 end, 1},
        {"空气质量改善带动生态住宅需求", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.03 end, 2},
        {"养老地产需求爆发式增长", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.05 end, 3},
        {"远程办公趋势推动郊区住宅需求", "info", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.04 end, 3},
        {"地铁通车带动沿线房价上涨", "success", function(e,m) e.priceIndex = e.priceIndex + 2 end, 2},
        {"医疗资源紧张引发医养结合地产热", "info", function(e,m) end, 2},
        {"教育双减政策弱化学区房概念", "warning", function(e,m) e.priceIndex = e.priceIndex - 1 end, 3},
        {"社区团购兴起带动社区商业变革", "info", function(e,m) end, 1},
        {"新能源汽车充电桩成社区标配", "info", function(e,m) end, 1},
        {"智能家居市场爆发", "info", function(e,m) end, 1},
        {"城市群一体化规划出台", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 4},
        {"高铁新线路通车缩短城际时间", "success", function(e,m) e.priceIndex = e.priceIndex + 1 end, 2},
        {"自贸区扩容带动区域发展", "success", function(e,m) e.demandMultiplier = e.demandMultiplier * 1.06 end, 3},
        {"大型体育赛事申办成功", "success", function(e,m) e.priceIndex = e.priceIndex + 2; e.demandMultiplier = e.demandMultiplier * 1.08 end, 4},
        {"城市重大安全事故引发反思", "danger", function(e,m) e.demandMultiplier = e.demandMultiplier * 0.92 end, 2},
    }
    for _, v in ipairs(socialEvents) do
        table.insert(pool, {text=v[1], type=v[2], cat="社会", effect=v[3], duration=v[4] or 2, weight=1})
    end
end

--- 触发黑天鹅事件（替代旧的 TriggerRandomEvent）
---@param economy table GD.economy引用
---@param macro table GD.macro引用
---@param totalMonths number
---@return table|nil 触发的事件(含text/type/cat)，nil表示未触发
function ME.TriggerBlackSwan(economy, macro, totalMonths)
    ME.InitBlackSwanPool()

    -- 基础触发概率20%/月，黑天鹅额外5%
    local baseChance = 0.20
    -- 萧条/衰退期事件更频繁
    if economy.cycle == "depression" then baseChance = 0.30
    elseif economy.cycle == "recession" then baseChance = 0.25 end

    if math.random() > baseChance then return nil end

    -- 根据经济状态调权重
    local pool = ME._blackSwanPool
    local weighted = {}
    local totalWeight = 0
    for _, evt in ipairs(pool) do
        local w = evt.weight or 1
        -- 景气时正面事件概率高，萧条时负面事件概率高
        if economy.cycle == "boom" or economy.cycle == "recovery" then
            if evt.type == "success" or evt.type == "info" then w = w * 1.5 end
            if evt.type == "danger" then w = w * 0.5 end
        elseif economy.cycle == "depression" or economy.cycle == "recession" then
            if evt.type == "danger" or evt.type == "warning" then w = w * 1.5 end
            if evt.type == "success" then w = w * 0.5 end
        end
        totalWeight = totalWeight + w
        table.insert(weighted, {evt = evt, cumWeight = totalWeight})
    end

    -- 加权随机选择
    local roll = math.random() * totalWeight
    local selected = weighted[1].evt
    for _, item in ipairs(weighted) do
        if roll <= item.cumWeight then
            selected = item.evt
            break
        end
    end

    -- 执行效果
    if selected.effect then
        selected.effect(economy, macro)
    end

    return {
        text = selected.text,
        type = selected.type,
        cat = selected.cat,
        duration = selected.duration or 1,
    }
end

-- ============================================================================
-- 宏观数据摘要（供UI显示）
-- ============================================================================

--- 获取宏观指标格式化文本（用于DashboardScreen）
---@param macro table
---@param section? string  nil=核心, "gdp"=GDP结构, "housing"=房地产, "people"=人口就业, "fiscal"=财政
---@return table[]
function ME.GetMacroSummary(macro, section)
    if not section or section == "" then
        -- 核心指标(默认)
        return {
            {label = "GDP增速",     value = macro.gdpGrowth .. "%",    color = macro.gdpGrowth >= 6 and "success" or (macro.gdpGrowth >= 3 and "info" or "danger")},
            {label = "CPI",         value = macro.cpi .. "%",          color = macro.cpi > 4 and "danger" or (macro.cpi > 2.5 and "warning" or "info")},
            {label = "M2增速",      value = macro.m2Growth .. "%",     color = macro.m2Growth > 15 and "warning" or "info"},
            {label = "5Y-LPR",      value = macro.lpr5y .. "%",        color = macro.lpr5y > 5 and "warning" or "info"},
            {label = "房贷利率",    value = macro.effectiveMortgageRate .. "%", color = macro.effectiveMortgageRate > 5.5 and "danger" or "info"},
            {label = "汇率",        value = macro.exchangeRate .. "",  color = "info"},
            {label = "居民杠杆",    value = macro.householdLeverage .. "%", color = macro.householdLeverage > 55 and "danger" or (macro.householdLeverage > 40 and "warning" or "info")},
            {label = "PMI",         value = macro.pmi .. "",           color = macro.pmi >= 50 and "success" or "danger"},
            {label = "消费信心",    value = macro.consumerConfidence .. "", color = macro.consumerConfidence >= 100 and "success" or (macro.consumerConfidence >= 85 and "info" or "danger")},
        }
    elseif section == "gdp" then
        return {
            {label = "GDP总量",     value = string.format("%.0f亿", macro.gdpLevel),  color = "info"},
            {label = "人均GDP",     value = string.format("%.0f元", macro.gdpPerCapita), color = macro.gdpPerCapita > 50000 and "success" or "info"},
            {label = "固投增速",    value = macro.fixedInvestRate .. "%", color = macro.fixedInvestRate > 20 and "warning" or "info"},
            {label = "消费率",      value = macro.consumptionRate .. "%", color = macro.consumptionRate > 55 and "success" or "info"},
            {label = "出口增速",    value = macro.exportGrowth .. "%",   color = macro.exportGrowth > 10 and "success" or (macro.exportGrowth < 0 and "danger" or "info")},
            {label = "PPI",         value = macro.ppi .. "%",            color = macro.ppi > 5 and "warning" or (macro.ppi < -3 and "danger" or "info")},
            {label = "货币宽松度",  value = macro.moneyLooseness .. "",  color = macro.moneyLooseness > 30 and "warning" or (macro.moneyLooseness < -30 and "danger" or "info")},
        }
    elseif section == "housing" then
        return {
            {label = "商品房均价",  value = string.format("%.0f元/㎡", macro.avgHousePrice), color = "info"},
            {label = "房价收入比",  value = macro.housingPriceToIncome .. "", color = macro.housingPriceToIncome > 12 and "danger" or (macro.housingPriceToIncome > 8 and "warning" or "info")},
            {label = "租金回报率",  value = macro.rentalYield .. "%",    color = macro.rentalYield > 3 and "success" or (macro.rentalYield > 2 and "info" or "warning")},
            {label = "地价指数",    value = macro.landPriceIndex .. "",  color = macro.landPriceIndex > 150 and "danger" or (macro.landPriceIndex > 120 and "warning" or "info")},
            {label = "待售面积",    value = string.format("%.0f万㎡", macro.unsoldArea), color = macro.unsoldArea > 50000 and "danger" or "info"},
            {label = "地产投资",    value = string.format("%.0f亿", macro.reInvestment), color = "info"},
            {label = "居民储蓄率",  value = macro.savingsRate .. "%",    color = "info"},
        }
    elseif section == "people" then
        return {
            {label = "城镇化率",    value = macro.urbanizationRate .. "%", color = macro.urbanizationRate > 60 and "success" or "info"},
            {label = "人口增长率",  value = macro.populationGrowth .. "‰", color = macro.populationGrowth > 0 and "info" or "danger"},
            {label = "失业率",      value = macro.unemploymentRate .. "%", color = macro.unemploymentRate > 5 and "danger" or (macro.unemploymentRate > 4 and "warning" or "info")},
            {label = "工资增速",    value = macro.wageGrowth .. "%",      color = macro.wageGrowth > 8 and "success" or (macro.wageGrowth > 0 and "info" or "danger")},
            {label = "人均收入",    value = string.format("%.0f元/年", macro.avgIncome), color = "info"},
        }
    elseif section == "fiscal" then
        return {
            {label = "财政赤字率",  value = macro.fiscalDeficitRate .. "%", color = macro.fiscalDeficitRate > 3.5 and "danger" or (macro.fiscalDeficitRate > 3 and "warning" or "info")},
            {label = "政府债务/GDP", value = macro.govDebtToGdp .. "%",    color = macro.govDebtToGdp > 60 and "danger" or (macro.govDebtToGdp > 40 and "warning" or "info")},
        }
    end
    return {}
end

--- 获取所有宏观指标分区标签（供UI Tab切换使用）
function ME.GetMacroSections()
    return {
        {id = "",        label = "核心指标"},
        {id = "gdp",     label = "GDP与产出"},
        {id = "housing", label = "房地产"},
        {id = "people",  label = "人口就业"},
        {id = "fiscal",  label = "财政"},
    }
end

--- 获取政策摘要
function ME.GetPolicySummary(policy)
    local f = policy.finance
    local l = policy.land
    local t = policy.transaction
    local r = policy.regulation
    local o = policy.overall
    local trendNames = {loosening="宽松中", neutral="稳定", tightening="收紧中"}
    return {
        overall = {
            tightness = o.tightness,
            trend = trendNames[o.trend] or "稳定",
            level = o.tightness > 30 and "偏紧" or (o.tightness < -30 and "宽松" or "中性"),
        },
        finance = {
            {label = "首套首付", value = math.floor(f.downPaymentFirst * 100) .. "%"},
            {label = "二套首付", value = math.floor(f.downPaymentSecond * 100) .. "%"},
            {label = "利率上浮", value = (f.mortgageRateCap >= 1 and "+" or "") .. math.floor((f.mortgageRateCap - 1) * 100) .. "%"},
            {label = "开发贷额度", value = f.devLoanTightness == "tight" and "收紧" or (f.devLoanTightness == "loose" and "宽松" or "正常")},
        },
        land = {
            {label = "供地节奏", value = l.supplyPace > 1.2 and "加速" or (l.supplyPace < 0.8 and "放缓" or "正常")},
            {label = "出让方式", value = l.auctionMode == "bid" and "招拍挂" or "勾地"},
            {label = "配建要求", value = l.mandatoryBuild > 0 and (math.floor(l.mandatoryBuild * 100) .. "%") or "无"},
            {label = "溢价率上限", value = l.maxPremiumRate >= 999 and "不限" or (l.maxPremiumRate .. "%")},
        },
        transaction = {
            {label = "本地限购", value = t.purchaseLimitLocal >= 999 and "不限购" or (t.purchaseLimitLocal .. "套")},
            {label = "外地限购", value = t.purchaseLimitNonLocal >= 999 and "不限购" or (t.purchaseLimitNonLocal == 0 and "禁购" or (t.purchaseLimitNonLocal .. "套"))},
            {label = "限售年限", value = t.sellLockYears > 0 and (t.sellLockYears .. "年") or "无"},
            {label = "限价", value = (t.priceCeilingRatio >= 999 and t.priceFloorRatio <= 0) and "无" or "有"},
        },
        regulation = {
            {label = "预售监管", value = math.floor(r.presaleFundRatio * 100) .. "%"},
            {label = "质量监管", value = r.qualInspection == "strict" and "严格" or (r.qualInspection == "lax" and "宽松" or "正常")},
        },
    }
end

return ME
