-- ============================================================================
-- Finance.lua - 金融系统 (9.1~9.6)
-- 融资产品 / 现金流管理 / 预售资金监管 / 三条红线 / 税务筹划 / 存款系统
-- ============================================================================

local FN = {}
local GV = require("Governance")

-- ============================================================================
-- 9.1 融资产品全图谱
-- ============================================================================
FN.PRODUCTS = {
    bank_dev   = {
        name = "银行流动资金贷款", desc = "以企业资产为担保的流动资金贷款",
        rateRange = {3, 5}, months = 36, minQual = 0, minCredit = 60,
        disburseMonths = 1, maxRatio = 0.40, needProject = false,
        durationRange = {1, 60},  -- 可选期限范围(月)
        icon = "🏦",
    },
    trust      = {
        name = "信托融资", desc = "快速到账的非标融资",
        rateRange = {4, 8}, months = 18, minQual = 1, minCredit = 50,
        disburseMonths = 1, maxRatio = 0.30, needProject = false,
        durationRange = {1, 60},
        icon = "📜",
    },
    usd_bond   = {
        name = "美元债", desc = "境外发行美元计价债券，周期长利率低",
        rateRange = {4, 8}, months = 60, minQual = 2, minCredit = 70,
        disburseMonths = 6, maxRatio = 0.20, needProject = false,
        durationRange = {1, 120},  -- 债券类可达120个月
        icon = "💵",
    },
    corp_bond  = {
        name = "发行债券", desc = "以公司总资产为担保发行的债券，利率低周期灵活",
        rateRange = {2, 6}, months = 60, minQual = 1, minCredit = 65,
        disburseMonths = 2, maxRatio = 0.25, needProject = false,
        durationRange = {1, 120},  -- 债券类可达120个月
        icon = "📊",
    },
    bridge     = {
        name = "民间过桥", desc = "紧急资金周转，到账快",
        rateRange = {4, 8}, months = 6, minQual = 0, minCredit = 0,
        disburseMonths = 0, maxRatio = 0.15, needProject = false,
        durationRange = {1, 60},
        icon = "⚡",
    },
    supply_abs = {
        name = "供应链ABS", desc = "以应收账款为底层资产的证券化产品",
        rateRange = {4, 8}, months = 24, minQual = 1, minCredit = 65,
        disburseMonths = 2, maxRatio = 0.20, needProject = true,
        durationRange = {1, 60},
        icon = "🔗",
    },
    coinvest   = {
        name = "员工跟投", desc = "管理层与核心员工按比例跟投项目",
        rateRange = {0, 0}, months = 0, minQual = 0, minCredit = 0,
        disburseMonths = 0, maxRatio = 0.05, needProject = true,
        isCoinvest = true,
        icon = "👥",
    },
}
FN.PRODUCT_ORDER = {"bank_dev", "trust", "usd_bond", "corp_bond", "bridge", "supply_abs", "coinvest"}

-- 还款方式选项
FN.REPAY_METHODS = {
    {id = "interest_monthly", name = "按月付息到期还本", desc = "每月支付利息，到期一次性归还本金"},
    {id = "bullet",           name = "到期还本付息",     desc = "到期一次性支付本金+全部利息"},
}

-- ============================================================================
-- 9.3 预售资金监管里程碑
-- ============================================================================
FN.ESCROW_MILESTONES = {
    {name = "正负零", progressThreshold = 0.15, releaseRatio = 0.20},
    {name = "封顶",   progressThreshold = 0.50, releaseRatio = 0.50},
    {name = "落架",   progressThreshold = 0.75, releaseRatio = 0.80},
    {name = "竣工",   progressThreshold = 1.00, releaseRatio = 1.00},
}
FN.MISAPPROPRIATION_AUDIT_CHANCE = 0.30  -- 挪用被审计发现概率

-- ============================================================================
-- 9.4 三条红线
-- ============================================================================
FN.RED_LINE_THRESHOLDS = {
    assetLiability = 0.70,  -- 剔除预收款的资产负债率 ≤70%
    netDebt        = 1.00,  -- 净负债率 ≤100%
    cashShortDebt  = 1.00,  -- 现金短债比 ≥1
}
FN.RED_LINE_TIERS = {
    {name = "绿档", violations = 0, debtGrowthCap = 0.15, color = "Success"},
    {name = "黄档", violations = 1, debtGrowthCap = 0.10, color = "Warning"},
    {name = "橙档", violations = 2, debtGrowthCap = 0.05, color = "Danger"},
    {name = "红档", violations = 3, debtGrowthCap = 0.00, color = "Danger"},
}

-- ============================================================================
-- 9.5 简化税制：项目毛利润×20% + 自持租金×10%
-- ============================================================================
-- 项目清盘结算税 = (销售总收入 - 土地成本 - 前期费用 - 建设费用) × 20%
FN.PROJECT_PROFIT_TAX_RATE = 0.20
-- 自持物业租金税 = 年租金收入 × 15%（按月均摊缴纳）
FN.RENTAL_TAX_RATE = 0.15

-- 税务筹划方案（简化：仅保留降低税率的通用方案）
FN.TAX_PLANS = {
    {id = "spv",      name = "项目公司架构",   desc = "通过设立项目公司(SPV)实现独立核算，降低有效税率",
     savingsRate = 0.10, risk = "中", riskVariant = "warning", cost = 150},
    {id = "allocate", name = "成本分摊优化",   desc = "合理分摊公共配套成本到各开发项目，提高可扣除成本",
     savingsRate = 0.08, risk = "低", riskVariant = "success", cost = 80},
}

-- ============================================================================
-- 9.6 存款系统
-- ============================================================================
FN.DEPOSIT_TYPES = {
    {id = "demand",  name = "活期存款",   rate = 0.35,  minAmount = 0,    minMonths = 0},
    {id = "fixed3",  name = "3个月定期",  rate = 1.50,  minAmount = 500,  minMonths = 3},
    {id = "fixed6",  name = "6个月定期",  rate = 2.00,  minAmount = 1000, minMonths = 6},
    {id = "fixed12", name = "1年定期",    rate = 2.50,  minAmount = 2000, minMonths = 12},
}

-- 存款金额档位（万元）
FN.DEPOSIT_AMOUNTS = {500, 1000, 2000, 5000, 10000}

-- ============================================================================
-- 9.2 现金流安全线
-- ============================================================================
FN.CASH_SAFETY_LINE = 3000  -- 万元

