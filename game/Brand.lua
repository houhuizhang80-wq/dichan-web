-- ============================================================================
-- Brand.lua - 品牌与声誉系统 (12.1~12.3)
-- 品牌价值模型 / 社交媒体舆情 / 社会责任
-- ============================================================================

local BR = {}

-- ============================================================================
-- 常量定义
-- ============================================================================

-- 品牌四维度及权重
BR.DIMENSIONS = {
    {id = "productQuality",  name = "产品品质",   weight = 0.30},
    {id = "deliverySatisfy", name = "交付满意度", weight = 0.25},
    {id = "socialResp",      name = "社会责任",   weight = 0.25},
    {id = "mediaSentiment",  name = "媒体舆情",   weight = 0.20},
}

-- 社交媒体平台
BR.PLATFORMS = {
    {id = "douyin",      name = "抖房",   viralThreshold = 10000, spreadFactor = 1.5},
    {id = "xiaohongshu", name = "小红房",  viralThreshold = 5000,  spreadFactor = 1.2},
    {id = "weibo",       name = "房博",   viralThreshold = 8000,  spreadFactor = 1.8},
}

-- 社会责任活动
BR.CSR_EVENTS = {
    {id = "poverty",    name = "精准扶贫",   cost = 500,  brandBoost = 3,  govBoost = 5,  desc = "帮扶贫困村庄基础设施建设"},
    {id = "school",     name = "捐建学校",   cost = 1000, brandBoost = 5,  govBoost = 8,  desc = "援建希望小学，资助师资力量"},
    {id = "disaster",   name = "抗灾救助",   cost = 800,  brandBoost = 8,  govBoost = 10, desc = "向灾区捐款捐物，参与重建"},
    {id = "greenBuild", name = "绿色建筑",   cost = 600,  brandBoost = 4,  govBoost = 3,  desc = "推广绿色节能建筑标准"},
    {id = "community",  name = "社区公益",   cost = 300,  brandBoost = 2,  govBoost = 2,  desc = "赞助社区活动、修缮公共设施"},
}

-- 危机事件（由外部模块触发或月度检测）
BR.CRISIS_EVENTS = {
    {id = "safety_accident", name = "安全事故",   brandLoss = 15, creditLoss = 5,  duration = 6,  desc = "工地安全事故造成人员伤亡"},
    {id = "mass_complaint",  name = "业主群诉",   brandLoss = 10, creditLoss = 3,  duration = 4,  desc = "大量业主集体投诉维权"},
    {id = "unfinished",      name = "楼盘烂尾",   brandLoss = 25, creditLoss = 10, duration = 12, desc = "项目停工烂尾，社会影响恶劣"},
    {id = "quality_defect",  name = "质量缺陷",   brandLoss = 8,  creditLoss = 2,  duration = 3,  desc = "交付房屋出现严重质量问题"},
}

-- 公关手段
BR.PR_ACTIONS = {
    {id = "statement",   name = "发布声明",   cost = 100,  recoveryRate = 0.30, cooldown = 2, desc = "官方声明回应舆论关切"},
    {id = "apology",     name = "公开道歉",   cost = 200,  recoveryRate = 0.60, cooldown = 3, desc = "高管公开致歉并承诺整改"},
    {id = "compensate",  name = "赔偿方案",   cost = 500,  recoveryRate = 0.80, cooldown = 1, desc = "制定赔偿方案，实际解决问题"},
}

-- 帖子模板
local POST_TEMPLATES = {
    positive = {
        "入住%s小区三个月了，质量真心不错！ 👍",
        "%s的园林设计太赞了，每天下班回来心情都好",
        "不得不说%s的物业服务确实到位，推荐！",
        "朋友来我家(%s)都说装修品质高，有面子",
        "感谢%s准时交房，没有延期！",
    },
    negative = {
        "%s交房快一年了，墙面还在掉皮 😡",
        "千万别买%s！承诺的配套全部没兑现",
        "%s的房子漏水严重，开发商推诿不管",
        "后悔买了%s，质量差价格高，血亏",
        "%s延期交房半年了还没消息，维权中...",
    },
    csr = {
        "%s地产向灾区捐赠%d万元，企业担当！",
        "%s出资援建希望小学，为孩子们点赞！",
        "%s推动绿色建筑标准，行业标杆",
        "看到%s参与精准扶贫的报道，好感度拉满",
    },
    crisis = {
        "刚看到新闻！%s工地出了安全事故，太可怕了",
        "%s又上热搜了…业主集体维权，场面很大",
        "天哪%s那个项目真的烂尾了？买了的人怎么办",
        "%s交的房质量也太差了吧，朋友家地板全鼓了",
    },
}

