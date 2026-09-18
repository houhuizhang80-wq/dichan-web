---@diagnostic disable: return-type-mismatch
-- ============================================================================
-- Operations.lua - 持有型项目运营模块
-- 购物中心/写字楼/长租公寓/酒店 的运营管理
-- 支持：手动选择运营模式、运营中变更模式（需装修改造）、多状态流转
-- ============================================================================

local DT = require("DevTypes")

local OP = {}

-- ============================================================================
-- 状态流转说明
-- waiting_for_mode → (选择模式) → preparing → ramp_up → mature → declining
--                                     ↑
-- renovating ←←←←←← (变更模式) ←←←←←← mature/ramp_up
-- renovating → (改造完成) → ramp_up
-- ============================================================================

-- ============================================================================
-- 初始化运营数据
-- ============================================================================

--- 创建持有型项目运营数据（初始状态为 waiting_for_mode，等待手动选择模式）
---@param devTypeId string 开发类型ID
---@param buildArea number 建筑面积(㎡)
---@return table operations 运营数据
function OP.InitOperationsData(devTypeId, buildArea)
    local typeDef = DT.GetType(devTypeId)
    if not typeDef or typeDef.category ~= DT.CATEGORY_HOLD then
        return nil
    end
    local opsConfig = typeDef.operations or {}

    -- 酒店: 根据面积计算房间数
    local roomCount = 0
    if devTypeId == "hotel" then
        local avgRoomSize = opsConfig.avgRoomSize or 35
        roomCount = math.floor(buildArea * 0.6 / avgRoomSize) -- 60%可用面积
    end

    local data = {
        devTypeId = devTypeId,
        status = "waiting_for_mode",   -- 等待手动选择运营模式
        -- 运营模式
        operationMode = nil,
        operationModeName = nil,
        revenueMultiplier = 1.0,
        opexMultiplier = 1.0,
        -- 装修改造
        renovating = false,
        renovationMonthsTotal = 0,
        renovationMonthsElapsed = 0,
        renovationCost = 0,
        renovationHistory = {},   -- 历次改造记录
        -- 出租率/入住率
        occupancy = 0,
        targetOccupancy = opsConfig.targetOccupancy or 0.90,
        rampUpMonths = opsConfig.rampUpMonths or 12,
        rampUpElapsed = 0,
        -- 租金收入
        baseRentPerSqm = opsConfig.baseRentPerSqm or 60,
        currentRentPerSqm = 0,
        rentableArea = math.floor(buildArea * 0.65), -- 可租面积约65%
        -- 酒店特有
        roomCount = roomCount,
        baseRevPAR = opsConfig.baseRevPAR or 0,
        seasonalFactors = opsConfig.seasonalFactors or nil,
        -- 运营费用
        opexRatio = opsConfig.opexRatio or 0.30,
        commissionRate = opsConfig.commissionRate or 0,
        -- NOI(净营业收入)
        monthlyRevenue = 0,
        monthlyOpex = 0,
        monthlyNOI = 0,
        cumulativeNOI = 0,
        -- 估值
        capRate = opsConfig.capRate or 0.05,
        valuation = 0,
        -- 租户管理
        tenants = {},
        tenantCount = 0,
        maxTenants = 0,
        tenantSatisfaction = 70,    -- 0-100
        -- 历史记录(最近12个月)
        noiHistory = {},
        occupancyHistory = {},
        -- 统计
        totalRevenue = 0,
        totalOpex = 0,
        operatingMonths = 0,
        -- 模式变更次数
        modeChangeCount = 0,
    }

    -- 按类型设定最大租户数
    if devTypeId == "shopping_mall" then
        data.maxTenants = math.max(20, math.floor(buildArea / 300))
    elseif devTypeId == "office_building" then
        data.maxTenants = math.max(10, math.floor(buildArea / 500))
    elseif devTypeId == "long_rent_apartment" then
        data.maxTenants = math.max(50, math.floor(buildArea * 0.6 / 30)) -- 30㎡/间
    elseif devTypeId == "hotel" then
        data.maxTenants = 0 -- 酒店无固定租户概念
    end

    return data
end

-- ============================================================================
-- 运营模式选择与变更
-- ============================================================================

