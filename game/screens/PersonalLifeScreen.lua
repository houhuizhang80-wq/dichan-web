---@diagnostic disable: undefined-field
-- ============================================================================
-- PersonalLifeScreen.lua - 个人生活与社会身份中心
-- 独立 AppShell 二级页；业务动作全部委托给 PersonalLife.lua。
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local PL = require("PersonalLife")
local PFE = require("PersonalFinanceEcosystem")

local M = {}
M._activeTab = 1

local TABS = {
    "身份总览", "私人资产", "健康服务", "进修成长", "圈层活动", "公益项目", "我的持有",
}

local TAB_CATEGORY = {
    [2] = "asset",
    [3] = "health",
    [4] = "education",
    [5] = "social",
    [6] = "charity",
}

local CATEGORY_TITLE = {
    asset = "私人资产",
    health = "健康服务",
    education = "进修成长",
    social = "圈层活动",
    charity = "公益项目",
}

local CATEGORY_COLORS = {
    asset = T.Info,
    health = T.Success,
    education = T.Primary,
    social = T.Warning,
    charity = T.Danger,
}

local function formatMoney(amount)
    return C.FormatMoney(tonumber(amount) or 0)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil, "个人生活系统接口未就绪" end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil, tostring(a) end
    return a, b, c
end

local function getPlayer()
    local player = GD.player or {}
    if GD.player then call(PL.Ensure, player) end
    return player
end

local function normalizeList(source)
    local list = {}
    if type(source) ~= "table" then return list end
    for _, value in ipairs(source) do
        table.insert(list, value)
    end
    if #list == 0 then
        for _, value in pairs(source) do
            if type(value) == "table" then table.insert(list, value) end
        end
    end
    return list
end

local function getOverview(player)
    local summary = call(PL.GetSummary, GD)
    if type(summary) ~= "table" then summary = {} end
    local identity = type(summary.identity) == "table" and summary.identity or {}
    local dimensions = type(summary.dimensions) == "table" and summary.dimensions or {}

    local overview = {
        level = tonumber(identity.level) or 1,
        cash = tonumber(summary.cash or player.cash) or 0,
        monthlyFee = tonumber(summary.monthlyCost) or 0,
        credit = tonumber(player.socialCreditScore or player.creditScore) or 0,
        title = identity.name or "个人生活身份",
        description = identity.desc or "通过资产、健康、成长、圈层与公益积累个人社会影响力。",
        score = tonumber(identity.score or dimensions.score) or 0,
        dimensions = {
            {id = "wealth", label = "财富", value = dimensions.wealth or 0, max = 40, color = T.Info},
            {id = "consumption", label = "消费品质", value = dimensions.consumption or 0, max = 40, color = T.Warning},
            {id = "circle", label = "社会圈层", value = dimensions.circle or 0, max = 40, color = T.Primary},
            {id = "charity", label = "公益贡献", value = dimensions.charity or 0, max = 45, color = T.Danger},
            {id = "growth", label = "成长能力", value = dimensions.growth or 0, max = 40, color = T.Success},
        },
    }
    overview.level = math.max(1, math.min(12, overview.level))
    return overview
end

local function getCatalog(category)
    return normalizeList(call(PL.GetCatalog, GD, category))
end

local function getOwned()
    local summary = call(PL.GetSummary, GD)
    return normalizeList(type(summary) == "table" and summary.records or nil)
end

local function itemId(item)
    return item and (item.id or item.key or item.assetId or item.itemId)
end

local function itemName(item)
    return (item and (item.name or item.title or item.label)) or "未命名项目"
end

local function itemPrice(item)
    return tonumber(item and (item.price or item.cost or item.purchasePrice)) or 0
end

local function itemMonthlyFee(item)
    return tonumber(item and (item.monthlyFee or item.monthlyCost or item.monthly)) or 0
end

local function itemCreditRequired(item)
    return tonumber(item and (item.minCredit or item.creditRequired or item.requiredCredit)) or 0
end

local function itemActive(item)
    return item
        and not item.sold
        and item.status ~= "sold"
        and item.status ~= "paused"
        and item.status ~= "paused_insufficient_cash"
end

local function ownsItem(item, owned)
    local id = itemId(item)
    if not id then return false end
    for _, record in ipairs(owned) do
        if itemId(record) == id then return true end
    end
    return false
end