-- ============================================================================
-- 9.7 并购目标池
-- ============================================================================
FN.MA_TEMPLATES = {
    {name = "嘉和小镇开发", type = "在建项目", basePrice = 15000, desc = "已完成60%主体结构，配套学校",
     effect = "assets", assetValue = 18000, monthlyIncome = 0, costReduction = 0, qualBoost = 0},
    {name = "滨河物业公司", type = "物业公司", basePrice = 5000, desc = "管理面积120万平，年利润800万",
     effect = "income", assetValue = 6000, monthlyIncome = 67, costReduction = 0, qualBoost = 0},
    {name = "诚信建筑工程", type = "施工企业", basePrice = 8000, desc = "一级施工资质，可降低建安成本",
     effect = "cost", assetValue = 8000, monthlyIncome = 0, costReduction = 0.05, qualBoost = 0},
    {name = "汇鑫设计院", type = "设计公司", basePrice = 3000, desc = "甲级设计资质，提升产品溢价",
     effect = "income", assetValue = 3500, monthlyIncome = 30, costReduction = 0, qualBoost = 0},
    {name = "中恒装饰集团", type = "装修公司", basePrice = 4000, desc = "精装修一体化，降低装修成本15%",
     effect = "cost", assetValue = 4500, monthlyIncome = 0, costReduction = 0.03, qualBoost = 0},
    {name = "盛达地产(三级)", type = "地产公司", basePrice = 20000, desc = "三级开发资质，收购可提升资质",
     effect = "qual", assetValue = 22000, monthlyIncome = 100, costReduction = 0, qualBoost = 1},
    {name = "万城商业广场", type = "商业地产", basePrice = 25000, desc = "已运营购物中心，年租金收入2000万",
     effect = "income", assetValue = 28000, monthlyIncome = 167, costReduction = 0, qualBoost = 0},
    {name = "安居物流园", type = "物流园区", basePrice = 10000, desc = "仓储物流配套，降低供应链成本",
     effect = "cost", assetValue = 12000, monthlyIncome = 50, costReduction = 0.02, qualBoost = 0},
}

-- ============================================================================
-- 9.8 IPO 条件
-- ============================================================================
FN.IPO_CONDITIONS = {
    {id = "capital",    name = "注册资本 >= 5000万", check = function(co) return co.registeredCapital >= 5000 end},
    {id = "qual",       name = "资质等级 >= 一级",    check = function(co) return co.qualification >= 3 end},
    {id = "builtArea",  name = "累计竣工 >= 30万平",  check = function(co) return co.totalBuiltArea >= 300000 end},
    {id = "credit",     name = "信用评分 >= 85分",    check = function(co) return co.creditScore >= 85 end},
    {id = "projects",   name = "已完成 >= 3个项目",   check = function(co, GD)
        local c = 0
        for _, p in ipairs(GD.projects) do
            if p.status == "completed" then c = c + 1 end
        end
        return c >= 3
    end},
    {id = "debt",       name = "负债率 < 70%",        check = function(co) return co.totalAssets > 0 and (co.totalDebt / co.totalAssets < 0.7) end},
}

-- ============================================================================
-- 初始化金融数据
-- ============================================================================
function FN.InitFinanceData()
    return {
        -- 存款
        deposits = {},       -- {type(id), amount, rate, startMonth, months, matured}
        demandBalance = 0,   -- 活期余额(万元)
        totalInterest = 0,   -- 累计利息收入

        -- 监管账户 (key = projectId)
        escrowAccounts = {},  -- {[projectId] = {total, released, frozen, milestoneIdx}}

        -- 三条红线
        redLine = {
            assetLiability = 0,   -- 剔除预收款资产负债率
            netDebt = 0,          -- 净负债率
            cashShortDebt = 999,  -- 现金短债比
            tier = "绿档",
            tierIdx = 1,
            violations = 0,
            debtGrowthCap = 0.15,
        },

        -- 现金流
        cashFlow = {
            monthlyIn = 0,
            monthlyOut = 0,
            netFlow = 0,
            forecast3m = 0,        -- 3个月预测净现金流
            safetyLine = FN.CASH_SAFETY_LINE,
            belowSafety = false,
        },

        -- 税务（简化税制：项目毛利润×20% + 自持租金×10%）
        tax = {
            projectTaxPaid = 0,    -- 项目清盘结算税累计（毛利润×20%）
            rentalTaxPaid = 0,     -- 自持租金税累计（租金×10%）
            monthlyRentalTax = 0,  -- 当月租金税
            monthlyTaxTotal = 0,   -- 当月总税负
            activePlans = {},      -- 已启用的筹划方案id列表
            totalSavings = 0,      -- 筹划累计节税
            taxHistory = {},       -- 历年纳税记录 {year, projectTax, rentalTax, totalTax}
        },

        -- 员工跟投记录
        coinvestments = {},  -- {projectId, projectName, amount, investMonth, settled, returnAmount}

        -- 年度基数
        yearStartDebt = 0,
    }
end

-- ============================================================================
-- 旧存档兼容
-- ============================================================================
function FN.EnsureFinanceFields(fin)
    if not fin then return FN.InitFinanceData() end
    -- 补全缺失字段
    if not fin.deposits then fin.deposits = {} end
    if not fin.demandBalance then fin.demandBalance = 0 end
    if not fin.totalInterest then fin.totalInterest = 0 end
    if not fin.escrowAccounts then fin.escrowAccounts = {} end
    if not fin.redLine then
        fin.redLine = {assetLiability=0, netDebt=0, cashShortDebt=999,
            tier="绿档", tierIdx=1, violations=0, debtGrowthCap=0.15}
    end
    if not fin.redLine.tierIdx then fin.redLine.tierIdx = 1 end
    if not fin.cashFlow then
        fin.cashFlow = {monthlyIn=0, monthlyOut=0, netFlow=0, forecast3m=0,
            safetyLine=FN.CASH_SAFETY_LINE, belowSafety=false}
    end
    if not fin.tax then
        fin.tax = {projectTaxPaid=0, rentalTaxPaid=0, monthlyRentalTax=0,
            monthlyTaxTotal=0, activePlans={}, totalSavings=0, taxHistory={}}
    end
    if not fin.tax.activePlans then fin.tax.activePlans = {} end
    if not fin.tax.totalSavings then fin.tax.totalSavings = 0 end
    if not fin.tax.projectTaxPaid then fin.tax.projectTaxPaid = 0 end
    if not fin.tax.rentalTaxPaid then fin.tax.rentalTaxPaid = 0 end
    if not fin.tax.monthlyRentalTax then fin.tax.monthlyRentalTax = 0 end
    if not fin.tax.monthlyTaxTotal then fin.tax.monthlyTaxTotal = 0 end
    if not fin.tax.taxHistory then fin.tax.taxHistory = {} end
    if not fin.yearStartDebt then fin.yearStartDebt = 0 end
    if not fin.coinvestments then fin.coinvestments = {} end
    return fin
end

-- ============================================================================
-- 月度更新（在 GD.MonthlyTick 中 UpdateFinance 之前调用）
-- ============================================================================
function FN.MonthlyUpdate(GD)
    local fin = GD.finance
    if not fin then return end

    FN._UpdateDeposits(GD, fin)
    FN._UpdateEscrow(GD, fin)
    FN._UpdateRedLines(GD, fin)
    FN._UpdateCashFlow(GD, fin)
    FN._UpdateTaxAccruals(GD, fin)

    -- 并购收入（来自已收购的企业）
    if GD.maIncome then
        for _, mi in ipairs(GD.maIncome) do
            GD.company.cash = GD.company.cash + mi.monthly
            GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + mi.monthly
        end
    end
end

