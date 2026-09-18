-- ============================================================================
-- Governance.lua - 股权结构与公司治理
-- 融资轮次 / 股东管理 / 分红分配 / 控制权
-- ============================================================================

local DT = require("DevTypes")
local PC = require("ProjectCapacity")
local MK = require("Marketing")
local ME = require("MacroEconomy")
local GV = {}

-- ============================================================================
-- 股权预设
-- ============================================================================
GV.EQUITY_PRESETS = {
    sole = {
        name = "独资经营",
        desc = "创始人100%控股，完全掌控决策",
        icon = "👤",
        capitalOptions = {500, 1000, 1500, 2000, 3000},   -- 启动资金选项(万元)
        dividendRate = 0,                                    -- 分红比例0%（初始不分红）
        ---@param capital number
        ---@param founderName string?
        ---@return table[]
        shareholders = function(capital, founderName)
            return {
                {id = "founder", name = founderName or "创始人", shares = 10000, ratio = 1.0, type = "founder", totalDividends = 0, investAmount = capital},
            }
        end,
    },
    partnership = {
        name = "合伙创业",
        desc = "创始人70% + 合伙人30%，共担风险共享收益",
        icon = "👥",
        capitalOptions = {2000, 3000, 5000, 8000},          -- 合伙人出资，资金更充裕
        dividendRate = 0,                                    -- 分红比例0%（初始不分红）
        shareholders = function(capital, founderName)
            return {
                {id = "founder", name = founderName or "创始人", shares = 7000, ratio = 0.70, type = "founder", totalDividends = 0, investAmount = math.floor(capital * 0.7)},
                {id = "partner_1", name = "联合创始人", shares = 3000, ratio = 0.30, type = "partner", totalDividends = 0, investAmount = math.floor(capital * 0.3)},
            }
        end,
    },
    angel = {
        name = "天使融资",
        desc = "创始人60% + 合伙人20% + 天使投资人20%，资金最充裕",
        icon = "💰",
        capitalOptions = {5000, 8000, 10000},                -- 天使注资，最高1亿
        dividendRate = 0,                                    -- 分红比例0%（初始不分红）
        shareholders = function(capital, founderName)
            return {
                {id = "founder", name = founderName or "创始人", shares = 6000, ratio = 0.60, type = "founder", totalDividends = 0, investAmount = math.floor(capital * 0.6)},
                {id = "partner_1", name = "联合创始人", shares = 2000, ratio = 0.20, type = "partner", totalDividends = 0, investAmount = math.floor(capital * 0.2)},
                {id = "angel_1", name = "天使投资人", shares = 2000, ratio = 0.20, type = "angel", totalDividends = 0, investAmount = math.floor(capital * 0.2)},
            }
        end,
    },
}
GV.PRESET_ORDER = {"sole", "partnership", "angel"}

-- ============================================================================
-- 融资轮次配置
-- ============================================================================
GV.FINANCING_ROUNDS = {
    angel    = {name = "天使轮",    order = 1, dilutionRange = {0.10, 0.20}, valuationMult = {1.1, 1.3}, minRevenue = 0},
    round_a  = {name = "A轮",      order = 2, dilutionRange = {0.10, 0.15}, valuationMult = {1.3, 1.5}, minRevenue = 5000},
    round_b  = {name = "B轮",      order = 3, dilutionRange = {0.05, 0.10}, valuationMult = {1.5, 1.7}, minRevenue = 20000},
    pre_ipo  = {name = "Pre-IPO",   order = 4, dilutionRange = {0.03, 0.05}, valuationMult = {1.7, 2.0}, minRevenue = 100000},
    ipo      = {name = "IPO上市",   order = 5, dilutionRange = {0.20, 0.25}, valuationMult = {2.0, 2.3}, minRevenue = 500000},
}
GV.ROUND_ORDER = {"angel", "round_a", "round_b", "pre_ipo", "ipo"}

--- 创始人最低持股比例底线（30%）
GV.FOUNDER_MIN_RATIO = 0.30

-- ============================================================================
-- 控制权阈值
-- ============================================================================
GV.CONTROL_LEVELS = {
    {threshold = 0.67, name = "绝对控制", color = "Success", desc = "可通过任何决议"},
    {threshold = 0.50, name = "相对控制", color = "Info",    desc = "可通过普通决议"},
    {threshold = 0.34, name = "否决权",   color = "Warning", desc = "可否决特殊决议"},
    {threshold = 0.00, name = "少数股东", color = "Danger",  desc = "无法阻止重大决议"},
}

-- ============================================================================
-- 初始化
-- ============================================================================

---@param preset string "sole"|"partnership"|"angel"
---@param capital number 注册资本(万元)
---@param founderName string? 创始人姓名
---@return table governance
function GV.InitGovernanceData(preset, capital, founderName)
    local presetDef = GV.EQUITY_PRESETS[preset] or GV.EQUITY_PRESETS.sole
    local shareholders = presetDef.shareholders(capital, founderName)

    local dividendRate = presetDef.dividendRate or 0
    local gov = {
        equityPreset   = preset,
        totalShares    = 10000,
        founderShares  = shareholders[1].shares,
        founderRatio   = shareholders[1].ratio,
        shareholders   = shareholders,
        financingHistory = {},
        currentRound   = (preset == "angel") and "round_a" or "angel",
        boardSeats     = 3,
        dividendPolicy = {
            rate         = dividendRate,  -- 分红比例（由股权结构决定）
            minCashRatio = 0.20,          -- 最低现金留存比例
        },
        lastValuation  = capital,    -- 最近估值(万元)
        isIPO          = false,
        totalRaised    = 0,          -- 累计融资金额
        -- 董事会决策字段
        resolutionHistory   = {},
        resolutionCooldowns = {},
        boardDecisionCount  = 0,
        -- 高管团队字段
        executives = {},
        fullManagement = false,       -- CEO全权托管经营开关
        fullManagementSince = nil,
        lastFullManagementMonth = nil,
        lastAutoLoanMonth = nil,
        ceoMonthlyReports = {},
        pendingCeoReport = nil,
        ceoReportHistory = {},
        ceoReportEnabled = true,
        ceoReportFrequency = "monthly",
        ceoCashflowPolicy = {reserveRatio = 0.25, acquisitionRatio = 0.35, developmentRatio = 0.40},
        esopPool          = 0,
        riskReserve       = 0,
        buybackAuthorized = false,
    }
    return gov
end

-- ============================================================================
-- 向后兼容
-- ============================================================================
function GV.EnsureGovernanceFields(gov, founderName)
    if not gov then return end
    gov.equityPreset    = gov.equityPreset or "sole"
    gov.totalShares     = gov.totalShares or 10000
    gov.founderShares   = gov.founderShares or 10000
    gov.founderRatio    = gov.founderRatio or 1.0
    gov.shareholders    = gov.shareholders or {
        {id = "founder", name = founderName or "创始人", shares = 10000, ratio = 1.0, type = "founder", totalDividends = 0, investAmount = 0},
    }
    -- 旧存档：更新创始人股东名字
    if founderName then
        for _, sh in ipairs(gov.shareholders) do
            if sh.id == "founder" and (sh.name == "创始人" or sh.name == nil) then
                sh.name = founderName
            end
        end
    end
    gov.financingHistory = gov.financingHistory or {}
    gov.currentRound    = gov.currentRound or "angel"
    gov.boardSeats      = gov.boardSeats or 3
    gov.dividendPolicy  = gov.dividendPolicy or {rate = 0, minCashRatio = 0.20}
    gov.lastValuation   = gov.lastValuation or 0
    gov.isIPO           = gov.isIPO or false
    gov.totalRaised     = gov.totalRaised or 0
    -- 董事会决策字段
    gov.resolutionHistory   = gov.resolutionHistory or {}
    gov.resolutionCooldowns = gov.resolutionCooldowns or {}
    gov.boardDecisionCount  = gov.boardDecisionCount or 0
    -- 高管团队字段
    gov.executives = gov.executives or {}
    gov.fullManagement = gov.fullManagement == true
    gov.fullManagementSince = gov.fullManagementSince
    gov.lastFullManagementMonth = gov.lastFullManagementMonth
    gov.lastAutoLoanMonth = gov.lastAutoLoanMonth
    gov.ceoMonthlyReports = gov.ceoMonthlyReports or {}
    gov.pendingCeoReport = gov.pendingCeoReport
    gov.ceoReportHistory = gov.ceoReportHistory or {}
    if gov.ceoReportEnabled == nil then gov.ceoReportEnabled = true end
    gov.ceoReportFrequency = gov.ceoReportFrequency or "monthly"
    gov.ceoCashflowPolicy = gov.ceoCashflowPolicy or {reserveRatio = 0.25, acquisitionRatio = 0.35, developmentRatio = 0.40}
    -- 股权操作字段
    gov.esopPool        = gov.esopPool or 0
    gov.riskReserve     = gov.riskReserve or 0
    gov.buybackAuthorized = gov.buybackAuthorized or false
    -- 确保每个股东都有完整字段
    for _, sh in ipairs(gov.shareholders) do
        sh.totalDividends = sh.totalDividends or 0
        sh.investAmount   = sh.investAmount or 0
    end
end

-- ============================================================================
-- 月度更新
-- ============================================================================
--- 按股份比例分配董事会席位
--- 持股>=10%的股东获得至少1个席位，剩余席位按比例分配
function GV.AllocateBoardSeats(gov)
    if not gov or not gov.shareholders then return end
    local totalSeats = gov.boardSeats or 3
    local qualifiedShareholders = {}
    for _, sh in ipairs(gov.shareholders) do
        if sh.ratio >= 0.10 then
            table.insert(qualifiedShareholders, sh)
        end
    end
    -- 每位合格股东计算席位数
    gov.boardSeatAllocation = {}
    if #qualifiedShareholders == 0 then return end
    local assignedSeats = 0
    for _, sh in ipairs(qualifiedShareholders) do
        local seats = math.max(1, math.floor(totalSeats * sh.ratio + 0.5))
        gov.boardSeatAllocation[sh.id or sh.name] = seats
        assignedSeats = assignedSeats + seats
    end
    -- 如果实际分配超过总席位，按比例缩减；不足则给最大股东补齐
    if assignedSeats < totalSeats and #qualifiedShareholders > 0 then
        local biggest = qualifiedShareholders[1]
        gov.boardSeatAllocation[biggest.id or biggest.name] =
            (gov.boardSeatAllocation[biggest.id or biggest.name] or 1) + (totalSeats - assignedSeats)
    end
end

-- ============================================================================
-- CEO月度经营报告与审批计划
-- ============================================================================

local function ceoNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then return fallback or 0 end
    return number
end

local function ceoCompanySnapshot(GD, companyId)
    local currentId = GD.activeCompanyId
    if companyId == nil or tostring(companyId) == tostring(currentId) then
        local currentRecord = nil
        for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
            if tostring(record.id or "") == tostring(currentId or "") then
                currentRecord = record
                break
            end
        end
        return {
            id = currentId,
            name = GD.company and GD.company.name or "未命名公司",
            company = GD.company,
            projects = GD.projects or {},
            landMarket = GD.landMarket or {},
            landReserve = GD.landReserve or {},
            loans = GD.loans or {},
            fixedAssets = GD.fixedAssets or {},
            rentalListings = GD.rentalListings or {},
            currentContext = true,
            record = currentRecord,
        }
    end
    if not GD.EnsureCompanyPortfolio then return nil end
    GD.EnsureCompanyPortfolio(true)
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        if tostring(record.id) == tostring(companyId) then
            local state = record.state or {}
            return {
                id = record.id,
                name = record.name or (state.company and state.company.name) or "未命名公司",
                company = state.company or {},
                projects = state.projects or {},
                landMarket = state.landMarket or {},
                landReserve = state.landReserve or {},
                loans = state.loans or {},
                fixedAssets = state.fixedAssets or {},
                rentalListings = state.rentalListings or {},
                record = record,
            }
        end
    end
    return nil
end

local function ceoSuggestedProjectPrice(GD, project)
    local city = GD.GetCityData and GD.GetCityData(project and project.land and project.land.city) or nil
    local cityPrice = city and city.avgPrice or 10000
    local expected = DT.GetExpectedPrice and DT.GetExpectedPrice(
        project and project.devTypeId or "rigid_residential",
        cityPrice,
        project and (project.plotLocation or (project.land and project.land.plotLocation)) or "suburb",
        project and project.standardId or "basic",
        project and project.land and project.land.floorPrice or 0
    ) or cityPrice
    return math.max(1000, math.floor(expected * ((GD.economy and GD.economy.priceIndex or 100) / 100)))
end

local function ceoFindLand(snapshot, landId)
    for _, land in ipairs(snapshot.landMarket or {}) do
        if tostring(land.id) == tostring(landId) then return land, "market" end
    end
    for _, land in ipairs(snapshot.landReserve or {}) do
        if tostring(land.id) == tostring(landId) then return land, "reserve" end
    end
    return nil, nil
end

local function ceoEligible(GD, snapshot)
    local company = snapshot and snapshot.company
    local gov = company and company.governance
    return snapshot ~= nil
        and snapshot.record ~= nil
        and snapshot.record.status == "operating"
        and company ~= nil
        and (company.name or "") ~= ""
        and gov ~= nil
        and gov.fullManagement == true
        and gov.executives ~= nil
        and gov.executives.ceo ~= nil
        and (gov.founderRatio or 0) >= 0.50
end

local function ceoProjectTypeName(project)
    local typeDef = project and project.devTypeId and DT.GetType(project.devTypeId) or nil
    return typeDef and (typeDef.name or typeDef.shortName) or (project and project.devTypeId) or "未分类项目"
end

local function ceoProjectDisplayName(project)
    local name = project and project.name
    if name and name ~= "" and not name:lower():find("ceo", 1, true) then
        return name
    end
    local land = project and project.land or {}
    local typeDef = project and project.devTypeId and DT.GetType(project.devTypeId) or nil
    local typeName = typeDef and (typeDef.shortName or typeDef.name) or "项目"
    local location = land.location or land.city or "新项目"
    return location .. typeName .. "项目"
end

local function ceoBuildClearanceResult(project)
    local sheet = project and project.clearanceSheet or {}
    local coreCost = ceoNumber(sheet.landCost, 0) + ceoNumber(sheet.buildCost, 0)
    local otherCost = ceoNumber(sheet.designCost, 0)
        + ceoNumber(sheet.marketingCost, 0)
        + ceoNumber(sheet.financeCost, 0)
        + ceoNumber(sheet.ddCost, 0)
        + ceoNumber(sheet.riskCost, 0)
        + ceoNumber(sheet.otherCost, 0)
    local totalCostBeforeTax = ceoNumber(sheet.totalCostBeforeTax, coreCost + otherCost)
    local salesRevenue = ceoNumber(sheet.totalRevenue, ceoNumber(sheet.revenue, 0))
    local grossProfit = ceoNumber(sheet.grossProfit, salesRevenue - totalCostBeforeTax)
    local tax = ceoNumber(sheet.incomeTax, 0)
    local netProfit = ceoNumber(sheet.netProfitAfterTax, grossProfit - tax)
    local profitMargin = salesRevenue > 0 and netProfit / salesRevenue or 0
    return {
        id = "clearance:" .. tostring(project and project.id or "project") .. ":" .. tostring(project and project.ceoClearanceMonth or 0),
        resultType = "sale_clearance",
        projectId = project and project.id or nil,
        projectName = ceoProjectDisplayName(project),
        salesRevenue = salesRevenue,
        cost = coreCost,
        coreCost = coreCost,
        totalCost = totalCostBeforeTax,
        totalCostBeforeTax = totalCostBeforeTax,
        totalCostAfterTax = totalCostBeforeTax + tax,
        grossProfit = grossProfit,
        tax = tax,
        incomeTax = tax,
        otherCost = otherCost,
        netProfit = netProfit,
        netProfitAfterTax = netProfit,
        profitMargin = profitMargin,
        clearedMonth = project and project.ceoClearanceMonth or 0,
        confirmed = false,
    }
end

local function ceoBuildFixedAssetResult(GD, project, asset, preview, targetRent)
    local developmentCost = math.max(0, ceoNumber(preview and preview.originalValue, 0))
    local renovationCost = math.max(0, ceoNumber(preview and preview.renovCost, 0))
    local tax = math.max(0, ceoNumber(preview and preview.latTax, 0))
    local totalCost = developmentCost + renovationCost + tax
    local assetValue = math.max(0, ceoNumber(asset and asset.currentValue, preview and preview.actualMarketValue or 0))
    local valuationProfit = assetValue - totalCost
    return {
        id = "fixed_asset:" .. tostring(project and project.id or "project") .. ":" .. tostring(GD.totalMonths or 0),
        resultType = "fixed_asset_rental",
        projectId = project and project.id or nil,
        projectName = ceoProjectDisplayName(project),
        developmentCost = developmentCost,
        renovationCost = renovationCost,
        tax = tax,
        totalCost = totalCost,
        assetValue = assetValue,
        netProfit = valuationProfit,
        profitMargin = totalCost > 0 and valuationProfit / totalCost or 0,
        targetMonthlyRent = math.max(0, ceoNumber(targetRent, 0)),
        clearedMonth = project and project._ceoFixedAssetMonth or GD.totalMonths or 0,
        confirmed = false,
    }
end

local function ceoRecordClearanceResult(GD, project)
    if not project or not project.salesCleared or project.ceoClearanceResult then return end
    project.ceoClearanceMonth = GD.totalMonths or 0
    project.ceoClearanceResult = ceoBuildClearanceResult(project)
    print("[CEO-LIFECYCLE] 清盘成果待汇报 project=" .. tostring(project.name)
        .. " revenue=" .. tostring(project.ceoClearanceResult.salesRevenue)
        .. " net=" .. tostring(project.ceoClearanceResult.netProfit))
end

local function ceoRecordFixedAssetResult(GD, project, asset, preview, targetRent)
    if not project or not project._fixedAssetConverted or project.ceoFixedAssetResult then return end
    project.ceoFixedAssetResult = ceoBuildFixedAssetResult(GD, project, asset, preview, targetRent)
    print("[CEO-LIFECYCLE] 自持转固盈利成果待汇报 project=" .. tostring(project.name)
        .. " value=" .. tostring(project.ceoFixedAssetResult.assetValue)
        .. " profit=" .. tostring(project.ceoFixedAssetResult.netProfit))
end

