---@diagnostic disable: param-type-mismatch, assign-type-mismatch, undefined-global
-- ============================================================================
-- SettingsScreen.lua - 系统设置: 全功能面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local ME = require("MacroEconomy")

local M = {}
M._redeemInput = ""
M._message = nil
M._activeTab = 1    -- 1=存档管理 2=游戏设置 3=福利中心 4=消息记录 5=排行榜 6=关于
M._leaderboardData = nil  -- 排行榜缓存
M._leaderboardLoading = false
M._myRank = nil
M._myRankLoading = false
M._cloudSlotInfos = nil
M._cloudSlotLoading = false
M._expandedLists = M._expandedLists or {}
M._companyNameInput = ""
M._companyNameCompanyId = nil

function M.Create(navigate)

    local tabNames = {"存档管理", "游戏设置", "福利中心", "消息记录", "排行榜", "关于"}

    -- 消息反馈
    local messageWidget = nil
    if M._message then
        local colors = {
            success = T.Success,
            danger = T.Danger,
            warning = T.Warning,
            info = T.Info,
        }
        messageWidget = UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = T.BgCard,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = colors[M._message.variant] or T.Border,
            children = {
                UI.Label {
                    text = M._message.text,
                    fontSize = T.FontBody,
                    fontColor = colors[M._message.variant] or T.TextPrimary,
                },
            }
        }
        M._message = nil
    end

    -- 构建当前tab内容
    local tabContent
    if M._activeTab == 1 then
        tabContent = buildSaveLoad(navigate)
    elseif M._activeTab == 2 then
        tabContent = buildGameSettings(navigate)
    elseif M._activeTab == 3 then
        tabContent = buildWelfare(navigate)
    elseif M._activeTab == 4 then
        tabContent = buildEventLog(navigate)
    elseif M._activeTab == 5 then
        tabContent = buildLeaderboard(navigate)
    elseif M._activeTab == 6 then
        tabContent = buildAbout(navigate)
    end

    -- 组装最终UI
    local topChildren = {
        UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Panel {
                            width = 4,
                            height = 18,
                            backgroundColor = T.Accent,
                            borderRadius = 2,
                        },
                        UI.Label {
                            text = "系统设置",
                            fontSize = T.FontSubtitle,
                            fontColor = T.TextPrimary,
                        },
                    },
                },
                C.SecondaryButton {
                    text = "返回游戏",
                    onClick = function()
                        navigate(GetPreviousScreen())
                    end,
                },
            }
        },
    }
    if messageWidget then
        table.insert(topChildren, messageWidget)
    end
    table.insert(topChildren, C.TabBar {
        tabs = tabNames,
        active = M._activeTab,
        onChange = function(idx)
            M._activeTab = idx
            navigate("settings")
        end,
    })
    table.insert(topChildren, tabContent)
    table.insert(topChildren, UI.Panel {height = 20})

    return UI.ScrollView {
        id = "screenScrollView",
        width = "100%",
        height = "100%",
        scrollY = true,
        padding = T.PagePadding,
        gap = 14,
        children = topChildren,
    }
end

