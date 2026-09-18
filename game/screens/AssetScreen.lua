-- ============================================================================
-- AssetScreen.lua - 资产运营中心（6-Tab架构）
-- Tab 1: 项目预览 | Tab 2: 销售预览 | Tab 3: 持有运营
-- Tab 4: 自持物业 | Tab 5: 固定资产 | Tab 6: 物业服务
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local DT = require("DevTypes")
local CompanySelector = require("CompanySelector")
local ProjectScreen = require("screens/ProjectScreen")
local SalesScreen = require("screens/SalesScreen")

local M = {}

-- 当前活跃 Tab 索引
local activeTab = 1

-- 固定资产入账：装修选择面板状态
local fixedAssetExpandedId = nil   -- 当前展开装修面板的项目id
local fixedAssetRenovIdx = 1      -- 选中的装修等级索引(1~4)

-- 固定资产装修选择状态（毛坯→装修）
local faRenovExpandedIdx = nil     -- 当前展开装修面板的固定资产索引
local faRenovSelectedIdx = 2       -- 选中的装修等级索引(2=简装,3=精装,4=豪装)

-- 出租挂牌：租户选择状态
local faRentExpandedIdx = nil      -- 当前展开租户选择面板的固定资产索引
local faRentSelectedTenant = 1     -- 选中的租户类型索引(1=企业,2=零售,3=散户)
local projectRentExpandedId = nil  -- 当前展开租户选择面板的自持项目id
local projectRentSelectedTenant = 1 -- 选中的自持项目租户类型索引

local function ResetCompanyState()
    fixedAssetExpandedId = nil
    fixedAssetRenovIdx = 1
    faRenovExpandedIdx = nil
    faRenovSelectedIdx = 2
    faRentExpandedIdx = nil
    faRentSelectedTenant = 1
    projectRentExpandedId = nil
    projectRentSelectedTenant = 1
    M._expandedLists = {}
end

-- 列表展开/收起状态
M._expandedLists = M._expandedLists or {}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 分割线
local function Divider()
    return UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4}
end

--- 空状态提示
local function EmptyHint(text, subText)
    return UI.Panel {
        width = "100%", padding = 30,
        justifyContent = "center", alignItems = "center", gap = 8,
        children = {
            UI.Label {text = text, fontSize = T.FontBody, fontColor = T.TextMuted},
            subText and UI.Label {text = subText, fontSize = T.FontSmall, fontColor = T.TextMuted} or nil,
        }
    }
end

--- 构建固定资产装修选择+缴税确认面板（或展开按钮）
---@param p table 项目
---@param navigate function
---@return table UI元素
local function BuildFixedAssetRenovPanel(p, navigate)
    if p._fixedAssetConverted then
        return C.Badge {text = "已入固定资产", variant = "success"}
    end
    local isExpanded = (fixedAssetExpandedId == p.id)
    if not isExpanded then
        return C.ActionButton {
            text = "入固定资产", paddingH = 12, height = 34,
            onClick = function()
                fixedAssetExpandedId = p.id
                fixedAssetRenovIdx = 1
                navigate("asset")
            end,
        }
    end
    -- 展开面板
    local selIdx = fixedAssetRenovIdx or 1
    local preview = GD.PreviewFixedAssetConvert(p, selIdx)
    if not preview then
        return UI.Label {text = "无法计算入账信息", fontSize = T.FontCaption, fontColor = T.Danger}
    end
    local panelChildren = {}
    table.insert(panelChildren, UI.Label {
        text = "选择装修等级", fontSize = T.FontSubtitle, fontColor = T.Accent,
    })
    -- 装修等级选项
    for li, lv in ipairs(GD.RENOVATION_LEVELS) do
        local captureLi = li
        local isSelected = (li == selIdx)
        local lvPreview = GD.PreviewFixedAssetConvert(p, li)
        local costText = lv.costPerSqm > 0
            and string.format("%d元/㎡ · 共%s", lv.costPerSqm, GD.FormatMoney(lvPreview and lvPreview.renovCost or 0))
            or "免费"
        table.insert(panelChildren, UI.Button {
            text = lv.name .. "  " .. costText,
            fontSize = T.FontCaption,
            backgroundColor = isSelected and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isSelected and T.Primary or T.TabInactiveFont,
            borderRadius = T.ButtonRadius, width = "100%", height = 36,
            paddingHorizontal = 10, marginBottom = 2,
            borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
            onClick = function()
                fixedAssetRenovIdx = captureLi
                navigate("asset")
            end,
        })
    end
    -- 费用预览
    table.insert(panelChildren, UI.Panel {
        width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
        padding = 8, marginTop = 6, gap = 2,
        children = {
            C.InfoRow {label = "建设原值", value = GD.FormatMoney(preview.originalValue)},
            C.InfoRow {label = "装修费用", value = GD.FormatMoney(preview.renovCost),
                color = preview.renovCost > 0 and T.Warning or T.TextMuted},
            C.InfoRow {label = "入账原值（含装修）", value = GD.FormatMoney(preview.bookOriginal)},
            UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 3},
            C.InfoRow {label = "市场估值上限", value = GD.FormatMoney(preview.fullMarketValue), color = T.TextMuted},
            C.InfoRow {label = "装修后评估价", value = GD.FormatMoney(preview.actualMarketValue), color = T.Accent},
            C.InfoRow {label = "增值额", value = GD.FormatMoney(preview.taxableAppreciation),
                color = preview.taxableAppreciation > 0 and T.Info or T.TextMuted},
        }
    })
    -- LAT税费明细
    if preview.latTax > 0 then
        local taxItems = {
            UI.Label {text = "土地增值税（四级超额累进）", fontSize = T.FontCaption, fontColor = T.Warning},
        }
        for _, d in ipairs(preview.latDetails) do
            table.insert(taxItems, C.InfoRow {
                label = "增值率" .. d.range .. " × " .. d.rate .. "%",
                value = GD.FormatMoney(d.tax), color = T.Warning,
            })
        end
        table.insert(taxItems, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 2})
        table.insert(taxItems, C.InfoRow {
            label = "应缴税费（实际税率" .. preview.effectiveRate .. "%）",
            value = GD.FormatMoney(preview.latTax), color = T.Danger,
        })
        table.insert(panelChildren, UI.Panel {
            width = "100%", backgroundColor = T.WarningBg, borderRadius = T.CardRadius,
            padding = 8, marginTop = 4, gap = 2, children = taxItems,
        })
    else
        table.insert(panelChildren, UI.Label {
            text = "无增值，免征土地增值税", fontSize = T.FontCaption, fontColor = T.Success, marginTop = 4,
        })
    end
    -- 总支出汇总
    table.insert(panelChildren, UI.Panel {
        width = "100%", backgroundColor = T.Surface, borderRadius = T.CardRadius,
        padding = 8, marginTop = 4, gap = 2,
        children = {
            C.InfoRow {label = "总支出", value = GD.FormatMoney(preview.totalCost), color = T.Danger},
            C.InfoRow {label = "当前现金", value = GD.FormatMoney(GD.company.cash),
                color = GD.company.cash >= preview.totalCost and T.Success or T.Danger},
        }
    })
    local canAfford = GD.company.cash >= preview.totalCost
    if not canAfford then
        table.insert(panelChildren, UI.Label {
            text = "资金不足，还需" .. GD.FormatMoney(preview.totalCost - GD.company.cash),
            fontSize = T.FontCaption, fontColor = T.Danger, marginTop = 2,
        })
    end
    -- 确认/取消按钮
    local captureP = p
    local captureSelIdx = selIdx
    table.insert(panelChildren, UI.Panel {
        flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
        children = {
            UI.Button {
                text = "取消", fontSize = T.FontBody,
                backgroundColor = T.Surface, fontColor = T.TextSecondary,
                borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 1,
                onClick = function()
                    fixedAssetExpandedId = nil
                    navigate("asset")
                end,
            },
            UI.Button {
                text = canAfford and "确认装修并入账" or "资金不足",
                fontSize = T.FontBody,
                backgroundColor = canAfford and T.Primary or T.TextMuted,
                fontColor = T.TextOnDark,
                borderRadius = T.ButtonRadius, paddingHorizontal = 16, height = 40, flexGrow = 2,
                onClick = canAfford and function()
                    GD.ConvertToFixedAsset(captureP, captureSelIdx)
                    fixedAssetExpandedId = nil
                    activeTab = 5
                    navigate("asset")
                end or nil,
            },
        }
    })
    return UI.Panel {
        width = "100%", gap = 6, marginTop = 6,
        padding = 10, backgroundColor = T.BgElevated, borderRadius = T.CardRadius,
        children = panelChildren,
    }
