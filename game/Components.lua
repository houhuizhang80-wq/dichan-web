-- ============================================================================
-- Components.lua - 复用UI组件（克制商务金融浅色系）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")

local C = {}

local function textValue(value, fallback)
    if value == nil then return fallback or "" end
    return tostring(value)
end

-- 项目页面有大量运行态数值直接传给 UI.Label；统一在项目边界转换，
-- 同时覆盖初始构建和 FindById 后的动态 SetText 更新。
if not UI.Label._projectScalarTextNormalized then
    local labelInit = UI.Label.Init
    local labelSetText = UI.Label.SetText

    function UI.Label:Init(props)
        props = props or {}
        if props.text ~= nil then
            props.text = textValue(props.text)
        end
        return labelInit(self, props)
    end

    function UI.Label:SetText(value)
        return labelSetText(self, textValue(value))
    end

    UI.Label._projectScalarTextNormalized = true
end

-- ============================================================================
-- StatCard - 指标卡片
-- ============================================================================
function C.StatCard(props)
    local color = props.color or T.TextPrimary
    local bgColor = props.bgColor or T.BgCard
    return UI.Panel {
        flexGrow = props.flexGrow or 1,
        flexBasis = 0,
        minWidth = props.minWidth or 120,
        padding = props.padding or 14,
        gap = props.gap or 6,
        backgroundColor = bgColor,
        borderRadius = T.CardRadius,
        borderWidth = T.DividerWidth,
        borderColor = T.Border,
        boxShadow = T.ShadowCard,
        children = {
            UI.Label {
                text = textValue(props.title),
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                flexShrink = 1,
                minWidth = 0,
                whiteSpace = "normal",
                maxLines = props.titleMaxLines or 2,
            },
            UI.Label {
                text = textValue(props.value, "0"),
                fontSize = props.valueFontSize or T.FontTitle,
                fontColor = color,
                fontWeight = "bold",
                flexShrink = 1,
                minWidth = 0,
                whiteSpace = "normal",
                maxLines = props.valueMaxLines or 2,
            },
            props.subtitle and UI.Label {
                text = textValue(props.subtitle),
                fontSize = T.FontCaption,
                fontColor = props.subtitleColor or T.TextMuted,
                flexShrink = 1,
                minWidth = 0,
                whiteSpace = "normal",
                maxLines = props.subtitleMaxLines or 2,
            } or nil,
        }
    }
end

-- ============================================================================
-- InfoRow - 标签值对
-- ============================================================================
function C.InfoRow(props)
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "flex-start",
        width = "100%",
        gap = 10,
        paddingVertical = 4,
        children = {
            UI.Label {
                text = textValue(props.label),
                fontSize = T.FontBody,
                fontColor = T.TextSecondary,
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                minWidth = 0,
                whiteSpace = "normal",
                maxLines = props.labelMaxLines or 2,
            },
            UI.Label {
                text = textValue(props.value),
                fontSize = T.FontBody,
                fontColor = props.color or T.TextPrimary,
                textAlign = "right",
                width = props.valueWidth or "45%",
                flexGrow = props.valueGrow or 0,
                flexShrink = 0,
                whiteSpace = "normal",
                maxLines = props.valueMaxLines or 2,
            },
        }
    }
end

-- ============================================================================
-- SectionTitle - 区域标题
-- ============================================================================
function C.SectionTitle(props)
    return UI.Panel {
        width = props.width or "100%",
        flexGrow = props.flexGrow,
        flexBasis = props.flexBasis,
        flexShrink = props.flexShrink,
        minWidth = props.minWidth,
        minHeight = 22,
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 8,
        marginBottom = 4,
        children = {
            UI.Panel {
                width = 4,
                height = 18,
                flexShrink = 0,
                backgroundColor = props.color or T.Accent,
            },
            UI.Label {
                text = textValue(props.text),
                fontSize = T.FontSubtitle,
                fontColor = T.TextPrimary,
                flexGrow = 1,
                flexShrink = 1,
                minWidth = 0,
                whiteSpace = "normal",
                maxLines = props.maxLines or 2,
            },
        }
    }
end