-- ============================================================================
-- 项目清盘结算税（项目完成时调用）
-- 税额 = (销售总收入 - 土地成本 - 前期费用 - 建设费用) × 20%
-- 筹划方案可降低有效税率
-- ============================================================================
--- 项目结算税（已废弃，税收统一在清盘结算 ManualClearance 中手动缴纳）
--- 保留函数接口兼容，不再扣除现金
function FN.ProjectSettlementTax(GD, project)
    return 0
end

-- ============================================================================
-- 年度企业所得税汇算清缴（保留接口兼容，简化税制下仅记录年度纳税历史）
-- ============================================================================
function FN.YearlyCorpTaxSettlement(GD)
    local fin = GD.finance
    if not fin then return end
    local tax = fin.tax

    -- 简化税制下不再年度征收企业所得税
    -- 仅记录本年度纳税历史（项目税+租金税的年度累计）
    -- 注意：projectTaxPaid 和 rentalTaxPaid 是总累计，需要与上年比较得出本年增量
    -- 这里简单记录当前累计值，由 YearlyReset 负责标记年度起点
    local yearProjectTax = tax.projectTaxPaid - (tax._yearStartProjectTax or 0)
    local yearRentalTax = tax.rentalTaxPaid - (tax._yearStartRentalTax or 0)

    table.insert(tax.taxHistory, {
        year = GD.year,
        projectTax = yearProjectTax,
        rentalTax = yearRentalTax,
        totalTax = yearProjectTax + yearRentalTax,
    })
end

-- ============================================================================
-- 年度重置（每年1月调用）
-- ============================================================================
function FN.YearlyReset(GD)
    local fin = GD.finance
    if not fin then return end
    fin.yearStartDebt = GD.company.totalDebt

    -- 记录年度起点累计值，用于年末计算本年增量
    local tax = fin.tax
    tax._yearStartProjectTax = tax.projectTaxPaid
    tax._yearStartRentalTax = tax.rentalTaxPaid
end

-- ============================================================================
-- 私有: 存款利息更新
-- ============================================================================
function FN._UpdateDeposits(GD, fin)
    -- 活期利息(月)
    if fin.demandBalance > 0 then
        local demandType = FN.DEPOSIT_TYPES[1] -- demand
        local monthInterest = fin.demandBalance * demandType.rate / 100 / 12
        monthInterest = math.floor(monthInterest * 100) / 100
        if monthInterest > 0 then
            fin.demandBalance = fin.demandBalance + monthInterest
            fin.totalInterest = fin.totalInterest + monthInterest
        end
    end

    -- 定期存款到期检查
    for i = #fin.deposits, 1, -1 do
        local dep = fin.deposits[i]
        if not dep.matured then
            local elapsed = (GD.totalMonths or 0) - dep.startMonth
            if elapsed >= dep.months then
                -- 到期：本金+利息归还cash
                local totalInterest = dep.amount * dep.rate / 100 / 12 * dep.months
                totalInterest = math.floor(totalInterest * 100) / 100
                GD.company.cash = GD.company.cash + dep.amount + totalInterest
                fin.totalInterest = fin.totalInterest + totalInterest
                GD.AddEvent("定期存款到期，本金" .. GD.FormatMoney(dep.amount)
                    .. " + 利息" .. GD.FormatMoney(totalInterest) .. "已入账", "success")
                table.remove(fin.deposits, i)
            end
        end
    end
end

-- ============================================================================
-- 私有: 预售资金监管释放
-- ============================================================================
function FN._UpdateEscrow(GD, fin)
    for _, p in ipairs(GD.projects) do
        local esc = fin.escrowAccounts[p.id]
        if esc and esc.total > 0 and not esc.frozen then
            local progress = 0
            if p.construction then
                progress = math.max(0, math.min(1, (p.construction.progress or 0) / 100))
            end
            if p.status == "delivery" or p.status == "completed" or p.status == "pending_completion" then
                progress = 1.0
            end

            -- 按里程碑释放
            local targetRelease = 0
            local milestoneIdx = esc.milestoneIdx or 0
            for mi, ms in ipairs(FN.ESCROW_MILESTONES) do
                if progress >= ms.progressThreshold and mi > milestoneIdx then
                    targetRelease = math.max(targetRelease, esc.total * ms.releaseRatio)
                    esc.milestoneIdx = mi
                    GD.AddEvent("【" .. p.name .. "】达到" .. ms.name
                        .. "节点，监管资金释放至" .. math.floor(ms.releaseRatio * 100) .. "%", "success")
                end
            end

            if targetRelease > esc.released then
                local releaseAmount = targetRelease - esc.released
                esc.released = targetRelease
                GD.company.cash = GD.company.cash + releaseAmount
                GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + releaseAmount
                if GD.AddLedger then
                    GD.AddLedger("income", "监管释放", p.name .. " 预售监管资金释放", releaseAmount)
                end
            end
        end
    end
end