end

-- ============================================================================
-- Tab 1: 持有运营
-- ============================================================================
local function BuildTab1_HoldOps(navigate)
    local children = {}

    -- 收集持有型运营项目
    local opsProjects = {}
    for _, p in ipairs(GD.projects) do
        if (p.devCategory or "sale") == "hold" and p.operations then
            table.insert(opsProjects, p)
        end
    end

    if #opsProjects == 0 then
        table.insert(children, EmptyHint(
            "暂无持有型运营项目",
            "购物中心/写字楼/公寓/酒店竣工后自动进入运营"
        ))
        return children
    end

    -- 汇总
    local totalNOI, totalRevenue, totalValuation, activeCount = 0, 0, 0, 0
    for _, p in ipairs(opsProjects) do
        local ops = p.operations
        totalNOI = totalNOI + (ops.monthlyNOI or 0)
        totalRevenue = totalRevenue + (ops.totalRevenue or 0)
        totalValuation = totalValuation + (ops.valuation or 0)
        if ops.status ~= "preparing" then activeCount = activeCount + 1 end
    end

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "持有型资产总览"},
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "持有项目", value = #opsProjects .. "个", minWidth = 70, color = T.Info},
            C.StatCard {title = "运营中", value = activeCount .. "个", minWidth = 70, color = T.Success},
            C.StatCard {title = "月NOI", value = GD.FormatMoney(math.floor(totalNOI / 10000)), minWidth = 80, color = T.Accent},
            C.StatCard {title = "资产估值", value = GD.FormatMoney(math.floor(totalValuation / 10000)), minWidth = 80, color = T.Warning},
        }},
        Divider(),
        C.InfoRow {label = "累计运营收入", value = GD.FormatMoney(math.floor(totalRevenue / 10000)), color = T.Success},
        Divider(),
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "一键毛坯入固定资产", bgColor = T.Primary, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for _, project in ipairs(opsProjects) do
                        if not project._fixedAssetConverted then
                            local ok = GD.ConvertToFixedAsset(project, 1)
                            if ok then count = count + 1 end
                        end
                    end
                    if count > 0 then activeTab = 5 end
                    GD.AddEvent("持有项目一键入固定资产完成：" .. count .. "个", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
        }},
    }})

    local opsExpanded = M._expandedLists.holdOpsProjects == true
    for opsDisplayIdx, p in ipairs(opsProjects) do
        if C.ShouldShowListItem(opsDisplayIdx, opsExpanded, 6) then
        local ops = p.operations
        local typeDef = DT.GetType(p.devTypeId)
        local opsStatusMap = {preparing = "筹备期", ramp_up = "爬坡期", mature = "成熟期", declining = "衰退期"}
        local opsStatusColor = {preparing = "warning", ramp_up = "accent", mature = "success", declining = "danger"}
        local occPct = math.floor((ops.occupancy or 0) * 100)

        local items = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", gap = 6, alignItems = "center", children = {
                        UI.Label {text = p.name, fontSize = T.FontSubtitle, fontColor = T.Accent},
                        C.Badge {text = ((typeDef and typeDef.icon and typeDef.icon ~= "" and (typeDef.icon .. " ") or "") .. (typeDef and typeDef.shortName or "")), variant = "info"},
                    }},
                    C.Badge {text = opsStatusMap[ops.status] or ops.status, variant = opsStatusColor[ops.status] or "info"},
                },
            },
            C.InfoRow {label = "运营月数", value = (ops.operatingMonths or 0) .. "个月"},
            C.ProgressCard {
                title = (p.devTypeId == "hotel") and "入住率" or "出租率",
                progress = occPct,
                barColor = occPct >= 80 and T.Success or (occPct >= 50 and T.Warning or T.Danger),
            },
        }

        if ops.tenantCount and ops.maxTenants and ops.maxTenants > 0 then
            table.insert(items, C.InfoRow {label = "租户", value = ops.tenantCount .. "/" .. ops.maxTenants})
        end
        if ops.tenantSatisfaction then
            local satC = ops.tenantSatisfaction >= 70 and T.Success or (ops.tenantSatisfaction >= 50 and T.Warning or T.Danger)
            table.insert(items, C.InfoRow {label = "租户满意度", value = ops.tenantSatisfaction .. "/100", color = satC})
        end

        table.insert(items, Divider())

        local revWan = math.floor((ops.monthlyRevenue or 0) / 10000)
        local opexWan = math.floor((ops.monthlyOpex or 0) / 10000)
        local noiWan = math.floor((ops.monthlyNOI or 0) / 10000)
        table.insert(items, C.InfoRow {label = "月营收", value = GD.FormatMoney(revWan), color = T.Info})
        table.insert(items, C.InfoRow {label = "月运营费用", value = GD.FormatMoney(opexWan), color = T.Warning})
        table.insert(items, C.InfoRow {label = "月NOI", value = GD.FormatMoney(noiWan), color = noiWan > 0 and T.Success or T.Danger})

        if (ops.valuation or 0) > 0 then
            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "资产估值", value = GD.FormatMoney(math.floor(ops.valuation / 10000)), color = T.Accent})
            table.insert(items, C.InfoRow {label = "Cap Rate", value = string.format("%.1f%%", (ops.capRate or 0.05) * 100)})
        end

        -- 操作按钮行
        local btnRow = {}

        -- 入固定资产（装修选择面板）
        table.insert(btnRow, BuildFixedAssetRenovPanel(p, navigate))

        -- 挂牌出售按钮
        if p.isListed then
            table.insert(btnRow, C.SecondaryButton {
                text = "撤回挂牌", paddingH = 12, height = 34,
                onClick = function()
                    GD.DelistAsset(p)
                    navigate("asset")
                end,
            })
        elseif not (p.status == "sold_off") then
            table.insert(btnRow, C.SecondaryButton {
                text = "挂牌出售", paddingH = 12, height = 34,
                onClick = function()
                    -- 挂牌要价默认为估值
                    local askPrice = ops.valuation and math.floor(ops.valuation / 10000) or 0
                    if askPrice <= 0 then askPrice = 5000 end
                    GD.ListAssetForSale(p, askPrice)
                    navigate("asset")
                end,
            })
        end

        if #btnRow > 0 then
            table.insert(items, Divider())
            table.insert(items, UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
                children = btnRow,
            })
        end

        table.insert(children, C.Card {children = items})
        end
    end
    table.insert(children, C.FoldButton {
        total = #opsProjects,
        limit = 6,
        expanded = opsExpanded,
        onClick = function()
            M._expandedLists.holdOpsProjects = not opsExpanded
            navigate("asset")
        end,
    })

    return children
end