-- ============================================================================
-- 数据初始化
-- ============================================================================

function BR.InitBrandData()
    return {
        score = 50,                -- 品牌总分 [0,100]
        dimensions = {
            productQuality  = 50,  -- 产品品质 [0,100]
            deliverySatisfy = 50,  -- 交付满意度 [0,100]
            socialResp      = 0,   -- 社会责任 [0,100]
            mediaSentiment  = 50,  -- 媒体舆情 [0,100]
        },
        premiumRate  = 0,          -- 当前品牌溢价率
        landBidBonus = 0,          -- 拿地评分加分

        govFavor = 0,              -- 政府好感度 [0,100]

        posts    = {},             -- 社交媒体帖子 (最近50条)
        hotNews  = {},             -- 热点新闻 (点赞过万)

        csrHistory   = {},         -- 公益活动历史
        activeCrisis = nil,        -- 当前危机 {id, name, brandLoss, monthsLeft, originalLoss}
        prCooldown   = 0,          -- 公关冷却剩余月数
    }
end

function BR.EnsureBrandFields(brand)
    if not brand then return BR.InitBrandData() end
    if not brand.dimensions then
        brand.dimensions = {productQuality=50, deliverySatisfy=50, socialResp=0, mediaSentiment=50}
    end
    if brand.score == nil then brand.score = 50 end
    if brand.premiumRate == nil then brand.premiumRate = 0 end
    if brand.landBidBonus == nil then brand.landBidBonus = 0 end
    if brand.govFavor == nil then brand.govFavor = 0 end
    if not brand.posts then brand.posts = {} end
    if not brand.hotNews then brand.hotNews = {} end
    if not brand.csrHistory then brand.csrHistory = {} end
    if brand.prCooldown == nil then brand.prCooldown = 0 end
    return brand
end

-- ============================================================================
-- 内部工具函数
-- ============================================================================

local function _Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function _RandPick(arr)
    return arr[math.random(1, #arr)]
end

local function _CompanyName(GD)
    return GD.company.name or "本公司"
end

-- ============================================================================
-- 月度更新：自动生成帖子
-- ============================================================================

local function _GeneratePosts(GD)
    local brand = GD.brand
    local compName = _CompanyName(GD)
    local newPosts = {}

    -- 1) 基于项目状态生成帖子
    for _, p in ipairs(GD.projects) do
        if p.status == "delivery" or p.status == "completed" then
            local q = (p.construction and p.construction.quality) or 70
            if q >= 90 and math.random() < 0.5 then
                -- 高品质 → 正面帖
                local tmpl = _RandPick(POST_TEMPLATES.positive)
                table.insert(newPosts, {
                    text = string.format(tmpl, p.name or compName),
                    platform = _RandPick(BR.PLATFORMS).id,
                    sentiment = "positive",
                    likes = math.random(500, 8000),
                    month = GD.totalMonths,
                })
            elseif q < 70 and math.random() < 0.6 then
                -- 低品质 → 负面帖
                local tmpl = _RandPick(POST_TEMPLATES.negative)
                table.insert(newPosts, {
                    text = string.format(tmpl, p.name or compName),
                    platform = _RandPick(BR.PLATFORMS).id,
                    sentiment = "negative",
                    likes = math.random(1000, 15000),
                    month = GD.totalMonths,
                })
            end
        end
    end

    -- 2) 危机期间额外生成2-3条负面帖
    if brand.activeCrisis then
        local crisisCount = math.random(2, 3)
        for _ = 1, crisisCount do
            local tmpl = _RandPick(POST_TEMPLATES.crisis)
            table.insert(newPosts, {
                text = string.format(tmpl, compName),
                platform = _RandPick(BR.PLATFORMS).id,
                sentiment = "negative",
                likes = math.random(5000, 30000),
                month = GD.totalMonths,
            })
        end
    end

    -- 3) 无帖子时也有少量自然帖
    if #newPosts == 0 and math.random() < 0.3 then
        local tmpl = _RandPick(POST_TEMPLATES.positive)
        table.insert(newPosts, {
            text = string.format(tmpl, compName),
            platform = _RandPick(BR.PLATFORMS).id,
            sentiment = "positive",
            likes = math.random(200, 3000),
            month = GD.totalMonths,
        })
    end

    -- 检测爆款（点赞超过平台阈值 → 热点新闻）
    for _, post in ipairs(newPosts) do
        for _, plat in ipairs(BR.PLATFORMS) do
            if post.platform == plat.id and post.likes >= plat.viralThreshold then
                post.isViral = true
                table.insert(brand.hotNews, {
                    text = post.text,
                    platform = plat.name,
                    likes = post.likes,
                    sentiment = post.sentiment,
                    month = GD.totalMonths,
                })
                -- 热点放大效果
                post.likes = math.floor(post.likes * plat.spreadFactor)
                if post.sentiment == "negative" then
                    GD.AddEvent("【舆情危机】" .. plat.name .. "出现热点负面帖：" .. post.text, "danger")
                else
                    GD.AddEvent("【品牌热点】" .. plat.name .. "出现爆款好评帖！", "success")
                end
                break
            end
        end
        table.insert(brand.posts, post)
    end

    -- 保留最近50条帖子
    while #brand.posts > 50 do
        table.remove(brand.posts, 1)
    end
    -- 保留最近20条热点
    while #brand.hotNews > 20 do
        table.remove(brand.hotNews, 1)
    end