-- ============================================================================
-- ProgressCard - 带进度条的卡片
-- ============================================================================
function C.ProgressCard(props)
    local progress = props.progress or 0
    local barColor = props.barColor or T.Accent
    return UI.Panel {
        width = "100%",
        padding = 14,
        gap = 8,
        backgroundColor = T.BgCard,
        borderRadius = T.CardRadius,
        borderWidth = T.DividerWidth,
        borderColor = T.Border,
        boxShadow = T.ShadowCard,
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                width = "100%",
                children = {
                    UI.Label {
                        text = textValue(props.title),
                        fontSize = T.FontBody,
                        fontColor = T.TextPrimary,
                    },
                    UI.Label {
                        text = textValue(props.status, math.floor(progress) .. "%"),
                        fontSize = T.FontSmall,
                        fontColor = T.TextSecondary,
                    },
                }
            },
            -- 进度条
            UI.Panel {
                width = "100%",
                height = 12,
                backgroundColor = T.TrackBg or T.Border,
                borderWidth = 2,
                borderColor = T.Border,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = math.max(1, progress) .. "%",
                        height = "100%",
                        backgroundColor = barColor,
                    }
                }
            },
        }
    }
end

-- ============================================================================
-- EventItem - 事件日志条目
-- ============================================================================
function C.EventItem(props)
    local typeColors = {
        success = T.Success,
        warning = T.Warning,
        danger = T.Danger,
        info = T.Info,
    }
    local dotColor = typeColors[props.type] or T.Info
    return UI.Panel {
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 8,
        width = "100%",
        paddingVertical = 5,
        children = {
            UI.Panel {
                width = 6,
                height = 6,
                backgroundColor = dotColor,
                marginTop = 5,
            },
            UI.Panel {
                flexGrow = 1,
                flexBasis = 0,
                gap = 2,
                children = {
                    UI.Label {
                        text = textValue(props.text),
                        fontSize = T.FontSmall,
                        fontColor = T.TextPrimary,
                        maxLines = 2,
                    },
                    UI.Label {
                        text = props.time or "",
                        fontSize = T.FontCaption,
                        fontColor = T.TextMuted,
                    },
                }
            }
        }
    }
end

-- ============================================================================
-- ActionButton - 主操作按钮
-- ============================================================================
function C.ActionButton(props)
    local bgColor = props.bgColor or T.Accent
    return UI.Button {
        text = props.text or "确认",
        fontSize = T.FontBody,
        backgroundColor = bgColor,
        fontColor = props.fontColor or T.TextOnDark,
        borderRadius = T.ButtonRadius,
        borderWidth = props.borderWidth or 1,
        borderColor = props.borderColor or T.PrimaryBorder,
        paddingHorizontal = props.paddingH or 20,
        height = props.height or 40,
        width = props.width,
        disabled = props.disabled,
        onClick = props.onClick,
    }
end

-- ============================================================================
-- SecondaryButton - 次要按钮
-- ============================================================================
function C.SecondaryButton(props)
    return UI.Button {
        text = props.text or "取消",
        fontSize = T.FontBody,
        backgroundColor = T.BgCard,
        fontColor = T.TextSecondary,
        borderRadius = T.ButtonRadius,
        borderWidth = T.DividerWidth,
        borderColor = T.Border,
        boxShadow = T.ShadowCard,
        paddingHorizontal = props.paddingH or 20,
        height = props.height or 40,
        width = props.width,
        disabled = props.disabled,
        onClick = props.onClick,
    }
end

-- ============================================================================
-- Badge - 状态标签
-- ============================================================================
function C.Badge(props)
    local colors = {
        progress = T.StatusColors.progress,
        doing   = T.StatusColors.progress,
        done    = T.StatusColors.done,
        planned = T.StatusColors.planned,
        alert   = T.StatusColors.alert,
        success = T.StatusColors.done,
        warning = T.StatusColors.alert,
        danger  = T.StatusColors.alert,
        info    = T.StatusColors.progress,
        accent  = T.StatusColors.progress,
    }
    local c = colors[props.variant or "info"] or colors.info
    local dot = props.dot ~= false and UI.Panel {
        width = 6,
        height = 6,
        backgroundColor = c.dot or c.fg,
    } or nil
    return UI.Panel {
        flexDirection = "row",
        flexShrink = props.flexShrink or 0,
        maxWidth = props.maxWidth,
        alignItems = "center",
        gap = 5,
        paddingHorizontal = 10,
        paddingVertical = 3,
        backgroundColor = c.bg,
        borderWidth = 1,
        borderColor = c.fg,
        children = {
            dot,
            UI.Label {
                text = textValue(props.text),
                fontSize = T.FontCaption,
                fontColor = c.fg,
                flexShrink = 1,
                minWidth = 0,
                maxLines = 1,
            }
        }
    }
