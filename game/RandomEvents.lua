-- ============================================================================
-- RandomEvents.lua - 项目级随机事件系统
-- 停工事件(施工阶段) + 销售降速事件(销售阶段)
-- ============================================================================

local RE = {}

-- ============================================================================
-- 停工事件定义
-- ============================================================================
RE.STOPPAGE_EVENTS = {
    {
        id = "extreme_weather",
        name = "极端天气",
        desc = "遭遇极端暴雨/暴雪天气，工地无法施工",
        probability = 0.04,           -- 每月4%概率
        durationRange = {1, 3},       -- 停工1-3个月
        costPctRange = {0.005, 0.015}, -- 占建安成本的0.5%-1.5%额外损失
        penaltyDesc = "设备防护费+误工费",
    },
    {
        id = "safety_inspection",
        name = "安全大检查",
        desc = "住建局突击安全检查，责令整改后方可复工",
        probability = 0.03,
        durationRange = {1, 4},
        costPctRange = {0.01, 0.03},
        penaltyDesc = "整改费用+罚款",
    },
    {
        id = "labor_dispute",
        name = "劳资纠纷",
        desc = "施工队集体讨薪/罢工，工地陷入停滞",
        probability = 0.025,
        durationRange = {1, 3},
        costPctRange = {0.01, 0.025},
        penaltyDesc = "赔偿金+调解费",
    },
    {
        id = "ownership_dispute",
        name = "权属纠纷",
        desc = "土地权属存在争议，法院责令暂停施工等候裁决",
        probability = 0.015,
        durationRange = {3, 12},
        costPctRange = {0.02, 0.06},
        penaltyDesc = "诉讼费+资金占用成本",
    },
    {
        id = "quality_rework",
        name = "质量返工",
        desc = "质检发现严重质量问题，必须拆除重建部分结构",
        probability = 0.02,
        durationRange = {2, 6},
        costPctRange = {0.03, 0.08},
        penaltyDesc = "拆除费+重建费+延期成本",
    },
    {
        id = "environmental_remediation",
        name = "环保整改",
        desc = "环保督查发现违规排放/扬尘超标，责令停工整改",
        probability = 0.03,
        durationRange = {1, 4},
        costPctRange = {0.01, 0.03},
        penaltyDesc = "整改设备费+环保罚款",
    },
    {
        id = "public_event",
        name = "公共事件",
        desc = "周边发生重大公共事件，施工区域临时管控",
        probability = 0.02,
        durationRange = {1, 6},
        costPctRange = {0.005, 0.02},
        penaltyDesc = "人员遣散费+设备闲置费",
    },
}

-- ============================================================================
-- 销售降速事件定义
-- ============================================================================
RE.SALES_SLOWDOWN_EVENTS = {
    {
        id = "competitor_price_cut",
        name = "竞品降价",
        desc = "周边楼盘大幅降价促销，分流客户",
        probability = 0.05,
        durationRange = {2, 6},
        slowdownRange = {0.20, 0.40},  -- 销售速度降低20%-40%
        suggestion = "可考虑跟进降价或加大促销力度",
    },
    {
        id = "negative_pr",
        name = "负面舆情",
        desc = "项目被媒体曝光负面新闻（虚假宣传/延期交付等）",
        probability = 0.03,
        durationRange = {2, 5},
        slowdownRange = {0.30, 0.60},
        suggestion = "可增加营销预算改善口碑",
    },
    {
        id = "facilities_unfulfilled",
        name = "配套未兑现",
        desc = "此前承诺的学校/地铁等配套迟迟未动工，引发信任危机",
        probability = 0.025,
        durationRange = {3, 8},
        slowdownRange = {0.25, 0.50},
        suggestion = "可降价补偿客户或等待政策落实",
    },
    {
        id = "policy_tightening",
        name = "政策收紧",
        desc = "当地出台更严格的限购/限贷政策",
        probability = 0.03,
        durationRange = {3, 12},
        slowdownRange = {0.20, 0.50},
        suggestion = "等待政策周期转变",
    },
    {
        id = "economic_downturn",
        name = "经济下行",
        desc = "区域经济遭遇阶段性困难，购房需求萎缩",
        probability = 0.025,
        durationRange = {4, 12},
        slowdownRange = {0.15, 0.40},
        suggestion = "可降价加速去化或暂缓推盘",
    },
    {
        id = "industry_default",
        name = "行业违约潮",
        desc = "同行出现集体暴雷，市场信心严重受挫",
        probability = 0.015,
        durationRange = {6, 12},
        slowdownRange = {0.40, 0.70},
        suggestion = "维护品牌口碑，展示交付能力",
    },
    {
        id = "subsidized_housing",
        name = "保障房冲击",
        desc = "大量保障性住房入市，分流刚需客户",
        probability = 0.02,
        durationRange = {3, 8},
        slowdownRange = {0.10, 0.30},
        suggestion = "可提升产品品质或降价竞争",
    },
}