-- ============================================================================
-- Tab 1: 存档管理
-- ============================================================================
function buildSaveLoad(navigate)
    local slotCards = {}

    -- 自动存档区域
    local autoInfo = GD.GetAutoSaveInfo()
    if autoInfo then
        local autoChildren = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = "自动存档", fontSize = T.FontSubtitle, fontColor = T.Info},
                    C.Badge {text = "每季度", variant = "info"},
                }
            },
            UI.Panel {
                width = "100%", gap = 2,
                children = {
                    C.InfoRow {label = "公司", value = autoInfo.name},
                    C.InfoRow {label = "日期", value = autoInfo.date},
                    C.InfoRow {label = "现金", value = C.FormatMoney(autoInfo.cash), color = T.Success},
                    C.InfoRow {label = "保存于", value = autoInfo.savedAt},
                }
            },
            UI.Panel {
                flexDirection = "row", gap = 8, width = "100%", marginTop = 4,
                children = {
                    UI.Button {
                        text = "读取自动存档",
                        fontSize = T.FontBody,
                        backgroundColor = T.PrimaryLight,
                        fontColor = T.Primary,
                        borderRadius = T.ButtonRadius,
                        width = "100%",
                        height = 36,
                        onClick = function()
                            local ok, err = GD.LoadAutoSave()
                            if ok then
                                M._message = {text = "自动存档读取成功！", variant = "success"}
                                navigate("dashboard")
                            else
                                M._message = {text = "读取失败: " .. (err or ""), variant = "danger"}
                                navigate("settings")
                            end
                        end,
                    },
                },
            },
        }
        table.insert(slotCards, C.Card {children = autoChildren})
    end

    -- 手动存档位
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
        local info = GD.GetSlotInfo(i)
        local hasData = (info ~= nil)

        local slotChildren = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = "存档位 " .. i, fontSize = T.FontSubtitle, fontColor = T.Accent},
                    hasData and C.Badge {text = "有数据", variant = "success"} or C.Badge {text = "空", variant = "info"},
                }
            },
        }

        if hasData then
            local infoRows = {
                C.InfoRow {label = "公司", value = info.name},
                C.InfoRow {label = "日期", value = info.date},
                C.InfoRow {label = "现金", value = C.FormatMoney(info.cash), color = T.Success},
            }
            if info.savedAt and info.savedAt ~= "" then
                table.insert(infoRows, C.InfoRow {label = "保存于", value = info.savedAt})
            end
            table.insert(slotChildren, UI.Panel {
                width = "100%", gap = 2,
                children = infoRows,
            })
        else
            table.insert(slotChildren, UI.Label {
                text = "暂无存档数据",
                fontSize = T.FontSmall, fontColor = T.TextMuted, marginVertical = 4,
            })
        end

        -- 操作按钮
        local btns = {}
        if GD.gameStarted then
            table.insert(btns, C.ActionButton {
                text = "保存",
                width = "48%",
                onClick = function()
                    GD.SaveToSlot(i)
                    M._message = {text = "已保存到存档位" .. i, variant = "success"}
                    navigate("settings")
                end,
            })
        end
        if hasData then
            table.insert(btns, UI.Button {
                text = "读取",
                fontSize = T.FontBody,
                backgroundColor = T.PrimaryLight,
                fontColor = T.Primary,
                borderRadius = T.ButtonRadius,
                width = "48%",
                height = 36,
                onClick = function()
                    local ok, err = GD.LoadFromSlot(i)
                    if ok then
                        M._message = {text = "读档成功！", variant = "success"}
                        navigate("dashboard")
                    else
                        M._message = {text = "读档失败: " .. (err or ""), variant = "danger"}
                        navigate("settings")
                    end
                end,
            })
        end
        table.insert(slotChildren, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", marginTop = 4,
            children = btns,
        })

        table.insert(slotCards, C.Card {children = slotChildren})
    end

    -- 云存档区域
    local cloudCards = {}
    local cloudAvailable = clientCloud ~= nil
    if cloudAvailable then
        if not M._cloudSlotLoading and not M._cloudSlotInfos then
            M._cloudSlotLoading = true
            GD.GetCloudSlotInfos(function(infos, err)
                M._cloudSlotLoading = false
                M._cloudSlotInfos = infos or {}
                if err then
                    M._message = {text = "云存档读取失败: " .. err, variant = "danger"}
                end
                navigate("settings")
            end)
        end

        local cloudHeader = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {text = "云存档", fontSize = T.FontSubtitle, fontColor = T.Info},
                    C.Badge {text = M._cloudSlotLoading and "同步中" or "已连接", variant = M._cloudSlotLoading and "warning" or "success"},
                },
            },
            UI.Label {
                text = "云存档与本地存档独立保存，可在登录同一账号的设备间恢复。",
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                maxLines = 2,
            },
        }
        local refreshButton = C.SecondaryButton {
            text = "刷新云存档",
            width = "48%",
            onClick = function()
                M._cloudSlotInfos = nil
                navigate("settings")
            end,
        }
        table.insert(cloudHeader, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", marginTop = 4,
            children = {refreshButton},
        })
        table.insert(cloudCards, C.Card {children = cloudHeader})

        for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
            local info = M._cloudSlotInfos and M._cloudSlotInfos[i]
            local children = {
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {text = "云存档位 " .. i, fontSize = T.FontSubtitle, fontColor = T.Accent},
                        C.Badge {text = info and "有数据" or "空", variant = info and "success" or "info"},
                    },
                },
            }
            if info then
                table.insert(children, UI.Panel {
                    width = "100%", gap = 2,
                    children = {
                        C.InfoRow {label = "公司", value = info.name},
                        C.InfoRow {label = "日期", value = info.date},
                        C.InfoRow {label = "现金", value = C.FormatMoney(info.cash), color = T.Success},
                        C.InfoRow {label = "保存于", value = info.savedAt},
                    },
                })
            else
                table.insert(children, UI.Label {text = "暂无云存档数据", fontSize = T.FontSmall, fontColor = T.TextMuted, marginVertical = 4})
            end
            local buttons = {}
            if GD.gameStarted then
                table.insert(buttons, C.ActionButton {
                    text = "上传",
                    width = "48%",
                    onClick = function()
                        GD.SaveToCloudSlot(i, function(ok, err)
                            M._message = ok and {text = "云存档上传成功！", variant = "success"} or {text = err or "云存档上传失败", variant = "danger"}
                            M._cloudSlotInfos = nil
                            navigate("settings")
                        end)
                    end,
                })
            end
            if info then
                table.insert(buttons, C.SecondaryButton {
                    text = "下载并读取",
                    width = "48%",
                    onClick = function()
                        GD.LoadFromCloudSlot(i, function(ok, err)
                            M._message = ok and {text = "云存档读取成功！", variant = "success"} or {text = err or "云存档读取失败", variant = "danger"}
                            navigate(ok and "dashboard" or "settings")
                        end)
                    end,
                })
            end
            table.insert(children, UI.Panel {flexDirection = "row", gap = 8, width = "100%", marginTop = 4, children = buttons})
            table.insert(cloudCards, C.Card {children = children})
        end
    else
        table.insert(cloudCards, C.Card {
            children = {
                UI.Label {text = "云存档功能需要联网并登录账号。", fontSize = T.FontBody, fontColor = T.TextMuted},
            },
        })
    end
    table.insert(slotCards, UI.Panel {width = "100%", gap = 10, children = cloudCards})

    -- 底部提示
    table.insert(slotCards, UI.Panel {
        width = "100%",
        padding = 10,
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label {
                text = "自动存档每3个月保存一次",
                fontSize = T.FontCaption, fontColor = T.TextMuted,
            },
            UI.Label {
                text = "注意：刷新页面后本地存档将丢失",
                fontSize = T.FontCaption, fontColor = T.Warning,
            },
        }
    })

    return UI.Panel {width = "100%", gap = 10, children = slotCards}
