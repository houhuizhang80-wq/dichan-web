-- ============================================================================
-- Construction.lua - 工程建设管理模块 (7.1~7.5)
-- 进度计划(CPM) / 人机料法环 / 质量管控 / 安全管控 / 变更签证
-- ============================================================================

local CS = {}

-- ============================================================================
-- 7.1 CPM 施工活动 (网络图)
-- ============================================================================
CS.ACTIVITIES = {
    {id="piling",     name="桩基工程",   durationMonths=3, prerequisites={},              phase="foundation"},
    {id="excavation", name="基坑支护",   durationMonths=2, prerequisites={"piling"},      phase="foundation"},
    {id="basement",   name="地下结构",   durationMonths=3, prerequisites={"excavation"},   phase="foundation"},
    {id="structure",  name="主体结构",   durationMonths=8, prerequisites={"basement"},     phase="structure"},
    {id="secondary",  name="二次结构",   durationMonths=3, prerequisites={"structure"},    phase="structure"},
    {id="facade",     name="外立面装饰", durationMonths=4, prerequisites={"structure"},    phase="decoration"},
    {id="interior",   name="室内装修",   durationMonths=4, prerequisites={"facade"},       phase="decoration"},
    {id="landscape",  name="景观市政",   durationMonths=3, prerequisites={"structure"},    phase="landscape"},
    {id="completion", name="竣工验收",   durationMonths=1, prerequisites={"secondary","interior","landscape"}, phase="done"},
}

-- 里程碑
CS.MILESTONES = {
    {id="pile_done",    name="桩基完成",   triggerActivity="piling",     qualityBonus=2},
    {id="zero_level",   name="正负零",     triggerActivity="basement",   qualityBonus=3},
    {id="top_out",      name="主体封顶",   triggerActivity="structure",  qualityBonus=5},
    {id="scaffold_off", name="落架",       triggerActivity="facade",     qualityBonus=2},
    {id="acceptance",   name="竣工备案",   triggerActivity="completion", qualityBonus=5},
}

-- ============================================================================
-- 7.2 人机料法环
-- ============================================================================
CS.CREW_TYPES = {
    {id="civil",      name="土建班组",   baseCost=15, efficiencyRange={0.8, 1.2}},
    {id="steel",      name="钢筋班组",   baseCost=12, efficiencyRange={0.7, 1.1}},
    {id="mep",        name="机电班组",   baseCost=18, efficiencyRange={0.8, 1.15}},
    {id="finishing",   name="装修班组",   baseCost=20, efficiencyRange={0.75, 1.2}},
}

CS.MACHINE_TYPES = {
    {id="tower_crane", name="塔吊",   rentCost=8,  failRate=0.03, phases={"foundation","structure"}},
    {id="elevator",    name="施工电梯", rentCost=5,  failRate=0.05, phases={"structure","decoration"}},
    {id="pump",        name="混凝土泵", rentCost=4,  failRate=0.04, phases={"foundation","structure"}},
}

CS.MATERIAL_TESTS = {
    {id="concrete",  name="混凝土试块",  passRate=0.92, reworkCostPct=0.02},
    {id="steel_bar", name="钢筋力学性能", passRate=0.95, reworkCostPct=0.015},
    {id="waterproof", name="防水材料",   passRate=0.90, reworkCostPct=0.025},
}

CS.PROCESS_CHOICES = {
    {category="formwork", name="模板体系", options={
        {id="wood",     name="木模板",  costMult=1.0, speedMult=1.0, qualityMult=1.0},
        {id="aluminum", name="铝合金模板", costMult=1.35, speedMult=1.25, qualityMult=1.15},
    }},
    {category="scaffold", name="外脚手架", options={
        {id="cantilever", name="悬挑架", costMult=1.0, speedMult=1.0, safetyMult=1.0},
        {id="climbing",   name="爬架",   costMult=1.40, speedMult=1.10, safetyMult=1.30},
    }},
}

CS.ENV_STOPPAGES = {
    {id="exam",      name="中高考禁噪", months={6,7},   durationDays=15, probability=0.9},
    {id="pollution",  name="环保限令",   months={11,12,1}, durationDays=20, probability=0.4},
    {id="spring",     name="春节停工",   months={1,2},   durationDays=25, probability=0.95},
    {id="typhoon",    name="台风暴雨",   months={7,8,9}, durationDays=10, probability=0.3},
}

