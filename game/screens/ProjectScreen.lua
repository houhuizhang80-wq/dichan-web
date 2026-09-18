---@diagnostic disable: param-type-mismatch, assign-type-mismatch
-- ============================================================================
-- ProjectScreen.lua - 第四层: 项目开发 (完整可玩版)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local CS = require("Construction")
local DT = require("DevTypes")
local OP = require("Operations")

local M = {}
M._selectedProject = 1
M._activeTab = 1
M._conSubTab = 1

-- 自定义户型配比状态
M._customMix = nil      -- {basic=N, improved=N, luxury=N} or nil
M._selectedOpts = nil   -- {[optName]=true}
M._selectedLayout = nil -- 选中的布局方案 "row"/"courtyard"/"tower"

-- 成本展开状态
M._expandedCostCat = nil -- (reserved)
M._expandedLists = M._expandedLists or {}

local DEVELOPMENT_STATUSES = {
    permits = true, design = true, construction = true, presale = true,
    pending_settlement = true, pending_completion = true,
    pending_operations = true,
    delivery = true,
    completed = true,
    operations = true,
    mature = true,
}

function M.GetVisibleProjects()
    local projects = {}
    for _, p in ipairs(GD.projects) do
        local needsArchive = (p.status == "completed" or p.status == "operations" or p.status == "mature") and not p.salesCleared
        if DEVELOPMENT_STATUSES[p.status]
            and not p.salesCleared
            and not p._devArchived
            and p.status ~= "sold_off"
            and (needsArchive or not p._fixedAssetConverted) then
            table.insert(projects, p)
        end
    end
    return projects
end

function M.OpenProject(project, navigate)
    local projects = M.GetVisibleProjects()
    for index, candidate in ipairs(projects) do
        if candidate == project or (project.id ~= nil and tostring(candidate.id) == tostring(project.id)) then
            M._selectedProject = index
            M._activeTab = 1
            M._conSubTab = 1
            M._customMix = nil
            M._selectedOpts = nil
            M._selectedLayout = nil
            M._expandedCostCat = nil
            print("[ProjectPreview] 打开开发项目: " .. tostring(project.name or project.id or index))
            navigate("project")
            return true
        end
    end
    GD.AddEvent("该项目已不在开发管理范围内", "warning")
    navigate("project")
    return false
end

