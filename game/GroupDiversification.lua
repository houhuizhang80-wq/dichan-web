-- ============================================================================
-- GroupDiversification.lua - 集团多元化产业、协同、收益与风险
-- ============================================================================

local GDI = {}
local GIO = require("GroupIndustryOperations")

GDI.Operations = GIO
GDI.DATA_VERSION = 2
GDI.MAX_LEVEL = 5

GDI.SECTORS = {
    property_chain = {name = "地产协同产业链", shortName = "产业链", desc = "围绕开发、设计、建材、家居与物业形成纵向协同。"},
    held_assets = {name = "持有型不动产", shortName = "持有资产", desc = "布局产业、物流、算力、康养和公共设施等长期运营资产。"},
    modern_services = {name = "现代服务业", shortName = "现代服务", desc = "输出资管、更新顾问、人才安居与场馆运营能力。"},
    low_carbon = {name = "能源与低碳", shortName = "能源低碳", desc = "建设分布式能源、碳资产和区域供能能力。"},
    financial_capital = {name = "金融资本", shortName = "金融资本", desc = "以稳定租金资产和集团风控为基础开展资本业务。"},
    consumer_tourism = {name = "消费与文旅", shortName = "消费文旅", desc = "依托社区、商业和旅游资产发展实体消费品牌。"},
}
GDI.SECTOR_ORDER = {"property_chain", "held_assets", "modern_services", "low_carbon", "financial_capital", "consumer_tourism"}

GDI.STRATEGIES = {
    steady = {name = "稳健经营", desc = "降低波动和风险，保留更高利润质量。", revenue = 0.92, margin = 0.04, risk = 0.65},
    growth = {name = "规模扩张", desc = "扩大收入规模，但提高固定成本和经营风险。", revenue = 1.20, margin = -0.03, risk = 1.40},
    efficiency = {name = "精益提效", desc = "控制规模，改善利润率和资产周转。", revenue = 1.02, margin = 0.08, risk = 0.82},
}
GDI.STRATEGY_ORDER = {"steady", "growth", "efficiency"}

local function industry(data)
    data.maxLevel = data.maxLevel or GDI.MAX_LEVEL
    data.volatility = data.volatility or 0.08
    data.riskRate = data.riskRate or 0.015
    data.assetRatio = data.assetRatio or 0.70
    data.fixedCost = data.fixedCost or math.floor(data.investment * 0.0015)
    data.unlock = data.unlock or {}
    return data
end