local function ceoEnsureReportProposalFields(report)
    if type(report) ~= "table" then return nil end
    report.proposals = report.proposals or {}
    local proposals = report.proposals
    proposals.land = proposals.land or {enabled = false, decision = "reject"}
    proposals.development = proposals.development or {
        enabled = false,
        decision = "reject",
        allocationDecision = "reject",
        openingPriceDecision = "reject",
    }
    proposals.development.projectManager = proposals.development.projectManager
        or {enabled = false, decision = "reject"}
    proposals.cashflow = proposals.cashflow or {
        enabled = true,
        decision = nil,
        reserveRatio = 0.25,
        acquisitionRatio = 0.35,
        developmentRatio = 0.40,
    }
    proposals.loan = proposals.loan or {enabled = true, targetDebtRatio = 0.45}
    proposals.renovation = proposals.renovation or {enabled = false, decision = "reject"}
    proposals.equityInvestment = proposals.equityInvestment or {enabled = false, decision = "reject"}
    proposals.propertyOperation = proposals.propertyOperation or {enabled = false, decision = "reject"}
    proposals.presale = proposals.presale or {enabled = false, decision = "reject"}
    proposals.clearanceResults = proposals.clearanceResults or {enabled = false, items = {}}
    proposals.clearanceResults.items = proposals.clearanceResults.items or {}
    return proposals
end

local function ceoNormalizeReport(GD, report, projectContext)
    if type(report) ~= "table" then return end
    report.summary = report.summary or {}
    local proposals = ceoEnsureReportProposalFields(report)
    local development = proposals.development
    if type(development) == "table" then
        development.estimatedArea = math.max(0, ceoNumber(development.estimatedArea, 0))
        local price = math.max(0, ceoNumber(development.openingPrice, 0))
        development.openingPrice = price
        development.estimatedRevenue = math.floor(price * development.estimatedArea / 10000)
    end
    local renovation = report.proposals.renovation
    if type(renovation) == "table" then
        renovation.levelIndex = math.max(1, math.min(4, math.floor(ceoNumber(renovation.levelIndex, 1))))
        renovation.holdAreaEstimate = math.max(0, ceoNumber(renovation.holdAreaEstimate, 0))
        renovation.estimatedCost = math.max(0, ceoNumber(renovation.estimatedCost, 0))
    end
    local equity = report.proposals.equityInvestment
    if type(equity) == "table" then
        equity.amount = math.max(0, ceoNumber(equity.amount, 0))
        equity.equityRatio = math.max(0, math.min(0.30, ceoNumber(equity.equityRatio, 0)))
        equity.estimatedValue = math.max(0, ceoNumber(equity.estimatedValue, 0))
        equity.expectedDividend = math.max(0, ceoNumber(equity.expectedDividend, 0))
    end
    -- CEO托管下自持物业统一走装修、转固和挂牌出租，不再同时进入项目运营模式。
    local propertyOperation = report.proposals.propertyOperation
    if type(propertyOperation) == "table" then
        propertyOperation.enabled = false
        propertyOperation.decision = "reject"
    end
    local development = report.proposals.development
    if type(development) == "table" and type(development.projectManager) ~= "table" then
        development.projectManager = {enabled = false, decision = "reject"}
    end
    -- 预售提案价格、名称和项目类型标准化；旧报告按 projectId 回填动态项目资料
    local presale = report.proposals.presale
    if type(presale) == "table" then
        presale.openingPrice = math.max(0, ceoNumber(presale.openingPrice, 0))
        local matchedProject = nil
        local projects = projectContext and projectContext.projects or projectContext
        if type(projects) == "table" then
            for _, project in ipairs(projects) do
                if presale.projectId and tostring(project.id) == tostring(presale.projectId) then
                    matchedProject = project
                    break
                end
            end
        end
        if matchedProject then
            presale.projectId = matchedProject.id
            presale.projectName = ceoProjectDisplayName(matchedProject)
            presale.projectType = ceoProjectTypeName(matchedProject)
            presale.projectTypeShortName = (DT.GetType(matchedProject.devTypeId) or {}).shortName or presale.projectType
            presale.projectCity = matchedProject.land and matchedProject.land.city or presale.projectCity
            presale.projectLocation = matchedProject.land and matchedProject.land.location or presale.projectLocation
            if presale.openingPrice < 1000 then
                presale.openingPrice = ceoSuggestedProjectPrice(GD, matchedProject)
            end
            presale.estimatedRevenue = math.floor(presale.openingPrice * (presale.totalArea or matchedProject.sales.totalArea or 0) / 10000)
        else
            presale.projectName = presale.projectName or "项目"
            presale.projectType = presale.projectType or "未分类项目"
        end
    end
    local clearanceItems = report.proposals.clearanceResults
    if type(clearanceItems) == "table" then
        clearanceItems.enabled = clearanceItems.enabled == true and #(clearanceItems.items or {}) > 0
        clearanceItems.items = clearanceItems.items or {}
        local projects = projectContext and projectContext.projects or projectContext
        for _, result in ipairs(clearanceItems.items) do
            result.confirmed = result.confirmed == true
            if result.resultType ~= "fixed_asset_rental" then
                result.resultType = "sale_clearance"
            end
            if type(projects) == "table" then
                for _, project in ipairs(projects) do
                    if result.projectId and tostring(project.id) == tostring(result.projectId) then
                        if result.resultType == "sale_clearance" then
                            result.projectName = ceoProjectDisplayName(project)
                        elseif result.resultType == "fixed_asset_rental" then
                            result.projectName = ceoProjectDisplayName(project)
                        end
                        break
                    end
                end
            end
        end
    end
end

local function ceoGetHoldArea(project)
    return math.max(0, ceoNumber(project and project.unitPlan and project.unitPlan.holdArea, 0))
end

local function ceoGetProjectManagerPlan(GD, projects)
    local hired = {}
    for _, project in ipairs(projects or {}) do
        if project.projectManager and project.projectManager.hired then
            hired[project.projectManager.name] = true
        end
    end
    local candidate = nil
    for _, manager in ipairs(GD.PM_POOL or {}) do
        if not hired[manager.name] then
            candidate = manager
            break
        end
    end
    if not candidate then return {enabled = false, decision = "reject"} end
    return {
        enabled = true,
        name = candidate.name,
        salary = ceoNumber(candidate.salary, 0),
        level = ceoNumber(candidate.level, 1),
        trait = candidate.trait or "常规型",
        decision = "approve",
    }
end

local function ceoBuildRenovationProposal(GD, snapshot, project)
    local holdArea = ceoGetHoldArea(project)
    if holdArea <= 0 then return {enabled = false, decision = "reject", levelIndex = 1, holdAreaEstimate = 0, estimatedCost = 0} end
    local levelIndex = 2
    local preview = GD.PreviewFixedAssetConvert and GD.PreviewFixedAssetConvert(project, levelIndex) or nil
    return {
        enabled = preview ~= nil,
        decision = nil,
        levelIndex = levelIndex,
        levelName = preview and preview.renovLevel and preview.renovLevel.name or "简装",
        holdAreaEstimate = preview and preview.holdArea or holdArea,
        estimatedCost = preview and preview.renovCost or 0,
        estimatedTotalCost = preview and preview.totalCost or 0,
        projectId = project and project.id or nil,
        projectName = project and project.name or "",
    }
end

local function ceoBuildEquityProposal(GD, company)
    local compIdx = nil
    local comp = nil
    for i, candidate in ipairs(GD.competitors or {}) do
        if candidate and candidate.name then
            compIdx = i
            comp = candidate
            break
        end
    end
    local amount = 0
    if company and company.cash then amount = math.floor(math.max(0, company.cash * 0.05)) end
    if amount < 100 then amount = 0 end
    local estimatedValue = 0
    if comp and amount > 0 then
        local valuation = math.max(1, ceoNumber(comp.cash, 0) * 2.5)
        estimatedValue = math.floor(amount / (valuation + amount) * valuation)
    end
    return {
        enabled = comp ~= nil and amount >= 100,
        decision = nil,
        targetCompIdx = compIdx,
        targetCompanyName = comp and comp.name or "暂无合适投资对象",
        amount = amount,
        equityRatio = 0,
        estimatedValue = estimatedValue,
        expectedDividend = math.floor(estimatedValue * 0.02),
    }
end