--- 选择运营模式（首次选择，从 waiting_for_mode 进入 preparing）
---@param project table 项目数据
---@param modeId string 运营模式ID
---@param GD table 全局游戏数据
---@return boolean, string|nil
function OP.SelectMode(project, modeId, GD)
    local ops = project.operations
    if not ops then return false, "运营数据不存在" end
    if ops.status ~= "waiting_for_mode" then
        return false, "当前状态不允许选择运营模式"
    end

    local mode = DT.GetOperationMode(ops.devTypeId, modeId)
    if not mode then return false, "无效的运营模式" end

    -- 应用运营模式参数
    ops.operationMode = modeId
    ops.operationModeName = mode.name
    ops.revenueMultiplier = mode.revenueMultiplier or 1.0
    ops.opexMultiplier = mode.opexMultiplier or 1.0

    -- 培育期根据模式调整
    local typeDef = DT.GetType(ops.devTypeId)
    local baseRampUp = typeDef and typeDef.operations and typeDef.operations.rampUpMonths or 12
    ops.rampUpMonths = math.floor(baseRampUp * (mode.rampUpMultiplier or 1.0))

    -- 检查是否需要前期装修
    local renovCost = mode.renovationCost or 0
    local renovMonths = mode.renovationMonths or 0
    if renovCost > 0 and renovMonths > 0 then
        -- 需要装修才能开始运营
        local actualCost = math.floor(project.cost.buildCost * renovCost)
        if GD and GD.company.cash < actualCost then
            -- 资金不足也允许选择，但提示风险
            -- （实际游戏中首次选择应免装修费，只有变更才扣费）
        end
        -- 首次选择免装修费（装修包含在建设成本中），直接进入招商
        ops.status = "preparing"
    else
        ops.status = "preparing"
    end

    return true
end

--- 变更运营模式（从运营中切换，需装修改造）
---@param project table 项目数据
---@param newModeId string 新运营模式ID
---@param GD table 全局游戏数据
---@return boolean, string|nil
function OP.ChangeMode(project, newModeId, GD)
    local ops = project.operations
    if not ops then return false, "运营数据不存在" end

    -- 装修中不允许再变更
    if ops.status == "renovating" then
        return false, "正在装修改造中，无法再次变更"
    end
    if ops.status == "waiting_for_mode" then
        return false, "请先选择运营模式"
    end
    if ops.operationMode == newModeId then
        return false, "已是当前运营模式"
    end

    local newMode = DT.GetOperationMode(ops.devTypeId, newModeId)
    if not newMode then return false, "无效的运营模式" end

    -- 计算装修改造成本
    local renovCostPct = newMode.renovationCost or 0.05
    local renovCost = math.floor(project.cost.buildCost * renovCostPct)
    local renovMonths = newMode.renovationMonths or 3

    if GD.company.cash < renovCost then
        return false, "资金不足，改造需 " .. GD.FormatMoney(renovCost)
    end

    -- 扣除改造费用
    GD.company.cash = GD.company.cash - renovCost
    project.cost.totalCost = project.cost.totalCost + renovCost

    -- 记录改造历史
    local oldModeName = ops.operationModeName or "未知"
    table.insert(ops.renovationHistory, {
        fromMode = ops.operationMode,
        fromModeName = oldModeName,
        toMode = newModeId,
        toModeName = newMode.name,
        cost = renovCost,
        months = renovMonths,
        startMonth = ops.operatingMonths,
    })

    -- 进入装修改造状态
    ops.renovating = true
    ops.renovationMonthsTotal = renovMonths
    ops.renovationMonthsElapsed = 0
    ops.renovationCost = renovCost
    ops._pendingMode = newModeId
    ops._pendingModeName = newMode.name
    ops._pendingRevMult = newMode.revenueMultiplier or 1.0
    ops._pendingOpexMult = newMode.opexMultiplier or 1.0
    ops._pendingRampUpMult = newMode.rampUpMultiplier or 1.0

    -- 设置状态
    ops.status = "renovating"
    -- 装修期间入住率逐步下降
    ops.occupancy = math.max(0.10, ops.occupancy * 0.5)
    ops.modeChangeCount = (ops.modeChangeCount or 0) + 1

    GD.AddEvent("【" .. project.name .. "】开始装修改造: " .. oldModeName .. " → " ..
        newMode.icon .. newMode.name .. "，费用" .. GD.FormatMoney(renovCost) ..
        "，工期" .. renovMonths .. "个月", "warning")
    return true
