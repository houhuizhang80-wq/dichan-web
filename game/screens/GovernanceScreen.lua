-- ============================================================================
-- GovernanceScreen.lua - 公司治理中心 (4-Tab)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local CompanySelector = require("CompanySelector")

local GV = GD.Governance -- Governance 模块

local M = {}
M._activeTab = 1  -- 1=股权结构 2=融资中心 3=分红政策 4=控制权 5=董事会 6=高管团队 7=股权操作
M._customInputs = M._customInputs or {}

function M.Create(navigate)
    local gov = GD.company and GD.company.governance
    if not gov then
        return UI.ScrollView {
            id = "screenScrollView",
            width = "100%", height = "100%", scrollY = true,
            padding = T.PagePadding, gap = 14,
            children = {
                C.SectionTitle {text = "公司治理"},
                CompanySelector.Build {
                    navigate = navigate,
                    returnScreen = "governance",
                    onSwitched = function() M._customInputs = {} end,
                },
                UI.Panel {
                    width = "100%", height = "100%",
                    justifyContent = "center", alignItems = "center", gap = 12,
                    children = {
                        UI.Label {text = "尚未创建公司", fontSize = T.FontTitle, fontColor = T.TextMuted},
                        C.ActionButton {text = "前往创建", onClick = function() navigate("companyCreate") end},
                    },
                },
            },
        }
    end

    -- 确保所有治理字段在渲染前完整初始化（防止旧存档缺字段导致崩溃）
    local fName = GD.player and GD.player.founderName
    GV.EnsureGovernanceFields(gov, fName)

    local tabNames = {"股权结构", "融资中心", "分红政策", "控制权", "董事会", "高管团队", "股权操作"}
    local tabFns = {
        M._TabEquity, M._TabFinancing, M._TabDividend, M._TabControl,
        M._TabBoard, M._TabExecutive, M._TabEquityOps,
    }

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%", height = "100%", scrollY = true,
        padding = T.PagePadding, gap = 14,
        children = {
            C.SectionTitle {text = "公司治理"},
            CompanySelector.Build {
                navigate = navigate,
                returnScreen = "governance",
                onSwitched = function()
                    M._customInputs = {}
                end,
            },

            C.TabBar {
                tabs = tabNames,
                active = M._activeTab,
                onChange = function(idx)
                    M._activeTab = idx
                    navigate("governance")
                end,
            },

            tabFns[M._activeTab](navigate, gov),

            UI.Panel {height = 20},
        }
    }
end