-- ============================================================================
-- 私有: 三条红线计算
-- ============================================================================
function FN._UpdateRedLines(GD, fin)
    local co = GD.company
    local rl = fin.redLine

    -- 预收账款 = 所有项目未交付的已售金额(简化)
    local presaleRevenue = 0
    for _, p in ipairs(GD.projects) do
        if p.status == "presale" or p.status == "construction" then
            presaleRevenue = presaleRevenue + ((p.sales and p.sales.revenue) or 0)
        end
    end

    -- 短期债务(12个月内到期)
    local shortDebt = 0
    for _, loan in ipairs(GD.loans) do
        if loan.remainMonths <= 12 then
            shortDebt = shortDebt + loan.amount
        end
    end

    -- 1. 剔除预收款资产负债率 = (总负债 - 预收) / (总资产 - 预收)
    local adjLiability = co.totalDebt - presaleRevenue
    local adjAssets = co.totalAssets - presaleRevenue
    if adjAssets > 0 then
        rl.assetLiability = adjLiability / adjAssets
    else
        rl.assetLiability = 0
    end

    -- 2. 净负债率 = (有息负债 - 现金) / 净资产
    local netEquity = co.totalAssets - co.totalDebt
    if netEquity > 0 then
        rl.netDebt = (co.totalDebt - co.cash) / netEquity
    else
        rl.netDebt = co.totalDebt > 0 and 999 or 0
    end

    -- 3. 现金短债比 = 现金 / 短期有息负债
    if shortDebt > 0 then
        rl.cashShortDebt = co.cash / shortDebt
    else
        rl.cashShortDebt = 999  -- 无短债
    end

    -- 计算违规数
    local violations = 0
    if rl.assetLiability > FN.RED_LINE_THRESHOLDS.assetLiability then violations = violations + 1 end
    if rl.netDebt > FN.RED_LINE_THRESHOLDS.netDebt then violations = violations + 1 end
    if rl.cashShortDebt < FN.RED_LINE_THRESHOLDS.cashShortDebt then violations = violations + 1 end
    rl.violations = violations

    -- 确定档位
    local tierIdx = math.min(violations + 1, #FN.RED_LINE_TIERS)
    local tier = FN.RED_LINE_TIERS[tierIdx]
    local oldTier = rl.tier
    rl.tier = tier.name
    rl.tierIdx = tierIdx
    rl.debtGrowthCap = tier.debtGrowthCap

    -- 档位变化提醒
    if oldTier and oldTier ~= rl.tier then
        if tierIdx > 1 then
            GD.AddEvent("三条红线预警：公司降级为【" .. rl.tier .. "】，有息负债增速上限" .. math.floor(rl.debtGrowthCap * 100) .. "%", "danger")
        else
            GD.AddEvent("三条红线达标：公司恢复为【绿档】", "success")
        end
    end
end

-- ============================================================================
-- 私有: 现金流更新
-- ============================================================================
function FN._UpdateCashFlow(GD, fin)
    local cf = fin.cashFlow
    cf.monthlyIn = GD.company.monthlyRevenue
    cf.monthlyOut = GD.company.monthlyExpense
    cf.netFlow = cf.monthlyIn - cf.monthlyOut

    -- 3个月预测(简化: 当前净流量 × 3 + 当前现金)
    cf.forecast3m = GD.company.cash + cf.netFlow * 3

    -- 安全线检查
    local wasBelowSafety = cf.belowSafety
    cf.belowSafety = GD.company.cash < cf.safetyLine
    if cf.belowSafety and not wasBelowSafety then
        GD.AddEvent("现金流预警：账面现金低于安全线(" .. GD.FormatMoney(cf.safetyLine) .. ")!", "danger")
    end
end

-- ============================================================================
-- 私有: 税务预提累计（简化税制：仅自持物业租金×15%）
-- 项目税在清盘结算时一次性缴纳（见 ProjectSettlementTax）
-- ============================================================================
function FN._UpdateTaxAccruals(GD, fin)
    local tax = fin.tax
    local monthlyTax = 0

    -- 自持物业租金税 = 年租金 × 15%，按月均摊
    local rentalTax = 0
    for _, p in ipairs(GD.projects) do
        if p.status == "operations" or p.status == "mature" then
            local ops = p.operations
            if ops and ops.monthlyRentalIncome and ops.monthlyRentalIncome > 0 then
                rentalTax = rentalTax + ops.monthlyRentalIncome * FN.RENTAL_TAX_RATE
            end
        end
    end
    tax.monthlyRentalTax = math.floor(rentalTax * 100) / 100
    tax.rentalTaxPaid = tax.rentalTaxPaid + tax.monthlyRentalTax
    monthlyTax = monthlyTax + tax.monthlyRentalTax

    -- 月度税负汇总
    tax.monthlyTaxTotal = math.floor(monthlyTax * 100) / 100

    -- 税负从现金扣除
    if tax.monthlyTaxTotal > 0 then
        local managed = GV.IsFullManagementEnabled and GV.IsFullManagementEnabled(GD)
        if managed and not GV.SpendManagedCash(GD, tax.monthlyTaxTotal, "CEO托管暂停缴纳月度税费：现金必须保持为正") then
            tax.deferredMonthlyTax = (tax.deferredMonthlyTax or 0) + tax.monthlyTaxTotal
        else
            GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + tax.monthlyTaxTotal
        end
    end
end

-- ============================================================================
-- 玩家操作: 获取可申请融资产品列表
-- ============================================================================
function FN.GetAvailableProducts(GD)
    local co = GD.company
    local fin = GD.finance
    local rl = fin and fin.redLine or {}
    local results = {}

    for _, pid in ipairs(FN.PRODUCT_ORDER) do
        local prod = FN.PRODUCTS[pid]
        local canApply = true
        local reason = ""

        -- 资质检查
        if prod.minQual > 0 and co.qualification < prod.minQual then
            canApply = false
            reason = "资质不足(需" .. ({"三级","二级","一级"})[prod.minQual] .. ")"
        end
        -- 信用检查
        if canApply and prod.minCredit > 0 and co.creditScore < prod.minCredit then
            canApply = false
            reason = "信用分不足(需>=" .. prod.minCredit .. ")"
        end
        -- 红线检查
        if canApply and rl.tier == "红档" and not prod.isCoinvest then
            canApply = false
            reason = "红档企业禁止新增有息负债"
        end
        -- 债务增长检查
        if canApply and fin and fin.yearStartDebt > 0 and not prod.isCoinvest then
            local currentGrowth = (co.totalDebt - fin.yearStartDebt) / fin.yearStartDebt
            if currentGrowth >= (rl.debtGrowthCap or 0.15) then
                canApply = false
                reason = rl.tier .. "年度债务增长已达上限"
            end
        end

        -- 可贷额度
        local maxLoan = math.floor(co.totalAssets * prod.maxRatio - co.totalDebt * prod.maxRatio)
        if maxLoan < 0 then maxLoan = 0 end
        if maxLoan <= 0 and canApply and not prod.isCoinvest then
            canApply = false
            reason = "负债率过高，无可贷额度"
        end

        -- 实际利率(产品利率区间中值 + 特质加成)
        local midRate = (prod.rateRange[1] + prod.rateRange[2]) / 2
        local finBonus = (co.traitEffects and co.traitEffects.financeCostBonus) or 0
        local effectiveRate = math.max(1.0, midRate + finBonus)

        table.insert(results, {
            id = pid,
            product = prod,        -- 原始产品定义引用
            name = prod.name,
            desc = prod.desc,
            icon = prod.icon,
            rateRange = prod.rateRange,
            effectiveRate = effectiveRate,
            months = prod.months,
            maxLoan = maxLoan,
            disburseMonths = prod.disburseMonths,
            eligible = canApply,   -- 统一使用 eligible
            reason = reason,
            needProject = prod.needProject,
            isCoinvest = prod.isCoinvest,
        })
    end
    return results
end

-- ============================================================================
-- 玩家操作: 申请融资
-- ============================================================================
function FN.ApplyFinancing(GD, productId, amount, projectId, duration, repayMethod)
    local prod = FN.PRODUCTS[productId]
    if not prod then
        GD.AddEvent("融资产品不存在", "danger")
        return false
    end

    -- 跟投特殊处理
    if prod.isCoinvest then
        local fin = GD.finance
        -- 查找绑定项目（使用传入的projectId参数）
        local bindProject = nil
        if projectId then
            for _, p in ipairs(GD.projects) do
                if p.id == projectId then
                    bindProject = p
                    break
                end
            end
        end
        if not bindProject then
            GD.AddEvent("请选择要跟投的项目", "warning")
            return false, "未选择项目"
        end
        -- 防重复：同一项目只能跟投一次
        if fin then
            for _, ci in ipairs(fin.coinvestments) do
                if not ci.settled and ci.projectId == bindProject.id then
                    GD.AddEvent("该项目已有进行中的跟投", "warning")
                    return false, "该项目已有跟投"
                end
            end
        end
        -- 跟投金额上限：总资产的5%
        local maxCoinvest = math.floor(GD.company.totalAssets * 0.05)
        if amount > maxCoinvest then
            amount = maxCoinvest
        end
        if amount < 50 then
            GD.AddEvent("跟投金额过低（最低50万）", "warning")
            return false, "金额过低"
        end
        -- 记录跟投
        GD.company.cash = GD.company.cash + amount
        if fin then
            table.insert(fin.coinvestments, {
                projectId = bindProject.id,
                projectName = bindProject.name,
                amount = amount,
                investMonth = GD.totalMonths,
                settled = false,
                returnAmount = 0,
            })
        end
        GD.AddEvent("员工跟投【" .. bindProject.name .. "】到账 " .. GD.FormatMoney(amount) .. "（无息，绑定项目收益分配）", "success")
        return true
    end

    local midRate = (prod.rateRange[1] + prod.rateRange[2]) / 2
    local finBonus = GD.company.traitEffects.financeCostBonus or 0
    local effectiveRate = math.max(1.0, midRate + finBonus)

    -- 使用玩家自定义期限，或产品默认期限
    local finalDuration = duration or prod.months
    -- 限制在产品允许范围内
    if prod.durationRange then
        finalDuration = math.max(prod.durationRange[1], math.min(prod.durationRange[2], finalDuration))
    end

    -- 还款方式，默认按月付息到期还本
    local finalRepayMethod = repayMethod or "interest_monthly"

    GD.ApplyLoan(prod.name, amount, effectiveRate, finalDuration, projectId, finalRepayMethod)
    return true
end

-- ============================================================================
-- 员工跟投结算(项目完成时调用)
-- ============================================================================
function FN.SettleCoinvestment(GD, projectId)
    local fin = GD.finance
    if not fin or not fin.coinvestments then return end
    for _, ci in ipairs(fin.coinvestments) do
        if not ci.settled and (ci.projectId == projectId or ci.projectId == "general") then
            -- 计算收益：跟投本金 + 项目利润分成(跟投额/项目总投资 × 项目净利润 × 80%)
            local project = nil
            for _, p in ipairs(GD.projects) do
                if p.id == projectId then project = p; break end
            end
            local projectProfit = 0
            if project and project.sales then
                projectProfit = (project.sales.revenue or 0) - (project.cost and project.cost.totalCost or 0)
            end
            local investRatio = 0
            if project and project.cost and project.cost.totalCost > 0 then
                investRatio = ci.amount / project.cost.totalCost
            else
                investRatio = 0.05  -- 通用跟投默认5%
            end
            local profitShare = math.floor(math.max(0, projectProfit) * investRatio * 0.80)
            local totalReturn = ci.amount + profitShare
            ci.settled = true
            ci.returnAmount = totalReturn
            -- 退还本金+收益(从公司现金扣除，相当于给员工分配)
            GD.company.cash = GD.company.cash - totalReturn
            GD.company.monthlyExpense = GD.company.monthlyExpense + totalReturn
            if profitShare > 0 then
                GD.AddEvent("员工跟投结算【" .. ci.projectName .. "】退还本金" .. GD.FormatMoney(ci.amount) .. " + 收益分成" .. GD.FormatMoney(profitShare), "success")
            else
                GD.AddEvent("员工跟投结算【" .. ci.projectName .. "】退还本金" .. GD.FormatMoney(ci.amount) .. "（项目无盈利，无分成）", "info")
            end
        end
    end
end

-- ============================================================================
-- 玩家操作: 预览提前还款
-- ============================================================================
function FN.GetEarlyRepayAmount(loan, principalAmount)
    if not loan then return 0, 0, 0 end

    local outstanding = math.max(0, tonumber(loan.amount) or 0)
    local principal = principalAmount == nil
        and outstanding
        or math.min(outstanding, math.floor(math.max(0, tonumber(principalAmount) or 0)))
    local accruedInterest = math.max(0, tonumber(loan.accruedInterest) or 0)
    local interestPaid = 0
    if loan.repayMethod == "bullet" and accruedInterest > 0 and principal > 0 then
        if principal >= outstanding then
            interestPaid = accruedInterest
        else
            interestPaid = math.floor(accruedInterest * principal / math.max(1, outstanding) * 100) / 100
        end
    end
    return principal + interestPaid, principal, interestPaid
end

-- ============================================================================
-- 玩家操作: 提前还款
-- ============================================================================
function FN.EarlyRepay(GD, loanIdx, principalAmount)
    local loan = GD.loans[loanIdx]
    if not loan then
        GD.AddEvent("贷款不存在", "danger")
        return false, "贷款不存在"
    end

    local totalRepay, principal, interestPaid = FN.GetEarlyRepayAmount(loan, principalAmount)
    local outstanding = math.max(0, tonumber(loan.amount) or 0)
    if principal <= 0 then
        GD.AddEvent("提前还款金额无效", "danger")
        return false, "提前还款金额无效"
    end

    local accruedInterest = math.max(0, tonumber(loan.accruedInterest) or 0)
    if GD.company.cash < totalRepay then
        local message = "现金不足，无法提前还款（需" .. GD.FormatMoney(totalRepay) .. "）"
        GD.AddEvent(message, "danger")
        return false, message
    end

    GD.company.cash = GD.company.cash - totalRepay
    GD.company.totalDebt = math.max(0, (GD.company.totalDebt or 0) - principal)
    GD.company.totalAssets = math.max(0, (GD.company.totalAssets or 0) - totalRepay)
    if GD.company.assetBreakdown then
        GD.company.assetBreakdown.cash = GD.company.cash
    end
    if interestPaid > 0 then
        GD.company.monthlyExpense = (GD.company.monthlyExpense or 0) + interestPaid
    end

    loan.amount = math.max(0, outstanding - principal)
    loan.accruedInterest = math.max(0, accruedInterest - interestPaid)
    local fullyRepaid = loan.amount <= 0
    local loanName = loan.name or "贷款"
    local message
    if interestPaid > 0 then
        message = "提前还款【" .. loanName .. "】本金" .. GD.FormatMoney(principal)
            .. " + 累计利息" .. GD.FormatMoney(interestPaid)
    else
        message = "提前还款【" .. loanName .. "】本金" .. GD.FormatMoney(principal)
    end

    if fullyRepaid then
        local fixedAssetIdx = loan.fixedAssetIdx
        table.remove(GD.loans, loanIdx)

        -- 贷款索引变化后同步固定资产抵押索引；本笔还清则立即解除抵押。
        for assetIdx, fa in ipairs(GD.fixedAssets or {}) do
            if fa.mortgageLoanIdx == loanIdx then
                local hasOtherMortgage = false
                for _, otherLoan in ipairs(GD.loans) do
                    if otherLoan.fixedAssetIdx == assetIdx then
                        hasOtherMortgage = true
                        break
                    end
                end
                if not hasOtherMortgage and GD.ReleaseFixedAssetMortgage then
                    GD.ReleaseFixedAssetMortgage(assetIdx)
                else
                    fa.mortgageLoanIdx = nil
                end
            elseif fa.mortgageLoanIdx and fa.mortgageLoanIdx > loanIdx then
                fa.mortgageLoanIdx = fa.mortgageLoanIdx - 1
            end
        end
        if fixedAssetIdx and GD.fixedAssets[fixedAssetIdx]
            and GD.fixedAssets[fixedAssetIdx].mortgaged
            and GD.fixedAssets[fixedAssetIdx].mortgageLoanIdx == nil
            and GD.ReleaseFixedAssetMortgage
        then
            GD.ReleaseFixedAssetMortgage(fixedAssetIdx)
        end
        message = message .. "，贷款已结清"
    else
        message = message .. "，剩余本金" .. GD.FormatMoney(loan.amount)
    end

    GD.AddEvent(message, "info")
    return true, message, principal
end

function FN.BatchEarlyRepay(GD, loanIndexes)
    local selected = {}
    local totalRepay = 0
    local seen = {}
    for _, rawIdx in ipairs(loanIndexes or {}) do
        local idx = math.floor(tonumber(rawIdx) or 0)
        local loan = GD.loans[idx]
        if idx >= 1 and loan and not seen[idx] then
            local repayAmount, principal = FN.GetEarlyRepayAmount(loan)
            if principal > 0 then
                seen[idx] = true
                totalRepay = totalRepay + repayAmount
                table.insert(selected, idx)
            end
        end
    end
    table.sort(selected, function(a, b) return a > b end)

    if #selected == 0 then
        return false, "请至少选择一笔贷款", 0, 0
    end
    if (GD.company.cash or 0) < totalRepay then
        local message = "现金不足，批量还款需要" .. GD.FormatMoney(totalRepay)
        GD.AddEvent(message, "danger")
        return false, message, 0, 0
    end

    local repaidCount = 0
    local actualPrincipal = 0
    for _, idx in ipairs(selected) do
        local ok, message, principal = FN.EarlyRepay(GD, idx)
        if not ok then
            return false, message or "批量还款失败", repaidCount, actualPrincipal
        end
        repaidCount = repaidCount + 1
        actualPrincipal = actualPrincipal + (principal or 0)
    end

    local message = "批量还款完成：结清" .. repaidCount .. "笔，本金" .. GD.FormatMoney(actualPrincipal)
    GD.AddEvent(message, "success")
    return true, message, repaidCount, actualPrincipal
end

-- ============================================================================
-- 玩家操作: 销售收入存入监管账户
-- ============================================================================
function FN.DepositToEscrow(GD, projectId, amount)
    local fin = GD.finance
    if not fin then
        -- 未初始化finance时直接入cash(向后兼容)
        GD.company.cash = GD.company.cash + amount
        GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + amount
        return
    end

    if not fin.escrowAccounts[projectId] then
        fin.escrowAccounts[projectId] = {total = 0, released = 0, frozen = false, milestoneIdx = 0}
    end
    local esc = fin.escrowAccounts[projectId]
    esc.total = esc.total + amount

    -- 监管资金只是冻结回款，不再重复计入公司营收；释放时才进入公司现金和当月营收。
end

-- ============================================================================
-- 玩家操作: 一次性释放项目剩余监管资金（清盘/打包出售/归档时使用）
-- ============================================================================
function FN.ReleaseEscrow(GD, projectId)
    local fin = GD.finance
    if not fin or not fin.escrowAccounts then return 0 end
    local esc = fin.escrowAccounts[projectId]
    if not esc then return 0 end
    local total = esc.total or 0
    local released = esc.released or 0
    local amount = math.max(0, math.floor(total - released))
    if amount > 0 then
        esc.released = total
        GD.company.cash = GD.company.cash + amount
        GD.company.monthlyRevenue = (GD.company.monthlyRevenue or 0) + amount
        if GD.AddLedger then
            GD.AddLedger("income", "监管释放", tostring(projectId) .. " 剩余监管资金释放", amount)
        end
    end
    return amount
end

-- ============================================================================
-- 玩家操作: 挪用监管资金(风险操作)
-- ============================================================================
function FN.AttemptMisappropriation(GD, projectId, amount)
    local fin = GD.finance
    if not fin then return false end
    local esc = fin.escrowAccounts[projectId]
    if not esc then
        GD.AddEvent("该项目无监管账户", "danger")
        return false
    end

    local available = esc.total - esc.released
    if esc.frozen then
        GD.AddEvent("监管账户已被冻结，无法操作", "danger")
        return false
    end
    if amount > available then
        GD.AddEvent("挪用金额超过监管余额", "danger")
        return false
    end

    -- 审计检查
    if math.random() < FN.MISAPPROPRIATION_AUDIT_CHANCE then
        -- 被查！冻结 + 罚款
        esc.frozen = true
        local penalty = math.floor(amount * 0.20)
        GD.company.cash = GD.company.cash - penalty
        GD.company.creditScore = math.max(0, GD.company.creditScore - 10)
        GD.AddEvent("监管资金挪用被审计发现！账户冻结，罚款" .. GD.FormatMoney(penalty) .. "，信用-10", "danger")
        return false
    end

    -- 成功挪用
    esc.released = esc.released + amount
    GD.company.cash = GD.company.cash + amount
    GD.AddEvent("从监管账户挪用" .. GD.FormatMoney(amount) .. "（高风险操作）", "warning")
    return true
end

-- ============================================================================
-- 玩家操作: 查询监管账户状态
-- ============================================================================
function FN.GetEscrowStatus(GD, projectId)
    local fin = GD.finance
    if not fin then return nil end
    return fin.escrowAccounts[projectId]
end

-- ============================================================================
-- 玩家操作: 获取三条红线状态
-- ============================================================================
function FN.GetRedLineStatus(GD)
    local fin = GD.finance
    if not fin then return nil end
    return fin.redLine
end

-- ============================================================================
-- 玩家操作: 计算项目毛利润税（预估，不实际扣除）
-- 用于 UI 展示项目预计税负
-- ============================================================================
function FN.CalcProjectProfitTax(GD, revenue, deductibleCost)
    if revenue <= 0 or deductibleCost <= 0 then return 0 end
    local grossProfit = revenue - deductibleCost
    if grossProfit <= 0 then return 0 end

    -- 筹划减免
    local savingsRate = 0
    local fin = GD and GD.finance
    if fin then
        for _, planId in ipairs(fin.tax.activePlans) do
            for _, plan in ipairs(FN.TAX_PLANS) do
                if plan.id == planId then
                    savingsRate = savingsRate + plan.savingsRate
                end
            end
        end
    end
    savingsRate = math.min(savingsRate, 0.50)

    return math.max(0, math.floor(grossProfit * FN.PROJECT_PROFIT_TAX_RATE * (1 - savingsRate)))
end

-- ============================================================================
-- 兼容接口: CalcLandAppreciationTax → 转发到 CalcProjectProfitTax
-- ============================================================================
function FN.CalcLandAppreciationTax(revenue, deductibleCost)
    return FN.CalcProjectProfitTax(nil, revenue, deductibleCost)
end

-- ============================================================================
-- 兼容接口: CalcCorpIncomeTax → 转发到 CalcProjectProfitTax
-- ============================================================================
function FN.CalcCorpIncomeTax(GD, profit)
    return FN.CalcProjectProfitTax(GD, profit, 0)
end

-- ============================================================================
-- 玩家操作: 启用税务筹划方案
-- ============================================================================
function FN.ApplyTaxPlan(GD, planId)
    local fin = GD.finance
    if not fin then return false end

    -- 检查是否已启用
    for _, id in ipairs(fin.tax.activePlans) do
        if id == planId then
            GD.AddEvent("该筹划方案已启用", "warning")
            return false
        end
    end

    -- 查找方案
    local plan
    for _, p in ipairs(FN.TAX_PLANS) do
        if p.id == planId then plan = p; break end
    end
    if not plan then return false end

    -- 扣除费用
    if GD.company.cash < plan.cost then
        GD.AddEvent("现金不足，无法启用筹划方案(需" .. GD.FormatMoney(plan.cost) .. ")", "danger")
        return false
    end

    GD.company.cash = GD.company.cash - plan.cost
    table.insert(fin.tax.activePlans, planId)
    GD.AddEvent("启用税务筹划【" .. plan.name .. "】，花费" .. GD.FormatMoney(plan.cost), "success")
    return true
end

-- ============================================================================
-- 玩家操作: 存款
-- ============================================================================
function FN.MakeDeposit(GD, depositTypeId, amount)
    local fin = GD.finance
    if not fin then return false end
    if amount <= 0 then return false end
    if GD.company.cash < amount then
        GD.AddEvent("现金不足，无法存款", "danger")
        return false
    end

    -- 查找存款类型
    local dtype
    for _, dt in ipairs(FN.DEPOSIT_TYPES) do
        if dt.id == depositTypeId then dtype = dt; break end
    end
    if not dtype then return false end

    if amount < dtype.minAmount then
        GD.AddEvent("存款金额不满足最低要求(" .. GD.FormatMoney(dtype.minAmount) .. ")", "danger")
        return false
    end

    GD.company.cash = GD.company.cash - amount

    if depositTypeId == "demand" then
        fin.demandBalance = fin.demandBalance + amount
        GD.AddEvent("活期存款存入" .. GD.FormatMoney(amount), "info")
    else
        table.insert(fin.deposits, {
            type = depositTypeId,
            name = dtype.name,
            amount = amount,
            rate = dtype.rate,
            startMonth = GD.totalMonths or 0,
            months = dtype.minMonths,
            matured = false,
        })
        GD.AddEvent(dtype.name .. "存入" .. GD.FormatMoney(amount) .. "，年利率" .. dtype.rate .. "%", "info")
    end
    return true
end

-- ============================================================================
-- 玩家操作: 取款
-- ============================================================================
function FN.WithdrawDeposit(GD, idx)
    local fin = GD.finance
    if not fin then return false end

    -- idx == 0 表示取活期
    if idx == 0 then
        if fin.demandBalance <= 0 then
            GD.AddEvent("活期余额为零", "warning")
            return false
        end
        local amount = fin.demandBalance
        GD.company.cash = GD.company.cash + amount
        fin.demandBalance = 0
        GD.AddEvent("活期存款取出" .. GD.FormatMoney(amount), "info")
        return true
    end

    -- 定期提前取出
    local dep = fin.deposits[idx]
    if not dep then return false end

    -- 提前取出：只返还本金，利息清零(罚息)
    GD.company.cash = GD.company.cash + dep.amount
    GD.AddEvent("定期存款提前取出" .. GD.FormatMoney(dep.amount) .. "（利息作废）", "warning")
    table.remove(fin.deposits, idx)
    return true
end

-- ============================================================================
-- 玩家操作: 生成并购目标（随机从池中选取）
-- ============================================================================
function FN.GenerateMATargets(GD)
    local pool = {}
    for _, tmpl in ipairs(FN.MA_TEMPLATES) do
        -- 价格波动 ±20%
        local priceVar = 0.8 + math.random() * 0.4
        local price = math.floor(tmpl.basePrice * priceVar)
        table.insert(pool, {
            name = tmpl.name,
            type = tmpl.type,
            price = price,
            desc = tmpl.desc,
            effect = tmpl.effect,
            assetValue = math.floor(tmpl.assetValue * priceVar),
            monthlyIncome = tmpl.monthlyIncome,
            costReduction = tmpl.costReduction,
            qualBoost = tmpl.qualBoost,
        })
    end
    -- Fisher-Yates 打乱
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local count = math.min(4, #pool)
    local targets = {}
    for i = 1, count do
        table.insert(targets, pool[i])
    end
    return targets
end

-- ============================================================================
-- 玩家操作: 执行并购
-- ============================================================================
function FN.ExecuteMA(GD, target)
    local co = GD.company
    if co.cash < target.price then
        GD.AddEvent("现金不足，无法完成收购", "danger")
        return false
    end

    co.cash = co.cash - target.price
    co.totalAssets = co.totalAssets + target.assetValue

    -- 根据效果类型应用
    if target.effect == "income" and target.monthlyIncome > 0 then
        if not GD.maIncome then GD.maIncome = {} end
        table.insert(GD.maIncome, {name = target.name, monthly = target.monthlyIncome})
    end
    if target.effect == "cost" and target.costReduction > 0 then
        co.traitEffects.buildCostBonus = (co.traitEffects.buildCostBonus or 0) - target.costReduction
        GD.AddEvent("收购带来建安成本降低" .. math.floor(target.costReduction * 100) .. "%", "info")
    end
    if target.effect == "qual" and target.qualBoost > 0 then
        local newQual = math.min(3, co.qualification + target.qualBoost)
        if newQual > co.qualification then
            co.qualification = newQual
            GD.AddEvent("通过收购获得资质提升至" .. GD.GetQualName(), "success")
        end
    end

    -- 记录并购历史
    if not GD.maHistory then GD.maHistory = {} end
    table.insert(GD.maHistory, {
        name = target.name,
        type = target.type,
        price = target.price,
        month = GD.totalMonths,
        year = GD.year,
    })

    GD.AddEvent("成功收购【" .. target.name .. "】(" .. target.type .. ")，花费" .. GD.FormatMoney(target.price), "success")
    return true
end

-- ============================================================================
-- 玩家操作: 检查IPO条件
-- ============================================================================
function FN.CheckIPOConditions(GD)
    local co = GD.company
    local results = {}
    local allPass = true
    for _, cond in ipairs(FN.IPO_CONDITIONS) do
        local ok = cond.check(co, GD)
        if not ok then allPass = false end
        table.insert(results, {name = cond.name, ok = ok})
    end
    return results, allPass
end

-- ============================================================================
-- 玩家操作: 执行IPO上市
-- ============================================================================
function FN.ExecuteIPO(GD)
    local _, allPass = FN.CheckIPOConditions(GD)
    if not allPass then
        GD.AddEvent("IPO条件不满足，无法上市", "danger")
        return false
    end

    local co = GD.company
    -- IPO 估值 = 总资产 × 1.5 + 年利润 × 10 PE
    local annualProfit = math.max(0, co.annualProfit or 0)
    local valuation = co.totalAssets * 1.5 + annualProfit * 10
    local ipoRaise = math.floor(valuation * 0.25) -- 发行25%股份

    co.cash = co.cash + ipoRaise
    co.totalAssets = co.totalAssets + ipoRaise

    GD.ipoData = {
        valuation = valuation,
        raiseAmount = ipoRaise,
        year = GD.year,
        month = GD.month,
    }
    GD.ipoCompleted = true

    GD.AddEvent("恭喜！" .. co.name .. " 成功登陆A股上市！", "success")
    GD.AddEvent("IPO估值 " .. GD.FormatMoney(valuation) .. "，募资 " .. GD.FormatMoney(ipoRaise), "success")
    GD.AddEvent("游戏通关！感谢您的经营，公司已成为上市企业！", "success")

    return true, valuation, ipoRaise
end

-- ============================================================================
-- 工具函数: 加权平均资本成本 WACC
-- WACC = Σ(贷款余额 × 利率) / Σ(贷款余额)
-- 考虑税盾: WACC_after_tax = WACC × (1 - 税率)
-- ============================================================================
function FN.CalcWACC(GD, afterTax)
    local totalWeighted = 0
    local totalDebt = 0
    for _, loan in ipairs(GD.loans) do
        totalWeighted = totalWeighted + loan.amount * (loan.rate or 0)
        totalDebt = totalDebt + loan.amount
    end
    if totalDebt <= 0 then return 0 end

    local wacc = totalWeighted / totalDebt
    if afterTax then
        -- 税盾效应: 利息可在企业所得税前扣除(25%)
        wacc = wacc * (1 - 0.25)
    end
    return math.floor(wacc * 100) / 100  -- 保留两位小数
end

-- ============================================================================
-- 工具函数: 净现值 NPV
-- NPV = Σ(CFt / (1+r)^t) , t从0开始
-- cashflows: {CF0, CF1, CF2, ...} (CF0通常为负=初始投入)
-- rate: 年折现率(小数, 如0.08=8%)
-- ============================================================================
function FN.CalcNPV(cashflows, rate)
    if not cashflows or #cashflows == 0 then return 0 end
    local npv = 0
    for i = 1, #cashflows do
        local t = i - 1  -- t从0开始
        npv = npv + cashflows[i] / ((1 + rate) ^ t)
    end
    return math.floor(npv * 100) / 100
end

-- ============================================================================
-- 工具函数: 内部收益率 IRR (二分法求解)
-- 找到使 NPV=0 的折现率
-- cashflows: {CF0, CF1, CF2, ...}
-- 返回年化IRR(小数), 如0.12表示12%
-- ============================================================================
function FN.CalcIRR(cashflows, maxIter)
    if not cashflows or #cashflows < 2 then return 0 end
    maxIter = maxIter or 100

    local lo, hi = -0.5, 5.0  -- IRR搜索范围: -50% ~ 500%
    local mid = 0
    for _ = 1, maxIter do
        mid = (lo + hi) / 2
        local npv = FN.CalcNPV(cashflows, mid)
        if math.abs(npv) < 0.01 then
            break
        end
        -- 初始投资为负时: NPV随利率升高而降低
        if npv > 0 then
            lo = mid
        else
            hi = mid
        end
    end
    return math.floor(mid * 10000) / 10000  -- 保留4位小数
end

-- ============================================================================
-- 工具函数: 项目投资回报分析
-- 生成项目的关键回报指标: NPV, IRR, ROE, 回收期
-- ============================================================================
function FN.CalcProjectReturns(GD, project)
    if not project then return nil end
    local p = project
    local totalInvest = p.totalCost or 0
    local totalRevenue = (p.sales and p.sales.revenue or 0)
    local profit = totalRevenue - totalInvest

    -- 构建简化现金流(按年): 初始投入 → 各年回收
    local constructionYears = math.max(1, math.ceil((p.construction and p.construction.totalMonths or 24) / 12))
    local cashflows = {}
    -- 投入阶段(均摊到建设年)
    local annualInvest = totalInvest / constructionYears
    for y = 1, constructionYears do
        table.insert(cashflows, -annualInvest)
    end
    -- 回收阶段(销售型: 集中1-2年; 持有型: 分散多年)
    if p.devTypeInfo and p.devTypeInfo.revenueModel == "hold" then
        -- 持有型: 假设15年运营期
        local annualRental = (p.operations and p.operations.monthlyRentalIncome or 0) * 12
        if annualRental <= 0 then annualRental = totalInvest * 0.06 end -- 预估6%回报
        for _ = 1, 15 do
            table.insert(cashflows, annualRental)
        end
    else
        -- 销售型: 假设销售期2年
        local saleYears = 2
        local annualRevenue = totalRevenue / saleYears
        for _ = 1, saleYears do
            table.insert(cashflows, annualRevenue)
        end
    end

    -- 计算指标
    local wacc = FN.CalcWACC(GD, true)
    local discountRate = math.max(0.05, wacc / 100)  -- 至少5%折现率
    local npv = FN.CalcNPV(cashflows, discountRate)
    local irr = FN.CalcIRR(cashflows)

    -- ROE = 净利润 / 自有资金
    local equity = math.max(1, (GD.company.totalAssets or 1) - (GD.company.totalDebt or 0))
    local roe = profit / equity

    -- 静态回收期(月)
    local paybackMonths = 0
    if totalRevenue > 0 and totalInvest > 0 then
        local monthlyAvgReturn = totalRevenue / math.max(1, #cashflows * 12)
        if monthlyAvgReturn > 0 then
            paybackMonths = math.ceil(totalInvest / monthlyAvgReturn)
        end
    end

    return {
        npv = npv,
        irr = irr,
        roe = math.floor(roe * 10000) / 10000,
        profit = math.floor(profit),
        profitRate = totalInvest > 0 and math.floor(profit / totalInvest * 10000) / 10000 or 0,
        paybackMonths = paybackMonths,
        wacc = wacc,
        discountRate = discountRate,
    }
end

-- ============================================================================
-- 查询: 获取税务汇总信息
-- ============================================================================
function FN.GetTaxSummary(GD)
    local fin = GD.finance
    if not fin then return {} end
    local tax = fin.tax
    return {
        {label = "项目结算税累计", value = math.floor(tax.projectTaxPaid)},
        {label = "租金税累计",     value = math.floor(tax.rentalTaxPaid)},
        {label = "当月租金税",     value = tax.monthlyRentalTax},
        {label = "当月税负合计",   value = tax.monthlyTaxTotal},
        {label = "筹划节税累计",   value = math.floor(tax.totalSavings)},
    }
end

-- ============================================================================
-- 查询: 获取融资概览(WACC + 红线 + 现金流)
-- ============================================================================
function FN.GetFinanceSummary(GD)
    local fin = GD.finance
    if not fin then return {} end
    local rl = fin.redLine
    local cf = fin.cashFlow
    local wacc = FN.CalcWACC(GD, false)
    local waccAfterTax = FN.CalcWACC(GD, true)

    return {
        -- 融资成本
        wacc = wacc,
        waccAfterTax = waccAfterTax,
        totalLoans = #GD.loans,
        totalDebt = GD.company.totalDebt,
        -- 红线
        redLineTier = rl.tier,
        redLineTierIdx = rl.tierIdx,
        assetLiability = math.floor(rl.assetLiability * 10000) / 100,  -- 转百分比
        netDebt = math.floor(rl.netDebt * 10000) / 100,
        cashShortDebt = math.floor(rl.cashShortDebt * 100) / 100,
        -- 现金流
        monthlyIn = cf.monthlyIn,
        monthlyOut = cf.monthlyOut,
        netFlow = cf.netFlow,
        forecast3m = cf.forecast3m,
        belowSafety = cf.belowSafety,
    }
end

return FN
