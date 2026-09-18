-- ============================================================================
-- Personal.lua - 个人财务系统
-- 个人现金 / 工资 / 投资理财 / 资金往来
-- ============================================================================

local InvestmentService = require("personal/InvestmentService")
local PersonalFinanceEcosystem = require("PersonalFinanceEcosystem")
local PersonalLife = require("PersonalLife")

local PS = {}

PS.INHERITANCE_TAX_RATE = 0.10

-- ============================================================================
-- 投资产品配置
-- ============================================================================
PS.INVESTMENT_PRODUCTS = {
    deposit = {
        name = "银行存款", icon = "🏦",
        desc = "安全稳定，随时存取",
        annualRate = 0.012, risk = 0,
        minAmount = 0, liquidity = "随时",
        color = "Success",
    },
    moneyFund = {
        name = "货币基金", icon = "💵",
        desc = "低风险理财，收益略高于存款",
        annualRate = 0.015, risk = 0.005,
        minAmount = 100, liquidity = "T+1",
        color = "Info",
    },
    bond = {
        name = "债券基金", icon = "📜",
        desc = "中低风险，稳健收益",
        annualRate = 0.02, risk = 0.03,
        minAmount = 500, liquidity = "T+3",
        color = "Info",
    },
    indexFund = {
        name = "指数基金", icon = "📈",
        desc = "跟踪市场指数，中等风险",
        annualRate = 0.025, risk = 0.15,
        minAmount = 1000, liquidity = "T+3",
        color = "Warning",
    },
    trust = {
        name = "信托计划", icon = "🔒",
        desc = "高门槛锁定型配置，收益受3%上限约束",
        annualRate = 0.026, risk = 0.10,
        minAmount = 5000, liquidity = "锁定12月",
        color = "Danger",
    },
    stock = {
        name = "A股投资", icon = "📊",
        desc = "个股/行业ETF，跟随大盘与宏观周期波动",
        annualRate = 0.03, risk = 0.35,
        minAmount = 500, liquidity = "T+1",
        color = "Danger",
    },
    peFund = {
        name = "私募股权", icon = "🏛️",
        desc = "长期非上市股权配置，年化收益硬限制在3%以内",
        annualRate = 0.03, risk = 0.25,
        minAmount = 10000, liquidity = "锁定24月",
        color = "Danger",
    },
    reits = {
        name = "REITs基金", icon = "🏗️",
        desc = "不动产信托基金，分红稳定，跟随楼市行情",
        annualRate = 0.024, risk = 0.12,
        minAmount = 1000, liquidity = "T+3",
        color = "Warning",
    },
}
PS.PRODUCT_ORDER = {"deposit", "moneyFund", "bond", "indexFund", "trust", "stock", "peFund", "reits"}

-- ============================================================================
-- 工资限制
-- ============================================================================
PS.MAX_SALARY_RATIO = 0.05  -- 月薪上限=公司月营收的5%
PS.DEFAULT_SALARY = 0       -- 初始月薪（万元）
PS.INITIAL_PERSONAL_CASH = 3000  -- 初始个人资金（万元）

-- ============================================================================
-- 初始化
-- ============================================================================

-- ============================================================================
-- 生命周期配置
-- ============================================================================
PS.AGE_PER_YEAR = 1          -- 每现实年(游戏年)增长1岁
PS.CHILD_AGE_PER_YEAR = 1    -- 子女同步增长1岁
PS.MAX_NATURAL_AGE = 100     -- 自然寿命绝对上限（不可能超过100岁）
PS.MARRIAGE_MAX_AGE = 60     -- 结婚年龄上限
PS.CHILDBIRTH_MAX_AGE = 50   -- 生育年龄上限

--- 能力效率曲线（基于年龄段）
--- @return number efficiency 效率系数(0~1.5), number expBonus 经验加成
function PS.GetAbilityEfficiency(age)
    if age < 20 then
        return 0.5, 0
    elseif age <= 30 then
        -- 成长期：能力增长+50%
        return 1.5, 0
    elseif age <= 50 then
        -- 黄金期：100%效率
        return 1.0, 0
    elseif age <= 65 then
        -- 成熟期：90%效率 +20%经验加成
        return 0.9, 0.2
    elseif age <= 70 then
        return 0.8, 0.2
    elseif age <= 80 then
        return 0.5 + (80 - age) * 0.03, 0.15
    else
        return 0.3, 0.1
    end
end

--- 生活方式模式
PS.LIFESTYLE_MODES = {
    healthy = {
        name = "健康养生",
        icon = "🧘",
        desc = "注重健康，健康衰减-50%，社交活动减少",
        healthDecayMult = 0.5,     -- 健康衰减倍率
        abilityGrowthMult = 1.0,   -- 能力增长倍率
        socialPenalty = -0.2,      -- 社交/声望增长减少20%
    },
    workaholic = {
        name = "工作狂人",
        icon = "💼",
        desc = "拼命工作，能力增长+20%，健康衰减+50%",
        healthDecayMult = 1.5,     -- 健康衰减加速
        abilityGrowthMult = 1.2,   -- 能力增长加速
        socialPenalty = 0,
    },
    balanced = {
        name = "平衡生活",
        icon = "⚖️",
        desc = "工作与生活平衡，无额外奖惩",
        healthDecayMult = 1.0,
        abilityGrowthMult = 1.0,
        socialPenalty = 0,
    },
}

---@param capital number 公司注册资本(个人初始出资)
---@return table player
function PS.InitPlayerData(capital)
    local startAge = 18  -- 创始人固定18岁起步
    local founderGender = math.random() > 0.5 and "male" or "female"
    local founderName = PS.RandomFounderName(founderGender == "male")
    local player = {
        cash            = PS.INITIAL_PERSONAL_CASH,  -- 个人初始资金(万元)，注册公司资本从这里支出
        salary          = PS.DEFAULT_SALARY,
        companySalaries = {},       -- {[companyId] = monthlySalary}
        companySalarySettingsV1 = true,
        founderName     = founderName,  -- 创始人姓名
        founderGender   = founderGender, -- 创始人性别
        founderAge      = startAge,  -- 创始人起始年龄(固定18岁)
        founderHealth   = 100,       -- 健康度 0-100（起始满血）
        founderAlive    = true,      -- 是否存活
        founderAbility  = 50,        -- 综合能力值 0-100
        lifestyleMode   = "balanced", -- 生活方式模式: healthy/workaholic/balanced
        successorName   = nil,       -- 继承人姓名（子女继承后填入）
        generation      = 1,         -- 第几代掌门人
        honoraryChairman = nil,      -- 荣誉董事长（退休后）
        totalIncome     = 0,         -- 累计总收入
        totalDividends  = 0,         -- 累计分红收入
        totalSalary     = 0,         -- 累计工资收入
        totalInvestReturn = 0,       -- 累计投资收益
        investments     = {
            deposit   = {amount = 0},
            moneyFund = {amount = 0},
            bond      = {amount = 0},
            indexFund = {amount = 0},
            trust     = {amount = 0, lockMonths = 0},
            stock     = {amount = 0},
            peFund    = {amount = 0, lockMonths = 0},
            reits     = {amount = 0},
        },
        cityOperations = {
            invest = {},
            bond = {},
            sponsor = {},
            credit = {},
            bank = {},
            bot = {},
        },
        investmentHistory = {},      -- {year, month, type, amount, isReturn}
        netWorth        = 0,
        yearlyIncome    = 0,         -- 本年度收入(年初重置)
        yearlySalary    = 0,
        yearlyDividends = 0,
        yearlyInvestReturn = 0,
        yearlyTax        = 0,
        totalTax         = 0,
        personalTaxHistory = {},
        lastTaxSettlementYear = nil,
        -- 家族办公室（资产>1亿时解锁）
        familyOffice    = nil,       -- 初始未解锁
        -- 遗嘱系统
        will            = nil,       -- {hasWill, lawyerFee, beneficiaries, createdYear}
        family = PS.InitFamilyData(),
    }
    return player
end

-- ============================================================================
-- 向后兼容
-- ============================================================================
function PS.EnsurePlayerFields(player)
    if not player then return end
    player.cash               = player.cash or 0
    player.salary             = player.salary or 0
    player.companySalaries    = player.companySalaries or {}
    player.personalLoans      = player.personalLoans or {}
    player.inheritanceTaxDue  = player.inheritanceTaxDue or nil
    if player.inheritanceTaxDue then
        local due = player.inheritanceTaxDue
        due.total = math.max(0, tonumber(due.total) or 0)
        due.remaining = math.max(0, tonumber(due.remaining) or due.total)
        due.paid = math.max(0, tonumber(due.paid) or (due.total - due.remaining))
        due.graceMonths = math.max(1, math.floor(tonumber(due.graceMonths) or 6))
        due.elapsedMonths = math.max(0, math.floor(tonumber(due.elapsedMonths) or 0))
        due.active = due.active ~= false and due.remaining > 0
    end
    -- 创始人姓名/性别（旧存档兼容）
    if not player.founderName then
        player.founderGender = player.founderGender or "male"
        player.founderName = PS.RandomFounderName(player.founderGender == "male")
    end
    player.founderGender      = player.founderGender or "male"
    -- 新增字段向后兼容
    player.founderAbility     = player.founderAbility or 50
    player.lifestyleMode      = player.lifestyleMode or "balanced"
    player.honoraryChairman   = player.honoraryChairman  -- nil 即可
    -- familyOffice / will 允许 nil
    player.totalIncome        = player.totalIncome or 0
    player.totalDividends     = player.totalDividends or 0
    player.totalSalary        = player.totalSalary or 0
    player.totalInvestReturn  = player.totalInvestReturn or 0
    player.investments        = player.investments or {}
    -- 确保每个投资产品存在
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        if not player.investments[pid] then
            player.investments[pid] = {amount = 0}
        end
        player.investments[pid].amount = player.investments[pid].amount or 0
    end
    if player.investments.trust then
        player.investments.trust.lockMonths = player.investments.trust.lockMonths or 0
    end
    if not player.investments.stock then
        player.investments.stock = {amount = 0}
    end
    if not player.investments.peFund then
        player.investments.peFund = {amount = 0, lockMonths = 0}
    end
    player.investments.peFund.lockMonths = player.investments.peFund.lockMonths or 0
    if not player.investments.reits then
        player.investments.reits = {amount = 0}
    end
    player.investmentHistory  = player.investmentHistory or {}
    player.cityOperations = player.cityOperations or {}
    for _, operationType in ipairs({"invest", "bond", "sponsor", "credit", "bank", "bot"}) do
        player.cityOperations[operationType] = player.cityOperations[operationType] or {}
    end
    player.netWorth           = player.netWorth or 0
    player.yearlyIncome       = player.yearlyIncome or 0
    player.yearlySalary       = player.yearlySalary or 0
    player.yearlyDividends    = player.yearlyDividends or 0
    player.yearlyInvestReturn = player.yearlyInvestReturn or 0
end

-- ============================================================================
-- 月度更新
-- ============================================================================
function PS.MonthlyUpdate(GD)
    local p = GD.player
    if not p then return end

    -- 1) 工资入账
    PS._processSalary(GD)

    -- 2) 个人理财收益、锁定期与待清算赎回
    InvestmentService.MonthlyUpdate(GD)

    -- 3) 信用借条、市场报价和突发财务事件
    PersonalFinanceEcosystem.MonthlyUpdate(GD)

    -- 4) 财富身份、生活服务、课程与公益承诺
    PersonalLife.MonthlyUpdate(GD)

    -- 5) 贷款月供
    PS._processLoanRepayment(GD)

    -- 5.1) 遗产税宽限期与月度提醒/逾期兜底
    PS._processInheritanceTaxDue(GD)

    -- 5) 房产增值+租金
    PS._processPropertyUpdates(GD)

    -- 6) 生活消费维护费
    PS._processLifestyleCosts(GD)

    -- 7) 创始人衰老、健康事件、死亡判定
    PS._processFounderAging(GD)

    -- 8) 家庭开销（子女教育/培养、赡养、配偶）
    PS._processFamilyExpenses(GD)

    -- 9) 家族办公室月度结算
    PS._processFamilyOffice(GD)

    -- 10) 成就检测
    PS.CheckMilestones(GD)

    -- 11) 更新净资产
    PS.CalcNetWorth(GD)
end

-- ============================================================================
-- 年度重置
-- ============================================================================
function PS.YearlyReset(GD)
    local p = GD.player
    if not p then return end
    p.yearlyIncome       = 0
    p.yearlySalary       = 0
    p.yearlyDividends    = 0
    p.yearlyInvestReturn = 0
end

-- ============================================================================
-- 工资系统
-- ============================================================================

local function getPersonalCompanyTarget(GD, companyId)
    if not GD.GetCompanyPortfolioSummary then return nil, nil, false end
    local companies = GD.GetCompanyPortfolioSummary()
    local wantedId = companyId or GD.activeCompanyId
    for _, record in ipairs(companies or {}) do
        if tostring(record.id) == tostring(wantedId) then
            local isCurrent = GD.activeCompanyId
                and tostring(GD.activeCompanyId) == tostring(record.id)
            local company = isCurrent and GD.company
                or (record.state and record.state.company)
            return record, company, isCurrent == true
        end
    end
    return nil, nil, false
end

local function ensureCompanySalarySettings(GD)
    local p = GD.player
    if not p then return end
    p.companySalaries = p.companySalaries or {}
    if not p.companySalarySettingsV1 then
        if (p.salary or 0) > 0 and GD.activeCompanyId then
            p.companySalaries[tostring(GD.activeCompanyId)] = p.salary
        end
        p.companySalarySettingsV1 = true
    end
    local total = 0
    for _, amount in pairs(p.companySalaries) do
        total = total + math.max(0, tonumber(amount) or 0)
    end
    p.salary = total
end

function PS.GetCompanyFinanceOptions(GD)
    ensureCompanySalarySettings(GD)
    local options = {}
    if not GD.GetCompanyPortfolioSummary then return options end
    for _, record in ipairs(GD.GetCompanyPortfolioSummary() or {}) do
        if record.status == "operating" and (record.founderRatio or 0) > 0 then
            local company = GD.activeCompanyId
                and tostring(GD.activeCompanyId) == tostring(record.id)
                and GD.company
                or (record.state and record.state.company)
            options[#options + 1] = {
                id = record.id,
                name = record.name or "未命名公司",
                city = record.city or "未登记城市",
                founderRatio = record.founderRatio or 0,
                cash = company and (company.cash or 0) or (record.cash or 0),
                monthlyRevenue = company and (company.monthlyRevenue or 0) or 0,
                salary = (GD.player.companySalaries or {})[tostring(record.id)] or 0,
            }
        end
    end
    return options
end

--- 设置指定公司的个人月薪
---@param GD table
---@param amount number 月薪(万元)
---@param companyId string|nil 公司组合ID
---@return boolean ok
---@return string? reason
function PS.SetSalary(GD, amount, companyId)
    local p = GD.player
    if not p then return false, "未初始化个人数据" end
    ensureCompanySalarySettings(GD)
    local record, company = getPersonalCompanyTarget(GD, companyId)
    if not record or not company then return false, "请选择已成立的公司" end
    if (record.founderRatio or 0) <= 0.50 then
        return false, "个人持股须大于50%才能设置该公司薪酬"
    end

    amount = math.max(0, math.floor(amount))
    local maxSalary = math.floor((company.monthlyRevenue or 0) * PS.MAX_SALARY_RATIO)
    if maxSalary < 1 then maxSalary = 50 end

    if amount > maxSalary then
        return false, string.format("月薪不能超过该公司月营收5%%（上限%d万）", maxSalary)
    end

    p.companySalaries[tostring(record.id)] = amount
    ensureCompanySalarySettings(GD)
    return true
end

function PS._processSalary(GD)
    local p = GD.player
    if not p then return end
    ensureCompanySalarySettings(GD)
    if (p.salary or 0) <= 0 then return end

    local prepared = PersonalFinanceEcosystem.PrepareMonthlySalary(GD)
    local settledBaseSalary = 0
    local settledSalary = 0
    local companies = PS.GetCompanyFinanceOptions(GD)
    for _, option in ipairs(companies) do
        local baseSalary = math.max(0, option.salary or 0)
        if baseSalary > 0 and (option.founderRatio or 0) > 0.50 then
            local record, company, isCurrent = getPersonalCompanyTarget(GD, option.id)
            if record and company then
                local salary = math.floor(baseSalary * prepared.factor * 100) / 100
                if (company.cash or 0) < salary then
                    salary = math.floor((company.cash or 0) * 0.5 * 100) / 100
                end
                settledBaseSalary = settledBaseSalary + baseSalary
                if salary > 0 then
                    company.cash = (company.cash or 0) - salary
                    record.cash = company.cash
                    if isCurrent then GD.company.cash = company.cash end
                    p.cash = p.cash + salary
                    p.totalSalary = p.totalSalary + salary
                    p.totalIncome = p.totalIncome + salary
                    p.yearlyIncome = p.yearlyIncome + salary
                    p.yearlySalary = p.yearlySalary + salary
                    settledSalary = settledSalary + salary
                end
            end
        end
    end
    PersonalFinanceEcosystem.RecordSalarySettlement(GD, settledBaseSalary, settledSalary)
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
end

-- ============================================================================
-- 投资系统
-- ============================================================================

