-- ============================================================================
-- GroupIndustryOperations.lua - 集团产业公司的手动经营循环
-- ============================================================================

local GIO = {}

GIO.DATA_VERSION = 1

GIO.PROFILES = {
    heavy = {
        name = "重资产运营", mode = "contract", usesInventory = true,
        teamName = "运营班组", capacityName = "设施产能", inventoryName = "原料储备",
        baseCapacity = 100, capacityPerTeam = 28, capacityUpgrade = 35,
        opportunityMonths = {3, 6}, directCostFactor = 1.05,
    },
    operating = {
        name = "专业运营", mode = "contract", usesInventory = true,
        teamName = "项目团队", capacityName = "履约能力", inventoryName = "物资储备",
        baseCapacity = 80, capacityPerTeam = 30, capacityUpgrade = 30,
        opportunityMonths = {2, 5}, directCostFactor = 1.00,
    },
    service = {
        name = "专业服务", mode = "contract", usesInventory = false,
        teamName = "顾问团队", capacityName = "服务工时", inventoryName = "",
        baseCapacity = 70, capacityPerTeam = 35, capacityUpgrade = 25,
        opportunityMonths = {2, 4}, directCostFactor = 0.88,
    },
    financial = {
        name = "资本业务", mode = "financial", usesInventory = false,
        teamName = "投资团队", capacityName = "项目管理能力", inventoryName = "",
        baseCapacity = 60, capacityPerTeam = 30, capacityUpgrade = 20,
        opportunityMonths = {4, 9}, directCostFactor = 0.55,
    },
    consumer = {
        name = "消费零售", mode = "contract", usesInventory = true,
        teamName = "门店团队", capacityName = "门店承载", inventoryName = "商品库存",
        baseCapacity = 110, capacityPerTeam = 35, capacityUpgrade = 40,
        opportunityMonths = {2, 4}, directCostFactor = 1.12,
    },
    tourism = {
        name = "文旅酒店", mode = "contract", usesInventory = false,
        teamName = "运营团队", capacityName = "接待能力", inventoryName = "",
        baseCapacity = 90, capacityPerTeam = 32, capacityUpgrade = 35,
        opportunityMonths = {2, 5}, directCostFactor = 1.05,
    },
}

GIO.PLAN_OPTIONS = {
    market = {
        internal = {name = "集团内协同", demand = 0.88, value = 0.92, risk = 0.72, cost = 0.90},
        balanced = {name = "内外部均衡", demand = 1.00, value = 1.00, risk = 1.00, cost = 1.00},
        external = {name = "外部市场拓展", demand = 1.24, value = 1.14, risk = 1.30, cost = 1.12},
    },
    pricing = {
        volume = {name = "规模低价", demand = 1.25, value = 0.88, risk = 0.92, cost = 0.98},
        market = {name = "市场定价", demand = 1.00, value = 1.00, risk = 1.00, cost = 1.00},
        premium = {name = "品牌溢价", demand = 0.78, value = 1.20, risk = 1.18, cost = 1.08},
    },
    quality = {
        basic = {name = "成本优先", demand = 0.90, value = 0.94, risk = 1.35, cost = 0.88, synergy = 0.75},
        standard = {name = "标准交付", demand = 1.00, value = 1.00, risk = 1.00, cost = 1.00, synergy = 1.00},
        excellence = {name = "品质标杆", demand = 1.12, value = 1.14, risk = 0.72, cost = 1.18, synergy = 1.22},
    },
    capacity = {
        conservative = {name = "保守排产", utilization = 0.72, risk = 0.70, cost = 0.92},
        balanced = {name = "均衡排产", utilization = 0.90, risk = 1.00, cost = 1.00},
        maximum = {name = "满负荷经营", utilization = 1.12, risk = 1.45, cost = 1.10},
    },
}
GIO.PLAN_ORDER = {
    market = {"internal", "balanced", "external"},
    pricing = {"volume", "market", "premium"},
    quality = {"basic", "standard", "excellence"},
    capacity = {"conservative", "balanced", "maximum"},
}