end

-- ============================================================================
-- Tab 2: 游戏设置
-- ============================================================================
function buildGameSettings(navigate)
    local co = GD.company
    local activeCompanyId = GD.activeCompanyId or (GD.companyPortfolio and GD.companyPortfolio.activeId)
    if M._companyNameCompanyId ~= activeCompanyId then
        M._companyNameCompanyId = activeCompanyId
        M._companyNameInput = co.name or ""
    end
    local speedLabels = {"暂停", "正常(1x)", "快速(2x)", "极速(3x)"}
    local speedValues = {0, 1, 3, 6}

    -- 当前速度索引
    local curSpeedIdx = 1
    for i, v in ipairs(speedValues) do
        if GD.gameSpeed == v then curSpeedIdx = i; break end
    end

    -- 速度选择按钮
    local speedBtns = {}
    for i, label in ipairs(speedLabels) do
        local isActive = (i == curSpeedIdx)
        table.insert(speedBtns, UI.Button {
            text = label,
            fontSize = T.FontSmall,
            backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isActive and T.Primary or T.TabInactiveFont,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
            paddingHorizontal = 14,
            height = 34,
            flexGrow = 1,
            flexBasis = 0,
            onClick = function()
                GD.gameSpeed = speedValues[i]
                GD.paused = (speedValues[i] == 0)
                navigate("settings")
            end,
        })
    end

    -- 经济周期信息
    local cycleNames = {boom="繁荣期", recession="衰退期", depression="萧条期", recovery="复苏期"}
    local cycleColors = {boom=T.Success, recession=T.Warning, depression=T.Danger, recovery=T.Info}
    local cycleName = cycleNames[GD.economy.cycle] or "未知"
    local cycleColor = cycleColors[GD.economy.cycle] or T.TextMuted
    local cycleProgress = GD.economy.cycleDuration > 0 and math.floor(GD.economy.cycleMonth / GD.economy.cycleDuration * 100) or 0

    local children = {}

    -- 公司资料
    table.insert(children, C.SectionTitle {text = "公司资料", color = T.Accent})
    table.insert(children, C.Card {
        children = {
            C.InfoRow {label = "当前名称", value = co.name or "未创建", color = T.TextPrimary},
            UI.Label {
                text = "改名后会同步到公司组合、存档及所有使用公司名称的页面。",
                fontSize = T.FontSmall,
                fontColor = T.TextSecondary,
                maxLines = 2,
                whiteSpace = "normal",
            },
            UI.TextField {
                value = M._companyNameInput,
                placeholder = "请输入2至20个字的公司名称",
                maxLength = 20,
                width = "100%",
                height = 44,
                fontSize = T.FontBody,
                borderRadius = 6,
                paddingHorizontal = 12,
                borderWidth = 1,
                borderColor = T.Border,
                backgroundColor = T.BgInput,
                disabled = not GD.HasActiveOperatingCompany(),
                onChange = function(self, text)
                    M._companyNameInput = text
                end,
                onSubmit = function(self, text)
                    local ok, msg = GD.RenameActiveCompany(text)
                    M._message = {
                        text = msg or (ok and "公司名称已更新" or "公司改名失败"),
                        variant = ok and "success" or "warning",
                    }
                    if ok then M._companyNameInput = GD.company.name end
                    navigate("settings")
                end,
            },
            C.ActionButton {
                text = "确认改名",
                width = "100%",
                height = 40,
                disabled = not GD.HasActiveOperatingCompany(),
                onClick = function()
                    local ok, msg = GD.RenameActiveCompany(M._companyNameInput)
                    M._message = {
                        text = msg or (ok and "公司名称已更新" or "公司改名失败"),
                        variant = ok and "success" or "warning",
                    }
                    if ok then M._companyNameInput = GD.company.name end
                    navigate("settings")
                end,
            },
        }
    })

    -- 游戏速度
    table.insert(children, C.SectionTitle {text = "游戏速度"})
    table.insert(children, C.Card {
        children = {
            UI.Label {
                text = "控制游戏时间流逝速度，暂停后可仔细查看数据",
                fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4,
            },
            UI.Panel {
                flexDirection = "row", gap = 6, width = "100%", flexWrap = "wrap",
                children = speedBtns,
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 8,
                children = {
                    UI.Label {text = "1天 = " .. string.format("%.1f", GD.DAY_DURATION / math.max(1, GD.gameSpeed)) .. "秒(实际)", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = "已过 " .. GD.totalMonths .. " 个月", fontSize = T.FontCaption, fontColor = T.Info},
                }
            },
        }
    })

    -- 音量设置
    table.insert(children, C.SectionTitle {text = "音效设置"})
    table.insert(children, C.Card {
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                width = "100%", marginBottom = 6,
                children = {
                    UI.Label {text = "背景音乐", fontSize = T.FontSubtitle, fontColor = T.TextPrimary},
                    UI.Label {text = math.floor(GD.musicVolume * 100) .. "%", fontSize = T.FontBody, fontColor = T.Accent},
                }
            },
            UI.Slider {
                value = GD.musicVolume, min = 0, max = 1, step = 0.05,
                width = "100%",
                onChange = function(self, val)
                    SetMusicVolume(val)
                    navigate("settings")
                end,
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%", marginTop = 2,
                children = {
                    UI.Label {text = "静音", fontSize = T.FontCaption, fontColor = T.TextMuted},
                    UI.Label {text = "最大", fontSize = T.FontCaption, fontColor = T.TextMuted},
                }
            },
        }
    })

    -- 经济周期概览
    table.insert(children, C.SectionTitle {text = "当前经济环境"})
    local econCardChildren = {
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            children = {
                UI.Label {text = "经济周期", fontSize = T.FontBody, fontColor = T.TextSecondary},
                UI.Label {text = cycleName, fontSize = T.FontBody, fontColor = cycleColor},
            }
        },
        C.ProgressCard {
            title = "周期进度",
            progress = cycleProgress,
            status = GD.economy.cycleMonth .. "/" .. GD.economy.cycleDuration .. "月",
            barColor = cycleColor,
        },
        C.InfoRow {label = "房价指数", value = string.format("%.1f", GD.economy.priceIndex), color = GD.economy.priceIndex >= 100 and T.Success or T.Danger},
        C.InfoRow {label = "基准利率", value = string.format("%.2f%%", GD.economy.interestRate)},
        C.InfoRow {label = "需求倍数", value = string.format("%.2fx", GD.economy.demandMultiplier), color = GD.economy.demandMultiplier >= 1 and T.Success or T.Warning},
        C.InfoRow {label = "政策趋向", value = ({tighten="收紧", neutral="中性", loosen="宽松"})[GD.economy.policyTrend] or "中性"},
    }
    table.insert(children, C.Card {children = econCardChildren})

    -- 宏观经济指标（2.1）
    table.insert(children, C.SectionTitle {text = "宏观经济指标"})
    local macroCardChildren = {}
    local macroSummary = ME.GetMacroSummary(GD.macro)
    for _, item in ipairs(macroSummary) do
        table.insert(macroCardChildren, C.InfoRow {
            label = item.label, value = item.value, color = item.color or T.TextSecondary,
        })
    end
    if #macroCardChildren == 0 then
        table.insert(macroCardChildren, UI.Label {text = "暂无数据", fontSize = T.FontSmall, fontColor = T.TextMuted})
    end
    table.insert(children, C.Card {children = macroCardChildren})

    -- 房地产政策周期（2.2）
    table.insert(children, C.SectionTitle {text = "房地产政策"})
    local policyCardChildren = {}
    local policySummary = ME.GetPolicySummary(GD.policy)
    for _, item in ipairs(policySummary) do
        table.insert(policyCardChildren, C.InfoRow {
            label = item.label, value = item.value, color = item.color or T.TextSecondary,
        })
    end
    if #policyCardChildren == 0 then
        table.insert(policyCardChildren, UI.Label {text = "暂无数据", fontSize = T.FontSmall, fontColor = T.TextMuted})
    end
    table.insert(children, C.Card {children = policyCardChildren})

    -- 黑天鹅事件（2.3）
    if GD.activeBlackSwans and #GD.activeBlackSwans > 0 then
        table.insert(children, C.SectionTitle {text = "活跃黑天鹅事件"})
        local swanCardChildren = {}
        for _, swan in ipairs(GD.activeBlackSwans) do
            local catNames = {industry="行业", regional="区域", project="项目", other="其他"}
            local catColors = {industry=T.Danger, regional=T.Warning, project=T.Info, other=T.TextMuted}
            table.insert(swanCardChildren, UI.Panel {
                width = "100%", paddingVertical = 4, gap = 2,
                borderBottomWidth = 1, borderColor = T.Border,
                children = {
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", width = "100%",
                        children = {
                            UI.Label {
                                text = (catNames[swan.cat] or "其他") .. " | " .. swan.text,
                                fontSize = T.FontSmall, fontColor = catColors[swan.cat] or T.TextMuted,
                                flexShrink = 1,
                            },
                            UI.Label {
                                text = "剩" .. swan.remainMonths .. "月",
                                fontSize = T.FontCaption, fontColor = T.Warning,
                            },
                        }
                    },
                }
            })
        end
        table.insert(children, C.Card {children = swanCardChildren})
    end

    -- 游戏难度说明
    table.insert(children, C.SectionTitle {text = "难度说明"})
    table.insert(children, C.Card {
        children = {
            UI.Label {text = "游戏难度由以下因素综合决定：", fontSize = T.FontBody, fontColor = T.TextPrimary, marginBottom = 4},
            C.InfoRow {label = "所在城市", value = co.city, color = T.Accent},
            C.InfoRow {label = "企业性质", value = ((co.natureNames and co.natureNames[co.nature]) or "民营") .. " · 股份有限公司", color = T.Info},
            C.InfoRow {label = "注册资本", value = C.FormatMoney(co.registeredCapital)},
            UI.Label {
                text = "不同城市的房价、竞争程度和政策环境各有差异，\n合理选择城市和开发策略是成功的关键。",
                fontSize = T.FontSmall, fontColor = T.TextMuted, marginTop = 6,
            },
        }
    })

    return UI.Panel {width = "100%", gap = 10, children = children}