GDI.INDUSTRIES = {
    prefab_materials = industry {
        sector = "property_chain", name = "新型建材与装配式产业园", type = "heavy",
        desc = "生产装配式构件与绿色建材，降低集团成员项目的基础建安支出。",
        investment = 12000, revenueRate = 0.018, margin = 0.24, riskRate = 0.018, cycleSensitivity = 0.85,
        riskName = "产能利用率骤降", driver = "projects", synergy = {constructionCostReduction = 0.035},
        unlock = {members = 2, activeProjects = 2},
    },
    recycled_materials = industry {
        sector = "property_chain", name = "二手建材回收加工", type = "operating",
        desc = "回收拆除物和旧建材再加工，兼顾低成本采购与绿色收益。",
        investment = 4500, revenueRate = 0.024, margin = 0.20, riskRate = 0.022, cycleSensitivity = 0.55,
        riskName = "再生料质量争议", driver = "projects", synergy = {constructionCostReduction = 0.012, riskReduction = 0.01},
        unlock = {members = 2},
    },
    smart_home = industry {
        sector = "property_chain", name = "整装家居与智慧家居集团", type = "operating",
        desc = "承接精装、软装和智慧家庭订单，分享项目交付后的消费价值。",
        investment = 7000, revenueRate = 0.030, margin = 0.18, riskRate = 0.020, cycleSensitivity = 0.80,
        riskName = "批量交付售后激增", driver = "projects", synergy = {salesDemandBonus = 0.018},
        unlock = {members = 2, completedProjects = 1},
    },
    home_brand_mall = industry {
        sector = "property_chain", name = "自有家居品牌与线下卖场", type = "consumer",
        desc = "运营自有家居品牌与体验卖场，受消费周期和商业客流影响明显。",
        investment = 9000, revenueRate = 0.035, margin = 0.14, riskRate = 0.030, cycleSensitivity = 1.10,
        riskName = "门店库存与客流危机", driver = "assets", synergy = {salesDemandBonus = 0.012},
        unlock = {netAssets = 25000, completedProjects = 2, prerequisite = "smart_home"},
    },
    property_facility = industry {
        sector = "property_chain", name = "全域物业与设施运维集团", type = "operating",
        desc = "统筹住宅、园区、商业和公共设施运维，提升收缴与运营效率。",
        investment = 6000, revenueRate = 0.025, margin = 0.22, riskRate = 0.014, cycleSensitivity = 0.30,
        riskName = "大面积服务投诉", driver = "rentals", synergy = {propertyCostReduction = 0.035, propertyCollectionBonus = 0.015, rentalIncomeBonus = 0.012},
        unlock = {rentalAssets = 6000},
    },
    urban_renewal_ops = industry {
        sector = "property_chain", name = "老旧小区改造运维", type = "operating",
        desc = "承接改造、节能更新和后续社区运维，收益稳健但回款较慢。",
        investment = 8000, revenueRate = 0.020, margin = 0.20, riskRate = 0.018, cycleSensitivity = 0.25,
        riskName = "改造回款延期", driver = "members", synergy = {propertyCostReduction = 0.012, designSpeedBonus = 0.03},
        unlock = {members = 2, netAssets = 18000},
    },
    planning_design = industry {
        sector = "property_chain", name = "勘测规划设计研究院", type = "service",
        desc = "提供勘测、规划和设计服务，缩短集团成员项目的设计周期。",
        investment = 5000, revenueRate = 0.027, margin = 0.32, riskRate = 0.012, cycleSensitivity = 0.45,
        riskName = "重大设计责任索赔", driver = "projects", synergy = {designSpeedBonus = 0.10, constructionCostReduction = 0.008},
        unlock = {members = 2, activeProjects = 1},
    },

    science_park = industry {
        sector = "held_assets", name = "科创产业园与企业孵化器", type = "heavy",
        desc = "组合运营科创园、孵化器和标准厂房，依赖产业招商与区域经济。",
        investment = 20000, revenueRate = 0.013, margin = 0.38, riskRate = 0.016, cycleSensitivity = 0.60,
        riskName = "园区招商断档", driver = "rentals", synergy = {rentalIncomeBonus = 0.015},
        unlock = {netAssets = 35000, rentalAssets = 8000},
    },
    logistics_cold_chain = industry {
        sector = "held_assets", name = "冷链仓储与电商物流园", type = "heavy",
        desc = "运营冷链、电商物流和自助仓储设施，现金流稳定但能耗较高。",
        investment = 18000, revenueRate = 0.016, margin = 0.32, riskRate = 0.018, cycleSensitivity = 0.45,
        riskName = "仓储客户集中退租", driver = "assets", synergy = {rentalIncomeBonus = 0.012},
        unlock = {netAssets = 30000, rentalAssets = 5000},
    },
    data_center = industry {
        sector = "held_assets", name = "算力数据中心园区", type = "heavy",
        desc = "建设高能耗、高门槛的算力园区，盈利能力强但技术与能源风险高。",
        investment = 30000, revenueRate = 0.019, margin = 0.36, riskRate = 0.027, cycleSensitivity = 0.35,
        riskName = "机房故障与客户赔付", driver = "assets", synergy = {energyCostReduction = 0.01},
        unlock = {netAssets = 65000, rentalAssets = 12000, prerequisite = "distributed_energy"},
    },
    senior_care = industry {
        sector = "held_assets", name = "养老社区与康复护理中心", type = "operating",
        desc = "发展养老社区和康复护理，需求稳定但服务质量与合规要求高。",
        investment = 16000, revenueRate = 0.018, margin = 0.23, riskRate = 0.021, cycleSensitivity = 0.15,
        riskName = "照护质量与合规事件", driver = "assets", synergy = {brandBonus = 0.01},
        unlock = {netAssets = 28000, completedProjects = 2},
    },
    rural_resort = industry {
        sector = "held_assets", name = "露营基地与乡村度假区", type = "tourism",
        desc = "运营露营、民宿和温泉度假设施，旺季弹性高且波动明显。",
        investment = 11000, revenueRate = 0.026, margin = 0.25, riskRate = 0.028, volatility = 0.15, cycleSensitivity = 0.90,
        riskName = "淡季客流大幅下滑", driver = "assets", synergy = {brandBonus = 0.008},
        unlock = {netAssets = 22000, completedProjects = 1},
    },
    parking_underground = industry {
        sector = "held_assets", name = "停车场网络与地下商业", type = "heavy",
        desc = "整合停车场和地下商业空间，形成高频、分散的城市运营收入。",
        investment = 10000, revenueRate = 0.020, margin = 0.34, riskRate = 0.014, cycleSensitivity = 0.40,
        riskName = "地下设施安全整改", driver = "assets", synergy = {rentalIncomeBonus = 0.008},
        unlock = {netAssets = 18000, rentalAssets = 3000},
    },
    venue_complex = industry {
        sector = "held_assets", name = "会展中心与体育场馆", type = "heavy",
        desc = "投资会展和体育场馆，依赖活动排期、城市能级及专业运营。",
        investment = 24000, revenueRate = 0.015, margin = 0.27, riskRate = 0.023, cycleSensitivity = 0.75,
        riskName = "大型活动取消", driver = "members", synergy = {brandBonus = 0.012},
        unlock = {netAssets = 50000, members = 3, prerequisite = "convention_operations"},
    },

    asset_management = industry {
        sector = "modern_services", name = "不动产资管平台", type = "service",
        desc = "统一管理集团内外不动产，规模随租金资产和成员公司增长。",
        investment = 6500, revenueRate = 0.026, margin = 0.40, riskRate = 0.012, cycleSensitivity = 0.30,
        riskName = "受托资产估值争议", driver = "rentals", synergy = {rentalIncomeBonus = 0.018, financingRiskReduction = 0.01},
        unlock = {rentalAssets = 8000, members = 2},
    },
    urban_renewal_advisory = industry {
        sector = "modern_services", name = "城市更新与纾困顾问", type = "service",
        desc = "提供更新策划、项目纾困和交易顾问服务，轻资产但依赖专业信誉。",
        investment = 4000, revenueRate = 0.030, margin = 0.43, riskRate = 0.018, cycleSensitivity = -0.20,
        riskName = "纾困项目连带诉讼", driver = "projects", synergy = {designSpeedBonus = 0.05, riskReduction = 0.012},
        unlock = {members = 2, completedProjects = 2},
    },
    talent_housing = industry {
        sector = "modern_services", name = "人才安居与产业猎头", type = "service",
        desc = "为园区和企业提供人才住房、招商配套与猎头服务。",
        investment = 3500, revenueRate = 0.029, margin = 0.34, riskRate = 0.010, cycleSensitivity = 0.35,
        riskName = "大客户合同流失", driver = "members", synergy = {rentalIncomeBonus = 0.006, brandBonus = 0.006},
        unlock = {members = 2},
    },
    convention_operations = industry {
        sector = "modern_services", name = "会展与场地运营公司", type = "operating",
        desc = "输出招商、排期、票务和场地运营能力，可为大型场馆提供协同。",
        investment = 5500, revenueRate = 0.031, margin = 0.25, riskRate = 0.021, volatility = 0.13, cycleSensitivity = 0.85,
        riskName = "活动履约集中取消", driver = "assets", synergy = {brandBonus = 0.008},
        unlock = {netAssets = 15000, completedProjects = 1},
    },

    distributed_energy = industry {
        sector = "low_carbon", name = "分布式新能源与建筑光伏EPC", type = "operating",
        desc = "建设光伏、储能并承接建筑能源工程，降低集团物业能源成本。",
        investment = 9000, revenueRate = 0.023, margin = 0.27, riskRate = 0.017, cycleSensitivity = 0.20,
        riskName = "设备批次故障", driver = "assets", synergy = {energyCostReduction = 0.035, propertyCostReduction = 0.012},
        unlock = {netAssets = 18000, completedProjects = 1},
    },
    carbon_management = industry {
        sector = "low_carbon", name = "碳资产管理与碳交易", type = "service",
        desc = "开发碳资产、节能认证和碳交易服务，政策敏感且价格有波动。",
        investment = 4500, revenueRate = 0.030, margin = 0.38, riskRate = 0.025, volatility = 0.16, cycleSensitivity = 0.05,
        riskName = "碳价与核证规则突变", driver = "assets", synergy = {riskReduction = 0.012, brandBonus = 0.008},
        unlock = {netAssets = 16000, prerequisite = "distributed_energy"},
    },
    district_energy = industry {
        sector = "low_carbon", name = "区域集中供能", type = "heavy",
        desc = "为园区和大型社区提供集中冷、热和综合能源，投入高、合同期长。",
        investment = 22000, revenueRate = 0.016, margin = 0.34, riskRate = 0.020, cycleSensitivity = 0.15,
        riskName = "能源价格倒挂", driver = "rentals", synergy = {energyCostReduction = 0.045, propertyCostReduction = 0.015},
        unlock = {netAssets = 45000, rentalAssets = 12000, prerequisite = "distributed_energy"},
    },

    real_estate_fund = industry {
        sector = "financial_capital", name = "不动产私募基金", type = "financial",
        desc = "以集团资产和外部资本设立不动产基金，管理费稳定但退出受市场影响。",
        investment = 15000, revenueRate = 0.020, margin = 0.48, riskRate = 0.028, volatility = 0.14, cycleSensitivity = 1.00,
        riskName = "基金兑付与退出压力", driver = "rentals", synergy = {financingRiskReduction = 0.012},
        unlock = {netAssets = 60000, rentalAssets = 18000, members = 3, riskControl = 60, prerequisite = "asset_management"},
    },
    finance_lease = industry {
        sector = "financial_capital", name = "产业融资租赁", type = "financial",
        desc = "为产业园设备和能源设施提供融资租赁，收益稳定但承担信用风险。",
        investment = 12000, revenueRate = 0.021, margin = 0.41, riskRate = 0.027, cycleSensitivity = 0.70,
        riskName = "承租企业批量逾期", driver = "assets", synergy = {financingRiskReduction = 0.008},
        unlock = {netAssets = 45000, rentalAssets = 10000, riskControl = 58},
    },
    amc_equity = industry {
        sector = "financial_capital", name = "AMC产权收购合作", type = "financial",
        desc = "与资产管理机构合作收购困境项目产权，收益来自运营改善和资产退出。",
        investment = 22000, revenueRate = 0.024, margin = 0.44, riskRate = 0.040, volatility = 0.18, cycleSensitivity = -0.35,
        riskName = "困境产权处置失败", driver = "assets", synergy = {rentalIncomeBonus = 0.008},
        unlock = {netAssets = 85000, rentalAssets = 22000, members = 3, riskControl = 68, prerequisite = "urban_renewal_advisory"},
    },
    amc_debt = industry {
        sector = "financial_capital", name = "AMC债权收购合作", type = "financial",
        desc = "折价收购不良债权并通过重组、清收获利，不取得底层资产日常产权收益。",
        investment = 18000, revenueRate = 0.026, margin = 0.46, riskRate = 0.045, volatility = 0.20, cycleSensitivity = -0.45,
        riskName = "债权回收率不及预期", driver = "members", synergy = {financingRiskReduction = 0.006},
        unlock = {netAssets = 75000, rentalAssets = 15000, members = 3, riskControl = 72, prerequisite = "finance_lease"},
    },

    community_retail = industry {
        sector = "consumer_tourism", name = "社区生鲜与精品商超", type = "consumer",
        desc = "布局社区生鲜、精品商超和亲子门店，周转快但租金与库存压力高。",
        investment = 6500, revenueRate = 0.050, margin = 0.09, riskRate = 0.030, volatility = 0.12, cycleSensitivity = 0.75,
        riskName = "门店库存损耗失控", driver = "projects", synergy = {salesDemandBonus = 0.008, rentalIncomeBonus = 0.006},
        unlock = {netAssets = 14000, completedProjects = 2},
    },
    hotel_brands = industry {
        sector = "consumer_tourism", name = "多档位酒店品牌", type = "tourism",
        desc = "发展经济、中高端和度假酒店品牌，客房收益随周期和品牌波动。",
        investment = 15000, revenueRate = 0.029, margin = 0.23, riskRate = 0.028, volatility = 0.16, cycleSensitivity = 1.05,
        riskName = "酒店入住率危机", driver = "assets", synergy = {brandBonus = 0.012, rentalIncomeBonus = 0.006},
        unlock = {netAssets = 30000, completedProjects = 2},
    },
    tourism_culture = industry {
        sector = "consumer_tourism", name = "景区古镇与文创节庆", type = "tourism",
        desc = "运营景区、古镇、营地、文创产品和节庆活动，收益高波动且依赖客流。",
        investment = 17000, revenueRate = 0.032, margin = 0.24, riskRate = 0.035, volatility = 0.20, cycleSensitivity = 1.15,
        riskName = "景区客流与活动安全危机", driver = "assets", synergy = {brandBonus = 0.018},
        unlock = {netAssets = 36000, completedProjects = 3, prerequisite = "rural_resort"},
    },
}