end

--- 获取装修改造进度 (0-100)
---@param ops table
---@return number
function OP.GetRenovationProgress(ops)
    if not ops or not ops.renovating then return 0 end
    if ops.renovationMonthsTotal <= 0 then return 100 end
    return math.min(100, math.floor(ops.renovationMonthsElapsed / ops.renovationMonthsTotal * 100))
end

--- 获取装修改造剩余月数
---@param ops table
---@return number
function OP.GetRenovationRemaining(ops)
    if not ops or not ops.renovating then return 0 end
    return math.max(0, ops.renovationMonthsTotal - ops.renovationMonthsElapsed)
end

-- ============================================================================
-- 租户管理
-- ============================================================================

-- 租户模板
local TENANT_TEMPLATES = {
    shopping_mall = {
        {category = "anchor",        name = "主力店",    rentMult = 0.5,  areaPct = 0.15, stability = 0.95},
        {category = "fashion",       name = "时尚品牌",  rentMult = 1.2,  areaPct = 0.08, stability = 0.80},
        {category = "food",          name = "餐饮店",    rentMult = 0.9,  areaPct = 0.05, stability = 0.75},
        {category = "entertainment", name = "娱乐业态",  rentMult = 0.8,  areaPct = 0.10, stability = 0.85},
        {category = "service",       name = "生活服务",  rentMult = 0.7,  areaPct = 0.04, stability = 0.70},
    },
    office_building = {
        {category = "large_corp",    name = "大企业",    rentMult = 0.9,  areaPct = 0.25, stability = 0.95},
        {category = "sme",           name = "中小企业",  rentMult = 1.0,  areaPct = 0.10, stability = 0.80},
        {category = "startup",       name = "创业公司",  rentMult = 1.1,  areaPct = 0.05, stability = 0.60},
        {category = "coworking",     name = "共享办公",  rentMult = 1.3,  areaPct = 0.15, stability = 0.70},
    },
    long_rent_apartment = {
        {category = "young_worker",  name = "青年白领",  rentMult = 1.0,  areaPct = 0.01, stability = 0.70},
        {category = "student",       name = "学生",      rentMult = 0.8,  areaPct = 0.01, stability = 0.85},
        {category = "family",        name = "小家庭",    rentMult = 1.2,  areaPct = 0.02, stability = 0.90},
    },
}

