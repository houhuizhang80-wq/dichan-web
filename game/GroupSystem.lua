-- ============================================================================
-- GroupSystem.lua - 集团控股、资金、高管、策略与集团融资
-- ============================================================================

local GS = {}
local GDI = require("GroupDiversification")

GS.Diversification = GDI

local function getInternationalNetAssets(GD)
    local international = GD and GD.InternationalSystem
    if not international or not international.GetNetAssetValue then return 0, 0 end
    local summary = international.GetNetAssetValue(GD)
    if type(summary) ~= "table" then return 0, 0 end
    return math.max(0, tonumber(summary.netAssets) or 0), math.max(0, tonumber(summary.debt) or 0)
end

GS.STRATEGIES = {
    steady = {
        name = "稳健经营",
        desc = "重视现金安全与低杠杆，适合成熟公司",
        targetDebtRatio = 0.35,
        cashflow = {reserveRatio = 0.40, acquisitionRatio = 0.20, developmentRatio = 0.40},
    },
    growth = {
        name = "积极扩张",
        desc = "提高拿地和开发投入，在安全上限内使用杠杆",
        targetDebtRatio = 0.55,
        cashflow = {reserveRatio = 0.20, acquisitionRatio = 0.40, developmentRatio = 0.40},
    },
    asset = {
        name = "持有运营",
        desc = "优先长期持有、出租运营与稳定现金流",
        targetDebtRatio = 0.40,
        cashflow = {reserveRatio = 0.30, acquisitionRatio = 0.20, developmentRatio = 0.50},
    },
}
GS.STRATEGY_ORDER = {"steady", "growth", "asset"}

GS.LOAN_PRODUCTS = {
    group_credit = {
        name = "集团综合授信",
        desc = "以集团净资产和下属公司股权价值为基础的综合信用贷款",
        rate = 4.5,
        months = 36,
        durationRange = {12, 60},
        maxRatio = 0.25,
    },
    group_acquisition = {
        name = "集团并购贷款",
        desc = "用于集团扩张、并购和对子公司的资本安排",
        rate = 5.2,
        months = 60,
        durationRange = {24, 120},
        maxRatio = 0.35,
    },
}
GS.LOAN_PRODUCT_ORDER = {"group_credit", "group_acquisition"}

function GS.CreateDefaultData()
    return {
        active = false,
        id = nil,
        name = "",
        registeredCapital = 0,
        cash = 0,
        totalDebt = 0,
        personalShareRatio = 1.0,
        totalShares = 10000,
        personalShares = 10000,
        members = {},
        companyStrategies = {},
        executives = {},
        loans = {},
        dividendRate = 0.50,
        retainedEarnings = 0,
        annualProfit = 0,
        monthlyIncome = 0,
        monthlyExpense = 0,
        lastMonthlyIncome = 0,
        lastMonthlyExpense = 0,
        executiveSalaryArrears = 0,
        totalCompanyDividends = 0,
        totalEquitySaleIncome = 0,
        totalDividendsToPersonal = 0,
        totalPersonalCapitalInjected = 0,
        totalPersonalTransfersOut = 0,
        diversification = GDI.CreateDefaultData(),
        formedYear = nil,
        formedMonth = nil,
    }
end

function GS.EnsureFields(GD)
    if type(GD.group) ~= "table" then GD.group = GS.CreateDefaultData() end
    local group = GD.group
    group.active = group.active == true
    group.name = group.name or ""
    group.registeredCapital = group.registeredCapital or 0
    group.cash = group.cash or 0
    group.totalDebt = group.totalDebt or 0
    group.personalShareRatio = group.personalShareRatio or 1.0
    group.totalShares = group.totalShares or 10000
    group.personalShares = group.personalShares or math.floor(group.totalShares * group.personalShareRatio)
    group.members = group.members or {}
    group.companyStrategies = group.companyStrategies or {}
    group.executives = group.executives or {}
    group.loans = group.loans or {}
    group.dividendRate = group.dividendRate or 0.50
    group.retainedEarnings = group.retainedEarnings or 0
    group.annualProfit = group.annualProfit or 0
    group.monthlyIncome = group.monthlyIncome or 0
    group.monthlyExpense = group.monthlyExpense or 0
    group.lastMonthlyIncome = group.lastMonthlyIncome or 0
    group.lastMonthlyExpense = group.lastMonthlyExpense or 0
    group.executiveSalaryArrears = group.executiveSalaryArrears or 0
    group.totalCompanyDividends = group.totalCompanyDividends or 0
    group.totalEquitySaleIncome = group.totalEquitySaleIncome or 0
    group.totalDividendsToPersonal = group.totalDividendsToPersonal or 0
    group.totalPersonalCapitalInjected = group.totalPersonalCapitalInjected or 0
    group.totalPersonalTransfersOut = group.totalPersonalTransfersOut or 0
    GDI.EnsureFields(GD)
    return group