end

-- ============================================================================
-- Tab 3: 福利中心
-- ============================================================================
function buildWelfare(navigate)
    local children = {}

    -- 兑换码（放在最前面，方便操作）
    table.insert(children, C.SectionTitle {text = "兑换码", color = T.Accent})
    table.insert(children, C.Card {
        children = {
            UI.Label {
                text = "输入兑换码获取专属奖励",
                fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4,
            },
            UI.TextField {
                placeholder = "请输入兑换码",
                fontSize = T.FontBody,
                borderRadius = 4,
                height = 44,
                width = "100%",
                paddingHorizontal = 12,
                borderWidth = 1,
                borderColor = T.Border,
                backgroundColor = T.BgInput,
                value = M._redeemInput,
                onChange = function(self, text)
                    M._redeemInput = text
                end,
            },
            C.ActionButton {
                text = "兑换",
                width = "100%",
                marginTop = 6,
                disabled = not GD.gameStarted,
                onClick = function()
                    local ok, msg = GD.RedeemCode(M._redeemInput)
                    if ok then
                        M._message = {text = "兑换成功: " .. (msg or ""), variant = "success"}
                        M._redeemInput = ""
                    else
                        M._message = {text = msg or "兑换失败", variant = "danger"}
                    end
                    navigate("settings")
                end,
            },
            -- 已使用的兑换码列表
            UI.Panel {
                width = "100%", marginTop = 6, gap = 2,
                children = (function()
                    local used = {}
                    local count = 0
                    for code, _ in pairs(GD.redeemedCodes) do
                        count = count + 1
                        if count <= 6 then
                            table.insert(used, UI.Label {
                                text = "✓ " .. code,
                                fontSize = T.FontCaption, fontColor = T.TextMuted,
                            })
                        end
                    end
                    if count == 0 then
                        table.insert(used, UI.Label {
                            text = "尚未使用任何兑换码",
                            fontSize = T.FontCaption, fontColor = T.TextMuted,
                        })
                    end
                    return used
                end)(),
            },
        }
    })

    -- 新手礼包
    table.insert(children, C.SectionTitle {text = "新手礼包", color = T.Accent})
    local giftChildren = {
        UI.Label {text = "开业大礼包", fontSize = T.FontSubtitle, fontColor = T.Accent},
        UI.Label {text = "现金500万 + 信用分+5", fontSize = T.FontSmall, fontColor = T.TextSecondary, marginBottom = 4},
    }
    if GD.beginnerGiftClaimed then
        table.insert(giftChildren, UI.Label {text = "已领取", fontSize = T.FontBody, fontColor = T.TextMuted})
    else
        table.insert(giftChildren, C.ActionButton {
            text = "领取礼包",
            disabled = not GD.gameStarted,
            onClick = function()
                local ok, err = GD.ClaimBeginnerGift()
                if ok then
                    M._message = {text = "新手礼包领取成功！现金+500万, 信用+5", variant = "success"}
                else
                    M._message = {text = err or "领取失败", variant = "warning"}
                end
                navigate("settings")
            end,
        })
    end
    table.insert(children, C.Card {children = giftChildren})

    -- 广告奖励
    table.insert(children, C.SectionTitle {text = "观看广告赚钱"})
    table.insert(children, C.Card {
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = "每次观看奖励100万元（每天限10次）", fontSize = T.FontBody, fontColor = T.TextPrimary},
                    C.Badge {text = "今日" .. (GD.adRewardDayCount or 0) .. "/10次", variant = (GD.adRewardDayCount or 0) >= 10 and "danger" or "info"},
                }
            },
            UI.Label {
                text = "累计获得: " .. C.FormatMoney(GD.adRewardCount * 100) .. "（累计" .. GD.adRewardCount .. "次）",
                fontSize = T.FontSmall, fontColor = T.Success, marginVertical = 4,
            },
            C.ActionButton {
                text = (GD.adRewardDayCount or 0) >= 10 and "今日已达上限" or "观看广告 +100万",
                bgColor = (GD.adRewardDayCount or 0) >= 10 and T.TextSecondary or T.Success,
                fontColor = T.TextPrimary,
                disabled = not GD.gameStarted or (GD.adRewardDayCount or 0) >= 10,
                onClick = function()
                    local ok, msg = GD.ClaimAdReward()
                    if ok then
                        M._message = {text = "广告奖励已到账！现金+100万", variant = "success"}
                    else
                        M._message = {text = msg or "领取失败", variant = "warning"}
                    end
                    navigate("settings")
                end,
            },
        }
    })

    -- 兑换码已移至页面顶部

    return UI.Panel {width = "100%", gap = 10, children = children}
