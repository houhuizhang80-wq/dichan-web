---@diagnostic disable: assign-type-mismatch
---@diagnostic disable: unnecessary-if
-- ============================================================================
-- PersonalFinanceScreen.lua - 个人金融生态二级页面
-- 所有金额单位均为万元；仅调用 PersonalFinanceEcosystem 的个人金融接口。
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local PFE = require("PersonalFinanceEcosystem")

local M = {}

-- 页面级状态：切换主页面再回来时仍保留当前标签和未提交输入。
M._activeTab = 1
M._inputs = {}
M._propertyNotice = nil
M._taxSourceSequence = 0

local TAB_NAMES = {
    "金融总览", "信用市场", "我的借条", "财务事件", "二手转卖", "财务日记", "合法税务",
}

local function money(value)
    return C.FormatMoney(tonumber(value) or 0)
end

local function percentage(value)
    return string.format("%.1f%%", (tonumber(value) or 0) * 100)
end

local function monthText(info)
    if type(info) ~= "table" then return "--" end
    return string.format("%d年%d月", info.year or 0, info.month or 0)
end

local function addEvent(text, kind)
    if type(GD.AddEvent) == "function" then
        GD.AddEvent(text, kind or "info")
    end
end

local function refresh(navigate)
    navigate("personalFinance")
end

local function input(key, props)
    props = props or {}
    return UI.TextField {
        value = M._inputs[key] or "",
        placeholder = props.placeholder or "",
        width = props.width or "100%",
        height = props.height or 38,
        fontSize = props.fontSize or T.FontCaption,
        backgroundColor = T.BgInput,
        borderColor = T.Border,
        borderWidth = T.DividerWidth,
        fontColor = T.TextPrimary,
        onChange = function(_, text)
            M._inputs[key] = text
        end,
    }
end

local function pixelButton(props)
    return UI.Button {
        text = props.text or "确认",
        width = props.width,
        height = props.height or 34,
        fontSize = props.fontSize or T.FontCaption,
        backgroundColor = props.disabled and T.DisabledBg or (props.backgroundColor or T.Primary),
        fontColor = props.disabled and T.TextMuted or (props.fontColor or T.TextOnDark),
        borderRadius = 0,
        borderWidth = T.DividerWidth,
        borderColor = props.disabled and T.Border or (props.borderColor or T.PrimaryBorder),
        paddingHorizontal = props.paddingH or 10,
        disabled = props.disabled == true,
        onClick = props.onClick,
    }
end

local function infoNote(text, color)
    return UI.Label {
        text = text,
        fontSize = T.FontCaption,
        fontColor = color or T.TextMuted,
        whiteSpace = "normal",
        width = "100%",
    }
end

local function scoreColor(score)
    if score >= 760 then return T.Success end
    if score >= 640 then return T.Primary end
    if score >= 500 then return T.Warning end
    return T.Danger
end

local function contractStatus(contract)
    if contract.status == "defaulted" then return "违约", "danger" end
    if (contract.overdueCount or 0) > 0 then return "逾期" .. contract.overdueCount .. "次", "warning" end
    if (contract.npcDelayCount or 0) > 0 then return "回款延迟" .. contract.npcDelayCount .. "次", "warning" end
    return "正常履约", "success"
end

local function safeAction(navigate, callback, fallback)
    local ok, result = callback()
    if ok then
        addEvent("个人金融操作已完成", "success")
    else
        addEvent(result or fallback or "操作失败", "warning")
    end
    refresh(navigate)
end

function M.Create(navigate)
    if not GD.player then
        return UI.ScrollView {
            width = "100%", height = "100%", scrollY = true, padding = T.PagePadding,
            children = {
                C.SectionTitle {text = "个人金融生态"},
                infoNote("个人数据尚未初始化，暂不能使用金融功能。", T.Warning),
                pixelButton {text = "返回个人中心", width = "100%", onClick = function() navigate("personal") end},
            },
        }
    end

    local tabBuilders = {
        M._BuildOverview, M._BuildMarket, M._BuildContracts, M._BuildEvents,
        M._BuildResale, M._BuildDiary, M._BuildTax,
    }
    local builder = tabBuilders[M._activeTab] or M._BuildOverview

    return UI.ScrollView {
        id = "personalFinanceScroll",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = T.Gap,
        backgroundColor = T.BgMain,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = "个人金融生态", fontSize = T.FontTitle, fontColor = T.TextPrimary, fontWeight = "bold"},
                        UI.Label {text = "信用、借条、风控与合规税务", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    pixelButton {
                        text = "← 返回个人中心", height = 34,
                        backgroundColor = T.BgCard, fontColor = T.TextSecondary, borderColor = T.Border,
                        onClick = function() navigate("personal") end,
                    },
                },
            },
            C.TabBar {
                tabs = TAB_NAMES,
                active = M._activeTab,
                onChange = function(index)
                    M._activeTab = index
                    refresh(navigate)
                end,
            },
            builder(navigate),
            UI.Panel {height = 18, width = "100%"},
        },
    }