-- ============================================================================
-- 7.3 质量管控
-- ============================================================================
CS.QUALITY_SEQUENCES = {
    {id="foundation_accept", name="桩基验收",   phase="foundation", passScore=80},
    {id="structure_accept",  name="主体验收",   phase="structure",  passScore=85},
    {id="waterproof_accept", name="防水验收",   phase="structure",  passScore=82},
    {id="facade_accept",     name="外立面验收", phase="decoration", passScore=80},
    {id="final_accept",      name="竣工验收",   phase="done",       passScore=88},
}

CS.MEASURE_ITEMS = {
    {id="vertical",   name="垂直度",   standard=8,   unit="mm",  reworkThreshold=0.90},
    {id="flatness",   name="平整度",   standard=6,   unit="mm",  reworkThreshold=0.90},
    {id="section",    name="截面尺寸", standard=10,  unit="mm",  reworkThreshold=0.90},
}

CS.LEAK_TESTS = {
    {id="roof",      name="屋面淋水",   phase="decoration", passRate=0.85},
    {id="exterior",  name="外墙淋水",   phase="decoration", passRate=0.88},
    {id="bathroom",  name="卫生间蓄水", phase="decoration", passRate=0.90},
}

CS.SAMPLE_ROOM_COST = 50 -- 万元
CS.SAMPLE_ROOM_QUALITY_BONUS = 5

-- ============================================================================
-- 7.4 安全管控
-- ============================================================================
CS.SAFETY_CHECK_TYPES = {
    {id="daily",   name="日常巡检",  coverageBonus=1, costPerCheck=0},
    {id="weekly",  name="周专项检查", coverageBonus=3, costPerCheck=2},
    {id="monthly", name="月度大检查", coverageBonus=5, costPerCheck=5},
}

CS.MAJOR_HAZARDS = {
    {id="deep_pit",    name="深基坑",     phase="foundation", probability=0.02, costPct=0.03, delayDays=30},
    {id="high_form",   name="高支模坍塌", phase="structure",  probability=0.01, costPct=0.05, delayDays=45},
    {id="crane_fall",  name="塔吊事故",   phase="structure",  probability=0.008, costPct=0.04, delayDays=60},
    {id="fire",        name="施工火灾",   phase="decoration", probability=0.015, costPct=0.02, delayDays=20},
    {id="fall",        name="高处坠落",   phase="structure",  probability=0.025, costPct=0.01, delayDays=15},
}

-- ============================================================================
-- 7.5 变更签证
-- ============================================================================
CS.CHANGE_TYPES = {
    {id="design",    name="设计变更",   costRange={-0.02, 0.05}, durationRange={0, 2}},
    {id="site",      name="现场签证",   costRange={0.005, 0.02}, durationRange={0, 1}},
    {id="policy",    name="政策调整",   costRange={-0.01, 0.03}, durationRange={0, 1}},
    {id="claim",     name="施工索赔",   costRange={0.01, 0.08},  durationRange={1, 3}},
}

CS.MALICIOUS_CLAIM_THRESHOLD = 0.05 -- 单次变更超总成本5%视为恶意索赔

-- ============================================================================
-- 初始化
-- ============================================================================