-- ============================================================================
-- Tab 2: 自持物业
-- ============================================================================
local function BuildTab2_SelfHeld(navigate)
    local children = {}

    local holdProjects = {}
    for _, p in ipairs(GD.projects) do
        if (p.devCategory or "sale") == "sale" and p.unitPlan and p.unitPlan.planned and p.unitPlan.holdUnits > 0
            and not p.isListed and p.status ~= "sold_off"
            and not p._fixedAssetConverted then
            table.insert(holdProjects, p)
        end
    end

    if #holdProjects == 0 then
        table.insert(children, EmptyHint(
            "暂无自持物业",
            "销售型项目中规划自持单元后将在此显示"
        ))
        return children
    end

    -- 汇总
    local totalHoldUnits, totalHoldArea, totalMonthlyRent, totalAccumRent, rentableCount = 0, 0, 0, 0, 0
    for _, p in ipairs(holdProjects) do
        totalHoldUnits = totalHoldUnits + p.unitPlan.holdUnits
        totalHoldArea = totalHoldArea + p.unitPlan.holdArea
        totalMonthlyRent = totalMonthlyRent + (p.assets and p.assets.monthlyRentIncome or 0)
        totalAccumRent = totalAccumRent + (p.assets and p.assets.totalRentIncome or 0)
        if p.assets and p.assets.rentable then rentableCount = rentableCount + 1 end
    end

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "自持物业总览"},
        UI.Panel {flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "自持项目", value = #holdProjects .. "个", minWidth = 70},
            C.StatCard {title = "自持套数", value = totalHoldUnits .. "套", minWidth = 70},
            C.StatCard {title = "自持面积", value = string.format("%.1f万平", totalHoldArea / 10000), minWidth = 80},
        }},
        Divider(),
        C.InfoRow {label = "已运营物业", value = rentableCount .. "/" .. #holdProjects .. "个", color = rentableCount > 0 and T.Success or T.TextMuted},
        C.InfoRow {label = "本月租金合计", value = GD.FormatMoney(totalMonthlyRent), color = T.Success},
        C.InfoRow {label = "年租金(预估)", value = GD.FormatMoney(totalMonthlyRent * 12)},
        C.InfoRow {label = "年缴纳税收(15%)", value = GD.FormatMoney(math.floor(totalMonthlyRent * 12 * 0.15 * 100) / 100), color = T.Warning},
        C.InfoRow {label = "累计租金收入", value = GD.FormatMoney(totalAccumRent)},
        Divider(),
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "一键毛坯入固定资产", bgColor = T.Primary, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for _, project in ipairs(holdProjects) do
                        if project.assets and project.assets.rentable and not project._fixedAssetConverted then
                            local ok = GD.ConvertToFixedAsset(project, 1)
                            if ok then count = count + 1 end
                        end
                    end
                    if count > 0 then activeTab = 5 end
                    GD.AddEvent("自持物业一键入固定资产完成：" .. count .. "个", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
        }},
    }})

    local selfHeldExpanded = M._expandedLists.selfHeldProjects == true
    for selfHeldDisplayIdx, p in ipairs(holdProjects) do
        if C.ShouldShowListItem(selfHeldDisplayIdx, selfHeldExpanded, 6) then
        local a = p.assets or {}
        local up = p.unitPlan
        local statusText = (a.rentable) and "运营中" or "待竣工"
        local statusVariant = (a.rentable) and "success" or "warning"

        local items = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Label {text = p.name, fontSize = T.FontSubtitle, fontColor = T.Accent},
                    C.Badge {text = statusText, variant = statusVariant},
                }
            },
            C.InfoRow {label = "自持套数", value = up.holdUnits .. "套"},
            C.InfoRow {label = "自持面积", value = up.holdArea .. "平米"},
        }

        if a.rentable then
            local rentalListing = nil
            local rentalIdx = nil
            for ri, rl in ipairs(GD.rentalListings or {}) do
                if rl.projectId == p.id then
                    rentalListing = rl
                    rentalIdx = ri
                    break
                end
            end

            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "月租金单价", value = string.format("%.1f元/平/月", a.monthlyRentPricePerSqm or 0)})
            table.insert(items, C.ProgressCard {
                title = "出租率", progress = a.occupancyRate or 0,
                barColor = (a.occupancyRate or 0) >= 80 and T.Success or T.Warning,
            })
            table.insert(items, C.InfoRow {label = "本月租金收入", value = GD.FormatMoney(a.monthlyRentIncome or 0), color = T.Success})
            local annualRent = (a.monthlyRentIncome or 0) * 12
            local annualRentTax = math.floor(annualRent * 0.15 * 100) / 100
            table.insert(items, C.InfoRow {label = "年租金(预估)", value = GD.FormatMoney(annualRent)})
            table.insert(items, C.InfoRow {label = "年缴纳税收(15%)", value = GD.FormatMoney(annualRentTax), color = T.Warning})
            table.insert(items, C.InfoRow {label = "累计租金收入", value = GD.FormatMoney(a.totalRentIncome or 0)})

            if rentalListing and rentalListing.status == "leased" and rentalListing.tenant then
                table.insert(items, Divider())
                table.insert(items, C.InfoRow {label = "租户", value = rentalListing.tenant.name})
                table.insert(items, C.InfoRow {label = "签约月租", value = GD.FormatMoney(rentalListing.actualRent or 0), color = T.Success})
                table.insert(items, C.InfoRow {label = "租期进度", value = (rentalListing.leaseMonths or 0) .. "/" .. (rentalListing.leaseTerm or 0) .. "个月"})
            elseif rentalListing and rentalListing.status == "seeking" then
                table.insert(items, Divider())
                table.insert(items, C.InfoRow {label = "招租状态", value = "寻找" .. (rentalListing.tenantTypeName or "租户") .. "中（" .. (rentalListing.monthsSeeking or 0) .. "个月）", color = T.Warning})
                table.insert(items, C.InfoRow {label = "目标月租", value = GD.FormatMoney(rentalListing.targetRent or 0)})
            end

            -- 出租挂牌入口
            table.insert(items, Divider())
            local rentActions = {}
            if p.isListedForRent then
                table.insert(rentActions, C.SecondaryButton {
                    text = "撤回出租", paddingH = 12, height = 34,
                    onClick = function()
                        if rentalIdx then GD.DelistRental(rentalIdx) end
                        projectRentExpandedId = nil
                        navigate("asset")
                    end,
                })
            elseif projectRentExpandedId == p.id then
                table.insert(rentActions, UI.Panel {width = "100%", gap = 4, children = (function()
                    local tenantItems = {
                        UI.Label {text = "选择目标租户：", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 2},
                    }
                    for ti, tt in ipairs(GD.TENANT_TYPES) do
                        local isSelected = (projectRentSelectedTenant == ti)
                        table.insert(tenantItems, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", paddingVertical = 6, paddingHorizontal = 8,
                            backgroundColor = isSelected and T.AccentBg or T.TabInactiveBg, borderRadius = 6,
                            borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                            onClick = function() projectRentSelectedTenant = ti; navigate("asset") end,
                            children = {
                                UI.Panel {gap = 2, children = {
                                    UI.Label {text = tt.name, fontSize = T.FontSmall, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                                    UI.Label {text = tt.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                                }},
                                UI.Label {text = "租金系数: x" .. tt.rentMult, fontSize = T.FontCaption, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                            },
                        })
                    end
                    table.insert(tenantItems, UI.Panel {flexDirection = "row", gap = 8, marginTop = 4, children = {
                        C.ActionButton {
                            text = "确认挂牌", paddingH = 12, height = 32, bgColor = T.Success,
                            onClick = function()
                                local tt = GD.TENANT_TYPES[projectRentSelectedTenant]
                                if tt then
                                    local ok, err = GD.ListProjectForRent(p, tt.id)
                                    if not ok then GD.AddEvent(err or "挂牌出租失败", "danger") end
                                end
                                projectRentExpandedId = nil
                                navigate("asset")
                            end,
                        },
                        C.SecondaryButton {
                            text = "取消", paddingH = 12, height = 32,
                            onClick = function() projectRentExpandedId = nil; navigate("asset") end,
                        },
                    }})
                    return tenantItems
                end)()})
            else
                table.insert(rentActions, C.SecondaryButton {
                    text = "挂牌出租", paddingH = 12, height = 34,
                    onClick = function()
                        projectRentExpandedId = p.id
                        navigate("asset")
                    end,
                })
            end
            table.insert(items, UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = rentActions})

            -- 入固定资产（装修选择面板）
            table.insert(items, Divider())
            table.insert(items, BuildFixedAssetRenovPanel(p, navigate))
        else
            table.insert(items, UI.Label {text = "项目竣工后可在此挂牌出租，或转入固定资产运营", fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 4})
        end

        table.insert(children, C.Card {children = items})
        end
    end
    if #holdProjects > 6 then
        table.insert(children, C.FoldButton {
            total = #holdProjects,
            limit = 6,
            expanded = selfHeldExpanded,
            onClick = function()
                M._expandedLists.selfHeldProjects = not selfHeldExpanded
                navigate("asset")
            end,
        })
    end

    return children
end

-- ============================================================================
-- Tab 3: 固定资产
-- ============================================================================
local function BuildTab3_FixedAssets(navigate)
    local children = {}

    if #GD.fixedAssets == 0 then
        table.insert(children, EmptyHint(
            "暂无固定资产",
            "将持有运营项目或自持物业转入固定资产后显示"
        ))
        return children
    end

    -- 汇总
    local summary = GD.GetFixedAssetSummary()
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "固定资产总览"},
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "资产数量", value = summary.count .. "项", minWidth = 70, color = T.Info},
            C.StatCard {title = "账面净值", value = GD.FormatMoney(summary.totalBook), minWidth = 80, color = T.Accent},
            C.StatCard {title = "市场估值", value = GD.FormatMoney(summary.totalMarket), minWidth = 80, color = T.Warning},
            C.StatCard {title = "月租金", value = GD.FormatMoney(summary.totalMonthlyRent), minWidth = 70, color = T.Success},
        }},
        Divider(),
        C.InfoRow {label = "总面积", value = string.format("%.1f万平", summary.totalArea / 10000)},
        C.InfoRow {label = "已抵押资产", value = summary.mortgagedCount .. "项 / " .. GD.FormatMoney(summary.mortgagedValue), color = summary.mortgagedCount > 0 and T.Warning or T.TextMuted},
        C.InfoRow {label = "可抵押价值", value = GD.FormatMoney(summary.unmortgagedValue), color = T.Success},
        Divider(),
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "一键精装毛坯资产", bgColor = T.Primary, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for idx, fa in ipairs(GD.fixedAssets) do
                        if fa.renovLevel == "none" then
                            local ok = GD.RenovateFixedAsset(idx, 3)
                            if ok then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键装修完成：" .. count .. "项固定资产", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
            C.ActionButton {
                text = "一键挂牌出租", bgColor = T.Success, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    local tenant = GD.TENANT_TYPES[faRentSelectedTenant] or GD.TENANT_TYPES[1]
                    for idx, fa in ipairs(GD.fixedAssets) do
                        if not fa.isListedForRent and fa.renovLevel ~= "none" then
                            local ok = GD.ListFixedAssetForRent(idx, tenant.id)
                            if ok then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键挂牌出租完成：" .. count .. "项固定资产", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
            C.SecondaryButton {
                text = "一键撤回出租", height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for i = #GD.rentalListings, 1, -1 do
                        local rl = GD.rentalListings[i]
                        if rl.status == "seeking" or rl.status == "leased" then
                            local ok = GD.DelistRental(i)
                            if ok then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键撤回出租完成：" .. count .. "项", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
        }},
    }})

    -- 装修等级名称映射
    local RENOV_NAMES = {none = "毛坯", basic = "简装", standard = "精装", luxury = "豪装"}

    local listedByProjectName = {}
    for _, listing in ipairs(GD.assetListings or {}) do
        if listing.projectName and listing.status == "listed" then
            listedByProjectName[listing.projectName] = true
        end
    end

    local rentalByAssetIdx = {}
    local activeRentals = {}
    for ri, rl in ipairs(GD.rentalListings or {}) do
        if rl.status == "seeking" or rl.status == "leased" then
            table.insert(activeRentals, {rental = rl, idx = ri})
            if rl.assetIdx then
                rentalByAssetIdx[rl.assetIdx] = {rental = rl, idx = ri}
            end
        end
    end

    -- 各资产明细
    local fixedAssetsExpanded = M._expandedLists.fixedAssets == true
    for idx, fa in ipairs(GD.fixedAssets) do
        if C.ShouldShowListItem(idx, fixedAssetsExpanded, 6) then
        local valueChange = fa.currentValue - fa.originalValue
        local changeColor = valueChange >= 0 and T.Success or T.Danger
        local changeText = (valueChange >= 0 and "+" or "") .. GD.FormatMoney(valueChange)

        -- 检查是否在挂牌出售中
        local isListed = listedByProjectName[fa.projectName] == true

        -- 查找出租挂牌记录
        local rentalInfo = rentalByAssetIdx[idx]
        local rentalListing = rentalInfo and rentalInfo.rental or nil
        local rentalIdx = rentalInfo and rentalInfo.idx or nil

        local items = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = fa.projectName, fontSize = T.FontSubtitle, fontColor = T.Accent},
                    UI.Panel {flexDirection = "row", gap = 4, children = {
                        fa.mortgaged and C.Badge {text = "已抵押", variant = "warning"} or nil,
                        isListed and C.Badge {text = "出售挂牌中", variant = "info"} or nil,
                        fa.isListedForRent and C.Badge {text = (rentalListing and rentalListing.status == "leased") and "已出租" or "招租中", variant = (rentalListing and rentalListing.status == "leased") and "success" or "info"} or nil,
                    }},
                },
            },
        }

        -- 资产类型 + 出租率 + 装修状态（所有固定资产均显示）
        table.insert(items, C.InfoRow {label = "资产类型", value = fa.assetType or "商业物业"})
        table.insert(items, C.InfoRow {label = "持有面积", value = string.format("%.0f平米", fa.holdArea)})
        local renovName = RENOV_NAMES[fa.renovLevel or "none"] or "毛坯"
        local renovColor = (fa.renovLevel == "none") and T.Warning or T.Success
        table.insert(items, C.InfoRow {label = "装修状态", value = renovName, color = renovColor})
        table.insert(items, C.ProgressCard {
            title = "出租率", progress = fa.occupancyRate or 0,
            barColor = (fa.occupancyRate or 0) >= 80 and T.Success or ((fa.occupancyRate or 0) > 0 and T.Warning or T.TextMuted),
        })

        table.insert(items, Divider())
        table.insert(items, C.InfoRow {label = "原值", value = GD.FormatMoney(fa.originalValue)})
        table.insert(items, C.InfoRow {label = "账面净值", value = GD.FormatMoney(fa.bookValue)})
        table.insert(items, C.InfoRow {label = "市场估值", value = GD.FormatMoney(fa.currentValue), color = T.Accent})
        table.insert(items, C.InfoRow {label = "增值/减值", value = changeText, color = changeColor})

        if fa.monthlyRent and fa.monthlyRent > 0 then
            local actualRent = math.floor(fa.monthlyRent * ((fa.occupancyRate or 0) / 100) * 100) / 100
            table.insert(items, C.InfoRow {label = "月租金收入", value = GD.FormatMoney(actualRent), color = T.Success})
            local faAnnualRent = actualRent * 12
            local faAnnualTax = math.floor(faAnnualRent * 0.15 * 100) / 100
            table.insert(items, C.InfoRow {label = "年租金(预估)", value = GD.FormatMoney(faAnnualRent)})
            table.insert(items, C.InfoRow {label = "年缴纳税收(15%)", value = GD.FormatMoney(faAnnualTax), color = T.Warning})
        end

        -- 出租信息（已签约时显示租户信息）
        if rentalListing and rentalListing.status == "leased" and rentalListing.tenant then
            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "租户", value = rentalListing.tenant.name})
            table.insert(items, C.InfoRow {label = "租户类型", value = rentalListing.tenantTypeName})
            table.insert(items, C.InfoRow {label = "签约月租", value = GD.FormatMoney(rentalListing.actualRent or 0), color = T.Success})
            local rlAnnualRent = (rentalListing.actualRent or 0) * 12
            local rlAnnualTax = math.floor(rlAnnualRent * 0.15 * 100) / 100
            table.insert(items, C.InfoRow {label = "年缴纳税收(15%)", value = GD.FormatMoney(rlAnnualTax), color = T.Warning})
            table.insert(items, C.InfoRow {label = "租期进度", value = rentalListing.leaseMonths .. "/" .. rentalListing.leaseTerm .. "个月"})
            table.insert(items, C.InfoRow {label = "累计收租", value = GD.FormatMoney(rentalListing.totalRentCollected or 0)})
        elseif rentalListing and rentalListing.status == "seeking" then
            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "招租状态", value = "寻找" .. rentalListing.tenantTypeName .. "中（" .. rentalListing.monthsSeeking .. "个月）", color = T.Warning})
            table.insert(items, C.InfoRow {label = "目标月租", value = GD.FormatMoney(rentalListing.targetRent)})
        end

        -- ====== 装修按钮（毛坯状态显示） ======
        if fa.renovLevel == "none" then
            table.insert(items, Divider())
            if faRenovExpandedIdx == idx then
                -- 展开装修选择面板
                table.insert(items, UI.Label {text = "选择装修等级：", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4})
                for ri = 2, 4 do
                    local lv = GD.RENOVATION_LEVELS[ri]
                    if lv then
                        local cost = math.floor(fa.holdArea * lv.costPerSqm / 10000)
                        local isSelected = (faRenovSelectedIdx == ri)
                        table.insert(items, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", paddingVertical = 6, paddingHorizontal = 8,
                            backgroundColor = isSelected and T.AccentBg or T.TabInactiveBg, borderRadius = 6,
                            marginBottom = 4, borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                            onClick = function() faRenovSelectedIdx = ri; navigate("asset") end,
                            children = {
                                UI.Panel {gap = 2, children = {
                                    UI.Label {text = lv.name, fontSize = T.FontSmall, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                                    UI.Label {text = lv.costPerSqm .. "元/平米", fontSize = T.FontCaption, fontColor = T.TextMuted},
                                }},
                                UI.Label {text = "费用: " .. GD.FormatMoney(cost), fontSize = T.FontSmall, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                            },
                        })
                    end
                end
                table.insert(items, UI.Panel {flexDirection = "row", gap = 8, marginTop = 4, children = {
                    C.ActionButton {
                        text = "确认装修", paddingH = 12, height = 32, bgColor = T.Success,
                        onClick = function()
                            local ok, err = GD.RenovateFixedAsset(idx, faRenovSelectedIdx)
                            if not ok then GD.AddEvent(err or "装修失败", "danger") end
                            faRenovExpandedIdx = nil
                            navigate("asset")
                        end,
                    },
                    C.SecondaryButton {
                        text = "取消", paddingH = 12, height = 32,
                        onClick = function() faRenovExpandedIdx = nil; navigate("asset") end,
                    },
                }})
            else
                table.insert(items, C.SecondaryButton {
                    text = "装修", paddingH = 12, height = 34,
                    onClick = function()
                        faRenovExpandedIdx = idx
                        faRentExpandedIdx = nil  -- 关闭其他面板
                        navigate("asset")
                    end,
                })
            end
        end

        -- ====== 操作按钮行（挂牌出售 + 挂牌出租） ======
        table.insert(items, Divider())
        local btnRow = {}

        -- 挂牌出售按钮
        if not isListed then
            table.insert(btnRow, C.SecondaryButton {
                text = "挂牌出售", paddingH = 12, height = 34,
                onClick = function()
                    if fa.isMarketPurchase then
                        GD.ListFixedAssetForSale(idx, fa.currentValue)
                    else
                        for _, p in ipairs(GD.projects) do
                            if p.name == fa.projectName then
                                GD.ListAssetForSale(p, fa.currentValue)
                                break
                            end
                        end
                    end
                    navigate("asset")
                end,
            })
        end

        -- 挂牌出租 / 撤回出租按钮
        if fa.isListedForRent then
            table.insert(btnRow, C.SecondaryButton {
                text = "撤回出租", paddingH = 12, height = 34,
                onClick = function()
                    if rentalIdx then
                        GD.DelistRental(rentalIdx)
                    end
                    navigate("asset")
                end,
            })
        elseif fa.renovLevel ~= "none" then
            -- 未出租且已装修 → 可挂牌出租
            if faRentExpandedIdx == idx then
                -- 展开租户选择面板
                table.insert(btnRow, UI.Panel {width = "100%", gap = 4, children = (function()
                    local tenantItems = {
                        UI.Label {text = "选择目标租户：", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 2},
                    }
                    for ti, tt in ipairs(GD.TENANT_TYPES) do
                        local isSelected = (faRentSelectedTenant == ti)
                        table.insert(tenantItems, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", paddingVertical = 6, paddingHorizontal = 8,
                            backgroundColor = isSelected and T.AccentBg or T.TabInactiveBg, borderRadius = 6,
                            borderWidth = 1, borderColor = isSelected and T.PrimaryBorder or T.TabInactiveBorder,
                            onClick = function() faRentSelectedTenant = ti; navigate("asset") end,
                            children = {
                                UI.Panel {gap = 2, children = {
                                    UI.Label {text = tt.name, fontSize = T.FontSmall, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                                    UI.Label {text = tt.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                                }},
                                UI.Label {text = "租金系数: x" .. tt.rentMult, fontSize = T.FontCaption, fontColor = isSelected and T.Accent or T.TabInactiveFont},
                            },
                        })
                    end
                    table.insert(tenantItems, UI.Panel {flexDirection = "row", gap = 8, marginTop = 4, children = {
                        C.ActionButton {
                            text = "确认挂牌", paddingH = 12, height = 32, bgColor = T.Success,
                            onClick = function()
                                local tt = GD.TENANT_TYPES[faRentSelectedTenant]
                                if tt then
                                    local ok, err = GD.ListFixedAssetForRent(idx, tt.id)
                                    if not ok then GD.AddEvent(err or "挂牌出租失败", "danger") end
                                end
                                faRentExpandedIdx = nil
                                navigate("asset")
                            end,
                        },
                        C.SecondaryButton {
                            text = "取消", paddingH = 12, height = 32,
                            onClick = function() faRentExpandedIdx = nil; navigate("asset") end,
                        },
                    }})
                    return tenantItems
                end)()})
            else
                table.insert(btnRow, C.SecondaryButton {
                    text = "挂牌出租", paddingH = 12, height = 34,
                    onClick = function()
                        faRentExpandedIdx = idx
                        faRenovExpandedIdx = nil  -- 关闭其他面板
                        navigate("asset")
                    end,
                })
            end
        end

        if #btnRow > 0 then
            table.insert(items, UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = btnRow})
        end

        table.insert(children, C.Card {children = items})
        end
    end
    table.insert(children, C.FoldButton {
        total = #GD.fixedAssets,
        limit = 6,
        expanded = fixedAssetsExpanded,
        onClick = function()
            M._expandedLists.fixedAssets = not fixedAssetsExpanded
            navigate("asset")
        end,
    })

    -- ================================================================
    -- 挂牌出售记录（有活跃挂牌或有报价时显示）
    -- ================================================================
    local activeListings = {}
    for i, listing in ipairs(GD.assetListings) do
        if listing.status == "listed" then
            table.insert(activeListings, {listing = listing, idx = i})
        end
    end

    if #activeListings > 0 then
        table.insert(children, C.SectionTitle {text = "挂牌出售记录", color = T.Info})

        local listingsExpanded = M._expandedLists.assetListings == true
        for listingDisplayIdx, item in ipairs(activeListings) do
            if C.ShouldShowListItem(listingDisplayIdx, listingsExpanded, 6) then
            local listing = item.listing
            local listIdx = item.idx
            local listItems = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                    children = {
                        UI.Label {text = listing.projectName, fontSize = T.FontSubtitle, fontColor = T.Accent},
                        C.Badge {text = "挂牌" .. listing.monthsListed .. "个月", variant = "info"},
                    },
                },
                C.InfoRow {label = "要价", value = GD.FormatMoney(listing.askingPrice), color = T.Accent},
            }

            -- 显示买家报价
            if #listing.offers > 0 then
                table.insert(listItems, Divider())
                table.insert(listItems, UI.Label {text = "买家报价：", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4})

                for oi, offer in ipairs(listing.offers) do
                    if not offer.expired then
                        local diffPct = math.floor((offer.price - listing.askingPrice) / listing.askingPrice * 100)
                        local diffText = (diffPct >= 0 and "+" or "") .. diffPct .. "%"
                        local diffColor = diffPct >= 0 and T.Success or T.Danger

                        table.insert(listItems, UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                            width = "100%", paddingVertical = 4,
                            backgroundColor = T.BgInput, borderRadius = 6, paddingHorizontal = 8,
                            children = {
                                UI.Panel {gap = 2, children = {
                                    UI.Label {text = offer.buyer, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                                    UI.Panel {flexDirection = "row", gap = 4, children = {
                                        UI.Label {text = GD.FormatMoney(offer.price), fontSize = T.FontSmall, fontColor = T.Accent},
                                        UI.Label {text = diffText, fontSize = T.FontCaption, fontColor = diffColor},
                                    }},
                                }},
                                C.ActionButton {
                                    text = "接受", paddingH = 10, height = 28,
                                    bgColor = T.Success,
                                    onClick = function()
                                        GD.AcceptOffer(listIdx, oi)
                                        navigate("asset")
                                    end,
                                },
                            },
                        })
                    end
                end
            else
                table.insert(listItems, UI.Label {text = "等待买家报价中...", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4})
            end

            -- 撤牌按钮
            table.insert(listItems, Divider())
            table.insert(listItems, C.SecondaryButton {
                text = "撤回挂牌", paddingH = 12, height = 34,
                onClick = function()
                    if listing.isFixedAsset then
                        -- 固定资产挂牌（含市场购入资产）直接撤回
                        listing.status = "delisted"
                        for _, fa in ipairs(GD.fixedAssets) do
                            if fa.projectName == listing.projectName then
                                fa.isListed = false
                                break
                            end
                        end
                        GD.AddEvent("【" .. listing.projectName .. "】已撤回挂牌", "info")
                    else
                        for _, p in ipairs(GD.projects) do
                            if p.name == listing.projectName then
                                GD.DelistAsset(p)
                                break
                            end
                        end
                    end
                    navigate("asset")
                end,
            })

            table.insert(children, C.Card {children = listItems})
            end
        end
        table.insert(children, C.FoldButton {
            total = #activeListings,
            limit = 6,
            expanded = listingsExpanded,
            onClick = function()
                M._expandedLists.assetListings = not listingsExpanded
                navigate("asset")
            end,
        })
    end

    -- ================================================================
    -- 挂牌出租记录（有活跃出租挂牌时显示）
    -- ================================================================
    if #activeRentals > 0 then
        table.insert(children, C.SectionTitle {text = "挂牌出租记录", color = T.Success})

        local rentalsExpanded = M._expandedLists.rentalListings == true
        local visibleRentalCount = 0
        for _, item in ipairs(activeRentals) do
            visibleRentalCount = visibleRentalCount + 1
            if C.ShouldShowListItem(visibleRentalCount, rentalsExpanded, 6) then
                local rl = item.rental
            local rentalIdx = item.idx
            local rlItems = {}

            -- 标题行：资产名 + 状态标签
            local statusBadge
            if rl.status == "seeking" then
                statusBadge = C.Badge {text = "寻找租户(" .. (rl.monthsSeeking or 0) .. "月)", variant = "warning"}
            else
                local progress = (rl.leaseTerm and rl.leaseTerm > 0) and math.floor(rl.leaseMonths / rl.leaseTerm * 100) or 0
                statusBadge = C.Badge {text = "已出租 " .. progress .. "%", variant = "success"}
            end
            table.insert(rlItems, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = rl.assetName, fontSize = T.FontSubtitle, fontColor = T.Accent},
                    statusBadge,
                },
            })

            -- 租户类型 + 目标租金
            table.insert(rlItems, C.InfoRow {label = "目标租户", value = rl.tenantTypeName or "未知", color = T.TextSecondary})
            table.insert(rlItems, C.InfoRow {label = "目标月租", value = GD.FormatMoney(rl.targetRent), color = T.Accent})

            -- 已签约时显示租户详情
            if rl.status == "leased" and rl.tenant then
                table.insert(rlItems, Divider())
                table.insert(rlItems, C.InfoRow {label = "租户", value = rl.tenant.name or "未知", color = T.Success})
                table.insert(rlItems, C.InfoRow {label = "签约月租", value = GD.FormatMoney(rl.tenant.signedRent or rl.targetRent), color = T.Success})
                table.insert(rlItems, C.InfoRow {label = "租期进度", value = rl.leaseMonths .. "/" .. rl.leaseTerm .. "个月", color = T.TextSecondary})
                table.insert(rlItems, C.InfoRow {label = "累计收租", value = GD.FormatMoney(rl.totalRentCollected or 0), color = T.Success})
            end

            -- 撤回出租按钮
            table.insert(rlItems, Divider())
            table.insert(rlItems, C.SecondaryButton {
                text = "撤回出租", paddingH = 12, height = 34,
                onClick = function()
                    GD.DelistRental(rentalIdx)
                    navigate("asset")
                end,
            })

            table.insert(children, C.Card {children = rlItems})
            end
        end
        table.insert(children, C.FoldButton {
            total = #activeRentals,
            limit = 6,
            expanded = rentalsExpanded,
            onClick = function()
                M._expandedLists.rentalListings = not rentalsExpanded
                navigate("asset")
            end,
        })
    end

    return children