end

-- ============================================================================
-- 金融总览
-- ============================================================================
function M._BuildOverview(navigate)
    local summary = PFE.GetCreditSummary(GD)
    local salary = PFE.GetPreparedSalaryFactor(GD)
    local debt = summary.debt or 0
    local receivable = summary.receivable or 0
    local riskAdjusted = summary.riskAdjustedReceivable or 0
    local discount = math.max(0, receivable - riskAdjusted)
    local limits = {}

    local financeScore = tonumber(summary.financeScore) or 0
    local socialCreditScore = tonumber(summary.socialCreditScore) or 0
    if financeScore < 430 then
        limits[#limits + 1] = "信用评分低于430：信用市场借入已关闭。"
    elseif financeScore < 500 then
        limits[#limits + 1] = "信用评分偏低：可借额度与市场报价将受到明显限制。"
    else
        limits[#limits + 1] = "信用借入可用，实际额度仍取决于对手方信任和当月报价。"
    end
    if socialCreditScore < 40 then
        limits[#limits + 1] = "社会信用严重受限：部分圈层和生活方式活动不可进入。"
    elseif socialCreditScore < 65 then
        limits[#limits + 1] = "社会信用一般：高门槛圈层活动可能受限。"
    end
    if debt > 0 then
        limits[#limits + 1] = "请预留个人现金用于月供；逾期会降低金融评分与社会信用。"
    end

    return UI.Panel {width = "100%", gap = 12, children = {
        UI.Panel {flexDirection = "row", flexWrap = "wrap", gap = 8, width = "100%", children = {
            C.StatCard {title = "金融评分", value = tostring(summary.financeScore or 0), subtitle = "评级 " .. (summary.financeRating or "--"), color = scoreColor(summary.financeScore), minWidth = 110},
            C.StatCard {title = "社会信用", value = tostring(summary.socialCreditScore or 0), subtitle = summary.socialRating or "--", color = scoreColor((summary.socialCreditScore or 0) * 8), minWidth = 110},
            C.StatCard {title = "个人债务", value = money(debt), subtitle = "借入本金余额", color = debt > 0 and T.Danger or T.Success, minWidth = 110},
            C.StatCard {title = "风险后债权", value = money(riskAdjusted), subtitle = "名义 " .. money(receivable), color = T.Info, minWidth = 110},
        }},
        C.Card {children = {
            C.SectionTitle {text = "信用与风险敞口", color = T.Accent},
            C.InfoRow {label = "金融评级", value = summary.financeRating or "--", color = scoreColor(summary.financeScore)},
            C.InfoRow {label = "社会信用评级", value = summary.socialRating or "--", color = scoreColor((summary.socialCreditScore or 0) * 8)},
            C.InfoRow {label = "借入负债余额", value = money(debt), color = debt > 0 and T.Danger or T.Success},
            C.InfoRow {label = "名义债权余额", value = money(receivable), color = T.Info},
            C.InfoRow {label = "债权风险折价", value = "-" .. money(discount), color = discount > 0 and T.Warning or T.Success},
            C.InfoRow {label = "风险调整后债权", value = money(riskAdjusted), color = T.Success},
            C.InfoRow {label = "金融净调整", value = money(riskAdjusted - debt), color = riskAdjusted >= debt and T.Success or T.Danger},
        }},
        C.Card {children = {
            C.SectionTitle {text = "最近职业收入波动", color = T.Info},
            C.InfoRow {label = "基准月职业收入", value = money(salary.baseSalary or 0)},
            C.InfoRow {label = "本月波动因子", value = string.format("%.2f%%", ((salary.factor or 1) - 1) * 100), color = (salary.factor or 1) >= 1 and T.Success or T.Warning},
            C.InfoRow {label = "本月调整后收入", value = money(salary.adjustedSalary or 0), color = T.Success},
            infoNote((salary.highIdentity and "高社会身份/资产阶段的月收入波动区间为±15%。" or "当前月职业收入波动区间为±5%。")),
        }},
        C.Card {children = (function()
            local rows = {C.SectionTitle {text = "信用限制提示", color = T.Warning}}
            for _, text in ipairs(limits) do table.insert(rows, infoNote("• " .. text, T.TextSecondary)) end
            table.insert(rows, pixelButton {text = "查看信用市场", width = "100%", onClick = function()
                M._activeTab = 2
                refresh(navigate)
            end})
            return rows
        end)()},
    }}
end

-- ============================================================================
-- 信用市场
-- ============================================================================
function M._BuildMarket(navigate)
    local market = PFE.RefreshMarket(GD)
    local summary = PFE.GetCreditSummary(GD)
    local financeScore = tonumber(summary.financeScore) or 0
    local playerCash = GD.player.cash or 0
    local cards = {}

    for _, quote in pairs(market.quotes or {}) do
        local id = quote.npcId
        local amountKey, termKey = "market:" .. id .. ":amount", "market:" .. id .. ":term"
        local amount = tonumber(M._inputs[amountKey] or "") or 0
        local months = math.floor(tonumber(M._inputs[termKey] or "") or 0)
        local validTerm = months >= (quote.minMonths or 3) and months <= (quote.maxMonths or 24)
        local validAmount = amount >= 10
        local canBorrow = financeScore >= 430 and validAmount and validTerm and amount <= (quote.borrowLimit or 0)
        local canLend = validAmount and validTerm and amount <= (quote.lendLimit or 0) and amount <= playerCash
        local validationNote = nil
        if not validAmount or not validTerm then
            validationNote = infoNote("请输入至少10万、" .. (quote.minMonths or 3) .. "～" .. (quote.maxMonths or 24) .. "个月的期限；无效输入时操作按钮已禁用。", T.Warning)
        elseif financeScore < 430 then
            validationNote = infoNote("当前金融评分低于430，借入功能已禁用。", T.Danger)
        end
        local npcId = id

        table.insert(cards, C.Card {children = {
            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                UI.Panel {gap = 2, children = {
                    UI.Label {text = quote.name or "未命名对手方", fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold"},
                    UI.Label {text = quote.role or "信用市场参与者", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                C.Badge {text = "评级 " .. (quote.financeRatingRequired or "--"), variant = "info"},
            }},
            UI.Panel {flexDirection = "row", flexWrap = "wrap", gap = 8, width = "100%", children = {
                C.StatCard {title = "借入年利率", value = percentage(quote.borrowAnnualRate), color = T.Warning, minWidth = 110, valueFontSize = T.FontSubtitle},
                C.StatCard {title = "出借年利率", value = percentage(quote.lendAnnualRate), color = T.Success, minWidth = 110, valueFontSize = T.FontSubtitle},
            }},
            C.InfoRow {label = "本月可借限额", value = money(quote.borrowLimit), color = T.Warning},
            C.InfoRow {label = "本月可出借限额", value = money(quote.lendLimit), color = T.Info},
            C.InfoRow {label = "允许期限", value = (quote.minMonths or 3) .. "～" .. (quote.maxMonths or 24) .. "个月"},
            UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                input(amountKey, {placeholder = "金额(万，至少10)", width = "60%"}),
                input(termKey, {placeholder = "期限(月)", width = "40%"}),
            }},
            UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                pixelButton {
                    text = "向他借入", width = "49%", backgroundColor = T.Warning,
                    disabled = not canBorrow,
                    onClick = function()
                        safeAction(navigate, function() return PFE.BorrowFromNPC(GD, npcId, amount, months) end, "借入失败")
                    end,
                },
                pixelButton {
                    text = "向他出借", width = "49%", backgroundColor = T.Info,
                    disabled = not canLend,
                    onClick = function()
                        safeAction(navigate, function() return PFE.LendToNPC(GD, npcId, amount, months) end, "出借失败")
                    end,
                },
            }},
            validationNote,
        }})
    end

    return UI.Panel {width = "100%", gap = 12, children = {
        C.Card {children = {
            C.SectionTitle {text = "本月私人信用市场", color = T.Accent},
            C.InfoRow {label = "可用个人现金", value = money(playerCash), color = T.Success},
            C.InfoRow {label = "当前金融评分", value = tostring(summary.financeScore or 0) .. " / " .. (summary.financeRating or "--"), color = scoreColor(summary.financeScore)},
            infoNote("利率和额度按月更新。借入仅进入个人现金，出借仅扣除个人现金，不影响公司现金或公司负债。"),
        }},
        UI.Panel {width = "100%", gap = 10, children = cards},
    }}
end

-- ============================================================================
-- 我的借条
-- ============================================================================
function M._BuildContracts(navigate)
    local summary = PFE.GetCreditSummary(GD)
    local cards = {}

    for _, contract in ipairs(summary.contracts or {}) do
        local direction = contract.direction == "borrow" and "我向对手方借入" or "我向对手方出借"
        local directionColor = contract.direction == "borrow" and T.Warning or T.Info
        local statusText, statusVariant = contractStatus(contract)
        local repayKey = "repay:" .. tostring(contract.id)
        local isBorrow = contract.direction == "borrow" and (contract.status == "active" or contract.status == "defaulted")
        local repayAmount = tonumber(M._inputs[repayKey] or "") or 0
        local canPartRepay = isBorrow and repayAmount > 0 and repayAmount <= (contract.outstanding or 0) and repayAmount <= (GD.player.cash or 0)
        local canFullRepay = isBorrow and (GD.player.cash or 0) >= (contract.outstanding or 0)
        local id = contract.id

        table.insert(cards, C.Card {children = {
            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                UI.Panel {gap = 2, children = {
                    UI.Label {text = contract.npcName or "未知对手方", fontSize = T.FontBody, fontColor = T.TextPrimary, fontWeight = "bold"},
                    UI.Label {text = direction, fontSize = T.FontCaption, fontColor = directionColor},
                }},
                C.Badge {text = statusText, variant = statusVariant},
            }},
            C.InfoRow {label = "本金余额", value = money(contract.outstanding), color = directionColor},
            C.InfoRow {label = "年利率", value = percentage(contract.annualRate)},
            C.InfoRow {label = "月供/约定月回款", value = money(contract.monthlyPayment), color = contract.direction == "borrow" and T.Danger or T.Success},
            C.InfoRow {label = "下次还款/回款", value = monthText(contract.nextPayment)},
            C.InfoRow {label = "到期时间", value = monthText(contract.maturity)},
            contract.purpose and C.InfoRow {label = "用途", value = contract.purpose} or nil,
            isBorrow and UI.Panel {width = "100%", gap = 6, marginTop = 4, children = {
                UI.Label {text = "提前偿还", fontSize = T.FontCaption, fontColor = T.Warning},
                UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                    input(repayKey, {placeholder = "还款本金(万)", width = "48%"}),
                    pixelButton {
                        text = "部分偿还", width = "25%", backgroundColor = T.Warning,
                        disabled = not canPartRepay,
                        onClick = function()
                            safeAction(navigate, function() return PFE.EarlyRepay(GD, id, repayAmount) end, "提前偿还失败")
                        end,
                    },
                    pixelButton {
                        text = "全额偿还", width = "25%", backgroundColor = T.Success,
                        disabled = not canFullRepay,
                        onClick = function()
                            safeAction(navigate, function() return PFE.EarlyRepay(GD, id, contract.outstanding) end, "全额偿还失败")
                        end,
                    },
                }},
                not canFullRepay and infoNote("个人现金不足以全额偿还；输入有效金额后可部分偿还。", T.TextMuted) or nil,
            }} or nil,
        }})
    end

    return UI.Panel {width = "100%", gap = 12, children = {
        C.Card {children = {
            C.SectionTitle {text = "借条清单", color = T.Accent},
            C.InfoRow {label = "借入债务", value = money(summary.debt), color = (summary.debt or 0) > 0 and T.Danger or T.Success},
            C.InfoRow {label = "风险后债权", value = money(summary.riskAdjustedReceivable), color = T.Success},
            infoNote("仅“我向对手方借入”的未结借条支持提前偿还；按钮在现金不足或金额无效时会真正禁用。"),
        }},
        #cards > 0 and UI.Panel {width = "100%", gap = 10, children = cards} or C.Card {children = {
            infoNote("当前没有进行中的私人借条。可前往信用市场与具名 NPC 建立借入或出借合约。", T.TextSecondary),
            pixelButton {text = "前往信用市场", width = "100%", onClick = function() M._activeTab = 2; refresh(navigate) end},
        }},
    }}