-- ============================================================================
-- 初始化项目事件数据
-- ============================================================================

--- 确保项目包含随机事件字段
---@param project table
function RE.EnsureEventFields(project)
    if not project.randomEvents then
        project.randomEvents = {
            activeStoppages = {},     -- 活跃停工事件: {id, name, desc, remainMonths, monthlyCost, penaltyDesc, startMonth}
            activeSalesSlowdowns = {},-- 活跃销售降速: {id, name, desc, remainMonths, slowdownRate, suggestion, startMonth}
            history = {},             -- 历史事件记录: {id, name, type, month, duration, cost}
        }
    end
    -- 向后兼容
    if not project.randomEvents.activeStoppages then project.randomEvents.activeStoppages = {} end
    if not project.randomEvents.activeSalesSlowdowns then project.randomEvents.activeSalesSlowdowns = {} end
    if not project.randomEvents.history then project.randomEvents.history = {} end
end

-- ============================================================================
-- 停工事件逻辑
-- ============================================================================

--- 检查并触发停工事件（施工阶段每月调用）
---@param project table
---@param GD table
---@return table|nil 触发的事件，nil=未触发
function RE.CheckStoppageEvents(project, GD)
    RE.EnsureEventFields(project)
    local re = project.randomEvents

    -- 已有3个活跃停工事件时不再叠加
    if #re.activeStoppages >= 3 then return nil end

    -- 安全评分影响：评分越低越容易触发（safety 90=基准，70=1.5倍概率）
    local safetyFactor = 1.0
    local safety = project.construction and project.construction.safety or 90
    if safety < 90 then
        safetyFactor = 1.0 + (90 - safety) * 0.025  -- 每低1分概率+2.5%
    end

    for _, evt in ipairs(RE.STOPPAGE_EVENTS) do
        -- 检查是否同类事件已存在
        local alreadyActive = false
        for _, active in ipairs(re.activeStoppages) do
            if active.id == evt.id then alreadyActive = true; break end
        end
        if alreadyActive then goto continue_stoppage end

        local adjustedProb = evt.probability * safetyFactor
        if math.random() < adjustedProb then
            -- 触发！
            local duration = math.random(evt.durationRange[1], evt.durationRange[2])
            local costPct = evt.costPctRange[1] + math.random() * (evt.costPctRange[2] - evt.costPctRange[1])
            local buildCost = project.cost and project.cost.buildCost or 10000
            local totalPenaltyCost = math.floor(buildCost * costPct)
            local monthlyCost = math.floor(totalPenaltyCost / math.max(1, duration))

            local activeEvt = {
                id = evt.id,
                name = evt.name,
                desc = evt.desc,
                remainMonths = duration,
                totalDuration = duration,
                monthlyCost = monthlyCost,
                totalCost = totalPenaltyCost,
                penaltyDesc = evt.penaltyDesc,
                startMonth = GD.totalMonths,
            }
            table.insert(re.activeStoppages, activeEvt)

            -- 记录历史
            table.insert(re.history, {
                id = evt.id,
                name = evt.name,
                type = "stoppage",
                month = GD.totalMonths,
                duration = duration,
                cost = totalPenaltyCost,
            })

            -- 游戏事件通知
            GD.AddEvent("【" .. project.name .. "】⚠️ " .. evt.name .. "! 停工" .. duration .. "个月，预计损失" .. totalPenaltyCost .. "万", "danger")

            return activeEvt
        end
        ::continue_stoppage::
    end
    return nil
end