--- 创建完整的施工数据结构
---@param opts {totalMonths: number}
---@return table
function CS.InitConstructionData(opts)
    local totalMonths = (opts and opts.totalMonths) or 30

    -- 初始化 CPM 活动
    local activities = {}
    for _, tmpl in ipairs(CS.ACTIVITIES) do
        table.insert(activities, {
            id = tmpl.id,
            name = tmpl.name,
            durationMonths = tmpl.durationMonths,
            prerequisites = tmpl.prerequisites,
            phase = tmpl.phase,
            started = false,
            finished = false,
            elapsed = 0,           -- 已进行月数
            actualDuration = tmpl.durationMonths,  -- 实际工期(受工法影响)
        })
    end

    -- 初始化里程碑
    local milestones = {}
    for _, tmpl in ipairs(CS.MILESTONES) do
        table.insert(milestones, {
            id = tmpl.id,
            name = tmpl.name,
            triggerActivity = tmpl.triggerActivity,
            qualityBonus = tmpl.qualityBonus,
            achieved = false,
            achievedMonth = 0,
        })
    end

    -- 初始化机械
    local machines = {}
    for _, tmpl in ipairs(CS.MACHINE_TYPES) do
        table.insert(machines, {
            typeId = tmpl.id,
            name = tmpl.name,
            status = "standby",  -- standby/active/broken
            failCount = 0,
        })
    end

    -- 初始化班组
    local crews = {}
    for _, tmpl in ipairs(CS.CREW_TYPES) do
        table.insert(crews, {
            typeId = tmpl.id,
            name = tmpl.name,
            efficiency = 1.0,
            morale = 80,
        })
    end

    return {
        -- 基础字段(保留兼容旧逻辑)
        phase = "none",
        phaseNames = {"未开工","桩基工程","主体结构","装饰装修","景观市政","竣工"},
        progress = 0,
        quality = 85,
        safety = 90,
        monthsElapsed = 0,
        totalMonths = totalMonths,

        -- 7.1 进度计划
        schedule = {
            activities = activities,
            milestones = milestones,
            criticalPath = {"piling","excavation","basement","structure","facade","interior","completion"},
            delayDays = 0,
        },

        -- 7.2 五维管控
        crews = crews,
        machines = machines,
        materialTests = {},
        processChoices = {formwork = "wood", scaffold = "cantilever"},
        envStoppages = {},

        -- 7.3 质量管控
        qualitySystem = {
            score = 85,
            acceptances = {},
            sampleRoom = false,
            sampleRoomBonus = 0,
            measurements = {},
            leakTests = {},
        },

        -- 7.4 安全管控
        safetySystem = {
            score = 90,
            checks = {},
            accidents = {},
            totalAccidentCost = 0,
        },

        -- 7.5 变更签证
        changeOrders = {
            items = {},
            totalCostDelta = 0,
            totalDurationDelta = 0,
        },
    }
end

-- ============================================================================
-- 月度更新 (替换 GameData.UpdateProjects 中的施工逻辑)
-- ============================================================================

--- 获取活动模板
local function _GetActivityTemplate(actId)
    for _, a in ipairs(CS.ACTIVITIES) do
        if a.id == actId then return a end
    end
    return nil
end

--- 获取施工活动(运行时数据)
local function _GetActivity(con, actId)
    for _, a in ipairs(con.schedule.activities) do
        if a.id == actId then return a end
    end
    return nil
end

--- 计算速度系数(工法加成)
local function _GetSpeedMultiplier(con)
    local mult = 1.0
    for _, pc in ipairs(CS.PROCESS_CHOICES) do
        local chosen = con.processChoices[pc.category]
        if chosen then
            for _, opt in ipairs(pc.options) do
                if opt.id == chosen then
                    mult = mult * (opt.speedMult or 1.0)
                    break
                end
            end
        end
    end
    return mult
end

--- 推进 CPM 进度
local function _UpdateSchedule(con, buildBonus)
    local sch = con.schedule
    local speedMult = _GetSpeedMultiplier(con) * buildBonus

    for _, act in ipairs(sch.activities) do
        if not act.finished then
            -- 检查前置是否全部完成
            local canStart = true
            for _, preId in ipairs(act.prerequisites) do
                local preAct = _GetActivity(con, preId)
                if preAct and not preAct.finished then
                    canStart = false
                    break
                end
            end

            if canStart and not act.started then
                act.started = true
            end

            if act.started then
                act.elapsed = act.elapsed + speedMult
                if act.elapsed >= act.actualDuration then
                    act.finished = true
                    act.elapsed = act.actualDuration
                end
            end
        end
    end

    -- 计算总进度 = 已完成活动工期之和 / 总工期之和
    local totalDur = 0
    local doneDur = 0
    for _, act in ipairs(sch.activities) do
        totalDur = totalDur + act.actualDuration
        if act.finished then
            doneDur = doneDur + act.actualDuration
        else
            doneDur = doneDur + math.min(act.elapsed, act.actualDuration)
        end
    end
    if totalDur > 0 then
        con.progress = math.min(100, math.floor(doneDur / totalDur * 100))
    end
    con.monthsElapsed = con.monthsElapsed + buildBonus
end