end

-- ============================================================================
-- 财务事件
-- ============================================================================
function M._BuildEvents(navigate)
    local state = PFE.Ensure(GD.player)
    local pending = state.pendingEvent
    local history = state.eventHistory or {}
    local rows = {}

    if pending and pending.status == "pending" then
        table.insert(rows, C.Card {children = (function()
            local children = {
                C.SectionTitle {text = "待处理：" .. (pending.title or "财务事件"), color = T.Warning},
                infoNote(pending.description or "请在截止前选择处理方式。", T.TextSecondary),
                C.InfoRow {label = "事件金额", value = money(pending.amount), color = T.Warning},
                C.InfoRow {label = "截止时间", value = monthText({year = math.floor(((pending.deadlineMonth or 1) - 1) / 12), month = ((pending.deadlineMonth or 1) - 1) % 12 + 1}), color = T.Danger},
            }
            for _, option in ipairs(pending.options or {}) do
                local cost = tonumber(option.cost) or 0
                local affordable = cost <= (GD.player.cash or 0)
                local eventId, optionId = pending.id, option.id
                table.insert(children, UI.Panel {width = "100%", padding = 10, gap = 5, backgroundColor = T.Surface, borderWidth = T.DividerWidth, borderColor = T.Border, children = {
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", children = {
                        UI.Label {text = option.name or "处理方案", fontSize = T.FontBody, fontColor = T.TextPrimary},
                        UI.Label {text = cost > 0 and ("成本 " .. money(cost)) or "无直接成本", fontSize = T.FontCaption, fontColor = cost > 0 and T.Warning or T.Success},
                    }},
                    infoNote("效果：" .. (option.effect or "--")),
                    pixelButton {
                        text = affordable and "选择此方案" or "现金不足",
                        width = "100%", backgroundColor = affordable and T.Primary or T.DisabledBg,
                        disabled = not affordable,
                        onClick = function()
                            safeAction(navigate, function() return PFE.ResolveFinancialEvent(GD, eventId, optionId) end, "事件处理失败")
                        end,
                    },
                }})
            end
            return children
        end)()})
    else
        table.insert(rows, C.Card {children = {
            C.SectionTitle {text = "暂无待处理事件", color = T.Success},
            infoNote("突发财务事件会在月度更新中按规则出现；无待处理事件时可查看下方历史。"),
        }})
    end

    local historyRows = {C.SectionTitle {text = "财务事件历史", color = T.Info}}
    if #history == 0 then
        table.insert(historyRows, infoNote("尚无财务事件记录。", T.TextMuted))
    else
        for index = #history, math.max(1, #history - 15), -1 do
            local record = history[index]
            local label = record.status == "resolved" and "已处理" or (record.status == "expired" and "已过期" or "待处理")
            table.insert(historyRows, UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", paddingVertical = 3, children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 1, children = {
                    UI.Label {text = record.title or "财务事件", fontSize = T.FontCaption, fontColor = T.TextPrimary},
                    UI.Label {text = "发生于 " .. (record.createdMonth or "--") .. " 月序", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Panel {alignItems = "flex-end", gap = 2, children = {
                    C.Badge {text = label, variant = record.status == "resolved" and "success" or (record.status == "expired" and "danger" or "warning")},
                    UI.Label {text = money(record.amount), fontSize = T.FontCaption, fontColor = T.Warning},
                }},
            }})
        end
    end
    table.insert(rows, C.Card {children = historyRows})
    return UI.Panel {width = "100%", gap = 12, children = rows}
