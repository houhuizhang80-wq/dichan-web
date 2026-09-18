-- ============================================================================
-- DevTypes.lua - 地产开发类型注册表（5种开发类型 + 开发标准系统）
-- ============================================================================

local DT = {}

-- ============================================================================
-- 类别常量
-- ============================================================================
DT.CATEGORY_SALE   = "sale"    -- 销售型
DT.CATEGORY_HOLD   = "hold"    -- 持有型（保留常量兼容旧存档）
DT.CATEGORY_AGENCY = "agency"  -- 代建型（保留常量兼容旧存档）

DT.CATEGORY_NAMES = {
    [DT.CATEGORY_SALE]   = "销售型",
    [DT.CATEGORY_HOLD]   = "持有型",
    [DT.CATEGORY_AGENCY] = "代建型",
}

-- ============================================================================
-- 土地用途 → 可开发类型映射
-- ============================================================================
DT.LAND_USE_TYPES = {
    -- 土地市场只区分住宅/商业：住宅地只做住宅产品，商业地只做写字楼/商业
    residential  = { "rigid_residential", "improved_residential", "luxury_residential" },
    commercial   = { "office_building", "commercial_realestate" },
    -- 旧存档兼容：历史“商住/综合”仍允许全部主流产品
    mixed        = { "rigid_residential", "improved_residential", "luxury_residential", "office_building", "commercial_realestate" },
}

-- 中文用途名 → 英文 landUse key 映射（用于 UI 层转换）
DT.USE_TYPE_TO_LAND_USE = {
    ["住宅"] = "residential",
    ["商业"] = "commercial",
    ["商住"] = "mixed",
    ["综合"] = "mixed",
}

-- ============================================================================
-- 开发标准系统
-- ============================================================================

---@class DevStandard
---@field id string
---@field name string
---@field icon string
---@field costMult number      -- 成本倍率（1.0=不变，1.1=+10%）
---@field reputationPerRound number  -- 每回合口碑增量
---@field priceMult number     -- 售价倍率（1.0=底价，1.1=+10%）
---@field qualityRisk number   -- 质量问题概率（0~1）
---@field qualityPenaltyReputation number  -- 质量问题惩罚口碑值
---@field qualityPenaltyCostRatio number   -- 质量问题整改费用(占建安成本比例)
---@field description string

---@type table<string, DevStandard>
DT.STANDARDS = {
    basic = {
        id = "basic",
        name = "基础标准",
        icon = "🏗️",
        costMult = 1.0,
        reputationPerRound = 0,
        priceMult = 1.0,
        qualityRisk = 0,
        qualityPenaltyReputation = 0,
        qualityPenaltyCostRatio = 0,
        description = "无额外成本，无口碑加成，售价为城市底价，无质量风险",
    },
    quality = {
        id = "quality",
        name = "优质标准",
        icon = "⭐",
        costMult = 1.10,
        reputationPerRound = 10,
        priceMult = 1.10,
        qualityRisk = 0.10,
        qualityPenaltyReputation = -50,
        qualityPenaltyCostRatio = 0.15,
        description = "成本+10%，每回合口碑+10，售价+10%，10%概率出质量问题",
    },
    premium = {
        id = "premium",
        name = "高端标准",
        icon = "💎",
        costMult = 1.20,
        reputationPerRound = 20,
        priceMult = 1.20,
        qualityRisk = 0.20,
        qualityPenaltyReputation = -50,
        qualityPenaltyCostRatio = 0.15,
        description = "成本+20%，每回合口碑+20，售价+20%，20%概率出质量问题",
    },
}

--- 获取开发标准定义
---@param standardId string "basic"|"quality"|"premium"
---@return DevStandard
function DT.GetStandard(standardId)
    return DT.STANDARDS[standardId] or DT.STANDARDS["basic"]
end

--- 获取所有开发标准（有序列表）
---@return DevStandard[]
function DT.GetAllStandards()
    return {DT.STANDARDS["basic"], DT.STANDARDS["quality"], DT.STANDARDS["premium"]}
end

-- ============================================================================
-- 地块位置类型
-- ============================================================================