end

-- ============================================================================
-- Tab 4: 物业服务
-- ============================================================================
local function BuildTab4_PropertyService(navigate)
    local children = {}

    local propProjects = GD.GetAllPropertyProjects()

    if #propProjects == 0 then
        table.insert(children, EmptyHint(
            "暂无需要物业服务的项目",
            "已售出房产的项目交付后将在此显示"
        ))
        return children
    end

    -- 汇总
    local totalIncome, totalCost, enabledCount, totalStaff = 0, 0, 0, 0
    for _, item in ipairs(propProjects) do
        local pm = item.project.propertyMgmt
        if pm.enabled then
            enabledCount = enabledCount + 1
            totalIncome = totalIncome + (pm.monthlyIncome or 0)
            totalCost = totalCost + (pm.monthlyOperateCost or 0)
        end
        totalStaff = totalStaff + (pm.staffCount or 0)
    end

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "物业服务总览"},
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.StatCard {title = "需服务项目", value = #propProjects .. "个", minWidth = 70, color = T.Info},
            C.StatCard {title = "已启用", value = enabledCount .. "个", minWidth = 70, color = T.Success},
            C.StatCard {title = "物业人员", value = totalStaff .. "人", minWidth = 70, color = T.Accent},
            C.StatCard {title = "月净收入", value = GD.FormatMoney(totalIncome - totalCost), minWidth = 80, color = (totalIncome - totalCost) >= 0 and T.Success or T.Danger},
        }},
        Divider(),
        C.InfoRow {label = "月物业费收入", value = GD.FormatMoney(totalIncome), color = T.Success},
        C.InfoRow {label = "月运营成本", value = GD.FormatMoney(totalCost), color = T.Warning},
        Divider(),
        UI.Panel {flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap", children = {
            C.ActionButton {
                text = "一键启用物业服务", bgColor = T.Primary, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for _, item in ipairs(propProjects) do
                        if not item.project.propertyMgmt.enabled then
                            if GD.TogglePropertyFee(item.idx) then count = count + 1 end
                        end
                    end
                    GD.AddEvent("一键启用物业服务完成：" .. count .. "个项目", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
            C.ActionButton {
                text = "一键建议配员", bgColor = T.Success, height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for _, item in ipairs(propProjects) do
                        local project = item.project
                        local soldUnits = project.sales and project.sales.soldUnits or 0
                        local idealStaff = math.max(1, math.ceil(soldUnits / 50))
                        if GD.SetPropertyStaff(item.idx, idealStaff) then count = count + 1 end
                    end
                    GD.AddEvent("一键物业配员完成：" .. count .. "个项目", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
            C.SecondaryButton {
                text = "一键标准服务", height = 34, paddingH = 12,
                onClick = function()
                    local count = 0
                    for _, item in ipairs(propProjects) do
                        local ok1 = GD.UpgradePropertyService(item.idx, 2)
                        local ok2 = GD.SetPropertyFeeRate(item.idx, 3.0)
                        if ok1 or ok2 then count = count + 1 end
                    end
                    GD.AddEvent("一键标准物业设置完成：" .. count .. "个项目", count > 0 and "success" or "info")
                    navigate("asset")
                end,
            },
        }},
    }})

    -- 各项目物业管理卡片
    local propertyExpanded = M._expandedLists.propertyServiceProjects == true
    for propertyDisplayIdx, item in ipairs(propProjects) do
        if C.ShouldShowListItem(propertyDisplayIdx, propertyExpanded, 6) then
        local p = item.project
        local pIdx = item.idx
        local pm = p.propertyMgmt
        local soldUnits = p.sales and p.sales.soldUnits or 0
        local totalUnits = p.sales and p.sales.totalUnits or 0
        local levelInfo = GD.PROPERTY_SERVICE_LEVELS[pm.serviceLevelIdx] or GD.PROPERTY_SERVICE_LEVELS[1]

        local items = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Panel {gap = 2, children = {
                        UI.Label {text = p.name, fontSize = T.FontSubtitle, fontColor = T.Accent},
                        UI.Label {text = "已售 " .. soldUnits .. "/" .. totalUnits .. " 套", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    }},
                    C.Badge {
                        text = pm.enabled and "服务中" or "未启用",
                        variant = pm.enabled and "success" or "warning",
                    },
                },
            },
        }

        if pm.enabled then
            -- 服务等级
            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "服务等级", value = levelInfo.name .. " (" .. levelInfo.desc .. ")"})
            table.insert(items, C.InfoRow {label = "物业费单价", value = string.format("%.1f元/平/月", pm.feePerSqm)})
            table.insert(items, C.InfoRow {label = "物业人员", value = (pm.staffCount or 0) .. "人"})

            -- 满意度
            local satColor = pm.satisfactionRate >= 70 and T.Success or (pm.satisfactionRate >= 50 and T.Warning or T.Danger)
            table.insert(items, C.ProgressCard {
                title = "业主满意度",
                progress = pm.satisfactionRate,
                barColor = satColor,
            })

            -- 收缴率
            table.insert(items, C.ProgressCard {
                title = "物业费收缴率",
                progress = pm.collectionRate or 0,
                barColor = (pm.collectionRate or 0) >= 80 and T.Success or T.Warning,
            })

            -- 财务
            table.insert(items, Divider())
            table.insert(items, C.InfoRow {label = "月物业费收入", value = GD.FormatMoney(pm.monthlyIncome or 0), color = T.Success})
            table.insert(items, C.InfoRow {label = "月运营成本", value = GD.FormatMoney(pm.monthlyOperateCost or 0), color = T.Warning})
            local netIncome = (pm.monthlyIncome or 0) - (pm.monthlyOperateCost or 0)
            table.insert(items, C.InfoRow {label = "月净收入", value = GD.FormatMoney(netIncome), color = netIncome >= 0 and T.Success or T.Danger})
            table.insert(items, C.InfoRow {label = "累计物业收入", value = GD.FormatMoney(pm.totalIncome or 0)})

            -- 操作按钮
            table.insert(items, Divider())

            -- 升级服务等级
            local levelBtns = {}
            for li, lv in ipairs(GD.PROPERTY_SERVICE_LEVELS) do
                local isActive = (li == pm.serviceLevelIdx)
                table.insert(levelBtns, UI.Button {
                    text = lv.name,
                    fontSize = T.FontCaption,
                    backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
                    fontColor = isActive and T.Primary or T.TabInactiveFont,
                    borderRadius = 4, paddingHorizontal = 8, height = 26,
                    borderWidth = 1, borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
                    onClick = function()
                        if not isActive then
                            GD.UpgradePropertyService(pIdx, li)
                            navigate("asset")
                        end
                    end,
                })
            end
            table.insert(items, UI.Panel {
                width = "100%", gap = 4,
                children = {
                    UI.Label {text = "服务等级：", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 4, flexWrap = "wrap", children = levelBtns},
                }
            })

            -- 增减人员
            local staffRow = {}
            table.insert(staffRow, C.SecondaryButton {
                text = "-1", paddingH = 8, height = 28,
                onClick = function()
                    local c = math.max(0, (pm.staffCount or 0) - 1)
                    GD.SetPropertyStaff(pIdx, c)
                    navigate("asset")
                end,
            })
            table.insert(staffRow, UI.Label {
                text = (pm.staffCount or 0) .. "人",
                fontSize = T.FontBody, fontColor = T.TextPrimary,
                width = 50, textAlign = "center",
            })
            table.insert(staffRow, C.SecondaryButton {
                text = "+1", paddingH = 8, height = 28,
                onClick = function()
                    GD.SetPropertyStaff(pIdx, (pm.staffCount or 0) + 1)
                    navigate("asset")
                end,
            })
            local idealStaff = math.max(1, math.ceil(soldUnits / 50))
            table.insert(items, UI.Panel {
                width = "100%", gap = 4,
                children = {
                    UI.Label {text = "物业人员（建议" .. idealStaff .. "人，每50户配1人）：", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = staffRow},
                }
            })

            -- 调整费率
            local feeRow = {}
            table.insert(feeRow, C.SecondaryButton {
                text = "-0.5", paddingH = 8, height = 28,
                onClick = function()
                    local newFee = math.max(0.5, pm.feePerSqm - 0.5)
                    GD.SetPropertyFeeRate(pIdx, newFee)
                    navigate("asset")
                end,
            })
            table.insert(feeRow, UI.Label {
                text = string.format("%.1f元", pm.feePerSqm),
                fontSize = T.FontBody, fontColor = T.TextPrimary,
                width = 60, textAlign = "center",
            })
            table.insert(feeRow, C.SecondaryButton {
                text = "+0.5", paddingH = 8, height = 28,
                onClick = function()
                    local newFee = math.min(30, pm.feePerSqm + 0.5)
                    GD.SetPropertyFeeRate(pIdx, newFee)
                    navigate("asset")
                end,
            })
            table.insert(items, UI.Panel {
                width = "100%", gap = 4,
                children = {
                    UI.Label {text = "物业费单价调整：", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Panel {flexDirection = "row", gap = 8, alignItems = "center", children = feeRow},
                }
            })

            -- 停用按钮
            table.insert(items, C.SecondaryButton {
                text = "停用物业服务", paddingH = 12, height = 34,
                onClick = function()
                    GD.TogglePropertyFee(pIdx)
                    navigate("asset")
                end,
            })
        else
            -- 未启用 → 一键启用
            table.insert(items, Divider())
            table.insert(items, UI.Label {
                text = "启用物业服务可收取物业费，增加公司收入",
                fontSize = T.FontSmall, fontColor = T.TextMuted,
            })
            table.insert(items, C.ActionButton {
                text = "启用物业服务",
                onClick = function()
                    GD.TogglePropertyFee(pIdx)
                    navigate("asset")
                end,
            })
        end

        table.insert(children, C.Card {children = items})
        end
    end
    table.insert(children, C.FoldButton {
        total = #propProjects,
        limit = 6,
        expanded = propertyExpanded,
        onClick = function()
            M._expandedLists.propertyServiceProjects = not propertyExpanded
            navigate("asset")
        end,
    })

    return children
end

local PROJECT_STATUS_NAMES = {
    permits = "报建审批",
    design = "设计阶段",
    construction = "工程建设",
    presale = "预售中",
    pending_settlement = "待工程结算",
    pending_completion = "待确认竣工",
    pending_operations = "待选运营模式",
    delivery = "交付中",
    completed = "已完成",
    operations = "运营中",
    mature = "成熟运营",
}

local function GetProjectLocation(p)
    local land = p.land or {}
    local city = land.city or "未登记城市"
    local location = land.location or p.plotLocation or "未登记地块"
    return city .. " · " .. location
end

local function GetProjectProgress(p)
    if p.construction and p.construction.progress ~= nil then
        return math.max(0, math.min(100, math.floor(p.construction.progress)))
    end
    if p.design and p.design.progress ~= nil then
        return math.max(0, math.min(100, math.floor(p.design.progress)))
    end
    return 0
end

local function BuildProjectPreviewTab(navigate)
    local children = {}
    local projects = ProjectScreen.GetVisibleProjects()

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "开发项目预览"},
        UI.Label {
            text = "共 " .. #projects .. " 个开发项目。选择项目可直接进入该项目的开发管理页面。",
            fontSize = T.FontSmall,
            fontColor = T.TextMuted,
            whiteSpace = "normal",
        },
    }})

    if #projects == 0 then
        table.insert(children, EmptyHint("暂无开发项目", "请先在对应城市取得土地并启动开发"))
        return children
    end

    for _, project in ipairs(projects) do
        local capturedProject = project
        local typeDef = DT.GetType(capturedProject.devTypeId or "rigid_residential")
        local progress = GetProjectProgress(capturedProject)
        local cardChildren = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                gap = 8,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = capturedProject.name or "未命名项目",
                                fontSize = T.FontSubtitle,
                                fontColor = T.Accent,
                                fontWeight = "bold",
                                whiteSpace = "normal",
                            },
                            UI.Label {
                                text = GetProjectLocation(capturedProject),
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                                whiteSpace = "normal",
                            },
                        },
                    },
                    C.Badge {
                        text = PROJECT_STATUS_NAMES[capturedProject.status] or tostring(capturedProject.status or "未知状态"),
                        variant = capturedProject.status == "completed" and "success" or "info",
                    },
                },
            },
            C.InfoRow {
                label = "项目类型",
                value = (typeDef and (typeDef.shortName or typeDef.name)) or "未分类",
            },
            C.InfoRow {
                label = "开发类别",
                value = DT.CATEGORY_NAMES[capturedProject.devCategory or "sale"] or "销售型",
            },
            C.ProgressCard {
                title = "开发进度",
                progress = progress,
                barColor = T.Primary,
            },
            C.ActionButton {
                text = "进入项目开发",
                width = "100%",
                height = 36,
                onClick = function()
                    ProjectScreen.OpenProject(capturedProject, navigate)
                end,
            },
        }
        table.insert(children, C.Card {children = cardChildren})
    end

    return children