end

-- ============================================================================
-- 二手转卖
-- ============================================================================
function M._BuildResale(navigate)
    local inventory = PFE.BuildResaleInventory(GD)
    local cards = {}
    for _, asset in ipairs(inventory) do
        local resaleId = asset.resaleId
        if asset.canSell then
            table.insert(cards, C.Card {children = {
                UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = asset.name or "可转卖资产", fontSize = T.FontBody, fontColor = T.TextPrimary},
                        UI.Label {text = asset.category or "生活品/私人资产", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    C.Badge {text = "可出售", variant = "success"},
                }},
                C.InfoRow {label = "原始价格", value = money(asset.originalPrice)},
                C.InfoRow {label = "预计二手回收", value = money(asset.estimatedPrice), color = T.Success},
                pixelButton {
                    text = "按二手价出售", width = "100%", backgroundColor = T.Success,
                    onClick = function()
                        safeAction(navigate, function() return PFE.SellResaleAsset(GD, resaleId) end, "二手转卖失败")
                    end,
                },
            }})
        else
            table.insert(cards, C.Card {children = {
                C.SectionTitle {text = asset.name or "个人房产", color = T.Info},
                C.InfoRow {label = "参考价值", value = money(asset.estimatedPrice), color = T.Info},
                infoNote(asset.message or "房产请前往个人房产页面出售。", T.Warning),
                pixelButton {
                    text = "前往个人房产页", width = "100%", backgroundColor = T.Info,
                    onClick = function()
                        M._propertyNotice = "房产出售请在个人中心的“个人房产”页完成，以便统一处理按揭和租赁状态。"
                        addEvent(M._propertyNotice, "info")
                        navigate("personal")
                    end,
                },
            }})
        end
    end

    local header = {
        C.SectionTitle {text = "生活品与私人资产二手转卖", color = T.Accent},
        C.InfoRow {label = "当前个人现金", value = money(GD.player.cash), color = T.Success},
        infoNote("生活品和私人资产按统一二手规则折价出售。房产不可在本页出售，必须前往个人房产页面。"),
    }
    if M._propertyNotice ~= nil then table.insert(header, infoNote(M._propertyNotice, T.Info)) end

    return UI.Panel {width = "100%", gap = 12, children = {
        C.Card {children = header},
        #cards > 0 and UI.Panel {width = "100%", gap = 10, children = cards} or C.Card {children = {
            infoNote("暂无可识别的生活品、私人资产或房产库存。", T.TextMuted),
        }},
    }}