DT.PLOT_LOCATIONS = {
    core = {
        id = "core",
        name = "核心区",
        icon = "城",
        priceMult = 1.20,      -- 房价+20%
        costMult = 1.05,       -- 开发成本+5%
    },
    suburb = {
        id = "suburb",
        name = "郊区",
        icon = "🌳",
        priceMult = 0.90,      -- 房价-10%
        costMult = 0.95,       -- 开发成本-5%
    },
}

--- 获取地块位置修正系数
---@param plotLocation string "core"|"suburb"
---@return {priceMult: number, costMult: number}
function DT.GetPlotLocationMults(plotLocation)
    local loc = DT.PLOT_LOCATIONS[plotLocation]
    if loc then
        return { priceMult = loc.priceMult, costMult = loc.costMult }
    end
    return { priceMult = 1.0, costMult = 1.0 }
end

-- ============================================================================
-- 5种开发类型定义
-- ============================================================================

---@class DevTypeDefinition
---@field id string
---@field name string
---@field shortName string
---@field category string
---@field icon string
---@field description string
---@field costRatio number         -- 成本 = 城市均价 × costRatio
---@field designCostRatio number
---@field totalMonths number       -- 开发周期（月）= 回合数×12
---@field devRounds number         -- 开发回合数（年）
---@field presaleThreshold? number
---@field revenueModel string
---@field marginRange number[]     -- 利润率区间 [min, max]
---@field targetMargin number
---@field marketRisk number
---@field policyRisk number
---@field operationRisk number
---@field cycleSensitivity number
---@field defaultUnitMix? table[]
---@field specialMechanics? table
---@field lifecyclePhases? table[]
---@field suitableTiers number[]       -- 适配城市等级
---@field suitablePlotLocations string[] -- 适配地块位置
---@field requireReputation? number    -- 需要的最低口碑值
---@field affectedByPopulation? boolean -- 是否受人口流入影响
---@field baseBuildCost? number   -- 已废弃，保留兼容（旧字段兼容映射）
---@field priceMult? number      -- 已废弃
---@field premiumRange? number[]

---@type table<string, DevTypeDefinition>
DT.TYPES = {}

-- ---------------------------------------------------------------------------
-- 1. 刚需房
-- ---------------------------------------------------------------------------
DT.TYPES["rigid_residential"] = {
    id = "rigid_residential",
    name = "刚需房",
    shortName = "刚需",
    category = DT.CATEGORY_SALE,
    icon = "🏠",
    description = "面向首次置业，快周转、低利润、稳健型。适合所有城市",
    -- 经济参数
    costRatio = 0.25,            -- 保留兼容旧存档
    baseBuildCostPerSqm = 3500,  -- 独立建安成本（元/㎡），不依赖城市均价
    preCostRatio = 0.08,         -- 前期费用占建安成本比例（规划、设计、报建等）
    designCostRatio = 0.05,
    totalMonths = 12,            -- 1回合 = 12个月
    devRounds = 1,               -- 1年
    presaleThreshold = 0.25,
    -- 收入模型（利润=总售价的30%-38%，刚需利润率偏低）
    revenueModel = "sale",
    marginRange = {0.30, 0.38},   -- 利润率30%-38%
    targetMargin = 0.33,
    -- 风险
    marketRisk = 0.3,
    policyRisk = 0.5,
    operationRisk = 0.1,
    cycleSensitivity = 0.6,
    -- 城市适配
    suitableTiers = {1, 2, 3},         -- 所有城市
    suitablePlotLocations = {"core", "suburb"},  -- 核心区和郊区都可
    requireReputation = 0,              -- 无口碑要求
    affectedByPopulation = false,
    -- 单元配比
    defaultUnitMix = {
        {key = "basic", ratio = 60, areaRange = {70, 90}},
        {key = "improved", ratio = 35, areaRange = {90, 120}},
        {key = "luxury", ratio = 5, areaRange = {120, 140}},
    },
    specialMechanics = {},
    lifecyclePhases = {
        {name = "四证办理", months = 2},
        {name = "规划设计", months = 2},
        {name = "施工建设", months = 8},
        {name = "预售+施工", months = 0},
        {name = "交付", months = 2},
    },
}

