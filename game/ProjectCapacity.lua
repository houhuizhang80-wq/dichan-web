-- ============================================================================
-- ProjectCapacity.lua - 项目容量与资金分配系统
-- 多项目并行开发的核心管理模块
-- ============================================================================

local PC = {}

-- ============================================================================
-- 1. 容量计算
-- ============================================================================

--- 计算当前项目容量上限
--- 容量 = min(base + 区域公司数 + 项目总数, max)
---@param company table GD.company
---@return number capacity
function PC.CalcCapacity(company)
    local cap = company.projectCapacity or {base = 1, max = 5}
    local base = cap.base or 1

    -- 每个区域公司 +1
    local rcBonus = 0
    for _ in ipairs(company.regionalCompanies or {}) do
        rcBonus = rcBonus + 1
    end

    -- 每个在岗项目总 +1
    local pdBonus = 0
    for _, kp in ipairs(company.keyPositions or {}) do
        if kp.type == "project_director" then
            pdBonus = pdBonus + 1
        end
    end

    return math.min(base + rcBonus + pdBonus, cap.max or 5)
end

--- 统计当前活跃开发项目数（占用开发容量的阶段）
--- 仅计算需要主动开发管理的项目：拿证、设计、施工、预售
--- 后期阶段（交付、运营、结算等）不占用开发容量
---@param projects table GD.projects
---@return number
function PC.CountActiveProjects(projects)
    -- 不占用开发容量的后期状态（含销售阶段：销售数量无上限）
    local lateStages = {
        presale = true,            -- 预售/销售中不占开发容量，同时销售数无上限
        completed = true,
        delivery = true,
        pending_settlement = true,
        pending_completion = true,
        pending_operations = true,
        settlement = true,
        operations = true,
        mature = true,
        sold_off = true,
    }
    local count = 0
    for _, p in ipairs(projects) do
        if not lateStages[p.status] then
            count = count + 1
        end
    end
    return count
end

--- 检查是否可以创建新项目
---@param company table GD.company
---@param projects table GD.projects
---@return boolean canCreate
---@return string|nil reason
function PC.CanCreateProject(company, projects)
    local capacity = PC.CalcCapacity(company)
    local active = PC.CountActiveProjects(projects)
    if active >= capacity then
        return false, "项目容量已满 (" .. active .. "/" .. capacity ..
            ")。提升方式：设立区域公司(+1) 或 招聘项目总(+1)"
    end
    return true, nil
end

-- ============================================================================
-- 2. 资金拨付
-- ============================================================================

--- 向项目拨付资金（从公司现金池转入项目预算）
---@param company table GD.company
---@param project table 目标项目
---@param amount number 拨付金额（万元）
---@return boolean success
---@return string|nil reason
function PC.AllocateFund(company, project, amount)
    if amount <= 0 then return false, "拨付金额必须大于0" end
    if company.cash < amount then
        return false, "公司现金不足（可用: " .. math.floor(company.cash) .. "万）"
    end
    if not project.budget then
        project.budget = {allocated = 0, spent = 0, remaining = 0}
    end
    company.cash = company.cash - amount
    project.budget.allocated = project.budget.allocated + amount
    project.budget.remaining = project.budget.allocated - project.budget.spent
    return true
end

--- 项目消耗资金（从项目预算扣除）
--- 如果项目无budget字段（旧项目），回退到旧模式返回true
---@param project table
---@param amount number
---@return boolean hasEnough 是否有足够预算
function PC.SpendFromBudget(project, amount)
    if not project.budget then return true end
    project.budget.spent = project.budget.spent + amount
    project.budget.remaining = project.budget.allocated - project.budget.spent
    return project.budget.remaining >= 0
end

--- 计算项目建议拨付金额（智能推荐）
---@param project table
---@return number suggestedAmount
function PC.CalcSuggestedAllocation(project)
    if project.status == "permits" then
        local permitCost = 0
        for _, permit in ipairs(project.permits or {}) do
            permitCost = permitCost + (permit.cost or 0)
        end
        return (project.cost.landCost or 0) + permitCost
    elseif project.status == "design" then
        return project.cost.designCost or 500
    elseif project.status == "construction" or project.status == "presale" then
        local totalMo = math.max(1, project.construction.totalMonths or 12)
        local elapsed = project.construction.monthsElapsed or 0
        local remain = math.max(1, totalMo - elapsed)
        local monthlyCost = math.floor((project.cost.buildCost or 0) / totalMo)
        return monthlyCost * math.min(remain, 6) -- 建议拨付6个月的
    end
    return 0
end

--- 获取项目预算摘要
---@param project table
---@return table {allocated, spent, remaining, burnRate, monthsLeft}
function PC.GetBudgetSummary(project)
    local b = project.budget or {allocated = 0, spent = 0, remaining = 0}
    local totalMo = math.max(1, (project.construction or {}).totalMonths or 12)
    local monthlyCost = math.floor((project.cost.buildCost or 0) / totalMo)
    local monthsLeft = monthlyCost > 0 and math.floor(b.remaining / monthlyCost) or 999
    return {
        allocated = b.allocated,
        spent = b.spent,
        remaining = b.remaining,
        burnRate = monthlyCost,
        monthsLeft = monthsLeft,
    }