--- 买入投资产品
---@param GD table
---@param productId string
---@param amount number 投资金额(万元)
---@return boolean ok
---@return string|table result
function PS.Invest(GD, productId, amount)
    return InvestmentService.Buy(GD, productId, amount)
end

--- 赎回投资产品
---@param GD table
---@param productId string
---@param amount number 赎回金额(万元)
---@return boolean ok
---@return string|table result
function PS.Redeem(GD, productId, amount)
    return InvestmentService.Redeem(GD, productId, amount)
end

--- 计算宏观经济调整后的月化收益率
--- 每种产品的收益受不同宏观指标影响，取代固定年化率
---@param productId string
---@param macro table|nil 宏观经济指标(GD.economy.macro)
---@param cycle string|nil 当前经济周期
---@return number adjustedMonthlyRate
function PS._calcMacroAdjustedRate(productId, macro, cycle)
    local product = PS.INVESTMENT_PRODUCTS[productId]
    if not product then return 0 end
    local base = product.annualRate

    -- 无宏观数据时退回静态利率
    if not macro then return base / 12 end

    -- 经济周期乘数(影响权益类产品)
    local cycleMul = ({
        boom = 1.35, recovery = 1.12, stable = 1.0,
        slowdown = 0.82, recession = 0.55, depression = 0.25,
    })[cycle] or 1.0

    local adjusted = base -- 年化

    if productId == "deposit" then
        -- 银行存款: 跟随基准利率(约LPR×0.5)，周期影响小
        adjusted = math.max(0.005, (macro.lpr5y or 6.21) * 0.005)

    elseif productId == "moneyFund" then
        -- 货币基金: 略高于存款，宽松货币政策时收益下降
        local lprBase = (macro.lpr5y or 6.21) * 0.006
        local looseAdj = (macro.moneyLooseness or 0) * 0.00015
        adjusted = math.max(0.012, lprBase - looseAdj)

    elseif productId == "bond" then
        -- 债券: 实际利率驱动，CPI侵蚀名义收益
        local nomYield = (macro.lpr5y or 6.21) * 0.008
        local cpiDrag = (macro.cpi or 1.5) * 0.002
        adjusted = math.max(0.015, nomYield - cpiDrag + 0.02)
        -- 衰退期债券反而走强(避险)
        if cycle == "recession" or cycle == "depression" then
            adjusted = adjusted * 1.15
        end

    elseif productId == "indexFund" then
        -- 指数基金: GDP增速 + PMI景气 + 消费者信心
        local gdpAdj = math.max(0.3, (macro.gdpGrowth or 8) / 8.0)
        local pmiAdj = math.max(0.2, ((macro.pmi or 51) - 45) / 10)
        local confAdj = (macro.consumerConfidence or 105) / 105
        adjusted = base * (0.4*gdpAdj + 0.3*pmiAdj + 0.3*confAdj) * cycleMul

    elseif productId == "trust" then
        -- 信托: 跟随房地产市场(租金回报率)
        local yieldAdj = (macro.rentalYield or 4.5) / 4.5
        adjusted = base * yieldAdj * math.max(0.5, cycleMul)

    elseif productId == "stock" then
        -- A股: 强周期，PMI权重大(先行指标)，"牛短熊长"
        local gdpAdj = math.max(0.2, (macro.gdpGrowth or 8) / 8.0)
        local pmiAdj = ((macro.pmi or 51) - 45) / 8
        local confAdj = (macro.consumerConfidence or 105) / 100
        local combined = 0.25*gdpAdj + 0.45*pmiAdj + 0.30*confAdj
        adjusted = base * combined * cycleMul

    elseif productId == "peFund" then
        -- 私募股权: GDP增速 + 固定资产投资，周期敏感度中等
        local gdpAdj = math.max(0.3, (macro.gdpGrowth or 8) / 8.0)
        local investAdj = math.max(0.3, (macro.fixedInvestRate or 36) / 36)
        adjusted = base * (0.6*gdpAdj + 0.4*investAdj) * math.max(0.55, cycleMul)

    elseif productId == "reits" then
        -- REITs: 租金回报率 + 房价收入比健康度(比值越高越不健康)
        local yieldAdj = (macro.rentalYield or 4.5) / 4.5
        local priceHealth = math.max(0.4, 7.0 / math.max(1, macro.housingPriceToIncome or 6.5))
        adjusted = base * (0.6*yieldAdj + 0.4*priceHealth) * math.max(0.45, cycleMul)
    end

    return adjusted / 12 -- 转月化
end

--- 投资收益月度结算(宏观关联版)
function PS._processInvestmentReturns(GD)
    local p = GD.player
    if not p then return end

    local macro = GD.economy and GD.economy.macro or nil
    local cycle = GD.economy and GD.economy.cycle or "stable"

    local totalReturn = 0
    for pid, product in pairs(PS.INVESTMENT_PRODUCTS) do
        local inv = p.investments[pid]
        if inv and inv.amount > 0 then
            -- 宏观调整后的月化收益率
            local monthlyRate = PS._calcMacroAdjustedRate(pid, macro, cycle)
            -- 风险波动: rate * (1 ± risk×随机)
            local riskFactor = 1 + (math.random() * 2 - 1) * product.risk
            local monthReturn = math.floor(inv.amount * monthlyRate * riskFactor)
            -- 负收益保护: 单月亏损不超过持有额的2%(股票3%)
            if monthReturn < 0 then
                local maxLoss = (pid == "stock") and 0.03 or 0.02
                monthReturn = math.max(monthReturn, -math.floor(inv.amount * maxLoss))
            end
            inv.amount = inv.amount + monthReturn
            if inv.amount < 0 then inv.amount = 0 end
            totalReturn = totalReturn + monthReturn
        end
    end

    if totalReturn ~= 0 then
        p.totalInvestReturn = p.totalInvestReturn + totalReturn
        p.totalIncome = p.totalIncome + math.max(0, totalReturn)
        p.yearlyIncome = p.yearlyIncome + math.max(0, totalReturn)
        p.yearlyInvestReturn = p.yearlyInvestReturn + totalReturn
    end
end

-- ============================================================================
-- 资金往来
-- ============================================================================

--- 个人向指定公司注资
---@param GD table
---@param amount number
---@param companyId string|nil 公司组合ID
---@return boolean ok
---@return string? reason
function PS.InjectCapital(GD, amount, companyId)
    local p = GD.player
    if not p then return false, "未初始化" end
    local record, company, isCurrent = getPersonalCompanyTarget(GD, companyId)
    if not record or not company then return false, "请选择已成立的公司" end
    if (record.founderRatio or 0) < 0.999999 then
        return false, "只有个人持股100%的全资公司才能直接注资"
    end

    amount = math.floor(amount)
    if amount <= 0 then return false, "金额无效" end
    if amount > p.cash then return false, "个人现金不足" end

    p.cash = p.cash - amount
    company.cash = (company.cash or 0) + amount
    record.cash = company.cash
    if isCurrent then GD.company.cash = company.cash end
    GD.AddEvent("向" .. (record.name or "公司") .. "追加注资" .. GD.FormatMoney(amount), "success")
    if isCurrent and GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    return true
end

--- 从指定公司提取资金
---@param GD table
---@param amount number
---@param companyId string|nil 公司组合ID
---@return boolean ok
---@return string? reason
function PS.WithdrawFromCompany(GD, amount, companyId)
    local p = GD.player
    if not p then return false, "未初始化" end
    local record, company, isCurrent = getPersonalCompanyTarget(GD, companyId)
    if not record or not company then return false, "请选择已成立的公司" end
    if (record.founderRatio or 0) < 0.999999 then
        return false, "只有个人持股100%的全资公司才能提取资金"
    end

    amount = math.floor(amount)
    if amount <= 0 then return false, "金额无效" end
    if amount > (company.cash or 0) then return false, "公司现金不足" end

    company.cash = (company.cash or 0) - amount
    record.cash = company.cash
    if isCurrent then GD.company.cash = company.cash end
    p.cash = p.cash + amount
    p.totalDividends = p.totalDividends + amount
    p.totalIncome = p.totalIncome + amount
    p.yearlyIncome = p.yearlyIncome + amount
    p.yearlyDividends = p.yearlyDividends + amount
    GD.AddEvent("从" .. (record.name or "公司") .. "提取" .. GD.FormatMoney(amount), "info")
    if isCurrent and GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    return true
end

function PS.GetInheritanceTaxStatus(GD)
    local p = GD.player
    local due = p and p.inheritanceTaxDue
    if not due or due.active == false or (due.remaining or 0) <= 0 then
        return {active = false, remaining = 0, elapsedMonths = 0, graceMonths = 6, overdue = false}
    end
    local elapsed = math.max(0, math.floor(due.elapsedMonths or 0))
    local grace = math.max(1, math.floor(due.graceMonths or 6))
    return {
        active = true,
        total = due.total or due.remaining,
        remaining = due.remaining,
        paid = due.paid or 0,
        elapsedMonths = elapsed,
        graceMonths = grace,
        monthsLeft = math.max(0, grace - elapsed),
        overdue = elapsed > grace,
        finalMonth = elapsed == grace,
    }
end

function PS.PayInheritanceTax(GD)
    local p = GD.player
    local status = PS.GetInheritanceTaxStatus(GD)
    if not p or not status.active then return false, "当前没有待缴遗产税" end
    if (p.cash or 0) < status.remaining then
        return false, "个人现金不足，还需" .. GD.FormatMoney(status.remaining - (p.cash or 0))
    end
    local paid = status.remaining
    p.cash = p.cash - paid
    p.inheritanceTaxDue.paid = (p.inheritanceTaxDue.paid or 0) + paid
    p.inheritanceTaxDue.remaining = 0
    p.inheritanceTaxDue.active = false
    p.inheritanceTaxDue.paidAtMonth = GD.totalMonths or 0
    GD.AddEvent("已从个人现金缴清遗产税" .. GD.FormatMoney(paid), "success")
    return true, "遗产税已缴清"
end

function PS._processInheritanceTaxDue(GD)
    local p = GD.player
    local status = PS.GetInheritanceTaxStatus(GD)
    if not p or not status.active then return end

    local due = p.inheritanceTaxDue
    due.elapsedMonths = status.elapsedMonths + 1
    status = PS.GetInheritanceTaxStatus(GD)
    if status.elapsedMonths <= status.graceMonths then
        GD._pendingInheritanceTaxPopup = true
        if status.finalMonth then
            GD.AddEvent("遗产税缴纳期限进入最后一个月，逾期将自动办理资产抵押贷款", "danger")
        else
            GD.AddEvent("遗产税待缴" .. GD.FormatMoney(status.remaining) .. "，剩余宽限期" .. status.monthsLeft .. "个月", "warning")
        end
        return
    end

    local shortage = status.remaining
    if shortage > 0 then
        local borrowed = PS._raiseInheritanceTaxLoan(GD, shortage)
        if borrowed > 0 then
            GD.AddEvent("遗产税逾期，已自动办理资产抵押贷款并准备缴税", "danger")
        end
    end
    local afterLoan = PS.GetInheritanceTaxStatus(GD)
    if afterLoan.active and (p.cash or 0) >= afterLoan.remaining then
        PS.PayInheritanceTax(GD)
    else
        GD._pendingInheritanceTaxPopup = true
        GD.AddEvent("遗产税逾期且抵押额度不足，仍有" .. GD.FormatMoney(afterLoan.remaining) .. "待缴", "danger")
    end
end

function PS.EarlyRepayInheritanceTaxLoans(GD)
    local p = GD.player
    if not p then return false, "未初始化" end
    local total = 0
    for _, loan in ipairs(p.personalLoans or {}) do
        if loan.type == "inheritanceTaxMortgage" then
            total = total + math.max(0, loan.remaining or 0)
        end
    end
    if total <= 0 then return false, "没有遗产税资产抵押贷款" end
    if (p.cash or 0) < total then
        return false, "个人现金不足，还需" .. GD.FormatMoney(total - (p.cash or 0))
    end
    p.cash = p.cash - total
    local i = #p.personalLoans
    while i >= 1 do
        if p.personalLoans[i].type == "inheritanceTaxMortgage" then
            table.remove(p.personalLoans, i)
        end
        i = i - 1
    end
    GD.AddEvent("已提前还清全部遗产税资产抵押贷款" .. GD.FormatMoney(total), "success")
    return true, "已全部还清"
end

-- ============================================================================
-- 净资产计算
-- ============================================================================
function PS.CalcNetWorth(GD)
    local p = GD.player
    if not p then return 0 end

    local total = p.cash
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = p.investments[pid]
        if inv then
            total = total + (inv.amount or 0)
        end
    end
    for _, prop in ipairs(p.properties or {}) do
        total = total + (prop.currentValue or prop.purchasePrice or 0)
    end
    for _, item in ipairs(p.lifestyleItems or {}) do
        total = total + math.floor((item.price or 0) * 0.6)
    end
    if p.familyOffice then
        total = total + (p.familyOffice.totalAssets or 0)
    end
    for _, loan in ipairs(p.personalLoans or {}) do
        total = total - (loan.remaining or loan.amount or 0)
    end

    -- 城市研究资产属于个人而非任一公司；贷款在此单独扣除，避免与公司负债重复。
    local cityOps = p.cityOperations or {}
    for _, data in pairs(cityOps.invest or {}) do
        for _, holding in ipairs(data.holdings or {}) do
            if holding.active then total = total + (holding.amount or 0) end
        end
    end
    for _, data in pairs(cityOps.bond or {}) do
        for _, bond in ipairs(data.holdings or {}) do
            if bond.active then total = total + (bond.principal or 0) end
        end
    end
    for _, data in pairs(cityOps.credit or {}) do
        for _, deposit in ipairs(data.deposits or {}) do
            if deposit.active then total = total + (deposit.amount or 0) end
        end
        for _, fund in ipairs(data.wealthFunds or {}) do
            if fund.active then total = total + (fund.amount or 0) end
        end
        for _, loan in ipairs(data.loans or {}) do
            if loan.active then total = total - (loan.remaining or loan.amount or 0) end
        end
    end
    for _, bank in pairs(cityOps.bank or {}) do
        if (bank.step or 0) >= 6 then
            local ownership = (bank.myShares or 0) / math.max(1, bank.totalShares or 1)
            local bankNetAssets = math.max(0, (bank.bankCash or 0) + (bank.currentLoans or 0) - (bank.currentDeposits or 0))
            total = total + math.floor(bankNetAssets * ownership)
        else
            total = total + math.max(0, bank.totalInvested or 0)
        end
    end
    for _, data in pairs(cityOps.bot or {}) do
        for _, project in ipairs(data.projects or {}) do
            if project.active then
                local selfFund = project.selfFund or project.investAmount or math.floor((project.buildCost or 0) * 0.3)
                local remainingValue = math.max(0, selfFund - math.max(0, project.totalIncome or 0) + math.max(0, project.totalExpense or 0))
                total = total + remainingValue
            end
        end
    end

    -- 集团成立后，个人持有的是集团股权，不再重复计算集团下属公司股权。
    if GD.GroupSystem and GD.GroupSystem.IsActive(GD) then
        total = total + GD.GroupSystem.GetPersonalEquityValue(GD)
    elseif GD.GetCompanyPortfolioSummary then
        local companies = GD.GetCompanyPortfolioSummary()
        for _, rec in ipairs(companies or {}) do
            local company = rec.state and rec.state.company or {}
            local gov = company.governance
            local companyValue = math.max(gov and (gov.lastValuation or 0) or 0, rec.totalAssets or company.totalAssets or 0)
            local ratio = rec.founderRatio or 0
            if ratio > 0 then
                total = total + math.floor(companyValue * ratio)
            end
        end
    else
        local gov = GD.company and GD.company.governance
        if gov then
            local lastVal = gov.lastValuation or 0
            local totalAssets = GD.company.totalAssets or 0
            local companyValue = math.max(lastVal, totalAssets)
            total = total + math.floor(companyValue * (gov.founderRatio or 1.0))
        elseif GD.company then
            total = total + (GD.company.totalAssets or 0)
        end
    end

    -- 信用借贷市场中的借入负债与风险折价债权计入个人净资产。
    total = total + PersonalFinanceEcosystem.GetNetWorthAdjustment(GD)

    p.netWorth = total
    return total
end

--- 获取投资组合摘要
function PS.GetInvestmentSummary(GD)
    local summary = InvestmentService.GetSummary(GD)
    local detail = InvestmentService.GetDetail(GD)
    summary.products = detail.products or {}
    for _, product in ipairs(summary.products) do
        local legacy = PS.INVESTMENT_PRODUCTS[product.id] or {}
        product.icon = legacy.icon or "◆"
        product.rate = product.targetRate or 0.01
    end
    return summary
end

-- ============================================================================
-- 个人贷款系统
-- ============================================================================

PS.PERSONAL_LOAN_PRODUCTS = {
    mortgage = {
        name = "住房按揭贷款", icon = "🏠",
        desc = "首套房30%首付，利率优惠", rate = 4.2,
        maxMonths = 360, dpRatio = 0.3,
    },
    carLoan = {
        name = "购车贷款", icon = "🚗",
        desc = "最长5年，利率适中", rate = 5.5,
        maxMonths = 60, dpRatio = 0.2,
    },
    consumeLoan = {
        name = "消费贷款", icon = "💳",
        desc = "无抵押信用贷，利率较高", rate = 8.0,
        maxMonths = 36, dpRatio = 0,
        maxAmount = 500,
    },
}