end

function GS.IsActive(GD)
    local group = GS.EnsureFields(GD)
    return group.active == true
end

local function findRecord(GD, companyId)
    if not companyId or not GD.companyPortfolio then return nil end
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        if tostring(record.id) == tostring(companyId) then return record end
    end
    return nil
end

local function findMember(group, companyId)
    for _, member in ipairs(group.members or {}) do
        if tostring(member.companyId) == tostring(companyId) then return member end
    end
    return nil
end

local function getFounderShareholder(company)
    local gov = company and company.governance
    if not gov then return nil end
    for _, shareholder in ipairs(gov.shareholders or {}) do
        if shareholder.id == "founder" then return shareholder end
    end
    return nil
end

local function getOwnershipRatio(record)
    if not record then return 0 end
    local company = record.state and record.state.company
    local shareholder = getFounderShareholder(company)
    if shareholder then return shareholder.ratio or 0 end
    return record.founderRatio or 0
end

local function getCompanyValue(record)
    if not record then return 0 end
    local company = record.state and record.state.company or {}
    local gov = company.governance
    return math.max(
        record.totalAssets or company.totalAssets or 0,
        gov and (gov.lastValuation or 0) or 0,
        company.registeredCapital or 0
    )
end

function GS.GetCompanyOwnershipLabel(GD, companyId)
    local group = GS.EnsureFields(GD)
    local member = findMember(group, companyId)
    if group.active and member and member.active ~= false and (member.ownershipRatio or 0) > 0 then
        return "集团持股", member.ownershipRatio or 0
    end
    local record = findRecord(GD, companyId)
    return "个人持股", record and (record.founderRatio or 0) or 0
end

function GS.IsMemberCompany(GD, companyId)
    local group = GS.EnsureFields(GD)
    if not group.active then return false end
    local member = findMember(group, companyId)
    return member ~= nil and member.active ~= false and (member.ownershipRatio or 0) > 0
end

function GS.GetMember(GD, companyId)
    local group = GS.EnsureFields(GD)
    return findMember(group, companyId)
end

local function normalizeName(name)
    local result = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local len = utf8.len(result)
    if not len then return nil, "集团名称包含无效字符" end
    if len < 2 then return nil, "集团名称至少2个字" end
    if len > 20 then return nil, "集团名称最多20个字" end
    if result:find("[%c\r\n]") then return nil, "集团名称不能包含换行或控制字符" end
    return result
end

