---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- CompanyCreateScreen.lua - 公司创立(股份有限公司，按性质/特质分变体)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local GV = require("Governance")

local M = {}

M._state = nil
M._presetCity = nil

function M.SetPresetCity(cityName)
    M._presetCity = cityName
    if M._state then
        M._state.selectedCity = cityName or M._state.selectedCity
        M._state.cityLocked = cityName ~= nil
    end
end

-- ============================================================================
-- 城市等级描述与资本倍率
-- ============================================================================
local CITY_TIER_INFO = {
    [3] = {label = "城市", tag = "", tagColor = T.Accent, desc = "政策宽松，竞争小，适合起步", capitalMult = 1.0},
}

--- 根据股权预设和城市等级，计算实际资本选项
---@param presetId string
---@param cityTier number
---@return number[]
local function GetCapitalOptions(presetId, cityTier)
    local preset = GV.EQUITY_PRESETS[presetId]
    if not preset then return {500} end
    local base = preset.capitalOptions
    local mult = CITY_TIER_INFO[cityTier] and CITY_TIER_INFO[cityTier].capitalMult or 1.0
    if mult == 1.0 then return base end
    local result = {}
    for _, v in ipairs(base) do
        table.insert(result, math.floor(v * mult))
    end
    return result
end

--- 获取选中城市的tier
local function GetSelectedCityTier(cityName)
    for _, c in ipairs(GD.cities) do
        if c.name == cityName then return c.tier end
    end
    return 3
end

-- 内部刷新函数：保存滚动位置 → 重建 → 延迟恢复滚动位置
local function RefreshInPlace(navigate)
    -- 尝试获取当前滚动位置
    local savedScrollY = 0
    local oldRoot = UI.GetRoot()
    if oldRoot then
        local sv = oldRoot:FindById("companyCreateScroll")
        if sv and sv.GetScroll then
            local _, sy = sv:GetScroll()
            if sy > 1 then
                savedScrollY = sy
            end
        end
    end

    local newContent = M.Create(navigate)
    UI.SetRoot(newContent)

    -- 延迟恢复滚动位置（通过全局变量让 HandleUpdate 在布局完成后恢复）
    if savedScrollY > 0 and SetPendingScrollRestore then
        SetPendingScrollRestore("companyCreateScroll", savedScrollY)
    end
end

