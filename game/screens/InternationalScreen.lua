---@diagnostic disable: assign-type-mismatch, param-type-mismatch
-- ============================================================================
-- InternationalScreen.lua - 国际地产投资中心
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}
M._countryId = M._countryId or "us"
M._activeTab = M._activeTab or 1
M._inputs = M._inputs or {}
M._lastAction = M._lastAction or nil

local function refresh(navigate)
    navigate("international")
end

local function input(key, fallback)
    if M._inputs[key] == nil then M._inputs[key] = fallback or "" end
    return M._inputs[key]
end

local function numberInput(key, fallback)
    return math.floor(tonumber(input(key, fallback)) or 0)
end

local function divisionSummary(INS)
    return INS.GetSummary(GD)
end

local function result(ok, message)
    local text = message or (ok and "国际业务操作成功" or "国际业务操作失败")
    M._lastAction = {ok = ok == true, text = text}
    GD.AddEvent(text, ok and "success" or "warning")
end

local function appendActionFeedback(rows)
    if not M._lastAction then return end
    rows[#rows + 1] = UI.Label {
        text = M._lastAction.text,
        fontSize = T.FontSmall,
        fontColor = M._lastAction.ok and T.Success or T.Danger,
        whiteSpace = "normal",
        maxLines = 4,
    }
end

local function countryCard(navigate, country)
    local selected = country.id == M._countryId
    local dd = country.dueDiligence
    local ddText = not dd and "未尽调" or (dd.status == "completed" and "尽调完成" or ("进行中" .. tostring(dd.remainMonths or 0) .. "月"))
    return UI.Button {
        width = "100%", height = 76, padding = 10,
        flexDirection = "column", alignItems = "flex-start", justifyContent = "center", gap = 3,
        backgroundColor = selected and T.PrimaryLight or T.Surface,
        borderWidth = 2, borderColor = selected and T.Primary or T.Border,
        onClick = function() M._countryId = country.id; refresh(navigate) end,
        children = {
            UI.Label {text = country.name .. " · " .. country.currency, fontSize = T.FontBody, fontColor = selected and T.Primary or T.TextPrimary},
            UI.Label {text = "汇率 " .. string.format("%.3f", country.fxToCny) .. " · 国别声望 " .. tostring(math.floor(country.reputation)) .. " · " .. ddText, fontSize = T.FontCaption, fontColor = T.TextMuted},
        },
    }
end