-- ---------------------------------------------------------------------------
-- 2. 改善房
-- ---------------------------------------------------------------------------
DT.TYPES["improved_residential"] = {
    id = "improved_residential",
    name = "改善房",
    shortName = "改善",
    category = DT.CATEGORY_SALE,
    icon = "🏡",
    description = "面向换房改善客群，品质与利润兼顾。适合所有城市和地块",
    costRatio = 0.30,            -- 保留兼容旧存档
    baseBuildCostPerSqm = 4550,  -- 刚需建安成本 × 1.30
    preCostRatio = 0.10,         -- 前期费用占建安成本比例
    designCostRatio = 0.06,
    totalMonths = 24,            -- 2回合 = 24个月
    devRounds = 2,               -- 2年
    presaleThreshold = 0.25,
    -- 收入模型（利润=总售价的33%-42%，改善房利润适中）
    revenueModel = "sale",
    marginRange = {0.33, 0.42},
    targetMargin = 0.37,
    marketRisk = 0.4,
    policyRisk = 0.4,
    operationRisk = 0.15,
    cycleSensitivity = 0.7,
    -- 城市适配：所有城市、所有地块
    suitableTiers = {1, 2, 3},
    suitablePlotLocations = {"core", "suburb"},
    requireReputation = 0,
    affectedByPopulation = false,
    defaultUnitMix = {
        {key = "basic", ratio = 10, areaRange = {90, 110}},
        {key = "improved", ratio = 60, areaRange = {110, 145}},
        {key = "luxury", ratio = 30, areaRange = {145, 180}},
    },
    specialMechanics = {
        {type = "landscape", name = "园林景观", costPct = 0.03, qualityBonus = 5},
    },
    lifecyclePhases = {
        {name = "四证办理", months = 3},
        {name = "规划设计", months = 4},
        {name = "施工建设", months = 16},
        {name = "预售+施工", months = 0},
        {name = "交付", months = 4},
    },
}

-- ---------------------------------------------------------------------------
-- 3. 高端住宅
-- ---------------------------------------------------------------------------
DT.TYPES["luxury_residential"] = {
    id = "luxury_residential",
    name = "高端住宅",
    shortName = "高端",
    category = DT.CATEGORY_SALE,
    icon = "🏰",
    description = "顶级品质，高投入高溢价。适合所有城市和地块",
    costRatio = 0.32,            -- 保留兼容旧存档
    baseBuildCostPerSqm = 5600,  -- 刚需建安成本 × 1.60
    preCostRatio = 0.12,         -- 前期费用占建安成本比例
    designCostRatio = 0.08,
    totalMonths = 36,            -- 3回合 = 36个月
    devRounds = 3,               -- 3年
    presaleThreshold = 0.30,
    -- 收入模型（利润=总售价的36%-45%，高端盘利润率最高）
    revenueModel = "sale",
    marginRange = {0.36, 0.45},
    targetMargin = 0.40,
    marketRisk = 0.7,
    policyRisk = 0.6,
    operationRisk = 0.2,
    cycleSensitivity = 0.9,
    -- 城市适配：所有城市、所有地块
    suitableTiers = {1, 2, 3},
    suitablePlotLocations = {"core", "suburb"},
    requireReputation = 0,
    affectedByPopulation = false,
    defaultUnitMix = {
        {key = "improved", ratio = 20, areaRange = {160, 200}},
        {key = "luxury", ratio = 80, areaRange = {200, 400}},
    },
    specialMechanics = {
        {type = "brand_premium", name = "品牌溢价", qualityReq = 80, premiumPct = 0.15},
        {type = "private_club", name = "私人会所", costPct = 0.05, qualityBonus = 10},
    },
    lifecyclePhases = {
        {name = "四证办理", months = 4},
        {name = "规划设计", months = 6},
        {name = "施工建设", months = 24},
        {name = "预售+施工", months = 0},
        {name = "交付", months = 6},
    },
}