--- 更新当前阶段(根据活动状态)
local function _UpdatePhase(con)
    local sch = con.schedule
    local completionAct = _GetActivity(con, "completion")
    if completionAct and completionAct.finished then
        con.phase = "done"
        return
    end

    local landscapeAct = _GetActivity(con, "landscape")
    local facadeAct = _GetActivity(con, "facade")
    local structureAct = _GetActivity(con, "structure")
    local basementAct = _GetActivity(con, "basement")

    if landscapeAct and landscapeAct.started and not landscapeAct.finished then
        con.phase = "landscape"
    elseif facadeAct and facadeAct.started then
        con.phase = "decoration"
    elseif structureAct and structureAct.started then
        con.phase = "structure"
    elseif basementAct and basementAct.started or _GetActivity(con, "piling").started then
        con.phase = "foundation"
    else
        con.phase = "none"
    end
end

--- 检查里程碑
local function _CheckMilestones(con, GD, p)
    for _, ms in ipairs(con.schedule.milestones) do
        if not ms.achieved then
            local act = _GetActivity(con, ms.triggerActivity)
            if act and act.finished then
                ms.achieved = true
                ms.achievedMonth = con.monthsElapsed
                con.qualitySystem.score = math.min(100, con.qualitySystem.score + ms.qualityBonus)
                if GD and p then
                    GD.AddEvent("【" .. p.name .. "】里程碑达成: " .. ms.name, "success")
                end
            end
        end
    end
end

--- 检查环境停工
local function _CheckEnvStoppages(con, month)
    for _, env in ipairs(CS.ENV_STOPPAGES) do
        local inMonth = false
        for _, m in ipairs(env.months) do
            if m == month then inMonth = true; break end
        end
        if inMonth and math.random() < env.probability then
            table.insert(con.envStoppages, {
                reason = env.name,
                month = con.monthsElapsed,
                durationDays = env.durationDays,
            })
            con.schedule.delayDays = con.schedule.delayDays + env.durationDays
            return env  -- 每月最多一次停工
        end
    end
    return nil
end

--- 检查机械故障
local function _CheckMachineFailures(con)
    for _, m in ipairs(con.machines) do
        local tmpl = nil
        for _, mt in ipairs(CS.MACHINE_TYPES) do
            if mt.id == m.typeId then tmpl = mt; break end
        end
        if tmpl and m.status == "active" and math.random() < tmpl.failRate then
            m.status = "broken"
            m.failCount = m.failCount + 1
            con.schedule.delayDays = con.schedule.delayDays + 7
            return m  -- 每月最多一次故障
        end
        -- 修复已坏机械
        if m.status == "broken" then
            m.status = "active"
        end
    end
    return nil
end

--- 激活/停用机械(根据当前阶段)
local function _UpdateMachineStatus(con)
    for _, m in ipairs(con.machines) do
        local tmpl = nil
        for _, mt in ipairs(CS.MACHINE_TYPES) do
            if mt.id == m.typeId then tmpl = mt; break end
        end
        if tmpl and m.status ~= "broken" then
            local inPhase = false
            for _, ph in ipairs(tmpl.phases) do
                if ph == con.phase then inPhase = true; break end
            end
            m.status = inPhase and "active" or "standby"
        end
    end
end

--- 检查安全事故
local function _CheckSafetyAccidents(con, GD, p)
    local safetyScore = con.safetySystem.score
    -- 安全评分越低，事故概率越高
    local safetyFactor = (100 - safetyScore) / 100  -- 0~1, 越大越危险

    -- 工法安全加成
    local safetyMult = 1.0
    for _, pc in ipairs(CS.PROCESS_CHOICES) do
        local chosen = con.processChoices[pc.category]
        if chosen then
            for _, opt in ipairs(pc.options) do
                if opt.id == chosen and opt.safetyMult then
                    safetyMult = safetyMult * opt.safetyMult
                    break
                end
            end
        end
    end

    for _, hz in ipairs(CS.MAJOR_HAZARDS) do
        if hz.phase == con.phase then
            local adjustedProb = hz.probability * (1 + safetyFactor) / safetyMult
            if math.random() < adjustedProb then
                local cost = math.floor((p.cost.buildCost or 0) * hz.costPct)
                table.insert(con.safetySystem.accidents, {
                    hazardId = hz.id,
                    name = hz.name,
                    month = con.monthsElapsed,
                    cost = cost,
                    delayDays = hz.delayDays,
                })
                con.safetySystem.totalAccidentCost = con.safetySystem.totalAccidentCost + cost
                con.safetySystem.score = math.max(0, con.safetySystem.score - 15)
                con.schedule.delayDays = con.schedule.delayDays + hz.delayDays
                if GD then
                    GD.company.cash = GD.company.cash - cost
                end
                if GD and p then
                    GD.AddEvent("【" .. p.name .. "】安全事故: " .. hz.name .. "，损失" .. cost .. "万", "danger")
                end
                return  -- 每月最多一次事故
            end
        end
    end