local CLIENTS = {
    heavy = {"大型开发商", "产业园区平台", "城市建设集团", "基础设施运营商"},
    operating = {"城市运营平台", "商业资产业主", "社区服务中心", "产业客户"},
    service = {"地方国企", "开发企业", "机构投资人", "产业园客户"},
    financial = {"产业投资平台", "资产持有机构", "困境项目方", "设备运营企业"},
    consumer = {"社区商业项目", "连锁渠道商", "区域采购平台", "大型社区"},
    tourism = {"旅行渠道平台", "企业会奖客户", "城市文旅集团", "度假客群运营商"},
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function roundMoney(value)
    return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

local function optionValue(category, id, key, fallback)
    local option = GIO.PLAN_OPTIONS[category] and GIO.PLAN_OPTIONS[category][id]
    if not option then return fallback or 1 end
    return option[key] or fallback or 1
end

local function addTransaction(GD, business, txType, category, amount, description)
    business.transactions = business.transactions or {}
    business.transactions[#business.transactions + 1] = {
        year = GD.year,
        month = GD.month,
        type = txType,
        category = category,
        amount = roundMoney(amount),
        description = description,
    }
    while #business.transactions > 60 do table.remove(business.transactions, 1) end
end

local function spendCompanyCash(GD, business, amount, category, description, pending)
    amount = roundMoney(amount)
    if amount <= 0 then return true end
    if (business.companyCash or 0) < amount then return false end
    business.companyCash = roundMoney(business.companyCash - amount)
    if pending ~= false then
        business.pendingExpense = roundMoney((business.pendingExpense or 0) + amount)
    end
    addTransaction(GD, business, "expense", category, amount, description)
    return true
end

local function receiveCompanyCash(GD, business, amount, category, description, pending)
    amount = roundMoney(amount)
    if amount <= 0 then return end
    business.companyCash = roundMoney((business.companyCash or 0) + amount)
    if pending ~= false then
        business.pendingRevenue = roundMoney((business.pendingRevenue or 0) + amount)
    end
    addTransaction(GD, business, "income", category, amount, description)
end

function GIO.GetProfile(def)
    return GIO.PROFILES[def and def.type or "operating"] or GIO.PROFILES.operating
end

function GIO.CreateBusinessState(def, business, companyCash)
    local profile = GIO.GetProfile(def)
    business.companyName = business.companyName or ((def and def.name or "产业") .. "有限公司")
    business.companyCash = roundMoney(companyCash or 0)
    business.registeredCapital = business.registeredCapital or (business.invested or (def and def.investment) or 0)
    business.retainedEarnings = business.retainedEarnings or 0
    business.companyDebt = business.companyDebt or 0
    business.loans = business.loans or {}
    business.staffTeams = business.staffTeams or 0
    business.capacity = business.capacity or profile.baseCapacity
    business.inventory = business.inventory or 0
    business.plan = business.plan or {}
    business.plan.market = GIO.PLAN_OPTIONS.market[business.plan.market] and business.plan.market or nil
    business.plan.pricing = GIO.PLAN_OPTIONS.pricing[business.plan.pricing] and business.plan.pricing or nil
    business.plan.quality = GIO.PLAN_OPTIONS.quality[business.plan.quality] and business.plan.quality or nil
    business.plan.capacity = GIO.PLAN_OPTIONS.capacity[business.plan.capacity] and business.plan.capacity or nil
    business.opportunities = business.opportunities or {}
    business.orders = business.orders or {}
    business.completedOrders = business.completedOrders or 0
    business.failedOrders = business.failedOrders or 0
    business.totalDividends = business.totalDividends or 0
    business.totalCapitalInjected = business.totalCapitalInjected or 0
    business.reputation = clamp(tonumber(business.reputation) or 50, 0, 100)
    business.salaryArrears = business.salaryArrears or 0
    business.pendingRevenue = business.pendingRevenue or 0
    business.pendingExpense = business.pendingExpense or 0
    business.lastUtilization = business.lastUtilization or 0
    business.lastDeliveredOrders = business.lastDeliveredOrders or 0
    business.lastStalledOrders = business.lastStalledOrders or 0
    business.transactions = business.transactions or {}
    business.nextOpportunityId = business.nextOpportunityId or 1
    business.operationsVersion = GIO.DATA_VERSION
    business.companyKind = "industry"
    business.operationMode = "manual"
    business.playerControlGranted = true
    business.settlementMode = "manual_company"
    return business
end

function GIO.EnsureBusiness(def, business)
    if not business then return nil end
    local initialCash = 0
    if business.companyCash == nil then
        initialCash = math.max(0, (business.invested or (def and def.investment) or 0) - (business.assetValue or 0))
    end
    return GIO.CreateBusinessState(def, business, business.companyCash or initialCash)
end

function GIO.IsReady(def, business)
    GIO.EnsureBusiness(def, business)
    local plan = business.plan or {}
    if not plan.market or not plan.pricing or not plan.quality or not plan.capacity then
        return false, "请先完成市场、定价、品质和产能四项经营方案"
    end
    if (business.staffTeams or 0) <= 0 then return false, "请先组建至少1支经营团队" end
    return true, "公司已具备接单经营条件"
end

function GIO.RenameCompany(GD, def, business, name)
    GIO.EnsureBusiness(def, business)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local length = utf8.len(name)
    if not length then return false, "公司名称包含无效字符" end
    if length < 2 or length > 24 then return false, "公司名称需为2至24个字符" end
    if name:find("[%c\r\n]") then return false, "公司名称不能包含控制字符" end
    business.companyName = name
    GD.AddEvent("产业公司更名为“" .. name .. "”", "info")
    return true, "产业公司名称已更新"
end

function GIO.SetPlan(GD, def, business, category, optionId)
    GIO.EnsureBusiness(def, business)
    if not GIO.PLAN_OPTIONS[category] or not GIO.PLAN_OPTIONS[category][optionId] then
        return false, "未知经营方案"
    end
    business.plan[category] = optionId
    GD.AddEvent(business.companyName .. "调整经营方案：" .. GIO.PLAN_OPTIONS[category][optionId].name, "info")
    return true, "经营方案已更新"
end

function GIO.GetTeamMonthlyCost(def, business)
    local base = math.max(3, (def.fixedCost or 10) * 0.28)
    return roundMoney(base * (1 + math.max(0, (business.level or 1) - 1) * 0.12))
end

function GIO.AdjustStaff(GD, def, business, delta)
    GIO.EnsureBusiness(def, business)
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false, "团队数量未变化" end
    local current = business.staffTeams or 0
    local target = clamp(current + delta, 0, 20)
    if target == current then return false, delta > 0 and "已达到团队上限" or "当前没有可裁减团队" end
    if target > current then
        local hireCost = roundMoney((target - current) * GIO.GetTeamMonthlyCost(def, business) * 2)
        if not spendCompanyCash(GD, business, hireCost, "团队建设", "招聘和培训经营团队") then
            return false, "产业公司现金不足，招聘需要" .. tostring(hireCost) .. "万元"
        end
    else
        local severance = roundMoney((current - target) * GIO.GetTeamMonthlyCost(def, business))
        if not spendCompanyCash(GD, business, severance, "团队调整", "团队优化遣散支出") then
            return false, "产业公司现金不足，团队调整需要" .. tostring(severance) .. "万元"
        end
    end
    business.staffTeams = target
    GD.AddEvent(business.companyName .. "经营团队调整为" .. tostring(target) .. "支", "info")
    return true, "经营团队已调整"
end

function GIO.GetCapacityUpgradeCost(def, business)
    local profile = GIO.GetProfile(def)
    return math.floor((def.investment or 1000) * 0.08 + (business.capacity or profile.baseCapacity) * 4)
end

function GIO.ExpandCapacity(GD, def, business)
    GIO.EnsureBusiness(def, business)
    local profile = GIO.GetProfile(def)
    local cost = GIO.GetCapacityUpgradeCost(def, business)
    if not spendCompanyCash(GD, business, cost, "设施扩建", "扩建产业经营设施", false) then
        return false, "产业公司现金不足，扩建需要" .. tostring(cost) .. "万元"
    end
    business.capacity = (business.capacity or profile.baseCapacity) + profile.capacityUpgrade
    business.assetValue = roundMoney((business.assetValue or 0) + cost)
    business.invested = roundMoney((business.invested or 0) + cost)
    GD.AddEvent(business.companyName .. "完成设施扩建，产能提升至" .. tostring(business.capacity), "success")
    return true, "设施产能已扩建"
end

function GIO.GetInventoryUnitCost(def, business)
    local quality = business.plan and business.plan.quality or "standard"
    return roundMoney(math.max(0.5, (def.investment or 1000) * 0.00012) * optionValue("quality", quality, "cost", 1))
end

function GIO.ProcureInventory(GD, def, business, quantity)
    GIO.EnsureBusiness(def, business)
    local profile = GIO.GetProfile(def)
    if not profile.usesInventory then return false, "该产业不需要库存采购" end
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 then return false, "请输入有效采购数量" end
    local cost = roundMoney(quantity * GIO.GetInventoryUnitCost(def, business))
    if not spendCompanyCash(GD, business, cost, "采购", "采购经营物资", false) then
        return false, "产业公司现金不足，采购需要" .. tostring(cost) .. "万元"
    end
    business.inventory = roundMoney((business.inventory or 0) + quantity)
    return true, "采购完成，库存增加" .. tostring(quantity)
end

function GIO.GetMarketDevelopmentCost(def, business)
    return math.floor(math.max(30, (def.investment or 1000) * 0.0025) * (1 + #business.opportunities * 0.08))
end

local function opportunityTitle(def, profile, index)
    if profile.mode == "financial" then
        return (index % 2 == 0) and "存量资产重组方案" or "产业资本投放方案"
    elseif def.type == "consumer" then
        return (index % 2 == 0) and "区域门店经营合约" or "社区渠道供货计划"
    elseif def.type == "tourism" then
        return (index % 2 == 0) and "季度渠道包销合作" or "企业会奖接待合同"
    elseif def.type == "service" then
        return (index % 2 == 0) and "专项顾问服务合同" or "年度专业服务框架"
    end
    return (index % 2 == 0) and "年度运营服务合同" or "产业项目交付订单"
end

function GIO.DevelopMarket(GD, def, business)
    GIO.EnsureBusiness(def, business)
    local ready, reason = GIO.IsReady(def, business)
    if not ready then return false, reason end
    if #business.opportunities >= 8 then return false, "待评估商机过多，请先处理现有商机" end
    local cost = GIO.GetMarketDevelopmentCost(def, business)
    if not spendCompanyCash(GD, business, cost, "市场拓展", "客户开发和方案投标", false) then
        return false, "产业公司现金不足，市场拓展需要" .. tostring(cost) .. "万元"
    end
    local profile = GIO.GetProfile(def)
    local clients = CLIENTS[def.type] or CLIENTS.operating
    local market = business.plan.market
    local pricing = business.plan.pricing
    local quality = business.plan.quality
    local count = 3
    for i = 1, count do
        local duration = math.random(profile.opportunityMonths[1], profile.opportunityMonths[2])
        local levelScale = 1 + math.max(0, (business.level or 1) - 1) * 0.35
        local baseMonthly = (business.invested or def.investment) * def.revenueRate * levelScale
        local monthlyRevenue = roundMoney(baseMonthly * (0.65 + math.random() * 0.75)
            * optionValue("market", market, "value", 1)
            * optionValue("pricing", pricing, "value", 1)
            * optionValue("quality", quality, "value", 1))
        local contractValue = roundMoney(monthlyRevenue * duration)
        local margin = clamp(def.margin
            - (optionValue("quality", quality, "cost", 1) - 1) * 0.22
            + (optionValue("pricing", pricing, "value", 1) - 1) * 0.18, 0.05, 0.62)
        local requiredCapacity = math.max(10, math.floor((business.capacity or profile.baseCapacity) * (0.18 + math.random() * 0.26)))
        local capitalCommitment = profile.mode == "financial" and roundMoney(contractValue * (4.5 + math.random() * 2.5)) or 0
        business.opportunities[#business.opportunities + 1] = {
            id = business.nextOpportunityId,
            title = opportunityTitle(def, profile, i),
            client = clients[math.random(1, #clients)],
            duration = duration,
            contractValue = contractValue,
            monthlyRevenue = monthlyRevenue,
            margin = margin,
            requiredCapacity = requiredCapacity,
            inventoryPerMonth = profile.usesInventory and math.max(5, math.floor(requiredCapacity * 0.70)) or 0,
            capitalCommitment = capitalCommitment,
            expiresMonths = 3,
            risk = roundMoney(def.riskRate
                * optionValue("market", market, "risk", 1)
                * optionValue("quality", quality, "risk", 1)),
        }
        business.nextOpportunityId = business.nextOpportunityId + 1
    end
    GD.AddEvent(business.companyName .. "完成市场拓展，新增" .. tostring(count) .. "个待决策商机", "success")
    return true, "已获得3个新商机"
end

local function findById(items, id)
    for index, item in ipairs(items or {}) do
        if tostring(item.id) == tostring(id) then return item, index end
    end
    return nil, nil
end

function GIO.AcceptOpportunity(GD, def, business, opportunityId)
    GIO.EnsureBusiness(def, business)
    local opportunity, index = findById(business.opportunities, opportunityId)
    if not opportunity then return false, "商机已失效" end
    local profile = GIO.GetProfile(def)
    local monthlyCost = roundMoney(opportunity.monthlyRevenue * (1 - opportunity.margin) * profile.directCostFactor)
    local requiredCash = profile.mode == "financial" and opportunity.capitalCommitment or monthlyCost * 2
    if (business.companyCash or 0) < requiredCash then
        return false, "产业公司营运资金不足，承接至少需要" .. tostring(roundMoney(requiredCash)) .. "万元"
    end
    if profile.mode == "financial" then
        if not spendCompanyCash(GD, business, opportunity.capitalCommitment, "资本投放", opportunity.title .. "资本占用", false) then
            return false, "产业公司资本金不足"
        end
    end
    local order = {
        id = "order_" .. tostring(opportunity.id),
        title = opportunity.title,
        client = opportunity.client,
        duration = opportunity.duration,
        remainMonths = opportunity.duration,
        contractValue = opportunity.contractValue,
        monthlyRevenue = opportunity.monthlyRevenue,
        margin = opportunity.margin,
        monthlyCost = monthlyCost,
        requiredCapacity = opportunity.requiredCapacity,
        inventoryPerMonth = opportunity.inventoryPerMonth,
        capitalCommitment = opportunity.capitalCommitment,
        risk = opportunity.risk,
        progress = 0,
        status = "active",
        totalRevenue = 0,
        totalExpense = 0,
        stalledMonths = 0,
    }
    business.orders[#business.orders + 1] = order
    table.remove(business.opportunities, index)
    GD.AddEvent(business.companyName .. "承接“" .. order.title .. "”，合同额" .. tostring(order.contractValue) .. "万元", "success")
    return true, "订单已承接"
end

function GIO.RejectOpportunity(GD, def, business, opportunityId)
    GIO.EnsureBusiness(def, business)
    local opportunity, index = findById(business.opportunities, opportunityId)
    if not opportunity then return false, "商机已失效" end
    table.remove(business.opportunities, index)
    return true, "已放弃该商机"
end

function GIO.InjectCapital(GD, def, business, amount)
    GIO.EnsureBusiness(def, business)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效注资金额" end
    if (GD.group.cash or 0) < amount then return false, "集团现金不足" end
    GD.group.cash = roundMoney(GD.group.cash - amount)
    business.companyCash = roundMoney(business.companyCash + amount)
    business.registeredCapital = roundMoney(business.registeredCapital + amount)
    business.totalCapitalInjected = roundMoney(business.totalCapitalInjected + amount)
    addTransaction(GD, business, "capital", "集团注资", amount, "集团向产业公司增资")
    return true, "集团注资已进入产业公司账户"
end

function GIO.GetLoanRoom(def, business)
    GIO.EnsureBusiness(def, business)
    local assets = math.max(1, (business.assetValue or 0) + (business.companyCash or 0))
    return math.max(0, math.floor(assets * 0.45 - (business.companyDebt or 0)))
end

function GIO.ApplyLoan(GD, def, business, amount, months)
    GIO.EnsureBusiness(def, business)
    amount = math.floor(tonumber(amount) or 0)
    months = clamp(math.floor(tonumber(months) or 36), 12, 60)
    if amount <= 0 then return false, "请输入有效贷款金额" end
    if amount > GIO.GetLoanRoom(def, business) then return false, "超过产业公司当前可贷额度" end
    local rate = 5.6 + (def.riskRate or 0.02) * 100 + math.max(0, 55 - (business.reputation or 50)) * 0.02
    business.loans[#business.loans + 1] = {
        id = "industry_loan_" .. tostring(#business.loans + 1) .. "_" .. tostring(GD.totalMonths or 0),
        name = "产业经营贷款",
        amount = amount,
        rate = roundMoney(rate),
        remainMonths = months,
        totalMonths = months,
        accruedInterest = 0,
    }
    business.companyDebt = roundMoney(business.companyDebt + amount)
    receiveCompanyCash(GD, business, amount, "产业融资", "取得产业经营贷款", false)
    return true, "产业经营贷款已到账"
end

function GIO.GetEarlyRepayAmount(loan)
    return roundMoney((loan and loan.amount or 0) + (loan and loan.accruedInterest or 0))
end

function GIO.EarlyRepayLoan(GD, def, business, loanIndex)
    GIO.EnsureBusiness(def, business)
    local loan = business.loans[loanIndex]
    if not loan then return false, "产业贷款不存在" end
    local amount = GIO.GetEarlyRepayAmount(loan)
    if not spendCompanyCash(GD, business, amount, "偿还贷款", "提前偿还产业经营贷款", false) then
        return false, "产业公司现金不足，还款需要" .. tostring(amount) .. "万元"
    end
    business.companyDebt = roundMoney(math.max(0, business.companyDebt - (loan.amount or 0)))
    table.remove(business.loans, loanIndex)
    return true, "产业贷款已结清"
end

function GIO.DistributeDividend(GD, def, business, amount)
    GIO.EnsureBusiness(def, business)
    amount = math.floor(tonumber(amount) or 0)
    local limit = math.floor(math.max(0, math.min(business.companyCash or 0, business.retainedEarnings or 0)))
    if amount <= 0 then return false, "请输入有效分红金额" end
    if amount > limit then return false, "超过产业公司可分配利润，最多" .. tostring(limit) .. "万元" end
    business.companyCash = roundMoney(business.companyCash - amount)
    business.retainedEarnings = roundMoney(math.max(0, business.retainedEarnings - amount))
    business.totalDividends = roundMoney(business.totalDividends + amount)
    GD.group.cash = roundMoney((GD.group.cash or 0) + amount)
    GD.group.monthlyIncome = roundMoney((GD.group.monthlyIncome or 0) + amount)
    addTransaction(GD, business, "dividend", "上缴集团", amount, "产业公司向集团分红")
    return true, "产业公司分红已进入集团账户"
end

local function expireOpportunities(business)
    for index = #business.opportunities, 1, -1 do
        local opportunity = business.opportunities[index]
        opportunity.expiresMonths = math.max(0, (opportunity.expiresMonths or 1) - 1)
        if opportunity.expiresMonths <= 0 then table.remove(business.opportunities, index) end
    end
end

local function settleLoans(GD, business)
    local expense = 0
    for index = #business.loans, 1, -1 do
        local loan = business.loans[index]
        local interest = roundMoney((loan.amount or 0) * (loan.rate or 0) / 100 / 12)
        if business.companyCash >= interest then
            business.companyCash = roundMoney(business.companyCash - interest)
            expense = expense + interest
            addTransaction(GD, business, "expense", "贷款利息", interest, loan.name .. "月度利息")
        else
            loan.accruedInterest = roundMoney((loan.accruedInterest or 0) + interest)
        end
        loan.remainMonths = math.max(0, (loan.remainMonths or 1) - 1)
        if loan.remainMonths <= 0 then
            local due = GIO.GetEarlyRepayAmount(loan)
            if business.companyCash >= due then
                business.companyCash = roundMoney(business.companyCash - due)
                business.companyDebt = roundMoney(math.max(0, business.companyDebt - (loan.amount or 0)))
                table.remove(business.loans, index)
                addTransaction(GD, business, "expense", "到期还款", due, "产业经营贷款到期结清")
            else
                loan.remainMonths = 1
                business.reputation = clamp(business.reputation - 2, 0, 100)
            end
        end
    end
    return roundMoney(expense)
end

function GIO.GetAvailableCapacity(def, business)
    local profile = GIO.GetProfile(def)
    local physical = business.capacity or profile.baseCapacity
    local teamCapacity = (business.staffTeams or 0) * profile.capacityPerTeam
    local base = math.min(physical, teamCapacity)
    return math.max(0, math.floor(base * optionValue("capacity", business.plan.capacity, "utilization", 0.72)))
end

function GIO.GetProjectedMonthlyResult(GD, def, business)
    GIO.EnsureBusiness(def, business)
    local ready = GIO.IsReady(def, business)
    local payroll = roundMoney((business.staffTeams or 0) * GIO.GetTeamMonthlyCost(def, business))
    local maintenance = roundMoney((def.fixedCost or 0) * 0.35)
    local revenue, directCost = 0, 0
    if ready then
        local capacityLeft = GIO.GetAvailableCapacity(def, business)
        for _, order in ipairs(business.orders or {}) do
            if order.status == "active" and capacityLeft >= (order.requiredCapacity or 0) then
                revenue = revenue + (order.monthlyRevenue or 0)
                directCost = directCost + (order.monthlyCost or 0)
                capacityLeft = capacityLeft - (order.requiredCapacity or 0)
            end
        end
    end
    local expense = payroll + maintenance + directCost
    return {revenue = roundMoney(revenue), expense = roundMoney(expense), profit = roundMoney(revenue - expense)}
end

function GIO.MonthlyUpdateBusiness(GD, def, business, crisisPenalty)
    GIO.EnsureBusiness(def, business)
    local profile = GIO.GetProfile(def)
    local revenue = roundMoney(business.pendingRevenue or 0)
    local expense = roundMoney(business.pendingExpense or 0)
    business.pendingRevenue = 0
    business.pendingExpense = 0
    business.lastDeliveredOrders = 0
    business.lastStalledOrders = 0
    expireOpportunities(business)

    local payroll = roundMoney((business.staffTeams or 0) * GIO.GetTeamMonthlyCost(def, business))
    local maintenance = roundMoney((def.fixedCost or 0) * 0.35)
    local fixedCost = payroll + maintenance
    local paidFixed = math.min(business.companyCash or 0, fixedCost)
    business.companyCash = roundMoney((business.companyCash or 0) - paidFixed)
    expense = expense + fixedCost
    business.salaryArrears = roundMoney((business.salaryArrears or 0) + fixedCost - paidFixed)
    if paidFixed > 0 then addTransaction(GD, business, "expense", "团队与设施", paidFixed, "团队薪酬与设施维护") end

    local availableCapacity = GIO.GetAvailableCapacity(def, business)
    local usedCapacity = 0
    local ready = GIO.IsReady(def, business)
    for _, order in ipairs(business.orders or {}) do
        if order.status == "active" then
            local capacityOk = ready and usedCapacity + (order.requiredCapacity or 0) <= availableCapacity
            local inventoryOk = not profile.usesInventory or (business.inventory or 0) >= (order.inventoryPerMonth or 0)
            local cashOk = (business.companyCash or 0) >= (order.monthlyCost or 0)
            if capacityOk and inventoryOk and cashOk then
                if profile.usesInventory then business.inventory = roundMoney(business.inventory - (order.inventoryPerMonth or 0)) end
                business.companyCash = roundMoney(business.companyCash - (order.monthlyCost or 0))
                expense = expense + (order.monthlyCost or 0)
                local monthRevenue = roundMoney((order.monthlyRevenue or 0) * (crisisPenalty or 1))
                business.companyCash = roundMoney(business.companyCash + monthRevenue)
                revenue = revenue + monthRevenue
                order.totalRevenue = roundMoney((order.totalRevenue or 0) + monthRevenue)
                order.totalExpense = roundMoney((order.totalExpense or 0) + (order.monthlyCost or 0))
                order.remainMonths = math.max(0, (order.remainMonths or 1) - 1)
                order.progress = clamp(1 - order.remainMonths / math.max(1, order.duration or 1), 0, 1)
                order.stalledMonths = 0
                usedCapacity = usedCapacity + (order.requiredCapacity or 0)
                addTransaction(GD, business, "income", "合同回款", monthRevenue, order.title .. "当月回款")
                addTransaction(GD, business, "expense", "合同履约", order.monthlyCost or 0, order.title .. "当月履约成本")
                if order.remainMonths <= 0 then
                    order.status = "completed"
                    business.completedOrders = business.completedOrders + 1
                    business.lastDeliveredOrders = business.lastDeliveredOrders + 1
                    business.reputation = clamp(business.reputation + 1.5, 0, 100)
                    if profile.mode == "financial" and (order.capitalCommitment or 0) > 0 then
                        business.companyCash = roundMoney(business.companyCash + order.capitalCommitment)
                        addTransaction(GD, business, "capital", "资本回收", order.capitalCommitment, order.title .. "收回投放本金")
                    end
                end
            else
                order.stalledMonths = (order.stalledMonths or 0) + 1
                business.lastStalledOrders = business.lastStalledOrders + 1
                if order.stalledMonths >= 3 then
                    order.status = "failed"
                    business.failedOrders = business.failedOrders + 1
                    business.reputation = clamp(business.reputation - 4, 0, 100)
                    if profile.mode == "financial" and (order.capitalCommitment or 0) > 0 then
                        local recovered = roundMoney(order.capitalCommitment * 0.82)
                        business.companyCash = roundMoney(business.companyCash + recovered)
                        expense = expense + roundMoney(order.capitalCommitment - recovered)
                    end
                end
            end
        end
    end

    expense = expense + settleLoans(GD, business)
    if business.activeRisk then
        local riskCost = roundMoney(business.activeRisk.monthlyLoss or 0)
        local paid = math.min(business.companyCash or 0, riskCost)
        business.companyCash = roundMoney((business.companyCash or 0) - paid)
        expense = expense + riskCost
        business.activeRisk.monthsLeft = math.max(0, (business.activeRisk.monthsLeft or 1) - 1)
        if paid > 0 then addTransaction(GD, business, "expense", "风险损失", paid, business.activeRisk.name or "经营风险损失") end
        if business.activeRisk.monthsLeft <= 0 then business.activeRisk = nil end
    end

    local profit = roundMoney(revenue - expense)
    business.lastRevenue = revenue
    business.lastExpense = expense
    business.lastProfit = profit
    business.totalRevenue = roundMoney((business.totalRevenue or 0) + revenue)
    business.totalExpense = roundMoney((business.totalExpense or 0) + expense)
    business.totalProfit = roundMoney((business.totalProfit or 0) + profit)
    business.retainedEarnings = roundMoney(math.max(0, (business.retainedEarnings or 0) + profit))
    business.lastUtilization = availableCapacity > 0 and clamp(usedCapacity / availableCapacity, 0, 1.2) or 0
    if business.salaryArrears > 0 and business.companyCash > 0 then
        local paidArrears = math.min(business.companyCash, business.salaryArrears)
        business.companyCash = roundMoney(business.companyCash - paidArrears)
        business.salaryArrears = roundMoney(business.salaryArrears - paidArrears)
    end
    return {revenue = revenue, expense = expense, profit = profit}
end

function GIO.ResolveRisk(GD, def, business)
    GIO.EnsureBusiness(def, business)
    if not business.activeRisk then return false, "该产业公司当前没有待处置风险" end
    local cost = business.activeRisk.resolveCost or 0
    if not spendCompanyCash(GD, business, cost, "风险处置", "专项处置“" .. (business.activeRisk.name or "经营风险") .. "”", false) then
        return false, "产业公司现金不足，风险处置需要" .. tostring(cost) .. "万元"
    end
    business.activeRisk = nil
    business.reputation = clamp(business.reputation + 2, 0, 100)
    return true, "产业公司风险事件已处置"
end

function GIO.GetSynergyFactor(def, business)
    GIO.EnsureBusiness(def, business)
    local ready = GIO.IsReady(def, business)
    if not ready then return 0 end
    local quality = optionValue("quality", business.plan.quality, "synergy", 1)
    local staffing = clamp((business.staffTeams or 0) / 3, 0.35, 1.15)
    local distress = (business.salaryArrears or 0) > 0 and 0.55 or 1
    local risk = business.activeRisk and 0.75 or 1
    return clamp(quality * staffing * distress * risk, 0, 1.25)
end

function GIO.GetSummary(def, business)
    GIO.EnsureBusiness(def, business)
    local profile = GIO.GetProfile(def)
    local activeOrders = 0
    for _, order in ipairs(business.orders or {}) do
        if order.status == "active" then activeOrders = activeOrders + 1 end
    end
    local ready, reason = GIO.IsReady(def, business)
    return {
        companyName = business.companyName,
        companyCash = business.companyCash,
        companyDebt = business.companyDebt,
        retainedEarnings = business.retainedEarnings,
        staffTeams = business.staffTeams,
        teamName = profile.teamName,
        capacity = business.capacity,
        capacityName = profile.capacityName,
        inventory = business.inventory,
        inventoryName = profile.inventoryName,
        usesInventory = profile.usesInventory,
        opportunities = #business.opportunities,
        activeOrders = activeOrders,
        completedOrders = business.completedOrders,
        failedOrders = business.failedOrders,
        reputation = business.reputation,
        utilization = business.lastUtilization,
        salaryArrears = business.salaryArrears,
        ready = ready,
        readyReason = reason,
        loanRoom = GIO.GetLoanRoom(def, business),
    }
end

return GIO
