---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- BrandScreen.lua - 品牌声誉管理 (3-Tab)
-- Tab1: 品牌价值  Tab2: 社交舆情  Tab3: 社会责任
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local BR = GD.Brand  -- Brand 模块引用

local M = {}
M._activeTab = 1

function M.Create(navigate)
    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 14,
        children = {
            C.SectionTitle {text = "品牌声誉"},

            C.TabBar {
                tabs = {"品牌价值", "社交舆情", "社会责任"},
                active = M._activeTab,
                onChange = function(idx)
                    M._activeTab = idx
                    navigate("brand")
                end,
            },

            M._activeTab == 1 and M._TabBrandValue(navigate) or
            M._activeTab == 2 and M._TabSocialMedia(navigate) or
            M._TabCSR(navigate),

            UI.Panel {height = 20},
        }
    }
end

-- ============================================================================
-- Tab1: 品牌价值总览
-- ============================================================================
function M._TabBrandValue(navigate)
    local brand = GD.brand or {}
    local dims = brand.dimensions or {}
    local score = brand.score or 50

    -- 品牌等级文本
    local tierText, tierVariant
    if score >= 80 then
        tierText = "卓越品牌"
        tierVariant = "success"
    elseif score >= 60 then
        tierText = "知名品牌"
        tierVariant = "accent"
    elseif score >= 40 then
        tierText = "普通品牌"
        tierVariant = "warning"
    else
        tierText = "低端品牌"
        tierVariant = "danger"
    end

    -- 四维度卡片
    local dimCards = {}
    local dimColors = {
        productQuality  = T.Accent,
        deliverySatisfy = T.Success,
        socialResp      = T.Info,
        mediaSentiment  = T.Warning,
    }
    for _, dim in ipairs(BR.DIMENSIONS) do
        local val = dims[dim.id] or 0
        table.insert(dimCards, C.StatCard {
            title = dim.name,
            value = tostring(math.floor(val)),
            subtitle = "权重 " .. math.floor(dim.weight * 100) .. "%",
            color = dimColors[dim.id] or T.TextPrimary,
            minWidth = 100,
        })
    end

    -- 危机信息
    local crisisWidget = nil
    if brand.activeCrisis then
        local crisis = brand.activeCrisis
        crisisWidget = C.Card {
            children = {
                C.SectionTitle {text = "当前危机", color = T.Danger},
                C.InfoRow {label = "类型", value = crisis.name, color = T.Danger},
                C.InfoRow {label = "品牌损失", value = "-" .. crisis.originalLoss, color = T.Danger},
                C.InfoRow {label = "剩余影响", value = crisis.monthsLeft .. "个月"},
                C.ProgressCard {
                    title = "危机消退进度",
                    progress = math.max(0, (1 - crisis.monthsLeft / (crisis.totalDuration or 6)) * 100),
                    barColor = T.Danger,
                },
            }
        }
    end

    local children = {
        -- 总分区
        C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Panel {
                            gap = 4,
                            children = {
                                UI.Label {text = "品牌综合评分", fontSize = T.FontBody, fontColor = T.TextSecondary},
                                UI.Label {text = tostring(score), fontSize = 36, fontColor = T.Accent},
                            }
                        },
                        C.Badge {text = tierText, variant = tierVariant},
                    }
                },
            }
        },
        -- 品牌效果
        C.Card {
            children = {
                C.SectionTitle {text = "品牌效果"},
                C.InfoRow {
                    label = "产品溢价率",
                    value = string.format("%.1f%%", (brand.premiumRate or 0) * 100),
                    color = T.Success,
                },
                C.InfoRow {
                    label = "拿地评分加成",
                    value = "+" .. (brand.landBidBonus or 0) .. "分",
                    color = T.Info,
                },
                C.InfoRow {
                    label = "政府好感度",
                    value = tostring(brand.govFavor or 0),
                    color = T.Warning,
                },
            }
        },
        -- 四维度
        C.Card {
            children = {
                C.SectionTitle {text = "品牌四维度"},
                UI.Panel {
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 8,
                    width = "100%",
                    children = dimCards,
                },
            }
        },
    }
    if crisisWidget then
        table.insert(children, crisisWidget)
    end
    return UI.Panel {width = "100%", gap = 12, children = children}