PS.PERSONAL_CREDIT_BANKS = {
    {id = "national", name = "国有商业银行", rate = 3.0, maxMonths = 60},
    {id = "joint_stock", name = "全国股份制银行", rate = 3.6, maxMonths = 60},
    {id = "city_bank", name = "城市商业银行", rate = 4.3, maxMonths = 60},
    {id = "digital_bank", name = "数字银行", rate = 5.0, maxMonths = 60},
}

local function getPersonalCreditBank(bankId)
    for _, bank in ipairs(PS.PERSONAL_CREDIT_BANKS) do
        if bank.id == bankId then return bank end
    end
    return nil
end

function PS.GetPersonalCreditSummary(GD)
    local p = GD.player
    if not p then return {netWorth = 0, creditLimit = 0, usedCredit = 0, availableCredit = 0} end
    local netWorth = math.max(0, PS.CalcNetWorth(GD))
    local usedCredit = 0
    for _, loan in ipairs(p.personalLoans or {}) do
        if loan.type == "personalCredit" then
            usedCredit = usedCredit + math.max(0, loan.remaining or loan.amount or 0)
        end
    end
    local creditLimit = math.max(0, math.floor(netWorth * 0.70))
    return {
        netWorth = netWorth,
        creditLimit = creditLimit,
        usedCredit = usedCredit,
        availableCredit = math.max(0, creditLimit - usedCredit),
    }
end

function PS.ApplyPersonalCreditLoan(GD, bankId, amount, months)
    local p = GD.player
    if not p then return false, "未初始化" end
    local bank = getPersonalCreditBank(bankId)
    if not bank then return false, "请选择贷款银行" end
    amount = math.floor(tonumber(amount) or 0)
    months = math.floor(tonumber(months) or 0)
    if amount <= 0 then return false, "金额无效" end
    if months <= 0 or months > bank.maxMonths then
        return false, "期限须在1~" .. bank.maxMonths .. "月"
    end
    local credit = PS.GetPersonalCreditSummary(GD)
    if amount > credit.availableCredit then
        return false, "超过剩余授信额度" .. GD.FormatMoney(credit.availableCredit)
    end
    local monthlyPay = math.max(1, math.floor(amount * (bank.rate / 100 / 12 + 1 / months)))
    p.personalLoans = p.personalLoans or {}
    table.insert(p.personalLoans, {
        type = "personalCredit",
        name = bank.name .. "个人信用贷款",
        icon = "信",
        bankId = bank.id,
        bankName = bank.name,
        amount = amount,
        remaining = amount,
        rate = bank.rate,
        monthlyPay = monthlyPay,
        totalMonths = months,
        remainMonths = months,
    })
    p.cash = p.cash + amount
    GD.AddEvent("获批" .. bank.name .. "个人信用贷款" .. GD.FormatMoney(amount)
        .. "，年利率" .. string.format("%.1f%%", bank.rate), "success")
    return true
end

--- 申请个人贷款
---@param GD table
---@param loanType string  mortgage|carLoan|consumeLoan
---@param amount number 贷款金额
---@param months number 期限
---@return boolean ok
---@return string? reason
function PS.ApplyPersonalLoan(GD, loanType, amount, months)
    local p = GD.player
    if not p then return false, "未初始化" end
    local prod = PS.PERSONAL_LOAN_PRODUCTS[loanType]
    if not prod then return false, "未知贷款类型" end

    amount = math.floor(amount)
    months = math.floor(months)
    if amount <= 0 then return false, "金额无效" end
    if months <= 0 or months > prod.maxMonths then
        return false, "期限须在1~" .. prod.maxMonths .. "月"
    end
    if prod.maxAmount and amount > prod.maxAmount then
        return false, "最高可贷" .. prod.maxAmount .. "万"
    end
    -- 每月还款额不超过月收入(月薪+投资收益)的50%
    local monthlyPay = math.floor(amount * (prod.rate / 100 / 12 + 1 / months))
    local monthlyIncome = math.max(1, p.salary + math.floor(p.yearlyInvestReturn / 12))
    if monthlyPay > monthlyIncome * 0.5 and loanType ~= "consumeLoan" then
        return false, "月供超过收入50%，申请被拒"
    end

    p.personalLoans = p.personalLoans or {}
    table.insert(p.personalLoans, {
        type = loanType,
        name = prod.name,
        amount = amount,
        remaining = amount,
        rate = prod.rate,
        monthlyPay = monthlyPay,
        totalMonths = months,
        remainMonths = months,
    })
    p.cash = p.cash + amount
    GD.AddEvent("获批" .. prod.name .. GD.FormatMoney(amount) .. "，月供" .. GD.FormatMoney(monthlyPay), "info")
    return true
end

--- 提前还贷
---@param GD table
---@param idx number 贷款索引
---@return boolean ok
---@return string? reason
function PS.EarlyRepayPersonalLoan(GD, idx)
    local p = GD.player
    if not p then return false, "未初始化" end
    local loans = p.personalLoans or {}
    local loan = loans[idx]
    if not loan then return false, "无此贷款" end
    if p.cash < loan.remaining then return false, "现金不足" end
    p.cash = p.cash - loan.remaining
    table.remove(loans, idx)
    GD.AddEvent("提前还清" .. loan.name, "success")
    return true
end

--- 月度还贷
function PS._processLoanRepayment(GD)
    local p = GD.player
    if not p or not p.personalLoans then return end
    local i = 1
    while i <= #p.personalLoans do
        local loan = p.personalLoans[i]
        local pay = math.min(loan.monthlyPay, loan.remaining)
        if p.cash >= pay then
            local interestPaid = math.floor(loan.remaining * loan.rate / 100 / 12 * 100) / 100
            p.cash = p.cash - pay
            loan.remaining = loan.remaining - pay + interestPaid
            loan.remainMonths = loan.remainMonths - 1
            if loan.type == "mortgage" and interestPaid > 0 then
                if not loan.taxDeductionId then
                    p.personalLoanTaxSequence = (p.personalLoanTaxSequence or 0) + 1
                    loan.taxDeductionId = p.personalLoanTaxSequence
                end
                PersonalFinanceEcosystem.RecordTaxDeduction(
                    GD,
                    "mortgageInterest",
                    interestPaid,
                    "mortgage-interest:" .. tostring(GD.totalMonths or 0) .. ":" .. tostring(loan.taxDeductionId),
                    loan.name .. "利息"
                )
            end
            if loan.remainMonths <= 0 or loan.remaining <= 0 then
                GD.AddEvent(loan.name .. "已还清", "success")
                table.remove(p.personalLoans, i)
            else
                i = i + 1
            end
        else
            -- 逾期警告
            loan._overdue = (loan._overdue or 0) + 1
            GD.AddEvent(loan.name .. "月供不足，逾期" .. loan._overdue .. "次！", "danger")
            i = i + 1
        end
    end
end

-- ============================================================================
-- 个人房产系统
-- ============================================================================

PS.PROPERTY_CATALOG = {
    {id = "apt_small",  name = "小户型公寓",  icon = "🏢", price = 300,  rent = 2,  appreciation = 0.03},
    {id = "apt_medium", name = "三居室住宅",  icon = "🏠", price = 800,  rent = 5,  appreciation = 0.04},
    {id = "villa",      name = "独栋别墅",    icon = "🏡", price = 2000, rent = 12, appreciation = 0.05},
    {id = "shop",       name = "商铺",        icon = "🏬", price = 1500, rent = 10, appreciation = 0.03},
    {id = "penthouse",  name = "顶层豪宅",    icon = "🌆", price = 5000, rent = 25, appreciation = 0.06},
}

--- 购买房产(可贷款)
---@param GD table
---@param catalogIdx number 目录索引
---@param useMortgage boolean 是否按揭
---@return boolean ok
---@return string? reason
function PS.BuyProperty(GD, catalogIdx, useMortgage)
    local p = GD.player
    if not p then return false, "未初始化" end
    local cat = PS.PROPERTY_CATALOG[catalogIdx]
    if not cat then return false, "无此房源" end

    local price = cat.price
    p.properties = p.properties or {}

    if useMortgage then
        local downPay = math.floor(price * 0.3)
        if p.cash < downPay then return false, "首付不足(需" .. GD.FormatMoney(downPay) .. ")" end
        p.cash = p.cash - downPay
        local loanAmt = price - downPay
        -- 自动申请按揭
        p.personalLoans = p.personalLoans or {}
        local monthlyPay = math.floor(loanAmt * (4.2 / 100 / 12 + 1 / 360))
        table.insert(p.personalLoans, {
            type = "mortgage", name = cat.name .. "按揭",
            amount = loanAmt, remaining = loanAmt,
            rate = 4.2, monthlyPay = monthlyPay,
            totalMonths = 360, remainMonths = 360,
        })
        table.insert(p.properties, {
            id = cat.id, name = cat.name, icon = cat.icon,
            purchasePrice = price, currentValue = price,
            monthlyRent = cat.rent, appreciation = cat.appreciation,
            renting = false, purchaseMonth = GD.totalMonths,
        })
        GD.AddEvent("按揭购入" .. cat.name .. "，首付" .. GD.FormatMoney(downPay), "success")
        return true
    else
        if p.cash < price then return false, "现金不足" end
        p.cash = p.cash - price
        table.insert(p.properties, {
            id = cat.id, name = cat.name, icon = cat.icon,
            purchasePrice = price, currentValue = price,
            monthlyRent = cat.rent, appreciation = cat.appreciation,
            renting = false, purchaseMonth = GD.totalMonths,
        })
        GD.AddEvent("全款购入" .. cat.name, "success")
        return true
    end
end

--- 出租/停租
function PS.ToggleRent(GD, propIdx)
    local p = GD.player
    if not p then return false end
    local prop = (p.properties or {})[propIdx]
    if not prop then return false, "无此房产" end
    prop.renting = not prop.renting
    GD.AddEvent(prop.name .. (prop.renting and "已出租" or "已停租"), "info")
    return true
end

--- 卖出房产
function PS.SellProperty(GD, propIdx)
    local p = GD.player
    if not p then return false end
    local props = p.properties or {}
    local prop = props[propIdx]
    if not prop then return false, "无此房产" end
    local sellPrice = prop.currentValue
    p.cash = p.cash + sellPrice
    local profit = sellPrice - prop.purchasePrice
    GD.AddEvent("卖出" .. prop.name .. "，" .. (profit >= 0 and "赚" or "亏") .. GD.FormatMoney(math.abs(profit)), profit >= 0 and "success" or "danger")
    table.remove(props, propIdx)
    return true
end

--- 房产月度更新(增值+租金)
function PS._processPropertyUpdates(GD)
    local p = GD.player
    if not p or not p.properties then return end
    local totalRent = 0
    for _, prop in ipairs(p.properties) do
        -- 年化增值按月结算
        local monthlyApp = prop.currentValue * prop.appreciation / 12
        -- 经济周期影响
        local cycleMul = 1.0
        local ecoCycle = GD.economy and GD.economy.cycle or "stable"
        if ecoCycle == "boom" then cycleMul = 1.5
        elseif ecoCycle == "recession" then cycleMul = 0.3
        elseif ecoCycle == "depression" then cycleMul = -0.2 end
        prop.currentValue = math.max(prop.purchasePrice * 0.5, math.floor(prop.currentValue + monthlyApp * cycleMul))

        -- 租金收入
        if prop.renting then
            -- 租金随房价浮动
            local actualRent = math.floor(prop.monthlyRent * (prop.currentValue / prop.purchasePrice))
            p.cash = p.cash + actualRent
            totalRent = totalRent + actualRent
        end
    end
    if totalRent > 0 then
        p.totalIncome = p.totalIncome + totalRent
        p.yearlyIncome = p.yearlyIncome + totalRent
        p.totalRentIncome = (p.totalRentIncome or 0) + totalRent
    end
end

-- ============================================================================
-- 生活消费系统
-- ============================================================================

PS.LIFESTYLE_ITEMS = {
    {id = "economy_car",       name = "经济型轿车",      icon = "🚙", price = 30,   monthly = 1,  prestige = 5,   category = "car"},
    {id = "luxury_car",        name = "豪华轿车",        icon = "🏎️",  price = 200,  monthly = 5,  prestige = 15,  category = "car"},
    {id = "supercar",          name = "超级跑车",        icon = "🏁", price = 800,  monthly = 15, prestige = 30,  category = "car"},
    {id = "watch",             name = "名牌腕表",        icon = "⌚", price = 50,   monthly = 0,  prestige = 8,   category = "luxury"},
    {id = "art_collection",    name = "艺术品收藏",      icon = "▣",  price = 500,  monthly = 2,  prestige = 35,  category = "luxury"},
    {id = "yacht",             name = "私人游艇",        icon = "🛥️",  price = 1500, monthly = 20, prestige = 40,  category = "luxury"},
    {id = "jet",               name = "私人飞机",        icon = "✈️",  price = 5000, monthly = 50, prestige = 60,  category = "luxury"},
    {id = "travel_local",      name = "国内旅行",        icon = "🗺️",  price = 10,   monthly = 0,  prestige = 3,   category = "travel", consumable = true},
    {id = "travel_intl",       name = "国际旅行",        icon = "🌍", price = 50,   monthly = 0,  prestige = 8,   category = "travel", consumable = true},
    {id = "resort_retreat",    name = "顶级度假疗养",    icon = "▤",  price = 120,  monthly = 0,  prestige = 12,  category = "travel", consumable = true, healthBoost = 4},
    {id = "club_membership",   name = "高端会所会籍",    icon = "◈",  price = 80,   monthly = 3,  prestige = 12,  category = "social", identity = "会所会员"},
    {id = "golf_membership",   name = "私人高尔夫会籍",  icon = "◉",  price = 300,  monthly = 6,  prestige = 25,  category = "social", identity = "精英俱乐部会员"},
    {id = "business_dinner",   name = "顶级商务晚宴",    icon = "◇",  price = 80,   monthly = 0,  prestige = 12,  category = "social", consumable = true},
    {id = "industry_association", name = "行业协会理事会籍", icon = "◆", price = 120, monthly = 2, prestige = 18, category = "social", identity = "行业协会理事"},
    {id = "culture_sponsor",   name = "城市文化赞助",    icon = "▥",  price = 200,  monthly = 0,  prestige = 25,  category = "charity", consumable = true, charity = true},
    {id = "charity",           name = "慈善捐赠",        icon = "❤️",  price = 100,  monthly = 0,  prestige = 20,  category = "charity", consumable = true, charity = true},
    {id = "alma_mater_donation", name = "资助母校",      icon = "□",  price = 300,  monthly = 0,  prestige = 35,  category = "charity", consumable = true, charity = true},
    {id = "public_foundation", name = "公益基金捐赠",    icon = "▦",  price = 500,  monthly = 0,  prestige = 60,  category = "charity", consumable = true, charity = true},
    {id = "private_health",    name = "高端医疗体检",    icon = "✚",  price = 30,   monthly = 0,  prestige = 2,   category = "health", consumable = true, healthBoost = 2},
    {id = "emba",              name = "商学院EMBA",     icon = "▣",  price = 180,  monthly = 0,  prestige = 18,  category = "education", consumable = true, abilityBoost = 3},
}

PS.SOCIAL_IDENTITIES = {
    {title = "城市公益领袖", minPrestige = 300, minCharity = 5000, desc = "长期公益投入带来的顶级社会身份"},
    {title = "城市荣誉贤达", minPrestige = 240, minCharity = 1500, desc = "商业影响力与公益声望兼具"},
    {title = "慈善家", minPrestige = 120, minCharity = 500, desc = "通过持续慈善捐助获得社会认可"},
    {title = "商界名流", minPrestige = 150, minCharity = 0, desc = "高端消费与社交圈层形成公众影响力"},
    {title = "高净值名士", minPrestige = 80, minCharity = 0, desc = "在本地富豪圈拥有一定知名度"},
    {title = "城市新贵", minPrestige = 30, minCharity = 0, desc = "个人财富与生活方式开始被关注"},
    {title = "普通市民", minPrestige = 0, minCharity = 0, desc = "暂未形成稳定社会身份"},
}

