-- ============================================================================
-- PersonalLife.lua - 个人生活方式系统
-- 金额单位：万元。仅管理 GD.player.personalLife 与个人字段（player.cash）。
-- 不读取、不写入任何公司数据。
-- ============================================================================

local PersonalLife = {}
local PFE = require("PersonalFinanceEcosystem")

local VERSION = 1
local HISTORY_LIMIT = 160
local MAX_RECORDS = 80

local DIMENSION_KEYS = {"wealth", "consumption", "circle", "charity", "growth"}
local CATEGORY_TYPES = {
    asset = "asset",
    health = "service",
    education = "course",
    social = "activity",
    charity = "pledge",
}

local function item(id, name, desc, category, price, monthly, effects, extra)
    extra = extra or {}
    return {
        id = id,
        name = name,
        desc = desc,
        category = category,
        price = price,
        monthly = monthly,
        effects = effects,
        type = extra.type or CATEGORY_TYPES[category],
        resaleRatio = extra.resaleRatio,
        depreciation = extra.depreciation,
        duration = extra.duration,
    }
end

--- 固定目录：五类各十项，恰好 50 项。
PersonalLife.ITEMS = {
    -- asset：私人资产
    item("classic_watch", "经典机械腕表", "适合正式商务场合的私人收藏腕表。", "asset", 18, 0, {wealth = 2, consumption = 3, circle = 2, charity = 0, growth = 0}, {resaleRatio = 0.62, depreciation = 0.999}),
    item("executive_sedan", "行政轿车", "兼顾通勤舒适度与正式接待需求。", "asset", 42, 0, {wealth = 3, consumption = 5, circle = 3, charity = 0, growth = 0}, {resaleRatio = 0.55, depreciation = 0.985}),
    item("art_collection", "当代艺术藏品", "经鉴定入藏的当代艺术作品。", "asset", 75, 0, {wealth = 6, consumption = 4, circle = 4, charity = 0, growth = 1}, {resaleRatio = 0.68, depreciation = 1.001}),
    item("grand_piano", "三角钢琴", "用于家庭音乐会与长期艺术培养。", "asset", 28, 0, {wealth = 2, consumption = 4, circle = 2, charity = 0, growth = 3}, {resaleRatio = 0.50, depreciation = 0.992}),
    item("wine_cellar", "私人酒窖", "适合小型私宴与珍藏葡萄酒管理。", "asset", 36, 0, {wealth = 3, consumption = 5, circle = 4, charity = 0, growth = 1}, {resaleRatio = 0.58, depreciation = 0.997}),
    item("sailing_boat", "近海帆船", "可用于家庭休闲与客户接待的近海帆船。", "asset", 120, 0, {wealth = 5, consumption = 7, circle = 6, charity = 0, growth = 1}, {resaleRatio = 0.48, depreciation = 0.980}),
    item("heritage_jewelry", "传承珠宝", "具备保存价值的私人珠宝组合。", "asset", 95, 0, {wealth = 7, consumption = 5, circle = 4, charity = 0, growth = 0}, {resaleRatio = 0.70, depreciation = 1.000}),
    item("rare_books", "珍本书库", "围绕商业、历史与艺术建立的私人书库。", "asset", 24, 0, {wealth = 2, consumption = 2, circle = 2, charity = 0, growth = 6}, {resaleRatio = 0.65, depreciation = 1.000}),
    item("offroad_vehicle", "越野旅行车", "用于长途自驾和户外活动的私人车辆。", "asset", 55, 0, {wealth = 3, consumption = 6, circle = 3, charity = 0, growth = 2}, {resaleRatio = 0.52, depreciation = 0.982}),
    item("collector_camera", "收藏级相机", "用于旅行记录与影像创作的专业相机。", "asset", 16, 0, {wealth = 1, consumption = 3, circle = 2, charity = 0, growth = 4}, {resaleRatio = 0.60, depreciation = 0.990}),

    -- health：健康服务
    item("family_doctor", "家庭医生服务", "提供日常健康咨询与年度风险管理。", "health", 4, 1.2, {wealth = 0, consumption = 2, circle = 0, charity = 0, growth = 2}),
    item("fitness_coach", "私教训练计划", "以体能、姿态和习惯为目标的定制训练。", "health", 2, 0.8, {wealth = 0, consumption = 3, circle = 1, charity = 0, growth = 3}),
    item("nutrition_program", "营养管理方案", "营养师跟踪的膳食与作息改善计划。", "health", 1.5, 0.6, {wealth = 0, consumption = 2, circle = 0, charity = 0, growth = 3}),
    item("mental_wellness", "心理健康咨询", "定期心理咨询与压力恢复支持。", "health", 2.5, 0.9, {wealth = 0, consumption = 2, circle = 0, charity = 0, growth = 4}),
    item("preventive_screening", "高端体检管理", "覆盖重要指标的预防性筛查与复诊提醒。", "health", 8, 0.4, {wealth = 0, consumption = 3, circle = 0, charity = 0, growth = 3}),
    item("sleep_clinic", "睡眠修复服务", "针对睡眠质量与恢复节律的长期改善。", "health", 3, 0.7, {wealth = 0, consumption = 2, circle = 0, charity = 0, growth = 4}),
    item("sports_recovery", "运动康复服务", "运动损伤预防和柔韧性维护服务。", "health", 2, 0.7, {wealth = 0, consumption = 3, circle = 0, charity = 0, growth = 3}),
    item("dental_care", "口腔健康会员", "涵盖检查、洁牙和长期口腔保健。", "health", 1.8, 0.5, {wealth = 0, consumption = 2, circle = 1, charity = 0, growth = 2}),
    item("health_retreat", "年度健康疗愈", "每月预存的高品质健康休整计划。", "health", 6, 0.9, {wealth = 0, consumption = 4, circle = 1, charity = 0, growth = 4}),
    item("senior_care_plan", "家庭健康守护", "为家庭成员建立的健康风险咨询与协调服务。", "health", 3.5, 1.0, {wealth = 0, consumption = 2, circle = 1, charity = 1, growth = 3}),

    -- education：进修成长
    item("mba_program", "在职 MBA 课程", "系统训练战略、组织与资本管理能力。", "education", 32, 0, {wealth = 2, consumption = 1, circle = 5, charity = 0, growth = 9}, {duration = 18}),
    item("board_governance", "董事会治理研修", "聚焦董事会职责、风险与治理结构。", "education", 12, 0, {wealth = 1, consumption = 1, circle = 4, charity = 0, growth = 7}, {duration = 6}),
    item("real_estate_finance", "房地产金融进修", "学习地产融资、估值与资产证券化。", "education", 10, 0, {wealth = 4, consumption = 0, circle = 3, charity = 0, growth = 8}, {duration = 6}),
    item("public_speaking", "公众表达训练", "提升演讲、媒体沟通和临场表达能力。", "education", 5, 0, {wealth = 0, consumption = 1, circle = 5, charity = 0, growth = 6}, {duration = 4}),
    item("leadership_lab", "领导力实验室", "通过案例与反馈训练团队领导能力。", "education", 9, 0, {wealth = 1, consumption = 1, circle = 4, charity = 0, growth = 8}, {duration = 5}),
    item("family_office_course", "家族办公室课程", "学习家族财富治理、传承和慈善架构。", "education", 16, 0, {wealth = 5, consumption = 1, circle = 3, charity = 3, growth = 8}, {duration = 8}),
    item("digital_transformation", "数字化转型课程", "建立数字业务、数据治理与技术战略视野。", "education", 8, 0, {wealth = 2, consumption = 1, circle = 2, charity = 0, growth = 8}, {duration = 5}),
    item("art_history", "艺术史私塾", "通过系统艺术史学习提升审美与文化素养。", "education", 6, 0, {wealth = 0, consumption = 2, circle = 3, charity = 0, growth = 6}, {duration = 6}),
    item("law_compliance", "法律合规进修", "掌握商业合同、合规与风险控制基础。", "education", 7, 0, {wealth = 2, consumption = 0, circle = 2, charity = 0, growth = 7}, {duration = 5}),
    item("sustainable_development", "可持续发展研修", "理解 ESG、公共价值与长期责任经营。", "education", 8, 0, {wealth = 1, consumption = 1, circle = 3, charity = 4, growth = 7}, {duration = 6}),

    -- social：圈层活动
    item("business_dinner", "行业私宴", "与行业伙伴进行小范围深度交流。", "social", 1.5, 0, {wealth = 0, consumption = 3, circle = 4, charity = 0, growth = 1}),
    item("club_membership", "城市会所入会", "取得城市会所的年度会员资格。", "social", 12, 0, {wealth = 1, consumption = 5, circle = 7, charity = 0, growth = 1}),
    item("industry_association", "行业协会年会", "参与行业协会年会并拓展专业联系。", "social", 3, 0, {wealth = 0, consumption = 2, circle = 5, charity = 0, growth = 3}),
    item("golf_membership", "高尔夫邀请赛", "在邀请赛中开展轻松商务社交。", "social", 6, 0, {wealth = 0, consumption = 5, circle = 6, charity = 0, growth = 1}),
    item("wine_tasting", "精品品鉴会", "围绕精品酒与文化主题的社交活动。", "social", 2.5, 0, {wealth = 0, consumption = 4, circle = 4, charity = 0, growth = 1}),
    item("alumni_forum", "校友领袖论坛", "参与校友网络的主题论坛和闭门交流。", "social", 2, 0, {wealth = 0, consumption = 2, circle = 5, charity = 0, growth = 3}),
    item("city_salon", "城市发展沙龙", "与城市发展相关人士交流公共议题。", "social", 1, 0, {wealth = 0, consumption = 1, circle = 4, charity = 1, growth = 3}),
    item("cultural_gala", "文化慈善晚宴", "参与文化机构举办的年度慈善晚宴。", "social", 5, 0, {wealth = 0, consumption = 4, circle = 5, charity = 3, growth = 1}),
    item("investor_roundtable", "投资人圆桌会", "和专业投资人交换市场观点与合作机会。", "social", 3.5, 0, {wealth = 2, consumption = 2, circle = 6, charity = 0, growth = 4}),
    item("outdoor_retreat", "企业家户外行", "低压力环境下的企业家交流与协作活动。", "social", 4, 0, {wealth = 0, consumption = 4, circle = 5, charity = 0, growth = 3}),

    -- charity：公益项目
    item("education_grant", "助学基金认捐", "持续支持教育资源不足地区的学生。", "charity", 3, 0.8, {wealth = 0, consumption = 1, circle = 2, charity = 8, growth = 3}),
    item("rural_health", "乡村医疗支持", "为基层医疗服务提供持续资助。", "charity", 4, 1.0, {wealth = 0, consumption = 1, circle = 1, charity = 9, growth = 2}),
    item("environmental_protection", "生态保护计划", "资助生态修复与环境教育项目。", "charity", 2.5, 0.7, {wealth = 0, consumption = 1, circle = 2, charity = 7, growth = 3}),
    item("elderly_meals", "长者助餐项目", "为社区长者提供稳定的助餐支持。", "charity", 1.5, 0.5, {wealth = 0, consumption = 1, circle = 1, charity = 7, growth = 2}),
    item("disaster_relief", "灾害应急认捐", "加入灾害发生时可快速响应的应急捐赠计划。", "charity", 5, 1.2, {wealth = 0, consumption = 1, circle = 2, charity = 9, growth = 2}),
    item("arts_sponsorship", "青年艺术扶持", "为青年艺术创作者提供创作资助。", "charity", 3, 0.6, {wealth = 0, consumption = 2, circle = 3, charity = 7, growth = 3}),
    item("community_library", "社区图书馆共建", "共同建设开放的社区阅读空间。", "charity", 2, 0.5, {wealth = 0, consumption = 1, circle = 2, charity = 7, growth = 4}),
    item("special_education", "特殊教育援助", "支持特殊需要儿童的教育和康复服务。", "charity", 4.5, 0.9, {wealth = 0, consumption = 1, circle = 1, charity = 9, growth = 3}),
    item("youth_sports", "青少年体育计划", "支持青少年体育设施和训练机会。", "charity", 2, 0.5, {wealth = 0, consumption = 1, circle = 2, charity = 6, growth = 3}),
    item("heritage_preservation", "文化遗产守护", "支持本地文化遗产的修缮与公众教育。", "charity", 6, 1.1, {wealth = 0, consumption = 2, circle = 3, charity = 8, growth = 4}),
}

