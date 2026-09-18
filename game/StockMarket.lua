---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- StockMarket.lua - 股票市场系统
-- 随机生成15家上市公司，支持买入/卖出，股价按月波动
-- ============================================================================

local SM = {}

-- 15家上市公司模板
SM.COMPANY_TEMPLATES = {
    {name = "万川地产",   industry = "房地产", code = "SH000002", basePrice = 15.20, volatility = 0.010, dividendRate = 0.006, lossProbability = 0.42},
    {name = "碧川园控股", industry = "房地产", code = "HK002007", basePrice = 8.50,  volatility = 0.014, dividendRate = 0.002, lossProbability = 0.58},
    {name = "寰宇银行",   industry = "金融",   code = "SH601988", basePrice = 4.30,  volatility = 0.006, dividendRate = 0.010, lossProbability = 0.25},
    {name = "招远银行",   industry = "金融",   code = "SH600036", basePrice = 38.60, volatility = 0.008, dividendRate = 0.008, lossProbability = 0.30},
    {name = "安和保险",   industry = "保险",   code = "SH601318", basePrice = 52.80, volatility = 0.009, dividendRate = 0.006, lossProbability = 0.34},
    {name = "川源酒业",   industry = "消费",   code = "SH600519", basePrice = 1680.00, volatility = 0.008, dividendRate = 0.007, lossProbability = 0.25},
    {name = "格川电器",   industry = "家电",   code = "SZ000651", basePrice = 42.50, volatility = 0.009, dividendRate = 0.007, lossProbability = 0.34},
    {name = "讯联控股",   industry = "科技",   code = "HK700",    basePrice = 380.00, volatility = 0.014, dividendRate = 0.001, lossProbability = 0.54},
    {name = "河马商联",   industry = "科技",   code = "HK9988",   basePrice = 85.00,  volatility = 0.015, dividendRate = 0.000, lossProbability = 0.60},
    {name = "比川动力",   industry = "汽车",   code = "SZ002594", basePrice = 265.00, volatility = 0.016, dividendRate = 0.001, lossProbability = 0.56},
    {name = "寰宇建筑",   industry = "建筑",   code = "SH601668", basePrice = 6.80,  volatility = 0.007, dividendRate = 0.009, lossProbability = 0.30},
    {name = "保宁发展",   industry = "房地产", code = "SH600048", basePrice = 12.40, volatility = 0.011, dividendRate = 0.005, lossProbability = 0.45},
    {name = "海川水泥",   industry = "建材",   code = "SH600585", basePrice = 28.30, volatility = 0.009, dividendRate = 0.006, lossProbability = 0.38},
    {name = "宁川时代",   industry = "新能源", code = "SZ300750", basePrice = 210.00, volatility = 0.017, dividendRate = 0.000, lossProbability = 0.60},
    {name = "铁川基建",   industry = "基建",   code = "SH601390", basePrice = 7.50,  volatility = 0.007, dividendRate = 0.008, lossProbability = 0.34},
}

local TEMPLATE_BY_CODE = {}
for _, tmpl in ipairs(SM.COMPANY_TEMPLATES) do
    TEMPLATE_BY_CODE[tmpl.code] = tmpl
end

local function round2(v)
    return math.floor((v or 0) * 100) / 100
end