GDI.INDUSTRY_ORDER = {
    "prefab_materials", "recycled_materials", "smart_home", "home_brand_mall", "property_facility", "urban_renewal_ops", "planning_design",
    "science_park", "logistics_cold_chain", "data_center", "senior_care", "rural_resort", "parking_underground", "venue_complex",
    "asset_management", "urban_renewal_advisory", "talent_housing", "convention_operations",
    "distributed_energy", "carbon_management", "district_energy",
    "real_estate_fund", "finance_lease", "amc_equity", "amc_debt",
    "community_retail", "hotel_brands", "tourism_culture",
}

local function roundMoney(value)
    return math.floor((value or 0) * 100 + 0.5) / 100
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function GDI.CreateDefaultData()
    return {
        version = GDI.DATA_VERSION,
        businesses = {},
        riskControl = 50,
        totalInvested = 0,
        totalRevenue = 0,
        totalExpense = 0,
        totalProfit = 0,
        lastMonthlyRevenue = 0,
        lastMonthlyExpense = 0,
        lastMonthlyProfit = 0,
        liquidityStressMonths = 0,
        activeLiquidityCrisis = nil,
        crisisCount = 0,
        history = {},
        revision = 0,
        settlementPeriod = nil,
        manualCompanyCount = 0,
        manualLastMonthlyRevenue = 0,
        manualLastMonthlyExpense = 0,
        manualLastMonthlyProfit = 0,
    }
end

