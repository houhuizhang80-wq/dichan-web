-- ============================================================================
-- PersonalFinanceEcosystem.lua - 个人金融生态后端
-- 仅管理 player.personalFinanceEcosystem；金额单位均为万元。
-- 不读取或修改公司现金、公司负债。
-- ============================================================================

local PersonalFinanceEcosystem = {}

local VERSION = 1
local CONTRACT_LIMIT = 120
local RECORD_LIMIT = 160
local DIARY_LIMIT = 120
local EVENT_HISTORY_LIMIT = 48
local TAX_RECORD_LIMIT = 80

local NPCS = {
    {id = "shen_yu", name = "沈瑜", role = "社区理财顾问", baseRate = 0.068, risk = 0.05, maxAmount = 300},
    {id = "fang_wei", name = "方玮", role = "民营企业主", baseRate = 0.082, risk = 0.10, maxAmount = 600},
    {id = "lin_qing", name = "林清", role = "律师合伙人", baseRate = 0.074, risk = 0.07, maxAmount = 450},
    {id = "zhou_ning", name = "周宁", role = "资深投资人", baseRate = 0.095, risk = 0.14, maxAmount = 1000},
    {id = "gu_xia", name = "顾夏", role = "家族办公室经理", baseRate = 0.062, risk = 0.03, maxAmount = 1500},
}

local EVENT_DEFINITIONS = {
    appliance = {name = "家电紧急维修", deadline = 1, minCost = 18, maxCost = 60},
    medical = {name = "医疗急诊", deadline = 1, minCost = 35, maxCost = 130},
    friend = {name = "朋友临时周转", deadline = 1, minCost = 30, maxCost = 100},
    family = {name = "家庭紧急支出", deadline = 1, minCost = 45, maxCost = 160},
    legal = {name = "法律咨询与材料保全", deadline = 2, minCost = 12, maxCost = 55},
}