-- ============================================================================
-- Tab1: 股权结构
-- ============================================================================
function M._TabEquity(navigate, gov)
    local presetDef = GV.EQUITY_PRESETS[gov.equityPreset] or GV.EQUITY_PRESETS.sole
    local children = {}

    -- 类型映射
    local typeLabels = {
        founder = "创始人", partner = "合伙人", angel = "天使投资",
        institutional = "机构投资", public = "公众股东",
    }
    local typeVariants = {
        founder = "accent", partner = "info", angel = "warning",
        institutional = "info", public = "success",
    }
    local typeColors = {
        founder = T.Accent, partner = T.Info, angel = T.Warning,
        institutional = T.PrimaryLight, public = T.Success,
    }

    -- 统计
    local totalInvest = 0
    local totalDividends = 0
    local typeCounts = {}
    for _, sh in ipairs(gov.shareholders) do
        totalInvest = totalInvest + (sh.investAmount or 0)
        totalDividends = totalDividends + (sh.totalDividends or 0)
        local t = sh.type or "founder"
        typeCounts[t] = (typeCounts[t] or 0) + 1
    end

    -- 概览指标按四行显示，避免窄屏横向挤压
    table.insert(children, C.Card {children = {
        C.InfoRow {label = "股东数", value = #gov.shareholders .. "位", color = T.Info},
        C.InfoRow {label = "总股本", value = gov.totalShares .. "股", color = T.TextPrimary},
        C.InfoRow {label = "创始人占比", value = string.format("%.1f%%", gov.founderRatio * 100), color = T.Accent},
        C.InfoRow {label = "当前估值", value = C.FormatMoney(gov.lastValuation or 0), color = T.Success},
    }})

    -- 股权模式 + 投资/分红汇总
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "股权概况"},
        C.InfoRow {label = "股权模式", value = presetDef.name, color = T.Info},
        C.InfoRow {label = "ESOP期权池", value = (gov.esopPool or 0) .. "股", color = T.Info},
        UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
        C.InfoRow {label = "累计获投资金", value = C.FormatMoney(totalInvest), color = T.Accent},
        C.InfoRow {label = "累计派发分红", value = C.FormatMoney(totalDividends), color = T.Success},
        C.InfoRow {label = "融资轮次", value = #(gov.financingHistory or {}) .. "轮"},
        gov.isIPO and C.InfoRow {label = "上市状态", value = "已上市", color = T.Success} or nil,
    }})

    -- 股东类型分布
    local typeOrder = {"founder", "partner", "angel", "institutional", "public"}
    local typeSummaryItems = {}
    for _, t in ipairs(typeOrder) do
        if typeCounts[t] then
            -- 计算该类型合计持股比例
            local typeRatio = 0
            for _, sh in ipairs(gov.shareholders) do
                if sh.type == t then typeRatio = typeRatio + sh.ratio end
            end
            table.insert(typeSummaryItems, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8, width = "100%",
                paddingVertical = 3,
                children = {
                    UI.Panel {
                        width = 10, height = 10, borderRadius = 5,
                        backgroundColor = typeColors[t] or T.TextMuted,
                    },
                    UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                        UI.Label {text = typeLabels[t] or t, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                    }},
                    UI.Label {text = typeCounts[t] .. "位", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = string.format("%.1f%%", typeRatio * 100), fontSize = T.FontSmall, fontColor = typeColors[t] or T.TextPrimary},
                }
            })
        end
    end
    if #typeSummaryItems > 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "股东类型分布"},
            UI.Panel {width = "100%", gap = 2, children = typeSummaryItems},
        }})
    end

    -- 持股比例图（水平柱状）
    local pieItems = {}
    for _, sh in ipairs(gov.shareholders) do
        local barWidth = math.max(2, math.floor(sh.ratio * 100))
        local barColor = typeColors[sh.type] or T.Success
        table.insert(pieItems, UI.Panel {
            width = "100%", gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", width = "100%",
                    children = {
                        UI.Label {text = sh.name, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        UI.Label {text = string.format("%.1f%%", sh.ratio * 100), fontSize = T.FontSmall, fontColor = T.TextPrimary},
                    }
                },
                UI.Panel {
                    width = "100%", height = 8, backgroundColor = T.DisabledBg, borderRadius = 4,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = barWidth .. "%", height = "100%",
                            backgroundColor = barColor, borderRadius = 4,
                        }
                    }
                },
            }
        })
    end
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "持股分布"},
        UI.Panel {width = "100%", gap = 6, children = pieItems},
    }})

    -- 股东明细列表（表格形式）
    table.insert(children, C.SectionTitle {text = "股东明细"})
    -- 表头
    table.insert(children, UI.Panel {
        flexDirection = "row", alignItems = "center", width = "100%",
        paddingVertical = 4, paddingHorizontal = 8,
        children = {
            UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, children = {
                UI.Label {text = "股东", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }},
            UI.Panel {width = 60, alignItems = "center", children = {
                UI.Label {text = "类型", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }},
            UI.Panel {width = 60, alignItems = "flex-end", children = {
                UI.Label {text = "持股%", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }},
            UI.Panel {width = 70, alignItems = "flex-end", children = {
                UI.Label {text = "股份数", fontSize = T.FontCaption, fontColor = T.TextMuted},
            }},
        }
    })

    local shCards = {}
    for i, sh in ipairs(gov.shareholders) do
        local roi = (sh.investAmount or 0) > 0
            and ((sh.totalDividends or 0) / sh.investAmount * 100)
            or 0

        -- 紧凑表格行
        table.insert(shCards, UI.Panel {
            width = "100%", gap = 0,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", width = "100%",
                    paddingVertical = 6, paddingHorizontal = 8,
                    backgroundColor = (i % 2 == 0) and T.BgCard or {0, 0, 0, 0},
                    borderRadius = 4,
                    children = {
                        UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, children = {
                            UI.Label {text = sh.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                        }},
                        UI.Panel {width = 60, alignItems = "center", children = {
                            C.Badge {text = typeLabels[sh.type] or sh.type, variant = typeVariants[sh.type] or "info"},
                        }},
                        UI.Panel {width = 60, alignItems = "flex-end", children = {
                            UI.Label {text = string.format("%.1f%%", sh.ratio * 100), fontSize = T.FontSmall, fontColor = T.Accent},
                        }},
                        UI.Panel {width = 70, alignItems = "flex-end", children = {
                            UI.Label {text = tostring(sh.shares), fontSize = T.FontSmall, fontColor = T.TextSecondary},
                        }},
                    }
                },
                -- 展开详情行
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%",
                    paddingHorizontal = 8, paddingBottom = 4, flexWrap = "wrap",
                    children = {
                        UI.Label {
                            text = "投资:" .. C.FormatMoney(sh.investAmount or 0),
                            fontSize = T.FontCaption, fontColor = T.TextMuted,
                        },
                        UI.Label {
                            text = "分红:" .. C.FormatMoney(sh.totalDividends or 0),
                            fontSize = T.FontCaption, fontColor = T.Success,
                        },
                        (sh.investAmount or 0) > 0 and UI.Label {
                            text = string.format("ROI:%.1f%%", roi),
                            fontSize = T.FontCaption,
                            fontColor = roi > 0 and T.Success or T.TextMuted,
                        } or nil,
                    }
                },
            }
        })
    end
    table.insert(children, C.Card {children = shCards})

    -- 融资稀释历史（如果有融资记录）
    if #(gov.financingHistory or {}) > 0 then
        local dilutionItems = {}
        for _, h in ipairs(gov.financingHistory) do
            table.insert(dilutionItems, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%",
                paddingVertical = 4,
                children = {
                    UI.Panel {width = 70, children = {
                        UI.Label {text = h.name, fontSize = T.FontSmall, fontColor = T.Accent},
                    }},
                    UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                        UI.Label {
                            text = string.format("稀释%.1f%% | 融%s", h.dilution * 100, C.FormatMoney(h.raiseAmount)),
                            fontSize = T.FontCaption, fontColor = T.TextSecondary,
                        },
                    }},
                    UI.Panel {width = 60, alignItems = "flex-end", children = {
                        UI.Label {
                            text = string.format("Y%d.M%d", h.year, h.month),
                            fontSize = T.FontCaption, fontColor = T.TextMuted,
                        },
                    }},
                }
            })
        end
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "融资稀释历史"},
            UI.Panel {width = "100%", gap = 2, children = dilutionItems},
        }})
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab2: 融资中心
-- ============================================================================
function M._TabFinancing(navigate, gov)
    local summary = GV.GetFinancingSummary(GD)

    -- 可用轮次
    local roundCards = {}
    for _, roundId in ipairs(GV.ROUND_ORDER) do
        local roundDef = GV.FINANCING_ROUNDS[roundId]
        local canDo, reason = GV.CanFinance(GD, roundId)

        -- 检查是否已完成
        local completed = false
        for _, h in ipairs(gov.financingHistory) do
            if h.round == roundId then completed = true; break end
        end

        local dilMin = math.floor(roundDef.dilutionRange[1] * 100)
        local dilMax = math.floor(roundDef.dilutionRange[2] * 100)
        local valMin = roundDef.valuationMult[1]
        local valMax = roundDef.valuationMult[2]

        local cardItems = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = roundDef.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                    C.Badge {
                        text = completed and "已完成" or (canDo and "可申请" or "未解锁"),
                        variant = completed and "success" or (canDo and "info" or "warning"),
                    },
                }
            },
            C.InfoRow {label = "稀释范围", value = dilMin .. "%-" .. dilMax .. "%"},
            C.InfoRow {label = "估值倍率", value = string.format("%.1fx-%.1fx", valMin, valMax)},
        }

        if roundDef.minRevenue > 0 then
            table.insert(cardItems, C.InfoRow {
                label = "营收门槛",
                value = C.FormatMoney(roundDef.minRevenue),
                color = (GD.company.monthlyRevenue * 12) >= roundDef.minRevenue and T.Success or T.TextMuted,
            })
        end

        if not completed and not canDo and reason then
            table.insert(cardItems, UI.Label {
                text = reason, fontSize = T.FontCaption, fontColor = T.Danger,
            })
        end

        if canDo and not completed then
            -- 使用中间稀释比例
            local midDilution = (roundDef.dilutionRange[1] + roundDef.dilutionRange[2]) / 2
            table.insert(cardItems, C.ActionButton {
                text = string.format("申请%s（出让%.0f%%）", roundDef.name, midDilution * 100),
                onClick = function()
                    local ok, msg = GV.ExecuteFinancing(GD, roundId, midDilution)
                    if ok then
                        GD.AddEvent(msg, "success")
                    else
                        GD.AddEvent(msg or "融资失败", "danger")
                    end
                    navigate("governance")
                end,
            })
        end

        table.insert(roundCards, C.Card {children = cardItems})
    end

    -- 融资历史
    local historyItems = {}
    for _, h in ipairs(gov.financingHistory) do
        table.insert(historyItems, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = h.name, fontSize = T.FontBody, fontColor = T.Accent},
                    UI.Label {text = string.format("Y%d.M%d", h.year, h.month), fontSize = T.FontCaption, fontColor = T.TextMuted},
                }
            },
            C.InfoRow {label = "融资金额", value = C.FormatMoney(h.raiseAmount), color = T.Success},
            C.InfoRow {label = "投前估值", value = C.FormatMoney(h.preValuation)},
            C.InfoRow {label = "投后估值", value = C.FormatMoney(h.postValuation), color = T.Accent},
            C.InfoRow {label = "稀释比例", value = string.format("%.1f%%", h.dilution * 100), color = T.Warning},
            C.InfoRow {label = "投资方", value = h.investorName},
        }})
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            -- 融资概览
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "累计融资", value = C.FormatMoney(summary.totalRaised), color = T.Success, minWidth = 90},
                    C.StatCard {title = "当前估值", value = C.FormatMoney(summary.lastValuation), color = T.Accent, minWidth = 90},
                    C.StatCard {title = "融资轮次", value = summary.rounds .. "轮", color = T.Info, minWidth = 80},
                    C.StatCard {title = "上市状态", value = summary.isIPO and "已上市" or "未上市",
                        color = summary.isIPO and T.Success or T.TextMuted, minWidth = 80},
                }
            },

            -- 融资轮次
            C.SectionTitle {text = "融资轮次", color = T.Info},
            UI.Panel {width = "100%", gap = 8, children = roundCards},

            -- 融资历史
            #historyItems > 0 and C.SectionTitle {text = "融资历史"} or nil,
            #historyItems > 0 and UI.Panel {width = "100%", gap = 8, children = historyItems} or nil,
        }
    }
