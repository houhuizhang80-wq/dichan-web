-- ============================================================================
-- InheritanceScreen.lua - 掌门人去世后的专用继承页面
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local PS = GD.Personal

local M = {}
M._selectedHeirName = nil

local function InfoRow(label, value, color)
    return C.InfoRow {label = label, value = value, color = color}
end

local function BuildHeirCards(children, navigate)
    local cards = {}
    for _, child in ipairs(children or {}) do
        local isSelected = M._selectedHeirName == child.name
        local spouseText = child.spouse and (child.spouse.name .. "（" .. tostring(child.spouse.age or 0) .. "岁）") or "未成家"
        local nextCount = child.children and #child.children or 0
        table.insert(cards, UI.Button {
            text = string.format("%s（%d岁，能力%d）", child.name or "子女", child.age or 0, math.floor(child.ability or 30)),
            fontSize = T.FontBody,
            backgroundColor = isSelected and T.PrimaryLight or T.BgCard,
            fontColor = isSelected and T.Primary or T.TextPrimary,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and T.PrimaryBorder or T.Border,
            borderRadius = T.ButtonRadius,
            width = "100%",
            height = 44,
            onClick = function()
                M._selectedHeirName = child.name
                navigate("inheritance")
            end,
        })
        table.insert(cards, UI.Panel {
            width = "100%", padding = 8, marginBottom = 4,
            backgroundColor = T.Surface, borderRadius = T.CardRadius,
            children = {
                InfoRow("婚姻", spouseText, child.spouse and T.Success or T.TextMuted),
                InfoRow("下一代子女", tostring(nextCount) .. "人", nextCount > 0 and T.Success or T.Warning),
            }
        })
    end
    return cards
end

function M.Create(navigate)
    local p = GD.player
    local co = GD.company
    local fam = p and p.family or {}
    local children = fam.children or {}

    GD.paused = true

    if not co.showHeirSelection then
        return UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center", gap = 12,
            backgroundColor = T.BgMain,
            children = {
                UI.Label {text = "当前没有待处理的继承事项", fontSize = T.FontTitle, fontColor = T.TextPrimary},
                C.ActionButton {text = "返回总览", onClick = function() navigate("dashboard") end},
            }
        }
    end

    if not M._selectedHeirName and #children > 0 then
        local heir = PS.FindSuccessionHeir(p, true)
        M._selectedHeirName = heir and heir.name or children[1].name
    end

    local preview = PS.GetInheritancePreview(GD, M._selectedHeirName) or {}
    local heir = preview.heir
    local deceasedName = co.inheritanceDeceasedName or p.founderName or "掌门人"
    local deceasedAge = co.inheritanceDeceasedAge or p.founderAge or 0
    local shortage = preview.shortage or 0
    local cashAvailable = preview.cashAvailable or 0

    local childrenPanels = {
        C.SectionTitle {text = "掌门人继承", color = T.Danger},
        C.Card {children = {
            UI.Label {text = deceasedName .. "已去世，享年" .. tostring(deceasedAge) .. "岁。", fontSize = T.FontSubtitle, fontColor = T.Danger},
            UI.Label {text = "游戏已暂停。必须完成继承后才能继续经营。", fontSize = T.FontBody, fontColor = T.TextSecondary},
        }},
        C.SectionTitle {text = "选择继承人", color = T.Primary},
    }

    local heirCards = BuildHeirCards(children, navigate)
    if #heirCards == 0 then
        table.insert(childrenPanels, C.Card {children = {
            UI.Label {text = "无子女可继承", fontSize = T.FontSubtitle, fontColor = T.Danger},
            UI.Label {text = "当前掌门人没有可继承子女，请返回危机处理。", fontSize = T.FontBody, fontColor = T.TextSecondary},
        }})
    else
        table.insert(childrenPanels, UI.Panel {width = "100%", gap = 8, children = heirCards})
    end

    table.insert(childrenPanels, C.SectionTitle {text = "遗产税与延期缴纳", color = T.Warning})
    table.insert(childrenPanels, C.Card {children = {
        InfoRow("遗产总估值", GD.FormatMoney(preview.totalWealth or 0), T.Accent),
        InfoRow("遗产税率", tostring(math.floor((preview.taxRate or 0) * 100)) .. "%", T.Warning),
        InfoRow("应缴遗产税", GD.FormatMoney(preview.taxAmount or 0), T.Danger),
        InfoRow("当前个人现金", GD.FormatMoney(cashAvailable), cashAvailable >= (preview.taxAmount or 0) and T.Success or T.Warning),
        InfoRow("当前资金缺口", GD.FormatMoney(shortage), shortage > 0 and T.Warning or T.Success),
        UI.Label {
            text = "继承完成后不会自动清算投资、扣缴税款或办理抵押贷款。继承人有6个月时间筹集个人资金缴税；可在个人贷款页申请个人信用贷款后再手动缴纳。逾期未缴时，系统才会自动办理遗产资产抵押贷款并由个人承担月供。",
            fontSize = T.FontSmall, fontColor = T.TextSecondary,
            whiteSpace = "normal", maxLines = 6,
        },
    }})

    table.insert(childrenPanels, C.ActionButton {
        text = heir and ("确认由 " .. heir.name .. " 继承并继续游戏") or "请选择继承人",
        bgColor = heir and T.Success or T.TextMuted,
        disabled = not heir,
        width = "100%",
        height = 48,
        onClick = function()
            if not heir then return end
            local ok, msg = PS.ResolveInheritance(GD, heir.name)
            if ok then
                M._selectedHeirName = nil
                navigate("personal")
            else
                GD.AddEvent(msg or "继承失败", "danger")
                navigate("inheritance")
            end
        end,
    })

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 14,
        backgroundColor = T.BgMain,
        children = childrenPanels,
    }
end

return M