--- 12 级社会身份，按生活方式五维综合得分判定。
PersonalLife.IDENTITIES = {
    {level = 1, id = "ordinary_citizen", name = "平实市民", minScore = 0, desc = "生活方式仍处于基础阶段。"},
    {level = 2, id = "aspiring_professional", name = "进取职场人", minScore = 8, desc = "开始主动投资健康和成长。"},
    {level = 3, id = "refined_resident", name = "品质生活家", minScore = 16, desc = "已建立稳定的品质生活习惯。"},
    {level = 4, id = "community_partner", name = "社区伙伴", minScore = 25, desc = "在社区和职业网络中逐渐被看见。"},
    {level = 5, id = "industry_connector", name = "行业连接者", minScore = 35, desc = "拥有可持续的专业社交网络。"},
    {level = 6, id = "cultural_patron", name = "文化支持者", minScore = 46, desc = "兼顾文化品位与公共参与。"},
    {level = 7, id = "public_benefactor", name = "公益推动者", minScore = 58, minCharity = 12, desc = "持续以实际行动支持公共事务。"},
    {level = 8, id = "city_leader", name = "城市领袖", minScore = 71, minCircle = 16, desc = "在城市发展网络中具备稳定影响力。"},
    {level = 9, id = "social_pillar", name = "社会中坚", minScore = 85, minCharity = 20, desc = "以专业能力和公益投入赢得尊重。"},
    {level = 10, id = "philanthropic_entrepreneur", name = "公益企业家", minScore = 101, minCharity = 28, desc = "商业成就与公共责任形成良性循环。"},
    {level = 11, id = "city_benefactor", name = "城市善治者", minScore = 119, minCircle = 28, minCharity = 35, desc = "在多个公共领域持续作出贡献。"},
    {level = 12, id = "legacy_builder", name = "时代传承者", minScore = 140, minCharity = 45, minGrowth = 24, desc = "以长期投入塑造可传承的社会价值。"},
}