end

-- ============================================================================
-- Tab3: 分红政策
-- ============================================================================
function M._TabDividend(navigate, gov)
    local policy = gov.dividendPolicy
    local co = GD.company

    -- 分红率预设
    local ratePresets = {0, 0.10, 0.20, 0.30, 0.50}
    local rateBtns = {}
    for _, rate in ipairs(ratePresets) do
        local isActive = math.abs(policy.rate - rate) < 0.01
        table.insert(rateBtns, UI.Button {
            text = math.floor(rate * 100) .. "%",
            fontSize = T.FontBody,
            backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isActive and T.Primary or T.TabInactiveFont,
            borderRadius = 6, borderWidth = 1,
            borderColor = isActive and T.PrimaryLight or T.TabInactiveBorder,
            paddingHorizontal = 16, height = 34,
            onClick = function()
                GV.SetDividendRate(GD, rate)
                navigate("governance")
            end,
        })
    end

    -- 模拟下次分红
    local estDividend = 0
    if co.annualProfit > 0 then
        local maxByProfit = math.floor(co.annualProfit * policy.rate)
        local maxByCash = math.max(0, math.floor(co.cash - co.cash * policy.minCashRatio))
        estDividend = math.min(maxByProfit, maxByCash)
    end
    local founderShare = math.floor(estDividend * gov.founderRatio)

    -- 股东分红明细预览
    local shDividendItems = {}
    for _, sh in ipairs(gov.shareholders) do
        local shShare = math.floor(estDividend * sh.ratio)
        table.insert(shDividendItems, C.InfoRow {
            label = sh.name .. string.format(" (%.1f%%)", sh.ratio * 100),
            value = C.FormatMoney(shShare),
            color = sh.id == "founder" and T.Accent or T.TextPrimary,
        })
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            -- 当前政策
            C.Card {children = {
                C.SectionTitle {text = "分红政策设置", color = T.Accent},
                C.InfoRow {label = "当前分红率", value = math.floor(policy.rate * 100) .. "%", color = T.Accent},
                C.InfoRow {label = "最低现金留存", value = math.floor(policy.minCashRatio * 100) .. "%"},
                UI.Panel {
                    flexDirection = "row", gap = 6, flexWrap = "wrap", width = "100%", marginTop = 8,
                    children = rateBtns,
                },
                UI.Label {
                    text = "分红在每年1月自动发放，基于上年利润",
                    fontSize = T.FontCaption, fontColor = T.TextMuted, marginTop = 8,
                },
            }},

            -- 分红预估
            C.Card {children = {
                C.SectionTitle {text = "下次分红预估", color = T.Info},
                C.InfoRow {label = "年度利润", value = C.FormatMoney(co.annualProfit),
                    color = co.annualProfit > 0 and T.Success or T.Danger},
                C.InfoRow {label = "预计分红总额", value = C.FormatMoney(estDividend), color = T.Accent},
                C.InfoRow {label = "创始人可得", value = C.FormatMoney(founderShare), color = T.Success},
                UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                UI.Panel {width = "100%", gap = 2, children = shDividendItems},
            }},

            -- 历史分红
            C.Card {children = {
                C.SectionTitle {text = "上次分红"},
                C.InfoRow {label = "金额", value = C.FormatMoney(co.lastDividend or 0),
                    color = (co.lastDividend or 0) > 0 and T.Success or T.TextMuted},
            }},
        }
    }
end

-- ============================================================================
-- Tab4: 控制权
-- ============================================================================
function M._TabControl(navigate, gov)
    local founderRatio = gov.founderRatio
    local currentLevel = GV.GetControlLevel(founderRatio)

    -- 控制权等级卡片
    local levelCards = {}
    for _, level in ipairs(GV.CONTROL_LEVELS) do
        local isCurrent = (level.name == currentLevel.name)
        local reached = founderRatio >= level.threshold

        table.insert(levelCards, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 10,
            width = "100%", paddingVertical = 8, paddingHorizontal = 12,
            backgroundColor = isCurrent and T.BgCardHover or {0, 0, 0, 0},
            borderRadius = 6,
            children = {
                -- 标记
                UI.Panel {
                    width = 10, height = 10, borderRadius = 5,
                    backgroundColor = reached and (T[level.color] or T.TextMuted) or T.TrackBg,
                },
                -- 信息
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, children = {
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", width = "100%",
                        children = {
                            UI.Label {
                                text = level.name .. (isCurrent and "  [当前]" or ""),
                                fontSize = T.FontBody,
                                fontColor = isCurrent and T.TextPrimary or T.TextSecondary,
                            },
                            UI.Label {
                                text = level.threshold > 0 and (math.floor(level.threshold * 100) .. "%+") or "<34%",
                                fontSize = T.FontSmall,
                                fontColor = T.TextMuted,
                            },
                        }
                    },
                    UI.Label {text = level.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
            }
        })
    end

    -- 控制权进度条
    local barPct = math.floor(founderRatio * 100)

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            -- 当前控制权
            C.Card {children = {
                C.SectionTitle {text = "创始人控制权", color = T[currentLevel.color] or T.Accent},
                UI.Panel {
                    flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                    children = {
                        C.StatCard {title = "持股比例", value = string.format("%.1f%%", founderRatio * 100), color = T.Accent, minWidth = 90},
                        C.StatCard {title = "控制等级", value = currentLevel.name, color = T[currentLevel.color] or T.TextPrimary, minWidth = 90},
                        C.StatCard {title = "董事会席位", value = gov.boardSeats .. "席", color = T.Info, minWidth = 80},
                    }
                },
                -- 持股进度条（带阈值标记）
                UI.Panel {width = "100%", marginTop = 8, gap = 4, children = {
                    UI.Panel {
                        width = "100%", height = 12, backgroundColor = T.DisabledBg,
                        borderRadius = 6, overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.max(1, barPct) .. "%", height = "100%",
                                backgroundColor = T[currentLevel.color] or T.Accent,
                                borderRadius = 6,
                            }
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", width = "100%",
                        children = {
                            UI.Label {text = "0%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.Label {text = "34%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.Label {text = "50%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.Label {text = "67%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                            UI.Label {text = "100%", fontSize = T.FontCaption, fontColor = T.TextMuted},
                        }
                    },
                }},
            }},

            -- 控制权等级说明
            C.Card {children = {
                C.SectionTitle {text = "控制权等级"},
                UI.Panel {width = "100%", gap = 2, children = levelCards},
            }},

            -- 提示
            C.Card {children = {
                C.SectionTitle {text = "控制权风险提示", color = T.Warning},
                UI.Label {
                    text = "每轮融资会稀释创始人股份。跌破67%将失去绝对控制权（无法单独通过特殊决议），跌破34%将失去否决权。",
                    fontSize = T.FontSmall, fontColor = T.TextSecondary,
                },
                gov.isIPO and UI.Label {
                    text = "公司已上市，股权结构不再变动",
                    fontSize = T.FontSmall, fontColor = T.Info, marginTop = 4,
                } or nil,
            }},
        }
    }
