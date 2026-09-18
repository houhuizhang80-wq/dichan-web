-- ============================================================================
-- AgencyFee.lua - 代建型项目费用管理模块
-- 政府代建 / 商业代建 的合同、里程碑、费用确认
-- ============================================================================

local DT = require("DevTypes")

local AF = {}

-- ============================================================================
-- 初始化代建数据
-- ============================================================================

--- 创建代建项目费用数据
---@param devTypeId string 开发类型ID
---@param totalInvestment number 项目总投资(万元)
---@return table|nil agency
function AF.InitAgencyData(devTypeId, totalInvestment)
    local typeDef = DT.GetType(devTypeId)
    if not typeDef or typeDef.category ~= DT.CATEGORY_AGENCY then
        return nil
    end
    local agencyConfig = typeDef.agency or {}

    -- 费率(在浮动区间内随机)
    local feeRange = agencyConfig.feeRange or {0.04, 0.06}
    local feeRate = feeRange[1] + math.random() * (feeRange[2] - feeRange[1])
    feeRate = math.floor(feeRate * 1000) / 1000 -- 保留3位小数

    -- 总管理费
    local totalFee = math.floor(totalInvestment * feeRate)

    -- 初始化里程碑
    local milestones = {}
    local configMS = agencyConfig.milestones or {}
    for i, ms in ipairs(configMS) do
        milestones[i] = {
            name = ms.name,
            triggerProgress = ms.progress,
            feePct = ms.feePct,
            feeAmount = math.floor(totalFee * ms.feePct),
            status = i == 1 and "current" or "locked",  -- 第一个里程碑直接激活
            achieved = false,
            paidAmount = 0,
        }
    end

    local data = {
        devTypeId = devTypeId,
        status = "active",         -- active/settlement/completed
        -- 合同
        contract = {
            totalInvestment = totalInvestment,
            feeRate = feeRate,
            totalFee = totalFee,
            paymentMode = agencyConfig.paymentMode or "progress",
            riskSharing = agencyConfig.riskSharing or false,
            profitSharingRate = agencyConfig.profitSharingRate or 0,
            signedMonth = 0,       -- 签约月份(由GameData设置)
        },
        -- 里程碑
        milestones = milestones,
        currentMilestoneIdx = 1,
        -- 费用
        confirmedFee = 0,          -- 已确认管理费(万元)
        paidFee = 0,               -- 已收款(万元)
        pendingFee = 0,            -- 待收款(万元)
        monthlyFeeIncome = 0,      -- 本月费用收入
        -- 超额分成(商业代建)
        profitShareEarned = 0,
        -- 审计(政府代建)
        auditCount = 0,
        lastAuditMonth = 0,
        auditPenalty = 0,
        -- 质量考核
        qualityScore = 70,
        qualityBonus = 0,
        -- 历史
        feeHistory = {},
        -- 统计
        operatingMonths = 0,
    }

    -- 首个里程碑(合同签订)立即确认
    if #milestones > 0 and milestones[1].triggerProgress == 0 then
        milestones[1].achieved = true
        milestones[1].status = "achieved"
        data.confirmedFee = milestones[1].feeAmount
        data.pendingFee = milestones[1].feeAmount
        if #milestones > 1 then
            milestones[2].status = "current"
            data.currentMilestoneIdx = 2
        end
    end

    return data
end

-- ============================================================================
-- 月度更新
-- ============================================================================

--- 月度费用处理
---@param project table 项目数据
---@param GD table 全局游戏数据
function AF.MonthlyUpdate(project, GD)
    local ag = project.agency
    if not ag or ag.status == "completed" then return end

    ag.operatingMonths = ag.operatingMonths + 1
    ag.monthlyFeeIncome = 0

    -- 检查里程碑达成
    AF.CheckMilestones(project, ag, GD)

    -- 按进度/按月收取管理费
    AF.ProcessFeePayment(project, ag, GD)

    -- 政府审计(每N个月)
    if ag.devTypeId == "gov_agency" then
        AF.HandleGovAudit(project, ag, GD)
    end

    -- 质量评分更新
    AF.UpdateQualityScore(project, ag, GD)

    -- 记录历史
    table.insert(ag.feeHistory, ag.monthlyFeeIncome)
    if #ag.feeHistory > 12 then table.remove(ag.feeHistory, 1) end

    if ag.status == "settlement" and (ag.pendingFee or 0) <= 0 then
        ag.settled = true
        ag.status = "completed"
    end
end