local function canPurchase(item, overview, owned)
    local id = itemId(item)
    if not id then return false, "项目标识缺失" end
    if item.category == "social" then
        local allowed, reason = call(PFE.CanAccessLifestyleItem, GD, item)
        if allowed == false then return false, reason end
    end
    if item.type == "asset" and ownsItem(item, owned) then return false, "已持有该项目" end
    if overview.cash < itemPrice(item) then return false, "可用现金不足" end
    return true, nil
end

local function canOperate(action, record, overview)
    if action == "sell" then
        return record.type == "asset" and record.status ~= "sold", record.type == "asset" and record.status ~= "sold" and nil or "该项目不可出售"
    end
    if action == "cancel" then
        return record.type == "service" or record.type == "pledge", record.status == "active" and nil or "项目当前未启用"
    end
    if action == "reactivate" then
        return (record.type == "service" or record.type == "pledge") and record.status ~= "active", record.status ~= "active" and nil or "项目正在生效"
    end
    return false, "未知操作"
end

local function notifyAndRefresh(navigate, actionName, fn, id)
    local ok, message = call(fn, GD, id)
    if ok == true then
        GD.AddEvent(message or (actionName .. "成功"), "success")
    else
        GD.AddEvent(message or (actionName .. "失败"), "warning")
    end
    navigate("personalLife")
end

local function compactButton(props)
    props.fontSize = T.FontCaption
    props.height = 32
    props.paddingH = 10
    return C.ActionButton(props)
end

local function levelProgress(overview)
    local current = PL.IDENTITIES[overview.level]
    local nextIdentity = PL.IDENTITIES[overview.level + 1]
    return {
        current = overview.level,
        next = nextIdentity and nextIdentity.level or nil,
        value = overview.score,
        required = nextIdentity and nextIdentity.minScore or math.max(overview.score, current and current.minScore or 1),
        nextName = nextIdentity and nextIdentity.name or "已达最高级",
    }
end