end

-- ============================================================================
-- Tab5: 董事会决策
-- ============================================================================
function M._TabBoard(navigate, gov)
    local co = GD.company

    -- 决议卡片
    local resCards = {}
    for idx, res in ipairs(GV.BOARD_RESOLUTIONS) do
        local canDo, reason = GV.CanProposeResolution(GD, idx)
        local cooldownLeft = 0
        if gov.resolutionCooldowns[res.id] then
            cooldownLeft = math.max(0, res.cooldown - (GD.totalMonths - gov.resolutionCooldowns[res.id]))
        end

        local statusText = canDo and "可发起" or (cooldownLeft > 0 and ("冷却" .. cooldownLeft .. "月") or "不可用")
        local statusVariant = canDo and "success" or (cooldownLeft > 0 and "warning" or "danger")

        table.insert(resCards, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Panel {flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label {text = res.icon, fontSize = T.FontSubtitle},
                        UI.Label {text = res.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                    }},
                    C.Badge {text = statusText, variant = statusVariant},
                }
            },
            UI.Label {text = res.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary, marginTop = 2},
            UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", marginTop = 4, flexWrap = "wrap",
                children = {
                    res.cost > 0 and UI.Label {
                        text = "费用:" .. C.FormatMoney(res.cost),
                        fontSize = T.FontCaption, fontColor = T.Warning,
                    } or nil,
                    UI.Label {
                        text = "表决:" .. math.floor(res.threshold * 100) .. "%+",
                        fontSize = T.FontCaption, fontColor = T.Info,
                    },
                    UI.Label {
                        text = "冷却:" .. res.cooldown .. "月",
                        fontSize = T.FontCaption, fontColor = T.TextMuted,
                    },
                }
            },
            C.ActionButton {
                text = "发起决议",
                bgColor = canDo and T.PrimaryLight or T.DisabledBg,
                fontColor = canDo and T.Primary or T.TextMuted,
                onClick = function()
                    local ok, msg = GV.ProposeResolution(GD, idx)
                    if ok then
                        GD.AddEvent(msg, "success")
                    else
                        GD.AddEvent(msg or "决议失败", "danger")
                    end
                    navigate("governance")
                end,
            },
        }})
    end

    -- 决议历史
    local historyItems = {}
    for i, h in ipairs(gov.resolutionHistory) do
        if i > 10 then break end
        table.insert(historyItems, UI.Panel {
            flexDirection = "row", justifyContent = "space-between",
            alignItems = "center", width = "100%",
            paddingVertical = 6, paddingHorizontal = 8,
            backgroundColor = (i % 2 == 0) and T.BgCard or {0, 0, 0, 0},
            borderRadius = 4,
            children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 1, children = {
                    UI.Label {text = h.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                    UI.Label {
                        text = string.format("Y%d.M%d 赞成%.0f%%", h.year, h.month, (h.yesVotes or 0) * 100),
                        fontSize = T.FontCaption, fontColor = T.TextMuted,
                    },
                }},
                C.Badge {
                    text = h.passed and "通过" or "否决",
                    variant = h.passed and "success" or "danger",
                },
            }
        })
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = {
            -- 概览
            UI.Panel {
                flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
                children = {
                    C.StatCard {title = "累计决议", value = gov.boardDecisionCount .. "项", color = T.Accent, minWidth = 80},
                    C.StatCard {title = "董事会席位", value = gov.boardSeats .. "席", color = T.Info, minWidth = 80},
                    C.StatCard {title = "风险准备金", value = C.FormatMoney(gov.riskReserve or 0), color = T.Warning, minWidth = 90},
                    C.StatCard {title = "ESOP池", value = (gov.esopPool or 0) .. "股", color = T.Success, minWidth = 80},
                }
            },

            -- 可用决议
            C.SectionTitle {text = "董事会决议", color = T.Accent},
            UI.Panel {width = "100%", gap = 8, children = resCards},

            -- 决议历史
            #historyItems > 0 and C.SectionTitle {text = "决议记录"} or nil,
            #historyItems > 0 and C.Card {children = historyItems} or nil,
        }
    }
end