function GDI.EnsureFields(GD)
    local group = GD.group or {}
    if type(group.diversification) ~= "table" then
        group.diversification = GDI.CreateDefaultData()
    end
    local data = group.diversification
    data.version = GDI.DATA_VERSION
    data.businesses = data.businesses or {}
    data.riskControl = clamp(tonumber(data.riskControl) or 50, 0, 100)
    data.totalInvested = data.totalInvested or 0
    data.totalRevenue = data.totalRevenue or 0
    data.totalExpense = data.totalExpense or 0
    data.totalProfit = data.totalProfit or 0
    data.lastMonthlyRevenue = data.lastMonthlyRevenue or 0
    data.lastMonthlyExpense = data.lastMonthlyExpense or 0
    data.lastMonthlyProfit = data.lastMonthlyProfit or 0
    data.liquidityStressMonths = data.liquidityStressMonths or 0
    data.crisisCount = data.crisisCount or 0
    data.history = data.history or {}
    data.revision = data.revision or 0
    data.settlementPeriod = data.settlementPeriod or nil
    data.manualCompanyCount = data.manualCompanyCount or 0
    data.manualLastMonthlyRevenue = data.manualLastMonthlyRevenue or 0
    data.manualLastMonthlyExpense = data.manualLastMonthlyExpense or 0
    data.manualLastMonthlyProfit = data.manualLastMonthlyProfit or 0
    local manualCompanyCount = 0
    for industryId, business in pairs(data.businesses) do
        local def = GDI.INDUSTRIES[industryId]
        if type(business) == "table" and def then
            business.industryId = industryId
            business.level = clamp(math.floor(tonumber(business.level) or 1), 1, def.maxLevel)
            business.strategy = GDI.STRATEGIES[business.strategy] and business.strategy or "steady"
            business.invested = business.invested or def.investment
            business.assetValue = business.assetValue or roundMoney((business.invested or 0) * def.assetRatio)
            business.totalRevenue = business.totalRevenue or 0
            business.totalExpense = business.totalExpense or 0
            business.totalProfit = business.totalProfit or 0
            business.lastRevenue = business.lastRevenue or 0
            business.lastExpense = business.lastExpense or 0
            business.lastProfit = business.lastProfit or 0
            business.active = business.active ~= false
            GIO.EnsureBusiness(def, business)
            manualCompanyCount = manualCompanyCount + 1
        end
    end
    data.manualCompanyCount = manualCompanyCount
    GD.group = group
    return data
end

local function memberMap(group)
    local map = {}
    for _, member in ipairs(group.members or {}) do
        if member.active ~= false and (member.ownershipRatio or 0) > 0 then
            map[tostring(member.companyId)] = member
        end
    end
    return map
end

local function companyState(GD, record)
    if tostring(record.id) == tostring(GD.activeCompanyId) and GD.company then
        return {
            company = GD.company,
            projects = GD.projects or {},
            fixedAssets = GD.fixedAssets or {},
            rentalListings = GD.rentalListings or {},
        }
    end
    return record.state or {}
end

function GDI.BuildOperatingSnapshot(GD)
    local group = GD.group or {}
    local members = memberMap(group)
    local snapshot = {
        activeMembers = 0,
        activeProjects = 0,
        completedProjects = 0,
        fixedAssetValue = 0,
        rentalAssetValue = 0,
        monthlyRent = 0,
        companyEquityValue = 0,
        industryAssetValue = 0,
        activeBusinessCount = 0,
    }
    for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
        local member = members[tostring(record.id)]
        if member then
            snapshot.activeMembers = snapshot.activeMembers + 1
            local state = companyState(GD, record)
            local company = state.company or {}
            local companyValue = math.max(record.totalAssets or 0, company.totalAssets or 0,
                company.governance and (company.governance.lastValuation or 0) or 0,
                company.registeredCapital or 0)
            snapshot.companyEquityValue = snapshot.companyEquityValue + companyValue * (member.ownershipRatio or 0)
            for _, project in ipairs(state.projects or {}) do
                local status = project.status or ""
                if status == "design" or status == "construction" or status == "presale"
                    or status == "pending_settlement" or status == "pending_completion" then
                    snapshot.activeProjects = snapshot.activeProjects + 1
                end
                if status == "completed" or status == "delivery" or status == "operations"
                    or status == "mature" or status == "sold_off" then
                    snapshot.completedProjects = snapshot.completedProjects + 1
                end
            end
            local listedProjects = {}
            for _, listing in ipairs(state.rentalListings or {}) do
                if listing.status == "leased" or listing.status == "rented" or listing.isRented == true then
                    snapshot.monthlyRent = snapshot.monthlyRent + (listing.actualRent or listing.targetRent or 0)
                    if listing.projectId then listedProjects[tostring(listing.projectId)] = true end
                end
            end
            for _, asset in ipairs(state.fixedAssets or {}) do
                local value = asset.currentValue or asset.marketValue or asset.bookValue or 0
                snapshot.fixedAssetValue = snapshot.fixedAssetValue + value
                if asset.isListedForRent or listedProjects[tostring(asset.projectId or "")] then
                    snapshot.rentalAssetValue = snapshot.rentalAssetValue + value
                end
            end
        end
    end
    local data = GDI.EnsureFields(GD)
    for _, business in pairs(data.businesses) do
        if business.active ~= false then
            snapshot.industryAssetValue = snapshot.industryAssetValue + (business.assetValue or 0)
            snapshot.activeBusinessCount = snapshot.activeBusinessCount + 1
        end
    end
    snapshot.groupTotalAssets = (group.cash or 0) + snapshot.companyEquityValue + snapshot.industryAssetValue
    snapshot.groupNetAssets = snapshot.groupTotalAssets - (group.totalDebt or 0)
    snapshot.groupDebtRatio = (group.totalDebt or 0) / math.max(1, snapshot.groupTotalAssets)
    return snapshot
end

local function unlockRequirements(def, data, snapshot)
    local unlock = def.unlock or {}
    local requirements = {}
    local ok = true
    local function add(label, current, required, formatter)
        if not required or required <= 0 then return end
        local met = current >= required
        requirements[#requirements + 1] = {
            label = label,
            current = current,
            required = required,
            met = met,
            text = formatter and formatter(current, required) or (tostring(math.floor(current)) .. "/" .. tostring(required)),
        }
        if not met then ok = false end
    end
    add("集团净资产", snapshot.groupNetAssets, unlock.netAssets, function(current, required)
        return string.format("%.0f万/%.0f万", current, required)
    end)
    add("稳定租金资产", snapshot.rentalAssetValue, unlock.rentalAssets, function(current, required)
        return string.format("%.0f万/%.0f万", current, required)
    end)
    add("成员公司", snapshot.activeMembers, unlock.members)
    add("在建项目", snapshot.activeProjects, unlock.activeProjects)
    add("已完成项目", snapshot.completedProjects, unlock.completedProjects)
    add("集团风控", data.riskControl, unlock.riskControl)
    if unlock.prerequisite then
        local prerequisite = data.businesses[unlock.prerequisite]
        local met = prerequisite ~= nil and prerequisite.active ~= false
        local prerequisiteDef = GDI.INDUSTRIES[unlock.prerequisite]
        requirements[#requirements + 1] = {
            label = "前置产业", current = met and 1 or 0, required = 1, met = met,
            text = prerequisiteDef and prerequisiteDef.name or unlock.prerequisite,
        }
        if not met then ok = false end
    end
    return ok, requirements