end

-- ============================================================================
-- Tab 4: 消息记录
-- ============================================================================
function buildEventLog(navigate)
    local children = {}

    table.insert(children, C.SectionTitle {text = "事件记录 (最近50条)"})

    if #GD.events == 0 then
        table.insert(children, C.Card {
            children = {
                UI.Label {text = "暂无事件记录", fontSize = T.FontBody, fontColor = T.TextMuted},
            }
        })
    else
        -- 按类型统计
        local counts = {success=0, warning=0, danger=0, info=0}
        for _, evt in ipairs(GD.events) do
            counts[evt.type] = (counts[evt.type] or 0) + 1
        end

        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 8, width = "100%", flexWrap = "wrap",
            children = {
                C.StatCard {title = "成功", value = tostring(counts.success), color = T.Success, minWidth = 80},
                C.StatCard {title = "警告", value = tostring(counts.warning), color = T.Warning, minWidth = 80},
                C.StatCard {title = "危险", value = tostring(counts.danger), color = T.Danger, minWidth = 80},
                C.StatCard {title = "信息", value = tostring(counts.info), color = T.Info, minWidth = 80},
            }
        })

        -- 事件列表
        local eventCards = {}
        local eventsExpanded = M._expandedLists.events == true
        for i = 1, #GD.events do
            if C.ShouldShowListItem(i, eventsExpanded, 30) then
                local evt = GD.events[i]
                table.insert(eventCards, C.EventItem {
                    text = evt.text,
                    type = evt.type,
                    time = evt.time or "",
                })
            end
        end
        table.insert(eventCards, C.FoldButton {
            total = #GD.events,
            limit = 30,
            expanded = eventsExpanded,
            onClick = function()
                M._expandedLists.events = not eventsExpanded
                navigate("settings")
            end,
        })
        table.insert(children, C.Card {
            children = eventCards,
        })
    end

    -- 通知记录
    if #GD.notifications > 0 then
        table.insert(children, C.SectionTitle {text = "系统通知"})
        local notifItems = {}
        local notificationsExpanded = M._expandedLists.notifications == true
        for i = 1, #GD.notifications do
            if C.ShouldShowListItem(i, notificationsExpanded, 10) then
                local n = GD.notifications[i]
                table.insert(notifItems, C.InfoRow {label = n.text or "通知", value = n.time or ""})
            end
        end
        table.insert(notifItems, C.FoldButton {
            total = #GD.notifications,
            limit = 10,
            expanded = notificationsExpanded,
            onClick = function()
                M._expandedLists.notifications = not notificationsExpanded
                navigate("settings")
            end,
        })
        table.insert(children, C.Card {children = notifItems})
    end

    return UI.Panel {width = "100%", gap = 10, children = children}