local function buildOverview(navigate, INS)
    local countries = INS.GetCountries(GD)
    local selected = nil
    for _, country in ipairs(countries) do if country.id == M._countryId then selected = country; break end end
    selected = selected or countries[1]
    local metrics = INS.GetSummary(GD)
    local rows = {
        C.SectionTitle {text = "选择投资国家", color = T.Accent},
        UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, children = (function()
            local cards = {}
            for _, country in ipairs(countries) do cards[#cards + 1] = countryCard(navigate, country) end
            return cards
        end)()},
        C.SectionTitle {text = selected.name .. "国别研究", color = T.Info},
        C.InfoRow {label = "本币 / 当前汇率", value = selected.currency .. " / " .. string.format("%.3f", selected.fxToCny) .. " CNY", color = T.Accent},
        C.InfoRow {label = "该国外汇账户", value = string.format("%.2f %s / %s", selected.foreignBalanceLocal or 0, selected.currency, C.FormatMoney(selected.foreignBalanceCny or 0)), color = T.Info},
        C.InfoRow {label = "国别声望", value = string.format("%.0f/100", selected.reputation), color = selected.reputation >= 60 and T.Success or T.Warning},
        C.InfoRow {label = "外资土地准入", value = selected.landAllowed and "可直接持有土地" or "受限，建议联合开发", color = selected.landAllowed and T.Success or T.Warning},
        C.InfoRow {label = "国际业务容量", value = tostring(metrics.capacityUsed) .. " / " .. tostring(metrics.capacity) .. "个项目", color = metrics.capacityUsed < metrics.capacity and T.Info or T.Danger},
        C.InfoRow {label = "海外团队", value = tostring(metrics.teamCount) .. "人", color = metrics.teamCount > 0 and T.Success or T.Warning},
        C.InfoRow {label = "活跃海外业务", value = tostring(metrics.activeProjects) .. "项目 / " .. tostring(metrics.activeAssets) .. "物业 / " .. tostring(metrics.activeFunds) .. "基金", color = T.Info},
        C.SectionTitle {text = "国别尽职调查", color = T.Warning},
        UI.Label {text = "尽调评估土地权属、外资准入、税务、政策和隐藏风险；未完成尽调不能启动海外投资。", fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 3},
        C.InfoRow {label = "当前状态", value = selected.dueDiligence and (selected.dueDiligence.status == "completed" and "已完成" or "进行中") or "未开始", color = selected.dueDiligence and selected.dueDiligence.status == "completed" and T.Success or T.Warning},
        C.ActionButton {
            text = selected.dueDiligence and selected.dueDiligence.status == "completed" and "国别尽调已完成" or "启动国别尽调（240万·2个月）",
            width = "100%", disabled = selected.dueDiligence and selected.dueDiligence.status == "completed",
            onClick = function() local ok, message = INS.StartDueDiligence(GD, selected.id, "general"); result(ok, message); refresh(navigate) end,
        },
        C.SectionTitle {text = "跨境工具", color = T.Info},
        UI.TextField {value = input("hedgeAmount", "1000"), width = "100%", height = 38, keyboardType = "number", placeholder = "对冲金额（万元）", onChange = function(_, value) M._inputs.hedgeAmount = value end},
        C.SecondaryButton {text = "购买12个月汇率对冲", width = "100%", onClick = function() local ok, message = INS.ApplyFXHedge(GD, selected.id, numberInput("hedgeAmount", 1000), 12); result(ok, message); refresh(navigate) end},
        C.SecondaryButton {text = "升级国际业务部容量", width = "100%", onClick = function() local ok, message = INS.UpgradeCapacity(GD); result(ok, message); refresh(navigate) end},
    }
    appendActionFeedback(rows)
    return UI.Panel {width = "100%", gap = 8, children = rows}
end