--- 检查里程碑达成
function AF.CheckMilestones(project, ag, GD)
    local constructionProgress = 0
    if project.construction then
        constructionProgress = (project.construction.overallProgress or 0) / 100
    end

    for i, ms in ipairs(ag.milestones) do
        if not ms.achieved and ms.status ~= "locked" then
            local triggered = false
            -- 按工程进度触发
            if ms.triggerProgress > 0 and constructionProgress >= ms.triggerProgress then
                triggered = true
            end
            -- 结算审计: 项目完成时触发
            if ms.triggerProgress >= 1.0 and
               (project.status == "settlement" or project.status == "completed") then
                triggered = true
            end

            if triggered then
                ms.achieved = true
                ms.status = "achieved"
                ag.confirmedFee = ag.confirmedFee + ms.feeAmount
                ag.pendingFee = ag.pendingFee + ms.feeAmount
                GD.AddEvent("【" .. project.name .. "】代建里程碑达成: " ..
                    ms.name .. " 确认费用" .. GD.FormatMoney(ms.feeAmount), "success")
                -- 解锁下一个
                if i < #ag.milestones then
                    ag.milestones[i + 1].status = "current"
                    ag.currentMilestoneIdx = i + 1
                end
            end
        end
    end
end

--- 处理费用支付(业主付款给我方)
function AF.ProcessFeePayment(project, ag, GD)
    if ag.pendingFee <= 0 then return end

    -- 按月分期支付待收款
    local paymentPerMonth = math.max(1, math.floor(ag.pendingFee * 0.5)) -- 每月支付50%待收
    paymentPerMonth = math.min(paymentPerMonth, ag.pendingFee)

    ag.paidFee = ag.paidFee + paymentPerMonth
    ag.pendingFee = ag.pendingFee - paymentPerMonth
    ag.monthlyFeeIncome = paymentPerMonth

    -- 收入进公司
    GD.company.cash = GD.company.cash + paymentPerMonth
    GD.company.monthlyRevenue = GD.company.monthlyRevenue + paymentPerMonth

    -- 区域公司PnL
    if project.regionalCompanyIdx then
        local rc = GD.company.regionalCompanies[project.regionalCompanyIdx]
        if rc then rc.pnl = rc.pnl + paymentPerMonth end
    end
end

--- 政府审计处理
function AF.HandleGovAudit(project, ag, GD)
    -- 每6个月审计一次
    if ag.operatingMonths - ag.lastAuditMonth < 6 then return end

    ag.lastAuditMonth = ag.operatingMonths
    ag.auditCount = ag.auditCount + 1

    -- 审计结果: 基于质量评分
    local passChance = ag.qualityScore / 100
    if math.random() < passChance then
        GD.AddEvent("【" .. project.name .. "】政府审计通过(第" .. ag.auditCount .. "次)", "success")
    else
        -- 审计不通过, 罚款
        local penalty = math.floor(ag.contract.totalFee * 0.02)
        ag.auditPenalty = ag.auditPenalty + penalty
        GD.company.cash = GD.company.cash - penalty
        GD.AddEvent("【" .. project.name .. "】政府审计发现问题! 罚款" ..
            GD.FormatMoney(penalty), "warning")
    end
end

--- 质量评分更新
function AF.UpdateQualityScore(project, ag, GD)
    -- 基于施工质量
    local constructionQuality = 70
    if project.construction and project.construction.qualityScore then
        constructionQuality = project.construction.qualityScore
    end
    -- 缓慢趋向施工质量
    ag.qualityScore = ag.qualityScore + (constructionQuality - ag.qualityScore) * 0.1
    ag.qualityScore = math.max(30, math.min(100, ag.qualityScore))

    -- 质量奖金(商业代建, 质量>80分)
    if ag.devTypeId == "com_agency" and ag.qualityScore >= 80 then
        local bonus = math.floor(ag.contract.totalFee * 0.005) -- 0.5%奖金
        if bonus > ag.qualityBonus then
            local extra = bonus - ag.qualityBonus
            ag.qualityBonus = bonus
            GD.company.cash = GD.company.cash + extra
            GD.AddEvent("【" .. project.name .. "】质量考核优秀, 获得奖金" ..
                GD.FormatMoney(extra), "success")
        end
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