-- ---------------------------------------------------------------------------
-- 4. 商业地产（写字楼、商铺等）
-- ---------------------------------------------------------------------------
DT.TYPES["office_building"] = {
    id = "office_building",
    name = "写字楼",
    shortName = "写字楼",
    category = DT.CATEGORY_SALE,
    icon = "",
    description = "办公楼产品，价格约为住宅均价两倍，适合商业地块",
    costRatio = 0.35,
    baseBuildCostPerSqm = 5500,
    preCostRatio = 0.10,
    designCostRatio = 0.06,
    totalMonths = 36,
    devRounds = 3,
    presaleThreshold = 0.30,
    revenueModel = "sale",
    marginRange = {0.34, 0.44},
    targetMargin = 0.38,
    marketRisk = 0.6,
    policyRisk = 0.3,
    operationRisk = 0.3,
    cycleSensitivity = 0.8,
    suitableTiers = {1, 2, 3},
    suitablePlotLocations = {"core", "suburb"},
    requireReputation = 0,
    affectedByPopulation = true,
    defaultUnitMix = {
        {key = "basic", ratio = 35, areaRange = {80, 150}},
        {key = "improved", ratio = 45, areaRange = {150, 300}},
        {key = "luxury", ratio = 20, areaRange = {300, 800}},
    },
    specialMechanics = {
        {type = "lease_back", name = "售后返租", rentYield = 0.06, lockYears = 3},
    },
    lifecyclePhases = {
        {name = "四证办理", months = 4},
        {name = "规划设计", months = 5},
        {name = "施工建设", months = 24},
        {name = "预售+施工", months = 0},
        {name = "交付", months = 4},
    },
}

-- ---------------------------------------------------------------------------
-- 5. 商业地产（商铺、商业综合体等）
-- ---------------------------------------------------------------------------
DT.TYPES["commercial_realestate"] = {
    id = "commercial_realestate",
    name = "商业地产",
    shortName = "商业",
    category = DT.CATEGORY_SALE,
    icon = "🏢",
    description = "商铺/商业综合体，价格约为住宅均价两倍，受人口流入影响。适合商业地块",
    costRatio = 0.35,            -- 保留兼容旧存档
    baseBuildCostPerSqm = 5500,  -- 独立建安成本（元/㎡）
    preCostRatio = 0.10,         -- 前期费用占建安成本比例
    designCostRatio = 0.06,
    totalMonths = 36,            -- 3回合 = 36个月
    devRounds = 3,               -- 3年
    presaleThreshold = 0.30,
    -- 收入模型（利润=总售价的34%-44%，商业盘利润波动较大但上限高）
    revenueModel = "sale",
    marginRange = {0.34, 0.44},
    targetMargin = 0.38,
    marketRisk = 0.6,
    policyRisk = 0.3,
    operationRisk = 0.3,
    cycleSensitivity = 0.8,
    -- 城市适配：所有城市、所有地块
    suitableTiers = {1, 2, 3},
    suitablePlotLocations = {"core", "suburb"},
    requireReputation = 0,
    affectedByPopulation = true,        -- 受人口流入影响
    defaultUnitMix = {
        {key = "basic", ratio = 40, areaRange = {30, 80}},
        {key = "improved", ratio = 40, areaRange = {80, 200}},
        {key = "luxury", ratio = 20, areaRange = {200, 500}},
    },
    specialMechanics = {
        {type = "lease_back", name = "售后返租", rentYield = 0.06, lockYears = 3},
    },
    lifecyclePhases = {
        {name = "四证办理", months = 4},
        {name = "规划设计", months = 5},
        {name = "施工建设", months = 24},
        {name = "预售+施工", months = 0},
        {name = "交付", months = 4},
    },
}

-- ============================================================================
-- 旧类型ID兼容映射（保证旧存档不崩溃）
-- ============================================================================
DT._LEGACY_TYPE_MAP = {
    commercial_sale = "commercial_realestate",
    shopping_mall   = "commercial_realestate",
}

-- ============================================================================
-- 运营模式配置（每种开发类型可选的运营方式）
-- ============================================================================

---@class OperationMode
---@field id string 模式ID
---@field name string 模式名称
---@field icon string 图标
---@field description string 描述
---@field revenueMultiplier number 收入倍率(相对基准)
---@field opexMultiplier number 运营费用倍率
---@field rampUpMultiplier number 培育期倍率
---@field renovationCost number 变更模式时的装修/改造成本(占建安%)
---@field renovationMonths number 改造工期(月)
---@field pros string[] 优势
---@field cons string[] 劣势