assert(#PersonalLife.ITEMS == 50, "PersonalLife.ITEMS 必须恰好包含 50 项")
assert(#PersonalLife.IDENTITIES == 12, "PersonalLife.IDENTITIES 必须恰好包含 12 级")

local ITEMS_BY_ID = {}
for _, definition in ipairs(PersonalLife.ITEMS) do
    assert(not ITEMS_BY_ID[definition.id], "PersonalLife.ITEMS 存在重复 id: " .. definition.id)
    ITEMS_BY_ID[definition.id] = definition
end

local function money(value)
    return math.floor(math.max(0, tonumber(value) or 0) * 100 + 0.00001) / 100
end

local function trim(list, limit)
    while #list > limit do
        table.remove(list, 1)
    end
end

local function monthSerial(GD)
    local year = math.floor(tonumber(GD and GD.year) or 0)
    local month = math.max(1, math.min(12, math.floor(tonumber(GD and GD.month) or 1)))
    return year * 12 + month
end

local function getPlayer(GD)
    return type(GD) == "table" and type(GD.player) == "table" and GD.player or nil
end

local function copyEffects(effects)
    return {
        wealth = tonumber(effects and effects.wealth) or 0,
        consumption = tonumber(effects and effects.consumption) or 0,
        circle = tonumber(effects and effects.circle) or 0,
        charity = tonumber(effects and effects.charity) or 0,
        growth = tonumber(effects and effects.growth) or 0,
    }
end

local function copyItem(definition)
    local result = {}
    for key, value in pairs(definition) do result[key] = value end
    result.effects = copyEffects(definition.effects)
    return result
end

local function addHistory(state, row)
    state.history[#state.history + 1] = row
    trim(state.history, HISTORY_LIMIT)
end

local function nextSequence(state)
    state.sequence = math.max(0, math.floor(tonumber(state.sequence) or 0)) + 1
    return state.sequence
end

local function sourceId(state, record, label)
    return "personal-life:" .. tostring(record.id) .. ":" .. tostring(label) .. ":" .. tostring(nextSequence(state))
end

local function addTaxDeduction(GD, state, record, category, amount, label)
    amount = money(amount)
    if amount <= 0 then return false end
    local ok, deductionOrReason = PFE.RecordTaxDeduction(
        GD,
        category,
        amount,
        sourceId(state, record, label),
        "个人生活方式：" .. tostring(record.name)
    )
    if not ok then
        print("[PersonalLife] 税前扣除登记失败: " .. tostring(deductionOrReason))
        return false
    end
    return true
end

local function recordEligibleForDeduction(record)
    return record.category == "charity" or record.category == "education" or record.category == "health"
end

local function normalizeRecord(record, fallbackId)
    if type(record) ~= "table" then return nil end
    record.id = tostring(record.id or fallbackId or "legacy")
    record.name = tostring(record.name or record.title or record.id)
    record.category = record.category or "asset"
    record.type = record.type or CATEGORY_TYPES[record.category] or "asset"
    record.purchasePrice = money(record.purchasePrice or record.price)
    record.currentValue = money(record.currentValue or record.purchasePrice)
    record.monthly = money(record.monthly)
    record.effects = copyEffects(record.effects)
    record.status = record.status or (record.sold and "sold" or "active")
    record.purchaseSerial = tonumber(record.purchaseSerial) or 0
    record.totalPaid = money(record.totalPaid or record.purchasePrice)
    record.progressMonths = math.max(0, math.floor(tonumber(record.progressMonths) or 0))
    record.duration = math.max(0, math.floor(tonumber(record.duration) or 0))
    return record
end

--- 初始化并迁移旧版 personalLife 数据。只修改 player.personalLife，不触碰公司数据。
---@param player table
---@return table state
function PersonalLife.Ensure(player)
    assert(type(player) == "table", "player 必须为 table")
    player.cash = money(player.cash)

    local state = player.personalLife or {}
    state.version = VERSION
    state.records = state.records or state.assets or state.items or state.ownedItems or {}
    state.history = state.history or state.logs or {}
    state.sequence = math.max(0, math.floor(tonumber(state.sequence) or 0))
    state.lastMonthlySerial = tonumber(state.lastMonthlySerial) or nil

    local normalized = {}
    for key, oldRecord in pairs(state.records) do
        local record = normalizeRecord(oldRecord, "legacy-" .. tostring(key))
        if record then
            local finalId = record.id
            if normalized[finalId] then finalId = finalId .. "-legacy-" .. tostring(key) end
            record.id = finalId
            normalized[finalId] = record
        end
    end
    state.records = normalized
    state.assets = nil
    state.items = nil
    state.ownedItems = nil
    trim(state.history, HISTORY_LIMIT)

    player.personalLife = state
    return state
end

local function recordCount(state)
    local count = 0
    for _ in pairs(state.records) do count = count + 1 end
    return count
end

local function findRecord(state, id)
    local requested = tostring(id or "")
    local direct = state.records[requested]
    if direct then return direct end
    for _, record in pairs(state.records) do
        if record.id == requested then return record end
    end
    return nil
end

local function makeRecord(definition, serial, recordId)
    return {
        id = recordId or definition.id,
        name = definition.name,
        desc = definition.desc,
        category = definition.category,
        type = definition.type,
        purchasePrice = money(definition.price),
        currentValue = definition.type == "asset" and money(definition.price) or 0,
        monthly = money(definition.monthly),
        resaleRatio = tonumber(definition.resaleRatio) or 0.6,
        depreciation = tonumber(definition.depreciation) or 0.995,
        effects = copyEffects(definition.effects),
        duration = math.max(0, math.floor(tonumber(definition.duration) or 0)),
        progressMonths = 0,
        purchaseSerial = serial,
        totalPaid = money(definition.price),
        status = definition.type == "activity" and "completed" or "active",
    }
end

local function activeFactor(record)
    if record.sold or record.status == "sold" then return 0 end
    if record.type == "asset" then return 1 end
    if record.type == "service" or record.type == "pledge" then
        return record.status == "active" and 1 or 0
    end
    if record.type == "course" then
        if record.status == "completed" then return 1 end
        if record.duration <= 0 then return 1 end
        return math.min(1, record.progressMonths / record.duration)
    end
    if record.type == "activity" then return record.status == "completed" and 1 or 0 end
    return 0
end

--- 返回目录副本；category 为 nil 时返回完整 50 项目录。
function PersonalLife.GetCatalog(GD, category)
    if category ~= nil and CATEGORY_TYPES[category] == nil then return {} end
    local catalog = {}
    for _, definition in ipairs(PersonalLife.ITEMS) do
        if category == nil or definition.category == category then
            catalog[#catalog + 1] = copyItem(definition)
        end
    end
    return catalog
end

--- 购买生活方式项目；资产不可重复购买，social 项目须通过社会信用准入。
---@return boolean ok
---@return table|string result
function PersonalLife.Purchase(GD, id)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local definition = ITEMS_BY_ID[tostring(id or "")]
    if not definition then return false, "未找到生活方式项目" end
    local state = PersonalLife.Ensure(player)
    local existing = findRecord(state, definition.id)

    if existing and definition.type == "asset" and not existing.sold and existing.status ~= "sold" then
        return false, "唯一私人资产已持有，不能重复购买"
    end
    if existing and definition.type == "asset" and (existing.sold or existing.status == "sold") then
        -- 同一资产出售后允许重新购入，并复用其资产档案。
    elseif existing and definition.type == "service" and (existing.status == "paused" or existing.status == "paused_insufficient_cash") then
        return false, "该服务已暂停，请使用 Reactivate 恢复"
    elseif existing and definition.type == "pledge" and (existing.status == "paused" or existing.status == "paused_insufficient_cash") then
        return false, "该公益认捐已暂停，请使用 Reactivate 恢复"
    elseif existing and definition.type ~= "asset" and definition.type ~= "activity" then
        return false, "该项目已购买，请勿重复登记"
    end
    if definition.type == "activity" and recordCount(state) >= MAX_RECORDS then
        return false, "个人生活方式记录已达上限"
    end
    if definition.category == "social" then
        local canAccess, reason = PFE.CanAccessLifestyleItem(GD, definition)
        if not canAccess then return false, reason end
    end

    local price = money(definition.price)
    if player.cash + 0.00001 < price then return false, "个人现金不足" end

    player.cash = money(player.cash - price)
    local recordId = definition.id
    if definition.type == "activity" then
        recordId = definition.id .. "#" .. tostring(nextSequence(state))
    end
    local record = makeRecord(definition, monthSerial(GD), recordId)
    state.records[recordId] = record
    addHistory(state, {kind = "purchase", id = record.id, name = record.name, amount = price, serial = monthSerial(GD)})
    if recordEligibleForDeduction(record) then
        local taxCategory = record.category == "health" and "medical" or record.category
        addTaxDeduction(GD, state, record, taxCategory, price, "purchase")
    end
    print("[PersonalLife] 购买 " .. record.name .. "，支付 " .. price .. " 万")
    return true, record
end

--- 暂停持续性服务或公益认捐；暂停后不会再扣月费。
function PersonalLife.Cancel(GD, id)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalLife.Ensure(player)
    local record = findRecord(state, id)
    if not record then return false, "未找到已购项目" end
    if record.type ~= "service" and record.type ~= "pledge" then
        return false, "仅服务或公益认捐可暂停"
    end
    if record.status ~= "active" then return false, "该项目当前未处于启用状态" end

    record.status = "paused"
    record.pausedSerial = monthSerial(GD)
    addHistory(state, {kind = "cancel", id = record.id, name = record.name, serial = record.pausedSerial})
    print("[PersonalLife] 已暂停 " .. record.name)
    return true, record
end

--- 恢复已暂停的 service 或 pledge，不收取重复购买费；后续月结正常扣月费。
function PersonalLife.Reactivate(GD, id)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalLife.Ensure(player)
    local record = findRecord(state, id)
    if not record then return false, "未找到已购项目" end
    if record.type ~= "service" and record.type ~= "pledge" then return false, "仅服务或公益认捐可恢复" end
    if record.status ~= "paused" and record.status ~= "paused_insufficient_cash" then
        return false, "该项目不需要恢复"
    end

    record.status = "active"
    record.reactivatedSerial = monthSerial(GD)
    addHistory(state, {kind = "reactivate", id = record.id, name = record.name, serial = record.reactivatedSerial})
    print("[PersonalLife] 已恢复 " .. record.name)
    return true, record
end

local function processRecurringCharge(GD, player, state, record, serial, result)
    local charge = money(record.monthly)
    if charge <= 0 then return end
    if player.cash + 0.00001 < charge then
        record.status = "paused_insufficient_cash"
        record.pausedSerial = serial
        result.paused = result.paused + 1
        addHistory(state, {kind = "paused_insufficient_cash", id = record.id, name = record.name, amount = charge, serial = serial})
        print("[PersonalLife] 现金不足，已暂停 " .. record.name)
        return
    end

    player.cash = money(player.cash - charge)
    record.totalPaid = money(record.totalPaid + charge)
    record.lastPaidSerial = serial
    result.charged = money(result.charged + charge)
    result.chargedCount = result.chargedCount + 1
    addHistory(state, {kind = "monthly_charge", id = record.id, name = record.name, amount = charge, serial = serial})
    if recordEligibleForDeduction(record) then
        local taxCategory = record.category == "health" and "medical" or record.category
        addTaxDeduction(GD, state, record, taxCategory, charge, "monthly-" .. tostring(serial))
    end
end

--- 月结：扣 active service/pledge 月费；现金不足则暂停；course 每月推进，完成后提供完整成长效果。
function PersonalLife.MonthlyUpdate(GD)
    local player = getPlayer(GD)
    if not player then return {processed = false, reason = "未初始化个人数据"} end
    local state = PersonalLife.Ensure(player)
    local serial = monthSerial(GD)
    if state.lastMonthlySerial == serial then return {processed = false, reason = "本月已更新"} end

    local result = {processed = true, charged = 0, chargedCount = 0, paused = 0, coursesCompleted = 0}
    for _, record in pairs(state.records) do
        if record.type == "asset" and not record.sold and record.status ~= "sold" then
            record.currentValue = money(record.currentValue * (tonumber(record.depreciation) or 0.995))
        elseif (record.type == "service" or record.type == "pledge") and record.status == "active" then
            processRecurringCharge(GD, player, state, record, serial, result)
        elseif record.type == "course" and record.status == "active" then
            record.progressMonths = record.progressMonths + 1
            if record.duration <= 0 or record.progressMonths >= record.duration then
                record.status = "completed"
                record.completedSerial = serial
                result.coursesCompleted = result.coursesCompleted + 1
                addHistory(state, {kind = "course_completed", id = record.id, name = record.name, serial = serial})
                print("[PersonalLife] 课程完成 " .. record.name)
            end
        end
    end
    state.lastMonthlySerial = serial
    if result.chargedCount > 0 then
        print("[PersonalLife] 月度生活方式支出 " .. result.charged .. " 万")
    end
    return result
end

--- 返回当前生效的五维评分及综合分。
function PersonalLife.GetDimensions(GD)
    local player = getPlayer(GD)
    local dimensions = {wealth = 0, consumption = 0, circle = 0, charity = 0, growth = 0, total = 0}
    if not player then return dimensions end
    local state = PersonalLife.Ensure(player)

    for _, record in pairs(state.records) do
        local factor = activeFactor(record)
        if factor > 0 then
            for _, key in ipairs(DIMENSION_KEYS) do
                dimensions[key] = dimensions[key] + (tonumber(record.effects[key]) or 0) * factor
            end
        end
    end
    for _, key in ipairs(DIMENSION_KEYS) do
        dimensions[key] = math.floor(dimensions[key] * 100 + 0.00001) / 100
        dimensions.total = dimensions.total + dimensions[key]
    end
    dimensions.total = math.floor(dimensions.total * 100 + 0.00001) / 100
    dimensions.score = math.floor(dimensions.total / #DIMENSION_KEYS * 100 + 0.00001) / 100
    return dimensions
end

--- 按五维综合分及必要维度返回当前 12 级社会身份。
function PersonalLife.GetIdentity(GD)
    local dimensions = PersonalLife.GetDimensions(GD)
    local current = PersonalLife.IDENTITIES[1]
    for _, identity in ipairs(PersonalLife.IDENTITIES) do
        if dimensions.score >= identity.minScore
            and (not identity.minCharity or dimensions.charity >= identity.minCharity)
            and (not identity.minCircle or dimensions.circle >= identity.minCircle)
            and (not identity.minGrowth or dimensions.growth >= identity.minGrowth) then
            current = identity
        end
    end
    return {
        level = current.level,
        id = current.id,
        name = current.name,
        desc = current.desc,
        score = dimensions.score,
        dimensions = dimensions,
    }
end

--- 汇总个人生活方式状态，供 UI 读取。
function PersonalLife.GetSummary(GD)
    local player = getPlayer(GD)
    if not player then
        return {cash = 0, dimensions = PersonalLife.GetDimensions(GD), identity = PersonalLife.GetIdentity(GD), records = {}, monthlyCost = 0}
    end
    local state = PersonalLife.Ensure(player)
    local records, monthlyCost, assetValue = {}, 0, 0
    for _, record in pairs(state.records) do
        local row = {}
        for key, value in pairs(record) do row[key] = value end
        row.effects = copyEffects(record.effects)
        records[#records + 1] = row
        if record.status == "active" and (record.type == "service" or record.type == "pledge") then
            monthlyCost = money(monthlyCost + record.monthly)
        end
        if record.type == "asset" and not record.sold and record.status ~= "sold" then
            assetValue = money(assetValue + record.currentValue)
        end
    end
    table.sort(records, function(left, right) return left.id < right.id end)
    return {
        cash = money(player.cash),
        dimensions = PersonalLife.GetDimensions(GD),
        identity = PersonalLife.GetIdentity(GD),
        records = records,
        monthlyCost = monthlyCost,
        assetValue = assetValue,
        history = state.history,
        lastMonthlySerial = state.lastMonthlySerial,
    }
end

--- 出售指定私人资产。售价 = currentValue × item.resaleRatio，默认比例为 0.6。
function PersonalLife.SellAsset(GD, id)
    local player = getPlayer(GD)
    if not player then return false, "未初始化个人数据" end
    local state = PersonalLife.Ensure(player)
    local record = findRecord(state, id)
    if not record then return false, "未找到私人资产" end
    if record.type ~= "asset" then return false, "仅私人资产可以二手出售" end
    if record.sold or record.status == "sold" then return false, "该私人资产已出售" end

    local ratio = tonumber(record.resaleRatio) or 0.6
    ratio = math.max(0, math.min(1, ratio))
    local proceeds = money(record.currentValue * ratio)
    player.cash = money(player.cash + proceeds)
    record.sold = true
    record.status = "sold"
    record.salePrice = proceeds
    record.soldSerial = monthSerial(GD)
    addHistory(state, {kind = "asset_sale", id = record.id, name = record.name, amount = proceeds, serial = record.soldSerial})
    print("[PersonalLife] 出售 " .. record.name .. "，回收 " .. proceeds .. " 万")
    return true, {id = record.id, name = record.name, proceeds = proceeds, ratio = ratio}
end

return PersonalLife