end

-- ============================================================================
-- Tab 5: 排行榜
-- ============================================================================
function buildLeaderboard(navigate)
    local children = {}

    table.insert(children, C.SectionTitle {text = "全服资产排行榜", color = T.Accent})

    -- 我的排名
    if not clientCloud then
        table.insert(children, C.Card {
            children = {
                UI.Label {text = "排行榜功能需要联网", fontSize = T.FontBody, fontColor = T.TextMuted},
            }
        })
        return UI.Panel {width = "100%", gap = 10, children = children}
    end

    -- 触发加载
    if not M._leaderboardLoading and not M._leaderboardData then
        M._leaderboardLoading = true
        clientCloud:GetRankList("total_assets", 0, 50, {
            ok = function(rankList)
                M._leaderboardLoading = false
                M._leaderboardData = rankList or {}
                -- 获取昵称
                local userIds = {}
                for _, item in ipairs(M._leaderboardData) do
                    table.insert(userIds, item.player)
                end
                if #userIds > 0 then
                    GetUserNickname({
                        userIds = userIds,
                        onSuccess = function(nicknames)
                            M._nicknameMap = {}
                            for _, info in ipairs(nicknames) do
                                M._nicknameMap[info.userId] = info.nickname or "未知"
                            end
                            navigate("settings")
                        end,
                        onError = function()
                            M._nicknameMap = {}
                            navigate("settings")
                        end
                    })
                else
                    M._nicknameMap = {}
                    navigate("settings")
                end
            end,
            error = function(code, reason)
                M._leaderboardLoading = false
                M._leaderboardData = {}
                M._nicknameMap = {}
                navigate("settings")
            end,
        })
    end

    -- 查询我的排名
    if not M._myRankLoading and M._myRank == nil then
        M._myRankLoading = true
        local myId = lobby and lobby:GetMyUserId() or nil
        if myId then
            clientCloud:GetUserRank(myId, "total_assets", {
                ok = function(rank, scoreValue)
                    M._myRankLoading = false
                    M._myRank = {rank = rank, score = scoreValue or 0}
                end,
                error = function()
                    M._myRankLoading = false
                    M._myRank = {rank = nil, score = 0}
                end,
            })
        else
            M._myRankLoading = false
            M._myRank = {rank = nil, score = 0}
        end
    end

    -- 我的信息卡
    local myAssets = math.floor(GD.company.totalAssets)
    local myRankText = "加载中..."
    if M._myRank then
        if M._myRank.rank then
            myRankText = "第 " .. M._myRank.rank .. " 名"
        else
            myRankText = "未上榜"
        end
    end
    table.insert(children, C.Card {
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center", width = "100%",
                children = {
                    UI.Label {text = "我的排名", fontSize = T.FontSubtitle, fontColor = T.Accent},
                    UI.Label {text = myRankText, fontSize = T.FontSubtitle, fontColor = T.Warning},
                }
            },
            C.InfoRow {label = "我的总资产", value = C.FormatMoney(myAssets), color = T.Success},
            C.InfoRow {label = "公司名称", value = GD.company.name or "未创建"},
        }
    })

    -- 刷新按钮
    table.insert(children, UI.Button {
        text = M._leaderboardLoading and "加载中..." or "刷新排行榜",
        variant = "outline",
        size = "sm",
        width = "100%",
        disabled = M._leaderboardLoading,
        onClick = function()
            M._leaderboardData = nil
            M._leaderboardLoading = false
            M._myRank = nil
            M._myRankLoading = false
            M._nicknameMap = nil
            navigate("settings")
        end,
    })

    -- 排行榜列表
    if M._leaderboardLoading then
        table.insert(children, C.Card {
            children = {
                UI.Label {text = "正在加载排行榜...", fontSize = T.FontBody, fontColor = T.TextMuted},
            }
        })
    elseif M._leaderboardData and #M._leaderboardData > 0 then
        table.insert(children, C.SectionTitle {text = "TOP 50 资产排行"})
        local rankItems = {}
        local myId = lobby and lobby:GetMyUserId() or nil
        for i, item in ipairs(M._leaderboardData) do
            local assets = (item.iscore and item.iscore.total_assets) or 0
            local nickname = (M._nicknameMap and M._nicknameMap[item.player]) or ("玩家" .. tostring(item.player))
            local isMe = (myId and item.player == myId)

            -- 排名颜色
            local rankColor = T.TextSecondary
            if i == 1 then rankColor = "#FFD700"     -- 金
            elseif i == 2 then rankColor = "#C0C0C0" -- 银
            elseif i == 3 then rankColor = "#CD7F32" -- 铜
            end

            local rowBg = isMe and T.PrimaryLight or nil
            local rowChildren = {
                UI.Label {
                    text = "#" .. i,
                    fontSize = T.FontBody,
                    fontColor = rankColor,
                    width = 36,
                },
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = nickname .. (isMe and " (我)" or ""),
                            fontSize = T.FontSmall,
                            fontColor = isMe and T.TextOnDark or T.TextPrimary,
                        },
                    }
                },
                UI.Label {
                    text = C.FormatMoney(assets),
                    fontSize = T.FontSmall,
                    fontColor = isMe and T.TextOnDark or T.Success,
                },
            }

            table.insert(rankItems, UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                paddingVertical = 8,
                paddingHorizontal = 10,
                backgroundColor = rowBg,
                borderRadius = isMe and 6 or 0,
                borderBottomWidth = (i < #M._leaderboardData) and 1 or 0,
                borderColor = T.Border,
                gap = 8,
                children = rowChildren,
            })
        end
        table.insert(children, C.Card {children = rankItems})
    elseif M._leaderboardData then
        table.insert(children, C.Card {
            children = {
                UI.Label {text = "暂无排行数据，开始游戏后自动上传", fontSize = T.FontBody, fontColor = T.TextMuted},
            }
        })
    end

    return UI.Panel {width = "100%", gap = 10, children = children}