local TAX_CATEGORIES = {
    charity = {name = "公益捐赠", capRatio = 0.30},
    education = {name = "继续教育及子女教育", capRatio = 0.20},
    medical = {name = "医疗支出", capRatio = 0.15},
    elderCare = {name = "赡养老人", capRatio = 0.12},
    mortgageInterest = {name = "住房贷款利息", capRatio = 0.12},
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function money(value)
    return math.floor(math.max(0, tonumber(value) or 0) * 100 + 0.00001) / 100
end

local function signedMoney(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value * 100 + 0.00001) / 100
    end
    return math.ceil(value * 100 - 0.00001) / 100
end

local function trim(list, limit)
    while #list > limit do
        table.remove(list, 1)
    end
end

local function monthSerial(GD)
    local year = math.floor(tonumber(GD and GD.year) or 0)
    local month = clamp(math.floor(tonumber(GD and GD.month) or 1), 1, 12)
    return year * 12 + month
end

local function monthInfo(serial)
    serial = math.max(1, math.floor(tonumber(serial) or 1))
    local year = math.floor((serial - 1) / 12)
    return {serial = serial, year = year, month = ((serial - 1) % 12) + 1}
end

--- 无副作用的确定性伪随机数。相同状态和月份永远得到相同结果，UI 读取不会重骰。
local function stableRoll(seed)
    seed = tostring(seed or "")
    local value = 2166136261
    for index = 1, #seed do
        value = (value * 16777619 + seed:byte(index) * 97 + index * 31) % 2147483647
    end
    return (value % 1000000) / 1000000
end

local function boundedAmount(minimum, maximum, seed)
    local raw = minimum + (maximum - minimum) * stableRoll(seed)
    return money(math.floor(raw + 0.5))
end

local function addRecord(state, record)
    state.records[#state.records + 1] = record
    trim(state.records, RECORD_LIMIT)
end

local function addEventHistory(state, record)
    state.eventHistory[#state.eventHistory + 1] = record
    trim(state.eventHistory, EVENT_HISTORY_LIMIT)
end

local function addPlayerEvent(GD, text, kind)
    if GD and type(GD.AddEvent) == "function" then
        GD.AddEvent(text, kind or "info")
    end
end

local function contractById(state, contractId)
    for index, contract in ipairs(state.contracts) do
        if contract.id == contractId then return contract, index end
    end
    return nil, nil
end

local function ratePayment(principal, annualRate, months)
    principal = money(principal)
    months = math.max(1, math.floor(tonumber(months) or 1))
    local monthlyRate = math.max(0, tonumber(annualRate) or 0) / 12
    if monthlyRate <= 0 then return money(principal / months) end
    local factor = (1 + monthlyRate) ^ months
    return money(principal * monthlyRate * factor / (factor - 1))
end

local function creditRating(score)
    if score >= 800 then return "AAA"
    elseif score >= 760 then return "AA"
    elseif score >= 700 then return "A"
    elseif score >= 640 then return "BBB"
    elseif score >= 580 then return "BB"
    elseif score >= 500 then return "B"
    end
    return "C"
end

local function socialRating(score)
    if score >= 90 then return "优秀"
    elseif score >= 75 then return "良好"
    elseif score >= 55 then return "正常"
    elseif score >= 35 then return "受限"
    end
    return "严重受限"
end

local function getPlayer(GD)
    return GD and GD.player or nil
end

local function applyScorePenalty(state, financeDelta, socialDelta, reason)
    state.financeScore = clamp(math.floor((state.financeScore or 680) + financeDelta), 300, 850)
    state.socialCreditScore = clamp(math.floor((state.socialCreditScore or 70) + socialDelta), 0, 100)
    state.scoreHistory[#state.scoreHistory + 1] = {
        financeDelta = financeDelta, socialDelta = socialDelta, reason = reason,
    }
    trim(state.scoreHistory, RECORD_LIMIT)
end

local function buildNpcIndex(state)
    state.npcs = state.npcs or {}
    for _, definition in ipairs(NPCS) do
        local npc = state.npcs[definition.id] or {}
        npc.id = definition.id
        npc.name = definition.name
        npc.role = definition.role
        npc.baseRate = definition.baseRate
        npc.risk = definition.risk
        npc.maxAmount = definition.maxAmount
        npc.trust = clamp(tonumber(npc.trust) or 55, 0, 100)
        npc.defaultCount = math.max(0, math.floor(tonumber(npc.defaultCount) or 0))
        state.npcs[definition.id] = npc
    end
end

--- 初始化状态，并安全吸收可识别的旧版个人信用字段。
---@param player table
---@return table state
function PersonalFinanceEcosystem.Ensure(player)
    assert(type(player) == "table", "player 必须为 table")
    player.cash = math.max(0, tonumber(player.cash) or 0)
    local state = player.personalFinanceEcosystem or {}
    state.version = VERSION
    state.contracts = state.contracts or {}
    state.records = state.records or {}
    state.diary = state.diary or {}
    state.eventHistory = state.eventHistory or {}
    state.taxDeductions = state.taxDeductions or {}
    state.taxSourceIds = state.taxSourceIds or {}
    state.salaryFactors = state.salaryFactors or {}
    state.scoreHistory = state.scoreHistory or {}
    state.market = state.market or {quotes = {}, refreshedSerial = nil}
    state.pendingEvent = state.pendingEvent
    state.financeScore = clamp(math.floor(tonumber(state.financeScore or player.financeScore) or 680), 300, 850)
    state.socialCreditScore = clamp(math.floor(tonumber(state.socialCreditScore or player.socialCreditScore) or 70), 0, 100)
    state.contractSequence = math.max(0, math.floor(tonumber(state.contractSequence) or 0))
    state.diarySequence = math.max(0, math.floor(tonumber(state.diarySequence) or 0))
    state.eventSequence = math.max(0, math.floor(tonumber(state.eventSequence) or 0))
    state.lastMonthlySerial = tonumber(state.lastMonthlySerial) or nil
    state.lastContractProcessSerial = tonumber(state.lastContractProcessSerial) or nil
    state.lastEventSerial = tonumber(state.lastEventSerial) or nil
    state.eventCooldownUntil = tonumber(state.eventCooldownUntil) or 0
    buildNpcIndex(state)

    for _, contract in ipairs(state.contracts) do
        contract.outstanding = money(contract.outstanding or contract.amount or 0)
        contract.annualRate = math.max(0, tonumber(contract.annualRate) or 0)
        contract.monthlyPayment = money(contract.monthlyPayment or 0)
        contract.nextPaymentMonth = math.max(1, math.floor(tonumber(contract.nextPaymentMonth) or 1))
        contract.maturityMonth = math.max(contract.nextPaymentMonth, math.floor(tonumber(contract.maturityMonth) or contract.nextPaymentMonth))
        contract.status = contract.status or "active"
        contract.overdueCount = math.max(0, math.floor(tonumber(contract.overdueCount) or 0))
        contract.npcDelayCount = math.max(0, math.floor(tonumber(contract.npcDelayCount) or 0))
    end
    trim(state.contracts, CONTRACT_LIMIT)
    trim(state.records, RECORD_LIMIT)
    trim(state.diary, DIARY_LIMIT)
    trim(state.eventHistory, EVENT_HISTORY_LIMIT)
    trim(state.taxDeductions, TAX_RECORD_LIMIT)
    player.personalFinanceEcosystem = state
    return state
end

local function nextContractId(state)
    state.contractSequence = state.contractSequence + 1
    return "pfe-contract-" .. state.contractSequence
end

local function nextDiaryId(state)
    state.diarySequence = state.diarySequence + 1
    return "pfe-diary-" .. state.diarySequence
end

local function nextEventId(state)
    state.eventSequence = state.eventSequence + 1
    return "pfe-event-" .. state.eventSequence
end

--- 刷新本月 NPC 双向信用报价。重复读取同一月份不会重新计算。
function PersonalFinanceEcosystem.RefreshMarket(GD)
    local player = getPlayer(GD)
    if not player then return {refreshed = false, quotes = {}, reason = "未初始化个人数据"} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local serial = monthSerial(GD)
    if state.market.refreshedSerial == serial then
        return {refreshed = false, quotes = state.market.quotes, month = monthInfo(serial)}
    end

    local quotes = {}
    local scoreAdjustment = (state.financeScore - 680) / 10000
    for _, definition in ipairs(NPCS) do
        local npc = state.npcs[definition.id]
        local phase = stableRoll("market:" .. definition.id .. ":" .. serial)
        local borrowRate = clamp(definition.baseRate + (phase - 0.5) * 0.018 - scoreAdjustment, 0.035, 0.180)
        local lendRate = clamp(borrowRate + 0.010 + definition.risk * 0.06, 0.045, 0.220)
        local trustFactor = 0.60 + npc.trust / 250
        local borrowLimit = money(math.max(50, definition.maxAmount * trustFactor * clamp(state.financeScore / 700, 0.55, 1.20)))
        local lendLimit = money(math.max(30, definition.maxAmount * (0.45 + npc.trust / 200)))
        quotes[definition.id] = {
            npcId = definition.id, name = definition.name, role = definition.role,
            borrowAnnualRate = borrowRate, lendAnnualRate = lendRate,
            borrowLimit = borrowLimit, lendLimit = lendLimit,
            minMonths = 3, maxMonths = 24,
            financeRatingRequired = creditRating(state.financeScore),
        }
    end
    state.market.quotes = quotes
    state.market.refreshedSerial = serial
    addRecord(state, {kind = "market_refresh", serial = serial})
    return {refreshed = true, quotes = quotes, month = monthInfo(serial)}
end

local function quoteFor(state, npcId)
    return state.market.quotes and state.market.quotes[npcId] or nil
end

local function createContract(state, details)
    local contract = details
    contract.id = nextContractId(state)
    state.contracts[#state.contracts + 1] = contract
    trim(state.contracts, CONTRACT_LIMIT)
    return contract
end

--- 向具名 NPC 借入资金；只增加个人现金，不触碰公司现金或负债。
function PersonalFinanceEcosystem.BorrowFromNPC(GD, npcId, amount, months)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    PersonalFinanceEcosystem.RefreshMarket(GD)
    local quote = quoteFor(state, npcId)
    if not quote then return false, "未找到该信用市场参与者" end
    if state.financeScore < 430 then return false, "当前信用评分过低，暂不能借入" end

    amount = money(amount)
    months = math.floor(tonumber(months) or 0)
    if amount < 10 then return false, "借入金额至少10万" end
    if amount > quote.borrowLimit then return false, "超过本月可借额度" end
    if months < quote.minMonths or months > quote.maxMonths then return false, "期限须在3至24个月之间" end

    local serial = monthSerial(GD)
    local payment = ratePayment(amount, quote.borrowAnnualRate, months)
    local contract = createContract(state, {
        direction = "borrow", npcId = npcId, npcName = quote.name,
        amount = amount, outstanding = amount, annualRate = quote.borrowAnnualRate,
        monthlyPayment = payment, totalMonths = months, installmentsRemaining = months,
        startMonth = serial, nextPaymentMonth = serial + 1, maturityMonth = serial + months,
        overdueCount = 0, status = "active", purpose = "npc_credit_borrow",
    })
    player.cash = player.cash + amount
    addRecord(state, {kind = "borrow", contractId = contract.id, npcId = npcId, amount = amount, serial = serial})
    addPlayerEvent(GD, "向" .. quote.name .. "借入" .. amount .. "万，月供" .. payment .. "万", "info")
    return true, contract
end

--- 向具名 NPC 出借资金；资金仅从个人现金支出，NPC 偿还风险由借条记录承担。
function PersonalFinanceEcosystem.LendToNPC(GD, npcId, amount, months, purpose)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    PersonalFinanceEcosystem.RefreshMarket(GD)
    local quote = quoteFor(state, npcId)
    if not quote then return false, "未找到该信用市场参与者" end

    amount = money(amount)
    months = math.floor(tonumber(months) or 0)
    if amount < 10 then return false, "出借金额至少10万" end
    if amount > player.cash then return false, "个人现金不足" end
    if amount > quote.lendLimit then return false, "超过该 NPC 本月可承接额度" end
    if months < quote.minMonths or months > quote.maxMonths then return false, "期限须在3至24个月之间" end

    local serial = monthSerial(GD)
    local payment = ratePayment(amount, quote.lendAnnualRate, months)
    local contract = createContract(state, {
        direction = "lend", npcId = npcId, npcName = quote.name,
        amount = amount, outstanding = amount, annualRate = quote.lendAnnualRate,
        monthlyPayment = payment, totalMonths = months, installmentsRemaining = months,
        startMonth = serial, nextPaymentMonth = serial + 1, maturityMonth = serial + months,
        npcDelayCount = 0, status = "active", purpose = purpose or "npc_credit_lend",
    })
    player.cash = player.cash - amount
    addRecord(state, {kind = "lend", contractId = contract.id, npcId = npcId, amount = amount, serial = serial})
    addPlayerEvent(GD, "向" .. quote.name .. "出借" .. amount .. "万，约定月回款" .. payment .. "万", "info")
    return true, contract
end

--- 为朋友周转生成一张零息借条。该接口只由事件选项或明确调用触发。
function PersonalFinanceEcosystem.CreateFriendPromissoryNote(GD, friendName, amount, months)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    amount = money(amount)
    months = math.max(1, math.floor(tonumber(months) or 3))
    if amount <= 0 or amount > player.cash then return false, "个人现金不足" end

    local serial = monthSerial(GD)
    local contract = createContract(state, {
        direction = "lend", npcId = "friend", npcName = friendName or "朋友",
        amount = amount, outstanding = amount, annualRate = 0,
        monthlyPayment = ratePayment(amount, 0, months), totalMonths = months,
        installmentsRemaining = months, startMonth = serial, nextPaymentMonth = serial + 1,
        maturityMonth = serial + months, npcDelayCount = 0, status = "active",
        purpose = "friend_promissory_note", friendLoan = true,
    })
    player.cash = player.cash - amount
    addRecord(state, {kind = "friend_lend", contractId = contract.id, amount = amount, serial = serial})
    return true, contract
end

local function settleBorrowPayment(GD, player, state, contract, serial)
    local due = math.min(contract.monthlyPayment, money(contract.outstanding + contract.outstanding * contract.annualRate / 12))
    if player.cash + 0.00001 < due then
        contract.overdueCount = contract.overdueCount + 1
        contract.nextPaymentMonth = serial + 1
        applyScorePenalty(state, -math.min(30, 8 + contract.overdueCount * 4), -math.min(12, 2 + contract.overdueCount), "个人借条逾期")
        addRecord(state, {kind = "borrow_overdue", contractId = contract.id, amount = due, serial = serial})
        if contract.overdueCount >= 3 then
            contract.status = "defaulted"
            contract.recoveryValue = money(contract.outstanding * 0.75)
            addPlayerEvent(GD, contract.npcName .. "的借条已违约，信用评分受到严重影响", "danger")
        else
            addPlayerEvent(GD, contract.npcName .. "的借条本月逾期，已计入信用记录", "warning")
        end
        return {overdue = true, amount = due}
    end

    local interest = money(contract.outstanding * contract.annualRate / 12)
    local principalPaid = money(math.max(0, due - interest))
    if principalPaid <= 0 then principalPaid = math.min(contract.outstanding, due) end
    principalPaid = math.min(contract.outstanding, principalPaid)
    local actualPaid = money(interest + principalPaid)
    player.cash = math.max(0, player.cash - actualPaid)
    contract.outstanding = money(contract.outstanding - principalPaid)
    contract.installmentsRemaining = math.max(0, contract.installmentsRemaining - 1)
    contract.nextPaymentMonth = serial + 1
    contract.overdueCount = 0
    if contract.outstanding <= 0.01 or contract.installmentsRemaining <= 0 then
        if contract.outstanding > 0.01 and player.cash >= contract.outstanding then
            player.cash = player.cash - contract.outstanding
            actualPaid = money(actualPaid + contract.outstanding)
            contract.outstanding = 0
        end
        if contract.outstanding <= 0.01 then
            contract.outstanding = 0
            contract.status = "settled"
        end
    end
    addRecord(state, {kind = "borrow_payment", contractId = contract.id, amount = actualPaid, serial = serial})
    return {paid = actualPaid}
end

local function settleLendPayment(GD, player, state, contract, serial)
    local npc = state.npcs[contract.npcId] or {risk = contract.friendLoan and 0.18 or 0.10, trust = 50}
    local delayRisk = clamp((npc.risk or 0.10) + (100 - (npc.trust or 50)) / 1000 + contract.npcDelayCount * 0.06, 0.02, 0.55)
    local roll = stableRoll("repay:" .. contract.id .. ":" .. serial .. ":" .. contract.npcDelayCount)
    if roll < delayRisk then
        contract.npcDelayCount = contract.npcDelayCount + 1
        contract.nextPaymentMonth = serial + 1
        addRecord(state, {kind = "npc_delay", contractId = contract.id, serial = serial})
        if contract.npcDelayCount >= 3 then
            local recoveryRatio = clamp(0.35 + stableRoll("recovery:" .. contract.id) * 0.35 - (npc.risk or 0) * 0.20, 0.25, 0.70)
            local recovery = money(contract.outstanding * recoveryRatio)
            player.cash = player.cash + recovery
            contract.recoveryValue = recovery
            contract.outstanding = 0
            contract.status = "defaulted"
            npc.defaultCount = (npc.defaultCount or 0) + 1
            npc.trust = clamp((npc.trust or 50) - 18, 0, 100)
            addRecord(state, {kind = "npc_default_recovery", contractId = contract.id, amount = recovery, serial = serial})
            addPlayerEvent(GD, contract.npcName .. "发生违约，已回收" .. recovery .. "万", "warning")
        else
            addPlayerEvent(GD, contract.npcName .. "本月延迟回款，借条已顺延", "warning")
        end
        return {delayed = true}
    end

    local interest = money(contract.outstanding * contract.annualRate / 12)
    local principalPaid = money(math.max(0, contract.monthlyPayment - interest))
    if principalPaid <= 0 then principalPaid = math.min(contract.outstanding, contract.monthlyPayment) end
    principalPaid = math.min(contract.outstanding, principalPaid)
    local paid = money(interest + principalPaid)
    player.cash = player.cash + paid
    contract.outstanding = money(contract.outstanding - principalPaid)
    contract.installmentsRemaining = math.max(0, contract.installmentsRemaining - 1)
    contract.nextPaymentMonth = serial + 1
    contract.npcDelayCount = 0
    npc.trust = clamp((npc.trust or 50) + 1, 0, 100)
    if contract.outstanding <= 0.01 or contract.installmentsRemaining <= 0 then
        if contract.outstanding > 0 then
            player.cash = player.cash + contract.outstanding
            paid = money(paid + contract.outstanding)
        end
        contract.outstanding = 0
        contract.status = "settled"
    end
    addRecord(state, {kind = "npc_repayment", contractId = contract.id, amount = paid, serial = serial})
    return {paid = paid}
end

--- 执行所有到期借条。每月仅可结算一次；NPC 延迟和违约只在此处发生。
function PersonalFinanceEcosystem.ProcessContracts(GD)
    local player = getPlayer(GD)
    if not player then return {processed = false, reason = "未初始化个人数据"} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local serial = monthSerial(GD)
    if state.lastContractProcessSerial == serial then return {processed = false, reason = "本月已结算"} end

    local result = {processed = true, paid = 0, received = 0, overdue = 0, delayed = 0, defaults = 0}
    for _, contract in ipairs(state.contracts) do
        if contract.status == "active" and contract.nextPaymentMonth <= serial then
            local settlement
            if contract.direction == "borrow" then
                settlement = settleBorrowPayment(GD, player, state, contract, serial)
                result.paid = money(result.paid + (settlement.paid or 0))
                if settlement.overdue then result.overdue = result.overdue + 1 end
            else
                settlement = settleLendPayment(GD, player, state, contract, serial)
                result.received = money(result.received + (settlement.paid or 0))
                if settlement.delayed then result.delayed = result.delayed + 1 end
            end
            if contract.status == "defaulted" then result.defaults = result.defaults + 1 end
        end
    end
    state.lastContractProcessSerial = serial
    return result
end

--- 提前偿还玩家借入的 NPC 借条。可偿还全部或指定本金，绝不透支个人现金。
function PersonalFinanceEcosystem.EarlyRepay(GD, contractId, amount)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local contract = contractById(state, contractId)
    if not contract then return false, "未找到借条" end
    if contract.direction ~= "borrow" then return false, "仅玩家借入的借条可提前偿还" end
    if contract.status ~= "active" and contract.status ~= "defaulted" then return false, "该借条已结束" end

    local repay = money(amount or contract.outstanding)
    if repay <= 0 then return false, "还款金额无效" end
    repay = math.min(repay, contract.outstanding)
    if player.cash + 0.00001 < repay then return false, "个人现金不足" end

    player.cash = math.max(0, player.cash - repay)
    contract.outstanding = money(contract.outstanding - repay)
    if contract.outstanding <= 0.01 then
        contract.outstanding = 0
        contract.status = "settled"
        contract.installmentsRemaining = 0
    end
    addRecord(state, {kind = "early_repay", contractId = contract.id, amount = repay, serial = monthSerial(GD)})
    addPlayerEvent(GD, "已提前偿还" .. contract.npcName .. "的借条" .. repay .. "万", "success")
    return true, contract
end

function PersonalFinanceEcosystem.GetCreditSummary(GD)
    local player = getPlayer(GD)
    if not player then return {financeScore = 680, socialCreditScore = 70, contracts = {}} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local debt, receivable, riskAdjustedReceivable = 0, 0, 0
    local contracts = {}
    for _, contract in ipairs(state.contracts) do
        if contract.status == "active" or contract.status == "defaulted" then
            local row = {
                id = contract.id, direction = contract.direction, npcId = contract.npcId,
                npcName = contract.npcName, outstanding = contract.outstanding,
                annualRate = contract.annualRate, monthlyPayment = contract.monthlyPayment,
                nextPayment = monthInfo(contract.nextPaymentMonth), maturity = monthInfo(contract.maturityMonth),
                status = contract.status, overdueCount = contract.overdueCount,
                npcDelayCount = contract.npcDelayCount, purpose = contract.purpose,
            }
            contracts[#contracts + 1] = row
            if contract.direction == "borrow" then
                debt = debt + contract.outstanding
            else
                receivable = receivable + contract.outstanding
                local discount = contract.status == "defaulted" and 0 or clamp(0.08 + (contract.npcDelayCount or 0) * 0.12, 0.08, 0.65)
                riskAdjustedReceivable = riskAdjustedReceivable + contract.outstanding * (1 - discount)
            end
        end
    end
    return {
        financeScore = state.financeScore, financeRating = creditRating(state.financeScore),
        socialCreditScore = state.socialCreditScore, socialRating = socialRating(state.socialCreditScore),
        debt = money(debt), receivable = money(receivable), riskAdjustedReceivable = money(riskAdjustedReceivable),
        contracts = contracts, quotes = state.market.quotes or {},
    }
end

--- 社会类生活方式活动准入校验；非 social 分类不受本系统限制。
function PersonalFinanceEcosystem.CanAccessLifestyleItem(GD, item)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local category = type(item) == "table" and item.category or nil
    local itemId = type(item) == "table" and item.id or item
    if category ~= "social" and itemId ~= "club_membership" and itemId ~= "golf_membership"
        and itemId ~= "business_dinner" and itemId ~= "industry_association" then
        return true, "非社会圈层活动，不受社会信用限制"
    end
    local required = 40
    if itemId == "club_membership" then required = 50
    elseif itemId == "business_dinner" then required = 45
    elseif itemId == "industry_association" then required = 58
    elseif itemId == "golf_membership" then required = 65 end
    if state.socialCreditScore < required then
        return false, "社会信用评分不足，需达到" .. required .. "分"
    end
    return true, "社会信用评分符合准入要求"
end

local function currentTaxYear(GD)
    return math.floor(tonumber(GD and GD.year) or 0)
end

--- 记录一项合法税前扣除凭证。amount 仅记账，不会直接返税或改变现金。
function PersonalFinanceEcosystem.RecordTaxDeduction(GD, category, amount, sourceId, note)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local rule = TAX_CATEGORIES[category]
    if not rule then return false, "不支持的合法抵扣类别" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    amount = money(amount)
    sourceId = tostring(sourceId or "")
    if amount <= 0 then return false, "抵扣金额无效" end
    if sourceId == "" then return false, "sourceId 不能为空" end
    if state.taxSourceIds[sourceId] then return false, "该 sourceId 已登记，不能重复抵扣" end

    local row = {category = category, amount = amount, sourceId = sourceId, note = tostring(note or ""), year = currentTaxYear(GD)}
    state.taxDeductions[#state.taxDeductions + 1] = row
    state.taxSourceIds[sourceId] = row.year
    trim(state.taxDeductions, TAX_RECORD_LIMIT)
    return true, row
end

PersonalFinanceEcosystem.AddTaxDeduction = PersonalFinanceEcosystem.RecordTaxDeduction

local function estimateTax(income)
    income = math.max(0, tonumber(income) or 0)
    local brackets = {
        {threshold = 0, rate = 0.03}, {threshold = 36, rate = 0.10},
        {threshold = 144, rate = 0.20}, {threshold = 300, rate = 0.25},
        {threshold = 420, rate = 0.30}, {threshold = 660, rate = 0.35},
        {threshold = 960, rate = 0.45},
    }
    local tax, remaining = 0, income
    for index = #brackets, 1, -1 do
        local bracket = brackets[index]
        if remaining > bracket.threshold then
            tax = tax + (remaining - bracket.threshold) * bracket.rate
            remaining = bracket.threshold
        end
    end
    return money(tax)
end

local function compatibleTaxEstimate(GD, income)
    if GD and type(GD.CalcIncomeTax) == "function" then
        local ok, value = pcall(GD.CalcIncomeTax, income)
        if ok and type(value) == "number" then return money(value) end
    end
    return estimateTax(income)
end

--- 生成合法税务优化建议；仅提示可登记的真实扣除，不会自动返税、不会改变现金。
function PersonalFinanceEcosystem.GetTaxOptimizationAdvice(GD)
    local player = getPlayer(GD)
    if not player then return {advice = {}, estimatedTax = 0} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local year = currentTaxYear(GD)
    local taxableIncome = math.max(0, tonumber(player.yearlyIncome) or 0)
    local existing = {}
    for _, row in ipairs(state.taxDeductions) do
        if row.year == year then existing[row.category] = (existing[row.category] or 0) + (row.amount or 0) end
    end

    local advice, totalAccepted = {}, 0
    for category, rule in pairs(TAX_CATEGORIES) do
        local cap = money(taxableIncome * rule.capRatio)
        local accepted = math.min(cap, existing[category] or 0)
        totalAccepted = totalAccepted + accepted
        advice[#advice + 1] = {
            category = category, name = rule.name, declaredAmount = money(existing[category] or 0),
            maximumEligibleAmount = cap, acceptedDeduction = accepted,
            remainingEligibleAmount = money(math.max(0, cap - accepted)),
            note = "仅在有真实、合法且可留存凭证的情况下登记，不自动返税。",
        }
    end
    local beforeTax = compatibleTaxEstimate(GD, taxableIncome)
    local afterTax = compatibleTaxEstimate(GD, math.max(0, taxableIncome - totalAccepted))
    return {
        year = year, taxableIncome = taxableIncome, totalAcceptedDeduction = money(totalAccepted),
        estimatedTaxBefore = beforeTax, estimatedTaxAfter = afterTax,
        estimatedTaxSaving = money(math.max(0, beforeTax - afterTax)), advice = advice,
        disclaimer = "建议仅用于合法税前扣除规划，实际税务以适用法律、申报资料和主管机关核定为准。",
    }
end

--- 为当月工资生成并缓存波动因子。调用一次后同月不会变化。
function PersonalFinanceEcosystem.PrepareMonthlySalary(GD)
    local player = getPlayer(GD)
    if not player then return {factor = 1, adjustedSalary = 0, prepared = false} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local serial = monthSerial(GD)
    local saved = state.salaryFactors[tostring(serial)]
    if saved then return saved end

    local highIdentity = (player.prestige or 0) >= 150 or (player.netWorth or 0) >= 10000 or state.socialCreditScore >= 82
    local maxVariation = highIdentity and 0.15 or 0.05
    local factor = 1 + (stableRoll("salary:" .. serial .. ":" .. (player.founderName or "player")) * 2 - 1) * maxVariation
    local prepared = {
        serial = serial, factor = factor, maxVariation = maxVariation,
        baseSalary = money(player.salary or 0), adjustedSalary = money((player.salary or 0) * factor),
        highIdentity = highIdentity,
    }
    state.salaryFactors[tostring(serial)] = prepared
    local count = 0
    for _ in pairs(state.salaryFactors) do count = count + 1 end
    if count > 24 then
        local oldest = serial
        for key in pairs(state.salaryFactors) do oldest = math.min(oldest, tonumber(key) or oldest) end
        state.salaryFactors[tostring(oldest)] = nil
    end
    return prepared
end

function PersonalFinanceEcosystem.GetPreparedSalaryFactor(GD)
    return PersonalFinanceEcosystem.PrepareMonthlySalary(GD)
end

--- 记录实际工资结算结果，不直接转移现金，避免与 Personal.lua 的工资入账重复。
function PersonalFinanceEcosystem.RecordSalarySettlement(GD, settledBaseSalary, actualSalary)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local prepared = PersonalFinanceEcosystem.PrepareMonthlySalary(GD)
    local base = money(settledBaseSalary == nil and prepared.baseSalary or settledBaseSalary)
    local adjusted = money(actualSalary == nil and base * prepared.factor or actualSalary)
    local serial = monthSerial(GD)
    if state.salarySettlementSerial == serial then return true, state.lastSalarySettlement end
    local result = {serial = serial, baseSalary = base, factor = prepared.factor, adjustedSalary = adjusted, adjustment = signedMoney(adjusted - base)}
    state.salarySettlementSerial = serial
    state.lastSalarySettlement = result
    addRecord(state, {kind = "salary_settlement", serial = serial, amount = adjusted, adjustment = result.adjustment})
    return true, result
end

--- 建立可二手转卖的个人资产清单。房产只返回跳转提示，不能在这里出售。
function PersonalFinanceEcosystem.BuildResaleInventory(GD)
    local player = getPlayer(GD)
    if not player then return {} end
    PersonalFinanceEcosystem.Ensure(player)
    local inventory = {}
    for index, item in ipairs(player.lifestyleItems or {}) do
        inventory[#inventory + 1] = {
            resaleId = "lifestyle:" .. index, source = "lifestyleItems", sourceIndex = index,
            id = item.id, name = item.name or item.id or "生活方式资产", category = item.category,
            originalPrice = money(item.price), estimatedPrice = money(math.floor((item.price or 0) * 0.6)), canSell = true,
        }
    end
    local personalLife = player.personalLife or {}
    local records = personalLife.records or personalLife.assets or {}
    for key, record in pairs(records) do
        if type(record) == "table"
            and record.type == "asset"
            and not record.sold
            and not record.disposed
            and record.status ~= "sold" then
            local price = tonumber(record.currentValue) or tonumber(record.resaleValue) or tonumber(record.purchasePrice) or tonumber(record.price) or 0
            local ratio = clamp(tonumber(record.resaleRatio) or 0.6, 0, 1)
            inventory[#inventory + 1] = {
                resaleId = "personalLife:" .. tostring(key), source = "personalLife", sourceIndex = key,
                id = record.id or tostring(key), name = record.name or record.title or "私人资产",
                category = record.category or record.type, originalPrice = money(tonumber(record.purchasePrice) or tonumber(record.price) or price),
                estimatedPrice = money(price * ratio), canSell = true,
            }
        end
    end
    for index, property in ipairs(player.properties or {}) do
        inventory[#inventory + 1] = {
            resaleId = "property:" .. index, source = "properties", sourceIndex = index,
            id = property.id, name = property.name or "个人房产", category = "property",
            estimatedPrice = money(property.currentValue or property.purchasePrice or 0), canSell = false,
            message = "房产请前往个人房产页面出售，以便处理按揭与租赁状态。",
        }
    end
    return inventory
end

--- 按统一 60% 二手规则出售生活方式资产或 personalLife 私人资产。
function PersonalFinanceEcosystem.SellResaleAsset(GD, resaleId)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    resaleId = tostring(resaleId or "")
    local source, key = resaleId:match("^([^:]+):(.+)$")
    if not source then return false, "无效的转卖资产编号" end
    if source == "property" then return false, "房产请前往个人房产页面出售" end

    local asset
    if source == "lifestyle" then
        local index = tonumber(key)
        asset = index and (player.lifestyleItems or {})[index] or nil
        if not asset then return false, "未找到生活方式资产" end
        local proceeds = money(math.floor((asset.price or 0) * 0.6))
        player.cash = player.cash + proceeds
        player.prestige = math.max(0, (player.prestige or 0) - (asset.prestige or 0))
        local name = asset.name or "生活方式资产"
        table.remove(player.lifestyleItems, index)
        addRecord(state, {kind = "resale", source = source, amount = proceeds, serial = monthSerial(GD), name = name})
        return true, {name = name, proceeds = proceeds}
    end

    if source == "personalLife" then
        local personalLife = player.personalLife or {}
        local records = personalLife.records or personalLife.assets
        asset = records and records[key] or nil
        if not asset and records then asset = records[tonumber(key)] end
        if type(asset) ~= "table"
            or asset.type ~= "asset"
            or asset.sold
            or asset.disposed
            or asset.status == "sold" then
            return false, "未找到可转卖的私人资产"
        end
        local value = tonumber(asset.currentValue) or tonumber(asset.resaleValue) or tonumber(asset.purchasePrice) or tonumber(asset.price) or 0
        local ratio = clamp(tonumber(asset.resaleRatio) or 0.6, 0, 1)
        local proceeds = money(value * ratio)
        player.cash = money(player.cash + proceeds)
        asset.sold = true
        asset.disposed = true
        asset.status = "sold"
        asset.soldMonth = monthSerial(GD)
        asset.soldSerial = asset.soldMonth
        asset.salePrice = proceeds
        addRecord(state, {kind = "resale", source = source, amount = proceeds, serial = monthSerial(GD), name = asset.name or asset.title})
        return true, {name = asset.name or asset.title or "私人资产", proceeds = proceeds}
    end
    return false, "不支持的资产来源"
end

--- 财务日记只记录，不改变个人现金。
function PersonalFinanceEcosystem.AddDiary(GD, title, content, amount, entryType)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    title = tostring(title or ""):sub(1, 80)
    content = tostring(content or ""):sub(1, 1000)
    if title == "" then return false, "日记标题不能为空" end
    local entry = {
        id = nextDiaryId(state), title = title, content = content, amount = money(amount),
        type = tostring(entryType or "note"):sub(1, 40), serial = monthSerial(GD),
    }
    state.diary[#state.diary + 1] = entry
    trim(state.diary, DIARY_LIMIT)
    return true, entry
end

function PersonalFinanceEcosystem.DeleteDiary(GD, diaryId)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    for index, entry in ipairs(state.diary) do
        if entry.id == diaryId then
            table.remove(state.diary, index)
            return true
        end
    end
    return false, "未找到该日记"
end

function PersonalFinanceEcosystem.GetDiary(GD)
    local player = getPlayer(GD)
    if not player then return {} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local result = {}
    for index = #state.diary, 1, -1 do result[#result + 1] = state.diary[index] end
    return result
end

local function createFinancialEvent(GD, player, state, serial)
    local ordered = {"appliance", "medical", "friend", "family", "legal"}
    local kind = ordered[math.floor(stableRoll("event-kind:" .. serial .. ":" .. (player.founderName or "player")) * #ordered) + 1]
    local definition = EVENT_DEFINITIONS[kind]
    local amount = boundedAmount(definition.minCost, definition.maxCost, "event-amount:" .. kind .. ":" .. serial)
    local event = {
        id = nextEventId(state), kind = kind, title = definition.name, amount = amount,
        createdMonth = serial, deadlineMonth = serial + definition.deadline, status = "pending",
    }
    if kind == "appliance" then
        event.description = "家中关键家电损坏，需要安排维修。"
        event.options = {{id = "pay", name = "立即维修", cost = amount, effect = "避免后续额外损失"}, {id = "delay", name = "暂缓处理", cost = 0, effect = "到期后增加损失"}}
    elseif kind == "medical" then
        event.description = "出现需要尽快处理的医疗急诊。"
        event.options = {{id = "pay", name = "支付医疗费用", cost = amount, effect = "妥善处理"}, {id = "defer", name = "延后处理", cost = 0, effect = "社会信用与财务压力受损"}}
    elseif kind == "friend" then
        event.friendName = ({"陈航", "许岚", "韩松", "唐宁"})[math.floor(stableRoll("friend:" .. serial) * 4) + 1]
        event.description = event.friendName .. "希望借款周转，承诺分3个月归还。"
        event.options = {{id = "lend", name = "借出并签署借条", cost = amount, effect = "生成朋友借条"}, {id = "decline", name = "婉拒", cost = 0, effect = "无现金变化"}}
    elseif kind == "family" then
        event.description = "家庭出现紧急支出，需要在期限内安排资金。"
        event.options = {{id = "pay", name = "承担支出", cost = amount, effect = "维护家庭关系"}, {id = "partial", name = "先支付一半", cost = money(amount * 0.5), effect = "仍有一定后果"}}
    else
        event.description = "需要法律咨询和材料保全，及时处理可降低后续风险。"
        event.options = {{id = "pay", name = "聘请律师咨询", cost = amount, effect = "保留处理记录"}, {id = "ignore", name = "暂不处理", cost = 0, effect = "到期后信用受损"}}
    end
    state.pendingEvent = event
    state.eventCooldownUntil = serial + 2
    addEventHistory(state, {id = event.id, kind = kind, title = event.title, amount = amount, createdMonth = serial, status = "pending"})
    addPlayerEvent(GD, "突发财务事件：" .. event.title, "warning")
    return event
end

local function expirePendingEvent(GD, player, state, serial)
    local event = state.pendingEvent
    if not event or event.status ~= "pending" or serial <= event.deadlineMonth then return nil end
    local cashLoss = 0
    if event.kind == "appliance" then cashLoss = money(event.amount * 1.35)
    elseif event.kind == "family" then cashLoss = money(event.amount * 0.60)
    elseif event.kind == "medical" then cashLoss = money(event.amount * 0.35)
    elseif event.kind == "legal" then cashLoss = money(event.amount * 0.40) end
    local paid = math.min(player.cash, cashLoss)
    player.cash = math.max(0, player.cash - paid)
    applyScorePenalty(state, -8, -5, "突发财务事件过期")
    event.status = "expired"
    event.expiredMonth = serial
    event.cashLoss = paid
    state.pendingEvent = nil
    addEventHistory(state, {id = event.id, kind = event.kind, title = event.title, amount = paid, createdMonth = event.createdMonth, status = "expired"})
    addPlayerEvent(GD, event.title .. "已过期，产生后续损失并影响信用", "danger")
    return event
end

--- 处理突发财务事件的用户选项。所有支出先校验现金，不允许透支。
function PersonalFinanceEcosystem.ResolveFinancialEvent(GD, eventId, optionId)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local event = state.pendingEvent
    if not event or event.status ~= "pending" or event.id ~= eventId then return false, "未找到待处理财务事件" end
    if monthSerial(GD) > event.deadlineMonth then
        expirePendingEvent(GD, player, state, monthSerial(GD))
        return false, "事件已过期"
    end
    local option
    for _, candidate in ipairs(event.options or {}) do if candidate.id == optionId then option = candidate break end end
    if not option then return false, "无效的处理选项" end
    local cost = money(option.cost)
    if cost > player.cash then return false, "个人现金不足，无法选择该方案" end

    local extra = nil
    if event.kind == "friend" and optionId == "lend" then
        local ok, contractOrReason = PersonalFinanceEcosystem.CreateFriendPromissoryNote(GD, event.friendName, event.amount, 3)
        if not ok then return false, contractOrReason end
        extra = contractOrReason
    else
        player.cash = math.max(0, player.cash - cost)
    end
    if event.kind == "family" and optionId == "partial" then applyScorePenalty(state, -2, -1, "家庭紧急支出部分处理") end
    if event.kind == "medical" and optionId == "defer" then applyScorePenalty(state, -5, -3, "医疗急诊延后") end
    if event.kind == "legal" and optionId == "ignore" then applyScorePenalty(state, -4, -2, "法律咨询暂不处理") end
    event.status = "resolved"
    event.resolvedMonth = monthSerial(GD)
    event.optionId = optionId
    event.paid = cost
    state.pendingEvent = nil
    addEventHistory(state, {id = event.id, kind = event.kind, title = event.title, amount = cost, createdMonth = event.createdMonth, status = "resolved", optionId = optionId})
    addRecord(state, {kind = "financial_event", eventId = event.id, optionId = optionId, amount = cost, serial = monthSerial(GD)})
    addPlayerEvent(GD, event.title .. "已处理", "success")
    return true, {event = event, extra = extra}
end

--- 本模块的月结入口：刷新市场、结算借条、过期事件并以约12%概率产生一项新事件。
function PersonalFinanceEcosystem.MonthlyUpdate(GD)
    local player = getPlayer(GD)
    if not player then return {processed = false, reason = "未初始化个人数据"} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local serial = monthSerial(GD)
    if state.lastMonthlySerial == serial then return {processed = false, reason = "本月已更新"} end

    local market = PersonalFinanceEcosystem.RefreshMarket(GD)
    local contracts = PersonalFinanceEcosystem.ProcessContracts(GD)
    local expired = expirePendingEvent(GD, player, state, serial)
    local generated = nil
    if not state.pendingEvent and serial >= state.eventCooldownUntil then
        local chance = stableRoll("event-chance:" .. serial .. ":" .. (player.founderName or "player"))
        if chance < 0.12 then generated = createFinancialEvent(GD, player, state, serial) end
    end
    state.lastMonthlySerial = serial
    return {processed = true, market = market, contracts = contracts, expiredEvent = expired, pendingEvent = generated or state.pendingEvent}
end

--- 年度收口：归档年度税务统计，不改变现金或自动退税。
function PersonalFinanceEcosystem.YearlyClose(GD)
    local player = getPlayer(GD)
    if not player then return {closed = false, reason = "未初始化个人数据"} end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local year = currentTaxYear(GD)
    if state.lastYearlyCloseYear == year then return {closed = false, reason = "本年度已收口"} end
    local advice = PersonalFinanceEcosystem.GetTaxOptimizationAdvice(GD)
    state.yearlyClosings = state.yearlyClosings or {}
    state.yearlyClosings[#state.yearlyClosings + 1] = {
        year = year, taxableIncome = advice.taxableIncome, acceptedDeduction = advice.totalAcceptedDeduction,
        estimatedTaxBefore = advice.estimatedTaxBefore, estimatedTaxAfter = advice.estimatedTaxAfter,
    }
    trim(state.yearlyClosings, 20)
    state.lastYearlyCloseYear = year
    return {closed = true, summary = state.yearlyClosings[#state.yearlyClosings]}
end

--- 返回应计入个人净资产的调整：借入负债为负，出借债权按违约风险折价。
function PersonalFinanceEcosystem.GetNetWorthAdjustment(GD)
    local player = getPlayer(GD)
    if not player then return 0 end
    local state = PersonalFinanceEcosystem.Ensure(player)
    local adjustment = 0
    for _, contract in ipairs(state.contracts) do
        if contract.status == "active" or contract.status == "defaulted" then
            if contract.direction == "borrow" then
                adjustment = adjustment - contract.outstanding
            else
                local discount
                if contract.status == "defaulted" then
                    discount = 1
                else
                    discount = clamp(0.08 + (contract.npcDelayCount or 0) * 0.12 + (contract.friendLoan and 0.06 or 0), 0.08, 0.75)
                end
                adjustment = adjustment + contract.outstanding * (1 - discount)
            end
        end
    end
    return signedMoney(adjustment)
end

return PersonalFinanceEcosystem