local function dimensionRows(overview)
    local rows = {}
    for i = 1, math.min(5, #overview.dimensions) do
        local dimension = overview.dimensions[i]
        local value = tonumber(dimension.value) or 0
        local maxValue = math.max(1, tonumber(dimension.max or dimension.target) or 100)
        local ratio = math.max(0, math.min(1, value / maxValue))
        table.insert(rows, C.ProgressCard {
            title = dimension.label or ("身份维度" .. i),
            status = string.format("%.0f / %.0f", value, maxValue),
            progress = ratio * 100,
            barColor = dimension.color or T.Primary,
        })
    end
    return rows
end

function M._CreateOverview(navigate, player)
    local overview = getOverview(player)
    local progression = levelProgress(overview)
    local nextText = progression.next and ("下一等级：" .. tostring(progression.nextName or ("第" .. progression.next .. "级"))) or "已达到第12级最高身份"
    local ratio = math.max(0, math.min(1, progression.value / progression.required))

    return UI.Panel {
        width = "100%", gap = T.Gap,
        children = {
            C.Card {children = {
                C.SectionTitle {text = "当前身份：" .. overview.title, color = T.Primary},
                UI.Label {text = overview.description, fontSize = T.FontSmall, fontColor = T.TextSecondary, maxLines = 3},
                C.InfoRow {label = "当前等级", value = "第" .. overview.level .. " / 12级", color = T.Primary},
                C.InfoRow {label = "升级目标", value = nextText, color = progression.next and T.Warning or T.Success},
                C.ProgressCard {
                    title = "身份等级进度",
                    status = string.format("%.0f / %.0f", progression.value, progression.required),
                    progress = ratio * 100,
                    barColor = progression.next and T.Primary or T.Success,
                },
            }},
            UI.Panel {
                flexDirection = "row", flexWrap = "wrap", gap = 10, width = "100%",
                children = {
                    C.StatCard {title = "可用现金", value = formatMoney(overview.cash), color = T.Success, minWidth = 105},
                    C.StatCard {title = "每月月费", value = formatMoney(overview.monthlyFee), color = overview.monthlyFee > 0 and T.Warning or T.TextMuted, minWidth = 105},
                    C.StatCard {title = "社会信用", value = string.format("%.0f", overview.credit), color = overview.credit >= 60 and T.Success or T.Warning, minWidth = 105},
                },
            },
            C.SectionTitle {text = "五维身份", color = T.Info},
            UI.Panel {width = "100%", gap = 8, children = dimensionRows(overview)},
            C.Card {children = {
                C.SectionTitle {text = "生活中心说明", color = T.TextSecondary},
                UI.Label {
                    text = "购买、出售、取消与恢复均由个人生活系统执行。购买前会检查可用现金、已持有状态和社会信用门槛。",
                    fontSize = T.FontCaption, fontColor = T.TextMuted, maxLines = 3,
                },
                C.SecondaryButton {text = "返回个人中心", width = "100%", onClick = function() navigate("personal") end},
            }},
        },
    }
end

function M._CreateCatalog(navigate, category, player)
    local overview = getOverview(player)
    local owned = getOwned()
    local catalog = getCatalog(category)
    local cards = {}

    for _, item in ipairs(catalog) do
        local allowed, reason = canPurchase(item, overview, owned)
        local price = itemPrice(item)
        local monthlyFee = itemMonthlyFee(item)
        local creditRequired = itemCreditRequired(item)
        local accent = CATEGORY_COLORS[category] or T.Primary
        local details = {
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap", justifyContent = "space-between", alignItems = "flex-start", gap = 8,
                children = {
                    UI.Label {text = itemName(item), fontSize = T.FontBody, fontColor = T.TextPrimary, flexShrink = 1},
                    C.Badge {text = allowed and "可购买" or "暂不可用", variant = allowed and "success" or "warning", dot = false},
                },
            },
            UI.Label {text = item.desc or item.description or "提升个人生活质量与社会身份。", fontSize = T.FontCaption, fontColor = T.TextSecondary, maxLines = 3},
            C.InfoRow {label = "一次性投入", value = formatMoney(price), color = accent},
            C.InfoRow {label = "每月费用", value = monthlyFee > 0 and formatMoney(monthlyFee) or "无", color = monthlyFee > 0 and T.Warning or T.TextMuted},
            creditRequired > 0 and C.InfoRow {label = "社会信用要求", value = string.format("%.0f", creditRequired), color = overview.credit >= creditRequired and T.Success or T.Danger} or nil,
            item.prestige and C.InfoRow {label = "声望影响", value = "+" .. tostring(item.prestige), color = T.Primary} or nil,
            not allowed and UI.Label {text = reason or "暂不满足购买条件", fontSize = T.FontCaption, fontColor = T.Danger, maxLines = 2} or nil,
            compactButton {
                text = "购买",
                width = "100%",
                bgColor = allowed and accent or T.DisabledBg,
                fontColor = allowed and T.TextOnDark or T.TextMuted,
                disabled = not allowed,
                onClick = function()
                    notifyAndRefresh(navigate, "购买" .. itemName(item), PL.Purchase, itemId(item))
                end,
            },
        }
        table.insert(cards, C.Card {children = details})
    end

    return UI.Panel {
        width = "100%", gap = T.Gap,
        children = {
            C.Card {children = {
                C.SectionTitle {text = CATEGORY_TITLE[category] or "个人生活项目", color = CATEGORY_COLORS[category] or T.Primary},
                C.InfoRow {label = "当前现金", value = formatMoney(overview.cash), color = T.Success},
                C.InfoRow {label = "当前社会信用", value = string.format("%.0f", overview.credit), color = T.Info},
                UI.Label {text = "每个购买按钮都会在提交前按现金、持有状态与信用限制校验。", fontSize = T.FontCaption, fontColor = T.TextMuted, maxLines = 2},
            }},
            #cards > 0 and UI.Panel {width = "100%", gap = 8, children = cards} or C.Card {children = {
                UI.Label {text = "该分类暂时没有可展示项目。", fontSize = T.FontSmall, fontColor = T.TextMuted},
            }},
        },
    }
end

local function ownedStatus(record)
    if itemActive(record) then return "生效中", "success" end
    return "已取消", "warning"
end