end

--- 质量评分自然衰减
local function _UpdateQualityScore(con)
    -- 没有样板间且没有检查时缓慢衰减
    if #con.qualitySystem.acceptances == 0 and not con.qualitySystem.sampleRoom then
        con.qualitySystem.score = math.max(60, con.qualitySystem.score - 0.5)
    end
    -- 样板间加成
    if con.qualitySystem.sampleRoom then
        con.qualitySystem.score = math.min(100, con.qualitySystem.score + 0.3)
    end
    con.quality = math.floor(con.qualitySystem.score)
end

--- 安全评分自然衰减
local function _UpdateSafetyScore(con)
    -- 没有近期检查时缓慢衰减
    local recentChecks = 0
    for _, ck in ipairs(con.safetySystem.checks) do
        if con.monthsElapsed - ck.month <= 2 then
            recentChecks = recentChecks + 1
        end
    end
    if recentChecks == 0 then
        con.safetySystem.score = math.max(50, con.safetySystem.score - 1)
    end
    con.safety = math.floor(con.safetySystem.score)
end

--- 主月度更新入口
---@param project table 项目数据
---@param GD table GameData 引用
---@return {canPresale: boolean, isComplete: boolean}
function CS.MonthlyUpdate(project, GD)
    local con = project.construction
    local PC = require("ProjectCapacity")
    local dirBonus = PC.GetDirectorBonuses(GD.company, project.id)
    local executiveEffects = GD.GetExecutiveEffects and GD.GetExecutiveEffects(GD) or {}
    local buildBonus = 1 + (GD.company.traitEffects.buildSpeedBonus or 0)
        + (dirBonus.buildSpeed or 0) / 100
        + (executiveEffects.speedBonus or 0)

    -- 首月自动启动第一个活动
    if con.monthsElapsed == 0 then
        local first = con.schedule.activities[1]
        if first and not first.started then
            first.started = true
        end
    end

    -- CPM 推进
    _UpdateSchedule(con, buildBonus)
    _UpdatePhase(con)
    if con.phase == "done" then
        con.progress = 100
    end
    _CheckMilestones(con, GD, project)

    -- 机械管理：只更新设备状态展示，不再随机故障拖慢工期
    _UpdateMachineStatus(con)

    -- 已取消项目施工进度影响因素：环境停工/安全事故不再改变工期或暂停进度。
    -- 评分仍按正常施工维护，保证项目按计划推进。

    -- 评分更新
    _UpdateQualityScore(con)
    _UpdateSafetyScore(con)

    -- 返回状态（预售条件使用 DevTypes 定义的 presaleThreshold）
    local DT = require("DevTypes")
    local typeDef = DT.TYPES[project.devTypeId]
    local threshold = (typeDef and typeDef.presaleThreshold) or 0.25
    return {
        canPresale = con.progress >= (threshold * 100),
        isComplete = con.phase == "done" and con.progress >= 100,
    }
end

-- ============================================================================
-- 玩家操作函数
-- ============================================================================

--- 安全检查
function CS.PerformSafetyCheck(con, checkTypeId)
    local tmpl = nil
    for _, ct in ipairs(CS.SAFETY_CHECK_TYPES) do
        if ct.id == checkTypeId then tmpl = ct; break end
    end
    if not tmpl then return false, "未知检查类型" end

    table.insert(con.safetySystem.checks, {
        type = checkTypeId,
        name = tmpl.name,
        month = con.monthsElapsed,
        issues = math.random(0, 3),
    })
    con.safetySystem.score = math.min(100, con.safetySystem.score + tmpl.coverageBonus)
    con.safety = math.floor(con.safetySystem.score)
    return true, tmpl.name .. "完成，安全评分+" .. tmpl.coverageBonus
end