end

local function GetSalesPreviewStatus(project, group)
    if group == "selling" then
        local sales = project.sales or {}
        if sales.allUnitsSold then return "已售罄待清盘", "warning" end
        return "销售中", "success"
    end
    if group == "ready" then return "可开始预售", "warning" end
    return "施工中待预售", "info"
end

local function BuildSalesPreviewTab(navigate)
    local children = {}
    local readyProjects, sellingProjects, progressProjects = SalesScreen.GetVisibleProjects()
    local projects = {}
    for _, project in ipairs(sellingProjects) do
        projects[#projects + 1] = {project = project, group = "selling"}
    end
    for _, project in ipairs(readyProjects) do
        projects[#projects + 1] = {project = project, group = "ready"}
    end
    for _, project in ipairs(progressProjects) do
        projects[#projects + 1] = {project = project, group = "progress"}
    end

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "销售项目预览"},
        UI.Label {
            text = "共 " .. #projects .. " 个销售相关项目，包含销售中、可预售及施工中待预售项目。",
            fontSize = T.FontSmall,
            fontColor = T.TextMuted,
            whiteSpace = "normal",
        },
    }})

    if #projects == 0 then
        table.insert(children, EmptyHint("暂无销售项目", "销售型项目取得四证后将在此显示"))
        return children
    end

    for _, item in ipairs(projects) do
        local capturedProject = item.project
        local capturedGroup = item.group
        local sales = capturedProject.sales or {}
        local soldUnits = sales.soldUnits or 0
        local totalUnits = sales.totalUnits or 0
        local sellRate = totalUnits > 0 and math.floor(soldUnits / totalUnits * 100) or 0
        local statusText, statusVariant = GetSalesPreviewStatus(capturedProject, capturedGroup)
        local typeDef = DT.GetType(capturedProject.devTypeId or "rigid_residential")
        local cardChildren = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                gap = 8,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = capturedProject.name or "未命名项目",
                                fontSize = T.FontSubtitle,
                                fontColor = T.Accent,
                                fontWeight = "bold",
                                whiteSpace = "normal",
                            },
                            UI.Label {
                                text = GetProjectLocation(capturedProject),
                                fontSize = T.FontCaption,
                                fontColor = T.TextMuted,
                                whiteSpace = "normal",
                            },
                        },
                    },
                    C.Badge {text = statusText, variant = statusVariant},
                },
            },
            C.InfoRow {
                label = "产品类型",
                value = (typeDef and (typeDef.shortName or typeDef.name)) or "未分类",
            },
            C.InfoRow {
                label = "批准售价",
                value = (sales.basePrice or 0) > 0 and ((sales.basePrice or 0) .. " 元/平") or "尚未定价",
            },
            C.InfoRow {
                label = "销售套数",
                value = soldUnits .. " / " .. totalUnits .. " 套",
            },
            C.ProgressCard {
                title = "销售进度",
                progress = sellRate,
                barColor = capturedGroup == "selling" and T.Success or T.Info,
            },
            C.ActionButton {
                text = "进入项目销售",
                width = "100%",
                height = 36,
                onClick = function()
                    SalesScreen.OpenProject(capturedProject, navigate)
                end,
            },
        }
        table.insert(children, C.Card {children = cardChildren})
    end

    return children
