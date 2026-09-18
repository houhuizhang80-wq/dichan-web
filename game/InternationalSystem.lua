-- ============================================================================
-- InternationalSystem.lua - 集团海外事业部、跨境投资与独立账务
-- ============================================================================

local INS = {}

INS.VERSION = 2
INS.BASE_CURRENCY = "CNY"
INS.MODE_ORDER = {"direct_land", "existing_asset", "joint_venture", "fund_reits"}
INS.MODE_DEFS = {
    direct_land = {id = "direct_land", name = "直接拿地自主开发", shortName = "自主开发", desc = "完成国别尽调后拿地、建设并销售或持有出租。", baseRisk = 0.24, duration = 30, capacity = 2},
    existing_asset = {id = "existing_asset", name = "收购存量物业", shortName = "存量物业", desc = "购买写字楼、公寓或酒店，获取租金与资产增值。", baseRisk = 0.14, duration = 1, capacity = 1},
    joint_venture = {id = "joint_venture", name = "联合本地开发商", shortName = "联合开发", desc = "与当地合作方共同开发并按权益分配收益。", baseRisk = 0.18, duration = 24, capacity = 1},
    fund_reits = {id = "fund_reits", name = "海外地产基金/REITs", shortName = "基金/REITs", desc = "财务投资并获取分红与净值变化。", baseRisk = 0.12, duration = 12, capacity = 1},
}

INS.COUNTRIES = {
    {id = "us", name = "西澜联邦", currency = "USD", fxToCny = 7.20, foreignLand = true, taxRate = 0.21, withholdingRate = 0.10, propertyTaxRate = 0.012, transferTaxRate = 0.025, marketGrowth = 0.045, vacancy = 0.08, risk = 0.20, baseReputation = 45, capacity = 2, localPartnerBonus = 0.05, desc = "市场成熟、流动性较好，税务和合规成本较高。"},
    {id = "uae", name = "沙洲联合酋长国", currency = "AED", fxToCny = 1.96, foreignLand = false, taxRate = 0.09, withholdingRate = 0.05, propertyTaxRate = 0.004, transferTaxRate = 0.04, marketGrowth = 0.070, vacancy = 0.06, risk = 0.28, baseReputation = 42, capacity = 2, localPartnerBonus = 0.10, desc = "高增长国际枢纽，部分区域需要本地合作方持有土地。"},
    {id = "japan", name = "东瀛岛国", currency = "JPY", fxToCny = 0.050, foreignLand = true, taxRate = 0.23, withholdingRate = 0.10, propertyTaxRate = 0.014, transferTaxRate = 0.03, marketGrowth = 0.025, vacancy = 0.055, risk = 0.15, baseReputation = 48, capacity = 2, localPartnerBonus = 0.04, desc = "产权规则清晰、租赁市场稳定，但长期增长相对温和。"},
    {id = "singapore", name = "狮城联邦", currency = "SGD", fxToCny = 5.35, foreignLand = false, taxRate = 0.17, withholdingRate = 0.08, propertyTaxRate = 0.010, transferTaxRate = 0.035, marketGrowth = 0.040, vacancy = 0.045, risk = 0.12, baseReputation = 50, capacity = 2, localPartnerBonus = 0.08, desc = "监管透明，外资持有和交易税费较严格。"},
}

INS.EVENT_DEFS = {
    policy_incentive = {id = "policy_incentive", name = "招商引资优惠", kind = "good", duration = 6, cashFactor = 0.92, growthBonus = 0.04, desc = "当地提供税费减免和审批便利。"},
    infrastructure = {id = "infrastructure", name = "基建落地", kind = "good", duration = 8, cashFactor = 0.95, growthBonus = 0.06, desc = "周边基础设施改善，资产需求上升。"},
    capital_restriction = {id = "capital_restriction", name = "外资政策收紧", kind = "bad", duration = 6, cashFactor = 1.18, growthBonus = -0.08, desc = "外资税费上升，部分资产暂时限制出售。"},
    strike = {id = "strike", name = "社会动荡与罢工", kind = "bad", duration = 3, cashFactor = 1.25, growthBonus = -0.05, desc = "项目效率和物业收入下降。"},
    disaster = {id = "disaster", name = "自然灾害", kind = "bad", duration = 2, cashFactor = 1.35, growthBonus = -0.04, desc = "物业维修和保险自付成本上升。"},
    recession = {id = "recession", name = "本地经济衰退", kind = "bad", duration = 8, cashFactor = 1.10, growthBonus = -0.12, desc = "房价下跌、空置率上升。"},
}