function M.Create(navigate)
    -- 只显示仍处于开发、结算、竣工确认或销售交付流程中的项目。
    -- 已清盘/已转固定资产/运营成熟项目转到营销或资产运营中心，避免在开发页残留。
    local projects = M.GetVisibleProjects()
    if #projects == 0 then
        local hint = "请先在投资发展中心竞得土地"
        if #GD.projects > 0 then
            hint = "所有项目已竣工，可前往营销销售或资产运营查看"
        end
        return UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            gap = 16,
            children = {
                UI.Label {text = "暂无在建项目", fontSize = T.FontTitle, fontColor = T.TextMuted},
                UI.Label {text = hint, fontSize = T.FontBody, fontColor = T.TextMuted},
                C.ActionButton {text = #GD.projects > 0 and "前往销售中心" or "前往投资中心", onClick = function() navigate(#GD.projects > 0 and "sales" or "invest") end},
            }
        }
    end

    local projIdx = math.min(M._selectedProject, #projects)
    local p = projects[projIdx]
    local projTabs = {}
    for i, proj in ipairs(projects) do
        table.insert(projTabs, proj.name)
    end

    local tabIdx = M._activeTab
    local cash = GD.company.cash

    -- =======================================================================
    -- Tab1: 四证办理
    -- =======================================================================
    local function BuildPermitsTab()
        local permitCards = {}

        -- 前置条件说明卡
        table.insert(permitCards, C.Card {children = {
            C.SectionTitle {text = "四证办理流程"},
            C.InfoRow {label = "公司可用现金", value = GD.FormatMoney(cash), color = cash > 0 and T.Success or T.Danger},
            UI.Label {text = "按顺序办理：用地规划→工程规划→施工许可→预售许可", fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 4},
        }})

        for idx, permit in ipairs(p.permits) do
            local capturedIdx = idx
            local statusText, statusColor, canStart
            if permit.status == "done" then
                statusText = "已取得"
                statusColor = T.Success
            elseif permit.status == "processing" then
                statusText = "办理中"
                statusColor = T.Info
            elseif permit.status == "pending" then
                statusText = "待办理"
                statusColor = T.Warning
                canStart = true
            else
                statusText = "未解锁"
                statusColor = T.TextMuted
            end

            -- 检查前置许可是否完成
            local prereqMet = true
            local prereqHint = ""
            if capturedIdx > 1 then
                local prev = p.permits[capturedIdx - 1]
                if prev.status ~= "done" then
                    prereqMet = false
                    prereqHint = "需先完成: " .. prev.name
                end
            end

            local insufficientFund = (permit.cost > 0 and cash < permit.cost)

            local cardChildren = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {text = permit.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {
                            text = statusText,
                            variant = permit.status == "done" and "success" or (permit.status == "processing" and "info" or "warning"),
                        },
                    }
                },
            }

            -- 办理中: 进度条
            if permit.status == "processing" then
                table.insert(cardChildren, C.ProgressCard {
                    title = "办理进度",
                    progress = permit.progress,
                    barColor = T.Info,
                })
            end

            -- 待办理: 操作区
            if canStart then
                -- 费用提示
                if permit.cost > 0 then
                    table.insert(cardChildren, C.InfoRow {
                        label = "办理费用",
                        value = GD.FormatMoney(permit.cost),
                        color = insufficientFund and T.Danger or T.TextSecondary,
                    })
                end
                -- 前置条件未满足提示
                if not prereqMet then
                    table.insert(cardChildren, UI.Label {
                        text = prereqHint,
                        fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 2,
                    })
                end
                -- 资金不足提示
                if insufficientFund then
                    table.insert(cardChildren, UI.Label {
                        text = "现金不足，无法办理",
                        fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 2,
                    })
                end

                local canApply = prereqMet and not insufficientFund
                table.insert(cardChildren, UI.Panel {
                    flexDirection = "row", justifyContent = "flex-end", width = "100%", marginTop = 6,
                    children = {
                        C.ActionButton {
                            text = "申请办理",
                            height = 30, paddingH = 14,
                            disabled = not canApply,
                            onClick = function()
                                permit.status = "processing"
                                GD.company.cash = GD.company.cash - permit.cost
                                GD.AddEvent("【" .. p.name .. "】开始办理 " .. permit.name, "info")
                                navigate("project")
                            end,
                        },
                    },
                })
            end

            -- 已完成: 显示完成信息
            if permit.status == "done" then
                table.insert(cardChildren, UI.Label {
                    text = "办理完成",
                    fontSize = T.FontCaption, fontColor = T.Success, marginTop = 2,
                })
            end

            table.insert(permitCards, C.Card {children = cardChildren})
        end
        return UI.Panel {width = "100%", gap = 10, children = permitCards}
    end

    -- =======================================================================
    -- Tab2: 设计管理
    -- =======================================================================
    local function BuildDesignTab()
        local d = p.design
        local pl = d.planning
        local sc = d.scheme
        local cc = d.costCap
        local rv = d.review

        local designPhases = {
            none = "未开始", concept = "概念方案", schematic = "扩初设计",
            construction_drawing = "施工图", review = "图纸审查", done = "设计完成",
        }
        local phaseName = designPhases[d.phase] or d.phase

        -- ── 卡片 1: 设计总览 ──
        local overviewChildren = {
            C.SectionTitle {text = "设计总览"},
        }
        -- 代建型提示
        if p.devCategory == "agency" and d.autoConfirmed then
            table.insert(overviewChildren, UI.Panel {
                width = "100%", padding = 8, backgroundColor = T.SuccessBg, borderRadius = 6, marginBottom = 4,
                children = {
                    UI.Label {text = "委托方已提供设计方案，规划/方案/限额已自动确认，仅需完成图纸审查即可开工。",
                        fontSize = T.FontCaption, fontColor = T.Success},
                },
            })
        end
        -- 持有型提示
        if p.devCategory == "hold" then
            local dtDef = DT.GetType(p.devTypeId)
            if dtDef then
                table.insert(overviewChildren, UI.Panel {
                    width = "100%", padding = 8, backgroundColor = T.InfoBg, borderRadius = 6, marginBottom = 4,
                    children = {
                        UI.Label {text = ((dtDef.icon ~= "" and (dtDef.icon .. " ") or "") .. dtDef.name .. " — 持有运营型，建成后通过租金/经营收益回报"),
                            fontSize = T.FontCaption, fontColor = T.Info},
                    },
                })
            end
        end
        table.insert(overviewChildren, C.InfoRow {label = "当前阶段", value = phaseName, color = d.phase == "done" and T.Success or T.Info})
        if d.phase ~= "none" and d.phase ~= "done" then
            table.insert(overviewChildren, C.ProgressCard {title = "阶段进度", progress = d.phaseProgress, barColor = T.Info})
        end
        -- 定位选择（根据开发类型差异化）
        table.insert(overviewChildren, UI.Label {text = "项目定位", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6})
        if p.devCategory == "agency" then
            -- 代建型：定位已自动确定，只读显示
            table.insert(overviewChildren, C.InfoRow {label = "定位", value = d.positioning .. " (自动)", color = T.TextSecondary})
        else
            local positionings
            if p.devCategory == "hold" then
                -- 持有型：使用专属定位选项
                positionings = GD.HOLD_POSITIONING_OPTIONS[p.devTypeId] or {"标准", "品质", "高端"}
            else
                -- 销售型：按住宅/非住宅区分
                local isResidential = (p.devTypeId == "rigid_residential" or p.devTypeId == "improved_residential" or p.devTypeId == "luxury_residential")
                if isResidential then
                    positionings = {"刚需", "改善", "高端"}
                else
                    -- 商业/文旅/产业销售型：定位已自动设定
                    positionings = nil
                    table.insert(overviewChildren, C.InfoRow {label = "定位", value = d.positioning, color = T.Accent})
                end
            end
            if positionings then
                local posButtons = {}
                for _, pos in ipairs(positionings) do
                    local capturedPos = pos
                    local sel = (d.positioning == capturedPos)
                    table.insert(posButtons, UI.Button {
                        text = capturedPos, fontSize = T.FontSmall,
                        backgroundColor = sel and T.PrimaryLight or T.BgInput,
                        fontColor = sel and T.Primary or T.TextPrimary,
                        borderRadius = 6, paddingHorizontal = 14, height = 30,
                        onClick = function()
                            d.positioning = capturedPos
                            -- 更新定位 tier
                            local tierMap = {
                                ["刚需"] = 1, ["改善"] = 2, ["高端"] = 3,
                                ["社区商业"] = 1, ["品质商业"] = 2, ["高端商业"] = 3,
                                ["标准写字楼"] = 1, ["甲级写字楼"] = 2, ["超甲写字楼"] = 3,
                                ["青年公寓"] = 1, ["品质公寓"] = 2, ["高端公寓"] = 3,
                                ["经济酒店"] = 1, ["精品酒店"] = 2, ["奢华酒店"] = 3,
                            }
                            local dd = GD.DEV_TYPE_DESIGN_DEFAULTS[p.devTypeId]
                            if dd then dd.positioningTier = tierMap[capturedPos] or 2 end
                            navigate("project")
                        end,
                    })
                end
                table.insert(overviewChildren, UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", children = posButtons})
            end
        end
        -- 外立面风格选择
        if p.devCategory == "agency" then
            -- 代建型：风格已自动确定
            local sCfg = GD.STYLE_CONFIG[d.style]
            table.insert(overviewChildren, UI.Label {text = "外立面风格", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6})
            table.insert(overviewChildren, C.InfoRow {label = "风格", value = (sCfg and sCfg.name or d.style) .. " (自动)", color = T.TextSecondary})
        else
            local styleKeys = {"modern", "chinese", "artdeco", "french"}
            local styleButtons = {}
            for _, sk in ipairs(styleKeys) do
                local cfg = GD.STYLE_CONFIG[sk]
                local sel = (d.style == sk)
                table.insert(styleButtons, UI.Button {
                    text = cfg.name, fontSize = T.FontSmall,
                    backgroundColor = sel and T.PrimaryLight or T.BgInput,
                    fontColor = sel and T.Primary or T.TextPrimary,
                    borderRadius = 6, paddingHorizontal = 12, height = 28,
                    onClick = function()
                        d.style = sk
                        navigate("project")
                    end,
                })
            end
            table.insert(overviewChildren, UI.Label {text = "外立面风格", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6})
            table.insert(overviewChildren, UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", children = styleButtons})
            -- 风格指标预览
            if d.style then
                local sCfg = GD.STYLE_CONFIG[d.style]
                if sCfg then
                    local previewItems = {
                        C.InfoRow {label = "成本系数", value = string.format("×%.2f", sCfg.costMult)},
                    }
                    if p.devCategory == "sale" then
                        table.insert(previewItems, C.InfoRow {label = "售价系数", value = string.format("×%.2f", sCfg.priceMult)})
                        table.insert(previewItems, C.InfoRow {label = "需求系数", value = string.format("×%.2f", sCfg.demandMult)})
                    else
                        -- 持有型：租金系数 = 售价系数的概念
                        table.insert(previewItems, C.InfoRow {label = "租金系数", value = string.format("×%.2f", sCfg.priceMult)})
                        table.insert(previewItems, C.InfoRow {label = "招商系数", value = string.format("×%.2f", sCfg.demandMult)})
                    end
                    table.insert(overviewChildren, UI.Panel {marginTop = 4, gap = 2, children = previewItems})
                end
            end
        end

        -- ── 卡片 2: 规划指标 ──
        local planChildren = {C.SectionTitle {text = "规划指标"}}
        if pl.confirmed then
            table.insert(planChildren, C.Badge {text = "已确认", variant = "success"})
            table.insert(planChildren, C.InfoRow {label = "容积率", value = string.format("%.2f", pl.far)})
            table.insert(planChildren, C.InfoRow {label = "建筑密度", value = string.format("%.0f%%", pl.density * 100)})
            table.insert(planChildren, C.InfoRow {label = "绿化率", value = string.format("%.0f%%", pl.greenRate * 100)})
            table.insert(planChildren, C.InfoRow {label = "限高", value = pl.heightLimit .. "m"})
            local facStr = {}
            if pl.facilities.kindergarten then table.insert(facStr, "幼儿园") end
            if pl.facilities.communityRoom then table.insert(facStr, "社区用房") end
            if pl.facilities.affordable > 0 then table.insert(facStr, "保障房" .. pl.facilities.affordable .. "%") end
            if #facStr > 0 then
                table.insert(planChildren, C.InfoRow {label = "配建", value = table.concat(facStr, " / ")})
            end
        else
            table.insert(planChildren, C.InfoRow {label = "容积率", value = string.format("%.2f (上限 %.2f)", pl.far, p.land.far or 99)})
            table.insert(planChildren, C.InfoRow {label = "建筑密度", value = string.format("%.0f%%", pl.density * 100)})
            table.insert(planChildren, C.InfoRow {label = "绿化率", value = string.format("%.0f%%", pl.greenRate * 100)})
            table.insert(planChildren, C.InfoRow {label = "限高", value = pl.heightLimit .. "m"})
            table.insert(planChildren, C.ActionButton {
                text = "确认规划指标",
                onClick = function()
                    local ok, err = GD.ConfirmPlanning(p)
                    if ok then
                        GD.AddEvent("【" .. p.name .. "】规划指标已确认", "info")
                    else
                        GD.AddEvent("规划确认失败: " .. (err or ""), "warning")
                    end
                    navigate("project")
                end,
            })
        end

        -- ── 卡片 3: 方案设计 ──
        local isHold = (p.devCategory == "hold")
        local isAgency = (p.devCategory == "agency")
        local tenantMixCfg = isHold and GD.HOLD_TENANT_MIX_CONFIG[p.devTypeId] or nil
        local mixLabel = isHold and "业态配比" or "户型配比"

        local schemeChildren = {C.SectionTitle {text = "方案设计"}}
        if sc.confirmed then
            table.insert(schemeChildren, C.Badge {text = isAgency and "自动确认" or "已确认", variant = "success"})
            local layoutName = GD.LAYOUT_CONFIG[sc.layout] and GD.LAYOUT_CONFIG[sc.layout].name or sc.layout
            table.insert(schemeChildren, C.InfoRow {label = "布局", value = layoutName})
            -- 配比显示（按类型区分）
            local mixParts = {}
            for _, um in ipairs(sc.unitMix) do
                if isHold and tenantMixCfg then
                    local tmCfg = tenantMixCfg[um.key]
                    if tmCfg then table.insert(mixParts, tmCfg.name .. um.ratio .. "%") end
                else
                    local umCfg = GD.UNIT_MIX_CONFIG[um.key]
                    if umCfg then table.insert(mixParts, umCfg.name .. um.ratio .. "%") end
                end
            end
            if #mixParts > 0 then
                table.insert(schemeChildren, C.InfoRow {label = mixLabel, value = table.concat(mixParts, " / ")})
            end
            table.insert(schemeChildren, C.InfoRow {label = isHold and "使用效率" or "得房率", value = string.format("%.0f%%", sc.efficiency * 100)})
            table.insert(schemeChildren, C.InfoRow {label = "方案评分", value = string.format("%.0f分", sc.schemeScore), color = sc.schemeScore >= 70 and T.Success or T.Warning})
        elseif isAgency then
            -- 代建型不应走到这里（CreateProject 已自动确认），但做防御
            table.insert(schemeChildren, UI.Label {text = "方案已由系统自动确认", fontSize = T.FontSmall, fontColor = T.TextMuted})
        elseif not pl.confirmed then
            table.insert(schemeChildren, UI.Label {text = "请先确认规划指标", fontSize = T.FontSmall, fontColor = T.TextMuted})
        elseif isHold and tenantMixCfg then
            -- ========== 持有型：业态配比调节 ==========
            -- 初始化持有型自定义配比
            if not M._customMix then
                M._customMix = {}
                local keys = {}
                for k, _ in pairs(tenantMixCfg) do table.insert(keys, k) end
                local evenShare = math.floor(100 / #keys)
                local remainder = 100 - evenShare * #keys
                for i, k in ipairs(keys) do
                    M._customMix[k] = evenShare + (i == 1 and remainder or 0)
                end
            end

            -- 布局选择
            table.insert(schemeChildren, UI.Label {text = "选择布局方案 (点击选择)", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4})
            local layoutKeys = {"row", "courtyard", "tower"}
            if not M._selectedLayout then M._selectedLayout = "row" end
            for _, lk in ipairs(layoutKeys) do
                local capturedLK = lk
                local cfg = GD.LAYOUT_CONFIG[capturedLK]
                local isSelected = (M._selectedLayout == capturedLK)
                table.insert(schemeChildren, UI.Panel {
                    width = "100%", padding = 8, gap = 4,
                    backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                    borderRadius = 6, marginTop = 4, borderWidth = isSelected and 2 or 1,
                    borderColor = isSelected and T.PrimaryLight or T.TabInactiveBorder,
                    onClick = function() M._selectedLayout = capturedLK; navigate("project") end,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Label {text = (isSelected and "● " or "○ ") .. cfg.name, fontSize = T.FontBody, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                            UI.Label {text = string.format("效率%.0f%%  成本×%.2f  租金×%.2f  工期×%.1f", cfg.efficiency * 100, cfg.costMult, cfg.priceMult, cfg.durationMult),
                                fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                        }},
                    },
                })
            end

            -- 业态配比调节
            table.insert(schemeChildren, UI.Label {text = "业态配比 (总计需为100%)", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 8})
            local holdMixKeys = {}
            for k, _ in pairs(tenantMixCfg) do table.insert(holdMixKeys, k) end
            table.sort(holdMixKeys)

            local mixTotal = 0
            for _, mk in ipairs(holdMixKeys) do
                mixTotal = mixTotal + (M._customMix[mk] or 0)
            end

            for _, mk in ipairs(holdMixKeys) do
                local capturedKey = mk
                local tmCfg = tenantMixCfg[capturedKey]
                local curVal = M._customMix[capturedKey] or 0
                local adjBtns = {}
                local adjustSteps = {-10, -5, 5, 10}
                for _, step in ipairs(adjustSteps) do
                    local capturedStep = step
                    local label = step > 0 and ("+" .. step) or tostring(step)
                    table.insert(adjBtns, UI.Button {
                        text = label, fontSize = T.FontCaption,
                        backgroundColor = T.BgInput, fontColor = T.TextPrimary,
                        borderRadius = 4, width = 36, height = 24,
                        onClick = function()
                            local newVal = math.max(0, math.min(100, curVal + capturedStep))
                            M._customMix[capturedKey] = newVal
                            navigate("project")
                        end,
                    })
                end
                table.insert(schemeChildren, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, width = "100%", marginTop = 2,
                    children = {
                        UI.Label {text = tmCfg.name, fontSize = T.FontSmall, fontColor = T.TextSecondary, width = 60},
                        UI.Label {text = curVal .. "%", fontSize = T.FontBody, fontColor = T.Accent, width = 36},
                        UI.Panel {flexDirection = "row", gap = 4, children = adjBtns},
                        UI.Label {text = string.format("(%d~%d㎡ 租金×%.2f)", tmCfg.areaRange[1], tmCfg.areaRange[2], tmCfg.rentMult),
                            fontSize = T.FontCaption, fontColor = T.TextMuted},
                    },
                })
            end
            if mixTotal ~= 100 then
                table.insert(schemeChildren, UI.Label {
                    text = "当前合计 " .. mixTotal .. "%，需调整至100%",
                    fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 4,
                })
            end

            -- 确认按钮（单个按钮，使用已选布局）
            local selLayout = M._selectedLayout or "row"
            local selCfg = GD.LAYOUT_CONFIG[selLayout]
            local canConfirm = (mixTotal == 100)
            table.insert(schemeChildren, UI.Panel {
                flexDirection = "row", gap = 8, marginTop = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.ActionButton {
                        text = "确认方案: " .. selCfg.name,
                        height = 36, paddingH = 16,
                        disabled = not canConfirm,
                        onClick = function()
                            local unitMix = {}
                            for _, mk2 in ipairs(holdMixKeys) do
                                local r = M._customMix[mk2] or 0
                                if r > 0 then
                                    table.insert(unitMix, {key = mk2, ratio = r})
                                end
                            end
                            local ok, err = GD.ConfirmScheme(p, selLayout, unitMix)
                            if ok then
                                GD.AddEvent("【" .. p.name .. "】方案设计确认: " .. selCfg.name, "info")
                                M._customMix = nil
                                M._selectedLayout = nil
                            else
                                GD.AddEvent("方案确认失败: " .. (err or ""), "warning")
                            end
                            navigate("project")
                        end,
                    },
                    UI.Button {
                        text = "⚡ 一键自动方案",
                        fontSize = T.FontBody, height = 36,
                        backgroundColor = T.Warning, fontColor = T.TextOnDark,
                        borderRadius = 6, paddingHorizontal = 16,
                        onClick = function()
                            local ok, err = GD.AutoConfirmScheme(p)
                            if ok then
                                M._customMix = nil
                                M._selectedLayout = nil
                            else
                                GD.AddEvent("自动方案失败: " .. (err or ""), "warning")
                            end
                            navigate("project")
                        end,
                    },
                },
            })
        else
            -- ========== 销售型：户型配比调节（原有逻辑） ==========
            -- 初始化自定义配比
            if not M._customMix then
                M._customMix = {basic = 60, improved = 30, luxury = 10}
            end

            -- 布局选择（可点击 radio 卡片）
            table.insert(schemeChildren, UI.Label {text = "选择布局方案 (点击选择)", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4})
            local layoutKeys = {"row", "courtyard", "tower"}
            if not M._selectedLayout then M._selectedLayout = "row" end
            for _, lk in ipairs(layoutKeys) do
                local capturedLK = lk
                local cfg = GD.LAYOUT_CONFIG[capturedLK]
                local isSelected = (M._selectedLayout == capturedLK)
                table.insert(schemeChildren, UI.Panel {
                    width = "100%", padding = 8, gap = 4,
                    backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                    borderRadius = 6, marginTop = 4, borderWidth = isSelected and 2 or 1,
                    borderColor = isSelected and T.PrimaryLight or T.TabInactiveBorder,
                    onClick = function() M._selectedLayout = capturedLK; navigate("project") end,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Label {text = (isSelected and "● " or "○ ") .. cfg.name, fontSize = T.FontBody, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                            UI.Label {text = string.format("得房率%.0f%%  成本×%.2f  售价×%.2f  工期×%.1f", cfg.efficiency * 100, cfg.costMult, cfg.priceMult, cfg.durationMult),
                                fontSize = T.FontCaption, fontColor = isSelected and T.Primary or T.TabInactiveFont},
                        }},
                    },
                })
            end

            -- 户型配比调节
            table.insert(schemeChildren, UI.Label {text = "户型配比 (总计需为100%)", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 8})
            local mixKeys = {"basic", "improved", "luxury"}
            local mixTotal = 0
            for _, mk in ipairs(mixKeys) do
                mixTotal = mixTotal + (M._customMix[mk] or 0)
            end

            for _, mk in ipairs(mixKeys) do
                local capturedKey = mk
                local umCfg = GD.UNIT_MIX_CONFIG[capturedKey]
                local curVal = M._customMix[capturedKey] or 0
                local adjBtns = {}
                local adjustSteps = {-10, -5, 5, 10}
                for _, step in ipairs(adjustSteps) do
                    local capturedStep = step
                    local label = step > 0 and ("+" .. step) or tostring(step)
                    table.insert(adjBtns, UI.Button {
                        text = label, fontSize = T.FontCaption,
                        backgroundColor = T.BgInput, fontColor = T.TextPrimary,
                        borderRadius = 4, width = 36, height = 24,
                        onClick = function()
                            local newVal = math.max(0, math.min(100, curVal + capturedStep))
                            M._customMix[capturedKey] = newVal
                            navigate("project")
                        end,
                    })
                end
                table.insert(schemeChildren, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, width = "100%", marginTop = 2,
                    children = {
                        UI.Label {text = umCfg.name, fontSize = T.FontSmall, fontColor = T.TextSecondary, width = 50},
                        UI.Label {text = curVal .. "%", fontSize = T.FontBody, fontColor = T.Accent, width = 36},
                        UI.Panel {flexDirection = "row", gap = 4, children = adjBtns},
                        UI.Label {text = string.format("(%d~%d㎡ 售价×%.2f)", umCfg.areaRange[1], umCfg.areaRange[2], umCfg.priceMult),
                            fontSize = T.FontCaption, fontColor = T.TextMuted},
                    },
                })
            end
            -- 配比校验提示
            if mixTotal ~= 100 then
                table.insert(schemeChildren, UI.Label {
                    text = "当前合计 " .. mixTotal .. "%，需调整至100%",
                    fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 4,
                })
            end

            -- 确认按钮（单个按钮，使用已选布局）
            local selLayout = M._selectedLayout or "row"
            local selCfg = GD.LAYOUT_CONFIG[selLayout]
            local canConfirm = (mixTotal == 100)
            table.insert(schemeChildren, UI.Panel {
                flexDirection = "row", gap = 8, marginTop = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.ActionButton {
                        text = "确认方案: " .. selCfg.name,
                        height = 36, paddingH = 16,
                        disabled = not canConfirm,
                        onClick = function()
                            local unitMix = {}
                            for _, mk2 in ipairs(mixKeys) do
                                local r = M._customMix[mk2] or 0
                                if r > 0 then
                                    table.insert(unitMix, {key = mk2, ratio = r})
                                end
                            end
                            local ok, err = GD.ConfirmScheme(p, selLayout, unitMix)
                            if ok then
                                GD.AddEvent("【" .. p.name .. "】方案设计确认: " .. selCfg.name, "info")
                                M._customMix = nil
                                M._selectedLayout = nil
                            else
                                GD.AddEvent("方案确认失败: " .. (err or ""), "warning")
                            end
                            navigate("project")
                        end,
                    },
                    UI.Button {
                        text = "⚡ 一键自动方案",
                        fontSize = T.FontBody, height = 36,
                        backgroundColor = T.Warning, fontColor = T.TextOnDark,
                        borderRadius = 6, paddingHorizontal = 16,
                        onClick = function()
                            local ok, err = GD.AutoConfirmScheme(p)
                            if ok then
                                M._customMix = nil
                                M._selectedLayout = nil
                            else
                                GD.AddEvent("自动方案失败: " .. (err or ""), "warning")
                            end
                            navigate("project")
                        end,
                    },
                },
            })
        end

        -- ── 卡片 4: 限额设计 ──
        local costCapChildren = {C.SectionTitle {text = "限额设计"}}
        if cc.confirmed then
            table.insert(costCapChildren, C.Badge {text = isAgency and "自动确认" or "已确认", variant = cc.overrun and "danger" or "success"})
            table.insert(costCapChildren, C.InfoRow {label = "钢筋用量", value = string.format("%.1f kg/㎡ (标准≤%d)", cc.steelPerSqm, GD.COST_CAP_STANDARDS.steelPerSqm)})
            table.insert(costCapChildren, C.InfoRow {label = "混凝土用量", value = string.format("%.2f m³/㎡ (标准≤%.1f)", cc.concretePerSqm, GD.COST_CAP_STANDARDS.concretePerSqm)})
            if cc.overrun then
                table.insert(costCapChildren, C.InfoRow {label = "超限罚款", value = string.format("%.0f万", cc.penalty), color = T.Danger})
            end
            local optNames = {}
            for _, o in ipairs(cc.optimizations) do table.insert(optNames, o) end
            if #optNames > 0 then
                table.insert(costCapChildren, C.InfoRow {label = "优化措施", value = table.concat(optNames, ", ")})
            end
        elseif not sc.confirmed then
            table.insert(costCapChildren, UI.Label {text = "请先确认方案设计", fontSize = T.FontSmall, fontColor = T.TextMuted})
        else
            table.insert(costCapChildren, C.InfoRow {label = "当前钢筋", value = string.format("%.1f kg/㎡ (标准≤%d)", cc.steelPerSqm, GD.COST_CAP_STANDARDS.steelPerSqm)})
            table.insert(costCapChildren, C.InfoRow {label = "当前混凝土", value = string.format("%.2f m³/㎡ (标准≤%.1f)", cc.concretePerSqm, GD.COST_CAP_STANDARDS.concretePerSqm)})
            -- 多选优化选项
            if not M._selectedOpts then M._selectedOpts = {} end
            local optChoices = {"铝模替代木模", "装配式构件", "BIM碰撞检查"}
            table.insert(costCapChildren, UI.Label {text = "选择优化措施 (可多选)", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6})
            local optBtns = {}
            for _, opt in ipairs(optChoices) do
                local capturedOpt = opt
                local isSelected = M._selectedOpts[capturedOpt] == true
                table.insert(optBtns, UI.Button {
                    text = (isSelected and "✓ " or "") .. capturedOpt,
                    fontSize = T.FontCaption,
                    backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
                    fontColor = isSelected and T.Primary or T.TabInactiveFont,
                    borderRadius = 4, paddingHorizontal = 10, height = 28,
                    borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                    onClick = function()
                        M._selectedOpts[capturedOpt] = not M._selectedOpts[capturedOpt]
                        navigate("project")
                    end,
                })
            end
            table.insert(costCapChildren, UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = optBtns})

            -- 确认按钮
            table.insert(costCapChildren, C.ActionButton {
                text = "确认限额设计",
                height = 32, paddingH = 14, marginTop = 6,
                onClick = function()
                    local opts = {}
                    for _, optName in ipairs(optChoices) do
                        if M._selectedOpts[optName] then
                            table.insert(opts, optName)
                        end
                    end
                    local ok, err = GD.ConfirmCostCap(p, opts)
                    if ok then
                        GD.AddEvent("【" .. p.name .. "】限额设计确认", "info")
                        M._selectedOpts = nil
                        M._activeTab = 3 -- 自动切到工程管理
                    else
                        GD.AddEvent("限额确认失败: " .. (err or ""), "warning")
                    end
                    navigate("project")
                end,
            })
        end

        -- ── 卡片 5: 图纸审查 ──
        local reviewChildren = {C.SectionTitle {text = "图纸审查"}}
        if d.phase == "review" or (d.phase == "done" and rv.currentStage > 0) then
            for i, stg in ipairs(rv.stages) do
                local sText, sColor
                if stg.status == "passed" then
                    sText = "✓ 通过"
                    sColor = T.Success
                elseif stg.status == "rejected" then
                    sText = "✗ 未通过 (返工中)"
                    sColor = T.Danger
                elseif i == rv.currentStage then
                    sText = "● 审查中..."
                    sColor = T.Warning
                else
                    sText = "○ 待审"
                    sColor = T.TextMuted
                end
                table.insert(reviewChildren, C.InfoRow {
                    label = stg.name, value = sText, color = sColor,
                })
            end
            -- 审查进度
            local passedCount = 0
            for _, stg in ipairs(rv.stages) do
                if stg.status == "passed" then passedCount = passedCount + 1 end
            end
            table.insert(reviewChildren, C.ProgressCard {
                title = "审查进度", progress = math.floor(passedCount / math.max(1, #rv.stages) * 100),
                barColor = T.Info,
            })
            if rv.reworkCost > 0 then
                table.insert(reviewChildren, C.InfoRow {label = "返工费用", value = string.format("%.0f万", rv.reworkCost), color = T.Danger})
            end
            if d.phase == "done" then
                table.insert(reviewChildren, C.Badge {text = "全部审查通过", variant = "success"})
            end
        elseif d.phase ~= "none" then
            table.insert(reviewChildren, UI.Label {text = "完成限额设计确认后自动进入审查", fontSize = T.FontSmall, fontColor = T.TextMuted})
        else
            table.insert(reviewChildren, UI.Label {text = "设计尚未开始", fontSize = T.FontSmall, fontColor = T.TextMuted})
        end

        return UI.Panel {width = "100%", gap = 10, children = {
            C.Card {children = overviewChildren},
            C.Card {children = planChildren},
            C.Card {children = schemeChildren},
            C.Card {children = costCapChildren},
            C.Card {children = reviewChildren},
        }}
    end

    -- =======================================================================
    -- Tab3: 工程管理 (6 sub-tabs)
    -- =======================================================================
    local function BuildConstructionTab()
        local con = p.construction
        local sch = con.schedule or {}
        local qs = con.qualitySystem or {}
        local ss = con.safetySystem or {}
        local co = con.changeOrders or {}

        local phaseNameMap = {none = "未开工", foundation = "桩基工程", structure = "主体结构", decoration = "装饰装修", landscape = "景观市政", done = "竣工"}

        local subTabs = {"总览", "进度计划", "人机料法环", "质量管控", "安全管控", "变更签证"}
        local subTabBar = C.TabBar {
            tabs = subTabs,
            active = M._conSubTab,
            onChange = function(idx) M._conSubTab = idx; navigate("project") end,
        }

        local subContent

        -- ── 子Tab1: 总览 ──
        if M._conSubTab == 1 then
            local msItems = {}
            for _, ms in ipairs(sch.milestones or {}) do
                table.insert(msItems, UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Panel {width = 8, height = 8, backgroundColor = ms.achieved and T.Success or T.TextMuted, borderRadius = 4},
                        UI.Label {
                            text = ms.name .. (ms.achieved and (" (第" .. math.floor(ms.achievedMonth) .. "月)") or ""),
                            fontSize = T.FontSmall,
                            fontColor = ms.achieved and T.Success or T.TextMuted,
                        },
                    }
                })
            end

            -- 环境停工汇总
            local envCount = #(con.envStoppages or {})
            local envTotalDays = 0
            for _, ev in ipairs(con.envStoppages or {}) do
                envTotalDays = envTotalDays + (ev.durationDays or 0)
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "工程进度"},
                    C.InfoRow {label = "当前阶段", value = phaseNameMap[con.phase] or "未开工", color = T.Info},
                    C.InfoRow {label = "已施工", value = math.floor(con.monthsElapsed) .. " / " .. con.totalMonths .. " 个月"},
                    C.InfoRow {label = "累计延期", value = (sch.delayDays or 0) .. " 天", color = (sch.delayDays or 0) > 0 and T.Warning or T.TextSecondary},
                    C.InfoRow {label = "环境停工", value = envCount .. "次 / 累计" .. envTotalDays .. "天", color = envCount > 0 and T.Warning or T.TextSecondary},
                    C.ProgressCard {title = "总进度", progress = con.progress, barColor = T.Accent},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "关键指标"},
                    C.InfoRow {label = "质量评分", value = con.quality .. "分", color = con.quality >= 80 and T.Success or T.Warning},
                    C.InfoRow {label = "安全评分", value = con.safety .. "分", color = con.safety >= 80 and T.Success or T.Warning},
                    C.InfoRow {label = "累计变更", value = (co.totalCostDelta or 0) .. "万 / 工期+" .. (co.totalDurationDelta or 0) .. "月"},
                    C.InfoRow {label = "事故损失", value = GD.FormatMoney(ss.totalAccidentCost or 0), color = (ss.totalAccidentCost or 0) > 0 and T.Danger or T.TextSecondary},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "里程碑"},
                    UI.Panel {width = "100%", gap = 4, children = msItems},
                }},
            }}

        -- ── 子Tab2: 进度计划 ──
        elseif M._conSubTab == 2 then
            local actItems = {}
            local criticalSet = {}
            for _, cid in ipairs(sch.criticalPath or {}) do criticalSet[cid] = true end

            for _, act in ipairs(sch.activities or {}) do
                local statusText = "未开始"
                local statusColor = T.TextMuted
                if act.finished then
                    statusText = "已完成"
                    statusColor = T.Success
                elseif act.started then
                    statusText = string.format("进行中 %d/%d月", math.floor(act.elapsed), act.actualDuration)
                    statusColor = T.Info
                end

                local rowChildren = {
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                        UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 1, children = {
                            UI.Label {text = act.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            criticalSet[act.id] and C.Badge {text = "关键", variant = "danger"} or nil,
                        }},
                        C.Badge {text = statusText, color = statusColor},
                    }},
                }
                if act.started and not act.finished then
                    local pct = math.min(100, math.floor(act.elapsed / act.actualDuration * 100))
                    table.insert(rowChildren, C.ProgressCard {title = "", progress = pct, barColor = criticalSet[act.id] and T.Danger or T.Accent})
                end
                table.insert(actItems, UI.Panel {width = "100%", gap = 2, paddingVertical = 4, children = rowChildren})
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "CPM 施工活动"},
                    C.InfoRow {label = "关键线路", value = #(sch.criticalPath or {}) .. "个活动"},
                    C.InfoRow {label = "累计延期", value = (sch.delayDays or 0) .. "天", color = (sch.delayDays or 0) > 0 and T.Warning or T.TextSecondary},
                    UI.Panel {width = "100%", gap = 2, children = actItems},
                }},
            }}

        -- ── 子Tab3: 人机料法环 ──
        elseif M._conSubTab == 3 then
            -- 班组
            local crewItems = {}
            for _, crew in ipairs(con.crews or {}) do
                local moraleColor = crew.morale >= 80 and T.Success or (crew.morale >= 60 and T.Warning or T.Danger)
                table.insert(crewItems, C.InfoRow {
                    label = crew.name,
                    value = string.format("效率%.0f%%  士气%d", crew.efficiency * 100, crew.morale),
                    color = moraleColor,
                })
            end

            -- 机械
            local machineItems = {}
            for _, m in ipairs(con.machines or {}) do
                local statusMap = {standby = "待命", active = "运行中", broken = "故障"}
                local color = m.status == "active" and T.Success or (m.status == "broken" and T.Danger or T.TextMuted)
                table.insert(machineItems, C.InfoRow {
                    label = m.name,
                    value = (statusMap[m.status] or m.status) .. " (故障" .. m.failCount .. "次)",
                    color = color,
                })
            end

            -- 材料送检按钮
            local testBtns = {}
            for _, mt in ipairs(CS.MATERIAL_TESTS) do
                local capturedMt = mt
                table.insert(testBtns, C.SecondaryButton {text = capturedMt.name, height = 28, onClick = function()
                    local ok, msg = CS.PerformMaterialTest(con, capturedMt.id)
                    if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, ok and "info" or "warning") end
                    navigate("project")
                end})
            end

            -- 材料检测历史
            local testHistory = {}
            for i = #(con.materialTests or {}), math.max(1, #(con.materialTests or {}) - 4), -1 do
                local mt = con.materialTests[i]
                if mt then
                    table.insert(testHistory, C.InfoRow {
                        label = mt.name .. " (第" .. math.floor(mt.month) .. "月)",
                        value = mt.passed and "合格" or "不合格!",
                        color = mt.passed and T.Success or T.Danger,
                    })
                end
            end

            -- 工法选择
            local processItems = {}
            for _, pc in ipairs(CS.PROCESS_CHOICES) do
                local capturedPc = pc
                local chosen = con.processChoices[capturedPc.category] or capturedPc.options[1].id
                local optBtns = {}
                for _, opt in ipairs(capturedPc.options) do
                    local capturedOpt = opt
                    local isActive = (chosen == capturedOpt.id)
                    table.insert(optBtns, UI.Button {
                        text = capturedOpt.name, fontSize = T.FontSmall, height = 28,
                        backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
                        fontColor = isActive and T.Primary or T.TabInactiveFont,
                        borderRadius = 6, paddingHorizontal = 10,
                        borderWidth = 1, borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
                        onClick = function()
                            local ok2, msg2 = CS.ChangeProcess(con, capturedPc.category, capturedOpt.id)
                            if msg2 then GD.AddEvent("【" .. p.name .. "】" .. capturedPc.name .. ": " .. msg2, "info") end
                            navigate("project")
                        end,
                    })
                end
                -- 工法指标提示
                local hintParts = {}
                for _, opt in ipairs(capturedPc.options) do
                    local parts = {opt.name .. ":"}
                    if opt.costMult ~= 1.0 then table.insert(parts, "成本×" .. string.format("%.2f", opt.costMult)) end
                    if opt.speedMult and opt.speedMult ~= 1.0 then table.insert(parts, "速度×" .. string.format("%.2f", opt.speedMult)) end
                    if opt.qualityMult and opt.qualityMult ~= 1.0 then table.insert(parts, "质量×" .. string.format("%.2f", opt.qualityMult)) end
                    if opt.safetyMult and opt.safetyMult ~= 1.0 then table.insert(parts, "安全×" .. string.format("%.2f", opt.safetyMult)) end
                    table.insert(hintParts, table.concat(parts, " "))
                end

                table.insert(processItems, UI.Panel {gap = 4, children = {
                    UI.Label {text = capturedPc.name, fontSize = T.FontSmall, fontColor = T.TextMuted},
                    UI.Panel {flexDirection = "row", gap = 6, children = optBtns},
                    UI.Label {text = table.concat(hintParts, "  |  "), fontSize = T.FontCaption, fontColor = T.TextMuted},
                }})
            end

            -- 环境停工记录
            local envItems = {}
            for _, ev in ipairs(con.envStoppages or {}) do
                table.insert(envItems, C.InfoRow {label = ev.reason, value = "第" .. math.floor(ev.month) .. "月 停" .. ev.durationDays .. "天", color = T.Warning})
            end
            if #envItems == 0 then
                table.insert(envItems, UI.Label {text = "暂无停工记录", fontSize = T.FontSmall, fontColor = T.TextMuted})
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "劳务班组"},
                    UI.Panel {width = "100%", gap = 2, children = crewItems},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "大型机械"},
                    UI.Panel {width = "100%", gap = 2, children = machineItems},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "材料送检"},
                    UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = testBtns},
                    #testHistory > 0 and UI.Panel {width = "100%", gap = 2, marginTop = 6, children = testHistory} or nil,
                }},
                C.Card {children = {
                    C.SectionTitle {text = "工法选择"},
                    UI.Panel {width = "100%", gap = 8, children = processItems},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "环境停工记录"},
                    UI.Panel {width = "100%", gap = 2, children = envItems},
                }},
            }}

        -- ── 子Tab4: 质量管控 ──
        elseif M._conSubTab == 4 then
            -- 工序验收
            local accBtns = {}
            for _, sq in ipairs(CS.QUALITY_SEQUENCES) do
                local capturedSq = sq
                local passed = false
                for _, acc in ipairs(qs.acceptances or {}) do
                    if acc.sequenceId == capturedSq.id and acc.passed then passed = true; break end
                end
                local canAccept = (capturedSq.phase == con.phase or capturedSq.phase == "done") and not passed
                table.insert(accBtns, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", paddingVertical = 2,
                    children = {
                        UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", children = {
                            UI.Label {text = capturedSq.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            UI.Label {text = "(要求≥" .. capturedSq.passScore .. "分)", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            passed and C.Badge {text = "已通过", variant = "success"} or nil,
                        }},
                        canAccept and C.SecondaryButton {text = "举牌验收", height = 26, onClick = function()
                            local ok, msg = CS.PerformQualityAcceptance(con, capturedSq.id)
                            if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, ok and "info" or "warning") end
                            navigate("project")
                        end} or nil,
                    }
                })
            end

            -- 验收历史
            local accHistory = {}
            for i = #(qs.acceptances or {}), math.max(1, #(qs.acceptances or {}) - 4), -1 do
                local acc = qs.acceptances[i]
                if acc then
                    table.insert(accHistory, C.InfoRow {
                        label = acc.name .. " (第" .. math.floor(acc.month) .. "月)",
                        value = acc.score .. "分 " .. (acc.passed and "通过" or "未通过"),
                        color = acc.passed and T.Success or T.Danger,
                    })
                end
            end

            -- 样板间
            local sampleChildren = {}
            if qs.sampleRoom then
                table.insert(sampleChildren, C.Badge {text = "已建成", variant = "success"})
                table.insert(sampleChildren, C.InfoRow {label = "质量加成", value = "+" .. (qs.sampleRoomBonus or CS.SAMPLE_ROOM_QUALITY_BONUS) .. "分", color = T.Success})
            else
                local sampleCost = CS.SAMPLE_ROOM_COST
                local canBuild = cash >= sampleCost
                table.insert(sampleChildren, C.InfoRow {label = "建造费用", value = GD.FormatMoney(sampleCost)})
                table.insert(sampleChildren, C.InfoRow {label = "质量加成", value = "+" .. CS.SAMPLE_ROOM_QUALITY_BONUS .. "分", color = T.Info})
                if not canBuild then
                    table.insert(sampleChildren, UI.Label {text = "现金不足", fontSize = T.FontCaption, fontColor = T.Danger})
                end
                table.insert(sampleChildren, C.ActionButton {
                    text = "建造样板间",
                    height = 30, paddingH = 14,
                    disabled = not canBuild,
                    onClick = function()
                        local ok, msg = CS.BuildSampleRoom(con, p)
                        if ok then
                            GD.company.cash = GD.company.cash - sampleCost
                            p.cost.totalCost = p.cost.totalCost + sampleCost
                        end
                        if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, ok and "success" or "warning") end
                        navigate("project")
                    end,
                })
            end

            -- 实测实量
            local measureBtns = {}
            for _, mi in ipairs(CS.MEASURE_ITEMS) do
                local capturedMi = mi
                table.insert(measureBtns, C.SecondaryButton {text = capturedMi.name .. " (标准≤" .. capturedMi.standard .. capturedMi.unit .. ")", height = 28, onClick = function()
                    local ok, msg = CS.PerformMeasurement(con, capturedMi.id)
                    if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, ok and "info" or "warning") end
                    navigate("project")
                end})
            end

            -- 测量历史
            local measureHistory = {}
            for i = #(qs.measurements or {}), math.max(1, #(qs.measurements or {}) - 4), -1 do
                local m = qs.measurements[i]
                if m then
                    table.insert(measureHistory, C.InfoRow {
                        label = m.name .. " (第" .. math.floor(m.month) .. "月)",
                        value = string.format("合格率%.0f%% %s", m.batchPassRate * 100, m.passed and "达标" or "返工!"),
                        color = m.passed and T.Success or T.Danger,
                    })
                end
            end

            -- 淋水试验 (LEAK_TESTS)
            local leakBtns = {}
            local leakHistory = {}
            for _, lt in ipairs(CS.LEAK_TESTS) do
                local capturedLt = lt
                local canTest = (con.phase == capturedLt.phase or con.phase == "done")
                -- 检查是否已测试过
                local alreadyTested = false
                for _, rec in ipairs(qs.leakTests or {}) do
                    if rec.testId == capturedLt.id and rec.passed then alreadyTested = true; break end
                end
                table.insert(leakBtns, UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", paddingVertical = 2,
                    children = {
                        UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", children = {
                            UI.Label {text = capturedLt.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            UI.Label {text = "(" .. capturedLt.phase .. "阶段)", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            alreadyTested and C.Badge {text = "已通过", variant = "success"} or nil,
                        }},
                        (canTest and not alreadyTested) and C.SecondaryButton {text = "执行试验", height = 26, onClick = function()
                            -- 淋水试验逻辑
                            local passed = math.random() < capturedLt.passRate
                            if not qs.leakTests then qs.leakTests = {} end
                            table.insert(qs.leakTests, {
                                testId = capturedLt.id,
                                name = capturedLt.name,
                                month = con.monthsElapsed,
                                passed = passed,
                            })
                            if passed then
                                qs.score = math.min(100, qs.score + 2)
                                con.quality = math.floor(qs.score)
                                GD.AddEvent("【" .. p.name .. "】" .. capturedLt.name .. "试验通过，质量+2", "success")
                            else
                                qs.score = math.max(60, qs.score - 3)
                                con.quality = math.floor(qs.score)
                                GD.AddEvent("【" .. p.name .. "】" .. capturedLt.name .. "试验未通过，需返修!", "warning")
                            end
                            navigate("project")
                        end} or nil,
                    }
                })
            end
            -- 淋水历史
            for i = #(qs.leakTests or {}), math.max(1, #(qs.leakTests or {}) - 4), -1 do
                local lt = (qs.leakTests or {})[i]
                if lt then
                    table.insert(leakHistory, C.InfoRow {
                        label = lt.name .. " (第" .. math.floor(lt.month) .. "月)",
                        value = lt.passed and "通过" or "未通过",
                        color = lt.passed and T.Success or T.Danger,
                    })
                end
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "质量评分"},
                    C.StatCard {title = "当前质量", value = con.quality .. "分", color = con.quality >= 80 and T.Success or T.Warning},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "工序验收 (三方举牌)"},
                    UI.Panel {width = "100%", gap = 4, children = accBtns},
                    #accHistory > 0 and UI.Panel {width = "100%", gap = 2, marginTop = 6, children = {
                        UI.Label {text = "验收记录", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        table.unpack(accHistory),
                    }} or nil,
                }},
                C.Card {children = {
                    C.SectionTitle {text = "实体样板间"},
                    UI.Panel {width = "100%", gap = 4, children = sampleChildren},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "实测实量"},
                    UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", children = measureBtns},
                    #measureHistory > 0 and UI.Panel {width = "100%", gap = 2, marginTop = 4, children = measureHistory} or nil,
                }},
                C.Card {children = {
                    C.SectionTitle {text = "淋水试验"},
                    UI.Panel {width = "100%", gap = 4, children = leakBtns},
                    #leakHistory > 0 and UI.Panel {width = "100%", gap = 2, marginTop = 4, children = leakHistory} or nil,
                }},
            }}

        -- ── 子Tab5: 安全管控 ──
        elseif M._conSubTab == 5 then
            -- 检查按钮
            local checkBtns = {}
            for _, ct in ipairs(CS.SAFETY_CHECK_TYPES) do
                local capturedCt = ct
                local costLabel = capturedCt.costPerCheck > 0 and (" " .. capturedCt.costPerCheck .. "万") or " 免费"
                local canAfford = cash >= capturedCt.costPerCheck
                table.insert(checkBtns, C.SecondaryButton {
                    text = capturedCt.name .. costLabel, height = 30,
                    onClick = function()
                        if capturedCt.costPerCheck > 0 and GD.company.cash < capturedCt.costPerCheck then
                            GD.AddEvent("现金不足，无法进行" .. capturedCt.name, "warning")
                            navigate("project")
                            return
                        end
                        local ok, msg = CS.PerformSafetyCheck(con, capturedCt.id)
                        if capturedCt.costPerCheck > 0 then
                            GD.company.cash = GD.company.cash - capturedCt.costPerCheck
                        end
                        if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, "info") end
                        navigate("project")
                    end,
                })
            end

            -- 当前阶段危险源
            local hazardItems = {}
            for _, hz in ipairs(CS.MAJOR_HAZARDS) do
                if hz.phase == con.phase then
                    table.insert(hazardItems, C.InfoRow {
                        label = hz.name,
                        value = string.format("概率%.1f%%  损失%.0f%%  延期%d天", hz.probability * 100, hz.costPct * 100, hz.delayDays),
                        color = T.Danger,
                    })
                end
            end
            if #hazardItems == 0 then
                table.insert(hazardItems, UI.Label {text = "当前阶段无重大危险源", fontSize = T.FontSmall, fontColor = T.TextMuted})
            end

            -- 事故记录
            local accidentItems = {}
            for _, ac in ipairs(ss.accidents or {}) do
                table.insert(accidentItems, C.InfoRow {
                    label = ac.name .. " (第" .. math.floor(ac.month) .. "月)",
                    value = "损失" .. GD.FormatMoney(ac.cost) .. " 延期" .. ac.delayDays .. "天",
                    color = T.Danger,
                })
            end
            if #accidentItems == 0 then
                table.insert(accidentItems, UI.Label {text = "暂无事故记录", fontSize = T.FontSmall, fontColor = T.Success})
            end

            -- 检查历史
            local checkHistory = {}
            for i = #(ss.checks or {}), math.max(1, #(ss.checks or {}) - 4), -1 do
                local ck = ss.checks[i]
                if ck then
                    table.insert(checkHistory, C.InfoRow {
                        label = ck.name .. " (第" .. math.floor(ck.month) .. "月)",
                        value = "发现" .. ck.issues .. "项隐患",
                        color = ck.issues > 0 and T.Warning or T.Success,
                    })
                end
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "安全评分"},
                    C.StatCard {title = "当前安全", value = con.safety .. "分", color = con.safety >= 80 and T.Success or T.Warning},
                    UI.Panel {flexDirection = "row", gap = 6, marginTop = 6, flexWrap = "wrap", children = checkBtns},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "重大危险源 (" .. (phaseNameMap[con.phase] or "") .. ")"},
                    UI.Panel {width = "100%", gap = 2, children = hazardItems},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "事故记录"},
                    C.InfoRow {label = "累计损失", value = GD.FormatMoney(ss.totalAccidentCost or 0), color = (ss.totalAccidentCost or 0) > 0 and T.Danger or T.TextSecondary},
                    UI.Panel {width = "100%", gap = 2, children = accidentItems},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "检查记录"},
                    #checkHistory > 0 and UI.Panel {width = "100%", gap = 2, children = checkHistory}
                        or UI.Label {text = "暂无检查记录", fontSize = T.FontSmall, fontColor = T.TextMuted},
                }},
            }}

        -- ── 子Tab6: 变更签证 ──
        else
            local changeBtns = {}
            for _, ct in ipairs(CS.CHANGE_TYPES) do
                local capturedCt = ct
                table.insert(changeBtns, UI.Panel {
                    gap = 2,
                    children = {
                        C.SecondaryButton {text = capturedCt.name, height = 28, onClick = function()
                            local ok, msg = CS.SubmitChangeOrder(con, capturedCt.id, capturedCt.name, p.cost.buildCost or 0)
                            if msg then GD.AddEvent("【" .. p.name .. "】" .. msg, ok and "info" or "warning") end
                            navigate("project")
                        end},
                        UI.Label {
                            text = string.format("成本%.0f%%~%.0f%% 工期+%d~%d月", capturedCt.costRange[1] * 100, capturedCt.costRange[2] * 100, capturedCt.durationRange[1], capturedCt.durationRange[2]),
                            fontSize = T.FontCaption, fontColor = T.TextMuted,
                        },
                    },
                })
            end

            -- 变更记录
            local orderItems = {}
            for i = #(co.items or {}), math.max(1, #(co.items or {}) - 9), -1 do
                local item = co.items[i]
                if item then
                    local statusBadge = item.malicious and C.Badge {text = "驳回(恶意索赔)", variant = "danger"}
                        or C.Badge {text = "已审批", variant = "success"}
                    table.insert(orderItems, UI.Panel {width = "100%", gap = 2, paddingVertical = 4, children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Label {text = item.typeName .. " (第" .. math.floor(item.month) .. "月)", fontSize = T.FontSmall, fontColor = T.TextPrimary},
                            statusBadge,
                        }},
                        C.InfoRow {
                            label = "影响",
                            value = (item.approved and ("成本" .. (item.costDelta >= 0 and "+" or "") .. item.costDelta .. "万 工期+" .. item.durationDelta .. "月") or "已驳回"),
                            color = item.malicious and T.Danger or T.Warning,
                        },
                    }})
                end
            end
            if #orderItems == 0 then
                table.insert(orderItems, UI.Label {text = "暂无变更记录", fontSize = T.FontSmall, fontColor = T.TextMuted})
            end

            subContent = UI.Panel {width = "100%", gap = 10, children = {
                C.Card {children = {
                    C.SectionTitle {text = "提交变更签证"},
                    UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", children = changeBtns},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "变更汇总"},
                    C.InfoRow {label = "累计成本变更", value = GD.FormatMoney(co.totalCostDelta or 0), color = (co.totalCostDelta or 0) > 0 and T.Warning or T.TextSecondary},
                    C.InfoRow {label = "累计工期变更", value = "+" .. (co.totalDurationDelta or 0) .. "月", color = (co.totalDurationDelta or 0) > 0 and T.Warning or T.TextSecondary},
                }},
                C.Card {children = {
                    C.SectionTitle {text = "变更记录 (最近10条)"},
                    UI.Panel {width = "100%", gap = 2, children = orderItems},
                }},
            }}
        end

        return UI.Panel {width = "100%", gap = 10, children = {
            subTabBar,
            subContent,
        }}
    end

    -- =======================================================================
    -- Tab4: 成本控制 (完整可玩版)
    -- =======================================================================
    local function BuildCostTab()
        local cost = p.cost
        local alert = GD.GetCostAlertInfo(p)

        -- 确保 subjectDetail 存在
        if not cost.subjectDetail or next(cost.subjectDetail) == nil then
            GD.InitCostSubjects(p)
        end

        -- 初始化成本控制运行时状态
        if not cost._veApplied then cost._veApplied = {} end
        if not cost._costLog then cost._costLog = {} end
        if not cost._adjHistory then cost._adjHistory = {} end

        local cards = {}

        -- ================================================================
        -- Card 1: 成本总览仪表盘
        -- ================================================================
        local pctUsed = cost.targetCost > 0 and math.min(100, math.floor(cost.totalCost / cost.targetCost * 100)) or 0
        local dynPct = cost.targetCost > 0 and math.floor((cost.dynamicCost or cost.targetCost) / cost.targetCost * 100) or 100
        local barColor = alert.level == "red" and T.Danger or (alert.level == "yellow" and T.Warning or T.Success)
        local alertColorVal = T[alert.color] or T.TextPrimary

        -- 四大指标卡
        table.insert(cards, C.Card {children = {
            C.SectionTitle {text = "成本总览"},
            UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
                UI.Panel {flex = 1, minWidth = 120, padding = 8, backgroundColor = T.BgInput, borderRadius = 8, gap = 2, children = {
                    UI.Label {text = "目标成本", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = C.FormatMoney(cost.targetCost), fontSize = T.FontSubtitle, fontColor = T.Accent},
                }},
                UI.Panel {flex = 1, minWidth = 120, padding = 8, backgroundColor = T.BgInput, borderRadius = 8, gap = 2, children = {
                    UI.Label {text = "动态成本", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = C.FormatMoney(cost.dynamicCost or cost.targetCost), fontSize = T.FontSubtitle, fontColor = alertColorVal},
                    UI.Label {text = dynPct .. "% (目标比)", fontSize = T.FontCaption, fontColor = alertColorVal},
                }},
            }},
            UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", marginTop = 4, children = {
                UI.Panel {flex = 1, minWidth = 120, padding = 8, backgroundColor = T.BgInput, borderRadius = 8, gap = 2, children = {
                    UI.Label {text = "已发生成本", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = C.FormatMoney(cost.totalCost), fontSize = T.FontSubtitle, fontColor = cost.totalCost > cost.targetCost and T.Danger or T.TextPrimary},
                    UI.Label {text = pctUsed .. "% 已消耗", fontSize = T.FontCaption, fontColor = T.TextSecondary},
                }},
                UI.Panel {flex = 1, minWidth = 120, padding = 8, backgroundColor = T.BgInput, borderRadius = 8, gap = 2, children = {
                    UI.Label {text = "预算余量", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = C.FormatMoney(math.max(0, cost.targetCost - cost.totalCost)),
                        fontSize = T.FontSubtitle,
                        fontColor = cost.totalCost > cost.targetCost and T.Danger or T.Success},
                    UI.Label {text = "精度 ±" .. math.floor(cost.budgetPrecision * 100) .. "%",
                        fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
            }},
            C.ProgressCard {title = "成本执行进度", progress = pctUsed, barColor = barColor},
        }})

        -- ================================================================
        -- Card 2: 成本预警
        -- ================================================================
        local alertVariant = alert.level == "red" and "danger" or (alert.level == "yellow" and "warning" or "success")
        local alertLabel = alert.level == "red" and "超支" or (alert.level == "yellow" and "预警" or "安全")
        table.insert(cards, C.Card {children = {
            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                C.SectionTitle {text = "成本预警"},
                C.Badge {text = alertLabel, variant = alertVariant},
            }},
            C.InfoRow {label = "预警等级", value = alertLabel, color = alertColorVal},
            C.InfoRow {label = "动态/目标比", value = dynPct .. "%", color = alertColorVal},
            (alert.overrun or 0) > 0 and C.InfoRow {label = "超出额度", value = C.FormatMoney(alert.overrun), color = T.Danger} or nil,
            -- 成本构成占比
            C.InfoRow {label = "土地成本", value = C.FormatMoney(cost.landCost) ..
                (cost.targetCost > 0 and string.format(" (%.0f%%)", cost.landCost / cost.targetCost * 100) or "")},
            C.InfoRow {label = "建安成本", value = C.FormatMoney(cost.buildCost) ..
                (cost.targetCost > 0 and string.format(" (%.0f%%)", cost.buildCost / cost.targetCost * 100) or "")},
            C.InfoRow {label = "设计费用", value = C.FormatMoney(cost.designCost) ..
                (cost.targetCost > 0 and string.format(" (%.0f%%)", cost.designCost / cost.targetCost * 100) or "")},
            (cost.ddCost or 0) > 0 and C.InfoRow {label = "尽调费用", value = C.FormatMoney(cost.ddCost)} or nil,
            (cost.riskCost or 0) > 0 and C.InfoRow {label = "风险附加", value = C.FormatMoney(cost.riskCost), color = T.Warning} or nil,
        }})

        -- 联合拿地合作方信息
        if p.jointBid then
            local jb = p.jointBid
            local jbRows = {
                C.SectionTitle {text = "联合拿地合作方"},
                C.InfoRow {label = "合作方", value = jb.partnerName},
                C.InfoRow {label = "合作方土地出资", value = C.FormatMoney(jb.partnerLandCost or 0)},
                C.InfoRow {label = "合作方初始份额", value = jb.partnerSharePct .. "%"},
                C.InfoRow {label = "玩家初始份额", value = jb.playerSharePct .. "%"},
            }
            -- 按总投入重新计算动态份额预览
            local totalCost = cost.totalCost or 0
            if totalCost > 0 then
                local partnerInvest = jb.partnerLandCost or 0
                local dynRatio = math.floor(partnerInvest / totalCost * 1000) / 10
                table.insert(jbRows, C.InfoRow {label = "当前投入份额", value = string.format("%.1f%%", dynRatio) .. "（按总投入）", color = T.Accent})
            end
            -- 清盘后显示分红明细
            if jb.clearanceDetail then
                local cd = jb.clearanceDetail
                table.insert(jbRows, C.InfoRow {label = "─── 清盘明细 ───", value = ""})
                table.insert(jbRows, C.InfoRow {label = "项目总收入", value = C.FormatMoney(cd.revenue)})
                table.insert(jbRows, C.InfoRow {label = "项目总成本", value = C.FormatMoney(cd.totalCost)})
                table.insert(jbRows, C.InfoRow {label = "含融资成本", value = C.FormatMoney(cd.financeCost)})
                table.insert(jbRows, C.InfoRow {label = "净利润", value = C.FormatMoney(cd.netProfit), color = cd.netProfit >= 0 and T.Success or T.Danger})
                table.insert(jbRows, C.InfoRow {label = "合作方最终份额", value = string.format("%.1f%%", cd.partnerFinalRatio)})
                if (cd.partnerDividend or 0) > 0 then
                    table.insert(jbRows, C.InfoRow {label = "合作方分红", value = C.FormatMoney(cd.partnerDividend), color = T.Warning})
                end
                if (cd.partnerLoss or 0) > 0 then
                    table.insert(jbRows, C.InfoRow {label = "合作方承担亏损", value = C.FormatMoney(cd.partnerLoss), color = T.Danger})
                end
            end
            table.insert(cards, C.Card {children = jbRows})
        end

        -- ================================================================
        -- Card 3: VE 价值工程 (成本优化操作)
        -- ================================================================
        local VE_ACTIONS = {
            {id = "standard_reduce", name = "标准化设计降本", desc = "统一户型模块减少设计变更", savePct = 0.03, costToApply = 50, target = "con_civil",
                condition = function() return p.design.scheme.confirmed end, condHint = "需先确认方案设计"},
            {id = "material_sub", name = "材料替代优化", desc = "使用性价比更高的替代材料", savePct = 0.05, costToApply = 30, target = "con_install",
                condition = function() return p.status ~= "permits" end, condHint = "需进入设计或施工阶段"},
            {id = "batch_procure", name = "集中采购议价", desc = "整合多项目采购量获取折扣", savePct = 0.04, costToApply = 20, target = "con_decor",
                condition = function() return #GD.projects > 1 end, condHint = "需有2个以上在建项目"},
            {id = "design_opt", name = "设计优化", desc = "精简不必要的设计冗余", savePct = 0.02, costToApply = 80, target = "prec_design",
                condition = function() return p.design.phase ~= "done" end, condHint = "设计阶段内有效"},
            {id = "landscape_vr", name = "景观减配VE", desc = "适度降低景观标准节约成本", savePct = 0.06, costToApply = 10, target = "con_landscape",
                condition = function() return true end, condHint = ""},
            {id = "energy_saving", name = "节能方案优化", desc = "采用被动式节能减少设备投入", savePct = 0.03, costToApply = 60, target = "inf_power",
                condition = function() return true end, condHint = ""},
        }

        local veRows = {C.SectionTitle {text = "VE 价值工程 (成本优化)"}}
        table.insert(veRows, UI.Label {text = "通过优化方案降低各科目成本，需支付咨询费用", fontSize = T.FontCaption, fontColor = T.TextMuted})

        for _, ve in ipairs(VE_ACTIONS) do
            local capturedVe = ve
            local applied = cost._veApplied[capturedVe.id] == true
            local condOk = capturedVe.condition()
            local canAfford = cash >= capturedVe.costToApply

            local subjectAmt = cost.subjectDetail[capturedVe.target] or 0
            local saveAmt = math.floor(subjectAmt * capturedVe.savePct)

            local veChildren = {
                UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = capturedVe.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        applied and C.Badge {text = "已执行", variant = "success"} or nil,
                    }},
                    not applied and UI.Label {
                        text = "节约 " .. C.FormatMoney(saveAmt) .. " / 费用 " .. capturedVe.costToApply .. "万",
                        fontSize = T.FontCaption, fontColor = T.Info,
                    } or nil,
                }},
                UI.Label {text = capturedVe.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
            }

            if applied then
                table.insert(veChildren, UI.Label {text = "已节约 " .. C.FormatMoney(saveAmt), fontSize = T.FontSmall, fontColor = T.Success})
            elseif not condOk then
                table.insert(veChildren, UI.Label {text = capturedVe.condHint, fontSize = T.FontCaption, fontColor = T.Warning})
            else
                if not canAfford then
                    table.insert(veChildren, UI.Label {text = "现金不足", fontSize = T.FontCaption, fontColor = T.Danger})
                end
                table.insert(veChildren, C.ActionButton {
                    text = "执行优化", height = 28, paddingH = 12,
                    disabled = not canAfford,
                    onClick = function()
                        GD.company.cash = GD.company.cash - capturedVe.costToApply
                        cost.totalCost = cost.totalCost + capturedVe.costToApply -- 咨询费计入成本

                        -- 降低对应科目
                        local oldAmt = cost.subjectDetail[capturedVe.target] or 0
                        local saved = math.floor(oldAmt * capturedVe.savePct)
                        cost.subjectDetail[capturedVe.target] = oldAmt - saved
                        -- 同步降低建安成本
                        cost.buildCost = math.max(0, cost.buildCost - saved)
                        cost.targetCost = math.max(0, cost.targetCost - saved + capturedVe.costToApply)
                        cost.dynamicCost = math.max(0, (cost.dynamicCost or cost.targetCost) - saved + capturedVe.costToApply)
                        cost._veApplied[capturedVe.id] = true
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = capturedVe.name,
                            delta = -saved + capturedVe.costToApply,
                            detail = "节约" .. C.FormatMoney(saved) .. " 咨询费" .. capturedVe.costToApply .. "万",
                        })
                        GD.AddEvent("【" .. p.name .. "】VE优化: " .. capturedVe.name ..
                            "，节约" .. C.FormatMoney(saved) .. "，咨询费" .. capturedVe.costToApply .. "万", "success")
                        navigate("project")
                    end,
                })
            end

            table.insert(veRows, UI.Panel {
                width = "100%", gap = 3, paddingVertical = 6,
                borderBottomWidth = 1, borderColor = T.Border,
                children = veChildren,
            })
        end
        table.insert(cards, C.Card {children = veRows})

        -- ================================================================
        -- Card 5: 成本预算调整
        -- ================================================================
        local adjRows = {C.SectionTitle {text = "预算调整"}}
        table.insert(adjRows, UI.Label {text = "手动调整目标成本(审批后生效)", fontSize = T.FontCaption, fontColor = T.TextMuted})

        -- 调整目标成本: 增加/减少
        local adjAmounts = {-500, -200, -100, 100, 200, 500}
        local adjBtns = {}
        for _, amt in ipairs(adjAmounts) do
            local capturedAmt = amt
            local label = capturedAmt > 0 and ("+" .. C.FormatMoney(capturedAmt)) or C.FormatMoney(capturedAmt)
            local btnColor = capturedAmt > 0 and T.Warning or T.Success
            table.insert(adjBtns, UI.Button {
                text = label, fontSize = T.FontSmall,
                backgroundColor = T.BgInput, fontColor = btnColor,
                borderRadius = 6, paddingHorizontal = 10, height = 28,
                onClick = function()
                    local oldTarget = cost.targetCost
                    cost.targetCost = math.max(0, cost.targetCost + capturedAmt)
                    cost.dynamicCost = math.max(0, (cost.dynamicCost or oldTarget) + capturedAmt)
                    table.insert(cost._adjHistory, {
                        month = GD.totalMonths,
                        oldTarget = oldTarget,
                        newTarget = cost.targetCost,
                        delta = capturedAmt,
                    })
                    table.insert(cost._costLog, {
                        month = GD.totalMonths,
                        action = "预算调整",
                        delta = capturedAmt,
                        detail = "目标成本 " .. C.FormatMoney(oldTarget) .. " → " .. C.FormatMoney(cost.targetCost),
                    })
                    GD.AddEvent("【" .. p.name .. "】预算调整: 目标成本" ..
                        (capturedAmt > 0 and "+" or "") .. C.FormatMoney(capturedAmt) ..
                        " → " .. C.FormatMoney(cost.targetCost), "info")
                    navigate("project")
                end,
            })
        end
        table.insert(adjRows, UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", marginTop = 4, children = adjBtns})

        -- 调整历史
        if #cost._adjHistory > 0 then
            table.insert(adjRows, UI.Label {text = "调整记录", fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 8})
            for i = #cost._adjHistory, math.max(1, #cost._adjHistory - 4), -1 do
                local rec = cost._adjHistory[i]
                if rec then
                    local deltaStr = (rec.delta > 0 and "+" or "") .. C.FormatMoney(rec.delta)
                    table.insert(adjRows, C.InfoRow {
                        label = "第" .. rec.month .. "月",
                        value = deltaStr .. " → " .. C.FormatMoney(rec.newTarget),
                        color = rec.delta > 0 and T.Warning or T.Success,
                    })
                end
            end
        end
        table.insert(cards, C.Card {children = adjRows})

        -- ================================================================
        -- Card 6: 科目预算重分配
        -- ================================================================
        local reallocRows = {C.SectionTitle {text = "科目预算重分配"}}
        table.insert(reallocRows, UI.Label {text = "微调各科目预算分配 (不改变总目标成本)", fontSize = T.FontCaption, fontColor = T.TextMuted})

        -- 只展示主要可调科目
        local reallocSubjects = {
            {id = "con_civil", name = "土建工程"},
            {id = "con_install", name = "安装工程"},
            {id = "con_decor", name = "精装修"},
            {id = "con_landscape", name = "景观工程"},
            {id = "ind_market", name = "营销费"},
        }
        for _, rs in ipairs(reallocSubjects) do
            local capturedRs = rs
            local curAmt = cost.subjectDetail[capturedRs.id] or 0
            local pctOfTarget = cost.targetCost > 0 and math.floor(curAmt / cost.targetCost * 100) or 0

            local miniAdj = {}
            local steps = {-100, -50, 50, 100}
            for _, step in ipairs(steps) do
                local capturedStep = step
                local stepLabel = capturedStep > 0 and ("+" .. capturedStep) or tostring(capturedStep)
                table.insert(miniAdj, UI.Button {
                    text = stepLabel, fontSize = T.FontCaption,
                    backgroundColor = T.BgInput, fontColor = capturedStep > 0 and T.Warning or T.Success,
                    borderRadius = 4, width = 40, height = 22,
                    onClick = function()
                        local oldVal = cost.subjectDetail[capturedRs.id] or 0
                        local newVal = math.max(0, oldVal + capturedStep)
                        cost.subjectDetail[capturedRs.id] = newVal
                        -- 对应调整 buildCost (如果是建安类科目)
                        if capturedRs.id:sub(1, 3) == "con" then
                            cost.buildCost = math.max(0, cost.buildCost + capturedStep)
                        end
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = "科目调整: " .. capturedRs.name,
                            delta = capturedStep,
                            detail = C.FormatMoney(oldVal) .. " → " .. C.FormatMoney(newVal),
                        })
                        navigate("project")
                    end,
                })
            end

            table.insert(reallocRows, UI.Panel {
                flexDirection = "row", alignItems = "center", justifyContent = "space-between", width = "100%",
                paddingVertical = 4,
                children = {
                    UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", width = 110, children = {
                        UI.Label {text = capturedRs.name, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    }},
                    UI.Label {text = C.FormatMoney(curAmt) .. " (" .. pctOfTarget .. "%)", fontSize = T.FontSmall, fontColor = T.Accent, width = 100},
                    UI.Panel {flexDirection = "row", gap = 3, children = miniAdj},
                },
            })
        end
        table.insert(cards, C.Card {children = reallocRows})

        -- ================================================================
        -- Card 7: 特殊成本操作
        -- ================================================================
        local specialRows = {C.SectionTitle {text = "特殊成本操作"}}

        -- 7a: 风险准备金
        local reserveAmt = math.floor(cost.targetCost * 0.05)
        local hasReserve = cost._hasReserve == true
        if not hasReserve then
            table.insert(specialRows, UI.Panel {gap = 4, paddingVertical = 4, children = {
                UI.Label {text = "计提风险准备金", fontSize = T.FontBody, fontColor = T.TextPrimary},
                UI.Label {text = "预留目标成本5%(" .. C.FormatMoney(reserveAmt) .. ")作为不可预见费用缓冲", fontSize = T.FontCaption, fontColor = T.TextMuted},
                (cash >= reserveAmt) and C.ActionButton {
                    text = "计提 " .. C.FormatMoney(reserveAmt), height = 28, paddingH = 12,
                    onClick = function()
                        cost._hasReserve = true
                        cost.targetCost = cost.targetCost + reserveAmt
                        cost.dynamicCost = (cost.dynamicCost or cost.targetCost) + reserveAmt
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = "计提风险准备金",
                            delta = reserveAmt,
                            detail = "目标成本增加 " .. C.FormatMoney(reserveAmt),
                        })
                        GD.AddEvent("【" .. p.name .. "】计提风险准备金 " .. C.FormatMoney(reserveAmt), "info")
                        navigate("project")
                    end,
                } or UI.Label {text = "现金不足", fontSize = T.FontCaption, fontColor = T.Danger},
            }})
        else
            table.insert(specialRows, UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                UI.Label {text = "风险准备金", fontSize = T.FontBody, fontColor = T.TextPrimary},
                C.Badge {text = "已计提 " .. C.FormatMoney(reserveAmt), variant = "success"},
            }})
        end

        table.insert(specialRows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4})

        -- 7b: 设计冻结(锁定设计防止成本蔓延)
        local designFrozen = cost._designFrozen == true
        if not designFrozen then
            table.insert(specialRows, UI.Panel {gap = 4, paddingVertical = 4, children = {
                UI.Label {text = "设计冻结", fontSize = T.FontBody, fontColor = T.TextPrimary},
                UI.Label {text = "冻结设计变更以控制成本蔓延，冻结后设计费降低10%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                (p.design.scheme.confirmed) and C.ActionButton {
                    text = "冻结设计", height = 28, paddingH = 12,
                    onClick = function()
                        cost._designFrozen = true
                        local designSave = math.floor(cost.designCost * 0.10)
                        cost.designCost = cost.designCost - designSave
                        cost.targetCost = cost.targetCost - designSave
                        cost.dynamicCost = math.max(0, (cost.dynamicCost or cost.targetCost) - designSave)
                        cost.subjectDetail["prec_design"] = (cost.subjectDetail["prec_design"] or 0) - designSave
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = "设计冻结",
                            delta = -designSave,
                            detail = "设计费节约 " .. C.FormatMoney(designSave),
                        })
                        GD.AddEvent("【" .. p.name .. "】设计冻结，设计费降低 " .. C.FormatMoney(designSave), "success")
                        navigate("project")
                    end,
                } or UI.Label {text = "请先确认方案设计", fontSize = T.FontCaption, fontColor = T.Warning},
            }})
        else
            table.insert(specialRows, UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                UI.Label {text = "设计冻结", fontSize = T.FontBody, fontColor = T.TextPrimary},
                C.Badge {text = "已冻结", variant = "info"},
            }})
        end

        table.insert(specialRows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4})

        -- 7c: 赶工令 (加速但增加成本)
        table.insert(specialRows, UI.Panel {gap = 4, paddingVertical = 4, children = {
            UI.Label {text = "赶工令", fontSize = T.FontBody, fontColor = T.TextPrimary},
            UI.Label {text = "加快施工进度但增加15%建安成本，缩短工期2个月", fontSize = T.FontCaption, fontColor = T.TextMuted},
            (p.status == "construction" or p.construction.phase ~= "none") and C.ActionButton {
                text = "下达赶工令 (+" .. C.FormatMoney(math.floor(cost.buildCost * 0.15)) .. ")",
                height = 28, paddingH = 12,
                onClick = function()
                    local extraCost = math.floor(cost.buildCost * 0.15)
                    cost.buildCost = cost.buildCost + extraCost
                    cost.targetCost = cost.targetCost + extraCost
                    cost.dynamicCost = (cost.dynamicCost or cost.targetCost) + extraCost
                    cost.subjectDetail["con_civil"] = (cost.subjectDetail["con_civil"] or 0) + math.floor(extraCost * 0.6)
                    cost.subjectDetail["con_install"] = (cost.subjectDetail["con_install"] or 0) + math.floor(extraCost * 0.4)
                    -- 缩短工期
                    p.construction.totalMonths = math.max(6, p.construction.totalMonths - 2)
                    table.insert(cost._costLog, {
                        month = GD.totalMonths,
                        action = "赶工令",
                        delta = extraCost,
                        detail = "建安成本+" .. C.FormatMoney(extraCost) .. " 工期-2月",
                    })
                    GD.AddEvent("【" .. p.name .. "】下达赶工令，成本+" .. C.FormatMoney(extraCost) .. "，工期缩短2个月", "warning")
                    navigate("project")
                end,
            } or UI.Label {text = "需进入施工阶段", fontSize = T.FontCaption, fontColor = T.Warning},
        }})

        table.insert(specialRows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4})

        -- 7d: 成本审计
        local auditCost = 100
        table.insert(specialRows, UI.Panel {gap = 4, paddingVertical = 4, children = {
            UI.Label {text = "成本审计", fontSize = T.FontBody, fontColor = T.TextPrimary},
            UI.Label {text = "聘请第三方审计，有30%概率发现隐藏节约空间(建安成本2~5%)", fontSize = T.FontCaption, fontColor = T.TextMuted},
            (cash >= auditCost) and C.ActionButton {
                text = "发起审计 (" .. auditCost .. "万)", height = 28, paddingH = 12,
                onClick = function()
                    GD.company.cash = GD.company.cash - auditCost
                    cost.totalCost = cost.totalCost + auditCost
                    local foundSaving = math.random() < 0.30
                    if foundSaving then
                        local savePct = 0.02 + math.random() * 0.03
                        local saveAmt = math.floor(cost.buildCost * savePct)
                        cost.buildCost = cost.buildCost - saveAmt
                        cost.targetCost = math.max(0, cost.targetCost - saveAmt)
                        cost.dynamicCost = math.max(0, (cost.dynamicCost or cost.targetCost) - saveAmt)
                        -- 按比例降低建安科目
                        local conIds = {"con_civil", "con_install", "con_decor", "con_landscape"}
                        for _, cid in ipairs(conIds) do
                            local old = cost.subjectDetail[cid] or 0
                            cost.subjectDetail[cid] = math.max(0, old - math.floor(saveAmt * old / math.max(1, cost.buildCost + saveAmt)))
                        end
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = "成本审计(成功)",
                            delta = -saveAmt + auditCost,
                            detail = "发现节约空间 " .. C.FormatMoney(saveAmt),
                        })
                        GD.AddEvent("【" .. p.name .. "】成本审计发现节约空间 " .. C.FormatMoney(saveAmt) .. "!", "success")
                    else
                        table.insert(cost._costLog, {
                            month = GD.totalMonths,
                            action = "成本审计(未发现)",
                            delta = auditCost,
                            detail = "未发现明显节约空间",
                        })
                        GD.AddEvent("【" .. p.name .. "】成本审计完成，未发现明显节约空间", "info")
                    end
                    navigate("project")
                end,
            } or UI.Label {text = "现金不足", fontSize = T.FontCaption, fontColor = T.Danger},
        }})
        table.insert(cards, C.Card {children = specialRows})

        -- ================================================================
        -- Card 8: 成本变动记录
        -- ================================================================
        local logRows = {C.SectionTitle {text = "成本变动记录"}}
        if #cost._costLog == 0 then
            table.insert(logRows, UI.Label {text = "暂无变动记录", fontSize = T.FontSmall, fontColor = T.TextMuted})
        else
            for i = #cost._costLog, math.max(1, #cost._costLog - 9), -1 do
                local rec = cost._costLog[i]
                if rec then
                    local deltaStr = rec.delta >= 0 and ("+" .. C.FormatMoney(rec.delta)) or C.FormatMoney(rec.delta)
                    local deltaColor = rec.delta > 0 and T.Warning or T.Success
                    table.insert(logRows, UI.Panel {
                        width = "100%", paddingVertical = 3,
                        borderBottomWidth = 1, borderColor = T.Border,
                        gap = 1,
                        children = {
                            UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", children = {
                                    UI.Label {text = "第" .. rec.month .. "月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                                    UI.Label {text = rec.action, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                }},
                                UI.Label {text = deltaStr, fontSize = T.FontSmall, fontColor = deltaColor},
                            }},
                            UI.Label {text = rec.detail, fontSize = T.FontCaption, fontColor = T.TextMuted},
                        },
                    })
                end
            end
        end
        table.insert(cards, C.Card {children = logRows})

        return UI.Panel {width = "100%", gap = 10, children = cards}
    end

    -- =======================================================================
    -- Tab5: 招采管理
    -- =======================================================================
    local function BuildProcurementTab()
        local proc = p.procurement
        local cards = {}

        -- Card 1: 招采包列表
        local pkgRows = {C.SectionTitle {text = "招采包管理"}}
        if #proc.packages == 0 then
            table.insert(pkgRows, UI.Label {text = "进入施工阶段后自动生成招采包", fontSize = T.FontSmall, fontColor = T.TextMuted})
        end
        for i, pkg in ipairs(proc.packages) do
            local capturedI = i
            local capturedPkg = pkg
            local statusText = capturedPkg.status == "pending" and "待招标" or (capturedPkg.status == "bidding" and "招标中" or "已定标")
            local statusVariant = capturedPkg.status == "done" and "success" or (capturedPkg.status == "bidding" and "warning" or "info")
            table.insert(pkgRows, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})

            local pkgChildren = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                    children = {
                        UI.Label {text = capturedPkg.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {text = statusText, variant = statusVariant},
                    }
                },
            }

            -- 招标模式选择(仅待招标)
            if capturedPkg.status == "pending" then
                local modeBtns = {}
                for _, modeKey in ipairs(GD.PROCUREMENT_MODE_ORDER) do
                    local capturedModeKey = modeKey
                    local mode = GD.PROCUREMENT_MODES[capturedModeKey]
                    local isActive = capturedPkg.mode == capturedModeKey
                    table.insert(modeBtns, UI.Button {
                        text = mode.name, fontSize = T.FontCaption,
                        backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
                        fontColor = isActive and T.Primary or T.TabInactiveFont,
                        borderRadius = 4, paddingHorizontal = 8, height = 24,
                        borderWidth = 1, borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
                        onClick = function()
                            capturedPkg.mode = capturedModeKey
                            navigate("project")
                        end,
                    })
                end
                table.insert(pkgChildren, UI.Panel {flexDirection = "row", gap = 6, width = "100%", children = modeBtns})
                -- 模式提示
                local curMode = GD.PROCUREMENT_MODES[capturedPkg.mode or "open"]
                if curMode then
                    table.insert(pkgChildren, UI.Label {
                        text = string.format("最少%d家 周期%d月 节约%.0f%%~%.0f%%", curMode.minBidders, curMode.durationMonths, curMode.costSavingRange[1] * 100, curMode.costSavingRange[2] * 100),
                        fontSize = T.FontCaption, fontColor = T.TextMuted,
                    })
                end
                table.insert(pkgChildren, C.ActionButton {
                    text = "发起招标", height = 30,
                    onClick = function()
                        GD.StartProcurement(p, capturedI)
                        navigate("project")
                    end,
                })
            end

            -- 投标人列表(招标中)
            if capturedPkg.status == "bidding" then
                local bidRows = {
                    C.InfoRow {label = "剩余月数", value = (capturedPkg.remainMonths or 0) .. "个月"},
                }
                for ci, c in ipairs(capturedPkg.bidders or {}) do
                    local capturedCi = ci
                    local capturedC = c
                    table.insert(bidRows, UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                        paddingVertical = 2,
                        children = {
                            UI.Panel {flexDirection = "row", gap = 4, alignItems = "center", children = {
                                UI.Label {text = capturedC.name, fontSize = T.FontSmall, fontColor = capturedC.blacklisted and T.Danger or T.TextPrimary},
                                capturedC.blacklisted and UI.Label {text = "(黑名单)", fontSize = T.FontCaption, fontColor = T.Danger} or nil,
                                capturedC.unbalancedFlag and UI.Label {text = "⚠不平衡", fontSize = T.FontCaption, fontColor = T.Warning} or nil,
                            }},
                            UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = {
                                UI.Label {text = C.FormatMoney(capturedC.quoteAmount), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                                (not capturedC.blacklisted) and C.SecondaryButton {
                                    text = "选定", height = 24, paddingH = 10,
                                    onClick = function()
                                        GD.CompleteProcurement(p, capturedI, capturedCi)
                                        navigate("project")
                                    end,
                                } or nil,
                            }},
                        }
                    })
                end
                table.insert(pkgChildren, UI.Panel {width = "100%", gap = 2, children = bidRows})
            end

            -- 已定标结果
            if capturedPkg.status == "done" then
                table.insert(pkgChildren, UI.Panel {width = "100%", gap = 2, children = {
                    C.InfoRow {label = "中标单位", value = capturedPkg.winner or "-"},
                    C.InfoRow {label = "中标金额", value = C.FormatMoney(capturedPkg.contractAmount or 0), color = T.Success},
                }})
            end

            table.insert(pkgRows, UI.Panel {width = "100%", gap = 4, children = pkgChildren})
        end
        table.insert(cards, C.Card {children = pkgRows})

        -- Card 2: 招采历史
        if #proc.history > 0 then
            local histRows = {C.SectionTitle {text = "招采历史"}}
            for i = #proc.history, math.max(1, #proc.history - 4), -1 do
                local h = proc.history[i]
                if h then
                    local winnerName = h.winner or h.contractorName or "-"
                    local pkgName = h.package or h.catId or "未知"
                    table.insert(histRows, C.InfoRow {
                        label = pkgName .. " → " .. winnerName,
                        value = C.FormatMoney(h.amount or 0),
                    })
                end
            end
            table.insert(cards, C.Card {children = histRows})
        end

        -- Card 3: 黑名单管理
        local blRows = {C.SectionTitle {text = "施工单位黑名单"}}
        local bl = GD.company.contractorBlacklist or {}
        if #bl == 0 then
            table.insert(blRows, UI.Label {text = "暂无黑名单记录", fontSize = T.FontSmall, fontColor = T.TextMuted})
        end
        for _, entry in ipairs(bl) do
            local capturedEntry = entry
            table.insert(blRows, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                paddingVertical = 2,
                children = {
                    UI.Panel {gap = 1, children = {
                        UI.Label {text = capturedEntry.name, fontSize = T.FontSmall, fontColor = T.Danger},
                        UI.Label {text = capturedEntry.reason or "", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    C.SecondaryButton {
                        text = "移除", height = 24, paddingH = 10,
                        onClick = function()
                            GD.RemoveFromBlacklist(capturedEntry.name)
                            navigate("project")
                        end,
                    },
                }
            })
        end
        table.insert(cards, C.Card {children = blRows})

        return UI.Panel {width = "100%", gap = 10, children = cards}
    end

    -- =======================================================================
    -- Tab6: 单元规划
    -- =======================================================================
    local function BuildUnitPlanTab()
        local up = p.unitPlan
        local totalUnits = up.planned and (up.sellUnits + up.holdUnits) or p.sales.totalUnits
        local avgArea = (p.sales.totalArea > 0 and totalUnits > 0) and math.floor(p.sales.totalArea / totalUnits) or 100

        if up.planned then
            -- 已规划: 显示锁定的分配结果
            local items = {
                C.Card {children = {
                    C.SectionTitle {text = "单元规划 (已锁定)"},
                    C.InfoRow {label = "总套数", value = totalUnits .. "套"},
                    C.InfoRow {label = "计划销售", value = up.sellUnits .. "套 (" .. up.sellArea .. "㎡)", color = T.Success},
                    C.InfoRow {label = "计划自持", value = up.holdUnits .. "套 (" .. up.holdArea .. "㎡)", color = T.Accent},
                    C.InfoRow {label = "销售占比", value = string.format("%.0f%%", totalUnits > 0 and up.sellUnits / totalUnits * 100 or 0)},
                    C.InfoRow {label = "自持占比", value = string.format("%.0f%%", totalUnits > 0 and up.holdUnits / totalUnits * 100 or 0)},
                }},
            }
            -- 自持物业运营状态
            if up.holdUnits > 0 then
                local a = p.assets
                local assetItems = {
                    C.SectionTitle {text = "自持物业运营"},
                }
                if p._fixedAssetConverted then
                    table.insert(assetItems, C.InfoRow {label = "状态", value = "已转入固定资产", color = T.Success})
                    table.insert(assetItems, UI.Label {text = "请在资产运营中心的固定资产页查看估值、装修和出租。", fontSize = T.FontCaption, fontColor = T.TextMuted})
                else
                    table.insert(assetItems, C.InfoRow {label = "状态", value = a.rentable and "已出租" or "待竣工", color = a.rentable and T.Success or T.TextMuted})
                    if a.rentable then
                        table.insert(assetItems, C.InfoRow {label = "出租率", value = a.occupancyRate .. "%", color = a.occupancyRate >= 80 and T.Success or T.Warning})
                        table.insert(assetItems, C.InfoRow {label = "月租金单价", value = string.format("%.1f元/㎡/月", a.monthlyRentPricePerSqm)})
                        table.insert(assetItems, C.InfoRow {label = "本月租金收入", value = GD.FormatMoney(a.monthlyRentIncome), color = T.Success})
                        table.insert(assetItems, C.InfoRow {label = "累计租金收入", value = GD.FormatMoney(a.totalRentIncome)})
                    end
                end
                table.insert(items, C.Card {children = assetItems})
            end
            return UI.Panel {width = "100%", gap = 10, children = items}
        end

        -- 未规划: 让玩家选择分配方案
        if not M._planHoldUnits then M._planHoldUnits = 0 end
        local holdUnits = M._planHoldUnits
        local sellUnits = totalUnits - holdUnits
        local holdPct = totalUnits > 0 and math.floor(holdUnits / totalUnits * 100) or 0

        -- 预制方案按钮
        local presets = {}
        local presetDefs = {
            {name = "全部销售", hold = 0},
            {name = "自持20%", hold = math.floor(totalUnits * 0.2)},
            {name = "自持50%", hold = math.floor(totalUnits * 0.5)},
            {name = "全部自持", hold = totalUnits},
        }
        for _, preset in ipairs(presetDefs) do
            local capturedPreset = preset
            table.insert(presets, UI.Button {
                text = capturedPreset.name,
                fontSize = T.FontSmall,
                backgroundColor = (holdUnits == capturedPreset.hold) and T.PrimaryLight or T.BgInput,
                fontColor = (holdUnits == capturedPreset.hold) and T.Primary or T.TextPrimary,
                borderRadius = 6, paddingHorizontal = 12, height = 28,
                onClick = function()
                    M._planHoldUnits = capturedPreset.hold
                    navigate("project")
                end,
            })
        end

        -- 调整按钮
        local adjButtons = {}
        local steps = {-10, -1, 1, 10}
        for _, step in ipairs(steps) do
            local capturedStep = step
            local label = capturedStep > 0 and ("+" .. capturedStep) or tostring(capturedStep)
            table.insert(adjButtons, UI.Button {
                text = label, fontSize = T.FontSmall,
                backgroundColor = T.BgInput, fontColor = T.TextPrimary,
                borderRadius = 6, width = 48, height = 30,
                onClick = function()
                    local newHold = math.max(0, math.min(totalUnits, holdUnits + capturedStep))
                    M._planHoldUnits = newHold
                    navigate("project")
                end,
            })
        end

        -- 收益预估
        local city = GD.GetCityData(p.land and p.land.city or nil)
        local salePrice = math.floor(DT.GetExpectedPrice(
            p.devTypeId,
            city.avgPrice,
            p.plotLocation or (p.land and p.land.plotLocation) or "suburb",
            p.standardId or "basic",
            p.land and p.land.floorPrice or 0
        ) * (GD.economy.priceIndex / 100))
        local sellRevenue = sellUnits * avgArea * salePrice / 10000
        local annualRent = holdUnits * avgArea * salePrice / 20 / 10000

        return UI.Panel {width = "100%", gap = 10, children = {
            C.Card {children = (function()
                local planItems = {
                    C.SectionTitle {text = "单元分配规划"},
                    C.InfoRow {label = "项目总套数", value = totalUnits .. "套 (户均约" .. avgArea .. "㎡)"},
                }
                -- 自持比例不再强制，无最低自持要求
                return planItems
            end)()},
            C.Card {children = {
                C.SectionTitle {text = "快捷方案"},
                UI.Panel {flexDirection = "row", gap = 8, flexWrap = "wrap", children = presets},
            }},
            C.Card {children = {
                C.SectionTitle {text = "精确调整自持套数"},
                UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", width = "100%", children = adjButtons},
                UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 6},
                C.InfoRow {label = "销售", value = sellUnits .. "套 (" .. (100 - holdPct) .. "%)", color = T.Success},
                C.InfoRow {label = "自持", value = holdUnits .. "套 (" .. holdPct .. "%)", color = T.Accent},
            }},
            C.Card {children = (function()
                local revItems = {
                    C.SectionTitle {text = "收益预估 (参考市价" .. string.format("%.0f", salePrice) .. "元/㎡)"},
                    C.InfoRow {label = "预计销售回款", value = GD.FormatMoney(sellRevenue), color = T.Success},
                }
                if holdUnits > 0 then
                    table.insert(revItems, C.InfoRow {label = "预计年租金收入", value = GD.FormatMoney(annualRent), color = T.Accent})
                    table.insert(revItems, C.InfoRow {label = "租金回报率", value = "5.0% (年租金=售价1/20)", color = T.TextMuted})
                end
                return revItems
            end)()},
            C.ActionButton {
                text = "确认规划 (不可更改)",
                onClick = function()
                    local ok, err = GD.PlanUnits(p, sellUnits, holdUnits)
                    if not ok then
                        GD.AddEvent("规划失败: " .. (err or "未知错误"), "danger")
                    else
                        M._activeTab = 7 -- 自动切到资金管理
                    end
                    M._planHoldUnits = nil
                    navigate("project")
                end,
            },
        }}
    end

    -- =======================================================================
    -- Tab7: 资金管理
    -- =======================================================================
    local function BuildFundTab()
        local PCM = GD.ProjectCapacity
        local budget = PCM.GetBudgetSummary(p)
        local suggested = PCM.CalcSuggestedAllocation(p)
        local director = PCM.GetProjectDirector(GD.company, p.id)
        local dirBonuses = PCM.GetDirectorBonuses(GD.company, p.id)
        local unassigned = PCM.GetUnassignedDirectors(GD.company)

        local fundCards = {}

        -- 预算概况卡
        local burnInfo = ""
        if budget.burnRate > 0 then
            burnInfo = string.format("月均消耗 %s，预计可支撑 %d 个月",
                C.FormatMoney(budget.burnRate), budget.monthsLeft)
        end
        local lowBudget = budget.remaining < budget.burnRate * 2 and budget.burnRate > 0

        table.insert(fundCards, C.Card {children = {
            C.SectionTitle {text = "项目预算"},
            C.InfoRow {label = "已拨付", value = C.FormatMoney(budget.allocated)},
            C.InfoRow {label = "已支出", value = C.FormatMoney(budget.spent)},
            C.InfoRow {label = "剩余预算", value = C.FormatMoney(budget.remaining), color = lowBudget and T.Danger or T.Success},
            UI.Label {text = burnInfo, fontSize = T.FontSmall, fontColor = lowBudget and T.Warning or T.TextMuted, marginTop = 4},
            lowBudget and UI.Label {text = "预算不足，请及时拨付！", fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 2} or nil,
        }})

        -- 手动拨付操作
        local allocAmounts = {500, 1000, 2000, 5000}
        if suggested > 0 then
            table.insert(allocAmounts, 1, suggested)
        end
        local seen = {}
        local uniqueAmounts = {}
        for _, a in ipairs(allocAmounts) do
            if not seen[a] then
                seen[a] = true
                table.insert(uniqueAmounts, a)
            end
        end
        table.sort(uniqueAmounts)

        local allocBtns = {}
        for _, amt in ipairs(uniqueAmounts) do
            local capturedAmt = amt
            local label = C.FormatMoney(capturedAmt)
            if capturedAmt == suggested and suggested > 0 then label = label .. " (推荐)" end
            local canAfford = cash >= capturedAmt
            table.insert(allocBtns, C.ActionButton {
                text = "拨付 " .. label,
                height = 30, paddingH = 10,
                disabled = not canAfford,
                onClick = function()
                    PCM.AllocateFund(GD.company, p, capturedAmt)
                    GD.AddEvent("【" .. p.name .. "】手动拨付 " .. C.FormatMoney(capturedAmt), "info")
                    navigate("project")
                end,
            })
        end
        table.insert(fundCards, C.Card {children = {
            C.SectionTitle {text = "资金拨付"},
            UI.Label {text = "公司可用现金: " .. C.FormatMoney(cash), fontSize = T.FontSmall, fontColor = T.TextMuted},
            UI.Panel {flexDirection = "row", flexWrap = "wrap", gap = 6, marginTop = 8, children = allocBtns},
        }})

        return UI.Panel {width = "100%", gap = 10, children = fundCards}
    end

    -- =======================================================================
    -- Tab8: 运营管理 (持有型项目专属)
    -- =======================================================================
    local function BuildOperationsTab()
        local cards = {}
        local isHold = (p.devCategory == "hold")

        if not isHold then
            table.insert(cards, C.Card {children = {
                C.SectionTitle {text = "运营管理"},
                UI.Label {text = "仅持有型项目支持运营管理", fontSize = T.FontBody, fontColor = T.TextMuted},
            }})
            return UI.Panel {width = "100%", gap = 10, children = cards}
        end

        local ops = p.operations

        -- ═══════════════════════════════════════════
        -- 状态1: 待选运营模式 (pending_operations)
        -- ═══════════════════════════════════════════
        if p.status == "pending_operations" then
            local modes = DT.GetOperationModes(p.devTypeId)

            -- 标题说明
            table.insert(cards, C.Card {children = {
                C.SectionTitle {text = "🎯 选择运营模式"},
                UI.Label {
                    text = "项目已竣工！请从以下模式中选择一种开始运营。不同模式的收益、成本和风险各有不同。",
                    fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4,
                },
                UI.Label {
                    text = "💡 首次选择免装修费，后续变更需支付改造费用",
                    fontSize = T.FontCaption, fontColor = T.Info,
                },
            }})

            -- 每个模式一个完整卡片
            for _, mode in ipairs(modes) do
                local capturedMode = mode
                local prosText = table.concat(mode.pros or {}, "  ·  ")
                local consText = table.concat(mode.cons or {}, "  ·  ")

                -- 收入评级
                local revLabel, revColor
                if mode.revenueMultiplier >= 1.1 then revLabel = "高收益"; revColor = T.Success
                elseif mode.revenueMultiplier >= 0.9 then revLabel = "中收益"; revColor = T.Info
                else revLabel = "低收益"; revColor = T.Warning end

                -- 成本评级
                local costLabel, costColor
                if mode.opexMultiplier <= 0.85 then costLabel = "低成本"; costColor = T.Success
                elseif mode.opexMultiplier <= 1.0 then costLabel = "中成本"; costColor = T.Info
                else costLabel = "高成本"; costColor = T.Danger end

                -- 培育期评级
                local rampLabel
                if mode.rampUpMultiplier <= 0.5 then rampLabel = "短培育"
                elseif mode.rampUpMultiplier <= 0.8 then rampLabel = "中培育"
                else rampLabel = "长培育" end

                table.insert(cards, C.Card {children = {
                    -- 模式名称 + 选择按钮
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                        UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                            UI.Label {text = mode.icon, fontSize = 22},
                            UI.Label {text = mode.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                        }},
                        C.ActionButton {
                            text = "选择此模式", height = 32, paddingH = 16,
                            onClick = function()
                                local ok, err = GD.SelectOperationMode(p, capturedMode.id)
                                if not ok then
                                    GD.AddEvent("选择失败: " .. (err or ""), "warning")
                                end
                                navigate("project")
                            end,
                        },
                    }},
                    -- 描述
                    UI.Label {text = mode.description, fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4},
                    -- 数据指标
                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", marginTop = 8, flexWrap = "wrap", children = {
                        C.Badge {text = revLabel .. " ×" .. string.format("%.2f", mode.revenueMultiplier), variant = mode.revenueMultiplier >= 1.0 and "success" or "warning"},
                        C.Badge {text = costLabel .. " ×" .. string.format("%.2f", mode.opexMultiplier), variant = mode.opexMultiplier <= 1.0 and "info" or "danger"},
                        C.Badge {text = rampLabel .. " ×" .. string.format("%.1f", mode.rampUpMultiplier), variant = "accent"},
                    }},
                    -- 优势/风险
                    #prosText > 0 and UI.Panel {width = "100%", marginTop = 6, padding = 6, backgroundColor = T.SuccessBg, borderRadius = 4, children = {
                        UI.Label {text = "✅ " .. prosText, fontSize = T.FontCaption, fontColor = T.Success},
                    }} or nil,
                    #consText > 0 and UI.Panel {width = "100%", marginTop = 4, padding = 6, backgroundColor = T.WarningBg, borderRadius = 4, children = {
                        UI.Label {text = "⚠️ " .. consText, fontSize = T.FontCaption, fontColor = T.Warning},
                    }} or nil,
                }})
            end

        -- ═══════════════════════════════════════════
        -- 状态2: 运营中 (operations / mature / 含 renovating)
        -- ═══════════════════════════════════════════
        elseif p.status == "operations" or p.status == "mature" then
            if not ops then
                table.insert(cards, C.Card {children = {
                    C.SectionTitle {text = "运营管理"},
                    UI.Label {text = "运营数据异常", fontSize = T.FontBody, fontColor = T.Danger},
                }})
                return UI.Panel {width = "100%", gap = 10, children = cards}
            end

            -- ── 装修改造中提示 ──
            if ops.status == "renovating" then
                local prog = OP.GetRenovationProgress(ops)
                local remain = OP.GetRenovationRemaining(ops)
                local pendingName = ops._pendingModeName or "新模式"

                table.insert(cards, C.Card {children = {
                    C.SectionTitle {text = "🔨 装修改造进行中"},
                    -- 进度条
                    UI.Panel {width = "100%", height = 20, backgroundColor = T.BgInput, borderRadius = 10, overflow = "hidden", children = {
                        UI.Panel {width = prog .. "%", height = "100%", backgroundColor = T.Warning, borderRadius = 10},
                    }},
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 4, children = {
                        UI.Label {text = "进度 " .. prog .. "%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = "剩余 " .. remain .. " 个月", fontSize = T.FontCaption, fontColor = T.Warning},
                    }},
                    C.InfoRow {label = "目标模式", value = pendingName, color = T.Accent},
                    C.InfoRow {label = "改造费用", value = GD.FormatMoney(ops.renovationCost), color = T.Danger},
                    C.InfoRow {label = "当前入住率", value = string.format("%.0f%%", (ops.occupancy or 0) * 100), color = T.Warning},
                    UI.Label {
                        text = "⚠️ 装修期间无运营收入，仅产生维护费用。改造完成后将以新模式重新进入培育期。",
                        fontSize = T.FontCaption, fontColor = T.Warning, marginTop = 6,
                    },
                }})
            end

            -- ── 运营概况卡 ──
            local statusName = OP.GetStatusName(p)
            local modeName = ops.operationModeName or "未设定"
            local modeIcon = ""
            local curMode = DT.GetOperationMode(ops.devTypeId, ops.operationMode or "")
            if curMode then modeIcon = curMode.icon .. " " end

            local summaryItems = {C.SectionTitle {text = "📊 运营概况"}}
            table.insert(summaryItems, C.InfoRow {label = "运营模式", value = modeIcon .. modeName, color = T.Accent})
            table.insert(summaryItems, C.InfoRow {label = "运营状态", value = statusName, color = ops.status == "mature" and T.Success or T.Info})
            table.insert(summaryItems, C.InfoRow {label = "出租率/入住率", value = string.format("%.1f%%", ops.occupancy * 100),
                color = ops.occupancy >= 0.8 and T.Success or (ops.occupancy >= 0.5 and T.Warning or T.Danger)})
            table.insert(summaryItems, C.InfoRow {label = "月租金收入", value = GD.FormatMoney(ops.monthlyRevenue), color = T.Success})
            table.insert(summaryItems, C.InfoRow {label = "月运营支出", value = GD.FormatMoney(ops.monthlyOpex), color = T.Danger})
            local noiColor = ops.monthlyNOI >= 0 and T.Success or T.Danger
            table.insert(summaryItems, C.InfoRow {label = "月度NOI", value = GD.FormatMoney(ops.monthlyNOI), color = noiColor})
            table.insert(summaryItems, C.InfoRow {label = "累计NOI", value = GD.FormatMoney(ops.cumulativeNOI),
                color = ops.cumulativeNOI >= 0 and T.Success or T.Danger})
            table.insert(summaryItems, C.InfoRow {label = "资产估值", value = GD.FormatMoney(ops.valuation), color = T.Info})
            if ops.devTypeId ~= "hotel" then
                table.insert(summaryItems, C.InfoRow {label = "租户数", value = ops.tenantCount .. "/" .. ops.maxTenants})
            else
                table.insert(summaryItems, C.InfoRow {label = "客房数", value = tostring(ops.roomCount)})
            end
            table.insert(summaryItems, C.InfoRow {label = "租户满意度", value = math.floor(ops.tenantSatisfaction) .. "%",
                color = ops.tenantSatisfaction >= 70 and T.Success or (ops.tenantSatisfaction >= 50 and T.Warning or T.Danger)})
            table.insert(summaryItems, C.InfoRow {label = "运营月数", value = ops.operatingMonths .. "个月"})
            table.insert(summaryItems, C.InfoRow {label = "模式变更次数", value = tostring(ops.modeChangeCount or 0)})

            -- 收入/成本乘数
            table.insert(summaryItems, UI.Panel {flexDirection = "row", gap = 8, width = "100%", marginTop = 4, children = {
                C.Badge {text = "收入×" .. string.format("%.2f", ops.revenueMultiplier or 1), variant = "success"},
                C.Badge {text = "成本×" .. string.format("%.2f", ops.opexMultiplier or 1), variant = "info"},
            }})
            table.insert(cards, C.Card {children = summaryItems})

            -- ── 租户列表（非酒店） ──
            if ops.devTypeId ~= "hotel" and #ops.tenants > 0 then
                local tenantItems = {C.SectionTitle {text = "🏪 租户列表 (" .. ops.tenantCount .. ")"}}
                local tenantExpandedKey = "tenants_" .. tostring(p.id or p.name or M._selectedProject)
                local tenantsExpanded = M._expandedLists[tenantExpandedKey] == true
                for i = 1, #ops.tenants do
                    if C.ShouldShowListItem(i, tenantsExpanded, 10) then
                        local t = ops.tenants[i]
                        local satColor = t.satisfaction >= 70 and T.Success or (t.satisfaction >= 50 and T.Warning or T.Danger)
                        table.insert(tenantItems, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", padding = 6, backgroundColor = T.BgInput, borderRadius = 4, marginBottom = 3,
                            children = {
                                UI.Panel {gap = 1, flexShrink = 1, children = {
                                    UI.Label {text = t.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                    UI.Label {text = t.area .. "㎡ · 合同" .. t.contractMonths .. "月 · 剩余" .. t.remainMonths .. "月",
                                        fontSize = T.FontCaption, fontColor = T.TextMuted},
                                }},
                                UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                                    UI.Label {text = "满意度" .. t.satisfaction .. "%", fontSize = T.FontCaption, fontColor = satColor},
                                    UI.Label {text = "×" .. string.format("%.1f", t.rentMult), fontSize = T.FontCaption, fontColor = T.Info},
                                }},
                            },
                        })
                    end
                end
                table.insert(tenantItems, C.FoldButton {
                    total = #ops.tenants,
                    limit = 10,
                    expanded = tenantsExpanded,
                    onClick = function()
                        M._expandedLists[tenantExpandedKey] = not tenantsExpanded
                        navigate("project")
                    end,
                })
                table.insert(cards, C.Card {children = tenantItems})
            end

            -- ── NOI趋势（最近12月） ──
            local noiTrend = OP.GetNOITrend(p, 12)
            if #noiTrend > 2 then
                local trendItems = {C.SectionTitle {text = "📈 NOI趋势（近12月）"}}
                local maxNOI = 0.01
                for _, v in ipairs(noiTrend) do
                    maxNOI = math.max(maxNOI, math.abs(v))
                end
                local bars = {}
                for i, v in ipairs(noiTrend) do
                    local pct = math.abs(v) / maxNOI * 100
                    local barColor = v >= 0 and T.Success or T.Danger
                    table.insert(bars, UI.Panel {
                        flex = 1, height = 50, justifyContent = "flex-end", alignItems = "center",
                        children = {
                            UI.Panel {width = "80%", height = math.max(2, pct * 0.4), backgroundColor = barColor, borderRadius = 2},
                            UI.Label {text = string.format("%.0f", v), fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 1},
                        },
                    })
                end
                table.insert(trendItems, UI.Panel {
                    flexDirection = "row", width = "100%", height = 60, gap = 2, alignItems = "flex-end",
                    children = bars,
                })
                table.insert(cards, C.Card {children = trendItems})
            end

            -- ── 变更运营模式（非装修中时显示） ──
            if ops.status ~= "renovating" then
                local modes = DT.GetOperationModes(p.devTypeId)
                if #modes > 1 then
                    local changeItems = {C.SectionTitle {text = "🔄 变更运营模式"}}
                    table.insert(changeItems, UI.Label {
                        text = "变更模式需支付装修改造费用并经历装修期，期间无运营收入。改造完成后重新进入培育期。",
                        fontSize = T.FontCaption, fontColor = T.Warning, marginBottom = 8,
                    })

                    for _, mode in ipairs(modes) do
                        local capturedMode = mode
                        local isCurrent = (ops.operationMode == mode.id)
                        local renovCost = math.floor(p.cost.buildCost * (mode.renovationCost or 0.05))
                        local canAfford = GD.company.cash >= renovCost

                        if isCurrent then
                            table.insert(changeItems, UI.Panel {
                                width = "100%", padding = 10, backgroundColor = T.PrimaryLight,
                                borderRadius = 8, marginBottom = 6, borderWidth = 1, borderColor = T.PrimaryLight,
                                children = {
                                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                                        UI.Label {text = mode.icon .. " " .. mode.name, fontSize = T.FontBody, fontColor = T.Primary},
                                        C.Badge {text = "当前模式", variant = "accent"},
                                    }},
                                    UI.Label {text = mode.description, fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 4},
                                },
                            })
                        else
                            local prosText = table.concat(mode.pros or {}, " · ")
                            local consText = table.concat(mode.cons or {}, " · ")

                            table.insert(changeItems, UI.Panel {
                                width = "100%", padding = 10, backgroundColor = T.BgInput,
                                borderRadius = 8, marginBottom = 6, gap = 4,
                                children = {
                                    UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                                        UI.Panel {gap = 2, flexShrink = 1, children = {
                                            UI.Label {text = mode.icon .. " " .. mode.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                                            UI.Label {text = mode.description, fontSize = T.FontCaption, fontColor = T.TextMuted},
                                        }},
                                        C.ActionButton {
                                            text = canAfford and "变更" or "资金不足",
                                            height = 30, paddingH = 14,
                                            disabled = not canAfford,
                                            onClick = function()
                                                local ok, err = GD.ChangeOperationMode(p, capturedMode.id)
                                                if not ok then
                                                    GD.AddEvent("变更失败: " .. (err or ""), "warning")
                                                end
                                                navigate("project")
                                            end,
                                        },
                                    }},
                                    -- 费用信息
                                    UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
                                        UI.Label {text = "改造费 " .. GD.FormatMoney(renovCost),
                                            fontSize = T.FontCaption, fontColor = canAfford and T.TextMuted or T.Danger},
                                        UI.Label {text = "工期 " .. (mode.renovationMonths or 3) .. "个月",
                                            fontSize = T.FontCaption, fontColor = T.TextMuted},
                                        UI.Label {text = "收入×" .. string.format("%.2f", mode.revenueMultiplier),
                                            fontSize = T.FontCaption, fontColor = T.Success},
                                        UI.Label {text = "成本×" .. string.format("%.2f", mode.opexMultiplier),
                                            fontSize = T.FontCaption, fontColor = mode.opexMultiplier > 1 and T.Danger or T.Info},
                                    }},
                                    -- 优势/风险
                                    #prosText > 0 and UI.Label {text = "✅ " .. prosText, fontSize = T.FontCaption, fontColor = T.Success} or nil,
                                    #consText > 0 and UI.Label {text = "⚠️ " .. consText, fontSize = T.FontCaption, fontColor = T.Warning} or nil,
                                },
                            })
                        end
                    end
                    table.insert(cards, C.Card {children = changeItems})
                end
            end

            -- ── 改造历史 ──
            local history = ops.renovationHistory or {}
            if #history > 0 then
                local histItems = {C.SectionTitle {text = "📋 改造历史"}}
                for i = #history, math.max(1, #history - 4), -1 do
                    local h = history[i]
                    table.insert(histItems, UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        width = "100%", padding = 6, backgroundColor = T.BgInput, borderRadius = 4, marginBottom = 3,
                        children = {
                            UI.Panel {gap = 1, flexShrink = 1, children = {
                                UI.Label {text = (h.fromModeName or "?") .. " → " .. (h.toModeName or "?"),
                                    fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                UI.Label {text = "费用 " .. GD.FormatMoney(h.cost or 0) .. " · 工期 " .. (h.months or 0) .. "月",
                                    fontSize = T.FontCaption, fontColor = T.TextMuted},
                            }},
                            UI.Label {text = "第" .. (h.startMonth or 0) .. "月", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        },
                    })
                end
                table.insert(cards, C.Card {children = histItems})
            end

        -- ═══════════════════════════════════════════
        -- 状态3: 其他（施工中等，尚未进入运营）
        -- ═══════════════════════════════════════════
        else
            table.insert(cards, C.Card {children = {
                C.SectionTitle {text = "运营管理"},
                UI.Label {text = "项目竣工后可选择运营模式开始运营", fontSize = T.FontBody, fontColor = T.TextMuted},
                UI.Label {text = "届时可选择自营、合作运营、整租、酒店加盟等多种模式", fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 4},
            }})
        end

        return UI.Panel {width = "100%", gap = 10, children = cards}
    end

    -- =======================================================================
    -- 主体组装
    -- =======================================================================
    local tabContent
    if tabIdx == 1 then tabContent = BuildPermitsTab()
    elseif tabIdx == 2 then tabContent = BuildDesignTab()
    elseif tabIdx == 3 then tabContent = BuildConstructionTab()
    elseif tabIdx == 4 then tabContent = BuildCostTab()
    elseif tabIdx == 5 then tabContent = BuildProcurementTab()
    elseif tabIdx == 6 then tabContent = BuildUnitPlanTab()
    elseif tabIdx == 7 then tabContent = BuildFundTab()
    elseif tabIdx == 8 then tabContent = BuildOperationsTab()
    else tabContent = BuildFundTab() end

    -- 项目状态
    local statusMap = {
        permits = "报建审批",
        design = "设计阶段",
        construction = "在建",
        presale = "预售中",
        delivery = "交付中",
        pending_operations = "待选运营",
        renovating = "装修改造",
        operations = "运营中",
        mature = "成熟运营",
        settlement = "代建结算",
        completed = "已完成",
    }

    local scrollChildren = {
        C.SectionTitle {text = "项目开发管理"},
    }

    -- 项目选择(仅多项目时显示)
    if #projects > 1 then
        table.insert(scrollChildren, C.TabBar {
            tabs = projTabs,
            active = projIdx,
            onChange = function(idx)
                M._selectedProject = idx
                M._activeTab = 1
                M._conSubTab = 1
                M._customMix = nil
                M._selectedOpts = nil
                M._selectedLayout = nil
                M._expandedCostCat = nil
                navigate("project")
            end,
        })
    end

    -- 项目概况卡
    local typeDef = DT.GetType(p.devTypeId or "rigid_residential")
    local catVariant = (p.devCategory == "hold") and "info" or ((p.devCategory == "agency") and "warning" or "success")
    local statusVariant = (p.status == "completed") and "success"
        or ((p.status == "operations" or p.status == "mature") and "info"
        or ((p.status == "renovating") and "warning"
        or ((p.status == "settlement") and "warning" or "accent")))

    table.insert(scrollChildren, C.Card {children = {
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
            children = {
                UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                    UI.Label {text = p.name, fontSize = T.FontSubtitle, fontColor = T.Accent},
                    C.Badge {text = ((typeDef and typeDef.icon and typeDef.icon ~= "" and (typeDef.icon .. " ") or "") .. (typeDef and typeDef.shortName or "")), variant = catVariant},
                }},
                C.Badge {text = statusMap[p.status] or p.status, variant = statusVariant},
            }
        },
        UI.Panel {
            flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
            children = {
                UI.Label {text = p.land.city .. " · " .. p.land.location, fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = "建面 " .. string.format("%.1f万㎡", p.land.buildArea / 10000), fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = p.land.useType, fontSize = T.FontSmall, fontColor = T.TextMuted},
                UI.Label {text = DT.CATEGORY_NAMES[p.devCategory or "sale"] or "销售型", fontSize = T.FontSmall,
                    fontColor = catVariant == "info" and T.Info or (catVariant == "warning" and T.Warning or T.Success)},
            }
        },
    }})

    -- ── 项目生命周期进度条 ──
    local cat = p.devCategory or "sale"
    local lifecyclePhases, lifecycleIcons
    if cat == "hold" then
        lifecyclePhases = {"permits", "design", "construction", "pending_operations", "renovating", "operations", "mature"}
        lifecycleIcons = {"📋", "📐", "🏗️", "⚙️", "🔨", "🏢", "💎"}
    elseif cat == "agency" then
        lifecyclePhases = {"permits", "design", "construction", "settlement", "completed"}
        lifecycleIcons = {"📋", "📐", "🏗️", "📊", "✅"}
    else
        lifecyclePhases = {"permits", "design", "construction", "presale", "pending_settlement", "pending_completion", "delivery", "completed"}
        lifecycleIcons = {"📋", "📐", "🏗️", "🏠", "💰", "✔️", "📦", "✅"}
    end
    local lifecycleNames = {
        permits = "四证", design = "设计", construction = "施工",
        presale = "预售", pending_settlement = "结算", pending_completion = "竣工", delivery = "交付", completed = "完成",
        pending_operations = "选运营", renovating = "装修", operations = "运营", mature = "成熟", settlement = "结算",
    }
    local curPhaseIdx = 0
    for i, ph in ipairs(lifecyclePhases) do
        if ph == p.status then curPhaseIdx = i break end
    end
    if curPhaseIdx == 0 then curPhaseIdx = 1 end -- fallback

    local phaseNodes = {}
    for i, ph in ipairs(lifecyclePhases) do
        local isDone = (i < curPhaseIdx)
        local isCurrent = (i == curPhaseIdx)
        local bgColor = isDone and T.Success or (isCurrent and T.PrimaryLight or T.BgInput)
        local txtColor = isDone and T.TextOnDark or (isCurrent and T.Primary or T.TextMuted)
        -- 节点
        table.insert(phaseNodes, UI.Panel {
            alignItems = "center", gap = 2,
            children = {
                UI.Panel {
                    width = 28, height = 28, borderRadius = 14,
                    backgroundColor = bgColor, justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label {text = isDone and "✓" or lifecycleIcons[i], fontSize = 12, fontColor = txtColor},
                    },
                },
                UI.Label {
                    text = lifecycleNames[ph] or ph, fontSize = T.FontCaption,
                    fontColor = isCurrent and T.PrimaryLight or (isDone and T.Success or T.TextMuted),
                },
            },
        })
        -- 连线（非最后一个）
        if i < #lifecyclePhases then
            table.insert(phaseNodes, UI.Panel {
                width = 16, height = 2, marginTop = 12,
                backgroundColor = isDone and T.Success or T.Border,
            })
        end
    end
    table.insert(scrollChildren, UI.Panel {
        flexDirection = "row", alignItems = "flex-start", justifyContent = "center",
        width = "100%", paddingVertical = 6, gap = 2,
        children = phaseNodes,
    })

    -- ── 项目经理管理卡 ──
    local pm = p.projectManager
    local pmCardChildren = {}

    if pm and pm.hired then
        -- PM汇报审批优先显示
        if pm.report then
            table.insert(pmCardChildren, UI.Panel {
                width = "100%", padding = 10, backgroundColor = T.WarningBg, borderRadius = 8, gap = 6,
                children = {
                    UI.Panel {flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label {text = "📋", fontSize = 18},
                        UI.Label {text = "项目经理汇报 — 待审批", fontSize = T.FontBody, fontColor = T.Warning},
                    }},
                    UI.Label {text = pm.report.message, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 6, flexWrap = "wrap", marginTop = 4, children = (function()
                        local btns = {}
                        if pm.report.choices then
                            for ci, ch in ipairs(pm.report.choices) do
                                local capturedCI = ci
                                table.insert(btns, C.ActionButton {
                                    text = (ci == 1 and "✅ " or "") .. ch.name,
                                    height = 32, paddingH = 12,
                                    onClick = function()
                                        local ok, err = GD.ApprovePMReport(p, capturedCI)
                                        if not ok then GD.AddEvent("审批失败: " .. (err or ""), "warning") end
                                        navigate("project")
                                    end,
                                })
                            end
                        else
                            table.insert(btns, C.ActionButton {
                                text = "✅ 批准", height = 32, paddingH = 14,
                                onClick = function()
                                    GD.ApprovePMReport(p, 1)
                                    navigate("project")
                                end,
                            })
                        end
                        return btns
                    end)()},
                },
            })
        end

        -- 当前PM信息
        local levelStars = string.rep("⭐", pm.level)
        local bonusTexts = {}
        if pm.speedBonus > 0 then table.insert(bonusTexts, "速度+" .. math.floor(pm.speedBonus * 100) .. "%") end
        if pm.qualityBonus > 0 then table.insert(bonusTexts, "质量+" .. math.floor(pm.qualityBonus * 100) .. "%") end
        if pm.qualityBonus < 0 then table.insert(bonusTexts, "质量" .. math.floor(pm.qualityBonus * 100) .. "%") end
        if pm.costSaving > 0 then table.insert(bonusTexts, "成本-" .. math.floor(pm.costSaving * 100) .. "%") end

        table.insert(pmCardChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
            children = {
                UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                    UI.Label {text = "👔 " .. pm.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = pm.trait, variant = "accent"},
                    UI.Label {text = levelStars, fontSize = 12},
                }},
                UI.Label {text = "月薪 " .. pm.salary .. "万", fontSize = T.FontSmall, fontColor = T.TextMuted},
            },
        })
        if #bonusTexts > 0 then
            table.insert(pmCardChildren, UI.Label {
                text = "加成: " .. table.concat(bonusTexts, "  "),
                fontSize = T.FontSmall, fontColor = T.Success, marginTop = 2,
            })
        end
        table.insert(pmCardChildren, UI.Label {text = pm.desc, fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 2})

        -- 自动模式开关 + 解雇按钮
        table.insert(pmCardChildren, UI.Panel {
            flexDirection = "row", gap = 8, marginTop = 6, alignItems = "center",
            children = {
                UI.Button {
                    text = pm.autoMode and "🤖 自动模式: 开" or "🔧 自动模式: 关",
                    fontSize = T.FontSmall, height = 30,
                    backgroundColor = pm.autoMode and T.Success or T.BgInput,
                    fontColor = pm.autoMode and T.TextPrimary or T.TextSecondary,
                    borderRadius = 6, paddingHorizontal = 12,
                    onClick = function()
                        pm.autoMode = not pm.autoMode
                        GD.AddEvent("【" .. p.name .. "】项目经理自动模式: " .. (pm.autoMode and "开启" or "关闭"), "info")
                        navigate("project")
                    end,
                },
                UI.Button {
                    text = "解雇", fontSize = T.FontSmall, height = 30,
                    backgroundColor = T.Danger, fontColor = T.TextOnDark,
                    borderRadius = 6, paddingHorizontal = 12,
                    onClick = function()
                        GD.FireProjectManager(p)
                        navigate("project")
                    end,
                },
            },
        })
        if pm.autoMode then
            table.insert(pmCardChildren, UI.Label {
                text = "自动模式下，项目经理将自动办理四证、确认设计方案、推进工程，关键决策前会提交汇报等待审批。",
                fontSize = T.FontCaption, fontColor = T.Info, marginTop = 4,
            })
        end
    else
        if pm and pm.released and pm.name then
            local levelStars = string.rep("⭐", pm.level or 1)
            table.insert(pmCardChildren, UI.Panel {
                width = "100%", padding = 10, backgroundColor = T.SuccessBg, borderRadius = 8, gap = 4,
                children = {
                    UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                        UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                            UI.Label {text = "👔 " .. pm.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            C.Badge {text = "已完成", variant = "success"},
                            UI.Label {text = levelStars, fontSize = 12},
                        }},
                        UI.Label {text = "已释放", fontSize = T.FontSmall, fontColor = T.Success},
                    }},
                    UI.Label {text = "该项目经理已完成本项目，可在其他项目重新雇佣；本项目保留其历史记录。", fontSize = T.FontCaption, fontColor = T.TextSecondary},
                },
            })
        end
        -- 未雇佣PM：显示候选人列表
        table.insert(pmCardChildren, UI.Label {
            text = "雇佣项目经理后开启自动模式，可全自动推进项目（四证→设计→施工），关键节点汇报审批。",
            fontSize = T.FontCaption, fontColor = T.TextMuted,
        })
        local availPMs = GD.GetAvailablePMs()
        if #availPMs == 0 then
            table.insert(pmCardChildren, UI.Label {
                text = "暂无可用项目经理（全部已被其他项目雇佣）",
                fontSize = T.FontSmall, fontColor = T.Warning, marginTop = 6,
            })
        else
            for _, pmCand in ipairs(availPMs) do
                local capturedName = pmCand.name
                local stars = string.rep("⭐", pmCand.level)
                local traits = {}
                if pmCand.speedBonus > 0 then table.insert(traits, "速度+" .. math.floor(pmCand.speedBonus * 100) .. "%") end
                if pmCand.qualityBonus > 0 then table.insert(traits, "质量+" .. math.floor(pmCand.qualityBonus * 100) .. "%") end
                if pmCand.qualityBonus < 0 then table.insert(traits, "质量" .. math.floor(pmCand.qualityBonus * 100) .. "%") end
                if pmCand.costSaving > 0 then table.insert(traits, "省成本" .. math.floor(pmCand.costSaving * 100) .. "%") end
                table.insert(pmCardChildren, UI.Panel {
                    width = "100%", padding = 8, backgroundColor = T.BgInput, borderRadius = 6, marginTop = 4, gap = 4,
                    children = {
                        UI.Panel {flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%", children = {
                            UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                                UI.Label {text = pmCand.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                                C.Badge {text = pmCand.trait, variant = "accent"},
                                UI.Label {text = stars, fontSize = 11},
                            }},
                            UI.Label {text = "月薪 " .. pmCand.salary .. "万", fontSize = T.FontSmall, fontColor = T.Warning},
                        }},
                        UI.Label {text = pmCand.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                        UI.Label {text = table.concat(traits, " | "), fontSize = T.FontCaption, fontColor = T.Success},
                        C.ActionButton {
                            text = "雇佣 " .. pmCand.name, height = 28, paddingH = 10,
                            disabled = GD.company.cash < pmCand.salary,
                            onClick = function()
                                local ok, err = GD.HireProjectManager(p, capturedName)
                                if not ok then GD.AddEvent("雇佣失败: " .. (err or ""), "warning") end
                                navigate("project")
                            end,
                        },
                    },
                })
            end
        end
    end

    local pmFinalChildren = {C.SectionTitle {text = "👔 项目经理"}}
    for _, ch in ipairs(pmCardChildren) do table.insert(pmFinalChildren, ch) end
    table.insert(scrollChildren, C.Card {children = pmFinalChildren})

    -- ── 阶段引导提示 ──
    local guideText, guideColor, guideTab = nil, T.Warning, nil
    if p.status == "permits" then
        -- 检查四证进度
        local processingAny = false
        local allDone = true
        for _, permit in ipairs(p.permits) do
            if permit.status == "processing" then processingAny = true end
            if permit.status ~= "done" then allDone = false end
        end
        if not processingAny and not allDone then
            -- 找第一个pending的证
            for _, permit in ipairs(p.permits) do
                if permit.status == "pending" then
                    guideText = "⏩ 下一步: 点击「开始办理」" .. permit.name
                    guideTab = 1
                    break
                end
            end
        elseif processingAny then
            guideText = "⏳ 四证办理中，请等待..."
            guideColor = T.Info
        end
    elseif p.status == "design" then
        local d = p.design
        if d.autoConfirmed then
            -- 代建型：前三步自动确认，只关注审查
            if d.phase == "review" then
                guideText = "⏳ 图纸审查中 (委托方图纸)，请等待审查结果..."
                guideColor = T.Info
            elseif d.phase == "done" then
                guideText = nil  -- 设计已完成，即将自动进入施工
            else
                guideText = "⏳ 设计自动推进中... (" .. math.floor(d.phaseProgress) .. "%)"
                guideColor = T.Info
            end
        elseif d.phase == "concept" and d.phaseProgress >= 100 and not d.planning.confirmed then
            guideText = "⏩ 下一步: 请确认「规划指标」以推进设计"
            guideTab = 2
        elseif d.phase == "schematic" and d.phaseProgress >= 100 and not d.scheme.confirmed then
            local mixDesc = (p.devCategory == "hold") and "业态配比" or "户型配比"
            guideText = "⏩ 下一步: 请确认「方案设计」(选布局+" .. mixDesc .. ")"
            guideTab = 2
        elseif d.phase == "construction_drawing" and d.phaseProgress >= 100 and not d.costCap.confirmed then
            guideText = "⏩ 下一步: 请确认「限额设计」以进入审查"
            guideTab = 2
        elseif d.phase == "review" then
            guideText = "⏳ 图纸审查中，请等待审查结果..."
            guideColor = T.Info
        elseif d.phase ~= "done" then
            local designPhaseNames = {concept = "概念方案", schematic = "扩初设计", construction_drawing = "施工图"}
            guideText = "⏳ " .. (designPhaseNames[d.phase] or "设计") .. "进行中... (" .. math.floor(d.phaseProgress) .. "%)"
            guideColor = T.Info
        end
    elseif p.status == "construction" then
        local phase = p.construction.phase or "none"
        local phaseNames = {foundation = "桩基", structure = "主体", decoration = "装修", landscape = "景观"}
        guideText = "🏗️ 施工中 [" .. (phaseNames[phase] or "施工") .. "] 进度 " .. math.floor(p.construction.progress or 0) .. "%"
        guideColor = T.Info
        guideTab = 3
    elseif p.status == "presale" then
        guideText = "🏠 预售中 已售 " .. (p.sales.soldUnits or 0) .. "/" .. (p.sales.totalUnits or 0) .. "套"
        guideColor = T.Info
    elseif p.status == "pending_settlement" then
        guideText = "💰 施工完成！请进行项目结算（多退少补）"
        guideColor = T.Warning
    elseif p.status == "pending_completion" then
        guideText = "✔️ 结算完成！请确认竣工"
        guideColor = T.Warning
    elseif p.status == "delivery" then
        guideText = "📦 交付阶段，继续销售尾盘"
        guideColor = T.Info
    elseif p.status == "pending_operations" then
        if pm and pm.hired and pm.report then
            guideText = "📋 项目经理已提交汇报，请在上方审批运营模式"
            guideColor = T.Warning
        else
            guideText = "⏩ 下一步: 请选择运营模式（运营管理 Tab）"
            guideColor = T.Warning
            guideTab = 8
        end
    elseif p.status == "operations" then
        local ops = p.operations
        if ops and ops.status == "renovating" then
            local remain = OP.GetRenovationRemaining(ops)
            local prog = OP.GetRenovationProgress(ops)
            guideText = "🔨 装修改造中 进度" .. prog .. "% 剩余" .. remain .. "个月"
            guideColor = T.Warning
            guideTab = 8
        else
            local occ = ops and math.floor((ops.occupancy or 0) * 100) or 0
            guideText = "🏢 运营中 入住率 " .. occ .. "%"
            guideColor = T.Info
        end
    elseif p.status == "settlement" then
        guideText = "📊 结算阶段，等待委托方结算"
        guideColor = T.Info
    elseif p.status == "completed" or p.status == "mature" then
        guideText = (p.salesCleared or p._devArchived) and "✅ 项目已归档，可在营销/资产运营中心查看" or "✅ 项目已完成，可清盘归档"
        guideColor = T.Success
    end

    if guideText then
        table.insert(scrollChildren, UI.Panel {
            width = "100%", padding = 10, borderRadius = 8,
            backgroundColor = guideColor == T.Warning and T.WarningBg or T.InfoBg,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, width = "100%",
                    children = {
                        UI.Label {text = guideText, fontSize = T.FontSmall, fontColor = guideColor, flexShrink = 1},
                        guideTab and UI.Button {
                            text = "前往", fontSize = T.FontCaption,
                            backgroundColor = T.PrimaryLight, fontColor = T.Primary,
                            borderRadius = 4, paddingHorizontal = 12, height = 26,
                            onClick = function()
                                M._activeTab = guideTab
                                navigate("project")
                            end,
                        } or nil,
                    },
                },
            },
        })
    end

    -- 项目结算按钮（pending_settlement 状态显示）
    if p.status == "pending_settlement" then
        local budgetRemaining = p.budget and p.budget.remaining or 0
        local budgetAllocated = p.budget and p.budget.allocated or 0
        local budgetSpent = p.budget and p.budget.spent or 0
        local settlementInfo = {}
        table.insert(settlementInfo, UI.Label { text = "项目施工已完成，需要结算", fontSize = T.FontSubtitle, fontColor = T.Warning })
        table.insert(settlementInfo, UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 })
        table.insert(settlementInfo, C.InfoRow { label = "已拨付预算", value = GD.FormatMoney(budgetAllocated) })
        table.insert(settlementInfo, C.InfoRow { label = "已支出", value = GD.FormatMoney(budgetSpent) })
        if budgetRemaining > 0 then
            table.insert(settlementInfo, C.InfoRow { label = "剩余预算", value = GD.FormatMoney(budgetRemaining), color = T.Success })
            table.insert(settlementInfo, UI.Label {
                text = "结算后将退回 " .. GD.FormatMoney(budgetRemaining) .. " 到公司账户",
                fontSize = T.FontSmall, fontColor = T.Success, textAlign = "center", marginTop = 4,
            })
        elseif budgetRemaining < 0 then
            table.insert(settlementInfo, C.InfoRow { label = "预算超支", value = GD.FormatMoney(math.abs(budgetRemaining)), color = T.Danger })
            table.insert(settlementInfo, UI.Label {
                text = "结算后需从公司账户补缴 " .. GD.FormatMoney(math.abs(budgetRemaining)),
                fontSize = T.FontSmall, fontColor = T.Danger, textAlign = "center", marginTop = 4,
            })
        else
            table.insert(settlementInfo, UI.Label {
                text = "预算刚好用完，无需补缴或退回",
                fontSize = T.FontSmall, fontColor = T.TextSecondary, textAlign = "center", marginTop = 4,
            })
        end
        table.insert(settlementInfo, UI.Panel {
            flexDirection = "row", gap = 10, marginTop = 8, justifyContent = "center",
            children = {
                C.ActionButton {
                    text = "确认结算", height = 40, paddingH = 24,
                    onClick = function()
                        local ok, msg = GD.SettleProject(p)
                        if not ok then
                            GD.AddEvent("结算失败: " .. (msg or ""), "warning")
                        end
                        navigate("project")
                    end,
                },
            },
        })
        table.insert(scrollChildren, C.Card { children = {
            UI.Panel { width = "100%", alignItems = "center", gap = 6, padding = 12, children = settlementInfo },
        }})
    end

    -- 确认竣工按钮（pending_completion 状态显示）
    if p.status == "pending_completion" then
        local settlement = p.settlement or {}
        local infoChildren = {}
        table.insert(infoChildren, UI.Label { text = "项目已结算完成", fontSize = T.FontSubtitle, fontColor = T.Success })
        table.insert(infoChildren, UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 })
        if (settlement.refund or 0) > 0 then
            table.insert(infoChildren, C.InfoRow { label = "已退回余额", value = GD.FormatMoney(settlement.refund), color = T.Success })
        end
        if (settlement.shortfall or 0) > 0 then
            table.insert(infoChildren, C.InfoRow { label = "已补缴差额", value = GD.FormatMoney(settlement.shortfall), color = T.Warning })
        end
        local remainUnits = (p.sales and p.sales.totalUnits or 0) - (p.sales and p.sales.soldUnits or 0)
        local completionHint = "确认竣工后将进入交付阶段，可转固定资产及运营。"
        if remainUnits > 0 then
            completionHint = "确认竣工后，剩余" .. remainUnits .. "套将转为现房销售，可继续在营销页面售卖。"
        end
        table.insert(infoChildren, UI.Label {
            text = completionHint,
            fontSize = T.FontSmall, fontColor = remainUnits > 0 and T.Info or T.TextSecondary, textAlign = "center", marginTop = 4,
        })
        table.insert(infoChildren, UI.Panel {
            flexDirection = "row", gap = 10, marginTop = 8, justifyContent = "center",
            children = {
                C.ActionButton {
                    text = "确认竣工", height = 40, paddingH = 24,
                    onClick = function()
                        local ok, msg = GD.ConfirmCompletion(p)
                        if not ok then
                            GD.AddEvent("竣工失败: " .. (msg or ""), "warning")
                        end
                        navigate("project")
                    end,
                },
            },
        })
        table.insert(scrollChildren, C.Card { children = {
            UI.Panel { width = "100%", alignItems = "center", gap = 6, padding = 12, children = infoChildren },
        }})
    end

    -- ★ 项目已完成 → 清盘归档按钮
    if (p.status == "completed" or p.status == "operations" or p.status == "mature") and not p.salesCleared then
        local archiveChildren = {}
        local sheet = p.clearanceSheet
        table.insert(archiveChildren, UI.Label { text = "项目已完成", fontSize = T.FontSubtitle, fontColor = T.Success })
        table.insert(archiveChildren, UI.Panel { width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4 })
        if sheet and not sheet.taxPaid then
            table.insert(archiveChildren, UI.Label {
                text = "清盘结算清单已生成，请确认缴税后归档。",
                fontSize = T.FontSmall, fontColor = T.Warning,
            })
            table.insert(archiveChildren, C.InfoRow { label = "销售回款", value = GD.FormatMoney(sheet.revenue or 0), color = T.Success })
            if (sheet.holdRevenue or 0) > 0 then
                table.insert(archiveChildren, C.InfoRow { label = "自持估值", value = GD.FormatMoney(sheet.holdRevenue), color = T.Info })
            end
            table.insert(archiveChildren, C.InfoRow { label = "成本合计", value = GD.FormatMoney(sheet.totalCostBeforeTax or 0), color = T.Warning })
            table.insert(archiveChildren, C.InfoRow { label = "税前利润", value = GD.FormatMoney(sheet.grossProfit or 0), color = (sheet.grossProfit or 0) >= 0 and T.Success or T.Danger })
            table.insert(archiveChildren, C.InfoRow { label = "项目所得税", value = GD.FormatMoney(sheet.incomeTax or 0), color = T.Danger })
            table.insert(archiveChildren, C.InfoRow { label = "税后利润", value = GD.FormatMoney(sheet.netProfitAfterTax or 0), color = (sheet.netProfitAfterTax or 0) >= 0 and T.Success or T.Danger })
        else
            table.insert(archiveChildren, UI.Label {
                text = "项目建设和销售/自持资产处理已完成，可生成清盘结算清单。清盘后将从开发列表中移除；自持与固定资产仍可在资产运营中心查看。",
                fontSize = T.FontSmall, fontColor = T.TextSecondary,
            })
        end
        table.insert(archiveChildren, UI.Panel {
            flexDirection = "row", gap = 10, marginTop = 8, justifyContent = "center", flexWrap = "wrap",
            children = {
                (sheet and not sheet.taxPaid) and C.ActionButton {
                    text = "确认缴税并归档", height = 40, paddingH = 24,
                    onClick = function()
                        local ok, msg = GD.ConfirmClearanceTax(p)
                        if ok then
                            p._devArchived = true
                            M._selectedProject = 1
                        elseif msg then
                            GD.AddEvent("清盘失败: " .. msg, "warning")
                        end
                        navigate("project")
                    end,
                } or C.ActionButton {
                    text = "生成清盘清单", height = 40, paddingH = 24,
                    onClick = function()
                        local ok, msg = GD.ManualClearance(p)
                        if ok then
                            p._devArchived = true
                            M._selectedProject = 1
                        elseif msg and msg ~= "clearance_sheet_ready" then
                            GD.AddEvent("清盘失败: " .. msg, "warning")
                        end
                        navigate("project")
                    end,
                },
            },
        })
        table.insert(scrollChildren, C.Card { children = {
            UI.Panel { width = "100%", alignItems = "center", gap = 6, padding = 12, children = archiveChildren },
        }})
    end

    -- 子Tab (持有型增加运营管理)
    local tabNames = {"四证办理", "设计管理", "工程管理", "成本控制", "招采管理", "单元规划", "资金管理"}
    if (p.devCategory == "hold") then
        table.insert(tabNames, "运营管理")
    end
    table.insert(scrollChildren, C.TabBar {
        tabs = tabNames,
        active = tabIdx,
        onChange = function(idx)
            M._activeTab = idx
            M._conSubTab = 1
            navigate("project")
        end,
    })

    table.insert(scrollChildren, tabContent)
    table.insert(scrollChildren, UI.Panel {height = 20})

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 12,
        children = scrollChildren,
    }
end

return M