DT.OPERATION_MODES = {
    -- ── 通用运营模式（适用于所有自持/持有型物业） ──
    _default = {
        {id = "self_lease", name = "自持出租", icon = "🏠",
            description = "自持部分自行招租管理",
            revenueMultiplier = 1.0, opexMultiplier = 1.0, rampUpMultiplier = 1.0,
            renovationCost = 0.03, renovationMonths = 2,
            pros = {"灵活管理"}, cons = {"招租压力"}},
        {id = "entrust_lease", name = "委托出租", icon = "🤝",
            description = "委托中介代理出租",
            revenueMultiplier = 0.90, opexMultiplier = 0.80, rampUpMultiplier = 0.5,
            renovationCost = 0.01, renovationMonths = 1,
            pros = {"省心省力"}, cons = {"佣金支出"}},
    },
    -- 按 devTypeId 可覆盖特定模式
    sale_hold = {
        {id = "self_lease", name = "自持出租", icon = "🏠",
            description = "自持部分自行招租管理",
            revenueMultiplier = 1.0, opexMultiplier = 1.0, rampUpMultiplier = 1.0,
            renovationCost = 0.03, renovationMonths = 2,
            pros = {"灵活管理"}, cons = {"招租压力"}},
        {id = "entrust_lease", name = "委托出租", icon = "🤝",
            description = "委托中介代理出租",
            revenueMultiplier = 0.90, opexMultiplier = 0.80, rampUpMultiplier = 0.5,
            renovationCost = 0.01, renovationMonths = 1,
            pros = {"省心省力"}, cons = {"佣金支出"}},
    },
}

--- 获取某开发类型可选的运营模式列表
---@param devTypeId string
---@return OperationMode[]
function DT.GetOperationModes(devTypeId)
    return DT.OPERATION_MODES[devTypeId] or DT.OPERATION_MODES._default or {}
end

--- 获取运营模式详情
---@param devTypeId string
---@param modeId string
---@return OperationMode|nil
function DT.GetOperationMode(devTypeId, modeId)
    local modes = DT.OPERATION_MODES[devTypeId] or {}
    for _, m in ipairs(modes) do
        if m.id == modeId then return m end
    end
    return nil
end

-- ============================================================================
-- 查询API
-- ============================================================================

--- 获取类型定义（兼容旧ID）
---@param typeId string
---@return DevTypeDefinition|nil
function DT.GetType(typeId)
    -- 先查旧ID映射
    local mappedId = DT._LEGACY_TYPE_MAP[typeId]
    if mappedId then typeId = mappedId end
    return DT.TYPES[typeId]
end