end

-- ============================================================================
-- 3. 项目总指派
-- ============================================================================

--- 将项目总指派到项目
---@param company table GD.company
---@param personId string 关键岗位ID
---@param projectId string 项目ID
---@return boolean success
---@return string|nil reason
function PC.AssignDirector(company, personId, projectId)
    local person = nil
    for _, kp in ipairs(company.keyPositions or {}) do
        if kp.id == personId then person = kp; break end
    end
    if not person then return false, "未找到该高管" end
    if person.type ~= "project_director" then
        return false, person.title .. "不是项目总，无法指派到项目"
    end
    if person.assignedProjectId and person.assignedProjectId ~= projectId then
        return false, person.name .. "已指派到项目" .. person.assignedProjectId
    end
    person.assignedProjectId = projectId
    return true
end

--- 解除项目总指派
---@param company table
---@param personId string
---@return boolean
function PC.UnassignDirector(company, personId)
    for _, kp in ipairs(company.keyPositions or {}) do
        if kp.id == personId then
            kp.assignedProjectId = nil
            return true
        end
    end
    return false
end

--- 获取项目的项目总信息
---@param company table
---@param projectId string
---@return table|nil person
function PC.GetProjectDirector(company, projectId)
    for _, kp in ipairs(company.keyPositions or {}) do
        if kp.type == "project_director" and kp.assignedProjectId == projectId then
            return kp
        end
    end
    return nil
end

--- 获取所有未指派的项目总列表
---@param company table
---@return table[] unassigned
function PC.GetUnassignedDirectors(company)
    local result = {}
    for _, kp in ipairs(company.keyPositions or {}) do
        if kp.type == "project_director" and not kp.assignedProjectId then
            table.insert(result, kp)
        end
    end
    return result
end

-- ============================================================================
-- 4. 区域公司项目归属
-- ============================================================================

--- 将项目分配到区域公司
---@param company table
---@param projectId string
---@param regionIdx number
---@return boolean
---@return string|nil reason
function PC.AssignToRegion(company, projectId, regionIdx)
    local rc = (company.regionalCompanies or {})[regionIdx]
    if not rc then return false, "区域公司不存在" end
    local activeCount = 0
    for _, pid in ipairs(rc.projects or {}) do
        if pid ~= projectId then activeCount = activeCount + 1 end
    end
    if activeCount >= (rc.maxProjects or 2) then
        return false, rc.name .. "项目数已满(" .. activeCount .. "/" .. (rc.maxProjects or 2) .. ")"
    end
    -- 避免重复添加
    for _, pid in ipairs(rc.projects) do
        if pid == projectId then return true end
    end
    table.insert(rc.projects, projectId)
    return true
end

--- 根据城市查找匹配的区域公司索引
---@param company table
---@param city string
---@return number|nil regionIdx
function PC.FindRegionByCity(company, city)
    for i, rc in ipairs(company.regionalCompanies or {}) do
        if rc.city == city then
            return i
        end
    end
    return nil
end

-- ============================================================================
-- 5. 项目总能力加成
-- ============================================================================

--- 获取项目总带来的加成
---@param company table GD.company
---@param projectId string
---@return table {permitSpeed, designSpeed, buildSpeed, salesBonus}
function PC.GetDirectorBonuses(company, projectId)
    local director = PC.GetProjectDirector(company, projectId)
    if not director then
        return {permitSpeed = 0, designSpeed = 0, buildSpeed = 0, salesBonus = 0}
    end
    local a = director.ability / 100
    local c = director.connections / 100
    return {
        permitSpeed = a * 0.15,       -- 能力85 -> +12.75%报建
        designSpeed = a * 0.10,       -- 能力85 -> +8.5%设计
        buildSpeed  = a * 0.10,       -- 能力85 -> +8.5%施工
        salesBonus  = c * 0.10,       -- 人脉70 -> +7%销售
    }
end

-- ============================================================================
-- 6. 向后兼容
-- ============================================================================

--- 确保公司数据包含容量系统字段
function PC.EnsureCompanyFields(company)
    if not company.projectCapacity then
        company.projectCapacity = {base = 1, bonus = 0, max = 5}
    end
end

--- 确保项目数据包含预算和归属字段
function PC.EnsureProjectFields(project)
    if not project.budget then
        local spent = project.cost and project.cost.totalCost or 0
        project.budget = {
            allocated = spent,
            spent = spent,
            remaining = 0,
        }
    end
    -- regionalCompanyIdx 和 directorId 默认 nil 即可
end

--- 确保关键岗位数据包含指派字段
function PC.EnsureKeyPositionFields(company)
    for _, kp in ipairs(company.keyPositions or {}) do
        -- assignedProjectId 默认 nil 即可，无需操作
        _ = kp.assignedProjectId
    end
end

--- 确保区域公司数据包含上限字段
function PC.EnsureRegionalFields(company)
    for _, rc in ipairs(company.regionalCompanies or {}) do
        if not rc.maxProjects then
            rc.maxProjects = 2
        end
        if not rc.projects then
            rc.projects = {}
        end
    end
end

return PC