--- 工序验收(三方举牌)
function CS.PerformQualityAcceptance(con, sequenceId)
    local tmpl = nil
    for _, sq in ipairs(CS.QUALITY_SEQUENCES) do
        if sq.id == sequenceId then tmpl = sq; break end
    end
    if not tmpl then return false, "未知工序" end

    -- 检查阶段匹配
    if tmpl.phase ~= con.phase and tmpl.phase ~= "done" then
        return false, "当前阶段不适用此验收"
    end

    -- 已经验收过
    for _, acc in ipairs(con.qualitySystem.acceptances) do
        if acc.sequenceId == sequenceId and acc.passed then
            return false, "已通过验收"
        end
    end

    local score = math.random(70, 100)
    local passed = score >= tmpl.passScore
    table.insert(con.qualitySystem.acceptances, {
        sequenceId = sequenceId,
        name = tmpl.name,
        month = con.monthsElapsed,
        score = score,
        passed = passed,
    })

    if passed then
        con.qualitySystem.score = math.min(100, con.qualitySystem.score + 3)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. "通过 (" .. score .. "分)"
    else
        con.qualitySystem.score = math.max(60, con.qualitySystem.score - 2)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. "未通过 (" .. score .. "分), 需返工"
    end
end

--- 材料送检
function CS.PerformMaterialTest(con, testId)
    local tmpl = nil
    for _, mt in ipairs(CS.MATERIAL_TESTS) do
        if mt.id == testId then tmpl = mt; break end
    end
    if not tmpl then return false, "未知检测项" end

    local passed = math.random() < tmpl.passRate
    table.insert(con.materialTests, {
        testId = testId,
        name = tmpl.name,
        month = con.monthsElapsed,
        passed = passed,
    })

    if passed then
        con.qualitySystem.score = math.min(100, con.qualitySystem.score + 1)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. " 检测合格"
    else
        con.qualitySystem.score = math.max(60, con.qualitySystem.score - 2)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. " 不合格，材料退场!"
    end
end

--- 建造实体样板间
function CS.BuildSampleRoom(con, project)
    if con.qualitySystem.sampleRoom then
        return false, "样板间已建成"
    end
    con.qualitySystem.sampleRoom = true
    con.qualitySystem.sampleRoomBonus = CS.SAMPLE_ROOM_QUALITY_BONUS
    con.qualitySystem.score = math.min(100, con.qualitySystem.score + CS.SAMPLE_ROOM_QUALITY_BONUS)
    con.quality = math.floor(con.qualitySystem.score)
    return true, "样板间建成，质量评分+" .. CS.SAMPLE_ROOM_QUALITY_BONUS .. "，花费" .. CS.SAMPLE_ROOM_COST .. "万"
end

--- 切换工法
function CS.ChangeProcess(con, category, choiceId)
    local tmpl = nil
    for _, pc in ipairs(CS.PROCESS_CHOICES) do
        if pc.category == category then tmpl = pc; break end
    end
    if not tmpl then return false, "未知工法类别" end

    local found = false
    for _, opt in ipairs(tmpl.options) do
        if opt.id == choiceId then found = true; break end
    end
    if not found then return false, "未知工法选项" end

    con.processChoices[category] = choiceId
    -- 重新计算活动工期
    local speedMult = _GetSpeedMultiplier(con)
    for _, act in ipairs(con.schedule.activities) do
        if not act.finished then
            local baseTmpl = _GetActivityTemplate(act.id)
            if baseTmpl then
                act.actualDuration = math.max(1, math.floor(baseTmpl.durationMonths / speedMult))
            end
        end
    end
    return true, "工法切换成功"
end

--- 提交变更签证
function CS.SubmitChangeOrder(con, changeTypeId, description, projectCost)
    local tmpl = nil
    for _, ct in ipairs(CS.CHANGE_TYPES) do
        if ct.id == changeTypeId then tmpl = ct; break end
    end
    if not tmpl then return false, "未知变更类型" end

    local costPct = tmpl.costRange[1] + math.random() * (tmpl.costRange[2] - tmpl.costRange[1])
    local costDelta = math.floor((projectCost or 0) * costPct)
    local durationDelta = math.random(tmpl.durationRange[1], tmpl.durationRange[2])

    -- 恶意索赔判定
    local malicious = costPct > CS.MALICIOUS_CLAIM_THRESHOLD

    table.insert(con.changeOrders.items, {
        type = changeTypeId,
        typeName = tmpl.name,
        description = description or tmpl.name,
        costDelta = costDelta,
        durationDelta = durationDelta,
        month = con.monthsElapsed,
        approved = not malicious,
        malicious = malicious,
    })

    if not malicious then
        con.changeOrders.totalCostDelta = con.changeOrders.totalCostDelta + costDelta
        con.changeOrders.totalDurationDelta = con.changeOrders.totalDurationDelta + durationDelta
    end

    if malicious then
        return true, "变更被驳回: 涉嫌恶意索赔 (金额占比" .. string.format("%.1f%%", costPct * 100) .. ")"
    else
        return true, tmpl.name .. "已审批，成本变更" .. costDelta .. "万，工期+" .. durationDelta .. "月"
    end