function M.Create(navigate)
    -- 内部刷新回调（选项切换时不经过 navigate，避免页面跳动）
    local function refresh()
        RefreshInPlace(navigate)
    end

    -- 初始化状态(仅首次)
    if not M._state then
        local defaultPreset = GV.EQUITY_PRESETS[GV.PRESET_ORDER[1]]
        local defaultCity = M._presetCity or "兰德市"
        M._state = {
            companyName = "",
            nature = "llc",
            founderTrait = "balanced",
            capital = defaultPreset.capitalOptions[1],
            customCapitalInput = tostring(defaultPreset.capitalOptions[1]),
            manualCapital = false,
            selectedCity = defaultCity,
            cityLocked = M._presetCity ~= nil,
            equityPreset = GV.PRESET_ORDER[1],
        }
    end
    local state = M._state

    local groupActive = GD.GroupSystem and GD.GroupSystem.IsActive(GD)
    local availablePersonalCash = GD.player and (GD.player.cash or 0) or (GD.Personal and GD.Personal.INITIAL_PERSONAL_CASH or 3000)
    local availableCapitalCash = groupActive and (GD.group.cash or 0) or availablePersonalCash

    -- 当前城市等级 & 当前股权预设
    local cityTier = GetSelectedCityTier(state.selectedCity)
    local tierInfo = CITY_TIER_INFO[cityTier] or CITY_TIER_INFO[3]
    local currentPreset = GV.EQUITY_PRESETS[state.equityPreset] or GV.EQUITY_PRESETS.sole

    -- 注册资本选项根据城市等级调整
    local capitalOptions = GetCapitalOptions(state.equityPreset, cityTier)
    state.customCapitalInput = state.customCapitalInput or tostring(state.capital or capitalOptions[1])
    if state.manualCapital then
        local customCapital = math.floor(tonumber(state.customCapitalInput) or state.capital or capitalOptions[1])
        state.capital = math.max(1, customCapital)
    else
        local capitalValid = false
        for _, v in ipairs(capitalOptions) do
            if v == state.capital then capitalValid = true; break end
        end
        if not capitalValid then
            state.capital = capitalOptions[1]
            state.customCapitalInput = tostring(state.capital)
        end
    end

    -- 当前城市数据
    local selectedCityData = nil
    for _, c in ipairs(GD.cities) do
        if c.name == state.selectedCity then selectedCityData = c; break end
    end
    selectedCityData = selectedCityData or GD.cities[#GD.cities]

    -- ======== 企业性质按钮 ========
    local natureConfigs = {
        {key="llc",          label="有限责任公司", desc="以认缴出资额为限承担责任，决策灵活，适合中小企业"},
        {key="joint_stock",  label="股份制企业",   desc="资本划分为等额股份，便于融资扩张，适合做大做强"},
    }
    local natureBtns = {}
    for _, nc in ipairs(natureConfigs) do
        local isSelected = (state.nature == nc.key)
        table.insert(natureBtns, UI.Panel {
            flexGrow = 1,
            flexBasis = 0,
            padding = 10,
            backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and T.Accent or T.TabInactiveBorder,
            alignItems = "center",
            gap = 4,
            onClick = function()
                state.nature = nc.key
                refresh()
            end,
            children = {
                UI.Label {
                    text = nc.label,
                    fontSize = T.FontBody,
                    fontColor = isSelected and T.Primary or T.TabInactiveFont,
                    fontWeight = "bold",
                    textAlign = "center",
                },
                UI.Label {
                    text = nc.desc,
                    fontSize = T.FontCaption,
                    fontColor = isSelected and T.Primary or T.TabInactiveFont,
                    textAlign = "center",
                },
            },
        })
    end

    -- ======== 创始人特质按钮 ========
    local traitConfigs = {
        {key="balanced",   label="均衡发展",     icon="⚖", buff="无特殊加成", debuff="无特殊减益", color=T.Info},
        {key="fast_turn",  label="高周转派",     icon="⚡", buff="建设速度+15%", debuff="质量风险+20%", color=T.Warning},
        {key="quality",    label="品质坚守者",   icon="🏅", buff="品牌溢价+25%", debuff="建安成本+10%", color=T.Success},
        {key="capital",    label="资本运作高手", icon="💰", buff="融资成本-2%",  debuff="债务风险+15%", color=T.Accent},
        {key="government", label="政府关系型",   icon="🏛", buff="报建速度+30%", debuff="合规风险+10%", color=T.PrimaryDark},
    }

    local traitCards = {}
    for _, tc in ipairs(traitConfigs) do
        local isSelected = (state.founderTrait == tc.key)
        table.insert(traitCards, UI.Panel {
            width = "48%",
            padding = 10,
            backgroundColor = isSelected and {tc.color[1], tc.color[2], tc.color[3], 30} or T.TabInactiveBg,
            borderRadius = 8,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and tc.color or T.TabInactiveBorder,
            gap = 3,
            onClick = function()
                state.founderTrait = tc.key
                refresh()
            end,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label {text = tc.icon, fontSize = 16},
                        UI.Label {
                            text = tc.label,
                            fontSize = T.FontBody,
                            fontColor = isSelected and tc.color or T.TextPrimary,
                            fontWeight = "bold",
                        },
                    },
                },
                UI.Label {
                    text = "+" .. tc.buff,
                    fontSize = T.FontCaption,
                    fontColor = T.Success,
                },
                tc.key ~= "balanced" and UI.Label {
                    text = "-" .. tc.debuff,
                    fontSize = T.FontCaption,
                    fontColor = T.Danger,
                } or UI.Label {
                    text = "稳健中庸，适合新手",
                    fontSize = T.FontCaption,
                    fontColor = T.TextMuted,
                },
            }
        })
    end

    -- ======== 注册资本按钮 ========
    local capitalBtns = {}
    for _, cap in ipairs(capitalOptions) do
        local isSelected = (state.capital == cap)
        table.insert(capitalBtns, UI.Button {
            text = C.FormatMoney(cap),
            fontSize = T.FontSmall,
            backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isSelected and T.Primary or T.TabInactiveFont,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = isSelected and T.Accent or T.TabInactiveBorder,
            paddingHorizontal = 14,
            height = 32,
            onClick = function()
                state.capital = cap
                state.customCapitalInput = tostring(cap)
                state.manualCapital = false
                refresh()
            end,
        })
    end

    local occupiedCities = {}
    if GD.GetCompanyPortfolioSummary then
        for _, rec in ipairs(GD.GetCompanyPortfolioSummary() or {}) do
            if rec.status == "operating" and (rec.founderRatio or 0) >= 0.50 and rec.city then
                occupiedCities[rec.city] = rec.name or "已有公司"
            end
        end
    end

    -- ======== 城市按钮（每个城市最多一家正在经营的地产公司）========
    local function CityButton(city)
        local isSelected = (state.selectedCity == city.name)
        local existingCompanyName = occupiedCities[city.name]
        return UI.Button {
            text = existingCompanyName and (city.name .. "·已有公司") or city.name,
            fontSize = T.FontSmall,
            backgroundColor = existingCompanyName and T.DisabledBg or (isSelected and T.PrimaryLight or T.TabInactiveBg),
            fontColor = existingCompanyName and T.TextMuted or (isSelected and T.Primary or T.TabInactiveFont),
            borderRadius = 6,
            borderWidth = isSelected and 2 or 1,
            borderColor = isSelected and T.Accent or T.TabInactiveBorder,
            paddingHorizontal = 14,
            height = 32,
            onClick = function()
                if existingCompanyName then
                    GD.AddEvent(city.name .. "已有正在经营的地产公司“" .. existingCompanyName .. "”，每个城市最多成立一家", "warning")
                    return
                end
                state.selectedCity = city.name
                -- 城市改变，重置资本为新档位的第一个选项
                local newOpts = GetCapitalOptions(state.equityPreset, city.tier)
                state.capital = newOpts[1]
                state.customCapitalInput = tostring(state.capital)
                state.manualCapital = false
                refresh()
            end,
        }
    end
    local cityBtns = {}
    for _, c in ipairs(GD.cities) do
        table.insert(cityBtns, CityButton(c))
    end

    -- ======== 初始状态预览 ========
    local natureNameMap = {llc = "有限责任公司", joint_stock = "股份制企业"}
    local natureName = natureNameMap[state.nature] or "有限责任公司"
    local traitName = GD.company.founderTraitNames[state.founderTrait] or "均衡型"

    local traitPreview = ""
    for _, tc in ipairs(traitConfigs) do
        if tc.key == state.founderTrait then
            if tc.key == "balanced" then
                traitPreview = "无特殊加成"
            else
                traitPreview = tc.buff .. " / " .. tc.debuff
            end
            break
        end
    end

    -- 股权结构预览
    local equityPreview = {}
    local presetDef = GV.EQUITY_PRESETS[state.equityPreset]
    if presetDef then
        local shareholders = presetDef.shareholders(state.capital)
        for _, sh in ipairs(shareholders) do
            table.insert(equityPreview, sh.name .. " " .. math.floor(sh.ratio * 100) .. "%")
        end
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = T.BgDark,
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                padding = 16,
                backgroundColor = T.BgMain,
                borderColor = T.Border,
                borderWidth = 1,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 12,
                        flexGrow = 1,
                        flexBasis = 0,
                        minWidth = 0,
                        children = {
                            UI.Panel {width=4, height=22, backgroundColor=T.Accent, borderRadius=2},
                            UI.Label {
                                text = "创立房地产公司",
                                fontSize = T.FontTitle,
                                fontColor = T.TextPrimary,
                                flexShrink = 1,
                            },
                            C.SecondaryButton {
                                text = "返回",
                                width = 72,
                                height = 34,
                                paddingH = 12,
                                onClick = function()
                                    M._state = nil
                                    M._presetCity = nil
                                    navigate(GetPreviousScreen())
                                end,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Panel {
                                paddingHorizontal = 8, paddingVertical = 3,
                                backgroundColor = {T.Accent[1], T.Accent[2], T.Accent[3], 40},
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = state.selectedCity,
                                        fontSize = T.FontCaption,
                                        fontColor = T.Accent,
                                    },
                                },
                            },
                        },
                    },
                }
            },

            -- 可滚动内容区
            UI.ScrollView {
                id = "companyCreateScroll",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = T.PagePadding,
                gap = 14,
                children = {
                    -- 公司名称
                    C.Card {
                        children = {
                            C.SectionTitle {text = "公司名称"},
                            UI.TextField {
                                value = state.companyName,
                                placeholder = "请输入公司名称，如：鸿远置业",
                                width = "100%",
                                height = 40,
                                fontSize = T.FontBody,
                                borderRadius = 6,
                                paddingHorizontal = 12,
                                onChange = function(self, text)
                                    state.companyName = text
                                end,
                            },
                        }
                    },

                    -- 企业性质
                    C.Card {
                        children = {
                            C.SectionTitle {text = "企业类型"},
                            UI.Panel {
                                flexDirection = "row",
                                gap = 10,
                                children = natureBtns,
                            },
                        }
                    },

                    -- 注册城市（提前到股权结构之前）
                    C.Card {
                        children = {
                            C.SectionTitle {text = "注册城市"},
                            state.cityLocked and UI.Label {
                                text = "已从城市中心进入，默认选择" .. state.selectedCity .. "；也可在这里切换注册城市。公司成立后只能在注册城市拿地和开发项目。",
                                fontSize = T.FontCaption,
                                fontColor = T.Warning,
                            } or UI.Label {
                                text = "建议先从城市页进入后成立公司；注册后公司只能在注册城市开发项目。",
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                            },
                            -- 城市选择
                            UI.Panel {gap = 6, width = "100%", children = {
                                UI.Panel {flexDirection="row", gap=8, flexWrap="wrap", children=cityBtns},
                            }},
                            -- 选中城市详情（如果已选）
                            UI.Panel {
                                width = "100%",
                                padding = 10,
                                marginTop = 8,
                                backgroundColor = {T.Accent[1], T.Accent[2], T.Accent[3], 15},
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = {T.Accent[1], T.Accent[2], T.Accent[3], 60},
                                gap = 6,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 8,
                                        children = {
                                            UI.Label {text=state.selectedCity, fontSize=T.FontSubtitle, fontColor=T.TextPrimary, fontWeight="bold"},
                                        },
                                    },
                                    UI.Panel {
                                        flexDirection = "row", flexWrap = "wrap", gap = 8,
                                        children = {
                                            UI.Label {text="均价 " .. string.format("%.1f", selectedCityData.avgPrice / 10000) .. "万/m²", fontSize=T.FontCaption, fontColor=T.Accent},
                                            UI.Label {text="GDP " .. string.format("%.0f", selectedCityData.gdp) .. "亿", fontSize=T.FontCaption, fontColor=T.TextSecondary},
                                            UI.Label {text="人口 " .. string.format("%.0f", selectedCityData.population) .. "万", fontSize=T.FontCaption, fontColor=T.TextSecondary},
                                            UI.Label {text="竞争度 " .. math.floor(selectedCityData.compete * 100) .. "%", fontSize=T.FontCaption, fontColor=selectedCityData.compete > 0.6 and T.Danger or T.Success},
                                        },
                                    },
                                    UI.Label {
                                        text = "政策: " .. selectedCityData.policy,
                                        fontSize = T.FontCaption,
                                        fontColor = T.TextMuted,
                                    },
                                },
                            },
                        }
                    },

                    -- 股权结构选择（集团出资时固定为集团全资，否则由玩家选择）
                    C.Card {
                        children = groupActive and {
                            C.SectionTitle {text = "股权结构", color = T.Accent},
                            C.Badge {text = "集团全资子公司", variant = "success"},
                            UI.Label {
                                text = (GD.group.name or "集团") .. "承担全部注册资本并持有新公司100%股权；个人通过持有集团股权间接持有该公司。",
                                fontSize = T.FontSmall, fontColor = T.TextSecondary,
                                whiteSpace = "normal", maxLines = 4,
                            },
                        } or (function()
                            local items = {C.SectionTitle {text = "股权结构", color = T.Accent}}
                            for _, presetId in ipairs(GV.PRESET_ORDER) do
                                local preset = GV.EQUITY_PRESETS[presetId]
                                local isSelected = (state.equityPreset == presetId)
                                -- 显示当前城市等级对应的资本范围
                                local opts = GetCapitalOptions(presetId, cityTier)
                                local capMin = opts[1]
                                local capMax = opts[#opts]
                                local capRange = C.FormatMoney(capMin) .. "~" .. C.FormatMoney(capMax)
                                local divText = "分红" .. math.floor(preset.dividendRate * 100) .. "%"
                                -- 股东结构预览
                                local shPreview = ""
                                local shs = preset.shareholders(capMax)
                                for i, sh in ipairs(shs) do
                                    if i > 1 then shPreview = shPreview .. " + " end
                                    shPreview = shPreview .. sh.name .. math.floor(sh.ratio * 100) .. "%"
                                end
                                table.insert(items, UI.Panel {
                                    width = "100%",
                                    paddingVertical = 10, paddingHorizontal = 14,
                                    marginBottom = 6,
                                    backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                                    borderRadius = T.ButtonRadius,
                                    borderWidth = isSelected and 2 or 1,
                                    borderColor = isSelected and T.Accent or T.TabInactiveBorder,
                                    gap = 4,
                                    onClick = function()
                                        state.equityPreset = presetId
                                        local newOpts = GetCapitalOptions(presetId, cityTier)
                                        state.capital = newOpts[1]
                                        state.customCapitalInput = tostring(state.capital)
                                        state.manualCapital = false
                                        refresh()
                                    end,
                                    children = {
                                        UI.Panel {
                                            flexDirection = "row", alignItems = "center", gap = 10,
                                            children = {
                                                UI.Label {text = preset.icon, fontSize = 22, width = 30},
                                                UI.Panel {flexShrink = 1, children = {
                                                    UI.Label {text = preset.name, fontSize = T.FontBody, fontColor = isSelected and T.Primary or T.TabInactiveFont, fontWeight = "bold"},
                                                    UI.Label {text = preset.desc, fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.TextSecondary, marginTop = 1},
                                                }},
                                            },
                                        },
                                        UI.Panel {flexDirection = "row", gap = 12, marginTop = 2, flexWrap = "wrap", children = {
                                            UI.Label {text = "资金: " .. capRange, fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.Success},
                                            UI.Label {text = divText, fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.Warning},
                                            UI.Label {text = "结构: " .. shPreview, fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.Info},
                                        }},
                                    },
                                })
                            end
                            table.insert(items, UI.Label {
                                text = "股权结构决定启动资金范围、分红比例和股东人数",
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                            })
                            return items
                        end)()
                    },

                    -- 注册资本
                    C.Card {
                        children = {
                            C.SectionTitle {text = "注册资本"},
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6, marginBottom = 6,
                                children = {
                                    UI.Label {
                                        text = currentPreset.name .. " · " .. state.selectedCity,
                                        fontSize = T.FontCaption,
                                        fontColor = T.Accent,
                                    },
                                },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap = 8,
                                flexWrap = "wrap",
                                children = capitalBtns,
                            },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 8,
                                width = "100%",
                                children = {
                                    UI.TextField {
                                        value = state.customCapitalInput,
                                        placeholder = "手动输入注册资本(万元)",
                                        flexGrow = 1,
                                        flexBasis = 0,
                                        height = 36,
                                        fontSize = T.FontSmall,
                                        borderRadius = 6,
                                        paddingHorizontal = 10,
                                        onChange = function(self, text)
                                            state.customCapitalInput = text
                                            state.manualCapital = true
                                        end,
                                    },
                                    C.ActionButton {
                                        text = "应用",
                                        width = 72,
                                        height = 36,
                                        onClick = function()
                                            local customCapital = math.floor(tonumber(state.customCapitalInput) or 0)
                                            if customCapital <= 0 then
                                                GD.AddEvent("请输入有效注册资本", "warning")
                                                return
                                            end
                                            state.capital = customCapital
                                            state.customCapitalInput = tostring(customCapital)
                                            state.manualCapital = true
                                            refresh()
                                        end,
                                    },
                                },
                            },
                            UI.Label {
                                text = groupActive
                                    and ("当前集团现金: " .. C.FormatMoney(availableCapitalCash) .. "，注册资本将从集团账户扣除并注入全资子公司")
                                    or ("当前个人现金: " .. C.FormatMoney(availableCapitalCash) .. "，注册资本将全部从个人账户扣除并注入公司"),
                                fontSize = T.FontCaption,
                                fontColor = availableCapitalCash >= (state.capital or 0) and T.Success or T.Danger,
                                marginTop = 2,
                            },
                            UI.Label {
                                text = "注册资本即公司启动资金；可选预设，也可手动输入任意万元金额。",
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                                marginTop = 4,
                            },
                        }
                    },

                    -- 创始人特质
                    C.Card {
                        children = {
                            C.SectionTitle {text = "创始人特质"},
                            UI.Panel {
                                flexDirection = "row",
                                gap = 8,
                                flexWrap = "wrap",
                                children = traitCards,
                            },
                            UI.Label {
                                text = "特质决定公司发展方向，一经选定不可更改",
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                                marginTop = 6,
                            },
                        }
                    },

                    -- 初始状态预览
                    C.Card {
                        children = (function()
                            local items = {}
                            table.insert(items, C.SectionTitle {text = "公司初始状态预览", color = T.Info})
                            table.insert(items, C.InfoRow {label = "公司名称", value = #state.companyName >= 2 and state.companyName or "(请输入)", color = #state.companyName >= 2 and T.TextPrimary or T.TextMuted})
                            table.insert(items, C.InfoRow {label = "企业类型", value = natureName})
                            table.insert(items, C.InfoRow {label = "注册城市", value = state.selectedCity, color = T.Accent})
                            table.insert(items, C.InfoRow {label = "城市均价", value = string.format("%.1f万/m²", selectedCityData.avgPrice / 10000)})
                            table.insert(items, C.InfoRow {label = "股权结构", value = groupActive and "集团全资" or currentPreset.name, color = T.Accent})
                            if groupActive then
                                table.insert(items, C.InfoRow {label = "股东构成", value = (GD.group.name or "集团") .. " 100%", color = T.Info})
                            elseif #equityPreview > 0 then
                                table.insert(items, C.InfoRow {label = "股东构成", value = table.concat(equityPreview, "  "), color = T.Info})
                            end
                            table.insert(items, C.InfoRow {label = "注册资本", value = C.FormatMoney(state.capital), color = T.Success})
                            table.insert(items, C.InfoRow {label = "分红策略", value = groupActive and "子公司分红进入集团账户" or ("年利润的" .. math.floor(currentPreset.dividendRate * 100) .. "%"), color = T.Warning})
                            table.insert(items, C.InfoRow {label = "创始人特质", value = traitName})
                            table.insert(items, C.InfoRow {label = "特质效果", value = traitPreview, color = state.founderTrait ~= "balanced" and T.Warning or T.TextMuted})
                            table.insert(items, UI.Panel {
                                width = "100%", height = 1,
                                backgroundColor = T.Border, marginVertical = 4,
                            })
                            table.insert(items, C.InfoRow {label = "资质等级", value = "暂定级"})
                            table.insert(items, C.InfoRow {label = "可开发面积", value = "10万平米以下"})
                            table.insert(items, C.InfoRow {label = "信用分", value = "70分"})
                            table.insert(items, C.InfoRow {label = "员工", value = "0人 (需招聘)"})
                            return items
                        end)()
                    },

                    -- 确认按钮
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        paddingVertical = 12,
                        children = {
                            C.ActionButton {
                                text = "确认注册，开始经营",
                                width = "80%",
                                height = 48,
                                onClick = function()
                                    if #state.companyName < 2 then
                                        GD.AddEvent("公司名称至少2个字", "warning")
                                        return
                                    end
                                    local capital = state.capital
                                    if state.manualCapital then
                                        capital = math.floor(tonumber(state.customCapitalInput) or 0)
                                        if capital <= 0 then
                                            GD.AddEvent("请输入有效注册资本", "warning")
                                            return
                                        end
                                        state.capital = capital
                                    end
                                    GD._pendingEquityPreset = state.equityPreset
                                    local ok, msg = GD.InitCompany(
                                        state.companyName,
                                        state.nature,
                                        state.founderTrait,
                                        state.capital,
                                        state.selectedCity
                                    )
                                    if not ok then
                                        GD._pendingEquityPreset = nil
                                        GD.AddEvent(msg or "公司注册失败", "warning")
                                        return
                                    end
                                    M._state = nil
                                    M._presetCity = nil
                                    navigate("dashboard")
                                end,
                            },
                        }
                    },

                    -- 底部留白
                    UI.Panel {height = 30},
                }
            },
        }
    }
end

return M
