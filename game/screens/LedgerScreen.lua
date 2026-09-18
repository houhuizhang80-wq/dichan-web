-- ============================================================================
-- LedgerScreen.lua - 月度明细账单
-- ============================================================================

local UI = require("urhox-libs/UI")
local T  = require("UITheme")
local GD = require("GameData")

local M = {}

--- 格式化金额
local function FM(amount)
    if math.abs(amount) >= 10000 then
        return string.format("%.2f亿", amount / 10000)
    elseif math.abs(amount) >= 1 then
        return string.format("%.1f万", amount)
    else
        return string.format("%.2f万", amount)
    end
end

--- 构建单条明细行
local function buildEntry(entry)
    local isIncome = entry.type == "income"
    local color = isIncome and T.Success or T.Danger
    local sign = isIncome and "+" or "-"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 6,
        paddingHorizontal = 10,
        borderBottomWidth = 1,
        borderColor = T.BorderLight,
        children = {
            -- 分类标签
            UI.Panel {
                paddingHorizontal = 6,
                paddingVertical = 2,
                backgroundColor = isIncome and T.SuccessBg or T.DangerBg,
                borderRadius = 4,
                children = {
                    UI.Label {
                        text = entry.category,
                        fontSize = 10,
                        fontColor = color,
                    },
                },
            },
            -- 描述
            UI.Label {
                text = entry.desc,
                fontSize = 12,
                fontColor = T.TextSecondary,
                marginLeft = 8,
                flexShrink = 1,
                flexGrow = 1,
            },
            -- 金额
            UI.Label {
                text = sign .. FM(entry.amount),
                fontSize = 13,
                fontColor = color,
                fontWeight = "bold",
                marginLeft = 8,
            },
        },
    }
end

--- 构建月度汇总头
local function buildSummaryHeader(summary, year, month)
    local profit = summary.totalIncome - summary.totalExpense
    local profitColor = profit >= 0 and T.Success or T.Danger

    return UI.Panel {
        width = "100%",
        backgroundColor = T.BgCard,
        borderRadius = 8,
        padding = 12,
        gap = 8,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {
                        text = string.format("%d年%d月 收支明细", year, month),
                        fontSize = 16,
                        fontColor = T.TextPrimary,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                },
            },
            -- 收支汇总
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 12,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        paddingVertical = 8,
                        paddingHorizontal = 10,
                        backgroundColor = T.SuccessBg,
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label { text = "收入", fontSize = 11, fontColor = T.TextMuted },
                            UI.Label {
                                text = "+" .. FM(summary.totalIncome),
                                fontSize = 14,
                                fontColor = T.Success,
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        paddingVertical = 8,
                        paddingHorizontal = 10,
                        backgroundColor = T.DangerBg,
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label { text = "支出", fontSize = 11, fontColor = T.TextMuted },
                            UI.Label {
                                text = "-" .. FM(summary.totalExpense),
                                fontSize = 14,
                                fontColor = T.Danger,
                                fontWeight = "bold",
                            },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        paddingVertical = 8,
                        paddingHorizontal = 10,
                        backgroundColor = T.BgInput,
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label { text = "净利润", fontSize = 11, fontColor = T.TextMuted },
                            UI.Label {
                                text = (profit >= 0 and "+" or "") .. FM(profit),
                                fontSize = 14,
                                fontColor = profitColor,
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 构建一个月的明细列表
local function buildMonthSection(entries, year, month)
    local summary = GD.GetLedgerSummary(entries)
    local children = { buildSummaryHeader(summary, year, month) }

    -- 按分类分组
    local incomeEntries = {}
    local expenseEntries = {}
    for _, e in ipairs(entries) do
        if e.type == "income" then
            table.insert(incomeEntries, e)
        else
            table.insert(expenseEntries, e)
        end
    end

    -- 收入条目
    if #incomeEntries > 0 then
        table.insert(children, UI.Label {
            text = "── 收入明细 ──",
            fontSize = 12,
            fontColor = T.Success,
            marginTop = 8,
            marginBottom = 4,
            alignSelf = "center",
        })
        for _, e in ipairs(incomeEntries) do
            table.insert(children, buildEntry(e))
        end
    end

    -- 支出条目
    if #expenseEntries > 0 then
        table.insert(children, UI.Label {
            text = "── 支出明细 ──",
            fontSize = 12,
            fontColor = T.Danger,
            marginTop = 8,
            marginBottom = 4,
            alignSelf = "center",
        })
        for _, e in ipairs(expenseEntries) do
            table.insert(children, buildEntry(e))
        end
    end

    -- 无数据
    if #entries == 0 then
        table.insert(children, UI.Label {
            text = "本月暂无收支记录",
            fontSize = 13,
            fontColor = T.TextMuted,
            marginTop = 20,
            alignSelf = "center",
        })
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = T.BgCard,
        borderRadius = 8,
        padding = 10,
        gap = 2,
        marginBottom = 12,
        children = children,
    }
end

function M.Create(navigate)
    local contentChildren = {}

    -- 当月
    local currentEntries = GD.monthlyLedger or {}
    if #currentEntries > 0 then
        table.insert(contentChildren, buildMonthSection(currentEntries, GD.year, GD.month))
    else
        -- 当月无数据，显示提示
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            backgroundColor = T.BgCard,
            borderRadius = 8,
            padding = 16,
            alignItems = "center",
            children = {
                UI.Label {
                    text = string.format("%d年%d月（当前）", GD.year, GD.month),
                    fontSize = 15,
                    fontColor = T.TextPrimary,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "月度结算后将显示收支明细",
                    fontSize = 12,
                    fontColor = T.TextMuted,
                    marginTop = 8,
                },
            },
        })
    end

    -- 历史月份
    for _, hist in ipairs(GD.ledgerHistory or {}) do
        table.insert(contentChildren, buildMonthSection(hist.entries, hist.year, hist.month))
    end

    -- 无历史数据提示
    if #(GD.ledgerHistory or {}) == 0 and #currentEntries == 0 then
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            padding = 30,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无账单数据",
                    fontSize = 14,
                    fontColor = T.TextMuted,
                },
                UI.Label {
                    text = "经营一段时间后，每月的收支明细将在此展示",
                    fontSize = 12,
                    fontColor = T.TextMuted,
                    marginTop = 8,
                },
            },
        })
    end

    -- 返回按钮
    local backBtn = UI.Button {
        text = "← 返回",
        variant = "outline",
        size = "sm",
        onClick = function() navigate("dashboard") end,
    }

    return UI.ScrollView {
        id = "ledgerScroll",
        width = "100%",
        height = "100%",
        children = {
            UI.Panel {
                width = "100%",
                padding = 12,
                gap = 10,
                children = {
                    -- 顶部导航
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        width = "100%",
                        gap = 10,
                        children = {
                            backBtn,
                            UI.Label {
                                text = "财务明细账单",
                                fontSize = 18,
                                fontColor = T.TextPrimary,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "当前公司：" .. tostring(GD.company and GD.company.name or "未命名公司")
                                    .. "；仅显示当前公司，不含集团、其他公司和个人账户。",
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                                flexGrow = 1, flexBasis = 0, flexShrink = 1, minWidth = 0,
                                whiteSpace = "normal", maxLines = 3,
                            },
                        },
                    },
                    -- 内容
                    table.unpack(contentChildren),
                },
            },
        },
    }
end

return M