--- 获取指定类别的所有类型
---@param category string "sale"|"hold"|"agency"
---@return DevTypeDefinition[]
function DT.GetTypesByCategory(category)
    local result = {}
    for _, t in pairs(DT.TYPES) do
        if t.category == category then
            result[#result + 1] = t
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

--- 获取所有类型(有序列表)
---@return DevTypeDefinition[]
function DT.GetAllTypes()
    local result = {}
    for _, t in pairs(DT.TYPES) do
        result[#result + 1] = t
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

--- 根据土地用途获取可选开发类型
---@param landUse string "residential"|"commercial"|"mixed"|"industrial"|"cultural"
---@return DevTypeDefinition[]
function DT.GetTypesForLandUse(landUse)
    local typeIds = DT.LAND_USE_TYPES[landUse] or DT.LAND_USE_TYPES["mixed"]
    local result = {}
    for _, id in ipairs(typeIds) do
        local t = DT.TYPES[id]
        if t then result[#result + 1] = t end
    end
    return result
end

--- 检查开发类型是否适配当前城市和地块
---@param typeId string 开发类型ID
---@param cityTier number 城市等级（1/2/3）
---@param plotLocation string 地块位置（"core"/"suburb"）
---@param companyReputation number 公司口碑值
---@return boolean ok
---@return string? reason 不适配原因
function DT.CheckSuitability(typeId, cityTier, plotLocation, companyReputation)
    local t = DT.GetType(typeId)
    if not t then return false, "未知开发类型" end

    -- 检查城市等级
    local tierOk = false
    for _, tier in ipairs(t.suitableTiers or {1,2,3}) do
        if tier == cityTier then tierOk = true; break end
    end
    if not tierOk then
        return false, t.name .. "不适合该城市"
    end

    -- 检查地块位置
    local locOk = false
    for _, loc in ipairs(t.suitablePlotLocations or {"core","suburb"}) do
        if loc == plotLocation then locOk = true; break end
    end
    if not locOk then
        local locNames = {}
        for _, loc in ipairs(t.suitablePlotLocations) do
            locNames[#locNames+1] = (DT.PLOT_LOCATIONS[loc] or {}).name or loc
        end
        return false, t.name .. "仅适合" .. table.concat(locNames, "/") .. "地块"
    end

    -- 检查口碑要求
    local reqRep = t.requireReputation or 0
    if reqRep > 0 and companyReputation < reqRep then
        return false, t.name .. "需要口碑≥" .. reqRep .. "（当前：" .. companyReputation .. "）"
    end

    return true
end

--- 获取开发成本（基于独立建安基础值 × 地块位置修正 × 开发标准修正）
--- 不再依赖城市均价，建安成本是独立的绝对值
---@param typeId string 开发类型ID
---@param cityAvgPrice number|nil 保留参数兼容旧调用，新逻辑忽略此参数
---@param plotLocation string|nil 地块位置 "core"/"suburb"
---@param standardId string|nil 开发标准 "basic"/"quality"/"premium"
---@param traitBonus number|nil 特质加成
---@return number 元/㎡
function DT.GetBuildCost(typeId, cityAvgPrice, plotLocation, standardId, traitBonus)
    local t = DT.GetType(typeId)
    if not t then return 3500 end

    -- 如果 cityAvgPrice 是旧版调用（只传了traitBonus数字），做向后兼容
    if type(cityAvgPrice) == "number" and cityAvgPrice < 10 then
        local oldTraitBonus = cityAvgPrice
        local oldBaseCost = t.baseBuildCostPerSqm or t.baseBuildCost or (t.costRatio * 30000)
        local mult = 1 + (oldTraitBonus or 0)
        return math.floor(oldBaseCost * mult * 0.90)
    end

    -- 基础成本 = 独立建安基础值（不再用 cityAvgPrice × costRatio）
    local baseCost = t.baseBuildCostPerSqm or 3500

    -- 地块位置修正
    local locMults = DT.GetPlotLocationMults(plotLocation or "suburb")
    baseCost = baseCost * locMults.costMult

    -- 开发标准修正
    local standard = DT.GetStandard(standardId or "basic")
    baseCost = baseCost * standard.costMult

    -- 特质加成
    local mult = 1 + (traitBonus or 0)
    return math.floor(baseCost * mult)
end

--- 获取预期售价（锚定城市房价，开发标准按同倍率上浮）
--- 刚需≈城市房价；改善+30%；高端+60%；商业/写字楼≈住宅2倍
--- 地价不再抬高售价，而由土地价格侧控制利润率
---@param typeId string 开发类型ID
---@param cityAvgPrice number 城市均价（元/㎡）
---@param plotLocation string|nil 地块位置 "core"/"suburb"
---@param standardId string|nil 开发标准 "basic"/"quality"/"premium"
---@param floorPricePerSqm number|nil 实际楼面地价（元/㎡），保留参数兼容旧调用
---@return number 元/㎡
function DT.GetExpectedPrice(typeId, cityAvgPrice, plotLocation, standardId, floorPricePerSqm)
    local t = DT.GetType(typeId)
    cityAvgPrice = cityAvgPrice or 15000
    if not t then return cityAvgPrice end

    local locMults = DT.GetPlotLocationMults(plotLocation or "suburb")
    local typeMult = 1.0
    if typeId == "improved_residential" then
        typeMult = 1.30
    elseif typeId == "luxury_residential" then
        typeMult = 1.60
    elseif typeId == "commercial_realestate" or typeId == "office_building" then
        typeMult = 2.00
    end

    local standard = DT.GetStandard(standardId or "basic")
    local price = cityAvgPrice * typeMult * locMults.priceMult * standard.priceMult
    return math.floor(price)
end

--- 获取基于地理位置的年租金收益率（3%-5.5%）
--- 核心区租金收益率低（房价高），郊区收益率高
---@param plotLocation string|nil "core"/"urban"/"suburb"
---@param cityTier number|nil 城市等级
---@return number 年租金收益率（0.03-0.055）
function DT.GetRentYieldByLocation(plotLocation, cityTier)
    -- 按位置区分基础收益率
    if plotLocation == "core" then
        return 0.03    -- 核心区 3.0%（房价高，收益率低）
    elseif plotLocation == "suburb" then
        return 0.055   -- 郊区 5.5%（房价低，收益率高）
    end
    return 0.04        -- 市中心/默认 4.0%
end

--- 装修等级对租金收益率的加成（百分点）
--- 毛坯(none)=+0%, 简装(basic)=+1.5%, 精装(standard)=+2.5%, 豪装(luxury)=+3.5%
---@param renovLevel string|nil 装修等级id: "none"/"basic"/"standard"/"luxury"
---@return number bonus 加成百分点（如0.015表示+1.5%）
function DT.GetDecorationRentBonus(renovLevel)
    if renovLevel == "basic" then
        return 0.015   -- 简装 +1.5%
    elseif renovLevel == "standard" then
        return 0.025   -- 精装 +2.5%
    elseif renovLevel == "luxury" then
        return 0.035   -- 豪装 +3.5%
    end
    return 0           -- 毛坯/未装修 +0%
end

--- 获取含装修加成的完整年化租金收益率
---@param plotLocation string 地块位置
---@param cityTier number 城市等级
---@param renovLevel string|nil 装修等级
---@return number yield 年化收益率（如0.06表示6%）
function DT.GetFullRentYield(plotLocation, cityTier, renovLevel)
    local baseYield = DT.GetRentYieldByLocation(plotLocation, cityTier)
    local bonus = DT.GetDecorationRentBonus(renovLevel)
    return baseYield + bonus
end

--- 获取总工期
---@param typeId string
---@return number months
function DT.GetTotalMonths(typeId)
    local t = DT.GetType(typeId)
    return t and t.totalMonths or 30
end

--- 获取开发回合数（年）
---@param typeId string
---@return number rounds
function DT.GetDevRounds(typeId)
    local t = DT.GetType(typeId)
    return t and t.devRounds or 2
end

--- 获取生命周期阶段
---@param typeId string
---@return table[]
function DT.GetLifecycle(typeId)
    local t = DT.GetType(typeId)
    return t and t.lifecyclePhases or {}
end

--- 获取类别名称
---@param category string
---@return string
function DT.GetCategoryName(category)
    return DT.CATEGORY_NAMES[category] or "未知"
end

--- 获取类型的风险评级(简化: 低/中/高)
---@param typeId string
---@return string
function DT.GetRiskRating(typeId)
    local t = DT.GetType(typeId)
    if not t then return "中" end
    local avg = (t.marketRisk + t.policyRisk + t.operationRisk) / 3
    if avg <= 0.3 then return "低"
    elseif avg <= 0.55 then return "中"
    else return "高" end
end

--- 获取7维度比较数据
---@param typeId string
---@return table {dimension: number(0-100)}
function DT.GetRadarData(typeId)
    local t = DT.GetType(typeId)
    if not t then return {} end
    local estBuildCost = t.baseBuildCostPerSqm or ((t.costRatio or 0.30) * 30000)  -- 基础建安成本
    return {
        buildCost = math.min(100, math.floor(estBuildCost / 100)),
        duration = math.min(100, math.floor(t.totalMonths / 0.4)),
        profitability = math.floor((t.targetMargin or 0.05) * 200),
        marketRisk = math.floor(t.marketRisk * 100),
        policyRisk = math.floor(t.policyRisk * 100),
        operationDifficulty = math.floor(t.operationRisk * 100),
        cycleSensitivity = math.floor(t.cycleSensitivity * 100),
    }
end

return DT