end

-- ============================================================================
-- 财务日记
-- ============================================================================
function M._BuildDiary(navigate)
    local titleKey, contentKey, amountKey, typeKey = "diary:title", "diary:content", "diary:amount", "diary:type"
    local title = M._inputs[titleKey] or ""
    local content = M._inputs[contentKey] or ""
    local amount = tonumber(M._inputs[amountKey] or "") or 0
    local entryType = M._inputs[typeKey] or "note"
    local canAdd = title ~= ""
    local diary = PFE.GetDiary(GD)
    local entries = {}

    for _, entry in ipairs(diary) do
        local id = entry.id
        table.insert(entries, C.Card {children = {
            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, children = {
                    UI.Label {text = entry.title or "未命名记录", fontSize = T.FontBody, fontColor = T.TextPrimary},
                    UI.Label {text = "类型：" .. (entry.type or "note") .. " | 月序：" .. (entry.serial or "--"), fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Label {text = money(entry.amount), fontSize = T.FontBody, fontColor = (entry.amount or 0) > 0 and T.Warning or T.TextSecondary},
            }},
            (entry.content or "") ~= "" and infoNote(entry.content, T.TextSecondary) or nil,
            pixelButton {
                text = "删除记录", width = "100%", backgroundColor = T.Danger,
                onClick = function()
                    safeAction(navigate, function() return PFE.DeleteDiary(GD, id) end, "删除日记失败")
                end,
            },
        }})
    end

    return UI.Panel {width = "100%", gap = 12, children = {
        C.Card {children = {
            C.SectionTitle {text = "新增财务日记", color = T.Accent},
            input(titleKey, {placeholder = "标题（必填，最多80字）"}),
            -- UI.TextField 是单行组件；这里用加高、自动横向滚动的长 TextField，刻意不猜测不存在的 TextArea。
            input(contentKey, {placeholder = "内容（长文本单行输入，最多1000字）", height = 58}),
            UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                input(amountKey, {placeholder = "关联金额(万，可空)", width = "55%"}),
                input(typeKey, {placeholder = "类型，如收入/支出", width = "45%"}),
            }},
            pixelButton {
                text = "添加日记", width = "100%", disabled = not canAdd,
                onClick = function()
                    safeAction(navigate, function() return PFE.AddDiary(GD, title, content, amount, entryType) end, "添加日记失败")
                end,
            },
            infoNote("日记只记录个人财务备注，不会改变现金。内容使用长 TextField，不使用未经确认的 TextArea。"),
        }},
        C.Card {children = {
            C.SectionTitle {text = "财务日记（最新在前）", color = T.Info},
            #entries > 0 and UI.Panel {width = "100%", gap = 8, children = entries} or infoNote("尚无财务日记。", T.TextMuted),
        }},
    }}