function SM.SyncMarketConfig(GD)
    if not GD.stockMarket then return end

    GD.stockMarket.totalDividends = round2(GD.stockMarket.totalDividends or 0)

    if GD.stockMarket.holdings then
        for _, holding in pairs(GD.stockMarket.holdings) do
            holding.totalDividends = holding.totalDividends or 0
            if not GD.stockMarket.dividendUnitMigrated then
                holding.totalDividends = round2(holding.totalDividends / 10000)
            end
        end
    end
    GD.stockMarket.dividendUnitMigrated = true

    if not GD.stockMarket.companies then return end
    for _, stock in ipairs(GD.stockMarket.companies) do
        local tmpl = TEMPLATE_BY_CODE[stock.code]
        if tmpl then
            stock.name = tmpl.name
            stock.industry = tmpl.industry or stock.industry
            stock.volatility = tmpl.volatility
            stock.dividendRate = tmpl.dividendRate
            stock.lossProbability = tmpl.lossProbability
            stock.basePrice = stock.basePrice or tmpl.basePrice
        else
            stock.volatility = math.min(stock.volatility or 0.012, 0.018)
            stock.dividendRate = math.min(stock.dividendRate or 0, 0.010)
            stock.lossProbability = stock.lossProbability or 0.45
        end
        stock.priceHistory = stock.priceHistory or {stock.currentPrice or stock.basePrice or 1}
        stock.trend = stock.trend or 0
        stock.changePercent = stock.changePercent or 0
    end
end

--- 初始化股市数据（在 GD 中创建 stockMarket 表）
function SM.Init(GD)
    if GD.stockMarket and GD.stockMarket.companies and #GD.stockMarket.companies > 0 then
        SM.SyncMarketConfig(GD)
        return
    end

    GD.stockMarket = {
        companies = {},
        holdings = {},      -- {[code] = {shares, avgCost, totalCost}}
        history = {},       -- 交易历史
        totalInvested = 0,
        totalReturns = 0,
        totalDividends = 0,
        dividendUnitMigrated = true,
    }

    for _, tmpl in ipairs(SM.COMPANY_TEMPLATES) do
        -- 在基础价格上随机浮动 ±20%
        local priceRandom = 0.8 + math.random() * 0.4
        local currentPrice = math.floor(tmpl.basePrice * priceRandom * 100) / 100
        -- 随机市值（亿）
        local marketCap = math.floor(currentPrice * (50 + math.random(200)) * 10) / 10
        -- 市盈率
        local pe = math.floor((8 + math.random() * 40) * 10) / 10

        table.insert(GD.stockMarket.companies, {
            name = tmpl.name,
            industry = tmpl.industry,
            code = tmpl.code,
            currentPrice = currentPrice,
            prevPrice = currentPrice,
            basePrice = tmpl.basePrice,
            volatility = tmpl.volatility,
            dividendRate = tmpl.dividendRate,
            lossProbability = tmpl.lossProbability or 0.6,
            marketCap = marketCap,
            pe = pe,
            changePercent = 0,
            priceHistory = {currentPrice},  -- 最近12个月价格记录
            trend = 0,  -- -1=下跌趋势, 0=震荡, 1=上涨趋势
        })
    end
end