-- ============================================================================
-- Tab6: 高管团队
-- ============================================================================
function M._TabExecutive(navigate, gov)
    local monthlyCost = GV.GetExecutiveMonthlyCost(GD)
    local totalRoles = #GV.EXECUTIVE_ROLES
    local children = {}

    -- 统计
    local hiredCount = 0
    local totalPaidAll = 0
    local activeEffects = {}
    for _, roleDef in ipairs(GV.EXECUTIVE_ROLES) do
        local exec = gov.executives[roleDef.id]
        if exec then
            hiredCount = hiredCount + 1
            totalPaidAll = totalPaidAll + (exec.totalPaid or 0)
            table.insert(activeEffects, {name = roleDef.name, icon = roleDef.icon, desc = roleDef.desc, value = roleDef.effectValue, effect = roleDef.effect})
        end
    end
    local completeness = totalRoles > 0 and (hiredCount / totalRoles) or 0

    -- 概览 StatCards (4列)
    table.insert(children, UI.Panel {
        flexDirection = "row", gap = 10, width = "100%", flexWrap = "wrap",
        children = {
            C.StatCard {title = "在职高管", value = hiredCount .. "/" .. totalRoles, color = T.Accent, minWidth = 80},
            C.StatCard {title = "月薪总额", value = C.FormatMoney(monthlyCost), color = T.Warning, minWidth = 80},
            C.StatCard {title = "年薪总额", value = C.FormatMoney(monthlyCost * 12), color = T.Danger, minWidth = 80},
            C.StatCard {title = "累计支出", value = C.FormatMoney(totalPaidAll), color = T.Info, minWidth = 80},
        }
    })

    -- 团队效能概览卡片
    local teamCardChildren = {
        C.SectionTitle {text = "团队效能概览", color = T.Accent},
    }
    -- 团队完整度进度条
    local barPct = math.floor(completeness * 100)
    local barColor = barPct >= 80 and T.Success or (barPct >= 50 and T.Warning or T.Danger)
    table.insert(teamCardChildren, UI.Panel {
        width = "100%", gap = 4,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Label {text = "团队完整度", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    UI.Label {text = barPct .. "%", fontSize = T.FontSmall, fontColor = barColor},
                }
            },
            UI.Panel {
                width = "100%", height = 10, backgroundColor = T.DisabledBg,
                borderRadius = 5, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = math.max(1, barPct) .. "%", height = "100%",
                        backgroundColor = barColor, borderRadius = 5,
                    }
                }
            },
        }
    })
    -- 激活效果列表
    if #activeEffects > 0 then
        table.insert(teamCardChildren, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 6})
        table.insert(teamCardChildren, UI.Label {text = "激活中的效果", fontSize = T.FontSmall, fontColor = T.TextMuted})
        for _, ae in ipairs(activeEffects) do
            table.insert(teamCardChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8, width = "100%",
                paddingVertical = 4,
                children = {
                    UI.Label {text = ae.icon, fontSize = T.FontBody},
                    UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                        UI.Label {text = ae.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                    }},
                    UI.Label {
                        text = "+" .. math.floor(ae.value * 100) .. "%",
                        fontSize = T.FontBody, fontColor = T.Success,
                    },
                }
            })
        end
    else
        table.insert(teamCardChildren, UI.Label {
            text = "暂未聘用任何高管，无激活效果",
            fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4,
        })
    end
    table.insert(children, C.Card {children = teamCardChildren})

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "CEO委托经营", color = T.Accent},
        UI.Label {
            text = gov.fullManagement
                and ((gov.ceoReportEnabled ~= false)
                    and "委托中：CEO持续推进日常经营，拿地、开发方案和开盘价格按汇报频次提交玩家审批。"
                    or "静默委托中：CEO按现有策略自主执行拿地、开发、开盘和日常经营，不弹出经营汇报。")
                or "未委托：CEO不会自动操作，公司由玩家手动管理。",
            fontSize = T.FontSmall,
            fontColor = gov.fullManagement and T.Success or T.TextSecondary,
        },
        UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", marginTop = 6,
            children = {
                C.ActionButton {
                    text = "开启CEO委托",
                    width = "50%",
                    bgColor = gov.fullManagement and T.DisabledBg or T.Accent,
                    fontColor = gov.fullManagement and T.TextMuted or T.TextOnDark,
                    disabled = gov.fullManagement,
                    onClick = function()
                        local ok, msg = GV.SetFullManagement(GD, true)
                        GD.AddEvent(msg or "委托设置失败", ok and "success" or "warning")
                        navigate("governance")
                    end,
                },
                C.ActionButton {
                    text = "关闭CEO委托",
                    width = "50%",
                    bgColor = not gov.fullManagement and T.Success or T.Accent,
                    fontColor = T.TextOnDark,
                    disabled = not gov.fullManagement,
                    onClick = function()
                        local ok, msg = GV.SetFullManagement(GD, false)
                        GD.AddEvent(msg or "委托设置失败", ok and "success" or "warning")
                        navigate("governance")
                    end,
                },
            },
        },
        gov.fullManagement and UI.Label {
            text = (gov.ceoReportEnabled ~= false)
                and "托管范围：自动招聘CEO团队、项目经理，自动推进结算、竣工、装修缴税转固、挂牌出租、售罄清盘和日常经营；拿地、开发方案、销售/自持比例及开盘价格通过CEO汇报逐项确认。"
                or "静默托管范围：自动招聘团队与项目经理，并按现有经营策略自主拿地、开发、开盘、结算、转固、出租和清盘；关闭汇报不影响CEO持续经营。",
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
            marginTop = 4,
        } or nil,
    }})

    -- CEO汇报设置
    if gov.fullManagement then
        local reportEnabled = gov.ceoReportEnabled ~= false
        local frequency = gov.ceoReportFrequency or "monthly"
        local freqLabels = {monthly = "每月", quarterly = "每季度", yearly = "每年"}
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "CEO汇报设置"},
            UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", alignItems = "center",
                children = {
                    UI.Label {text = "是否汇报：", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    C.ActionButton {
                        text = reportEnabled and "是（汇报中）" or "否（静默托管）",
                        bgColor = reportEnabled and T.Success or T.DisabledBg,
                        fontColor = reportEnabled and T.TextOnDark or T.TextMuted,
                        paddingHorizontal = 12, height = 30,
                        onClick = function()
                            local ok, msg = GV.SetCeoReportEnabled(GD, not reportEnabled)
                            GD.AddEvent(msg or "汇报设置失败", ok and "success" or "warning")
                            navigate("governance")
                        end,
                    },
                },
            },
            reportEnabled and UI.Panel {
                flexDirection = "row", gap = 6, width = "100%", marginTop = 6, alignItems = "center",
                children = {
                    UI.Label {text = "汇报频次：", fontSize = T.FontSmall, fontColor = T.TextSecondary},
                    C.ActionButton {
                        text = "每月",
                        bgColor = frequency == "monthly" and T.Primary or T.BgInput,
                        fontColor = frequency == "monthly" and T.TextOnDark or T.TextPrimary,
                        paddingHorizontal = 10, height = 28,
                        onClick = function() gov.ceoReportFrequency = "monthly"; navigate("governance") end,
                    },
                    C.ActionButton {
                        text = "每季度",
                        bgColor = frequency == "quarterly" and T.Primary or T.BgInput,
                        fontColor = frequency == "quarterly" and T.TextOnDark or T.TextPrimary,
                        paddingHorizontal = 10, height = 28,
                        onClick = function() gov.ceoReportFrequency = "quarterly"; navigate("governance") end,
                    },
                    C.ActionButton {
                        text = "每年",
                        bgColor = frequency == "yearly" and T.Primary or T.BgInput,
                        fontColor = frequency == "yearly" and T.TextOnDark or T.TextPrimary,
                        paddingHorizontal = 10, height = 28,
                        onClick = function() gov.ceoReportFrequency = "yearly"; navigate("governance") end,
                    },
                },
            } or nil,
            UI.Label {
                text = reportEnabled
                    and ("当前" .. (freqLabels[frequency] or "每月") .. "汇报一次经营情况，需审批重大计划。")
                    or "静默托管模式：CEO完全自主决策，不弹窗汇报。资产负债率仍按已设定目标执行。",
                fontSize = T.FontCaption,
                fontColor = T.TextMuted,
                marginTop = 4,
            },
        }})
    end

    -- 在职高管
    local hiredCards = {}
    for _, roleDef in ipairs(GV.EXECUTIVE_ROLES) do
        local exec = gov.executives[roleDef.id]
        if exec then
            local tenure = GD.totalMonths - (exec.hiredMonth or GD.totalMonths)
            local annualCost = exec.salary  -- salary已是年薪
            local monthlySalary = math.floor(exec.salary / 12 * 100) / 100
            local captureRoleId = roleDef.id
            local captureSeverance = math.floor(exec.salary / 12 * 3 * 100) / 100  -- 3个月月薪

            -- 效果描述映射
            local effectLabels = {
                autoManage = "自动经营能力",
                execution = "经营执行效率",
                coordination = "跨部门协同",
                financeControl = "财务管控",
                opexReduce = "运营成本降低",
                opEfficiency = "运营效率提升",
                revenueBoost = "公司收入提升",
                techBoost = "技术竞争力提升",
                riskReduce = "经营风险降低",
                teamBoost = "团队效率提升",
            }
            local effectLabel = effectLabels[roleDef.effect] or roleDef.desc

            table.insert(hiredCards, C.Card {children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center", width = "100%",
                    children = {
                        UI.Panel {flexDirection = "row", alignItems = "center", gap = 6, children = {
                            UI.Label {text = roleDef.icon, fontSize = T.FontSubtitle},
                            UI.Label {text = roleDef.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        }},
                        C.Badge {text = "在职 " .. tenure .. "月", variant = "success"},
                    }
                },
                UI.Label {text = roleDef.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary, marginTop = 2},
                UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                C.InfoRow {label = "月薪", value = C.FormatMoney(monthlySalary), color = T.Warning},
                C.InfoRow {label = "年薪", value = C.FormatMoney(annualCost)},
                C.InfoRow {label = "累计支出", value = C.FormatMoney(exec.totalPaid or 0)},
                C.InfoRow {label = "入职时间", value = string.format("Y%d.M%d", exec.hiredYear or 1, exec.hiredMon or 1)},
                C.InfoRow {label = "效果加成", value = string.format("+%.0f%% %s", roleDef.effectValue * 100, effectLabel), color = T.Success},
                UI.Panel {flexDirection = "row", gap = 8, width = "100%", marginTop = 6, flexWrap = "wrap", children = {
                    roleDef.action and C.ActionButton {
                        text = roleDef.actionName or "执行职责",
                        bgColor = T.Accent,
                        fontColor = T.TextOnDark,
                        onClick = function()
                            local ok, msg = GV.ExecuteAction(GD, captureRoleId)
                            if ok then
                                GD.AddEvent(msg, "success")
                            else
                                GD.AddEvent(msg or "操作失败", "warning")
                            end
                            navigate("governance")
                        end,
                    } or nil,
                    C.ActionButton {
                        text = "解雇（补偿" .. C.FormatMoney(captureSeverance) .. "）",
                        bgColor = T.Danger,
                        fontColor = T.TextOnDark,
                        onClick = function()
                            local ok, msg = GV.FireExecutive(GD, captureRoleId)
                            if ok then
                                GD.AddEvent(msg, "warning")
                            else
                                GD.AddEvent(msg or "解雇失败", "danger")
                            end
                            navigate("governance")
                        end,
                    },
                }},
                roleDef.actionDesc and UI.Label {
                    text = "💡 " .. roleDef.actionDesc,
                    fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 2,
                } or nil,
            }})
        end
    end

    if #hiredCards > 0 then
        table.insert(children, C.SectionTitle {text = "在职高管", color = T.Success})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = hiredCards})
    end

    -- 空缺职位
    local vacantCards = {}
    for _, roleDef in ipairs(GV.EXECUTIVE_ROLES) do
        if not gov.executives[roleDef.id] then
            local canAfford = GD.company.cash >= roleDef.bonus
            local captureRoleId = roleDef.id
            local firstYearCost = roleDef.bonus + roleDef.salary  -- salary已是年薪

            table.insert(vacantCards, C.Card {children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center", width = "100%",
                    children = {
                        UI.Panel {flexDirection = "row", alignItems = "center", gap = 6, children = {
                            UI.Label {text = roleDef.icon, fontSize = T.FontSubtitle},
                            UI.Label {text = roleDef.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        }},
                        C.Badge {text = "空缺", variant = "warning"},
                    }
                },
                UI.Label {text = roleDef.desc, fontSize = T.FontSmall, fontColor = T.TextSecondary, marginTop = 2},
                UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
                C.InfoRow {label = "年薪", value = C.FormatMoney(roleDef.salary), color = T.Warning},
                C.InfoRow {label = "月薪", value = C.FormatMoney(math.floor(roleDef.salary / 12 * 100) / 100)},
                C.InfoRow {label = "签约奖金", value = C.FormatMoney(roleDef.bonus), color = T.Accent},
                C.InfoRow {label = "首年总成本", value = C.FormatMoney(firstYearCost)},
                C.InfoRow {label = "效果加成", value = "+" .. math.floor(roleDef.effectValue * 100) .. "%", color = T.Success},
                roleDef.actionDesc and UI.Label {
                    text = "📋 职责: " .. roleDef.actionName .. " — " .. roleDef.actionDesc,
                    fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 2,
                } or nil,
                C.ActionButton {
                    text = canAfford and ("聘用（" .. C.FormatMoney(roleDef.bonus) .. "）") or ("资金不足（需" .. C.FormatMoney(roleDef.bonus) .. "）"),
                    bgColor = canAfford and T.Success or T.DisabledBg,
                    fontColor = canAfford and T.TextDark or T.TextMuted,
                    onClick = function()
                        local ok, msg = GV.HireExecutive(GD, captureRoleId)
                        if ok then
                            GD.AddEvent(msg, "success")
                        else
                            GD.AddEvent(msg or "聘用失败", "danger")
                        end
                        navigate("governance")
                    end,
                },
            }})
        end
    end

    if #vacantCards > 0 then
        table.insert(children, C.SectionTitle {text = "空缺职位", color = T.Warning})
        table.insert(children, UI.Panel {width = "100%", gap = 8, children = vacantCards})
    end

    -- 高管薪酬一览表
    local salaryTableRows = {}
    for _, roleDef in ipairs(GV.EXECUTIVE_ROLES) do
        local exec = gov.executives[roleDef.id]
        local statusText = exec and "在职" or "空缺"
        local statusColor = exec and T.Success or T.TextMuted
        local currentSalary = exec and C.FormatMoney(exec.salary) or "-"
        local paid = exec and C.FormatMoney(exec.totalPaid or 0) or "-"

        table.insert(salaryTableRows, UI.Panel {
            flexDirection = "row", alignItems = "center", width = "100%",
            paddingVertical = 6, paddingHorizontal = 8,
            backgroundColor = (#salaryTableRows % 2 == 0) and T.BgCard or {0, 0, 0, 0},
            borderRadius = 4,
            children = {
                UI.Panel {width = 30, children = {
                    UI.Label {text = roleDef.icon, fontSize = T.FontSmall},
                }},
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, children = {
                    UI.Label {text = roleDef.name, fontSize = T.FontSmall, fontColor = T.TextPrimary},
                }},
                UI.Panel {width = 50, alignItems = "center", children = {
                    UI.Label {text = statusText, fontSize = T.FontCaption, fontColor = statusColor},
                }},
                UI.Panel {width = 70, alignItems = "flex-end", children = {
                    UI.Label {text = currentSalary, fontSize = T.FontCaption, fontColor = T.Warning},
                }},
                UI.Panel {width = 80, alignItems = "flex-end", children = {
                    UI.Label {text = paid, fontSize = T.FontCaption, fontColor = T.TextSecondary},
                }},
            }
        })
    end

    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "高管薪酬一览"},
        -- 表头
        UI.Panel {
            flexDirection = "row", alignItems = "center", width = "100%",
            paddingVertical = 4, paddingHorizontal = 8,
            children = {
                UI.Panel {width = 30, children = {
                    UI.Label {text = "", fontSize = T.FontCaption},
                }},
                UI.Panel {flexGrow = 1, flexBasis = 0, flexShrink = 1, children = {
                    UI.Label {text = "职位", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Panel {width = 50, alignItems = "center", children = {
                    UI.Label {text = "状态", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Panel {width = 70, alignItems = "flex-end", children = {
                    UI.Label {text = "月薪", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
                UI.Panel {width = 80, alignItems = "flex-end", children = {
                    UI.Label {text = "累计支出", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }},
            }
        },
        UI.Panel {width = "100%", height = 1, backgroundColor = T.Border},
        UI.Panel {width = "100%", gap = 0, children = salaryTableRows},
        -- 汇总行
        UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginTop = 4},
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            paddingVertical = 6, paddingHorizontal = 8,
            children = {
                UI.Label {text = "合计", fontSize = T.FontSmall, fontColor = T.Accent},
                UI.Label {text = "月薪 " .. C.FormatMoney(monthlyCost) .. " / 累计 " .. C.FormatMoney(totalPaidAll), fontSize = T.FontSmall, fontColor = T.Accent},
            }
        },
    }})

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

-- ============================================================================
-- Tab7: 股权操作
-- ============================================================================
function M._TabEquityOps(navigate, gov)
    local co = GD.company
    local children = {}
    local marketValuation = GV.GetMarketValuation(GD)
    local pricePerShare = GV.GetBuybackPricePerShare(GD)

    -- 检查是否有非创始人股东
    local hasOthers = false
    local nonFounderShares = 0
    local nonFounderRatio = 0
    for _, sh in ipairs(gov.shareholders) do
        if sh.id ~= "founder" then
            hasOthers = true
            nonFounderShares = nonFounderShares + sh.shares
            nonFounderRatio = nonFounderRatio + sh.ratio
        end
    end

    -- 创始人股份
    local founderShares = gov.founderShares or 0
    for _, sh in ipairs(gov.shareholders) do
        if sh.id == "founder" then founderShares = sh.shares; break end
    end

    -- 概览指标（四行显示）
    table.insert(children, C.Card {children = {
        C.InfoRow {label = "总股本", value = gov.totalShares .. "股", color = T.TextPrimary},
        C.InfoRow {label = "创始人持股", value = string.format("%.1f%%", gov.founderRatio * 100), color = T.Accent},
        C.InfoRow {label = "ESOP池", value = (gov.esopPool or 0) .. "股", color = T.Info},
        C.InfoRow {label = "市场市值", value = C.FormatMoney(marketValuation), color = T.Success},
        C.InfoRow {label = "回购价溢价", value = string.format("%.0f%%", GV.BUYBACK_PREMIUM_RATE * 100), color = T.Warning},
    }})

    -- 操作前置信息
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "股权操作概况"},
        C.InfoRow {label = "每股估价", value = C.FormatMoney(math.floor(pricePerShare)) .. "/股"},
        C.InfoRow {label = "可用资金", value = C.FormatMoney(co.cash), color = co.cash > 0 and T.Success or T.Danger},
        C.InfoRow {label = "非创始人持股", value = hasOthers and string.format("%d股（%.1f%%）", nonFounderShares, nonFounderRatio * 100) or "无", color = hasOthers and T.Warning or T.TextMuted},
        C.InfoRow {label = "回购授权", value = gov.buybackAuthorized and "已授权" or "未授权", color = gov.buybackAuthorized and T.Success or T.TextMuted},
        C.InfoRow {label = "创始人股份", value = founderShares .. "股"},
    }})

    -- === 股份回购 ===
    local buybackPresets = {0.02, 0.05, 0.08, 0.10}
    local buybackBtns = {}
    for _, pct in ipairs(buybackPresets) do
        local quote = GV.GetBuybackQuote(GD, pct)
        local shares = quote and quote.shares or 0
        local cost = quote and quote.cost or 0
        local canDo = co.cash >= cost and shares > 0 and hasOthers
        local capturePct = pct

        -- 回购后预估创始人比例
        local newTotal = gov.totalShares - math.min(shares, nonFounderShares)
        local estRatio = newTotal > 0 and (founderShares / newTotal * 100) or 100

        table.insert(buybackBtns, C.Card {children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = string.format("回购 %d%%", math.floor(pct * 100)), fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = canDo and "可执行" or "不可用", variant = canDo and "success" or "warning"},
                }
            },
            C.InfoRow {label = "回购股数", value = shares .. "股"},
            C.InfoRow {label = "预计花费", value = C.FormatMoney(cost), color = T.Warning},
            C.InfoRow {label = "回购后持股", value = string.format("→ %.1f%%", estRatio), color = T.Accent},
            C.ActionButton {
                text = "执行回购（" .. C.FormatMoney(cost) .. "）",
                bgColor = canDo and T.PrimaryLight or T.DisabledBg,
                fontColor = canDo and T.Primary or T.TextMuted,
                onClick = function()
                    local ok, msg = GV.ExecuteBuyback(GD, capturePct)
                    if ok then
                        GD.AddEvent(msg, "success")
                    else
                        GD.AddEvent(msg or "回购失败", "danger")
                    end
                    navigate("governance")
                end,
            },
        }})
    end

    -- 自定义回购金额
    local buybackCardChildren = {
        C.SectionTitle {text = "股份回购", color = T.Accent},
        UI.Label {
            text = "按市场市值并溢价10%从非创始人股东回购股份并注销，提升创始人持股比例",
            fontSize = T.FontSmall, fontColor = T.TextSecondary,
        },
    }
    if not hasOthers then
        table.insert(buybackCardChildren, UI.Label {
            text = "当前仅创始人持股，无可回购对象",
            fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6,
        })
    else
        table.insert(buybackCardChildren, UI.Panel {
            width = "100%", gap = 8, marginTop = 6,
            children = buybackBtns,
        })
        -- 自定义金额
        table.insert(buybackCardChildren, UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4})
        table.insert(buybackCardChildren, UI.Label {text = "自定义回购金额（万元）", fontSize = T.FontSmall, fontColor = T.TextSecondary})
        table.insert(buybackCardChildren, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", alignItems = "center",
            children = {
                UI.TextField {
                    placeholder = "输入金额",
                    fontSize = T.FontBody,
                    width = 140, height = 34,
                    backgroundColor = T.BgInput,
                    fontColor = T.TextPrimary,
                    borderRadius = 6,
                    paddingHorizontal = 10,
                    onChange = function(self, text)
                        M._customInputs["buybackAmt"] = tonumber(text)
                    end,
                },
                C.ActionButton {
                    text = "执行回购",
                    onClick = function()
                        local amt = M._customInputs["buybackAmt"]
                        if not amt or amt <= 0 then
                            GD.AddEvent("请输入有效金额", "danger")
                            navigate("governance")
                            return
                        end
                        local ok, msg = GV.BuybackByAmount(GD, amt)
                        if ok then
                            GD.AddEvent(msg, "success")
                        else
                            GD.AddEvent(msg or "回购失败", "danger")
                        end
                        navigate("governance")
                    end,
                },
            }
        })
    end
    table.insert(children, C.Card {children = buybackCardChildren})

    -- === ESOP期权池 ===
    local esopPresets = {0.02, 0.05, 0.08, 0.10}
    local esopBtns = {}
    for _, pct in ipairs(esopPresets) do
        local shares = math.floor(gov.totalShares * pct)
        local canDo = founderShares >= shares
        local capturePct = pct
        local newFounderRatio = gov.totalShares > 0 and ((founderShares - shares) / gov.totalShares * 100) or 0

        table.insert(esopBtns, C.ActionButton {
            text = string.format("划出%d%%（%d股→持股%.1f%%）", math.floor(pct * 100), shares, newFounderRatio),
            bgColor = canDo and T.Info or T.DisabledBg,
            fontColor = canDo and T.TextDark or T.TextMuted,
            onClick = function()
                local ok, msg = GV.CreateESOP(GD, capturePct)
                if ok then
                    GD.AddEvent(msg, "success")
                else
                    GD.AddEvent(msg or "设立失败", "danger")
                end
                navigate("governance")
            end,
        })
    end

    local esopRatio = gov.totalShares > 0 and ((gov.esopPool or 0) / gov.totalShares * 100) or 0
    table.insert(children, C.Card {children = {
        C.SectionTitle {text = "ESOP期权池", color = T.Info},
        UI.Label {
            text = "从创始人份额中划出股份用于员工激励",
            fontSize = T.FontSmall, fontColor = T.TextSecondary,
        },
        UI.Panel {width = "100%", height = 1, backgroundColor = T.Border, marginVertical = 4},
        C.InfoRow {label = "当前池", value = (gov.esopPool or 0) .. "股", color = T.Info},
        C.InfoRow {label = "占总股本", value = string.format("%.1f%%", esopRatio)},
        C.InfoRow {label = "创始人可划出", value = founderShares .. "股"},
        UI.Panel {
            width = "100%", gap = 6, marginTop = 6,
            children = esopBtns,
        },
    }})

    -- === 股份收购（从其他股东） ===
    local transferCards = {}
    for idx, sh in ipairs(gov.shareholders) do
        if sh.id ~= "founder" and sh.shares > 0 then
            local acqPresets = {0.25, 0.50, 1.0}
            local acqBtns = {}
            for _, ratio in ipairs(acqPresets) do
                local shareCount = math.floor(sh.shares * ratio)
                if shareCount < 1 then shareCount = 1 end
                local cost = math.floor(shareCount * pricePerShare * 0.5)
                local canAfford = co.cash >= cost
                local captureIdx = idx
                local captureCount = shareCount

                -- 收购后持股比例预估
                local newFounderShares = founderShares + shareCount
                local estRatio = gov.totalShares > 0 and (newFounderShares / gov.totalShares * 100) or 100

                table.insert(acqBtns, C.ActionButton {
                    text = string.format("%d%%（%s→%.1f%%）", math.floor(ratio * 100), C.FormatMoney(cost), estRatio),
                    bgColor = canAfford and T.Success or T.DisabledBg,
                    fontColor = canAfford and T.TextDark or T.TextMuted,
                    onClick = function()
                        local ok, msg = GV.TransferShares(GD, captureIdx, 0, captureCount)
                        if ok then
                            GD.AddEvent(msg, "success")
                        else
                            GD.AddEvent(msg or "收购失败", "danger")
                        end
                        navigate("governance")
                    end,
                })
            end

            table.insert(transferCards, C.Card {children = {
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center", width = "100%",
                    children = {
                        UI.Label {text = sh.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                        C.Badge {text = string.format("%.1f%%", sh.ratio * 100), variant = "info"},
                    }
                },
                C.InfoRow {label = "持股数", value = sh.shares .. "股"},
                C.InfoRow {label = "收购单价", value = C.FormatMoney(math.floor(pricePerShare * 0.5)) .. "/股（50%折价）"},
                UI.Label {text = "收购比例", fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 4},
                UI.Panel {
                    flexDirection = "row", gap = 6, width = "100%", marginTop = 4, flexWrap = "wrap",
                    children = acqBtns,
                },
            }})
        end
    end

    if #transferCards > 0 then
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "收购股东股份", color = T.Success},
            UI.Label {
                text = "以折价（估值50%）从其他股东收购股份，收购后股份转入创始人名下",
                fontSize = T.FontSmall, fontColor = T.TextSecondary,
            },
        }})
        for _, tc in ipairs(transferCards) do
            table.insert(children, tc)
        end
    else
        table.insert(children, C.Card {children = {
            C.SectionTitle {text = "收购股东股份", color = T.TextMuted},
            UI.Label {
                text = "当前仅创始人持股，无可收购对象",
                fontSize = T.FontSmall, fontColor = T.TextMuted,
            },
        }})
    end

    return UI.Panel {
        width = "100%", gap = 12,
        children = children,
    }
end

return M