end

-- ============================================================================
-- Card - 通用卡片容器
-- ============================================================================
function C.Card(props)
    return UI.Panel {
        width = props.width or "100%",
        padding = props.padding or T.CardPadding,
        gap = props.gap or T.Gap,
        backgroundColor = T.BgCard,
        borderRadius = T.CardRadius,
        borderWidth = T.DividerWidth,
        borderColor = T.Border,
        boxShadow = T.ShadowCard,
        flexGrow = props.flexGrow,
        flexBasis = props.flexBasis,
        minWidth = props.minWidth,
        children = props.children,
    }
end

-- ============================================================================
-- InfoCard - 信息卡片（标题 + 多行 label-value 对）
-- ============================================================================
function C.InfoCard(props)
    local rows = {}
    if props.title then
        table.insert(rows, UI.Label {
            text = props.title,
            fontSize = T.FontBody,
            fontColor = T.Accent,
            fontWeight = "bold",
            marginBottom = 4,
        })
    end
    for _, r in ipairs(props.rows or {}) do
        table.insert(rows, C.InfoRow {label = r.label, value = r.value, color = r.color})
    end
    return UI.Panel {
        width = props.width or "100%",
        padding = props.padding or T.CardPadding,
        gap = 2,
        backgroundColor = T.BgCard,
        borderRadius = T.CardRadius,
        borderWidth = T.DividerWidth,
        borderColor = T.Border,
        boxShadow = T.ShadowCard,
        children = rows,
    }
end

-- ============================================================================
-- TabBar - 简易Tab栏（支持自动换行，适配多Tab场景）
-- ============================================================================
function C.TabBar(props)
    local tabs = props.tabs or {}
    local active = props.active or 1
    local children = {}
    for i, tab in ipairs(tabs) do
        local isActive = (i == active)
        table.insert(children, UI.Button {
            text = tab,
            fontSize = T.FontBody,
            backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isActive and T.Primary or T.TabInactiveFont,
            borderRadius = T.ButtonRadius,
            borderWidth = 2,
            borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
            paddingHorizontal = 14,
            height = 32,
            onClick = function()
                if props.onChange then props.onChange(i) end
            end,
        })
    end
    return UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 4,
        width = "100%",
        paddingBottom = 8,
        borderColor = T.Border,
        children = children,
    }
end

-- ============================================================================
-- MoneyText 格式化
-- ============================================================================
function C.FormatMoney(amount)
    if amount == 0 then
        return "0万"
    elseif math.abs(amount) >= 10000 then
        return string.format("%.2f亿", amount / 10000)
    elseif math.abs(amount) >= 1 then
        return string.format("%.0f万", amount)
    elseif math.abs(amount) >= 0.01 then
        return string.format("%.2f万", amount)
    else
        return "0万"
    end
end

-- ============================================================================
-- ListFold - 通用列表展开/收起工具
-- ============================================================================
C.FOLD_LIMIT = 6

function C.ShouldShowListItem(index, expanded, limit)
    limit = limit or C.FOLD_LIMIT
    return expanded == true or index <= limit
end

function C.FoldButton(props)
    local total = props.total or 0
    local limit = props.limit or C.FOLD_LIMIT
    if total <= limit then return UI.Panel {height = 0, width = "100%"} end
    local expanded = props.expanded == true
    local hidden = math.max(0, total - limit)
    return UI.Button {
        text = expanded and "▲ 收起列表" or ("▼ 展开全部 " .. total .. " 条（还有" .. hidden .. "条）"),
        fontSize = T.FontCaption,
        backgroundColor = T.Transparent,
        fontColor = T.Primary,
        borderRadius = T.ButtonRadius,
        borderWidth = 2,
        borderColor = T.PrimaryBorder,
        height = props.height or 30,
        width = props.width or "100%",
        onClick = props.onClick,
    }
end

return C