--- 更新活跃停工事件（每月调用，扣费+倒计时）
---@param project table
---@param GD table
---@return boolean hasActiveStoppage 是否有活跃停工
function RE.UpdateStoppages(project, GD)
    RE.EnsureEventFields(project)
    local re = project.randomEvents

    for i = #re.activeStoppages, 1, -1 do
        local evt = re.activeStoppages[i]
        -- 每月扣除罚金成本
        if evt.monthlyCost > 0 then
            GD.company.cash = GD.company.cash - evt.monthlyCost
            GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + evt.monthlyCost
            project.cost.totalCost = (project.cost.totalCost or 0) + evt.monthlyCost
        end
        -- 倒计时
        evt.remainMonths = evt.remainMonths - 1
        if evt.remainMonths <= 0 then
            GD.AddEvent("【" .. project.name .. "】" .. evt.name .. "已解除，恢复施工", "success")
            table.remove(re.activeStoppages, i)
        end
    end

    return #re.activeStoppages > 0
end

--- 判断项目是否因随机事件处于停工状态
---@param project table
---@return boolean
function RE.IsProjectStopped(project)
    if not project.randomEvents then return false end
    return #project.randomEvents.activeStoppages > 0
end

-- ============================================================================
-- 销售降速事件逻辑
-- ============================================================================

--- 检查并触发销售降速事件（销售阶段每月调用）
---@param project table
---@param GD table
---@return table|nil 触发的事件
function RE.CheckSalesSlowdownEvents(project, GD)
    RE.EnsureEventFields(project)
    local re = project.randomEvents

    -- 最多叠加3个销售事件
    if #re.activeSalesSlowdowns >= 3 then return nil end

    -- 口碑影响: 品牌分越低越容易触发负面事件
    local brandFactor = 1.0
    local brandScore = GD.brand and GD.brand.score or 50
    if brandScore < 50 then
        brandFactor = 1.0 + (50 - brandScore) * 0.02  -- 每低1分概率+2%
    elseif brandScore > 70 then
        brandFactor = 1.0 - (brandScore - 70) * 0.01  -- 每高1分概率-1%
    end
    brandFactor = math.max(0.5, brandFactor)

    for _, evt in ipairs(RE.SALES_SLOWDOWN_EVENTS) do
        -- 检查是否同类事件已存在
        local alreadyActive = false
        for _, active in ipairs(re.activeSalesSlowdowns) do
            if active.id == evt.id then alreadyActive = true; break end
        end
        if alreadyActive then goto continue_sales end

        local adjustedProb = evt.probability * brandFactor
        if math.random() < adjustedProb then
            local duration = math.random(evt.durationRange[1], evt.durationRange[2])
            local slowdownRate = evt.slowdownRange[1] + math.random() * (evt.slowdownRange[2] - evt.slowdownRange[1])
            slowdownRate = math.floor(slowdownRate * 100) / 100  -- 保留2位小数

            local activeEvt = {
                id = evt.id,
                name = evt.name,
                desc = evt.desc,
                remainMonths = duration,
                totalDuration = duration,
                slowdownRate = slowdownRate,
                suggestion = evt.suggestion,
                startMonth = GD.totalMonths,
            }
            table.insert(re.activeSalesSlowdowns, activeEvt)

            -- 历史记录
            table.insert(re.history, {
                id = evt.id,
                name = evt.name,
                type = "sales_slowdown",
                month = GD.totalMonths,
                duration = duration,
                slowdownRate = slowdownRate,
            })

            local pctStr = string.format("%.0f%%", slowdownRate * 100)
            GD.AddEvent("【" .. project.name .. "】⚠️ " .. evt.name .. "! 销售速度-" .. pctStr .. "，持续" .. duration .. "个月", "warning")

            return activeEvt
        end
        ::continue_sales::
    end
    return nil
end

--- 更新活跃销售降速事件（倒计时）
---@param project table
---@param GD table
function RE.UpdateSalesSlowdowns(project, GD)
    RE.EnsureEventFields(project)
    local re = project.randomEvents

    for i = #re.activeSalesSlowdowns, 1, -1 do
        local evt = re.activeSalesSlowdowns[i]
        evt.remainMonths = evt.remainMonths - 1
        if evt.remainMonths <= 0 then
            GD.AddEvent("【" .. project.name .. "】" .. evt.name .. "影响消退，销售恢复正常", "success")
            table.remove(re.activeSalesSlowdowns, i)
        end
    end
end

--- 计算当前销售降速总系数（多事件叠加）
--- 返回值: 0~1之间，0=完全正常，1=完全停售
---@param project table
---@return number totalSlowdown
function RE.GetSalesSlowdownFactor(project)
    if not project.randomEvents then return 0 end
    local totalSlowdown = 0
    for _, evt in ipairs(project.randomEvents.activeSalesSlowdowns) do
        totalSlowdown = totalSlowdown + evt.slowdownRate
    end
    return math.min(1.0, totalSlowdown)  -- 上限100%