INS.TEAM_ROLES = {
    {id = "business", name = "海外商务", cost = 160, monthly = 18, risk = 0.05, efficiency = 0.04},
    {id = "legal", name = "跨境法务", cost = 220, monthly = 24, risk = 0.10, efficiency = 0.03},
    {id = "finance", name = "海外财务审计", cost = 190, monthly = 22, risk = 0.06, efficiency = 0.04},
    {id = "manager", name = "本地项目经理", cost = 260, monthly = 30, risk = 0.12, efficiency = 0.08},
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function money(value)
    return math.floor((tonumber(value) or 0) * 100) / 100
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function bool(value)
    return value == true or value == 1 or value == "true"
end

local function periodKey(GD, year, month)
    return tostring(year or GD.year or 0) .. "-" .. tostring(month or GD.month or 0)
end

local function currentPeriod(GD)
    return tostring(GD.year or 0) .. "-" .. tostring(GD.month or 0)
end

local function findCountry(countryId)
    for _, country in ipairs(INS.COUNTRIES) do
        if country.id == countryId then return country end
    end
    return nil
end

local function findById(list, id)
    for _, item in ipairs(list or {}) do
        if item.id == id then return item end
    end
    return nil
end

local function removeById(list, id)
    for index, item in ipairs(list or {}) do
        if item.id == id then
            table.remove(list, index)
            return item
        end
    end
    return nil
end

local function newId(data, prefix)
    local id = prefix .. "_" .. tostring(data.nextId or 1)
    data.nextId = (data.nextId or 1) + 1
    return id
end

local function logTransaction(GD, data, txType, amountCny, description, extra)
    local tx = {
        id = "intl_tx_" .. tostring(data.nextTransactionId or 1),
        type = txType,
        amountCny = money(amountCny),
        description = tostring(description or "国际业务交易"),
        period = currentPeriod(GD),
        year = GD.year,
        month = GD.month,
    }
    data.nextTransactionId = (data.nextTransactionId or 1) + 1
    for key, value in pairs(extra or {}) do tx[key] = value end
    data.transactions[#data.transactions + 1] = tx
    while #data.transactions > 240 do table.remove(data.transactions, 1) end
    return tx
end

local function logTax(GD, data, countryId, taxType, amountCny, objectId, description)
    amountCny = money(amountCny)
    if amountCny <= 0 then return end
    data.taxRecords[#data.taxRecords + 1] = {
        id = newId(data, "intl_tax"), countryId = countryId, type = taxType,
        amountCny = amountCny, objectId = objectId, description = description,
        period = currentPeriod(GD),
    }
    while #data.taxRecords > 160 do table.remove(data.taxRecords, 1) end
end

local function getEventFactors(data, countryId)
    local cashFactor = 1
    local growthBonus = 0
    local blockedExit = false
    local efficiency = 1
    for _, event in ipairs(data.events or {}) do
        if event.countryId == countryId and (event.remainMonths or 0) > 0 then
            cashFactor = cashFactor * (tonumber(event.cashFactor) or 1)
            growthBonus = growthBonus + (tonumber(event.growthBonus) or 0)
            if event.eventType == "capital_restriction" then blockedExit = true end
            if event.kind == "bad" then efficiency = efficiency * 0.70 else efficiency = efficiency * 1.08 end
        end
    end
    return cashFactor, growthBonus, blockedExit, efficiency
end

local function divisionAccount(data, countryId)
    local country = findCountry(countryId)
    if not country then return nil end
    local division = data.division
    local account = division.foreignAccounts[countryId]
    if type(account) ~= "table" then
        account = {
            id = "fx_account_" .. tostring(division.nextAccountId or 1),
            countryId = countryId, currency = country.currency, balanceLocal = 0,
            opened = false, openedPeriod = nil,
        }
        division.nextAccountId = (division.nextAccountId or 1) + 1
        division.foreignAccounts[countryId] = account
    end
    account.balanceLocal = money(account.balanceLocal)
    account.opened = bool(account.opened) or account.balanceLocal > 0
    return account
end

local function foreignAccountCny(data, countryId)
    local country = findCountry(countryId)
    local account = country and divisionAccount(data, countryId) or nil
    if not country or not account then return 0 end
    return money(account.balanceLocal * (data.fxRates[countryId] or country.fxToCny))
end

local function putForeignCash(data, countryId, amountCny)
    amountCny = money(amountCny)
    local account = divisionAccount(data, countryId)
    local country = findCountry(countryId)
    if amountCny <= 0 or not account or not country then return false end
    local fx = data.fxRates[countryId] or country.fxToCny
    account.balanceLocal = money(account.balanceLocal + amountCny / math.max(0.0001, fx))
    account.opened = true
    return true
end

local function takeCash(data, amountCny, countryId)
    amountCny = money(amountCny)
    if amountCny <= 0 then return true end
    local division = data.division
    local accountCny = countryId and foreignAccountCny(data, countryId) or 0
    local fromAccount = math.min(accountCny, amountCny)
    if fromAccount > 0 then
        local account = divisionAccount(data, countryId)
        local country = findCountry(countryId)
        local fx = data.fxRates[countryId] or country.fxToCny
        account.balanceLocal = money(account.balanceLocal - fromAccount / fx)
    end
    local remainder = money(amountCny - fromAccount)
    if remainder > (division.treasuryCny or 0) then
        if fromAccount > 0 then putForeignCash(data, countryId, fromAccount) end
        return false
    end
    division.treasuryCny = money((division.treasuryCny or 0) - remainder)
    return true
end

local function spendOperating(GD, data, amountCny, description, txType, countryId, objectId)
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    amountCny = money(amountCny)
    if amountCny <= 0 then return true end
    if not takeCash(data, amountCny, countryId) then
        return false, "海外事业部可用资金不足，请先由集团注资或兑换外汇"
    end
    data.division.paidExpenseCny = money((data.division.paidExpenseCny or 0) + amountCny)
    data.division.totalExpenseCny = money((data.division.totalExpenseCny or 0) + amountCny)
    logTransaction(GD, data, txType or "international_expense", -amountCny, description, {
        countryId = countryId, objectId = objectId, classification = "expense",
    })
    return true
end

local function spendInvestment(GD, data, amountCny, description, txType, countryId, objectId)
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    amountCny = money(amountCny)
    if amountCny <= 0 then return false, "请输入有效投资金额" end
    if not takeCash(data, amountCny, countryId) then
        return false, "海外事业部可用资金不足，请先由集团注资或兑换外汇"
    end
    logTransaction(GD, data, txType, -amountCny, description, {
        countryId = countryId, objectId = objectId, classification = "investment",
    })
    return true
end

local function receiveIncome(GD, data, countryId, amountCny, description, txType, objectId, recognizedIncomeCny)
    amountCny = money(amountCny)
    if amountCny <= 0 or not data.division.active then return 0 end
    local recognizedIncome = money(recognizedIncomeCny == nil and amountCny or recognizedIncomeCny)
    if countryId and findCountry(countryId) then
        putForeignCash(data, countryId, amountCny)
    else
        data.division.treasuryCny = money((data.division.treasuryCny or 0) + amountCny)
    end
    if data.monthlyProcessingSerial then
        data._periodIncome = money((data._periodIncome or 0) + recognizedIncome)
    else
        data.division.pendingIncomeCny = money((data.division.pendingIncomeCny or 0) + recognizedIncome)
    end
    logTransaction(GD, data, txType or "international_income", amountCny, description, {
        countryId = countryId, objectId = objectId, classification = recognizedIncome == amountCny and "income" or "capital_return", recognizedIncomeCny = recognizedIncome,
    })
    return amountCny
end

local function archiveBusiness(data, item, exitType, proceedsCny, profitCny, taxCny, period)
    local record = {}
    for key, value in pairs(item or {}) do record[key] = value end
    record.status = "exited"
    record.exitType = exitType
    record.proceedsCny = money(proceedsCny)
    record.realizedProfitCny = money(profitCny)
    record.taxCny = money(taxCny)
    record.exitPeriod = period
    data.history[#data.history + 1] = record
    while #data.history > 120 do table.remove(data.history, 1) end
end

local function activeExposure(data, countryId)
    local total = 0
    for _, item in ipairs(data.projects or {}) do if item.countryId == countryId then total = total + (item.investedCny or 0) end end
    for _, item in ipairs(data.assets or {}) do if item.countryId == countryId then total = total + (item.investedCny or 0) end end
    for _, item in ipairs(data.funds or {}) do if item.countryId == countryId then total = total + (item.navCny or item.investedCny or 0) end end
    for _, loan in ipairs(data.division.bankLoans or {}) do if loan.countryId == countryId then total = total + (loan.remainingCny or 0) end end
    return math.max(1, total)
end

local function fxFactor(data, countryId, entryFx)
    local country = findCountry(countryId)
    local currentFx = data.fxRates[countryId] or (country and country.fxToCny) or entryFx or 1
    local baseFx = tonumber(entryFx) or currentFx
    if baseFx <= 0 then return 1 end
    local hedgeAmount = 0
    for _, hedge in ipairs(data.hedges or {}) do
        if hedge.countryId == countryId and (hedge.remainMonths or 0) > 0 then
            hedgeAmount = hedgeAmount + (hedge.amountCny or 0)
        end
    end
    local coverage = clamp(hedgeAmount / activeExposure(data, countryId), 0, 1)
    return 1 + (currentFx / baseFx - 1) * (1 - coverage)
end

local function recalcDerived(data)
    local used = 0
    local invested = 0
    local maxId = 0
    for _, item in ipairs(data.projects) do
        local def = INS.MODE_DEFS[item.mode]
        used = used + (def and def.capacity or 1)
        invested = invested + math.max(0, tonumber(item.investedCny) or 0)
    end
    for _, item in ipairs(data.assets) do
        used = used + 1
        invested = invested + math.max(0, tonumber(item.investedCny) or 0)
    end
    for _, item in ipairs(data.funds) do
        used = used + 1
        invested = invested + math.max(0, tonumber(item.investedCny) or 0)
    end
    for _, list in ipairs({data.projects, data.assets, data.funds, data.history, data.events, data.hedges}) do
        for _, item in ipairs(list) do
            local n = tonumber(tostring(item.id or ""):match("(%d+)$")) or 0
            maxId = math.max(maxId, n)
        end
    end
    data.capacityUsed = used
    data.activeInvestedCny = money(invested)
    data.nextId = math.max(math.floor(tonumber(data.nextId) or 1), maxId + 1)
    local debt = 0
    for _, loan in ipairs(data.division.bankLoans) do debt = debt + math.max(0, tonumber(loan.remainingCny) or 0) end
    data.division.totalDebtCny = money(debt)
end

function INS.CreateDefaultData()
    return {
        version = INS.VERSION, active = true, selectedCountry = "us",
        countries = {}, dueDiligence = {}, projects = {}, assets = {}, funds = {},
        loans = {}, events = {}, transactions = {}, taxRecords = {}, history = {},
        team = {business = 0, legal = 0, finance = 0, manager = 0},
        capacityLevel = 1, capacityUsed = 0, activeInvestedCny = 0,
        fxRates = {}, hedges = {},
        division = {
            active = false, name = "集团海外事业部", registeredCapitalCny = 0,
            treasuryCny = 0, retainedEarningsCny = 0, totalExpenseCny = 0,
            monthlyIncomeCny = 0, monthlyExpenseCny = 0, totalDebtCny = 0,
            pendingIncomeCny = 0, pendingExpenseCny = 0,
            foreignAccounts = {}, bankDeposits = {}, bankLoans = {},
            nextAccountId = 1, nextDepositId = 1, nextLoanId = 1,
        },
        nextId = 1, nextTransactionId = 1, lastMonthlySerial = nil,
        totalInvestedCny = 0, totalProfitCny = 0,
        lastMonthlyIncome = 0, lastMonthlyExpense = 0,
    }
end

local function normalizeLoan(loan, fallbackId)
    loan.id = loan.id or fallbackId
    loan.countryId = findCountry(loan.countryId) and loan.countryId or "us"
    loan.amountCny = money(loan.amountCny or loan.amount)
    loan.remainingCny = money(loan.remainingCny or loan.amountCny)
    loan.rate = clamp(loan.rate or 0.07, 0, 1)
    loan.remainMonths = math.max(0, math.floor(tonumber(loan.remainMonths) or 12))
    loan.accruedInterest = money(loan.accruedInterest)
    loan.status = loan.status or (loan.remainMonths <= 0 and "overdue" or "active")
    return loan
end

function INS.EnsureFields(GD)
    if type(GD.international) ~= "table" then GD.international = INS.CreateDefaultData() end
    local data = GD.international
    local defaults = INS.CreateDefaultData()
    for _, key in ipairs({"countries", "dueDiligence", "projects", "assets", "funds", "loans", "events", "transactions", "taxRecords", "history", "team", "fxRates", "hedges"}) do
        if type(data[key]) ~= "table" then data[key] = defaults[key] end
    end
    if type(data.division) ~= "table" then data.division = defaults.division end
    local division = data.division
    for key, value in pairs(defaults.division) do
        if division[key] == nil then division[key] = value end
    end
    division.name = tostring(division.name or "集团海外事业部")
    division.active = bool(division.active)
    for _, key in ipairs({"registeredCapitalCny", "treasuryCny", "retainedEarningsCny", "totalExpenseCny", "monthlyIncomeCny", "monthlyExpenseCny", "totalDebtCny", "pendingIncomeCny", "pendingExpenseCny"}) do
        division[key] = money(division[key])
    end
    for _, key in ipairs({"foreignAccounts", "bankDeposits", "bankLoans"}) do if type(division[key]) ~= "table" then division[key] = {} end end
    division.nextAccountId = math.max(1, math.floor(tonumber(division.nextAccountId) or 1))
    division.nextDepositId = math.max(1, math.floor(tonumber(division.nextDepositId) or 1))
    division.nextLoanId = math.max(1, math.floor(tonumber(division.nextLoanId) or 1))
    for _, role in ipairs(INS.TEAM_ROLES) do data.team[role.id] = math.max(0, math.floor(tonumber(data.team[role.id]) or 0)) end
    data.capacityLevel = math.max(1, math.floor(tonumber(data.capacityLevel) or 1))
    data.selectedCountry = findCountry(data.selectedCountry) and data.selectedCountry or "us"
    data.nextId = math.max(1, math.floor(tonumber(data.nextId) or 1))
    data.nextTransactionId = math.max(1, math.floor(tonumber(data.nextTransactionId) or 1))
    data.totalInvestedCny = money(data.totalInvestedCny)
    data.totalProfitCny = money(data.totalProfitCny)
    data.lastMonthlyIncome = money(data.lastMonthlyIncome)
    data.lastMonthlyExpense = money(data.lastMonthlyExpense)
    for _, country in ipairs(INS.COUNTRIES) do
        local state = data.countries[country.id]
        if type(state) ~= "table" then state = {}; data.countries[country.id] = state end
        state.countryId = country.id
        state.reputation = clamp(state.reputation or country.baseReputation, 0, 100)
        state.investedCny = money(state.investedCny)
        state.profitCny = money(state.profitCny)
        state.active = state.active ~= false
        data.fxRates[country.id] = math.max(0.0001, tonumber(data.fxRates[country.id]) or country.fxToCny)
        divisionAccount(data, country.id)
    end
    for _, item in ipairs(data.projects) do
        item.mode = INS.MODE_DEFS[item.mode] and item.mode or "direct_land"
        item.countryId = findCountry(item.countryId) and item.countryId or "us"
        item.investedCny = money(item.investedCny)
        item.progress = clamp(item.progress, 0, 1)
        item.totalMonths = math.max(1, math.floor(tonumber(item.totalMonths) or INS.MODE_DEFS[item.mode].duration))
        item.remainMonths = math.max(0, math.floor(tonumber(item.remainMonths) or item.totalMonths))
        item.status = item.status or "active"
    end
    for _, item in ipairs(data.assets) do
        item.countryId = findCountry(item.countryId) and item.countryId or "us"
        item.investedCny = money(item.investedCny)
        item.monthlyRentCny = money(item.monthlyRentCny or item.investedCny * 0.006)
        item.occupancy = clamp(item.occupancy or 0.82, 0.2, 1)
        item.remainLockMonths = math.max(0, math.floor(tonumber(item.remainLockMonths) or 0))
        item.mode = "existing_asset"
    end
    for _, item in ipairs(data.funds) do
        item.countryId = findCountry(item.countryId) and item.countryId or "us"
        item.investedCny = money(item.investedCny)
        item.navCny = money(item.navCny or item.investedCny)
        item.remainLockMonths = math.max(0, math.floor(tonumber(item.remainLockMonths) or 0))
        item.annualYield = clamp(item.annualYield or 0.045, -0.2, 0.2)
        item.mode = "fund_reits"
    end
    local mergedLoans = {}
    local seenLoans = {}
    local function mergeLoan(loan)
        if type(loan) ~= "table" then return end
        local id = tostring(loan.id or "legacy_loan_" .. tostring(#mergedLoans + 1))
        if seenLoans[id] then return end
        seenLoans[id] = true
        mergedLoans[#mergedLoans + 1] = normalizeLoan(loan, id)
    end
    for _, loan in ipairs(division.bankLoans) do mergeLoan(loan) end
    for _, loan in ipairs(data.loans) do mergeLoan(loan) end
    division.bankLoans = mergedLoans
    data.loans = {}
    if not division.active and (#data.projects > 0 or #data.assets > 0 or #data.funds > 0 or #division.bankLoans > 0) then
        division.active = true
        division.registeredCapitalCny = math.max(division.registeredCapitalCny, data.totalInvestedCny)
    end
    data.version = INS.VERSION
    recalcDerived(data)
    return data
end

function INS.GetCountry(countryId) return findCountry(countryId) end

function INS.GetCountries(GD)
    local data = INS.EnsureFields(GD)
    local result = {}
    for _, country in ipairs(INS.COUNTRIES) do
        local state = data.countries[country.id]
        local activeEvents = 0
        for _, event in ipairs(data.events) do if event.countryId == country.id and (event.remainMonths or 0) > 0 then activeEvents = activeEvents + 1 end end
        result[#result + 1] = {
            id = country.id, name = country.name, currency = country.currency,
            fxToCny = data.fxRates[country.id], reputation = state.reputation,
            landAllowed = country.foreignLand, risk = country.risk, desc = country.desc,
            dueDiligence = data.dueDiligence[country.id], activeEvents = activeEvents,
            foreignBalanceLocal = divisionAccount(data, country.id).balanceLocal,
            foreignBalanceCny = foreignAccountCny(data, country.id),
        }
    end
    return result
end

function INS.GetCapacity(GD)
    local data = INS.EnsureFields(GD)
    local teamBonus = (data.team.manager or 0) + (data.team.business or 0)
    return data.capacityLevel * 2 + math.floor(teamBonus / 2), data.capacityUsed
end

function INS.GetNetAssetValue(GD)
    local data = INS.EnsureFields(GD)
    local division = data.division
    local gross = division.treasuryCny or 0
    for _, country in ipairs(INS.COUNTRIES) do gross = gross + foreignAccountCny(data, country.id) end
    for _, deposit in ipairs(division.bankDeposits) do
        local country = findCountry(deposit.countryId)
        local fx = data.fxRates[deposit.countryId] or (country and country.fxToCny) or 1
        gross = gross + money((deposit.balanceLocal or 0) * fx + (deposit.accruedInterestCny or 0))
    end
    for _, item in ipairs(data.projects) do gross = gross + (item.investedCny or 0) * (0.7 + (item.progress or 0) * 0.35) end
    for _, item in ipairs(data.assets) do gross = gross + (item.investedCny or 0) * fxFactor(data, item.countryId, item.entryFx) end
    for _, item in ipairs(data.funds) do gross = gross + (item.navCny or item.investedCny or 0) * fxFactor(data, item.countryId, item.entryFx) end
    local debt = division.totalDebtCny or 0
    return {grossAssets = money(gross), debt = money(debt), netAssets = money(gross - debt)}
end

function INS.GetSummary(GD)
    local data = INS.EnsureFields(GD)
    local capacity, used = INS.GetCapacity(GD)
    local activeEvents = 0
    for _, event in ipairs(data.events) do if (event.remainMonths or 0) > 0 then activeEvents = activeEvents + 1 end end
    local division = data.division
    local foreignAccountCount = 0
    local foreignCashCny = 0
    for _, country in ipairs(INS.COUNTRIES) do
        local account = divisionAccount(data, country.id)
        if account.opened then foreignAccountCount = foreignAccountCount + 1 end
        foreignCashCny = foreignCashCny + foreignAccountCny(data, country.id)
    end
    local net = INS.GetNetAssetValue(GD)
    return {
        totalInvestedCny = data.totalInvestedCny, activeInvestedCny = data.activeInvestedCny,
        totalProfitCny = data.totalProfitCny, activeProjects = #data.projects,
        activeAssets = #data.assets, activeFunds = #data.funds,
        capacity = capacity, capacityUsed = used, activeEvents = activeEvents,
        teamCount = (data.team.business or 0) + (data.team.legal or 0) + (data.team.finance or 0) + (data.team.manager or 0),
        divisionActive = division.active, divisionTreasuryCny = division.treasuryCny,
        divisionRetainedEarningsCny = division.retainedEarningsCny,
        divisionDebtCny = division.totalDebtCny, foreignCashCny = money(foreignCashCny),
        foreignAccountCount = foreignAccountCount, bankDepositCount = #division.bankDeposits,
        bankLoanCount = #division.bankLoans, grossAssetsCny = net.grossAssets, netAssetsCny = net.netAssets,
        lastMonthlyIncome = data.lastMonthlyIncome, lastMonthlyExpense = data.lastMonthlyExpense,
    }
end

function INS.RegisterDivision(GD, amountCny)
    local data = INS.EnsureFields(GD)
    local group = GD.group
    if not group or not group.active then return false, "请先成立集团" end
    if data.division.active then return false, "集团海外事业部已经成立" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny < 1000 then return false, "海外事业部注册资本最低1000万元" end
    if (group.cash or 0) < amountCny then return false, "集团现金不足，无法注册海外事业部" end
    group.cash = group.cash - amountCny
    local division = data.division
    division.active = true
    division.registeredCapitalCny = money(amountCny)
    division.treasuryCny = money(amountCny)
    division.openedPeriod = currentPeriod(GD)
    logTransaction(GD, data, "division_registration", amountCny, "集团注册成立海外事业部", {classification = "capital"})
    print("[INTERNATIONAL] division registered capital=" .. tostring(amountCny))
    return true, "集团海外事业部已成立，可开始国别尽调和跨境经营"
end

function INS.InjectDivisionCapital(GD, amountCny, countryId)
    local data = INS.EnsureFields(GD)
    local group = GD.group
    if not group or not group.active then return false, "请先成立集团" end
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny <= 0 then return false, "请输入有效注资金额" end
    if (group.cash or 0) < amountCny then return false, "集团现金不足，无法向海外事业部注资" end
    group.cash = group.cash - amountCny
    data.division.registeredCapitalCny = money(data.division.registeredCapitalCny + amountCny)
    if countryId and findCountry(countryId) then putForeignCash(data, countryId, amountCny) else data.division.treasuryCny = money(data.division.treasuryCny + amountCny) end
    logTransaction(GD, data, "division_capital_injection", amountCny, "集团向海外事业部注资", {countryId = countryId, classification = "capital"})
    return true, "海外事业部注资成功"
end

function INS.TransferCapital(GD, countryId, amountCny)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    amountCny = money(amountCny)
    if amountCny <= 0 then return false, "请输入有效调拨金额" end
    local fee = money(amountCny * 0.012)
    if (data.division.treasuryCny or 0) < amountCny + fee then return false, "事业部本币资金池不足" end
    data.division.treasuryCny = money(data.division.treasuryCny - amountCny - fee)
    putForeignCash(data, countryId, amountCny)
    data.division.paidExpenseCny = money((data.division.paidExpenseCny or 0) + fee)
    data.division.totalExpenseCny = money((data.division.totalExpenseCny or 0) + fee)
    logTransaction(GD, data, "international_transfer_fee", -fee, country.name .. "跨境调拨手续费", {countryId = countryId, classification = "expense"})
    logTransaction(GD, data, "international_capital_transfer", amountCny, "本币资金池调拨至" .. country.name .. "外汇账户", {countryId = countryId, feeCny = fee, classification = "transfer"})
    return true, "已向" .. country.name .. "外汇账户调拨" .. GD.FormatMoney(amountCny) .. "，手续费" .. GD.FormatMoney(fee)
end

function INS.ExchangeForeignToCny(GD, countryId, amountCny)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    amountCny = money(amountCny)
    if amountCny <= 0 then return false, "请输入有效兑换金额" end
    local available = foreignAccountCny(data, countryId)
    if available < amountCny then return false, "该国外汇账户余额不足" end
    local fee = money(amountCny * 0.006)
    local account = divisionAccount(data, countryId)
    local fx = data.fxRates[countryId] or country.fxToCny
    account.balanceLocal = money(account.balanceLocal - amountCny / fx)
    data.division.treasuryCny = money(data.division.treasuryCny + amountCny - fee)
    data.division.paidExpenseCny = money((data.division.paidExpenseCny or 0) + fee)
    data.division.totalExpenseCny = money((data.division.totalExpenseCny or 0) + fee)
    logTransaction(GD, data, "international_fx_exchange_fee", -fee, country.name .. "外汇回兑手续费", {countryId = countryId, classification = "expense"})
    logTransaction(GD, data, "international_fx_exchange", amountCny - fee, country.name .. "外汇兑换为本币", {countryId = countryId, feeCny = fee, classification = "transfer"})
    return true, "外汇已兑换为事业部本币资金，手续费" .. GD.FormatMoney(fee)
end

function INS.DistributeDivisionDividend(GD, amountCny)
    local data = INS.EnsureFields(GD)
    local division = data.division
    local group = GD.group
    if not group or not group.active then return false, "请先成立集团" end
    if not division.active then return false, "请先注册成立集团海外事业部" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    local limit = math.floor(math.min(division.treasuryCny, math.max(0, division.retainedEarningsCny)))
    if amountCny <= 0 then return false, "请输入有效分红金额" end
    if amountCny > limit then return false, "超过可分红留存收益，最多" .. GD.FormatMoney(limit) end
    division.treasuryCny = money(division.treasuryCny - amountCny)
    division.retainedEarningsCny = money(division.retainedEarningsCny - amountCny)
    group.cash = (group.cash or 0) + amountCny
    group.monthlyIncome = (group.monthlyIncome or 0) + amountCny
    group.annualProfit = (group.annualProfit or 0) + amountCny
    group.retainedEarnings = (group.retainedEarnings or 0) + amountCny
    group.totalInternationalDividends = (group.totalInternationalDividends or 0) + amountCny
    logTransaction(GD, data, "division_dividend", -amountCny, "海外事业部向集团分红", {classification = "dividend"})
    return true, "海外事业部已向集团分红并完整计入集团收益"
end

function INS.GetDivisionSummary(GD) return INS.EnsureFields(GD).division end

function INS.StartDueDiligence(GD, countryId, subjectType)
    local data = INS.EnsureFields(GD)
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    local country = findCountry(countryId)
    if not country then return false, "未知投资国家" end
    local dd = data.dueDiligence[countryId]
    if dd and dd.status == "completed" then return true, "该国尽调已完成" end
    if dd and dd.status == "processing" then return false, "该国尽调正在进行" end
    local cost = subjectType == "existing_asset" and 180 or 240
    local ok, message = spendOperating(GD, data, cost, country.name .. "国别尽职调查", "country_due_diligence", countryId)
    if not ok then return false, message end
    data.dueDiligence[countryId] = {countryId = countryId, subjectType = subjectType or "general", status = "processing", remainMonths = 2, costCny = cost, hiddenRisk = math.random() < 0.35, startedPeriod = currentPeriod(GD)}
    return true, country.name .. "国别尽调已启动，预计2个月完成"
end

function INS.GetDueDiligenceStatus(GD, countryId) return INS.EnsureFields(GD).dueDiligence[countryId] end

local function requireDueDiligence(data, countryId)
    local dd = data.dueDiligence[countryId]
    if not dd or dd.status ~= "completed" then return false, "请先完成该国国别尽职调查" end
    return true
end

local function checkCapacity(GD, data, mode)
    local def = INS.MODE_DEFS[mode]
    if not def then return false, "未知国际投资模式" end
    local capacity, used = INS.GetCapacity(GD)
    if used + def.capacity > capacity then return false, "国际业务容量不足，请升级国际业务部" end
    return true
end

local function countryRisk(data, countryId, mode)
    local country = findCountry(countryId)
    local def = INS.MODE_DEFS[mode]
    local state = data.countries[countryId]
    local risk = (country and country.risk or 0.2) + (def and def.baseRisk or 0.1)
    risk = risk - (state and state.reputation or 40) / 1000
    for _, role in ipairs(INS.TEAM_ROLES) do risk = risk - (data.team[role.id] or 0) * role.risk * 0.25 end
    local dd = data.dueDiligence[countryId]
    if not dd or dd.status ~= "completed" then risk = risk + 0.20 end
    if dd and dd.hiddenRisk then risk = risk + 0.10 end
    return clamp(risk, 0.03, 0.85)
end

local function createInvestment(data, mode, countryId, amountCny, fields)
    local item = fields or {}
    item.id = newId(data, "intl")
    item.mode = mode
    item.countryId = countryId
    item.investedCny = money(amountCny)
    item.status = item.status or "active"
    item.risk = item.risk or countryRisk(data, countryId, mode)
    return item
end

local function commitInvestment(data, item)
    data.totalInvestedCny = money(data.totalInvestedCny + item.investedCny)
    data.countries[item.countryId].investedCny = money(data.countries[item.countryId].investedCny + item.investedCny)
    recalcDerived(data)
end

function INS.InvestDirectLand(GD, countryId, amountCny, holdMode)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    local ready, reason = requireDueDiligence(data, countryId)
    if not ready then return false, reason end
    if not country.foreignLand and (data.team.manager or 0) <= 0 then return false, "该国土地受外资限制，需要本地项目经理或改用联合开发" end
    local capacityOk, capMessage = checkCapacity(GD, data, "direct_land")
    if not capacityOk then return false, capMessage end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny < 1000 then return false, "自主开发最低投资1000万元" end
    local item = createInvestment(data, "direct_land", countryId, amountCny, {
        name = country.name .. "海外自主开发项目", stage = "construction", progress = 0,
        holdMode = holdMode == "rent" and "rent" or "sale",
        localValue = amountCny / data.fxRates[countryId], entryFx = data.fxRates[countryId],
        totalMonths = INS.MODE_DEFS.direct_land.duration, remainMonths = INS.MODE_DEFS.direct_land.duration,
        createdMonth = GD.totalMonths or 0,
    })
    local ok, message = spendInvestment(GD, data, amountCny, country.name .. "自主开发项目投入", "international_direct_land", countryId, item.id)
    if not ok then return false, message end
    data.projects[#data.projects + 1] = item
    commitInvestment(data, item)
    return true, "已启动海外自主开发项目（" .. (item.holdMode == "rent" and "持有出租" or "开发销售") .. "）"
end

function INS.BuyExistingAsset(GD, countryId, amountCny, assetType)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    local ready, reason = requireDueDiligence(data, countryId)
    if not ready then return false, reason end
    local capacityOk, capMessage = checkCapacity(GD, data, "existing_asset")
    if not capacityOk then return false, capMessage end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny < 500 then return false, "存量物业最低投资500万元" end
    local item = createInvestment(data, "existing_asset", countryId, amountCny, {
        name = country.name .. (assetType or "写字楼") .. "存量物业", assetType = assetType or "office",
        localValue = amountCny / data.fxRates[countryId], entryFx = data.fxRates[countryId], occupancy = 0.82,
        monthlyRentCny = money(amountCny * 0.006), lockMonths = 12, remainLockMonths = 12,
        createdMonth = GD.totalMonths or 0,
    })
    local ok, message = spendInvestment(GD, data, amountCny, country.name .. "收购存量物业", "international_existing_asset", countryId, item.id)
    if not ok then return false, message end
    data.assets[#data.assets + 1] = item
    commitInvestment(data, item)
    return true, "已收购存量海外物业，下期开始产生租金"
end

function INS.CreateJointVenture(GD, countryId, amountCny, partnerName, sharePercent)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    local ready, reason = requireDueDiligence(data, countryId)
    if not ready then return false, reason end
    local capacityOk, capMessage = checkCapacity(GD, data, "joint_venture")
    if not capacityOk then return false, capMessage end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny < 800 then return false, "联合开发最低出资800万元" end
    local share = clamp(tonumber(sharePercent) or 50, 10, 90) / 100
    local item = createInvestment(data, "joint_venture", countryId, amountCny, {
        name = country.name .. "联合开发项目", stage = "construction", progress = 0,
        partnerName = partnerName or "本地合作开发商", playerShare = share,
        partnerShare = 1 - share, totalMonths = INS.MODE_DEFS.joint_venture.duration,
        remainMonths = INS.MODE_DEFS.joint_venture.duration,
        partnerReliability = clamp(0.68 + (data.team.legal or 0) * 0.03, 0.55, 0.95),
        entryFx = data.fxRates[countryId], createdMonth = GD.totalMonths or 0,
    })
    local ok, message = spendInvestment(GD, data, amountCny, country.name .. "联合开发出资", "international_joint_venture", countryId, item.id)
    if not ok then return false, message end
    data.projects[#data.projects + 1] = item
    commitInvestment(data, item)
    return true, "已签署本地合作开发协议"
end

function INS.InvestFund(GD, countryId, amountCny, fundType)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    local ready, reason = requireDueDiligence(data, countryId)
    if not ready then return false, reason end
    local capacityOk, capMessage = checkCapacity(GD, data, "fund_reits")
    if not capacityOk then return false, capMessage end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny < 300 then return false, "海外地产基金最低投资300万元" end
    local item = createInvestment(data, "fund_reits", countryId, amountCny, {
        name = country.name .. (fundType or "REITs") .. "基金", fundType = fundType or "REITs",
        navCny = amountCny, entryFx = data.fxRates[countryId], lockMonths = 6,
        remainLockMonths = 6, annualYield = 0.045, createdMonth = GD.totalMonths or 0,
    })
    local ok, message = spendInvestment(GD, data, amountCny, country.name .. "海外地产基金投资", "international_fund", countryId, item.id)
    if not ok then return false, message end
    data.funds[#data.funds + 1] = item
    commitInvestment(data, item)
    return true, "已完成海外基金/REITs认购"
end

function INS.HireTeam(GD, roleId, amount)
    local data = INS.EnsureFields(GD)
    local role = findById(INS.TEAM_ROLES, roleId)
    if not role then return false, "未知海外岗位" end
    local headcount = math.max(1, math.floor(tonumber(amount) or 1))
    local ok, message = spendOperating(GD, data, role.cost * headcount, "聘用" .. role.name .. tostring(headcount) .. "人", "international_team_hire", data.selectedCountry)
    if not ok then return false, message end
    data.team[roleId] = data.team[roleId] + headcount
    return true, role.name .. "已聘用" .. tostring(headcount) .. "人"
end

function INS.FireTeam(GD, roleId, amount)
    local data = INS.EnsureFields(GD)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if (data.team[roleId] or 0) < amount then return false, "该岗位没有足够在职人员" end
    data.team[roleId] = data.team[roleId] - amount
    logTransaction(GD, data, "international_team_change", 0, "海外团队减员", {roleId = roleId, count = amount})
    return true, "已减少海外团队人员"
end

function INS.UpgradeCapacity(GD)
    local data = INS.EnsureFields(GD)
    local cost = 800 * data.capacityLevel
    local ok, message = spendOperating(GD, data, cost, "升级国际业务部全球项目容量", "international_capacity", data.selectedCountry)
    if not ok then return false, message end
    data.capacityLevel = data.capacityLevel + 1
    local capacity = INS.GetCapacity(GD)
    return true, "国际业务容量已提升至" .. tostring(capacity) .. "个项目"
end

function INS.ApplyFXHedge(GD, countryId, amountCny, months)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not country then return false, "未知国家" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    months = math.max(3, math.floor(tonumber(months) or 12))
    if amountCny <= 0 then return false, "请输入有效对冲金额" end
    local exposure = activeExposure(data, countryId)
    local currentHedge = 0
    for _, hedge in ipairs(data.hedges) do if hedge.countryId == countryId and hedge.remainMonths > 0 then currentHedge = currentHedge + hedge.amountCny end end
    amountCny = math.min(amountCny, math.max(0, exposure - currentHedge))
    if amountCny <= 0 then return false, "该国现有外汇敞口已经全部对冲" end
    local cost = money(amountCny * 0.018 * months / 12)
    local ok, message = spendOperating(GD, data, cost, country.name .. "汇率对冲工具", "international_fx_hedge", countryId)
    if not ok then return false, message end
    data.hedges[#data.hedges + 1] = {id = newId(data, "hedge"), countryId = countryId, amountCny = amountCny, remainMonths = months, lockedFx = data.fxRates[countryId], costCny = cost}
    return true, "已对冲" .. GD.FormatMoney(amountCny) .. "的" .. country.name .. "外汇敞口"
end

function INS.DepositToInternationalBank(GD, countryId, amountCny, productType, months)
    local data = INS.EnsureFields(GD)
    local country = findCountry(countryId)
    if not data.division.active then return false, "请先注册成立集团海外事业部" end
    if not country then return false, "未知国家" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    if amountCny <= 0 then return false, "请输入有效存款金额" end
    if not takeCash(data, amountCny, countryId) then return false, "海外事业部可用资金不足" end
    local fx = data.fxRates[countryId]
    local deposit = {
        id = "intl_deposit_" .. tostring(data.division.nextDepositId), countryId = countryId,
        productType = productType or "fixed", principalCny = amountCny,
        balanceLocal = money(amountCny / fx), rate = productType == "fixed" and 0.032 or 0.018,
        remainMonths = math.max(1, math.floor(tonumber(months) or 12)),
        elapsedMonths = 0, accruedInterestCny = 0, fxAtDeposit = fx, status = "active",
    }
    data.division.nextDepositId = data.division.nextDepositId + 1
    data.division.bankDeposits[#data.division.bankDeposits + 1] = deposit
    logTransaction(GD, data, "international_bank_deposit", -amountCny, "海外事业部向" .. country.name .. "国际银行存款", {countryId = countryId, objectId = deposit.id, classification = "investment"})
    return true, "国际银行存款成功"
end

function INS.WithdrawInternationalBank(GD, depositId)
    local data = INS.EnsureFields(GD)
    for index, deposit in ipairs(data.division.bankDeposits) do
        if deposit.id == depositId then
            local country = findCountry(deposit.countryId)
            local fx = data.fxRates[deposit.countryId] or (country and country.fxToCny) or 1
            local principal = money((deposit.balanceLocal or 0) * fx)
            local interest = money(deposit.accruedInterestCny)
            local tax = money(math.max(0, interest) * (country and country.withholdingRate or 0.08))
            local netInterest = money(interest - tax)
            putForeignCash(data, deposit.countryId, principal + netInterest)
            if netInterest > 0 then
                data.division.pendingIncomeCny = money((data.division.pendingIncomeCny or 0) + netInterest)
                logTransaction(GD, data, "international_bank_interest", netInterest, "国际银行存款税后利息", {countryId = deposit.countryId, objectId = deposit.id, classification = "income"})
            end
            logTax(GD, data, deposit.countryId, "interest_withholding", tax, deposit.id, "国际银行利息预扣税")
            table.remove(data.division.bankDeposits, index)
            logTransaction(GD, data, "international_bank_withdraw", principal, "取回国际银行存款本金", {countryId = deposit.countryId, objectId = deposit.id, classification = "capital_return"})
            return true, "国际银行存款已取回，税后利息" .. GD.FormatMoney(interest - tax)
        end
    end
    return false, "未找到国际银行存款"
end

function INS.ApplyDivisionBankLoan(GD, countryId, amountCny, months, loanType, collateralCny)
    local data = INS.EnsureFields(GD)
    local division = data.division
    local country = findCountry(countryId)
    if not division.active then return false, "请先注册成立集团海外事业部" end
    if not country then return false, "未知国家" end
    amountCny = math.floor(tonumber(amountCny) or 0)
    months = math.max(12, math.floor(tonumber(months) or 36))
    if amountCny <= 0 then return false, "请输入有效贷款金额" end
    local net = INS.GetNetAssetValue(GD)
    local collateral = math.max(division.registeredCapitalCny, tonumber(collateralCny) or 0, net.grossAssets - division.treasuryCny)
    local maxRatio = loanType == "mortgage" and 0.65 or 0.35
    local currentCountryDebt = 0
    for _, loan in ipairs(division.bankLoans) do if loan.countryId == countryId then currentCountryDebt = currentCountryDebt + loan.remainingCny end end
    if amountCny + currentCountryDebt > collateral * maxRatio then return false, "超过国际银行当前可贷额度" end
    local financeDiscount = math.min(0.012, (data.team.finance or 0) * 0.002)
    local rate = math.max(0.035, (loanType == "mortgage" and 0.058 or 0.075) - financeDiscount)
    local loan = {
        id = "intl_bank_loan_" .. tostring(division.nextLoanId), countryId = countryId,
        loanType = loanType or "credit", amountCny = amountCny, remainingCny = amountCny,
        rate = rate, remainMonths = months, accruedInterest = 0, status = "active",
        localAmount = amountCny / data.fxRates[countryId], fxAtDraw = data.fxRates[countryId],
        collateralCny = loanType == "mortgage" and collateral or 0,
    }
    division.nextLoanId = division.nextLoanId + 1
    division.bankLoans[#division.bankLoans + 1] = loan
    putForeignCash(data, countryId, amountCny)
    recalcDerived(data)
    logTransaction(GD, data, "international_bank_loan", amountCny, country.name .. "国际银行贷款到账", {countryId = countryId, objectId = loan.id, classification = "financing"})
    return true, "国际银行贷款已进入该国外汇账户"
end

function INS.RepayDivisionBankLoan(GD, loanId, amountCny)
    local data = INS.EnsureFields(GD)
    local division = data.division
    for index, loan in ipairs(division.bankLoans) do
        if loan.id == loanId then
            local due = money((loan.remainingCny or 0) + (loan.accruedInterest or 0))
            local repay = math.min(math.floor(tonumber(amountCny) or due), due)
            if repay <= 0 then return false, "贷款已结清" end
            if not takeCash(data, repay, loan.countryId) then return false, "海外事业部资金不足" end
            local interestPaid = math.min(repay, loan.accruedInterest or 0)
            loan.accruedInterest = money((loan.accruedInterest or 0) - interestPaid)
            local principalPaid = math.min(repay - interestPaid, loan.remainingCny or 0)
            loan.remainingCny = money((loan.remainingCny or 0) - principalPaid)
            if loan.remainingCny <= 0 and loan.accruedInterest <= 0 then table.remove(division.bankLoans, index) end
            recalcDerived(data)
            logTransaction(GD, data, "international_bank_repayment", -repay, "偿还国际银行贷款", {countryId = loan.countryId, objectId = loan.id, interestCny = interestPaid, principalCny = principalPaid, classification = "financing"})
            return true, "国际银行贷款还款成功"
        end
    end
    return false, "未找到国际银行贷款"
end

function INS.ApplyLoan(GD, countryId, amountCny, months, loanType)
    return INS.ApplyDivisionBankLoan(GD, countryId, amountCny, months, loanType == "mortgage" and "mortgage" or "credit", nil)
end

local function exitBlocked(data, countryId)
    local _, _, blocked = getEventFactors(data, countryId)
    return blocked
end

function INS.SellAsset(GD, assetId)
    local data = INS.EnsureFields(GD)
    local asset = findById(data.assets, assetId)
    if not asset then return false, "未找到海外物业" end
    if asset.remainLockMonths > 0 then return false, "资产仍在锁定期内，暂不能出售" end
    if exitBlocked(data, asset.countryId) then return false, "当前外资政策限制资产出售，请先处置事件或等待解除" end
    local country = findCountry(asset.countryId)
    local _, growthBonus = getEventFactors(data, asset.countryId)
    local heldMonths = math.max(1, (GD.totalMonths or 0) - (asset.createdMonth or 0))
    local growth = (country.marketGrowth or 0.03) + growthBonus
    local value = money(asset.investedCny * math.max(0.55, 1 + growth * heldMonths / 12) * fxFactor(data, asset.countryId, asset.entryFx))
    local gain = math.max(0, value - asset.investedCny)
    local transferTax = money(value * country.transferTaxRate)
    local incomeTax = money(gain * country.taxRate)
    local withholding = money(math.max(0, value - transferTax - incomeTax) * country.withholdingRate)
    local tax = transferTax + incomeTax + withholding
    local net = money(value - tax)
    receiveIncome(GD, data, asset.countryId, net, "出售" .. asset.name .. "税后回款", "international_asset_exit", asset.id, math.max(0, net - asset.investedCny))
    logTax(GD, data, asset.countryId, "asset_exit", tax, asset.id, "物业出售税费")
    local profit = money(net - asset.investedCny)
    data.totalProfitCny = money(data.totalProfitCny + profit)
    data.countries[asset.countryId].profitCny = money(data.countries[asset.countryId].profitCny + profit)
    archiveBusiness(data, asset, "asset_sale", net, profit, tax, currentPeriod(GD))
    removeById(data.assets, asset.id)
    recalcDerived(data)
    return true, "海外物业已出售，税后回款" .. GD.FormatMoney(net)
end

function INS.RedeemFund(GD, fundId)
    local data = INS.EnsureFields(GD)
    local fund = findById(data.funds, fundId)
    if not fund then return false, "未找到海外基金" end
    if fund.remainLockMonths > 0 then return false, "基金仍在锁定期内" end
    if exitBlocked(data, fund.countryId) then return false, "当前资本管制限制基金赎回" end
    local country = findCountry(fund.countryId)
    local value = money(fund.navCny * fxFactor(data, fund.countryId, fund.entryFx))
    local gain = math.max(0, value - fund.investedCny)
    local tax = money(gain * ((country.taxRate or 0.2) + (country.withholdingRate or 0.08)))
    local net = money(value - tax)
    receiveIncome(GD, data, fund.countryId, net, "赎回" .. fund.name, "international_fund_exit", fund.id, math.max(0, net - fund.investedCny))
    logTax(GD, data, fund.countryId, "fund_exit", tax, fund.id, "基金赎回税费")
    local profit = money(net - fund.investedCny)
    data.totalProfitCny = money(data.totalProfitCny + profit)
    archiveBusiness(data, fund, "fund_redeem", net, profit, tax, currentPeriod(GD))
    removeById(data.funds, fund.id)
    recalcDerived(data)
    return true, "基金已赎回，税后回款" .. GD.FormatMoney(net)
end

function INS.ExitProject(GD, projectId, exitMode)
    local data = INS.EnsureFields(GD)
    local project = findById(data.projects, projectId)
    if not project then return false, "未找到海外项目" end
    if exitMode == "equity_transfer" and project.remainMonths > 6 then return false, "项目尚未达到可转让阶段" end
    if exitBlocked(data, project.countryId) then return false, "当前资本管制限制项目退出" end
    local progress = clamp(project.progress, 0, 1)
    local multiplier = exitMode == "distress" and (0.45 + progress * 0.20) or (exitMode == "reit" and (0.70 + progress * 0.22) or (0.72 + progress * 0.38))
    local value = money(project.investedCny * multiplier * fxFactor(data, project.countryId, project.entryFx))
    local country = findCountry(project.countryId)
    local gain = math.max(0, value - project.investedCny)
    local localTax = money(gain * country.taxRate)
    local withholding = money(math.max(0, value - localTax) * country.withholdingRate)
    local tax = localTax + withholding
    local net = money(value - tax)
    receiveIncome(GD, data, project.countryId, net, "海外项目退出回款", "international_project_exit", project.id, math.max(0, net - project.investedCny))
    logTax(GD, data, project.countryId, "project_exit", tax, project.id, "项目退出税费")
    local profit = money(net - project.investedCny)
    data.totalProfitCny = money(data.totalProfitCny + profit)
    archiveBusiness(data, project, exitMode or "equity_transfer", net, profit, tax, currentPeriod(GD))
    removeById(data.projects, project.id)
    recalcDerived(data)
    return true, "海外项目已退出，税后回款" .. GD.FormatMoney(net)
end

function INS.ResolveEvent(GD, eventId, action)
    local data = INS.EnsureFields(GD)
    local event = findById(data.events, eventId)
    if not event or event.remainMonths <= 0 then return false, "未找到有效海外事件" end
    local cost = action == "hedge" and 180 or 260
    local ok, message = spendOperating(GD, data, cost, "处置海外事件：" .. event.name, "international_event_resolution", event.countryId, event.id)
    if not ok then return false, message end
    event.remainMonths = 0
    event.resolved = true
    local state = data.countries[event.countryId]
    if state then state.reputation = clamp(state.reputation + 2, 0, 100) end
    return true, "海外事件已处置，限制和损失影响解除"
end

local function rollCountryEvent(GD, data, country, state)
    for _, event in ipairs(data.events) do if event.countryId == country.id and event.remainMonths > 0 then return end end
    if math.random() > country.risk * 0.10 then return end
    local keys = {"policy_incentive", "infrastructure", "capital_restriction", "strike", "disaster", "recession"}
    local def = INS.EVENT_DEFS[keys[math.random(1, #keys)]]
    if not def then return end
    local event = {id = newId(data, "event"), countryId = country.id, kind = def.kind, eventType = def.id, name = def.name, desc = def.desc, remainMonths = def.duration, cashFactor = def.cashFactor, growthBonus = def.growthBonus, warning = true, resolved = false}
    data.events[#data.events + 1] = event
    state.reputation = clamp(state.reputation + (def.kind == "good" and 2 or -3), 0, 100)
    GD.AddEvent("海外事件预警：" .. country.name .. "发生" .. def.name, def.kind == "good" and "success" or "warning")
end

local function completeProject(GD, data, project, serial)
    local country = findCountry(project.countryId)
    local _, growthBonus = getEventFactors(data, project.countryId)
    local teamEfficiency = 1 + (data.team.business or 0) * 0.02 + (data.team.manager or 0) * 0.03
    local marketFactor = clamp(1 + (country.marketGrowth + growthBonus) * project.totalMonths / 12, 0.65, 1.55)
    local riskLoss = project.risk * (project.mode == "joint_venture" and (1 - (project.partnerReliability or 0.72)) * 0.8 or 0.35)
    if project.holdMode == "rent" and project.mode == "direct_land" then
        local asset = createInvestment(data, "existing_asset", project.countryId, project.investedCny, {
            id = project.id, name = project.name .. "持有物业", assetType = "developed_property",
            entryFx = project.entryFx, occupancy = clamp(0.72 + (data.team.business or 0) * 0.03, 0.55, 0.95),
            monthlyRentCny = money(project.investedCny * 0.0065 * teamEfficiency), remainLockMonths = 6,
            createdMonth = GD.totalMonths or 0,
        })
        data.assets[#data.assets + 1] = asset
        archiveBusiness(data, project, "converted_to_asset", 0, 0, 0, serial)
        return "asset", 0
    end
    local revenue = money(project.investedCny * marketFactor * (1.10 - riskLoss))
    if project.mode == "joint_venture" then revenue = money(revenue * clamp(project.partnerReliability or 0.72, 0.55, 0.95)) end
    revenue = money(revenue * fxFactor(data, project.countryId, project.entryFx))
    local gain = math.max(0, revenue - project.investedCny)
    local localTax = money(gain * country.taxRate)
    local withholding = money(math.max(0, revenue - localTax) * country.withholdingRate)
    local tax = localTax + withholding
    local net = money(revenue - tax)
    receiveIncome(GD, data, project.countryId, net, project.name .. "项目结算", "international_project_income", project.id, math.max(0, net - project.investedCny))
    logTax(GD, data, project.countryId, "project_completion", tax, project.id, "项目结算税费")
    local profit = money(net - project.investedCny)
    data.totalProfitCny = money(data.totalProfitCny + profit)
    data.countries[project.countryId].profitCny = money(data.countries[project.countryId].profitCny + profit)
    archiveBusiness(data, project, "completed_sale", net, profit, tax, serial)
    return "sale", profit
end

local function processDueLoans(GD, data)
    local division = data.division
    for _, loan in ipairs(division.bankLoans) do
        local principal = math.max(0, loan.remainingCny or 0)
        local interest = money(principal * (loan.rate or 0.07) / 12)
        loan.accruedInterest = money((loan.accruedInterest or 0) + interest)
        loan.remainMonths = math.max(0, (loan.remainMonths or 0) - 1)
        data._periodExpense = money((data._periodExpense or 0) + interest)
        data._periodNonCashExpense = money((data._periodNonCashExpense or 0) + interest)
        if loan.remainMonths <= 0 then
            local due = money(loan.remainingCny + loan.accruedInterest)
            local available = foreignAccountCny(data, loan.countryId) + division.treasuryCny
            local repay = math.min(due, available)
            if repay > 0 then
                takeCash(data, repay, loan.countryId)
                local interestPaid = math.min(repay, loan.accruedInterest)
                loan.accruedInterest = money(loan.accruedInterest - interestPaid)
                loan.remainingCny = money(loan.remainingCny - math.min(repay - interestPaid, loan.remainingCny))
                logTransaction(GD, data, "international_bank_maturity_repayment", -repay, "国际银行贷款到期还款", {countryId = loan.countryId, objectId = loan.id, classification = "financing"})
            end
            if loan.remainingCny > 0 or loan.accruedInterest > 0 then
                loan.status = "overdue"
                loan.remainMonths = 1
                loan.rate = math.min(0.18, (loan.rate or 0.07) + 0.02)
                GD.AddEvent("海外事业部国际贷款逾期，未偿余额继续保留", "warning")
            else
                loan.status = "paid"
            end
        end
    end
    for index = #division.bankLoans, 1, -1 do
        local loan = division.bankLoans[index]
        if loan.status == "paid" then table.remove(division.bankLoans, index) end
    end
    recalcDerived(data)
end

function INS.MonthlyUpdate(GD, completedYear, completedMonth)
    local data = INS.EnsureFields(GD)
    local division = data.division
    if not division.active then return {processed = false, reason = "no_division"} end
    local serial = periodKey(GD, completedYear, completedMonth)
    if data.lastMonthlySerial == serial then return {processed = false, skipped = true, period = serial} end
    if data.monthlyProcessingSerial == serial then data.monthlyProcessingSerial = nil end
    local snapshot = deepCopy(data)
    data.monthlyProcessingSerial = serial
    local ok, result = pcall(function()
        data._periodIncome = money(division.pendingIncomeCny)
        data._periodExpense = money(division.pendingExpenseCny)
        data._periodNonCashExpense = 0
        local alreadyPaidExpense = money(division.paidExpenseCny)
        division.pendingIncomeCny = 0
        division.pendingExpenseCny = 0
        division.paidExpenseCny = 0

    for _, country in ipairs(INS.COUNTRIES) do
        local state = data.countries[country.id]
        local dd = data.dueDiligence[country.id]
        if dd and dd.status == "processing" then
            dd.remainMonths = math.max(0, (dd.remainMonths or 0) - 1)
            if dd.remainMonths <= 0 then dd.status = "completed"; dd.completedPeriod = serial; GD.AddEvent(country.name .. "国别尽职调查完成", "success") end
        end
        local oldFx = data.fxRates[country.id]
        local change = (math.random() - 0.5) * country.risk * 0.018
        data.fxRates[country.id] = clamp(oldFx * (1 + change), country.fxToCny * 0.70, country.fxToCny * 1.30)
        rollCountryEvent(GD, data, country, state)
    end

    local teamMonthlyCost = 0
    for _, role in ipairs(INS.TEAM_ROLES) do teamMonthlyCost = teamMonthlyCost + (data.team[role.id] or 0) * role.monthly end
    data._periodExpense = money(data._periodExpense + teamMonthlyCost)

    for _, hedge in ipairs(data.hedges) do hedge.remainMonths = math.max(0, hedge.remainMonths - 1) end
    for index = #data.hedges, 1, -1 do if data.hedges[index].remainMonths <= 0 then table.remove(data.hedges, index) end end

    for _, deposit in ipairs(division.bankDeposits) do
        deposit.elapsedMonths = (deposit.elapsedMonths or 0) + 1
        deposit.remainMonths = math.max(0, deposit.remainMonths - 1)
        deposit.accruedInterestCny = money((deposit.accruedInterestCny or 0) + deposit.principalCny * deposit.rate / 12)
        if deposit.remainMonths <= 0 then deposit.status = "matured" end
    end

    processDueLoans(GD, data)

    for _, asset in ipairs(data.assets) do
        asset.remainLockMonths = math.max(0, asset.remainLockMonths - 1)
        local country = findCountry(asset.countryId)
        local cashFactor, growthBonus = getEventFactors(data, asset.countryId)
        local occupancyTarget = clamp(1 - country.vacancy + growthBonus + (data.team.business or 0) * 0.015, 0.35, 0.98)
        asset.occupancy = clamp(asset.occupancy + (occupancyTarget - asset.occupancy) * 0.20 + (math.random() - 0.5) * 0.02, 0.35, 0.98)
        local grossRent = money(asset.monthlyRentCny * asset.occupancy * fxFactor(data, asset.countryId, asset.entryFx))
        local operating = money(grossRent * 0.12 * cashFactor)
        local propertyTax = money(asset.investedCny * country.propertyTaxRate / 12)
        local withholding = money(math.max(0, grossRent - operating - propertyTax) * country.withholdingRate)
        local net = money(grossRent - operating - propertyTax - withholding)
        if net >= 0 then receiveIncome(GD, data, asset.countryId, net, asset.name .. "租金净收入", "international_rent", asset.id) else data._periodExpense = money(data._periodExpense + math.abs(net)) end
        logTax(GD, data, asset.countryId, "property_and_withholding", propertyTax + withholding, asset.id, "物业持有税与预扣税")
        data.countries[asset.countryId].profitCny = money(data.countries[asset.countryId].profitCny + net)
        data.totalProfitCny = money(data.totalProfitCny + net)
    end

    for _, fund in ipairs(data.funds) do
        fund.remainLockMonths = math.max(0, fund.remainLockMonths - 1)
        local country = findCountry(fund.countryId)
        local _, growthBonus = getEventFactors(data, fund.countryId)
        local monthlyGrowth = ((country.marketGrowth + growthBonus) / 12) + (math.random() - 0.5) * country.risk * 0.01
        fund.navCny = money(math.max(fund.investedCny * 0.45, fund.navCny * (1 + monthlyGrowth)))
        local gross = money(fund.navCny * fund.annualYield / 12 * fxFactor(data, fund.countryId, fund.entryFx))
        local tax = money(math.max(0, gross) * country.withholdingRate)
        local net = money(gross - tax)
        if net > 0 then receiveIncome(GD, data, fund.countryId, net, fund.name .. "分红", "international_fund_income", fund.id) end
        logTax(GD, data, fund.countryId, "fund_withholding", tax, fund.id, "基金分红预扣税")
        data.totalProfitCny = money(data.totalProfitCny + net)
    end

    local completed = {}
    for _, project in ipairs(data.projects) do
        if not project.paused then
            local country = findCountry(project.countryId)
            local _, _, _, eventEfficiency = getEventFactors(data, project.countryId)
            local teamEfficiency = 1
            for _, role in ipairs(INS.TEAM_ROLES) do teamEfficiency = teamEfficiency + (data.team[role.id] or 0) * role.efficiency end
            if project.mode == "joint_venture" then teamEfficiency = teamEfficiency + country.localPartnerBonus end
            local efficiency = teamEfficiency * eventEfficiency * (1 - project.risk * 0.15)
            project.progress = math.min(1, project.progress + efficiency / project.totalMonths)
            project.remainMonths = math.max(0, project.remainMonths - 1)
            data._periodExpense = money(data._periodExpense + project.investedCny * 0.002 * select(1, getEventFactors(data, project.countryId)))
            if project.progress >= 1 or project.remainMonths <= 0 then completed[#completed + 1] = project end
        end
    end
    for _, project in ipairs(completed) do completeProject(GD, data, project, serial); removeById(data.projects, project.id) end

    for _, event in ipairs(data.events) do event.remainMonths = math.max(0, event.remainMonths - 1) end
    local income = money(data._periodIncome)
    local unpaidExpense = money(math.max(0, data._periodExpense - (data._periodNonCashExpense or 0)))
    local expense = money(data._periodExpense + alreadyPaidExpense)
    division.monthlyIncomeCny = income
    division.monthlyExpenseCny = expense
    division.totalExpenseCny = money(division.totalExpenseCny + unpaidExpense + (data._periodNonCashExpense or 0))
    local netProfit = money(income - expense)
    division.retainedEarningsCny = money(division.retainedEarningsCny + netProfit)
    data.totalProfitCny = money(data.totalProfitCny - expense)
    data.lastMonthlyIncome = income
    data.lastMonthlyExpense = expense
    if unpaidExpense > 0 then
        local availableCash = division.treasuryCny or 0
        for _, country in ipairs(INS.COUNTRIES) do availableCash = availableCash + foreignAccountCny(data, country.id) end
        local paid = math.min(unpaidExpense, availableCash)
        local unpaid = paid
        for _, country in ipairs(INS.COUNTRIES) do
            if unpaid <= 0 then break end
            local available = foreignAccountCny(data, country.id)
            local fromCountry = math.min(unpaid, available)
            if fromCountry > 0 then takeCash(data, fromCountry, country.id); unpaid = money(unpaid - fromCountry) end
        end
        if unpaid > 0 then takeCash(data, unpaid, nil) end
        division.operatingPayableCny = money((division.operatingPayableCny or 0) + unpaidExpense - paid)
        if unpaidExpense - paid > 0 then GD.AddEvent("海外事业部经营费用出现应付款，请及时补充资金", "warning") end
        logTransaction(GD, data, "international_monthly_expense", -unpaidExpense, "海外事业部月末待支付经营费用", {period = serial, paidCny = paid, payableCny = unpaidExpense - paid, classification = "expense"})
    end
    recalcDerived(data)
        data.lastMonthlySerial = serial
        data.monthlyProcessingSerial = nil
        print("[INTERNATIONAL] monthly settled period=" .. serial .. " income=" .. tostring(income) .. " expense=" .. tostring(expense))
        return {processed = true, period = serial, income = income, expense = expense, netProfit = netProfit}
    end)
    if not ok then
        GD.international = snapshot
        print("[INTERNATIONAL] ERROR monthly settlement rolled back period=" .. serial .. " message=" .. tostring(result))
        return {processed = false, failed = true, period = serial, error = tostring(result)}
    end
    return result
end

return INS