end

-- ============================================================================
-- Tab2: 社交舆情
-- ============================================================================
function M._TabSocialMedia(navigate)
    local brand = GD.brand or {}

    -- 平台名映射
    local platNames = {}
    for _, p in ipairs(BR.PLATFORMS) do
        platNames[p.id] = p.name
    end

    -- 最近20条帖子
    local postWidgets = {}
    local startIdx = math.max(1, #(brand.posts or {}) - 19)
    for i = #(brand.posts or {}), startIdx, -1 do
        local post = brand.posts[i]
        local sentColor = post.sentiment == "positive" and T.Success or T.Danger
        local sentIcon = post.sentiment == "positive" and "👍" or "👎"
        local viralTag = post.isViral and " 🔥热门" or ""
        table.insert(postWidgets, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = T.BgCard,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = post.isViral and T.Warning or T.Border,
            gap = 4,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = (platNames[post.platform] or "未知") .. viralTag,
                            fontSize = T.FontCaption,
                            fontColor = T.TextMuted,
                        },
                        UI.Label {
                            text = sentIcon .. " " .. post.likes,
                            fontSize = T.FontCaption,
                            fontColor = sentColor,
                        },
                    }
                },
                UI.Label {
                    text = post.text or "",
                    fontSize = T.FontSmall,
                    fontColor = T.TextPrimary,
                    maxLines = 3,
                },
            }
        })
    end
    if #postWidgets == 0 then
        table.insert(postWidgets, UI.Label {
            text = "暂无社交媒体动态",
            fontSize = T.FontBody,
            fontColor = T.TextMuted,
        })
    end

    -- 公关操作按钮
    local prWidgets = {}
    local hasCrisis = brand.activeCrisis ~= nil
    local onCooldown = (brand.prCooldown or 0) > 0
    for _, pr in ipairs(BR.PR_ACTIONS) do
        local disabled = not hasCrisis or onCooldown or GD.company.cash < pr.cost
        local statusText = ""
        if not hasCrisis then
            statusText = "（无危机）"
        elseif onCooldown then
            statusText = "（冷却" .. brand.prCooldown .. "月）"
        elseif GD.company.cash < pr.cost then
            statusText = "（资金不足）"
        end
        table.insert(prWidgets, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Panel {
                            gap = 2,
                            flexShrink = 1,
                            children = {
                                UI.Label {text = pr.name, fontSize = T.FontBody, fontColor = T.TextPrimary},
                                UI.Label {text = pr.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                                UI.Label {
                                    text = "费用: " .. pr.cost .. "万 | 恢复: " .. math.floor(pr.recoveryRate * 100) .. "% | 冷却: " .. pr.cooldown .. "月",
                                    fontSize = T.FontCaption,
                                    fontColor = T.TextSecondary,
                                },
                            }
                        },
                        C.ActionButton {
                            text = "执行" .. statusText,
                            disabled = disabled,
                            onClick = function()
                                local ok, err = BR.DoPR(GD, pr.id)
                                if not ok then
                                    GD.AddEvent("公关失败: " .. (err or ""), "warning")
                                end
                                navigate("brand")
                            end,
                        },
                    }
                },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- 舆情概览
            C.Card {
                children = {
                    C.SectionTitle {text = "舆情概览"},
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        width = "100%",
                        children = {
                            C.StatCard {
                                title = "媒体舆情分",
                                value = tostring(brand.dimensions and brand.dimensions.mediaSentiment or 50),
                                color = T.Info,
                            },
                            C.StatCard {
                                title = "帖子总数",
                                value = tostring(#(brand.posts or {})),
                            },
                            C.StatCard {
                                title = "热点新闻",
                                value = tostring(#(brand.hotNews or {})),
                                color = T.Warning,
                            },
                        }
                    },
                }
            },
            -- 帖子列表
            C.Card {
                children = {
                    C.SectionTitle {text = "社交动态（最近20条）"},
                    UI.Panel {width = "100%", gap = 6, children = postWidgets},
                }
            },
            -- 公关应对
            C.Card {
                children = {
                    C.SectionTitle {text = "公关应对", color = hasCrisis and T.Danger or T.TextMuted},
                    UI.Panel {width = "100%", gap = 8, children = prWidgets},
                }
            },
        }
    }
