-- ============================================================================
-- InvestmentService.lua - 独立个人理财服务
-- 仅管理 GD.player.personalInvestment 与旧版 investments 兼容镜像，不触碰公司数据。
-- 金额单位沿用项目约定：万元。
-- ============================================================================

local InvestmentService = {}

local MONEY_PRECISION = 100
local RECORD_LIMIT = 200
local REPORT_LIMIT = 20

--- 八类个人理财产品。所有年度目标收益率均受 1%~3% 全局硬限制。
InvestmentService.PRODUCTS = {
    deposit = {
        id = "deposit", name = "银行存款", desc = "保本型活期与定期存款组合",
        minAmount = 0, riskTier = "low", liquidityMonths = 0,
        targetRange = {min = 0.0100, max = 0.0130}, lockMonths = 0,
    },
    moneyFund = {
        id = "moneyFund", name = "货币基金", desc = "低波动现金管理工具",
        minAmount = 100, riskTier = "low", liquidityMonths = 1,
        targetRange = {min = 0.0110, max = 0.0165}, lockMonths = 0,
    },
    bond = {
        id = "bond", name = "债券基金", desc = "利率与信用债组合",
        minAmount = 500, riskTier = "medium", liquidityMonths = 1,
        targetRange = {min = 0.0115, max = 0.0210}, lockMonths = 0,
    },
    reits = {
        id = "reits", name = "REITs基金", desc = "不动产现金流份额",
        minAmount = 1000, riskTier = "medium", liquidityMonths = 1,
        targetRange = {min = 0.0110, max = 0.0245}, lockMonths = 0,
    },
    indexFund = {
        id = "indexFund", name = "指数基金", desc = "宽基市场指数配置",
        minAmount = 1000, riskTier = "high", liquidityMonths = 1,
        targetRange = {min = 0.0100, max = 0.0280}, lockMonths = 0,
    },
    trust = {
        id = "trust", name = "信托计划", desc = "锁定期收益型信托产品",
        minAmount = 5000, riskTier = "high", liquidityMonths = 0,
        targetRange = {min = 0.0140, max = 0.0265}, lockMonths = 12,
    },
    stock = {
        id = "stock", name = "股票投资", desc = "权益市场主动配置",
        minAmount = 500, riskTier = "high", liquidityMonths = 1,
        targetRange = {min = 0.0100, max = 0.0300}, lockMonths = 0,
    },
    peFund = {
        id = "peFund", name = "私募股权", desc = "长期非上市股权配置",
        minAmount = 10000, riskTier = "high", liquidityMonths = 0,
        targetRange = {min = 0.0125, max = 0.0300}, lockMonths = 24,
    },
}

InvestmentService.PRODUCT_ORDER = {
    "deposit", "moneyFund", "bond", "reits",
    "indexFund", "trust", "stock", "peFund",
}
InvestmentService.INVESTMENT_PRODUCTS = InvestmentService.PRODUCTS

---@class PersonalInvestmentStrategy
---@field id string
---@field name string
---@field weights table<string, number>