end

-- ============================================================================
-- 月度更新：计算媒体舆情分
-- ============================================================================

local function _UpdateSentiment(GD)
    local brand = GD.brand
    -- 取最近12条帖子计算正面占比
    local recentCount = math.min(#brand.posts, 12)
    if recentCount == 0 then
        brand.dimensions.mediaSentiment = 50
        return
    end
    local positiveCount = 0
    for i = #brand.posts - recentCount + 1, #brand.posts do
        if brand.posts[i].sentiment == "positive" then
            positiveCount = positiveCount + 1
        end
    end
    local ratio = positiveCount / recentCount
    brand.dimensions.mediaSentiment = _Clamp(math.floor(ratio * 100), 0, 100)
end

-- ============================================================================
-- 月度更新：计算产品品质维度（从项目质量汇总）
-- ============================================================================

local function _UpdateProductQuality(GD)
    local brand = GD.brand
    local totalQ = 0
    local count = 0
    for _, p in ipairs(GD.projects) do
        if p.construction and p.construction.quality then
            totalQ = totalQ + p.construction.quality
            count = count + 1
        end
    end
    if count > 0 then
        brand.dimensions.productQuality = _Clamp(math.floor(totalQ / count), 0, 100)
    end
end

-- ============================================================================
-- 月度更新：计算交付满意度（已交付项目的平均质量+售后）
-- ============================================================================

local function _UpdateDeliverySatisfy(GD)
    local brand = GD.brand
    local totalSat = 0
    local count = 0
    for _, p in ipairs(GD.projects) do
        if p.status == "delivery" or p.status == "completed" then
            local q = (p.construction and p.construction.quality) or 70
            -- 延期扣分: 超期每月-5
            local delay = 0
            if p.actualDeliveryMonth and p.plannedDeliveryMonth then
                delay = math.max(0, p.actualDeliveryMonth - p.plannedDeliveryMonth)
            end
            local sat = _Clamp(q - delay * 5, 0, 100)
            totalSat = totalSat + sat
            count = count + 1
        end
    end
    if count > 0 then
        brand.dimensions.deliverySatisfy = _Clamp(math.floor(totalSat / count), 0, 100)
    end
end

-- ============================================================================
-- 月度更新：四维度加权计算品牌总分
-- ============================================================================

local function _CalcBrandScore(GD)
    local brand = GD.brand
    local score = 0
    for _, dim in ipairs(BR.DIMENSIONS) do
        score = score + (brand.dimensions[dim.id] or 0) * dim.weight
    end

    -- 危机惩罚：当前有危机时持续扣分
    if brand.activeCrisis then
        local crisis = brand.activeCrisis
        local monthlyLoss = crisis.originalLoss / math.max(1, crisis.totalDuration or 6)
        score = score - monthlyLoss
        crisis.monthsLeft = crisis.monthsLeft - 1
        if crisis.monthsLeft <= 0 then
            GD.AddEvent("【品牌恢复】" .. crisis.name .. "的影响已逐渐消退", "info")
            brand.activeCrisis = nil
        end
    end

    -- 公关冷却递减
    if brand.prCooldown > 0 then
        brand.prCooldown = brand.prCooldown - 1
    end

    -- 政府好感度自然衰减
    brand.govFavor = _Clamp(brand.govFavor - 1, 0, 100)

    brand.score = _Clamp(math.floor(score), 0, 100)
end

-- ============================================================================
-- 月度更新：品牌效果（溢价率 + 拿地加分）
-- ============================================================================

local function _ApplyBrandEffects(GD)
    local brand = GD.brand
    local s = brand.score

    -- 溢价率: [0,40)→0%, [40,60)→0~3%, [60,80)→3~6%, [80,100]→6~10%
    if s < 40 then
        brand.premiumRate = 0
    elseif s < 60 then
        brand.premiumRate = (s - 40) / 20 * 0.03
    elseif s < 80 then
        brand.premiumRate = 0.03 + (s - 60) / 20 * 0.03
    else
        brand.premiumRate = 0.06 + (s - 80) / 20 * 0.04
    end

    -- 拿地加分: 品牌分 80+ 时 +5~10
    if s >= 80 then
        brand.landBidBonus = 5 + math.floor((s - 80) / 4)
    elseif s >= 60 then
        brand.landBidBonus = math.floor((s - 60) / 10)
    else
        brand.landBidBonus = 0
    end
end

-- ============================================================================
-- 月度更新：检测危机事件
-- ============================================================================

local function _CheckCrisisEvents(GD)
    local brand = GD.brand
    if brand.activeCrisis then return end  -- 已有危机则不叠加

    for _, p in ipairs(GD.projects) do
        -- 检测烂尾：建设中项目现金不足导致停工
        if p.status == "construction" and GD.company.cash < 0 then
            if math.random() < 0.15 then
                BR.TriggerCrisis(GD, "unfinished")
                return
            end
        end
        -- 检测质量缺陷：交付项目质量过低
        if (p.status == "delivery" or p.status == "completed") then
            local q = (p.construction and p.construction.quality) or 70
            if q < 60 and math.random() < 0.20 then
                BR.TriggerCrisis(GD, "quality_defect")
                return
            end
        end
        -- 检测安全事故：建设中项目 + 质量风险高
        if p.status == "construction" then
            local qRisk = GD.company.traitEffects and GD.company.traitEffects.qualityRisk or 0
            local complianceRisk = GD.company.traitEffects and GD.company.traitEffects.complianceRisk or 0
            local executiveRiskReduction = 0
            if GD.company.governance and GD.company.governance.executives
                and GD.company.governance.executives.clo
            then
                executiveRiskReduction = 0.10
            end
            local effectiveRisk = math.max(0, qRisk + complianceRisk - executiveRiskReduction)
            if effectiveRisk > 0 and math.random() < effectiveRisk * 0.05 then
                BR.TriggerCrisis(GD, "safety_accident")
                return
            end
        end
    end
end

-- ============================================================================
-- 月度总入口
-- ============================================================================

function BR.MonthlyUpdate(GD)
    if not GD.brand then return end
    _UpdateProductQuality(GD)
    _UpdateDeliverySatisfy(GD)
    _GeneratePosts(GD)
    _UpdateSentiment(GD)
    _CalcBrandScore(GD)
    _ApplyBrandEffects(GD)
    _CheckCrisisEvents(GD)
end

-- ============================================================================
-- 玩家操作：社会责任活动
-- ============================================================================

function BR.DoCSR(GD, eventId)
    if not GD.brand then return false, "品牌系统未初始化" end

    local csrDef = nil
    for _, e in ipairs(BR.CSR_EVENTS) do
        if e.id == eventId then csrDef = e; break end
    end
    if not csrDef then return false, "未知的公益活动" end

    if GD.company.cash < csrDef.cost then
        return false, "资金不足，需要" .. csrDef.cost .. "万元"
    end

    GD.company.cash = GD.company.cash - csrDef.cost
    local brand = GD.brand
    brand.dimensions.socialResp = _Clamp(brand.dimensions.socialResp + csrDef.brandBoost * 3, 0, 100)
    brand.govFavor = _Clamp(brand.govFavor + csrDef.govBoost, 0, 100)

    table.insert(brand.csrHistory, {
        id = eventId,
        name = csrDef.name,
        cost = csrDef.cost,
        month = GD.totalMonths,
        year = GD.year,
    })

    -- 生成正面帖子
    local compName = _CompanyName(GD)
    local tmpl = _RandPick(POST_TEMPLATES.csr)
    table.insert(brand.posts, {
        text = string.format(tmpl, compName, csrDef.cost),
        platform = _RandPick(BR.PLATFORMS).id,
        sentiment = "positive",
        likes = math.random(3000, 20000),
        month = GD.totalMonths,
    })

    GD.AddEvent("【社会责任】" .. csrDef.name .. "，投入" .. csrDef.cost .. "万元", "success")
    return true
end

-- ============================================================================
-- 玩家操作：公关应对
-- ============================================================================

function BR.DoPR(GD, actionId)
    if not GD.brand then return false, "品牌系统未初始化" end
    local brand = GD.brand

    if not brand.activeCrisis then
        return false, "当前没有需要公关应对的危机"
    end
    if brand.prCooldown > 0 then
        return false, "公关冷却中，还需" .. brand.prCooldown .. "个月"
    end

    local prDef = nil
    for _, a in ipairs(BR.PR_ACTIONS) do
        if a.id == actionId then prDef = a; break end
    end
    if not prDef then return false, "未知的公关操作" end

    if GD.company.cash < prDef.cost then
        return false, "资金不足，需要" .. prDef.cost .. "万元"
    end

    GD.company.cash = GD.company.cash - prDef.cost
    brand.prCooldown = prDef.cooldown

    -- 恢复品牌分
    local crisis = brand.activeCrisis
    local recovered = math.floor(crisis.originalLoss * prDef.recoveryRate)
    brand.score = _Clamp(brand.score + recovered, 0, 100)
    -- 缩短危机持续时间
    crisis.monthsLeft = math.max(0, crisis.monthsLeft - math.floor(crisis.monthsLeft * prDef.recoveryRate))

    if crisis.monthsLeft <= 0 then
        GD.AddEvent("【公关成功】" .. prDef.name .. "有效化解了" .. crisis.name .. "危机！", "success")
        brand.activeCrisis = nil
    else
        GD.AddEvent("【公关应对】" .. prDef.name .. "部分缓解了舆论压力，危机还需" .. crisis.monthsLeft .. "个月消退", "info")
    end
    return true
end

-- ============================================================================
-- 外部触发危机
-- ============================================================================

function BR.TriggerCrisis(GD, crisisType)
    if not GD.brand then return end
    local brand = GD.brand
    if brand.activeCrisis then return end  -- 不叠加

    local def = nil
    for _, c in ipairs(BR.CRISIS_EVENTS) do
        if c.id == crisisType then def = c; break end
    end
    if not def then return end

    brand.activeCrisis = {
        id = def.id,
        name = def.name,
        originalLoss = def.brandLoss,
        brandLoss = def.brandLoss,
        monthsLeft = def.duration,
        totalDuration = def.duration,
    }
    brand.score = _Clamp(brand.score - def.brandLoss, 0, 100)

    -- 信用影响
    if GD.company.credit then
        GD.company.credit = _Clamp(GD.company.credit - def.creditLoss, 0, 100)
    end

    GD.AddEvent("【品牌危机】" .. def.name .. "！品牌分-" .. def.brandLoss .. "，信用-" .. def.creditLoss, "danger")
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function BR.GetBrandSummary(GD)
    if not GD.brand then return nil end
    local brand = GD.brand
    return {
        score = brand.score,
        premiumRate = brand.premiumRate,
        landBidBonus = brand.landBidBonus,
        govFavor = brand.govFavor,
        hasCrisis = brand.activeCrisis ~= nil,
        crisisName = brand.activeCrisis and brand.activeCrisis.name or nil,
        postCount = #brand.posts,
        hotNewsCount = #brand.hotNews,
        csrCount = #brand.csrHistory,
    }
end

return BR