function GS.GetEligibleCompanies(GD)
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    if GD.EnsureCompanyPortfolio then GD.EnsureCompanyPortfolio(true) end
    local group = GS.EnsureFields(GD)
    local result = {}
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        local ratio = record.founderRatio or getOwnershipRatio(record)
        if record.status == "operating"
            and ratio >= 0.50
            and not (group.active and GS.IsMemberCompany(GD, record.id))
        then
            result[#result + 1] = record
        end
    end
    return result
end

function GS.GetFormationCompanies(GD)
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    if GD.EnsureCompanyPortfolio then GD.EnsureCompanyPortfolio(true) end
    local result = {}
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        local ratio = record.founderRatio or getOwnershipRatio(record)
        if record.status == "operating" and ratio > 0 then
            result[#result + 1] = record
        end
    end
    return result
end

local function validateCompanyTransfer(record)
    local company = record and record.state and record.state.company
    if not company then return false, "公司快照数据缺失" end
    local shareholder = getFounderShareholder(company)
    if not shareholder or (shareholder.ratio or 0) <= 0 then
        return false, "集团发起人未持有该公司股权"
    end
    return true
end

local function transferCompanyToGroup(GD, record)
    local group = GS.EnsureFields(GD)
    local company = record and record.state and record.state.company
    local valid, validationError = validateCompanyTransfer(record)
    if not valid then return false, validationError end
    local shareholder = getFounderShareholder(company)
    shareholder.name = group.name
    shareholder.ownerType = "group"
    shareholder.groupId = group.id
    record.ownerType = "group"
    record.groupId = group.id
    record.founderRatio = shareholder.ratio

    local member = findMember(group, record.id)
    if not member then
        member = {
            companyId = record.id,
            joinedYear = GD.year,
            joinedMonth = GD.month,
        }
        group.members[#group.members + 1] = member
    end
    member.name = record.name
    member.city = record.city
    member.ownershipRatio = shareholder.ratio
    member.active = true
    group.companyStrategies[tostring(record.id)] = group.companyStrategies[tostring(record.id)] or "steady"

    if tostring(GD.activeCompanyId) == tostring(record.id) then
        GD.company = company
    end
    return true
end

function GS.FormGroup(GD, name, capital, companyIds)
    local group = GS.EnsureFields(GD)
    if group.active then return false, "集团已经成立" end
    local normalizedName, nameError = normalizeName(name)
    if not normalizedName then return false, nameError end
    capital = math.floor(tonumber(capital) or 0)
    if capital <= 0 then return false, "请输入有效的集团注册资本" end
    if not GD.player then return false, "个人数据未初始化" end
    if (GD.player.cash or 0) < capital then return false, "个人现金不足" end
    if (GD.companyPortfolio and GD.companyPortfolio.companies and #GD.companyPortfolio.companies or 0) < 2 then
        return false, "至少需要两家公司才能组建集团"
    end

    local selected = {}
    for _, companyId in ipairs(companyIds or {}) do selected[tostring(companyId)] = true end
    local records = {}
    for _, record in ipairs(GS.GetFormationCompanies(GD)) do
        if selected[tostring(record.id)] then records[#records + 1] = record end
    end
    if #records < 2 then return false, "至少选择两家可控公司组建集团" end
    for _, record in ipairs(records) do
        local valid, validationError = validateCompanyTransfer(record)
        if not valid then return false, validationError end
    end

    GD.group = GS.CreateDefaultData()
    group = GD.group
    group.active = true
    group.id = "group_" .. tostring(GD.totalMonths or 0) .. "_" .. tostring(GD.year or 0)
    group.name = normalizedName
    group.registeredCapital = capital
    group.cash = capital
    group.formedYear = GD.year
    group.formedMonth = GD.month

    for _, record in ipairs(records) do
        local ok, err = transferCompanyToGroup(GD, record)
        if not ok then return false, err end
    end
    GD.player.cash = GD.player.cash - capital
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    GD.AddEvent("“" .. group.name .. "”正式成立，注册资本" .. GD.FormatMoney(capital)
        .. "，首批控股" .. tostring(#records) .. "家公司", "success")
    print("[GROUP] formed name=" .. group.name .. " members=" .. tostring(#records)
        .. " capital=" .. tostring(capital))
    return true, "集团成立成功"
end

function GS.AddMemberCompany(GD, companyId)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    if GS.IsMemberCompany(GD, companyId) then return false, "该公司已属于集团" end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    local record = findRecord(GD, companyId)
    if not record or record.status ~= "operating" or (record.founderRatio or 0) <= 0 then
        return false, "只能纳入集团仍持有股份的经营公司"
    end
    local ok, msg = transferCompanyToGroup(GD, record)
    if not ok then return false, msg end
    GS.ApplyCompanyStrategy(GD, companyId)
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    GD.AddEvent(record.name .. "已纳入" .. group.name, "success")
    return true, "公司已纳入集团"
end

function GS.RegisterNewCompany(GD, companyId)
    local group = GS.EnsureFields(GD)
    if not group.active then return false end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    local record = findRecord(GD, companyId or GD.activeCompanyId)
    if not record then return false, "新公司组合记录缺失" end
    local ok, msg = transferCompanyToGroup(GD, record)
    if not ok then return false, msg end
    GS.ApplyCompanyStrategy(GD, record.id)
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    return true, "新公司已登记为集团全资子公司"
end

function GS.NormalizeMembership(GD)
    local group = GS.EnsureFields(GD)
    if not group.active then return group end
    for _, member in ipairs(group.members) do
        local record = findRecord(GD, member.companyId)
        if record then
            local ratio = getOwnershipRatio(record)
            member.name = record.name or member.name
            member.city = record.city or member.city
            member.ownershipRatio = ratio
            member.active = record.status == "operating" and ratio > 0
            if member.active then
                record.ownerType = "group"
                record.groupId = group.id
                local shareholder = getFounderShareholder(record.state and record.state.company)
                if shareholder then
                    shareholder.ownerType = "group"
                    shareholder.groupId = group.id
                    shareholder.name = group.name
                end
            end
        else
            member.active = false
            member.ownershipRatio = 0
        end
    end
    return group
end

function GS.GetSummary(GD)
    local group = GS.NormalizeMembership(GD)
    local equityValue = 0
    local activeMembers = 0
    local whollyOwned = 0
    for _, member in ipairs(group.members or {}) do
        if member.active ~= false and (member.ownershipRatio or 0) > 0 then
            local record = findRecord(GD, member.companyId)
            equityValue = equityValue + math.floor(getCompanyValue(record) * (member.ownershipRatio or 0))
            activeMembers = activeMembers + 1
            if (member.ownershipRatio or 0) >= 0.999999 then whollyOwned = whollyOwned + 1 end
        end
    end
    local diversification = GDI.EnsureFields(GD)
    local industryAssetValue = 0
    for _, business in pairs(diversification.businesses or {}) do
        if business.active ~= false then
            industryAssetValue = industryAssetValue + (business.assetValue or 0)
        end
    end
    local internationalNetAssets, internationalDebt = getInternationalNetAssets(GD)
    local totalAssets = (group.cash or 0) + equityValue + industryAssetValue + internationalNetAssets + internationalDebt
    local totalDebt = (group.totalDebt or 0) + internationalDebt
    local netAssets = totalAssets - totalDebt
    return {
        cash = group.cash or 0,
        equityValue = equityValue,
        industryAssetValue = industryAssetValue,
        internationalNetAssets = internationalNetAssets,
        internationalDebt = internationalDebt,
        totalAssets = totalAssets,
        totalDebt = totalDebt,
        netAssets = netAssets,
        activeMembers = activeMembers,
        whollyOwned = whollyOwned,
        monthlyIncome = group.monthlyIncome or 0,
        monthlyExpense = group.monthlyExpense or 0,
        retainedEarnings = group.retainedEarnings or 0,
    }
end

function GS.GetPersonalEquityValue(GD)
    local group = GS.EnsureFields(GD)
    if not group.active then return 0 end
    local summary = GS.GetSummary(GD)
    return math.floor(math.max(0, summary.netAssets) * (group.personalShareRatio or 1.0))
end

local function syncGroupExecutivesToCompany(GD, company)
    local group = GS.EnsureFields(GD)
    local gov = company and company.governance
    if not gov then return end
    gov.executives = gov.executives or {}
    for roleId, executive in pairs(group.executives or {}) do
        if not gov.executives[roleId] then
            gov.executives[roleId] = {
                id = roleId,
                name = executive.name,
                hiredMonth = executive.hiredMonth,
                hiredYear = executive.hiredYear,
                hiredMon = executive.hiredMon,
                salary = 0,
                totalPaid = 0,
                source = "group",
                groupId = group.id,
            }
        end
    end
    for roleId, executive in pairs(gov.executives) do
        if executive.source == "group" and not group.executives[roleId] then
            gov.executives[roleId] = nil
        end
    end
end

function GS.ApplyCompanyStrategy(GD, companyId)
    local group = GS.EnsureFields(GD)
    if not group.active or not GS.IsMemberCompany(GD, companyId) then return false, "目标公司不属于集团" end
    local industryBusiness = group.diversification
        and group.diversification.businesses
        and group.diversification.businesses[tostring(companyId)]
    if industryBusiness and industryBusiness.companyKind == "industry" then
        local record = findRecord(GD, companyId)
        local company = record and record.state and record.state.company
        local gov = company and company.governance
        if gov then
            gov.fullManagement = false
            gov.pendingCeoReport = nil
        end
        return false, "产业公司采用手动经营，不接受集团CEO托管"
    end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    local record = findRecord(GD, companyId)
    local company = record and record.state and record.state.company
    local gov = company and company.governance
    if not gov then return false, "公司治理数据缺失" end
    local strategyId = group.companyStrategies[tostring(companyId)] or "steady"
    local strategy = GS.STRATEGIES[strategyId] or GS.STRATEGIES.steady
    group.companyStrategies[tostring(companyId)] = strategyId

    syncGroupExecutivesToCompany(GD, company)
    gov.groupStrategyId = strategyId
    gov.ceoTargetDebtRatio = strategy.targetDebtRatio
    gov.ceoCashflowPolicy = {
        reserveRatio = strategy.cashflow.reserveRatio,
        acquisitionRatio = strategy.cashflow.acquisitionRatio,
        developmentRatio = strategy.cashflow.developmentRatio,
    }
    if gov.ceoReportEnabled == nil then gov.ceoReportEnabled = true end
    gov.ceoReportFrequency = gov.ceoReportFrequency or "monthly"
    if group.executives.ceo then
        gov.fullManagement = true
        gov.fullManagementSince = gov.fullManagementSince or GD.totalMonths
    else
        local companyCeo = gov.executives.ceo
        if not companyCeo or companyCeo.source == "group" then
            gov.fullManagement = false
            gov.pendingCeoReport = nil
        end
    end

    record.state.company = company
    if tostring(GD.activeCompanyId) == tostring(companyId) then GD.company = company end
    return true, "经营策略已更新为“" .. strategy.name .. "”"
end

function GS.SetCompanyStrategy(GD, companyId, strategyId)
    if not GS.STRATEGIES[strategyId] then return false, "未知经营策略" end
    local group = GS.EnsureFields(GD)
    group.companyStrategies[tostring(companyId)] = strategyId
    local ok, msg = GS.ApplyCompanyStrategy(GD, companyId)
    if ok then
        local member = findMember(group, companyId)
        GD.AddEvent((member and member.name or "下属公司") .. "已执行集团策略：" .. GS.STRATEGIES[strategyId].name, "success")
    end
    return ok, msg
end

function GS.SyncAllMemberManagement(GD)
    local group = GS.EnsureFields(GD)
    local count = 0
    for _, member in ipairs(group.members or {}) do
        if member.active ~= false then
            local ok = GS.ApplyCompanyStrategy(GD, member.companyId)
            if ok then count = count + 1 end
        end
    end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    return count
end

local function getExecutiveRole(GD, roleId)
    local roles = GD.Governance and GD.Governance.EXECUTIVE_ROLES or {}
    for _, role in ipairs(roles) do
        if role.id == roleId then return role end
    end
    return nil
end

function GS.HireExecutive(GD, roleId)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    local role = getExecutiveRole(GD, roleId)
    if not role then return false, "未知高管职位" end
    if group.executives[roleId] then return false, role.name .. "已在集团任职" end
    if (group.cash or 0) < (role.bonus or 0) then
        return false, "集团资金不足，签约奖金需" .. GD.FormatMoney(role.bonus or 0)
    end
    group.cash = group.cash - (role.bonus or 0)
    group.executives[roleId] = {
        id = roleId,
        name = role.name,
        salary = role.salary or 0,
        hiredMonth = GD.totalMonths,
        hiredYear = GD.year,
        hiredMon = GD.month,
        totalPaid = role.bonus or 0,
    }
    GS.SyncAllMemberManagement(GD)
    return true, "集团已聘用" .. role.name
end

function GS.FireExecutive(GD, roleId)
    local group = GS.EnsureFields(GD)
    local executive = group.executives[roleId]
    if not executive then return false, "该集团职位当前空缺" end
    local role = getExecutiveRole(GD, roleId)
    local severance = math.floor((((role and role.salary or executive.salary or 0) / 12) * 3) * 100) / 100
    if (group.cash or 0) < severance then return false, "集团资金不足以支付遣散费" end
    group.cash = group.cash - severance
    group.executives[roleId] = nil

    for _, member in ipairs(group.members or {}) do
        local record = findRecord(GD, member.companyId)
        local gov = record and record.state and record.state.company and record.state.company.governance
        if gov and gov.executives and gov.executives[roleId] and gov.executives[roleId].source == "group" then
            gov.executives[roleId] = nil
        end
        if roleId == "ceo" and gov then
            gov.fullManagement = false
            gov.pendingCeoReport = nil
        end
        if tostring(GD.activeCompanyId) == tostring(member.companyId) and record and record.state then
            GD.company = record.state.company
        end
    end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    return true, "集团已解聘" .. (role and role.name or executive.name)
end

function GS.InjectPersonalCapital(GD, amount)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    if not GD.player then return false, "个人数据未初始化" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效注资金额" end
    if (GD.player.cash or 0) < amount then return false, "个人现金不足" end

    GD.player.cash = GD.player.cash - amount
    group.cash = group.cash + amount
    group.registeredCapital = (group.registeredCapital or 0) + amount
    group.totalPersonalCapitalInjected = (group.totalPersonalCapitalInjected or 0) + amount
    GD.AddEvent("个人向" .. group.name .. "注资" .. GD.FormatMoney(amount), "success")
    print("[GROUP] personal capital injected amount=" .. tostring(amount)
        .. " groupCash=" .. tostring(group.cash) .. " personalCash=" .. tostring(GD.player.cash))
    return true, "个人向集团注资成功"
end

local function getPersonalDividendLimit(group)
    local distributable = math.max(0, math.min(group.cash or 0, group.retainedEarnings or 0))
    return math.floor(distributable * math.max(0, math.min(1, group.personalShareRatio or 1.0)))
end

local function creditPersonalDividend(GD, group, amount)
    group.cash = group.cash - amount
    group.retainedEarnings = math.max(0, (group.retainedEarnings or 0) - amount)
    group.totalDividendsToPersonal = (group.totalDividendsToPersonal or 0) + amount
    GD.player.cash = (GD.player.cash or 0) + amount
    GD.player.totalDividends = (GD.player.totalDividends or 0) + amount
    GD.player.totalIncome = (GD.player.totalIncome or 0) + amount
    GD.player.yearlyIncome = (GD.player.yearlyIncome or 0) + amount
    GD.player.yearlyDividends = (GD.player.yearlyDividends or 0) + amount
end

function GS.GetPersonalTransferLimit(GD)
    return getPersonalDividendLimit(GS.EnsureFields(GD))
end

function GS.TransferToPersonal(GD, amount)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    if not GD.player then return false, "个人数据未初始化" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效转出金额" end
    local transferLimit = getPersonalDividendLimit(group)
    if amount > transferLimit then
        return false, "超过个人当前可分配额度，最多可转出" .. GD.FormatMoney(transferLimit)
    end

    creditPersonalDividend(GD, group, amount)
    group.totalPersonalTransfersOut = (group.totalPersonalTransfersOut or 0) + amount
    GD.AddEvent(group.name .. "向个人股东分红" .. GD.FormatMoney(amount), "info")
    print("[GROUP] transferred dividend to personal amount=" .. tostring(amount)
        .. " groupCash=" .. tostring(group.cash) .. " retainedEarnings=" .. tostring(group.retainedEarnings)
        .. " personalCash=" .. tostring(GD.player.cash))
    return true, "集团分红已转入个人账户"
end

function GS.InjectCapital(GD, companyId, amount)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    local member = findMember(group, companyId)
    if not member or member.active == false then return false, "目标公司不属于集团" end
    if (member.ownershipRatio or 0) < 0.999999 then return false, "只能向集团全资控股公司注资" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效注资金额" end
    if (group.cash or 0) < amount then return false, "集团账户资金不足" end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    local record = findRecord(GD, companyId)
    local company = record and record.state and record.state.company
    if not company then return false, "公司快照数据缺失" end

    group.cash = group.cash - amount
    company.cash = (company.cash or 0) + amount
    company.totalAssets = (company.totalAssets or 0) + amount
    company.registeredCapital = (company.registeredCapital or 0) + amount
    if company.assetBreakdown then company.assetBreakdown.cash = company.cash end
    record.cash = company.cash
    record.totalAssets = company.totalAssets
    record.state.company = company
    if tostring(GD.activeCompanyId) == tostring(companyId) then
        GD.company = company
        GD.CaptureActiveCompanyState()
    end
    GD.AddEvent(group.name .. "向" .. (record.name or "全资公司") .. "注资" .. GD.FormatMoney(amount), "success")
    return true, "集团注资成功"
end

function GS.ReceiveCompanyDividend(GD, companyId, amount)
    local group = GS.EnsureFields(GD)
    amount = math.floor(tonumber(amount) or 0)
    if not group.active or not GS.IsMemberCompany(GD, companyId) or amount <= 0 then return false end
    group.cash = group.cash + amount
    group.monthlyIncome = group.monthlyIncome + amount
    group.annualProfit = group.annualProfit + amount
    group.retainedEarnings = group.retainedEarnings + amount
    group.totalCompanyDividends = group.totalCompanyDividends + amount
    return true
end

function GS.CreditCompanyEquitySale(GD, companyId, amount)
    local group = GS.EnsureFields(GD)
    amount = math.floor(tonumber(amount) or 0)
    if not group.active or not GS.IsMemberCompany(GD, companyId) or amount <= 0 then return false end
    group.cash = group.cash + amount
    group.monthlyIncome = group.monthlyIncome + amount
    group.annualProfit = group.annualProfit + amount
    group.retainedEarnings = group.retainedEarnings + amount
    group.totalEquitySaleIncome = group.totalEquitySaleIncome + amount
    return true
end

function GS.OnCompanyOwnershipChanged(GD, companyId, ratio)
    local group = GS.EnsureFields(GD)
    local member = findMember(group, companyId)
    if not member then return false end
    ratio = math.max(0, tonumber(ratio) or 0)
    member.ownershipRatio = ratio
    member.active = ratio > 0
    local record = findRecord(GD, companyId)
    if record then
        record.founderRatio = ratio
        if ratio <= 0 then
            record.ownerType = nil
            record.groupId = nil
        end
    end
    return true
end

function GS.GetLoanOffer(GD, productId)
    local product = GS.LOAN_PRODUCTS[productId]
    if not product then return nil end
    local group = GS.EnsureFields(GD)
    local summary = GS.GetSummary(GD)
    local assets = math.max(1, summary.totalAssets)
    local leverageRoom = math.max(0, math.floor((0.65 * assets - (group.totalDebt or 0)) / 0.35))
    local productRoom = math.max(0, math.floor(math.max(0, summary.netAssets) * product.maxRatio))
    return {
        product = product,
        maxLoan = math.min(leverageRoom, productRoom),
        debtRatio = (group.totalDebt or 0) / assets,
    }
end

function GS.ApplyLoan(GD, productId, amount, months, repayMethod)
    local group = GS.EnsureFields(GD)
    if not group.active then return false, "请先成立集团" end
    local offer = GS.GetLoanOffer(GD, productId)
    if not offer then return false, "未知集团贷款产品" end
    amount = math.floor(tonumber(amount) or 0)
    months = math.floor(tonumber(months) or offer.product.months)
    months = math.max(offer.product.durationRange[1], math.min(offer.product.durationRange[2], months))
    if amount <= 0 then return false, "请输入有效贷款金额" end
    if amount > offer.maxLoan then return false, "超过集团当前可贷额度" end
    local loan = {
        id = "group_loan_" .. tostring(GD.totalMonths or 0) .. "_" .. tostring(#group.loans + 1),
        name = offer.product.name,
        productId = productId,
        amount = amount,
        rate = offer.product.rate,
        totalMonths = months,
        remainMonths = months,
        repayMethod = repayMethod == "bullet" and "bullet" or "interest_monthly",
        accruedInterest = 0,
    }
    group.loans[#group.loans + 1] = loan
    group.cash = group.cash + amount
    group.totalDebt = group.totalDebt + amount
    GD.AddEvent(group.name .. "获批" .. offer.product.name .. GD.FormatMoney(amount), "success")
    return true, "集团贷款申请成功"
end

function GS.GetEarlyRepayAmount(loan)
    if not loan then return 0 end
    return math.floor((loan.amount or 0) + (loan.accruedInterest or 0))
end

function GS.EarlyRepayLoan(GD, loanIndex)
    local group = GS.EnsureFields(GD)
    local loan = group.loans[loanIndex]
    if not loan then return false, "集团贷款不存在" end
    local total = GS.GetEarlyRepayAmount(loan)
    if (group.cash or 0) < total then return false, "集团现金不足，还款需要" .. GD.FormatMoney(total) end
    group.cash = group.cash - total
    group.totalDebt = math.max(0, (group.totalDebt or 0) - (loan.amount or 0))
    table.remove(group.loans, loanIndex)
    GD.AddEvent(group.name .. "已提前还清" .. (loan.name or "集团贷款") .. GD.FormatMoney(total), "success")
    return true, "集团贷款已还清"
end

function GS.SetDividendRate(GD, rate)
    local group = GS.EnsureFields(GD)
    group.dividendRate = math.max(0, math.min(0.80, tonumber(rate) or 0))
    return true
end

function GS.DistributeDividend(GD)
    local group = GS.EnsureFields(GD)
    if not group.active or not GD.player then return 0 end
    local distributable = math.max(0, math.min(group.cash or 0, group.retainedEarnings or 0))
    local declaredDividend = math.floor(distributable * (group.dividendRate or 0))
    local personalDividend = math.floor(declaredDividend * math.max(0, math.min(1, group.personalShareRatio or 1.0)))
    if personalDividend <= 0 then return 0 end
    creditPersonalDividend(GD, group, personalDividend)
    GD.AddEvent(group.name .. "向个人股东分红" .. GD.FormatMoney(personalDividend), "success")
    return personalDividend
end

function GS.MonthlyUpdate(GD, completedYear, completedMonth)
    local group = GS.EnsureFields(GD)
    if not group.active then return end

    -- 产业公司独立月结，经营现金和利润留在公司，仅手动分红进入集团。
    GDI.MonthlyUpdate(GD, completedYear, completedMonth)

    local executiveCost = 0
    for _, executive in pairs(group.executives or {}) do
        local salary = math.floor(((executive.salary or 0) / 12) * 100) / 100
        executiveCost = executiveCost + salary
    end
    if executiveCost > 0 then
        local paidCurrent = math.min(group.cash, executiveCost)
        group.cash = group.cash - paidCurrent
        local unpaidCurrent = executiveCost - paidCurrent
        group.executiveSalaryArrears = (group.executiveSalaryArrears or 0) + unpaidCurrent
        if paidCurrent > 0 then
            for _, executive in pairs(group.executives or {}) do
                local salary = math.floor(((executive.salary or 0) / 12) * 100) / 100
                local paidShare = executiveCost > 0 and paidCurrent * salary / executiveCost or 0
                executive.totalPaid = (executive.totalPaid or 0) + paidShare
            end
        end
        if unpaidCurrent <= 0 and group.cash > 0 and group.executiveSalaryArrears > 0 then
            local arrearsPaid = math.min(group.cash, group.executiveSalaryArrears)
            group.cash = group.cash - arrearsPaid
            group.executiveSalaryArrears = group.executiveSalaryArrears - arrearsPaid
        end
        group.monthlyExpense = group.monthlyExpense + executiveCost
        group.annualProfit = group.annualProfit - executiveCost
        group.retainedEarnings = math.max(0, group.retainedEarnings - executiveCost)
    end

    for i = #group.loans, 1, -1 do
        local loan = group.loans[i]
        local interest = math.floor((loan.amount or 0) * (loan.rate or 0) / 100 / 12)
        if loan.repayMethod == "bullet" then
            loan.accruedInterest = (loan.accruedInterest or 0) + interest
        elseif group.cash >= interest then
            group.cash = group.cash - interest
            group.monthlyExpense = group.monthlyExpense + interest
            group.annualProfit = group.annualProfit - interest
            group.retainedEarnings = math.max(0, group.retainedEarnings - interest)
        else
            loan.accruedInterest = (loan.accruedInterest or 0) + interest
        end
        loan.remainMonths = math.max(0, (loan.remainMonths or 1) - 1)
        if loan.remainMonths <= 0 then
            local due = GS.GetEarlyRepayAmount(loan)
            if group.cash >= due then
                group.cash = group.cash - due
                group.totalDebt = math.max(0, group.totalDebt - (loan.amount or 0))
                table.remove(group.loans, i)
                GD.AddEvent(group.name .. "到期偿还集团贷款" .. GD.FormatMoney(due), "warning")
            else
                loan.remainMonths = 1
                GD.AddEvent(group.name .. "集团贷款到期但资金不足，已进入逾期", "danger")
            end
        end
    end

    if GD.month == 12 and (group.dividendRate or 0) > 0 then
        GS.DistributeDividend(GD)
        group.annualProfit = 0
    end
    group.lastMonthlyIncome = group.monthlyIncome or 0
    group.lastMonthlyExpense = group.monthlyExpense or 0
    group.monthlyIncome = 0
    group.monthlyExpense = 0
end

return GS
