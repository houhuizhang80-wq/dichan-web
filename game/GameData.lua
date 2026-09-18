---@diagnostic disable: assign-type-mismatch, return-type-mismatch
-- ============================================================================
-- GameData.lua - 游戏全局状态 + 经济模拟 + 时间系统
-- ============================================================================

local GD = {}
local ME = require("MacroEconomy")
local LA = require("LandAcquisition")
local CS = require("Construction")
local MK = require("Marketing")
local FN = require("Finance")
local BR = require("Brand")
local PC = require("ProjectCapacity")
local DT = require("DevTypes")
local OP = require("Operations")
local AF = require("AgencyFee")
local PS = require("Personal")
local GV = require("Governance")
local GS = require("GroupSystem")
local GDI = GS.Diversification
local INS = require("InternationalSystem")
local SM = require("StockMarket")
local RE = require("RandomEvents")

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[deepCopy(k, seen)] = deepCopy(v, seen)
    end
    return copy
end

-- ============================================================================
-- 部门定义表（职权、岗位、加成、设立成本）
-- ============================================================================
GD.DEPT_DEFS = {
    invest = {
        name = "投资发展部",
        authority = "土地拓展与投资决策，可行性研究，市场调研分析",
        bonus = "+投资研判效率，降低拿地风险",
        setupCost = 20,  -- 设立费用(万)
        monthCost = 0,   -- 月度运营费(万)
        roles = {
            {title = "投资总监", salaryMin = 8400, salaryMax = 14000, ability = "+投资研判效率15%"},
            {title = "投资经理", salaryMin = 5600,  salaryMax = 10500, ability = "+土地分析精度"},
            {title = "市场研究员", salaryMin = 4200, salaryMax = 7000, ability = "+市场数据准确度"},
        },
    },
    design = {
        name = "设计管理部",
        authority = "产品设计管控，规划方案审查，设计变更管理",
        bonus = "+设计审查速度15%，提升产品品质",
        setupCost = 20,
        monthCost = 0,
        roles = {
            {title = "设计总监", salaryMin = 10500, salaryMax = 17500, ability = "+设计审查速度20%"},
            {title = "设计主管", salaryMin = 7000, salaryMax = 12600, ability = "+设计审查速度10%"},
            {title = "设计师",   salaryMin = 4900,  salaryMax = 8400, ability = "+图纸审核效率"},
        },
    },
    cost = {
        name = "成本招采部",
        authority = "成本测算与控制，招标采购管理，供应商评估",
        bonus = "降低建安成本波动30%，优化采购价格",
        setupCost = 18,
        monthCost = 0,
        roles = {
            {title = "成本总监", salaryMin = 8400, salaryMax = 14000, ability = "-建安成本8%"},
            {title = "成本经理", salaryMin = 5600,  salaryMax = 9800, ability = "-建安成本5%"},
            {title = "采购专员", salaryMin = 3500,  salaryMax = 6300,  ability = "+供应商议价能力"},
        },
    },
    engineer = {
        name = "工程管理部",
        authority = "工程进度管控，施工质量监督，安全文明管理",
        bonus = "+工程质量，降低施工安全事故率",
        setupCost = 20,
        monthCost = 0,
        roles = {
            {title = "工程总监", salaryMin = 9100, salaryMax = 15400, ability = "+工程质量15%"},
            {title = "工程经理", salaryMin = 6300,  salaryMax = 11200, ability = "+工程进度管控"},
            {title = "质量工程师", salaryMin = 4900, salaryMax = 8400, ability = "+质量检查通过率"},
        },
    },
    marketing = {
        name = "营销策划部",
        authority = "营销方案策划，定价策略制定，销售渠道管理",
        bonus = "+去化速度10%，提升营销转化率",
        setupCost = 25,
        monthCost = 0,
        roles = {
            {title = "营销总监", salaryMin = 10500, salaryMax = 17500, ability = "+去化速度15%"},
            {title = "销售经理", salaryMin = 7000, salaryMax = 14000, ability = "+去化速度10%"},
            {title = "策划专员", salaryMin = 4200,  salaryMax = 7000, ability = "+活动转化率"},
        },
    },
    finance = {
        name = "财务融资部",
        authority = "财务核算管理，融资渠道拓展，资金计划编制",
        bonus = "+融资额度，降低融资成本",
        setupCost = 18,
        monthCost = 0,
        roles = {
            {title = "财务总监", salaryMin = 10500, salaryMax = 17500, ability = "+融资额度20%"},
            {title = "财务经理", salaryMin = 5600,  salaryMax = 10500, ability = "+融资额度10%"},
            {title = "会计",     salaryMin = 3500,  salaryMax = 6300,  ability = "+财务报表准确度"},
        },
    },
    legal = {
        name = "法务合规部",
        authority = "合同法律审查，合规风险防控，诉讼纠纷处理",
        bonus = "+风险防范，降低法律纠纷概率",
        setupCost = 15,
        monthCost = 0,
        roles = {
            {title = "法务总监", salaryMin = 10500, salaryMax = 17500, ability = "+合同风险识别20%"},
            {title = "法务主管", salaryMin = 8400, salaryMax = 14000, ability = "+风险防范"},
            {title = "合规专员", salaryMin = 4200,  salaryMax = 7000, ability = "+合规检查效率"},
        },
    },
    hr = {
        name = "人力行政部",
        authority = "人才招聘培训，行政后勤管理，企业文化建设",
        bonus = "+运营效率，降低人员流失率",
        setupCost = 12,
        monthCost = 0,
        roles = {
            {title = "人力总监", salaryMin = 7000, salaryMax = 12600, ability = "+招聘效率，降薪资10%"},
            {title = "行政主管", salaryMin = 4200,  salaryMax = 7000, ability = "+运营效率"},
            {title = "人事专员", salaryMin = 3500,  salaryMax = 5600,  ability = "+员工满意度"},
        },
    },
    audit = {
        name = "审计监察部",
        authority = "内部审计监督，反腐败调查，经营风险评估",
        bonus = "+内审覆盖率，降低腐败风险",
        setupCost = 12,
        monthCost = 0,
        roles = {
            {title = "审计总监", salaryMin = 8400, salaryMax = 14000, ability = "+内审效率20%"},
            {title = "审计主管", salaryMin = 5600,  salaryMax = 10500, ability = "+风险识别能力"},
            {title = "审计专员", salaryMin = 4200,  salaryMax = 7000, ability = "+审计覆盖率"},
        },
    },
}

-- ============================================================================
-- 时间系统
-- ============================================================================
GD.DAY_DURATION = 3      -- 1x速度下3秒=1天; 2x=1秒/天; 3x=0.5秒/天
GD.timeAccum = 0
GD.gameSpeed = 1         -- 0=暂停 1=正常 2=快 4=极快
GD.paused = false
GD.gameStarted = false
GD.companyPortfolio = { nextId = 1, activeId = nil, companies = {} }
GD.activeCompanyId = nil
GD.group = GS.CreateDefaultData()
GD.international = INS.CreateDefaultData()

-- 当前日期
GD.year = 2001
GD.month = 1
GD.day = 1
GD.totalMonths = 0
GD.totalDays = 0

-- ============================================================================
-- 公司数据 (统一为股份有限公司，按性质分变体)
-- ============================================================================
GD.company = {
    name = "",
    -- 企业性质(均为股份有限公司)
    nature = "private",          -- private=民营 / foreign=外资 / joint_venture=合资
    natureNames = {llc="有限责任公司", joint_stock="股份制企业", private="民营", foreign="外资", joint_venture="合资"},
    -- 创始人特质
    founderTrait = "balanced",   -- fast_turn/quality/capital/government/balanced
    founderTraitNames = {
        fast_turn = "高周转派",
        quality   = "品质坚守者",
        capital   = "资本运作高手",
        government= "政府关系型",
        balanced  = "均衡型",
    },
    -- 特质效果(初始化时根据trait设置)
    traitEffects = {
        buildSpeedBonus   = 0,    -- 建设速度加成(如+0.15=+15%)
        qualityRisk       = 0,    -- 质量风险加成
        buildCostBonus    = 0,    -- 建安成本加成
        brandPremium      = 0,    -- 品牌溢价加成
        financeCostBonus  = 0,    -- 融资成本加成
        debtRisk          = 0,    -- 债务风险加成
        permitSpeedBonus  = 0,    -- 报建速度加成
        complianceRisk    = 0,    -- 合规风险加成
    },
    -- 注册信息
    registeredCapital = 1000,   -- 万元(1000万~50000万即5亿)
    city = "",
    cityTier = 1,               -- 1/2/3
    scope = {
        realEstate = true,
        property = false,
        commercial = false,
        rental = false,
        decoration = false,
    },
    -- 资质
    qualification = 0,          -- 0=暂定 1=三级 2=二级 3=一级
    qualNames = {"暂定级", "三级", "二级", "一级"},
    qualMaxArea = {100000, 200000, 250000, 999999999},
    totalBuiltArea = 0,         -- 累计竣工面积(平米)
    -- 信用
    creditScore = 70,
    -- 分红(所有公司均为股份制，均需分红)
    dividendRate = 0,           -- 分红比例(初始0%，由股权预设决定)
    annualProfit = 0,           -- 当年累计净利润(万元)
    lastDividend = 0,           -- 上次分红金额(万元)
    -- 财务
    cash = 0,                   -- 万元
    totalAssets = 0,
    totalDebt = 0,
    negativeCashMonths = 0,     -- 连续现金为负的月数
    cashCrisisWarned = false,   -- 本轮负现金是否已弹过提醒
    isGameOver = false,         -- 游戏结束标记（玩家主动宣告破产）
    showCashCrisis = false,     -- 资金危机弹窗标记（现金为负时暂停游戏）
    monthlyRevenue = 0,
    monthlyExpense = 0,
    monthlyProfit = 0,
    -- 人员
    employees = {},
    monthlySalary = 0,
    -- ========================================
    -- 1.2 组织架构
    -- ========================================
    -- 总部部门(9个标准部门，默认未设立)
    hqDepartments = {
        {id="invest",   name="投资发展部", established=false, headcount=0, monthCost=0, staff={}},
        {id="design",   name="设计管理部", established=false, headcount=0, monthCost=0, staff={}},
        {id="cost",     name="成本招采部", established=false, headcount=0, monthCost=0, staff={}},
        {id="engineer", name="工程管理部", established=false, headcount=0, monthCost=0, staff={}},
        {id="marketing",name="营销策划部", established=false, headcount=0, monthCost=0, staff={}},
        {id="finance",  name="财务融资部", established=false, headcount=0, monthCost=0, staff={}},
        {id="legal",    name="法务合规部", established=false, headcount=0, monthCost=0, staff={}},
        {id="hr",       name="人力行政部", established=false, headcount=0, monthCost=0, staff={}},
        {id="audit",    name="审计监察部", established=false, headcount=0, monthCost=0, staff={}},
    },
    -- 区域/城市公司
    regionalCompanies = {},     -- {name, city, pnl=0, projects={}, employees={}}
    -- 6.4 供应商黑名单(公司级)
    contractorBlacklist = {},   -- {{name=str, reason=str, addedMonth=int, addedYear=int}}
    -- 项目公司(SPV) — 每个地块一个，在CreateProject时自动创建
    -- 存储在 project.spv 字段中
    -- ========================================
    -- 1.3 人力系统(关键岗位)
    -- ========================================
    keyPositions = {},          -- 关键高管列表
    -- 旧departments字段保留兼容
    departments = {},
    -- ========================================
    -- 1.4 项目容量系统
    -- ========================================
    projectCapacity = {
        base = 10,             -- 基础容量（可同时开发10个项目）
        bonus = 0,             -- 加成容量
        max = 20,              -- 硬上限（区域公司/项目总加成后最高可达20）
    },
}

-- ============================================================================
-- 公司生命周期重置
-- ============================================================================
local function createFreshCompanyData()
    return {
        name = "",
        nature = "private",
        natureNames = {llc="有限责任公司", joint_stock="股份制企业", private="民营", foreign="外资", joint_venture="合资"},
        founderTrait = "balanced",
        founderTraitNames = {
            fast_turn = "高周转派",
            quality   = "品质坚守者",
            capital   = "资本运作高手",
            government= "政府关系型",
            balanced  = "均衡型",
        },
        traitEffects = {
            buildSpeedBonus = 0, qualityRisk = 0, buildCostBonus = 0, brandPremium = 0,
            financeCostBonus = 0, debtRisk = 0, permitSpeedBonus = 0, complianceRisk = 0,
        },
        registeredCapital = 1000,
        city = "",
        cityTier = 1,
        scope = {realEstate = true, property = false, commercial = false, rental = false, decoration = false},
        qualification = 0,
        qualNames = {"暂定级", "三级", "二级", "一级"},
        qualMaxArea = {100000, 200000, 250000, 999999999},
        totalBuiltArea = 0,
        creditScore = 70,
        dividendRate = 0,
        annualProfit = 0,
        lastDividend = 0,
        cash = 0,
        totalAssets = 0,
        totalDebt = 0,
        negativeCashMonths = 0,
        cashCrisisWarned = false,
        isGameOver = false,
        showCashCrisis = false,
        monthlyRevenue = 0,
        monthlyExpense = 0,
        monthlyProfit = 0,
        employees = {},
        monthlySalary = 0,
        hqDepartments = {
            {id="invest", name="投资发展部", established=false, headcount=0, monthCost=0, staff={}},
            {id="design", name="设计管理部", established=false, headcount=0, monthCost=0, staff={}},
            {id="cost", name="成本招采部", established=false, headcount=0, monthCost=0, staff={}},
            {id="engineer", name="工程管理部", established=false, headcount=0, monthCost=0, staff={}},
            {id="marketing", name="营销策划部", established=false, headcount=0, monthCost=0, staff={}},
            {id="finance", name="财务融资部", established=false, headcount=0, monthCost=0, staff={}},
            {id="legal", name="法务合规部", established=false, headcount=0, monthCost=0, staff={}},
            {id="hr", name="人力行政部", established=false, headcount=0, monthCost=0, staff={}},
            {id="audit", name="审计监察部", established=false, headcount=0, monthCost=0, staff={}},
        },
        regionalCompanies = {},
        contractorBlacklist = {},
        keyPositions = {},
        departments = {},
        projectCapacity = {base = 10, bonus = 0, max = 20},
    }
end

local PERSONAL_CITY_OPERATION_FIELDS = {
    invest = "cityInvestData",
    bond = "cityBondData",
    sponsor = "citySponsorData",
    credit = "cityCreditData",
    bank = "cityBankData",
    bot = "cityBOTData",
}

local function isArrayTable(value)
    return type(value) == "table" and #value > 0
end

local CITY_OPERATION_IDENTITY_FIELDS = {
    "id", "name", "type", "typeLabel", "amount", "principal", "buildCost",
    "cost", "annualRate", "termMonths", "year", "month",
}

local function getScalarSignature(entry)
    if type(entry) ~= "table" then return type(entry) .. ":" .. tostring(entry) end
    local parts = {}
    for _, key in ipairs(CITY_OPERATION_IDENTITY_FIELDS) do
        local value = entry[key]
        if value ~= nil and type(value) ~= "table" then
            parts[#parts + 1] = tostring(key) .. "=" .. type(value) .. ":" .. tostring(value)
        end
    end
    if #parts == 0 then
        for key, value in pairs(entry) do
            if type(value) ~= "table" then
                parts[#parts + 1] = tostring(key) .. "=" .. type(value) .. ":" .. tostring(value)
            end
        end
        table.sort(parts)
    end
    return table.concat(parts, "|")
end

local function mergeCityOperationValue(target, source)
    if type(source) ~= "table" then return target end
    if type(target) ~= "table" then return deepCopy(source) end
    if isArrayTable(source) then
        -- 同一份城市数据会同时存在于旧顶层字段和当前公司快照中。
        -- 按浅层标量签名做多重集合合并，只补齐额外记录，避免读档后重复持仓。
        local targetCounts = {}
        for _, entry in ipairs(target) do
            local signature = getScalarSignature(entry)
            targetCounts[signature] = (targetCounts[signature] or 0) + 1
        end
        local seenSource = {}
        for _, entry in ipairs(source) do
            local signature = getScalarSignature(entry)
            seenSource[signature] = (seenSource[signature] or 0) + 1
            if seenSource[signature] > (targetCounts[signature] or 0) then
                table.insert(target, deepCopy(entry))
            end
        end
        return target
    end
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = deepCopy(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            target[key] = mergeCityOperationValue(target[key], value)
        end
    end
    return target
end

local function mergeCityOperationTable(target, source)
    if type(source) ~= "table" then return target end
    for cityName, cityData in pairs(source) do
        if target[cityName] == nil then
            target[cityName] = deepCopy(cityData)
        else
            target[cityName] = mergeCityOperationValue(target[cityName], cityData)
        end
    end
    return target
end

--- Bind all legacy GD.city*Data accessors to the one personal, cross-company authority.
--- Returns false during module initialization before GD.player exists.
function GD.EnsurePersonalCityOperations()
    if not GD.player then return false end
    PS.EnsurePlayerFields(GD.player)
    local operations = GD.player.cityOperations
    for operationType, field in pairs(PERSONAL_CITY_OPERATION_FIELDS) do
        operations[operationType] = operations[operationType] or {}
        GD[field] = operations[operationType]
    end
    return true
end

function GD.GetPersonalCityCash()
    GD.EnsurePersonalCityOperations()
    return GD.player and (GD.player.cash or 0) or 0
end

function GD.SpendPersonalCityCash(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效金额" end
    if not GD.player then return false, "个人数据未初始化" end
    if (GD.player.cash or 0) < amount then return false, "个人现金不足" end
    GD.player.cash = GD.player.cash - amount
    return true
end

function GD.CreditPersonalCityCash(amount, isIncome)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 or not GD.player then return false end
    GD.player.cash = (GD.player.cash or 0) + amount
    if isIncome and amount > 0 then
        GD.player.totalIncome = (GD.player.totalIncome or 0) + amount
        GD.player.totalInvestReturn = (GD.player.totalInvestReturn or 0) + amount
        GD.player.yearlyIncome = (GD.player.yearlyIncome or 0) + amount
        GD.player.yearlyInvestReturn = (GD.player.yearlyInvestReturn or 0) + amount
    end
    return true
end

local LEGACY_CITY_NAME_MAP = {
    ["长沙"] = "兰德市",
    ["昆明"] = "齐隆市",
    ["洛阳"] = "罗江市",
    ["贵阳"] = "华尔市",
    ["南宁"] = "山花市",
    ["兰州"] = "西北市",
    ["烟台"] = "鹿鸣市",
    ["徐州"] = "许州市",
    ["惠州"] = "会齐市",
}

local LEGACY_COMPETITOR_NAME_MAP = {
    ["融创中国"] = "融盛控股",
    ["瑞安建设"] = "瑞澜建设",
}

local LEGACY_BRAND_NAME_MAP = {
    ["万达集团"] = "万澜集团",
    ["碧桂园"] = "碧川园",
    ["恒大地产"] = "恒远地产",
    ["保利发展"] = "保宁发展",
    ["中海地产"] = "中泽地产",
    ["龙湖集团"] = "龙川集团",
    ["融创中国"] = "融盛控股",
    ["华润置地"] = "华泽置地",
    ["绿地控股"] = "绿野控股",
    ["招商蛇口"] = "招远港湾",
    ["金地集团"] = "金川集团",
    ["新城控股"] = "新川控股",
    ["中梁控股"] = "中岚控股",
    ["旭辉集团"] = "旭川集团",
    ["世茂集团"] = "世川集团",
    ["金茂集团"] = "金川置地",
    ["中交地产"] = "通达地产",
    ["远洋集团"] = "远川集团",
    ["首开股份"] = "首川股份",
    ["电建地产"] = "能建地产",
    ["中铁置业"] = "铁川置业",
    ["光大安石"] = "光川安石",
    ["平安不动产"] = "安和不动产",
    ["黑石集团"] = "玄石资本",
    ["凯德集团"] = "凯川集团",
    ["太古地产"] = "太川地产",
    ["嘉里建设"] = "嘉川建设",
    ["蓝光发展"] = "蓝川发展",
    ["阳光城"] = "阳川城",
    ["泰禾集团"] = "泰川集团",
    ["华夏幸福"] = "华川安居",
    ["华为科技"] = "华川科技",
    ["腾讯分部"] = "讯联分部",
    ["阿里巴巴"] = "河马商联",
    ["字节跳动"] = "码点传媒",
    ["美团运营中心"] = "美邻运营中心",
    ["京东物流"] = "京川物流",
    ["小米科技"] = "微米科技",
    ["网易游戏"] = "网川游戏",
    ["星巴克"] = "星谷咖啡",
    ["海底捞"] = "海川捞",
    ["名创优品"] = "名川优品",
    ["优衣库"] = "优衣汇",
    ["屈臣氏"] = "屈川氏",
    ["万宁"] = "万川便利",
    ["永辉超市"] = "永川超市",
    ["盒马鲜生"] = "盒川鲜生",
    ["万科地产"] = "万川地产",
    ["碧桂园控股"] = "碧川园控股",
    ["中国银行"] = "寰宇银行",
    ["招商银行"] = "招远银行",
    ["中国平安"] = "安和保险",
    ["贵州茅台"] = "川源酒业",
    ["格力电器"] = "格川电器",
    ["腾讯控股"] = "讯联控股",
    ["比亚迪"] = "比川动力",
    ["中国建筑"] = "寰宇建筑",
    ["海螺水泥"] = "海川水泥",
    ["宁德时代"] = "宁川时代",
    ["中国中铁"] = "铁川基建",
    ["工商银行"] = "工川银行",
    ["建设银行"] = "建川银行",
    ["民生银行"] = "民和银行",
    ["华泰保险资管公司"] = "华川保险资管公司",
    ["国家产业投资基金"] = "产业振兴投资基金",
    ["汇丰资产亚太基金"] = "汇川资产亚太基金",
    ["平安私募股权基金"] = "安和私募股权基金",
    ["国家主权财富基金"] = "主权财富基金",
    ["全国社会保障基金"] = "社会保障基金",
    ["中国人寿资产管理"] = "人寿资产管理",
    ["中国平安战略投资部"] = "安和保险战略投资部",
    ["国家电网财务公司"] = "能源电网财务公司",
    ["国开发展基金"] = "开发性产业基金",
}

local function remapCityName(name)
    if type(name) ~= "string" or name == "" then return name end
    return LEGACY_CITY_NAME_MAP[name] or name
end

local function remapKeyedCityTable(source)
    if type(source) ~= "table" then return source end
    local remapped = {}
    for cityName, cityData in pairs(source) do
        local newName = remapCityName(cityName)
        if remapped[newName] == nil then
            if type(cityData) == "table" and type(cityData.city) == "string" then
                cityData.city = remapCityName(cityData.city)
            end
            remapped[newName] = cityData
        else
            if type(remapped[newName]) == "table" and type(cityData) == "table" then
                mergeCityOperationValue(remapped[newName], cityData)
            end
        end
    end
    return remapped
end

local function remapCityNameInText(text)
    if type(text) ~= "string" or text == "" then return text end
    for oldName, newName in pairs(LEGACY_CITY_NAME_MAP) do
        if string.find(text, oldName, 1, true) then
            text = string.gsub(text, oldName, newName)
        end
    end
    if LEGACY_BRAND_NAME_MAP[text] then
        return LEGACY_BRAND_NAME_MAP[text]
    end
    for oldName, newName in pairs(LEGACY_BRAND_NAME_MAP) do
        if string.find(text, oldName, 1, true) then
            text = string.gsub(text, oldName, newName)
        end
    end
    return text
end

local function remapNamedRecordCity(record)
    if type(record) ~= "table" then return end
    if type(record.city) == "string" then
        record.city = remapCityName(record.city)
    end
    if type(record.projectCity) == "string" then
        record.projectCity = remapCityName(record.projectCity)
    end
    if type(record.name) == "string" then
        record.name = remapCityNameInText(record.name)
    end
    if type(record.assetName) == "string" then
        record.assetName = remapCityNameInText(record.assetName)
    end
    if type(record.projectName) == "string" then
        record.projectName = remapCityNameInText(record.projectName)
    end
    if type(record.description) == "string" then
        record.description = remapCityNameInText(record.description)
    end
    if type(record.text) == "string" then
        record.text = remapCityNameInText(record.text)
    end
    if type(record.buyer) == "string" then
        record.buyer = remapCityNameInText(record.buyer)
    end
    if type(record.sellerName) == "string" then
        record.sellerName = remapCityNameInText(record.sellerName)
    end
    if type(record.tenantName) == "string" then
        record.tenantName = remapCityNameInText(record.tenantName)
    end
    if type(record.channelData) == "table" then
        remapNamedRecordCity(record.channelData)
    end
    if type(record.offers) == "table" then
        for _, offer in ipairs(record.offers) do
            remapNamedRecordCity(offer)
        end
    end
end

local function remapStockMarketNames(market)
    if type(market) ~= "table" or type(market.companies) ~= "table" then return end
    for _, stock in ipairs(market.companies) do
        if type(stock.name) == "string" then
            stock.name = remapCityNameInText(stock.name)
        end
        for _, tmpl in ipairs(SM.COMPANY_TEMPLATES) do
            if tmpl.code == stock.code then
                stock.name = tmpl.name
                stock.industry = tmpl.industry or stock.industry
                break
            end
        end
    end
end

function GD.NormalizeFictionalWorldNames()
    for _, city in ipairs(GD.cities or {}) do
        city.name = remapCityName(city.name)
    end
    if GD.company then
        GD.company.city = remapCityName(GD.company.city)
        for _, rc in ipairs(GD.company.regionalCompanies or {}) do
            remapNamedRecordCity(rc)
        end
        local pendingReport = GD.company.governance and GD.company.governance.pendingCeoReport
        if type(pendingReport) == "table" and type(pendingReport.proposals) == "table" then
            for _, landProposal in ipairs(pendingReport.proposals.land or {}) do
                remapNamedRecordCity(landProposal)
                if landProposal.land then remapNamedRecordCity(landProposal.land) end
            end
            for _, projectProposal in ipairs(pendingReport.proposals.projects or {}) do
                remapNamedRecordCity(projectProposal)
            end
            local presale = pendingReport.proposals.presale
            if type(presale) == "table" then
                if #presale > 0 then
                    for _, item in ipairs(presale) do remapNamedRecordCity(item) end
                else
                    remapNamedRecordCity(presale)
                end
            end
        end
    end
    for _, record in ipairs((GD.companyPortfolio and GD.companyPortfolio.companies) or {}) do
        remapNamedRecordCity(record)
        local company = record.state and record.state.company
        if company then
            company.city = remapCityName(company.city)
            for _, rc in ipairs(company.regionalCompanies or {}) do
                remapNamedRecordCity(rc)
            end
        end
        for _, land in ipairs((record.state and record.state.landReserve) or {}) do
            remapNamedRecordCity(land)
        end
        for _, project in ipairs((record.state and record.state.projects) or {}) do
            remapNamedRecordCity(project)
            if project.land then remapNamedRecordCity(project.land) end
        end
        for _, asset in ipairs((record.state and record.state.fixedAssets) or {}) do
            remapNamedRecordCity(asset)
        end
        for _, listing in ipairs((record.state and record.state.assetListings) or {}) do
            remapNamedRecordCity(listing)
        end
        for _, listing in ipairs((record.state and record.state.rentalListings) or {}) do
            remapNamedRecordCity(listing)
        end
        if record.state and record.state.assetMarket then
            for _, listing in ipairs(record.state.assetMarket.listings or {}) do
                remapNamedRecordCity(listing)
            end
        end
        local governance = company and company.governance
        local pendingReport = governance and governance.pendingCeoReport
        if type(pendingReport) == "table" then
            if type(pendingReport.proposals) == "table" then
                for _, landProposal in ipairs(pendingReport.proposals.land or {}) do
                    remapNamedRecordCity(landProposal)
                    if landProposal.land then remapNamedRecordCity(landProposal.land) end
                end
                for _, projectProposal in ipairs(pendingReport.proposals.projects or {}) do
                    remapNamedRecordCity(projectProposal)
                end
                local presale = pendingReport.proposals.presale
                if type(presale) == "table" then
                    if #presale > 0 then
                        for _, item in ipairs(presale) do remapNamedRecordCity(item) end
                    else
                        remapNamedRecordCity(presale)
                    end
                end
            end
        end
    end
    for _, land in ipairs(GD.landMarket or {}) do remapNamedRecordCity(land) end
    for _, land in ipairs(GD.landReserve or {}) do remapNamedRecordCity(land) end
    for _, project in ipairs(GD.projects or {}) do
        remapNamedRecordCity(project)
        if project.land then remapNamedRecordCity(project.land) end
    end
    for _, asset in ipairs(GD.fixedAssets or {}) do remapNamedRecordCity(asset) end
    for _, listing in ipairs(GD.assetListings or {}) do remapNamedRecordCity(listing) end
    for _, listing in ipairs(GD.rentalListings or {}) do remapNamedRecordCity(listing) end
    if GD.assetMarket then
        for _, listing in ipairs(GD.assetMarket.listings or {}) do
            remapNamedRecordCity(listing)
        end
    end
    GD.landSupplyPlans = remapKeyedCityTable(GD.landSupplyPlans)
    GD.landSupplyCommitments = remapKeyedCityTable(GD.landSupplyCommitments)
    GD.landSupplyAnnual = remapKeyedCityTable(GD.landSupplyAnnual)
    if GD.player and GD.player.cityOperations then
        for operationType, tableData in pairs(GD.player.cityOperations) do
            GD.player.cityOperations[operationType] = remapKeyedCityTable(tableData)
            for _, cityData in pairs(GD.player.cityOperations[operationType] or {}) do
                if type(cityData) == "table" then
                    for _, listKey in ipairs({"holdings", "bonds", "deposits", "loans", "wealthFunds", "shareholders", "history"}) do
                        for _, item in ipairs(cityData[listKey] or {}) do
                            remapNamedRecordCity(item)
                        end
                    end
                    if type(cityData.projects) == "table" then
                        for _, item in ipairs(cityData.projects) do remapNamedRecordCity(item) end
                    end
                    if type(cityData.sponsors) == "table" then
                        for _, item in ipairs(cityData.sponsors) do remapNamedRecordCity(item) end
                    end
                    if type(cityData.records) == "table" then
                        for _, item in ipairs(cityData.records) do remapNamedRecordCity(item) end
                    end
                end
            end
        end
        GD.EnsurePersonalCityOperations()
    end
    for _, event in ipairs(GD.events or {}) do
        if type(event.text) == "string" then
            event.text = remapCityNameInText(event.text)
        end
    end
    for _, comp in ipairs(GD.competitors or {}) do
        if type(comp.name) == "string" then
            comp.name = LEGACY_COMPETITOR_NAME_MAP[comp.name] or remapCityNameInText(comp.name)
        end
    end
    remapStockMarketNames(GD.stockMarket)
    for _, record in ipairs((GD.companyPortfolio and GD.companyPortfolio.companies) or {}) do
        remapStockMarketNames(record.state and record.state.stockMarket)
    end
end

--- Import old top-level and company-snapshot city data without replacing populated personal data.
function GD.MigratePersonalCityOperations(legacyRoot, portfolio)
    if not GD.EnsurePersonalCityOperations() then return false end
    local operations = GD.player.cityOperations
    local function mergeSource(source, companyState)
        if type(source) ~= "table" then return end
        local migratedBookedDebt = 0
        local creditTables = source.cityCreditData
        if type(creditTables) == "table" then
            for _, cityData in pairs(creditTables) do
                for _, loan in ipairs(cityData.loans or {}) do
                    if loan.active and loan.bookedDebt then
                        migratedBookedDebt = migratedBookedDebt + (loan.remaining or loan.amount or 0)
                        loan.bookedDebt = false
                    end
                end
            end
        end
        if migratedBookedDebt > 0 and companyState then
            companyState.totalDebt = math.max(0, (companyState.totalDebt or 0) - migratedBookedDebt)
        end
        for operationType, field in pairs(PERSONAL_CITY_OPERATION_FIELDS) do
            mergeCityOperationTable(operations[operationType], source[field])
        end
    end

    local records = portfolio and portfolio.companies or {}
    -- 旧顶层运行态和公司快照都可能各自计入信用社负债，分别迁移并冲减其对应公司口径。
    mergeSource(legacyRoot, GD.company)
    for _, record in ipairs(records or {}) do
        local state = record and record.state
        mergeSource(state, state and state.company)
        if type(state) == "table" then
            for _, field in pairs(PERSONAL_CITY_OPERATION_FIELDS) do state[field] = nil end
        end
    end
    for _, cityData in pairs(operations.credit or {}) do
        for _, loan in ipairs(cityData.loans or {}) do loan.bookedDebt = false end
    end
    return GD.EnsurePersonalCityOperations()
end

local COMPANY_STATE_FIELDS = {
    "company", "projects", "loans", "fixedAssets", "finance", "brand",
    "landReserve", "assetListings", "rentalListings", "assetMarket",
    "equityInvestments", "_compLoans",
    "monthlyLedger", "ledgerHistory", "stockMarket",
}

local function resetCompanyScopedRuntime()
    GD.company = createFreshCompanyData()
    GD.projects = {}
    GD.loans = {}
    GD.fixedAssets = {}
    GD.finance = FN.InitFinanceData()
    GD.brand = BR.InitBrandData()
    GD.landReserve = {}
    GD.assetListings = {}
    GD.rentalListings = {}
    GD.assetMarket = {listings = {}, lastRefreshMonth = 0, nextId = 1}
    GD.equityInvestments = {}
    GD._compLoans = {}
    GD.monthlyLedger = {}
    GD.ledgerHistory = {}
    GD.stockMarket = nil
end

local function getCompanyFounderRatio(company)
    local gov = company and company.governance
    if not gov then return 0 end
    if gov.founderRatio then return gov.founderRatio end
    for _, sh in ipairs(gov.shareholders or {}) do
        if sh.id == "founder" then
            return (sh.shares or 0) / math.max(1, gov.totalShares or 1)
        end
    end
    return 0
end

local function normalizeCompanyRecord(record)
    if not record then return end
    record.id = record.id or ("co_" .. tostring(GD.companyPortfolio.nextId or 1))
    record.status = record.status or "operating"
    record.state = record.state or {}
    local company = record.state.company or record.company or {}
    record.name = record.name or company.name or "未命名公司"
    record.city = record.city or company.city or ""
    record.nature = record.nature or company.nature or "private"
    record.cash = company.cash or record.cash or 0
    record.totalAssets = company.totalAssets or record.totalAssets or 0
    record.totalDebt = company.totalDebt or record.totalDebt or 0
    record.monthlyProfit = company.monthlyProfit or record.monthlyProfit or 0
    record.projectCount = #(record.state.projects or {})
    record.founderRatio = getCompanyFounderRatio(company)
end

local function findCompanyRecord(companyId)
    if not companyId then return nil end
    GD.EnsureCompanyPortfolio(false)
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        if tostring(record.id) == tostring(companyId) then return record end
    end
    return nil
end

function GD.EnsureCompanyPortfolio(migrateCurrent)
    if type(GD.companyPortfolio) ~= "table" then
        GD.companyPortfolio = {nextId = 1, activeId = nil, companies = {}}
    end
    local portfolio = GD.companyPortfolio
    portfolio.companies = portfolio.companies or {}
    portfolio.nextId = portfolio.nextId or 1
    if portfolio.activeId == nil and GD.activeCompanyId ~= nil then
        portfolio.activeId = GD.activeCompanyId
    end

    local maxId = 0
    for _, record in ipairs(portfolio.companies) do
        normalizeCompanyRecord(record)
        local num = tonumber(tostring(record.id):match("co_(%d+)"))
        if num and num > maxId then maxId = num end
    end
    if portfolio.nextId <= maxId then portfolio.nextId = maxId + 1 end

    if migrateCurrent ~= false and #portfolio.companies == 0 and GD.company and (GD.company.name or "") ~= "" then
        GD.CaptureActiveCompanyState("operating")
    end
end

function GD.HasActiveOperatingCompany()
    if not GD.activeCompanyId then return false end
    local record = findCompanyRecord(GD.activeCompanyId)
    return record ~= nil
        and record.status == "operating"
        and (record.founderRatio or 0) >= 0.50
        and GD.company and (GD.company.name or "") ~= ""
end

function GD.MigrateSharedLandMarket()
    local seen = {}
    for _, land in ipairs(GD.landMarket or {}) do
        if land.id then seen[tostring(land.id)] = true end
    end
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        local state = record.state
        if state and state.landMarket then
            for _, land in ipairs(state.landMarket) do
                LA.EnsureLandFields(land)
                local id = land.id and tostring(land.id) or nil
                if id and not seen[id] and GD.IsMarketLand(land) then
                    table.insert(GD.landMarket, land)
                    seen[id] = true
                end
            end
            state.landMarket = nil
        end
    end
end

function GD.NormalizeLandOwnership()
    for _, land in ipairs(GD.landReserve or {}) do
        land.ownerType = "player_company"
        land.ownerCompanyId = land.ownerCompanyId or GD.activeCompanyId
    end
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        local state = record.state
        for _, land in ipairs(state and state.landReserve or {}) do
            land.ownerType = "player_company"
            land.ownerCompanyId = land.ownerCompanyId or record.id
        end
    end
    for _, land in ipairs(GD.landMarket or {}) do
        if land.channel == LA.CHANNELS.SECONDARY and not land.ownerCompanyId then
            land.ownerType = land.ownerType or "npc"
        end
    end
end

local function appendCompanyLedger(state, incomeOrExpense, category, desc, amount)
    if not state or not state.monthlyLedger or amount == 0 then return end
    table.insert(state.monthlyLedger, {
        type = incomeOrExpense,
        category = category,
        desc = desc,
        amount = math.abs(amount),
    })
end

function GD.ListLandForSecondarySale(landId, askingPrice)
    GD.CaptureActiveCompanyState()
    local record = findCompanyRecord(GD.activeCompanyId)
    if not record then return false, "当前公司状态不存在" end
    local reserve = record.state.landReserve or {}
    local landIndex, land = nil, nil
    for i, candidate in ipairs(reserve) do
        if tostring(candidate.id) == tostring(landId) then
            landIndex, land = i, candidate
            break
        end
    end
    if not land then return false, "未找到该公司土地" end
    for _, project in ipairs(record.state.projects or {}) do
        if project.land and tostring(project.land.id) == tostring(land.id) then
            return false, "已绑定项目的土地不能挂牌转让" end
    end
    if land.jointBid or land.mortgageId or land.isMortgaged then
        return false, "联合拿地或抵押土地不能挂牌转让" end
    local price = math.floor(tonumber(askingPrice) or tonumber(land.price) or tonumber(land.startPrice) or 0)
    if price <= 0 then return false, "挂牌价必须大于0" end

    table.remove(reserve, landIndex)
    land.channel = LA.CHANNELS.SECONDARY
    land.status = "for_sale"
    land.ownerType = "player_company"
    land.ownerCompanyId = record.id
    land.sellerCompanyId = record.id
    land.sellerCompanyName = record.name or record.state.company.name
    land.channelData = land.channelData or {}
    land.channelData.askingPrice = price
    land.channelData.sellerName = land.sellerCompanyName
    land.channelData.sellerType = "player_company"
    land.channelData.listedByCompanyId = record.id
    land.channelData.listedMonth = GD.totalMonths
    table.insert(GD.landMarket, land)
    GD.landReserve = reserve
    GD.AddEvent("" .. land.location .. "已挂牌二手土地，挂牌价" .. GD.FormatMoney(price), "info")
    GD.CaptureActiveCompanyState("operating")
    return true, "土地已挂牌，其他公司可发起议价"
end

function GD.BuySecondaryLand(landId, offerPrice, buyerCompanyId)
    GD.CaptureActiveCompanyState()
    local buyerId = buyerCompanyId or GD.activeCompanyId
    local buyerRecord = findCompanyRecord(buyerId)
    if not buyerRecord or buyerRecord.status ~= "operating" then
        return false, "买方公司不存在或已退出" end
    normalizeCompanyRecord(buyerRecord)
    if (buyerRecord.founderRatio or 0) < 0.50 then
        return false, "买方公司持股不足，不能执行土地购买" end
    local buyerCompany = buyerRecord.state and buyerRecord.state.company
    if not buyerCompany then return false, "买方公司状态缺失" end

    local marketIndex, land = nil, nil
    for i, candidate in ipairs(GD.landMarket or {}) do
        if tostring(candidate.id) == tostring(landId) then
            marketIndex, land = i, candidate
            break
        end
    end
    if not land then return false, "二手土地已下架或不存在" end
    if land.channel ~= LA.CHANNELS.SECONDARY or land.status ~= "for_sale" then
        return false, "该土地当前不可二手交易" end
    local sellerId = land.ownerCompanyId or land.sellerCompanyId
    if not sellerId or tostring(sellerId) == tostring(buyerId) then
        return false, "买卖双方无效，不能自买自卖" end
    local sellerRecord = findCompanyRecord(sellerId)
    if not sellerRecord or not sellerRecord.state then
        return false, "卖方公司不存在" end
    local sellerCompany = sellerRecord.state.company
    if not sellerCompany then return false, "卖方公司状态缺失" end
    if buyerCompany.city ~= land.city then
        return false, "买方公司只能购买注册城市的土地" end
    normalizeCompanyRecord(sellerRecord)
    if sellerRecord.status ~= "operating" then
        return false, "卖方公司已退出，不能交易" end

    local asking = tonumber(land.channelData and land.channelData.askingPrice) or tonumber(land.startPrice) or 0
    local offer = math.floor(tonumber(offerPrice) or 0)
    if asking <= 0 or offer <= 0 then return false, "报价必须大于0" end
    local accepted, message, finalPrice = LA.EvaluateSecondaryOffer(land, offer)
    if not accepted then return false, message end
    if (buyerCompany.cash or 0) < finalPrice then return false, "买方公司现金不足" end

    local sellerReserve = sellerRecord.state.landReserve or {}
    for _, sellerLand in ipairs(sellerReserve) do
        if tostring(sellerLand.id) == tostring(land.id) then
            return false, "卖方土地储备状态异常，交易已取消"
        end
    end

    buyerCompany.cash = (buyerCompany.cash or 0) - finalPrice
    sellerCompany.cash = (sellerCompany.cash or 0) + finalPrice
    appendCompanyLedger(buyerRecord.state, "expense", "二手土地购置", "购买" .. tostring(land.location or land.id), finalPrice)
    appendCompanyLedger(sellerRecord.state, "income", "二手土地转让", "出售" .. tostring(land.location or land.id), finalPrice)

    land.price = finalPrice
    land.startPrice = finalPrice
    land.status = "sold"
    land.ownerCompanyId = buyerId
    land.sellerCompanyId = sellerId
    land.acquiredMonth = GD.totalMonths
    land.channelData.askingPrice = nil
    table.insert(buyerRecord.state.landReserve, land)
    table.remove(GD.landMarket, marketIndex)

    sellerRecord.cash = sellerCompany.cash or 0
    sellerRecord.totalAssets = sellerCompany.totalAssets or sellerRecord.totalAssets or 0
    sellerRecord.totalDebt = sellerCompany.totalDebt or sellerRecord.totalDebt or 0
    buyerRecord.cash = buyerCompany.cash or 0
    buyerRecord.totalAssets = buyerCompany.totalAssets or buyerRecord.totalAssets or 0
    buyerRecord.totalDebt = buyerCompany.totalDebt or buyerRecord.totalDebt or 0
    if tostring(buyerId) == tostring(GD.activeCompanyId) then
        GD.company = buyerCompany
        GD.landReserve = buyerRecord.state.landReserve
        GD.CaptureActiveCompanyState("operating")
    elseif tostring(sellerId) == tostring(GD.activeCompanyId) then
        GD.company = sellerCompany
        GD.landReserve = sellerRecord.state.landReserve
        GD.CaptureActiveCompanyState("operating")
    end
    return true, message .. "，已完成公司间土地转让", finalPrice
end

function GD.CaptureActiveCompanyState(status, reason)
    GD.EnsureCompanyPortfolio(false)
    if not GD.company or (GD.company.name or "") == "" then return nil end

    local portfolio = GD.companyPortfolio
    local id = GD.activeCompanyId or portfolio.activeId
    local record = id and findCompanyRecord(id) or nil
    if not record then
        id = "co_" .. tostring(portfolio.nextId or 1)
        portfolio.nextId = (portfolio.nextId or 1) + 1
        record = {id = id, createdYear = GD.year, createdMonth = GD.month, status = "operating"}
        table.insert(portfolio.companies, record)
    end

    portfolio.activeId = id
    GD.activeCompanyId = id
    record.status = status or record.status or "operating"
    record.exitReason = reason or record.exitReason
    if status == "sold" or status == "bankrupt" then
        record.exitYear = GD.year
        record.exitMonth = GD.month
    end
    record.lastActiveYear = GD.year
    record.lastActiveMonth = GD.month
    record.name = GD.company.name or record.name or "未命名公司"
    record.city = GD.company.city or record.city or ""
    record.nature = GD.company.nature or record.nature or "private"
    record.cash = GD.company.cash or 0
    record.totalAssets = GD.company.totalAssets or 0
    record.totalDebt = GD.company.totalDebt or 0
    record.monthlyProfit = GD.company.monthlyProfit or 0
    record.projectCount = #(GD.projects or {})
    record.founderRatio = getCompanyFounderRatio(GD.company)

    local state = {}
    for _, field in ipairs(COMPANY_STATE_FIELDS) do
        state[field] = deepCopy(GD[field])
    end
    record.state = state
    return record
end

local function applyCompanyRecord(record)
    if not record or record.status ~= "operating" then return false, "该公司已退出，不能切换经营" end
    normalizeCompanyRecord(record)
    if (record.founderRatio or 0) < 0.50 then
        return false, "个人持股低于50%，仅保留分红权，不能进入公司操作"
    end
    local state = record.state or {}
    resetCompanyScopedRuntime()
    for _, field in ipairs(COMPANY_STATE_FIELDS) do
        if state[field] ~= nil then GD[field] = deepCopy(state[field]) end
    end
    if not GD.company or (GD.company.name or "") == "" then return false, "公司数据缺失" end
    if not GD.finance then GD.finance = FN.InitFinanceData() end
    FN.EnsureFinanceFields(GD.finance)
    if not GD.brand then GD.brand = BR.InitBrandData() else BR.EnsureBrandFields(GD.brand) end
    if not GD.assetMarket then GD.assetMarket = {listings = {}, lastRefreshMonth = 0, nextId = 1} end
    if GD.company.governance then GV.EnsureGovernanceFields(GD.company.governance, GD.player and GD.player.founderName) end
    PC.EnsureCompanyFields(GD.company)
    PC.EnsureKeyPositionFields(GD.company)
    PC.EnsureRegionalFields(GD.company)
    GD.companyPortfolio.activeId = record.id
    GD.activeCompanyId = record.id
    GD.NormalizeProjectNames()
    if GD.NormalizeRentalListingsAfterLoad then GD.NormalizeRentalListingsAfterLoad() end
    GD.EnsurePersonalCityOperations()
    if GD.EnsureCityBankFields then
        for _, bank in pairs(GD.cityBankData or {}) do GD.EnsureCityBankFields(bank) end
    end
    GD.company.isGameOver = GD.company.isGameOver or false
    GD.company.showCashCrisis = GD.company.showCashCrisis or false
    GD.gameStarted = true
    GD.paused = false
    return true
end

function GD.SwitchCompany(companyId, activeStateAlreadyCaptured)
    GD.EnsureCompanyPortfolio(true)
    if GD.activeCompanyId and tostring(GD.activeCompanyId) == tostring(companyId) then
        return true, "已在经营该公司"
    end
    if not activeStateAlreadyCaptured then
        GD.CaptureActiveCompanyState()
    end
    local record = findCompanyRecord(companyId)
    local ok, msg = applyCompanyRecord(record)
    if ok then
        GD.AddEvent("已切换经营公司：" .. (record.name or "未命名公司"), "success")
        return true, "已切换到" .. (record.name or "该公司")
    end
    return false, msg or "公司切换失败"
end

function GD.RenameActiveCompany(newName)
    if not GD.HasActiveOperatingCompany() then
        return false, "当前没有可经营的公司"
    end

    local normalizedName = tostring(newName or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    local nameLength = utf8.len(normalizedName)
    if not nameLength then
        return false, "公司名称包含无效字符"
    end
    if nameLength < 2 then
        return false, "公司名称至少2个字"
    end
    if nameLength > 20 then
        return false, "公司名称最多20个字"
    end
    if normalizedName:find("[%c\r\n]") then
        return false, "公司名称不能包含换行或控制字符"
    end
    if normalizedName == GD.company.name then
        return false, "新名称与当前名称相同"
    end

    GD.EnsureCompanyPortfolio(true)
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        normalizeCompanyRecord(record)
        if tostring(record.id) ~= tostring(GD.activeCompanyId)
            and GD.IsCompanyPortfolioVisible(record)
            and record.name == normalizedName then
            return false, "已有同名公司，请使用其他名称"
        end
    end

    local oldName = GD.company.name
    GD.company.name = normalizedName
    local record = GD.CaptureActiveCompanyState("operating")
    if not record then
        GD.company.name = oldName
        return false, "公司改名失败，请稍后重试"
    end

    GD.AddEvent("公司已由“" .. oldName .. "”更名为“" .. normalizedName .. "”", "success")
    print("[COMPANY-RENAME] companyId=" .. tostring(record.id)
        .. " oldName=" .. tostring(oldName)
        .. " newName=" .. normalizedName)
    return true, "公司名称已更新"
end

function GD.IsCompanyPortfolioVisible(record)
    return record ~= nil
        and record.status ~= "sold"
        and (record.founderRatio or 0) > 0
end

function GD.GetCompanyPortfolioSummary(captureCurrent)
    if captureCurrent ~= false then GD.CaptureActiveCompanyState() end
    GD.EnsureCompanyPortfolio(true)
    local list = {}
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        normalizeCompanyRecord(record)
        if GD.IsCompanyPortfolioVisible(record) then
            table.insert(list, record)
        end
    end
    return list
end

function GD.PrepareRuntimeForNewCompany()
    GD.CaptureActiveCompanyState()
    resetCompanyScopedRuntime()
    GD.EnsurePersonalCityOperations()
    GD.companyPortfolio.activeId = nil
    GD.activeCompanyId = nil
    GD.gameStarted = false
    GD.paused = false
end

function GD.ReleaseActiveCompanyControl(reason)
    local record = GD.CaptureActiveCompanyState("operating", reason)
    if not record then return false, "当前公司数据缺失" end
    record.status = "operating"
    record.founderRatio = getCompanyFounderRatio(record.state and record.state.company)
    GD.companyPortfolio.activeId = nil
    GD.activeCompanyId = nil
    resetCompanyScopedRuntime()
    GD.EnsurePersonalCityOperations()
    GD.gameStarted = true
    GD.paused = true
    GD._pendingCashCrisisPopup = false
    return true
end

function GD.MarkActiveCompanyExited(status, reason)
    local exited = GD.CaptureActiveCompanyState(status or "sold", reason)
    if exited then
        exited.status = status or "sold"
        exited.exitReason = reason or exited.exitReason
        exited.exitYear = GD.year
        exited.exitMonth = GD.month
    end
    GD.companyPortfolio.activeId = nil
    GD.activeCompanyId = nil

    local nextRecord = nil
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        if record.status == "operating"
            and record.id ~= (exited and exited.id)
            and (record.founderRatio or 0) >= 0.50 then
            nextRecord = record
            break
        end
    end
    if nextRecord then
        applyCompanyRecord(nextRecord)
        return true, "已退出原公司，并切换到" .. (nextRecord.name or "另一家公司")
    end

    resetCompanyScopedRuntime()
    GD.EnsurePersonalCityOperations()
    GD.gameStarted = true
    GD.paused = true
    GD._pendingCashCrisisPopup = false
    return true, "已退出原公司，可继续在任意城市创办新公司"
end

function GD.ResetCompanyForNewStart(reason)
    GD.MarkActiveCompanyExited("sold", reason or "旧公司已退出，可重新成立新公司")
end

-- ============================================================================
-- 城市数据
-- ============================================================================
GD.cities = {
    {name="兰德市", tier=3, gdp=13200, population=1042, avgPrice=10000, growth=0.06, infrastructureLevel=3, infrastructureCapacity=1120, policy="宽松",     policyStrength=1, inventory=18, compete=0.30, potential=65},
    {name="齐隆市", tier=3, gdp=7500,  population=862,  avgPrice=12000, growth=0.04, infrastructureLevel=3, infrastructureCapacity=930, policy="宽松",     policyStrength=1, inventory=20, compete=0.25, potential=60},
    {name="罗江市", tier=3, gdp=5600,  population=707,  avgPrice=8000,  growth=0.02, infrastructureLevel=2, infrastructureCapacity=755, policy="无限购",   policyStrength=0, inventory=24, compete=0.15, potential=45},
    {name="华尔市", tier=3, gdp=4900,  population=622,  avgPrice=7500,  growth=0.03, infrastructureLevel=2, infrastructureCapacity=680, policy="无限购",   policyStrength=0, inventory=22, compete=0.18, potential=48},
    {name="山花市", tier=3, gdp=5200,  population=880,  avgPrice=9000,  growth=0.04, infrastructureLevel=3, infrastructureCapacity=950, policy="宽松",     policyStrength=1, inventory=19, compete=0.22, potential=55},
    {name="西北市", tier=3, gdp=3400,  population=438,  avgPrice=9500,  growth=0.02, infrastructureLevel=2, infrastructureCapacity=480, policy="无限购",   policyStrength=0, inventory=26, compete=0.12, potential=40},
    {name="鹿鸣市", tier=3, gdp=9100,  population=710,  avgPrice=11000, growth=0.03, infrastructureLevel=3, infrastructureCapacity=770, policy="宽松",     policyStrength=1, inventory=17, compete=0.28, potential=58},
    {name="许州市", tier=3, gdp=8500,  population=908,  avgPrice=10500, growth=0.05, infrastructureLevel=3, infrastructureCapacity=980, policy="宽松",     policyStrength=1, inventory=16, compete=0.26, potential=62},
    {name="会齐市", tier=3, gdp=5400,  population=606,  avgPrice=11500, growth=0.04, infrastructureLevel=3, infrastructureCapacity=660, policy="宽松",     policyStrength=1, inventory=21, compete=0.20, potential=52},
}

-- ============================================================================
-- 经济周期
-- ============================================================================
GD.economy = {
    cycle = "boom",             -- boom/recession/depression/recovery
    cycleMonth = 0,
    cycleDuration = 18,         -- 当前周期持续月数
    priceIndex = 100,           -- 房价指数(基准100)
    interestRate = 4.5,         -- 贷款基准利率%
    demandMultiplier = 1.0,     -- 需求倍数
    policyTrend = "neutral",    -- tighten/neutral/loosen
}

-- ============================================================================
-- 规划设计管理常量 (4.1-4.4)
-- ============================================================================
GD.LAYOUT_CONFIG = {
    row       = {name="行列式",   efficiency=0.72, priceMult=1.00, costMult=1.00, durationMult=1.0},
    courtyard = {name="围合式",   efficiency=0.65, priceMult=1.08, costMult=1.10, durationMult=1.1},
    tower     = {name="点式高层", efficiency=0.78, priceMult=1.05, costMult=1.15, durationMult=1.2},
}
GD.UNIT_MIX_CONFIG = {
    basic    = {name="刚需型", areaRange={80,100},  priceMult=0.90, speedMult=1.3},
    improved = {name="改善型", areaRange={120,140}, priceMult=1.10, speedMult=1.0},
    luxury   = {name="豪宅型", areaRange={180,250}, priceMult=1.40, speedMult=0.6},
}
GD.STYLE_CONFIG = {
    modern  = {name="现代简约", costMult=1.00, priceMult=1.00, demandMult=1.05},
    chinese = {name="新中式",   costMult=1.15, priceMult=1.10, demandMult=1.00},
    artdeco = {name="ArtDeco",  costMult=1.20, priceMult=1.15, demandMult=0.90},
    french  = {name="法式",     costMult=1.25, priceMult=1.20, demandMult=0.85},
}
GD.DESIGN_PHASE_DURATION = {concept=1, schematic=1, construction_drawing=1, review=0}
GD.REVIEW_STAGES = {
    {id="structure",  name="结构安全",  basePassRate=0.75},
    {id="fire",       name="消防审查",  basePassRate=0.80},
    {id="energy",     name="节能审查",  basePassRate=0.85},
    {id="thirdparty", name="第三方复核", basePassRate=0.70},
}
GD.COST_CAP_STANDARDS = {steelPerSqm=45, concretePerSqm=0.4, penaltyRate=0.10}

-- 前期手续政策：从立项到进入施工最多6个月，施工阶段不受此上限影响。
GD.PRECONSTRUCTION_POLICY = "six_month_cap"
GD.PRECONSTRUCTION_MAX_MONTHS = 6

function GD.EnsurePreconstructionFields(project)
    if not project then return end
    project.preconstructionPolicy = GD.PRECONSTRUCTION_POLICY
    if not project.startMonth then
        project.startMonth = GD.totalMonths or 0
    end
    local elapsed = tonumber(project.preconstructionElapsedMonths)
    if elapsed == nil then
        elapsed = math.max(0, (GD.totalMonths or 0) - (project.startMonth or 0))
    end
    project.preconstructionElapsedMonths = math.max(0, elapsed)
end

local function forcePreconstructionComplete(project)
    if not project or (project.status ~= "permits" and project.status ~= "design") then
        return false
    end

    local land = project.land or {}
    local d = project.design or {}
    project.design = d
    d.planning = d.planning or {
        confirmed = true,
        far = land.far or 2.0,
        density = land.density or 0.28,
        greenRate = land.greenRate or 0.30,
        heightLimit = land.heightLimit or 100,
        facilities = {kindergarten = false, communityRoom = false, affordable = 0},
    }
    d.scheme = d.scheme or {
        confirmed = true,
        layout = "row",
        unitMix = {{key = "basic", ratio = 60}, {key = "improved", ratio = 30}, {key = "luxury", ratio = 10}},
        efficiency = 0.72,
        schemeScore = 70,
    }
    d.costCap = d.costCap or {
        confirmed = true,
        steelPerSqm = 45,
        concretePerSqm = 0.4,
        optimizations = {},
        overrun = false,
        penalty = 0,
    }
    d.review = d.review or {currentStage = 0, stages = {}, reworkCost = 0}

    -- 尽量复用正常确认入口，确保面积、成本和规划字段与普通项目一致。
    if not d.planning.confirmed then
        local ok = GD.ConfirmPlanning(project)
        if not ok then
            d.planning.far = math.min(tonumber(d.planning.far) or 2.0, land.far or 99)
            d.planning.density = math.min(tonumber(d.planning.density) or 0.28, land.density or 1)
            d.planning.greenRate = math.max(tonumber(d.planning.greenRate) or 0.30, land.greenRate or 0)
            d.planning.heightLimit = math.min(tonumber(d.planning.heightLimit) or 100, land.heightLimit or 999)
            GD.ConfirmPlanning(project)
        end
    end
    d.planning.confirmed = true

    if not d.scheme.confirmed then
        GD.AutoConfirmScheme(project)
    end
    d.scheme.confirmed = true
    d.scheme.layout = d.scheme.layout or "row"
    d.scheme.efficiency = d.scheme.efficiency or 0.72
    d.scheme.schemeScore = d.scheme.schemeScore or 70

    if not d.costCap.confirmed then
        GD.AutoConfirmCostCap(project)
    end
    d.costCap.confirmed = true

    for _, permit in ipairs(project.permits or {}) do
        permit.progress = 100
        permit.status = "done"
    end
    d.review.currentStage = #GD.REVIEW_STAGES
    d.review.stages = {}
    for _, cfg in ipairs(GD.REVIEW_STAGES) do
        table.insert(d.review.stages, {
            id = cfg.id,
            name = cfg.name,
            status = "passed",
            attempts = 1,
        })
    end
    d.phase = "done"
    d.phaseProgress = 100
    project.status = "construction"
    project.cost = project.cost or {}
    project.cost.budgetPrecision = GD.COST_PRECISION_BY_PHASE["construction"] or 0.05
    GD.InitProcurementPackages(project)
    GD.AddEvent("【" .. project.name .. "】前期手续已满6个月，行政加急完成并进入施工", "warning")
    return true
end

-- ============================================================================
-- 开发类型 → 默认设计参数映射
-- ============================================================================
-- positioningTier: 1=基础/2=品质/3=高端，影响建安成本基准
GD.DEV_TYPE_DESIGN_DEFAULTS = {
    -- 销售型
    rigid_residential    = {positioning = "刚需",     positioningTier = 1, style = "modern",  layoutDefault = "row"},
    improved_residential = {positioning = "改善",     positioningTier = 2, style = "modern",  layoutDefault = "row"},
    luxury_residential   = {positioning = "高端",     positioningTier = 3, style = "french",  layoutDefault = "courtyard"},
    commercial_sale      = {positioning = "商业",     positioningTier = 2, style = "modern",  layoutDefault = "tower"},
    -- 持有型
    shopping_mall        = {positioning = "品质商业", positioningTier = 2, style = "modern",  layoutDefault = "courtyard"},
    -- 销售型（原持有型转换）
    office_building      = {positioning = "甲级写字楼", positioningTier = 2, style = "modern", layoutDefault = "tower"},
}

-- 持有型定位选项（替代销售型的刚需/改善/高端）
GD.HOLD_POSITIONING_OPTIONS = {
    shopping_mall       = {"社区商业", "品质商业", "高端商业"},
}

-- 持有型方案设计的业态配比（替代户型配比）
GD.HOLD_TENANT_MIX_CONFIG = {
    shopping_mall = {
        anchor   = {name = "主力店",   areaRange = {2000, 5000}, rentMult = 0.70, stabilityMult = 1.3},
        retail   = {name = "零售店",   areaRange = {50, 200},    rentMult = 1.20, stabilityMult = 0.9},
        dining   = {name = "餐饮店",   areaRange = {100, 500},   rentMult = 1.00, stabilityMult = 1.1},
    },

}

-- 根据定位文本获取 tier（用于成本计算）
function GD.GetPositioningTier(project)
    local dd = GD.DEV_TYPE_DESIGN_DEFAULTS[project.devTypeId]
    if dd then return dd.positioningTier or 1 end
    -- 销售型兼容旧逻辑
    local pos = project.design.positioning
    if pos == "高端" then return 3
    elseif pos == "改善" then return 2 end
    return 1
end

-- 根据 tier 获取基准建安成本
function GD.GetBaseBuildCostByTier(tier)
    if tier == 3 then return 8000
    elseif tier == 2 then return 5000
    else return 3500 end
end

-- ============================================================================
-- 6.1 四级成本科目体系
-- ============================================================================
GD.COST_SUBJECTS = {
    {id="land",      name="土地获取", children={
        {id="land_price",  name="土地出让金"},
        {id="land_tax",    name="契税"},
        {id="land_other",  name="拆迁补偿/其他"},
    }},
    {id="precost",   name="前期费用", children={
        {id="prec_design", name="设计费"},
        {id="prec_survey", name="勘察费"},
        {id="prec_permit", name="报建规费"},
        {id="prec_dd",     name="尽调费用"},
    }},
    {id="construct", name="建安成本", children={
        {id="con_civil",     name="土建工程"},
        {id="con_install",   name="安装工程"},
        {id="con_decor",     name="精装修"},
        {id="con_landscape", name="景观工程"},
    }},
    {id="infra",     name="基础设施", children={
        {id="inf_road",  name="道路管网"},
        {id="inf_power", name="供电供水"},
        {id="inf_green", name="绿化环保"},
    }},
    {id="auxiliary",  name="配套设施", children={
        {id="aux_community", name="社区配套"},
        {id="aux_comm",      name="商业配套"},
        {id="aux_parking",   name="停车设施"},
    }},
    {id="indirect",   name="间接费用", children={
        {id="ind_manage",  name="管理费"},
        {id="ind_market",  name="营销费"},
        {id="ind_consult", name="咨询顾问"},
    }},
    {id="financial",  name="财务费用", children={
        {id="fin_interest",   name="利息支出"},
        {id="fin_guarantee",  name="担保费"},
    }},
    {id="tax",        name="税费", children={
        {id="tax_vat",       name="增值税"},
        {id="tax_surcharge", name="附加税"},
        {id="tax_land_vat",  name="土增税"},
    }},
}

-- ============================================================================
-- 6.2 目标成本 vs 动态成本
-- ============================================================================
GD.COST_PRECISION_BY_PHASE = {
    permits      = 0.30,
    design       = 0.15,
    construction = 0.05,
    presale      = 0.05,
    delivery     = 0.05,
    completed    = 0.05,
}
GD.COST_ALERT_THRESHOLDS = {
    {level="green",  ratio=0.90, label="安全",  color="Success"},
    {level="yellow", ratio=1.00, label="预警",  color="Warning"},
    {level="red",    ratio=1.10, label="超支",  color="Danger"},
}

-- ============================================================================
-- 6.3 招采模式 & 科目
-- ============================================================================
GD.PROCUREMENT_MODES = {
    open   = {name="公开招标", minBidders=3, durationMonths=3, costSavingRange={0.05, 0.15}},
    invite = {name="邀请招标", minBidders=3, durationMonths=2, costSavingRange={0.03, 0.10}},
    single = {name="单一来源", minBidders=1, durationMonths=1, costSavingRange={0.00, 0.03}},
}
GD.PROCUREMENT_MODE_ORDER = {"open", "invite", "single"}

GD.PROCUREMENT_CATEGORIES = {
    {id="civil",      name="土建总包",  subject="con_civil",     defaultMode="open"},
    {id="install",    name="安装工程",  subject="con_install",   defaultMode="open"},
    {id="decoration", name="精装修",    subject="con_decor",     defaultMode="invite"},
    {id="landscape",  name="景观工程",  subject="con_landscape", defaultMode="invite"},
    {id="consulting", name="设计/咨询", subject="prec_design",   defaultMode="invite"},
}

GD.UNBALANCED_BID_THRESHOLD = 0.30

-- ============================================================================
-- 宏观经济指标 (2.1)
-- ============================================================================
GD.macro = ME.CreateMacro()

-- ============================================================================
-- 房地产政策周期 (2.2)
-- ============================================================================
GD.policy = ME.CreatePolicy()

-- ============================================================================
-- 活跃的黑天鹅事件（持续型）
-- ============================================================================
GD.activeBlackSwans = {}  -- {text, type, cat, remainMonths}

-- ============================================================================
-- 土地市场
-- ============================================================================
GD.landMarket = {}     -- 全局共享土地市场
GD.landReserve = {}    -- 当前经营公司的已获取土地储备
GD.landSupplyPlans = {} -- 城市供地计划：计划公布后三个月才释放招拍挂土地
GD.landSupplyCommitments = {} -- 已批准供地占用的城市新增承载量
GD.landSupplyAnnual = {} -- 城市年度实际供地记录：按城市和释放年份累计

GD.LAND_SUPPLY_PLAN_DELAY = 3
GD.LAND_MARKET_CAPACITY = 40
GD.LAND_ANNUAL_MINIMUM = 1 -- 每座城市每年至少实际释放1宗公开土地
GD.LAND_POPULATION_PER_PLOT = 5 -- 每宗供地按约5万人新增承载需求折算
GD.LAND_SAFE_HEADROOM_RATIO = 0.80

-- 闲置土地管控
GD.IDLE_LAND_LIMIT       = 12   -- 闲置月数上限（超过则政府收回）
GD.IDLE_LAND_WARNING      = 9   -- 闲置警告阈值（月）
GD.IDLE_LAND_COMPENSATION = 0.5 -- 政府收回补偿比例（50%地价）

-- ============================================================================
-- 项目列表
-- ============================================================================
GD.projects = {}

-- ============================================================================
-- 贷款列表
-- ============================================================================
GD.loans = {}

-- ============================================================================
-- 固定资产列表(自持物业入固定资产)
-- ============================================================================
GD.fixedAssets = {}

-- ============================================================================
-- 金融系统数据 (9.1~9.6)
-- ============================================================================
GD.finance = FN.InitFinanceData()

-- ============================================================================
-- 商业资产市场(资产交易中心 - 可购买的商业物业)
-- ============================================================================
GD.assetMarket = {
    listings = {},     -- 市场可购买列表
    lastRefreshMonth = 0,
    nextId = 1,
}

-- ============================================================================
-- 品牌与声誉系统 (12.1~12.3)
-- ============================================================================
GD.brand = BR.InitBrandData()

-- ============================================================================
-- 事件日志
-- ============================================================================
GD.events = {}
GD.notifications = {}

-- ============================================================================
-- 存档/礼包/兑换码
-- ============================================================================
GD.beginnerGiftClaimed = false
GD.adRewardCount = 0
GD.adRewardDayCount = 0   -- 当天已领取次数
GD.adRewardLastDay = 0    -- 上次领取的月内天（用于每日重置）
GD.redeemedCodes = {}
GD.musicVolume = 0.6       -- 背景音乐音量 0.0~1.0

-- ============================================================================
-- AI竞争对手
-- ============================================================================
GD.competitors = {
    {name="万和地产", type="龙头国企", cash=1000000, aggressive=0.3, style="稳健",   tier="S"},
    {name="保家集团", type="龙头民企", cash=800000,  aggressive=0.5, style="激进",   tier="S"},
    {name="绿洲控股", type="央企巨头", cash=600000,  aggressive=0.2, style="稳健",   tier="A"},
    {name="融盛控股", type="全国民企", cash=400000,  aggressive=0.7, style="激进",   tier="A"},
    {name="嘉禾置业", type="区域国企", cash=200000,  aggressive=0.4, style="保守",   tier="B"},
    {name="华通房产", type="民企新锐", cash=100000,  aggressive=0.8, style="激进",   tier="B"},
    {name="盛德地产", type="区域民企", cash=50000,   aggressive=0.5, style="均衡",   tier="C"},
    {name="瑞澜建设", type="港资企业", cash=30000,   aggressive=0.3, style="保守",   tier="C"},
    {name="天成置业", type="本地民企", cash=10000,   aggressive=0.6, style="激进",   tier="D"},
    {name="宏图房产", type="创业公司", cash=1000,    aggressive=0.9, style="激进",   tier="D"},
}
-- 股权投资记录: {compIdx, investAmount, equityRatio, totalDividends, investMonth, investYear}
GD.equityInvestments = {}
-- 同业借款持久化
GD._compLoans = {}

-- ============================================================================
-- 售罄检查（所有销售阶段通用）
-- ============================================================================
function GD._CheckAllUnitsSold(p)
    if not p or not p.sales then return end
    local unitPlan = p.unitPlan or {}
    if p.sales.totalUnits > 0
        and p.sales.soldUnits >= p.sales.totalUnits
        and not p.sales.allUnitsSold then
        p.sales.allUnitsSold = true
        -- 如果当前在 delivery 阶段，自动推进到 completed
        if p.status == "delivery" then
            p.status = "completed"
        end
        if unitPlan.holdUnits and unitPlan.holdUnits > 0 then
            -- 有自持部分：初始化物业运营
            if not p.operations then
                p.operations = {
                    status = "preparing",
                    mode = "property_mgmt",
                    monthsElapsed = 0,
                    prepareMonths = 0,
                }
            end
            if p.assets then
                p.assets.rentable = true
                p.assets.occupancyRate = p.assets.occupancyRate or 30
            end
            GD.AddEvent("【" .. p.name .. "】全部售罄！自持" .. unitPlan.holdUnits .. "套转入物业管理，请手动清盘", "success")
        else
            GD.AddEvent("【" .. p.name .. "】全部售罄！请在销售页面手动清盘", "success")
        end
    end
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

function GD.AddEvent(text, type)
    type = type or "info"
    table.insert(GD.events, 1, {
        text = text,
        type = type,
        year = GD.year,
        month = GD.month,
        time = GD.GetDateStr(),
    })
    if #GD.events > 50 then
        table.remove(GD.events, #GD.events)
    end
end

-- ============================================================================
-- 明细账单系统
-- ============================================================================
GD.monthlyLedger = {}       -- 当月明细
GD.ledgerHistory = {}       -- 历史月份明细（最多保留6个月）

--- 添加一条收支明细
---@param incomeOrExpense "income"|"expense" 收入或支出
---@param category string 分类（如"租金收入"、"工资支出"等）
---@param desc string 详细描述
---@param amount number 金额（万元，正数）
function GD.AddLedger(incomeOrExpense, category, desc, amount)
    if incomeOrExpense ~= "income" and incomeOrExpense ~= "expense" then
        print("[LEDGER] rejected invalid type=" .. tostring(incomeOrExpense)
            .. " category=" .. tostring(category))
        return false
    end
    amount = tonumber(amount)
    if not amount or amount == 0 then return false end
    amount = math.abs(amount)
    table.insert(GD.monthlyLedger, {
        type = incomeOrExpense,
        category = tostring(category or "未分类"),
        desc = tostring(desc or ""),
        amount = amount,
    })
    return true
end

--- 月度结算时归档当月明细
---@param completedYear number|nil 已完成账单所属年份；省略时使用当前年份
---@param completedMonth number|nil 已完成账单所属月份；省略时使用当前月份
function GD.ArchiveLedger(completedYear, completedMonth)
    if #GD.monthlyLedger > 0 then
        table.insert(GD.ledgerHistory, 1, {
            year = completedYear or GD.year,
            month = completedMonth or GD.month,
            entries = GD.monthlyLedger,
        })
        -- 最多保留6个月历史
        while #GD.ledgerHistory > 6 do
            table.remove(GD.ledgerHistory, #GD.ledgerHistory)
        end
    end
    GD.monthlyLedger = {}
end

--- 获取当月账单汇总
function GD.GetLedgerSummary(entries)
    entries = entries or GD.monthlyLedger
    local totalIncome = 0
    local totalExpense = 0
    local categories = {}
    for _, e in ipairs(entries) do
        if e.type == "income" then
            totalIncome = totalIncome + e.amount
        else
            totalExpense = totalExpense + e.amount
        end
        local key = tostring(e.type) .. "::" .. tostring(e.category)
        if not categories[key] then
            categories[key] = { type = e.type, category = e.category, total = 0, count = 0 }
        end
        categories[key].total = categories[key].total + e.amount
        categories[key].count = categories[key].count + 1
    end
    return { totalIncome = totalIncome, totalExpense = totalExpense, categories = categories }
end

function GD.FormatMoney(amount)
    if math.abs(amount) >= 10000 then
        return string.format("%.1f亿", amount / 10000)
    else
        return string.format("%.0f万", amount)
    end
end

function GD.GetQualName()
    return GD.company.qualNames[GD.company.qualification + 1] or "暂定级"
end

function GD.GetCityData(cityName)
    local targetCity = cityName or GD.company.city
    for _, c in ipairs(GD.cities) do
        if c.name == targetCity then return c end
    end
    return GD.cities[1]
end

function GD.GetDaysInMonth(m, y)
    local days = {31,28,31,30,31,30,31,31,30,31,30,31}
    if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then
        return 29
    end
    return days[m] or 30
end

function GD.GetDateStr()
    return string.format("%d年%02d月%02d日", GD.year, GD.month, GD.day)
end

-- ============================================================================
-- 生成土地 (委托 LandAcquisition 模块，多渠道编排)
-- ============================================================================
function GD.GetCityLandSupplyMetrics(cityName)
    local city = type(cityName) == "table" and cityName or GD.GetCityData(cityName)
    if not city then
        return {annualDemand = 0, headroom = 0, allowedPopulation = 0, plannedCount = 0}
    end
    local population = math.max(0, tonumber(city.population) or 0)
    local infrastructureCapacity = tonumber(city.infrastructureCapacity) or population
    local headroom = math.max(0, infrastructureCapacity - population)
    local annualDemand = math.max(0, population * math.max(0, tonumber(city.growth) or 0))
    local committedPopulation = math.max(0, tonumber(GD.landSupplyCommitments[city.name]) or 0)
    local allowedPopulation = math.min(
        annualDemand,
        math.max(0, headroom * GD.LAND_SAFE_HEADROOM_RATIO - committedPopulation)
    )
    local plannedCount = math.floor(allowedPopulation / math.max(1, GD.LAND_POPULATION_PER_PLOT) / 4)
    return {
        population = population,
        infrastructureCapacity = infrastructureCapacity,
        infrastructureLevel = tonumber(city.infrastructureLevel) or 1,
        headroom = headroom,
        annualDemand = annualDemand,
        allowedPopulation = allowedPopulation,
        plannedCount = math.max(0, plannedCount),
    }
end

function GD.IsMarketLand(land)
    return type(land) == "table"
        and (land.status == "available"
            or land.status == "negotiable"
            or land.status == "locked"
            or land.status == "for_sale")
end

local function countCityMarketLand(cityName)
    local count = 0
    for _, land in ipairs(GD.landMarket or {}) do
        if land.city == cityName and GD.IsMarketLand(land) then count = count + 1 end
    end
    return count
end

local function trimLandMarketCapacity()
    local capacity = math.max(27, tonumber(GD.LAND_MARKET_CAPACITY) or 40)
    while #GD.landMarket > capacity do
        local removed = false
        for i, land in ipairs(GD.landMarket) do
            if land.status == "available" then
                table.remove(GD.landMarket, i)
                removed = true
                break
            end
        end
        if not removed then break end
    end
end

function GD.GetCityLandSupplyPlan(cityName)
    local city = type(cityName) == "table" and cityName or GD.GetCityData(cityName)
    local plan = city and GD.landSupplyPlans and GD.landSupplyPlans[city.name] or nil
    if not plan then return nil end
    return plan
end

function GD.AdvanceLandSupplyPlans()
    GD.landSupplyPlans = GD.landSupplyPlans or {}
    GD.landSupplyCommitments = GD.landSupplyCommitments or {}
    GD.landSupplyAnnual = GD.landSupplyAnnual or {}
    local released = 0
    local announced = 0
    local totalMonths = GD.totalMonths or 0
    local releaseYear = GD.year or 2001
    local releaseYearKey = tostring(releaseYear)

    for _, city in ipairs(GD.cities or {}) do
        local plan = GD.landSupplyPlans[city.name]
        if not plan then
            local metrics = GD.GetCityLandSupplyMetrics(city)
            local plannedCount = metrics.plannedCount
            GD.landSupplyCommitments[city.name] =
                (tonumber(GD.landSupplyCommitments[city.name]) or 0)
                + plannedCount * GD.LAND_POPULATION_PER_PLOT
            GD.landSupplyPlans[city.name] = {
                city = city.name,
                announcedMonth = totalMonths,
                releaseMonth = totalMonths + GD.LAND_SUPPLY_PLAN_DELAY,
                plannedCount = metrics.plannedCount,
                infrastructureCapacity = metrics.infrastructureCapacity,
                annualDemand = metrics.annualDemand,
                status = "planned",
            }
            announced = announced + 1
        elseif plan.status == "planned" and (plan.releaseMonth or math.huge) <= totalMonths then
            local annualRecord = GD.landSupplyAnnual[city.name]
            local releasedThisYear = annualRecord
                and tonumber(annualRecord[releaseYearKey]) or 0
            local plannedCount = math.max(0, tonumber(plan.plannedCount) or 0)
            local annualMinimum = math.max(0, tonumber(GD.LAND_ANNUAL_MINIMUM) or 0)
            local minimumGap = math.max(0, annualMinimum - releasedThisYear)
            local targetReleaseCount = math.max(plannedCount, minimumGap)
            local remainingCapacity = math.max(0, (GD.LAND_MARKET_CAPACITY or 40) - #GD.landMarket)
            local releaseCount = math.min(targetReleaseCount, remainingCapacity)
            if releaseCount > 0 then
                local actualReleased = LA.GeneratePublicAuction({
                    city = city,
                    economy = GD.economy,
                    policy = GD.policy,
                    totalMonths = totalMonths,
                    year = GD.year,
                    month = GD.month,
                    landMarket = GD.landMarket,
                    strictCount = true,
                }, releaseCount)
                released = released + actualReleased
                if actualReleased > 0 then
                    annualRecord = annualRecord or {}
                    annualRecord[releaseYearKey] = releasedThisYear + actualReleased
                    GD.landSupplyAnnual[city.name] = annualRecord
                end
            end
            plan.status = "released"
            plan.releasedMonth = totalMonths
            plan.releasedCount = releaseCount
            local metrics = GD.GetCityLandSupplyMetrics(city)
            plannedCount = metrics.plannedCount
            GD.landSupplyCommitments[city.name] =
                (tonumber(GD.landSupplyCommitments[city.name]) or 0)
                + plannedCount * GD.LAND_POPULATION_PER_PLOT
            GD.landSupplyPlans[city.name] = {
                city = city.name,
                announcedMonth = totalMonths,
                releaseMonth = totalMonths + GD.LAND_SUPPLY_PLAN_DELAY,
                plannedCount = metrics.plannedCount,
                infrastructureCapacity = metrics.infrastructureCapacity,
                annualDemand = metrics.annualDemand,
                status = "planned",
                previousReleasedMonth = totalMonths,
            }
            announced = announced + 1
        end
    end
    trimLandMarketCapacity()
    return released, announced
end

function GD.EnsureLandMarketCityMinimum()
    -- 旧接口保留兼容，但不再无条件补足3块土地；供地只能来自三个月前公布的计划。
    return GD.AdvanceLandSupplyPlans()
end

function GD.GenerateLand()
    return GD.AdvanceLandSupplyPlans()
end

-- ============================================================================
-- 土地闲置信息
-- ============================================================================
---@param land table 土地对象
---@return table {idleMonths:number, isWarning:boolean, isExpired:boolean}
function GD.GetLandIdleInfo(land)
    local acquiredMonth = land.acquiredMonth or GD.totalMonths
    local idleMonths = GD.totalMonths - acquiredMonth
    return {
        idleMonths = idleMonths,
        isWarning  = idleMonths >= GD.IDLE_LAND_WARNING,
        isExpired  = idleMonths >= GD.IDLE_LAND_LIMIT,
    }
end

--- 构建已关联项目的土地ID集合（用于O(1)查找，避免O(n²)遍历）
---@return table<string, boolean>
local function buildLandProjectSet()
    local set = {}
    for _, p in ipairs(GD.projects) do
        if p.land then set[p.land.id] = true end
    end
    return set
end

--- 检查土地是否已有关联项目
---@param land table
---@param projectLandSet table|nil 预构建的集合（性能优化）
---@return boolean
local function landHasProject(land, projectLandSet)
    if projectLandSet then
        return projectLandSet[land.id] == true
    end
    -- 降级路径：无预构建集合时仍线性查找
    for _, p in ipairs(GD.projects) do
        if p.land and p.land.id == land.id then return true end
    end
    return false
end

-- ============================================================================
-- 闲置土地检查（每月调用）
-- ============================================================================
function GD.CheckIdleLands()
    -- 性能优化：预构建土地→项目映射集合，O(1)查找代替O(n)线性扫描
    local projectLandSet = buildLandProjectSet()
    -- 倒序遍历以安全移除
    for i = #GD.landReserve, 1, -1 do
        local land = GD.landReserve[i]
        if not landHasProject(land, projectLandSet) then
            local info = GD.GetLandIdleInfo(land)
            if info.isExpired then
                -- 政府收回，补偿50%地价
                local price = land.price or land.startPrice
                local compensation = math.floor(price * GD.IDLE_LAND_COMPENSATION)
                GD.company.cash = GD.company.cash + compensation
                table.remove(GD.landReserve, i)
                GD.AddEvent(land.location .. " 地块闲置超1年，被政府依法收回，获补偿 " .. GD.FormatMoney(compensation), "danger")
            elseif info.isWarning then
                GD.AddEvent(land.location .. " 已闲置 " .. info.idleMonths .. " 个月，超12个月将被政府收回！", "warning")
            end
        end
    end
end

-- ============================================================================
-- 项目名称规范化：跨公司全局唯一，且名称不包含“CEO”（大小写不敏感）
-- ============================================================================
local PROJECT_PHASE_NAMES = {"二期", "三期", "四期", "五期", "六期", "七期", "八期", "九期", "十期"}

local function cleanProjectName(name)
    name = tostring(name or "")
    if name:lower():find("ceo", 1, true) then return "" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function defaultProjectName(land, devTypeId)
    local typeDef = DT.GetType(devTypeId) or DT.GetType("rigid_residential")
    local typeName = typeDef and (typeDef.shortName or typeDef.name) or "地产"
    local location = land and (land.location or land.city) or "新城"
    return tostring(location) .. tostring(typeName) .. "项目"
end

---@param land table
---@param devTypeId string
---@param customName string|nil
---@param excludeProject table|nil
---@return string projectName
function GD.GetUniqueProjectName(land, devTypeId, customName, excludeProject)
    local baseName = cleanProjectName(customName)
    if baseName == "" then baseName = defaultProjectName(land, devTypeId) end

    local used = {}
    local activeId = GD.activeCompanyId or (GD.companyPortfolio and GD.companyPortfolio.activeId)
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        if tostring(record.id or "") ~= tostring(activeId or "") then
            for _, project in ipairs(record.state and record.state.projects or {}) do
                used[tostring(project.name or "")] = true
            end
        end
    end
    for _, project in ipairs(GD.projects or {}) do
        if project ~= excludeProject then
            used[tostring(project.name or "")] = true
        end
    end
    if not used[baseName] then return baseName end

    local suffixIndex = 1
    while true do
        local suffix = PROJECT_PHASE_NAMES[suffixIndex] or (tostring(suffixIndex + 1) .. "期")
        local candidate = baseName .. suffix
        if not used[candidate] then return candidate end
        suffixIndex = suffixIndex + 1
    end
end

--- 旧存档项目名称迁移：移除历史 CEO 字符并消除跨公司的重名。
function GD.NormalizeProjectNames()
    local used = {}
    local activeId = GD.activeCompanyId or (GD.companyPortfolio and GD.companyPortfolio.activeId)
    local function rewriteLinkedNames(projectId, oldName, newName)
        for _, asset in ipairs(GD.fixedAssets or {}) do
            if tostring(asset.projectId or "") == tostring(projectId or "") then
                asset.projectName = newName
                asset.name = newName
            end
        end
        for _, listing in ipairs(GD.rentalListings or {}) do
            if tostring(listing.projectId or "") == tostring(projectId or "") then
                listing.assetName = newName
            elseif listing.assetIdx and GD.fixedAssets and GD.fixedAssets[listing.assetIdx]
                and tostring(GD.fixedAssets[listing.assetIdx].projectId or "") == tostring(projectId or "")
            then
                listing.assetName = newName
            end
        end
        for _, listing in ipairs(GD.assetListings or {}) do
            if listing.projectId and tostring(listing.projectId) == tostring(projectId or "")
                or (not listing.projectId and listing.projectName == oldName)
            then
                listing.projectName = newName
            end
        end
        for _, investment in ipairs(GD.finance and GD.finance.coinvestments or {}) do
            if tostring(investment.projectId or "") == tostring(projectId or "") then
                investment.projectName = newName
            end
        end
    end
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        if tostring(record.id or "") ~= tostring(activeId or "") then
            local state = record.state or {}
            for _, otherProject in ipairs(state.projects or {}) do
                local otherOldName = tostring(otherProject.name or "")
                local otherCleaned = cleanProjectName(otherOldName)
                local otherBase = otherCleaned ~= "" and otherCleaned
                    or defaultProjectName(otherProject.land, otherProject.devTypeId)
                local otherName = otherBase
                local suffixIndex = 1
                while used[otherName] do
                    local suffix = PROJECT_PHASE_NAMES[suffixIndex] or (tostring(suffixIndex + 1) .. "期")
                    otherName = otherBase .. suffix
                    suffixIndex = suffixIndex + 1
                end
                otherProject.name = otherName
                used[otherName] = true
                if otherName ~= otherOldName then
                    for _, asset in ipairs(state.fixedAssets or {}) do
                        if tostring(asset.projectId or "") == tostring(otherProject.id or "") then
                            asset.projectName = otherName
                            asset.name = otherName
                        end
                    end
                    for _, listing in ipairs(state.rentalListings or {}) do
                        if tostring(listing.projectId or "") == tostring(otherProject.id or "") then
                            listing.assetName = otherName
                        end
                    end
                    for _, listing in ipairs(state.assetListings or {}) do
                        if listing.projectId and tostring(listing.projectId) == tostring(otherProject.id or "")
                            or (not listing.projectId and listing.projectName == otherOldName)
                        then
                            listing.projectName = otherName
                        end
                    end
                    for _, investment in ipairs(state.finance and state.finance.coinvestments or {}) do
                        if tostring(investment.projectId or "") == tostring(otherProject.id or "") then
                            investment.projectName = otherName
                        end
                    end
                    record.projectCount = #(state.projects or {})
                end
            end
        end
    end
    for _, project in ipairs(GD.projects or {}) do
        local oldName = tostring(project.name or "")
        local cleaned = cleanProjectName(oldName)
        local needsRename = cleaned == "" or used[cleaned] == true
        local newName = cleaned
        if needsRename then
            local baseName = defaultProjectName(project.land, project.devTypeId)
            newName = baseName
            local suffixIndex = 1
            while used[newName] do
                local suffix = PROJECT_PHASE_NAMES[suffixIndex] or (tostring(suffixIndex + 1) .. "期")
                newName = baseName .. suffix
                suffixIndex = suffixIndex + 1
            end
        end
        project.name = newName
        used[newName] = true

        if newName ~= oldName then
            rewriteLinkedNames(project.id, oldName, newName)
            GD.AddEvent("项目名称已规范为【" .. newName .. "】", "info")
        end
    end
end

-- ============================================================================
-- 从土地储备启动开发（创建项目）
-- ============================================================================
---@param landId string 土地ID
---@param devTypeId string 开发类型ID
---@param customName string|nil 自定义项目名
---@return boolean success
---@return string message
function GD.StartDevelopment(landId, devTypeId, customName, standardId)
    -- 查找土地
    local land = nil
    for _, l in ipairs(GD.landReserve) do
        if l.id == landId then land = l; break end
    end
    if not land then return false, "未找到该地块" end

    local companyCity = GD.company and GD.company.city or ""
    if companyCity ~= "" and land.city ~= companyCity then
        return false, "该公司注册地为" .. companyCity .. "，只能开发本城市项目"
    end

    -- 检查是否已有关联项目
    if landHasProject(land) then return false, "该地块已有项目在开发中" end

    -- 检查项目容量
    local canCreate, capMsg = PC.CanCreateProject(GD.company, GD.projects)
    if not canCreate then return false, capMsg end

    -- 检查开发类型适配性
    local cityData = GD.GetCityData(land.city)
    local cityTier = cityData and cityData.tier or GD.company.cityTier or 2
    local plotLocation = land.plotLocation or "suburb"
    local companyRep = BR.GetTotalReputation and BR.GetTotalReputation() or (GD.company.creditScore or 0)
    local suitOk, suitMsg = DT.CheckSuitability(devTypeId, cityTier, plotLocation, companyRep)
    if not suitOk then return false, suitMsg end

    -- 创建项目
    local project = GD.CreateProject(land, devTypeId, customName, standardId)
    land.developmentStarted = true
    return true, project.name .. " 项目已创建"
end

-- ============================================================================
-- 创建项目
-- ============================================================================
function GD.CreateProject(land, devTypeId, customName, standardId)
    -- 默认为刚需住宅(向后兼容)
    devTypeId = devTypeId or "rigid_residential"
    local typeDef = DT.GetType(devTypeId) or DT.GetType("rigid_residential")
    local devCategory = typeDef.category  -- "sale"/"hold"/"agency"
    standardId = standardId or "basic"

    -- 项目名称：统一清理 CEO 字符并保证跨公司全局唯一。
    local projectName = GD.GetUniqueProjectName(land, devTypeId, customName)

    local acquisitionLandCost = tonumber(land.price or land.startPrice) or 0
    local project = {
        id = "P" .. (#GD.projects + 1),
        name = projectName,
        land = land,
        devTypeId = devTypeId,
        devCategory = devCategory,
        standardId = standardId,             -- 开发标准: "basic"/"quality"/"premium"
        plotLocation = land.plotLocation or "suburb",  -- 地块位置: "core"/"suburb"
        -- 四证
        permits = {
            {name="国有土地使用证",     status="pending", progress=0, duration=1,  cost=0},
            {name="建设用地规划许可证", status="locked",  progress=0, duration=1,  cost=50},
            {name="建设工程规划许可证", status="locked",  progress=0, duration=1,  cost=100},
            {name="建筑工程施工许可证", status="locked",  progress=0, duration=0,  cost=80},
        },
        -- 设计 (根据开发类型自动设置默认定位和风格)
        design = {
            positioning = (GD.DEV_TYPE_DESIGN_DEFAULTS[devTypeId] or {}).positioning or "",
            style = (GD.DEV_TYPE_DESIGN_DEFAULTS[devTypeId] or {}).style or "modern",
            phase = "none",        -- none/concept/schematic/construction_drawing/review/done
            phaseProgress = 0,
            -- 4.1 规划指标
            planning = {
                confirmed = false,
                far = land.far or 2.0,
                density = land.density or 0.28,
                greenRate = land.greenRate or 0.30,
                heightLimit = land.heightLimit or 100,
                facilities = {
                    kindergarten = false,
                    communityRoom = false,
                    affordable = 0,    -- 保障房比例 0~0.15
                },
            },
            -- 4.2 方案设计
            scheme = {
                confirmed = false,
                layout = "",           -- "row"/"courtyard"/"tower"
                unitMix = {},          -- {{type="basic", ratio=0.5}, ...}
                efficiency = 0,        -- 得房率
                schemeScore = 0,       -- 方案综合评分 0-100
            },
            -- 4.3 限额设计
            costCap = {
                confirmed = false,
                steelPerSqm = 45,      -- kg/㎡
                concretePerSqm = 0.4,  -- m³/㎡
                optimizations = {},    -- {"basementHeight","pileType","facadeMaterial"}
                overrun = false,
                penalty = 0,
            },
            -- 4.4 图纸审查
            review = {
                currentStage = 0,      -- 0=未开始, 1-4=对应审查阶段
                stages = {},           -- 运行时由 UpdateDesign 初始化
                reworkCost = 0,
            },
        },
        -- 工程(7.1~7.5 详见 Construction.lua)
        construction = CS.InitConstructionData({ totalMonths = typeDef.totalMonths or 30 }),
        -- 成本
        -- 成本(6.1/6.2)
        cost = {
            landCost = acquisitionLandCost,  -- 土地成本（真实成交价优先，未成交时回退起始价）
            buildCost = 0,
            designCost = 0,
            marketingCost = 0,
            financeCost = 0,
            taxCost = 0,
            totalCost = acquisitionLandCost,  -- 初始值=真实土地成本，后续累加各项实际开发支出
            targetCost = 0,
            ddCost = 0,
            riskCost = 0,
            -- 6.1 四级科目明细 (subject_id -> amount)
            subjectDetail = {},
            -- 6.2 动态成本跟踪
            dynamicCost = 0,
            budgetPrecision = 0.30,
            alertLevel = "green",
        },
        -- 6.3 招采管理
        procurement = {
            packages = {},
            history = {},
        },
        -- 销售
        sales = {
            canPresale = false,    -- 是否达到预售条件(自动标记)
            canSell = false,       -- 是否正式开始销售(手动触发)
            basePrice = 0,         -- 当前售价(元/平)，调价会改变
            approvedOpeningPrice = 0, -- 批准开盘价，销售速度的永久基准
            packageBasePrice = 0,  -- 打包出售基准价(元/平)，首次定价/开售时锁定，不受后续涨跌价影响
            discount = 1.0,
            totalUnits = 0,
            soldUnits = 0,
            totalArea = 0,
            soldArea = 0,
            revenue = 0,           -- 累计回款(万元)
            monthlyVisits = 0,
            conversionRate = 0,
            -- 营销相关
            marketingBudget = 0,        -- 月营销预算(万元)
            totalMarketingCost = 0,     -- 累计营销支出(万元)
            activeChannels = {          -- 渠道开关
                selfSales = true,       -- 自销团队(默认开启)
                agency = false,         -- 代理公司
                distribution = false,   -- 分销渠道
                referral = false,       -- 全民营销(老带新)
            },
            promotionType = "none",     -- none/discount/gift/event
            promotionMonthsLeft = 0,    -- 促销剩余月数
            -- 8.1~8.5 营销子系统(详见 Marketing.lua)
            marketing = MK.InitMarketingData(),
        },
        -- 单元规划(玩家决策: 销售 vs 自持)
        unitPlan = {
            planned = false,       -- 是否已完成规划
            sellUnits = 0,         -- 计划销售套数
            holdUnits = 0,         -- 计划自持套数
            sellArea = 0,          -- 计划销售面积(平米)
            holdArea = 0,          -- 计划自持面积(平米)
            minHoldRatio = 0,      -- 最低自持比例(来自土地配建要求)
        },
        -- 自持物业资产
        assets = {
            rentable = false,              -- 是否可出租(竣工后为true)
            monthlyRentPricePerSqm = 0,    -- 月租金单价(元/平)
            occupancyRate = 0,             -- 出租率(0-100)
            monthlyRentIncome = 0,         -- 本月租金收入(万元)
            totalRentIncome = 0,           -- 累计租金收入(万元)
        },
        -- 物业管理(已售房源收物业费)
        propertyMgmt = {
            enabled = false,           -- 是否启用物业费收取
            feePerSqm = GD.GetDefaultPropertyFee and GD.GetDefaultPropertyFee(devTypeId) or 3.0,  -- 物业费单价(元/平/月)，按类型差异化
            collectionRate = 0,        -- 缴费率(0-100)，交付后逐步爬升
            monthlyIncome = 0,         -- 本月物业费收入(万元)
            totalIncome = 0,           -- 累计物业费收入(万元)
            serviceLevelIdx = 1,       -- 物业服务等级(1=基础 2=标准 3=高端)
            satisfactionRate = 80,     -- 业主满意度(影响缴费率)
            monthlyOperateCost = 0,    -- 月度物业运营成本(万元)
            staffCount = 0,            -- 物业人员数量
        },
        -- 状态
        status = "permits",        -- permits/design/construction/presale/delivery/completed
        startMonth = GD.totalMonths,
        preconstructionPolicy = GD.PRECONSTRUCTION_POLICY,
        preconstructionElapsedMonths = 0,
    }
    -- 自持比例不再强制，玩家可自由选择
    project.unitPlan.minHoldRatio = 0

    -- 计算成本(基于城市均价 × costRatio × 地块位置 × 开发标准 + 特质加成)
    local cityData = GD.GetCityData(land.city)
    local cityAvgPrice = cityData and cityData.avgPrice or 15000
    local unitBuildCost = DT.GetBuildCost(devTypeId, cityAvgPrice, project.plotLocation, standardId, GD.company.traitEffects.buildCostBonus or 0)
    project.cost.buildCost = math.floor(land.buildArea * unitBuildCost / 10000)
    project.cost.basePriceIndex = GD.economy.priceIndex  -- 记录立项时的市场指数，用于成本波动计算
    project.cost.designCost = math.floor(project.cost.buildCost * (typeDef.designCostRatio or 0.05))

    -- 尽调成本 & 隐性风险附加（Phase 3）
    local ddDirectCost = 0
    local ddRiskCost = 0
    local ddExtraMonths = 0
    if land.dueDiligence then
        ddDirectCost = land.dueDiligence.totalCost or 0
        -- 已发现的风险成本
        for _, risk in ipairs(land.dueDiligence.risks or {}) do
            ddRiskCost = ddRiskCost + (risk.costImpact or 0)
            ddExtraMonths = ddExtraMonths + (risk.monthsDelay or 0)
        end
        -- 跳过尽调的隐性风险（期望值）
        local hiddenCost, hiddenMonths = LA.CalcHiddenRiskCost(land)
        ddRiskCost = ddRiskCost + hiddenCost
        ddExtraMonths = ddExtraMonths + hiddenMonths
    end
    project.cost.ddCost = ddDirectCost         -- 尽调直接费用
    project.cost.riskCost = ddRiskCost         -- 风险附加成本
    local permitCost = 0
    for _, permit in ipairs(project.permits or {}) do
        permitCost = permitCost + math.max(0, tonumber(permit.cost) or 0)
    end
    project.cost.permitCost = permitCost
    project.cost.totalCost = project.cost.landCost + project.cost.designCost
        + ddDirectCost + ddRiskCost + permitCost
    project.cost.targetCost = project.cost.totalCost + project.cost.buildCost

    -- 6.1 初始化科目明细
    GD.InitCostSubjects(project)
    -- 6.2 初始化动态成本
    project.cost.dynamicCost = project.cost.targetCost
    project.cost.budgetPrecision = GD.COST_PRECISION_BY_PHASE[project.status] or 0.30

    -- 工期调整：尽调发现的风险延长工期
    if ddExtraMonths > 0 then
        project.construction.totalMonths = project.construction.totalMonths + ddExtraMonths
    end

    -- 按类别设置销售/运营/代建数据
    if devCategory == "sale" then
        project.sales.totalArea = math.floor(land.buildArea * 0.85) -- 可售面积
        project.sales.totalUnits = math.floor(project.sales.totalArea / 100)
    elseif devCategory == "hold" then
        -- 持有型: 不销售, 初始化运营数据
        project.sales.totalArea = 0
        project.sales.totalUnits = 0
        project.operations = OP.InitOperationsData(devTypeId, land.buildArea)
    elseif devCategory == "agency" then
        -- 代建型: 不销售, 初始化代建数据
        project.sales.totalArea = 0
        project.sales.totalUnits = 0
        project.agency = AF.InitAgencyData(devTypeId, project.cost.targetCost)
        if project.agency then
            project.agency.contract.signedMonth = GD.totalMonths
        end
    end

    -- 联合拿地合作方信息（从土地对象继承）
    if land.jointBid then
        local jb = land.jointBid
        project.jointBid = {
            partnerName = jb.partnerName,
            partnerSharePct = jb.partnerSharePct,   -- 合作方出资比例(%)
            playerSharePct = jb.playerSharePct,      -- 玩家出资比例(%)
            partnerLandCost = jb.partnerCost,        -- 合作方土地出资(万元)
            playerLandCost = jb.playerCost,           -- 玩家土地出资(万元)
            -- 动态字段：项目总投入和份额在清盘时按实际总成本重新计算
        }
    end

    -- 创建项目公司SPV(风险隔离)
    project.spv = {
        name = project.name .. "项目公司",
        registeredCapital = math.floor(project.cost.targetCost * 0.3), -- SPV注册资本约为总成本30%
        pnl = 0,
        established = GD.totalMonths,
    }

    -- 项目资金管理（多项目并行系统）
    project.budget = {
        allocated = 0,
        spent = 0,
        remaining = 0,
    }
    project.regionalCompanyIdx = nil   -- 所属区域公司索引(nil=总部直管)
    project.directorId = nil           -- 项目总ID(nil=未指派)

    -- 注: 土地成本已在竞拍/拿地时从公司现金扣除，不需要再拨付到项目预算
    -- 土地成本记入 project.cost.landCost 作为成本核算，但不影响项目预算流
    -- 项目预算(budget)仅用于跟踪建安、设计等后续支出

    -- 自动归属匹配城市的区域公司
    local regionIdx = PC.FindRegionByCity(GD.company, land.city or GD.company.city)
    if regionIdx then
        local ok = PC.AssignToRegion(GD.company, project.id, regionIdx)
        if ok then
            project.regionalCompanyIdx = regionIdx
        end
    end

    -- 代建型: 设计由委托方完成，自动确认所有设计子阶段
    if devCategory == "agency" then
        project.design.planning.confirmed = true
        project.design.scheme.confirmed = true
        project.design.scheme.layout = (GD.DEV_TYPE_DESIGN_DEFAULTS[devTypeId] or {}).layoutDefault or "row"
        project.design.scheme.efficiency = (GD.LAYOUT_CONFIG[project.design.scheme.layout] or {}).efficiency or 0.72
        project.design.scheme.schemeScore = 75
        project.design.scheme.unitMix = {{key = "basic", ratio = 100}}
        project.design.costCap.confirmed = true
        project.design.costCap.steelPerSqm = 42
        project.design.costCap.concretePerSqm = 0.38
        project.design.autoConfirmed = true -- 标记为自动确认(UI显示用)
    end

    table.insert(GD.projects, project)
    GD.AddEvent("新项目【" .. project.name .. "】已创建 [" .. typeDef.icon .. typeDef.name ..
        "/" .. DT.GetCategoryName(devCategory) .. "] (SPV: " .. project.spv.name .. ")", "success")
    return project
end

-- ============================================================================
-- 开发项目销售回款/打包出售辅助函数
-- ============================================================================
local function calcBatchRevenue(batch)
    if not batch then return 0 end
    local amount = batch.contractedRevenue or 0
    if amount <= 0 then
        amount = (batch.unitCount or 0) * (batch.unitRevenue or 0)
    end
    return math.max(0, math.floor(amount))
end

local function getProjectPackageBasePrice(project)
    if not project or not project.sales then return 0 end
    local sales = project.sales
    local basePrice = 0
    if (sales.packageBasePrice or 0) > 0 then
        basePrice = sales.packageBasePrice
    elseif (sales.approvedOpeningPrice or 0) > 0 then
        basePrice = sales.approvedOpeningPrice
    elseif (sales.basePrice or 0) > 0 then
        basePrice = sales.basePrice
    end
    if basePrice <= 0 then
        local city = GD.GetCityData(project.land and project.land.city)
        basePrice = city and city.avgPrice or 10000
    end
    if (sales.packageBasePrice or 0) <= 0 and basePrice > 0 then
        sales.packageBasePrice = basePrice
    end
    return basePrice
end

function GD.EnsureProjectPackageBasePrice(project)
    return getProjectPackageBasePrice(project)
end

local PROJECT_NET_MARGIN_MIN = -0.20
local PROJECT_NET_MARGIN_MAX = 0.30
local PROJECT_PROFIT_BUCKETS = {
    { maxHash = 9,  minMargin = -0.20, maxMargin = -0.08 }, -- 10%：明显亏损
    { maxHash = 24, minMargin = -0.08, maxMargin = 0.00 },  -- 15%：轻微亏损
    { maxHash = 64, minMargin = 0.00,  maxMargin = 0.12 },  -- 40%：常规微利
    { maxHash = 89, minMargin = 0.12,  maxMargin = 0.22 },  -- 25%：经营良好
    { maxHash = 99, minMargin = 0.22,  maxMargin = 0.30 },  -- 10%：优质项目
}

local function stableProjectProfitHash(project)
    local key = tostring(project and project.id or "") .. ":"
        .. tostring(project and project.name or "") .. ":"
        .. tostring(project and project.land and project.land.id or "")
    local hash = 0
    for i = 1, #key do
        hash = (hash * 131 + string.byte(key, i)) % 2147483647
    end
    return hash
end

local function stableProjectProfitMargin(project)
    local hash = stableProjectProfitHash(project)
    local bucketValue = hash % 100
    for _, bucket in ipairs(PROJECT_PROFIT_BUCKETS) do
        if bucketValue <= bucket.maxHash then
            local range = bucket.maxMargin - bucket.minMargin
            local fraction = (math.floor(hash / 100) % 1001) / 1000
            return bucket.minMargin + range * fraction
        end
    end
    return 0
end

--- 确保销售型项目拥有稳定的目标税后净利润率（-20%~30%）。
---@param project table
---@return number targetMargin
function GD.EnsureProjectProfitTarget(project)
    if not project or (project.devCategory or "sale") ~= "sale" then return 0 end
    project.profitModel = project.profitModel or {}
    if project.profitModel.targetNetMargin == nil then
        project.profitModel.targetNetMargin = tonumber(project.land and project.land.targetNetMargin)
            or stableProjectProfitMargin(project)
    end
    project.profitModel.targetNetMargin = math.max(PROJECT_NET_MARGIN_MIN,
        math.min(PROJECT_NET_MARGIN_MAX, tonumber(project.profitModel.targetNetMargin) or 0))
    return project.profitModel.targetNetMargin
end

local function getProjectedProjectRevenue(project)
    if not project or not project.sales then return 0 end
    local saleArea = math.max(0, (project.unitPlan and project.unitPlan.planned
        and project.unitPlan.sellArea) or project.sales.totalArea or 0)
    if saleArea <= 0 then return 0 end
    local price = project.sales.basePrice or 0
    if price <= 0 then
        local city = GD.GetCityData(project.land and project.land.city)
        local marketAvg = city and city.avgPrice or 15000
        price = DT.GetExpectedPrice(project.devTypeId, marketAvg,
            project.plotLocation or (project.land and project.land.plotLocation) or "suburb",
            project.standardId or "basic", project.land and project.land.floorPrice or 0)
        local layout = project.design and project.design.scheme and project.design.scheme.layout
        local style = project.design and project.design.style
        price = price * ((GD.LAYOUT_CONFIG[layout] or {}).priceMult or 1)
            * ((GD.STYLE_CONFIG[style] or {}).priceMult or 1)
            * ((GD.economy and GD.economy.priceIndex or 100) / 100)
    end
    return math.max(0, math.floor(saleArea * price / 10000))
end

--- 按目标税后利润率反推建安预算，土地成本保持真实成交价不变。
---@param project table
---@return boolean adjusted
function GD.RebalanceProjectDevelopmentCost(project)
    if not project or (project.devCategory or "sale") ~= "sale" or not project.cost then return false end
    local constructionMonthsElapsed = project.construction and project.construction.monthsElapsed or 0
    if constructionMonthsElapsed > 0 then return false end
    local projectedRevenue = getProjectedProjectRevenue(project)
    if projectedRevenue <= 0 then return false end
    local targetMargin = GD.EnsureProjectProfitTarget(project)
    local targetNetProfit = projectedRevenue * targetMargin
    local targetGrossProfit = targetNetProfit > 0 and (targetNetProfit / 0.80) or targetNetProfit
    local targetTotalCostBeforeTax = math.max(1, projectedRevenue - targetGrossProfit)
    local constructionMonths = math.max(1,
        project.construction and project.construction.totalMonths or 30)
    local estimatedFinanceCost = math.floor((project.cost.landCost or 0) * 0.04
        * constructionMonths / 12)
    local estimatedMarketingCost = math.floor(projectedRevenue * 0.03)
    local fixedCost = (project.cost.landCost or 0) + (project.cost.ddCost or 0)
        + (project.cost.riskCost or 0) + (project.cost.permitCost or 0)
        + estimatedFinanceCost + estimatedMarketingCost
    local buildAndDesign = math.max(1, targetTotalCostBeforeTax - fixedCost)
    local designCostRatio = (DT.GetType(project.devTypeId) or {}).designCostRatio or 0.05
    local previousDesignCost = project.cost.designCost or 0
    local buildCost = math.max(1, math.floor(buildAndDesign / (1 + designCostRatio)))
    project.cost.buildCost = buildCost
    project.cost.designCost = math.max(0, math.floor(buildCost * designCostRatio))
    project.cost.totalCost = math.max(0, (project.cost.totalCost or 0)
        - previousDesignCost + project.cost.designCost)
    project.cost.targetCost = (project.cost.landCost or 0) + buildCost
        + project.cost.designCost + (project.cost.ddCost or 0) + (project.cost.riskCost or 0)
        + (project.cost.permitCost or 0)
    project.profitModel.projectedRevenue = projectedRevenue
    project.profitModel.projectedTotalCostBeforeTax = targetTotalCostBeforeTax
    project.profitModel.projectedIncomeTax = targetGrossProfit > 0
        and math.floor(targetGrossProfit * 0.20) or 0
    project.profitModel.projectedTotalCost = targetTotalCostBeforeTax
        + project.profitModel.projectedIncomeTax
    project.profitModel.estimatedFinanceCost = estimatedFinanceCost
    project.profitModel.estimatedMarketingCost = estimatedMarketingCost
    print("[PROJECT-PROFIT] project=" .. tostring(project.name)
        .. " targetNetMargin=" .. string.format("%.2f%%", targetMargin * 100)
        .. " revenue=" .. tostring(projectedRevenue)
        .. " land=" .. tostring(project.cost.landCost or 0)
        .. " build=" .. tostring(project.cost.buildCost or 0)
        .. " projectedAllCost=" .. tostring(project.profitModel.projectedTotalCost or 0))
    return true
end

local function releaseEscrowNow(project)
    if not project or not GD.finance or not GD.finance.escrowAccounts then return 0 end
    local projectKey = project.id or project.name
    local esc = GD.finance.escrowAccounts[projectKey]
    if not esc and project.name then esc = GD.finance.escrowAccounts[project.name] end
    if not esc then return 0 end
    local total = esc.total or 0
    local released = esc.released or 0
    local amount = math.max(0, math.floor(total - released))
    if amount > 0 then
        esc.released = total
        GD.company.cash = GD.company.cash + amount
        GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + amount
        if GD.AddLedger then
            GD.AddLedger("income", "监管释放", (project.name or "项目") .. " 剩余监管资金释放", amount)
        end
    end
    return amount
end

--- 将项目签约队列中的未回款合同强制结算到账。
---@param project table
---@param reason string|nil
---@param immediateCash boolean|nil true=全额进入现金；false=按预售监管比例拆分
---@return number settledRevenue
function GD.SettlePendingSalesCollections(project, reason, immediateCash)
    if not project or not project.sales or not project.sales.marketing or not project.sales.marketing.collection then return 0 end
    local sales = project.sales
    local coll = sales.marketing.collection
    local queue = coll.signingQueue or {}
    local total = 0
    for _, batch in ipairs(queue) do
        total = total + calcBatchRevenue(batch)
    end
    if total <= 0 then
        coll.signingQueue = {}
        return 0
    end

    sales.revenue = (sales.revenue or 0) + total
    sales.monthRevenue = (sales.monthRevenue or 0) + total
    coll.collectedAmount = (coll.collectedAmount or 0) + total
    coll.signingQueue = {}

    if immediateCash then
        GD.company.cash = GD.company.cash + total
        GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + total
    else
        local presaleFundRatio = (GD.policy and GD.policy.regulation and GD.policy.regulation.presaleFundRatio) or 0.25
        local escrowAmount = math.floor(total * presaleFundRatio)
        local freeAmount = total - escrowAmount
        if freeAmount > 0 then
            GD.company.cash = GD.company.cash + freeAmount
            GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + freeAmount
        end
        if escrowAmount > 0 and GD.Finance and GD.Finance.DepositToEscrow then
            GD.Finance.DepositToEscrow(GD, project.id or project.name, escrowAmount)
        elseif escrowAmount > 0 then
            GD.company.cash = GD.company.cash + escrowAmount
            GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + escrowAmount
        end
    end

    if GD.AddLedger then
        GD.AddLedger("income", reason or "销售回款", (project.name or "项目") .. " 未回款合同结算", total)
    end
    GD.AddEvent("【" .. (project.name or "项目") .. "】未回款合同" .. GD.FormatMoney(total) .. "已结算到账", "success")
    return total
end

--- 预估项目剩余可打包出售价值（万元）。
---@param project table
---@return number amount
---@return table detail
function GD.PreviewProjectPackageSale(project)
    if not project or not project.sales then return 0, {reason = "项目不存在"} end
    local sales = project.sales
    local unitPlan = project.unitPlan or {}
    local basePrice = getProjectPackageBasePrice(project)

    local remainingUnits = math.max(0, (sales.totalUnits or 0) - (sales.soldUnits or 0))
    local remainingArea = 0
    if sales.totalUnits and sales.totalUnits > 0 and sales.totalArea then
        remainingArea = math.floor((sales.totalArea or 0) * remainingUnits / sales.totalUnits)
    else
        remainingArea = sales.totalArea or unitPlan.sellArea or 0
    end
    local unsoldRevenue = math.floor(remainingArea * basePrice / 10000)

    -- 自持部分保留为独立资产，不参与“剩余现房八折出售”。
    local holdArea = unitPlan.holdArea or 0
    local holdRevenue = 0
    if holdArea > 0 and not project._fixedAssetConverted then
        holdRevenue = math.floor(holdArea * basePrice / 10000)
    end

    local pendingRevenue = 0
    local coll = sales.marketing and sales.marketing.collection
    if coll and coll.signingQueue then
        for _, batch in ipairs(coll.signingQueue) do
            pendingRevenue = pendingRevenue + calcBatchRevenue(batch)
        end
    end

    local remainingValue = unsoldRevenue
    local amount = math.floor(remainingValue * 0.8)
    return amount, {
        basePrice = basePrice,
        remainingUnits = remainingUnits,
        remainingArea = remainingArea,
        unsoldRevenue = unsoldRevenue,
        holdRevenue = holdRevenue,
        pendingRevenue = pendingRevenue,
        totalBeforeDiscount = remainingValue,
        discount = 0.8,
    }
end

--- 判断项目是否已完成工程结算和竣工确认，可将预售后剩余现房八折出售。
---@param project table
---@return boolean canSell
---@return string reason
function GD.CanPackageSellProject(project)
    if not project then return false, "项目不存在" end
    if project.salesCleared or project.status == "sold_off" then return false, "项目已处置" end
    if (project.devCategory or "sale") ~= "sale" then return false, "仅销售型开发项目支持八折出售" end
    if not project.sales then return false, "项目缺少销售数据" end
    if project.sales.packageSold then return false, "项目剩余现房已八折出售" end
    if project.status ~= "delivery" and project.status ~= "completed" then
        return false, "项目必须先完成工程结算并确认竣工，预售后剩余现房才可八折出售"
    end
    if not project.settlement then
        return false, "项目尚未完成工程结算"
    end
    if not project.sales.isExistingHomeSale then
        return false, "项目尚未确认竣工或没有剩余现房"
    end
    local remainingUnits = math.max(0,
        (project.sales.totalUnits or 0) - (project.sales.soldUnits or 0))
    if remainingUnits <= 0 then
        return false, "没有可八折出售的剩余现房"
    end
    return true, ""
end

--- 一键八折出售竣工项目的剩余现房，之后仍须按正常税率清盘纳税。
---@param project table
---@return boolean success
---@return string message
---@return table|nil detail
function GD.PackageSellProjectToThirdParty(project)
    local canSell, reason = GD.CanPackageSellProject(project)
    if not canSell then return false, reason end

    local amount, detail = GD.PreviewProjectPackageSale(project)
    if amount <= 0 then return false, "没有可打包出售的剩余现房货值" end

    -- 已签约合同按原价回款，剩余现房按锁定开盘基准价的80%成交。
    local pendingRevenue = GD.SettlePendingSalesCollections(project, "项目八折现房出售", true)
    local cashBeforeSale = GD.company.cash
    local packageAmount = amount
    GD.company.cash = GD.company.cash + packageAmount
    GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + packageAmount
    project.sales.revenue = (project.sales.revenue or 0) + packageAmount
    project.sales.monthRevenue = (project.sales.monthRevenue or 0) + packageAmount
    project.sales.soldUnits = project.sales.totalUnits or project.sales.soldUnits or 0
    project.sales.allUnitsSold = true
    project.sales.canSell = false
    project.sales.canPresale = false
    project.sales.packageSold = true

    local escrowReleased = releaseEscrowNow(project)
    project.packageSale = {
        year = GD.year,
        month = GD.month,
        day = GD.day,
        amount = packageAmount,
        pendingRevenueSettled = pendingRevenue,
        escrowReleased = escrowReleased,
        cashBefore = cashBeforeSale,
        cashAfter = GD.company.cash,
        detail = detail,
        clearancePending = true,
        taxRate = 0.20,
    }
    project.status = "completed"
    project.clearanceSheet = nil

    -- 八折收入已计入项目销售收入；立即按正常项目所得税率生成清盘清单，缴税确认后才完成清盘。
    local _, clearanceMessage = GD.ManualClearance(project)
    if clearanceMessage == "clearance_sheet_ready" and project.clearanceSheet then
        project.packageSale.incomeTax = project.clearanceSheet.incomeTax or 0
        project.packageSale.grossProfit = project.clearanceSheet.grossProfit or 0
        project.packageSale.netProfitAfterTax = project.clearanceSheet.netProfitAfterTax or 0
    end

    print("[PACKAGE-SALE] project=" .. tostring(project.name)
        .. " remainingUnits=" .. tostring(detail.remainingUnits or 0)
        .. " packageRevenue=" .. tostring(packageAmount)
        .. " incomeTax=" .. tostring(project.packageSale.incomeTax or 0)
        .. " clearanceReady=" .. tostring(project.clearanceSheet ~= nil))

    GD.AddLedger("income", "项目八折出售", project.name .. " 竣工现房八折出售第三方", packageAmount)
    GD.AddEvent("【" .. project.name .. "】剩余现房已八折出售，收到" .. GD.FormatMoney(packageAmount)
        .. "；已生成清盘清单，须按正常税率缴税后完成清盘", "warning")
    if escrowReleased > 0 then
        GD.AddEvent("【" .. project.name .. "】同步释放监管余额" .. GD.FormatMoney(escrowReleased), "success")
    end
    return true, "八折出售完成，等待清盘缴税", detail
end

-- ============================================================================
-- 单元规划(玩家决定销售/自持分配)
-- ============================================================================
function GD.PlanUnits(project, sellUnits, holdUnits)
    local up = project.unitPlan
    if up.planned then return false, "该项目已完成单元规划" end
    local totalUnits = project.sales.totalUnits
    if sellUnits + holdUnits ~= totalUnits then
        return false, "销售+自持套数必须等于总套数(" .. totalUnits .. ")"
    end
    -- 自持比例不再强制，玩家可自由选择（minHoldRatio 已固定为 0）

    local avgArea = project.sales.totalArea / totalUnits
    up.planned = true
    up.sellUnits = sellUnits
    up.holdUnits = holdUnits
    up.sellArea = math.floor(sellUnits * avgArea)
    up.holdArea = math.floor(holdUnits * avgArea)

    -- 更新可售数量为仅销售部分
    project.sales.totalUnits = sellUnits
    project.sales.totalArea = up.sellArea
    GD.RebalanceProjectDevelopmentCost(project)

    GD.AddEvent("【" .. project.name .. "】单元规划完成: 销售" .. sellUnits .. "套, 自持" .. holdUnits .. "套", "success")
    return true
end

-- ============================================================================
-- 4.1 确认规划指标
-- ============================================================================
function GD.ConfirmPlanning(project)
    local d = project.design
    local p = d.planning
    local land = project.land
    -- 验证指标不超过土地规划条件上限
    if p.far > (land.far or 99) then return false, "容积率不得超过土地上限" end
    if p.density > (land.density or 1) then return false, "建筑密度不得超过土地上限" end
    if p.greenRate < (land.greenRate or 0) then return false, "绿化率不得低于土地下限" end
    if p.heightLimit > (land.heightLimit or 999) then return false, "限高不得超过土地上限" end

    -- 重算建筑面积
    land.buildArea = math.floor(land.area * p.far)
    project.sales.totalArea = math.floor(land.buildArea * 0.85)
    project.sales.totalUnits = math.floor(project.sales.totalArea / 100)
    -- 更新设计费
    project.cost.designCost = math.floor(project.cost.buildCost * 0.05)
    p.confirmed = true
    GD.AddEvent("【" .. project.name .. "】规划指标已确认 (FAR=" .. p.far .. ")", "info")
    return true
end

-- ============================================================================
-- 4.2 方案设计评分（不修改项目，返回 metrics 供 UI 展示）
-- ============================================================================
function GD.CalcSchemeMetrics(project, layoutKey, unitMixTable, styleKey)
    local lc = GD.LAYOUT_CONFIG[layoutKey]
    local sc = GD.STYLE_CONFIG[styleKey or project.design.style]
    if not lc then return nil end
    if not sc then return nil end

    local land = project.land
    local buildArea = land.buildArea or 0
    -- 建安单价：统一使用 DT.GetBuildCost（独立建安成本 × 位置 × 标准），与立项一致
    local city = GD.GetCityData(land.city)
    local marketAvg = city and city.avgPrice or 15000
    local unitBuildCost = DT.GetBuildCost(project.devTypeId, marketAvg,
        project.plotLocation or "suburb", project.standardId or "basic",
        GD.company.traitEffects.buildCostBonus or 0)

    local totalBuildCost = math.floor(buildArea * unitBuildCost * lc.costMult * sc.costMult / 10000)

    -- 预期均价：锚定产品类型基准价，再叠加方案布局/风格倍率
    local expectedPrice = math.floor(DT.GetExpectedPrice(
        project.devTypeId,
        marketAvg,
        project.plotLocation or (land and land.plotLocation) or "suburb",
        project.standardId or "basic",
        land.floorPrice or 0
    ) * (GD.economy.priceIndex / 100) * lc.priceMult * sc.priceMult)

    -- 去化速度乘数（户型加权）
    local speedMult = 0
    local totalRatio = 0
    for _, mix in ipairs(unitMixTable) do
        local uc = GD.UNIT_MIX_CONFIG[mix.type]
        if uc then
            speedMult = speedMult + uc.speedMult * mix.ratio
            totalRatio = totalRatio + mix.ratio
        end
    end
    if totalRatio > 0 then speedMult = speedMult / totalRatio else speedMult = 1.0 end
    speedMult = speedMult * sc.demandMult

    -- 预期利润率
    local sellableArea = math.floor(buildArea * 0.85)
    local totalRevenue = math.floor(sellableArea * expectedPrice / 10000) -- 万元
    local landCost = project.cost.landCost or 0
    local totalCostEst = landCost + totalBuildCost + math.floor(totalBuildCost * 0.05) -- 土地+建安+设计
    local profitRate = totalCostEst > 0 and ((totalRevenue - totalCostEst) / totalCostEst * 100) or 0

    -- 方案评分: 利润率(40%) + 去化速度(30%) + 得房率(30%)
    local profitScore = math.min(40, math.max(0, profitRate * 2)) -- 20%利润率→40分
    local speedScore = math.min(30, speedMult * 23)               -- 1.3→30分
    local effScore = lc.efficiency * 40                            -- 0.78→31分
    local score = math.floor(profitScore + speedScore + effScore)

    return {
        buildCost = totalBuildCost,
        expectedPrice = expectedPrice,
        speedMult = speedMult,
        efficiency = lc.efficiency,
        profitRate = math.floor(profitRate * 10) / 10,
        totalRevenue = totalRevenue,
        totalCostEst = totalCostEst,
        score = math.min(100, math.max(0, score)),
    }
end

-- ============================================================================
-- 4.2 确认方案设计
-- ============================================================================
function GD.ConfirmScheme(project, layoutKey, unitMixTable)
    local d = project.design
    local sc = GD.STYLE_CONFIG[d.style]
    local lc = GD.LAYOUT_CONFIG[layoutKey]
    if not lc then return false, "请选择布局类型" end
    if not sc then return false, "请选择外立面风格" end
    if #unitMixTable == 0 then return false, "请配置户型" end

    -- 验证户型配比合计100%
    local totalRatio = 0
    for _, mix in ipairs(unitMixTable) do totalRatio = totalRatio + mix.ratio end
    if math.abs(totalRatio - 100) > 1 then return false, "户型比例合计必须为100%" end

    local metrics = GD.CalcSchemeMetrics(project, layoutKey, unitMixTable, d.style)
    if not metrics then return false, "方案计算失败" end

    d.scheme.layout = layoutKey
    d.scheme.unitMix = unitMixTable
    d.scheme.efficiency = metrics.efficiency
    d.scheme.schemeScore = metrics.score
    d.scheme.confirmed = true

    -- 重算核心成本：统一使用 DT.GetBuildCost（基于城市均价×costRatio），与立项一致
    local cityData = GD.GetCityData(project.land and project.land.city)
    local cityAvgPrice = cityData and cityData.avgPrice or 15000
    local unitBuildCost = DT.GetBuildCost(project.devTypeId, cityAvgPrice,
        project.plotLocation or "suburb", project.standardId or "basic",
        GD.company.traitEffects.buildCostBonus or 0)
    project.cost.buildCost = math.floor(project.land.buildArea * unitBuildCost * lc.costMult * sc.costMult / 10000)
    project.cost.designCost = math.floor(project.cost.buildCost * 0.05)
    project.construction.totalMonths = math.floor(30 * lc.durationMult)
    project.cost.targetCost = project.cost.landCost + project.cost.buildCost + project.cost.designCost
        + (project.cost.ddCost or 0) + (project.cost.riskCost or 0)
    GD.RebalanceProjectDevelopmentCost(project)

    GD.AddEvent("【" .. project.name .. "】方案设计确认 (" .. lc.name .. "/" .. sc.name .. " 评分:" .. metrics.score .. ")", "info")
    return true
end

-- ============================================================================
-- 4.2b 自动选择方案设计（一键推荐/项目经理自动用）
-- ============================================================================
function GD.AutoConfirmScheme(project)
    local d = project.design
    if d.scheme.confirmed then return true end
    if not d.planning.confirmed then
        GD.ConfirmPlanning(project)
    end
    -- 选择默认布局
    local dd = GD.DEV_TYPE_DESIGN_DEFAULTS[project.devTypeId]
    local layout = (dd and dd.layoutDefault) or "row"
    -- 构建默认配比
    local unitMix = {}
    local isHold = (project.devCategory == "hold")
    local tenantMixCfg = isHold and GD.HOLD_TENANT_MIX_CONFIG[project.devTypeId] or nil
    if isHold and tenantMixCfg then
        local keys = {}
        for k, _ in pairs(tenantMixCfg) do table.insert(keys, k) end
        table.sort(keys)
        local evenShare = math.floor(100 / #keys)
        local remainder = 100 - evenShare * #keys
        for i, k in ipairs(keys) do
            table.insert(unitMix, {key = k, ratio = evenShare + (i == 1 and remainder or 0)})
        end
    else
        unitMix = {{key = "basic", ratio = 60}, {key = "improved", ratio = 30}, {key = "luxury", ratio = 10}}
    end
    return GD.ConfirmScheme(project, layout, unitMix)
end

-- ============================================================================
-- 4.2c 自动确认限额设计
-- ============================================================================
function GD.AutoConfirmCostCap(project)
    local d = project.design
    if d.costCap.confirmed then return true end
    if not d.scheme.confirmed then return false, "方案未确认" end
    return GD.ConfirmCostCap(project, {"铝模替代木模", "BIM碰撞检查"})
end

-- ============================================================================
-- 4.2d 项目经理系统
-- ============================================================================
GD.PM_POOL = {
    -- 高级（level 3）
    {name = "张建国", level = 3, salary = 4,  trait = "稳健型", speedBonus = 0.00, qualityBonus = 0.05, costSaving = 0.02,
     desc = "经验丰富，注重质量和成本控制，项目推进稳妥"},
    {name = "赵雪梅", level = 3, salary = 5, trait = "全能型", speedBonus = 0.10, qualityBonus = 0.05, costSaving = 0.03,
     desc = "行业顶尖，速度质量成本全面优秀，月薪较高"},
    {name = "刘德华", level = 3, salary = 5,  trait = "品质型", speedBonus = 0.05, qualityBonus = 0.08, costSaving = 0.01,
     desc = "对品质要求极高，打造精品项目首选"},
    -- 中级（level 2）
    {name = "李明远", level = 2, salary = 3,  trait = "高效型", speedBonus = 0.15, qualityBonus = 0.00, costSaving = 0.00,
     desc = "推进速度快，善于协调各方资源加速工期"},
    {name = "陈大鹏", level = 2, salary = 3,  trait = "节约型", speedBonus = 0.05, qualityBonus = 0.00, costSaving = 0.05,
     desc = "擅长控制成本，能有效降低建设开支"},
    {name = "孙丽萍", level = 2, salary = 3,  trait = "协调型", speedBonus = 0.08, qualityBonus = 0.03, costSaving = 0.02,
     desc = "善于沟通协调，多方关系处理出色"},
    {name = "周伟民", level = 2, salary = 2,  trait = "技术型", speedBonus = 0.05, qualityBonus = 0.06, costSaving = 0.00,
     desc = "技术功底扎实，施工方案优化能力强"},
    -- 初级（level 1）
    {name = "王志强", level = 1, salary = 1.5,  trait = "新锐型", speedBonus = 0.05, qualityBonus = -0.02, costSaving = 0.01,
     desc = "年轻有干劲，综合能力中等，性价比高"},
    {name = "林小峰", level = 1, salary = 1.5,  trait = "勤奋型", speedBonus = 0.08, qualityBonus = -0.01, costSaving = 0.00,
     desc = "吃苦耐劳，工期推进有保障"},
    {name = "黄婷婷", level = 1, salary = 1,  trait = "学习型", speedBonus = 0.03, qualityBonus = 0.00, costSaving = 0.02,
     desc = "成长潜力大，薪资低适合预算紧张时选用"},
    {name = "郑宏宇", level = 3, salary = 5,  trait = "统筹型", speedBonus = 0.08, qualityBonus = 0.06, costSaving = 0.02,
     desc = "擅长多专业统筹，适合大型综合体和复杂项目"},
    {name = "马嘉诚", level = 3, salary = 4.5, trait = "抢工型", speedBonus = 0.18, qualityBonus = -0.01, costSaving = -0.01,
     desc = "压缩工期能力强，适合现金流压力较大的项目"},
    {name = "吴雅楠", level = 3, salary = 4.5, trait = "精装型", speedBonus = 0.04, qualityBonus = 0.10, costSaving = 0.00,
     desc = "精装修和品质交付经验丰富，适合改善和高端产品"},
    {name = "何建平", level = 3, salary = 4, trait = "风控型", speedBonus = 0.02, qualityBonus = 0.06, costSaving = 0.04,
     desc = "合同、签证和成本风险控制能力突出"},
    {name = "唐文博", level = 2, salary = 3, trait = "招采型", speedBonus = 0.06, qualityBonus = 0.02, costSaving = 0.06,
     desc = "熟悉招采与供应链管理，能压降建安成本"},
    {name = "许静怡", level = 2, salary = 3, trait = "报建型", speedBonus = 0.10, qualityBonus = 0.02, costSaving = 0.01,
     desc = "报批报建经验丰富，前期手续推进更顺畅"},
    {name = "邓凯", level = 2, salary = 2.5, trait = "安全型", speedBonus = 0.04, qualityBonus = 0.07, costSaving = 0.01,
     desc = "重视安全文明施工，减少事故和返工风险"},
    {name = "郭晓敏", level = 2, salary = 2.5, trait = "交付型", speedBonus = 0.07, qualityBonus = 0.05, costSaving = 0.00,
     desc = "擅长交付筹备与客诉协调，适合尾盘和交付项目"},
    {name = "罗志远", level = 1, salary = 1.8, trait = "成本型", speedBonus = 0.02, qualityBonus = 0.00, costSaving = 0.04,
     desc = "成本意识强，适合预算紧张的中小项目"},
    {name = "程雨晴", level = 1, salary = 1.8, trait = "成长型", speedBonus = 0.06, qualityBonus = 0.02, costSaving = 0.01,
     desc = "学习快、执行力较强，可承担标准化项目"},
}

--- 获取可雇佣的项目经理候选人（排除已被其他项目雇佣的）
function GD.GetAvailablePMs()
    local hired = {}
    for _, proj in ipairs(GD.projects) do
        if proj.projectManager and proj.projectManager.hired then
            hired[proj.projectManager.name] = true
        end
    end
    local available = {}
    for _, pm in ipairs(GD.PM_POOL) do
        if not hired[pm.name] then
            table.insert(available, pm)
        end
    end
    return available
end

--- 雇佣项目经理
function GD.HireProjectManager(project, pmName)
    if project.projectManager and project.projectManager.hired then
        return false, "已有项目经理"
    end
    local pmData = nil
    for _, pm in ipairs(GD.PM_POOL) do
        if pm.name == pmName then pmData = pm; break end
    end
    if not pmData then return false, "候选人不存在" end
    -- 检查是否被其他项目雇佣
    for _, proj in ipairs(GD.projects) do
        if proj.projectManager and proj.projectManager.hired and proj.projectManager.name == pmName then
            return false, pmName .. " 已被其他项目雇佣"
        end
    end
    project.projectManager = {
        hired = true,
        name = pmData.name,
        level = pmData.level,
        salary = pmData.salary,
        trait = pmData.trait,
        speedBonus = pmData.speedBonus,
        qualityBonus = pmData.qualityBonus,
        costSaving = pmData.costSaving,
        desc = pmData.desc,
        autoMode = false,         -- 是否开启自动推进
        hiredMonth = GD.totalMonths,
        report = nil,             -- 待审批汇报 {type, message, month, choices}
    }
    GD.company.cash = GD.company.cash - pmData.salary  -- 扣首月工资
    GD.AddEvent("【" .. project.name .. "】雇佣项目经理: " .. pmData.name .. " (" .. pmData.trait .. ") 月薪" .. pmData.salary .. "万", "success")
    return true
end

--- 解雇项目经理
function GD.FireProjectManager(project)
    if not project.projectManager or not project.projectManager.hired then
        return false, "没有项目经理"
    end
    local name = project.projectManager.name
    project.projectManager = {hired = false}
    GD.AddEvent("【" .. project.name .. "】解雇项目经理: " .. name, "info")
    return true
end

--- 项目经理自动推进（在 UpdateProjects 中每月调用）
function GD.PMAutoAdvance(project)
    local pm = project.projectManager
    if not pm or not pm.hired or not pm.autoMode then return end
    -- 有未处理的汇报则暂停
    if pm.report then return end

    local d = project.design
    local status = project.status

    -- 报建阶段：自动启动未启动的证照
    if status == "permits" then
        for _, permit in ipairs(project.permits) do
            if permit.status == "pending" then
                permit.status = "processing"
            end
        end
        return
    end

    -- 设计阶段：自动确认各阶段
    if status == "design" then
        if d.phase == "concept" and d.phaseProgress >= 100 and not d.planning.confirmed then
            GD.ConfirmPlanning(project)
            GD.AddEvent("【" .. project.name .. "】项目经理 " .. pm.name .. " 自动确认规划指标", "info")
        elseif d.phase == "schematic" and d.phaseProgress >= 100 and not d.scheme.confirmed then
            GD.AutoConfirmScheme(project)
            GD.AddEvent("【" .. project.name .. "】项目经理 " .. pm.name .. " 自动确认方案设计", "info")
        elseif d.phase == "construction_drawing" and d.phaseProgress >= 100 and not d.costCap.confirmed then
            GD.AutoConfirmCostCap(project)
            GD.AddEvent("【" .. project.name .. "】项目经理 " .. pm.name .. " 自动确认限额设计", "info")
        end
        return
    end

    -- 结算 & 竣工阶段：项目经理不干预，必须玩家手动操作
    if status == "pending_settlement" or status == "pending_completion" then
        return
    end

    -- 施工完成后自动处理
    if status == "pending_operations" then
        -- 持有型竣工后，PM汇报请求选择运营模式
        if not pm.report then
            local modes = DT.GetOperationModes(project.devTypeId)
            local modeNames = {}
            if modes then
                for _, m in ipairs(modes) do
                    table.insert(modeNames, {id = m.id, name = m.icon .. " " .. m.name})
                end
            end
            pm.report = {
                type = "operation_mode",
                message = "项目已竣工，建议选择运营模式。根据市场分析，推荐第一个模式。请批准或选择其他模式。",
                month = GD.totalMonths,
                choices = modeNames,
            }
            GD.AddEvent("【" .. project.name .. "】项目经理 " .. pm.name .. " 提交运营模式选择报告，等待批准", "warning")
        end
    end
end

--- 处理项目经理汇报审批
function GD.ApprovePMReport(project, choiceIdx)
    local pm = project.projectManager
    if not pm or not pm.report then return false, "无待审批汇报" end
    local report = pm.report

    if report.type == "operation_mode" then
        local choice = report.choices[choiceIdx or 1]
        if choice then
            local ok, err = GD.SelectOperationMode(project, choice.id)
            if ok then
                pm.report = nil
                GD.AddEvent("【" .. project.name .. "】批准运营模式: " .. choice.name, "success")
                return true
            else
                return false, err
            end
        end
        return false, "无效选择"
    elseif report.type == "completion" then
        pm.report = nil
        GD.AddEvent("【" .. project.name .. "】批准项目经理完工报告", "success")
        return true
    end
    pm.report = nil
    return true
end

-- ============================================================================
-- 4.3 确认限额设计
-- ============================================================================
function GD.ConfirmCostCap(project, optimizations)
    local d = project.design
    local cap = d.costCap
    local std = GD.COST_CAP_STANDARDS

    -- 基础用量（由定位 tier 决定，兼容所有类型）
    local tier = GD.GetPositioningTier(project)
    local baseSteel = 48     -- 基准钢筋 kg/㎡
    local baseConcrete = 0.42 -- 基准混凝土 m³/㎡
    if tier == 3 then baseSteel = 52; baseConcrete = 0.45
    elseif tier == 1 then baseSteel = 44; baseConcrete = 0.38 end

    -- 应用优化
    cap.optimizations = optimizations or {}
    for _, opt in ipairs(cap.optimizations) do
        if opt == "basementHeight" then baseSteel = baseSteel - 3
        elseif opt == "pileType" then baseConcrete = baseConcrete - 0.05
        elseif opt == "facadeMaterial" then
            project.cost.buildCost = math.floor(project.cost.buildCost * 0.95)
        end
    end

    cap.steelPerSqm = math.floor(baseSteel * 10) / 10
    cap.concretePerSqm = math.floor(baseConcrete * 100) / 100

    -- 检查是否超标
    cap.overrun = cap.steelPerSqm > std.steelPerSqm or cap.concretePerSqm > std.concretePerSqm
    if cap.overrun then
        cap.penalty = math.floor(project.cost.designCost * std.penaltyRate)
        GD.company.cash = GD.company.cash - cap.penalty
        GD.AddEvent("【" .. project.name .. "】限额设计超标，扣罚设计费 " .. cap.penalty .. "万", "warning")
    else
        cap.penalty = 0
        GD.AddEvent("【" .. project.name .. "】限额设计达标", "success")
    end

    cap.confirmed = true
    project.cost.targetCost = project.cost.landCost + project.cost.buildCost + project.cost.designCost
        + (project.cost.ddCost or 0) + (project.cost.riskCost or 0) + cap.penalty
    return true
end

-- ============================================================================
-- 4.4 图纸审查（单阶段检查）
-- ============================================================================
function GD.CheckReviewStage(project)
    local d = project.design
    local rev = d.review
    if rev.currentStage < 1 or rev.currentStage > #GD.REVIEW_STAGES then return end

    local stage = rev.stages[rev.currentStage]
    if not stage or stage.status == "passed" then return end

    local cfg = GD.REVIEW_STAGES[rev.currentStage]
    local passRate = cfg.basePassRate

    -- 设计总监加成
    for _, kp in ipairs(GD.company.keyPositions or {}) do
        if kp.type == "design_director" then passRate = passRate + 0.10 break end
    end
    -- 高评分加成
    if (d.scheme.schemeScore or 0) > 80 then passRate = passRate + 0.05 end
    passRate = math.min(0.95, passRate)

    stage.attempts = stage.attempts + 1
    if math.random() < passRate then
        stage.status = "passed"
        GD.AddEvent("【" .. project.name .. "】" .. cfg.name .. " 审查通过", "success")
        -- 推进到下一阶段
        if rev.currentStage < #GD.REVIEW_STAGES then
            rev.currentStage = rev.currentStage + 1
        else
            -- 全部通过
            d.phase = "done"
            GD.AddEvent("【" .. project.name .. "】全部图纸审查通过，设计完成!", "success")
        end
    else
        stage.status = "rejected"
        local rework = math.floor(project.cost.designCost * 0.05)
        rev.reworkCost = rev.reworkCost + rework
        GD.company.cash = GD.company.cash - rework
        GD.AddEvent("【" .. project.name .. "】" .. cfg.name .. " 审查未通过，返工费 " .. rework .. "万", "warning")
    end
end

-- ============================================================================
-- 4.5 运营模式选择与变更（持有型项目竣工后手动选择）
-- ============================================================================

--- 选择运营模式并开始运营（首次选择，从 pending_operations 进入运营）
---@param project table 项目数据
---@param modeId string 运营模式ID
---@return boolean, string|nil
function GD.SelectOperationMode(project, modeId)
    if (project.devCategory or "sale") ~= "hold" then
        return false, "仅持有型项目支持运营模式选择"
    end
    if project.status ~= "pending_operations" then
        return false, "当前阶段不允许选择运营模式"
    end

    -- 初始化运营数据（如果尚未初始化）
    if not project.operations then
        project.operations = OP.InitOperationsData(project.devTypeId, project.land.buildArea)
    end
    local ops = project.operations
    if not ops then return false, "运营数据初始化失败" end

    -- 通过 OP 模块选择模式
    local ok, err = OP.SelectMode(project, modeId, GD)
    if not ok then return false, err end

    -- 正式进入运营阶段
    project.status = "operations"
    local mode = DT.GetOperationMode(project.devTypeId, modeId)
    GD.AddEvent("【" .. project.name .. "】选择运营模式: " ..
        (mode and (mode.icon .. mode.name) or modeId) .. "，进入招商运营！", "success")
    return true
end

--- 变更运营模式（需要支付装修改造成本，进入装修期）
---@param project table
---@param newModeId string
---@return boolean, string|nil
function GD.ChangeOperationMode(project, newModeId)
    if (project.devCategory or "sale") ~= "hold" then
        return false, "仅持有型项目支持运营模式变更"
    end
    if project.status ~= "operations" and project.status ~= "mature" then
        return false, "当前阶段不允许变更运营模式"
    end

    -- 通过 OP 模块变更模式（包含装修改造逻辑）
    return OP.ChangeMode(project, newModeId, GD)
end

-- ============================================================================
-- 设计阶段月度更新 (MonthlyTick 驱动)
-- ============================================================================
function GD.UpdateDesign(project)
    local d = project.design
    if d.phase == "none" or d.phase == "done" then return end

    -- 设计速度加成（设计管理部 + 项目经理）
    local designBonus = 1.0
    local executiveEffects = GV.GetExecutiveEffects and GV.GetExecutiveEffects(GD) or {}
    designBonus = designBonus + (executiveEffects.speedBonus or 0)
        + (executiveEffects.teamBonus or 0)
    for _, dept in ipairs(GD.company.hqDepartments or {}) do
        if dept.id == "design" and dept.established then
            designBonus = designBonus + 0.15
            break
        end
    end
    if project.projectManager and project.projectManager.hired then
        designBonus = designBonus + (project.projectManager.speedBonus or 0)
    end
    local diversificationSynergy = GDI.GetProjectSynergy(GD, project)
    designBonus = designBonus + (diversificationSynergy.designSpeedBonus or 0)

    if d.phase == "review" then
        -- 审查阶段：每月检查一次
        local rev = d.review
        if rev.currentStage >= 1 and rev.currentStage <= #rev.stages then
            local stage = rev.stages[rev.currentStage]
            if stage.status == "rejected" then
                -- 被驳回后需要1个月返工再重新提交
                stage.status = "pending"
            else
                GD.CheckReviewStage(project)
            end
        end
        return
    end

    -- 非审查阶段：推进进度
    local duration = GD.DESIGN_PHASE_DURATION[d.phase] or 3
    local increment = (100 / duration) * designBonus
    d.phaseProgress = d.phaseProgress + increment

    if d.phaseProgress >= 100 then
        d.phaseProgress = 0
        -- 阶段切换
        if d.phase == "concept" then
            if not d.planning.confirmed then
                d.phaseProgress = 100  -- 暂停
                GD.AddEvent("【" .. project.name .. "】概念设计完成，请确认规划指标", "warning")
                return
            end
            d.phase = "schematic"
            GD.AddEvent("【" .. project.name .. "】进入方案设计阶段", "info")
        elseif d.phase == "schematic" then
            if not d.scheme.confirmed then
                d.phaseProgress = 100
                GD.AddEvent("【" .. project.name .. "】方案设计完成，请确认设计方案", "warning")
                return
            end
            d.phase = "construction_drawing"
            GD.AddEvent("【" .. project.name .. "】进入施工图设计阶段", "info")
        elseif d.phase == "construction_drawing" then
            if not d.costCap.confirmed then
                d.phaseProgress = 100
                GD.AddEvent("【" .. project.name .. "】施工图完成，请确认限额设计", "warning")
                return
            end
            d.phase = "review"
            -- 初始化审查阶段
            d.review.currentStage = 1
            d.review.stages = {}
            for _, cfg in ipairs(GD.REVIEW_STAGES) do
                table.insert(d.review.stages, {
                    id = cfg.id,
                    name = cfg.name,
                    status = "pending",
                    attempts = 0,
                })
            end
            GD.AddEvent("【" .. project.name .. "】进入图纸审查阶段", "info")
        end
    end
end

-- ============================================================================
-- 获取项目抵押贷款信息
-- ============================================================================
function GD.GetProjectLoanInfo(project)
    if not project then return { available = false, reason = "项目不存在" } end
    -- 根据项目阶段计算可抵押额度
    local value = (project.cost and project.cost.landCost or 0) + (project.cost and project.cost.buildCost or 0)
    local rate, maxRatio = 3.0, 0  -- 固定利率3%
    if project.status == "construction" then
        maxRatio = 0.70   -- 在建工程抵押70%
    elseif project.status == "presale" or project.status == "pending_settlement"
        or project.status == "pending_completion" or project.status == "delivery"
        or project.status == "completed" or project.status == "operations"
        or project.status == "sold_off" then
        return { available = false, reason = "项目已结算/竣工，不可新增抵押" }
    else
        return { available = false, reason = "项目尚未开工，不可抵押" }
    end

    -- 扣除已有该项目的抵押贷款
    local existingLoan = 0
    for _, loan in ipairs(GD.loans) do
        if loan.projectId == project.id and loan.isProjectMortgage then
            existingLoan = existingLoan + loan.amount
        end
    end
    local maxAmount = math.floor(value * maxRatio)
    local available = math.max(0, maxAmount - existingLoan)

    return {
        available = available > 0,
        projectValue = value,
        maxRatio = maxRatio,
        maxAmount = maxAmount,
        existingLoan = existingLoan,
        availableAmount = available,
        rate = rate,
        maxMonths = 36,  -- 最长3年
        reason = available <= 0 and "已达该项目抵押上限" or nil,
    }
end

-- ============================================================================
-- 项目抵押贷款: 申请
-- ============================================================================
function GD.ApplyProjectMortgage(project, amount, months)
    if not project then
        GD.AddEvent("项目不存在", "danger")
        return false
    end
    local info = GD.GetProjectLoanInfo(project)
    if not info.available then
        GD.AddEvent(info.reason or "不可抵押", "danger")
        return false
    end
    amount = amount or 0
    if amount > info.availableAmount then
        amount = info.availableAmount
    end
    if amount <= 0 then
        GD.AddEvent("抵押金额无效", "danger")
        return false
    end
    months = months or 36
    if months < 12 then months = 12 end
    if months > 36 then months = 36 end

    local projName = project.name or "未知项目"

    -- 创建贷款
    local loan = {
        name = projName .. "项目抵押贷款",
        amount = amount,
        rate = info.rate,
        totalMonths = months,
        remainMonths = months,
        projectId = project.id,
        isProjectMortgage = true,
        repayMethod = "interest_monthly",  -- 按月付息到期还本
        accruedInterest = 0,
    }
    table.insert(GD.loans, loan)
    GD.company.cash = GD.company.cash + amount
    GD.company.totalDebt = GD.company.totalDebt + amount

    GD.AddEvent("【" .. projName .. "】项目抵押贷款获批，到账"
        .. GD.FormatMoney(amount) .. "，利率" .. info.rate .. "%，期限" .. months .. "个月", "success")
    return true
end

-- ============================================================================
-- 固定资产: 抵押率参数
-- ============================================================================
GD.FIXED_ASSET_MORTGAGE_RATE_BASE = 3.0   -- 抵押贷款基准利率%（固定3%）
GD.FIXED_ASSET_MORTGAGE_MAX_RATIO = 0.90  -- 最高抵押率90%

-- ============================================================================
-- 固定资产: 装修等级配置
-- ============================================================================
GD.RENOVATION_LEVELS = {
    {id = "none",     name = "毛坯（不装修）", costPerSqm = 0,    valueRatio = 0.0,  desc = "不装修，按原值入账"},
    {id = "basic",    name = "简装",          costPerSqm = 800,  valueRatio = 0.3,  desc = "基础硬装，达成30%增值"},
    {id = "standard", name = "精装",          costPerSqm = 2000, valueRatio = 0.65, desc = "品质精装，达成65%增值"},
    {id = "luxury",   name = "豪装",          costPerSqm = 5000, valueRatio = 1.0,  desc = "顶级装修，达成100%市场估值"},
}

--- 计算四级超额累进土地增值税(LAT)
--- 增值率 ≤50% 征30%、≤100% 征40%、≤200% 征50%、>200% 征60%
---@param appreciationAmount number 增值额(万元)
---@param deductionAmount number 扣除项(原值,万元)
---@return number tax 应缴税额(万元)
---@return number effectiveRate 实际税率(%)
---@return table details 各档明细
function GD.CalcLAT(appreciationAmount, deductionAmount)
    if appreciationAmount <= 0 then
        return 0, 0, {}
    end
    local rate = deductionAmount > 0 and (appreciationAmount / deductionAmount * 100) or 0
    local brackets = {
        {cap = 50,  rate = 0.30, deduct = 0},      -- ≤50%
        {cap = 100, rate = 0.40, deduct = 0.05},    -- ≤100%
        {cap = 200, rate = 0.50, deduct = 0.15},    -- ≤200%
        {cap = math.huge, rate = 0.60, deduct = 0.35},  -- >200%
    }

    -- 超额累进：按各档增值额分别计税
    local totalTax = 0
    local remaining = appreciationAmount
    local prevCap = 0
    local details = {}
    for _, b in ipairs(brackets) do
        local bracketBase = deductionAmount * (b.cap / 100)
        local prevBase = deductionAmount * (prevCap / 100)
        local bracketAmount = math.min(remaining, bracketBase - prevBase)
        if bracketAmount <= 0 then break end
        local bracketTax = bracketAmount * b.rate
        totalTax = totalTax + bracketTax
        table.insert(details, {
            range = prevCap .. "%-" .. (b.cap == math.huge and "∞" or tostring(b.cap)) .. "%",
            amount = math.floor(bracketAmount * 100) / 100,
            rate = math.floor(b.rate * 100),
            tax = math.floor(bracketTax * 100) / 100,
        })
        remaining = remaining - bracketAmount
        prevCap = b.cap
        if remaining <= 0 then break end
    end
    totalTax = math.floor(totalTax * 100) / 100
    local effectiveRate = appreciationAmount > 0 and (totalTax / appreciationAmount * 100) or 0
    return totalTax, math.floor(effectiveRate * 10) / 10, details
end

--- 预览入固定资产信息（装修+税费计算，不执行操作）
---@param project table 项目
---@param renovLevelIdx number 装修等级索引(1~4)
---@return table|nil info 预览信息
function GD.PreviewFixedAssetConvert(project, renovLevelIdx)
    if not project then return nil end
    local holdUnits = project.unitPlan and project.unitPlan.holdUnits or 0
    local holdArea = project.unitPlan and project.unitPlan.holdArea or 0
    if holdUnits <= 0 then
        if (project.devCategory or "sale") == "hold" then
            holdArea = project.land and project.land.buildArea or 0
            holdUnits = project.sales and project.sales.totalUnits or 1
        else
            return nil
        end
    end
    -- 原值
    local totalArea = project.land and project.land.buildArea or holdArea
    local areaRatio = totalArea > 0 and (holdArea / totalArea) or 1.0
    local originalValue = math.floor((project.cost.landCost + project.cost.buildCost) * areaRatio)
    -- 市场估值上限(取售价估算，若无则按成本×1.5)
    local fullMarketValue
    if project.sales and project.sales.basePrice > 0 then
        fullMarketValue = math.floor(project.sales.basePrice * holdArea / 10000)
    else
        fullMarketValue = math.floor(originalValue * 1.5)
    end
    -- 装修
    local level = GD.RENOVATION_LEVELS[renovLevelIdx] or GD.RENOVATION_LEVELS[1]
    local renovCost = math.floor(holdArea * level.costPerSqm / 10000)  -- 元→万元
    -- 装修后评估价 = 原值 + (市场估值 - 原值) × valueRatio
    local appreciation = fullMarketValue - originalValue
    if appreciation < 0 then appreciation = 0 end
    local actualMarketValue = originalValue + math.floor(appreciation * level.valueRatio)
    -- 入账原值 = 建设成本 + 装修成本
    local bookOriginal = originalValue + renovCost
    -- LAT: 增值额 = 评估价 - 入账原值
    local taxableAppreciation = actualMarketValue - bookOriginal
    if taxableAppreciation < 0 then taxableAppreciation = 0 end
    local latTax, effectiveRate, latDetails = GD.CalcLAT(taxableAppreciation, bookOriginal)
    -- 总支出 = 装修费 + 税费
    local totalCost = renovCost + latTax

    return {
        holdUnits = holdUnits,
        holdArea = holdArea,
        originalValue = originalValue,         -- 建设原值(万元)
        fullMarketValue = fullMarketValue,     -- 市场估值上限(万元)
        renovLevel = level,                    -- 装修等级
        renovCost = renovCost,                 -- 装修费(万元)
        actualMarketValue = actualMarketValue, -- 装修后评估价(万元)
        bookOriginal = bookOriginal,           -- 入账原值(含装修,万元)
        taxableAppreciation = taxableAppreciation, -- 增值额(万元)
        latTax = latTax,                       -- 土地增值税(万元)
        effectiveRate = effectiveRate,          -- 实际税率(%)
        latDetails = latDetails,               -- 各档明细
        totalCost = totalCost,                 -- 总支出(万元)
    }
end

-- ============================================================================
-- 固定资产: 自持物业入固定资产（需选择装修等级，自动扣除装修费+LAT税费）
-- ============================================================================
function GD.ConvertToFixedAsset(project, renovLevelIdx)
    if not project then
        GD.AddEvent("项目不存在", "danger")
        return false
    end
    -- 只有已竣工、待运营或运营中的自持单元可入固定资产。
    if project.status ~= "completed" and project.status ~= "delivery" and project.status ~= "pending_operations"
        and project.status ~= "operations" and project.status ~= "mature" then
        GD.AddEvent("项目尚未竣工，不可入固定资产", "danger")
        return false
    end
    local holdUnits = project.unitPlan and project.unitPlan.holdUnits or 0
    local holdArea = project.unitPlan and project.unitPlan.holdArea or 0
    if holdUnits <= 0 then
        if (project.devCategory or "sale") == "hold" then
            holdArea = project.land and project.land.buildArea or 0
            holdUnits = project.sales and project.sales.totalUnits or 1
        else
            GD.AddEvent("该项目无自持单元，不可入固定资产", "danger")
            return false
        end
    end
    -- 检查是否已入过固定资产
    for _, fa in ipairs(GD.fixedAssets) do
        if fa.projectId == project.id then
            GD.AddEvent("该项目已入固定资产", "warning")
            return false
        end
    end

    -- 预览计算
    local info = GD.PreviewFixedAssetConvert(project, renovLevelIdx or 1)
    if not info then
        GD.AddEvent("无法计算固定资产信息", "danger")
        return false
    end

    -- 装修与转固土地增值税必须一并支付；CEO托管可先按目标负债率补足资金。
    if info.totalCost > 0 then
        local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        if isManaged and GV.EnsureManagementCash then
            GV.EnsureManagementCash(GD, info.totalCost, "自持物业装修及转固缴税")
        end
        if GD.company.cash < info.totalCost then
            GD.AddEvent("资金不足！装修及转固缴税需要" .. GD.FormatMoney(info.totalCost), "danger")
            return false
        end
    end

    if info.renovCost > 0 then
        GD.company.cash = GD.company.cash - info.renovCost
        GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + info.renovCost
        GD.AddLedger("expense", "固定资产装修", project.name .. " 转固装修", info.renovCost)
        GD.AddEvent("【" .. project.name .. "】支付装修费" .. GD.FormatMoney(info.renovCost)
            .. "（" .. info.renovLevel.name .. "）", "info")
    end
    if info.latTax > 0 then
        GD.company.cash = GD.company.cash - info.latTax
        GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + info.latTax
        if GD.finance and GD.finance.taxData then
            GD.finance.taxData.projectTaxPaid = (GD.finance.taxData.projectTaxPaid or 0) + info.latTax
        end
        GD.AddLedger("expense", "项目税费", project.name .. " 转固土地增值税", info.latTax)
        GD.AddEvent("【" .. project.name .. "】缴纳转固土地增值税" .. GD.FormatMoney(info.latTax), "warning")
    end

    -- 租金信息：按装修后评估价 × 含装修加成的年化收益率 / 12
    local occupancy = (project.assets or {}).occupancyRate or 0
    local cityData = GD.GetCityData(project.land and project.land.city)
    local cityTier = cityData and cityData.tier or 2
    local plotLoc = project.plotLocation or (project.land and project.land.plotLocation) or "suburb"
    local fullYield = DT.GetFullRentYield(plotLoc, cityTier, info.renovLevel.id)
    local monthlyRent = math.floor(info.actualMarketValue * fullYield / 12 * 100) / 100

    local asset = {
        projectId = project.id,
        projectName = project.name,
        name = project.name,
        holdUnits = info.holdUnits,
        holdArea = info.holdArea,
        originalValue = info.bookOriginal,       -- 入账原值(含装修,万元)
        currentValue = info.actualMarketValue,   -- 装修后评估价(万元)
        marketValue = info.actualMarketValue,    -- 兼容展示字段
        bookValue = info.bookOriginal,           -- 账面净值(万元)
        monthlyRent = monthlyRent,               -- 月租金收入(万元,含装修加成)
        occupancyRate = occupancy,               -- 出租率
        mortgaged = false,
        mortgageLoanIdx = nil,
        convertMonth = GD.totalMonths or 0,
        convertYear = GD.year,
        renovLevel = info.renovLevel.id,         -- 装修等级
        renovCost = info.renovCost,              -- 装修费(万元)
        latTax = info.latTax,                    -- 已缴LAT(万元)
        plotLocation = plotLoc,                  -- 地块位置(core/urban/suburb)
        assetType = (project.devCategory == "hold") and (DT.GetType(project.devTypeId) and DT.GetType(project.devTypeId).shortName or "商业物业") or "住宅物业",
        isListedForRent = false,                 -- 是否挂牌出租
    }
    table.insert(GD.fixedAssets, asset)
    project._fixedAssetConverted = true
    if project.status == "pending_operations" then
        project.status = "completed"
    end
    project.assets = project.assets or {}
    project.assets.rentable = false
    project.assets.occupancyRate = 0
    project.assets.monthlyRentIncome = 0
    project.isListedForRent = false

    GD.AddEvent("【" .. project.name .. "】自持物业入固定资产（" .. info.renovLevel.name .. "），原值"
        .. GD.FormatMoney(info.bookOriginal) .. "，评估价" .. GD.FormatMoney(info.actualMarketValue)
        .. "，支出合计" .. GD.FormatMoney(info.totalCost), "success")
    return true
end

-- ============================================================================
-- 固定资产: 字段兼容与规范化
-- ============================================================================
function GD.EnsureFixedAssetFields(fa)
    if not fa then return end
    fa.projectName = fa.projectName or fa.name or "固定资产"
    fa.name = fa.name or fa.projectName
    fa.originalValue = fa.originalValue or fa.bookValue or fa.currentValue or fa.marketValue or 0
    fa.bookValue = fa.bookValue or fa.originalValue or 0
    fa.currentValue = fa.currentValue or fa.marketValue or fa.bookValue or fa.originalValue or 0
    fa.marketValue = fa.marketValue or fa.currentValue or 0
    fa.monthlyRent = fa.monthlyRent or 0
    fa.occupancyRate = fa.occupancyRate or 0
    fa.holdArea = fa.holdArea or 0
    fa.holdUnits = fa.holdUnits or 0
    fa.mortgaged = fa.mortgaged or false
    fa.isListed = fa.isListed or false
    fa.isListedForRent = fa.isListedForRent or false
    fa.renovLevel = fa.renovLevel or "none"
    fa.assetType = fa.assetType or "物业资产"
end

-- ============================================================================
-- 固定资产: 获取抵押贷款信息
-- ============================================================================
function GD.GetFixedAssetMortgageInfo(assetIdx)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then return {available = false, reason = "资产不存在"} end
    if fa.mortgaged then
        -- 查找关联贷款
        local existingAmount = 0
        for _, loan in ipairs(GD.loans) do
            if loan.fixedAssetIdx == assetIdx then
                existingAmount = existingAmount + loan.amount
            end
        end
        return {
            available = false,
            reason = "已抵押(贷款余额" .. GD.FormatMoney(existingAmount) .. ")",
            assetValue = fa.currentValue,
            existingLoan = existingAmount,
        }
    end
    local maxAmount = math.floor(fa.currentValue * GD.FIXED_ASSET_MORTGAGE_MAX_RATIO)
    local rate = GD.FIXED_ASSET_MORTGAGE_RATE_BASE  -- 固定3%
    return {
        available = true,
        assetValue = fa.currentValue,
        bookValue = fa.bookValue,
        maxAmount = maxAmount,
        maxRatio = GD.FIXED_ASSET_MORTGAGE_MAX_RATIO,
        rate = rate,
        maxMonths = 36,  -- 最长3年
    }
end

-- ============================================================================
-- 固定资产: 申请抵押贷款
-- ============================================================================
function GD.ApplyFixedAssetMortgage(assetIdx, amount, months)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then
        GD.AddEvent("固定资产不存在", "danger")
        return false
    end
    if fa.mortgaged then
        GD.AddEvent("该资产已抵押，不可重复抵押", "danger")
        return false
    end
    local info = GD.GetFixedAssetMortgageInfo(assetIdx)
    if not info.available then
        GD.AddEvent(info.reason or "不可抵押", "danger")
        return false
    end
    amount = amount or 0
    if amount > info.maxAmount then
        amount = info.maxAmount
    end
    if amount <= 0 then
        GD.AddEvent("抵押金额无效", "danger")
        return false
    end
    months = months or 36
    if months < 12 then months = 12 end
    if months > 36 then months = 36 end

    local assetName = fa.projectName or "未知资产"

    -- 创建贷款
    local loan = {
        name = assetName .. "固定资产抵押贷款",
        amount = amount,
        rate = info.rate,
        totalMonths = months,
        remainMonths = months,
        projectId = fa.projectId,
        fixedAssetIdx = assetIdx,  -- 关联固定资产
        isFixedAssetMortgage = true,
        repayMethod = "interest_monthly",  -- 按月付息到期还本
        accruedInterest = 0,
    }
    table.insert(GD.loans, loan)
    GD.company.cash = GD.company.cash + amount
    GD.company.totalDebt = GD.company.totalDebt + amount

    -- 标记资产已抵押
    fa.mortgaged = true
    fa.mortgageLoanIdx = #GD.loans

    GD.AddEvent("【" .. assetName .. "】固定资产抵押贷款获批，到账"
        .. GD.FormatMoney(amount) .. "，利率" .. info.rate .. "%，期限" .. months .. "个月", "success")
    return true
end

-- ============================================================================
-- 固定资产: 解除抵押(贷款还清后自动调用)
-- ============================================================================
function GD.ReleaseFixedAssetMortgage(assetIdx)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then return end
    fa.mortgaged = false
    fa.mortgageLoanIdx = nil
    GD.AddEvent("【" .. (fa.projectName or "未知资产") .. "】固定资产抵押解除", "success")
end

-- ============================================================================
-- 固定资产: 月度更新(价值重估、租金同步)
-- ============================================================================
function GD.UpdateFixedAssets()
    for idx, fa in ipairs(GD.fixedAssets) do
        GD.EnsureFixedAssetFields(fa)
        -- 账面净值始终等于原值（不折旧）
        fa.bookValue = fa.originalValue
        -- 1. 同步项目租金信息（未转固定资产的旧项目数据才同步；已转入后由固定资产/出租挂牌系统独立管理）
        for _, p in ipairs(GD.projects) do
            if p.id == fa.projectId and not p._fixedAssetConverted then
                local a = p.assets or {}
                fa.monthlyRent = a.monthlyRentIncome or fa.monthlyRent
                fa.occupancyRate = a.occupancyRate or fa.occupancyRate
                break
            end
        end
        -- 2. 租金收入由出租挂牌系统(UpdateRentalListings)统一处理
        -- 不再在此自动收租，仅同步出租率微调（已签约的资产）
        -- 3. 市场价值随经济周期微调(±0.5%/月)
        local econFactor = 1.0
        if GD.economy then
            if GD.economy.trend == "boom" then econFactor = 1.005
            elseif GD.economy.trend == "recession" then econFactor = 0.995
            else econFactor = 1.001 end
        end
        fa.currentValue = math.floor(fa.currentValue * econFactor)
        fa.marketValue = fa.currentValue
        -- 4. 检查关联贷款是否已还清 → 自动解除抵押
        if fa.mortgaged then
            local hasLoan = false
            for _, loan in ipairs(GD.loans) do
                if loan.fixedAssetIdx == idx then
                    hasLoan = true
                    break
                end
            end
            if not hasLoan then
                GD.ReleaseFixedAssetMortgage(idx)
            end
        end
    end
end

-- ============================================================================
-- 固定资产: 获取公司级汇总数据
-- ============================================================================
function GD.GetFixedAssetSummary()
    local totalOriginal = 0
    local totalBook = 0
    local totalMarket = 0
    local totalRent = 0
    local totalArea = 0
    local totalUnits = 0
    local mortgagedCount = 0
    local mortgagedValue = 0
    for _, fa in ipairs(GD.fixedAssets) do
        GD.EnsureFixedAssetFields(fa)
        totalOriginal = totalOriginal + fa.originalValue
        totalBook = totalBook + fa.bookValue
        totalMarket = totalMarket + fa.currentValue
        totalRent = totalRent + fa.monthlyRent
        totalArea = totalArea + fa.holdArea
        totalUnits = totalUnits + fa.holdUnits
        if fa.mortgaged then
            mortgagedCount = mortgagedCount + 1
            mortgagedValue = mortgagedValue + fa.currentValue
        end
    end
    return {
        count = #GD.fixedAssets,
        totalOriginal = totalOriginal,
        totalBook = totalBook,
        totalMarket = totalMarket,
        totalMonthlyRent = totalRent,
        totalArea = totalArea,
        totalUnits = totalUnits,
        mortgagedCount = mortgagedCount,
        mortgagedValue = mortgagedValue,
        unmortgagedValue = totalMarket - mortgagedValue,
    }
end

-- ============================================================================
-- 挂牌出售系统 (运营资产 → 挂牌 → 买家报价 → 成交)
-- ============================================================================
GD.assetListings = {}

--- 挂牌出售（持有型项目或固定资产）
function GD.ListAssetForSale(project, askingPrice)
    if not project then return false, "项目不存在" end
    -- 检查是否已挂牌
    for _, listing in ipairs(GD.assetListings) do
        if listing.projectName == project.name and listing.status == "listed" then
            return false, "该资产已在挂牌中"
        end
    end
    local listing = {
        projectName = project.name,
        askingPrice = askingPrice,
        status = "listed",       -- listed / sold / delisted
        listedMonth = GD.totalMonths,
        offers = {},             -- 买家报价列表
        monthsListed = 0,
    }
    table.insert(GD.assetListings, listing)
    project.isListed = true
    GD.AddEvent("【" .. project.name .. "】已挂牌出售，要价" .. GD.FormatMoney(askingPrice), "info")
    return true
end

--- 撤牌
function GD.DelistAsset(project)
    if not project then return false end
    for i, listing in ipairs(GD.assetListings) do
        if listing.projectName == project.name and listing.status == "listed" then
            listing.status = "delisted"
            project.isListed = false
            GD.AddEvent("【" .. project.name .. "】已撤回挂牌", "info")
            return true
        end
    end
    return false, "未找到挂牌记录"
end

--- 接受报价
function GD.AcceptOffer(listingIdx, offerIdx)
    local listing = GD.assetListings[listingIdx]
    if not listing or listing.status ~= "listed" then return false, "挂牌不存在" end
    local offer = listing.offers[offerIdx]
    if not offer then return false, "报价不存在" end

    listing.status = "sold"
    local salePrice = offer.price

    -- 找到对应项目并处理
    local foundProject = false
    for i, p in ipairs(GD.projects) do
        if p.name == listing.projectName then
            p.isListed = false
            p.status = "sold_off"
            p.salesCleared = true
            foundProject = true
            break
        end
    end

    -- 入账（无论是项目还是市场购入资产都需入账）
    GD.company.cash = GD.company.cash + salePrice
    GD.AddEvent("【" .. listing.projectName .. "】以" .. GD.FormatMoney(salePrice) .. "出售给" .. offer.buyer, "success")

    -- 出售成交自动撤回出租挂牌
    for ri = #GD.rentalListings, 1, -1 do
        local rl = GD.rentalListings[ri]
        if rl.assetName == listing.projectName then
            table.remove(GD.rentalListings, ri)
            GD.AddEvent("【" .. listing.projectName .. "】出售成交，自动撤回出租", "info")
        end
    end

    -- 如果是固定资产，也从固定资产列表移除
    for i, fa in ipairs(GD.fixedAssets) do
        if fa.projectName == listing.projectName then
            table.remove(GD.fixedAssets, i)
            break
        end
    end

    return true
end

--- 每月更新挂牌（生成买家报价）
function GD.UpdateListings()
    for _, listing in ipairs(GD.assetListings) do
        if listing.status ~= "listed" then goto continue_listing end
        listing.monthsListed = listing.monthsListed + 1

        -- 每月有概率生成买家报价（挂牌越久概率越高）
        local chance = math.min(60, 15 + listing.monthsListed * 5)
        if math.random(100) <= chance then
            -- 报价在要价的 75%~110% 之间浮动
            local ratio = 0.75 + math.random() * 0.35
            local offerPrice = math.floor(listing.askingPrice * ratio * 100) / 100
            local buyerNames = {"万澜集团", "碧川园", "恒远地产", "保宁发展", "中泽地产", "龙川集团", "融盛控股", "华泽置地", "绿野控股", "招远港湾", "金川集团", "新川控股", "中岚控股", "旭川集团", "世川集团"}
            local buyer = buyerNames[math.random(#buyerNames)]
            table.insert(listing.offers, {
                buyer = buyer,
                price = offerPrice,
                month = GD.totalMonths,
                expired = false,
            })
            GD.AddEvent("【" .. listing.projectName .. "】收到" .. buyer .. "的报价：" .. GD.FormatMoney(offerPrice), "info")
        end

        -- 超过2个月未接受的报价过期
        for _, offer in ipairs(listing.offers) do
            if not offer.expired and GD.totalMonths - offer.month >= 2 then
                offer.expired = true
            end
        end

        ::continue_listing::
    end
end

-- ============================================================================
-- 商业资产市场: 生成可购买物业
-- ============================================================================
local MARKET_ASSET_TYPES = {
    -- priceMult: 相对城市地价(avgPrice)的价格系数（商业物业通常高于住宅地价）
    -- 年租金 = 总价 × (1/rentDivisor[1] ~ 1/rentDivisor[2])，不同类型不同区间
    {type = "写字楼",      areaRange = {2000, 8000},  priceMult = {0.8, 1.2},  rentDivisor = {16, 18}, occupancy = {0.70, 0.95}},
    {type = "商业综合体",  areaRange = {5000, 20000}, priceMult = {1.0, 1.5},  rentDivisor = {15, 17}, occupancy = {0.75, 0.95}},
    {type = "社区商铺",    areaRange = {500, 3000},   priceMult = {1.0, 1.8},  rentDivisor = {15, 16}, occupancy = {0.80, 0.98}},
    {type = "产业园区",    areaRange = {3000, 15000}, priceMult = {0.3, 0.6},  rentDivisor = {18, 20}, occupancy = {0.60, 0.90}},
    {type = "酒店物业",    areaRange = {3000, 10000}, priceMult = {1.0, 1.6},  rentDivisor = {16, 19}, occupancy = {0.55, 0.85}},
    {type = "长租公寓",    areaRange = {2000, 8000},  priceMult = {0.5, 0.9},  rentDivisor = {17, 20}, occupancy = {0.85, 0.98}},
}
local MARKET_SELLERS = {"金川置地", "通达地产", "远川集团", "首川股份", "能建地产", "铁川置业", "光川安石", "安和不动产", "玄石资本", "凯川集团", "太川地产", "嘉川建设"}
local MARKET_LOCATIONS = {"CBD核心区", "城市副中心", "高新技术区", "大学城片区", "交通枢纽旁", "老城区商圈", "滨江新区", "科创走廊"}

function GD.RefreshAssetMarket()
    local am = GD.assetMarket
    if not am then
        GD.assetMarket = {listings = {}, lastRefreshMonth = 0, nextId = 1}
        am = GD.assetMarket
    end
    -- 每季度刷新一批(保留未售出的)
    if GD.totalMonths - (am.lastRefreshMonth or 0) < 3 and #am.listings > 0 then return end
    am.lastRefreshMonth = GD.totalMonths

    -- 清除过期（超过6个月的）
    local kept = {}
    for _, li in ipairs(am.listings) do
        if GD.totalMonths - li.listMonth < 6 then
            table.insert(kept, li)
        end
    end
    am.listings = kept

    -- 生成3~5个新物业
    local newCount = math.random(3, 5)
    local city = GD.GetCityData()
    local cityAvgPrice = city and city.avgPrice or 15000  -- 元/㎡
    for _ = 1, newCount do
        local tmpl = MARKET_ASSET_TYPES[math.random(#MARKET_ASSET_TYPES)]
        local area = math.random(tmpl.areaRange[1], tmpl.areaRange[2])
        local mult = tmpl.priceMult[1] + math.random() * (tmpl.priceMult[2] - tmpl.priceMult[1])
        local totalPrice = math.floor(area * cityAvgPrice * mult / 10000)  -- 万元 = 面积×城市地价×类型系数/10000
        local seller = MARKET_SELLERS[math.random(#MARKET_SELLERS)]
        local location = MARKET_LOCATIONS[math.random(#MARKET_LOCATIONS)]
        -- 年租金 = 总价 × 年化收益率(含装修加成，市场资产默认精装)
        local locPlot = "urban" -- 市场资产默认城区
        if location == "CBD核心区" then locPlot = "core"
        elseif location == "老城区商圈" or location == "交通枢纽旁" then locPlot = "urban"
        else locPlot = "suburb" end
        local cityTier = city and city.tier or 2
        local yieldRate = DT.GetFullRentYield(locPlot, cityTier, "standard")
        local annualRent = totalPrice * yieldRate
        local monthlyRent = math.floor(annualRent / 12)
        local rentYield = yieldRate
        local occupancy = tmpl.occupancy[1] + math.random() * (tmpl.occupancy[2] - tmpl.occupancy[1])

        am.nextId = (am.nextId or 1) + 1
        table.insert(am.listings, {
            id = am.nextId,
            name = location .. tmpl.type,
            type = tmpl.type,
            area = area,
            price = totalPrice,
            monthlyRent = monthlyRent,
            rentYield = math.floor(rentYield * 10000) / 100,  -- 百分比
            occupancy = math.floor(occupancy * 100) / 100,
            seller = seller,
            listMonth = GD.totalMonths,
            status = "available",  -- available / sold
            plotLocation = locPlot, -- 地块位置(core/urban/suburb)
        })
    end
end

--- 购买市场商业资产 → 转入固定资产
function GD.BuyMarketAsset(listingId)
    local am = GD.assetMarket
    if not am then return false, "市场未初始化" end
    local listing = nil
    for _, li in ipairs(am.listings) do
        if li.id == listingId and li.status == "available" then
            listing = li
            break
        end
    end
    if not listing then return false, "该物业已售出或不存在" end
    if GD.company.cash < listing.price then
        return false, "现金不足，需要" .. GD.FormatMoney(listing.price)
    end
    -- 扣款
    GD.company.cash = GD.company.cash - listing.price
    GD.company.monthlyExpense = GD.company.monthlyExpense + listing.price
    listing.status = "sold"
    -- 转入固定资产（需手动挂牌出租）
    local asset = {
        projectId = "market_" .. listing.id,
        projectName = listing.name,
        name = listing.name,
        holdUnits = 1,
        holdArea = listing.area,
        originalValue = listing.price,
        currentValue = listing.price,
        marketValue = listing.price,
        bookValue = listing.price,
        monthlyRent = 0,                  -- 需挂牌出租后才有租金
        occupancyRate = 0,
        mortgaged = false,
        mortgageLoanIdx = nil,
        convertMonth = GD.totalMonths,
        convertYear = GD.year,
        isMarketPurchase = true,          -- 标记为市场购买
        assetType = listing.type,
        isOperating = false,              -- 需手动挂牌出租
        isRentable = false,               -- 需手动挂牌出租
        isListed = false,                 -- 未挂牌出售
        isListedForRent = false,          -- 未挂牌出租
        renovLevel = "standard",          -- 市场购入默认精装
        plotLocation = listing.plotLocation or "urban",  -- 地块位置
    }
    table.insert(GD.fixedAssets, asset)
    GD.AddEvent("购入商业资产【" .. listing.name .. "】" .. listing.area .. "㎡，总价" .. GD.FormatMoney(listing.price) .. "，月租金" .. GD.FormatMoney(listing.monthlyRent) .. "（已自动开启运营）", "success")
    return true
end

--- 挂牌出售固定资产（包括市场购入的资产）
function GD.ListFixedAssetForSale(assetIdx, askingPrice)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then return false, "资产不存在" end
    -- 检查是否已挂牌
    for _, listing in ipairs(GD.assetListings) do
        if listing.projectName == fa.projectName and listing.status == "listed" then
            return false, "该资产已在挂牌中"
        end
    end
    local listing = {
        projectName = fa.projectName,
        askingPrice = askingPrice,
        status = "listed",
        listedMonth = GD.totalMonths,
        offers = {},
        monthsListed = 0,
        isFixedAsset = true,      -- 标记为固定资产挂牌
        fixedAssetIdx = assetIdx,
    }
    table.insert(GD.assetListings, listing)
    fa.isListed = true
    GD.AddEvent("【" .. fa.projectName .. "】固定资产已挂牌出售，要价" .. GD.FormatMoney(askingPrice), "info")
    return true
end

-- ============================================================================
-- 出租挂牌系统 (固定资产/自持物业 → 挂牌出租 → 寻找租户 → 签约出租)
-- ============================================================================
GD.rentalListings = {}

--- 租户类型定义
GD.TENANT_TYPES = {
    {id = "enterprise",  name = "企业租户",   rentMult = 1.0,   stabilityMonths = {12, 36}, desc = "大中型企业，租金稳定，长期租约"},
    {id = "retail",      name = "零售商户",   rentMult = 1.1,   stabilityMonths = {6, 24},  desc = "商铺零售，租金略高，续约不确定"},
    {id = "individual",  name = "散户租客",   rentMult = 0.85,  stabilityMonths = {3, 12},  desc = "个人租户，租金较低，流动性高"},
}

--- 读档后规范化出租挂牌数据；兼容旧存档未保存 rentalListings 导致固定资产租金丢失的问题
function GD.NormalizeRentalListingsAfterLoad()
    GD.rentalListings = GD.rentalListings or {}
    local fixedListed = {}
    local projectListed = {}

    for _, rl in ipairs(GD.rentalListings) do
        rl.assetName = rl.assetName or rl.name or "出租资产"
        rl.status = rl.status or ((rl.tenant and "leased") or "seeking")
        rl.targetRent = rl.targetRent or rl.actualRent or rl.monthlyRent or 0
        rl.actualRent = rl.actualRent or rl.monthlyRent or rl.targetRent or 0
        rl.monthlyRent = 0
        rl.totalRentCollected = rl.totalRentCollected or 0
        rl.leaseMonths = rl.leaseMonths or 0
        rl.leaseTerm = rl.leaseTerm or 12
        rl.monthsSeeking = rl.monthsSeeking or 0
        if rl.assetIdx then
            fixedListed[rl.assetIdx] = true
            local fa = GD.fixedAssets[rl.assetIdx]
            if fa then
                fa.isListedForRent = true
                if rl.status == "leased" then
                    fa.monthlyRent = rl.actualRent or fa.monthlyRent or 0
                    fa.occupancyRate = fa.occupancyRate > 0 and fa.occupancyRate or 90
                    fa.isOperating = true
                    fa.isRentable = true
                end
            end
        elseif rl.projectId then
            projectListed[rl.projectId] = true
        end
    end

    -- 旧存档：固定资产标记为已出租但出租挂牌列表未持久化，按资产字段恢复租约
    for idx, fa in ipairs(GD.fixedAssets or {}) do
        GD.EnsureFixedAssetFields(fa)
        if fa.isListedForRent and not fixedListed[idx] then
            local rent = fa.monthlyRent or 0
            local leased = rent > 0 and (fa.occupancyRate or 0) > 0
            table.insert(GD.rentalListings, {
                assetIdx = idx,
                assetName = fa.projectName or fa.name or "固定资产",
                tenantTypeId = "enterprise",
                tenantTypeName = "企业租户",
                targetRent = rent,
                actualRent = rent,
                status = leased and "leased" or "seeking",
                listedMonth = GD.totalMonths or 0,
                monthsSeeking = 0,
                tenant = leased and {name = "原租户", signMonth = GD.totalMonths or 0} or nil,
                leaseMonths = 0,
                leaseTerm = 12,
                totalRentCollected = 0,
                monthlyRent = 0,
            })
            fixedListed[idx] = true
        end
    end

    -- 旧存档：自持项目已挂牌出租但出租挂牌列表缺失，同样恢复
    for _, p in ipairs(GD.projects or {}) do
        if p.isListedForRent and not p._fixedAssetConverted and p.id and not projectListed[p.id] then
            local a = p.assets or {}
            local rent = a.monthlyRentIncome or 0
            local leased = rent > 0 and (a.occupancyRate or 0) > 0
            table.insert(GD.rentalListings, {
                projectId = p.id,
                assetName = p.name or "自持物业",
                tenantTypeId = "enterprise",
                tenantTypeName = "企业租户",
                targetRent = rent,
                actualRent = rent,
                status = leased and "leased" or "seeking",
                listedMonth = GD.totalMonths or 0,
                monthsSeeking = 0,
                tenant = leased and {name = "原租户", signMonth = GD.totalMonths or 0} or nil,
                leaseMonths = 0,
                leaseTerm = 12,
                totalRentCollected = a.totalRentIncome or 0,
                monthlyRent = 0,
            })
            projectListed[p.id] = true
        end
    end
end

--- 挂牌出租固定资产
---@param assetIdx number 固定资产索引
---@param tenantTypeId string 目标租户类型ID(enterprise/retail/individual)
---@return boolean, string|nil
function GD.ListFixedAssetForRent(assetIdx, tenantTypeId)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then return false, "资产不存在" end
    if fa.isListedForRent then return false, "该资产已在挂牌出租中" end
    if fa.renovLevel == "none" then return false, "毛坯状态不可出租，请先装修" end

    -- 查找租户类型
    local tenantType = nil
    for _, tt in ipairs(GD.TENANT_TYPES) do
        if tt.id == tenantTypeId then tenantType = tt; break end
    end
    if not tenantType then return false, "无效的租户类型" end

    -- 计算月租金
    local cityData = GD.GetCityData()
    local cityTier = cityData and cityData.tier or 2
    local plotLoc = fa.plotLocation or "urban"
    local fullYield = DT.GetFullRentYield(plotLoc, cityTier, fa.renovLevel or "none")
    local baseMonthlyRent = math.floor(fa.currentValue * fullYield / 12 * 100) / 100
    local adjustedRent = math.floor(baseMonthlyRent * tenantType.rentMult * 100) / 100

    local listing = {
        assetIdx = assetIdx,
        assetName = fa.projectName,
        tenantTypeId = tenantTypeId,
        tenantTypeName = tenantType.name,
        targetRent = adjustedRent,            -- 目标月租金(万)
        status = "seeking",                    -- seeking(寻找租户) / leased(已签约) / expired(到期)
        listedMonth = GD.totalMonths,
        monthsSeeking = 0,                     -- 寻找租户的月数
        tenant = nil,                          -- 签约租户信息
        leaseMonths = 0,                       -- 已租月数
        leaseTerm = 0,                         -- 租约总期(月)
        totalRentCollected = 0,                -- 累计租金
    }
    table.insert(GD.rentalListings, listing)
    fa.isListedForRent = true
    GD.AddEvent("【" .. fa.projectName .. "】已挂牌出租，目标租户：" .. tenantType.name .. "，目标月租" .. GD.FormatMoney(adjustedRent), "info")
    return true
end

--- 挂牌出租自持物业项目
---@param project table 项目
---@param tenantTypeId string 目标租户类型ID
---@return boolean, string|nil
function GD.ListProjectForRent(project, tenantTypeId)
    if not project then return false, "项目不存在" end
    local holdUnits = project.unitPlan and project.unitPlan.holdUnits or 0
    if holdUnits <= 0 and (project.devCategory or "sale") ~= "hold" then
        return false, "没有自持物业"
    end
    if project.isListedForRent then return false, "该项目已在挂牌出租中" end
    if project._fixedAssetConverted then return false, "已转入固定资产" end

    -- 查找租户类型
    local tenantType = nil
    for _, tt in ipairs(GD.TENANT_TYPES) do
        if tt.id == tenantTypeId then tenantType = tt; break end
    end
    if not tenantType then return false, "无效的租户类型" end

    -- 计算月租金
    local cityData = GD.GetCityData(project.land and project.land.city)
    local cityTier = cityData and cityData.tier or 2
    local plotLoc = project.plotLocation or (project.land and project.land.plotLocation) or "suburb"
    local renovLevel = project.renovLevel or "none"
    local holdArea = project.unitPlan and project.unitPlan.holdArea or (project.land and project.land.buildArea or 0)
    local marketValue = 0
    if project.sales and project.sales.basePrice > 0 then
        marketValue = math.floor(project.sales.basePrice * holdArea / 10000)
    else
        marketValue = math.floor((project.cost.landCost + project.cost.buildCost) * 1.2)
    end
    local fullYield = DT.GetFullRentYield(plotLoc, cityTier, renovLevel)
    local baseMonthlyRent = math.floor(marketValue * fullYield / 12 * 100) / 100
    local adjustedRent = math.floor(baseMonthlyRent * tenantType.rentMult * 100) / 100

    local listing = {
        projectId = project.id,
        assetName = project.name,
        tenantTypeId = tenantTypeId,
        tenantTypeName = tenantType.name,
        targetRent = adjustedRent,
        status = "seeking",
        listedMonth = GD.totalMonths,
        monthsSeeking = 0,
        tenant = nil,
        leaseMonths = 0,
        leaseTerm = 0,
        totalRentCollected = 0,
    }
    table.insert(GD.rentalListings, listing)
    project.isListedForRent = true
    GD.AddEvent("【" .. project.name .. "】自持物业已挂牌出租，目标租户：" .. tenantType.name .. "，目标月租" .. GD.FormatMoney(adjustedRent), "info")
    return true
end

--- 撤回出租
---@param rentalIdx number 出租挂牌索引
---@return boolean, string|nil
function GD.DelistRental(rentalIdx)
    local rl = GD.rentalListings[rentalIdx]
    if not rl then return false, "挂牌不存在" end

    -- 恢复资产/项目状态
    if rl.assetIdx then
        local fa = GD.fixedAssets[rl.assetIdx]
        if fa then
            fa.isListedForRent = false
            fa.monthlyRent = 0
            fa.occupancyRate = 0
        end
    elseif rl.projectId then
        for _, p in ipairs(GD.projects) do
            if p.id == rl.projectId then
                p.isListedForRent = false
                break
            end
        end
    end

    table.remove(GD.rentalListings, rentalIdx)
    GD.AddEvent("【" .. rl.assetName .. "】已撤回出租挂牌", "info")
    return true
end

--- 出租挂牌月度更新（寻找租户 + 收租）
function GD.UpdateRentalListings()
    local rentalSynergy = GDI.GetSynergy(GD)
    local TENANT_NAMES = {"华川科技", "讯联分部", "河马商联", "码点传媒", "美邻运营中心", "京川物流", "微米科技", "网川游戏",
        "星谷咖啡", "海川捞", "名川优品", "优衣汇", "屈川氏", "万川便利", "永川超市", "盒川鲜生",
        "张先生", "李女士", "王老板", "陈总", "刘先生", "赵女士"}

    for i = #GD.rentalListings, 1, -1 do
        local rl = GD.rentalListings[i]

        if rl.status == "seeking" then
            rl.monthsSeeking = rl.monthsSeeking + 1
            -- 每月有概率找到租户（挂牌越久概率越高）
            local chance = math.min(70, 20 + rl.monthsSeeking * 10)
            if math.random(100) <= chance then
                -- 签约成功
                local namePool
                if rl.tenantTypeId == "enterprise" then
                    namePool = {TENANT_NAMES[1], TENANT_NAMES[2], TENANT_NAMES[3], TENANT_NAMES[4], TENANT_NAMES[5], TENANT_NAMES[6], TENANT_NAMES[7], TENANT_NAMES[8]}
                elseif rl.tenantTypeId == "retail" then
                    namePool = {TENANT_NAMES[9], TENANT_NAMES[10], TENANT_NAMES[11], TENANT_NAMES[12], TENANT_NAMES[13], TENANT_NAMES[14], TENANT_NAMES[15], TENANT_NAMES[16]}
                else
                    namePool = {TENANT_NAMES[17], TENANT_NAMES[18], TENANT_NAMES[19], TENANT_NAMES[20], TENANT_NAMES[21], TENANT_NAMES[22]}
                end
                local tenantName = namePool[math.random(#namePool)]
                -- 租约期限
                local tt = nil
                for _, t in ipairs(GD.TENANT_TYPES) do
                    if t.id == rl.tenantTypeId then tt = t; break end
                end
                local termMonths = tt and math.random(tt.stabilityMonths[1], tt.stabilityMonths[2]) or 12
                -- 实际签约租金 = 目标租金 × (0.9~1.05)
                local rentRatio = 0.9 + math.random() * 0.15
                local actualRent = math.floor(rl.targetRent * rentRatio * 100) / 100

                rl.status = "leased"
                rl.tenant = {name = tenantName, signMonth = GD.totalMonths}
                rl.leaseTerm = termMonths
                rl.leaseMonths = 0
                rl.actualRent = actualRent

                -- 更新固定资产或自持项目的租金和出租率
                if rl.assetIdx then
                    local fa = GD.fixedAssets[rl.assetIdx]
                    if fa then
                        fa.monthlyRent = actualRent
                        fa.occupancyRate = math.random(80, 95)
                        fa.isOperating = true
                        fa.isRentable = true
                    end
                elseif rl.projectId then
                    for _, p in ipairs(GD.projects) do
                        if p.id == rl.projectId then
                            p.assets = p.assets or {}
                            p.assets.rentable = true
                            p.assets.occupancyRate = math.random(80, 95)
                            p.assets.monthlyRentIncome = actualRent
                            p.assets.totalRentIncome = p.assets.totalRentIncome or 0
                            break
                        end
                    end
                end

                GD.AddEvent("【" .. rl.assetName .. "】成功签约租户" .. tenantName .. "，月租" .. GD.FormatMoney(actualRent) .. "，租期" .. termMonths .. "个月", "success")
            end

        elseif rl.status == "leased" then
            rl.leaseMonths = rl.leaseMonths + 1
            local actualRent = rl.actualRent or rl.targetRent
            -- 根据出租率计算实际收入
            local occ = 90
            if rl.assetIdx then
                local fa = GD.fixedAssets[rl.assetIdx]
                if fa then occ = fa.occupancyRate or 90 end
            elseif rl.projectId then
                for _, p in ipairs(GD.projects) do
                    if p.id == rl.projectId then
                        occ = p.assets and (p.assets.occupancyRate or 90) or 90
                        break
                    end
                end
            end
            local rentIncome = math.floor(actualRent * (occ / 100)
                * (rentalSynergy.rentalIncomeFactor or 1) * 100) / 100
            if rl.projectId then
                for _, p in ipairs(GD.projects) do
                    if p.id == rl.projectId then
                        p.assets = p.assets or {}
                        p.assets.rentable = true
                        p.assets.monthlyRentIncome = rentIncome
                        p.assets.totalRentIncome = (p.assets.totalRentIncome or 0) + rentIncome
                        break
                    end
                end
            end
            rl.totalRentCollected = rl.totalRentCollected + rentIncome
            GD.company.cash = GD.company.cash + rentIncome
            GD.company.monthlyRevenue = GD.company.monthlyRevenue + rentIncome
            GD.AddLedger("income", "租金收入", (rl.assetName or rl.name or "物业") .. " 租金", rentIncome)

            -- 租约到期检查
            if rl.leaseMonths >= rl.leaseTerm then
                -- 50%概率续约，50%概率到期
                if math.random(100) <= 50 then
                    -- 续约，租金上调2%~5%
                    local newRent = math.floor(actualRent * (1.02 + math.random() * 0.03) * 100) / 100
                    rl.actualRent = newRent
                    rl.leaseMonths = 0
                    local tt = nil
                    for _, t in ipairs(GD.TENANT_TYPES) do
                        if t.id == rl.tenantTypeId then tt = t; break end
                    end
                    rl.leaseTerm = tt and math.random(tt.stabilityMonths[1], tt.stabilityMonths[2]) or 12
                    if rl.assetIdx then
                        local fa = GD.fixedAssets[rl.assetIdx]
                        if fa then fa.monthlyRent = newRent end
                    elseif rl.projectId then
                        for _, p in ipairs(GD.projects) do
                            if p.id == rl.projectId then
                                p.assets = p.assets or {}
                                p.assets.monthlyRentIncome = newRent
                                break
                            end
                        end
                    end
                    GD.AddEvent("【" .. rl.assetName .. "】租户" .. (rl.tenant and rl.tenant.name or "未知") .. "续约，新月租" .. GD.FormatMoney(newRent), "success")
                else
                    -- 到期不续约，回到寻找状态
                    rl.status = "seeking"
                    rl.monthsSeeking = 0
                    rl.tenant = nil
                    rl.leaseMonths = 0
                    rl.leaseTerm = 0
                    if rl.assetIdx then
                        local fa = GD.fixedAssets[rl.assetIdx]
                        if fa then
                            fa.monthlyRent = 0
                            fa.occupancyRate = 0
                            fa.isOperating = false
                        end
                    elseif rl.projectId then
                        for _, p in ipairs(GD.projects) do
                            if p.id == rl.projectId then
                                p.assets = p.assets or {}
                                p.assets.monthlyRentIncome = 0
                                p.assets.occupancyRate = 0
                                break
                            end
                        end
                    end
                    GD.AddEvent("【" .. rl.assetName .. "】租户到期未续约，重新寻找租户", "warning")
                end
            end
        end
    end
end

-- ============================================================================
-- 固定资产装修 (毛坯 → 简装/精装/豪装)
-- ============================================================================
--- 装修固定资产
---@param assetIdx number 固定资产索引
---@param renovLevelIdx number 装修等级索引(2=简装,3=精装,4=豪装)
---@return boolean, string|nil
function GD.RenovateFixedAsset(assetIdx, renovLevelIdx)
    local fa = GD.fixedAssets[assetIdx]
    if not fa then return false, "资产不存在" end
    if fa.renovLevel ~= "none" then return false, "该资产已装修（" .. fa.renovLevel .. "），不可重复装修" end
    if renovLevelIdx < 2 or renovLevelIdx > 4 then return false, "无效的装修等级" end

    local level = GD.RENOVATION_LEVELS[renovLevelIdx]
    if not level then return false, "装修等级不存在" end

    -- 计算装修费用
    local renovCost = math.floor(fa.holdArea * level.costPerSqm / 10000)  -- 元→万元
    if GD.company.cash < renovCost then
        return false, "现金不足，需要" .. GD.FormatMoney(renovCost)
    end

    -- 扣费
    GD.company.cash = GD.company.cash - renovCost
    GD.company.monthlyExpense = GD.company.monthlyExpense + renovCost

    -- 更新资产信息
    fa.renovLevel = level.id
    fa.renovCost = (fa.renovCost or 0) + renovCost
    fa.originalValue = fa.originalValue + renovCost
    fa.bookValue = fa.originalValue
    -- 装修后重新评估市场价值
    local appreciation = fa.currentValue - (fa.originalValue - renovCost)
    if appreciation < 0 then appreciation = 0 end
    fa.currentValue = fa.originalValue + math.floor(appreciation * level.valueRatio)

    GD.AddEvent("【" .. fa.projectName .. "】完成装修（" .. level.name .. "），花费" .. GD.FormatMoney(renovCost) .. "，新评估价" .. GD.FormatMoney(fa.currentValue), "success")
    return true
end

-- ============================================================================
-- 城市投资数据结构（按城市名索引，持久化存储各类投资记录）
-- ============================================================================
-- 城市研究数据始终归 GD.player.cityOperations 所有；模块加载早期 player 可能尚未初始化，
-- 因此先保留临时表，随后在 Init/Load/切换公司时重新绑定别名。
GD.cityInvestData  = GD.cityInvestData  or {}
GD.cityBondData    = GD.cityBondData    or {}
GD.citySponsorData = GD.citySponsorData or {}
GD.cityCreditData  = GD.cityCreditData  or {}
GD.cityBankData    = GD.cityBankData    or {}
GD.cityBOTData     = GD.cityBOTData     or {}
GD.EnsurePersonalCityOperations()

-- 获取或初始化某城市的投资数据
function GD.GetCityInvest(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.cityInvestData[cityName] then
        GD.cityInvestData[cityName] = {holdings = {}}
    end
    return GD.cityInvestData[cityName]
end

function GD.GetCityBond(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.cityBondData[cityName] then
        GD.cityBondData[cityName] = {holdings = {}}
    end
    return GD.cityBondData[cityName]
end

function GD.GetCitySponsor(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.citySponsorData[cityName] then
        GD.citySponsorData[cityName] = {history = {}, totalSpent = 0, totalBrand = 0}
    end
    return GD.citySponsorData[cityName]
end

function GD.GetCityCredit(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.cityCreditData[cityName] then
        GD.cityCreditData[cityName] = {
            deposits = {},        -- 存款列表
            loans    = {},        -- 贷款列表
            wealthFunds = {},     -- 理财产品
            totalDeposit = 0,     -- 总存款余额
            totalLoan    = 0,     -- 总贷款余额
            totalWealth  = 0,     -- 总理财余额
            totalInterestEarned = 0,   -- 累计存款利息收入
            totalLoanPaid       = 0,   -- 累计贷款利息支出
        }
    end
    return GD.cityCreditData[cityName]
end

function GD.GetTotalCityCreditLoan()
    local total = 0
    for _, data in pairs(GD.cityCreditData or {}) do
        for _, loan in ipairs(data.loans or {}) do
            if loan.active then
                total = total + (loan.remaining or loan.amount or 0)
            end
        end
    end
    return math.max(0, math.floor(total))
end

function GD.GetUnbookedCityCreditLoanDebt()
    local total = 0
    for _, data in pairs(GD.cityCreditData or {}) do
        for _, loan in ipairs(data.loans or {}) do
            if loan.active and not loan.bookedDebt then
                total = total + (loan.amount or 0)
            end
        end
    end
    return math.max(0, math.floor(total))
end

function GD.GetCityCreditLoanLimit()
    local personalNetWorth = PS.CalcNetWorth(GD)
    local reputation = GD.player and (GD.player.prestige or 0) or 0
    local creditMult = math.max(0.25, math.min(0.75, 0.35 + reputation / 1000))
    local maxLoan = math.floor(math.max(0, personalNetWorth) * creditMult)
    local used = GD.GetTotalCityCreditLoan()
    return maxLoan, math.max(0, maxLoan - used), personalNetWorth, used
end

function GD.ApplyCityCreditLoan(cityName, amount, annualRate)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "请输入有效金额" end
    if not GD.player then return false, "个人数据未初始化" end
    local maxLoan, remaining, netWorth, used = GD.GetCityCreditLoanLimit()
    if maxLoan <= 0 then return false, "个人净资产为0，暂无法申请城市信用社贷款" end
    if amount > remaining then
        return false, "贷款额度不足：个人净资产" .. GD.FormatMoney(netWorth) .. "，总额度" .. GD.FormatMoney(maxLoan)
            .. "，已用" .. GD.FormatMoney(used) .. "，剩余" .. GD.FormatMoney(remaining)
    end
    local creditData = GD.GetCityCredit(cityName)
    GD.player.cash = GD.player.cash + amount
    creditData.totalLoan = (creditData.totalLoan or 0) + amount
    table.insert(creditData.loans, {
        active = true,
        name = cityName .. "信用社贷款(" .. GD.FormatMoney(amount) .. ")",
        amount = amount,
        remaining = amount,
        annualRate = annualRate or 7.5,
        interestPaid = 0,
        bookedDebt = false,
    })
    GD.AddEvent("个人从" .. cityName .. "信用合作社贷款" .. GD.FormatMoney(amount) .. "，年化" .. tostring(annualRate or 7.5) .. "%", "info")
    return true
end

local CITY_BANK_STEP_COSTS = {500, 10000, 200, 5000, 800, 1000}

local function inferCityBankStep(bank)
    local step = tonumber(bank.step)
    if step then
        return math.max(0, math.min(6, math.floor(step)))
    end
    local invested = tonumber(bank.totalInvested) or 0
    local cumulative = 0
    local inferred = 0
    for i, cost in ipairs(CITY_BANK_STEP_COSTS) do
        cumulative = cumulative + cost
        if invested >= cumulative then
            inferred = i
        else
            break
        end
    end
    if inferred == 0 and invested > 0 then inferred = 1 end
    return inferred
end

function GD.EnsureCityBankFields(bank)
    if not bank then return nil end
    bank.step          = inferCityBankStep(bank)
    bank.stepCost      = bank.stepCost or {0,0,0,0,0,0}
    bank.totalInvested = bank.totalInvested or 0
    bank.depositCap        = bank.depositCap        or 50000
    bank.depositDemandRate = bank.depositDemandRate or 1.2
    bank.deposit1yRate     = bank.deposit1yRate     or 2.0
    bank.deposit3yRate     = bank.deposit3yRate     or 2.8
    bank.currentDeposits   = bank.currentDeposits   or 0
    bank.totalDepositInterest = bank.totalDepositInterest or 0
    bank.loanCap              = bank.loanCap              or 40000
    bank.loanPersonalRate     = bank.loanPersonalRate     or 5.8
    bank.loanEnterpriseRate   = bank.loanEnterpriseRate   or 4.9
    bank.currentLoans         = bank.currentLoans         or 0
    bank.totalLoanInterest    = bank.totalLoanInterest    or 0
    bank.wealthProducts = bank.wealthProducts or {}
    bank.totalWealthAUM = bank.totalWealthAUM or 0
    bank.totalWealthFee = bank.totalWealthFee or 0
    bank.totalShares   = bank.totalShares  or 10000
    bank.myShares      = bank.myShares     or 10000
    bank.shareholders  = bank.shareholders or {}
    bank.bankCash      = bank.bankCash or 0
    bank._capitalSeeded = bank._capitalSeeded == true
    bank.monthlyProfit = bank.monthlyProfit or 0
    bank.monthlyNetProfit = bank.monthlyNetProfit or bank.monthlyProfit or 0
    bank.monthlyDividend = bank.monthlyDividend or 0
    bank.retainedEarnings = bank.retainedEarnings or bank.totalProfit or 0
    bank.totalProfit   = bank.retainedEarnings
    if bank.step >= 6 and not bank._capitalSeeded then
        if bank.bankCash <= 0 and bank.totalInvested > 0 then
            bank.bankCash = bank.totalInvested
        end
        bank._capitalSeeded = true
    end
    return bank
end

function GD.GetCityBank(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.cityBankData[cityName] then
        GD.cityBankData[cityName] = {
            step          = 0,
            stepCost      = {0,0,0,0,0,0},
            totalInvested = 0,
            -- ── 存款业务（市场驱动）──
            depositCap        = 50000,  -- 存款上限(万)
            depositDemandRate = 1.2,    -- 活期利率(%)
            deposit1yRate     = 2.0,    -- 1年定期利率(%)
            deposit3yRate     = 2.8,    -- 3年定期利率(%)
            currentDeposits   = 0,      -- 当前吸收存款总额(万)
            totalDepositInterest = 0,   -- 累计付息支出
            -- ── 贷款业务（市场驱动）──
            loanCap              = 40000,  -- 贷款上限(万)
            loanPersonalRate     = 5.8,    -- 个人贷款利率(%)
            loanEnterpriseRate   = 4.9,    -- 企业贷款利率(%)
            currentLoans         = 0,      -- 当前放贷总额(万)
            totalLoanInterest    = 0,      -- 累计收息收入
            -- ── 财富管理（发行产品，市场认购）──
            wealthProducts = {},      -- 已发行理财产品列表
            totalWealthAUM = 0,       -- 理财资产管理规模(万)
            totalWealthFee = 0,       -- 累计管理费收入
            -- ── 股权结构 ──
            totalShares   = 10000,    -- 总股份(万股)
            myShares      = 10000,    -- 我方持股(万股)
            shareholders  = {},       -- 其他股东: {name, shares, pct}
            -- ── 银行独立账户 ──
            bankCash      = 0,      -- 银行账户余额(万)，所有经营收支均从此账户进出
            -- ── 收益汇总 ──
            monthlyProfit = 0,
            monthlyDividend = 0,
            retainedEarnings = 0,
            totalProfit   = 0,      -- 累计留存利润（未分红部分），也是可分红上限
        }
    end
    return GD.EnsureCityBankFields(GD.cityBankData[cityName])
end

function GD.GetCityBOT(cityName)
    GD.EnsurePersonalCityOperations()
    if not GD.cityBOTData[cityName] then
        GD.cityBOTData[cityName] = {
            projects     = {},    -- 已中标代建项目列表
            refreshSeed  = GD.totalMonths or 0,  -- 随机刷新种子
        }
    end
    return GD.cityBOTData[cityName]
end

-- ============================================================================
-- 城市投资月度收益处理
-- ============================================================================
function GD.UpdateCityInvestIncome()
    GD.EnsurePersonalCityOperations()
    local player = GD.player
    if not player then return end
    local function recordPersonalIncome(amount)
        if amount <= 0 then return end
        player.totalIncome = (player.totalIncome or 0) + amount
        player.totalInvestReturn = (player.totalInvestReturn or 0) + amount
        player.yearlyIncome = (player.yearlyIncome or 0) + amount
        player.yearlyInvestReturn = (player.yearlyInvestReturn or 0) + amount
    end
    local function creditPersonalIncome(amount)
        if amount <= 0 then return end
        player.cash = (player.cash or 0) + amount
        recordPersonalIncome(amount)
    end
    local function applyPersonalCashflow(amount)
        player.cash = (player.cash or 0) + amount
        recordPersonalIncome(amount)
    end

    -- 1. 股权/商品投资月度分红/收益
    for cityName, data in pairs(GD.cityInvestData) do
        for _, h in ipairs(data.holdings) do
            if h.active and h.monthlyReturn then
                local income = math.floor(h.amount * h.monthlyReturn / 100)
                if income > 0 then
                    creditPersonalIncome(income)
                    h.totalIncome = (h.totalIncome or 0) + income
                end
            end
        end
    end

    -- 2. 债券月度票息
    for cityName, data in pairs(GD.cityBondData) do
        for _, b in ipairs(data.holdings) do
            if b.active then
                local monthlyInterest = math.floor(b.principal * b.annualRate / 100 / 12)
                creditPersonalIncome(monthlyInterest)
                b.interestEarned = (b.interestEarned or 0) + monthlyInterest
                b.remainMonths = (b.remainMonths or b.termMonths) - 1
                -- 到期兑付本金
                if b.remainMonths <= 0 then
                    player.cash = (player.cash or 0) + (b.principal or 0)
                    b.active = false
                    GD.AddEvent("【" .. cityName .. "】债券到期兑付，本金" .. GD.FormatMoney(b.principal) .. "，累计利息" .. GD.FormatMoney(b.interestEarned), "success")
                end
            end
        end
    end

    -- 3. 信用合作社存款月利息
    for cityName, data in pairs(GD.cityCreditData) do
        local totalInterest = 0
        for _, dep in ipairs(data.deposits) do
            if dep.active then
                local interest = math.floor(dep.amount * dep.annualRate / 100 / 12)
                creditPersonalIncome(interest)
                dep.interestEarned = (dep.interestEarned or 0) + interest
                data.totalInterestEarned = (data.totalInterestEarned or 0) + interest
                totalInterest = totalInterest + interest
            end
        end
        -- 合作社贷款月利息（支出）
        for _, loan in ipairs(data.loans) do
            if loan.active then
                local interest = math.floor(loan.amount * loan.annualRate / 100 / 12)
                player.cash = (player.cash or 0) - interest
                loan.interestPaid = (loan.interestPaid or 0) + interest
                data.totalLoanPaid = (data.totalLoanPaid or 0) + interest
            end
        end
        -- 理财产品月收益
        for _, wf in ipairs(data.wealthFunds) do
            if wf.active then
                local income = math.floor(wf.amount * wf.annualRate / 100 / 12)
                creditPersonalIncome(income)
                wf.incomeEarned = (wf.incomeEarned or 0) + income
            end
        end
    end

    -- 4. 商业银行月度市场驱动运营
    for cityName, bank in pairs(GD.cityBankData) do
        GD.EnsureCityBankFields(bank)
        if bank.step >= 6 then
            bank.depositCap        = bank.depositCap        or 50000
            bank.loanCap           = bank.loanCap           or 40000
            bank.depositDemandRate = bank.depositDemandRate or 1.2
            bank.deposit1yRate     = bank.deposit1yRate     or 2.0
            bank.deposit3yRate     = bank.deposit3yRate     or 2.8
            bank.loanPersonalRate  = bank.loanPersonalRate  or 5.8
            bank.loanEnterpriseRate= bank.loanEnterpriseRate or 4.9
            bank.currentDeposits   = bank.currentDeposits   or 0
            bank.currentLoans      = bank.currentLoans      or 0
            bank.totalWealthAUM    = bank.totalWealthAUM    or 0
            -- 向后兼容：只在首次迁移旧存档时将注册资本注入银行账户，避免每月重复补回资本。
            if not bank._capitalSeeded then
                if (bank.bankCash or 0) <= 0 and (bank.totalInvested or 0) > 0 then
                    bank.bankCash = bank.totalInvested
                end
                bank._capitalSeeded = true
            end
            bank.bankCash          = bank.bankCash          or 0

            -- 银行总资产按真实资产端计算：现金准备金 + 贷款资产。
            local function calcBankTotalAssets()
                return math.max(0, (bank.bankCash or 0) + (bank.currentLoans or 0))
            end
            -- 最低准备金按吸收存款的10%计提。
            local function calcMinReserve()
                return math.floor(math.max(0, bank.currentDeposits or 0) * 0.10)
            end

            -- ── 0. GDP挂钩：存贷上限随城市GDP增速动态调整
            local gdpGrowth = GD.macro and GD.macro.gdpGrowth or 6.0
            local cycle = GD.economy and GD.economy.cycle or "recovery"
            -- GDP增速影响存贷增长速率（增速高→增长快，增速低→增长慢甚至萎缩）
            local gdpFactor = math.max(0.2, math.min(2.0, gdpGrowth / 6.0))  -- 基准6%=1.0倍

            -- ── 1. 存款市场增长：利率+GDP双重影响
            local prevDeposits = bank.currentDeposits
            local depBenchmark = 2.0
            local depFactor = math.max(0.3, bank.deposit1yRate / depBenchmark)
            local depGrowth = math.floor(bank.depositCap * 0.015 * depFactor * gdpFactor)  -- 降低基础增速
            -- 经济下行时存款可能外流
            if cycle == "depression" then
                depGrowth = depGrowth - math.floor(bank.currentDeposits * 0.005)
            elseif cycle == "recession" then
                depGrowth = depGrowth - math.floor(bank.currentDeposits * 0.002)
            end
            bank.currentDeposits = math.max(0, math.min(bank.depositCap, bank.currentDeposits + depGrowth))
            -- 新增存款流入银行账户
            local depInflow = bank.currentDeposits - prevDeposits
            bank.bankCash = bank.bankCash + depInflow

            -- ── 2. 贷款市场增长：利率+GDP双重约束，受贷存比(≤75%)和准备金约束
            local prevLoans = bank.currentLoans
            local loanBenchmark = 5.5
            local loanFactor = math.max(0.3, loanBenchmark / math.max(0.1, bank.loanEnterpriseRate))
            local loanGrowth = math.floor(bank.loanCap * 0.012 * loanFactor * gdpFactor)  -- 降低基础增速
            local loanMaxByDeposit = math.floor(bank.currentDeposits * 0.75)
            local loanTarget = math.min(bank.loanCap, math.min(loanMaxByDeposit, bank.currentLoans + loanGrowth))
            -- 新增贷款须从 bankCash 划出，但不能低于准备金下限（总资产10%）
            local loanDelta = loanTarget - prevLoans
            if loanDelta > 0 then
                local minReserve = calcMinReserve()
                local maxLendable = math.max(0, bank.bankCash - minReserve)
                loanDelta = math.min(loanDelta, maxLendable)
            end
            bank.currentLoans = prevLoans + loanDelta
            bank.bankCash = bank.bankCash - loanDelta  -- 贷款划出

            -- ── 2.5 坏账机制：经济下行时部分贷款变成坏账
            bank.badDebt = bank.badDebt or 0
            bank.totalBadDebt = bank.totalBadDebt or 0
            bank.monthBadDebt = 0
            local badDebtRate = 0
            if cycle == "depression" then
                badDebtRate = 0.0006 + math.random() * 0.0009  -- 0.06%~0.15%月坏账率（年化0.7%~1.8%）
            elseif cycle == "recession" then
                badDebtRate = 0.0003 + math.random() * 0.0004  -- 0.03%~0.07%月坏账率（年化0.4%~0.8%）
            elseif cycle == "recovery" then
                badDebtRate = 0.0001 * math.random()          -- 0~0.01%
            end
            bank.monthBadDebt = math.floor(bank.currentLoans * badDebtRate)
            if bank.monthBadDebt > 0 then
                bank.currentLoans = bank.currentLoans - bank.monthBadDebt
                bank.badDebt = bank.badDebt + bank.monthBadDebt
                bank.totalBadDebt = bank.totalBadDebt + bank.monthBadDebt
                -- 坏账是贷款资产核销，不是现金支出；损失在净利润中一次性计入。
            end

            -- ── 3. 理财产品月度认购增长
            bank.totalWealthAUM = 0
            if bank.wealthProducts then
                for _, wp in ipairs(bank.wealthProducts) do
                    if wp.active then
                        local wpGrowth = math.floor(wp.targetSize * 0.18)
                        wp.currentAUM = math.min(wp.targetSize, (wp.currentAUM or 0) + wpGrowth)
                        bank.totalWealthAUM = bank.totalWealthAUM + wp.currentAUM
                        -- 管理费收入 → 进入银行账户
                        local feeIncome = math.floor(wp.currentAUM * (wp.feeRate or 0.5) / 100 / 12)
                        wp.totalFee = (wp.totalFee or 0) + feeIncome
                        bank.totalWealthFee = (bank.totalWealthFee or 0) + feeIncome
                        bank.bankCash = bank.bankCash + feeIncome
                    end
                end
            end

            local loanIncomeRaw = bank.currentLoans * bank.loanEnterpriseRate / 100 / 12
            local depExpenseRaw = bank.currentDeposits * bank.deposit1yRate / 100 / 12
            local loanIncome = math.floor(loanIncomeRaw + 0.5)
            local depExpense = math.floor(depExpenseRaw + 0.5)
            bank.totalLoanInterest    = (bank.totalLoanInterest    or 0) + loanIncome
            bank.totalDepositInterest = (bank.totalDepositInterest or 0) + depExpense
            bank.bankCash = bank.bankCash + loanIncome - depExpense

            -- 月度净利润必须保留真实正负值；否则亏损会被显示成0，且累计收益无法反映经营结果。
            local wealthFeeMonth = 0
            for _, wp in ipairs(bank.wealthProducts or {}) do
                if wp.active then
                    wealthFeeMonth = wealthFeeMonth + math.floor((wp.currentAUM or 0) * (wp.feeRate or 0.5) / 100 / 12 + 0.5)
                end
            end
            local netProfit = loanIncome - depExpense + wealthFeeMonth - (bank.monthBadDebt or 0)
            bank.monthlyNetProfit = netProfit
            bank.monthlyProfit = netProfit
            bank.monthlyDividend = 0
            bank.retainedEarnings = (bank.retainedEarnings or bank.totalProfit or 0) + netProfit
            bank.totalProfit = bank.retainedEarnings
        end
    end

    -- 5. BOT项目月通行费/广告收入
    for cityName, botData in pairs(GD.cityBOTData) do
        for _, proj in ipairs(botData.projects) do
            if proj.active and proj.remainMonths and proj.remainMonths > 0 then
                proj.selfFund = proj.selfFund or math.floor((proj.buildCost or 0) * 0.3)
                proj.debtFund = proj.debtFund or math.max(0, (proj.buildCost or 0) - proj.selfFund)
                proj.debtRemaining = proj.debtRemaining or proj.debtFund
                proj.investAmount = proj.investAmount or proj.selfFund
                if not proj._botCashflowV2 then
                    local elapsedMonths = math.max(0, 360 - (proj.remainMonths or 360))
                    local legacyNet = (proj.totalIncome or 0) - (proj.totalExpense or 0)
                    local legacyCap = math.floor((proj.selfFund or 0) * 0.06 / 12) * elapsedMonths
                    local cappedLegacyNet = math.min(legacyNet, legacyCap)
                    proj.totalOperationIncome = proj.totalIncome or 0
                    proj.totalOperationExpense = proj.totalExpense or 0
                    proj.totalIncome = math.max(0, cappedLegacyNet)
                    proj.totalExpense = math.max(0, -cappedLegacyNet)
                    if legacyNet > cappedLegacyNet then
                        proj.totalPublicConcession = (proj.totalPublicConcession or 0) + (legacyNet - cappedLegacyNet)
                    end
                    local migratedPrincipal = math.min(proj.debtFund or 0, math.floor((proj.debtFund or 0) * elapsedMonths / 360))
                    proj.debtRemaining = math.max(0, (proj.debtFund or 0) - migratedPrincipal)
                    proj.totalPrincipalRepaid = math.max(proj.totalPrincipalRepaid or 0, migratedPrincipal)
                    proj._botCashflowV2 = true
                end

                local monthIncome = math.floor(((proj.annualToll or 0) + (proj.annualAd or 0)) / 12)
                local operationExpense = math.floor(((proj.annualMaint or 0) + (proj.tax or 0) + (proj.finInterest or 0)) / 12)
                local principalRepay = 0
                if proj.debtRemaining > 0 then
                    local remainingMonths = math.max(1, proj.remainMonths or 1)
                    principalRepay = math.min(proj.debtRemaining, math.ceil(proj.debtRemaining / remainingMonths))
                    proj.debtRemaining = proj.debtRemaining - principalRepay
                end
                local monthExpense = operationExpense + principalRepay
                local rawMonthNet = monthIncome - monthExpense
                local annualNetCap = proj.annualNetCap or math.floor((proj.selfFund or 0) * 0.06)
                proj.annualNetCap = annualNetCap
                local monthlyNetCap = math.floor(annualNetCap / 12)
                local monthNet = math.min(rawMonthNet, monthlyNetCap)
                if rawMonthNet > monthNet then
                    proj.totalPublicConcession = (proj.totalPublicConcession or 0) + (rawMonthNet - monthNet)
                end
                proj.monthNet = monthNet
                applyPersonalCashflow(monthNet)
                proj.totalIncome = (proj.totalIncome or 0) + math.max(0, monthNet)
                proj.totalExpense = (proj.totalExpense or 0) + math.max(0, -monthNet)
                proj.totalOperationIncome = (proj.totalOperationIncome or 0) + monthIncome
                proj.totalOperationExpense = (proj.totalOperationExpense or 0) + operationExpense
                proj.totalPrincipalRepaid = (proj.totalPrincipalRepaid or 0) + principalRepay
                proj.remainMonths = proj.remainMonths - 1
                -- 30年到期无偿移交
                if proj.remainMonths <= 0 then
                    proj.active = false
                    GD.AddEvent("【" .. cityName .. "】BOT项目《" .. proj.name .. "》30年特许期满，已移交政府。累计投资净收益" .. GD.FormatMoney((proj.totalIncome or 0) - (proj.totalExpense or 0) - (proj.selfFund or 0)), "info")
                end
            end
        end
    end
end

-- ============================================================================
-- 多公司CEO托管月度经营推进
-- ============================================================================
function GD.UpdateManagedCompanyPortfolios(completedYear, completedMonth)
    if not GD.activeCompanyId or not GD.EnsureCompanyPortfolio then return 0 end
    GD.CaptureActiveCompanyState()
    GD.EnsureCompanyPortfolio(true)
    local originalId = GD.activeCompanyId
    local companyIds = {}
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        local company = record.state and record.state.company
        local gov = company and company.governance
        if tostring(record.id) ~= tostring(originalId)
            and record.status == "operating"
            and (record.founderRatio or getCompanyFounderRatio(company)) >= 0.50
            and gov and gov.fullManagement == true
            and gov.executives and gov.executives.ceo
        then
            companyIds[#companyIds + 1] = record.id
        end
    end

    local processed = 0
    local activeStateCaptured = true
    for _, companyId in ipairs(companyIds) do
        local switched = GD.SwitchCompany(companyId, activeStateCaptured)
        if switched then
            activeStateCaptured = false
            local previousCash = GD.company.cash or 0
            local previousRevenue = GD.company.monthlyRevenue or 0
            local previousExpense = GD.company.monthlyExpense or 0
            GD.ArchiveLedger(completedYear, completedMonth)
            GD.company.monthlyOpeningCash = previousCash
            GD.company.lastMonthRevenue = previousRevenue
            GD.company.lastMonthExpense = previousExpense
            GD.company.lastMonthProfit = previousRevenue - previousExpense
            GD.company.monthlyRevenue = 0
            GD.company.monthlyExpense = 0

            if GV.ManageCeoCashflow and GD.company.governance.ceoTargetDebtRatio then
                GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + 1, "多公司月度经营安全预留")
            end
            GD.UpdateProjects()
            GV.AutoManageCompany(GD, true)
            GD.UpdateAssets()
            GD.UpdateFixedAssets()
            GD.UpdateListings()
            GD.UpdateRentalListings()
            GD.UpdatePropertyMgmt()
            FN.MonthlyUpdate(GD)
            GD.UpdateFinance()
            GV.MonthlyUpdate(GD)
            GD.UpdateDepartmentCosts()
            GD.UpdateKeyPositionCosts()
            if GV.ManageCeoCashflow and GD.company.governance.ceoTargetDebtRatio then
                GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + 1, "多公司月度经营收支平衡")
            end
            GD.company.negativeCashMonths = GD.company.cash < 0
                and ((GD.company.negativeCashMonths or 0) + 1) or 0
            GD.CaptureActiveCompanyState()
            activeStateCaptured = true
            processed = processed + 1
        end
    end

    if tostring(GD.activeCompanyId) ~= tostring(originalId) then
        GD.SwitchCompany(originalId, activeStateCaptured)
    end
    if processed > 0 then
        print("[CEO-PORTFOLIO] 已推进非当前托管公司 count=" .. tostring(processed))
    end
    return processed
end

function GD.ProcessNonCurrentCompanyYearEnd()
    if GD.month ~= 12 or not GD.activeCompanyId or not GD.companyPortfolio then return 0 end
    GD.CaptureActiveCompanyState()
    local originalId = GD.activeCompanyId
    local companyIds = {}
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        if tostring(record.id) ~= tostring(originalId)
            and record.status == "operating"
            and (record.founderRatio or getCompanyFounderRatio(record.state and record.state.company)) > 0
        then
            companyIds[#companyIds + 1] = record.id
        end
    end

    local processed = 0
    local activeStateCaptured = true
    for _, companyId in ipairs(companyIds) do
        local switched = GD.SwitchCompany(companyId, activeStateCaptured)
        if switched then
            activeStateCaptured = false
            FN.YearlyCorpTaxSettlement(GD)
            local effectiveDividendRate = GD.company.dividendRate or 0
            if GD.company.governance and GD.company.governance.dividendPolicy then
                effectiveDividendRate = GD.company.governance.dividendPolicy.rate or effectiveDividendRate
            end
            GD.company.dividendRate = effectiveDividendRate
            if effectiveDividendRate > 0 then GD.YearlyDividend() end
            GD.UpdateEquityDividends()
            GD.CaptureActiveCompanyState()
            activeStateCaptured = true
            processed = processed + 1
        end
    end

    if tostring(GD.activeCompanyId) ~= tostring(originalId) then
        local restored, restoreError = GD.SwitchCompany(originalId, activeStateCaptured)
        if not restored then
            print("[YEAR-END] restore failed companyId=" .. tostring(originalId)
                .. " reason=" .. tostring(restoreError))
        end
    end
    if processed > 0 then
        print("[YEAR-END] processed non-current companies count=" .. tostring(processed))
    end
    return processed
end

-- ============================================================================
-- 月度Tick - 核心模拟引擎
-- ============================================================================
function GD.MonthlyTick()
    -- 先按已完成月份归档，再推进日期，避免3月账单被错误标记为4月。
    local completedYear = GD.year
    local completedMonth = GD.month
    local previousCash = GD.company.cash or 0
    local previousRevenue = GD.company.monthlyRevenue or 0
    local previousExpense = GD.company.monthlyExpense or 0
    GD.ArchiveLedger(completedYear, completedMonth)

    GD.month = GD.month + 1
    if GD.month > 12 then
        GD.month = 1
        GD.year = GD.year + 1
    end
    GD.totalMonths = GD.totalMonths + 1

    -- 0. 重置月度财务数据
    GD.company.monthlyOpeningCash = previousCash
    GD.company.lastMonthRevenue = previousRevenue
    GD.company.lastMonthExpense = previousExpense
    GD.company.lastMonthProfit = previousRevenue - previousExpense
    GD.company.monthlyRevenue = 0
    GD.company.monthlyExpense = 0

    -- 1. 经济周期更新
    GD.UpdateEconomy()

    -- 1.1 CEO托管现金流先于项目推进和月度扣款处理：在玩家设定的目标资产负债率内补足安全预留。
    -- 这样施工、利息、工资等本月经营支出不会因为CEO没有及时申请贷款而被动暂停。
    if GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        and GD.company.governance and GD.company.governance.ceoTargetDebtRatio
        and GV.ManageCeoCashflow
    then
        GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + 1, "月度经营安全预留")
    end

    -- 1.5 闲置土地检查
    GD.CheckIdleLands()

    -- 2. 更新项目进度
    GD.UpdateProjects()

    -- 2.1 CEO托管立即接管项目完工后的结算、竣工、转固、出租和售罄清盘。
    if GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        and GV.AutoManageCompany
    then
        local handled = GV.AutoManageCompany(GD, true)
        if handled > 0 then
            print("[CEO-LIFECYCLE] 月度自动处理项目事务 count=" .. tostring(handled))
        end
    end

    -- 3. 自持物业资产运营
    GD.UpdateAssets()

    -- 3.1 固定资产月度更新(价值重估)
    GD.UpdateFixedAssets()

    -- 3.15 挂牌出售系统月度更新
    GD.UpdateListings()

    -- 3.155 出租挂牌系统月度更新（寻找租户+收租）
    GD.UpdateRentalListings()

    -- 3.16 商业资产市场刷新（每季度自动刷新可购买物业）
    GD.RefreshAssetMarket()

    -- 3.2 物业管理费月度结算
    GD.UpdatePropertyMgmt()

    -- 3.5 金融系统月度更新（融资利息/监管账户/红线/现金流/税务）
    FN.MonthlyUpdate(GD)

    -- 3.55 城市投资月度收益（股权/债券/信用社/银行/BOT）
    GD.UpdateCityInvestIncome()

    -- 3.6 年度重置（1月）
    if GD.month == 1 then
        FN.YearlyReset(GD)
        PS.YearlyReset(GD)
        GD.UpdateDevStandardReputation()
    end

    -- 3.7 品牌与声誉月度更新（舆情/品牌分/危机检测）
    BR.MonthlyUpdate(GD)

    -- 3.8 股票市场月度更新
    SM.MonthlyUpdate(GD)

    -- 4. 财务计算
    GD.UpdateFinance()

    -- 5. 土地供地计划：按城市人口与基础设施余量，计划公布三个月后才释放招拍挂土地。
    local releasedLand, announcedPlans = GD.AdvanceLandSupplyPlans()
    if announcedPlans > 0 then
        GD.AddEvent("城市发布土地供地计划，三个月后进入拍卖", "info")
    end
    if releasedLand > 0 then
        GD.AddEvent("土地供地计划到期，释放" .. releasedLand .. "宗招拍挂土地", "success")
    end

    -- 5.5 推进尽职调查进度（市场中和储备中的地块）
    local function tickLandSurvey(l)
        if l.dueDiligence and l.dueDiligence.inProgress then
            local done, surveyType, risks = LA.TickSurvey(l)
            if done then
                local cfg = LA.SURVEY_CONFIG[surveyType]
                if risks and #risks > 0 then
                    GD.AddEvent("【" .. l.location .. "】" .. cfg.name .. "完成: 发现" .. #risks .. "项风险", "warning")
                else
                    GD.AddEvent("【" .. l.location .. "】" .. cfg.name .. "完成: 未发现异常", "success")
                end
            end
        end
    end
    for _, l in ipairs(GD.landMarket) do tickLandSurvey(l) end
    for _, l in ipairs(GD.landReserve) do tickLandSurvey(l) end

    -- 6. 随机事件
    GD.TriggerRandomEvent()

    -- 7. 信用分变化
    GD.UpdateCredit()

    -- 7.5 同业借款月度结息
    GD.UpdateCompLoans()

    -- 7.75 其余CEO托管公司先完成本月经营，确保所有成员公司的年末利润均在集团分红前归集。
    GD.CaptureActiveCompanyState()
    GD.UpdateManagedCompanyPortfolios(completedYear, completedMonth)

    -- 7.8 年度企业所得税汇算清缴（12月，在分红前计算）
    if GD.month == 12 then
        FN.YearlyCorpTaxSettlement(GD)
    end

    -- 8. 年度分红(所有公司均为股份制，每年12月结算)
    local effectiveDividendRate = GD.company.dividendRate
    if GD.company.governance and GD.company.governance.dividendPolicy then
        effectiveDividendRate = GD.company.governance.dividendPolicy.rate or effectiveDividendRate
    end
    GD.company.dividendRate = effectiveDividendRate  -- 保持同步
    if GD.month == 12 and effectiveDividendRate > 0 then
        GD.YearlyDividend()
    end

    -- 8.1 股权投资年度分红(12月)
    if GD.month == 12 then
        GD.UpdateEquityDividends()
        -- 未托管但仍在经营的公司也必须严格执行各自分红比例，成员公司股息统一归集集团。
        GD.ProcessNonCurrentCompanyYearEnd()
    end

    -- 8.45 创始人能力效率影响公司运营（效率>1加成收入，<1降低收入）
    if GD.player and GD.player.founderAlive then
        local eff = PS.GetCurrentEfficiency(GD)
        if math.abs(eff - 1.0) > 0.01 then
            local bonus = GD.company.monthlyRevenue * (eff - 1.0) * 0.3  -- 效率差异影响30%营收
            GD.company.monthlyRevenue = GD.company.monthlyRevenue + bonus
            GD.company.cash = GD.company.cash + bonus
        end
    end

    -- 8.5 个人财务月度更新（工资+投资收益+贷款+房产+生活+成就）
    PS.MonthlyUpdate(GD)

    -- 8.53 国际地产月结：先完成事业部汇率、租金、基金、项目、国际银行与国别事件结算。
    -- 集团总部随后读取事业部合并净资产，并处理集团本身的费用、融资和分红。
    INS.MonthlyUpdate(GD, completedYear, completedMonth)

    -- 8.54 集团总部月度更新：集团高管薪酬、集团贷款利息/到期还款及集团向个人分红。
    -- 集团分红必须先于12月个人所得税汇算入账，确保年度收入税基完整。
    GS.MonthlyUpdate(GD, completedYear, completedMonth)

    -- 8.55 年度个人所得税汇算清缴（12月收入全部入账后，自动从个人账户扣除）
    if GD.month == 12 then
        PS.YearlyTaxSettlement(GD)
    end

    -- 8.6 公司治理月度更新（控制权检查 + 高管职责）
    GV.MonthlyUpdate(GD)

    -- 9. 总部部门月度成本
    GD.UpdateDepartmentCosts()

    -- 10. 关键岗位年薪月摊
    GD.UpdateKeyPositionCosts()

    -- 11. CEO托管在所有月度扣款完成后再次平衡现金：应对随机事件、结算差额等预估外支出。
    if GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        and GD.company.governance and GD.company.governance.ceoTargetDebtRatio
        and GV.ManageCeoCashflow
    then
        GV.ManageCeoCashflow(GD, GV.GetManagementCashReserve(GD) + 1, "月度经营收支平衡")
    end

    -- 11.1 所有公司月结快照均已完成，统一生成汇报队列。
    GD.CaptureActiveCompanyState()
    if GD._pendingCeoReportPopup ~= true then
        local queued = GV.QueueCeoMonthlyReports and GV.QueueCeoMonthlyReports(GD) or 0
        if queued > 0 then
            GD.AddEvent("CEO已提交" .. queued .. "份月度经营报告，等待逐公司审批", "warning")
        end
    end

    -- 12. 现金负数月数累计 + 触发资金危机弹窗
    if GD.company.cash < 0 then
        GD.company.negativeCashMonths = (GD.company.negativeCashMonths or 0) + 1
        -- 首次变负（第1个月）：设置弹窗标记
        if GD.company.negativeCashMonths == 1 then
            GD._pendingCashCrisisPopup = true
            print("[CASH-CRISIS] MonthlyTick: 现金首次变负！设置弹窗标记 cash=" .. tostring(GD.company.cash))
        end
        if GD.company.negativeCashMonths >= 6 then
            GD.company.isGameOver = true
            GD.company.gameOverReason = string.format("现金流连续%d个月为负，公司被强制清算破产", GD.company.negativeCashMonths)
            GD.AddEvent("公司现金流持续为负超过6个月，被强制清算破产！", "danger")
        end
    else
        GD.company.negativeCashMonths = 0
        GD.company.cashCrisisWarned = false
    end

    -- 12. 云排行榜低频同步（避免每月平台写入造成月结卡顿）
    if GD.totalMonths % 6 == 0 then
        GD.SyncLeaderboard()
    end

    -- 13. 性能优化：定期清理冗余历史数据（每6个月执行一次）
    if GD.totalMonths % 6 == 0 then
        GD.PerformDataCleanup()
    end
end

--- 上传总资产到云排行榜
function GD.SyncLeaderboard()
    if not clientCloud then return end
    local assets = math.floor(GD.company.totalAssets)
    clientCloud:SetInt("total_assets", assets)
end

-- ============================================================================
-- 经济周期（整合宏观指标 + 政策周期）
-- ============================================================================
function GD.UpdateEconomy()
    local e = GD.economy
    local m = GD.macro
    local p = GD.policy
    e.cycleMonth = e.cycleMonth + 1

    -- 经济周期转换
    if e.cycleMonth >= e.cycleDuration then
        e.cycleMonth = 0
        e.cycleDuration = math.random(12, 24)
        if e.cycle == "boom" then
            e.cycle = "recession"
            GD.AddEvent("经济进入衰退期，市场降温", "warning")
        elseif e.cycle == "recession" then
            e.cycle = "depression"
            GD.AddEvent("市场进入萧条期，谨慎经营", "danger")
        elseif e.cycle == "depression" then
            e.cycle = "recovery"
            GD.AddEvent("经济开始复苏，市场回暖", "info")
        else
            e.cycle = "boom"
            GD.AddEvent("经济进入繁荣期，市场活跃", "success")
        end
    end

    -- (2.1) 更新宏观经济指标
    ME.UpdateMacro(m, e.cycle, GD.totalMonths)

    -- 同步核心字段: 利率使用 LPR
    e.interestRate = m.lpr5y

    -- 房价指数更新(受宏观+政策双重影响)
    local delta = 0
    if e.cycle == "boom" then
        delta = math.random(5, 15) * 0.1
    elseif e.cycle == "recession" then
        delta = math.random(-10, 2) * 0.1
    elseif e.cycle == "depression" then
        delta = math.random(-15, -3) * 0.1
    else
        delta = math.random(0, 10) * 0.1
    end
    -- 货币宽松度影响房价
    delta = delta + m.moneyLooseness * 0.005
    -- 待售面积过高抑制房价
    if m.unsoldArea > 50000 then delta = delta - 0.5
    elseif m.unsoldArea < 15000 then delta = delta + 0.3 end
    e.priceIndex = math.max(50, math.min(200, e.priceIndex + delta))

    -- 基础需求倍数(经济周期)
    local baseDemand = ({boom = 1.2, recovery = 1.0, recession = 0.8, depression = 0.5})[e.cycle] or 1.0
    -- (2.2) 政策对需求的影响
    local policyDemandMult = ME.GetPolicyDemandMultiplier(p)
    -- 居民杠杆率过高抑制需求
    local leverageMult = 1.0
    if m.householdLeverage > 60 then
        leverageMult = math.max(0.7, 1.0 - (m.householdLeverage - 60) * 0.01)
    end
    e.demandMultiplier = baseDemand * policyDemandMult * leverageMult

    -- 政策趋势映射
    e.policyTrend = p.overall.trend == "tightening" and "tighten"
        or (p.overall.trend == "loosening" and "loosen" or "neutral")

    -- (2.2) 更新政策周期
    ME.UpdatePolicy(p, e.cycle, m, GD.totalMonths)

    -- 衰减活跃的黑天鹅事件
    for i = #GD.activeBlackSwans, 1, -1 do
        GD.activeBlackSwans[i].remainMonths = GD.activeBlackSwans[i].remainMonths - 1
        if GD.activeBlackSwans[i].remainMonths <= 0 then
            table.remove(GD.activeBlackSwans, i)
        end
    end
end

-- ============================================================================
-- 项目进度更新
-- ============================================================================
function GD.UpdateProjects()
    for _, p in ipairs(GD.projects) do
        GD.EnsurePreconstructionFields(p)
        if p.status == "permits" or p.status == "design" then
            p.preconstructionElapsedMonths = math.min(
                GD.PRECONSTRUCTION_MAX_MONTHS,
                (p.preconstructionElapsedMonths or 0) + 1
            )
            if p.preconstructionElapsedMonths >= GD.PRECONSTRUCTION_MAX_MONTHS then
                forcePreconstructionComplete(p)
            end
        end

        -- 项目经理月薪扣除 & 自动推进
        if p.projectManager and p.projectManager.hired then
            GD.company.cash = GD.company.cash - p.projectManager.salary
            GD.PMAutoAdvance(p)
        end

        -- 四证办理
        if p.status == "permits" then
            local allDone = true
            local dirBonus = PC.GetDirectorBonuses(GD.company, p.id)
            local executiveEffects = GV.GetExecutiveEffects and GV.GetExecutiveEffects(GD) or {}
            local pmSpeed = (p.projectManager and p.projectManager.hired) and (p.projectManager.speedBonus or 0) or 0
            local permitBonus = (1 + (GD.company.traitEffects.permitSpeedBonus or 0)
                + (dirBonus.permitSpeed or 0) / 100 + pmSpeed
                + (executiveEffects.speedBonus or 0)
                + (executiveEffects.teamBonus or 0)) * 2  -- 报建手续速度缩短为原来一半时间
            for i, permit in ipairs(p.permits) do
                if permit.status == "processing" then
                    if (permit.duration or 0) <= 0 then
                        permit.progress = 100
                    else
                        permit.progress = permit.progress + (100 / permit.duration) * permitBonus
                    end
                    if permit.progress >= 100 then
                        permit.progress = 100
                        permit.status = "done"
                        GD.AddEvent("【" .. p.name .. "】" .. permit.name .. "已取得", "success")
                        -- 解锁下一个
                        if i < #p.permits then
                            local nextPermit = p.permits[i+1]
                            if nextPermit.duration and nextPermit.duration <= 0 then
                                -- 瞬时证照：同月直接完成，不再等待额外一个月
                                nextPermit.status = "done"
                                nextPermit.progress = 100
                                GD.AddEvent("【" .. p.name .. "】" .. nextPermit.name .. "已取得", "success")
                            else
                                nextPermit.status = "pending"
                            end
                        end
                    end
                end
                if permit.status ~= "done" then allDone = false end
            end
            if allDone then
                p.status = "design"
                p.design.phase = "concept"
                p.design.phaseProgress = 0
                GD.AddEvent("【" .. p.name .. "】四证齐全，进入规划设计阶段", "success")
            end
        end

        -- 规划设计
        if p.status == "design" then
            GD.UpdateDesign(p)
            if p.design.phase == "done" then
                p.status = "construction"
                p.cost.budgetPrecision = GD.COST_PRECISION_BY_PHASE["construction"] or 0.05
                GD.InitProcurementPackages(p)
                GD.AddEvent("【" .. p.name .. "】设计完成，开工建设！", "success")
            end
        end

        -- 工程建设 (7.1~7.5 由 Construction.lua 驱动)
        if p.status == "construction" then
            -- 按正常工期推进施工：不再因随机事件或资金状态暂停进度。
            RE.CheckJudicialHazard(p, GD)

            -- 建安成本按月支出（通过项目预算系统）— 随市场指数波动 × 城市风险差异
            local baseMonthlyCost = p.cost.buildCost / p.construction.totalMonths
            local rawAdj = GD.economy.priceIndex / (p.cost.basePriceIndex or 100) - 1  -- 偏离量（正=涨 负=跌）
            local typeDef = DT.GetType(p.devTypeId)
            local sensitivity = typeDef and typeDef.cycleSensitivity or 0.7
            local cityData = GD.GetCityData(p.land and p.land.city)
            local tierAmp = ({[1] = 1.4, [2] = 1.0, [3] = 0.6})[cityData and cityData.tier or 2] or 1.0  -- 一线放大、三线衰减
            local costIndexAdj = 1 + rawAdj * sensitivity * tierAmp
            local projectSynergy = GDI.GetProjectSynergy(GD, p)
            local monthlyCost = math.floor(baseMonthlyCost * costIndexAdj * (projectSynergy.constructionCostFactor or 1))
            local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
            local canAfford = not isManaged
                or GV.CanMaintainPositiveCash(GD, monthlyCost)

            if not canAfford then
                p.fundingSuspended = true
                GD.AddEvent("【" .. p.name .. "】CEO托管暂停施工：支付本月建设费后现金不足", "warning")
            else
                p.fundingSuspended = false

                local result = CS.MonthlyUpdate(p, GD)

                -- 扣款
                if p.budget and p.budget.remaining >= monthlyCost then
                    PC.SpendFromBudget(p, monthlyCost)
                else
                    local okFund = PC.AllocateFund(GD.company, p, monthlyCost)
                    if not okFund then
                        p.budget = p.budget or {allocated = 0, spent = 0, remaining = 0}
                        p.budget.allocated = (p.budget.allocated or 0) + monthlyCost
                        p.budget.remaining = p.budget.allocated - (p.budget.spent or 0)
                        GD.company.cash = GD.company.cash - monthlyCost
                        GD.AddEvent("【" .. p.name .. "】现金不足，建设仍按正常进度推进，透支补拨" .. monthlyCost .. "万", "warning")
                    else
                        GD.AddEvent("【" .. p.name .. "】预算不足，自动补拨" .. monthlyCost .. "万", "warning")
                    end
                    PC.SpendFromBudget(p, monthlyCost)
                end
                p.cost.totalCost = p.cost.totalCost + monthlyCost
                -- 月度融资成本（土地成本的年化4%按月摊）
                local monthlyFinCost = math.floor((p.cost.landCost or 0) * 0.04 / 12)
                if monthlyFinCost > 0 then
                    p.cost.financeCost = (p.cost.financeCost or 0) + monthlyFinCost
                    p.cost.totalCost = p.cost.totalCost + monthlyFinCost
                    GD.company.cash = GD.company.cash - monthlyFinCost
                end
                -- （月度税费已移除，税收仅在清盘结算时手动缴纳）
                -- 区域公司PnL追踪
                if p.regionalCompanyIdx then
                    local rc = GD.company.regionalCompanies[p.regionalCompanyIdx]
                    if rc then rc.pnl = rc.pnl - monthlyCost end
                end
                GD.UpdateDynamicCost(p)
                GD.UpdateProcurementTick(p)

                -- 达到预售条件(仅销售型) —— 只标记 canPresale，不自动开售
                if (p.devCategory or "sale") == "sale" then
                    if result.canPresale and not p.sales.canPresale then
                        p.sales.canPresale = true
                        GD.AddEvent("【" .. p.name .. "】达到预售条件，可在营销页面开始预售!", "success")
                    end
                end

                if result.isComplete then
                    GD.company.totalBuiltArea = GD.company.totalBuiltArea + p.land.buildArea
                    -- 施工完成 → 进入待结算状态（不自动退款，等待手动结算）
                    local cat = p.devCategory or "sale"
                    if cat == "sale" then
                        p.status = "pending_settlement"
                        p._afterSettlementStatus = "pending_completion"
                        GD.AddEvent("【" .. p.name .. "】施工完成！请进行项目结算", "warning")
                    elseif cat == "hold" then
                        p.status = "pending_settlement"
                        p._afterSettlementStatus = "pending_operations"
                        GD.AddEvent("【" .. p.name .. "】施工完成！请先进行项目结算，结算后再选择运营模式", "warning")
                    elseif cat == "agency" then
                        p.status = "settlement"
                        AF.SettleProject(p, GD)
                    end
                    GD.CheckQualification()
                end
            end -- canAfford else end
        end

        -- 预售期(同时施工+销售)
        if p.status == "presale" then
            -- 预售期也按正常工期推进施工，不再因停工事件暂停。

            -- 建安成本按月支出（通过项目预算系统）— 随市场指数波动 × 城市风险差异
            local baseMonthlyCost = p.cost.buildCost / p.construction.totalMonths
            local rawAdj = GD.economy.priceIndex / (p.cost.basePriceIndex or 100) - 1
            local typeDef = DT.GetType(p.devTypeId)
            local sensitivity = typeDef and typeDef.cycleSensitivity or 0.7
            local cityData = GD.GetCityData(p.land and p.land.city)
            local tierAmp = ({[1] = 1.4, [2] = 1.0, [3] = 0.6})[cityData and cityData.tier or 2] or 1.0
            local costIndexAdj = 1 + rawAdj * sensitivity * tierAmp
            local projectSynergy = GDI.GetProjectSynergy(GD, p)
            local monthlyCost = math.floor(baseMonthlyCost * costIndexAdj * (projectSynergy.constructionCostFactor or 1))
            local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
            local canAfford = not isManaged
                or GV.CanMaintainPositiveCash(GD, monthlyCost)

            if not canAfford then
                p.fundingSuspended = true
                GD.AddEvent("【" .. p.name .. "】CEO托管暂停施工：支付本月建设费后现金不足", "warning")
            else
                p.fundingSuspended = false

                local result = CS.MonthlyUpdate(p, GD)

                -- 扣款
                if p.budget and p.budget.remaining >= monthlyCost then
                    PC.SpendFromBudget(p, monthlyCost)
                else
                    local okFund = PC.AllocateFund(GD.company, p, monthlyCost)
                    if not okFund then
                        p.budget = p.budget or {allocated = 0, spent = 0, remaining = 0}
                        p.budget.allocated = (p.budget.allocated or 0) + monthlyCost
                        p.budget.remaining = p.budget.allocated - (p.budget.spent or 0)
                        GD.company.cash = GD.company.cash - monthlyCost
                        GD.AddEvent("【" .. p.name .. "】现金不足，建设仍按正常进度推进，透支补拨" .. monthlyCost .. "万", "warning")
                    else
                        GD.AddEvent("【" .. p.name .. "】预算不足，自动补拨" .. monthlyCost .. "万", "warning")
                    end
                    PC.SpendFromBudget(p, monthlyCost)
                end
                p.cost.totalCost = p.cost.totalCost + monthlyCost
                -- 月度融资成本（土地成本的年化4%按月摊）
                local monthlyFinCost2 = math.floor((p.cost.landCost or 0) * 0.04 / 12)
                if monthlyFinCost2 > 0 then
                    p.cost.financeCost = (p.cost.financeCost or 0) + monthlyFinCost2
                    p.cost.totalCost = p.cost.totalCost + monthlyFinCost2
                    GD.company.cash = GD.company.cash - monthlyFinCost2
                end
                -- （月度税费已移除，税收仅在清盘结算时手动缴纳）
                -- 区域公司PnL追踪
                if p.regionalCompanyIdx then
                    local rc = GD.company.regionalCompanies[p.regionalCompanyIdx]
                    if rc then rc.pnl = rc.pnl - monthlyCost end
                end
                GD.UpdateDynamicCost(p)
                GD.UpdateProcurementTick(p)

                if result.isComplete then
                    GD.company.totalBuiltArea = GD.company.totalBuiltArea + p.land.buildArea
                    -- 施工完成 → 进入待结算状态（不自动退款，等待手动结算）
                    p.status = "pending_settlement"
                    GD.AddEvent("【" .. p.name .. "】施工完成！请进行项目结算", "warning")
                    GD.CheckQualification()
                end
            end -- canAfford else end
            -- 销售(营销子系统) - 无论是否停工，销售继续
            MK.MonthlyUpdate(p, GD)
            -- 施工期也可能售罄（预售）
            GD._CheckAllUnitsSold(p)
        end

        -- 交付期继续销售
        if p.status == "delivery" then
            if p.sales.totalUnits > 0 then
                MK.MonthlyUpdate(p, GD)
            end
            GD._CheckAllUnitsSold(p)
            -- ★ 兜底：如果已售罄但状态仍为 delivery（旧存档/预售期售罄），直接完成
            if p.status == "delivery" then
                local s = p.sales
                if (s.totalUnits <= 0) or (s.allUnitsSold) or (s.totalUnits > 0 and s.soldUnits >= s.totalUnits) then
                    p.status = "completed"
                    s.allUnitsSold = true
                    GD.AddEvent("【" .. p.name .. "】全部售罄，项目完成", "success")
                end
            end
        end

        -- 待结算期（施工完成，等待玩家手动结算）
        if p.status == "pending_settlement" then
            if p.sales.totalUnits > 0 then
                MK.MonthlyUpdate(p, GD)
            end
            GD._CheckAllUnitsSold(p)
        end

        -- 待竣工期（已结算，等待玩家手动确认竣工）
        if p.status == "pending_completion" then
            if p.sales.totalUnits > 0 then
                MK.MonthlyUpdate(p, GD)
            end
            GD._CheckAllUnitsSold(p)
        end

        -- 持有型运营期(购物中心/写字楼/长租公寓/酒店)
        -- 注: OP.CalculateMonthlyFinancials 已将 NOI 加入公司现金，此处不再重复
        if p.status == "operations" then
            if p.operations then
                OP.MonthlyUpdate(p, GD)
                local ops = p.operations
                -- 成熟期超过24个月 → 标记为mature(长期运营)
                if ops.status == "mature" and (ops.matureMonths or 0) > 24 then
                    p.status = "mature"
                    GD.AddEvent("【" .. p.name .. "】运营成熟，进入长期持有阶段", "success")
                end
            end
        end

        -- 持有型成熟期(长期运营，持续产生收益)
        if p.status == "mature" then
            if p.operations then
                OP.MonthlyUpdate(p, GD)
            end
        end

        -- 代建型结算期
        if p.status == "settlement" then
            if p.agency then
                AF.MonthlyUpdate(p, GD)
                local ag = p.agency
                -- AF.MonthlyUpdate 已负责实际收款入账；这里不再重复加现金，只处理完成状态。
                if ag.settled then
                    p.status = "completed"
                    GD.AddEvent("【" .. p.name .. "】代建结算完成，项目结束", "success")
                end
            end
        end

        ::continue_project::
    end
end

-- ============================================================================
-- 自持物业资产运营(月度)
-- ============================================================================
function GD.UpdateAssets()
    for _, p in ipairs(GD.projects) do
        -- 持有型项目通过 operations/mature 状态单独处理运营收入，跳过旧逻辑
        if (p.devCategory or "sale") == "hold" then goto continue_assets end
        -- 已转入固定资产的跳过（租金由固定资产系统处理）
        if p._fixedAssetConverted then goto continue_assets end
        local a = p.assets
        -- 自持物业租金由出租挂牌系统统一处理，此处仅做租金单价初始化
        if a.rentable and p.unitPlan.holdUnits > 0 then
            -- 月租金单价 = 售价 × 年化收益率(含装修加成) / 12
            if a.monthlyRentPricePerSqm <= 0 and p.sales.basePrice > 0 then
                local cityData = GD.GetCityData(p.land and p.land.city)
                local cityTier = cityData and cityData.tier or 2
                local plotLoc = p.plotLocation or (p.land and p.land.plotLocation) or "suburb"
                local renovLevel = p.renovLevel or "none"  -- 项目自持默认毛坯
                local annualYield = DT.GetFullRentYield(plotLoc, cityTier, renovLevel)
                a.monthlyRentPricePerSqm = p.sales.basePrice * annualYield / 12
            end
            -- 未挂牌出租的项目不自动收租（需玩家手动挂牌）
            if not p.isListedForRent then goto continue_assets end
            -- 出租率缓慢爬升: +2%~5%/月, 上限95%
            if a.occupancyRate < 95 then
                a.occupancyRate = math.min(95, a.occupancyRate + math.random(2, 5))
            end
            -- 月租金收入(万元) — 由出租挂牌系统收取，此处仅同步数据
            local rentIncome = a.monthlyRentPricePerSqm * p.unitPlan.holdArea * (a.occupancyRate / 100) / 10000
            a.monthlyRentIncome = math.floor(rentIncome * 100) / 100
            a.totalRentIncome = a.totalRentIncome + a.monthlyRentIncome
        end
        ::continue_assets::
    end
end

-- ============================================================================
-- 物业管理费系统
-- ============================================================================
-- ============================================================================
-- 手动清盘
-- ============================================================================
--- 手动开始预售（玩家点击"开始预售"触发）
function GD.StartPresale(project)
    if not project then return false, "项目不存在" end
    if project.sales.canSell then return false, "已在销售中" end
    if not project.sales.canPresale then return false, "尚未达到预售条件" end

    project.sales.canSell = true
    project.status = "presale"
    project.cost.budgetPrecision = GD.COST_PRECISION_BY_PHASE["presale"] or 0.05

    -- 自动初始化单元规划（如果玩家未设置）
    if not project.unitPlan.planned then
        local totalArea = project.land.buildArea or 10000
        local avgUnitArea = 100
        local totalUnits = math.max(1, math.floor(totalArea / avgUnitArea))
        project.unitPlan.planned = true
        project.unitPlan.sellUnits = totalUnits
        project.unitPlan.holdUnits = 0
        project.sales.totalUnits = totalUnits
        GD.AddEvent("【" .. project.name .. "】自动完成单元规划：" .. totalUnits .. "套全部销售", "info")
    end

    -- 自动设置基础定价（如果玩家未设置）
    if project.sales.basePrice <= 0 then
        local city = GD.GetCityData(project.land and project.land.city)
        local plotLoc = project.plotLocation or (project.land and project.land.plotLocation) or "suburb"
        local stdId = project.standardId or "basic"
        -- 使用实际楼面地价参与定价公式（地价+前期+建安+利润）
        local floorPrice = project.land and project.land.floorPrice or 0
        local expectedPrice = DT.GetExpectedPrice(project.devTypeId, city.avgPrice, plotLoc, stdId, floorPrice)
        local suggestPrice = math.floor(expectedPrice * (GD.economy.priceIndex / 100))
        project.sales.basePrice = suggestPrice
        if (project.sales.packageBasePrice or 0) <= 0 then
            project.sales.packageBasePrice = suggestPrice
        end
        GD.AddEvent("【" .. project.name .. "】自动定价：" .. suggestPrice .. "元/平", "info")
    end

    -- 记录批准开盘价（涨价控制机制的基准价）- 开盘时始终以当前basePrice为基准
    if project.sales.basePrice > 0 then
        if (project.sales.packageBasePrice or 0) <= 0 then
            if (project.sales.approvedOpeningPrice or 0) > 0 then
                project.sales.packageBasePrice = project.sales.approvedOpeningPrice
            else
                project.sales.packageBasePrice = project.sales.basePrice
            end
        end
        project.sales.approvedOpeningPrice = project.sales.basePrice
    end

    GD.AddEvent("【" .. project.name .. "】正式开始预售！", "success")
    return true
end

function GD.ManualClearance(project)
    if not project then return false, "项目不存在" end
    if project.salesCleared then return false, "已清盘" end

    -- ====================================================================
    -- 第一阶段：生成结算清单（不立即执行，等玩家确认缴税后再执行）
    -- 如果已有 clearanceSheet 且 taxPaid=true，则执行第二阶段
    -- ====================================================================
    if project.clearanceSheet and project.clearanceSheet.taxPaid then
        -- 第二阶段：玩家已确认缴税，执行实际清盘
        project.salesCleared = true
        local sheet = project.clearanceSheet

        -- 将签约队列中尚未回款的批次强制结算入账，并释放已有监管余额。
        GD.SettlePendingSalesCollections(project, "项目清盘回款", true)
        releaseEscrowNow(project)

        -- 扣除项目所得税（税前利润×20%）
        if sheet.incomeTax > 0 then
            project.cost.incomeTax = sheet.incomeTax
            project.cost.totalCost = project.cost.totalCost + sheet.incomeTax
            GD.company.cash = GD.company.cash - sheet.incomeTax
            -- 同步到 Finance 的税务累计
            if GD.finance and GD.finance.taxData then
                GD.finance.taxData.projectTaxPaid = (GD.finance.taxData.projectTaxPaid or 0) + sheet.incomeTax
            end
        end

        GD.AddEvent("【" .. project.name .. "】已缴纳项目所得税" .. GD.FormatMoney(sheet.incomeTax), "warning")

        -- 联合拿地清盘分红：按投入比例分成【税后】利润
        if project.jointBid then
            local jb = project.jointBid
            local totalCost = project.cost and project.cost.totalCost or 0
            local financeCost = project.cost and project.cost.financeCost or 0
            local partnerInvest = jb.partnerLandCost or 0
            local totalInvest = totalCost
            local partnerRatio = totalInvest > 0 and (partnerInvest / totalInvest) or 0
            local playerRatio = 1 - partnerRatio

            -- 税后净利润 = 总收入 - 总成本（已含所得税）
            local netProfitAfterTax = (sheet.totalRevenue or sheet.revenue) - totalCost

            jb.clearanceDetail = {
                totalCost = totalCost,
                financeCost = financeCost,
                revenue = sheet.totalRevenue or sheet.revenue,
                netProfit = netProfitAfterTax,
                incomeTax = sheet.incomeTax,
                partnerInvest = partnerInvest,
                playerInvest = totalCost - partnerInvest,
                partnerFinalRatio = math.floor(partnerRatio * 1000) / 10,
                playerFinalRatio = math.floor(playerRatio * 1000) / 10,
            }

            if netProfitAfterTax > 0 then
                local partnerDividend = math.floor(netProfitAfterTax * partnerRatio)
                jb.clearanceDetail.partnerDividend = partnerDividend
                jb.clearanceDetail.playerDividend = netProfitAfterTax - partnerDividend
                GD.company.cash = GD.company.cash - partnerDividend
                GD.AddEvent("【" .. project.name .. "】清盘分红：税后利润" .. GD.FormatMoney(netProfitAfterTax)
                    .. "，" .. jb.partnerName .. "分得" .. GD.FormatMoney(partnerDividend)
                    .. "（投入占比" .. string.format("%.1f%%", partnerRatio * 100) .. "）", "warning")
            else
                local partnerLoss = math.floor(math.abs(netProfitAfterTax) * partnerRatio)
                jb.clearanceDetail.partnerDividend = 0
                jb.clearanceDetail.playerDividend = 0
                jb.clearanceDetail.partnerLoss = partnerLoss
                GD.AddEvent("【" .. project.name .. "】清盘亏损：" .. GD.FormatMoney(math.abs(netProfitAfterTax))
                    .. "，" .. jb.partnerName .. "承担亏损" .. GD.FormatMoney(partnerLoss)
                    .. "（投入占比" .. string.format("%.1f%%", partnerRatio * 100) .. "）", "info")
            end
        end

        -- 员工跟投结算
        if GD.Finance and GD.Finance.SettleCoinvestment then
            GD.Finance.SettleCoinvestment(GD, project.id)
        end

        GD.AddEvent("【" .. project.name .. "】已手动清盘", "success")
        return true
    end

    -- ====================================================================
    -- 第一阶段：生成结算清单（供 UI 显示，等玩家缴税确认）
    -- ====================================================================
    local cost = project.cost or {}
    local revenue = project.sales and project.sales.revenue or 0

    -- 将签约队列中尚未走完流水线的批次合同金额也计入销售收入
    -- 这些批次已签约成交，只是还在回款流程中
    local s = project.sales or {}
    local mk = s.marketing
    if mk and mk.collection and mk.collection.signingQueue then
        for _, batch in ipairs(mk.collection.signingQueue) do
            local batchRevenue = (batch.contractedRevenue or 0)
            if batchRevenue <= 0 then
                batchRevenue = (batch.unitCount or 0) * (batch.unitRevenue or 0)
            end
            revenue = revenue + batchRevenue
        end
    end
    -- 自持部分仅保留市场价值参考；销售清盘只核算出售房源，不把自持物业视作销售收入。
    local holdRevenue = 0
    if project.unitPlan and (project.unitPlan.holdUnits or 0) > 0 and not project._fixedAssetConverted then
        local holdArea = project.unitPlan.holdArea or 0
        local s = project.sales or {}
        local holdPrice = s.basePrice or 0
        if holdPrice <= 0 then
            local city = GD.GetCityData()
            holdPrice = city and city.avgPrice or 10000
        end
        holdRevenue = math.floor(holdArea * holdPrice / 10000)
    end
    local totalRevenue = revenue

    -- 混合项目清盘只分摊出售部分成本；自持部分成本留在固定资产原值中。
    local unitPlan = project.unitPlan or {}
    local sellArea = math.max(0, unitPlan.sellArea or (project.sales and project.sales.totalArea) or 0)
    local holdArea = math.max(0, unitPlan.holdArea or 0)
    local allocatedArea = sellArea + holdArea
    local saleCostRatio = allocatedArea > 0 and (sellArea / allocatedArea) or 1
    local totalCostBeforeLAT = (cost.totalCost or 0) * saleCostRatio
    local grossProfit = totalRevenue - totalCostBeforeLAT
    local incomeTax = 0
    local INCOME_TAX_RATE = 0.20
    if grossProfit > 0 then
        incomeTax = math.floor(grossProfit * INCOME_TAX_RATE)
    end

    local netProfitAfterTax = grossProfit - incomeTax

    -- 成本子项（用实际累积值，确保子项之和 = 合计）
    local cl_landCost = (cost.landCost or 0) * saleCostRatio
    local cl_designCost = (cost.designCost or 0) * saleCostRatio
    local cl_financeCost = (cost.financeCost or 0) * saleCostRatio
    local cl_marketingCost = (cost.marketingCost or 0) * saleCostRatio
    local cl_permitCost = (cost.permitCost or 0) * saleCostRatio
    local cl_ddCost = (cost.ddCost or 0) * saleCostRatio
    local cl_riskCost = (cost.riskCost or 0) * saleCostRatio
    -- 建设成本 = 总成本 - 其他已知子项（反算，包含市场波动的实际施工支出）
    local cl_buildCost = math.max(0, totalCostBeforeLAT - cl_landCost - cl_designCost
        - cl_financeCost - cl_marketingCost - cl_permitCost - cl_ddCost - cl_riskCost)
    -- 重新计算合计 = 各子项之和（确保精确相等）
    local cl_totalCost = cl_landCost + cl_buildCost + cl_designCost
        + cl_financeCost + cl_marketingCost + cl_permitCost + cl_ddCost + cl_riskCost

    -- 用精确合计重新算利润和税
    grossProfit = totalRevenue - cl_totalCost
    incomeTax = grossProfit > 0 and math.floor(grossProfit * INCOME_TAX_RATE) or 0
    netProfitAfterTax = grossProfit - incomeTax

    local netMargin = totalRevenue > 0 and (netProfitAfterTax / totalRevenue) or 0
    print("[PROJECT-CLEARANCE] project=" .. tostring(project.name)
        .. " revenue=" .. tostring(totalRevenue)
        .. " developmentCost=" .. tostring(cl_totalCost)
        .. " incomeTax=" .. tostring(incomeTax)
        .. " netProfit=" .. tostring(netProfitAfterTax)
        .. " netMargin=" .. string.format("%.2f%%", netMargin * 100))

    -- 生成结算清单
    project.clearanceSheet = {
        revenue = revenue,
        totalRevenue = totalRevenue,      -- 出售房源销售收入
        holdRevenue = holdRevenue,        -- 自持部分市场价值参考（不计入销售清盘收入）
        soldUnits = project.sales and project.sales.soldUnits or 0,
        totalUnits = project.sales and project.sales.totalUnits or 0,
        holdUnits = project.unitPlan and project.unitPlan.holdUnits or 0,
        -- 成本明细（子项之和 = totalCostBeforeTax）
        landCost = cl_landCost,
        buildCost = cl_buildCost,
        designCost = cl_designCost,
        marketingCost = cl_marketingCost,
        permitCost = cl_permitCost,
        financeCost = cl_financeCost,
        ddCost = cl_ddCost,
        riskCost = cl_riskCost,
        otherCost = 0,
        totalCostBeforeTax = cl_totalCost,
        -- 税费（仅项目所得税）
        incomeTaxRate = INCOME_TAX_RATE,
        incomeTax = incomeTax,
        -- 利润
        grossProfit = grossProfit,
        netProfitAfterTax = netProfitAfterTax,
        netMargin = netMargin,
        -- 缴税状态
        taxPaid = false,
    }

    GD.AddEvent("【" .. project.name .. "】结算清单已生成，请确认缴税后完成清盘", "info")
    return false, "clearance_sheet_ready"
end

--- 确认缴税并完成清盘
---@param project table
---@return boolean success
function GD.ConfirmClearanceTax(project)
    if not project then return false, "项目不存在" end
    if not project.clearanceSheet then return false, "未生成结算清单" end
    if project.clearanceSheet.taxPaid then return false, "已缴税" end
    project.clearanceSheet.taxPaid = true
    -- 再次调用 ManualClearance 执行第二阶段
    return GD.ManualClearance(project)
end

--- 项目结算（从 pending_settlement 进入 pending_completion）
--- 计算预算差额：多退少补
---@param project table
---@return boolean success
---@return string|nil msg
---@return table|nil details 结算明细
function GD.SettleProject(project)
    if not project then return false, "项目不存在" end
    if project.status ~= "pending_settlement" then
        return false, "项目不在待结算状态"
    end

    local details = {
        budgetAllocated = project.budget and project.budget.allocated or 0,
        budgetSpent = project.budget and project.budget.spent or 0,
        budgetRemaining = project.budget and project.budget.remaining or 0,
        refund = 0,
        shortfall = 0,
    }

    -- 计算实际建设总成本
    local totalCost = project.cost.totalCost or 0
    local budgetAllocated = details.budgetAllocated
    local budgetRemaining = details.budgetRemaining

    if budgetRemaining > 0 then
        -- 预算有余额 → 退回到公司账户
        details.refund = budgetRemaining
        GD.company.cash = GD.company.cash + budgetRemaining
        GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + budgetRemaining
        project.budget.remaining = 0
        GD.AddLedger("income", "项目结算", project.name .. " 剩余建设资金退回", budgetRemaining)
        GD.AddEvent("【" .. project.name .. "】结算退回剩余预算" .. GD.FormatMoney(budgetRemaining), "success")
    elseif budgetRemaining < 0 then
        -- 预算超支 → 需要从公司账户补缴差额
        local shortfall = math.abs(budgetRemaining)
        details.shortfall = shortfall
        local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        if isManaged and not GV.CanMaintainPositiveCash(GD, shortfall) then
            GD.AddEvent("【" .. project.name .. "】CEO托管延后结算：补缴差额后现金不足", "warning")
            return false, "托管现金不足，暂缓项目结算", details
        end
        if GD.company.cash >= shortfall then
            GD.company.cash = GD.company.cash - shortfall
            GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + shortfall
            project.budget.remaining = 0
            GD.AddLedger("expense", "项目结算", project.name .. " 结算补缴差额", shortfall)
            GD.AddEvent("【" .. project.name .. "】结算补缴差额" .. GD.FormatMoney(shortfall), "warning")
        else
            -- 资金不足也强制结算，记为负债
            GD.company.cash = GD.company.cash - shortfall
            GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + shortfall
            project.budget.remaining = 0
            GD.AddLedger("expense", "项目结算", project.name .. " 结算补缴差额", shortfall)
            GD.AddEvent("【" .. project.name .. "】结算补缴差额" .. GD.FormatMoney(shortfall) .. "（资金不足，已透支）", "danger")
        end
    end

    project.settlement = details
    local nextStatus = project._afterSettlementStatus or "pending_completion"
    project._afterSettlementStatus = nil
    project.status = nextStatus

    -- 员工跟投收益结算
    if GD.Finance and GD.Finance.SettleCoinvestment then
        GD.Finance.SettleCoinvestment(GD, project.id)
    end

    -- （项目税已移至清盘结算时手动缴纳，此处不再自动扣税）

    if nextStatus == "pending_operations" then
        GD.AddEvent("【" .. project.name .. "】项目结算完成！请选择运营模式或转入固定资产", "success")
    else
        GD.AddEvent("【" .. project.name .. "】项目结算完成！请确认竣工", "success")
    end
    return true, nil, details
end

--- 确认竣工（从 pending_completion 进入 delivery）
---@param project table
---@return boolean success
---@return string|nil msg
function GD.ConfirmCompletion(project)
    if not project then return false, "项目不存在" end
    if project.status ~= "pending_completion" then
        return false, "项目不在待竣工状态"
    end
    project.status = "delivery"
    -- 竣工后释放项目经理占用，但保留历史资料用于项目页展示，避免看起来“消失”。
    if project.projectManager and project.projectManager.hired then
        local pmName = project.projectManager.name
        project.projectManager.hired = false
        project.projectManager.released = true
        project.projectManager.releasedMonth = GD.totalMonths
        project.projectManager.autoMode = false
        project.projectManager.report = nil
        GD.AddEvent("项目经理【" .. pmName .. "】已完成" .. project.name .. "，可重新雇佣到其他项目", "info")
    end
    if project.unitPlan and project.unitPlan.planned and project.unitPlan.holdUnits > 0 then
        project.assets.rentable = true
        project.assets.occupancyRate = 30
    end
    -- 竣工后未售完的房子变为现房销售
    local s = project.sales
    if s and s.totalUnits > 0 and s.soldUnits < s.totalUnits then
        s.isExistingHomeSale = true  -- 标记为现房销售
        local remaining = s.totalUnits - s.soldUnits
        GD.AddEvent("【" .. project.name .. "】竣工确认！剩余" .. remaining .. "套转为现房销售", "success")
    else
        -- ★ 无可售单元 或 已全部售罄 → 跳过 delivery 直接 completed
        if s and s.totalUnits > 0 and s.soldUnits >= s.totalUnits then
            project.status = "completed"
            s.allUnitsSold = true
            GD.AddEvent("【" .. project.name .. "】竣工确认！全部售罄，项目完成", "success")
        elseif not s or s.totalUnits <= 0 then
            project.status = "completed"
            if s then s.allUnitsSold = true end
            GD.AddEvent("【" .. project.name .. "】竣工确认！项目完成", "success")
        else
            GD.AddEvent("【" .. project.name .. "】竣工确认！正式进入交付阶段", "success")
        end
    end
    -- 已售房源可开启物业服务
    local soldUnits = s and s.soldUnits or 0
    if soldUnits > 0 then
        GD.AddEvent("【" .. project.name .. "】已售" .. soldUnits .. "套，可在资产管理中开启物业服务收取物业费", "info")
    end
    return true
end

-- 物业服务等级配置
GD.PROPERTY_SERVICE_LEVELS = {
    {name = "基础物业", costPerSqm = 0.8, satisfactionBase = 60, collectionCap = 75,  desc = "保安+清洁"},
    {name = "标准物业", costPerSqm = 1.5, satisfactionBase = 80, collectionCap = 90,  desc = "安保+绿化+维修+客服"},
    {name = "高端物业", costPerSqm = 3.0, satisfactionBase = 95, collectionCap = 98,  desc = "管家式服务+智能社区"},
}

--- 根据开发类型获取默认物业费单价（元/平/月）
---@param devTypeId string|nil 开发类型ID
---@return number feePerSqm 默认物业费单价
function GD.GetDefaultPropertyFee(devTypeId)
    local fees = {
        rigid_residential     = 2.0,   -- 刚需住宅：物业费较低
        improved_residential  = 3.5,   -- 改善住宅：中等物业费
        luxury_residential    = 6.0,   -- 高端住宅：高物业费
        commercial_realestate = 8.0,   -- 商业地产：写字楼/商铺物业费最高
    }
    return fees[devTypeId] or 3.0
end

--- 启用/关闭物业费收取
function GD.TogglePropertyFee(projectIdx)
    local p = GD.projects[projectIdx]
    if not p then return false, "项目不存在" end
    if not p.propertyMgmt then p.propertyMgmt = {enabled=false,feePerSqm=GD.GetDefaultPropertyFee(p.devTypeId),collectionRate=0,monthlyIncome=0,totalIncome=0,serviceLevelIdx=1,satisfactionRate=80,monthlyOperateCost=0,staffCount=0} end
    if not p.propertyMgmt.staffCount then p.propertyMgmt.staffCount = 0 end
    local pm = p.propertyMgmt
    local soldUnits = p.sales and p.sales.soldUnits or 0
    if soldUnits <= 0 then return false, "无已售房源" end
    if p.status ~= "delivery" and p.status ~= "completed" and p.status ~= "operations" and p.status ~= "mature" then
        return false, "项目尚未交付"
    end
    pm.enabled = not pm.enabled
    if pm.enabled and pm.collectionRate <= 0 then
        pm.collectionRate = 50
    end
    GD.AddEvent("【" .. p.name .. "】物业费" .. (pm.enabled and "已启用" or "已停用"), "info")
    return true
end

--- 调整物业费单价
function GD.SetPropertyFeeRate(projectIdx, newFee)
    local p = GD.projects[projectIdx]
    if not p then return false, "项目不存在" end
    if not p.propertyMgmt then return false, "物业系统未初始化" end
    if newFee < 0.5 or newFee > 30 then return false, "单价须在0.5~30元/平/月" end
    local pm = p.propertyMgmt
    local oldFee = pm.feePerSqm
    pm.feePerSqm = newFee
    if newFee > oldFee then
        local dropPct = math.min(20, math.floor((newFee - oldFee) / oldFee * 30))
        pm.satisfactionRate = math.max(20, pm.satisfactionRate - dropPct)
    elseif newFee < oldFee then
        local upPct = math.min(15, math.floor((oldFee - newFee) / oldFee * 20))
        pm.satisfactionRate = math.min(100, pm.satisfactionRate + upPct)
    end
    GD.AddEvent("【" .. p.name .. "】物业费调整为 " .. string.format("%.1f", newFee) .. " 元/平/月", "info")
    return true
end

--- 升级物业服务等级
function GD.UpgradePropertyService(projectIdx, levelIdx)
    local p = GD.projects[projectIdx]
    if not p or not p.propertyMgmt then return false, "物业系统未初始化" end
    local level = GD.PROPERTY_SERVICE_LEVELS[levelIdx]
    if not level then return false, "无效等级" end
    local pm = p.propertyMgmt
    pm.serviceLevelIdx = levelIdx
    pm.satisfactionRate = math.max(pm.satisfactionRate, level.satisfactionBase)
    GD.AddEvent("【" .. p.name .. "】物业升级为「" .. level.name .. "」", "success")
    return true
end

--- 获取所有需要物业服务的项目（已售单元 > 0 且已交付/竣工）
function GD.GetAllPropertyProjects()
    local result = {}
    for idx, p in ipairs(GD.projects) do
        local soldUnits = p.sales and p.sales.soldUnits or 0
        if soldUnits > 0 and (p.status == "delivery" or p.status == "completed" or p.status == "operations" or p.status == "mature") then
            -- 确保物业管理数据已初始化（按开发类型设置默认物业费）
            if not p.propertyMgmt then
                p.propertyMgmt = {
                    enabled = false, feePerSqm = GD.GetDefaultPropertyFee(p.devTypeId), collectionRate = 0,
                    monthlyIncome = 0, totalIncome = 0, serviceLevelIdx = 1,
                    satisfactionRate = 80, monthlyOperateCost = 0,
                    staffCount = 0,
                }
            end
            if not p.propertyMgmt.staffCount then p.propertyMgmt.staffCount = 0 end
            table.insert(result, {project = p, idx = idx})
        end
    end
    return result
end

--- 雇佣/裁减物业人员
function GD.SetPropertyStaff(projectIdx, count)
    local p = GD.projects[projectIdx]
    if not p or not p.propertyMgmt then return false, "物业系统未初始化" end
    if count < 0 then return false, "人数不能为负" end
    local pm = p.propertyMgmt
    local old = pm.staffCount or 0
    pm.staffCount = count
    -- 人员数量影响满意度
    local soldUnits = p.sales and p.sales.soldUnits or 0
    if soldUnits > 0 then
        local ratio = count / math.max(1, math.ceil(soldUnits / 50))  -- 理想配比：每50户1人
        if ratio >= 1.0 then
            pm.satisfactionRate = math.min(100, pm.satisfactionRate + 2)
        elseif ratio < 0.5 then
            pm.satisfactionRate = math.max(20, pm.satisfactionRate - 3)
        end
    end
    if count > old then
        GD.AddEvent("【" .. p.name .. "】物业新增" .. (count - old) .. "名人员", "info")
    elseif count < old then
        GD.AddEvent("【" .. p.name .. "】物业裁减" .. (old - count) .. "名人员", "info")
    end
    return true
end

--- 物业费月度结算
function GD.UpdatePropertyMgmt()
    for _, p in ipairs(GD.projects) do
        if not p.propertyMgmt then goto continue_pm end
        local pm = p.propertyMgmt
        if not pm.enabled then
            pm.monthlyIncome = 0
            pm.monthlyOperateCost = 0
            goto continue_pm
        end
        local soldArea = p.sales and p.sales.soldArea or 0
        if soldArea <= 0 then goto continue_pm end

        local level = GD.PROPERTY_SERVICE_LEVELS[pm.serviceLevelIdx] or GD.PROPERTY_SERVICE_LEVELS[1]
        local propertySynergy = GDI.GetProjectSynergy(GD, p)

        -- 缴费率随满意度和集团物业能力调整，上限由服务等级决定
        local targetRate = math.min(100, math.min(level.collectionCap, pm.satisfactionRate)
            + (propertySynergy.propertyCollectionBonus or 0) * 100)
        if pm.collectionRate < targetRate then
            pm.collectionRate = math.min(targetRate, pm.collectionRate + math.random(2, 5))
        elseif pm.collectionRate > targetRate then
            pm.collectionRate = math.max(targetRate - 10, pm.collectionRate - math.random(1, 2))
        end

        -- 满意度自然变化
        local satDelta = 0
        if pm.feePerSqm <= level.costPerSqm * 1.5 then
            satDelta = math.random(0, 2)
        elseif pm.feePerSqm > level.costPerSqm * 3 then
            satDelta = -math.random(1, 3)
        end
        pm.satisfactionRate = math.max(20, math.min(100, pm.satisfactionRate + satDelta))

        -- 月物业费收入 = 已售面积 × 单价 × 缴费率 / 10000
        local grossIncome = soldArea * pm.feePerSqm * (pm.collectionRate / 100) / 10000
        -- 月运营成本 = 已售面积 × 服务等级成本单价 / 10000 + 人员工资
        local operateCost = soldArea * level.costPerSqm / 10000
        local staffCost = (pm.staffCount or 0) * 0.3  -- 每人月薪0.3万
        operateCost = (operateCost + staffCost) * (propertySynergy.propertyCostFactor or 1)

        pm.monthlyIncome = math.floor(grossIncome * 100) / 100
        pm.monthlyOperateCost = math.floor(operateCost * 100) / 100
        pm.totalIncome = pm.totalIncome + pm.monthlyIncome

        -- 净收入计入公司现金
        local netIncome = pm.monthlyIncome - pm.monthlyOperateCost
        GD.company.cash = GD.company.cash + netIncome
        GD.company.monthlyRevenue = GD.company.monthlyRevenue + pm.monthlyIncome
        GD.company.monthlyExpense = GD.company.monthlyExpense + pm.monthlyOperateCost
        GD.AddLedger("income", "物业收入", p.name .. " 物业管理费", pm.monthlyIncome)
        GD.AddLedger("expense", "物业运营", p.name .. " 物业运营成本", pm.monthlyOperateCost)

        ::continue_pm::
    end
end

-- ============================================================================
-- 开发标准口碑年度结算（每年调用一次）
-- 优质/高端标准给口碑奖励，同时检测质量风险
-- ============================================================================
function GD.UpdateDevStandardReputation()
    if not GD.brand then return end
    for _, p in ipairs(GD.projects) do
        local stdId = p.standardId or "basic"
        local std = DT.STANDARDS[stdId]
        if not std then goto continue_std end

        -- 仅对开发中/预售中的项目生效
        local isActive = (p.status == "construction" or p.status == "presale" or p.status == "design")
        if not isActive then goto continue_std end

        -- 口碑奖励（每年/每轮）
        if std.reputationPerRound > 0 then
            GD.brand.dimensions.productQuality = math.min(100,
                GD.brand.dimensions.productQuality + std.reputationPerRound)
            GD.AddEvent("【" .. p.name .. "】" .. std.name .. "标准建设，口碑+" .. std.reputationPerRound, "success")
        end

        -- 质量风险检测
        if std.qualityRisk > 0 then
            local roll = math.random()
            if roll < std.qualityRisk then
                -- 质量问题发生
                local repPenalty = std.qualityPenaltyReputation or -50
                local costPenaltyRatio = std.qualityPenaltyCostRatio or 0.15
                GD.brand.dimensions.productQuality = math.max(0,
                    GD.brand.dimensions.productQuality + repPenalty)
                -- 整改成本 = 建安成本 × 整改比例
                local rectCost = math.floor((p.cost.buildCost or 0) * costPenaltyRatio)
                p.cost.riskCost = (p.cost.riskCost or 0) + rectCost
                p.cost.totalCost = (p.cost.totalCost or 0) + rectCost
                p.cost.dynamicCost = (p.cost.dynamicCost or 0) + rectCost
                GD.company.cash = GD.company.cash - rectCost
                GD.AddEvent("【" .. p.name .. "】发生质量问题！口碑" .. repPenalty .. "，整改费用" .. rectCost .. "万元", "danger")
                -- 触发品牌危机
                if BR.TriggerCrisis then
                    BR.TriggerCrisis(GD, "quality_defect")
                end
            end
        end

        ::continue_std::
    end

    -- 已售楼盘物业服务加口碑：满意度高的已售项目持续提升口碑（交付和竣工阶段均生效）
    for _, p in ipairs(GD.projects) do
        if (p.status == "delivery" or p.status == "completed") and p.propertyMgmt and p.propertyMgmt.enabled then
            local pm = p.propertyMgmt
            if pm.satisfactionRate >= 80 then
                -- 满意度≥80的已售楼盘每年+2口碑
                GD.brand.dimensions.deliverySatisfy = math.min(100,
                    GD.brand.dimensions.deliverySatisfy + 2)
            elseif pm.satisfactionRate < 50 then
                -- 满意度<50的已售楼盘每年-3口碑
                GD.brand.dimensions.deliverySatisfy = math.max(0,
                    GD.brand.dimensions.deliverySatisfy - 3)
                GD.AddEvent("【" .. p.name .. "】业主满意度低，口碑下降", "warning")
            end
        end
    end
end

-- ============================================================================
-- 财务更新
-- ============================================================================
function GD.UpdateFinance()
    local expenseBeforeFinance = GD.company.monthlyExpense or 0
    local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
    local reserve = isManaged and GV.GetManagementCashReserve(GD) or 0
    local function spendCompanyCash(amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return true end
        if isManaged and (GD.company.cash or 0) - amount - reserve <= 0 then
            GD.AddEvent("CEO托管暂停扣款：现金安全预留不足", "warning")
            return false
        end
        GD.company.cash = GD.company.cash - amount
        return true
    end

    local function settleLoan(loan, payment, loanName)
        if spendCompanyCash(payment) then
            GD.company.totalDebt = GD.company.totalDebt - (loan.amount or 0)
            return true
        end
        GD.AddEvent("贷款【" .. loanName .. "】到期还款暂缓：CEO托管现金不足", "warning")
        loan.remainMonths = 1
        return false
    end

    -- 员工薪资：部门员工 + 旧全局员工（向后兼容）
    local deptSalaryWan = GD.GetTotalDeptSalary()
    local oldSalaryYuan = 0
    for _, emp in ipairs(GD.company.employees) do
        oldSalaryYuan = oldSalaryYuan + emp.salary
    end
    local salaryWan = deptSalaryWan + (oldSalaryYuan / 10000)
    GD.company.monthlySalary = salaryWan
    -- 注意：部门员工薪资已在UpdateDepartmentCosts中扣除，这里只扣旧员工
    local oldSalaryWan = oldSalaryYuan / 10000
    if not GV.SpendManagedCash(GD, oldSalaryWan, "CEO托管暂停支付旧员工工资：现金必须保持为正") then
        oldSalaryWan = 0
    end

    -- 贷款利息
    local interest = 0
    for i = #GD.loans, 1, -1 do
        local loan = GD.loans[i]
        local monthInterest = (loan.amount or 0) * (loan.rate or 0) / 100 / 12

        if loan.repayMethod == "bullet" then
            -- 到期还本付息：每月不扣息，累计到到期一次性支付
            loan.accruedInterest = (loan.accruedInterest or 0) + monthInterest
            interest = interest + 0  -- 不计入当月支出
        else
            -- 按月付息到期还本（默认）：每月扣除利息
            interest = interest + monthInterest
            if not spendCompanyCash(monthInterest) then
                loan.interestDeferred = (loan.interestDeferred or 0) + monthInterest
            end
        end

        loan.remainMonths = (loan.remainMonths or 1) - 1
        if loan.remainMonths <= 0 then
            local repayAmount = loan.amount or 0
            if loan.repayMethod == "bullet" then
                repayAmount = (loan.amount or 0) + (loan.accruedInterest or 0)
            end

            -- 检查是否为抵押贷款且现金不足 → 自动拍卖
            if (loan.isFixedAssetMortgage or loan.isProjectMortgage) and GD.company.cash < repayAmount then
                -- 抵押贷款违约：自动拍卖抵押物
                local auctionValue = 0
                if loan.isFixedAssetMortgage and loan.fixedAssetIdx then
                    -- 固定资产拍卖：按评估价的80%拍卖
                    local fa = GD.fixedAssets[loan.fixedAssetIdx]
                    if fa then
                        auctionValue = math.floor((fa.currentValue or 0) * 0.8)
                        GD.AddEvent("【" .. (fa.projectName or "未知资产") .. "】固定资产被银行强制拍卖！拍卖价"
                            .. GD.FormatMoney(auctionValue), "danger")
                        -- 拍卖所得先还贷款
                        GD.company.cash = GD.company.cash + auctionValue
                        -- 解除抵押并移除固定资产
                        fa.mortgaged = false
                        fa.mortgageLoanIdx = nil
                        local removedIdx = loan.fixedAssetIdx
                        table.remove(GD.fixedAssets, removedIdx)
                        -- 修正其他贷款的 fixedAssetIdx 引用
                        for _, otherLoan in ipairs(GD.loans) do
                            if otherLoan.fixedAssetIdx and otherLoan.fixedAssetIdx > removedIdx then
                                otherLoan.fixedAssetIdx = otherLoan.fixedAssetIdx - 1
                            end
                        end
                        -- 修正固定资产上的 mortgageLoanIdx 引用
                        for _, otherFa in ipairs(GD.fixedAssets) do
                            if otherFa.mortgageLoanIdx and otherFa.mortgageLoanIdx > removedIdx then
                                -- 注意：mortgageLoanIdx 指向 GD.loans 的索引，不受 fixedAssets 移除影响
                            end
                        end
                    else
                        GD.AddEvent("抵押固定资产已不存在，无法拍卖", "danger")
                    end
                elseif loan.isProjectMortgage and loan.projectId then
                    -- 项目拍卖：按项目价值的70%拍卖
                    local foundProject = false
                    for pIdx, p in ipairs(GD.projects) do
                        if p.id == loan.projectId then
                            local projValue = (p.cost and p.cost.landCost or 0) + (p.cost and p.cost.buildCost or 0)
                            auctionValue = math.floor(projValue * 0.7)
                            GD.AddEvent("【" .. (p.name or "未知项目") .. "】项目被银行强制拍卖！拍卖价"
                                .. GD.FormatMoney(auctionValue), "danger")
                            GD.company.cash = GD.company.cash + auctionValue
                            -- 标记项目为已拍卖
                            p.status = "sold_off"
                            p._auctioned = true
                            foundProject = true
                            break
                        end
                    end
                    if not foundProject then
                        GD.AddEvent("抵押项目已不存在，无法拍卖", "danger")
                    end
                end
            end

            local loanSettled = true
            local loanName = loan.name or "未知贷款"
            if loan.repayMethod == "bullet" then
                local totalPayment = (loan.amount or 0) + (loan.accruedInterest or 0)
                loanSettled = settleLoan(loan, totalPayment, loanName)
                GD.AddEvent("贷款【" .. loanName .. "】到期还本付息 本金"
                    .. GD.FormatMoney(loan.amount or 0) .. " + 利息"
                    .. GD.FormatMoney(loan.accruedInterest or 0), "warning")
            else
                loanSettled = settleLoan(loan, loan.amount or 0, loanName)
                GD.AddEvent("贷款【" .. loanName .. "】到期还款 " .. GD.FormatMoney(loan.amount or 0), "warning")
            end
            if loanSettled then
                table.remove(GD.loans, i)
            end
        end
    end

    GD.company.monthlyExpense = expenseBeforeFinance + oldSalaryWan + interest

    -- 高管薪资：计入费用 + 实际扣款
    local gov = GD.company.governance
    if gov and gov.executives then
        local execCost = 0
        for _, exec in pairs(gov.executives) do
            if exec.source ~= "group" then
                local monthlySalary = math.floor(((exec.salary or 0) / 12) * 100) / 100  -- 年薪/12=月薪
                execCost = execCost + monthlySalary
                if monthlySalary > 0 then
                    if spendCompanyCash(monthlySalary) then
                        exec.totalPaid = (exec.totalPaid or 0) + monthlySalary
                    end
                end
            end
        end
        GD.company.monthlyExpense = GD.company.monthlyExpense + execCost
    end

    -- ═══ 治理增益 & 高管效果 ═══
    local revenueMultiplier = 1.0
    local expenseMultiplier = 1.0
    if gov then
        local executiveEffects = GV.GetExecutiveEffects and GV.GetExecutiveEffects(GD) or {}
        -- 董事会决议增益（时限性）
        if gov.brandBoostUntil and GD.totalMonths <= gov.brandBoostUntil then
            revenueMultiplier = revenueMultiplier + 0.05  -- 品牌升级：收入+5%
        end
        if gov.techBoostUntil and GD.totalMonths <= gov.techBoostUntil then
            revenueMultiplier = revenueMultiplier + 0.08  -- 技术投资：收入+8%
        end
        if gov.strategyBoostUntil and GD.totalMonths <= gov.strategyBoostUntil then
            expenseMultiplier = expenseMultiplier - 0.10  -- 战略调整：费用-10%
        end
        if gov.auditSavingUntil and GD.totalMonths <= gov.auditSavingUntil then
            expenseMultiplier = expenseMultiplier - 0.05  -- 审计节省：费用-5%
        end

        -- 高管效果（持续性，在职期间有效）
        revenueMultiplier = revenueMultiplier + (executiveEffects.revenueBonus or 0)
        expenseMultiplier = expenseMultiplier - (executiveEffects.expenseReduction or 0)
    end

    -- 应用乘数（确保费用乘数不低于0.5），并把治理调整写入账单以保持最终损益可追溯。
    expenseMultiplier = math.max(0.5, expenseMultiplier)
    local rawRevenue = GD.company.monthlyRevenue
    local rawExpense = GD.company.monthlyExpense
    GD.company.monthlyRevenue = rawRevenue * revenueMultiplier
    GD.company.monthlyExpense = rawExpense * expenseMultiplier
    local revenueAdjustment = GD.company.monthlyRevenue - rawRevenue
    if math.abs(revenueAdjustment) > 0.001 then
        GD.AddLedger(revenueAdjustment > 0 and "income" or "expense", "经营治理调整",
            "治理与高管收入效率调整", math.abs(revenueAdjustment))
    end
    local expenseAdjustment = GD.company.monthlyExpense - rawExpense
    if math.abs(expenseAdjustment) > 0.001 then
        GD.AddLedger(expenseAdjustment > 0 and "expense" or "income", "经营治理调整",
            expenseAdjustment > 0 and "治理与高管费用调整" or "治理与高管费用节省",
            math.abs(expenseAdjustment))
    end

    GD.company.monthlyProfit = GD.company.monthlyRevenue - GD.company.monthlyExpense

    -- ═══ 明细账单记录（集中采集本月各项收支） ═══
    -- 支出项
    if salaryWan and salaryWan > 0 then
        GD.AddLedger("expense", "员工薪资", "公司员工月度工资", salaryWan)
    end
    if interest and interest > 0 then
        GD.AddLedger("expense", "贷款利息", "银行贷款月度利息", interest)
    end
    if gov and gov.executives then
        local execTotal = 0
        for _, exec in pairs(gov.executives) do
            execTotal = execTotal + math.floor(((exec.salary or 0) / 12) * 100) / 100
        end
        if execTotal > 0 then
            GD.AddLedger("expense", "高管薪酬", "C-suite高管月薪", execTotal)
        end
    end
    -- 部门运营费（含部门员工薪资）
    local deptOpCost = GD.company.monthlyDeptCost or 0
    if deptOpCost > 0 then
        GD.AddLedger("expense", "部门运营", "总部部门运营费用", deptOpCost)
    end
    -- 物业管理及租金均在实际到账时即时记账，避免月末状态变化导致漏记或重复。
    -- 城市商业银行与 BOT 均为个人持有，不进入公司月度明细账。
    -- 收入项：存款利息
    if GD.finance and GD.finance.deposits then
        for _, d in ipairs(GD.finance.deposits) do
            local monthI = math.floor(d.amount * (d.rate or 3.0) / 100 / 12)
            if monthI > 0 then
                GD.AddLedger("income", "存款利息", (d.bankName or "银行") .. " 存款利息", monthI)
            end
        end
    end
    -- 收入项：代建管理费
    if GD.agencyProjects then
        for _, ag in ipairs(GD.agencyProjects) do
            if ag.active and (ag.monthlyFeeIncome or 0) > 0 then
                GD.AddLedger("income", "代建收入", ag.name .. " 管理费", ag.monthlyFeeIncome)
            end
        end
    end
    -- 支出项：关键岗位薪酬
    local totalKPCost = 0
    for _, kp in ipairs(GD.company.keyPositions) do
        totalKPCost = totalKPCost + (kp.salary / 12)
    end
    if totalKPCost > 0 then
        GD.AddLedger("expense", "关键岗位", "关键岗位年薪月摊", totalKPCost)
    end
    -- 支出项：项目经理薪资
    local totalPMCost = 0
    for _, p in ipairs(GD.projects) do
        if p.projectManager and p.projectManager.hired then
            totalPMCost = totalPMCost + (p.projectManager.salary or 0)
        end
    end
    if totalPMCost > 0 then
        GD.AddLedger("expense", "项目经理", "项目经理月薪合计", totalPMCost)
    end
    -- 支出项：项目建设成本（当月施工支出）
    for _, p in ipairs(GD.projects) do
        if p.status == "construction" or p.status == "presale" then
            local monthlyCost = 0
            if p.construction and p.construction.totalMonths and p.construction.totalMonths > 0 then
                monthlyCost = math.floor((p.cost.buildCost or 0) / p.construction.totalMonths)
            end
            if monthlyCost > 0 then
                GD.AddLedger("expense", "建设成本", p.name .. " 月度建安", monthlyCost)
            end
            -- 融资成本
            local finCost = math.floor((p.cost.landCost or 0) * 0.04 / 12)
            if finCost > 0 then
                GD.AddLedger("expense", "融资成本", p.name .. " 土地融资利息", finCost)
            end
        end
    end
    -- 收入项：销售回款
    for _, p in ipairs(GD.projects) do
        if p.sales and p.sales.monthRevenue and p.sales.monthRevenue > 0 then
            GD.AddLedger("income", "销售回款", p.name .. " 本月回款", p.sales.monthRevenue)
        end
        -- 支出项：项目营销费用（含预算+广告+渠道佣金）
        if p.sales and p.sales.monthMarketingCost and p.sales.monthMarketingCost > 0 then
            GD.AddLedger("expense", "营销费用", p.name .. " 营销推广", p.sales.monthMarketingCost)
        end
    end
    -- 城市投资、地方债券与信用合作社均为个人持有，不进入公司月度明细账。
    -- 支出项：同业借款利息
    for _, loan in ipairs(GD._compLoans or {}) do
        if (loan.monthlyInterest or 0) > 0 then
            GD.AddLedger("expense", "同业借款", (loan.lender or "同行") .. " 借款月息", loan.monthlyInterest)
        end
    end
    -- 物业运营成本已在实际结算时即时记账。
    -- 支出项：税费（租金税）
    if GD.finance and GD.finance.tax then
        local rentalTax = GD.finance.tax.monthlyRentalTax or 0
        if rentalTax > 0 then
            GD.AddLedger("expense", "税费", "自持物业租金税", rentalTax)
        end
    end

    -- 累计年度利润(用于股份制分红)
    GD.company.annualProfit = GD.company.annualProfit + GD.company.monthlyProfit

    -- 总资产（现金 + 储备土地 + 存款 + 监管账户余额 + 固定资产账面净值）
    local totalLandValue = 0
    for _, l in ipairs(GD.landReserve) do
        totalLandValue = totalLandValue + (l.price or l.startPrice)
    end
    local depositBalance = 0
    local escrowBalance = 0
    if GD.finance then
        for _, d in ipairs(GD.finance.deposits) do
            depositBalance = depositBalance + d.amount
        end
        for _, ea in pairs(GD.finance.escrowAccounts) do
            escrowBalance = escrowBalance + (ea.balance or 0)
        end
    end
    -- 固定资产账面净值
    local fixedAssetValue = 0
    for _, fa in ipairs(GD.fixedAssets) do
        fixedAssetValue = fixedAssetValue + fa.bookValue
    end
    -- 在建工程资产(已投入的建设成本)
    local constructionInProgress = 0
    for _, p in ipairs(GD.projects) do
        if p.status == "construction" or p.status == "presale" or p.status == "delivery" or p.status == "pending_settlement" then
            constructionInProgress = constructionInProgress + (p.cost and p.cost.totalCost or 0)
        end
    end
    GD.company.constructionInProgress = constructionInProgress

    -- 城市商业银行、BOT、城市股权/债券和信用社均为个人资产，不参与公司资产计算。

    -- 股票持仓市值
    local stockValue = 0
    if GD.stockMarket and GD.stockMarket.holdings then
        for code, holding in pairs(GD.stockMarket.holdings) do
            if holding.shares > 0 then
                for _, stock in ipairs(GD.stockMarket.companies) do
                    if stock.code == code then
                        stockValue = stockValue + holding.shares * stock.currentPrice / 10000
                        break
                    end
                end
            end
        end
    end
    stockValue = math.floor(stockValue * 100) / 100

    GD.company.totalAssets = GD.company.cash + totalLandValue + depositBalance + escrowBalance
        + fixedAssetValue + constructionInProgress + stockValue

    -- 保存各公司资产分项供UI展示；个人城市经营资产不写入任一公司。
    GD.company.assetBreakdown = {
        cash = GD.company.cash,
        landReserve = totalLandValue,
        deposits = depositBalance,
        escrow = escrowBalance,
        fixedAssets = fixedAssetValue,
        construction = constructionInProgress,
        stockValue = stockValue,
    }
end

-- ============================================================================
-- 信用分
-- ============================================================================
function GD.UpdateCredit()
    -- 简化: 有盈利+1, 亏损-1, 负现金流-2
    if GD.company.monthlyProfit > 0 then
        GD.company.creditScore = math.min(100, GD.company.creditScore + 0.2)
    elseif GD.company.cash < 0 then
        GD.company.creditScore = math.max(0, GD.company.creditScore - 2)
    end
end

-- ============================================================================
-- 年度分红(股份制公司)
-- ============================================================================
function GD.YearlyDividend()
    local c = GD.company
    local dividend = GV.DistributeDividend(GD)
    if dividend > 0 then
        GD.AddEvent(GD.year .. "年度股东分红: " .. GD.FormatMoney(dividend) .. " (净利润" .. GD.FormatMoney(c.annualProfit) .. "的" .. math.floor((c.governance and c.governance.dividendPolicy.rate or c.dividendRate) * 100) .. "%)", "warning")
    else
        if c.annualProfit <= 0 then
            GD.AddEvent(GD.year .. "年度无盈利，不进行分红", "info")
        else
            GD.AddEvent(GD.year .. "年度现金不足，分红受限", "warning")
        end
    end
    c.annualProfit = 0  -- 重置年度利润
end

-- ============================================================================
-- 资质检查
-- ============================================================================
function GD.CheckQualification()
    local c = GD.company
    local area = c.totalBuiltArea
    if c.qualification == 0 and area >= 50000 and c.registeredCapital >= 800 then
        c.qualification = 1
        GD.AddEvent("恭喜！公司资质升级为【三级】", "success")
    elseif c.qualification == 1 and area >= 150000 and c.registeredCapital >= 2000 then
        c.qualification = 2
        GD.AddEvent("恭喜！公司资质升级为【二级】", "success")
    elseif c.qualification == 2 and area >= 300000 and c.registeredCapital >= 5000 then
        c.qualification = 3
        GD.AddEvent("恭喜！公司资质升级为【一级】", "success")
    end
end

-- ============================================================================
-- 随机事件（黑天鹅事件库 2.3）
-- ============================================================================
function GD.TriggerRandomEvent()
    local evt = ME.TriggerBlackSwan(GD.economy, GD.macro, GD.totalMonths)
    if not evt then return end

    -- 执行效果
    if evt.effect then
        evt.effect(GD.economy, GD.macro)
    end

    -- 记录事件
    GD.AddEvent(evt.text, evt.type)

    -- 持续型事件加入活跃列表
    if evt.duration and evt.duration > 0 then
        table.insert(GD.activeBlackSwans, {
            text = evt.text,
            type = evt.type,
            cat = evt.cat or "other",
            remainMonths = evt.duration,
        })
    end
end

-- ============================================================================
-- 竞拍AI逻辑 (委托 LandAcquisition 模块)
-- ============================================================================
function GD.GetAIBid(land, currentPrice, competitor)
    return LA.GetAIBid(land, currentPrice, competitor)
end

-- ============================================================================
-- 申请贷款
-- ============================================================================
function GD.ApplyLoan(name, amount, rate, months, projectId, repayMethod)
    amount = math.floor(math.max(0, tonumber(amount) or 0))
    if amount <= 0 then
        return false, "贷款金额无效"
    end

    -- 三条红线硬性拦截
    if GD.finance then
        local rl = GD.finance.redLine or {}
        local tierInfo = FN.RED_LINE_TIERS[math.max(1, math.min(#FN.RED_LINE_TIERS, tonumber(rl.tierIdx) or 1))]
        local debtGrowthCap = tonumber(rl.debtGrowthCap)
            or (tierInfo and tierInfo.debtGrowthCap)
            or 0
        if debtGrowthCap <= 0 then
            GD.AddEvent("【三条红线】当前为红档，禁止新增有息负债", "danger")
            return false, "当前为红档，禁止新增有息负债"
        end
    end
    -- 应用融资成本特质加成
    local finBonus = GD.company.traitEffects.financeCostBonus or 0
    -- 口碑利率优惠：score 80→-0.3%, score 100→-0.5%；score<40→+0.2%~+0.4%
    local brandScore = GD.brand and GD.brand.score or 50
    local brandRateAdj = 0
    if brandScore >= 50 then
        brandRateAdj = -(brandScore - 50) * 0.01  -- 每分降0.01%
    else
        brandRateAdj = (50 - brandScore) * 0.008   -- 每分升0.008%
    end
    -- 政策融资乘数: 开发贷额度管控
    local policyFinMult = ME.GetPolicyFinanceMultiplier(GD.policy)
    -- 实际可贷额度受政策影响
    local effectiveAmount = math.floor(amount * policyFinMult)
    if effectiveAmount <= 0 then
        return false, "政策管控后无可用贷款额度"
    end
    local effectiveRate = math.max(1.0, rate + finBonus + brandRateAdj) -- 至少1%
    local finalRepayMethod = repayMethod or "interest_monthly"
    local loan = {
        name = name,
        amount = effectiveAmount,
        rate = effectiveRate,
        totalMonths = months,
        remainMonths = months,
        projectId = projectId or nil,   -- 关联项目ID(项目抵押贷款)
        repayMethod = finalRepayMethod, -- "interest_monthly" | "bullet"
        accruedInterest = 0,            -- 到期还本付息时累计利息
    }
    table.insert(GD.loans, loan)
    GD.company.cash = GD.company.cash + effectiveAmount
    GD.company.totalDebt = GD.company.totalDebt + effectiveAmount
    GD.company.totalAssets = (GD.company.totalAssets or 0) + effectiveAmount
    if GD.company.assetBreakdown then
        GD.company.assetBreakdown.cash = GD.company.cash
    end
    local repayName = finalRepayMethod == "bullet" and "到期还本付息" or "按月付息到期还本"
    local msg = "成功获批贷款【" .. name .. "】" .. GD.FormatMoney(effectiveAmount)
        .. "，利率" .. effectiveRate .. "%，期限" .. months .. "个月"
        .. "，" .. repayName
    if effectiveAmount < amount then
        msg = msg .. "(政策管控下调" .. math.floor((1 - policyFinMult) * 100) .. "%)"
    end
    GD.AddEvent(msg, "success")
    return true, msg, effectiveAmount
end

-- 公司贷款提前还款统一入口：手动操作与CEO托管共用同一账务链路。
function GD.EarlyRepayLoan(loanIdx, principalAmount)
    return FN.EarlyRepay(GD, loanIdx, principalAmount)
end

-- 公司贷款批量提前还款：先整体验资，再按倒序复用统一账务链路。
function GD.BatchEarlyRepayLoans(loanIndexes)
    return FN.BatchEarlyRepay(GD, loanIndexes)
end

-- ============================================================================
-- 总部部门月度成本（运营费 + 员工薪资）
-- ============================================================================
function GD.UpdateDepartmentCosts()
    local totalDeptCost = 0
    local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
    local reserve = isManaged and GV.GetManagementCashReserve(GD) or 0
    for _, dept in ipairs(GD.company.hqDepartments) do
        if dept.established then
            totalDeptCost = totalDeptCost + dept.monthCost
        end
    end
    -- 部门员工薪资
    local staffSalary = GD.GetTotalDeptSalary()
    totalDeptCost = totalDeptCost + staffSalary

    GD.company.monthlyDeptCost = totalDeptCost  -- 记录供明细账单使用
    if totalDeptCost > 0 then
        if isManaged and (GD.company.cash or 0) - totalDeptCost - reserve <= 0 then
            GD.AddEvent("CEO托管暂停支付总部部门成本：现金安全预留不足", "warning")
        else
            GD.company.cash = GD.company.cash - totalDeptCost
            GD.company.monthlyExpense = GD.company.monthlyExpense + totalDeptCost
        end
    end
end

-- ============================================================================
-- 关键岗位年薪月摊
-- ============================================================================
function GD.UpdateKeyPositionCosts()
    local totalKPCost = 0
    local isManaged = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
    local reserve = isManaged and GV.GetManagementCashReserve(GD) or 0
    for _, kp in ipairs(GD.company.keyPositions) do
        totalKPCost = totalKPCost + (kp.salary / 12) -- 年薪月摊
    end
    if totalKPCost > 0 then
        if isManaged and (GD.company.cash or 0) - totalKPCost - reserve <= 0 then
            GD.AddEvent("CEO托管暂停支付关键岗位成本：现金安全预留不足", "warning")
        else
            GD.company.cash = GD.company.cash - totalKPCost
            GD.company.monthlyExpense = GD.company.monthlyExpense + totalKPCost
        end
    end
end

-- ============================================================================
-- 初始化公司
-- ============================================================================
function GD.HasOperatingCompanyInCity(city)
    if not city or city == "" then return false, nil end
    GD.CaptureActiveCompanyState()
    GD.EnsureCompanyPortfolio(true)
    for _, record in ipairs(GD.companyPortfolio.companies or {}) do
        normalizeCompanyRecord(record)
        if record.city == city and record.status == "operating" and (record.founderRatio or 0) >= 0.50 then
            return true, record
        end
    end
    return false, nil
end

function GD.InitCompany(name, nature, founderTrait, capital, city)
    local cityOccupied, existingCompany = GD.HasOperatingCompanyInCity(city)
    if cityOccupied then
        local existingName = existingCompany and existingCompany.name or "已有公司"
        GD.AddEvent(city .. "已有正在经营的地产公司“" .. existingName .. "”，每个城市最多成立一家", "warning")
        return false, "每个城市最多成立一家地产公司"
    end

    capital = math.max(1, math.floor(tonumber(capital) or 0))
    if not GD.player then
        GD.player = PS.InitPlayerData(capital)
    end
    PS.EnsurePlayerFields(GD.player)
    GD.EnsurePersonalCityOperations()
    local groupPaysCapital = GS.IsActive(GD)
    if groupPaysCapital then
        if (GD.group.cash or 0) < capital then
            GD.AddEvent("集团现金不足，无法出资注册资本" .. GD.FormatMoney(capital), "danger")
            return false, "集团现金不足"
        end
        GD.group.cash = GD.group.cash - capital
    else
        if GD.player.cash < capital then
            GD.AddEvent("个人现金不足，无法注入注册资本" .. GD.FormatMoney(capital), "danger")
            return false, "个人现金不足"
        end
        GD.player.cash = GD.player.cash - capital
    end
    if GD.company and (GD.company.name or "") ~= "" then
        GD.PrepareRuntimeForNewCompany()
    end

    local c = GD.company
    c.name = name
    c.nature = nature or "private"
    c.founderTrait = founderTrait or "balanced"
    c.registeredCapital = capital
    c.cash = capital
    c.city = city
    c.totalAssets = capital
    c.dividendRate = 0  -- 初始0%，后续被股权预设的分红率覆盖

    -- 应用创始人特质效果
    GD.ApplyTraitEffects(c.founderTrait)

    -- 设置城市层级
    for _, ct in ipairs(GD.cities) do
        if ct.name == city then
            c.cityTier = ct.tier
            break
        end
    end

    GD.gameStarted = true
    GD.paused = false
    local natureName = c.natureNames[c.nature] or "有限责任公司"
    local traitName = c.founderTraitNames[c.founderTrait] or "均衡型"
    GD.AddEvent(c.name .. "(" .. natureName .. ") 正式成立！注册资本 " .. GD.FormatMoney(capital), "success")
    GD.AddEvent("创始人特质: " .. traitName, "info")

    -- 个人财务已在注册资本扣款前初始化；后续重新创业保留个人现金、家庭、投资等资产
    PS.EnsurePlayerFields(GD.player)
    -- 初始化公司治理（股权预设）。集团出资的新公司统一由集团全资持有，
    -- 避免集团支付全部注册资本却把初始股份无偿分给个人或外部股东。
    local equityPreset = groupPaysCapital and "sole" or (GD._pendingEquityPreset or "sole")
    c.governance = GV.InitGovernanceData(equityPreset, capital, GD.player and GD.player.founderName)
    c.dividendRate = c.governance.dividendPolicy.rate
    GD._pendingEquityPreset = nil
    local presetDef = GV.EQUITY_PRESETS[equityPreset]
    GD.AddEvent("股权结构: " .. presetDef.name .. " (创始人持股" .. math.floor(c.governance.founderRatio * 100) .. "%，分红" .. math.floor(c.dividendRate * 100) .. "%)", "info")

    -- 初始化股票市场
    SM.Init(GD)

    -- 初始化共享土地市场与首批供地计划；新公司不再复制或重新生成一整套市场。
    if not GD.landSupplyPlans or next(GD.landSupplyPlans) == nil then
        GD.AdvanceLandSupplyPlans()
    end
    local newRecord = GD.CaptureActiveCompanyState("operating")
    if groupPaysCapital and newRecord then
        local grouped, groupMessage = GS.RegisterNewCompany(GD, newRecord.id)
        if not grouped then
            print("[GROUP] 新公司纳入集团失败: " .. tostring(groupMessage))
        else
            GD.AddEvent(c.name .. "由" .. (GD.group.name or "集团") .. "出资并纳入全资控股", "success")
        end
    end
    return true
end

-- ============================================================================
-- 应用创始人特质效果
-- ============================================================================
function GD.ApplyTraitEffects(trait)
    local te = GD.company.traitEffects
    -- 重置
    te.buildSpeedBonus = 0
    te.qualityRisk = 0
    te.buildCostBonus = 0
    te.brandPremium = 0
    te.financeCostBonus = 0
    te.debtRisk = 0
    te.permitSpeedBonus = 0
    te.complianceRisk = 0

    if trait == "fast_turn" then
        te.buildSpeedBonus = 0.15    -- 建设速度+15%
        te.qualityRisk = 0.20       -- 质量风险+20%
    elseif trait == "quality" then
        te.buildCostBonus = 0.10     -- 建安成本+10%
        te.brandPremium = 0.25       -- 创始人品质特质溢价+25%（叠加品牌系统溢价）
    elseif trait == "capital" then
        te.financeCostBonus = -0.02  -- 融资成本-2%
        te.debtRisk = 0.15           -- 债务风险+15%
    elseif trait == "government" then
        te.permitSpeedBonus = 0.30   -- 报建速度+30%
        te.complianceRisk = 0.10     -- 合规风险+10%
    end
    -- balanced: 全部为0
end

-- ============================================================================
-- 设立总部部门
-- ============================================================================
function GD.EstablishDepartment(deptId)
    local c = GD.company
    local def = GD.DEPT_DEFS[deptId]
    if not def then return false, "未找到该部门" end

    for _, dept in ipairs(c.hqDepartments) do
        if dept.id == deptId then
            if dept.established then return false, "该部门已设立" end
            -- 扣除设立费用
            if c.cash < def.setupCost then
                return false, "现金不足，需要" .. def.setupCost .. "万元"
            end
            c.cash = c.cash - def.setupCost
            dept.established = true
            dept.headcount = 0
            dept.monthCost = def.monthCost
            dept.staff = dept.staff or {}
            GD.AddEvent("总部【" .. dept.name .. "】正式设立 (花费" .. def.setupCost .. "万)", "success")
            return true
        end
    end
    return false, "未找到该部门"
end

-- ============================================================================
-- 部门招聘人员
-- ============================================================================
function GD.HireDeptStaff(deptId, roleIndex)
    local c = GD.company
    local def = GD.DEPT_DEFS[deptId]
    if not def then return false, "未找到该部门定义" end

    local dept = nil
    for _, d in ipairs(c.hqDepartments) do
        if d.id == deptId then dept = d; break end
    end
    if not dept then return false, "未找到该部门" end
    if not dept.established then return false, "该部门尚未设立" end

    local role = def.roles[roleIndex]
    if not role then return false, "无效的岗位" end

    -- 检查是否已招满（每个岗位最多1人）
    dept.staff = dept.staff or {}
    for _, s in ipairs(dept.staff) do
        if s.roleIndex == roleIndex then
            return false, "该岗位已有人员"
        end
    end

    -- 随机生成薪资
    local salary = math.random(role.salaryMin, role.salaryMax)
    salary = math.floor(salary / 100) * 100

    local staffMember = {
        name = role.title .. string.format("%02d", math.random(10, 99)),
        title = role.title,
        roleIndex = roleIndex,
        salary = salary,       -- 元/月
        ability = role.ability,
    }
    table.insert(dept.staff, staffMember)
    dept.headcount = #dept.staff

    GD.AddEvent("【" .. dept.name .. "】招聘 " .. staffMember.name .. " (" .. salary .. "元/月)", "info")
    return true
end

-- ============================================================================
-- 部门辞退人员
-- ============================================================================
function GD.FireDeptStaff(deptId, staffIndex)
    local c = GD.company
    for _, dept in ipairs(c.hqDepartments) do
        if dept.id == deptId then
            dept.staff = dept.staff or {}
            if staffIndex < 1 or staffIndex > #dept.staff then
                return false, "无效的人员索引"
            end
            local fired = table.remove(dept.staff, staffIndex)
            dept.headcount = #dept.staff
            GD.AddEvent("【" .. dept.name .. "】" .. fired.name .. " 离职", "warning")
            return true
        end
    end
    return false, "未找到该部门"
end

-- ============================================================================
-- 获取全部部门员工总薪资（万元/月）
-- ============================================================================
function GD.GetTotalDeptSalary()
    local totalYuan = 0
    for _, dept in ipairs(GD.company.hqDepartments) do
        if dept.established and dept.staff then
            for _, s in ipairs(dept.staff) do
                totalYuan = totalYuan + s.salary
            end
        end
    end
    return totalYuan / 10000  -- 转万元
end

-- ============================================================================
-- 获取部门总人数
-- ============================================================================
function GD.GetTotalDeptStaff()
    local total = 0
    for _, dept in ipairs(GD.company.hqDepartments) do
        if dept.established and dept.staff then
            total = total + #dept.staff
        end
    end
    return total
end

-- ============================================================================
-- 6.1 成本科目初始化
-- ============================================================================
function GD.InitCostSubjects(project)
    local detail = {}
    local c = project.cost
    -- 土地获取
    detail["land_price"]    = c.landCost * 0.95
    detail["land_tax"]      = c.landCost * 0.03
    detail["land_other"]    = c.landCost * 0.02
    -- 前期费用
    detail["prec_design"]   = c.designCost
    detail["prec_survey"]   = c.designCost * 0.10
    detail["prec_permit"]   = c.designCost * 0.15
    detail["prec_dd"]       = c.ddCost or 0
    -- 建安成本
    detail["con_civil"]     = c.buildCost * 0.50
    detail["con_install"]   = c.buildCost * 0.25
    detail["con_decor"]     = c.buildCost * 0.10
    detail["con_landscape"] = c.buildCost * 0.08
    -- 基础设施
    detail["inf_road"]      = c.buildCost * 0.04
    detail["inf_power"]     = c.buildCost * 0.02
    detail["inf_green"]     = c.buildCost * 0.01
    -- 配套/间接/财务/税费(预估)
    detail["aux_community"] = c.buildCost * 0.02
    detail["aux_comm"]      = c.buildCost * 0.01
    detail["aux_parking"]   = c.buildCost * 0.01
    detail["ind_manage"]    = c.buildCost * 0.02
    detail["ind_market"]    = c.marketingCost or 0
    detail["ind_consult"]   = c.designCost * 0.05
    detail["fin_interest"]  = c.financeCost or 0
    detail["fin_guarantee"] = 0
    detail["tax_vat"]       = c.taxCost * 0.50
    detail["tax_surcharge"] = c.taxCost * 0.15
    detail["tax_land_vat"]  = c.taxCost * 0.35
    c.subjectDetail = detail
end

-- ============================================================================
-- 6.2 动态成本更新 (每月调用)
-- ============================================================================
function GD.UpdateDynamicCost(project)
    local c = project.cost
    local spent = c.totalCost
    local totalMo = math.max(1, project.construction.totalMonths)
    local elapsed = project.construction.monthsElapsed or 0
    local remainMonths = math.max(1, totalMo - elapsed)
    local monthlyRate = c.buildCost / totalMo
    local forecast = spent + monthlyRate * remainMonths
    c.dynamicCost = forecast

    c.budgetPrecision = GD.COST_PRECISION_BY_PHASE[project.status] or 0.05

    -- 三色预警
    local ratio = c.targetCost > 0 and (c.dynamicCost / c.targetCost) or 0
    c.alertLevel = "green"
    for _, t in ipairs(GD.COST_ALERT_THRESHOLDS) do
        if ratio >= t.ratio then
            c.alertLevel = t.level
        end
    end

    -- 成本部加成: 波动降低30%
    for _, dept in ipairs(GD.company.hqDepartments or {}) do
        if dept.id == "cost" and dept.established then
            local fluctuation = c.dynamicCost - c.targetCost
            if fluctuation > 0 then
                c.dynamicCost = c.targetCost + fluctuation * 0.70
            end
            break
        end
    end
end

-- ============================================================================
-- 6.2 获取成本预警信息 (UI用)
-- ============================================================================
function GD.GetCostAlertInfo(project)
    local c = project.cost
    local ratio = c.targetCost > 0 and ((c.dynamicCost or c.totalCost) / c.targetCost) or 0
    local pct = math.floor(ratio * 100)
    for i = #GD.COST_ALERT_THRESHOLDS, 1, -1 do
        local t = GD.COST_ALERT_THRESHOLDS[i]
        if ratio >= t.ratio then
            return {
                level = t.level, label = t.label, color = t.color,
                ratio = ratio, pct = pct,
                overrun = (c.dynamicCost or 0) - c.targetCost,
            }
        end
    end
    return {level="green", label="安全", color="Success", ratio=ratio, pct=pct, overrun=0}
end

-- ============================================================================
-- 6.3 初始化招采包 (进入施工阶段时调用)
-- ============================================================================
function GD.InitProcurementPackages(project)
    if #project.procurement.packages > 0 then return end
    for _, cat in ipairs(GD.PROCUREMENT_CATEGORIES) do
        local baseAmount = (project.cost.subjectDetail or {})[cat.subject] or 0
        table.insert(project.procurement.packages, {
            catId      = cat.id,
            catName    = cat.name,
            mode       = cat.defaultMode,
            status     = "pending",    -- pending / bidding / done
            baseAmount = baseAmount,
            contractors = {},
            selectedIdx = nil,
            savingRate  = 0,
            biddingMonthsLeft = 0,
            marketRefPrice = baseAmount,
        })
    end
end

-- ============================================================================
-- 6.3 发起招采
-- ============================================================================
function GD.StartProcurement(project, packageIdx)
    local pkg = project.procurement.packages[packageIdx]
    if not pkg or pkg.status ~= "pending" then
        return false, "无法发起招采"
    end
    local modeInfo = GD.PROCUREMENT_MODES[pkg.mode]
    if not modeInfo then return false, "无效招采模式" end

    pkg.status = "bidding"
    pkg.biddingMonthsLeft = modeInfo.durationMonths

    local numBidders = modeInfo.minBidders + math.random(0, 2)
    pkg.contractors = {}
    for i = 1, numBidders do
        local name = pkg.catName .. "供应商" .. string.char(64 + i)
        local deviation = (math.random() - 0.5) * 0.40
        local bidAmount = math.floor(pkg.marketRefPrice * (1 + deviation))
        -- 6.4 黑名单检查
        local blacklisted = false
        for _, bl in ipairs(GD.company.contractorBlacklist or {}) do
            if bl.name == name then blacklisted = true; break end
        end
        table.insert(pkg.contractors, {
            name = name,
            bidAmount = bidAmount,
            isBlacklisted = blacklisted,
        })
    end

    GD.AddEvent("【" .. project.name .. "】" .. pkg.catName .. "招采已启动(" .. modeInfo.name .. ")", "info")
    return true
end

-- ============================================================================
-- 6.3 选定中标方 & 完成招采
-- ============================================================================
function GD.CompleteProcurement(project, packageIdx, contractorIdx)
    local pkg = project.procurement.packages[packageIdx]
    if not pkg or pkg.status ~= "bidding" then
        return false, "招采状态异常"
    end
    local chosen = pkg.contractors[contractorIdx]
    if not chosen then return false, "无效供应商" end
    if chosen.isBlacklisted then return false, "该供应商已被列入黑名单" end

    -- 6.5 不平衡报价检测
    local deviation = math.abs(chosen.bidAmount - pkg.marketRefPrice) / math.max(1, pkg.marketRefPrice)
    local unbalancedWarning = nil
    if deviation > GD.UNBALANCED_BID_THRESHOLD then
        unbalancedWarning = string.format("偏离市场价%.0f%%", deviation * 100)
    end

    pkg.status = "done"
    pkg.selectedIdx = contractorIdx
    pkg.savingRate = 1 - (chosen.bidAmount / math.max(1, pkg.baseAmount))

    -- 更新科目明细
    for _, cat in ipairs(GD.PROCUREMENT_CATEGORIES) do
        if cat.id == pkg.catId then
            project.cost.subjectDetail[cat.subject] = chosen.bidAmount
            break
        end
    end

    -- 记录招采历史
    table.insert(project.procurement.history, {
        catId = pkg.catId, contractorName = chosen.name,
        amount = chosen.bidAmount, month = GD.month, year = GD.year,
    })

    local msg = "【" .. project.name .. "】" .. pkg.catName .. " 中标方: " .. chosen.name
    if unbalancedWarning then
        msg = msg .. " [不平衡报价: " .. unbalancedWarning .. "]"
    end
    GD.AddEvent(msg, unbalancedWarning and "warning" or "success")
    return true, unbalancedWarning
end

-- ============================================================================
-- 6.3 招采月度推进 (MonthlyTick驱动)
-- ============================================================================
function GD.UpdateProcurementTick(project)
    for pkgIdx, pkg in ipairs(project.procurement.packages) do
        if pkg.status == "bidding" then
            pkg.biddingMonthsLeft = pkg.biddingMonthsLeft - 1
            if pkg.biddingMonthsLeft <= 0 then
                -- 自动选择最低价(非黑名单)
                local bestIdx, bestAmt = nil, math.huge
                for i, c in ipairs(pkg.contractors) do
                    if not c.isBlacklisted and c.bidAmount < bestAmt then
                        bestIdx = i; bestAmt = c.bidAmount
                    end
                end
                if bestIdx then
                    GD.CompleteProcurement(project, pkgIdx, bestIdx)
                end
            end
        end
    end
end

-- ============================================================================
-- 6.4 供应商黑名单管理
-- ============================================================================
function GD.AddToBlacklist(name, reason)
    local bl = GD.company.contractorBlacklist
    for _, entry in ipairs(bl) do
        if entry.name == name then return false, "该供应商已在黑名单中" end
    end
    table.insert(bl, {
        name = name, reason = reason or "质量/履约问题",
        addedMonth = GD.month, addedYear = GD.year,
    })
    GD.AddEvent("供应商【" .. name .. "】加入黑名单: " .. (reason or ""), "warning")
    return true
end

function GD.RemoveFromBlacklist(name)
    local bl = GD.company.contractorBlacklist
    for i, entry in ipairs(bl) do
        if entry.name == name then
            table.remove(bl, i)
            GD.AddEvent("供应商【" .. name .. "】已移出黑名单", "info")
            return true
        end
    end
    return false, "未找到该供应商"
end

-- ============================================================================
-- 创建区域/城市公司
-- ============================================================================
function GD.CreateRegionalCompany(name, cityName)
    local c = GD.company
    -- 检查是否已有该城市的区域公司
    for _, rc in ipairs(c.regionalCompanies) do
        if rc.city == cityName then
            return false, "该城市已有区域公司"
        end
    end
    local rc = {
        name = name,
        city = cityName,
        pnl = 0,           -- 独立损益(万元)
        projects = {},      -- 关联项目ID列表
        employees = {},     -- 区域员工
        established = GD.totalMonths,
        maxProjects = 2,   -- 该区域公司可管辖项目上限
    }
    table.insert(c.regionalCompanies, rc)
    GD.AddEvent("区域公司【" .. name .. "】(" .. cityName .. ")成立", "success")
    return true
end

-- ============================================================================
-- 招聘关键岗位
-- ============================================================================
function GD.HireKeyPosition(posType, name)
    local c = GD.company
    -- 岗位类型定义
    local posConfigs = {
        project_director  = {title="项目总",   baseSalary=80,  dept="invest"},
        design_director   = {title="设计总监", baseSalary=60,  dept="design"},
        cost_director     = {title="成本总监", baseSalary=55,  dept="cost"},
        marketing_director= {title="营销总监", baseSalary=65,  dept="marketing"},
        finance_director  = {title="财务总监", baseSalary=60,  dept="finance"},
    }
    local cfg = posConfigs[posType]
    if not cfg then return false, "无效的岗位类型" end

    -- 生成属性(1-100)
    local person = {
        id = "KP" .. (#c.keyPositions + 1),
        type = posType,
        title = cfg.title,
        name = name or (cfg.title .. (#c.keyPositions + 1)),
        dept = cfg.dept,
        -- 四维属性
        ability = math.random(40, 85),       -- 专业能力
        connections = math.random(20, 70),    -- 人脉资源
        integrity = math.random(50, 95),      -- 廉洁度
        loyalty = math.random(40, 80),        -- 忠诚度
        -- 薪酬激励
        salary = cfg.baseSalary,              -- 年薪(万元)
        coinvestRate = 0,                     -- 项目跟投比例(0-0.10, 超过5%触发道德风险)
        optionShares = 0,                     -- 期权份额
        -- 状态
        morale = 80,
        hireMonth = GD.totalMonths,
        assignedProjectId = nil,    -- 当前指派的项目ID（仅project_director有效）
    }
    table.insert(c.keyPositions, person)
    GD.AddEvent("招聘关键高管【" .. person.name .. "】担任" .. person.title .. "，年薪" .. person.salary .. "万", "success")
    return true, person
end

-- ============================================================================
-- 设置跟投比例(关键岗位激励)
-- ============================================================================
function GD.SetCoinvestRate(personId, rate)
    local c = GD.company
    for _, kp in ipairs(c.keyPositions) do
        if kp.id == personId then
            rate = math.max(0, math.min(0.10, rate))
            kp.coinvestRate = rate
            if rate > 0.05 then
                GD.AddEvent("警告: " .. kp.name .. "跟投比例" .. math.floor(rate*100) .. "%过高，道德风险上升", "warning")
            end
            return true
        end
    end
    return false, "未找到该高管"
end

-- ============================================================================
-- Tick入口(由main.lua HandleUpdate调用)
-- ============================================================================
function GD.Tick(dt)
    if not GD.gameStarted or GD.paused then return nil end
    if GD.HasActiveOperatingCompany and not GD.HasActiveOperatingCompany() then return nil end

    GD.timeAccum = GD.timeAccum + dt * GD.gameSpeed
    -- 防止从后台恢复时 dt 累积过大，限制最多追赶1天
    if GD.timeAccum > GD.DAY_DURATION * 2 then
        GD.timeAccum = GD.DAY_DURATION  -- 截断，避免连续多帧追赶
    end
    if GD.timeAccum >= GD.DAY_DURATION then
        GD.timeAccum = GD.timeAccum - GD.DAY_DURATION
        return GD.DailyTick()  -- returns "day" or "month"
    end
    return nil
end

-- ============================================================================
-- 每日Tick
-- ============================================================================
function GD.DailyTick()
    -- 游戏已结束，不再推进
    if GD.company.isGameOver then
        return "gameover"
    end
    local daysInMonth = GD.GetDaysInMonth(GD.month, GD.year)
    if GD.day >= daysInMonth
        and GV.HasPendingCeoReports
        and GV.HasPendingCeoReports(GD)
    then
        GV.ReopenPendingCeoReports(GD)
        GD.paused = true
        return "ceo_pending"
    end
    GD.day = GD.day + 1
    GD.totalDays = GD.totalDays + 1
    if GD.day > daysInMonth then
        GD.day = 1
        GD.MonthlyTick()  -- 月度结算(已含月/年进位)
        -- MonthlyTick可能触发游戏结束
        if GD.company.isGameOver then
            return "gameover"
        end
        return "month"
    end
    return "day"
end

-- ============================================================================
-- 存档 (File API + cjson)
-- ============================================================================
local SAVE_DIR = "saves"
local SAVE_VERSION = 5  -- v5: JSON格式存档
GD.MANUAL_SAVE_SLOT_COUNT = 8

local function buildSaveData()
    GD.EnsurePersonalCityOperations()
    GD.CaptureActiveCompanyState()
    GD.EnsureCompanyPortfolio(true)

    local data = {
        version = SAVE_VERSION,
        savedAt = os.date("%Y-%m-%d %H:%M:%S"),
        year = GD.year, month = GD.month, day = GD.day,
        totalMonths = GD.totalMonths, totalDays = GD.totalDays,
        gameSpeed = GD.gameSpeed,
        gameStarted = GD.gameStarted,
        company = GD.company,
        companyPortfolio = GD.companyPortfolio,
        activeCompanyId = GD.activeCompanyId,
        group = GD.group,
        international = GD.international,
        player = GD.player,
        economy = GD.economy,
        macro = GD.macro,
        policy = GD.policy,
        activeBlackSwans = GD.activeBlackSwans,
        projects = GD.projects,
        loans = GD.loans,
        finance = GD.finance,
        brand = GD.brand,
        landMarket = GD.landMarket,
        landReserve = GD.landReserve,
        landSupplyPlans = GD.landSupplyPlans,
        landSupplyCommitments = GD.landSupplyCommitments,
        landSupplyAnnual = GD.landSupplyAnnual,
        competitors = GD.competitors,
        equityInvestments = GD.equityInvestments,
        compLoans = GD._compLoans,
        fixedAssets = GD.fixedAssets,
        assetListings = GD.assetListings,
        rentalListings = GD.rentalListings,
        assetMarket = GD.assetMarket,
        stockMarket = GD.stockMarket,
        beginnerGiftClaimed = GD.beginnerGiftClaimed,
        adRewardCount = GD.adRewardCount,
        adRewardDayCount = GD.adRewardDayCount,
        adRewardLastDay = GD.adRewardLastDay,
        redeemedCodes = GD.redeemedCodes,
        musicVolume = GD.musicVolume,
        events = {},
    }
    for i = 1, math.min(20, #GD.events) do
        data.events[i] = GD.events[i]
    end
    return data
end

local function writeTextFile(path, text)
    local f = File(path, FILE_WRITE)
    if not f:IsOpen() then error("无法打开文件: " .. path) end
    f:WriteString(text)
    f:Close()
end

local function readTextFile(path)
    local f = File(path, FILE_READ)
    if not f:IsOpen() then error("cannot open") end
    local str = f:ReadString()
    f:Close()
    return str
end

local function writeSaveFileSafely(path, jsonStr)
    fileSystem:CreateDir(SAVE_DIR)
    local tmpPath = path .. ".tmp"
    local bakPath = path .. ".bak"
    writeTextFile(tmpPath, jsonStr)
    if fileSystem:FileExists(path) then
        pcall(function()
            fileSystem:Delete(bakPath)
            fileSystem:Copy(path, bakPath)
        end)
    end
    if fileSystem:FileExists(path) then fileSystem:Delete(path) end
    local renamed = fileSystem:Rename(tmpPath, path)
    if not renamed and fileSystem:FileExists(tmpPath) then
        fileSystem:Copy(tmpPath, path)
        fileSystem:Delete(tmpPath)
    end
end

local function decodeSaveFileWithBackup(path)
    local function tryPath(p)
        if not fileSystem:FileExists(p) then return nil, "存档不存在" end
        local okRead, str = pcall(readTextFile, p)
        if not okRead or not str or str == "" then return nil, "存档读取失败" end
        local okDecode, data = pcall(cjson.decode, str)
        if not okDecode or type(data) ~= "table" then return nil, "存档数据损坏" end
        return data, nil
    end

    local data, err = tryPath(path)
    if data then return data, nil, path end
    local backupData, backupErr = tryPath(path .. ".bak")
    if backupData then return backupData, nil, path .. ".bak" end
    return nil, err or backupErr or "存档数据损坏", path
end

function GD.SaveToSlot(slot)
    -- 存档前只做安全裁剪和增量GC，避免全量GC造成长时间卡顿。
    GD.PerformDataCleanup()
    collectgarbage("step", 80)

    local data = buildSaveData()

    local ok, err = pcall(function()
        local jsonStr = cjson.encode(data)
        writeSaveFileSafely(SAVE_DIR .. "/slot_" .. slot .. ".json", jsonStr)
    end)
    if ok then
        GD.AddEvent("游戏已保存到存档位" .. slot, "success")
        return true
    else
        GD.AddEvent("保存失败: " .. tostring(err), "danger")
        return false
    end
end

-- ============================================================================
-- 读档 (支持 v5 JSON 和旧版 Lua 格式向后兼容)
-- ============================================================================
function GD.LoadFromSlot(slot)
    -- 优先读取新格式 JSON
    local savePath = SAVE_DIR .. "/slot_" .. slot .. ".json"
    local data, loadErr, loadedPath = decodeSaveFileWithBackup(savePath)
    if not data then return false, loadErr or "存档数据损坏" end
    if loadedPath ~= savePath then
        GD.AddEvent("主存档损坏，已从备份恢复", "warning")
    end

    -- 恢复状态
    GD.year = data.year or 2001
    GD.month = data.month or 1
    GD.day = data.day or 1
    GD.totalMonths = data.totalMonths or 0
    GD.totalDays = data.totalDays or 0
    GD.gameSpeed = data.gameSpeed or 1
    GD.paused = false
    GD.gameStarted = data.gameStarted ~= false
    GD.timeAccum = 0
    GD.companyPortfolio = data.companyPortfolio or {nextId = 1, activeId = data.activeCompanyId, companies = {}}
    GD.activeCompanyId = data.activeCompanyId or GD.companyPortfolio.activeId
    GD.group = data.group or GS.CreateDefaultData()
    GS.EnsureFields(GD)
    GD.international = data.international or INS.CreateDefaultData()
    INS.EnsureFields(GD)

    if data.company then
        for k, v in pairs(data.company) do GD.company[k] = v end
    end
    -- 向后兼容: 旧存档公司数据补充新字段
    local cc = GD.company
    if not cc.nature then cc.nature = "private" end
    if not cc.natureNames then cc.natureNames = {llc="有限责任公司", joint_stock="股份制企业", private="民营", foreign="外资", joint_venture="合资"} end
    -- 确保新企业类型存在于 natureNames 中（向后兼容）
    if not cc.natureNames.llc then cc.natureNames.llc = "有限责任公司" end
    if not cc.natureNames.joint_stock then cc.natureNames.joint_stock = "股份制企业" end
    if not cc.founderTrait then cc.founderTrait = "balanced" end
    if not cc.founderTraitNames then
        cc.founderTraitNames = {fast_turn="高周转派", quality="品质坚守者", capital="资本运作高手", government="政府关系型", balanced="均衡型"}
    end
    if not cc.traitEffects then
        cc.traitEffects = {buildSpeedBonus=0, qualityRisk=0, buildCostBonus=0, brandPremium=0, financeCostBonus=0, debtRisk=0, permitSpeedBonus=0, complianceRisk=0}
        GD.ApplyTraitEffects(cc.founderTrait)
    end
    if not cc.hqDepartments then
        cc.hqDepartments = {
            {id="invest",name="投资发展部",established=false,headcount=0,monthCost=0,staff={}},
            {id="design",name="设计管理部",established=false,headcount=0,monthCost=0,staff={}},
            {id="cost",name="成本招采部",established=false,headcount=0,monthCost=0,staff={}},
            {id="engineer",name="工程管理部",established=false,headcount=0,monthCost=0,staff={}},
            {id="marketing",name="营销策划部",established=false,headcount=0,monthCost=0,staff={}},
            {id="finance",name="财务融资部",established=false,headcount=0,monthCost=0,staff={}},
            {id="legal",name="法务合规部",established=false,headcount=0,monthCost=0,staff={}},
            {id="hr",name="人力行政部",established=false,headcount=0,monthCost=0,staff={}},
            {id="audit",name="审计监察部",established=false,headcount=0,monthCost=0,staff={}},
        }
    else
        -- 旧存档兼容：确保每个部门有 staff 字段
        for _, dept in ipairs(cc.hqDepartments) do
            if not dept.staff then dept.staff = {} end
            dept.headcount = #dept.staff
        end
    end
    if not cc.contractorBlacklist then cc.contractorBlacklist = {} end
    if not cc.regionalCompanies then cc.regionalCompanies = {} end
    if not cc.keyPositions then cc.keyPositions = {} end
    -- 旧存档type字段迁移
    if cc.type then
        if cc.type == "joint_stock" then cc.dividendRate = cc.dividendRate or 0.20 end
        cc.type = nil
    end
    -- cc.dividendRate == 0 是合法值（初始分红率为0%），不再强制覆盖

    if data.economy then
        for k, v in pairs(data.economy) do GD.economy[k] = v end
    end

    -- 宏观经济指标(2.1)恢复/向后兼容
    if data.macro then
        local defaults = ME.CreateMacro()
        for k, v in pairs(defaults) do
            if data.macro[k] == nil then data.macro[k] = v end
        end
        GD.macro = data.macro
    else
        GD.macro = ME.CreateMacro()
    end

    -- 政策周期(2.2)恢复/向后兼容
    if data.policy then
        local defaults = ME.CreatePolicy()
        -- 逐子表合并，确保新增字段有默认值
        for section, defs in pairs(defaults) do
            if type(defs) == "table" then
                if not data.policy[section] then
                    data.policy[section] = defs
                else
                    for k, v in pairs(defs) do
                        if data.policy[section][k] == nil then
                            data.policy[section][k] = v
                        end
                    end
                end
            end
        end
        GD.policy = data.policy
    else
        GD.policy = ME.CreatePolicy()
    end

    -- 活跃黑天鹅事件恢复
    GD.activeBlackSwans = data.activeBlackSwans or {}

    GD.projects = data.projects or {}
    -- 向后兼容: 旧存档项目补充unitPlan和assets字段
    for _, p in ipairs(GD.projects) do
        if not p.unitPlan then
            p.unitPlan = {
                planned = true,       -- 旧存档视为已规划(全部销售)
                sellUnits = p.sales.totalUnits,
                holdUnits = 0,
                sellArea = p.sales.totalArea,
                holdArea = 0,
                minHoldRatio = 0,
            }
        end
        if not p.assets then
            p.assets = {
                rentable = false,
                monthlyRentPricePerSqm = 0,
                occupancyRate = 0,
                monthlyRentIncome = 0,
                totalRentIncome = 0,
            }
        end
        -- 向后兼容: 旧存档补充设计管理字段
        local dd = p.design
        if not dd then
            dd = {positioning="", style="", phase="done", phaseProgress=100,
                planning={confirmed=true, far=p.land.far or 2.0, density=p.land.density or 0.28,
                    greenRate=p.land.greenRate or 0.30, heightLimit=p.land.heightLimit or 100,
                    facilities={kindergarten=false, communityRoom=false, affordable=0}},
                scheme={confirmed=true, layout="row", unitMix={{key="basic",ratio=60},{key="improved",ratio=40}},
                    efficiency=0.72, schemeScore=70},
                costCap={confirmed=true, steelPerSqm=45, concretePerSqm=0.4, optimizations={}, overrun=false, penalty=0},
                review={currentStage=0, stages={}, reworkCost=0},
            }
            p.design = dd
        else
            -- 部分字段可能缺失
            if not dd.planning then
                dd.planning = {confirmed=true, far=p.land.far or 2.0, density=0.28, greenRate=0.30,
                    heightLimit=100, facilities={kindergarten=false, communityRoom=false, affordable=0}}
            end
            if not dd.scheme then
                dd.scheme = {confirmed=false, layout="", unitMix={}, efficiency=0, schemeScore=0}
            end
            if not dd.costCap then
                dd.costCap = {confirmed=false, steelPerSqm=45, concretePerSqm=0.4, optimizations={}, overrun=false, penalty=0}
            end
            if not dd.review then
                dd.review = {currentStage=0, stages={}, reworkCost=0}
            end
            -- 旧 phase 值 "construction" → "construction_drawing"
            if dd.phase == "construction" then dd.phase = "construction_drawing" end
        end
        -- 向后兼容: 旧存档补充成本科目与招采字段
        local co = p.cost
        co.permitCost = co.permitCost or 0
        if not co.subjectDetail or next(co.subjectDetail) == nil then
            co.subjectDetail = co.subjectDetail or {}
            co.dynamicCost = co.dynamicCost or co.targetCost or 0
            co.budgetPrecision = co.budgetPrecision or (GD.COST_PRECISION_BY_PHASE[p.status] or 0.30)
            co.alertLevel = co.alertLevel or "green"
            co.ddCost = co.ddCost or 0
            co.riskCost = co.riskCost or 0
            co.permitCost = co.permitCost or 0
            GD.InitCostSubjects(p)
        end
        if not p.procurement then
            p.procurement = {packages = {}, history = {}}
            if p.status == "construction" or p.status == "presale" or p.status == "delivery" then
                GD.InitProcurementPackages(p)
            end
        end
        -- 向后兼容: 旧存档补充工程管理字段(7.1~7.5)
        CS.EnsureConstructionFields(p.construction)
        -- 向后兼容: 旧存档补充营销字段(8.1~8.5)
        MK.EnsureMarketingFields(p.sales)
        if p.sales then
            local approvedOpeningPrice = tonumber(p.sales.approvedOpeningPrice) or 0
            local currentPrice = tonumber(p.sales.basePrice) or 0
            if approvedOpeningPrice <= 0 and currentPrice > 0 then
                p.sales.approvedOpeningPrice = currentPrice
            end
            if (p.sales.packageBasePrice or 0) <= 0 then
                if (p.sales.approvedOpeningPrice or 0) > 0 then
                    p.sales.packageBasePrice = p.sales.approvedOpeningPrice
                elseif (p.sales.basePrice or 0) > 0 then
                    p.sales.packageBasePrice = p.sales.basePrice
                else
                    p.sales.packageBasePrice = 0
                end
            end
        end
        -- 向后兼容: 旧存档补充多项目并行字段
        PC.EnsureProjectFields(p)
        GD.EnsurePreconstructionFields(p)
        -- 向后兼容: 旧存档补充开发类型字段
        if not p.devTypeId then
            p.devTypeId = "rigid_residential"
            p.devCategory = "sale"
        end
        -- 向后兼容: 旧存档补充物业管理字段（按开发类型设置默认物业费）
        if not p.propertyMgmt then
            p.propertyMgmt = {
                enabled = false, feePerSqm = GD.GetDefaultPropertyFee(p.devTypeId), collectionRate = 0,
                monthlyIncome = 0, totalIncome = 0, serviceLevelIdx = 1,
                satisfactionRate = 80, monthlyOperateCost = 0,
                staffCount = 0,
            }
        end
        if not p.propertyMgmt.staffCount then p.propertyMgmt.staffCount = 0 end
        -- 向后兼容: 持有型运营数据
        if p.operations then
            OP.EnsureOperationsFields(p.operations)
        end
        -- 向后兼容: 代建型费用数据
        if p.agency then
            AF.EnsureAgencyFields(p.agency)
        end
    end
    -- 向后兼容: 公司组织架构多项目字段
    PC.EnsureCompanyFields(GD.company)
    PC.EnsureKeyPositionFields(GD.company)
    PC.EnsureRegionalFields(GD.company)
    GD.loans = data.loans or {}
    -- 固定资产数据恢复 + 向后兼容
    GD.fixedAssets = data.fixedAssets or {}
    for _, fa in ipairs(GD.fixedAssets) do
        GD.EnsureFixedAssetFields(fa)
    end
    -- 挂牌出售/出租数据恢复
    GD.assetListings = data.assetListings or {}
    GD.rentalListings = data.rentalListings or {}
    GD.NormalizeRentalListingsAfterLoad()
    -- 商业资产市场恢复 + 向后兼容
    if data.assetMarket then
        GD.assetMarket = data.assetMarket
    else
        GD.assetMarket = {listings = {}, lastRefreshMonth = 0, nextId = 1}
    end
    -- 金融系统数据恢复 + 向后兼容
    if data.finance then
        GD.finance = data.finance
        FN.EnsureFinanceFields(GD.finance)
    else
        GD.finance = FN.InitFinanceData()
    end
    -- 品牌系统数据恢复 + 向后兼容
    if data.brand then
        GD.brand = data.brand
        BR.EnsureBrandFields(GD.brand)
    else
        GD.brand = BR.InitBrandData()
    end
    GD.landMarket = data.landMarket or GD.landMarket or {}
    GD.landReserve = data.landReserve or GD.landReserve or {}
    GD.landSupplyPlans = data.landSupplyPlans or GD.landSupplyPlans or {}
    GD.landSupplyCommitments = data.landSupplyCommitments or GD.landSupplyCommitments or {}
    GD.landSupplyAnnual = data.landSupplyAnnual or GD.landSupplyAnnual or {}
    GD.MigrateSharedLandMarket()
    -- 向后兼容: 旧存档地块补充渠道、状态、上市时间和尽调字段
    for _, land in ipairs(GD.landMarket) do LA.EnsureLandFields(land) end
    for _, land in ipairs(GD.landReserve) do LA.EnsureLandFields(land) end
    -- 项目中的 land 引用也需补充
    for _, p in ipairs(GD.projects) do
        if p.land then LA.EnsureLandFields(p.land) end
    end
    GD.competitors = data.competitors or GD.competitors
    -- 向后兼容：旧存档竞争对手补充 tier 字段
    local defaultTiers = {"S","S","A","A","B","B","C","C","D","D"}
    for ci, comp in ipairs(GD.competitors) do
        if not comp.tier then comp.tier = defaultTiers[ci] or "C" end
    end
    GD.equityInvestments = data.equityInvestments or {}
    GD._compLoans = data.compLoans or {}
    -- 股票市场数据恢复 + 向后兼容
    if data.stockMarket then
        GD.stockMarket = data.stockMarket
        SM.SyncMarketConfig(GD)
    else
        SM.Init(GD)
    end
    -- 城市投资数据现归个人持有。先恢复个人数据，再把旧顶层/公司快照合并迁移到 player.cityOperations。
    local legacyCityOperations = {
        cityInvestData  = data.cityInvestData,
        cityBondData    = data.cityBondData,
        citySponsorData = data.citySponsorData,
        cityCreditData  = data.cityCreditData,
        cityBankData    = data.cityBankData,
        cityBOTData     = data.cityBOTData,
    }
    GD.events = data.events or {}
    GD.beginnerGiftClaimed = data.beginnerGiftClaimed or false
    GD.adRewardCount = data.adRewardCount or 0
    GD.adRewardDayCount = data.adRewardDayCount or 0
    GD.adRewardLastDay = data.adRewardLastDay or 0
    GD.redeemedCodes = data.redeemedCodes or {}
    GD.musicVolume = data.musicVolume or 0.6

    -- 向后兼容: v3→v4 个人财务与公司治理
    if data.player then
        GD.player = data.player
        PS.EnsurePlayerFields(GD.player)
    else
        GD.player = PS.InitPlayerData(GD.company.registeredCapital or 1000)
    end
    GD.MigratePersonalCityOperations(legacyCityOperations, GD.companyPortfolio)
    GD.NormalizeFictionalWorldNames()
    GD.EnsureLandMarketCityMinimum()
    GD.NormalizeProjectNames()
    -- 向后兼容：补齐迁移后的信用社和商业银行字段。
    for _, cd in pairs(GD.cityCreditData or {}) do
        cd.deposits = cd.deposits or {}
        cd.loans = cd.loans or {}
        cd.wealthFunds = cd.wealthFunds or {}
        cd.totalDeposit = cd.totalDeposit or 0
        cd.totalLoan = cd.totalLoan or 0
        cd.totalWealth = cd.totalWealth or 0
    end
    for _, bank in pairs(GD.cityBankData or {}) do
        GD.EnsureCityBankFields(bank)
    end
    if GD.company.governance then
        GV.EnsureGovernanceFields(GD.company.governance, GD.player and GD.player.founderName)
    else
        GD.company.governance = GV.InitGovernanceData("sole", GD.company.registeredCapital or 1000, GD.player and GD.player.founderName)
    end
    GD.EnsureCompanyPortfolio(true)
    GD.NormalizeLandOwnership()
    GS.NormalizeMembership(GD)
    GS.SyncAllMemberManagement(GD)
    if GD.company and (GD.company.name or "") ~= "" then
        GD.CaptureActiveCompanyState("operating")
    end

    -- 加载后：如果现金为负且非游戏结束，触发资金危机弹窗
    if GD.company.cash and GD.company.cash < 0 and not GD.company.isGameOver then
        GD._pendingCashCrisisPopup = true
        print("[CASH-CRISIS] LoadFromSlot: 存档现金为负，设置弹窗标记 cash=" .. tostring(GD.company.cash))
    end

    GD.AddEvent("成功读取存档位" .. slot, "info")
    return true
end

-- ============================================================================
-- 云存档（客户端 clientCloud；本地存档仍作为独立备份保留）
-- ============================================================================
local CLOUD_SAVE_KEY_PREFIX = "estate_sim_cloud_slot_"

local function getCloudSaveKey(slot)
    return CLOUD_SAVE_KEY_PREFIX .. tostring(slot)
end

local function isValidCloudSlot(slot)
    return type(slot) == "number"
        and slot >= 1
        and slot <= GD.MANUAL_SAVE_SLOT_COUNT
        and slot == math.floor(slot)
end

function GD.SaveToCloudSlot(slot, callback)
    if not isValidCloudSlot(slot) then
        if callback then callback(false, "无效的云存档位") end
        return false
    end
    if not clientCloud then
        if callback then callback(false, "当前平台未连接云存档") end
        return false
    end

    local okBuild, dataOrError = pcall(buildSaveData)
    if not okBuild then
        if callback then callback(false, "准备云存档失败: " .. tostring(dataOrError)) end
        return false
    end

    local function onSuccess()
        GD.AddEvent("云存档上传成功：存档位" .. slot, "success")
        if callback then callback(true) end
    end
    local function onError(code, reason)
        local message = "云存档上传失败: " .. tostring(reason or code or "未知错误")
        GD.AddEvent(message, "danger")
        if callback then callback(false, message) end
    end
    local okCall, callError = pcall(function()
        clientCloud:Set(getCloudSaveKey(slot), dataOrError, {
            ok = onSuccess,
            error = onError,
            timeout = function()
                onError("timeout", "网络请求超时")
            end,
        })
    end)
    if not okCall then
        onError("call", callError)
        return false
    end
    return true
end

function GD.GetCloudSlotInfos(callback)
    if not clientCloud then
        if callback then callback(nil, "当前平台未连接云存档") end
        return false
    end

    local request = clientCloud:BatchGet()
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
        request:Key(getCloudSaveKey(i))
    end
    local okCall, callError = pcall(function()
        request:Fetch({
            ok = function(values)
                local infos = {}
                values = values or {}
                for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
                    local data = values[getCloudSaveKey(i)]
                    if type(data) == "string" then
                        local decodedOk, decoded = pcall(cjson.decode, data)
                        data = decodedOk and decoded or nil
                    end
                    if type(data) == "table" then
                        infos[i] = {
                            name = data.company and data.company.name or "未知",
                            date = string.format("%d年%02d月%02d日", data.year or 0, data.month or 0, data.day or 0),
                            cash = data.company and data.company.cash or 0,
                            savedAt = data.savedAt or "",
                            version = data.version or 0,
                        }
                    end
                end
                if callback then callback(infos) end
            end,
            error = function(code, reason)
                if callback then callback(nil, tostring(reason or code or "云存档读取失败")) end
            end,
            timeout = function()
                if callback then callback(nil, "云存档读取超时") end
            end,
        })
    end)
    if not okCall then
        if callback then callback(nil, tostring(callError)) end
        return false
    end
    return true
end

function GD.LoadFromCloudSlot(slot, callback)
    if not isValidCloudSlot(slot) then
        if callback then callback(false, "无效的云存档位") end
        return false
    end
    if not clientCloud then
        if callback then callback(false, "当前平台未连接云存档") end
        return false
    end

    local function fail(message)
        GD.AddEvent("云存档读取失败：" .. tostring(message), "danger")
        if callback then callback(false, message) end
    end
    local okCall, callError = pcall(function()
        clientCloud:Get(getCloudSaveKey(slot), {
            ok = function(values)
                local data = values and values[getCloudSaveKey(slot)]
                if type(data) == "string" then
                    local decodedOk, decoded = pcall(cjson.decode, data)
                    data = decodedOk and decoded or nil
                end
                if type(data) ~= "table" then
                    fail("云存档不存在或数据损坏")
                    return
                end
                local okEncode, jsonOrError = pcall(cjson.encode, data)
                if not okEncode then
                    fail("云存档数据编码失败: " .. tostring(jsonOrError))
                    return
                end
                local okWrite, writeError = pcall(function()
                    writeSaveFileSafely(SAVE_DIR .. "/slot_" .. slot .. ".json", jsonOrError)
                end)
                if not okWrite then
                    fail("云存档写入本地失败: " .. tostring(writeError))
                    return
                end
                local okLoad, loadError = GD.LoadFromSlot(slot)
                if okLoad then
                    GD.AddEvent("云存档下载并读取成功：存档位" .. slot, "success")
                    if callback then callback(true) end
                else
                    fail(loadError or "云存档加载失败")
                end
            end,
            error = function(code, reason)
                fail(tostring(reason or code or "云存档读取失败"))
            end,
            timeout = function()
                fail("云存档读取超时")
            end,
        })
    end)
    if not okCall then
        fail(tostring(callError))
        return false
    end
    return true
end

-- ============================================================================
-- 获取存档摘要信息
-- ============================================================================
function GD.GetSlotInfo(slot)
    local savePath = SAVE_DIR .. "/slot_" .. slot .. ".json"
    if not fileSystem:FileExists(savePath) then return nil end

    local str
    local ok = pcall(function()
        local f = File(savePath, FILE_READ)
        if not f:IsOpen() then error("cannot open") end
        str = f:ReadString()
        f:Close()
    end)
    if not ok or not str or str == "" then return nil end

    local dok, data = pcall(cjson.decode, str)
    if not dok or type(data) ~= "table" then return nil end
    return {
        name = data.company and data.company.name or "未知",
        date = string.format("%d年%02d月%02d日", data.year or 0, data.month or 0, data.day or 0),
        cash = data.company and data.company.cash or 0,
        savedAt = data.savedAt or "",
        version = data.version or 0,
    }
end

-- ============================================================================
-- 获取最新存档信息(用于继续游戏)
-- ============================================================================
function GD.GetLatestSlotInfo()
    local latest = nil
    local latestSlot = nil
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
        local info = GD.GetSlotInfo(i)
        if info and info.savedAt ~= "" then
            if not latest or info.savedAt > latest.savedAt then
                latest = info
                latestSlot = i
            end
        end
    end
    if latest then
        latest.slot = latestSlot
    end
    return latest
end

-- ============================================================================
-- 性能优化：数据清理/归档（防止后期数据无限膨胀导致卡顿和OOM）
-- ============================================================================

-- 性能优化：裁剪数组，只保留最后 limit 条，避免历史数据无限增长。
local function trimArrayTail(t, limit)
    if not t then return {} end
    if #t <= limit then return t end
    local kept = {}
    local startIdx = #t - limit + 1
    for i = startIdx, #t do
        kept[#kept + 1] = t[i]
    end
    return kept
end

--- 清理项目内部冗余历史数据（施工记录、营销历史、招采历史等）
---@param p table 项目对象
local function cleanProjectHistoryData(p)
    -- 施工系统历史数据限制
    if p.construction then
        local con = p.construction
        -- 安全事故记录：最多保留最近10条
        if con.safetySystem and con.safetySystem.accidents and #con.safetySystem.accidents > 10 then
            local kept = {}
            for i = #con.safetySystem.accidents - 9, #con.safetySystem.accidents do
                kept[#kept + 1] = con.safetySystem.accidents[i]
            end
            con.safetySystem.accidents = kept
        end
        -- 安全检查记录：最多保留最近10条
        if con.safetySystem and con.safetySystem.checks and #con.safetySystem.checks > 10 then
            local kept = {}
            for i = #con.safetySystem.checks - 9, #con.safetySystem.checks do
                kept[#kept + 1] = con.safetySystem.checks[i]
            end
            con.safetySystem.checks = kept
        end
        -- 质量验收记录：最多保留最近10条
        if con.qualitySystem and con.qualitySystem.acceptances and #con.qualitySystem.acceptances > 10 then
            local kept = {}
            for i = #con.qualitySystem.acceptances - 9, #con.qualitySystem.acceptances do
                kept[#kept + 1] = con.qualitySystem.acceptances[i]
            end
            con.qualitySystem.acceptances = kept
        end
        -- 质量测量记录：最多保留最近10条
        if con.qualitySystem and con.qualitySystem.measurements and #con.qualitySystem.measurements > 10 then
            local kept = {}
            for i = #con.qualitySystem.measurements - 9, #con.qualitySystem.measurements do
                kept[#kept + 1] = con.qualitySystem.measurements[i]
            end
            con.qualitySystem.measurements = kept
        end
        -- 变更令历史：最多保留最近8条
        if con.changeOrders and con.changeOrders.items and #con.changeOrders.items > 8 then
            local kept = {}
            for i = #con.changeOrders.items - 7, #con.changeOrders.items do
                kept[#kept + 1] = con.changeOrders.items[i]
            end
            con.changeOrders.items = kept
        end
        -- 环境停工记录：最多保留最近5条
        if con.envStoppages and #con.envStoppages > 5 then
            local kept = {}
            for i = #con.envStoppages - 4, #con.envStoppages do
                kept[#kept + 1] = con.envStoppages[i]
            end
            con.envStoppages = kept
        end
    end
    -- 营销签约队列是有效未回款合同，不能在清理阶段裁剪，否则会造成报表有收入但现金不到账。
    if p.sales and p.sales.marketing and p.sales.marketing.collection then
        local coll = p.sales.marketing.collection
        coll.signingQueue = coll.signingQueue or {}
    end
    -- 价格历史：最多保留最近24次调价
    if p.sales and p.sales.marketing and p.sales.marketing.pricing then
        local pricing = p.sales.marketing.pricing
        pricing.priceHistory = trimArrayTail(pricing.priceHistory, 24)
    end
    -- 随机事件历史：最多保留最近20条
    if p.randomEvents then
        p.randomEvents.history = trimArrayTail(p.randomEvents.history, 20)
    end
    -- 招采历史：最多保留最近10条
    if p.procurement and p.procurement.history and #p.procurement.history > 10 then
        local kept = {}
        for i = #p.procurement.history - 9, #p.procurement.history do
            kept[#kept + 1] = p.procurement.history[i]
        end
        p.procurement.history = kept
    end
end

--- 对已完成项目进行深度精简（移除不再需要的大块数据）
---@param p table 已完成的项目对象
local function archiveCompletedProject(p)
    -- 已完成的项目不再需要施工活动详情
    if p.construction then
        -- 保留汇总信息，删除细粒度追踪数据
        p.construction.activities = nil
        p.construction.milestones = nil
        p.construction.machines = nil
        -- 清空所有历史记录
        if p.construction.safetySystem then
            p.construction.safetySystem.accidents = {}
            p.construction.safetySystem.checks = {}
        end
        if p.construction.qualitySystem then
            p.construction.qualitySystem.acceptances = {}
            p.construction.qualitySystem.measurements = {}
        end
        if p.construction.changeOrders then
            p.construction.changeOrders.items = {}
        end
        p.construction.envStoppages = nil
    end
    -- 已完成项目的招采包详情可清理
    if p.procurement then
        p.procurement.packages = {}  -- 包已完成，清空详情
        -- 历史保留精简版（只保留最后3条）
        if p.procurement.history and #p.procurement.history > 3 then
            local kept = {}
            for i = #p.procurement.history - 2, #p.procurement.history do
                kept[#kept + 1] = p.procurement.history[i]
            end
            p.procurement.history = kept
        end
    end
    -- 营销详情：清空签约队列前必须真实入账，不能只改报表字段。
    if p.sales and p.sales.marketing then
        if p.sales.marketing.collection then
            GD.SettlePendingSalesCollections(p, "项目归档回款", true)
            releaseEscrowNow(p)
        end
        if p.sales.marketing.pricing then
            p.sales.marketing.pricing.priceHistory = trimArrayTail(p.sales.marketing.pricing.priceHistory, 6)
        end
    end
    if p.randomEvents then
        p.randomEvents.history = trimArrayTail(p.randomEvents.history, 5)
    end
    -- 设计阶段详情（已完成不再需要）
    if p.design and p.design.review then
        p.design.review.stages = {}
    end
    -- 标记已归档
    p._archived = true
end

--- 主清理函数（由MonthlyTick定期调用和AutoSave前调用）
function GD.PerformDataCleanup()
    -- 1. 清理进行中项目的历史累积数据
    for _, p in ipairs(GD.projects) do
        if not p._archived then
            cleanProjectHistoryData(p)
        end
        -- 已完成且售罄超过6个月的项目：深度精简
        if not p._archived then
            local isTerminal = (p.status == "completed" or p.status == "mature")
            local allSold = p.sales and p.sales.allUnitsSold
            -- 如果已经全部售罄并且是终态，归档
            if isTerminal and allSold then
                archiveCompletedProject(p)
            end
        end
    end

    -- 2. 清理土地市场过期地块（超过12个月未售出的地块移除，保留最近的）
    local maxLandMarketSize = 30  -- 最多保留30块地
    if #GD.landMarket > maxLandMarketSize then
        -- 按添加时间排序（后添加的保留），移除最早的
        local excess = #GD.landMarket - maxLandMarketSize
        for _ = 1, excess do
            table.remove(GD.landMarket, 1)  -- 移除最早的
        end
    end

    -- 3. 限制固定资产出售/出租挂牌历史
    if GD.assetListings then
        local active = {}
        for _, listing in ipairs(GD.assetListings) do
            if listing.status ~= "sold" and listing.status ~= "expired" then
                active[#active + 1] = listing
            end
        end
        GD.assetListings = trimArrayTail(active, 40)
    end
    if GD.rentalListings then
        local activeRentals = {}
        for _, listing in ipairs(GD.rentalListings) do
            if listing.status ~= "rented" and listing.status ~= "expired" and listing.status ~= "cancelled" then
                activeRentals[#activeRentals + 1] = listing
            end
        end
        GD.rentalListings = trimArrayTail(activeRentals, 40)
    end
    if GD.assetMarket and GD.assetMarket.listings then
        local available = {}
        for _, listing in ipairs(GD.assetMarket.listings) do
            if listing.status == "available" then
                available[#available + 1] = listing
            end
        end
        GD.assetMarket.listings = trimArrayTail(available, 30)
    end

    -- 4. 清理城市投资中已到期的数据
    -- 城市债券：移除已到期的
    for cityName, bondData in pairs(GD.cityBondData or {}) do
        if bondData.bonds then
            local active = {}
            for _, bond in ipairs(bondData.bonds) do
                if not bond.matured then
                    active[#active + 1] = bond
                end
            end
            bondData.bonds = trimArrayTail(active, 30)
        end
        if bondData.holdings then
            local activeHoldings = {}
            for _, bond in ipairs(bondData.holdings) do
                if bond.active ~= false then
                    activeHoldings[#activeHoldings + 1] = bond
                end
            end
            bondData.holdings = trimArrayTail(activeHoldings, 30)
        end
    end

    -- 5. 清理城市赞助、信用社理财和银行理财历史
    for _, sponsor in pairs(GD.citySponsorData or {}) do
        sponsor.history = trimArrayTail(sponsor.history, 20)
    end
    for _, creditData in pairs(GD.cityCreditData or {}) do
        if creditData.wealthFunds then
            local activeFunds = {}
            for _, fund in ipairs(creditData.wealthFunds) do
                if fund.active ~= false then
                    activeFunds[#activeFunds + 1] = fund
                end
            end
            creditData.wealthFunds = trimArrayTail(activeFunds, 30)
        end
        if creditData.loans then
            local activeLoans = {}
            for _, loan in ipairs(creditData.loans) do
                if loan.active ~= false then
                    activeLoans[#activeLoans + 1] = loan
                end
            end
            creditData.loans = trimArrayTail(activeLoans, 30)
        end
    end
    for _, bank in pairs(GD.cityBankData or {}) do
        if bank.wealthProducts then
            local activeProducts = {}
            for _, product in ipairs(bank.wealthProducts) do
                if product.active ~= false then
                    activeProducts[#activeProducts + 1] = product
                end
            end
            bank.wealthProducts = trimArrayTail(activeProducts, 30)
        end
    end

    -- 6. 股市交易历史只保留最近100条，价格历史在StockMarket中已按12个月裁剪
    if GD.stockMarket then
        GD.stockMarket.history = trimArrayTail(GD.stockMarket.history, 100)
    end

    -- 7. 强制GC回收刚释放的内存
    collectgarbage("step", 20)
end

-- ============================================================================
-- 自动存档（实时快照 + 每半年兜底保存）
-- ============================================================================
GD.autoSaveInterval = 6        -- 每6个月兜底深度保存一次，降低月结/JSON编码高峰
GD.realTimeAutoSaveDays = 30   -- 每30个游戏日轻量保存一次，减少快速模式连续卡顿
GD._autoSaveCounter = 0
GD._realTimeAutoSaveCounter = 0

function GD.AutoSave(lightweight)
    -- 实时保存只编码写盘；半年兜底保存再做深度清理，避免快速模式频繁卡顿。
    if not lightweight then
        GD.PerformDataCleanup()
        collectgarbage("step", 80)
    else
        collectgarbage("step", 20)
    end

    local ok, err = pcall(function()
        local jsonStr = cjson.encode(buildSaveData())
        writeSaveFileSafely(SAVE_DIR .. "/slot_auto.json", jsonStr)
    end)
    if ok then
        if not lightweight then
            print("[AUTOSAVE] 自动存档成功 " .. GD.year .. "年" .. GD.month .. "月")
        end
    else
        print("[AUTOSAVE] 自动存档失败: " .. tostring(err))
    end
end

-- 自动存档触发(每月调用，内部计数)
---@return boolean shouldAutoSave 是否应该在后续低峰帧执行自动存档
function GD.CheckAutoSave()
    GD._autoSaveCounter = GD._autoSaveCounter + 1
    if GD._autoSaveCounter >= GD.autoSaveInterval then
        GD._autoSaveCounter = 0
        GD._realTimeAutoSaveCounter = 0
        return true
    end
    return false
end

-- 实时自动存档触发(每日调用，内部计数；实际保存仍延迟到低峰帧执行)
---@return boolean shouldAutoSave 是否应该在后续低峰帧执行自动存档
function GD.CheckRealTimeAutoSave()
    GD._realTimeAutoSaveCounter = (GD._realTimeAutoSaveCounter or 0) + 1
    local interval = GD.realTimeAutoSaveDays or 7
    if GD._realTimeAutoSaveCounter >= interval then
        GD._realTimeAutoSaveCounter = 0
        return true
    end
    return false
end

-- 获取自动存档信息
function GD.GetAutoSaveInfo()
    local savePath = SAVE_DIR .. "/slot_auto.json"
    local data = decodeSaveFileWithBackup(savePath)
    if not data then return nil end
    return {
        name = data.company and data.company.name or "未知",
        date = string.format("%d年%02d月%02d日", data.year or 0, data.month or 0, data.day or 0),
        cash = data.company and data.company.cash or 0,
        savedAt = data.savedAt or "",
        version = data.version or 0,
        slot = "auto",
    }
end

-- 从自动存档读取
function GD.LoadAutoSave()
    local savePath = SAVE_DIR .. "/slot_auto.json"
    local data, loadErr = decodeSaveFileWithBackup(savePath)
    if not data then return false, loadErr or "自动存档数据损坏" end
    pcall(function()
        writeSaveFileSafely(SAVE_DIR .. "/slot_0.json", cjson.encode(data))
    end)
    local ok, err = GD.LoadFromSlot(0)
    return ok, err
end

-- 更新 GetLatestSlotInfo 以包含自动存档
function GD.GetLatestSlotInfoWithAuto()
    local latest = GD.GetLatestSlotInfo()
    local autoInfo = GD.GetAutoSaveInfo()
    if autoInfo then
        if not latest or autoInfo.savedAt > latest.savedAt then
            return autoInfo
        end
    end
    return latest
end

-- ============================================================================
-- 兑换码
-- ============================================================================
GD._codeRewards = {
    ["WELCOME2001"]  = {cash = 500,   desc = "开业大吉礼金500万"},
    ["BIGMONEY"]     = {cash = 2000,  desc = "巨额资金2000万"},
    ["CREDITUP"]     = {credit = 15,  desc = "信用分+15"},
    ["LANDBONUS"]    = {cash = 1000,  desc = "土地补贴1000万"},
    ["TOPBUILDER"]   = {cash = 3000,  desc = "名企扶持3000万"},
    ["VIP888"]       = {cash = 888,   desc = "VIP专属888万"},
    ["ZXCVBNM"]      = {personalCash = 500000, desc = "个人资金50亿", unlimited = true},
}

function GD.RedeemCode(code)
    code = string.upper(code or "")
    if code == "" then return false, "请输入兑换码" end
    local reward = GD._codeRewards[code]
    if not reward then return false, "无效的兑换码" end
    if reward.personalCash and not GD.player then return false, "个人数据尚未初始化" end
    -- unlimited 标记的兑换码可无限次使用
    if not reward.unlimited and GD.redeemedCodes[code] then
        return false, "该兑换码已使用"
    end

    if not reward.unlimited then
        GD.redeemedCodes[code] = true
    end
    if reward.cash then
        GD.company.cash = GD.company.cash + reward.cash
    end
    if reward.personalCash then
        GD.player.cash = (GD.player.cash or 0) + reward.personalCash
    end
    if reward.credit then
        GD.company.creditScore = math.min(100, GD.company.creditScore + reward.credit)
    end
    GD.AddEvent("兑换码生效: " .. reward.desc, "success")
    return true, reward.desc
end

-- ============================================================================
-- 新手礼包(一次性)
-- ============================================================================
function GD.ClaimBeginnerGift()
    if GD.beginnerGiftClaimed then return false, "新手礼包已领取" end
    GD.beginnerGiftClaimed = true
    GD.company.cash = GD.company.cash + 500
    GD.company.creditScore = math.min(100, GD.company.creditScore + 5)
    GD.AddEvent("领取新手礼包: 现金500万 + 信用分+5", "success")
    return true
end

-- ============================================================================
-- 投资测算 (委托 LandAcquisition 模块)
-- ============================================================================
function GD.CalcInvestment(land)
    local city = GD.GetCityData()
    return LA.CalcInvestment(land, city, GD.economy, GD.company.traitEffects)
end

-- ============================================================================
-- 获取市场趋势数据(近12个月模拟)
-- ============================================================================
function GD.GetMarketTrend()
    local city = GD.GetCityData()
    if not city then return {} end
    local data = {}
    local basePrice = city.avgPrice
    local idx = GD.economy.priceIndex
    -- 回溯12个月的指数变化(简化模拟)
    for m = 11, 0, -1 do
        local monthIdx = GD.totalMonths - m
        local fluctuation = 1 + (math.sin(monthIdx * 0.5) * 0.03 + math.cos(monthIdx * 0.3) * 0.02)
        local price = math.floor(basePrice * (idx / 100) * fluctuation)
        local mo = ((GD.month - m - 1) % 12) + 1
        table.insert(data, {
            month = mo,
            label = mo .. "月",
            price = price,
            index = math.floor(idx * fluctuation),
        })
    end
    return data
end

-- ============================================================================
-- 竞争对手最新动态
-- ============================================================================
function GD.GetCompetitorReport()
    local reports = {}
    local actions = {
        "拿地2宗", "新开盘1个项目", "降价促销", "收购区域公司",
        "获评信用A级", "完成年度目标", "IPO准备中", "布局新城市",
        "高管变动", "战略合作签约", "拿地失败退出", "资金链紧张",
        "启动城市更新项目", "债券融资成功", "利润大幅增长", "裁员优化",
    }
    for _, comp in ipairs(GD.competitors) do
        local action = actions[math.random(1, #actions)]
        local cashTrend = math.random(-10, 15)
        comp.cash = math.max(500, comp.cash + comp.cash * cashTrend / 100)
        table.insert(reports, {
            name = comp.name,
            type = comp.type,
            cash = comp.cash,
            style = comp.style,
            tier = comp.tier or "C",
            action = action,
            aggressive = comp.aggressive,
        })
    end
    return reports
end

-- ============================================================================
-- 股权投资相关函数
-- ============================================================================

--- 合并同一竞争对手的多笔股权投资，兼容旧存档重复记录
function GD.NormalizeEquityInvestments()
    if not GD.equityInvestments or #GD.equityInvestments <= 1 then return end
    local merged = {}
    local order = {}
    for _, inv in ipairs(GD.equityInvestments) do
        local key = inv.compIdx
        if key then
            local target = merged[key]
            if not target then
                target = {
                    compIdx = inv.compIdx,
                    compName = inv.compName,
                    investAmount = 0,
                    equityRatio = 0,
                    totalDividends = 0,
                    investYear = inv.investYear,
                    investMonth = inv.investMonth,
                }
                merged[key] = target
                table.insert(order, key)
            end
            target.compName = target.compName or inv.compName
            target.investAmount = (target.investAmount or 0) + (inv.investAmount or 0)
            target.equityRatio = math.min(0.30, (target.equityRatio or 0) + (inv.equityRatio or 0))
            target.totalDividends = (target.totalDividends or 0) + (inv.totalDividends or 0)
            if (inv.investYear or 9999) < (target.investYear or 9999)
                or ((inv.investYear or 9999) == (target.investYear or 9999) and (inv.investMonth or 99) < (target.investMonth or 99)) then
                target.investYear = inv.investYear
                target.investMonth = inv.investMonth
            end
        end
    end
    local normalized = {}
    for _, key in ipairs(order) do
        table.insert(normalized, merged[key])
    end
    GD.equityInvestments = normalized
end

function GD.GetEquityInvestmentCurrentValue(inv, comp)
    local investAmount = inv and (inv.investAmount or 0) or 0
    if investAmount <= 0 then return 0 end

    local marketValue = 0
    if comp then
        marketValue = (comp.cash or 0) * 2.5 * (inv.equityRatio or 0)
    end

    local startYear = inv.investYear or GD.year or 1
    local startMonth = inv.investMonth or 1
    local currentYear = GD.year or startYear
    local currentMonth = GD.month or startMonth
    local heldMonths = math.max(0, (currentYear - startYear) * 12 + (currentMonth - startMonth))
    local heldYears = heldMonths / 12
    local maxValue = investAmount * (1.03 ^ heldYears)

    return math.floor(math.max(0, math.min(marketValue, maxValue)))
end

--- 投资竞争对手的股权
---@param compIdx number 竞争对手索引
---@param amount number 投资金额(万元)
---@return boolean ok
---@return string message
function GD.InvestEquity(compIdx, amount)
    GD.NormalizeEquityInvestments()
    local comp = GD.competitors[compIdx]
    if not comp then return false, "竞争对手不存在" end
    if GD.company.cash < amount then return false, "公司资金不足" end
    if amount < 100 then return false, "最低投资100万" end

    -- 计算获得的股权比例(按对手资产估值)
    local compValuation = comp.cash * 2.5  -- 简化估值=资金*2.5倍
    local equityRatio = amount / (compValuation + amount)  -- 投后估值算法
    equityRatio = math.min(0.30, equityRatio)  -- 最多持股30%

    local existingInv = nil
    local existingRatio = 0
    for _, inv in ipairs(GD.equityInvestments) do
        if inv.compIdx == compIdx then
            existingInv = inv
            existingRatio = existingRatio + (inv.equityRatio or 0)
        end
    end
    if existingRatio + equityRatio > 0.30 then
        return false, "对该公司持股已达上限30%"
    end

    -- 扣款
    GD.company.cash = GD.company.cash - amount
    comp.cash = comp.cash + amount  -- 对手获得资金注入

    -- 记录投资：同一公司聚合为一条记录
    if existingInv then
        existingInv.compName = comp.name
        existingInv.investAmount = (existingInv.investAmount or 0) + amount
        existingInv.equityRatio = existingRatio + equityRatio
        existingInv.totalDividends = existingInv.totalDividends or 0
    else
        table.insert(GD.equityInvestments, {
            compIdx = compIdx,
            compName = comp.name,
            investAmount = amount,
            equityRatio = equityRatio,
            totalDividends = 0,
            investYear = GD.year,
            investMonth = GD.month,
        })
    end

    -- 关系提升
    comp._relation = math.min(100, (comp._relation or 50) + math.floor(equityRatio * 100))

    GD.AddEvent(string.format("股权投资%s %s，新增%.1f%%股权，累计%.1f%%", comp.name, GD.FormatMoney(amount), equityRatio * 100, (existingRatio + equityRatio) * 100), "success")
    return true, string.format("投资成功！累计持有%s %.1f%%股权", comp.name, (existingRatio + equityRatio) * 100)
end

--- 每年结算股权投资分红(12月调用)
function GD.UpdateEquityDividends()
    GD.NormalizeEquityInvestments()
    if #GD.equityInvestments == 0 then return 0 end
    local totalDividend = 0
    for _, inv in ipairs(GD.equityInvestments) do
        local comp = GD.competitors[inv.compIdx]
        if comp then
            local currentValue = GD.GetEquityInvestmentCurrentValue(inv, comp)
            local dividendRate = math.random(0, 500) / 10000
            local myDividend = math.floor(currentValue * dividendRate)
            if myDividend > 0 then
                inv.totalDividends = inv.totalDividends + myDividend
                totalDividend = totalDividend + myDividend
            end
        end
    end
    if totalDividend > 0 then
        GD.company.cash = GD.company.cash + totalDividend
        GD.AddEvent("股权投资分红收入: " .. GD.FormatMoney(totalDividend), "success")
    end
    return totalDividend
end

--- 退出股权投资(卖出)
---@param invIdx number 投资记录索引
---@return boolean ok
---@return string message
function GD.ExitEquityInvestment(invIdx)
    GD.NormalizeEquityInvestments()
    local inv = GD.equityInvestments[invIdx]
    if not inv then return false, "投资记录不存在" end

    local comp = GD.competitors[inv.compIdx]
    if not comp then return false, "竞争对手不存在" end

    -- 按当前估值卖出，现值年涨幅上限为3%
    local sellAmount = GD.GetEquityInvestmentCurrentValue(inv, comp)
    local profit = sellAmount - inv.investAmount

    -- 对手回购股权，需要支付资金（如果对手现金不足则只能部分回购）
    local actualSell = math.min(sellAmount, comp.cash)
    if actualSell < sellAmount * 0.5 then
        -- 对手现金严重不足时，按折价卖出
        actualSell = math.min(sellAmount * 0.5, comp.cash)
    end
    local actualProfit = actualSell - inv.investAmount

    GD.company.cash = GD.company.cash + actualSell
    comp.cash = comp.cash - actualSell  -- 对手支付回购款
    comp._relation = math.max(0, (comp._relation or 50) - 10)

    local profitText = actualProfit >= 0
        and ("盈利" .. GD.FormatMoney(actualProfit))
        or ("亏损" .. GD.FormatMoney(math.abs(actualProfit)))

    GD.AddEvent(string.format("退出%s股权投资，回收%s(%s)", comp.name, GD.FormatMoney(actualSell), profitText), actualProfit >= 0 and "success" or "warning")
    table.remove(GD.equityInvestments, invIdx)
    return true, string.format("退出成功，回收%s，%s", GD.FormatMoney(actualSell), profitText)
end

--- 引入竞争对手作为股东
---@param compIdx number 竞争对手索引
---@param amount number 对方投资金额(万元)
---@return boolean ok
---@return string message
function GD.IntroduceShareholder(compIdx, amount)
    local comp = GD.competitors[compIdx]
    if not comp then return false, "竞争对手不存在" end

    local rel = comp._relation or 50
    if rel < 50 then return false, "关系不足(需≥50)，对方不愿投资" end
    if comp.cash < amount then return false, comp.name .. "资金不足" end
    if amount < 500 then return false, "最低入股金额500万" end

    local gov = GD.company.governance
    if not gov then return false, "公司治理结构未初始化" end

    -- 持股≥50%才能引入竞争对手为股东
    if gov.founderRatio < 0.50 then
        return false, string.format("创始人持股%.1f%%，低于50%%，不能引入竞争对手为股东", gov.founderRatio * 100)
    end

    -- 计算对手获得的股权(按公司估值)
    local companyValuation = math.max(GD.company.cash * 2, gov.lastValuation)
    local dilutionRatio = amount / (companyValuation + amount)
    dilutionRatio = math.min(0.20, dilutionRatio)  -- 单次最多出让20%

    -- 检查创始人持股底线
    if gov.founderRatio * (1 - dilutionRatio) < 0.34 then
        return false, "引入该金额将使创始人持股低于34%(否决权底线)"
    end

    -- 对手扣款
    comp.cash = comp.cash - amount
    -- 公司获得资金
    GD.company.cash = GD.company.cash + amount

    -- 增发股份并稀释
    local newShares = math.floor(gov.totalShares * dilutionRatio / (1 - dilutionRatio))
    gov.totalShares = gov.totalShares + newShares

    -- 稀释所有现有股东
    for _, sh in ipairs(gov.shareholders) do
        sh.ratio = sh.shares / gov.totalShares
    end

    -- 添加新股东
    local investorId = "comp_" .. compIdx .. "_" .. GD.totalMonths
    table.insert(gov.shareholders, {
        id = investorId,
        name = comp.name,
        shares = newShares,
        ratio = newShares / gov.totalShares,
        type = "strategic",
        totalDividends = 0,
        investAmount = amount,
    })

    -- 更新创始人持股
    for _, sh in ipairs(gov.shareholders) do
        if sh.id == "founder" then
            gov.founderShares = sh.shares
            gov.founderRatio = sh.ratio
            break
        end
    end

    gov.lastValuation = companyValuation + amount
    comp._relation = math.min(100, (comp._relation or 50) + 20)

    GD.AddEvent(string.format("%s入股%s，获得%.1f%%股权(创始人持股%.1f%%)",
        comp.name, GD.FormatMoney(amount), dilutionRatio * 100, gov.founderRatio * 100), "info")
    return true, string.format("%s成功入股！投资%s，获得%.1f%%股权", comp.name, GD.FormatMoney(amount), dilutionRatio * 100)
end

--- 同业借款月度结息(MonthlyTick调用)
function GD.UpdateCompLoans()
    if not GD._compLoans or #GD._compLoans == 0 then return end
    local toRemove = {}
    for i, loan in ipairs(GD._compLoans) do
        -- 扣月息
        GD.company.cash = GD.company.cash - loan.monthlyInterest
        loan.remainMonths = loan.remainMonths - 1
        if loan.remainMonths <= 0 then
            -- 到期自动还本金
            if GD.company.cash >= loan.amount then
                GD.company.cash = GD.company.cash - loan.amount
                for _, comp in ipairs(GD.competitors) do
                    if comp.name == loan.lender then
                        comp.cash = comp.cash + loan.amount
                        comp._relation = math.min(100, (comp._relation or 50) + 5)
                        break
                    end
                end
                GD.AddEvent("同业借款到期自动还清: " .. loan.lender .. " " .. GD.FormatMoney(loan.amount), "info")
            else
                -- 无力偿还：关系恶化+信用扣分
                for _, comp in ipairs(GD.competitors) do
                    if comp.name == loan.lender then
                        comp._relation = math.max(0, (comp._relation or 50) - 20)
                        break
                    end
                end
                GD.company.creditScore = math.max(0, GD.company.creditScore - 5)
                GD.AddEvent("同业借款违约! " .. loan.lender .. " " .. GD.FormatMoney(loan.amount) .. " 信用-5", "danger")
            end
            table.insert(toRemove, i)
        end
    end
    -- 倒序删除已到期的
    for i = #toRemove, 1, -1 do
        table.remove(GD._compLoans, toRemove[i])
    end
end

-- ============================================================================
-- 营销管理(转发到 Marketing 模块, 保持旧接口向后兼容)
-- ============================================================================
function GD.SetMarketingBudget(project, budget)
    MK.SetMarketingBudget(project, budget)
    GD.AddEvent("【" .. project.name .. "】月营销预算调整为 " .. GD.FormatMoney(budget), "info")
end

function GD.ToggleChannel(project, channelKey, enabled)
    return MK.ToggleChannel(project, channelKey, enabled, GD)
end

function GD.SetPromotion(project, promoType, months)
    MK.SetPromotion(project, promoType, months, GD)
end

-- ============================================================================
-- 看广告奖励(每次100万)
-- ============================================================================
function GD.ClaimAdReward()
    -- 每天限领10次（每月模拟30天，用 totalMonths*30 + 虚拟天数做日期标识）
    local currentDay = GD.totalMonths
    if GD.adRewardLastDay ~= currentDay then
        GD.adRewardDayCount = 0
        GD.adRewardLastDay = currentDay
    end
    if GD.adRewardDayCount >= 10 then
        return false, "今日广告领取次数已达上限(10次)，明天再来吧"
    end
    GD.adRewardDayCount = GD.adRewardDayCount + 1
    GD.adRewardCount = GD.adRewardCount + 1
    GD.company.cash = GD.company.cash + 100
    GD.AddEvent("观看广告奖励: 现金+100万 (今日第" .. GD.adRewardDayCount .. "/10次)", "success")
    return true
end

-- 暴露模块引用，供屏幕层直接使用常量/函数
GD.LandAcquisition = LA
GD.Marketing = MK
GD.Finance = FN
GD.Brand = BR
GD.ProjectCapacity = PC
GD.DevTypes = DT
GD.Operations = OP
GD.AgencyFee = AF
GD.Personal = PS
GD.Governance = GV
GD.GroupSystem = GS
GD.InternationalSystem = INS
GD.GetExecutiveEffects = GV.GetExecutiveEffects
GD.StockMarket = SM

return GD