end

-- ============================================================================
-- 主入口
-- ============================================================================
function M.Create(navigate)
    -- 统计各 Tab 数据量用于 Badge 显示
    local holdOpsCount = 0
    for _, p in ipairs(GD.projects) do
        if (p.devCategory or "sale") == "hold" and p.operations then
            holdOpsCount = holdOpsCount + 1
        end
    end

    local selfHeldCount = 0
    for _, p in ipairs(GD.projects) do
        if (p.devCategory or "sale") == "sale" and p.unitPlan and p.unitPlan.planned and p.unitPlan.holdUnits > 0
            and not p._fixedAssetConverted then
            selfHeldCount = selfHeldCount + 1
        end
    end

    local fixedCount = #GD.fixedAssets
    local propCount = #GD.GetAllPropertyProjects()
    local projectPreviewCount = #ProjectScreen.GetVisibleProjects()
    local readySalesProjects, sellingProjects, progressSalesProjects = SalesScreen.GetVisibleProjects()
    local salesPreviewCount = #readySalesProjects + #sellingProjects + #progressSalesProjects

    -- Tab 标签（附带数量）
    local tabNames = {
        "项目预览" .. (projectPreviewCount > 0 and ("(" .. projectPreviewCount .. ")") or ""),
        "销售预览" .. (salesPreviewCount > 0 and ("(" .. salesPreviewCount .. ")") or ""),
        "持有运营" .. (holdOpsCount > 0 and ("(" .. holdOpsCount .. ")") or ""),
        "自持物业" .. (selfHeldCount > 0 and ("(" .. selfHeldCount .. ")") or ""),
        "固定资产" .. (fixedCount > 0 and ("(" .. fixedCount .. ")") or ""),
        "物业服务" .. (propCount > 0 and ("(" .. propCount .. ")") or ""),
    }

    -- 构建当前 Tab 内容
    local tabContent = {}
    if activeTab == 1 then
        tabContent = BuildProjectPreviewTab(navigate)
    elseif activeTab == 2 then
        tabContent = BuildSalesPreviewTab(navigate)
    elseif activeTab == 3 then
        tabContent = BuildTab1_HoldOps(navigate)
    elseif activeTab == 4 then
        tabContent = BuildTab2_SelfHeld(navigate)
    elseif activeTab == 5 then
        tabContent = BuildTab3_FixedAssets(navigate)
    elseif activeTab == 6 then
        tabContent = BuildTab4_PropertyService(navigate)
    end

    -- 组装
    local scrollChildren = {
        C.SectionTitle {text = "资产运营中心"},
        CompanySelector.Build {
            navigate = navigate,
            returnScreen = "asset",
            onSwitched = ResetCompanyState,
        },
        C.TabBar {
            tabs = tabNames,
            active = activeTab,
            onChange = function(i)
                activeTab = i
                navigate("asset")
            end,
        },
    }

    for _, child in ipairs(tabContent) do
        table.insert(scrollChildren, child)
    end

    table.insert(scrollChildren, UI.Panel {height = 20})

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 12,
        children = scrollChildren,
    }
end

return M