function M._CreateOwned(navigate, player)
    local overview = getOverview(player)
    local records = getOwned()
    local cards = {}
    local monthlyTotal = 0

    for _, record in ipairs(records) do
        monthlyTotal = monthlyTotal + itemMonthlyFee(record)
        local statusText, statusVariant = ownedStatus(record)
        local sellAllowed, sellReason = canOperate("sell", record, overview)
        local cancelAllowed, cancelReason = canOperate("cancel", record, overview)
        local reactivateAllowed, reactivateReason = canOperate("reactivate", record, overview)
        local buttons = {}

        if record.type == "asset" and record.status ~= "sold" then
            table.insert(buttons, compactButton {
                text = "出售",
                width = "31%",
                bgColor = sellAllowed and T.Warning or T.DisabledBg,
                fontColor = sellAllowed and T.TextOnDark or T.TextMuted,
                disabled = not sellAllowed,
                onClick = function()
                    notifyAndRefresh(navigate, "出售" .. itemName(record), PL.SellAsset, itemId(record))
                end,
            })
        end
        if itemActive(record) and (record.type == "service" or record.type == "pledge") then
            table.insert(buttons, compactButton {
                text = "暂停",
                width = "31%",
                bgColor = cancelAllowed and T.Danger or T.DisabledBg,
                fontColor = cancelAllowed and T.TextOnDark or T.TextMuted,
                disabled = not cancelAllowed,
                onClick = function()
                    notifyAndRefresh(navigate, "暂停" .. itemName(record), PL.Cancel, itemId(record))
                end,
            })
        elseif (record.type == "service" or record.type == "pledge")
            and not itemActive(record) then
            table.insert(buttons, compactButton {
                text = "恢复",
                width = "48%",
                bgColor = reactivateAllowed and T.Success or T.DisabledBg,
                fontColor = reactivateAllowed and T.TextOnDark or T.TextMuted,
                disabled = not reactivateAllowed,
                onClick = function()
                    notifyAndRefresh(navigate, "恢复" .. itemName(record), PL.Reactivate, itemId(record))
                end,
            })
        end

        local limitation = nil
        if not sellAllowed and sellReason then limitation = sellReason end
        if itemActive(record) and not cancelAllowed and cancelReason then limitation = cancelReason end
        if not itemActive(record) and not reactivateAllowed and reactivateReason then limitation = reactivateReason end

        table.insert(cards, C.Card {children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = itemName(record),
                        fontSize = T.FontBody,
                        fontColor = T.TextPrimary,
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        minWidth = 0,
                        whiteSpace = "normal",
                        maxLines = 2,
                    },
                    C.Badge {text = statusText, variant = statusVariant, dot = false},
                },
            },
            C.InfoRow {label = "分类", value = CATEGORY_TITLE[record.category] or record.category or "个人持有"},
            C.InfoRow {label = "购入成本", value = formatMoney(itemPrice(record)), color = T.Info},
            C.InfoRow {label = "当前月费", value = itemMonthlyFee(record) > 0 and formatMoney(itemMonthlyFee(record)) or "无", color = itemMonthlyFee(record) > 0 and T.Warning or T.TextMuted},
            limitation and UI.Label {text = limitation, fontSize = T.FontCaption, fontColor = T.Danger, maxLines = 2} or nil,
            #buttons > 0 and UI.Panel {width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, children = buttons} or nil,
        }})
    end

    return UI.Panel {
        width = "100%", gap = T.Gap,
        children = {
            UI.Panel {
                flexDirection = "row", flexWrap = "wrap", gap = 10, width = "100%",
                children = {
                    C.StatCard {title = "持有项目", value = tostring(#records), color = T.Primary, minWidth = 105},
                    C.StatCard {title = "每月月费", value = formatMoney(monthlyTotal), color = monthlyTotal > 0 and T.Warning or T.TextMuted, minWidth = 105},
                },
            },
            #cards > 0 and UI.Panel {width = "100%", gap = 8, children = cards} or C.Card {children = {
                C.SectionTitle {text = "尚无个人持有", color = T.TextSecondary},
                UI.Label {text = "可在私人资产、健康服务、进修成长、圈层活动和公益项目中购买个人生活项目。", fontSize = T.FontCaption, fontColor = T.TextMuted, maxLines = 3},
            }},
        },
    }
end

function M.Create(navigate)
    local player = getPlayer()
    local active = math.max(1, math.min(#TABS, M._activeTab))
    M._activeTab = active
    local content
    if active == 1 then
        content = M._CreateOverview(navigate, player)
    elseif active == 7 then
        content = M._CreateOwned(navigate, player)
    else
        content = M._CreateCatalog(navigate, TAB_CATEGORY[active], player)
    end

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 14,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    C.SecondaryButton {
                        text = "返回个人中心",
                        height = 34,
                        flexGrow = 1,
                        flexBasis = 120,
                        flexShrink = 1,
                        onClick = function() navigate("personal") end,
                    },
                    UI.Label {
                        text = "个人生活",
                        fontSize = T.FontTitle,
                        fontColor = T.TextPrimary,
                        fontWeight = "bold",
                        flexGrow = 1,
                        flexBasis = 100,
                        flexShrink = 1,
                        minWidth = 0,
                        maxLines = 1,
                    },
                },
            },
            C.TabBar {
                tabs = TABS,
                active = active,
                onChange = function(index)
                    M._activeTab = index
                    navigate("personalLife")
                end,
            },
            content,
            UI.Panel {height = 20},
        },
    }
end

return M