end

function GDI.GetUnlockStatus(GD, industryId, snapshot)
    local def = GDI.INDUSTRIES[industryId]
    if not def then return false, "未知产业赛道", {} end
    if not GD.group or GD.group.active ~= true then return false, "请先组建集团", {} end
    local data = GDI.EnsureFields(GD)
    snapshot = snapshot or GDI.BuildOperatingSnapshot(GD)
    local ok, requirements = unlockRequirements(def, data, snapshot)
    if ok then return true, "已满足创办条件", requirements end
    local missing = {}
    for _, req in ipairs(requirements) do
        if not req.met then missing[#missing + 1] = req.label .. " " .. req.text end
    end
    return false, "尚需：" .. table.concat(missing, "；"), requirements
end

function GDI.GetUpgradeCost(industryId, currentLevel)
    local def = GDI.INDUSTRIES[industryId]
    if not def then return 0 end
    currentLevel = clamp(math.floor(tonumber(currentLevel) or 1), 1, def.maxLevel)
    return math.floor(def.investment * (0.55 + currentLevel * 0.18))
end

local function invalidateSynergy(data)
    data.revision = (data.revision or 0) + 1
end

local synergyCache = {data = nil, revision = -1, companyId = nil, result = nil}

function GDI.Establish(GD, industryId)
    local def = GDI.INDUSTRIES[industryId]
    if not def then return false, "未知产业赛道" end
    local data = GDI.EnsureFields(GD)
    if data.businesses[industryId] then return false, "该产业已经成立" end
    local unlocked, reason = GDI.GetUnlockStatus(GD, industryId)
    if not unlocked then return false, reason end
    if (GD.group.cash or 0) < def.investment then
        return false, "集团现金不足，需要" .. tostring(def.investment) .. "万元"
    end
    GD.group.cash = GD.group.cash - def.investment
    data.businesses[industryId] = {
        industryId = industryId,
        level = 1,
        strategy = "steady",
        active = true,
        invested = def.investment,
        assetValue = roundMoney(def.investment * def.assetRatio),
        totalRevenue = 0,
        totalExpense = 0,
        totalProfit = 0,
        lastRevenue = 0,
        lastExpense = 0,
        lastProfit = 0,
        establishedYear = GD.year,
        establishedMonth = GD.month,
        companyKind = "industry",
        operationMode = "manual",
        playerControlGranted = true,
        settlementMode = "manual_company",
        settlementPeriod = nil,
    }
    GIO.EnsureBusiness(def, data.businesses[industryId])
    data.businesses[industryId].companyCash = roundMoney(def.investment * (1 - def.assetRatio))
    data.businesses[industryId].registeredCapital = def.investment
    data.businesses[industryId].totalCapitalInjected = def.investment
    data.manualCompanyCount = (data.manualCompanyCount or 0) + 1
    data.totalInvested = data.totalInvested + def.investment
    invalidateSynergy(data)
    GD.AddEvent("集团成立“" .. def.name .. "”，首期投资" .. tostring(def.investment) .. "万元", "success")
    print("[GROUP-DIVERSIFY] establish id=" .. industryId .. " investment=" .. tostring(def.investment)
        .. " groupCash=" .. tostring(GD.group.cash))
    return true, "产业成立成功"
end

function GDI.Upgrade(GD, industryId)
    local def = GDI.INDUSTRIES[industryId]
    local data = GDI.EnsureFields(GD)
    local business = data.businesses[industryId]
    if not def or not business then return false, "产业尚未成立" end
    if business.level >= def.maxLevel then return false, "产业已达到最高等级" end
    local cost = GDI.GetUpgradeCost(industryId, business.level)
    if (GD.group.cash or 0) < cost then return false, "集团现金不足，升级需要" .. tostring(cost) .. "万元" end
    GD.group.cash = GD.group.cash - cost
    business.level = business.level + 1
    business.invested = business.invested + cost
    business.assetValue = roundMoney((business.assetValue or 0) + cost * def.assetRatio)
    if business.settlementMode == "manual_company" then
        business.companyCash = roundMoney((business.companyCash or 0) + cost * (1 - def.assetRatio))
        business.registeredCapital = roundMoney((business.registeredCapital or 0) + cost)
        business.totalCapitalInjected = roundMoney((business.totalCapitalInjected or 0) + cost)
    end
    data.totalInvested = data.totalInvested + cost
    invalidateSynergy(data)
    GD.AddEvent(def.name .. "升级至" .. tostring(business.level) .. "级，投资" .. tostring(cost) .. "万元", "success")
    print("[GROUP-DIVERSIFY] upgrade id=" .. industryId .. " level=" .. tostring(business.level)
        .. " cost=" .. tostring(cost) .. " groupCash=" .. tostring(GD.group.cash))
    return true, "产业升级成功"
end

function GDI.SetStrategy(GD, industryId, strategyId)
    local data = GDI.EnsureFields(GD)
    local business = data.businesses[industryId]
    if business and business.settlementMode == "manual_company" then
        return false, "产业公司请在手动经营页设置市场、定价、品质与产能方案"
    end
    local strategy = GDI.STRATEGIES[strategyId]
    if not business then return false, "产业尚未成立" end
    if not strategy then return false, "未知经营策略" end
    business.strategy = strategyId
    local def = GDI.INDUSTRIES[industryId]
    GD.AddEvent((def and def.name or "集团产业") .. "调整为“" .. strategy.name .. "”", "info")
    return true, "经营策略已更新"
end

function GDI.StrengthenRiskControl(GD)
    local data = GDI.EnsureFields(GD)
    if data.riskControl >= 100 then return false, "集团风控已达到最高水平" end
    local cost = math.floor(800 + data.riskControl * 18)
    if (GD.group.cash or 0) < cost then return false, "集团现金不足，风控建设需要" .. tostring(cost) .. "万元" end
    GD.group.cash = GD.group.cash - cost
    GD.group.monthlyExpense = (GD.group.monthlyExpense or 0) + cost
    GD.group.annualProfit = (GD.group.annualProfit or 0) - cost
    GD.group.retainedEarnings = math.max(0, (GD.group.retainedEarnings or 0) - cost)
    data.riskControl = math.min(100, data.riskControl + 10)
    GD.AddEvent("集团投入" .. tostring(cost) .. "万元强化风控，风控水平提升至" .. tostring(data.riskControl), "success")
    return true, "集团风控能力已提升"
end

function GDI.ResolveBusinessRisk(GD, industryId)
    local data = GDI.EnsureFields(GD)
    local business = data.businesses[industryId]
    if not business or not business.activeRisk then return false, "该产业当前没有待处置风险" end
    local cost = business.activeRisk.resolveCost or 0
    if (GD.group.cash or 0) < cost then return false, "集团现金不足，风险处置需要" .. tostring(cost) .. "万元" end
    GD.group.cash = GD.group.cash - cost
    GD.group.monthlyExpense = (GD.group.monthlyExpense or 0) + cost
    GD.group.annualProfit = (GD.group.annualProfit or 0) - cost
    GD.group.retainedEarnings = math.max(0, (GD.group.retainedEarnings or 0) - cost)
    local riskName = business.activeRisk.name or "经营风险"
    business.activeRisk = nil
    data.riskControl = math.min(100, data.riskControl + 2)
    GD.AddEvent("集团完成“" .. riskName .. "”专项处置，支出" .. tostring(cost) .. "万元", "success")
    return true, "风险事件已处置"
end

local function isCurrentCompanyMember(GD)
    if not GD.group or GD.group.active ~= true or not GD.activeCompanyId then return false end
    for _, member in ipairs(GD.group.members or {}) do
        if tostring(member.companyId) == tostring(GD.activeCompanyId)
            and member.active ~= false and (member.ownershipRatio or 0) > 0 then
            return true
        end
    end
    return false
end

function GDI.GetSynergy(GD)
    local data = GDI.EnsureFields(GD)
    local companyId = tostring(GD.activeCompanyId or "")
    if synergyCache.data == data and synergyCache.revision == data.revision
        and synergyCache.companyId == companyId and synergyCache.result then
        return synergyCache.result
    end
    local result = {
        constructionCostFactor = 1,
        designSpeedBonus = 0,
        propertyCostFactor = 1,
        propertyCollectionBonus = 0,
        rentalIncomeFactor = 1,
        energyCostFactor = 1,
        salesDemandBonus = 0,
        financingRiskReduction = 0,
        riskReduction = 0,
        brandBonus = 0,
    }
    if not isCurrentCompanyMember(GD) then
        synergyCache = {data = data, revision = data.revision, companyId = companyId, result = result}
        return result
    end
    local constructionReduction = 0
    local propertyReduction = 0
    local energyReduction = 0
    local rentalBonus = 0
    for industryId, business in pairs(data.businesses) do
        local def = GDI.INDUSTRIES[industryId]
        if def and business.active ~= false then
            local synergy = def.synergy or {}
            local operationsFactor = business.settlementMode == "manual_company"
                and GIO.GetSynergyFactor(def, business) or 1
            local scale = (1 + math.max(0, (business.level or 1) - 1) * 0.35) * operationsFactor
            constructionReduction = constructionReduction + (synergy.constructionCostReduction or 0) * scale
            propertyReduction = propertyReduction + (synergy.propertyCostReduction or 0) * scale
            energyReduction = energyReduction + (synergy.energyCostReduction or 0) * scale
            rentalBonus = rentalBonus + (synergy.rentalIncomeBonus or 0) * scale
            result.designSpeedBonus = result.designSpeedBonus + (synergy.designSpeedBonus or 0) * scale
            result.propertyCollectionBonus = result.propertyCollectionBonus + (synergy.propertyCollectionBonus or 0) * scale
            result.salesDemandBonus = result.salesDemandBonus + (synergy.salesDemandBonus or 0) * scale
            result.financingRiskReduction = result.financingRiskReduction + (synergy.financingRiskReduction or 0) * scale
            result.riskReduction = result.riskReduction + (synergy.riskReduction or 0) * scale
            result.brandBonus = result.brandBonus + (synergy.brandBonus or 0) * scale
        end
    end
    result.constructionCostFactor = 1 - clamp(constructionReduction, 0, 0.18)
    result.propertyCostFactor = 1 - clamp(propertyReduction, 0, 0.15)
    result.energyCostFactor = 1 - clamp(energyReduction, 0, 0.18)
    result.rentalIncomeFactor = 1 + clamp(rentalBonus, 0, 0.15)
    result.designSpeedBonus = clamp(result.designSpeedBonus, 0, 0.30)
    result.propertyCollectionBonus = clamp(result.propertyCollectionBonus, 0, 0.08)
    result.salesDemandBonus = clamp(result.salesDemandBonus, 0, 0.08)
    result.financingRiskReduction = clamp(result.financingRiskReduction, 0, 0.08)
    result.riskReduction = clamp(result.riskReduction, 0, 0.08)
    result.brandBonus = clamp(result.brandBonus, 0, 0.08)
    synergyCache = {data = data, revision = data.revision, companyId = companyId, result = result}
    return result
end

function GDI.GetProjectSynergy(GD, project)
    if not project then return GDI.GetSynergy(GD) end
    return GDI.GetSynergy(GD)
end

local function demandFactor(def, snapshot)
    if def.driver == "projects" then
        return 1 + math.min(0.55, snapshot.activeProjects * 0.055 + snapshot.completedProjects * 0.025)
    elseif def.driver == "rentals" then
        return 1 + math.min(0.60, snapshot.rentalAssetValue / 100000 + snapshot.monthlyRent / 5000)
    elseif def.driver == "assets" then
        return 1 + math.min(0.50, snapshot.fixedAssetValue / 150000 + snapshot.completedProjects * 0.015)
    elseif def.driver == "members" then
        return 1 + math.min(0.40, math.max(0, snapshot.activeMembers - 1) * 0.08)
    end
    return 1
end

local function cycleFactor(def, cycle)
    local base = ({boom = 0.15, recovery = 0.06, recession = -0.12, depression = -0.25})[cycle] or 0
    return math.max(0.55, 1 + base * (def.cycleSensitivity or 0.5))
end

function GDI.GetProjectedMonthlyResult(GD, industryId, snapshot)
    local def = GDI.INDUSTRIES[industryId]
    local data = GDI.EnsureFields(GD)
    local business = data.businesses[industryId]
    if not def or not business then return nil end
    if business.settlementMode == "manual_company" then
        return GIO.GetProjectedMonthlyResult(GD, def, business)
    end
    snapshot = snapshot or GDI.BuildOperatingSnapshot(GD)
    local strategy = GDI.STRATEGIES[business.strategy] or GDI.STRATEGIES.steady
    local levelScale = 1 + ((business.level or 1) - 1) * 0.62
    local portfolioBonus = 1 + math.min(0.12, math.max(0, (snapshot.activeBusinessCount or 1) - 1) * 0.01)
    local revenue = (business.invested or def.investment) * def.revenueRate * levelScale
        * demandFactor(def, snapshot) * cycleFactor(def, GD.economy and GD.economy.cycle or "recovery")
        * strategy.revenue * portfolioBonus
    local margin = clamp(def.margin + strategy.margin + (data.riskControl - 50) * 0.0008, 0.04, 0.65)
    local expense = revenue * (1 - margin) + def.fixedCost * (1 + ((business.level or 1) - 1) * 0.35)
    return {revenue = roundMoney(revenue), expense = roundMoney(expense), profit = roundMoney(revenue - expense)}
end

local function createRiskEvent(GD, data, def, business, riskChance)
    if business.activeRisk or math.random() >= riskChance then return false end
    local invested = business.invested or def.investment
    local monthlyLoss = math.max(20, math.floor(invested * (0.0025 + def.riskRate * 0.08)))
    local duration = math.random(2, 5)
    business.activeRisk = {
        name = def.riskName or "经营风险事件",
        monthsLeft = duration,
        totalMonths = duration,
        monthlyLoss = monthlyLoss,
        resolveCost = math.floor(monthlyLoss * duration * 0.75),
        startedYear = GD.year,
        startedMonth = GD.month,
    }
    data.crisisCount = data.crisisCount + 1
    GD.AddEvent("【集团产业风险】" .. def.name .. "发生“" .. business.activeRisk.name .. "”，需尽快处置", "danger")
    print("[GROUP-DIVERSIFY] risk id=" .. tostring(business.industryId)
        .. " chance=" .. string.format("%.4f", riskChance) .. " duration=" .. tostring(duration))
    return true
end

local function hasFinancialBusiness(data)
    for industryId, business in pairs(data.businesses) do
        local def = GDI.INDUSTRIES[industryId]
        if def and def.type == "financial" and business.active ~= false then return true end
    end
    return false
end

function GDI.ResolveLiquidityCrisis(GD)
    local data = GDI.EnsureFields(GD)
    if not data.activeLiquidityCrisis then return false, "集团当前没有流动性危机" end
    local snapshot = GDI.BuildOperatingSnapshot(GD)
    local monthlyFixed = 0
    for industryId, business in pairs(data.businesses) do
        local def = GDI.INDUSTRIES[industryId]
        if def and business.active ~= false then monthlyFixed = monthlyFixed + def.fixedCost * (business.level or 1) end
    end
    if (GD.group.cash or 0) < math.max(1000, monthlyFixed * 3) then
        return false, "集团现金储备仍不足，至少需要覆盖三个月产业固定支出"
    end
    if snapshot.groupDebtRatio > 0.68 then return false, "集团资产负债率仍高于68%" end
    data.activeLiquidityCrisis = nil
    data.liquidityStressMonths = 0
    data.riskControl = math.min(100, data.riskControl + 3)
    GD.AddEvent("集团完成流动性重整，产业经营恢复正常", "success")
    return true, "集团流动性危机已解除"
end

function GDI.MonthlyUpdate(GD, completedYear, completedMonth)
    if not GD.group or GD.group.active ~= true then return nil end
    local data = GDI.EnsureFields(GD)
    local settlementYear = completedYear or GD.year or 0
    local settlementMonth = completedMonth or GD.month or 0
    local period = tostring(settlementYear) .. "-" .. tostring(settlementMonth)
    if data.settlementPeriod == period then
        return {
            revenue = data.lastMonthlyRevenue or 0,
            expense = data.lastMonthlyExpense or 0,
            profit = data.lastMonthlyProfit or 0,
            activeCount = data.manualCompanyCount or 0,
            skipped = true,
        }
    end
    local snapshot = GDI.BuildOperatingSnapshot(GD)
    local totalRevenue, totalExpense = 0, 0
    local manualRevenue, manualExpense = 0, 0
    local activeCount = 0
    local crisisPenalty = data.activeLiquidityCrisis and 0.76 or 1

    for _, industryId in ipairs(GDI.INDUSTRY_ORDER) do
        local def = GDI.INDUSTRIES[industryId]
        local business = data.businesses[industryId]
        if def and business and business.active ~= false then
            activeCount = activeCount + 1
            if business.settlementMode == "manual_company" then
                local result = GIO.MonthlyUpdateBusiness(GD, def, business, crisisPenalty)
                manualRevenue = manualRevenue + (result.revenue or 0)
                manualExpense = manualExpense + (result.expense or 0)
            else
                local projected = GDI.GetProjectedMonthlyResult(GD, industryId, snapshot)
                local variance = 1 + (math.random() * 2 - 1) * def.volatility
                local revenue = roundMoney(projected.revenue * variance * crisisPenalty)
                local expense = projected.expense
                if business.activeRisk then
                    expense = expense + (business.activeRisk.monthlyLoss or 0)
                    business.activeRisk.monthsLeft = math.max(0, (business.activeRisk.monthsLeft or 1) - 1)
                    if business.activeRisk.monthsLeft <= 0 then
                        GD.AddEvent(def.name .. "的“" .. (business.activeRisk.name or "经营风险") .. "”影响已自然消退", "info")
                        business.activeRisk = nil
                    end
                end
                expense = roundMoney(expense)
                local profit = roundMoney(revenue - expense)
                business.lastRevenue = revenue
                business.lastExpense = expense
                business.lastProfit = profit
                business.totalRevenue = business.totalRevenue + revenue
                business.totalExpense = business.totalExpense + expense
                business.totalProfit = business.totalProfit + profit
                business.assetValue = roundMoney(math.max(0, (business.assetValue or 0) * (1 + clamp(profit / math.max(1, business.invested) * 0.08, -0.006, 0.004))))
                totalRevenue = totalRevenue + revenue
                totalExpense = totalExpense + expense

                local strategy = GDI.STRATEGIES[business.strategy] or GDI.STRATEGIES.steady
                local leverageRisk = 1 + math.max(0, snapshot.groupDebtRatio - 0.45) * 2.5
                local controlRisk = 1 + math.max(0, 60 - data.riskControl) / 80
                local riskChance = def.riskRate * strategy.risk * leverageRisk * controlRisk
                createRiskEvent(GD, data, def, business, riskChance)
            end
        end
    end

    totalRevenue = totalRevenue
    totalExpense = totalExpense
    data.manualLastMonthlyRevenue = roundMoney(manualRevenue)
    data.manualLastMonthlyExpense = roundMoney(manualExpense)
    data.manualLastMonthlyProfit = roundMoney(manualRevenue - manualExpense)
    local profit = roundMoney(totalRevenue - totalExpense)
    GD.group.cash = (GD.group.cash or 0) + profit
    GD.group.monthlyIncome = (GD.group.monthlyIncome or 0) + totalRevenue
    GD.group.monthlyExpense = (GD.group.monthlyExpense or 0) + totalExpense
    GD.group.annualProfit = (GD.group.annualProfit or 0) + profit
    GD.group.retainedEarnings = math.max(0, (GD.group.retainedEarnings or 0) + profit)
    data.lastMonthlyRevenue = totalRevenue
    data.lastMonthlyExpense = totalExpense
    data.lastMonthlyProfit = profit
    data.totalRevenue = data.totalRevenue + totalRevenue
    data.totalExpense = data.totalExpense + totalExpense
    data.totalProfit = data.totalProfit + profit

    snapshot = GDI.BuildOperatingSnapshot(GD)
    local fixedCoverage = totalExpense > 0 and math.max(0, GD.group.cash or 0) / totalExpense or 99
    local stressed = (GD.group.cash or 0) < 0
        or snapshot.groupDebtRatio > 0.70
        or (hasFinancialBusiness(data) and fixedCoverage < 0.75)
    data.liquidityStressMonths = stressed and (data.liquidityStressMonths + 1) or math.max(0, data.liquidityStressMonths - 1)
    if not data.activeLiquidityCrisis and data.liquidityStressMonths >= 2 then
        data.activeLiquidityCrisis = {
            startedYear = GD.year,
            startedMonth = GD.month,
            months = 0,
            reason = (GD.group.cash or 0) < 0 and "集团现金为负"
                or (snapshot.groupDebtRatio > 0.70 and "资产负债率过高" or "金融业务流动性覆盖不足"),
        }
        data.crisisCount = data.crisisCount + 1
        GD.AddEvent("【集团流动性危机】" .. data.activeLiquidityCrisis.reason .. "，产业收入和融资能力受到冲击", "danger")
        print("[GROUP-DIVERSIFY] liquidity crisis reason=" .. data.activeLiquidityCrisis.reason
            .. " cash=" .. tostring(GD.group.cash) .. " debtRatio=" .. string.format("%.4f", snapshot.groupDebtRatio))
    end
    if data.activeLiquidityCrisis then
        data.activeLiquidityCrisis.months = (data.activeLiquidityCrisis.months or 0) + 1
        local emergencyCost = math.max(50, math.floor((GD.group.totalDebt or 0) * 0.001))
        GD.group.cash = GD.group.cash - emergencyCost
        GD.group.monthlyExpense = GD.group.monthlyExpense + emergencyCost
        GD.group.annualProfit = GD.group.annualProfit - emergencyCost
        GD.group.retainedEarnings = math.max(0, GD.group.retainedEarnings - emergencyCost)
        data.lastMonthlyExpense = data.lastMonthlyExpense + emergencyCost
        data.lastMonthlyProfit = data.lastMonthlyProfit - emergencyCost
        data.totalExpense = data.totalExpense + emergencyCost
        data.totalProfit = data.totalProfit - emergencyCost
    end

    data.settlementPeriod = period
    data.history[#data.history + 1] = {
        year = settlementYear, month = settlementMonth, revenue = data.lastMonthlyRevenue,
        expense = data.lastMonthlyExpense, profit = data.lastMonthlyProfit,
        activeCount = activeCount, riskControl = data.riskControl,
    }
    while #data.history > 36 do table.remove(data.history, 1) end
    print("[GROUP-DIVERSIFY] monthly year=" .. tostring(settlementYear) .. " month=" .. tostring(settlementMonth)
        .. " active=" .. tostring(activeCount) .. " revenue=" .. tostring(data.lastMonthlyRevenue)
        .. " expense=" .. tostring(data.lastMonthlyExpense) .. " profit=" .. tostring(data.lastMonthlyProfit)
        .. " groupCash=" .. tostring(GD.group.cash))
    return {revenue = data.lastMonthlyRevenue, expense = data.lastMonthlyExpense, profit = data.lastMonthlyProfit, activeCount = activeCount}
end

function GDI.GetSummary(GD, snapshot)
    local data = GDI.EnsureFields(GD)
    snapshot = snapshot or GDI.BuildOperatingSnapshot(GD)
    local activeCount, riskCount = 0, 0
    local manualCompanies = 0
    local sectorCounts = {}
    for industryId, business in pairs(data.businesses) do
        local def = GDI.INDUSTRIES[industryId]
        if def and business.active ~= false then
            activeCount = activeCount + 1
            sectorCounts[def.sector] = (sectorCounts[def.sector] or 0) + 1
            if business.activeRisk then riskCount = riskCount + 1 end
            if business.settlementMode == "manual_company" then manualCompanies = manualCompanies + 1 end
        end
    end
    return {
        activeCount = activeCount,
        manualCompanyCount = manualCompanies,
        sectorCounts = sectorCounts,
        industryAssetValue = snapshot.industryAssetValue,
        lastMonthlyRevenue = data.lastMonthlyRevenue,
        lastMonthlyExpense = data.lastMonthlyExpense,
        lastMonthlyProfit = data.lastMonthlyProfit,
        totalProfit = data.totalProfit,
        riskControl = data.riskControl,
        activeRiskCount = riskCount,
        hasLiquidityCrisis = data.activeLiquidityCrisis ~= nil,
        liquidityCrisis = data.activeLiquidityCrisis,
        rentalAssetValue = snapshot.rentalAssetValue,
        groupNetAssets = snapshot.groupNetAssets,
    }
end

function GDI.GetSectorIndustries(sectorId)
    local result = {}
    for _, industryId in ipairs(GDI.INDUSTRY_ORDER) do
        local def = GDI.INDUSTRIES[industryId]
        if def and def.sector == sectorId then result[#result + 1] = {id = industryId, def = def} end
    end
    return result
end

return GDI