end

-- ============================================================================
-- 合法税务
-- ============================================================================
function M._BuildTax(navigate)
    local advice = PFE.GetTaxOptimizationAdvice(GD)
    local categoryKey, amountKey, noteKey = "tax:category", "tax:amount", "tax:note"
    local category = M._inputs[categoryKey] or ""
    local amount = tonumber(M._inputs[amountKey] or "") or 0
    local note = M._inputs[noteKey] or ""
    local validCategories = {charity = true, education = true, medical = true, elderCare = true, mortgageInterest = true}
    local canRecord = validCategories[category] == true and amount > 0
    local rows = {}

    for _, item in ipairs(advice.advice or {}) do
        table.insert(rows, C.Card {children = {
            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                UI.Label {text = item.name or item.category, fontSize = T.FontBody, fontColor = T.TextPrimary},
                C.Badge {text = item.category or "--", variant = "info"},
            }},
            C.InfoRow {label = "已登记", value = money(item.declaredAmount), color = T.Info},
            C.InfoRow {label = "预计可抵扣", value = money(item.acceptedDeduction), color = T.Success},
            C.InfoRow {label = "年度可用上限", value = money(item.maximumEligibleAmount)},
            C.InfoRow {label = "剩余可登记", value = money(item.remainingEligibleAmount), color = T.Warning},
            infoNote(item.note or "仅限真实、合法且可留存凭证的项目。"),
        }})
    end

    return UI.Panel {width = "100%", gap = 12, children = {
        UI.Panel {flexDirection = "row", flexWrap = "wrap", gap = 8, width = "100%", children = {
            C.StatCard {title = "税前年收入", value = money(advice.taxableIncome), color = T.Info, minWidth = 110},
            C.StatCard {title = "预计税前税额", value = money(advice.estimatedTaxBefore), color = T.Warning, minWidth = 110},
            C.StatCard {title = "预计税后税额", value = money(advice.estimatedTaxAfter), color = T.Danger, minWidth = 110},
            C.StatCard {title = "预计节税", value = money(advice.estimatedTaxSaving), color = T.Success, minWidth = 110},
        }},
        C.Card {children = {
            C.SectionTitle {text = tostring(advice.year or GD.year or "--") .. "年合法抵扣汇总", color = T.Accent},
            C.InfoRow {label = "预计可抵扣总额", value = money(advice.totalAcceptedDeduction), color = T.Success},
            infoNote(advice.disclaimer or "建议仅用于合法税前扣除规划，实际税务以主管机关核定为准。", T.Warning),
        }},
        C.Card {children = {
            C.SectionTitle {text = "登记真实合法凭证", color = T.Info},
            input(categoryKey, {placeholder = "类别：charity / education / medical / elderCare / mortgageInterest"}),
            UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = {
                input(amountKey, {placeholder = "金额(万)", width = "40%"}),
                input(noteKey, {placeholder = "凭证说明（可选）", width = "60%"}),
            }},
            pixelButton {
                text = "登记合法抵扣", width = "100%", disabled = not canRecord,
                onClick = function()
                    M._taxSourceSequence = M._taxSourceSequence + 1
                    local sourceId = "ui-tax:" .. tostring(GD.year or 0) .. ":" .. category .. ":" .. M._taxSourceSequence
                    safeAction(navigate, function() return PFE.RecordTaxDeduction(GD, category, amount, sourceId, note) end, "登记抵扣失败")
                end,
            },
            infoNote("仅支持 charity、education、medical、elderCare、mortgageInterest 五类。按钮会在类别或金额无效时真正禁用。"),
        }},
        C.SectionTitle {text = "合法抵扣项目", color = T.Accent},
        UI.Panel {width = "100%", gap = 8, children = rows},
    }}
end

return M