end

-- ============================================================================
-- Tab 6: 关于
-- ============================================================================
function buildAbout(navigate)
    local children = {}

    table.insert(children, C.SectionTitle {text = "关于游戏"})
    table.insert(children, C.Card {
        children = {
            UI.Panel {
                width = "100%", alignItems = "center", gap = 8, paddingVertical = 10,
                children = {
                    UI.Label {text = "◈", fontSize = 36, fontColor = T.Accent},
                    UI.Label {text = "地产风云：完全模拟现实", fontSize = T.FontTitle, fontColor = T.TextPrimary},
                    UI.Label {text = "v1.0.0", fontSize = T.FontBody, fontColor = T.TextSecondary},
                }
            },
        }
    })

    table.insert(children, C.SectionTitle {text = "游戏简介"})
    table.insert(children, C.Card {
        children = {
            UI.Label {
                text = "《地产风云》是一款深度房地产经营模拟游戏。从注册公司到拿地开发、工程建设、营销销售、资产运营，全方位模拟房地产开发全流程。",
                fontSize = T.FontBody, fontColor = T.TextPrimary,
            },
        }
    })

    table.insert(children, C.SectionTitle {text = "核心玩法"})
    table.insert(children, C.Card {
        children = {
            C.InfoRow {label = "1. 公司管理", value = "注册资本、资质升级、人员招聘"},
            C.InfoRow {label = "2. 投资拿地", value = "土地市场、土地竞拍、储备开发、投资测算"},
            C.InfoRow {label = "3. 城市中心", value = "城市研究、地方债券、赞助、信用社、投资代建"},
            C.InfoRow {label = "4. 项目开发", value = "四证办理、设计定位、工程建设"},
            C.InfoRow {label = "5. 营销销售", value = "定价策略、渠道管理、促销活动"},
            C.InfoRow {label = "6. 资产运营", value = "自持物业、租赁管理、资产增值"},
            C.InfoRow {label = "7. 资本运作", value = "银行贷款、项目融资、分红管理"},
        }
    })

    local availableLandReserveCount = 0
    for _, land in ipairs(GD.landReserve or {}) do
        local hasProj = false
        for _, p in ipairs(GD.projects or {}) do
            if p.land and p.land.id == land.id then hasProj = true; break end
        end
        if not hasProj then availableLandReserveCount = availableLandReserveCount + 1 end
    end

    table.insert(children, C.SectionTitle {text = "游戏数据"})
    table.insert(children, C.Card {
        children = {
            C.InfoRow {label = "游戏内日期", value = GD.GetDateStr()},
            C.InfoRow {label = "已过月数", value = GD.totalMonths .. "个月"},
            C.InfoRow {label = "已过天数", value = GD.totalDays .. "天"},
            C.InfoRow {label = "可选城市", value = #GD.cities .. "座"},
            C.InfoRow {label = "竞争对手", value = #GD.competitors .. "家"},
            C.InfoRow {label = "当前项目", value = #GD.projects .. "个"},
            C.InfoRow {label = "土地储备", value = availableLandReserveCount .. "宗"},
            C.InfoRow {label = "在售地块", value = #GD.landMarket .. "宗"},
            C.InfoRow {label = "活跃贷款", value = #GD.loans .. "笔"},
        }
    })

    table.insert(children, C.SectionTitle {text = "操作提示"})
    table.insert(children, C.Card {
        children = {
            UI.Label {
                text = "• 合理控制游戏速度，在关键节点暂停决策\n• 关注经济周期，繁荣期积极拿地，萧条期谨慎经营\n• 资质升级需要累计竣工面积，注意提升注册资本\n• 信用分影响贷款额度和利率，保持良好信用\n• 股份制公司每年12月自动分红，注意现金流",
                fontSize = T.FontSmall, fontColor = T.TextSecondary,
            },
        }
    })

    return UI.Panel {width = "100%", gap = 10, children = children}
end

return M