end

--- 实测实量
function CS.PerformMeasurement(con, itemId)
    local tmpl = nil
    for _, mi in ipairs(CS.MEASURE_ITEMS) do
        if mi.id == itemId then tmpl = mi; break end
    end
    if not tmpl then return false, "未知测量项" end

    local deviation = math.random(1, tmpl.standard + 5)
    local passRate = deviation <= tmpl.standard and 1.0 or 0.0
    -- 模拟批次合格率
    local batchPassRate = 0.75 + math.random() * 0.25
    local needRework = batchPassRate < tmpl.reworkThreshold

    table.insert(con.qualitySystem.measurements, {
        itemId = itemId,
        name = tmpl.name,
        month = con.monthsElapsed,
        deviation = deviation,
        batchPassRate = batchPassRate,
        passed = not needRework,
    })

    if needRework then
        con.qualitySystem.score = math.max(60, con.qualitySystem.score - 3)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. " 合格率" .. string.format("%.0f%%", batchPassRate * 100) .. " < 90%，需返工!"
    else
        con.qualitySystem.score = math.min(100, con.qualitySystem.score + 1)
        con.quality = math.floor(con.qualitySystem.score)
        return true, tmpl.name .. " 合格率" .. string.format("%.0f%%", batchPassRate * 100) .. "，达标"
    end
end

-- ============================================================================
-- 向后兼容
-- ============================================================================

--- 确保旧存档包含所有新字段
function CS.EnsureConstructionFields(con)
    if not con then return end

    -- 如果已有 schedule 字段，说明是新版数据
    if con.schedule and con.schedule.activities and #con.schedule.activities > 0 then
        return
    end

    -- 从旧 progress 恢复
    local fresh = CS.InitConstructionData({totalMonths = con.totalMonths or 30})

    -- 保留旧的基础字段
    fresh.phase = con.phase or fresh.phase
    fresh.progress = con.progress or fresh.progress
    fresh.quality = con.quality or fresh.quality
    fresh.safety = con.safety or fresh.safety
    fresh.monthsElapsed = con.monthsElapsed or fresh.monthsElapsed
    fresh.totalMonths = con.totalMonths or fresh.totalMonths

    -- 根据旧 progress 反推活动状态
    CS._RecoverScheduleFromProgress(fresh)

    -- 复制新字段到旧对象
    con.schedule = fresh.schedule
    con.crews = con.crews or fresh.crews
    con.machines = con.machines or fresh.machines
    con.materialTests = con.materialTests or fresh.materialTests
    con.processChoices = con.processChoices or fresh.processChoices
    con.envStoppages = con.envStoppages or fresh.envStoppages
    con.qualitySystem = con.qualitySystem or fresh.qualitySystem
    con.safetySystem = con.safetySystem or fresh.safetySystem
    con.changeOrders = con.changeOrders or fresh.changeOrders

    -- 同步基础字段
    con.qualitySystem.score = con.quality or 85
    con.safetySystem.score = con.safety or 90
end

--- 根据旧 progress 反推活动完成状态
function CS._RecoverScheduleFromProgress(con)
    local progress = con.progress or 0
    local sch = con.schedule

    -- 按 CPM 顺序: 累计工期占比推算完成到哪一步
    local totalDur = 0
    for _, act in ipairs(sch.activities) do
        totalDur = totalDur + act.actualDuration
    end

    local targetDur = totalDur * progress / 100
    local accumulated = 0
    for _, act in ipairs(sch.activities) do
        if accumulated + act.actualDuration <= targetDur then
            act.started = true
            act.finished = true
            act.elapsed = act.actualDuration
            accumulated = accumulated + act.actualDuration
        elseif accumulated < targetDur then
            act.started = true
            act.elapsed = targetDur - accumulated
            accumulated = targetDur
        else
            break
        end
    end

    -- 同步里程碑
    for _, ms in ipairs(sch.milestones) do
        local act = _GetActivity(con, ms.triggerActivity)
        if act and act.finished then
            ms.achieved = true
            ms.achievedMonth = con.monthsElapsed
        end
    end
end

return CS