end

-- ============================================================================
-- 法拍土地隐患事件
-- ============================================================================

RE.JUDICIAL_HAZARDS = {
    {
        id = "undevelopable_lien",
        name = "多重抵押查封",
        desc = "土地存在多重抵押且债权人拒绝解除，无法办理开发手续",
        probability = 0.15,  -- 法拍地15%概率
        severity = "fatal",  -- fatal=不可开发
    },
    {
        id = "undevelopable_pollution",
        name = "严重土壤污染",
        desc = "土壤检测发现重金属严重超标，治理成本超过土地价值",
        probability = 0.10,
        severity = "fatal",
    },
    {
        id = "undevelopable_heritage",
        name = "发现文保单位",
        desc = "地块下方发现不可移动文物，被列入文保名单禁止开发",
        probability = 0.08,
        severity = "fatal",
    },
    {
        id = "costly_remediation",
        name = "地下管线复杂",
        desc = "发现密集地下管线需迁改，额外成本巨大",
        probability = 0.20,
        severity = "costly",  -- costly=可开发但成本暴增
        extraCostPct = 0.25,  -- 增加25%建安成本
    },
    {
        id = "legal_dispute",
        name = "原业主上访",
        desc = "原土地使用权人持续上访阻挠施工",
        probability = 0.15,
        severity = "delay",   -- delay=长期延误
        delayMonths = {6, 18},
    },
}

--- 对法拍土地进行隐患检测（购入后首月调用一次）
---@param project table 项目数据
---@param GD table
---@return table|nil hazard 触发的隐患事件，nil=未触发
function RE.CheckJudicialHazard(project, GD)
    if not project.land then return nil end
    if project.land.channel ~= "judicial" then return nil end

    -- 已经检测过
    RE.EnsureEventFields(project)
    if project.randomEvents.judicialHazardChecked then return nil end
    project.randomEvents.judicialHazardChecked = true

    -- 逐项检测
    for _, hazard in ipairs(RE.JUDICIAL_HAZARDS) do
        if math.random() < hazard.probability then
            project.randomEvents.judicialHazard = {
                id = hazard.id,
                name = hazard.name,
                desc = hazard.desc,
                severity = hazard.severity,
                extraCostPct = hazard.extraCostPct,
                delayMonths = hazard.delayMonths,
            }

            -- 根据严重程度处理
            if hazard.severity == "fatal" then
                -- 不可开发：项目锁死
                project.status = "frozen"
                project.frozenReason = hazard.name .. "：" .. hazard.desc
                GD.AddEvent("【" .. project.name .. "】🚨 " .. hazard.name .. "！土地无法开发，资金被锁死！", "danger")
            elseif hazard.severity == "costly" then
                -- 增加成本
                local extraCost = math.floor((project.cost.buildCost or 10000) * (hazard.extraCostPct or 0.25))
                project.cost.buildCost = (project.cost.buildCost or 10000) + extraCost
                project.cost.totalCost = (project.cost.totalCost or 0) + extraCost
                GD.AddEvent("【" .. project.name .. "】⚠️ " .. hazard.name .. "！建安成本增加" .. extraCost .. "万", "warning")
            elseif hazard.severity == "delay" then
                -- 长期延误
                local delay = math.random(hazard.delayMonths[1], hazard.delayMonths[2])
                if not project.randomEvents.activeStoppages then
                    project.randomEvents.activeStoppages = {}
                end
                table.insert(project.randomEvents.activeStoppages, {
                    id = hazard.id,
                    name = hazard.name,
                    desc = hazard.desc,
                    remainMonths = delay,
                    totalDuration = delay,
                    monthlyCost = 0,
                    totalCost = 0,
                    penaltyDesc = "法律纠纷处理中",
                    startMonth = GD.totalMonths,
                })
                GD.AddEvent("【" .. project.name .. "】⚠️ " .. hazard.name .. "！预计延误" .. delay .. "个月", "warning")
            end

            -- 记录历史
            table.insert(project.randomEvents.history, {
                id = hazard.id,
                name = hazard.name,
                type = "judicial_hazard",
                month = GD.totalMonths,
                severity = hazard.severity,
            })

            return project.randomEvents.judicialHazard
        end
    end
    return nil
end

return RE