--- 项目结算(竣工后调用)
---@param project table
---@param GD table
function AF.SettleProject(project, GD)
    local ag = project.agency
    if not ag then return end

    ag.status = "settlement"

    -- 确认所有未达成的里程碑
    for _, ms in ipairs(ag.milestones) do
        if not ms.achieved then
            ms.achieved = true
            ms.status = "achieved"
            ag.confirmedFee = ag.confirmedFee + ms.feeAmount
            ag.pendingFee = ag.pendingFee + ms.feeAmount
        end
    end

    -- 商业代建: 超额利润分成
    if ag.devTypeId == "com_agency" and ag.contract.riskSharing then
        local projectProfit = (project.sales and project.sales.revenue or 0) - (project.cost and project.cost.totalCost or 0)
        local profitRate = ag.contract.totalInvestment > 0 and (projectProfit / ag.contract.totalInvestment) or 0
        local threshold = 0.10 -- 10%基准利润率
        if profitRate > threshold then
            local excessProfit = (profitRate - threshold) * ag.contract.totalInvestment
            local share = math.floor(excessProfit * (ag.contract.profitSharingRate or 0.20))
            ag.profitShareEarned = share
            GD.company.cash = GD.company.cash + share
            GD.AddEvent("【" .. project.name .. "】代建超额分成: " ..
                GD.FormatMoney(share), "success")
        end
    end

    GD.AddEvent("【" .. project.name .. "】代建项目进入结算阶段", "info")
end

--- 完成结算
---@param project table
function AF.CompleteSettlement(project)
    local ag = project.agency
    if not ag then return end
    ag.status = "completed"
    ag.settled = true
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取费用计划概览
---@param project table
---@return table
function AF.GetFeeSchedule(project)
    local ag = project.agency
    if not ag then return {} end
    return {
        totalFee = ag.contract.totalFee,
        feeRate = ag.contract.feeRate,
        confirmedFee = ag.confirmedFee,
        paidFee = ag.paidFee,
        pendingFee = ag.pendingFee,
        profitShare = ag.profitShareEarned,
        qualityBonus = ag.qualityBonus,
        auditPenalty = ag.auditPenalty,
        netIncome = ag.paidFee + ag.profitShareEarned + ag.qualityBonus - ag.auditPenalty,
    }
end

--- 获取里程碑列表
---@param project table
---@return table[]
function AF.GetMilestones(project)
    local ag = project.agency
    if not ag then return {} end
    return ag.milestones
end

--- 获取合同信息
---@param project table
---@return table
function AF.GetContractInfo(project)
    local ag = project.agency
    if not ag then return {} end
    return {
        totalInvestment = ag.contract.totalInvestment,
        feeRate = math.floor(ag.contract.feeRate * 1000) / 10 .. "%",
        totalFee = ag.contract.totalFee,
        paymentMode = ag.contract.paymentMode == "progress" and "按进度" or "按里程碑",
        riskSharing = ag.contract.riskSharing and "是" or "否",
        profitSharingRate = ag.contract.profitSharingRate > 0
            and (math.floor(ag.contract.profitSharingRate * 100) .. "%") or "无",
    }
end

--- 获取代建简报
---@param project table
---@return table
function AF.GetSummary(project)
    local ag = project.agency
    if not ag then return {} end
    local achievedCount = 0
    for _, ms in ipairs(ag.milestones) do
        if ms.achieved then achievedCount = achievedCount + 1 end
    end
    return {
        status = ag.status == "active" and "执行中"
            or ag.status == "settlement" and "结算中"
            or "已完成",
        feeRate = ag.contract.feeRate,
        totalFee = ag.contract.totalFee,
        paidFee = ag.paidFee,
        progress = #ag.milestones > 0 and math.floor(achievedCount / #ag.milestones * 100) or 0,
        qualityScore = math.floor(ag.qualityScore),
        operatingMonths = ag.operatingMonths,
    }
end

-- ============================================================================
-- 向后兼容
-- ============================================================================

--- 确保代建字段存在
---@param ag table|nil
---@return table|nil
function AF.EnsureAgencyFields(ag)
    if not ag then return nil end
    ag.status = ag.status or "active"
    if not ag.contract then
        ag.contract = {totalInvestment=0, feeRate=0.04, totalFee=0,
            paymentMode="progress", riskSharing=false, profitSharingRate=0, signedMonth=0}
    end
    ag.milestones = ag.milestones or {}
    ag.currentMilestoneIdx = ag.currentMilestoneIdx or 1
    ag.confirmedFee = ag.confirmedFee or 0
    ag.paidFee = ag.paidFee or 0
    ag.pendingFee = ag.pendingFee or 0
    ag.monthlyFeeIncome = ag.monthlyFeeIncome or 0
    ag.settled = ag.settled or ag.status == "completed"
    ag.profitShareEarned = ag.profitShareEarned or 0
    ag.auditCount = ag.auditCount or 0
    ag.lastAuditMonth = ag.lastAuditMonth or 0
    ag.auditPenalty = ag.auditPenalty or 0
    ag.qualityScore = ag.qualityScore or 70
    ag.qualityBonus = ag.qualityBonus or 0
    ag.feeHistory = ag.feeHistory or {}
    ag.operatingMonths = ag.operatingMonths or 0
    return ag
end

return AF