function GV.BuildCeoMonthlyReport(GD, companyId, reportMonth)
    local snapshot = ceoCompanySnapshot(GD, companyId)
    if not ceoEligible(GD, snapshot) then return nil, "该公司未启用CEO全权托管" end
    local company = snapshot.company
    local gov = company.governance
    local activeProjects = 0
    local projectChanges = {}
    for _, project in ipairs(snapshot.projects or {}) do
        if project.status ~= "completed" and project.status ~= "mature" and project.status ~= "sold_off" then
            activeProjects = activeProjects + 1
        end
        if project.status == "delivery" or project.status == "completed" or project.status == "mature" then
            projectChanges[#projectChanges + 1] = {name = project.name or "项目", status = project.status}
        end
        -- 报告已开盘预售的项目
        if project.sales and project.sales.canSell and project.status == "presale" then
            projectChanges[#projectChanges + 1] = {name = project.name or "项目", status = "presale", note = "已开盘预售"}
        end
        -- 报告已清盘缴税的项目
        if project.salesCleared and project.ceoClearanceResult
            and not project.ceoClearanceResult.confirmed
        then
            projectChanges[#projectChanges + 1] = {
                name = project.name or "项目",
                status = "cleared",
                note = "已清盘缴税完成，等待确认成果",
            }
        end
        -- 报告已开启物业的项目
        if project.propertyMgmt and project.propertyMgmt.enabled then
            projectChanges[#projectChanges + 1] = {name = project.name or "项目", status = "property", note = "物业服务运营中"}
        end
    end

    local landCandidate = nil
    if activeProjects < GV.FULL_MANAGEMENT_PROJECT_LIMIT then
        for _, land in ipairs(snapshot.landMarket or {}) do
            if land.city == company.city and land.status == "available" then
                if not landCandidate or (land.startPrice or math.huge) < (landCandidate.startPrice or math.huge) then
                    landCandidate = land
                end
            end
        end
    end

    local developmentCandidate = nil
    for _, land in ipairs(snapshot.landReserve or {}) do
        if land.city == company.city and not land.developmentStarted
            and (not land.dueDiligence or not land.dueDiligence.inProgress)
        then
            local landUse = DT.USE_TYPE_TO_LAND_USE[land.useType] or "mixed"
            local types = DT.GetTypesForLandUse(landUse)
            local devType = types[1] and types[1].id or "rigid_residential"
            developmentCandidate = {landId = land.id, land = land, landLocation = land.location or "新项目", devTypeId = devType}
            break
        end
    end

    local plan = nil
    if developmentCandidate then
        local holdRatio = (DT.TYPES[developmentCandidate.devTypeId]
            and DT.TYPES[developmentCandidate.devTypeId].category == DT.CATEGORY_HOLD) and 1.0 or 0.20
        local totalArea = 0
        for _, land in ipairs(snapshot.landReserve or {}) do
            if tostring(land.id) == tostring(developmentCandidate.landId) then
                totalArea = ceoNumber(land.buildArea, 0)
                break
            end
        end
        local cityData = GD.GetCityData and GD.GetCityData(company.city) or nil
        local avgPrice = cityData and cityData.avgPrice or 15000
        local expected = DT.GetExpectedPrice and DT.GetExpectedPrice(
            developmentCandidate.devTypeId, avgPrice, "suburb", "basic", 0) or avgPrice
        plan = {
            landId = developmentCandidate.landId,
            devTypeId = developmentCandidate.devTypeId,
            projectName = GD.GetUniqueProjectName
                and GD.GetUniqueProjectName(developmentCandidate.land, developmentCandidate.devTypeId, nil)
                or (developmentCandidate.landLocation .. "项目"),
            holdRatio = holdRatio,
            saleRatio = 1 - holdRatio,
            openingPrice = math.max(1, math.floor(expected * ((GD.economy and GD.economy.priceIndex or 100) / 100))),
            estimatedArea = totalArea,
        }
    end

    local holdProject = nil
    for _, project in ipairs(snapshot.projects or {}) do
        if project.devCategory == "hold"
            and not project._fixedAssetConverted
            and (project.status == "pending_operations"
                or project.status == "completed"
                or project.status == "operations"
                or project.status == "mature")
        then
            holdProject = project
            break
        end
    end
    local propertyOperationProposal = {
        enabled = false,
        decision = "reject",
        projectId = nil,
        projectName = "CEO托管统一转固定资产出租",
        modeId = nil,
        modeName = "不适用",
    }

    local renovationProposal = ceoBuildRenovationProposal(GD, snapshot, holdProject)
    local equityProposal = ceoBuildEquityProposal(GD, company)

    -- 预售开盘提案：检测达到预售条件但未开售的项目
    -- 批准后标记 _presaleApproved 不再重复提交；拒绝则下月可再提
    local presaleProposal = {enabled = false, decision = nil}
    for _, project in ipairs(snapshot.projects or {}) do
        if project.sales and project.sales.canPresale and not project.sales.canSell
            and (project.devCategory or "sale") == "sale"
            and not project._presaleApproved then
            local basePrice = tonumber(project.sales.basePrice) or 0
            local suggestPrice = basePrice >= 1000 and basePrice or ceoSuggestedProjectPrice(GD, project)
            presaleProposal = {
                enabled = true,
                decision = nil,
                projectId = project.id,
                projectName = ceoProjectDisplayName(project),
                projectType = ceoProjectTypeName(project),
                projectTypeShortName = (DT.GetType(project.devTypeId) or {}).shortName or ceoProjectTypeName(project),
                projectCity = project.land and project.land.city or "",
                projectLocation = project.land and project.land.location or "",
                openingPrice = suggestPrice,
                totalUnits = project.sales.totalUnits or 0,
                totalArea = project.sales.totalArea or 0,
                estimatedRevenue = math.floor((suggestPrice) * (project.sales.totalArea or 0) / 10000),
            }
            break  -- 每次只报一个待预售项目
        end
    end
    local clearanceItems = {}
    for _, project in ipairs(snapshot.projects or {}) do
        if project.salesCleared
            and project.clearanceSheet
            and project.clearanceSheet.taxPaid
            and project.ceoClearanceResult
            and tostring(project.ceoClearanceResult.projectId or "") == tostring(project.id or "")
            and not project.ceoClearanceResult.confirmed
        then
            clearanceItems[#clearanceItems + 1] = project.ceoClearanceResult
        end
        if project._fixedAssetConverted
            and project.ceoFixedAssetResult
            and tostring(project.ceoFixedAssetResult.projectId or "") == tostring(project.id or "")
            and not project.ceoFixedAssetResult.confirmed
        then
            clearanceItems[#clearanceItems + 1] = project.ceoFixedAssetResult
        end
    end

    local listedRent = 0
    for _, listing in ipairs(snapshot.rentalListings or {}) do
        listedRent = listedRent + math.max(0, ceoNumber(listing.targetRent, 0))
    end
    local fixedAssetRent = 0
    for _, asset in ipairs(snapshot.fixedAssets or {}) do
        fixedAssetRent = fixedAssetRent + math.max(0, ceoNumber(asset.monthlyRent, 0))
    end
    local constructionCommitment = 0
    local projectManagerCost = 0
    for _, project in ipairs(snapshot.projects or {}) do
        if project.status == "construction" or project.status == "presale" then
            local totalMonths = math.max(1, ceoNumber(project.construction and project.construction.totalMonths, 1))
            constructionCommitment = constructionCommitment
                + math.floor(math.max(0, ceoNumber(project.cost and project.cost.buildCost, 0)) / totalMonths)
        end
        if project.projectManager and project.projectManager.hired then
            projectManagerCost = projectManagerCost + ceoNumber(project.projectManager.salary, 0)
        end
    end

    local policy = gov.ceoCashflowPolicy or {reserveRatio = 0.25, acquisitionRatio = 0.35, developmentRatio = 0.40}
    local reserve = 0
    if snapshot.currentContext then
        reserve = GV.GetManagementCashReserve(GD)
    else
        local gov = company.governance
        local reservePolicy = gov and gov.ceoCashflowPolicy and gov.ceoCashflowPolicy.reserveRatio or 0.25
        reserve = math.max(1, ceoNumber(company.monthlyExpense, 0) * reservePolicy)
    end
    local cash = ceoNumber(company.cash, 0)
    local debt = ceoNumber(company.totalDebt, 0)
    local assets = math.max(1, ceoNumber(company.totalAssets, 0), ceoNumber(company.registeredCapital, 0))
    local currentDebtRatio = math.max(0, math.min(0.65, debt / assets))
    local cashGap = math.max(0, reserve + 1 - cash)
    local loanRoom = math.max(0, math.floor(assets * 0.35 - debt))
    local loanAmount = math.min(1000, loanRoom, math.ceil(cashGap))
    local targetDebtRatio = currentDebtRatio
    if loanAmount > 0 then
        targetDebtRatio = math.min(0.65, (debt + loanAmount) / (assets + loanAmount))
    end

    local report = {
        id = "ceo_report:" .. tostring(reportMonth or GD.totalMonths) .. ":" .. tostring(snapshot.id),
        companyId = snapshot.id,
        companyName = snapshot.name,
        reportMonth = reportMonth or GD.totalMonths,
        status = "pending",
        summary = {
            openingCash = ceoNumber(company.monthlyOpeningCash, cash),
            closingCash = cash,
            revenue = ceoNumber(company.lastMonthRevenue, company.monthlyRevenue),
            expense = ceoNumber(company.lastMonthExpense, company.monthlyExpense),
            profit = ceoNumber(company.lastMonthProfit, company.monthlyProfit),
            assets = assets,
            debt = debt,
            activeProjects = activeProjects,
            projectChanges = projectChanges,
            constructionCommitment = constructionCommitment,
            projectManagerCost = projectManagerCost,
            listedRent = listedRent,
            fixedAssetRent = fixedAssetRent,
            safeReserve = reserve,
            availableCash = math.max(0, cash - reserve),
        },
        proposals = {
            land = {
                enabled = landCandidate ~= nil, decision = nil,
                landId = landCandidate and landCandidate.id or nil,
                location = landCandidate and landCandidate.location or "暂无合适地块",
                price = landCandidate and ceoNumber(landCandidate.startPrice, 0) or 0,
            },
            development = {
                enabled = plan ~= nil,
                decision = nil,
                allocationDecision = nil,
                openingPriceDecision = nil,
                landId = plan and plan.landId or nil,
                devTypeId = plan and plan.devTypeId or nil,
                projectName = plan and plan.projectName or "暂无可开发储备地块",
                holdRatio = plan and plan.holdRatio or 0,
                saleRatio = plan and plan.saleRatio or 1,
                openingPrice = plan and plan.openingPrice or 0,
                estimatedArea = plan and plan.estimatedArea or 0,
                estimatedRevenue = plan and math.floor((plan.openingPrice or 0) * (plan.estimatedArea or 0) / 10000) or 0,
                projectManager = plan and ceoGetProjectManagerPlan(GD, snapshot.projects) or {enabled = false, decision = "reject"},
            },
            renovation = renovationProposal,
            equityInvestment = equityProposal,
            propertyOperation = propertyOperationProposal,
            presale = presaleProposal,
            clearanceResults = {
                enabled = #clearanceItems > 0,
                items = clearanceItems,
            },
            cashflow = {
                enabled = true,
                decision = nil,
                reserveRatio = ceoNumber(policy.reserveRatio, 0.25),
                acquisitionRatio = ceoNumber(policy.acquisitionRatio, 0.35),
                developmentRatio = ceoNumber(policy.developmentRatio, 0.40),
            },
            loan = {
                enabled = true,
                -- 资产负债率控制指标（非贷款审批，CEO自行管理现金流）
                currentDebtRatio = currentDebtRatio,
                targetDebtRatio = gov.ceoTargetDebtRatio or math.min(0.45, currentDebtRatio + 0.05),
                assetBase = assets,
                debtBase = debt,
            },
        },
    }
    return report
end

function GV.QueueCeoMonthlyReports(GD)
    if not GD.gameStarted then return 0 end
    if not GD.EnsureCompanyPortfolio then return 0 end
    GD.CaptureActiveCompanyState()
    GD.EnsureCompanyPortfolio(true)
    local queue = {}
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        local snapshot = ceoCompanySnapshot(GD, record.id)
        if ceoEligible(GD, snapshot) then
            local gov = snapshot.company.governance

            -- 检查汇报开关和频次；同一周期到期的所有公司一次性入队，UI再逐个展示。
            local reportEnabled = gov.ceoReportEnabled ~= false  -- 默认开启
            if not reportEnabled then
                gov.pendingCeoReport = nil
                print("[CEO-REPORT] 跳过未开启汇报的公司，继续静默托管 id=" .. tostring(record.id)
                    .. " name=" .. tostring(snapshot.name))
                goto continue_report
            end
            local frequency = gov.ceoReportFrequency or "monthly"
            local month = GD.totalMonths or 0
            if frequency == "quarterly" and month % 3 ~= 0 then goto continue_report end
            if frequency == "yearly" and month % 12 ~= 0 then goto continue_report end

            local pending = gov.pendingCeoReport
            if pending and pending.status == "pending" then
                ceoNormalizeReport(GD, pending, snapshot)
                queue[#queue + 1] = pending
            else
                local report = GV.BuildCeoMonthlyReport(GD, record.id, GD.totalMonths)
                if report then
                    gov.pendingCeoReport = report
                    queue[#queue + 1] = report
                end
            end
            ::continue_report::
        elseif snapshot and snapshot.company and snapshot.company.governance
            and snapshot.company.governance.fullManagement == true
            and snapshot.company.governance.ceoReportEnabled ~= false
        then
            local gov = snapshot.company.governance
            print("[CEO-REPORT] 托管公司未进入汇报队列 id=" .. tostring(record.id)
                .. " name=" .. tostring(snapshot.name)
                .. " ceo=" .. tostring(gov.executives and gov.executives.ceo ~= nil)
                .. " founderRatio=" .. tostring(gov.founderRatio))
        end
    end
    -- 当前经营公司的报告写在运行态 company 中，必须在本函数结束前同步回公司组合快照。
    GD.CaptureActiveCompanyState()
    GD._pendingCeoReportQueue = queue
    GD._pendingCeoReportPopup = #queue > 0
    GD._ceoReportBatchTotal = #queue
    GD._ceoReportBatchProcessed = 0
    print("[CEO-REPORT] 本周期同时生成报告数=" .. tostring(#queue))
    return #queue
end

local function ceoCollectPendingReports(GD)
    if not GD.gameStarted or not GD.EnsureCompanyPortfolio then return {} end
    GD.CaptureActiveCompanyState()
    GD.EnsureCompanyPortfolio(true)
    local pendingReports = {}
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        local snapshot = ceoCompanySnapshot(GD, record.id)
        if record.status ~= "operating" then
            local gov = snapshot and snapshot.company and snapshot.company.governance
            if gov and gov.pendingCeoReport then
                gov.pendingCeoReport.status = "cancelled"
                gov.pendingCeoReport.cancelReason = "公司已退出经营"
                gov.pendingCeoReport = nil
                print("[CEO-REPORT] 已作废退出公司的历史报告 companyId=" .. tostring(record.id))
            end
        elseif ceoEligible(GD, snapshot) then
            local gov = snapshot.company.governance
            if gov.ceoReportEnabled ~= false then
                local report = gov.pendingCeoReport
                if report and report.status == "pending" then
                    ceoNormalizeReport(GD, report, snapshot)
                    report.summary.projectChanges = report.summary.projectChanges or {}
                    pendingReports[#pendingReports + 1] = report
                end
            elseif gov.pendingCeoReport then
                gov.pendingCeoReport = nil
            end
        end
    end
    return pendingReports
end

function GV.HasPendingCeoReports(GD)
    return #ceoCollectPendingReports(GD) > 0
end

function GV.ReopenPendingCeoReports(GD)
    local queue = ceoCollectPendingReports(GD)
    GD._pendingCeoReportQueue = queue
    GD._pendingCeoReportPopup = #queue > 0
    GD._ceoReportDeferred = false
    local processed = math.max(0, ceoNumber(GD._ceoReportBatchProcessed, 0))
    local expectedTotal = processed + #queue
    if not GD._ceoReportBatchTotal or GD._ceoReportBatchTotal < expectedTotal then
        GD._ceoReportBatchTotal = expectedTotal
    end
    return #queue
end

local function ceoHasDecision(proposal, key)
    if not proposal then return false end
    local decision = proposal[key]
    return decision == "approve" or decision == "reject"
end

function GV.GetCeoReportPendingDecisions(report)
    local pending = {}
    if not report or report.status ~= "pending" then
        pending[#pending + 1] = "报告已处理"
        return pending
    end
    local proposals = ceoEnsureReportProposalFields(report)
    if proposals.land and proposals.land.enabled and not ceoHasDecision(proposals.land, "decision") then
        pending[#pending + 1] = "土地购买计划"
    end
    if proposals.development and proposals.development.enabled then
        if not ceoHasDecision(proposals.development, "decision") then
            pending[#pending + 1] = "新项目开发计划"
        elseif proposals.development.decision == "approve" then
            -- 只有批准启动项目时，比例和开盘价才是有效子决策；拒绝项目后不应继续拦截执行。
            if not ceoHasDecision(proposals.development, "allocationDecision") then
                pending[#pending + 1] = "自持/销售比例计划"
            end
            if not ceoHasDecision(proposals.development, "openingPriceDecision") then
                pending[#pending + 1] = "计划开盘价"
            end
        end
    end
    if proposals.cashflow and proposals.cashflow.enabled ~= false
        and not ceoHasDecision(proposals.cashflow, "decision")
    then
        pending[#pending + 1] = "现金流配置计划"
    end
    -- loan 是资产负债率控制指标，无需审批决策
    if proposals.renovation and proposals.renovation.enabled
        and not ceoHasDecision(proposals.renovation, "decision")
    then
        pending[#pending + 1] = "固定资产装修计划"
    end
    if proposals.equityInvestment and proposals.equityInvestment.enabled
        and not ceoHasDecision(proposals.equityInvestment, "decision")
    then
        pending[#pending + 1] = "股权投资计划"
    end
    if proposals.propertyOperation and proposals.propertyOperation.enabled
        and not ceoHasDecision(proposals.propertyOperation, "decision")
    then
        pending[#pending + 1] = "物业运营计划"
    end
    if proposals.presale and proposals.presale.enabled
        and not ceoHasDecision(proposals.presale, "decision")
    then
        pending[#pending + 1] = "项目开盘预售计划"
    end
    local clearances = proposals.clearanceResults
    if clearances and clearances.enabled then
        for _, result in ipairs(clearances.items or {}) do
            if result.confirmed ~= true then
                pending[#pending + 1] = tostring(result.projectName or "项目") .. "成果确认"
            end
        end
    end
    return pending
end

function GV.ValidateCeoReportDecisions(report)
    local pending = GV.GetCeoReportPendingDecisions(report)
    if #pending > 0 then
        local message = "还有" .. tostring(#pending) .. "项未处理：" .. pending[1]
        if #pending > 1 then message = message .. "等" end
        return false, message
    end
    return true
end

local function ceoApplyLandPurchase(GD, report)
    local proposal = report.proposals.land
    if not proposal.enabled or proposal.decision ~= "approve" then return true end
    local land = nil
    for _, candidate in ipairs(GD.landMarket or {}) do
        if tostring(candidate.id) == tostring(proposal.landId) then land = candidate; break end
    end
    if not land or land.city ~= GD.company.city or land.status ~= "available" then
        return false, "计划地块已不可用"
    end
    local price = math.floor(ceoNumber(proposal.price, land.startPrice))
    if price <= 0 or not GV.EnsureManagementCash(GD, price, "已批准土地购买") then
        return false, "已达到目标资产负债率或融资受限，无法在保留现金安全垫后购地"
    end
    GD.company.cash = GD.company.cash - price
    land.price = price
    land.status = "acquired"
    land.acquiredMonth = GD.totalMonths
    land.ownerType = "player_company"
    land.ownerCompanyId = GD.activeCompanyId
    for i, candidate in ipairs(GD.landMarket or {}) do
        if candidate.id == land.id then table.remove(GD.landMarket, i); break end
    end
    table.insert(GD.landReserve, land)
    return true
end

local function ceoApplyDevelopment(GD, report)
    local proposal = report.proposals.development
    if not proposal.enabled or proposal.decision ~= "approve" then return true end
    local land = ceoFindLand({landReserve = GD.landReserve}, proposal.landId)
    if not land or land.developmentStarted then return false, "计划开发地块已不可用" end

    local pmPlan = proposal.projectManager
    local candidatePM = nil
    if pmPlan and pmPlan.enabled then
        for _, candidate in ipairs(GD.GetAvailablePMs and GD.GetAvailablePMs() or {}) do
            if candidate.name == pmPlan.name then
                candidatePM = candidate
                break
            end
        end
        if not candidatePM then return false, "计划项目经理已不可用" end
        if not GV.EnsureManagementCash(GD, candidatePM.salary, "已批准项目经理聘用") then
            return false, "已达到目标资产负债率或融资受限，无法为新项目聘用项目经理"
        end
    end

    local ok, msg = GD.StartDevelopment(proposal.landId, proposal.devTypeId, proposal.projectName, "basic")
    if not ok then return false, msg end
    local project = GD.projects[#GD.projects]
    if not project then return false, "项目创建失败" end
    local totalUnits = project.sales and project.sales.totalUnits or 0
    if totalUnits > 0 and proposal.allocationDecision == "approve" then
        local holdUnits = math.floor(totalUnits * math.max(0, math.min(1, ceoNumber(proposal.holdRatio, 0))))
        local planOk, planMsg = GD.PlanUnits(project, totalUnits - holdUnits, holdUnits)
        if not planOk then
            GD.AddEvent("CEO已启动项目，但自持/销售比例未能应用：" .. tostring(planMsg or "规划条件已变化"), "warning")
        end
    end
    if proposal.openingPriceDecision == "approve" and project.sales then
        local openingPrice = math.max(0, ceoNumber(proposal.openingPrice, 0))
        if openingPrice > 0 then
            project.sales.basePrice = openingPrice
            project.sales.approvedOpeningPrice = openingPrice
        end
    end
    if candidatePM then
        local okPm, pmMsg = GD.HireProjectManager(project, candidatePM.name)
        if okPm then
            project.projectManager.autoMode = true
            project.projectManager.autoEnabledByCeo = true
        else
            GD.AddEvent("CEO已启动项目，但项目经理未能聘用：" .. tostring(pmMsg or "候选人状态已变化"), "warning")
        end
    end
    return true
end

local function ceoApplyPropertyOperation(GD, report)
    local proposal = report.proposals.propertyOperation
    if not proposal or not proposal.enabled or proposal.decision ~= "approve" then return true end
    local target = nil
    for _, project in ipairs(GD.projects or {}) do
        if tostring(project.id) == tostring(proposal.projectId) then target = project; break end
    end
    if not target then return false, "待运营物业已不存在" end
    if not proposal.modeId then return false, "未选择物业运营模式" end
    local ok, msg = GD.SelectOperationMode(target, proposal.modeId)
    if not ok then return false, msg or "物业运营模式执行失败" end
    target._ceoHoldDisposition = "operations"
    return true
end

local function ceoApplyRenovation(GD, report)
    local proposal = report.proposals.renovation
    if not proposal or not proposal.enabled or proposal.decision ~= "approve" then return true end
    local target = nil
    for _, project in ipairs(GD.projects or {}) do
        if tostring(project.id) == tostring(proposal.projectId) then target = project; break end
    end
    if not target then return false, "固定资产装修项目已不存在" end
    local preview = GD.PreviewFixedAssetConvert(target, proposal.levelIndex)
    if not preview then return false, "无法计算固定资产装修预算" end
    proposal.holdAreaEstimate = preview.holdArea
    proposal.estimatedCost = preview.renovCost
    proposal.estimatedTotalCost = preview.totalCost
    target.renovationPlan = {
        approved = true,
        levelIndex = proposal.levelIndex,
        levelId = preview.renovLevel.id,
        estimatedCost = preview.renovCost,
        approvedMonth = GD.totalMonths,
    }
    return true
end

local function ceoApplyEquityInvestment(GD, report)
    local proposal = report.proposals.equityInvestment
    if not proposal or not proposal.enabled or proposal.decision ~= "approve" then return true end
    local amount = math.floor(math.max(0, ceoNumber(proposal.amount, 0)))
    if amount < 100 then return false, "股权投资金额不得低于100万元" end
    if not GV.EnsureManagementCash(GD, amount, "已批准股权投资") then
        return false, "已达到目标资产负债率或融资受限，无法在保留现金安全垫后投资"
    end
    local ok, msg = GD.InvestEquity(proposal.targetCompIdx, amount)
    if not ok then return false, msg or "股权投资失败" end
    proposal.amount = amount
    return true
end

local function ceoApplyLoan(GD, report)
    local proposal = report.proposals.loan
    if not proposal.enabled or proposal.decision ~= "approve" then return true end
    local gov = GD.company.governance
    local assets = math.max(1, ceoNumber(GD.company.totalAssets, GD.company.registeredCapital))
    local debt = math.max(0, ceoNumber(GD.company.totalDebt, 0))
    local targetRatio = math.max(0, math.min(1.0, ceoNumber(proposal.targetDebtRatio, 0.45)))

    -- 保存玩家批准的目标资产负债率，后续月份CEO自行按此控制
    gov.ceoTargetDebtRatio = targetRatio

    local currentRatio = debt / assets
    if currentRatio >= targetRatio then
        return true
    end

    -- 按目标资产负债率反算可贷款额；只保存目标，不在月报批准时盲目借满。
    local ratioAmount = math.floor(math.max(0, (targetRatio * assets - debt) / (1 - targetRatio)))
    local hardAmount = math.floor(math.max(0, (0.65 * assets - debt) / 0.35))
    local amount = math.min(ratioAmount, hardAmount)
    if amount <= 0 then return true end
    local ok, msg = GD.ApplyLoan("CEO托管经营贷款", amount, ceoNumber(proposal.rate, 5.2), math.floor(ceoNumber(proposal.months, 24)), nil, "interest_monthly")
    if not ok then return false, msg or "贷款申请失败" end
    return true
end

function GV.ApplyCeoReport(GD, report)
    local decisionsOk, decisionError = GV.ValidateCeoReportDecisions(report)
    if not decisionsOk then return false, decisionError end
    local targetSnapshot = ceoCompanySnapshot(GD, report and (report.companyId or GD.activeCompanyId))
    if not targetSnapshot or not targetSnapshot.record or targetSnapshot.record.status ~= "operating" then
        if report then
            report.status = "cancelled"
            report.cancelReason = "公司已退出经营"
        end
        return true, "公司已退出经营，历史CEO汇报已自动作废"
    end
    local originalId = GD.activeCompanyId
    local ok, msg = true, nil
    local function restoreOriginalCompany()
        if originalId and tostring(originalId) ~= tostring(GD.activeCompanyId) then
            GD.CaptureActiveCompanyState()
            GD.SwitchCompany(originalId)
        end
    end
    if report.companyId and tostring(report.companyId) ~= tostring(originalId) then
        ok, msg = GD.SwitchCompany(report.companyId)
    end
    if not ok then
        restoreOriginalCompany()
        return false, msg
    end
    local gov = GD.company.governance
    local proposals = ceoEnsureReportProposalFields(report)
    proposals.land.enabled = proposals.land.enabled == true
    proposals.development.enabled = proposals.development.enabled == true
    proposals.cashflow.enabled = proposals.cashflow.enabled ~= false
    proposals.loan.enabled = proposals.loan.enabled == true
    ceoNormalizeReport(GD, report, ceoCompanySnapshot(GD, report.companyId))
    -- 目标资产负债率是CEO现金流授权边界，必须先保存，后续本报告内获批支出才能按新目标自主融资。
    if proposals.loan and proposals.loan.enabled then
        gov.ceoTargetDebtRatio = math.max(0, math.min(0.65, ceoNumber(proposals.loan.targetDebtRatio, 0.45)))
    end
    if proposals.development.projectManager and proposals.development.projectManager.enabled
        and proposals.development.projectManager.decision ~= "reject"
    then
        proposals.development.projectManager.decision = "approve"
    end
    if proposals.cashflow.decision == "approve" then
        local reserveRatio = math.max(0.10, math.min(0.80, ceoNumber(proposals.cashflow.reserveRatio, 0.25)))
        local acquisitionRatio = math.max(0, math.min(1, ceoNumber(proposals.cashflow.acquisitionRatio, 0.35)))
        local developmentRatio = math.max(0, math.min(1, ceoNumber(proposals.cashflow.developmentRatio, 0.40)))
        local totalRatio = reserveRatio + acquisitionRatio + developmentRatio
        if totalRatio <= 0 then
            reserveRatio, acquisitionRatio, developmentRatio = 0.25, 0.35, 0.40
        else
            reserveRatio = reserveRatio / totalRatio
            acquisitionRatio = acquisitionRatio / totalRatio
            developmentRatio = developmentRatio / totalRatio
        end
        proposals.cashflow.reserveRatio = reserveRatio
        proposals.cashflow.acquisitionRatio = acquisitionRatio
        proposals.cashflow.developmentRatio = developmentRatio
        gov.ceoCashflowPolicy = {
            reserveRatio = reserveRatio,
            acquisitionRatio = acquisitionRatio,
            developmentRatio = developmentRatio,
        }
    end
    local applied = 0
    if proposals.land.decision == "approve" and proposals.land.executionStatus ~= "applied" then
        local done, err = ceoApplyLandPurchase(GD, report)
        if not done then
            ok, msg = false, err
        else
            proposals.land.executionStatus = "applied"
            applied = applied + 1
        end
    end
    if ok and proposals.development.decision == "approve"
        and proposals.development.executionStatus ~= "applied"
    then
        local done, err = ceoApplyDevelopment(GD, report)
        if not done then
            ok, msg = false, err
        else
            proposals.development.executionStatus = "applied"
            applied = applied + 1
        end
    end
    -- 资产负债率控制：仅保存玩家设定的目标比率，CEO自行管理现金流
    if ok and proposals.loan and proposals.loan.enabled then
        local targetRatio = math.max(0, math.min(0.65, ceoNumber(proposals.loan.targetDebtRatio, 0.45)))
        gov.ceoTargetDebtRatio = targetRatio
    end
    if ok and proposals.renovation.decision == "approve"
        and proposals.renovation.executionStatus ~= "applied"
    then
        local done, err = ceoApplyRenovation(GD, report)
        if not done then
            ok, msg = false, err
        else
            proposals.renovation.executionStatus = "applied"
            applied = applied + 1
        end
    end
    if ok and proposals.equityInvestment.decision == "approve"
        and proposals.equityInvestment.executionStatus ~= "applied"
    then
        local done, err = ceoApplyEquityInvestment(GD, report)
        if not done then
            ok, msg = false, err
        else
            proposals.equityInvestment.executionStatus = "applied"
            applied = applied + 1
        end
    end
    if ok and proposals.propertyOperation.decision == "approve"
        and proposals.propertyOperation.executionStatus ~= "applied"
    then
        local done, err = ceoApplyPropertyOperation(GD, report)
        if not done then
            ok, msg = false, err
        else
            proposals.propertyOperation.executionStatus = "applied"
            applied = applied + 1
        end
    end
    -- 预售开盘审批执行
    if ok and proposals.presale and proposals.presale.enabled
        and proposals.presale.decision == "approve"
        and proposals.presale.executionStatus ~= "applied"
    then
        local presale = proposals.presale
        local foundProject = false
        local started = false
        -- 找到对应项目并按玩家调整后的价格开盘
        for _, proj in ipairs(GD.projects or {}) do
            if tostring(proj.id or "") == tostring(presale.projectId or "") then
                foundProject = true
                if proj.sales and proj.sales.canPresale and not proj.sales.canSell then
                    local price = ceoNumber(presale.openingPrice, 0)
                    if price < 1000 then price = ceoSuggestedProjectPrice(GD, proj) end
                    if price > 0 then
                        proj.sales.basePrice = price
                        proj.sales.approvedOpeningPrice = price
                    end
                    local done = GD.StartPresale(proj)
                    if done then
                        proj._presaleApproved = true
                        proposals.presale.executionStatus = "applied"
                        applied = applied + 1
                        started = true
                        GD.AddEvent("【" .. proj.name .. "】CEO已按批准价格" .. (price or 0) .. "元/平开盘预售", "success")
                    end
                end
                break
            end
        end
        if not foundProject then
            ok = false
            msg = "计划开盘项目已不存在"
        elseif not started then
            ok = false
            msg = "计划开盘项目当前不满足预售条件，请重新查看CEO汇报"
        end
    end
    if ok and proposals.clearanceResults and proposals.clearanceResults.enabled then
        for _, result in ipairs(proposals.clearanceResults.items or {}) do
            if result.confirmed == true and result.executionStatus ~= "applied" then
                local matched = false
                for _, project in ipairs(GD.projects or {}) do
                    if tostring(project.id or "") == tostring(result.projectId or "") then
                        local actualResult = result.resultType == "fixed_asset_rental"
                            and project.ceoFixedAssetResult or project.ceoClearanceResult
                        local valid = actualResult
                            and tostring(actualResult.id or "") == tostring(result.id or "")
                        if result.resultType == "sale_clearance" then
                            valid = valid and project.salesCleared
                                and project.clearanceSheet and project.clearanceSheet.taxPaid
                        else
                            valid = valid and project._fixedAssetConverted
                        end
                        if not valid then
                            ok = false
                            msg = "项目成果已发生变化，请重新查看CEO汇报"
                        else
                            actualResult.confirmed = true
                            actualResult.confirmedMonth = GD.totalMonths
                            project.ceoClearanceReported = true
                            result.executionStatus = "applied"
                            matched = true
                        end
                        break
                    end
                end
                if ok and not matched then
                    ok = false
                    msg = "待确认项目成果已不存在"
                end
                if not ok then break end
            end
        end
    end
    if applied > 0 then
        report.appliedActionCount = math.max(0, ceoNumber(report.appliedActionCount, 0)) + applied
    end
    if ok then
        report.status = "approved"
        report.approvedMonth = GD.totalMonths
        gov.pendingCeoReport = nil
        table.insert(gov.ceoReportHistory, 1, report)
        if #gov.ceoReportHistory > 12 then table.remove(gov.ceoReportHistory) end
        GD.AddEvent("CEO月报已批准，执行" .. tostring(report.appliedActionCount or 0) .. "项经营计划", "success")
        GD.CaptureActiveCompanyState()
    elseif GD.CaptureActiveCompanyState then
        -- 失败前可能已有批准项成功落账；同步执行标记与公司状态，后续重试只处理未完成项。
        GD.CaptureActiveCompanyState()
    end
    restoreOriginalCompany()
    return ok, msg or "CEO月报已处理"
end

function GV.RejectCeoReport(GD, report)
    if not report or report.status ~= "pending" then return false, "报告已处理" end
    local targetSnapshot = ceoCompanySnapshot(GD, report.companyId or GD.activeCompanyId)
    if not targetSnapshot or not targetSnapshot.record or targetSnapshot.record.status ~= "operating" then
        report.status = "cancelled"
        report.cancelReason = "公司已退出经营"
        return true, "公司已退出经营，历史CEO汇报已自动作废"
    end
    local originalId = GD.activeCompanyId
    local target = report.companyId and tostring(report.companyId) or tostring(originalId)
    local function restoreOriginalCompany()
        if originalId and tostring(originalId) ~= tostring(GD.activeCompanyId) then
            GD.CaptureActiveCompanyState()
            GD.SwitchCompany(originalId)
        end
    end
    if target ~= tostring(originalId) then
        local ok, msg = GD.SwitchCompany(report.companyId)
        if not ok then
            restoreOriginalCompany()
            return false, msg
        end
    end
    local gov = GD.company.governance
    report.status = "rejected"
    report.rejectedMonth = GD.totalMonths
    gov.pendingCeoReport = nil
    table.insert(gov.ceoReportHistory, 1, report)
    if #gov.ceoReportHistory > 12 then table.remove(gov.ceoReportHistory) end
    GD.AddEvent("CEO月报计划已拒绝，本月保持经营方向不变", "info")
    GD.CaptureActiveCompanyState()
    restoreOriginalCompany()
    return true, "CEO月报计划已拒绝"
end
function GV.GetExecutiveEffects(GD)
    local effects = {
        revenueBonus = 0,
        expenseReduction = 0,
        riskReduction = 0,
        speedBonus = 0,
        teamBonus = 0,
    }
    local gov = GD.company and GD.company.governance
    for roleId, _ in pairs(gov and gov.executives or {}) do
        local roleDef
        for _, candidate in ipairs(GV.EXECUTIVE_ROLES) do
            if candidate.id == roleId then
                roleDef = candidate
                break
            end
        end
        if roleDef then
            local value = tonumber(roleDef.effectValue) or 0
            if roleDef.effect == "execution" or roleDef.effect == "coordination" then
                effects.speedBonus = effects.speedBonus + value
            elseif roleDef.effect == "revenueBoost" or roleDef.effect == "techBoost" then
                effects.revenueBonus = effects.revenueBonus + value
            elseif roleDef.effect == "riskReduce" then
                effects.riskReduction = effects.riskReduction + value
            elseif roleDef.effect == "teamBoost" then
                effects.teamBonus = effects.teamBonus + value
            elseif roleDef.effect == "autoManage" then
                effects.speedBonus = effects.speedBonus + value
            else
                effects.expenseReduction = effects.expenseReduction + value
            end
        end
    end
    return effects
end

function GV.RunExecutiveMonthlyDuties(GD)
    local gov = GD.company and GD.company.governance
    local executives = gov and gov.executives
    if not executives then return 0 end
    local handled = 0
    local fullManagement = GV.IsFullManagementEnabled(GD)

    -- CEO全权托管只处理无需玩家二次确认的常规事项；拿地、立项和战略开发仍走CEO月报。
    if executives.ceo and fullManagement then
        handled = handled + GV.RunFullManagement(GD)
    end

    -- 非全权托管时，由总经理/副总经理推进常规项目流程；全权托管由CEO统一调度。
    if not fullManagement and (executives.gm or executives.deputy_gm) then
        handled = handled + GV.AutoManageCompany(GD, true)
    end

    if executives.cmo then
        local ok = GV.ExecuteAction(GD, "cmo")
        if ok then handled = handled + 1 end
    end
    if executives.cto and (GD.totalMonths or 0) % 3 == 0 then
        local ok = GV.ExecuteAction(GD, "cto")
        if ok then handled = handled + 1 end
    end
    if executives.clo and (GD.totalMonths or 0) % 3 == 0 then
        local ok = GV.ExecuteAction(GD, "clo")
        if ok then handled = handled + 1 end
    end
    -- 普通高管的自动职责：每月共用与手动按钮一致的职责实现。
    if executives.hr_director then
        local ok = GV.ExecuteAction(GD, "hr_director")
        if ok then handled = handled + 1 end
    end
    if executives.cho then
        local ok = GV.ExecuteAction(GD, "cho")
        if ok then handled = handled + 1 end
    end
    if executives.cfo then
        local ok = GV.ExecuteAction(GD, "cfo")
        if ok then handled = handled + 1 end
    end
    if executives.coo then
        local ok = GV.ExecuteAction(GD, "coo")
        if ok then handled = handled + 1 end
    end
    if executives.finance_director then
        local ok = GV.ExecuteAction(GD, "finance_director")
        if ok then handled = handled + 1 end
    end
    return handled
end

function GV.MonthlyUpdate(GD)
    local gov = GD.company and GD.company.governance
    if not gov then return end
    local fName = GD.player and GD.player.founderName
    GV.EnsureGovernanceFields(gov, fName)
    -- 更新创始人持股比例缓存
    GV._refreshRatios(gov)
    -- 按股份比例分配董事会席位
    GV.AllocateBoardSeats(gov)
    -- 处理高管月薪
    GV._processExecutiveSalaries(GD)
    GV.RunExecutiveMonthlyDuties(GD)
    -- 检查控制权变化
    local level = GV.GetControlLevel(gov.founderRatio)
    if level.name == "少数股东" and not gov._lostControlWarned then
        GD.AddEvent("警告：" .. (fName or "创始人") .. "持股降至" .. math.floor(gov.founderRatio * 100) .. "%，已失去否决权！", "danger")
        gov._lostControlWarned = true
    end
end

-- ============================================================================
-- 年度分红（核心改革）
-- ============================================================================

local function payFounderDividend(GD, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    local groupSystem = GD.GroupSystem
    local activeCompanyId = GD.activeCompanyId
    local paidToGroup = groupSystem
        and groupSystem.IsMemberCompany(GD, activeCompanyId)
        and groupSystem.ReceiveCompanyDividend(GD, activeCompanyId, amount)
    if paidToGroup then return true end
    if not GD.player then return false end
    GD.player.cash = (GD.player.cash or 0) + amount
    GD.player.totalDividends = (GD.player.totalDividends or 0) + amount
    GD.player.totalIncome = (GD.player.totalIncome or 0) + amount
    GD.player.yearlyIncome = (GD.player.yearlyIncome or 0) + amount
    GD.player.yearlyDividends = (GD.player.yearlyDividends or 0) + amount
    return true
end

---@param GD table GameData全局单例
---@return number dividend 实际分红总额
function GV.DistributeDividend(GD)
    local c = GD.company
    local gov = c.governance
    if not gov then return 0 end

    if c.annualProfit <= 0 then
        return 0
    end

    local policy = gov.dividendPolicy
    -- 计算可分配金额
    local maxByProfit = math.floor(c.annualProfit * policy.rate)
    local maxByCash   = math.max(0, math.floor(c.cash - c.cash * policy.minCashRatio))
    local dividend    = math.min(maxByProfit, maxByCash)

    if dividend <= 0 then
        return 0
    end

    -- 从公司现金扣除
    c.cash = c.cash - dividend
    c.lastDividend = dividend

    -- 按持股比例分配。尾差归入创始人份额，确保公司扣款与股东收款总额完全一致。
    local distributed = 0
    local founderShareholder = nil
    local shares = {}
    for i, sh in ipairs(gov.shareholders) do
        local share = math.floor(dividend * (sh.ratio or 0))
        shares[i] = share
        distributed = distributed + share
        if sh.id == "founder" then founderShareholder = i end
    end
    local remainder = math.max(0, dividend - distributed)
    if remainder > 0 then
        local recipient = founderShareholder or #gov.shareholders
        if recipient > 0 then shares[recipient] = (shares[recipient] or 0) + remainder end
    end

    for i, sh in ipairs(gov.shareholders) do
        local share = shares[i] or 0
        if sh.id == "founder" then
            payFounderDividend(GD, share)
        end
        sh.totalDividends = (sh.totalDividends or 0) + share
    end

    return dividend
end

-- ============================================================================
-- 融资
-- ============================================================================

--- 判断能否进行某轮融资
---@param GD table
---@param roundId string
---@return boolean ok
---@return string? reason
function GV.CanFinance(GD, roundId)
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    local roundDef = GV.FINANCING_ROUNDS[roundId]
    if not roundDef then return false, "未知融资轮次" end

    -- 检查是否已完成该轮
    for _, h in ipairs(gov.financingHistory) do
        if h.round == roundId then
            return false, roundDef.name .. "已完成"
        end
    end

    -- 检查顺序（只能进行当前或之后的轮次）
    -- 如果已完成所有融资轮次（含IPO），不再允许新的融资
    if gov.currentRound == "completed" then
        return false, "已完成IPO，无法再进行股权融资"
    end
    local currentOrder = GV.FINANCING_ROUNDS[gov.currentRound]
    if currentOrder and roundDef.order < currentOrder.order then
        return false, "需先完成" .. currentOrder.name
    end

    -- 检查营收门槛
    local annualRevenue = GD.company.monthlyRevenue * 12
    if annualRevenue < roundDef.minRevenue then
        return false, "年营收需达到" .. GD.FormatMoney(roundDef.minRevenue)
    end

    -- IPO检查：创始人持股不能太低
    if roundId == "ipo" and gov.founderRatio < 0.25 then
        return false, "创始人持股低于25%，不满足上市条件"
    end

    return true
end

--- 执行融资
---@param GD table
---@param roundId string
---@param dilutionPct number 实际稀释比例 (0.05~0.25)
---@return boolean ok
---@return string? message
function GV.ExecuteFinancing(GD, roundId, dilutionPct)
    local ok, reason = GV.CanFinance(GD, roundId)
    if not ok then return false, reason end

    local gov = GD.company.governance
    local roundDef = GV.FINANCING_ROUNDS[roundId]

    -- 限定稀释范围
    dilutionPct = math.max(roundDef.dilutionRange[1], math.min(roundDef.dilutionRange[2], dilutionPct))

    -- 30%持股底线检查：预估融资后创始人持股
    local estNewRatio = gov.founderRatio * (1 - dilutionPct)
    if estNewRatio < GV.FOUNDER_MIN_RATIO then
        return false, string.format("融资后创始人持股将降至%.1f%%，低于%.0f%%底线，禁止操作",
            estNewRatio * 100, GV.FOUNDER_MIN_RATIO * 100)
    end

    -- 计算估值
    local totalAssets = GD.company.totalAssets
    local multMin, multMax = roundDef.valuationMult[1], roundDef.valuationMult[2]
    local mult = multMin + math.random() * (multMax - multMin)
    local preValuation = math.floor(totalAssets * mult)

    -- 融资金额 = 估值 * 稀释比例
    local raiseAmount = math.floor(preValuation * dilutionPct)

    -- 增发股份
    local newShares = math.floor(gov.totalShares * dilutionPct / (1 - dilutionPct))
    gov.totalShares = gov.totalShares + newShares

    -- 稀释所有现有股东
    for _, sh in ipairs(gov.shareholders) do
        sh.ratio = sh.shares / gov.totalShares
    end

    -- 添加新股东
    local investorName
    if roundId == "angel" then
        investorName = "天使投资人"
    elseif roundId == "ipo" then
        investorName = "公众股东"
    else
        investorName = roundDef.name .. "投资方"
    end
    local investorId = roundId .. "_investor_" .. #gov.financingHistory + 1
    local investorType = (roundId == "ipo") and "public" or "institutional"
    table.insert(gov.shareholders, {
        id = investorId,
        name = investorName,
        shares = newShares,
        ratio = newShares / gov.totalShares,
        type = investorType,
        totalDividends = 0,
        investAmount = raiseAmount,
    })

    -- 更新创始人持股
    for _, sh in ipairs(gov.shareholders) do
        if sh.id == "founder" then
            gov.founderShares = sh.shares
            gov.founderRatio = sh.ratio
            break
        end
    end

    -- 资金注入公司
    GD.company.cash = GD.company.cash + raiseAmount

    -- 记录融资历史
    table.insert(gov.financingHistory, {
        round = roundId,
        name = roundDef.name,
        preValuation = preValuation,
        postValuation = preValuation + raiseAmount,
        raiseAmount = raiseAmount,
        dilution = dilutionPct,
        newShares = newShares,
        investorName = investorName,
        year = GD.year,
        month = GD.month,
    })

    -- 更新轮次状态
    gov.currentRound = GV.GetNextRound(roundId)
    gov.lastValuation = preValuation + raiseAmount
    gov.totalRaised = gov.totalRaised + raiseAmount

    if roundId == "ipo" then
        gov.isIPO = true
    end

    local groupSystem = GD.GroupSystem
    if groupSystem and groupSystem.IsMemberCompany(GD, GD.activeCompanyId) then
        groupSystem.OnCompanyOwnershipChanged(GD, GD.activeCompanyId, gov.founderRatio or 0)
    end

    return true, string.format(
        "%s完成！融资%s，估值%s，出让%.1f%%股权",
        roundDef.name,
        GD.FormatMoney(raiseAmount),
        GD.FormatMoney(preValuation + raiseAmount),
        dilutionPct * 100
    )
end

-- ============================================================================
-- 查询工具
-- ============================================================================

function GV.GetFounderRatio(GD)
    local gov = GD.company and GD.company.governance
    if not gov then return 1.0 end
    return gov.founderRatio or 1.0
end

function GV.GetControlLevel(ratio)
    for _, level in ipairs(GV.CONTROL_LEVELS) do
        if ratio >= level.threshold then
            return level
        end
    end
    return GV.CONTROL_LEVELS[#GV.CONTROL_LEVELS]
end

function GV.GetNextRound(currentRound)
    for i, id in ipairs(GV.ROUND_ORDER) do
        if id == currentRound and i < #GV.ROUND_ORDER then
            return GV.ROUND_ORDER[i + 1]
        end
    end
    return "completed"
end

function GV.GetShareholderCount(GD)
    local gov = GD.company and GD.company.governance
    if not gov then return 1 end
    return #gov.shareholders
end

--- 获取融资摘要
function GV.GetFinancingSummary(GD)
    local gov = GD.company and GD.company.governance
    if not gov then return {rounds = 0, totalRaised = 0, lastValuation = 0} end
    return {
        rounds = #gov.financingHistory,
        totalRaised = gov.totalRaised,
        lastValuation = gov.lastValuation,
        currentRound = gov.currentRound,
        isIPO = gov.isIPO,
    }
end

--- 设置分红率
function GV.SetDividendRate(GD, rate)
    local gov = GD.company and GD.company.governance
    if not gov then return end
    rate = math.max(0, math.min(0.80, rate))
    gov.dividendPolicy.rate = rate
    -- 同步到公司级字段，确保 YearlyDividend 触发条件正确
    GD.company.dividendRate = rate
end

-- ============================================================================
-- 内部工具
-- ============================================================================

function GV._refreshRatios(gov)
    if gov.totalShares <= 0 then return end
    gov.founderShares = 0
    gov.founderRatio = 0
    for _, sh in ipairs(gov.shareholders) do
        sh.ratio = sh.shares / gov.totalShares
        if sh.id == "founder" then
            gov.founderShares = sh.shares
            gov.founderRatio = sh.ratio
        end
    end
end

-- ============================================================================
-- 董事会决策系统
-- ============================================================================

GV.BOARD_RESOLUTIONS = {
    {id = "strategy_change",  name = "战略方向调整",   desc = "调整公司发展战略方向",        icon = "🧭", cost = 500,   cooldown = 6,  threshold = 0.50, effect = "strategyCost"},
    {id = "special_dividend",  name = "特别分红",       desc = "发放一次性特别分红",          icon = "💰", cost = 0,     cooldown = 12, threshold = 0.67, effect = "specialDividend"},
    {id = "buyback_auth",      name = "授权股份回购",   desc = "董事会授权管理层进行回购",    icon = "🔄", cost = 0,     cooldown = 6,  threshold = 0.50, effect = "buybackAuth"},
    {id = "esop_create",       name = "设立期权池",     desc = "创建员工股权激励计划",        icon = "🎯", cost = 200,   cooldown = 12, threshold = 0.67, effect = "esopCreate"},
    {id = "brand_upgrade",     name = "品牌升级",       desc = "投入资金进行品牌形象升级",    icon = "✨", cost = 1000,  cooldown = 12, threshold = 0.50, effect = "brandUpgrade"},
    {id = "bonus_pool",        name = "设立奖金池",     desc = "拨出利润作为年终奖金池",      icon = "🏆", cost = 800,   cooldown = 12, threshold = 0.50, effect = "bonusPool"},
    {id = "expand_board",      name = "扩大董事会",     desc = "增加一个董事会席位",          icon = "🪑", cost = 300,   cooldown = 24, threshold = 0.67, effect = "expandBoard"},
    {id = "internal_audit",    name = "启动内部审计",   desc = "对公司财务进行全面审计",      icon = "🔍", cost = 600,   cooldown = 12, threshold = 0.34, effect = "audit"},
    {id = "risk_reserve",      name = "设立风险准备金", desc = "提取利润建立风险准备金",      icon = "🛡️", cost = 500,   cooldown = 6,  threshold = 0.50, effect = "riskReserve"},
    {id = "tech_invest",       name = "技术研发投入",   desc = "加大技术研发力度提升竞争力",  icon = "🔬", cost = 1500,  cooldown = 6,  threshold = 0.50, effect = "techInvest"},
}

--- 判断能否提出某项决议
---@param GD table
---@param resIdx number 决议在BOARD_RESOLUTIONS中的索引
---@return boolean ok
---@return string? reason
function GV.CanProposeResolution(GD, resIdx)
    local res = GV.BOARD_RESOLUTIONS[resIdx]
    if not res then return false, "未知决议" end
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    -- 检查冷却
    gov.resolutionCooldowns = gov.resolutionCooldowns or {}
    local lastTime = gov.resolutionCooldowns[res.id]
    if lastTime then
        local elapsed = GD.totalMonths - lastTime
        if elapsed < res.cooldown then
            return false, string.format("冷却中（还需%d个月）", res.cooldown - elapsed)
        end
    end

    -- 按股份计算董事会席位：拥有 10%以上持股的股东才能提出议案
    if gov.founderRatio < 0.10 then
        return false, "需持股≥10%才能提出议案"
    end

    -- 检查费用
    if res.cost > 0 and GD.company.cash < res.cost then
        return false, "资金不足（需" .. GD.FormatMoney(res.cost) .. "）"
    end

    return true
end

--- 执行董事会决议
---@param GD table
---@param resIdx number
---@return boolean ok
---@return string? message
function GV.ProposeResolution(GD, resIdx)
    local ok, reason = GV.CanProposeResolution(GD, resIdx)
    if not ok then return false, reason end

    local res = GV.BOARD_RESOLUTIONS[resIdx]
    local gov = GD.company.governance
    local co = GD.company

    -- 扣费用
    if res.cost > 0 then
        co.cash = co.cash - res.cost
    end

    -- 模拟投票
    local voteResult = GV._simulateVote(gov, res)

    -- 记录冷却
    gov.resolutionCooldowns = gov.resolutionCooldowns or {}
    gov.resolutionCooldowns[res.id] = GD.totalMonths

    if not voteResult.passed then
        -- 记录历史
        gov.resolutionHistory = gov.resolutionHistory or {}
        table.insert(gov.resolutionHistory, 1, {
            name = res.name, passed = false,
            yesVotes = voteResult.yesVotes, totalVotes = voteResult.totalVotes,
            year = GD.year, month = GD.month,
        })
        if #gov.resolutionHistory > 20 then table.remove(gov.resolutionHistory) end
        return false, res.name .. "未通过（赞成" .. string.format("%.0f%%", voteResult.yesVotes * 100) .. "）"
    end

    -- 执行效果
    local effectMsg = GV._applyResolutionEffect(GD, res)

    -- 记录历史
    gov.resolutionHistory = gov.resolutionHistory or {}
    table.insert(gov.resolutionHistory, 1, {
        name = res.name, passed = true,
        yesVotes = voteResult.yesVotes, totalVotes = voteResult.totalVotes,
        year = GD.year, month = GD.month,
    })
    if #gov.resolutionHistory > 20 then table.remove(gov.resolutionHistory) end

    gov.boardDecisionCount = (gov.boardDecisionCount or 0) + 1
    return true, res.name .. "通过！" .. (effectMsg or "")
end

--- 模拟股东会投票表决（按股份比例计票）
--- 重大事项需 2/3 以上通过，普通事项需 1/2 以上通过
function GV._simulateVote(gov, res)
    local yesVotes = 0
    local totalVotes = 0
    -- 所有股东按持股比例行使表决权
    for _, sh in ipairs(gov.shareholders) do
        totalVotes = totalVotes + sh.ratio
        -- 创始人和合伙人：全票赞成（提案人方）
        if sh.type == "founder" or sh.type == "partner" then
            yesVotes = yesVotes + sh.ratio
        -- 天使投资人：与创始人利益一致，大概率支持
        elseif sh.type == "angel" then
            if math.random() < 0.85 then yesVotes = yesVotes + sh.ratio end
        -- 机构投资人：审慎决策，根据议案成本判断
        elseif sh.type == "institutional" then
            local supportRate = 0.70
            if res.cost > 1000 then supportRate = 0.55 end  -- 高成本议案更谨慎
            if math.random() < supportRate then yesVotes = yesVotes + sh.ratio end
        -- 公众股东：跟随大股东倾向
        elseif sh.type == "public" then
            if gov.founderRatio >= 0.50 then
                -- 大股东控制力强，公众股东倾向跟随
                if math.random() < 0.75 then yesVotes = yesVotes + sh.ratio end
            else
                if math.random() < 0.50 then yesVotes = yesVotes + sh.ratio end
            end
        else
            if math.random() < 0.65 then yesVotes = yesVotes + sh.ratio end
        end
    end
    -- 特殊决议（threshold>=0.67）需2/3多数通过，普通决议需1/2多数
    local requiredRatio = res.threshold
    local passed = totalVotes > 0 and (yesVotes / totalVotes) >= requiredRatio
    return {passed = passed, yesVotes = yesVotes, totalVotes = totalVotes}
end

--- 应用决议效果
function GV._applyResolutionEffect(GD, res)
    local co = GD.company
    local gov = co.governance
    local eff = res.effect

    if eff == "strategyCost" then
        -- 战略调整：下个月运营效率+10%持续6个月
        gov.strategyBoostUntil = GD.totalMonths + 6
        return "战略调整生效，运营效率+10%持续6个月"

    elseif eff == "specialDividend" then
        -- 特别分红：立即分配利润的20%
        local amount = math.floor(co.cash * 0.20)
        if amount > 0 then
            co.cash = co.cash - amount
            local distributed = 0
            local founderIndex = nil
            local shares = {}
            for i, sh in ipairs(gov.shareholders) do
                local share = math.floor(amount * (sh.ratio or 0))
                shares[i] = share
                distributed = distributed + share
                if sh.id == "founder" then founderIndex = i end
            end
            local recipient = founderIndex or #gov.shareholders
            if recipient > 0 then
                shares[recipient] = (shares[recipient] or 0) + math.max(0, amount - distributed)
            end
            for i, sh in ipairs(gov.shareholders) do
                local share = shares[i] or 0
                sh.totalDividends = (sh.totalDividends or 0) + share
                if sh.id == "founder" then payFounderDividend(GD, share) end
            end
            return "特别分红" .. GD.FormatMoney(amount)
        end
        return "现金不足无法分红"

    elseif eff == "buybackAuth" then
        gov.buybackAuthorized = true
        return "已授权股份回购"

    elseif eff == "esopCreate" then
        gov.esopPool = gov.esopPool or 0
        local esopShares = math.floor(gov.totalShares * 0.05)
        gov.esopPool = gov.esopPool + esopShares
        return "期权池增加" .. esopShares .. "股（5%）"

    elseif eff == "brandUpgrade" then
        -- 品牌升级：月收入+5%持续12个月
        gov.brandBoostUntil = GD.totalMonths + 12
        return "品牌升级生效，月收入+5%持续12个月"

    elseif eff == "bonusPool" then
        -- 奖金池：士气提升
        gov.bonusPoolActive = true
        gov.bonusPoolUntil = GD.totalMonths + 12
        return "奖金池已设立，员工士气提升"

    elseif eff == "expandBoard" then
        gov.boardSeats = (gov.boardSeats or 3) + 1
        return "董事会扩大至" .. gov.boardSeats .. "席"

    elseif eff == "audit" then
        gov.auditCount = (gov.auditCount or 0) + 1
        -- 审计发现节省：减少5%运营成本1年
        gov.auditSavingUntil = GD.totalMonths + 12
        return "审计完成，运营成本-5%持续12个月"

    elseif eff == "riskReserve" then
        -- 风险准备金
        gov.riskReserve = (gov.riskReserve or 0) + res.cost
        return "风险准备金增至" .. GD.FormatMoney(gov.riskReserve)

    elseif eff == "techInvest" then
        -- 技术投资：收入+8%持续6个月
        gov.techBoostUntil = GD.totalMonths + 6
        return "研发投入生效，收入+8%持续6个月"
    end
    return ""
end

-- ============================================================================
-- 高管团队系统
-- ============================================================================

-- salary = 年薪(万), bonus = 签约奖金(万), monthlySalary 由 salary/12 自动计算
GV.EXECUTIVE_ROLES = {
    {id = "ceo",  name = "首席执行官(CEO)", desc = "统筹公司战略和日常经营，负责全权托管决策", icon = "♛", salary = 80, bonus = 20, effect = "autoManage", effectValue = 0.10,
     action = "automanage", actionName = "托管状态", actionDesc = "选择是否由CEO全权自动经营"},
    {id = "gm",   name = "总经理", desc = "负责业务落地和项目推进，协助公司自动运转", icon = "◆", salary = 60, bonus = 15, effect = "execution", effectValue = 0.08,
     action = "automanage", actionName = "经营调度", actionDesc = "自动处理公司当前可执行的经营动作"},
    {id = "deputy_gm", name = "副总经理", desc = "分管项目执行和跨部门协同，提升自动经营覆盖率", icon = "◇", salary = 45, bonus = 10, effect = "coordination", effectValue = 0.06,
     action = "automanage", actionName = "协同推进", actionDesc = "协助总经理推进待办事项"},
    {id = "finance_director", name = "财务总监", desc = "管理现金流、融资和成本纪律", icon = "¥", salary = 38, bonus = 8, effect = "financeControl", effectValue = 0.05,
     action = "autofinance", actionName = "财务巡检", actionDesc = "检查现金流、贷款和可用授信"},
    {id = "hr_director", name = "人事总监", desc = "管理招聘、组织架构和项目经理配置", icon = "▣", salary = 32, bonus = 6, effect = "teamBoost", effectValue = 0.05,
     action = "autohire", actionName = "招聘巡检", actionDesc = "为缺少项目经理的项目推荐人选"},
    {id = "cfo",  name = "首席财务官(CFO)", desc = "管理公司财务，一键缴税、优化税务",   icon = "▥", salary = 45, bonus = 10, effect = "opexReduce",   effectValue = 0.05,
     action = "autotax",  actionName = "一键缴税", actionDesc = "自动计算并完成当期税务申报"},
    {id = "coo",  name = "首席运营官(COO)", desc = "优化运营流程，一键收租、物业管理",   icon = "▤", salary = 40, bonus = 8,  effect = "opEfficiency", effectValue = 0.08,
     action = "autorent", actionName = "一键收租", actionDesc = "自动收取所有物业和租金收入"},
    {id = "cmo",  name = "首席营销官(CMO)", desc = "营销推广，一键调价、提升销售速度",   icon = "▸", salary = 35, bonus = 8,  effect = "revenueBoost", effectValue = 0.06,
     action = "autoprice", actionName = "一键调价", actionDesc = "根据市场行情自动调整所有在售项目定价"},
    {id = "cto",  name = "首席技术官(CTO)", desc = "技术研发，提升建筑品质、降低成本",   icon = "▦", salary = 50, bonus = 12, effect = "techBoost",    effectValue = 0.07,
     action = "autotech", actionName = "技术优化", actionDesc = "降低所有在建项目5%建设成本"},
    {id = "clo",  name = "首席法务官(CLO)", desc = "法律合规，一键合规检查、降低风险",   icon = "§", salary = 30, bonus = 6,  effect = "riskReduce",   effectValue = 0.10,
     action = "autoaudit", actionName = "合规检查", actionDesc = "对所有项目进行合规审查，降低罚款风险"},
    {id = "cho",  name = "首席人事官(CHO)", desc = "人才管理，一键招聘项目经理",         icon = "▨", salary = 25, bonus = 5,  effect = "teamBoost",    effectValue = 0.05,
     action = "autohire", actionName = "推荐人才", actionDesc = "为缺少项目经理的项目推荐合适人选"},
}

--- 聘用高管
---@param GD table
---@param roleId string
---@return boolean ok
---@return string? message
function GV.HireExecutive(GD, roleId)
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    local roleDef
    for _, r in ipairs(GV.EXECUTIVE_ROLES) do
        if r.id == roleId then roleDef = r; break end
    end
    if not roleDef then return false, "未知职位" end

    gov.executives = gov.executives or {}
    -- 检查是否已聘用
    if gov.executives[roleId] then
        return false, roleDef.name .. "已在职"
    end

    -- 检查聘用奖金
    if GD.company.cash < roleDef.bonus then
        return false, "资金不足（聘用奖金需" .. GD.FormatMoney(roleDef.bonus) .. "）"
    end

    -- 扣聘用奖金
    GD.company.cash = GD.company.cash - roleDef.bonus

    gov.executives[roleId] = {
        id = roleId,
        name = roleDef.name,
        hiredMonth = GD.totalMonths,
        hiredYear = GD.year,
        hiredMon = GD.month,
        salary = roleDef.salary,
        totalPaid = roleDef.bonus,
    }

    return true, "成功聘用" .. roleDef.name .. "（签约奖金" .. GD.FormatMoney(roleDef.bonus) .. "）"
end

--- 解雇高管
---@param GD table
---@param roleId string
---@return boolean ok
---@return string? message
function GV.FireExecutive(GD, roleId)
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    gov.executives = gov.executives or {}
    if not gov.executives[roleId] then
        return false, "该职位无人在职"
    end

    local roleDef
    for _, r in ipairs(GV.EXECUTIVE_ROLES) do
        if r.id == roleId then roleDef = r; break end
    end

    -- 解雇补偿：3个月月薪
    local monthlySal = (roleDef and roleDef.salary or 36) / 12
    local severance = math.floor(monthlySal * 3 * 100) / 100
    if GD.company.cash >= severance then
        GD.company.cash = GD.company.cash - severance
    end

    local name = gov.executives[roleId].name
    gov.executives[roleId] = nil

    return true, "已解雇" .. name .. "（遣散费" .. GD.FormatMoney(severance) .. "）"
end

function GV.SetCeoReportEnabled(GD, enabled)
    local gov = GD.company and GD.company.governance
    if not gov then return false, "未初始化治理结构" end
    GV.EnsureGovernanceFields(gov, GD.player and GD.player.founderName)
    gov.ceoReportEnabled = enabled == true
    if not gov.ceoReportEnabled then
        gov.pendingCeoReport = nil
        -- 汇报关闭后立即移除本公司的旧审批待办，CEO从本月起按既有策略自主经营。
        if GD._pendingCeoReportQueue then
            local companyId = tostring(GD.activeCompanyId or "")
            for index = #GD._pendingCeoReportQueue, 1, -1 do
                local report = GD._pendingCeoReportQueue[index]
                if tostring(report and report.companyId or "") == companyId then
                    table.remove(GD._pendingCeoReportQueue, index)
                end
            end
            GD._pendingCeoReportPopup = #GD._pendingCeoReportQueue > 0
        end
    end
    if GD.CaptureActiveCompanyState then GD.CaptureActiveCompanyState() end
    if GV.ReopenPendingCeoReports then GV.ReopenPendingCeoReports(GD) end
    return true, gov.ceoReportEnabled
        and "已开启CEO经营汇报，重大计划按设定频次提交审批"
        or "已关闭CEO经营汇报，CEO继续按现有策略自主经营"
end

function GV.SetFullManagement(GD, enabled)
    local gov = GD.company and GD.company.governance
    if not gov then return false, "未初始化治理结构" end
    GV.EnsureGovernanceFields(gov, GD.player and GD.player.founderName)
    if enabled and not gov.executives.ceo then
        return false, "启用全权托管前必须先聘用CEO"
    end

    gov.fullManagement = enabled == true
    if gov.fullManagement then
        gov.fullManagementSince = GD.totalMonths
        gov.lastFullManagementMonth = nil
        gov.pendingCeoReport = nil
        if gov.ceoReportEnabled ~= false then
            print("[Governance] CEO全权托管已开启，重大计划按汇报频次提交审批")
            return true, "已启用CEO全权托管，CEO立即接管日常经营并按设定频次提交重大计划"
        end
        print("[Governance] CEO静默全权托管已开启，按现有策略自主经营")
        return true, "已启用CEO全权托管，CEO将按现有策略自主经营且不弹出汇报"
    end

    gov.fullManagementSince = nil
    gov.lastFullManagementMonth = nil
    gov.lastAutoManageMonth = nil
    gov.pendingCeoReport = nil
    for _, project in ipairs(GD.projects or {}) do
        local pm = project.projectManager
        if pm and pm.hired and pm.autoMode then
            pm.autoMode = false
            pm.report = nil
        end
    end
    -- 关闭当前公司托管只移除该公司的报告，其他托管公司的待审批报告继续逐个展示。
    GD.CaptureActiveCompanyState()
    if GV.ReopenPendingCeoReports then
        GV.ReopenPendingCeoReports(GD)
    else
        GD._pendingCeoReportQueue = nil
        GD._pendingCeoReportPopup = false
    end
    print("[Governance] CEO全权托管已关闭，自动经营与项目经理自动模式已停止")
    return true, "已关闭CEO全权托管，CEO停止自动操作，由玩家手动管理"
end

function GV.IsFullManagementEnabled(GD)
    local gov = GD.company and GD.company.governance
    return gov ~= nil and gov.fullManagement == true and gov.executives and gov.executives.ceo ~= nil
end

function GV.GetManagementCashReserve(GD)
    local company = GD.company
    if not company then return 1 end

    local reserve = 1
    local gov = company.governance
    if gov and gov.executives then
        for _, exec in pairs(gov.executives) do
            reserve = reserve + math.floor(((exec.salary or 0) / 12) * 100) / 100
        end
    end

    local oldSalary = 0
    for _, emp in ipairs(company.employees or {}) do
        oldSalary = oldSalary + (emp.salary or 0)
    end
    reserve = reserve + oldSalary / 10000

    for _, dept in ipairs(company.hqDepartments or {}) do
        if dept.established then
            reserve = reserve + (dept.monthCost or 0)
        end
    end
    if GD.GetTotalDeptSalary then
        reserve = reserve + GD.GetTotalDeptSalary()
    end

    for _, kp in ipairs(company.keyPositions or {}) do
        reserve = reserve + (kp.salary or 0) / 12
    end

    for _, proj in ipairs(GD.projects or {}) do
        if proj.projectManager and proj.projectManager.hired then
            reserve = reserve + (proj.projectManager.salary or 0)
        end
        if proj.cost then
            reserve = reserve + math.floor(((proj.cost.landCost or 0) * 0.04 / 12) * 100) / 100
        end
        if proj.status == "construction" or proj.status == "presale" then
            local totalMonths = math.max(1, proj.construction and proj.construction.totalMonths or 1)
            reserve = reserve + math.floor(((proj.cost.buildCost or 0) / totalMonths) * 100) / 100
        end
    end

    for _, loan in ipairs(GD.loans or {}) do
        local interest = (loan.amount or 0) * (loan.rate or 0) / 100 / 12
        reserve = reserve + interest
        if (loan.remainMonths or 1) <= 1 then
            reserve = reserve + (loan.amount or 0)
            if loan.repayMethod == "bullet" then
                reserve = reserve + (loan.accruedInterest or 0)
            end
        end
    end

    return math.floor(reserve * 100) / 100
end

function GV.GetManagementDebtRatio(GD)
    local company = GD.company or {}
    local assets = math.max(1, ceoNumber(company.totalAssets, company.registeredCapital))
    local debt = math.max(0, ceoNumber(company.totalDebt, 0))
    return debt / assets, assets, debt
end

function GV.GetManagementLoanRoom(GD, targetRatio)
    local _, assets, debt = GV.GetManagementDebtRatio(GD)
    local ratio = math.max(0, math.min(0.65, ceoNumber(targetRatio, 0)))
    if ratio <= 0 or debt / assets >= ratio then return 0 end
    -- 贷款到账会同时增加资产与负债，故需解：(debt + loan) / (assets + loan) <= targetRatio
    return math.max(0, math.floor((ratio * assets - debt) / math.max(0.35, 1 - ratio)))
end

function GV.ManageCeoCashflow(GD, requiredCash, reason)
    local company = GD.company
    local gov = company and company.governance
    if not company or not gov or not GV.IsFullManagementEnabled(GD) then return 0 end

    local targetRatio = math.max(0, math.min(0.65, ceoNumber(gov.ceoTargetDebtRatio, 0)))
    if targetRatio <= 0 then return 0 end
    local reserve = GV.GetManagementCashReserve(GD)
    local targetCash = math.max(reserve + 1, ceoNumber(requiredCash, 0))
    local cashGap = math.ceil(math.max(0, targetCash - ceoNumber(company.cash, 0)))
    if cashGap <= 0 then return 0 end

    local room = GV.GetManagementLoanRoom(GD, targetRatio)
    if room <= 0 then
        return 0
    end

    -- 贷款到账受政策融资倍率影响，按预计净到账反推申请额；实际负债率仍由 ApplyLoan 后结果约束。
    local policyMultiplier = ME.GetPolicyFinanceMultiplier(GD.policy)
    local maxRequested = math.floor(room / policyMultiplier)
    local requested = math.min(math.ceil(cashGap / policyMultiplier), maxRequested)
    requested = math.max(0, requested)
    if requested <= 0 then return 0 end

    local rate = (GD.economy and GD.economy.interestRate or 4.2) + 1.0
    local ok, msg, effectiveAmount = GD.ApplyLoan("CEO自主现金流贷款", requested, rate, 24, nil, "interest_monthly")
    if not ok then
        GD.AddEvent("CEO现金流管理贷款失败：" .. tostring(msg or "融资条件不满足"), "warning")
        return 0
    end
    effectiveAmount = math.max(0, ceoNumber(effectiveAmount, 0))
    if effectiveAmount <= 0 then return 0 end
    gov.lastAutoLoanMonth = GD.totalMonths
    gov.lastAutoLoanReason = reason or "现金安全预留"
    gov.lastAutoLoanAmount = effectiveAmount
    local currentRatio = GV.GetManagementDebtRatio(GD)
    GD.AddEvent("CEO已为" .. (reason or "现金流安全") .. "自动融资，当前资产负债率"
        .. string.format("%.1f%%", currentRatio * 100) .. "，目标不超过"
        .. string.format("%.0f%%", targetRatio * 100), "info")
    return 1
end

function GV.EnsureManagementCash(GD, amount, reason)
    amount = math.max(0, ceoNumber(amount, 0))
    -- 无需支付时不应进入现金预留门禁。项目零差额结算、零所得税清盘都必须继续执行。
    if amount <= 0 then return true end
    if GV.CanSpendManagementCash(GD, amount) then return true end
    GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + amount + 1, reason)
    return GV.CanSpendManagementCash(GD, amount)
end

function GV.ManageCeoDebtRepayment(GD)
    local company = GD.company
    local gov = company and company.governance
    if not company or not gov or not GV.IsFullManagementEnabled(GD) then return 0 end
    if gov.lastAutoLoanMonth == GD.totalMonths or gov.lastAutoRepayMonth == GD.totalMonths then
        return 0
    end
    if not GD.EarlyRepayLoan or #(GD.loans or {}) == 0 then return 0 end

    -- 两个月经营安全预留以外的现金才可用于还款，避免还款后重新贷款或影响项目推进。
    local reserve = GV.GetManagementCashReserve(GD)
    local availableCash = math.floor(math.max(0, ceoNumber(company.cash, 0) - reserve * 2))
    if availableCash <= 0 then return 0 end

    local candidates = {}
    for loanIdx, loan in ipairs(GD.loans or {}) do
        if ceoNumber(loan.amount, 0) > 0 then
            table.insert(candidates, {index = loanIdx, loan = loan})
        end
    end
    table.sort(candidates, function(a, b)
        local aMonths = ceoNumber(a.loan.remainMonths, math.huge)
        local bMonths = ceoNumber(b.loan.remainMonths, math.huge)
        if aMonths ~= bMonths then return aMonths < bMonths end
        local aRate = ceoNumber(a.loan.rate, 0)
        local bRate = ceoNumber(b.loan.rate, 0)
        if aRate ~= bRate then return aRate > bRate end
        return ceoNumber(a.loan.amount, 0) < ceoNumber(b.loan.amount, 0)
    end)

    local selected = candidates[1]
    if not selected then return 0 end
    local loan = selected.loan
    local outstanding = ceoNumber(loan.amount, 0)
    local repaymentFactor = 1
    if loan.repayMethod == "bullet" and ceoNumber(loan.accruedInterest, 0) > 0 then
        repaymentFactor = 1 + ceoNumber(loan.accruedInterest, 0) / math.max(1, outstanding)
    end
    local principal = math.min(outstanding, math.floor(availableCash / repaymentFactor))
    if principal <= 0 then return 0 end

    local ratioBefore = GV.GetManagementDebtRatio(GD)
    local ok, _, actualPrincipal = GD.EarlyRepayLoan(selected.index, principal)
    if not ok then return 0 end

    actualPrincipal = math.max(0, ceoNumber(actualPrincipal, principal))
    gov.lastAutoRepayMonth = GD.totalMonths
    gov.lastAutoRepayAmount = actualPrincipal
    local ratioAfter = GV.GetManagementDebtRatio(GD)
    local targetRatio = math.max(0, math.min(0.65, ceoNumber(gov.ceoTargetDebtRatio, 0)))
    GD.AddEvent("CEO已使用安全预留外现金自动偿还贷款本金" .. GD.FormatMoney(actualPrincipal)
        .. "，资产负债率由" .. string.format("%.1f%%", ratioBefore * 100)
        .. "降至" .. string.format("%.1f%%", ratioAfter * 100)
        .. "，目标上限" .. string.format("%.0f%%", targetRatio * 100), "success")
    return 1
end

function GV.CanSpendManagementCash(GD, amount)
    local company = GD.company
    amount = tonumber(amount) or 0
    return company ~= nil and amount > 0
        and (company.cash or 0) - amount - GV.GetManagementCashReserve(GD) > 0
end

function GV.CanMaintainPositiveCash(GD, amount)
    local company = GD.company
    amount = tonumber(amount) or 0
    return company ~= nil and amount >= 0
        and (company.cash or 0) - amount > 0
end

function GV.SpendManagedCash(GD, amount, message)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    if GV.IsFullManagementEnabled(GD)
        and not GV.CanMaintainPositiveCash(GD, amount)
    then
        if message then GD.AddEvent(message, "warning") end
        return false
    end
    GD.company.cash = GD.company.cash - amount
    return true
end

function GV._HireManagementTeam(GD)
    local gov = GD.company and GD.company.governance
    if not gov then return 0 end
    local hired = 0
    local requiredRoles = {"gm", "finance_director", "hr_director", "cmo"}
    for _, roleId in ipairs(requiredRoles) do
        if not gov.executives[roleId] then
            local roleDef
            for _, candidate in ipairs(GV.EXECUTIVE_ROLES) do
                if candidate.id == roleId then
                    roleDef = candidate
                    break
                end
            end
            if roleDef and GV.EnsureManagementCash(GD, roleDef.bonus, "管理团队招聘") then
                local ok = GV.HireExecutive(GD, roleId)
                if ok then hired = hired + 1 end
            else
                GD.AddEvent("CEO托管暂停招聘：现金需保留" .. GD.FormatMoney(GV.GetManagementCashReserve(GD)), "warning")
            end
        end
    end
    return hired
end

function GV._AutoHireProjectManagers(GD)
    local hired = 0
    for _, proj in ipairs(GD.projects or {}) do
        if (proj.status == "permits" or proj.status == "design" or proj.status == "construction")
            and (not proj.projectManager or not proj.projectManager.hired)
        then
            local available = GD.GetAvailablePMs and GD.GetAvailablePMs() or {}
            local candidate = available[1]
            if candidate and GV.EnsureManagementCash(GD, candidate.salary, "项目经理招聘") then
                local ok = GD.HireProjectManager(proj, candidate.name)
                if ok then
                    proj.projectManager.autoMode = true
                    hired = hired + 1
                end
            elseif candidate then
                GD.AddEvent("【" .. proj.name .. "】CEO托管暂停招聘项目经理：现金需保留" .. GD.FormatMoney(GV.GetManagementCashReserve(GD)), "warning")
            end
        end
    end
    return hired
end

GV.FULL_MANAGEMENT_PROJECT_LIMIT = 5

function GV.GetFullManagementActiveProjectCount(GD)
    if PC and PC.CountActiveProjects then
        return PC.CountActiveProjects(GD.projects or {})
    end
    return 0
end

function GV._AutoAcquireLand(GD)
    local company = GD.company
    if not company or not company.city then return 0 end
    local capacity = math.min(
        GV.FULL_MANAGEMENT_PROJECT_LIMIT,
        PC and PC.CalcCapacity and PC.CalcCapacity(company) or GV.FULL_MANAGEMENT_PROJECT_LIMIT
    )
    local activeProjects = GV.GetFullManagementActiveProjectCount(GD)
    if activeProjects >= capacity then return 0 end

    local candidates = {}
    for _, land in ipairs(GD.landMarket or {}) do
        if land.city == company.city and land.status == "available" then
            table.insert(candidates, land)
        end
    end
    table.sort(candidates, function(a, b)
        return (a.startPrice or math.huge) < (b.startPrice or math.huge)
    end)
    local land = candidates[1]
    if not land then return 0 end
    local price = land.startPrice or 0
    if price <= 0 or not GV.CanSpendManagementCash(GD, price) then
        return 0
    end
    company.cash = company.cash - price
    land.price = price
    land.status = "acquired"
    land.acquiredMonth = GD.totalMonths
    land.ownerType = "player_company"
    land.ownerCompanyId = GD.activeCompanyId
    for i, marketLand in ipairs(GD.landMarket) do
        if marketLand.id == land.id then
            table.remove(GD.landMarket, i)
            break
        end
    end
    table.insert(GD.landReserve, land)
    return 1
end

function GV._AutoStartDevelopment(GD)
    if GV.GetFullManagementActiveProjectCount(GD) >= GV.FULL_MANAGEMENT_PROJECT_LIMIT then
        return 0
    end
    local land = nil
    for _, candidate in ipairs(GD.landReserve or {}) do
        if candidate.city == (GD.company and GD.company.city)
            and not candidate.developmentStarted
            and (not candidate.dueDiligence or not candidate.dueDiligence.inProgress)
        then
            land = candidate
            break
        end
    end
    if not land then return 0 end
    local landUse = DT.USE_TYPE_TO_LAND_USE[land.useType] or "mixed"
    local types = DT.GetTypesForLandUse(landUse)
    local devType = types[1] and types[1].id or "rigid_residential"
    local ok = GD.StartDevelopment(land.id, devType, nil, "basic")
    return ok and 1 or 0
end

function GV._AutoApplyLoan(GD, requiredCash, reason)
    return GV.ManageCeoCashflow(GD, requiredCash, reason or "月度经营安全预留")
end

function GV.AutoConfigureMarketingStrategy(GD, project)
    if not GV.IsFullManagementEnabled(GD) or not project or not project.sales then return 0 end
    local sales = project.sales
    MK.EnsureMarketingFields(sales)
    local month = GD.totalMonths or 0
    if sales.lastCeoMarketingStrategyMonth == month then return 0 end

    local inventoryRate = math.max(0, (sales.totalUnits or 0) - (sales.soldUnits or 0))
        / math.max(1, sales.totalUnits or 0)
    local strategy = inventoryRate > 0.60 and "growth" or "steady"
    local budget = strategy == "growth" and 100 or 50
    local reserve = GV.GetManagementCashReserve(GD)
    local available = math.max(0, math.floor((GD.company.cash or 0) - reserve))
    budget = math.min(budget, available)

    MK.SetShowroom(project, strategy == "growth" and "luxury" or "basic")
    MK.SetMediaAd(project, strategy == "growth" and "mid" or "low")
    MK.SetSelfMedia(project, strategy == "growth" and "active" or "basic")
    MK.SetDepositThreshold(project, strategy == "growth" and "50w" or "100w")
    if not sales.marketing.opening.opened then
        MK.SetOpeningMethod(project, strategy == "growth" and "offline" or "online", GD)
    end
    MK.SetMarketingBudget(project, budget)
    MK.ToggleChannel(project, "agency", true, GD)
    MK.ToggleChannel(project, "distribution", strategy == "growth", GD)
    MK.ToggleChannel(project, "referral", inventoryRate > 0.35, GD)
    MK.SelectBank(project, strategy == "growth" and "bank_c" or "bank_a")
    if sales.canSell and inventoryRate > 0.50 then
        MK.SetPromotion(project, strategy == "growth" and "event" or "gift", 3, GD)
    end

    sales.ceoMarketingStrategy = strategy
    sales.lastCeoMarketingStrategyMonth = month
    print("[CEO-MARKETING] project=" .. tostring(project.name)
        .. " strategy=" .. strategy .. " budget=" .. tostring(budget))
    return 1
end

function GV._AutoStartSales(GD)
    local started = 0
    for _, proj in ipairs(GD.projects or {}) do
        if proj.sales and proj.sales.canPresale and not proj.sales.canSell
            and (proj.devCategory or "sale") == "sale"
        then
            GV.AutoConfigureMarketingStrategy(GD, proj)
            local ok = GD.StartPresale(proj)
            if ok then started = started + 1 end
        end
    end
    return started
end

function GV.RunFullManagement(GD)
    local gov = GD.company and GD.company.governance
    if not GV.IsFullManagementEnabled(GD) then return 0 end
    if gov.lastFullManagementMonth == GD.totalMonths then return 0 end
    local handled = 0
    -- CEO在玩家设定的资产负债率内自主融资并掌控现金流。
    handled = handled + GV._AutoApplyLoan(GD, GV.GetManagementCashReserve(GD) + 1, "月度经营安全预留")
    handled = handled + GV._HireManagementTeam(GD)
    handled = handled + GV._AutoHireProjectManagers(GD)

    if gov.ceoReportEnabled == false then
        -- 静默托管不生成审批报告，CEO按既有经营策略自主完成战略动作。
        gov.pendingCeoReport = nil
        handled = handled + GV._AutoAcquireLand(GD)
        handled = handled + GV._AutoStartDevelopment(GD)
        handled = handled + GV._AutoStartSales(GD)
    end

    handled = handled + GV.AutoManageCompany(GD, true)
    gov.lastFullManagementMonth = GD.totalMonths
    gov.fullManagementActionCount = (gov.fullManagementActionCount or 0) + handled
    if handled > 0 then
        GD.AddEvent("CEO全权托管已自动处理" .. handled .. "项经营事务", "info")
    end
    return handled
end

--- 自动经营调度：由 CEO/总经理/副总等触发，处理无需玩家细节确认的常规动作
---@param GD table
---@param silent boolean|nil
---@return number handled
function GV.AutoManageCompany(GD, silent)
    local handled = 0
    local fullManagement = GV.IsFullManagementEnabled(GD)

    local function ensureAutomaticFixedAsset(project)
        local holdUnits = project.unitPlan and ceoNumber(project.unitPlan.holdUnits, 0) or 0
        local hasHold = holdUnits > 0 or (project.devCategory or "sale") == "hold"
        if not fullManagement or not hasHold then return 0 end
        if project._fixedAssetConverted then
            local assetIdx = nil
            local fixedAsset = nil
            for idx, asset in ipairs(GD.fixedAssets or {}) do
                if tostring(asset.projectId or "") == tostring(project.id or "") then
                    assetIdx = idx
                    fixedAsset = asset
                    break
                end
            end
            if not fixedAsset then return 0 end
            local targetRent = fixedAsset.monthlyRent or 0
            local handledConverted = 0
            if not fixedAsset.isListedForRent and assetIdx then
                local listed, listMsg = GD.ListFixedAssetForRent(assetIdx, "enterprise")
                if listed then
                    local listing = GD.rentalListings and GD.rentalListings[#GD.rentalListings]
                    targetRent = listing and listing.targetRent or targetRent
                    handledConverted = 1
                    GD.AddEvent("【" .. project.name .. "】CEO已补充固定资产出租挂牌", "success")
                elseif listMsg ~= "该资产已在挂牌出租中" then
                    GD.AddEvent("【" .. project.name .. "】CEO补充出租挂牌失败：" .. tostring(listMsg), "warning")
                end
            else
                for _, listing in ipairs(GD.rentalListings or {}) do
                    if listing.assetIdx == assetIdx then
                        targetRent = listing.targetRent or targetRent
                        break
                    end
                end
            end
            if not project.ceoFixedAssetResult then
                local renovationCost = math.max(0, ceoNumber(fixedAsset.renovCost, 0))
                local preview = {
                    originalValue = math.max(0, ceoNumber(fixedAsset.originalValue, 0) - renovationCost),
                    renovCost = renovationCost,
                    latTax = math.max(0, ceoNumber(fixedAsset.latTax, 0)),
                    actualMarketValue = math.max(0, ceoNumber(fixedAsset.currentValue, 0)),
                }
                project._ceoFixedAssetMonth = project._ceoFixedAssetMonth or fixedAsset.convertMonth or GD.totalMonths
                ceoRecordFixedAssetResult(GD, project, fixedAsset, preview, targetRent)
            end
            return handledConverted
        end
        local ready = project.status == "completed" or project.status == "delivery"
            or project.status == "pending_operations" or project.status == "operations" or project.status == "mature"
        if not ready then return 0 end

        local renovLevel = 2
        if project.renovationPlan and project.renovationPlan.approved then
            renovLevel = math.max(2, math.floor(ceoNumber(project.renovationPlan.levelIndex, 2)))
        end
        local preview = GD.PreviewFixedAssetConvert(project, renovLevel)
        if not preview then return 0 end
        if not GV.EnsureManagementCash(GD, preview.totalCost, "自持物业装修、缴税及转固定资产") then
            GD.AddEvent("【" .. project.name .. "】CEO暂缓转固定资产：目标负债率内资金不足", "warning")
            return 0
        end
        if not GD.ConvertToFixedAsset(project, renovLevel) then return 0 end

        local assetIdx = nil
        local fixedAsset = nil
        for idx, asset in ipairs(GD.fixedAssets or {}) do
            if tostring(asset.projectId or "") == tostring(project.id or "") then
                assetIdx = idx
                fixedAsset = asset
                break
            end
        end
        local targetRent = fixedAsset and fixedAsset.monthlyRent or 0
        if assetIdx then
            local listed, listMsg = GD.ListFixedAssetForRent(assetIdx, "enterprise")
            if listed then
                local listing = GD.rentalListings and GD.rentalListings[#GD.rentalListings]
                targetRent = listing and listing.targetRent or targetRent
                GD.AddEvent("【" .. project.name .. "】CEO已完成装修、缴税、转固定资产并挂牌出租", "success")
            elseif listMsg ~= "该资产已在挂牌出租中" then
                GD.AddEvent("【" .. project.name .. "】转固成功但挂牌出租失败：" .. tostring(listMsg), "warning")
            end
        end
        project._ceoHoldDisposition = "fixed_asset_rental"
        project._ceoFixedAssetMonth = GD.totalMonths
        ceoRecordFixedAssetResult(GD, project, fixedAsset, preview, targetRent)
        return 1
    end

    local function isClearanceReady(project)
        if not project or not project.sales or project.salesCleared then
            return false
        end
        local allUnitsSold = project.sales.allUnitsSold == true
            or (ceoNumber(project.sales.totalUnits, 0) > 0
                and ceoNumber(project.sales.soldUnits, 0) >= ceoNumber(project.sales.totalUnits, 0))
        if not allUnitsSold then return false end
        if project.status ~= "completed" and project.status ~= "delivery" then
            return false
        end
        local holdUnits = project.unitPlan and ceoNumber(project.unitPlan.holdUnits, 0) or 0
        return holdUnits <= 0 or project._fixedAssetConverted == true
    end

    for _, proj in ipairs(GD.projects or {}) do
        if fullManagement and proj.sales and (proj.devCategory or "sale") == "sale"
            and (proj.sales.canPresale or proj.sales.canSell)
        then
            handled = handled + GV.AutoConfigureMarketingStrategy(GD, proj)
        end
        -- 旧存档或异常中断可能只保存销量，先复用统一售罄入口补齐标志和项目状态。
        if proj.sales
            and ceoNumber(proj.sales.totalUnits, 0) > 0
            and ceoNumber(proj.sales.soldUnits, 0) >= ceoNumber(proj.sales.totalUnits, 0)
            and not proj.sales.allUnitsSold
        then
            GD._CheckAllUnitsSold(proj)
        end

        -- 旧存档或异常中断可能只保存100%进度，却没有同步施工完成阶段。
        -- CEO托管应以玩家可见的100%进度为完成事实，补齐待结算状态后继续同轮结算。
        if fullManagement
            and (proj.status == "construction" or proj.status == "presale")
            and proj.construction
            and ceoNumber(proj.construction.progress, 0) >= 100
            and (proj.devCategory or "sale") ~= "agency"
        then
            proj.construction.progress = 100
            proj.construction.phase = "done"
            proj.status = "pending_settlement"
            proj._afterSettlementStatus = (proj.devCategory or "sale") == "hold"
                and "pending_operations" or "pending_completion"
            GD.AddEvent("【" .. proj.name .. "】CEO检测到建设进度100%，已进入自动结算", "info")
        end

        -- 生命周期动作优先于开盘动作。旧逻辑先命中“可预售但未开售”的空分支，
        -- 会遮蔽 pending_settlement，导致全权托管项目永久无法结算。
        if proj.status == "pending_settlement" then
            local canSettle = not fullManagement
            if fullManagement then
                local shortfall = math.max(0, -ceoNumber(proj.budget and proj.budget.remaining, 0))
                canSettle = GV.EnsureManagementCash(GD, shortfall, "项目建设结算")
            end
            if canSettle then
                local ok, settleError = GD.SettleProject(proj)
                if ok then
                    handled = handled + 1
                    GD.AddEvent("【" .. proj.name .. "】CEO已自动确认项目建设结算", "success")
                elseif fullManagement then
                    GD.AddEvent("【" .. proj.name .. "】CEO自动结算失败："
                        .. tostring(settleError or "未知原因"), "warning")
                end
            elseif fullManagement then
                GD.AddEvent("【" .. proj.name .. "】CEO暂缓结算：目标负债率内无法补足结算差额", "warning")
            end
        elseif proj.status == "pending_completion" then
            local ok, completionError = GD.ConfirmCompletion(proj)
            if ok then
                handled = handled + 1
                GD.AddEvent("【" .. proj.name .. "】CEO已自动确认项目竣工", "success")
            elseif fullManagement then
                GD.AddEvent("【" .. proj.name .. "】CEO自动确认竣工失败："
                    .. tostring(completionError or "未知原因"), "warning")
            end
        elseif proj.sales and proj.sales.canPresale and not proj.sales.canSell
            and (proj.devCategory or "sale") == "sale"
            and (proj.status == "construction" or proj.status == "presale")
        then
            -- 全权托管模式下，预售通过月报审批；非全权托管自动开售。
            if not fullManagement then
                local ok = GD.StartPresale(proj)
                if ok then handled = handled + 1 end
            end
        elseif proj.status == "pending_operations" and fullManagement then
            proj._ceoHoldDisposition = "fixed_asset_rental"
        end

        -- 同一次托管调度中，建设结算成功后立即确认竣工，不延后到下个月。
        if fullManagement and proj.status == "pending_completion" then
            local completed = GD.ConfirmCompletion(proj)
            if completed then handled = handled + 1 end
        end

        handled = handled + ensureAutomaticFixedAsset(proj)

        -- CEO全权托管：竣工闭环后，所有出售房源售罄且自持部分已转固时自动生成清单、缴税并清盘。
        if fullManagement and isClearanceReady(proj) then
            if not proj.clearanceSheet then
                GD.ManualClearance(proj)
            end
            if proj.clearanceSheet and proj.clearanceSheet.taxPaid and not proj.salesCleared then
                -- 恢复“已标记缴税、实际清盘未完成”的中间态，复用第二阶段统一清盘入口。
                local cleared = GD.ManualClearance(proj)
                if cleared and proj.salesCleared then
                    handled = handled + 1
                    ceoRecordClearanceResult(GD, proj)
                    GD.AddEvent("【" .. proj.name .. "】CEO已恢复并完成项目清盘", "success")
                end
            elseif proj.clearanceSheet and not proj.clearanceSheet.taxPaid then
                local tax = math.max(0, ceoNumber(proj.clearanceSheet.incomeTax, 0))
                if GV.EnsureManagementCash(GD, tax, "项目清盘缴税") then
                    local cleared = GD.ConfirmClearanceTax(proj)
                    if cleared and proj.salesCleared then
                        handled = handled + 1
                        ceoRecordClearanceResult(GD, proj)
                        GD.AddEvent("【" .. proj.name .. "】CEO已自动生成结算清单、缴税并清盘", "success")
                    end
                else
                    GD.AddEvent("【" .. proj.name .. "】CEO暂缓清盘：目标负债率内无法补足税款", "warning")
                end
            elseif proj.salesCleared then
                ceoRecordClearanceResult(GD, proj)
            end
        end

        -- CEO全权托管：已清盘项目自动开启基础物业服务并足额招聘
        if fullManagement and proj.salesCleared and proj.sales then
            local soldUnits = proj.sales.soldUnits or 0
            if soldUnits > 0 then
                if not proj.propertyMgmt then
                    proj.propertyMgmt = {
                        enabled = false,
                        feePerSqm = GD.GetDefaultPropertyFee(proj.devTypeId),
                        collectionRate = 0,
                        monthlyIncome = 0,
                        totalIncome = 0,
                        serviceLevelIdx = 1,
                        satisfactionRate = 80,
                        monthlyOperateCost = 0,
                        staffCount = 0,
                    }
                end
                local pm = proj.propertyMgmt
                if not pm.enabled then
                    pm.enabled = true
                    pm.collectionRate = 70
                    -- 足额招聘：每50户1人
                    local idealStaff = math.max(1, math.ceil(soldUnits / 50))
                    pm.staffCount = idealStaff
                    handled = handled + 1
                    GD.AddEvent("【" .. proj.name .. "】CEO已自动开启基础物业服务，配置" .. idealStaff .. "名人员", "info")
                end
            end
        end
    end

    local gov = GD.company and GD.company.governance

    -- CEO自主现金流管理：按目标资产负债率和实际缺口贷款；富余现金只通过统一入口自动还款。
    if fullManagement and gov and gov.ceoTargetDebtRatio then
        handled = handled + GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + 1, "月度经营安全预留")
        handled = handled + GV.ManageCeoDebtRepayment(GD)
    end

    if handled > 0 and gov then
        gov.autoManagedCount = (gov.autoManagedCount or 0) + handled
        gov.lastAutoManageMonth = GD.totalMonths
        if not silent then
            GD.AddEvent("自动经营已处理" .. handled .. "项公司事务", "success")
        end
    elseif not silent then
        GD.AddEvent("当前暂无可自动处理的公司事务", "info")
    end
    return handled
end

--- 执行高管职责操作
---@param GD table
---@param roleId string
---@return boolean ok
---@return string? message
function GV.ExecuteAction(GD, roleId)
    local gov = GD.company and GD.company.governance
    if not gov or not gov.executives or not gov.executives[roleId] then
        return false, "该职位无人在职"
    end

    local roleDef
    for _, r in ipairs(GV.EXECUTIVE_ROLES) do
        if r.id == roleId then roleDef = r; break end
    end
    if not roleDef or not roleDef.action then
        return false, "该职位无可用操作"
    end

    local action = roleDef.action

    if action == "automanage" then
        local handled = GV.AutoManageCompany(GD, false)
        if handled > 0 then
            return true, "已自动处理" .. handled .. "项经营事务"
        end
        return true, "当前暂无可自动处理的经营事务"

    elseif action == "autofinance" then
        local co = GD.company or {}
        local netAssets = math.max(0, math.floor((co.totalAssets or 0) - (co.totalDebt or 0)))
        gov.lastFinanceReviewMonth = GD.totalMonths
        gov.financeReviewCount = (gov.financeReviewCount or 0) + 1
        local effects = GV.GetExecutiveEffects(GD)
        local room = math.floor(netAssets * effects.expenseReduction * 0.02)
        if room > 0 then
            gov.financeControlSaving = (gov.financeControlSaving or 0) + room
        end
        return true, "公司财务巡检完成：公司净资产" .. GD.FormatMoney(netAssets)
            .. "，本次成本纪律额度" .. GD.FormatMoney(room)

    elseif action == "autotax" then
        local pending = {}
        for _, proj in ipairs(GD.projects or {}) do
            if proj.clearanceSheet and not proj.clearanceSheet.taxPaid and not proj.salesCleared then
                table.insert(pending, proj)
            end
        end
        if #pending == 0 then
            return true, "当前无待缴项目税款"
        end
        local paid = 0
        for _, proj in ipairs(pending) do
            local tax = math.max(0, tonumber(proj.clearanceSheet.incomeTax) or 0)
            local canPay = tax <= 0
                or not GV.IsFullManagementEnabled(GD)
                or GV.CanSpendManagementCash(GD, tax)
            if canPay then
                local ok = GD.ConfirmClearanceTax(proj)
                if ok then paid = paid + 1 end
            end
        end
        if paid == 0 then
            return false, "待缴税款存在，但当前现金安全预留不足"
        end
        return true, "CFO已完成" .. paid .. "个项目的税务清算"

    elseif action == "autorent" then
        local listed = 0
        for idx, asset in ipairs(GD.fixedAssets or {}) do
            if not asset.isListedForRent and asset.renovLevel ~= "none" then
                local ok = GD.ListFixedAssetForRent(idx, "enterprise")
                if ok then listed = listed + 1 end
            end
        end
        for _, proj in ipairs(GD.projects or {}) do
            local holdUnits = proj.unitPlan and proj.unitPlan.holdUnits or 0
            local ready = proj.status == "completed" or proj.status == "delivery"
                or proj.status == "operations" or proj.status == "mature"
            if ready and holdUnits > 0 and not proj._fixedAssetConverted and not proj.isListedForRent then
                local ok = GD.ListProjectForRent(proj, "enterprise")
                if ok then listed = listed + 1 end
            end
        end
        if listed == 0 then
            return true, "COO已完成运营巡检，当前无需新增出租挂牌"
        end
        return true, "COO已完成运营巡检，新增" .. listed .. "处出租挂牌"

    elseif action == "autoprice" then
        -- CMO: 一键调价 - 以批准开盘价为稳定基准，不被自动调价覆盖
        local adjusted = 0
        for _, proj in ipairs(GD.projects or {}) do
            if (proj.status == "presale" or proj.status == "delivery") and proj.sales and proj.sales.canSell then
                local marketFactor = GD.economy and GD.economy.marketHeat or 1.0
                local approvedPrice = tonumber(proj.sales.approvedOpeningPrice) or 0
                if approvedPrice <= 0 then
                    approvedPrice = tonumber(proj.sales.basePrice) or 0
                end
                local newPrice = math.floor(approvedPrice * marketFactor)
                if newPrice > 0 and newPrice ~= proj.sales.basePrice then
                    MK.RequestReprice(proj, newPrice, GD, newPrice >= proj.sales.basePrice and "up" or "down")
                    adjusted = adjusted + 1
                end
            end
        end
        if adjusted == 0 then
            return true, "CMO完成营销巡检，当前无需调价或暂无在售项目"
        end
        return true, "CMO已调整" .. adjusted .. "个项目定价"

    elseif action == "autotech" then
        -- CTO: 技术优化 - 每个项目只应用一次，避免每季度重复削减成本
        local optimized = 0
        for _, proj in ipairs(GD.projects or {}) do
            if proj.status == "construction" and not proj.techOptimized then
                local buildCost = proj.cost and proj.cost.buildCost or 0
                local saving = math.floor(buildCost * 0.05)
                if saving > 0 then
                    proj.cost.buildCost = math.max(0, buildCost - saving)
                    proj.cost.totalCost = math.max(0, (proj.cost.totalCost or 0) - saving)
                    proj.techOptimized = true
                    optimized = optimized + 1
                end
            end
        end
        if optimized == 0 then
            return true, "CTO完成技术巡检，当前无待优化在建项目"
        end
        return true, "CTO已优化" .. optimized .. "个项目，降低5%建设成本"

    elseif action == "autoaudit" then
        -- CLO: 合规检查 - 逐月降低项目风险，并同步公司合规风险口径
        local issues = 0
        local riskReduction = (GV.GetExecutiveEffects(GD).riskReduction or 0) * 3
        for _, proj in ipairs(GD.projects or {}) do
            local risk = tonumber(proj.complianceRisk) or 0
            if risk > 0 then
                proj.complianceRisk = math.max(0, risk - math.max(0.3, riskReduction))
                issues = issues + 1
            end
        end
        gov.lastAuditMonth = GD.totalMonths
        gov.complianceRiskReduction = riskReduction
        if issues == 0 then
            return true, "CLO合规检查完成，所有项目合规状况良好"
        end
        return true, "CLO已排查" .. issues .. "个项目的合规风险"

    elseif action == "autohire" then
        local hired = GV._AutoHireProjectManagers(GD)
        if hired > 0 then
            return true, "人事团队已自动配置" .. hired .. "个项目经理"
        end
        return true, "人事团队检查完毕，当前无需新增项目经理"
    end

    return false, "未知操作"
end

--- 获取高管总薪酬成本（月度）
function GV.GetExecutiveMonthlyCost(GD)
    local gov = GD.company and GD.company.governance
    if not gov or not gov.executives then return 0 end
    local total = 0
    for _, exec in pairs(gov.executives) do
        if exec.source ~= "group" then
            total = total + math.floor(((exec.salary or 0) / 12) * 100) / 100  -- 年薪/12
        end
    end
    return total
end

--- 处理高管月度薪资（已移至 UpdateFinance 统一处理扣款和费用计算）
function GV._processExecutiveSalaries(GD)
    -- 扣款和 totalPaid 更新已在 GD.UpdateFinance() 中统一处理
    -- 此函数保留以兼容 MonthlyUpdate 调用链
end

-- ============================================================================
-- 股权操作系统
-- ============================================================================

GV.BUYBACK_PREMIUM_RATE = 0.10

function GV.GetMarketValuation(GD)
    local company = GD.company or {}
    local gov = company.governance or {}
    return math.max(
        tonumber(gov.lastValuation) or 0,
        tonumber(company.totalAssets) or 0,
        tonumber(company.registeredCapital) or 0,
        tonumber(gov.totalShares) or 1
    )
end

function GV.GetBuybackPricePerShare(GD)
    local gov = GD.company and GD.company.governance
    if not gov or (gov.totalShares or 0) <= 0 then return 0 end
    return GV.GetMarketValuation(GD) / gov.totalShares * (1 + GV.BUYBACK_PREMIUM_RATE)
end

local function getNonFounderShares(gov)
    local total = 0
    for _, shareholder in ipairs(gov.shareholders or {}) do
        if shareholder.id ~= "founder" then
            total = total + math.max(0, math.floor(shareholder.shares or 0))
        end
    end
    return total
end

function GV.GetBuybackQuote(GD, pct)
    local gov = GD.company and GD.company.governance
    if not gov or (gov.totalShares or 0) <= 0 then return nil end
    pct = math.max(0.01, math.min(0.10, tonumber(pct) or 0))
    local requestedShares = math.max(1, math.floor(gov.totalShares * pct))
    local actualShares = math.min(requestedShares, getNonFounderShares(gov))
    local pricePerShare = GV.GetBuybackPricePerShare(GD)
    return {
        marketValuation = GV.GetMarketValuation(GD),
        premiumRate = GV.BUYBACK_PREMIUM_RATE,
        pricePerShare = pricePerShare,
        shares = actualShares,
        cost = actualShares > 0 and math.max(1, math.ceil(pricePerShare * actualShares)) or 0,
    }
end

local function executeBuybackShares(GD, requestedShares)
    local gov = GD.company and GD.company.governance
    if not gov then return false, "未初始化治理结构" end
    local nonFounderShares = getNonFounderShares(gov)
    if nonFounderShares <= 0 then return false, "没有可回购的股份（仅创始人持股）" end

    local actualBuyback = math.min(math.max(0, math.floor(requestedShares or 0)), nonFounderShares)
    if actualBuyback < 1 then return false, "回购数量太少" end
    local pricePerShare = GV.GetBuybackPricePerShare(GD)
    local totalCost = math.max(1, math.ceil(pricePerShare * actualBuyback))
    if (GD.company.cash or 0) < totalCost then
        return false, "资金不足（需" .. GD.FormatMoney(totalCost) .. "）"
    end

    local allocations = {}
    local remaining = actualBuyback
    local remainingBase = nonFounderShares
    local lastNonFounderIndex = nil
    for index, shareholder in ipairs(gov.shareholders) do
        if shareholder.id ~= "founder" then lastNonFounderIndex = index end
    end
    for index, shareholder in ipairs(gov.shareholders) do
        if shareholder.id ~= "founder" and remaining > 0 then
            local available = math.max(0, math.floor(shareholder.shares or 0))
            local take = index == lastNonFounderIndex and remaining
                or math.floor(remaining * available / math.max(1, remainingBase))
            take = math.min(available, remaining, math.max(0, take))
            allocations[index] = take
            remaining = remaining - take
            remainingBase = math.max(0, remainingBase - available)
        end
    end
    if remaining > 0 then return false, "回购股份分配失败" end

    for index = #gov.shareholders, 1, -1 do
        local shareholder = gov.shareholders[index]
        local take = allocations[index] or 0
        if take > 0 then
            shareholder.shares = math.max(0, (shareholder.shares or 0) - take)
            shareholder.buybackProceeds = (shareholder.buybackProceeds or 0) + pricePerShare * take
        end
        if shareholder.id ~= "founder" and shareholder.shares <= 0 then
            table.remove(gov.shareholders, index)
        end
    end

    GD.company.cash = GD.company.cash - totalCost
    gov.totalShares = gov.totalShares - actualBuyback
    gov.totalBuybackCost = (gov.totalBuybackCost or 0) + totalCost
    gov.lastBuybackPremiumRate = GV.BUYBACK_PREMIUM_RATE
    GV._refreshRatios(gov)

    return true, string.format("按市场市值溢价%.0f%%回购%d股，花费%s，创始人持股升至%.1f%%",
        GV.BUYBACK_PREMIUM_RATE * 100, actualBuyback, GD.FormatMoney(totalCost), gov.founderRatio * 100)
end

--- 股份回购（按比例）
---@param GD table
---@param pct number 回购占总股本的比例 (0.01~0.10)
---@return boolean ok
---@return string? message
function GV.ExecuteBuyback(GD, pct)
    local gov = GD.company and GD.company.governance
    if not gov then return false, "未初始化治理结构" end
    pct = math.max(0.01, math.min(0.10, tonumber(pct) or 0))
    return executeBuybackShares(GD, math.floor(gov.totalShares * pct))
end

--- 股份回购（自定义金额）
---@param GD table
---@param amount number 回购金额（万元）
---@return boolean ok
---@return string? message
function GV.BuybackByAmount(GD, amount)
    local gov = GD.company and GD.company.governance
    if not gov then return false, "未初始化治理结构" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "金额必须大于0" end
    if (GD.company.cash or 0) < amount then return false, "资金不足" end

    local pricePerShare = GV.GetBuybackPricePerShare(GD)
    local maxShares = math.min(getNonFounderShares(gov), math.floor(gov.totalShares * 0.10))
    local buybackShares = math.min(maxShares, math.floor(amount / math.max(pricePerShare, 0.000001)))
    if buybackShares < 1 then return false, "金额太少，无法按当前市值回购一股" end
    return executeBuybackShares(GD, buybackShares)
end

--- ESOP期权池设立（从创始人份额划出）
---@param GD table
---@param pct number 占总股本的比例 (0.01~0.10)
---@return boolean ok
---@return string? message
function GV.CreateESOP(GD, pct)
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    pct = math.max(0.01, math.min(0.10, pct))
    local esopShares = math.floor(gov.totalShares * pct)

    -- 从创始人份额划出
    local founderSh
    for _, sh in ipairs(gov.shareholders) do
        if sh.id == "founder" then founderSh = sh; break end
    end
    if not founderSh then return false, "未找到创始人" end
    if founderSh.shares < esopShares then
        return false, "创始人股份不足"
    end

    -- 30%持股底线检查
    local newFounderRatio = (founderSh.shares - esopShares) / gov.totalShares
    if newFounderRatio < GV.FOUNDER_MIN_RATIO then
        return false, string.format("设立ESOP后创始人持股将降至%.1f%%，低于%.0f%%底线",
            newFounderRatio * 100, GV.FOUNDER_MIN_RATIO * 100)
    end

    founderSh.shares = founderSh.shares - esopShares
    gov.esopPool = (gov.esopPool or 0) + esopShares
    GV._refreshRatios(gov)

    return true, string.format("ESOP期权池增加%d股（%.1f%%），创始人持股降至%.1f%%",
        esopShares, pct * 100, gov.founderRatio * 100)
end

--- 创始人向外部投资人出售指定公司个人持有股份，款项进入个人账户。
--- 持股仍大于0时保留分红权；低于50%时保留公司记录但不能切换经营。
---@param GD table
---@param companyId string|nil 目标公司ID，nil表示当前公司
---@param pct number 出售占创始人当前持股的比例(0~1)
---@return boolean ok
---@return string? message
function GV.SellFounderSharesForCompany(GD, companyId, pct)
    if not GD.player then return false, "未初始化个人数据" end
    if not GD.EnsureCompanyPortfolio or not GD.GetCompanyPortfolioSummary then
        return false, "公司组合数据未初始化"
    end

    GD.EnsureCompanyPortfolio(true)
    local currentId = GD.activeCompanyId
    local isCurrent = companyId == nil or tostring(companyId) == tostring(currentId)
    local targetCompany = nil
    local targetRecord = nil

    if isCurrent then
        targetCompany = GD.company
        targetRecord = GD.GetCompanyPortfolioSummary(false)
        for _, record in ipairs(targetRecord) do
            if tostring(record.id) == tostring(currentId) then
                targetRecord = record
                break
            end
        end
        if type(targetRecord) ~= "table" or not targetRecord.state then
            targetRecord = nil
        end
    else
        local companies = GD.GetCompanyPortfolioSummary(false)
        for _, record in ipairs(companies) do
            if tostring(record.id) == tostring(companyId) then
                targetRecord = record
                break
            end
        end
        if not targetRecord then return false, "目标公司不存在或已不再持股" end
        if targetRecord.status ~= "operating" then return false, "该公司已退出，不能出售股份" end
        targetCompany = targetRecord.state and targetRecord.state.company
    end

    local gov = targetCompany and targetCompany.governance
    if not gov then return false, "目标公司未初始化治理结构" end
    if not targetCompany.name or targetCompany.name == "" then return false, "目标公司数据缺失" end
    pct = math.max(0.01, math.min(1.0, tonumber(pct) or 0))

    local founderSh
    for _, sh in ipairs(gov.shareholders or {}) do
        if sh.id == "founder" then founderSh = sh; break end
    end
    if not founderSh or (founderSh.shares or 0) <= 0 then return false, "个人已不持有公司股份" end

    local sellShares = math.floor(founderSh.shares * pct)
    if pct >= 0.999 then sellShares = founderSh.shares end
    if sellShares <= 0 then return false, "出售股份过少" end

    local valuation = math.max(
        gov.lastValuation or 0,
        targetCompany.totalAssets or 0,
        targetCompany.registeredCapital or 0,
        gov.totalShares or 1
    )
    local pricePerShare = valuation / math.max(1, gov.totalShares or 1)
    local amount = math.floor(sellShares * pricePerShare * 0.90)
    if amount <= 0 then amount = sellShares end

    local groupSystem = GD.GroupSystem
    local salePaidToGroup = groupSystem
        and groupSystem.IsMemberCompany(GD, companyId or currentId)
        and groupSystem.CreditCompanyEquitySale(GD, companyId or currentId, amount)
    if not salePaidToGroup then
        GD.player.cash = (GD.player.cash or 0) + amount
        GD.player.totalIncome = (GD.player.totalIncome or 0) + amount
        GD.player.yearlyIncome = (GD.player.yearlyIncome or 0) + amount
        GD.player.equitySaleIncome = (GD.player.equitySaleIncome or 0) + amount
    end

    founderSh.shares = founderSh.shares - sellShares
    table.insert(gov.shareholders, {
        id = "outside_buyer_" .. tostring((GD.totalMonths or 0) + #gov.shareholders + 1),
        name = pct >= 0.999 and "新控股股东" or "外部投资人",
        shares = sellShares,
        ratio = 0,
        type = "institutional",
        totalDividends = 0,
        investAmount = amount,
    })

    if founderSh.shares <= 0 then
        for i = #gov.shareholders, 1, -1 do
            if gov.shareholders[i].id == "founder" then
                table.remove(gov.shareholders, i)
                break
            end
        end
    end
    GV._refreshRatios(gov)

    local remainingRatio = gov.founderRatio or 0
    if groupSystem and salePaidToGroup then
        groupSystem.OnCompanyOwnershipChanged(GD, companyId or currentId, remainingRatio)
    end
    if targetRecord then
        targetRecord.founderRatio = remainingRatio
        targetRecord.state = targetRecord.state or {}
        targetRecord.state.company = targetCompany
        if remainingRatio <= 0 then
            targetRecord.status = "sold"
            targetRecord.exitReason = "个人已出售全部股份"
            targetRecord.exitYear = GD.year
            targetRecord.exitMonth = GD.month
        end
    end

    if isCurrent then
        if remainingRatio <= 0 then
            local exitMsg = "已出售" .. (targetCompany.name or "该公司") .. "全部股份，个人收款" .. GD.FormatMoney(amount)
            if GD.MarkActiveCompanyExited then
                local _, switchMsg = GD.MarkActiveCompanyExited("sold", exitMsg)
                return true, exitMsg .. "；" .. (switchMsg or "可继续创办新公司")
            end
        elseif remainingRatio < 0.50 then
            local controlMsg = "已出售" .. (targetCompany.name or "该公司") .. "部分股份，个人收款" .. GD.FormatMoney(amount)
            if GD.ReleaseActiveCompanyControl then
                GD.ReleaseActiveCompanyControl(controlMsg)
            end
            return true, controlMsg .. "；剩余持股" .. string.format("%.1f%%", remainingRatio * 100) .. "，已失去控制权，仅保留分红权"
        else
            GD.CaptureActiveCompanyState()
        end
    end

    local controlNote = remainingRatio < 0.50 and "，已失去公司控制权，仅保留分红权" or ""
    return true, string.format(
        "出售%s%d股，个人收款%s，剩余持股%.1f%%%s",
        targetCompany.name or "公司",
        sellShares,
        GD.FormatMoney(amount),
        remainingRatio * 100,
        controlNote
    )
end

--- 创始人向当前公司出售股份的兼容入口
---@param GD table
---@param pct number 出售占创始人当前持股的比例(0~1)
---@return boolean ok
---@return string? message
function GV.SellFounderShares(GD, pct)
    return GV.SellFounderSharesForCompany(GD, GD.activeCompanyId, pct)
end

--- 股份转让（股东间转移）
---@param GD table
---@param fromIdx number 转出方在shareholders数组中的索引
---@param toIdx number 转入方索引（0=创始人）
---@param shareCount number 转让股数
---@return boolean ok
---@return string? message
function GV.TransferShares(GD, fromIdx, toIdx, shareCount)
    local gov = GD.company.governance
    if not gov then return false, "未初始化治理结构" end

    local fromSh = gov.shareholders[fromIdx]
    if not fromSh then return false, "转出方不存在" end
    if fromSh.shares < shareCount then
        return false, "转出方股份不足"
    end

    -- toIdx=0 表示转给创始人
    local toSh
    if toIdx == 0 then
        for _, sh in ipairs(gov.shareholders) do
            if sh.id == "founder" then toSh = sh; break end
        end
    else
        toSh = gov.shareholders[toIdx]
    end
    if not toSh then return false, "转入方不存在" end
    if fromSh.id == toSh.id then return false, "不能转让给自己" end

    -- 30%持股底线检查（创始人转出时）
    if fromSh.id == "founder" then
        local newFounderRatio = (fromSh.shares - shareCount) / gov.totalShares
        if newFounderRatio < GV.FOUNDER_MIN_RATIO then
            return false, string.format("转让后创始人持股将降至%.1f%%，低于%.0f%%底线",
                newFounderRatio * 100, GV.FOUNDER_MIN_RATIO * 100)
        end
    end

    -- 转让费用 = 股份数 * 每股价格 * 0.5（折价转让）
    local pricePerShare = (gov.lastValuation or gov.totalShares) / gov.totalShares
    local transferCost = math.floor(shareCount * pricePerShare * 0.5)
    if toSh.id == "founder" and GD.company.cash < transferCost then
        return false, "资金不足（需" .. GD.FormatMoney(transferCost) .. "）"
    end

    -- 扣费（如果是创始人收购）
    if toSh.id == "founder" then
        GD.company.cash = GD.company.cash - transferCost
    end

    fromSh.shares = fromSh.shares - shareCount
    toSh.shares = toSh.shares + shareCount

    -- 清除空股东
    for i = #gov.shareholders, 1, -1 do
        if gov.shareholders[i].shares <= 0 then
            table.remove(gov.shareholders, i)
        end
    end

    GV._refreshRatios(gov)

    return true, string.format("转让%d股从%s到%s，创始人持股%.1f%%",
        shareCount, fromSh.name, toSh.name, gov.founderRatio * 100)
end

return GV