function PS.GetSocialIdentity(player)
    local p = player or {}
    local prestige = p.prestige or 0
    local charity = p.totalCharity or 0
    for _, item in ipairs(PS.SOCIAL_IDENTITIES) do
        if prestige >= item.minPrestige and charity >= item.minCharity then
            return item
        end
    end
    return PS.SOCIAL_IDENTITIES[#PS.SOCIAL_IDENTITIES]
end

--- 购买生活消费品
---@param GD table
---@param itemIdx number
---@return boolean ok
---@return string? reason
function PS.BuyLifestyle(GD, itemIdx)
    local p = GD.player
    if not p then return false, "未初始化" end
    local item = PS.LIFESTYLE_ITEMS[itemIdx]
    if not item then return false, "无此物品" end
    local canAccess, accessReason = PersonalFinanceEcosystem.CanAccessLifestyleItem(GD, item)
    if not canAccess then return false, accessReason end
    p.lifestyleItems = p.lifestyleItems or {}
    if not item.consumable then
        for _, owned in ipairs(p.lifestyleItems) do
            if owned.id == item.id then
                return false, "已拥有" .. item.name
            end
        end
    end
    if p.cash < item.price then return false, "现金不足" end

    p.cash = p.cash - item.price
    p.prestige = (p.prestige or 0) + item.prestige
    p.totalSpending = (p.totalSpending or 0) + item.price
    if item.healthBoost then
        p.founderHealth = math.min(100, (p.founderHealth or 100) + item.healthBoost)
    end
    if item.abilityBoost then
        p.founderAbility = math.min(100, (p.founderAbility or 50) + item.abilityBoost)
    end
    if item.identity then
        p.socialTitles = p.socialTitles or {}
        p.socialTitles[item.identity] = true
    end
    p.socialConsumptionHistory = p.socialConsumptionHistory or {}
    table.insert(p.socialConsumptionHistory, {
        year = GD.year,
        month = GD.month,
        item = item.name,
        amount = item.price,
        prestige = item.prestige,
        category = item.category,
    })

    -- 慈善捐赠追踪（税务抵扣用）
    if item.charity or item.id == "charity" then
        p.yearlyCharity = (p.yearlyCharity or 0) + item.price
        p.totalCharity  = (p.totalCharity or 0) + item.price
        PersonalFinanceEcosystem.RecordTaxDeduction(
            GD,
            "charity",
            item.price,
            "lifestyle-charity:" .. tostring(GD.totalMonths or 0) .. ":" .. tostring(item.id),
            item.name
        )
    elseif item.category == "education" then
        PersonalFinanceEcosystem.RecordTaxDeduction(
            GD,
            "education",
            item.price,
            "lifestyle-education:" .. tostring(GD.totalMonths or 0) .. ":" .. tostring(item.id),
            item.name
        )
    elseif item.category == "health" then
        PersonalFinanceEcosystem.RecordTaxDeduction(
            GD,
            "medical",
            item.price,
            "lifestyle-medical:" .. tostring(GD.totalMonths or 0) .. ":" .. tostring(item.id),
            item.name
        )
    end

    if item.consumable then
        -- 一次性消费（旅行/慈善）
        GD.AddEvent(item.icon .. " " .. item.name .. "，声望+" .. item.prestige, "success")
    else
        table.insert(p.lifestyleItems, {
            id = item.id, name = item.name, icon = item.icon,
            price = item.price, monthly = item.monthly,
            prestige = item.prestige, category = item.category,
            purchaseMonth = GD.totalMonths,
        })
        GD.AddEvent("购入" .. item.icon .. " " .. item.name .. "，声望+" .. item.prestige, "success")
    end
    return true
end

--- 卖出持有品
function PS.SellLifestyle(GD, ownedIdx)
    local p = GD.player
    if not p then return false end
    local items = p.lifestyleItems or {}
    local item = items[ownedIdx]
    if not item then return false, "无此物品" end
    -- 二手折价60%
    local sellPrice = math.floor(item.price * 0.6)
    p.cash = p.cash + sellPrice
    p.prestige = math.max(0, (p.prestige or 0) - item.prestige)
    GD.AddEvent("卖出" .. item.name .. "，回收" .. GD.FormatMoney(sellPrice), "info")
    table.remove(items, ownedIdx)
    return true
end

--- 月度维护费结算
function PS._processLifestyleCosts(GD)
    local p = GD.player
    if not p or not p.lifestyleItems then return end
    local totalCost = 0
    for _, item in ipairs(p.lifestyleItems) do
        if item.monthly > 0 then
            totalCost = totalCost + item.monthly
        end
    end
    if totalCost > 0 then
        p.cash = p.cash - totalCost
        p.totalSpending = (p.totalSpending or 0) + totalCost
    end
end

-- ============================================================================
-- 个人税务系统
-- ============================================================================

PS.TAX_BRACKETS = {
    {threshold = 0,     rate = 0.03},
    {threshold = 36,    rate = 0.10},
    {threshold = 144,   rate = 0.20},
    {threshold = 300,   rate = 0.25},
    {threshold = 420,   rate = 0.30},
    {threshold = 660,   rate = 0.35},
    {threshold = 960,   rate = 0.45},
}

--- 计算年度个人所得税
---@param annualIncome number 年度应税收入(万元)
---@return number tax
function PS.CalcIncomeTax(annualIncome)
    if annualIncome <= 0 then return 0 end
    local tax = 0
    local remaining = annualIncome
    for i = #PS.TAX_BRACKETS, 1, -1 do
        local bracket = PS.TAX_BRACKETS[i]
        if remaining > bracket.threshold then
            tax = tax + (remaining - bracket.threshold) * bracket.rate
            remaining = bracket.threshold
        end
    end
    return math.floor(tax)
end

--- 返回指定年度合法税前扣除汇总
---@param GD table
---@param annualIncome number 年度应税收入(万元)
---@return table summary
function PS.GetPersonalTaxSummary(GD, annualIncome)
    annualIncome = math.max(0, tonumber(annualIncome) or 0)
    local advice = PersonalFinanceEcosystem.GetTaxOptimizationAdvice(GD)
    local deductions = math.min(annualIncome, math.max(0, advice.totalAcceptedDeduction or 0))
    local taxableIncome = math.max(0, annualIncome - deductions)
    local taxBeforeDeductions = PS.CalcIncomeTax(annualIncome)
    local taxDue = PS.CalcIncomeTax(taxableIncome)
    return {
        year = math.floor(tonumber(GD and GD.year) or 0),
        grossIncome = annualIncome,
        acceptedDeductions = deductions,
        taxableIncome = taxableIncome,
        taxBeforeDeductions = taxBeforeDeductions,
        taxDue = taxDue,
        taxSaved = math.max(0, taxBeforeDeductions - taxDue),
        advice = advice,
    }
end

--- 年度个人所得税汇算清缴；每年只执行一次，税款自动从个人现金扣除
---@param GD table
---@return boolean settled
---@return table|string result
function PS.YearlyTaxSettlement(GD)
    local p = GD.player
    if not p then return false, "未初始化个人数据" end
    local year = math.floor(tonumber(GD.year) or 0)
    if p.lastTaxSettlementYear == year then return false, "本年度个人所得税已结算" end

    local summary = PS.GetPersonalTaxSummary(GD, p.yearlyIncome or 0)
    local taxDue = summary.taxDue
    p.cash = (p.cash or 0) - taxDue
    p.yearlyTax = taxDue
    p.totalTax = (p.totalTax or 0) + taxDue
    p.lastTaxSettlementYear = year
    p.personalTaxHistory = p.personalTaxHistory or {}
    p.personalTaxHistory[#p.personalTaxHistory + 1] = {
        year = year,
        grossIncome = summary.grossIncome,
        acceptedDeductions = summary.acceptedDeductions,
        taxableIncome = summary.taxableIncome,
        taxDue = taxDue,
        taxSaved = summary.taxSaved,
        cashAfterTax = p.cash,
    }
    while #p.personalTaxHistory > 20 do table.remove(p.personalTaxHistory, 1) end

    PersonalFinanceEcosystem.YearlyClose(GD)
    if taxDue > 0 then
        GD.AddEvent(
            year .. "年度个人所得税已自动扣缴" .. GD.FormatMoney(taxDue)
                .. "（应纳税所得额" .. GD.FormatMoney(summary.taxableIncome) .. "）",
            "warning"
        )
    else
        GD.AddEvent(year .. "年度个人所得税汇算完成，本年无需缴税", "info")
    end
    return true, summary
end

-- ============================================================================
-- 成就与里程碑系统
-- ============================================================================

PS.MILESTONES = {
    {id = "first_salary",    name = "第一桶金",     desc = "领取第一笔工资",        icon = "💰", check = function(p) return p.totalSalary > 0 end},
    {id = "millionaire",     name = "百万富翁",     desc = "个人净资产突破100万",    icon = "💎", check = function(p) return p.netWorth >= 100 end},
    {id = "ten_million",     name = "千万身家",     desc = "个人净资产突破1000万",   icon = "🏆", check = function(p) return p.netWorth >= 1000 end},
    {id = "hundred_million", name = "亿万富豪",     desc = "个人净资产突破1亿",      icon = "👑", check = function(p) return p.netWorth >= 10000 end},
    {id = "first_property",  name = "安居乐业",     desc = "购入第一套房产",         icon = "🏠", check = function(p) return p.properties and #p.properties >= 1 end},
    {id = "property_king",   name = "房产大亨",     desc = "持有5套及以上房产",      icon = "🏘️", check = function(p) return p.properties and #p.properties >= 5 end},
    {id = "investor",        name = "投资达人",     desc = "投资总额超过1000万",     icon = "📊", check = function(p)
        local total = 0
        for _, inv in pairs(p.investments or {}) do total = total + (inv.amount or 0) end
        return total >= 1000
    end},
    {id = "prestige_50",     name = "社会名流",     desc = "声望达到50",             icon = "🌟", check = function(p) return (p.prestige or 0) >= 50 end},
    {id = "prestige_100",    name = "顶级富豪",     desc = "声望达到100",            icon = "✨", check = function(p) return (p.prestige or 0) >= 100 end},
    {id = "philanthropist",  name = "慈善家",       desc = "累计慈善捐赠超过500万",  icon = "❤️", check = function(p) return (p.totalCharity or 0) >= 500 end},
    {id = "tax_payer",       name = "纳税大户",     desc = "累计缴纳个税超过500万",  icon = "📋", check = function(p) return (p.totalTax or 0) >= 500 end},
    {id = "car_collector",   name = "车库满满",     desc = "同时持有3辆车",          icon = "🚗", check = function(p)
        local count = 0
        for _, it in ipairs(p.lifestyleItems or {}) do if it.category == "car" then count = count + 1 end end
        return count >= 3
    end},
}

--- 检查并解锁成就
function PS.CheckMilestones(GD)
    local p = GD.player
    if not p then return end
    p.unlockedMilestones = p.unlockedMilestones or {}
    for _, ms in ipairs(PS.MILESTONES) do
        if not p.unlockedMilestones[ms.id] and ms.check(p) then
            p.unlockedMilestones[ms.id] = GD.totalMonths
            GD.AddEvent(ms.icon .. " 成就解锁: " .. ms.name .. " — " .. ms.desc, "success")
        end
    end
end

-- (已合并到主 MonthlyUpdate，移除旧 override 避免双重调用)

-- 扩展年度重置
local _origYearlyReset = PS.YearlyReset
function PS.YearlyReset(GD)
    _origYearlyReset(GD)
    local p = GD.player
    if p then
        p.yearlyCharity = 0
        p.yearlyTax = 0
    end
end

-- 扩展向后兼容
local _origEnsure = PS.EnsurePlayerFields
function PS.EnsurePlayerFields(player)
    _origEnsure(player)
    if not player then return end
    player.personalLoans = player.personalLoans or {}
    player.properties = player.properties or {}
    player.lifestyleItems = player.lifestyleItems or {}
    player.prestige = player.prestige or 0
    player.totalSpending = player.totalSpending or 0
    player.totalTax = player.totalTax or 0
    player.totalCharity = player.totalCharity or 0
    player.totalRentIncome = player.totalRentIncome or 0
    player.yearlyTax = player.yearlyTax or 0
    player.personalTaxHistory = player.personalTaxHistory or {}
    player.lastTaxSettlementYear = tonumber(player.lastTaxSettlementYear) or nil
    player.yearlyCharity = player.yearlyCharity or 0
    player.socialTitles = player.socialTitles or {}
    player.socialConsumptionHistory = player.socialConsumptionHistory or {}
    player.unlockedMilestones = player.unlockedMilestones or {}
    -- 创始人年龄/健康向后兼容
    player.founderAge = player.founderAge or 30
    -- ★ 旧存档年龄钳位：不允许超过自然寿命上限
    if player.founderAge > PS.MAX_NATURAL_AGE then
        player.founderAge = PS.MAX_NATURAL_AGE
    end
    player.founderHealth = player.founderHealth or 95
    if player.founderAlive == nil then player.founderAlive = true end
    player.generation = player.generation or 1
    -- 家庭系统向后兼容
    if not player.family then
        player.family = PS.InitFamilyData()
    end
    local fam = player.family
    fam.married = fam.married or false
    fam.children = fam.children or {}
    fam.weddingCost = fam.weddingCost or 0
    fam.monthlyFamilyExpense = fam.monthlyFamilyExpense or 0
    fam.totalFamilyExpense = fam.totalFamilyExpense or 0
    fam.totalChildExpense = fam.totalChildExpense or 0
    fam.totalElderExpense = fam.totalElderExpense or 0
    if not fam.elderCare then
        fam.elderCare = {enabled = true, monthlyExpense = 1.5, parentHealth = 80}
    end
    -- ★ 旧存档配偶/子女年龄钳位
    if fam.spouse and (fam.spouse.age or 0) >= PS.MAX_NATURAL_AGE then
        -- 配偶已过自然寿命，标记去世
        fam.married = false
        fam.spouse = nil
    end
    for i = #fam.children, 1, -1 do
        local child = fam.children[i]
        child.children = child.children or {}
        if child.married == nil then child.married = child.spouse ~= nil end
        if (child.age or 0) > PS.MAX_NATURAL_AGE then
            child.age = PS.MAX_NATURAL_AGE
        end
    end
    InvestmentService.Ensure(player)
    PersonalFinanceEcosystem.Ensure(player)
    PersonalLife.Ensure(player)
end

-- ============================================================================
-- 投资组合多元化评分
-- ============================================================================

--- 风险等级分类
local RISK_TIERS = {
    low    = {"deposit", "moneyFund"},           -- 低风险
    medium = {"bond", "reits"},                  -- 中风险
    high   = {"indexFund", "trust", "stock", "peFund"},  -- 高风险
}

--- 计算投资组合多元化评分(0~100)
--- 评估维度: 品种分散度(40%) + 风险层级均衡(35%) + 集中度惩罚(25%)
---@param GD table
---@return table {score, level, tierWeights, concentration, suggestions}
function PS.CalcPortfolioDiversification(GD)
    local p = GD.player
    local result = {
        score = 0, level = "无持仓",
        tierWeights = {low = 0, medium = 0, high = 0},
        concentration = 0,       -- 最大单品占比
        topProduct = "",         -- 占比最大的产品
        suggestions = {},
    }
    if not p then return result end

    -- 1. 统计总持仓和各品种金额
    local totalAmount = 0
    local amounts = {}
    local activeCount = 0
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = p.investments[pid]
        local amt = inv and inv.amount or 0
        amounts[pid] = amt
        totalAmount = totalAmount + amt
        if amt > 0 then activeCount = activeCount + 1 end
    end
    if totalAmount <= 0 then return result end

    -- 2. 品种分散度(0~40分): 持有品种越多越好
    local maxProducts = #PS.PRODUCT_ORDER
    local diversityScore = math.min(40, math.floor(activeCount / maxProducts * 40))

    -- 3. 风险层级均衡(0~35分): low/medium/high各占~33%最佳
    local tierTotals = {low = 0, medium = 0, high = 0}
    for tier, products in pairs(RISK_TIERS) do
        for _, pid in ipairs(products) do
            tierTotals[tier] = tierTotals[tier] + (amounts[pid] or 0)
        end
    end
    local tierWeights = {}
    for tier, total in pairs(tierTotals) do
        tierWeights[tier] = total / totalAmount
    end
    result.tierWeights = tierWeights
    -- 理想分布为各1/3，偏离越大扣分越多
    local idealWeight = 1 / 3
    local tierDeviation = 0
    for _, w in pairs(tierWeights) do
        tierDeviation = tierDeviation + math.abs(w - idealWeight)
    end
    -- tierDeviation 范围 0~1.33，归一化到 0~35
    local balanceScore = math.max(0, math.floor(35 * (1 - tierDeviation / 1.33)))

    -- 4. 集中度惩罚(0~25分): 单品占比>60%扣分
    local maxRatio = 0
    local topPid = ""
    for pid, amt in pairs(amounts) do
        local ratio = amt / totalAmount
        if ratio > maxRatio then
            maxRatio = ratio
            topPid = pid
        end
    end
    result.concentration = math.floor(maxRatio * 100)
    result.topProduct = topPid
    local concScore = 25
    if maxRatio > 0.8 then concScore = 0
    elseif maxRatio > 0.6 then concScore = 10
    elseif maxRatio > 0.4 then concScore = 18
    end

    -- 5. 总分与建议
    result.score = diversityScore + balanceScore + concScore
    if result.score >= 80 then result.level = "优秀"
    elseif result.score >= 60 then result.level = "良好"
    elseif result.score >= 40 then result.level = "一般"
    else result.level = "偏弱" end

    -- 生成建议
    if activeCount <= 2 then
        table.insert(result.suggestions, "持有品种过少，建议分散到3种以上产品")
    end
    if tierWeights.low > 0.7 then
        table.insert(result.suggestions, "低风险配置过高，收益有限，可适当配置权益类")
    end
    if tierWeights.high > 0.7 then
        table.insert(result.suggestions, "高风险配置过高，建议增加债券/存款稳住底仓")
    end
    if tierWeights.medium < 0.05 and totalAmount > 500 then
        table.insert(result.suggestions, "缺少中风险品种(债券/REITs)，建议补充")
    end
    if maxRatio > 0.6 then
        local prodName = PS.INVESTMENT_PRODUCTS[topPid] and PS.INVESTMENT_PRODUCTS[topPid].name or topPid
        table.insert(result.suggestions, prodName .. "占比" .. result.concentration .. "%过高，建议分散")
    end

    return result
end

--- 获取增强版投资摘要(含宏观参考利率+多元化评分)
function PS.GetInvestmentDetail(GD)
    local p = GD.player
    if not p then return {total = 0, products = {}, diversification = {}} end

    local macro = GD.economy and GD.economy.macro or nil
    local cycle = GD.economy and GD.economy.cycle or "stable"

    local total = 0
    local products = {}
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = p.investments[pid]
        local amt = inv and inv.amount or 0
        total = total + amt
        local adjustedMonthly = PS._calcMacroAdjustedRate(pid, macro, cycle)
        local adjustedAnnual = adjustedMonthly * 12
        local prod = PS.INVESTMENT_PRODUCTS[pid]
        local lockInfo = nil
        if pid == "trust" and inv.lockMonths and inv.lockMonths > 0 then
            lockInfo = inv.lockMonths
        elseif pid == "peFund" and inv.lockMonths and inv.lockMonths > 0 then
            lockInfo = inv.lockMonths
        end
        table.insert(products, {
            id = pid,
            name = prod.name,
            icon = prod.icon,
            amount = amt,
            baseRate = prod.annualRate,          -- 基准年化
            adjustedRate = adjustedAnnual,       -- 宏观调整后年化
            rateChange = adjustedAnnual - prod.annualRate, -- 变化
            risk = prod.risk,
            lockMonths = lockInfo,
            liquidity = prod.liquidity,
            color = prod.color,
        })
    end

    return {
        total = total,
        products = products,
        diversification = PS.CalcPortfolioDiversification(GD),
        yearlyReturn = p.yearlyInvestReturn or 0,
        totalReturn = p.totalInvestReturn or 0,
    }
end

-- ============================================================================
-- 家庭系统（婚姻、子女、赡养父母、家庭开销）
-- ============================================================================

-- 教育阶段配置: {名称, 起始年龄, 结束年龄, 月费(万)}
PS.EDUCATION_STAGES = {
    {name = "学龄前",   minAge = 0,  maxAge = 5,  monthlyCost = 0.3},
    {name = "基础教育", minAge = 6,  maxAge = 14, monthlyCost = 0.8},
    {name = "高中",     minAge = 15, maxAge = 17, monthlyCost = 1.5},
    {name = "大学",     minAge = 18, maxAge = 21, monthlyCost = 2.5},
    {name = "已成年",   minAge = 22, maxAge = 999, monthlyCost = 0},
}

--- 高等教育层级（成年后可选择深造）
PS.ADVANCED_EDUCATION = {
    basic     = {name = "基础教育",  cost = 0,     abilityBonus = 0,  duration = 0},
    college   = {name = "高等教育",  cost = 5,     abilityBonus = 5,  duration = 4},   -- 5万/月，4年
    mba       = {name = "商学院MBA", cost = 15,    abilityBonus = 15, duration = 2},   -- 15万/月，2年
    overseas  = {name = "海外留学",  cost = 30,    abilityBonus = 25, duration = 3},   -- 30万/月，3年
}

--- 子女培养项目
PS.CHILD_TRAINING = {
    tutor = {
        name = "私人导师",
        icon = "👨‍🏫",
        desc = "单项能力提升，每月0.5万",
        monthlyCost = 0.5,
        abilityGain = 2,       -- 每年+2能力
        category = "single",   -- 单项能力
    },
    training = {
        name = "综合培训班",
        icon = "📚",
        desc = "综合素质提升，每期2万(6个月)",
        monthlyCost = 0.33,    -- 2万/6月
        abilityGain = 3,       -- 每年+3能力（综合）
        category = "comprehensive",
    },
    internship = {
        name = "企业实习",
        icon = "🏢",
        desc = "在自家或合作企业实习，无费用但需年满16",
        monthlyCost = 0,
        abilityGain = 4,       -- 实战+4能力/年
        category = "practical",
        minAge = 16,
    },
    startup = {
        name = "创业资助",
        icon = "🚀",
        desc = "资助子女创业，10万起步，成功率受能力影响",
        startupCost = 10,      -- 一次性10万
        abilityGain = 5,       -- 成功后+5
        category = "startup",
        minAge = 18,
    },
}

--- 获取子女当前教育阶段
function PS.GetEducationStage(childAge)
    for _, stage in ipairs(PS.EDUCATION_STAGES) do
        if childAge >= stage.minAge and childAge <= stage.maxAge then
            return stage
        end
    end
    return PS.EDUCATION_STAGES[#PS.EDUCATION_STAGES]
end

--- 初始化家庭数据
function PS.InitFamilyData()
    return {
        married = false,
        spouse = nil,           -- {name, age, gender, job, monthlyIncome, personality, appearance, ability}
        weddingCost = 0,        -- 累计婚礼花费
        children = {},          -- {{name, age, gender, ability, training, education, ...}}
        elderCare = {
            enabled = true,     -- 默认赡养父母
            monthlyExpense = 1.5, -- 万/月
            parentHealth = 80,  -- 父母健康度 0-100
        },
        -- 传承相关
        successionMode = nil,   -- "gradual"(渐进10%税) / "onetime"(一次性20%税) / nil(未设置)
        gradualTransferPct = 0, -- 渐进转移已完成比例(0~100)
        monthlyFamilyExpense = 0,
        totalFamilyExpense = 0,
        totalChildExpense = 0,
        totalElderExpense = 0,
        totalTrainingExpense = 0,
    }
end

-- 配偶职业模板
PS.SPOUSE_JOBS = {
    {job = "教师",       income = 1.2},
    {job = "医生",       income = 2.0},
    {job = "工程师",     income = 1.8},
    {job = "公务员",     income = 1.5},
    {job = "会计师",     income = 1.6},
    {job = "律师",       income = 2.5},
    {job = "设计师",     income = 1.4},
    {job = "自由职业",   income = 1.0},
    {job = "全职太太/先生", income = 0},
}

-- 姓名池
local SURNAMES = {"李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴", "徐", "孙", "胡", "朱", "高"}
local GIVEN_M = {"伟", "强", "磊", "明", "辉", "鹏", "杰", "涛", "浩", "宇"}
local GIVEN_F = {"芳", "娜", "敏", "静", "婷", "雪", "慧", "丽", "莹", "琳"}
local CHILD_M = {"子轩", "浩宇", "梓睿", "一诺", "宇辰", "奕辰", "思远", "明泽"}
local CHILD_F = {"若汐", "一诺", "艺涵", "梓涵", "诗涵", "欣妍", "思语", "雨桐"}

local function randomName(isMale)
    local s = SURNAMES[math.random(#SURNAMES)]
    if isMale then return s .. GIVEN_M[math.random(#GIVEN_M)]
    else return s .. GIVEN_F[math.random(#GIVEN_F)] end
end

--- 公开版本，供InitPlayerData调用
function PS.RandomFounderName(isMale)
    return randomName(isMale)
end

function PS.RandomFamilyMemberName(isMale)
    return randomName(isMale)
end

local function randomChildName(isMale)
    local s = SURNAMES[math.random(#SURNAMES)]
    if isMale then return s .. CHILD_M[math.random(#CHILD_M)]
    else return s .. CHILD_F[math.random(#CHILD_F)] end
end

local function ensureChildFamilyFields(child)
    child.children = child.children or {}
    if child.married == nil then child.married = child.spouse ~= nil end
    child.familyStartedYear = child.familyStartedYear or nil
    child.lastChildbirthYear = child.lastChildbirthYear or nil
end

local function normalizeGender(gender)
    if gender == "男" or gender == "male" or gender == "m" then return "male" end
    if gender == "女" or gender == "female" or gender == "f" then return "female" end
    return nil
end

local function applyIdentity(target, name, gender)
    if not target then return false, "未找到对象" end
    local newName = tostring(name or "")
    newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    if newName ~= "" then target.name = newName end
    local g = normalizeGender(gender)
    if g then target.gender = g end
    if newName == "" and not g then return false, "请输入姓名或选择性别" end
    return true
end

function PS.UpdateFounderIdentity(GD, name, gender)
    local p = GD.player
    if not p then return false, "个人数据未初始化" end
    local newName = tostring(name or "")
    newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    if newName ~= "" then
        p.founderName = newName
        p.successorName = newName
        if GD.company and GD.company.governance and GD.company.governance.shareholders then
            for _, sh in ipairs(GD.company.governance.shareholders) do
                if sh.id == "founder" then sh.name = newName end
            end
        end
    end
    local g = normalizeGender(gender)
    if g then p.founderGender = g end
    if newName == "" and not g then return false, "请输入姓名或选择性别" end
    GD.AddEvent("掌门人身份信息已更新", "success")
    return true
end

function PS.UpdateSpouseIdentity(GD, name, gender)
    local fam = GD.player and GD.player.family
    if not fam or not fam.spouse then return false, "当前没有配偶" end
    local ok, msg = applyIdentity(fam.spouse, name, gender)
    if ok then GD.AddEvent("配偶身份信息已更新", "success") end
    return ok, msg
end

function PS.UpdateChildIdentity(GD, childIdx, name, gender)
    local fam = GD.player and GD.player.family
    local child = fam and fam.children and fam.children[childIdx]
    local ok, msg = applyIdentity(child, name, gender)
    if ok then GD.AddEvent("子女身份信息已更新", "success") end
    return ok, msg
end

function PS.UpdateChildSpouseIdentity(GD, childIdx, name, gender)
    local fam = GD.player and GD.player.family
    local child = fam and fam.children and fam.children[childIdx]
    if not child or not child.spouse then return false, "该子女没有配偶" end
    local ok, msg = applyIdentity(child.spouse, name, gender)
    if ok then GD.AddEvent("子女配偶身份信息已更新", "success") end
    return ok, msg
end

function PS.UpdateGrandchildIdentity(GD, childIdx, grandIdx, name, gender)
    local fam = GD.player and GD.player.family
    local child = fam and fam.children and fam.children[childIdx]
    local grandchild = child and child.children and child.children[grandIdx]
    local ok, msg = applyIdentity(grandchild, name, gender)
    if ok then GD.AddEvent("第三代身份信息已更新", "success") end
    return ok, msg
end

local function tryAutoChildMarriage(GD, child)
    ensureChildFamilyFields(child)
    if child.married or (child.age or 0) < 18 then return end
    if child.marriageCheckedYear == GD.year then return end
    child.marriageCheckedYear = GD.year

    local age = child.age or 18
    local chance = 0.10
    if age >= 22 then chance = 0.25 end
    if age >= 28 then chance = 0.38 end
    if age >= 35 then chance = 0.22 end
    if age > 45 then chance = 0.08 end

    if math.random() < chance then
        local spouseGender = child.gender == "male" and "female" or "male"
        local job = PS.SPOUSE_JOBS[math.random(#PS.SPOUSE_JOBS)]
        child.married = true
        child.spouse = {
            name = PS.RandomFamilyMemberName(spouseGender == "male"),
            age = math.max(18, age + math.random(-3, 4)),
            gender = spouseGender,
            job = job.job,
            monthlyIncome = job.income,
        }
        child.familyStartedYear = GD.year
        GD.AddEvent("子女" .. (child.name or "") .. "已成年并组建家庭，配偶" .. child.spouse.name, "success")
    end
end

local function tryAutoGrandchildBirth(GD, child)
    ensureChildFamilyFields(child)
    if not child.married or not child.spouse then return end
    if (child.age or 0) < 18 or (child.age or 0) > 45 then return end
    if #child.children >= 2 then return end
    if child.lastChildbirthYear and GD.year - child.lastChildbirthYear < 2 then return end
    if child.childbirthCheckedYear == GD.year then return end
    child.childbirthCheckedYear = GD.year

    local chance = #child.children == 0 and 0.30 or 0.16
    if (child.age or 0) >= 35 then chance = chance * 0.55 end
    if math.random() < chance then
        local isMale = math.random() > 0.5
        local baby = {
            name = randomChildName(isMale),
            age = 0,
            gender = isMale and "male" or "female",
            ability = math.max(20, math.min(80, math.floor(((child.ability or 40) + math.random(20, 60)) / 2))),
            training = nil,
            education = nil,
            grandchild = true,
        }
        table.insert(child.children, baby)
        child.lastChildbirthYear = GD.year
        GD.AddEvent("子女" .. (child.name or "") .. "喜得" .. (isMale and "一子" or "一女") .. "，家族第三代诞生", "success")
    end
end

function PS.ProcessAdultChildrenFamily(GD)
    local p = GD.player
    local fam = p and p.family
    if not fam then return end
    for _, child in ipairs(fam.children or {}) do
        ensureChildFamilyFields(child)
        if GD.month == 1 then
            if child.spouse then
                child.spouse.age = (child.spouse.age or math.max(18, (child.age or 18))) + PS.AGE_PER_YEAR
            end
            for _, grandchild in ipairs(child.children or {}) do
                grandchild.age = (grandchild.age or 0) + PS.CHILD_AGE_PER_YEAR
                grandchild.ability = math.min(80, (grandchild.ability or 30) + 1)
            end
            tryAutoChildMarriage(GD, child)
            tryAutoGrandchildBirth(GD, child)
        end
    end
end

-- ============================================================================
-- 相亲系统（BlindDate）
-- ============================================================================

--- 相亲介绍费配置
PS.BLIND_DATE_COST = 10  -- 每次相亲花费10万（交友/中介费）

--- 相亲性格特征池
PS.PERSONALITY_TRAITS = {
    "温柔体贴", "活泼开朗", "知性优雅", "独立自主", "勤俭持家",
    "浪漫多情", "沉稳内敛", "幽默风趣", "精明能干", "善良大方",
}

--- 相亲外貌描述池
PS.APPEARANCE_DESCS = {
    "容貌出众", "气质不凡", "清秀端庄", "阳光帅气", "英俊潇洒",
    "甜美可人", "干练知性", "温文尔雅", "眉清目秀", "风度翩翩",
}

--- 发起相亲（生成3个候选人）
---@return boolean, string
function PS.BlindDate(GD)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    if p.family.married then return false, "已经结婚了，不能相亲" end
    if (p.founderAge or 0) > PS.MARRIAGE_MAX_AGE then
        return false, "年龄超过" .. PS.MARRIAGE_MAX_AGE .. "岁，已过适婚年龄"
    end

    if p.cash < PS.BLIND_DATE_COST then
        return false, "现金不足，相亲费用" .. GD.FormatMoney(PS.BLIND_DATE_COST)
    end

    p.cash = p.cash - PS.BLIND_DATE_COST

    -- 生成3个候选人
    local candidates = {}
    local usedNames = {}
    for i = 1, 3 do
        local spouseJob = PS.SPOUSE_JOBS[math.random(#PS.SPOUSE_JOBS)]
        -- 候选人性别与创始人相反
        local founderIsMale = (p.founderGender or "male") == "male"
        local candidateGender = founderIsMale and "female" or "male"
        local candidateName
        repeat
            candidateName = randomName(candidateGender == "male")
        until not usedNames[candidateName]
        usedNames[candidateName] = true

        local candidateAge = math.max(22, (p.founderAge or 30) + math.random(-8, 5))
        local personality = PS.PERSONALITY_TRAITS[math.random(#PS.PERSONALITY_TRAITS)]
        local appearance = PS.APPEARANCE_DESCS[math.random(#PS.APPEARANCE_DESCS)]
        -- 家庭背景随机
        local familyBg = math.random(1, 5)  -- 1~5星
        -- 好感度随机
        local chemistry = math.random(50, 100)

        table.insert(candidates, {
            name = candidateName,
            age = candidateAge,
            gender = candidateGender,
            job = spouseJob.job,
            monthlyIncome = spouseJob.income,
            personality = personality,
            appearance = appearance,
            familyBackground = familyBg,
            chemistry = chemistry,
        })
    end

    p.family.datingCandidates = candidates
    GD.AddEvent("参加相亲活动，花费" .. GD.FormatMoney(PS.BLIND_DATE_COST) .. "，认识了3位候选人", "info")
    return true, "相亲成功，请选择心仪对象"
end

--- 选择相亲对象并结婚
---@param candidateIdx number 候选人索引(1~3)
---@return boolean, string
function PS.MarryCandidate(GD, candidateIdx)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    if p.family.married then return false, "已经结婚了" end
    if not p.family.datingCandidates or #p.family.datingCandidates == 0 then
        return false, "没有相亲候选人，请先相亲"
    end

    local candidate = p.family.datingCandidates[candidateIdx]
    if not candidate then return false, "无效的候选人" end

    -- 婚礼费用（根据身价浮动 50~200万）
    local netWorth = PS.CalcNetWorth(GD)
    local weddingCost = math.max(50, math.min(200, math.floor(netWorth * 0.03)))
    if p.cash < weddingCost then
        return false, "现金不足，婚礼预算至少" .. GD.FormatMoney(weddingCost)
    end

    p.cash = p.cash - weddingCost

    p.family.married = true
    p.family.spouse = {
        name = candidate.name,
        age = candidate.age,
        gender = candidate.gender,
        job = candidate.job,
        monthlyIncome = candidate.monthlyIncome,
        personality = candidate.personality,
        appearance = candidate.appearance,
    }
    p.family.weddingCost = weddingCost
    p.family.datingCandidates = nil  -- 清除候选人
    p.prestige = (p.prestige or 0) + 10

    GD.AddEvent("恭喜结婚！配偶" .. candidate.name .. "（" .. candidate.job .. "），婚礼花费" .. GD.FormatMoney(weddingCost), "success")
    return true, "新婚快乐！"
end

--- 结婚（保留直接结婚功能，不经过相亲）
---@return boolean, string
function PS.Marry(GD)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    if p.family.married then return false, "已经结婚了" end
    if (p.founderAge or 0) > PS.MARRIAGE_MAX_AGE then
        return false, "年龄超过" .. PS.MARRIAGE_MAX_AGE .. "岁，已过适婚年龄"
    end

    -- 婚礼费用 (50~200万，根据身价浮动)
    local netWorth = PS.CalcNetWorth(GD)
    local weddingCost = math.max(50, math.min(200, math.floor(netWorth * 0.03)))
    if p.cash < weddingCost then
        return false, "现金不足，婚礼预算至少" .. GD.FormatMoney(weddingCost)
    end

    p.cash = p.cash - weddingCost

    -- 随机配偶
    local spouseJob = PS.SPOUSE_JOBS[math.random(#PS.SPOUSE_JOBS)]
    local spouseGender = math.random() > 0.5 and "female" or "male"
    local spouseName = randomName(spouseGender == "male")
    local spouseAge = 25 + math.random(10)

    p.family.married = true
    p.family.spouse = {
        name = spouseName,
        age = spouseAge,
        gender = spouseGender,
        job = spouseJob.job,
        monthlyIncome = spouseJob.income,
    }
    p.family.weddingCost = weddingCost
    p.family.datingCandidates = nil  -- 清除候选人
    p.prestige = (p.prestige or 0) + 10

    GD.AddEvent("恭喜结婚！配偶" .. spouseName .. "（" .. spouseJob.job .. "），婚礼花费" .. GD.FormatMoney(weddingCost), "success")
    return true, "新婚快乐！"
end

--- 离婚
function PS.Divorce(GD)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    if not p.family.married then return false, "未婚状态" end

    -- 离婚法律费用
    local legalFee = 30
    local assetSplit = math.floor(p.cash * 0.3)  -- 分割30%现金
    local totalCost = legalFee + assetSplit

    if p.cash < totalCost then
        return false, "现金不足以支付离婚费用（律师费" .. GD.FormatMoney(legalFee) .. " + 财产分割" .. GD.FormatMoney(assetSplit) .. "）"
    end

    local spouseName = p.family.spouse and p.family.spouse.name or "配偶"
    p.cash = p.cash - totalCost
    p.family.married = false
    p.family.spouse = nil
    p.prestige = math.max(0, (p.prestige or 0) - 5)

    GD.AddEvent("与" .. spouseName .. "离婚，律师费" .. GD.FormatMoney(legalFee) .. "，财产分割" .. GD.FormatMoney(assetSplit), "warning")
    return true, "离婚手续已完成"
end

--- 生育子女
function PS.HaveChild(GD)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    if not p.family.married then return false, "需要先结婚" end
    if #p.family.children >= 3 then return false, "最多3个子女" end
    if (p.founderAge or 0) > PS.CHILDBIRTH_MAX_AGE then
        return false, "年龄超过" .. PS.CHILDBIRTH_MAX_AGE .. "岁，已过最佳生育年龄"
    end

    local gender = math.random() > 0.5 and "male" or "female"
    local childName = randomChildName(gender == "male")
    local genderText = gender == "male" and "男" or "女"

    -- 子女初始能力 = (父母平均能力 × 0.5 + 随机15~35)
    local parentAbility = p.founderAbility or 50
    local spouseAbility = (p.family.spouse and p.family.spouse.ability) or 50
    local baseAbility = math.floor((parentAbility + spouseAbility) * 0.5 * 0.5 + math.random(15, 35))
    baseAbility = math.max(20, math.min(70, baseAbility))

    table.insert(p.family.children, {
        name = childName,
        age = 0,
        gender = gender,
        birthYear = GD.year,
        birthMonth = GD.month,
        ability = baseAbility,
        training = nil,
    })

    p.prestige = (p.prestige or 0) + 5
    GD.AddEvent("喜得" .. (gender == "male" and "贵子" or "千金") .. "！" .. childName .. "（" .. genderText .. "，天赋" .. baseAbility .. "）出生", "success")
    return true, childName .. "出生了！"
end

--- 收养子女（无需婚姻，可在继承人危机时使用）
--- @param GD table 游戏数据
--- @param asHeir boolean? 是否作为继承人直接接班（创始人已去世时）
--- @return boolean, string
function PS.AdoptChild(GD, asHeir)
    local p = GD.player
    if not p or not p.family then return false, "数据未初始化" end
    local fam = p.family

    if not asHeir and #fam.children >= 3 then
        return false, "最多3个子女"
    end

    local gender = math.random() > 0.5 and "male" or "female"
    local childName = randomChildName(gender == "male")
    local genderText = gender == "male" and "男" or "女"

    if asHeir then
        -- 作为继承人直接接班：年龄22-28岁的成年人
        local heirAge = 22 + math.random(0, 6)
        local heirAbility = math.random(35, 60)  -- 紧急收养继承人能力中等
        table.insert(fam.children, {
            name = childName,
            age = heirAge,
            gender = gender,
            birthYear = (GD.year or 2024) - heirAge,
            birthMonth = math.random(1, 12),
            adopted = true,
            ability = heirAbility,
        })

        -- 执行继承
        local deceasedName = GD.company.noHeirDeceasedName or p.founderName or "创始人"
        p.successorName = childName
        p.generation = (p.generation or 1) + 1
        p.founderAlive = true
        p.founderAge = heirAge
        p.founderHealth = 80 + math.random(0, 15)
        p.founderAbility = heirAbility
        p.founderName = childName
        p.lifestyleMode = "balanced"
        fam.married = false
        fam.spouse = nil

        -- 收养继承的子女从列表移除（已成为掌门人）
        local newChildren = {}
        for _, child in ipairs(fam.children or {}) do
            if child.name ~= childName then
                table.insert(newChildren, child)
            end
        end
        fam.children = newChildren

        GD.AddEvent(deceasedName .. "不幸离世，收养继承人 " .. childName .. " 接管公司", "warning")
        GD.AddEvent("第" .. p.generation .. "代继承人 " .. childName .. "（" .. heirAge .. "岁，" .. genderText .. "）正式执掌公司", "success")

        return true, childName .. "已收养并继承公司！"
    else
        -- 普通收养：年龄0-5岁的幼儿
        local adoptAge = math.random(0, 5)
        local adoptAbility = math.random(20, 45)  -- 收养子女随机基础能力
        table.insert(fam.children, {
            name = childName,
            age = adoptAge,
            gender = gender,
            birthYear = (GD.year or 2024) - adoptAge,
            birthMonth = math.random(1, 12),
            adopted = true,
            ability = adoptAbility,
            training = nil,
        })
        p.prestige = (p.prestige or 0) + 3
        local ageText = adoptAge == 0 and "婴儿" or (adoptAge .. "岁")
        GD.AddEvent("收养了" .. (gender == "male" and "一位男孩" or "一位女孩") .. " " .. childName .. "（" .. ageText .. "，天赋" .. adoptAbility .. "）", "success")
        return true, "成功收养 " .. childName .. "！"
    end
end

--- 调整赡养费
function PS.SetElderCare(GD, monthlyAmount)
    local p = GD.player
    if not p or not p.family then return false end
    monthlyAmount = math.max(0, math.min(10, monthlyAmount))
    p.family.elderCare.monthlyExpense = monthlyAmount
    return true
end

-- ============================================================================
-- 创始人衰老、健康事件、死亡与继承
-- ============================================================================

--- 健康事件表（按年龄段）
PS.HEALTH_EVENTS = {
    -- {minAge, maxAge, chance, healthLoss, name}
    {minAge = 30, maxAge = 45, chance = 0.02, healthLoss = {1, 3},  name = "轻度劳累"},
    {minAge = 46, maxAge = 55, chance = 0.04, healthLoss = {2, 5},  name = "高血压预警"},
    {minAge = 46, maxAge = 55, chance = 0.02, healthLoss = {3, 8},  name = "腰椎间盘问题"},
    {minAge = 56, maxAge = 65, chance = 0.06, healthLoss = {3, 8},  name = "心脑血管问题"},
    {minAge = 56, maxAge = 65, chance = 0.03, healthLoss = {5, 12}, name = "糖尿病确诊"},
    {minAge = 66, maxAge = 75, chance = 0.08, healthLoss = {5, 15}, name = "重大疾病"},
    {minAge = 66, maxAge = 75, chance = 0.04, healthLoss = {8, 20}, name = "心脏手术"},
    {minAge = 76, maxAge = 100, chance = 0.12, healthLoss = {8, 25}, name = "严重器官衰竭"},
}

--- 月度处理：创始人衰老与健康（加速版：每年+10岁）
function PS._processFounderAging(GD)
    local p = GD.player
    if not p or not p.founderAlive then return end

    local mode = PS.LIFESTYLE_MODES[p.lifestyleMode or "balanced"] or PS.LIFESTYLE_MODES.balanced

    -- 每年1月增长年龄（每年+10岁，分摊到每月约+0.83，但用整数制：1月一次性+10）
    if GD.month == 1 then
        local prevAge = p.founderAge
        p.founderAge = p.founderAge + PS.AGE_PER_YEAR

        -- ★ 自然寿命绝对上限：到达100岁立即死亡
        if p.founderAge >= PS.MAX_NATURAL_AGE then
            p.founderAge = PS.MAX_NATURAL_AGE
            GD.AddEvent((p.founderName or "创始人") .. "寿终正寝，享年" .. p.founderAge .. "岁", "danger")
            PS._handleFounderDeath(GD)
            return
        end

        -- 自然衰老：基础健康衰减（每年衰减，受生活方式调节）
        local baseDecay = 1
        if p.founderAge >= 85 then
            baseDecay = 8    -- 85岁以上衰退极快
        elseif p.founderAge >= 75 then
            baseDecay = 5
        elseif p.founderAge >= 70 then
            baseDecay = 3
        elseif p.founderAge >= 60 then
            baseDecay = 2
        elseif p.founderAge >= 50 then
            baseDecay = 1.5
        end
        local actualDecay = math.floor(baseDecay * mode.healthDecayMult + 0.5)
        p.founderHealth = math.max(0, p.founderHealth - actualDecay)

        -- 能力值成长（受年龄效率和生活方式影响）
        local efficiency, expBonus = PS.GetAbilityEfficiency(p.founderAge)
        local abilityGrowth = 2 * efficiency * mode.abilityGrowthMult
        p.founderAbility = math.min(100, (p.founderAbility or 50) + abilityGrowth)
        if expBonus > 0 then
            p.founderAbility = math.min(100, p.founderAbility + expBonus * 1.5)
        end
        -- 衰退期能力下降
        if p.founderAge > 65 then
            local decline = (p.founderAge - 65) * 0.1
            p.founderAbility = math.max(20, p.founderAbility - decline)
        end

        -- 年龄里程碑事件
        local fn = p.founderName or "创始人"
        local milestones = {30, 50, 60, 65, 70, 80, 90}
        for _, ms in ipairs(milestones) do
            if prevAge < ms and p.founderAge >= ms then
                if ms == 30 then
                    GD.AddEvent(fn .. "步入而立之年，正值事业上升期", "info")
                elseif ms == 50 then
                    GD.AddEvent(fn .. "年满50岁，步入知天命之年", "info")
                elseif ms == 60 then
                    GD.AddEvent(fn .. "年满60岁，考虑企业传承事宜", "warning")
                elseif ms == 65 then
                    GD.AddEvent(fn .. "年满65岁，能力开始缓慢衰退", "warning")
                elseif ms == 70 then
                    GD.AddEvent(fn .. "年满70岁，健康状况需格外关注", "warning")
                elseif ms == 80 then
                    GD.AddEvent(fn .. "年满80岁，已是高龄，需尽快安排接班", "danger")
                elseif ms == 90 then
                    GD.AddEvent(fn .. "年满90岁高龄，身体已极度衰弱", "danger")
                end
            end
        end
    end

    -- 每月随机健康事件（概率受生活方式调节）
    for _, evt in ipairs(PS.HEALTH_EVENTS) do
        if p.founderAge >= evt.minAge and p.founderAge <= evt.maxAge then
            local adjustedChance = evt.chance * mode.healthDecayMult
            if math.random() < adjustedChance then
                local loss = math.random(evt.healthLoss[1], evt.healthLoss[2])
                p.founderHealth = math.max(0, p.founderHealth - loss)
                local medCost = math.floor(loss * 0.5 * 10) / 10
                p.cash = p.cash - medCost
                GD.AddEvent((p.founderName or "创始人") .. evt.name .. "，健康-" .. loss .. "，医疗费" .. medCost .. "万", "warning")
            end
        end
    end

    -- 健康恢复（每月少量恢复，年轻时恢复快）
    if p.founderHealth > 0 and p.founderHealth < 100 then
        local recoveryChance = 0
        if p.founderAge < 40 then
            recoveryChance = 0.4
        elseif p.founderAge < 50 then
            recoveryChance = 0.3
        elseif p.founderAge < 65 then
            recoveryChance = 0.15
        elseif p.founderAge < 75 then
            recoveryChance = 0.05
        else
            recoveryChance = 0.01  -- 75岁以上几乎不恢复
        end
        if p.lifestyleMode == "healthy" then
            recoveryChance = recoveryChance + 0.15
        end
        if math.random() < recoveryChance then
            p.founderHealth = math.min(100, p.founderHealth + 1)
        end
    end

    -- 健康过低影响效率提示
    if p.founderHealth > 0 and p.founderHealth <= 60 and GD.month == 6 then
        GD.AddEvent((p.founderName or "创始人") .. "健康状况不佳(当前" .. p.founderHealth .. ")，工作效率下降", "warning")
    end

    -- ★ 死亡判定（分层递进，确保不会活过100岁）
    if p.founderHealth <= 0 then
        PS._handleFounderDeath(GD)
        return
    end

    -- 高龄死亡概率：年龄越大概率越高
    local deathChance = 0
    if p.founderAge >= 90 then
        -- 90岁以上：每月15%基础 + 低健康加成，基本活不过几个月
        deathChance = 0.15 + (100 - p.founderHealth) * 0.005
    elseif p.founderAge >= 85 then
        -- 85-89岁：每月8%基础
        deathChance = 0.08 + (100 - p.founderHealth) * 0.003
    elseif p.founderAge >= 80 then
        -- 80-84岁：每月3%基础 + 低健康加成
        deathChance = 0.03 + (100 - p.founderHealth) * 0.002
    elseif p.founderAge >= 70 and p.founderHealth <= 30 then
        -- 70岁以上低健康：有概率猝死
        deathChance = (30 - p.founderHealth) * 0.003
    end

    if deathChance > 0 and math.random() < deathChance then
        PS._handleFounderDeath(GD)
        return
    end
end

function PS.FindSuccessionHeir(player, preferWill)
    if not player or not player.family or not player.family.children then return nil end
    local children = player.family.children

    if preferWill and player.will and player.will.hasWill and player.will.beneficiaries then
        local selected = nil
        local selectedShare = -1
        for _, b in ipairs(player.will.beneficiaries) do
            local name = b.name
            if name then
                for _, child in ipairs(children) do
                    if child.name == name and (b.share or 0) > selectedShare then
                        selected = child
                        selectedShare = b.share or 0
                    end
                end
            end
        end
        if selected then return selected end
    end

    local heir = nil
    local bestAbility = -1
    for _, child in ipairs(children) do
        local ability = child.ability or 30
        if ability > bestAbility then
            heir = child
            bestAbility = ability
        end
    end
    return heir
end

local function calcCompanyStakeValue(GD)
    if not GD then return 0 end
    if GD.GroupSystem and GD.GroupSystem.IsActive(GD) then
        return GD.GroupSystem.GetPersonalEquityValue(GD)
    end
    if GD.GetCompanyPortfolioSummary then
        local total = 0
        for _, rec in ipairs(GD.GetCompanyPortfolioSummary() or {}) do
            local company = rec.state and rec.state.company or {}
            local gov = company.governance
            local companyValue = math.max(gov and (gov.lastValuation or 0) or 0, rec.totalAssets or company.totalAssets or 0)
            local ratio = rec.founderRatio or 0
            if ratio > 0 then total = total + math.floor(companyValue * ratio) end
        end
        return total
    end
    if not GD.company then return 0 end
    local gov = GD.company.governance
    if gov then
        local lastVal = gov.lastValuation or 0
        local totalAssets = GD.company.totalAssets or 0
        local companyValue = math.max(lastVal, totalAssets)
        return math.floor(companyValue * (gov.founderRatio or 1.0))
    end
    return GD.company.totalAssets or 0
end

function PS.CalcEstateWealth(GD)
    local p = GD.player
    if not p then return 0 end

    local total = p.cash or 0
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = p.investments and p.investments[pid]
        if inv then total = total + (inv.amount or 0) end
    end
    for _, prop in ipairs(p.properties or {}) do
        total = total + (prop.currentValue or prop.purchasePrice or 0)
    end
    for _, item in ipairs(p.lifestyleItems or {}) do
        total = total + math.floor((item.price or 0) * 0.6)
    end
    if p.familyOffice then
        total = total + (p.familyOffice.totalAssets or 0)
    end
    total = total + calcCompanyStakeValue(GD)

    for _, loan in ipairs(p.personalLoans or {}) do
        total = total - (loan.remaining or loan.amount or 0)
    end
    return math.max(0, math.floor(total))
end

function PS.CalcEstateCollateralValue(GD)
    local p = GD.player
    if not p then return 0 end
    local collateralValue = calcCompanyStakeValue(GD)
    for _, prop in ipairs(p.properties or {}) do
        collateralValue = collateralValue + (prop.currentValue or prop.purchasePrice or 0)
    end
    for _, item in ipairs(p.lifestyleItems or {}) do
        collateralValue = collateralValue + math.floor((item.price or 0) * 0.6)
    end
    if p.familyOffice then
        collateralValue = collateralValue + (p.familyOffice.totalAssets or 0)
    end
    return math.max(0, math.floor(collateralValue))
end

function PS.GetInheritancePreview(GD, heirName)
    local p = GD.player
    local fam = p and p.family
    if not p or not fam then return nil end

    local heir = nil
    if heirName then
        for _, child in ipairs(fam.children or {}) do
            if child.name == heirName then
                heir = child
                break
            end
        end
    end
    heir = heir or PS.FindSuccessionHeir(p, true)

    local totalWealth = math.max(0, PS.CalcNetWorth(GD))
    local taxRate = PS.INHERITANCE_TAX_RATE
    local taxAmount = math.floor(totalWealth * taxRate)
    local cashAvailable = p.cash or 0
    local shortage = math.max(0, taxAmount - cashAvailable)
    local collateralValue = PS.CalcEstateCollateralValue(GD)
    local existingLoan = 0
    for _, loan in ipairs(p.personalLoans or {}) do
        if loan.type == "inheritanceTaxMortgage" then
            existingLoan = existingLoan + (loan.remaining or loan.amount or 0)
        end
    end
    local maxLoan = math.max(0, math.floor(collateralValue * 0.60) - existingLoan)

    return {
        heir = heir,
        totalWealth = totalWealth,
        taxRate = taxRate,
        taxAmount = taxAmount,
        cashAvailable = cashAvailable,
        shortage = shortage,
        collateralValue = collateralValue,
        maxLoan = maxLoan,
        canBorrow = shortage <= maxLoan,
    }
end

local function liquidateEstateInvestments(player)
    if not player or not player.investments then return end
    for _, pid in ipairs(PS.PRODUCT_ORDER) do
        local inv = player.investments[pid]
        if inv and (inv.amount or 0) > 0 then
            player.cash = (player.cash or 0) + inv.amount
            inv.amount = 0
            if inv.lockMonths then inv.lockMonths = 0 end
        end
    end
end

function PS._raiseInheritanceTaxLoan(GD, shortage)
    local p = GD.player
    shortage = math.ceil(shortage or 0)
    if not p or shortage <= 0 then return 0 end

    local collateralValue = PS.CalcEstateCollateralValue(GD)
    p.personalLoans = p.personalLoans or {}
    local existingInheritanceLoan = 0
    for _, loan in ipairs(p.personalLoans) do
        if loan.type == "inheritanceTaxMortgage" then
            existingInheritanceLoan = existingInheritanceLoan + (loan.remaining or loan.amount or 0)
        end
    end
    local maxLoan = math.max(0, math.floor(collateralValue * 0.60) - existingInheritanceLoan)
    local loanAmount = math.min(shortage, maxLoan)
    if loanAmount <= 0 then return 0 end

    local months = 120
    local rate = 4.8
    local monthlyPay = math.max(1, math.floor(loanAmount * (rate / 100 / 12 + 1 / months)))
    table.insert(p.personalLoans, {
        type = "inheritanceTaxMortgage",
        name = "遗产税资产抵押贷款",
        amount = loanAmount,
        remaining = loanAmount,
        rate = rate,
        monthlyPay = monthlyPay,
        totalMonths = months,
        remainMonths = months,
        collateralValue = collateralValue,
        familyDebt = true,
        purpose = "inheritance_tax",
    })
    p.cash = (p.cash or 0) + loanAmount
    GD.AddEvent("家族现金不足，已抵押资产贷款" .. GD.FormatMoney(loanAmount) .. "用于缴纳遗产税", "warning")
    return loanAmount
end

function PS.ResolveInheritance(GD, heirName)
    local p = GD.player
    if not p then return false, "未初始化" end
    local fam = p.family
    if not fam or not fam.children or #fam.children == 0 then return false, "无子女可继承" end

    local heir = nil
    if heirName then
        for _, child in ipairs(fam.children) do
            if child.name == heirName then
                heir = child
                break
            end
        end
    end
    heir = heir or PS.FindSuccessionHeir(p, true)
    if not heir then return false, "无子女可继承" end

    local co = GD.company or {}
    local deceasedName = co.inheritanceDeceasedName or p.founderName or "创始人"
    local deceasedAge = co.inheritanceDeceasedAge or p.founderAge or 0
    local totalWealth = math.max(0, PS.CalcNetWorth(GD))

    -- 遗产税固定按继承确认时个人净资产的10%登记，遗嘱只决定受益人分配。
    local taxRate = PS.INHERITANCE_TAX_RATE
    if p.will and p.will.hasWill and p.will.beneficiaries then
        local totalShare = 0
        for _, b in ipairs(p.will.beneficiaries) do
            totalShare = totalShare + (b.share or 0)
        end
        if totalShare > 0 then
            for _, b in ipairs(p.will.beneficiaries) do
                local portion = totalWealth * (1 - taxRate) * (b.share or 0) / totalShare
                GD.AddEvent(
                    "遗嘱执行：" .. (b.name or "受益人") .. " 继承"
                        .. string.format("%.0f", portion) .. "万（"
                        .. math.floor((b.share or 0) / totalShare * 100) .. "%）",
                    "info"
                )
            end
        end
    end
    local taxAmount = math.floor(totalWealth * taxRate)
    if taxAmount > 0 then
        p.inheritanceTaxDue = {
            total = taxAmount,
            remaining = taxAmount,
            paid = 0,
            graceMonths = 6,
            elapsedMonths = 0,
            active = true,
            heirName = heir.name,
            deceasedName = deceasedName,
            createdAtMonth = GD.totalMonths or 0,
        }
        GD.AddEvent(
            "遗产税" .. string.format("%.0f", taxAmount) .. "万（税率"
                .. math.floor(taxRate * 100) .. "%），继承后六个月内需由个人筹资缴清",
            "warning"
        )
    else
        p.inheritanceTaxDue = nil
    end

    GD.AddEvent(
        heir.name .. "继承遗产" .. string.format("%.0f", math.max(0, totalWealth - taxAmount))
            .. "万（税前估值，遗产税待缴）",
        "success"
    )

    -- 继承人接班
    p.successorName = heir.name
    p.generation = (p.generation or 1) + 1
    p.founderAlive = true
    p.founderAge = heir.age
    p.founderHealth = 85 + math.random(0, 10)
    p.founderAbility = heir.ability or 50
    p.founderName = heir.name
    p.founderGender = heir.gender or "male"
    p.lifestyleMode = "balanced"

    GD.AddEvent("第" .. p.generation .. "代继承人 " .. heir.name .. "（" .. tostring(heir.age or 0) .. "岁，能力" .. math.floor(p.founderAbility) .. "）接管公司", "success")

    -- 新掌门人的配偶和子女成为新一代核心家庭，其子女是后续继承人
    fam.children = heir.children or {}
    fam.married = heir.married or heir.spouse ~= nil
    fam.spouse = heir.spouse
    fam.successionMode = nil
    fam.gradualTransferPct = 0
    p.will = nil
    p.honoraryChairman = nil

    if GD.company then
        GD.company.showHeirSelection = false
        GD.company.inheritanceDeceasedName = nil
        GD.company.inheritanceDeceasedAge = nil
        GD.company.forceInheritanceScreen = false
        GD.company.showNoHeirCrisis = false
        GD.company.noHeirDeceasedName = nil
    end
    GD.paused = false
    return true, "继承完成"
end

--- 处理创始人死亡
function PS._handleFounderDeath(GD)
    local p = GD.player
    if not p then return end
    p.founderAlive = false
    p.founderHealth = 0

    local fam = p.family
    local deceasedName = p.founderName or "创始人"
    local deceasedAge = p.founderAge or 0

    if fam and fam.children and #fam.children > 0 then
        GD.AddEvent(deceasedName .. "不幸离世，享年" .. deceasedAge .. "岁。", "danger")
        GD.AddEvent("请选择继承人开始家族继承，子女任意年龄均可接班", "warning")
        if GD.company then
            GD.company.showHeirSelection = true
            GD.company.inheritanceDeceasedName = deceasedName
            GD.company.inheritanceDeceasedAge = deceasedAge
            GD.company.forceInheritanceScreen = true
        end
        GD.paused = true
    else
        -- 无子女继承人 → 弹出提示
        GD.AddEvent(deceasedName .. "不幸离世，享年" .. deceasedAge .. "岁，无子女可继承公司", "danger")
        GD.AddEvent("公司进入托管状态，请选择是否清算破产", "danger")
        GD.company.showNoHeirCrisis = true
        GD.company.noHeirDeceasedName = deceasedName
        GD.paused = true
    end
end

--- 家庭月度开销处理（子女加速成长版）
function PS._processFamilyExpenses(GD)
    local p = GD.player
    if not p or not p.family then return end
    local fam = p.family
    local totalExpense = 0

    -- 1) 基础家庭生活费
    local baseLiving = fam.married and 2.0 or 1.0
    totalExpense = totalExpense + baseLiving

    -- 2) 配偶收入（抵扣开销）
    local spouseIncome = 0
    if fam.married and fam.spouse then
        spouseIncome = fam.spouse.monthlyIncome or 0
    end

    -- 3) 子女教育开销 + 年龄增长（每年1月长10岁，与创始人同步）
    local childCost = 0
    local trainingCost = 0
    for _, child in ipairs(fam.children or {}) do
        if GD.month == 1 then
            child.age = child.age + PS.CHILD_AGE_PER_YEAR
        end
        -- 基础教育费用
        local stage = PS.GetEducationStage(child.age)
        childCost = childCost + stage.monthlyCost

        -- 培养项目费用
        if child.training then
            local trainCfg = PS.CHILD_TRAINING[child.training]
            if trainCfg then
                trainingCost = trainingCost + (trainCfg.monthlyCost or 0)
                -- 每年1月结算能力增长
                if GD.month == 1 then
                    child.ability = (child.ability or 30) + (trainCfg.abilityGain or 0)
                    child.ability = math.min(100, child.ability)
                end
            end
        end

        -- 子女自然能力成长（每年1月）
        if GD.month == 1 and not child.training then
            child.ability = math.min(80, (child.ability or 30) + 1)  -- 无培养时缓慢成长
        end
    end
    totalExpense = totalExpense + childCost + trainingCost

    PS.ProcessAdultChildrenFamily(GD)

    -- 4) 赡养父母
    local elderCost = 0
    if fam.elderCare and fam.elderCare.enabled then
        elderCost = fam.elderCare.monthlyExpense or 1.5
        -- 父母健康随时间缓慢下降
        if math.random() < 0.05 then
            fam.elderCare.parentHealth = math.max(0, (fam.elderCare.parentHealth or 80) - math.random(1, 3))
            if fam.elderCare.parentHealth < 30 then
                -- 低健康时医疗费增加
                elderCost = elderCost + 2
                if math.random() < 0.1 then
                    GD.AddEvent("父母身体不适，本月医疗开支增加2万", "warning")
                end
            end
        end
    end
    totalExpense = totalExpense + elderCost

    -- 5) 配偶年龄增长 + 寿命检查（每年1月，同步加速）
    if GD.month == 1 and fam.spouse then
        fam.spouse.age = (fam.spouse.age or 30) + PS.AGE_PER_YEAR

        -- ★ 配偶寿命上限检查
        if fam.spouse.age >= PS.MAX_NATURAL_AGE then
            fam.spouse.age = PS.MAX_NATURAL_AGE
            GD.AddEvent("配偶" .. (fam.spouse.name or "") .. "寿终正寝，享年" .. fam.spouse.age .. "岁", "danger")
            fam.married = false
            fam.spouse = nil
        elseif fam.spouse.age >= 85 then
            -- 高龄配偶有自然死亡概率
            local spouseDeathChance = 0.05 + (fam.spouse.age - 85) * 0.03
            if math.random() < spouseDeathChance then
                GD.AddEvent("配偶" .. (fam.spouse.name or "") .. "因年迈去世，享年" .. fam.spouse.age .. "岁", "danger")
                fam.married = false
                fam.spouse = nil
            end
        end
    end

    -- 6) 赡养父母寿命检查
    if fam.elderCare and fam.elderCare.enabled and GD.month == 1 then
        -- 父母也在变老（每年检查是否去世）
        local parentHealth = fam.elderCare.parentHealth or 80
        if parentHealth <= 0 then
            fam.elderCare.enabled = false
            GD.AddEvent("父母已去世，赡养费用结束", "info")
        end
    end

    -- 净开销 = 总开销 - 配偶收入
    local netExpense = math.max(0, totalExpense - spouseIncome)
    netExpense = math.floor(netExpense * 100) / 100

    if netExpense > 0 then
        p.cash = p.cash - netExpense
    end

    if childCost + trainingCost > 0 then
        PersonalFinanceEcosystem.RecordTaxDeduction(
            GD,
            "education",
            childCost + trainingCost,
            "family-education:" .. tostring(GD.totalMonths or 0),
            "子女教育与培养支出"
        )
    end
    if elderCost > 0 then
        PersonalFinanceEcosystem.RecordTaxDeduction(
            GD,
            "elderCare",
            elderCost,
            "family-elder-care:" .. tostring(GD.totalMonths or 0),
            "赡养老人支出"
        )
    end

    fam.monthlyFamilyExpense = netExpense
    fam.totalFamilyExpense = (fam.totalFamilyExpense or 0) + netExpense
    fam.totalChildExpense = (fam.totalChildExpense or 0) + childCost
    fam.totalElderExpense = (fam.totalElderExpense or 0) + elderCost
    fam.totalTrainingExpense = (fam.totalTrainingExpense or 0) + trainingCost
end

--- 获取家庭状态摘要
function PS.GetFamilySummary(GD)
    local p = GD.player
    if not p or not p.family then
        return {married = false, childCount = 0, monthlyExpense = 0}
    end
    local fam = p.family
    local childDetails = {}
    for _, child in ipairs(fam and fam.children or {}) do
        local stage = PS.GetEducationStage(child.age)
        table.insert(childDetails, {
            name = child.name,
            age = child.age,
            gender = child.gender == "male" and "男" or "女",
            education = stage.name,
            monthlyCost = stage.monthlyCost,
            ability = child.ability or 30,
            training = child.training,
            married = child.married or false,
            spouse = child.spouse,
            children = child.children or {},
        })
    end

    return {
        married = fam.married,
        spouse = fam.spouse,
        childCount = #fam.children,
        children = childDetails,
        elderCare = fam.elderCare,
        monthlyExpense = fam.monthlyFamilyExpense or 0,
        totalExpense = fam.totalFamilyExpense or 0,
        totalChildExpense = fam.totalChildExpense or 0,
        totalElderExpense = fam.totalElderExpense or 0,
        totalTrainingExpense = fam.totalTrainingExpense or 0,
        successionMode = fam.successionMode,
        gradualTransferPct = fam.gradualTransferPct or 0,
    }
end

-- ============================================================================
-- 生活方式模式 API
-- ============================================================================

--- 切换生活方式模式
---@param GD table
---@param mode string "healthy"|"workaholic"|"balanced"
---@return boolean, string
function PS.SetLifestyleMode(GD, mode)
    local p = GD.player
    if not p then return false, "未初始化" end
    if not PS.LIFESTYLE_MODES[mode] then return false, "无效的生活方式模式" end

    local oldMode = p.lifestyleMode or "balanced"
    if oldMode == mode then return false, "已经是该模式" end

    p.lifestyleMode = mode
    local cfg = PS.LIFESTYLE_MODES[mode]
    GD.AddEvent("生活方式切换为「" .. cfg.icon .. " " .. cfg.name .. "」", "info")
    return true, "已切换为" .. cfg.name
end

--- 获取当前能力效率（综合健康和年龄）
function PS.GetCurrentEfficiency(GD)
    local p = GD.player
    if not p then return 1.0 end
    local efficiency, _ = PS.GetAbilityEfficiency(p.founderAge or 30)
    -- 健康低于60时降低效率
    local health = p.founderHealth or 100
    if health < 60 then
        efficiency = efficiency * (0.5 + health / 120)  -- 60→100%, 30→75%, 0→50%
    end
    return efficiency
end

-- ============================================================================
-- 子女培养 API
-- ============================================================================

--- 为子女设置培养项目
---@param GD table
---@param childIdx number 子女索引
---@param trainingKey string|nil 培养项目key，nil表示取消培养
---@return boolean, string
function PS.SetChildTraining(GD, childIdx, trainingKey)
    local p = GD.player
    if not p or not p.family then return false, "未初始化" end
    local fam = p.family
    local child = fam.children[childIdx]
    if not child then return false, "无此子女" end

    if trainingKey == nil then
        child.training = nil
        GD.AddEvent(child.name .. "的培养项目已取消", "info")
        return true, "已取消培养"
    end

    local trainCfg = PS.CHILD_TRAINING[trainingKey]
    if not trainCfg then return false, "无效的培养项目" end

    -- 年龄限制检查
    if trainCfg.minAge and child.age < trainCfg.minAge then
        return false, child.name .. "年龄不足（需" .. trainCfg.minAge .. "岁以上）"
    end

    -- 创业资助特殊处理（一次性费用）
    if trainingKey == "startup" then
        if p.cash < trainCfg.startupCost then
            return false, "现金不足，创业资助需" .. trainCfg.startupCost .. "万"
        end
        p.cash = p.cash - trainCfg.startupCost
        child.ability = math.min(100, (child.ability or 30) + trainCfg.abilityGain)
        GD.AddEvent("资助" .. child.name .. "创业" .. trainCfg.startupCost .. "万，能力+" .. trainCfg.abilityGain, "success")
        return true, "创业资助完成"
    end

    child.training = trainingKey
    GD.AddEvent(child.name .. "开始" .. trainCfg.icon .. trainCfg.name .. "培养", "info")
    return true, "已安排" .. trainCfg.name
end

-- ============================================================================
-- 传承系统 API
-- ============================================================================

--- 设置传承模式
---@param GD table
---@param mode string "gradual"|"onetime"
---@return boolean, string
function PS.SetSuccessionMode(GD, mode)
    local p = GD.player
    if not p or not p.family then return false, "未初始化" end
    if mode ~= "gradual" and mode ~= "onetime" then
        return false, "无效的传承模式（可选：gradual/onetime）"
    end

    -- 需要有子女（任意年龄均可继承）
    if #(p.family.children or {}) == 0 then
        return false, "无子女可接班"
    end

    p.family.successionMode = mode
    if mode == "gradual" then
        GD.AddEvent("选择渐进式传承（每次转移10%股权，遗产税固定按个人净资产10%）", "info")
    else
        GD.AddEvent("选择一次性传承（创始人退休时全部交接，遗产税固定按个人净资产10%）", "info")
    end
    return true
end

--- 执行渐进式传承（每次转移10%）
---@param GD table
---@return boolean, string
function PS.DoGradualTransfer(GD)
    local p = GD.player
    if not p or not p.family then return false, "未初始化" end
    local fam = p.family

    if fam.successionMode ~= "gradual" then
        return false, "需先设置渐进式传承模式"
    end

    if (fam.gradualTransferPct or 0) >= 100 then
        return false, "已完成全部转移"
    end

    -- 每次转移10%资产，收10%传承税
    local netWorth = math.max(0, PS.CalcNetWorth(GD))
    local transferAmount = netWorth * 0.10
    local taxAmount = transferAmount * PS.INHERITANCE_TAX_RATE  -- 固定按个人净资产10%计税
    local totalCost = taxAmount  -- 实际支出是税金

    if p.cash < totalCost then
        liquidateEstateInvestments(p)
    end
    if p.cash < totalCost then
        local shortage = totalCost - (p.cash or 0)
        local borrowed = PS._raiseInheritanceTaxLoan(GD, shortage)
        if borrowed < shortage then
            return false, "现金不足以支付传承税（需" .. string.format("%.1f", totalCost) .. "万）"
        end
    end

    p.cash = p.cash - totalCost
    fam.gradualTransferPct = (fam.gradualTransferPct or 0) + 10

    GD.AddEvent("渐进传承：转移10%股权（" .. string.format("%.0f", transferAmount) .. "万），税金" .. string.format("%.1f", totalCost) .. "万", "info")

    -- 完成100%时自动交接
    if fam.gradualTransferPct >= 100 then
        PS._executeSuccession(GD)
    end

    return true, "已转移" .. fam.gradualTransferPct .. "%"
end

--- 执行一次性传承（创始人退休）
---@param GD table
---@return boolean, string
function PS.DoOnetimeSuccession(GD)
    local p = GD.player
    if not p or not p.family then return false, "未初始化" end

    -- 找到最佳继承人（能力最高子女，任意年龄均可继承）
    local heir = PS.FindSuccessionHeir(p, true)
    if not heir then return false, "无子女可接班" end

    -- 一次性传承税固定为继承时个人净资产的10%
    local netWorth = math.max(0, PS.CalcNetWorth(GD))
    local taxAmount = netWorth * PS.INHERITANCE_TAX_RATE
    if p.cash < taxAmount then
        liquidateEstateInvestments(p)
    end
    if p.cash < taxAmount then
        local shortage = taxAmount - (p.cash or 0)
        local borrowed = PS._raiseInheritanceTaxLoan(GD, shortage)
        if borrowed < shortage then
            return false, "现金不足以支付传承税（需" .. string.format("%.0f", taxAmount) .. "万）"
        end
    end

    p.cash = p.cash - taxAmount
    p.family.successionMode = "onetime"
    GD.AddEvent("一次性传承：缴纳遗产税" .. string.format("%.0f", taxAmount) .. "万（税率" .. math.floor(PS.INHERITANCE_TAX_RATE * 100) .. "%）", "warning")

    PS._executeSuccession(GD)
    return true, "传承完成"
end

--- 内部：执行实际的交接流程
function PS._executeSuccession(GD)
    local p = GD.player
    local fam = p.family
    if not fam or not fam.children then return end

    -- 找到最佳继承人（任意年龄子女均可继承）
    local heir = PS.FindSuccessionHeir(p, true)
    if not heir then return end

    -- 退休的创始人成为荣誉董事长
    local oldName = p.founderName or "创始人"
    p.honoraryChairman = {
        name = oldName,
        age = p.founderAge,
        prestige = p.prestige or 0,
        retiredYear = GD.year,
    }

    -- 继承人接班
    p.successorName = heir.name
    p.generation = (p.generation or 1) + 1
    p.founderName = heir.name
    p.founderAge = heir.age
    p.founderHealth = 85 + math.random(0, 10)
    p.founderAbility = heir.ability or 50
    p.founderAlive = true
    p.lifestyleMode = "balanced"  -- 新掌门默认平衡

    -- 荣誉董事长提供声望加成
    p.prestige = (p.prestige or 0) + 15

    -- 新掌门人的配偶和子女成为新一代核心家庭
    fam.children = heir.children or {}
    fam.married = heir.married or heir.spouse ~= nil
    fam.spouse = heir.spouse
    fam.successionMode = nil
    fam.gradualTransferPct = 0

    GD.AddEvent(oldName .. "正式退休，成为荣誉董事长（声望+15）", "success")
    GD.AddEvent("第" .. p.generation .. "代继承人 " .. heir.name .. "（能力" .. math.floor(p.founderAbility) .. "）接管公司", "success")
end

-- ============================================================================
-- 家族办公室系统
-- ============================================================================

--- 家族办公室解锁阈值
PS.FAMILY_OFFICE_THRESHOLD = 10000  -- 1亿 = 10000万

PS.FO_MIN_ANNUAL_RETURN = 0.01
PS.FO_MAX_ANNUAL_RETURN = 0.03

--- 家族办公室资产配置选项（所有组合最终年化收益统一限制在1%~3%）
PS.FO_ASSET_CLASSES = {
    stocks = {name = "股票型基金", icon = "📈", baseReturn = 0.025, risk = 0.005, minPct = 0, maxPct = 60},
    bonds  = {name = "债券组合",   icon = "📜", baseReturn = 0.012, risk = 0.002, minPct = 0, maxPct = 80},
    realestate = {name = "不动产",  icon = "🏠", baseReturn = 0.020, risk = 0.003, minPct = 0, maxPct = 50},
    pe     = {name = "私募股权",   icon = "🏛️", baseReturn = 0.030, risk = 0.006, minPct = 0, maxPct = 30},
}

--- 初始化家族办公室
function PS.InitFamilyOffice(GD)
    local p = GD.player
    if not p then return false, "未初始化" end

    local nw = PS.CalcNetWorth(GD)
    if nw < PS.FAMILY_OFFICE_THRESHOLD then
        return false, "个人资产需达到1亿才能开设家族办公室（当前" .. string.format("%.0f", nw) .. "万）"
    end

    if p.familyOffice then
        return false, "家族办公室已存在"
    end

    p.familyOffice = {
        totalAssets = 0,            -- 托管资产总额
        allocation = {              -- 资产配置比例(%)
            stocks = 30,
            bonds = 40,
            realestate = 20,
            pe = 10,
        },
        managerAbility = 60,        -- 职业经理人能力(50~100)
        managerSalary = 5,          -- 经理人月薪(万)
        yearlyReturn = 0,           -- 本年度收益
        totalReturn = 0,            -- 累计收益
        operatingCost = 0,          -- 本年运营费
        -- 家族治理
        charter = false,            -- 是否制定家族宪章
        charterYear = nil,          -- 宪章制定年份
        -- 慈善基金
        charity = {
            enabled = false,
            foundation = nil,       -- 基金会名称
            yearlyDonation = 0,     -- 年度捐赠额
            totalDonation = 0,      -- 累计捐赠
            taxDeduction = 0,       -- 可抵扣税额
        },
        createdYear = GD.year,
    }

    GD.AddEvent("家族办公室正式成立！专业化管理家族财富", "success")
    return true, "家族办公室已开设"
end

--- 向家族办公室注入资金
function PS.FO_InjectFunds(GD, amount)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end
    if amount <= 0 then return false, "金额需大于0" end
    if p.cash < amount then return false, "现金不足" end

    p.cash = p.cash - amount
    p.familyOffice.totalAssets = p.familyOffice.totalAssets + amount
    GD.AddEvent("向家族办公室注入资金" .. string.format("%.0f", amount) .. "万", "info")
    return true
end

--- 从家族办公室提取资金
function PS.FO_WithdrawFunds(GD, amount)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end
    if amount <= 0 then return false, "金额需大于0" end
    if p.familyOffice.totalAssets < amount then return false, "托管资产不足" end

    p.familyOffice.totalAssets = p.familyOffice.totalAssets - amount
    p.cash = p.cash + amount
    GD.AddEvent("从家族办公室提取" .. string.format("%.0f", amount) .. "万", "info")
    return true
end

--- 调整资产配置
---@param allocation table {stocks=30, bonds=40, realestate=20, pe=10}
function PS.FO_SetAllocation(GD, allocation)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end

    -- 验证总和为100
    local total = 0
    for k, v in pairs(allocation) do
        if not PS.FO_ASSET_CLASSES[k] then return false, "无效的资产类别: " .. k end
        local cls = PS.FO_ASSET_CLASSES[k]
        if v < cls.minPct or v > cls.maxPct then
            return false, cls.name .. "比例需在" .. cls.minPct .. "%-" .. cls.maxPct .. "%之间"
        end
        total = total + v
    end
    if math.abs(total - 100) > 1 then return false, "配置比例总和需为100%（当前" .. total .. "%）" end

    p.familyOffice.allocation = allocation
    GD.AddEvent("家族办公室资产配置已调整", "info")
    return true
end

--- 聘用/升级职业经理人
function PS.FO_HireManager(GD, abilityLevel)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end

    -- 能力等级 60~100，月薪 = 能力/10 万
    abilityLevel = math.max(50, math.min(100, abilityLevel or 60))
    local salary = math.floor(abilityLevel / 10)

    p.familyOffice.managerAbility = abilityLevel
    p.familyOffice.managerSalary = salary
    GD.AddEvent("聘用家族办公室经理人（能力" .. abilityLevel .. "，月薪" .. salary .. "万）", "info")
    return true
end

--- 制定家族宪章
function PS.FO_CreateCharter(GD)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end
    if p.familyOffice.charter then return false, "家族宪章已制定" end

    local cost = 50  -- 律师费50万
    if p.cash < cost then return false, "现金不足（律师费" .. cost .. "万）" end

    p.cash = p.cash - cost
    p.familyOffice.charter = true
    p.familyOffice.charterYear = GD.year
    p.prestige = (p.prestige or 0) + 10
    GD.AddEvent("家族宪章正式制定！家族治理升级，声望+10", "success")
    return true
end

--- 设立慈善基金会
function PS.FO_CreateCharity(GD, foundationName, yearlyAmount)
    local p = GD.player
    if not p or not p.familyOffice then return false, "家族办公室未开设" end
    if p.familyOffice.charity.enabled then return false, "基金会已存在" end

    yearlyAmount = math.max(10, yearlyAmount or 100)  -- 最低年捐10万
    local setupCost = 100  -- 设立费100万
    if p.cash < setupCost then return false, "现金不足（设立费" .. setupCost .. "万）" end

    p.cash = p.cash - setupCost
    p.familyOffice.charity = {
        enabled = true,
        foundation = foundationName or (p.founderName .. "慈善基金会"),
        yearlyDonation = yearlyAmount,
        totalDonation = 0,
        taxDeduction = 0,
    }
    p.prestige = (p.prestige or 0) + 20
    GD.AddEvent("「" .. p.familyOffice.charity.foundation .. "」正式成立！声望+20", "success")
    return true
end

--- 家族办公室月度结算
function PS._processFamilyOffice(GD)
    local p = GD.player
    if not p or not p.familyOffice then return end
    local fo = p.familyOffice

    -- 1) 运营费（每年总资产的1%，最低100万/年，按月扣除）
    local yearlyOpCost = math.max(100, fo.totalAssets * 0.01)
    local monthlyOpCost = yearlyOpCost / 12
    -- 经理人月薪
    monthlyOpCost = monthlyOpCost + (fo.managerSalary or 5)
    -- 保底：个人现金不足时缩减运营费（不能扣到负数）
    if p.cash < monthlyOpCost then
        monthlyOpCost = math.max(0, p.cash)
    end
    p.cash = p.cash - monthlyOpCost
    fo.operatingCost = (fo.operatingCost or 0) + monthlyOpCost

    -- 2) 投资收益结算（每年1月）
    if GD.month == 1 and fo.totalAssets > 0 then
        local totalReturn = 0
        local managerMult = 0.9 + ((fo.managerAbility or 60) - 50) / 500
        for cls, pct in pairs(fo.allocation or {}) do
            local cfg = PS.FO_ASSET_CLASSES[cls]
            if cfg and pct > 0 then
                local portion = fo.totalAssets * pct / 100
                local returnRate = cfg.baseReturn * managerMult
                local fluctuation = (math.random() * 2 - 1) * cfg.risk
                totalReturn = totalReturn + portion * (returnRate + fluctuation)
            end
        end
        local annualRate = totalReturn / fo.totalAssets
        annualRate = math.max(PS.FO_MIN_ANNUAL_RETURN, math.min(PS.FO_MAX_ANNUAL_RETURN, annualRate))
        totalReturn = math.floor(fo.totalAssets * annualRate * 10) / 10
        fo.annualReturnRate = annualRate
        fo.totalAssets = fo.totalAssets + totalReturn
        fo.yearlyReturn = totalReturn
        fo.totalReturn = (fo.totalReturn or 0) + totalReturn

        if totalReturn >= 0 then
            GD.AddEvent("家族办公室年度收益：+" .. string.format("%.1f", totalReturn) .. "万", "success")
        else
            GD.AddEvent("家族办公室年度亏损：" .. string.format("%.1f", totalReturn) .. "万", "danger")
        end
    end

    -- 3) 慈善基金年度捐赠（每年12月）
    if GD.month == 12 and fo.charity and fo.charity.enabled then
        local donation = fo.charity.yearlyDonation or 0
        if p.cash >= donation then
            p.cash = p.cash - donation
            fo.charity.totalDonation = (fo.charity.totalDonation or 0) + donation
            -- 慈善抵税（可抵扣应税收入的12%）
            fo.charity.taxDeduction = donation * 0.12
            p.prestige = (p.prestige or 0) + math.floor(donation / 50)
            GD.AddEvent("「" .. (fo.charity.foundation or "基金会") .. "」年度捐赠" .. string.format("%.0f", donation) .. "万", "success")
        end
    end
end

-- ============================================================================
-- 遗嘱系统
-- ============================================================================

--- 立遗嘱
function PS.CreateWill(GD, beneficiaries)
    local p = GD.player
    if not p then return false, "未初始化" end

    local lawyerFee = 2  -- 律师见证费2万
    if p.cash < lawyerFee then return false, "现金不足（律师费" .. lawyerFee .. "万）" end

    p.cash = p.cash - lawyerFee
    p.will = {
        hasWill = true,
        lawyerFee = lawyerFee,
        beneficiaries = beneficiaries or {},  -- [{name, share}]
        createdYear = GD.year,
    }
    GD.AddEvent("遗嘱已立，律师见证费" .. lawyerFee .. "万", "info")
    return true, "遗嘱已完成"
end

--- 获取综合状态（供UI和其他模块调用）
function PS.GetLifecycleStatus(GD)
    local p = GD.player
    if not p then return nil end

    local efficiency, expBonus = PS.GetAbilityEfficiency(p.founderAge or 18)
    local mode = PS.LIFESTYLE_MODES[p.lifestyleMode or "balanced"]

    return {
        age = p.founderAge or 18,
        health = p.founderHealth or 100,
        ability = math.floor(p.founderAbility or 50),
        efficiency = efficiency,
        expBonus = expBonus,
        lifestyleMode = p.lifestyleMode or "balanced",
        lifestyleModeName = mode and mode.name or "平衡生活",
        generation = p.generation or 1,
        honoraryChairman = p.honoraryChairman,
        hasWill = p.will and p.will.hasWill or false,
        hasFamilyOffice = p.familyOffice ~= nil,
        familyOfficeAssets = p.familyOffice and p.familyOffice.totalAssets or 0,
    }
end

return PS