end

-- ============================================================================
-- Tab3: 社会责任
-- ============================================================================
function M._TabCSR(navigate)
    local brand = GD.brand or {}

    -- 公益活动卡片
    local csrCards = {}
    for _, csr in ipairs(BR.CSR_EVENTS) do
        local canAfford = GD.company.cash >= csr.cost
        table.insert(csrCards, C.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Panel {
                            gap = 2,
                            flexShrink = 1,
                            children = {
                                UI.Label {text = csr.name, fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                                UI.Label {text = csr.desc, fontSize = T.FontCaption, fontColor = T.TextMuted},
                                UI.Label {
                                    text = "费用: " .. csr.cost .. "万 | 品牌+" .. csr.brandBoost .. " | 政府好感+" .. csr.govBoost,
                                    fontSize = T.FontCaption,
                                    fontColor = T.Info,
                                },
                            }
                        },
                        C.ActionButton {
                            text = canAfford and "参与" or "资金不足",
                            disabled = not canAfford,
                            onClick = function()
                                local ok, err = BR.DoCSR(GD, csr.id)
                                if not ok then
                                    GD.AddEvent("公益失败: " .. (err or ""), "warning")
                                end
                                navigate("brand")
                            end,
                        },
                    }
                },
            }
        })
    end

    -- 公益历史
    local historyWidgets = {}
    local histStart = math.max(1, #(brand.csrHistory or {}) - 9)
    for i = #(brand.csrHistory or {}), histStart, -1 do
        local h = brand.csrHistory[i]
        table.insert(historyWidgets, C.InfoRow {
            label = h.name .. "（第" .. (h.year or "?") .. "年）",
            value = "-" .. h.cost .. "万",
            color = T.Success,
        })
    end
    if #historyWidgets == 0 then
        table.insert(historyWidgets, UI.Label {
            text = "暂无公益记录",
            fontSize = T.FontSmall,
            fontColor = T.TextMuted,
        })
    end

    return UI.Panel {
        width = "100%",
        gap = 12,
        children = {
            -- 概览
            C.Card {
                children = {
                    C.SectionTitle {text = "社会责任概览"},
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        width = "100%",
                        children = {
                            C.StatCard {
                                title = "社会责任分",
                                value = tostring(brand.dimensions and brand.dimensions.socialResp or 0),
                                color = T.Info,
                            },
                            C.StatCard {
                                title = "政府好感度",
                                value = tostring(brand.govFavor or 0),
                                color = T.Warning,
                            },
                            C.StatCard {
                                title = "累计公益",
                                value = tostring(#(brand.csrHistory or {})) .. "次",
                                color = T.Success,
                            },
                        }
                    },
                }
            },
            -- 公益活动
            C.Card {
                children = {
                    C.SectionTitle {text = "公益活动"},
                    UI.Panel {width = "100%", gap = 8, children = csrCards},
                }
            },
            -- 历史记录
            C.Card {
                children = {
                    C.SectionTitle {text = "公益历史（最近10条）"},
                    UI.Panel {width = "100%", gap = 4, children = historyWidgets},
                }
            },
        }
    }
end

return M