--- 三套目标比例策略，所有比例合计严格为 100%。
---@type table<string, PersonalInvestmentStrategy>
InvestmentService.STRATEGIES = {
    conservative = {
        id = "conservative", name = "稳健保守",
        weights = {deposit = 0.30, moneyFund = 0.20, bond = 0.25, reits = 0.10, indexFund = 0.08, trust = 0.03, stock = 0.03, peFund = 0.01},
    },
    balanced = {
        id = "balanced", name = "均衡配置",
        weights = {deposit = 0.10, moneyFund = 0.10, bond = 0.20, reits = 0.15, indexFund = 0.15, trust = 0.10, stock = 0.10, peFund = 0.10},
    },
    growth = {
        id = "growth", name = "成长进取",
        weights = {deposit = 0.05, moneyFund = 0.05, bond = 0.10, reits = 0.10, indexFund = 0.15, trust = 0.12, stock = 0.25, peFund = 0.18},
    },
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function roundDown(value)
    return math.floor(math.max(0, value) * MONEY_PRECISION + 0.0000001) / MONEY_PRECISION
end

local function trimList(list, limit)
    while #list > limit do
        table.remove(list, 1)
    end
end

local function currentSerial(GD)
    local year = tonumber(GD and GD.year) or 0
    local month = clamp(tonumber(GD and GD.month) or 1, 1, 12)
    return year * 12 + month
end

local function productState(state, pid)
    state.holdings[pid] = state.holdings[pid] or {}
    local holding = state.holdings[pid]
    holding.amount = math.max(0, tonumber(holding.amount) or 0)
    holding.lockMonths = math.max(0, math.floor(tonumber(holding.lockMonths) or 0))
    holding.returnCarry = tonumber(holding.returnCarry) or 0
    holding.yearPrincipal = math.max(0, tonumber(holding.yearPrincipal) or holding.amount)
    holding.yearReturn = tonumber(holding.yearReturn) or 0
    return holding
end

local function macroData(GD)
    local economy = GD and GD.economy or {}
    return (GD and GD.macro) or economy.macro or {}, economy.cycle or "stable"
end

local function macroScore(pid, GD)
    local macro, cycle = macroData(GD)
    local lpr = clamp(((tonumber(macro.lpr5y) or 5.0) - 3.0) / 5.0, 0, 1)
    local gdp = clamp(((tonumber(macro.gdpGrowth) or 6.0) + 2.0) / 17.0, 0, 1)
    local pmi = clamp(((tonumber(macro.pmi) or 50.0) - 45.0) / 12.0, 0, 1)
    local confidence = clamp(((tonumber(macro.consumerConfidence) or 100.0) - 60.0) / 70.0, 0, 1)
    local investment = clamp(((tonumber(macro.fixedInvestRate) or 20.0) + 5.0) / 50.0, 0, 1)
    local rental = clamp(((tonumber(macro.rentalYield) or 3.5) - 1.0) / 7.0, 0, 1)
    local housingHealth = clamp(1 - ((tonumber(macro.housingPriceToIncome) or 7.0) - 5.0) / 12.0, 0, 1)
    local looseness = clamp(0.5 - (tonumber(macro.moneyLooseness) or 0) / 200.0, 0, 1)
    local cycleScore = ({boom = 0.85, recovery = 0.70, stable = 0.55, slowdown = 0.40, recession = 0.25, depression = 0.12})[cycle] or 0.50

    if pid == "deposit" then
        return lpr
    elseif pid == "moneyFund" then
        return 0.65 * lpr + 0.35 * looseness
    elseif pid == "bond" then
        local defensive = (cycle == "recession" or cycle == "depression") and 0.85 or 0.45
        return 0.55 * lpr + 0.45 * defensive
    elseif pid == "reits" then
        return 0.45 * rental + 0.35 * housingHealth + 0.20 * cycleScore
    elseif pid == "indexFund" then
        return 0.35 * gdp + 0.30 * pmi + 0.20 * confidence + 0.15 * cycleScore
    elseif pid == "trust" then
        return 0.40 * rental + 0.30 * housingHealth + 0.30 * cycleScore
    elseif pid == "stock" then
        return 0.25 * gdp + 0.35 * pmi + 0.25 * confidence + 0.15 * cycleScore
    elseif pid == "peFund" then
        return 0.40 * gdp + 0.35 * investment + 0.25 * cycleScore
    end
    return 0.5
end

--- 根据宏观环境计算产品年度目标率；结果始终处于产品建议区间及 1%~3% 硬限制内。
local function targetRate(pid, GD)
    local product = InvestmentService.PRODUCTS[pid]
    if not product then return 0.01 end
    local range = product.targetRange
    local rate = range.min + (range.max - range.min) * macroScore(pid, GD)
    return clamp(rate, math.max(0.01, range.min), math.min(0.03, range.max))
end

local function addRecord(state, record)
    state.transactions[#state.transactions + 1] = record
    trimList(state.transactions, RECORD_LIMIT)
end

local function mirrorLegacy(player, state, pid)
    player.investments = player.investments or {}
    player.investments[pid] = player.investments[pid] or {}
    local legacy = player.investments[pid]
    local holding = productState(state, pid)
    legacy.amount = holding.amount
    if pid == "trust" or pid == "peFund" then
        legacy.lockMonths = holding.lockMonths
    end
end

local function addLegacyHistory(player, GD, pid, amount, action)
    player.investmentHistory = player.investmentHistory or {}
    player.investmentHistory[#player.investmentHistory + 1] = {
        year = GD and GD.year or 0, month = GD and GD.month or 0,
        type = pid, amount = amount, action = action,
    }
    trimList(player.investmentHistory, RECORD_LIMIT)
end

local function ensureYear(GD, state)
    local year = tonumber(GD and GD.year) or 0
    if state.currentYear == year then return end
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local holding = productState(state, pid)
        state.annualTargets[pid] = targetRate(pid, GD)
        holding.yearPrincipal = holding.amount
        holding.yearReturn = 0
        holding.returnCarry = 0
    end
    state.currentYear = year
    state.yearlyProductReturn = 0
end

local function creditReturn(player, state, amount)
    if amount == 0 then return end
    state.totalProductReturn = (state.totalProductReturn or 0) + amount
    state.yearlyProductReturn = (state.yearlyProductReturn or 0) + amount
    -- 兼容旧个人理财累计字段；城市投资收益不在本服务内处理。
    player.totalInvestReturn = (player.totalInvestReturn or 0) + amount
    player.yearlyInvestReturn = (player.yearlyInvestReturn or 0) + amount
    if amount > 0 then
        player.totalIncome = (player.totalIncome or 0) + amount
        player.yearlyIncome = (player.yearlyIncome or 0) + amount
    end
end

local function finalizePreviousYear(GD, player, state)
    local previousYear = state.currentYear
    if not previousYear or previousYear == (tonumber(GD and GD.year) or 0) then return end

    ---@type number
    local totalReturn = 0
    ---@type number
    local totalPrincipal = 0
    local products = {}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local holding = productState(state, pid)
        local principal = math.max(0, holding.yearPrincipal or 0)
        local target = clamp(state.annualTargets[pid] or targetRate(pid, GD), 0.01, 0.03)
        local requiredReturn = principal * target
        local topUp = math.max(0, requiredReturn - holding.yearReturn)
        if topUp > 0 then
            holding.amount = (tonumber(holding.amount) or 0) + topUp
            holding.yearReturn = holding.yearReturn + topUp
            creditReturn(player, state, topUp)
            addRecord(state, {
                kind = "annual_topup", productId = pid, amount = topUp,
                year = previousYear, month = 12, targetRate = target,
            })
            mirrorLegacy(player, state, pid)
        end
        totalReturn = totalReturn + holding.yearReturn
        totalPrincipal = totalPrincipal + principal
        products[#products + 1] = {id = pid, principal = principal, returnAmount = holding.yearReturn, targetRate = target}
    end
    state.annualReports[#state.annualReports + 1] = {
        year = previousYear,
        totalPrincipal = totalPrincipal,
        totalReturn = totalReturn,
        actualRate = totalPrincipal > 0 and clamp(totalReturn / totalPrincipal, 0.01, 0.03) or 0,
        products = products,
    }
    trimList(state.annualReports, REPORT_LIMIT)
end

--- 初始化个人理财状态，并将旧版 investments 与 investmentHistory 安全迁移到新状态。
---@param player table
---@return table state
function InvestmentService.Ensure(player)
    assert(type(player) == "table", "player 必须为 table")
    player.cash = math.max(0, tonumber(player.cash) or 0)
    player.investments = player.investments or {}
    player.investmentHistory = player.investmentHistory or {}
    local state = player.personalInvestment or {}
    state.version = 1
    state.holdings = state.holdings or {}
    state.annualTargets = state.annualTargets or {}
    state.pendingRedemptions = state.pendingRedemptions or {}
    state.transactions = state.transactions or {}
    state.annualReports = state.annualReports or {}
    state.strategyId = InvestmentService.STRATEGIES[state.strategyId] and state.strategyId or "balanced"
    state.totalProductReturn = tonumber(state.totalProductReturn) or 0
    state.yearlyProductReturn = tonumber(state.yearlyProductReturn) or 0

    if not state.migratedLegacy then
        for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
            local legacy = player.investments[pid] or {}
            local holding = productState(state, pid)
            holding.amount = math.max(holding.amount, tonumber(legacy.amount) or 0)
            if pid == "trust" or pid == "peFund" then
                holding.lockMonths = math.max(holding.lockMonths, math.floor(tonumber(legacy.lockMonths) or 0))
            end
        end
        local startAt = math.max(1, #player.investmentHistory - RECORD_LIMIT + 1)
        for index = startAt, #player.investmentHistory do
            local legacy = player.investmentHistory[index]
            if type(legacy) == "table" then
                state.transactions[#state.transactions + 1] = {
                    kind = "legacy", productId = legacy.type, amount = legacy.amount or 0,
                    action = legacy.action, year = legacy.year, month = legacy.month,
                }
            end
        end
        state.migratedLegacy = true
    end

    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        productState(state, pid)
        mirrorLegacy(player, state, pid)
    end
    trimList(state.transactions, RECORD_LIMIT)
    trimList(state.pendingRedemptions, RECORD_LIMIT)
    trimList(state.annualReports, REPORT_LIMIT)
    player.personalInvestment = state
    return state
end

--- 买入个人理财产品。只会扣减个人现金，不会透支或影响任何公司字段。
---@param GD table
---@param pid string
---@param amount number
---@return boolean ok
---@return string|table result
function InvestmentService.Buy(GD, pid, amount)
    local player = GD and GD.player
    if not player then return false, "未初始化个人数据" end
    local product = InvestmentService.PRODUCTS[pid]
    if not product then return false, "未知理财产品" end
    local state = InvestmentService.Ensure(player)
    finalizePreviousYear(GD, player, state)
    ensureYear(GD, state)

    amount = roundDown(tonumber(amount) or 0)
    if amount <= 0 then return false, "金额必须大于0" end
    if amount < product.minAmount then return false, string.format("最低买入%.0f万", product.minAmount) end
    if amount > player.cash then return false, "个人现金不足" end

    local holding = productState(state, pid)
    player.cash = player.cash - amount
    holding.amount = holding.amount + amount
    holding.yearPrincipal = holding.yearPrincipal + amount
    if product.lockMonths > 0 then holding.lockMonths = product.lockMonths end
    state.annualTargets[pid] = clamp(state.annualTargets[pid] or targetRate(pid, GD), 0.01, 0.03)
    mirrorLegacy(player, state, pid)
    addRecord(state, {kind = "buy", productId = pid, amount = amount, year = GD.year, month = GD.month})
    addLegacyHistory(player, GD, pid, amount, "buy")
    return true, {amount = amount, holdingAmount = holding.amount, lockMonths = holding.lockMonths}
end

--- 赎回个人理财产品。存款即时到账，货基/股票及债基/指数/REITs 在下一游戏月清算。
---@param GD table
---@param pid string
---@param amount number
---@return boolean ok
---@return string|table result
function InvestmentService.Redeem(GD, pid, amount)
    local player = GD and GD.player
    if not player then return false, "未初始化个人数据" end
    local product = InvestmentService.PRODUCTS[pid]
    if not product then return false, "未知理财产品" end
    local state = InvestmentService.Ensure(player)
    finalizePreviousYear(GD, player, state)
    ensureYear(GD, state)

    local holding = productState(state, pid)
    amount = roundDown(tonumber(amount) or 0)
    if amount <= 0 then return false, "金额必须大于0" end
    if amount > holding.amount then return false, "持有金额不足" end
    if product.lockMonths > 0 and holding.lockMonths > 0 then
        return false, string.format("%s锁定中，还剩%d个月", product.name, holding.lockMonths)
    end

    if product.liquidityMonths > 0 and #state.pendingRedemptions >= RECORD_LIMIT then
        return false, "待清算赎回过多，请等待到账后再操作"
    end

    local beforeAmount = holding.amount
    holding.amount = holding.amount - amount
    if beforeAmount > 0 then
        local ratio = amount / beforeAmount
        holding.yearPrincipal = math.max(0, holding.yearPrincipal * (1 - ratio))
        holding.yearReturn = holding.yearReturn * (1 - ratio)
    end
    mirrorLegacy(player, state, pid)

    local result = {amount = amount, pending = false, dueMonth = nil}
    if product.liquidityMonths <= 0 then
        player.cash = player.cash + amount
        addRecord(state, {kind = "redeem", productId = pid, amount = amount, year = GD.year, month = GD.month, status = "settled"})
    else
        local dueSerial = currentSerial(GD) + product.liquidityMonths
        state.pendingRedemptions[#state.pendingRedemptions + 1] = {
            productId = pid, amount = amount, dueSerial = dueSerial,
            requestYear = GD.year, requestMonth = GD.month,
        }
        addRecord(state, {kind = "redeem", productId = pid, amount = amount, year = GD.year, month = GD.month, status = "pending", dueSerial = dueSerial})
        result.pending, result.dueMonth = true, product.liquidityMonths
    end
    addLegacyHistory(player, GD, pid, amount, "redeem")
    return true, result
end

--- 执行月度收益、锁定倒计时和待清算赎回到账；同一游戏月重复调用不会重复结算。
---@param GD table
---@return table result
function InvestmentService.MonthlyUpdate(GD)
    local player = GD and GD.player
    if not player then return {processed = false, reason = "未初始化个人数据"} end
    local state = InvestmentService.Ensure(player)
    finalizePreviousYear(GD, player, state)
    ensureYear(GD, state)
    local serial = currentSerial(GD)
    if state.lastMonthlySerial == serial then return {processed = false, reason = "本月已结算"} end

    ---@type number
    local settled = 0
    ---@type number
    local returnTotal = 0
    local remaining = {}
    for _, pending in ipairs(state.pendingRedemptions) do
        if (tonumber(pending.dueSerial) or math.huge) <= serial then
            local amount = math.max(0, tonumber(pending.amount) or 0)
            player.cash = player.cash + amount
            settled = settled + amount
            addRecord(state, {kind = "settlement", productId = pending.productId, amount = amount, year = GD.year, month = GD.month})
        else
            remaining[#remaining + 1] = pending
        end
    end
    state.pendingRedemptions = remaining

    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local product = InvestmentService.PRODUCTS[pid]
        local holding = productState(state, pid)
        if product.lockMonths > 0 and holding.lockMonths > 0 then
            holding.lockMonths = holding.lockMonths - 1
        end
        if holding.amount > 0 then
            local target = clamp(state.annualTargets[pid] or targetRate(pid, GD), 0.01, 0.03)
            state.annualTargets[pid] = target
            local principal = holding.yearPrincipal
            local remainingTarget = math.max(0, principal * target - holding.yearReturn)
            local _, cycle = macroData(GD)
            local volatile = ({deposit = 0.05, moneyFund = 0.10, bond = 0.25, reits = 0.55, indexFund = 0.80, trust = 0.35, stock = 1.00, peFund = 0.60})[pid] or 0.25
            local cycleBias = ({boom = 0.12, recovery = 0.06, stable = 0, slowdown = -0.04, recession = -0.10, depression = -0.15})[cycle] or 0
            local fluctuation = ((math.random() * 2 - 1) * 0.22 * volatile) + cycleBias * volatile
            local rawReturn = holding.amount * (target / 12) * (1 + fluctuation) + holding.returnCarry
            -- 权益类可有轻微负收益；全年累计收益仍由年度目标上限约束。
            if volatile >= 0.55 and math.random() < 0.08 * volatile then
                rawReturn = rawReturn - holding.amount * (0.0005 + 0.0015 * volatile)
            end
            local delta
            if rawReturn >= 0 then
                delta = math.floor(rawReturn * MONEY_PRECISION) / MONEY_PRECISION
            else
                delta = math.ceil(rawReturn * MONEY_PRECISION) / MONEY_PRECISION
            end
            holding.returnCarry = (tonumber(rawReturn) or 0) - (tonumber(delta) or 0)
            if delta > remainingTarget then delta = remainingTarget end
            if holding.amount + delta < 0 then delta = -holding.amount end
            if delta ~= 0 then
                holding.amount = holding.amount + delta
                holding.yearReturn = holding.yearReturn + delta
                returnTotal = returnTotal + delta
                creditReturn(player, state, delta)
                addRecord(state, {kind = "return", productId = pid, amount = delta, year = GD.year, month = GD.month, targetRate = target})
            end
        end
        mirrorLegacy(player, state, pid)
    end

    state.lastMonthlySerial = serial
    trimList(state.transactions, RECORD_LIMIT)
    return {processed = true, settled = settled, returnAmount = returnTotal}
end

--- 获取个人理财摘要，包括持仓、待到账赎回和独立收益字段。
---@param GD table
---@return table summary
function InvestmentService.GetSummary(GD)
    local player = GD and GD.player
    if not player then return {total = 0, pendingRedemptions = 0, yearlyProductReturn = 0, totalProductReturn = 0} end
    local state = InvestmentService.Ensure(player)
    ensureYear(GD, state)
    local total, pending = 0, 0
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do total = total + productState(state, pid).amount end
    for _, item in ipairs(state.pendingRedemptions) do pending = pending + (item.amount or 0) end
    return {
        total = total, pendingRedemptions = pending, availableCash = player.cash,
        yearlyProductReturn = state.yearlyProductReturn, totalProductReturn = state.totalProductReturn,
        strategyId = state.strategyId, currentYear = state.currentYear,
    }
end

--- 获取产品明细及受宏观影响但已硬钳制的目标与年化预测。
---@param GD table
---@return table detail
function InvestmentService.GetDetail(GD)
    local player = GD and GD.player
    if not player then return {total = 0, products = {}} end
    local state = InvestmentService.Ensure(player)
    ensureYear(GD, state)
    local total, products = 0, {}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local product, holding = InvestmentService.PRODUCTS[pid], productState(state, pid)
        local target = clamp(state.annualTargets[pid] or targetRate(pid, GD), 0.01, 0.03)
        local actual = holding.yearPrincipal > 0 and holding.yearReturn / holding.yearPrincipal or 0
        local month = clamp(tonumber(GD.month) or 1, 1, 12)
        local projected = holding.yearPrincipal > 0 and actual * 12 / month or target
        total = total + holding.amount
        products[#products + 1] = {
            id = pid, name = product.name, desc = product.desc, amount = holding.amount,
            minAmount = product.minAmount, riskTier = product.riskTier,
            targetRate = target, projectedAnnualRate = clamp(projected, 0.01, 0.03),
            yearlyReturn = holding.yearReturn, lockMonths = holding.lockMonths,
            liquidityMonths = product.liquidityMonths,
        }
    end
    return {total = total, products = products, diversification = InvestmentService.GetDiversification(GD), strategyId = state.strategyId}
end

--- 计算个人理财组合的品种、风险层级和集中度多元化评分。
---@param GD table
---@return table diversification
function InvestmentService.GetDiversification(GD)
    local player = GD and GD.player
    if not player then return {score = 0, level = "无持仓", tierWeights = {low = 0, medium = 0, high = 0}} end
    local state = InvestmentService.Ensure(player)
    local total, active, maximum, topPid = 0, 0, 0, nil
    local tiers = {low = 0, medium = 0, high = 0}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local amount = productState(state, pid).amount
        total = total + amount
        if amount > 0 then active = active + 1 end
        if amount > maximum then maximum, topPid = amount, pid end
        tiers[InvestmentService.PRODUCTS[pid].riskTier] = tiers[InvestmentService.PRODUCTS[pid].riskTier] + amount
    end
    if total <= 0 then return {score = 0, level = "无持仓", tierWeights = {low = 0, medium = 0, high = 0}} end
    local weights = {low = tiers.low / total, medium = tiers.medium / total, high = tiers.high / total}
    local deviation = math.abs(weights.low - 1 / 3) + math.abs(weights.medium - 1 / 3) + math.abs(weights.high - 1 / 3)
    local varietyScore = math.floor(active / #InvestmentService.PRODUCT_ORDER * 40)
    local balanceScore = math.max(0, math.floor(35 * (1 - deviation / (4 / 3))))
    local concentration = maximum / total
    local concentrationScore = concentration > 0.80 and 0 or (concentration > 0.60 and 10 or (concentration > 0.40 and 18 or 25))
    local score = varietyScore + balanceScore + concentrationScore
    return {
        score = score, level = score >= 80 and "优秀" or (score >= 60 and "良好" or (score >= 40 and "一般" or "偏弱")),
        tierWeights = weights, concentration = concentration, topProduct = topPid,
    }
end

--- 返回最近交易、收益与清算记录，默认按发生时间倒序。
---@param GD table
---@return table[] transactions
function InvestmentService.GetTransactions(GD)
    local player = GD and GD.player
    if not player then return {} end
    local state = InvestmentService.Ensure(player)
    local result = {}
    for index = #state.transactions, 1, -1 do result[#result + 1] = state.transactions[index] end
    return result
end

--- 设置当前资产配置策略。
---@param GD table
---@param strategyId string
---@return boolean ok
---@return string|table result
function InvestmentService.SetStrategy(GD, strategyId)
    local player = GD and GD.player
    if not player then return false, "未初始化个人数据" end
    local strategy = InvestmentService.STRATEGIES[strategyId]
    if not strategy then return false, "未知策略" end
    local state = InvestmentService.Ensure(player)
    state.strategyId = strategyId
    return true, strategy
end

--- 生成按当前或指定策略拆分的买入计划。
---@param GD table
---@param amount number
---@return table plan
function InvestmentService.GetStrategyPlan(GD, amount)
    local player = GD and GD.player
    local state = player and InvestmentService.Ensure(player) or {strategyId = "balanced"}
    local strategyId = state.strategyId or "balanced"
    ---@type PersonalInvestmentStrategy
    local strategy = InvestmentService.STRATEGIES[strategyId] or InvestmentService.STRATEGIES.balanced
    amount = roundDown(tonumber(amount) or 0)
    local items = {}
    ---@type number
    local allocated = 0
    for index, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local planned = index == #InvestmentService.PRODUCT_ORDER and roundDown(amount - allocated) or roundDown(amount * strategy.weights[pid])
        allocated = allocated + planned
        items[#items + 1] = {productId = pid, weight = strategy.weights[pid], amount = planned, minAmount = InvestmentService.PRODUCTS[pid].minAmount}
    end
    return {strategyId = strategy.id, name = strategy.name, amount = amount, items = items}
end

--- 依照策略只买入，不会自动赎回；现金不足时按可用个人现金安全停止。
---@param GD table
---@param amount number
---@return boolean ok
---@return table|string result
function InvestmentService.ExecuteStrategy(GD, amount)
    local player = GD and GD.player
    if not player then return false, "未初始化个人数据" end
    local requested = roundDown(tonumber(amount) or 0)
    if requested <= 0 then return false, "金额必须大于0" end
    local usable = math.min(requested, player.cash)
    if usable <= 0 then return false, "个人现金不足" end
    local plan = InvestmentService.GetStrategyPlan(GD, usable)
    local result, invested = {}, 0
    for _, item in ipairs(plan.items) do
        if item.amount >= item.minAmount and item.amount > 0 then
            local ok, info = InvestmentService.Buy(GD, item.productId, item.amount)
            result[#result + 1] = {productId = item.productId, amount = item.amount, ok = ok, info = info}
            if ok then invested = invested + item.amount end
        end
    end
    -- 未达到各产品最低门槛的零散资金安全停留在个人现金，不作隐式挪用。
    return invested > 0, {requested = requested, invested = invested, remainingCash = player.cash, actions = result}
end

--- 将超配的可流动持仓赎回，并以已到账个人现金补足低配产品；锁定产品不会被强制赎回。
---@param GD table
---@return boolean ok
---@return table|string result
function InvestmentService.Rebalance(GD)
    local player = GD and GD.player
    if not player then return false, "未初始化个人数据" end
    local state = InvestmentService.Ensure(player)
    ensureYear(GD, state)
    local strategyId = state.strategyId or "balanced"
    ---@type PersonalInvestmentStrategy
    local strategy = InvestmentService.STRATEGIES[strategyId] or InvestmentService.STRATEGIES.balanced
    local total = 0
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do total = total + productState(state, pid).amount end
    if total <= 0 then return false, "暂无可调仓持仓" end

    local result = {redemptions = {}, purchases = {}, pendingCash = 0, invested = 0}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local product, holding = InvestmentService.PRODUCTS[pid], productState(state, pid)
        local desired = total * strategy.weights[pid]
        local excess = roundDown(math.max(0, holding.amount - desired))
        if excess > 0 and product.lockMonths == 0 then
            local ok, info = InvestmentService.Redeem(GD, pid, excess)
            if ok then
                result.redemptions[#result.redemptions + 1] = {productId = pid, amount = excess, info = info}
                if info.pending then
                    result.pendingCash = (tonumber(result.pendingCash) or 0) + excess
                end
            end
        end
    end
    -- 仅使用实际可用个人现金买入，延迟清算款不会提前透支。
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local holding, product = productState(state, pid), InvestmentService.PRODUCTS[pid]
        local desired = total * strategy.weights[pid]
        local deficit = roundDown(math.max(0, desired - holding.amount))
        if deficit >= product.minAmount and deficit > 0 and player.cash >= deficit then
            local ok, info = InvestmentService.Buy(GD, pid, deficit)
            if ok then
                result.purchases[#result.purchases + 1] = {productId = pid, amount = deficit, info = info}
                result.invested = (tonumber(result.invested) or 0) + deficit
            end
        end
    end
    return true, result
end

--- 获取已完成年度报告及当前年度实时统计。
---@param GD table
---@return table report
function InvestmentService.GetAnnualReport(GD)
    local player = GD and GD.player
    if not player then return {current = nil, history = {}} end
    local state = InvestmentService.Ensure(player)
    finalizePreviousYear(GD, player, state)
    ensureYear(GD, state)
    local principal, earned, products = 0, 0, {}
    for _, pid in ipairs(InvestmentService.PRODUCT_ORDER) do
        local holding = productState(state, pid)
        local target = clamp(state.annualTargets[pid] or targetRate(pid, GD), 0.01, 0.03)
        principal, earned = principal + holding.yearPrincipal, earned + holding.yearReturn
        products[#products + 1] = {id = pid, principal = holding.yearPrincipal, returnAmount = holding.yearReturn, targetRate = target}
    end
    return {
        current = {
            year = state.currentYear, totalPrincipal = principal, totalReturn = earned,
            actualRate = principal > 0 and earned / principal or 0,
            products = products,
        },
        history = state.annualReports,
    }
end

return InvestmentService