--- 生成一个随机租户
---@param devTypeId string
---@param ops table 运营数据
---@return table|nil tenant
local function generateTenant(devTypeId, ops)
    local templates = TENANT_TEMPLATES[devTypeId]
    if not templates or #templates == 0 then return nil end

    local tmpl = templates[math.random(1, #templates)]
    local area = math.floor(ops.rentableArea * tmpl.areaPct * (0.8 + math.random() * 0.4))
    area = math.max(20, area)

    return {
        id = "T" .. math.random(10000, 99999),
        category = tmpl.category,
        name = tmpl.name .. "#" .. math.random(100, 999),
        area = area,
        rentMult = tmpl.rentMult,
        stability = tmpl.stability,
        contractMonths = math.random(12, 36),
        remainMonths = math.random(12, 36),
        satisfaction = 65 + math.random(0, 25),
    }
end

-- ============================================================================
-- 月度运营更新
-- ============================================================================

--- 月度运营更新(在MonthlyTick中调用)
---@param project table 项目数据
---@param GD table 全局游戏数据
function OP.MonthlyUpdate(project, GD)
    local ops = project.operations
    if not ops then return end

    -- 确保字段完整
    OP.EnsureOperationsFields(ops)

    -- 等待选择模式时不做任何运营处理
    if ops.status == "waiting_for_mode" then
        return
    end

    ops.operatingMonths = ops.operatingMonths + 1

    -- 状态机
    if ops.status == "renovating" then
        OP.HandleRenovating(project, ops, GD)
    elseif ops.status == "preparing" then
        OP.HandlePreparing(project, ops, GD)
    elseif ops.status == "ramp_up" then
        OP.HandleRampUp(project, ops, GD)
    elseif ops.status == "mature" then
        OP.HandleMature(project, ops, GD)
    elseif ops.status == "declining" then
        OP.HandleDeclining(project, ops, GD)
    end

    -- 计算月度财务（装修中仍有少量维护费用）
    OP.CalculateMonthlyFinancials(project, ops, GD)

    -- 更新估值
    OP.UpdateValuation(ops)

    -- 记录历史
    table.insert(ops.noiHistory, ops.monthlyNOI)
    if #ops.noiHistory > 12 then table.remove(ops.noiHistory, 1) end
    table.insert(ops.occupancyHistory, ops.occupancy)
    if #ops.occupancyHistory > 12 then table.remove(ops.occupancyHistory, 1) end
end

--- 装修改造期处理
function OP.HandleRenovating(project, ops, GD)
    ops.renovationMonthsElapsed = ops.renovationMonthsElapsed + 1

    -- 装修期间入住率/出租率降至很低
    if ops.devTypeId ~= "hotel" then
        -- 清退部分租户
        for i = #ops.tenants, 1, -1 do
            if math.random() < 0.3 then
                table.remove(ops.tenants, i)
                ops.tenantCount = math.max(0, ops.tenantCount - 1)
            end
        end
        local occupiedArea = 0
        for _, t in ipairs(ops.tenants) do occupiedArea = occupiedArea + t.area end
        ops.occupancy = ops.rentableArea > 0 and (occupiedArea / ops.rentableArea) or 0
    else
        ops.occupancy = math.max(0.05, ops.occupancy * 0.8)
    end

    -- 装修完成
    if ops.renovationMonthsElapsed >= ops.renovationMonthsTotal then
        -- 应用新模式
        ops.operationMode = ops._pendingMode
        ops.operationModeName = ops._pendingModeName
        ops.revenueMultiplier = ops._pendingRevMult or 1.0
        ops.opexMultiplier = ops._pendingOpexMult or 1.0

        -- 重新计算培育期
        local typeDef = DT.GetType(ops.devTypeId)
        local baseRampUp = typeDef and typeDef.operations and typeDef.operations.rampUpMonths or 12
        ops.rampUpMonths = math.floor(baseRampUp * (ops._pendingRampUpMult or 1.0))
        ops.rampUpElapsed = 0

        -- 清除临时数据
        ops._pendingMode = nil
        ops._pendingModeName = nil
        ops._pendingRevMult = nil
        ops._pendingOpexMult = nil
        ops._pendingRampUpMult = nil

        -- 进入新培育期
        ops.renovating = false
        ops.status = "ramp_up"
        ops.occupancy = math.max(0.10, ops.occupancy)

        GD.AddEvent("【" .. project.name .. "】装修改造完成！新模式: " ..
            ops.operationModeName .. "，进入培育期", "success")
    end
end

--- 招商筹备期处理
function OP.HandlePreparing(project, ops, GD)
    -- 每月自动招入2-4个租户(非酒店)
    if ops.devTypeId ~= "hotel" and ops.tenantCount < ops.maxTenants then
        local toAdd = math.min(math.random(2, 4), ops.maxTenants - ops.tenantCount)
        for _ = 1, toAdd do
            local tenant = generateTenant(ops.devTypeId, ops)
            if tenant then
                table.insert(ops.tenants, tenant)
                ops.tenantCount = ops.tenantCount + 1
            end
        end
    end

    -- 出租率达到30%或筹备满3个月 → 进入培育期
    local occupiedArea = 0
    for _, t in ipairs(ops.tenants) do occupiedArea = occupiedArea + t.area end
    ops.occupancy = ops.rentableArea > 0 and (occupiedArea / ops.rentableArea) or 0

    if ops.occupancy >= 0.30 or ops.operatingMonths >= 3 then
        ops.status = "ramp_up"
        ops.rampUpElapsed = 0
        GD.AddEvent("【" .. project.name .. "】正式开业运营！", "success")
    end
end

--- 培育期处理
function OP.HandleRampUp(project, ops, GD)
    ops.rampUpElapsed = ops.rampUpElapsed + 1

    -- 持续招租(非酒店)
    if ops.devTypeId ~= "hotel" then
        if ops.tenantCount < ops.maxTenants and math.random() < 0.6 then
            local tenant = generateTenant(ops.devTypeId, ops)
            if tenant then
                table.insert(ops.tenants, tenant)
                ops.tenantCount = ops.tenantCount + 1
            end
        end
        -- 偶尔退租
        OP.HandleTenantTurnover(ops)
    end

    -- 酒店: 入住率逐步爬升
    if ops.devTypeId == "hotel" then
        local targetOcc = ops.targetOccupancy
        local progress = math.min(1.0, ops.rampUpElapsed / ops.rampUpMonths)
        ops.occupancy = math.min(targetOcc, progress * targetOcc * (0.8 + math.random() * 0.2))
    else
        local occupiedArea = 0
        for _, t in ipairs(ops.tenants) do occupiedArea = occupiedArea + t.area end
        ops.occupancy = ops.rentableArea > 0 and (occupiedArea / ops.rentableArea) or 0
    end

    -- 达到目标出租率或培育期结束 → 成熟期
    if ops.rampUpElapsed >= ops.rampUpMonths or ops.occupancy >= ops.targetOccupancy * 0.95 then
        ops.status = "mature"
        GD.AddEvent("【" .. project.name .. "】运营进入成熟期！出租率" ..
            math.floor(ops.occupancy * 100) .. "%", "success")
    end
end

--- 成熟运营期处理
function OP.HandleMature(project, ops, GD)
    if ops.devTypeId ~= "hotel" then
        OP.HandleTenantTurnover(ops)
        if ops.tenantCount < ops.maxTenants and math.random() < 0.3 then
            local tenant = generateTenant(ops.devTypeId, ops)
            if tenant then
                table.insert(ops.tenants, tenant)
                ops.tenantCount = ops.tenantCount + 1
            end
        end
        local occupiedArea = 0
        for _, t in ipairs(ops.tenants) do occupiedArea = occupiedArea + t.area end
        ops.occupancy = ops.rentableArea > 0 and (occupiedArea / ops.rentableArea) or 0
    else
        local monthIdx = ((GD.month - 1) % 12) + 1
        local seasonal = (ops.seasonalFactors and ops.seasonalFactors[monthIdx]) or 1.0
        local base = ops.targetOccupancy * seasonal
        ops.occupancy = math.max(0.20, math.min(0.98, base * (0.9 + math.random() * 0.2)))
    end

    ops.tenantSatisfaction = math.max(30, math.min(100,
        ops.tenantSatisfaction + math.random(-3, 3)))

    if ops.operatingMonths > 60 and ops.tenantSatisfaction < 50 then
        ops.status = "declining"
        GD.AddEvent("【" .. project.name .. "】运营老化，需翻新改造", "warning")
    end
end

--- 衰退期处理
function OP.HandleDeclining(project, ops, GD)
    ops.occupancy = math.max(0.30, ops.occupancy - math.random(1, 3) / 100)
    OP.HandleTenantTurnover(ops, 0.15)
    ops.tenantSatisfaction = math.max(20, ops.tenantSatisfaction - math.random(1, 3))

    local occupiedArea = 0
    for _, t in ipairs(ops.tenants) do occupiedArea = occupiedArea + t.area end
    if ops.rentableArea > 0 then
        ops.occupancy = occupiedArea / ops.rentableArea
    end
end

--- 租户周转(退租)
---@param ops table
---@param extraChurnRate number|nil 额外退租概率
function OP.HandleTenantTurnover(ops, extraChurnRate)
    local churnBase = extraChurnRate or 0.05
    for i = #ops.tenants, 1, -1 do
        local t = ops.tenants[i]
        t.remainMonths = t.remainMonths - 1
        if t.remainMonths <= 0 or math.random() < (1 - t.stability) * churnBase then
            table.remove(ops.tenants, i)
            ops.tenantCount = ops.tenantCount - 1
        end
    end
end

-- ============================================================================
-- 财务计算
-- ============================================================================

--- 计算月度财务数据
function OP.CalculateMonthlyFinancials(project, ops, GD)
    local revenue = 0

    -- 装修期间无收入，但有维护费
    if ops.status == "renovating" then
        ops.monthlyRevenue = 0
        -- 装修期间仅有少量维护成本
        local maintenanceCost = ops.rentableArea * 5 / 10000  -- 5元/㎡月维护
        ops.monthlyOpex = math.floor(maintenanceCost * 100) / 100
        ops.monthlyNOI = -ops.monthlyOpex
        ops.cumulativeNOI = ops.cumulativeNOI + ops.monthlyNOI
        ops.totalOpex = ops.totalOpex + ops.monthlyOpex
        -- 从公司扣除
        GD.company.cash = GD.company.cash + ops.monthlyNOI
        return
    end

    if ops.devTypeId == "hotel" then
        local monthIdx = ((GD.month - 1) % 12) + 1
        local seasonal = (ops.seasonalFactors and ops.seasonalFactors[monthIdx]) or 1.0
        local revpar = ops.baseRevPAR * seasonal * ops.occupancy
        revenue = revpar * ops.roomCount * 30 / 10000  -- 万元
    else
        local rentPerSqm = ops.baseRentPerSqm
        local satMult = 0.8 + (ops.tenantSatisfaction / 100) * 0.4
        ops.currentRentPerSqm = math.floor(rentPerSqm * satMult * 100) / 100
        revenue = ops.currentRentPerSqm * ops.rentableArea * ops.occupancy / 10000

        if ops.commissionRate > 0 then
            local tenantTurnover = revenue * 5
            revenue = revenue + tenantTurnover * ops.commissionRate
        end
    end

    -- 应用运营模式收入乘数
    local revMult = ops.revenueMultiplier or 1.0
    revenue = revenue * revMult

    -- 运营费用
    local opexMult = ops.opexMultiplier or 1.0
    local opex = revenue * ops.opexRatio * opexMult

    -- NOI
    ops.monthlyRevenue = math.floor(revenue * 100) / 100
    ops.monthlyOpex = math.floor(opex * 100) / 100
    ops.monthlyNOI = math.floor((revenue - opex) * 100) / 100

    ops.cumulativeNOI = ops.cumulativeNOI + ops.monthlyNOI
    ops.totalRevenue = ops.totalRevenue + ops.monthlyRevenue
    ops.totalOpex = ops.totalOpex + ops.monthlyOpex

    -- 现金流入公司
    GD.company.cash = GD.company.cash + ops.monthlyNOI
    if ops.monthlyRevenue > 0 then
        GD.company.monthlyRevenue = GD.company.monthlyRevenue + ops.monthlyRevenue
    end

    -- 区域公司PnL
    if project.regionalCompanyIdx then
        local rc = GD.company.regionalCompanies[project.regionalCompanyIdx]
        if rc then rc.pnl = rc.pnl + ops.monthlyNOI end
    end
end

--- 更新资产估值
function OP.UpdateValuation(ops)
    if ops.monthlyNOI > 0 then
        local annualNOI = ops.monthlyNOI * 12
        ops.valuation = math.floor(annualNOI / ops.capRate)
    else
        ops.valuation = 0
    end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取资产估值(万元)
function OP.GetValuation(project)
    local ops = project.operations
    if not ops then return 0 end
    return ops.valuation
end

--- 获取出租率趋势
function OP.GetOccupancyTrend(project, months)
    local ops = project.operations
    if not ops then return {} end
    months = months or 12
    local h = ops.occupancyHistory
    local start = math.max(1, #h - months + 1)
    local result = {}
    for i = start, #h do result[#result + 1] = h[i] end
    return result
end

--- 获取NOI趋势
function OP.GetNOITrend(project, months)
    local ops = project.operations
    if not ops then return {} end
    months = months or 12
    local h = ops.noiHistory
    local start = math.max(1, #h - months + 1)
    local result = {}
    for i = start, #h do result[#result + 1] = h[i] end
    return result
end

--- 获取运营状态名称
function OP.GetStatusName(project)
    local ops = project.operations
    if not ops then return "无" end
    local names = {
        waiting_for_mode = "待选模式",
        renovating       = "装修改造中",
        preparing        = "招商筹备",
        ramp_up          = "运营培育",
        mature           = "成熟运营",
        declining        = "运营老化",
    }
    return names[ops.status] or ops.status
end

--- 获取运营简报
function OP.GetSummary(project)
    local ops = project.operations
    if not ops then return {} end
    return {
        status = OP.GetStatusName(project),
        operationMode = ops.operationMode,
        operationModeName = ops.operationModeName or "未选择",
        occupancy = math.floor(ops.occupancy * 100),
        monthlyNOI = ops.monthlyNOI,
        cumulativeNOI = ops.cumulativeNOI,
        valuation = ops.valuation,
        tenantCount = ops.tenantCount,
        satisfaction = ops.tenantSatisfaction,
        operatingMonths = ops.operatingMonths,
        renovating = ops.renovating or false,
        renovationProgress = OP.GetRenovationProgress(ops),
        renovationRemaining = OP.GetRenovationRemaining(ops),
        modeChangeCount = ops.modeChangeCount or 0,
    }
end

--- 获取可用运营模式列表（带当前模式标记）
function OP.GetAvailableModes(project)
    local ops = project.operations
    if not ops then return {} end
    local modes = DT.GetOperationModes(ops.devTypeId)
    local result = {}
    for _, m in ipairs(modes) do
        local info = {
            id = m.id,
            name = m.name,
            icon = m.icon,
            description = m.description,
            revenueMultiplier = m.revenueMultiplier,
            opexMultiplier = m.opexMultiplier,
            rampUpMultiplier = m.rampUpMultiplier,
            renovationCost = m.renovationCost,
            renovationMonths = m.renovationMonths,
            pros = m.pros,
            cons = m.cons,
            isCurrent = (ops.operationMode == m.id),
            -- 计算实际改造费用
            actualRenovCost = math.floor(project.cost.buildCost * (m.renovationCost or 0.05)),
        }
        result[#result + 1] = info
    end
    return result
end

-- ============================================================================
-- 向后兼容
-- ============================================================================

--- 确保运营字段存在(旧存档兼容)
function OP.EnsureOperationsFields(ops)
    if not ops then return nil end
    ops.status = ops.status or "waiting_for_mode"
    ops.occupancy = ops.occupancy or 0
    ops.targetOccupancy = ops.targetOccupancy or 0.90
    ops.rampUpMonths = ops.rampUpMonths or 12
    ops.rampUpElapsed = ops.rampUpElapsed or 0
    ops.baseRentPerSqm = ops.baseRentPerSqm or 60
    ops.currentRentPerSqm = ops.currentRentPerSqm or 0
    ops.rentableArea = ops.rentableArea or 0
    ops.roomCount = ops.roomCount or 0
    ops.baseRevPAR = ops.baseRevPAR or 0
    ops.opexRatio = ops.opexRatio or 0.30
    ops.commissionRate = ops.commissionRate or 0
    ops.monthlyRevenue = ops.monthlyRevenue or 0
    ops.monthlyOpex = ops.monthlyOpex or 0
    ops.monthlyNOI = ops.monthlyNOI or 0
    ops.cumulativeNOI = ops.cumulativeNOI or 0
    ops.capRate = ops.capRate or 0.05
    ops.valuation = ops.valuation or 0
    ops.tenants = ops.tenants or {}
    ops.tenantCount = ops.tenantCount or #ops.tenants
    ops.maxTenants = ops.maxTenants or 0
    ops.tenantSatisfaction = ops.tenantSatisfaction or 70
    ops.noiHistory = ops.noiHistory or {}
    ops.occupancyHistory = ops.occupancyHistory or {}
    ops.totalRevenue = ops.totalRevenue or 0
    ops.totalOpex = ops.totalOpex or 0
    ops.operatingMonths = ops.operatingMonths or 0
    ops.operationMode = ops.operationMode or nil
    ops.operationModeName = ops.operationModeName or nil
    ops.revenueMultiplier = ops.revenueMultiplier or 1.0
    ops.opexMultiplier = ops.opexMultiplier or 1.0
    -- 新增字段
    ops.renovating = ops.renovating or false
    ops.renovationMonthsTotal = ops.renovationMonthsTotal or 0
    ops.renovationMonthsElapsed = ops.renovationMonthsElapsed or 0
    ops.renovationCost = ops.renovationCost or 0
    ops.renovationHistory = ops.renovationHistory or {}
    ops.modeChangeCount = ops.modeChangeCount or 0
    return ops
end

return OP