--- 月度股价更新（低频季度波动：更小涨跌幅、更高下行风险）
function SM.MonthlyUpdate(GD)
    if not GD.stockMarket then return end
    -- 股价不再每月都波动：只在每季度末更新一次，其他月份保持上次涨跌显示，减少月结遍历。
    local isTradingMonth = ((GD.month or 1) % 3) == 0
    if not isTradingMonth then
        return
    end

    SM.SyncMarketConfig(GD)
    if not GD.stockMarket.companies or #GD.stockMarket.companies == 0 then return end

    local cycle = GD.economy and GD.economy.cycle or "recovery"
    local cycleBias = {boom = 0.010, recovery = 0.005, recession = -0.003, depression = -0.008}
    local bias = (cycleBias[cycle] or 0) + 0.001  -- 长期略微正期望，但仍受周期和估值约束

    local avgRatio = 0
    for _, s in ipairs(GD.stockMarket.companies) do
        avgRatio = avgRatio + ((s.currentPrice or s.basePrice) / math.max(0.01, s.basePrice or 1))
    end
    avgRatio = avgRatio / math.max(1, #GD.stockMarket.companies)
    if avgRatio < 0.75 then
        bias = bias + (0.75 - avgRatio) * 0.030
    elseif avgRatio > 1.25 then
        bias = bias - (avgRatio - 1.25) * 0.030
    end

    local industryList = {}
    local seen = {}
    for _, s in ipairs(GD.stockMarket.companies) do
        if not seen[s.industry] then
            seen[s.industry] = true
            table.insert(industryList, s.industry)
        end
    end
    local hotIndustry = (#industryList > 0) and industryList[math.random(#industryList)] or nil
    local hotBias = 0
    if hotIndustry and math.random() < 0.35 then
        hotBias = (math.random() - 0.45) * 0.012
    end

    local marketEventBias = 0
    if math.random() < 0.05 then
        local events = {
            {name = "政策托底预期", bias = 0.006},
            {name = "流动性边际改善", bias = 0.005},
            {name = "监管政策收紧", bias = -0.008},
            {name = "经济数据走弱", bias = -0.010},
            {name = "外部市场回调", bias = -0.007},
        }
        local marketEvent = events[math.random(#events)]
        marketEventBias = marketEvent.bias
        GD.AddEvent("股市: " .. marketEvent.name, marketEvent.bias > 0 and "info" or "warning")
    end

    for _, stock in ipairs(GD.stockMarket.companies) do
        stock.prevPrice = stock.currentPrice

        -- 不是所有股票每个季度都明显波动，降低波动频次。
        if math.random() > 0.58 then
            stock.changePercent = 0
            table.insert(stock.priceHistory, stock.currentPrice)
            if #stock.priceHistory > 16 then table.remove(stock.priceHistory, 1) end
        else
            if math.random() < 0.16 then
                stock.trend = math.random(-1, 1)
            end

            local stockEventBias = 0
            if math.random() < 0.025 then
                local sEvents = {
                    {name = "业绩略超预期", bias = 0.010},
                    {name = "订单改善", bias = 0.008},
                    {name = "利润承压", bias = -0.010},
                    {name = "融资成本上升", bias = -0.008},
                    {name = "项目回款不及预期", bias = -0.010},
                }
                local se = sEvents[math.random(#sEvents)]
                stockEventBias = se.bias
            end

            local industryBias = (stock.industry == hotIndustry) and hotBias or 0
            local randomChange = (math.random() - 0.5) * 2 * (stock.volatility or 0.01) * 0.55
            local trendEffect = (stock.trend or 0) * (stock.volatility or 0.01) * 0.08
            local valuationPressure = (stock.pe and stock.pe > 35) and -0.002 or 0
            local lossShock = 0
            if math.random() < (stock.lossProbability or 0.45) * 0.04 then
                lossShock = -(stock.volatility or 0.01) * (0.6 + math.random() * 1.0)
            end

            local totalChange = randomChange + bias + trendEffect + industryBias + marketEventBias + stockEventBias + valuationPressure + lossShock
            totalChange = math.max(-0.040, math.min(0.040, totalChange))

            local newPrice = stock.currentPrice * (1 + totalChange)
            newPrice = math.max((stock.basePrice or stock.currentPrice) * 0.20, math.min((stock.basePrice or stock.currentPrice) * 2.50, newPrice))
            stock.currentPrice = round2(newPrice)

            stock.changePercent = round2((stock.currentPrice - stock.prevPrice) / math.max(0.01, stock.prevPrice) * 100)

            local peChange = (math.random() - 0.55) * 1.0 + totalChange * 2
            stock.pe = math.floor(((stock.pe or 15) + peChange) * 10) / 10
            stock.pe = math.max(3, math.min(60, stock.pe))

            stock.marketCap = math.floor((stock.marketCap or 10) * (1 + totalChange) * 10) / 10
            stock.marketCap = math.max(10, stock.marketCap)

            table.insert(stock.priceHistory, stock.currentPrice)
            if #stock.priceHistory > 16 then
                table.remove(stock.priceHistory, 1)
            end
        end
    end

    -- 分红改为年度结算，且亏损/不分红公司会跳过。
    if GD.month == 12 then
        SM._processDividends(GD)
    end
end

--- 处理分红
function SM._processDividends(GD)
    if not GD.stockMarket or not GD.stockMarket.holdings then return end
    SM.SyncMarketConfig(GD)

    local totalDivWan = 0
    local paidCount = 0
    local skippedCount = 0

    for code, holding in pairs(GD.stockMarket.holdings) do
        if holding.shares and holding.shares > 0 then
            for _, stock in ipairs(GD.stockMarket.companies) do
                if stock.code == code then
                    stock.lastDividendStatus = "未分红"
                    stock.lastDividendAmount = 0
                    stock.lastDividendYear = GD.year

                    if (stock.dividendRate or 0) <= 0 then
                        skippedCount = skippedCount + 1
                        stock.lastDividendStatus = "无分红"
                        break
                    end

                    -- 多数公司会因经营亏损或现金流紧张跳过分红。
                    if math.random() < (stock.lossProbability or 0.6) then
                        skippedCount = skippedCount + 1
                        stock.lastDividendStatus = "亏损不分红"
                        break
                    end

                    local marketValueWan = holding.shares * stock.currentPrice / 10000
                    local payoutFactor = 0.55 + math.random() * 0.35
                    local divWan = round2(marketValueWan * stock.dividendRate * payoutFactor)
                    if divWan > 0 then
                        totalDivWan = totalDivWan + divWan
                        paidCount = paidCount + 1
                        holding.totalDividends = round2((holding.totalDividends or 0) + divWan)
                        stock.lastDividendStatus = "已分红"
                        stock.lastDividendAmount = divWan
                    else
                        skippedCount = skippedCount + 1
                        stock.lastDividendStatus = "分红过低"
                    end
                    break
                end
            end
        end
    end

    totalDivWan = round2(totalDivWan)
    if totalDivWan > 0 then
        GD.company.cash = GD.company.cash + totalDivWan
        GD.stockMarket.totalDividends = round2((GD.stockMarket.totalDividends or 0) + totalDivWan)
        GD.AddEvent("股票年度分红收入: " .. string.format("%.2f万", totalDivWan) .. "（" .. paidCount .. "家公司）", "success")
        if skippedCount > 0 then
            GD.AddEvent("股市: " .. skippedCount .. "家持仓公司因亏损或无分红政策未分红", "warning")
        end
        if GD.AddLedger then
            GD.AddLedger("income", "股票分红", "持股年度分红收入", totalDivWan)
        end
    elseif skippedCount > 0 then
        GD.AddEvent("股市: 本年度持仓公司多数亏损或不分红，未收到股票分红", "warning")
    end
end

--- 买入股票
---@param GD table
---@param stockCode string 股票代码
---@param investAmount number 投资金额（万元）
---@return boolean ok
---@return string message
function SM.Buy(GD, stockCode, investAmount)
    if not GD.stockMarket then return false, "股市未初始化" end
    SM.SyncMarketConfig(GD)
    if investAmount <= 0 then return false, "投资金额必须大于0" end
    if GD.company.cash < investAmount then return false, "资金不足" end

    local stock
    for _, s in ipairs(GD.stockMarket.companies) do
        if s.code == stockCode then stock = s; break end
    end
    if not stock then return false, "未找到该股票" end

    -- 万元转元计算股数（每手100股）
    local investYuan = investAmount * 10000
    local priceYuan = stock.currentPrice
    local shares = math.floor(investYuan / priceYuan / 100) * 100  -- 整手买入
    if shares < 100 then return false, "资金不足买入1手(100股)，至少需" .. string.format("%.2f万", priceYuan * 100 / 10000) end

    local actualCost = shares * priceYuan / 10000  -- 实际花费（万元）

    GD.company.cash = GD.company.cash - actualCost

    -- 更新持仓
    GD.stockMarket.holdings = GD.stockMarket.holdings or {}
    local holding = GD.stockMarket.holdings[stockCode]
    if not holding then
        holding = {shares = 0, avgCost = 0, totalCost = 0, totalDividends = 0}
        GD.stockMarket.holdings[stockCode] = holding
    end

    -- 计算新的平均成本
    local oldTotal = holding.shares * holding.avgCost
    holding.shares = holding.shares + shares
    holding.avgCost = (oldTotal + shares * priceYuan) / holding.shares
    holding.totalCost = holding.totalCost + actualCost

    GD.stockMarket.totalInvested = (GD.stockMarket.totalInvested or 0) + actualCost

    -- 记录交易
    table.insert(GD.stockMarket.history, {
        type = "buy", code = stockCode, name = stock.name,
        price = priceYuan, shares = shares, amount = actualCost,
        month = GD.totalMonths, year = GD.year, mon = GD.month,
    })

    GD.AddEvent("买入" .. stock.name .. " " .. shares .. "股，均价" .. string.format("%.2f", priceYuan) .. "元，花费" .. string.format("%.2f万", actualCost), "info")
    return true, "买入成功: " .. shares .. "股"
end

--- 卖出股票
---@param GD table
---@param stockCode string 股票代码
---@param sellShares number 卖出股数（0表示全部卖出）
---@return boolean ok
---@return string message
function SM.Sell(GD, stockCode, sellShares)
    if not GD.stockMarket then return false, "股市未初始化" end
    SM.SyncMarketConfig(GD)

    local holding = GD.stockMarket.holdings and GD.stockMarket.holdings[stockCode]
    if not holding or holding.shares <= 0 then return false, "未持有该股票" end

    if sellShares <= 0 then sellShares = holding.shares end
    sellShares = math.min(sellShares, holding.shares)
    sellShares = math.floor(sellShares / 100) * 100  -- 整手卖出
    if sellShares < 100 then return false, "至少卖出100股" end

    local stock
    for _, s in ipairs(GD.stockMarket.companies) do
        if s.code == stockCode then stock = s; break end
    end
    if not stock then return false, "未找到该股票" end

    local revenue = sellShares * stock.currentPrice / 10000  -- 收入（万元）
    local cost = sellShares * holding.avgCost / 10000  -- 成本（万元）
    local profit = revenue - cost

    GD.company.cash = GD.company.cash + revenue

    holding.shares = holding.shares - sellShares
    if holding.shares <= 0 then
        GD.stockMarket.holdings[stockCode] = nil
    end

    GD.stockMarket.totalReturns = (GD.stockMarket.totalReturns or 0) + revenue

    -- 记录交易
    table.insert(GD.stockMarket.history, {
        type = "sell", code = stockCode, name = stock.name,
        price = stock.currentPrice, shares = sellShares, amount = revenue,
        profit = profit,
        month = GD.totalMonths, year = GD.year, mon = GD.month,
    })

    local profitText = profit >= 0 and ("盈利" .. string.format("%.2f万", profit)) or ("亏损" .. string.format("%.2f万", math.abs(profit)))
    GD.AddEvent("卖出" .. stock.name .. " " .. sellShares .. "股，" .. profitText, profit >= 0 and "success" or "warning")
    return true, "卖出成功: " .. sellShares .. "股, " .. profitText
end

--- 获取持仓汇总
function SM.GetPortfolioSummary(GD)
    if not GD.stockMarket or not GD.stockMarket.holdings then
        return {totalValue = 0, totalCost = 0, totalProfit = 0, holdingCount = 0, totalDividends = 0}
    end
    SM.SyncMarketConfig(GD)

    local totalValue, totalCost, count = 0, 0, 0
    for code, holding in pairs(GD.stockMarket.holdings) do
        if holding.shares > 0 then
            count = count + 1
            totalCost = totalCost + holding.shares * holding.avgCost / 10000
            for _, stock in ipairs(GD.stockMarket.companies) do
                if stock.code == code then
                    totalValue = totalValue + holding.shares * stock.currentPrice / 10000
                    break
                end
            end
        end
    end

    return {
        totalValue = math.floor(totalValue * 100) / 100,
        totalCost = math.floor(totalCost * 100) / 100,
        totalProfit = math.floor((totalValue - totalCost) * 100) / 100,
        holdingCount = count,
        totalDividends = GD.stockMarket.totalDividends or 0,
    }
end

return SM