local function buildInvestments(navigate, INS)
    local countryId = M._countryId
    local summary = divisionSummary(INS)
    local dd = INS.GetDueDiligenceStatus(GD, countryId)
    local groupReady = GD.group and GD.group.active == true
    local ddReady = dd and dd.status == "completed"
    local modeReady = summary.divisionActive and ddReady
    local rows = {
        C.SectionTitle {text = "海外事业部投资模式", color = T.Accent},
        UI.Label {text = "国际投资由集团海外事业部独立经营：集团注资进入事业部，按国家兑换外汇，收益先留在事业部，只有手动分红才进入集团。", fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 4},
        C.InfoRow {label = "解锁条件", value = (groupReady and "集团已成立" or "需先成立集团") .. " · " .. (summary.divisionActive and "事业部已成立" or "需注册事业部") .. " · " .. (ddReady and "国别尽调完成" or "需完成国别尽调"), color = modeReady and T.Success or T.Warning},
        C.InfoRow {label = "事业部状态", value = summary.divisionActive and "已成立" or "未成立", color = summary.divisionActive and T.Success or T.Warning},
        C.InfoRow {label = "事业部本币 / 外汇", value = C.FormatMoney(summary.divisionTreasuryCny) .. " / " .. C.FormatMoney(summary.foreignCashCny), color = T.Accent},
        C.InfoRow {label = "独立留存收益 / 负债", value = C.FormatMoney(summary.divisionRetainedEarningsCny) .. " / " .. C.FormatMoney(summary.divisionDebtCny), color = T.Info},
        C.InfoRow {label = "事业部总资产 / 净资产", value = C.FormatMoney(summary.grossAssetsCny) .. " / " .. C.FormatMoney(summary.netAssetsCny), color = summary.netAssetsCny >= 0 and T.Success or T.Danger},
        C.InfoRow {label = "上月收入 / 费用", value = C.FormatMoney(summary.lastMonthlyIncome) .. " / " .. C.FormatMoney(summary.lastMonthlyExpense), color = T.Info},
        C.InfoRow {label = "外汇账户 / 国际银行", value = tostring(summary.foreignAccountCount) .. " / 存款" .. tostring(summary.bankDepositCount) .. "笔·贷款" .. tostring(summary.bankLoanCount) .. "笔", color = T.Info},
    }
    if not summary.divisionActive then
        rows[#rows + 1] = UI.TextField {value = tostring(input("divisionCapital", "1000") or ""), width = "100%", height = 38, keyboardType = "number", placeholder = "海外事业部注册资本（万元）", onChange = function(_, value) M._inputs.divisionCapital = tostring(value or "") end}
        rows[#rows + 1] = C.ActionButton {text = "注册成立集团海外事业部", width = "100%", onClick = function() local ok, message = INS.RegisterDivision(GD, numberInput("divisionCapital", 1000)); result(ok, message); refresh(navigate) end}
    else
        rows[#rows + 1] = UI.TextField {value = tostring(input("divisionInject", "1000") or ""), width = "100%", height = 38, keyboardType = "number", placeholder = "集团注资或调拨金额（万元）", onChange = function(_, value) M._inputs.divisionInject = tostring(value or "") end}
        rows[#rows + 1] = C.SecondaryButton {text = "集团注资并兑换到当前国外汇账户", width = "100%", onClick = function() local ok, message = INS.InjectDivisionCapital(GD, numberInput("divisionInject", 1000), countryId); result(ok, message); refresh(navigate) end}
        rows[#rows + 1] = C.SecondaryButton {text = "事业部本币调拨到当前国外汇账户", width = "100%", onClick = function() local ok, message = INS.TransferCapital(GD, countryId, numberInput("divisionInject", 1000)); result(ok, message); refresh(navigate) end}
        rows[#rows + 1] = C.SecondaryButton {text = "当前国外汇兑换回事业部本币", width = "100%", onClick = function() local ok, message = INS.ExchangeForeignToCny(GD, countryId, numberInput("divisionInject", 1000)); result(ok, message); refresh(navigate) end}
        rows[#rows + 1] = UI.TextField {value = tostring(input("divisionDividend", "500") or ""), width = "100%", height = 38, keyboardType = "number", placeholder = "事业部回兑本币分红金额（万元）", onChange = function(_, value) M._inputs.divisionDividend = tostring(value or "") end}
        rows[#rows + 1] = C.SecondaryButton {text = "外币兑换本币并向集团分红", width = "100%", onClick = function() local ok, message = INS.DistributeDivisionDividend(GD, numberInput("divisionDividend", 500)); result(ok, message); refresh(navigate) end}
    end
    rows[#rows + 1] = C.SectionTitle {text = "四种海外投资模式", color = T.Accent}
    rows[#rows + 1] = UI.Label {text = modeReady and "当前国家已完成尽调，可选择投资模式。资金从海外事业部独立账套扣除。" or "投资模式尚未解锁：请按上方提示成立集团、注册事业部，并在“国别研究”完成当前国家尽调。", fontSize = T.FontSmall, fontColor = modeReady and T.Success or T.Warning, whiteSpace = "normal", maxLines = 4}
    rows[#rows + 1] = UI.TextField {value = tostring(input("investAmount", "1000") or ""), width = "100%", height = 38, keyboardType = "number", placeholder = "投资金额（万元）", onChange = function(_, value) M._inputs.investAmount = tostring(value or "") end}
    rows[#rows + 1] = C.ActionButton {text = "模式1A：自主开发后销售", width = "100%", disabled = not modeReady, onClick = function() local ok, message = INS.InvestDirectLand(GD, countryId, numberInput("investAmount", 1000), "sale"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.ActionButton {text = "模式1B：自主开发并持有出租", width = "100%", disabled = not modeReady, onClick = function() local ok, message = INS.InvestDirectLand(GD, countryId, numberInput("investAmount", 1000), "rent"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.ActionButton {text = "模式2：收购存量写字楼", width = "100%", disabled = not modeReady, onClick = function() local ok, message = INS.BuyExistingAsset(GD, countryId, numberInput("investAmount", 1000), "写字楼"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.ActionButton {text = "模式3：联合本地开发商", width = "100%", disabled = not modeReady, onClick = function() local ok, message = INS.CreateJointVenture(GD, countryId, numberInput("investAmount", 1000), "本地合作开发商", 50); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.ActionButton {text = "模式4：海外地产基金/REITs", width = "100%", disabled = not modeReady, onClick = function() local ok, message = INS.InvestFund(GD, countryId, numberInput("investAmount", 1000), "REITs"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.SectionTitle {text = "海外团队", color = T.Info}
    for _, role in ipairs(INS.TEAM_ROLES) do
        local roleId = role.id
        rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", alignItems = "center", gap = 6, children = {
            UI.Label {text = role.name .. " · " .. tostring((INS.EnsureFields(GD).team[roleId] or 0)) .. "人 · 启动费" .. C.FormatMoney(role.cost), fontSize = T.FontSmall, fontColor = T.TextPrimary, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
            C.SecondaryButton {text = "聘用", width = 72, height = 34, disabled = not summary.divisionActive, onClick = function() local ok, message = INS.HireTeam(GD, roleId, 1); result(ok, message); refresh(navigate) end},
            C.SecondaryButton {text = "减员", width = 72, height = 34, disabled = not summary.divisionActive or (INS.EnsureFields(GD).team[roleId] or 0) <= 0, onClick = function() local ok, message = INS.FireTeam(GD, roleId, 1); result(ok, message); refresh(navigate) end},
        }}
    end
    rows[#rows + 1] = C.SectionTitle {text = "国际银行：存款与贷款", color = T.Info}
    rows[#rows + 1] = UI.TextField {value = tostring(input("bankAmount", "1000") or ""), width = "100%", height = 38, keyboardType = "number", placeholder = "国际银行金额（万元）", onChange = function(_, value) M._inputs.bankAmount = tostring(value or "") end}
    rows[#rows + 1] = C.SecondaryButton {text = "向当地国际银行信用贷款", width = "100%", disabled = not summary.divisionActive, onClick = function() local ok, message = INS.ApplyDivisionBankLoan(GD, countryId, numberInput("bankAmount", 1000), 36, "credit"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.SecondaryButton {text = "向当地国际银行抵押贷款", width = "100%", disabled = not summary.divisionActive, onClick = function() local ok, message = INS.ApplyDivisionBankLoan(GD, countryId, numberInput("bankAmount", 1000), 60, "mortgage"); result(ok, message); refresh(navigate) end}
    rows[#rows + 1] = C.SecondaryButton {text = "海外事业部国际银行存款", width = "100%", disabled = not summary.divisionActive, onClick = function() local ok, message = INS.DepositToInternationalBank(GD, countryId, numberInput("bankAmount", 1000), "fixed", 12); result(ok, message); refresh(navigate) end}
    local division = INS.GetDivisionSummary(GD)
    for _, deposit in ipairs(division.bankDeposits or {}) do
        local depositId = deposit.id
        rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", alignItems = "center", gap = 6, children = {
            UI.Label {text = "存款 " .. tostring(deposit.countryId) .. " · " .. C.FormatMoney(deposit.principalCny) .. " · " .. tostring(deposit.remainMonths or 0) .. "个月", fontSize = T.FontSmall, fontColor = T.TextPrimary, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0},
            C.SecondaryButton {text = "取回", width = 72, height = 34, onClick = function() local ok, message = INS.WithdrawInternationalBank(GD, depositId); result(ok, message); refresh(navigate) end},
        }}
    end
    for _, loan in ipairs(division.bankLoans or {}) do
        local loanId = loan.id
        rows[#rows + 1] = UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", alignItems = "center", gap = 6, children = {
            UI.Label {text = "贷款 " .. tostring(loan.countryId) .. " · 本金" .. C.FormatMoney(loan.remainingCny) .. " · 利息" .. C.FormatMoney(loan.accruedInterest or 0) .. " · " .. tostring(loan.status or "active"), fontSize = T.FontSmall, fontColor = loan.status == "overdue" and T.Danger or T.TextPrimary, flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, whiteSpace = "normal", maxLines = 2},
            C.SecondaryButton {text = "还款", width = 72, height = 34, onClick = function() local ok, message = INS.RepayDivisionBankLoan(GD, loanId, numberInput("bankAmount", 1000)); result(ok, message); refresh(navigate) end},
        }}
    end
    appendActionFeedback(rows)
    return UI.Panel {width = "100%", gap = 8, children = rows}
end

local function buildAssets(navigate, INS)
    local data = INS.EnsureFields(GD)
    local rows = {C.SectionTitle {text = "海外项目与资产", color = T.Accent}}
    if #data.projects == 0 and #data.assets == 0 and #data.funds == 0 then
        rows[#rows + 1] = UI.Label {text = "暂无海外项目、存量物业或基金持仓。完成国别尽调后可在投资模式中启动。", fontSize = T.FontSmall, fontColor = T.TextMuted, whiteSpace = "normal", maxLines = 3}
    end
    for _, project in ipairs(data.projects) do
        local projectId = project.id
        rows[#rows + 1] = C.Card {children = {
            C.Badge {text = project.mode == "joint_venture" and "联合开发" or "自主开发", variant = "info"},
            UI.Label {text = project.name, fontSize = T.FontBody, fontColor = T.TextPrimary, whiteSpace = "normal", maxLines = 2},
            C.InfoRow {label = "投入 / 进度", value = C.FormatMoney(project.investedCny) .. " / " .. tostring(math.floor((project.progress or 0) * 100)) .. "%"},
            C.SecondaryButton {text = "股权转让退出", width = "100%", onClick = function() local ok, message = INS.ExitProject(GD, projectId, "equity_transfer"); result(ok, message); refresh(navigate) end},
            C.SecondaryButton {text = "REIT证券化退出", width = "100%", onClick = function() local ok, message = INS.ExitProject(GD, projectId, "reit"); result(ok, message); refresh(navigate) end},
            C.SecondaryButton {text = "重大风险低价处置", width = "100%", onClick = function() local ok, message = INS.ExitProject(GD, projectId, "distress"); result(ok, message); refresh(navigate) end},
        }}
    end
    for _, asset in ipairs(data.assets) do
        local assetId = asset.id
        rows[#rows + 1] = C.Card {children = {
            C.Badge {text = "存量物业", variant = "success"},
            UI.Label {text = asset.name, fontSize = T.FontBody, fontColor = T.TextPrimary, whiteSpace = "normal", maxLines = 2},
            C.InfoRow {label = "投入 / 月租", value = C.FormatMoney(asset.investedCny) .. " / " .. C.FormatMoney(asset.monthlyRentCny)},
            C.InfoRow {label = "锁定期", value = tostring(asset.remainLockMonths or 0) .. "个月"},
            C.SecondaryButton {text = "出售资产", width = "100%", onClick = function() local ok, message = INS.SellAsset(GD, assetId); result(ok, message); refresh(navigate) end},
        }}
    end
    for _, fund in ipairs(data.funds) do
        local fundId = fund.id
        rows[#rows + 1] = C.Card {children = {
            C.Badge {text = "海外基金/REITs", variant = "warning"},
            UI.Label {text = fund.name, fontSize = T.FontBody, fontColor = T.TextPrimary, whiteSpace = "normal", maxLines = 2},
            C.InfoRow {label = "投入 / 当前净值", value = C.FormatMoney(fund.investedCny) .. " / " .. C.FormatMoney(fund.navCny)},
            C.InfoRow {label = "锁定期", value = tostring(fund.remainLockMonths or 0) .. "个月"},
            C.SecondaryButton {text = "赎回基金", width = "100%", onClick = function() local ok, message = INS.RedeemFund(GD, fundId); result(ok, message); refresh(navigate) end},
        }}
    end
    for _, tx in ipairs(data.transactions or {}) do
        if #rows >= 18 then break end
        rows[#rows + 1] = C.InfoRow {label = tostring(tx.period or "-") .. " · " .. tostring(tx.description or tx.type), value = C.FormatMoney(tx.amountCny or 0), color = (tx.amountCny or 0) >= 0 and T.Success or T.Warning}
    end
    appendActionFeedback(rows)
    return UI.Panel {width = "100%", gap = 8, children = rows}
end

local function buildRisks(navigate, INS)
    local data = INS.EnsureFields(GD)
    local rows = {C.SectionTitle {text = "国际风险与跨境税务", color = T.Warning}}
    for _, event in ipairs(data.events) do
        if (event.remainMonths or 0) > 0 then
            local eventId = event.id
            rows[#rows + 1] = C.Card {children = {
                C.Badge {text = event.name, variant = event.kind == "bad" and "danger" or "success"},
                UI.Label {text = event.desc .. " · 剩余" .. tostring(event.remainMonths) .. "个月", fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 3},
                C.ActionButton {text = "支付处置成本并降低影响", width = "100%", onClick = function() local ok, message = INS.ResolveEvent(GD, eventId, "hedge"); result(ok, message); refresh(navigate) end},
            }}
        end
    end
    if #rows == 1 then rows[#rows + 1] = UI.Label {text = "当前没有活跃的海外地缘或政策事件。每个国家独立生成事件，预警会显示在此处。", fontSize = T.FontSmall, fontColor = T.TextMuted, whiteSpace = "normal", maxLines = 3} end
    rows[#rows + 1] = C.SectionTitle {text = "税务规则", color = T.Info}
    rows[#rows + 1] = UI.Label {text = "海外租金、项目销售、资产/基金退出和银行利息分别计提当地持有税、企业所得税、交易税及预扣税；每笔税费写入国际税务台账。", fontSize = T.FontSmall, fontColor = T.TextSecondary, whiteSpace = "normal", maxLines = 5}
    for index = #data.taxRecords, math.max(1, #data.taxRecords - 7), -1 do
        local tax = data.taxRecords[index]
        if tax then rows[#rows + 1] = C.InfoRow {label = tostring(tax.period or "-") .. " · " .. tostring(tax.description or tax.type), value = C.FormatMoney(tax.amountCny or 0), color = T.Warning} end
    end
    appendActionFeedback(rows)
    return UI.Panel {width = "100%", gap = 8, children = rows}
end

function M.Create(navigate)
    local INS = GD.InternationalSystem
    if not INS then return UI.Label {text = "国际系统加载失败", fontSize = T.FontBody, fontColor = T.Danger} end
    local data = INS.EnsureFields(GD)
    data.selectedCountry = M._countryId
    local summary = INS.GetSummary(GD)
    local tabs = {"国别研究", "投资模式", "项目资产", "风险税务"}
    M._activeTab = math.max(1, math.min(#tabs, M._activeTab or 1))
    local content
    if M._activeTab == 1 then content = buildOverview(navigate, INS)
    elseif M._activeTab == 2 then content = buildInvestments(navigate, INS)
    elseif M._activeTab == 3 then content = buildAssets(navigate, INS)
    else content = buildRisks(navigate, INS) end
    return UI.ScrollView {
        id = "screenScrollView", width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 12,
        children = {
            UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", justifyContent = "space-between", alignItems = "flex-start", gap = 8, children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0, children = {
                    C.SectionTitle {text = "国际地产投资", color = T.Accent},
                    UI.Label {text = "四种海外投资模式 · 汇率 · 国别风险 · 跨境税务", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                C.Badge {text = "集团业务", variant = "info"},
            }},
            UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, children = {
                C.StatCard {title = "累计投入", value = C.FormatMoney(summary.totalInvestedCny), color = T.Accent},
                C.StatCard {title = "累计利润", value = C.FormatMoney(summary.totalProfitCny), color = summary.totalProfitCny >= 0 and T.Success or T.Danger},
                C.StatCard {title = "项目容量", value = tostring(summary.capacityUsed) .. "/" .. tostring(summary.capacity), color = summary.capacityUsed < summary.capacity and T.Info or T.Danger},
                C.StatCard {title = "活跃事件", value = tostring(summary.activeEvents), color = summary.activeEvents > 0 and T.Warning or T.Success},
            }},
            C.TabBar {tabs = tabs, active = M._activeTab, onChange = function(index) M._activeTab = index; refresh(navigate) end},
            content,
            UI.Panel {height = 20},
        },
    }
end

return M
