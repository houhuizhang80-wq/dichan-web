---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- main.lua - 地产风云：完全模拟现实 (入口文件)
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")
local PS = require("Personal")
local Effects = require("urhox-libs/Effects/Effects")

-- 屏幕模块
local StartScreen = require("screens/StartScreen")
local ChangelogScreen = require("screens/ChangelogScreen")
local CompanyCreateScreen = require("screens/CompanyCreateScreen")
local CityScreen = require("screens/CityScreen")
local DashboardScreen = require("screens/DashboardScreen")
local InvestScreen = require("screens/InvestScreen")
local AuctionScreen = require("screens/AuctionScreen")
local ProjectScreen = require("screens/ProjectScreen")
local SalesScreen = require("screens/SalesScreen")
local AssetScreen = require("screens/AssetScreen")
local CapitalScreen = require("screens/CapitalScreen")
local BrandScreen = require("screens/BrandScreen")
local PersonalScreen = require("screens/PersonalScreen")
local PersonalLifeScreen = require("screens/PersonalLifeScreen")
local PersonalFinanceScreen = require("screens/PersonalFinanceScreen")
local GovernanceScreen = require("screens/GovernanceScreen")
local GroupScreen = require("screens/GroupScreen")
local InternationalScreen = require("screens/InternationalScreen")
local GroupDiversificationScreen = require("screens/GroupDiversificationScreen")
local SettingsScreen = require("screens/SettingsScreen")
local LedgerScreen = require("screens/LedgerScreen")
local InheritanceScreen = require("screens/InheritanceScreen")
local GV = GD.Governance

-- ============================================================================
-- 全局状态
-- ============================================================================
local uiRoot_ = nil
---@type Label
local dateLabel_ = nil
local currentScreen_ = "start"
local previousScreen_ = "dashboard"  -- 设置页和公司注册页返回用
local pendingScrollRestore_ = nil  -- {scrollViewId, scrollY, framesLeft} 延迟恢复滚动位置


-- 音乐
local musicHandle_ = nil
local musicSource_ = nil

-- 启动时是否需要先显示更新日志页面（每次启动只跳转一次）
local showChangelogOnStart_ = true

-- 屏幕映射表
local screenMap_ = {
    start          = StartScreen,
    changelog      = ChangelogScreen,
    companyCreate  = CompanyCreateScreen,
    city           = CityScreen,
    dashboard      = DashboardScreen,
    invest         = InvestScreen,
    auction        = AuctionScreen,
    project        = ProjectScreen,
    sales          = SalesScreen,
    asset          = AssetScreen,
    capital        = CapitalScreen,
    brand          = BrandScreen,
    personal       = PersonalScreen,
    personalLife   = PersonalLifeScreen,
    personalFinance = PersonalFinanceScreen,
    governance     = GovernanceScreen,
    group          = GroupScreen,
    international  = InternationalScreen,
    groupDiversification = GroupDiversificationScreen,
    settings       = SettingsScreen,
    ledger         = LedgerScreen,
    inheritance    = InheritanceScreen,
}

-- 需要AppShell(TopBar+SideNav)的屏幕
local shellScreens_ = {
    dashboard = true,
    city      = true,
    invest    = true,
    auction   = true,
    project   = true,
    sales     = true,
    asset     = true,
    capital   = true,
    brand      = true,
    personal   = true,
    personalLife = true,
    personalFinance = true,
    governance = true,
    group = true,
    international = true,
    groupDiversification = true,
    settings   = true,
    ledger     = true,
}

-- 月结后只允许轻量页面自动全量刷新；复杂管理页只刷新顶栏，避免每月重建整棵 UI。
local monthlyAutoRefreshScreens_ = {
    dashboard = true,
}

local activeCompanyScreens_ = {
    invest = true,
    auction = true,
    project = true,
    sales = true,
    asset = true,
    capital = true,
    brand = true,
    governance = true,
    ledger = true,
}

-- ============================================================================
-- 生命周期
-- ============================================================================
function Start()
    graphics.windowTitle = "地产模拟"

    -- ===== 性能优化: 配置GC为增量模式，避免长期运行内存堆积 =====
    -- 不再 stop 自动GC；自动增量GC + 每帧小步进更稳定，避免旧UI树/临时表长期滞留。
    collectgarbage("incremental", 120, 200, 16)
    collectgarbage("restart")

    -- 创建场景(音频播放需要)
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    UI.Init({
        theme = T.AppTheme,
        scale = UI.Scale.DEFAULT,
    })

    -- 播放背景音乐
    StartMusic()

    -- 启动时先显示更新日志页面，看完后再进入开场页
    if showChangelogOnStart_ then
        showChangelogOnStart_ = false
        Navigate("changelog")
    else
        Navigate("start")
    end

    SubscribeToEvent("Update", "HandleUpdate")
    print("=== 地产风云：完全模拟现实 ===")
end

function Stop()
    -- 退出前自动保存（防止存档丢失）
    if GD.gameStarted then
        pcall(function()
            GD.AutoSave()
            print("[STOP] 退出前自动存档完成")
        end)
    end
    UI.Shutdown()
end

-- ============================================================================
-- 背景音乐
-- ============================================================================
function StartMusic()
    if musicHandle_ then return end
    musicHandle_ = Effects.PlaySoundLooped(scene_, "assets/audio/music_1778344188773.ogg", {
        gain = GD.musicVolume,
        soundType = SOUND_MUSIC,
    })
    if musicHandle_ then
        musicSource_ = musicHandle_.source
        print("[MUSIC] BGM started, volume=" .. GD.musicVolume)
    end
end

function SetMusicVolume(vol)
    vol = math.max(0, math.min(1, vol))
    GD.musicVolume = vol
    if musicSource_ then
        musicSource_.gain = vol
    end
end

function GetMusicSource()
    return musicSource_
end

function GetPreviousScreen()
    return previousScreen_ or "dashboard"
end

-- ============================================================================
-- 滚动位置延迟恢复（全局接口，供子屏幕调用）
-- ============================================================================
function SetPendingScrollRestore(scrollViewId, scrollY)
    pendingScrollRestore_ = { scrollViewId = scrollViewId, scrollY = scrollY, framesLeft = 3 }
end

-- ============================================================================
-- 导航系统
-- ============================================================================
function Navigate(screenId)
    if activeCompanyScreens_[screenId]
        and GD.HasActiveOperatingCompany
        and not GD.HasActiveOperatingCompany() then
        screenId = "personal"
    end

    if GD.gameStarted and GD.company and GD.company.showHeirSelection and not GD.company.isGameOver then
        screenId = "inheritance"
        GD.paused = true
    end

    -- 保存当前屏幕的滚动位置（用于同屏幕刷新时恢复）
    local isSameScreen = (screenId == currentScreen_)
    local savedY = nil
    if isSameScreen and uiRoot_ then
        local sv = uiRoot_:FindById("screenScrollView")
        if sv and sv.GetScroll then
            local _, sy = sv:GetScroll()
            if sy > 1 then
                savedY = sy
            end
        end
    end

    -- 记录上一个屏幕（用于设置页和公司注册页返回）
    if screenId == "settings" or screenId == "companyCreate" then
        previousScreen_ = currentScreen_
    end

    currentScreen_ = screenId

    local screenModule = screenMap_[screenId]
    if not screenModule then
        print("[NAV] ERROR: unknown screen: " .. screenId)
        return
    end

    -- 创建屏幕内容(pcall保护，捕获运行时错误)
    local ok, screenContent = pcall(screenModule.Create, Navigate)
    if not ok then
        local errMsg = tostring(screenContent)
        print("[NAV] ERROR creating screen '" .. screenId .. "': " .. errMsg)
        -- 显示错误页面
        screenContent = UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            gap = 12, padding = 40,
            backgroundColor = T.BgMain,
            children = {
                UI.Label {text = "页面加载出错", fontSize = T.FontTitle, fontColor = T.Danger},
                UI.Label {text = errMsg, fontSize = T.FontSmall, fontColor = T.TextSecondary, maxLines = 10},
                C.ActionButton {text = "返回总览", onClick = function() Navigate("dashboard") end},
            }
        }
    end

    -- 组装最终UI(pcall保护AppShell)
    local ok2, finalRoot = pcall(function()
        if shellScreens_[screenId] then
            return CreateAppShell(screenContent, screenId)
        else
            return screenContent
        end
    end)
    if not ok2 then
        local errMsg2 = tostring(finalRoot)
        print("[NAV] ERROR creating AppShell for '" .. screenId .. "': " .. errMsg2)
        finalRoot = UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            gap = 12, padding = 40,
            backgroundColor = T.BgMain,
            children = {
                UI.Label {text = "AppShell加载出错", fontSize = T.FontTitle, fontColor = T.Danger},
                UI.Label {text = errMsg2, fontSize = T.FontSmall, fontColor = T.TextSecondary, maxLines = 10},
                C.ActionButton {text = "返回总览", onClick = function() Navigate("dashboard") end},
            }
        }
    end
    -- 继承人选择弹窗（掌门人去世后立即选择继承人）
    if GD.company.showHeirSelection and not GD.company.isGameOver and screenId ~= "inheritance" then
        local p = GD.player or {}
        local fam = p.family or {}
        local children = fam.children or {}
        local deceasedName = GD.company.inheritanceDeceasedName or "掌门人"
        local heirButtons = {}
        for _, child in ipairs(children) do
            local capturedChild = child
            table.insert(heirButtons, UI.Button {
                text = string.format("%s（%d岁，能力%d）", capturedChild.name or "子女", capturedChild.age or 0, math.floor(capturedChild.ability or 30)),
                variant = "primary",
                backgroundColor = T.PrimaryLight,
                fontColor = T.Primary,
                borderWidth = 1,
                borderColor = T.PrimaryBorder,
                width = "100%", height = 40,
                onClick = function()
                    local ok, msg = PS.ResolveInheritance(GD, capturedChild.name)
                    if not ok then GD.AddEvent(msg or "继承失败", "danger") end
                    Navigate("personal")
                end,
            })
        end
        if #heirButtons == 0 then
            table.insert(heirButtons, UI.Label {text = "暂无可选子女", fontSize = 14, fontColor = T.TextMuted})
        end
        finalRoot = UI.Panel {
            width = "100%", height = "100%",
            children = {
                UI.Panel { width = "100%", height = "100%", children = { finalRoot } },
                UI.Panel {
                    positionType = "absolute", left = 0, top = 0, right = 0, bottom = 0,
                    backgroundColor = T.Overlay,
                    justifyContent = "center", alignItems = "center",
                    padding = 20,
                    children = {
                        UI.Panel {
                            width = "90%", maxWidth = 420,
                            backgroundColor = T.BgCard,
                            borderRadius = T.CardRadius, borderWidth = T.DividerWidth, borderColor = T.Border,
                            boxShadow = T.ShadowModal,
                            padding = 24,
                            alignItems = "center",
                            gap = 12,
                            children = {
                                UI.Label { text = "选择继承人", fontSize = 22, fontColor = T.Primary, fontWeight = "bold" },
                                UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                                UI.Label {
                                    text = deceasedName .. "已去世，请选择一名子女继承掌门人位置。\n子女任意年龄均可继承；继承后遗产税将在6个月内由继承人个人筹资缴纳，逾期后才会自动办理资产抵押贷款。",
                                    fontSize = 14, fontColor = T.TextSecondary, textAlign = "center",
                                },
                                UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                                UI.Panel {width = "100%", gap = 8, children = heirButtons},
                            }
                        }
                    }
                }
            }
        }
    end

    -- 无继承人危机弹窗（创始人死亡且无子女继承人）
    if GD.company.showNoHeirCrisis and not GD.company.isGameOver then
        local deceasedName = GD.company.noHeirDeceasedName or "创始人"
        finalRoot = UI.Panel {
            width = "100%", height = "100%",
            children = {
                UI.Panel { width = "100%", height = "100%", children = { finalRoot } },
                UI.Panel {
                    positionType = "absolute", left = 0, top = 0, right = 0, bottom = 0,
                    backgroundColor = T.Overlay,
                    justifyContent = "center", alignItems = "center",
                    padding = 20,
                    children = {
                        UI.Panel {
                            width = "90%", maxWidth = 400,
                            backgroundColor = T.BgCard,
                            borderRadius = T.CardRadius, borderWidth = T.DividerWidth, borderColor = T.Border,
                            boxShadow = T.ShadowModal,
                            padding = 24,
                            alignItems = "center",
                            gap = 12,
                            children = {
                                UI.Label { text = "继承人危机", fontSize = 22, fontColor = T.Danger, fontWeight = "bold" },
                                UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                                UI.Label {
                                    text = deceasedName .. "不幸离世，且无子女可继承公司。\n\n公司已进入托管状态，您可以选择：",
                                    fontSize = 14, fontColor = T.TextSecondary, textAlign = "center",
                                },
                                UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                                -- 收养继承人
                                UI.Button {
                                    text = "收养继承人（继续经营）",
                                    variant = "primary",
                                    backgroundColor = T.Success,
                                    width = "100%", height = 40,
                                    onClick = function()
                                        local adoptOk = PS.AdoptChild(GD, true)
                                        if adoptOk then
                                            GD.company.showNoHeirCrisis = false
                                            GD.paused = false
                                        end
                                        Navigate(currentScreen_)
                                    end,
                                },
                                -- 继续经营（托管模式）
                                UI.Button {
                                    text = "委托职业经理人继续经营",
                                    variant = "primary",
                                    backgroundColor = T.Primary,
                                    width = "100%", height = 40,
                                    onClick = function()
                                        GD.company.showNoHeirCrisis = false
                                        GD.paused = false
                                        GD.AddEvent("公司已委托职业经理人管理，继续经营", "success")
                                        Navigate(currentScreen_)
                                    end,
                                },
                                -- 手动破产
                                UI.Button {
                                    text = "清算破产（游戏结束）",
                                    variant = "danger",
                                    backgroundColor = T.Danger,
                                    width = "100%", height = 40,
                                    onClick = function()
                                        GD.company.showNoHeirCrisis = false
                                        GD.company.isGameOver = true
                                        GD.company.gameOverReason = deceasedName .. "离世，无继承人"
                                        GD.AddEvent("公司清算破产，游戏结束", "danger")
                                        Navigate(currentScreen_)
                                    end,
                                },
                            }
                        }
                    }
                }
            }
        }
    end

    -- 游戏结束覆盖层
    if GD.company.isGameOver then
        local co = GD.company
        finalRoot = UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = T.BgMain,
            justifyContent = "center", alignItems = "center",
            padding = 30,
            children = {
                UI.Panel {
                    width = "90%", maxWidth = 420,
                    backgroundColor = T.BgCard,
                    borderRadius = T.CardRadius, borderWidth = T.DividerWidth, borderColor = T.Border,
                    boxShadow = T.ShadowModal,
                    padding = 30,
                    alignItems = "center",
                    gap = 16,
                    children = {
                        UI.Label { text = co.gameOverReason and "游戏结束" or "公司破产", fontSize = 28, fontColor = T.Danger, fontWeight = "bold" },
                        UI.Label { text = co.gameOverReason or "公司资不抵债，已宣告破产", fontSize = 16, fontColor = T.TextSecondary },
                        UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                        -- 结算信息
                        UI.Label { text = "经营总结", fontSize = 18, fontColor = T.TextPrimary, fontWeight = "bold" },
                        UI.Panel {
                            width = "100%", gap = 8,
                            children = {
                                UI.Label { text = string.format("经营时长: %d年%d个月", math.floor(GD.totalMonths / 12), GD.totalMonths % 12),
                                    fontSize = 14, fontColor = T.TextSecondary },
                                UI.Label { text = "最终现金: " .. GD.FormatMoney(co.cash),
                                    fontSize = 14, fontColor = co.cash < 0 and T.Danger or T.TextSecondary },
                                UI.Label { text = "总资产: " .. GD.FormatMoney(co.totalAssets),
                                    fontSize = 14, fontColor = T.TextSecondary },
                                UI.Label { text = "总负债: " .. GD.FormatMoney(co.totalDebt),
                                    fontSize = 14, fontColor = T.TextSecondary },
                                UI.Label { text = "完成项目: " .. #(GD.completedProjects or {}),
                                    fontSize = 14, fontColor = T.TextSecondary },
                            }
                        },
                        UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                        UI.Button {
                            text = "保留个人资产，重新创业",
                            variant = "primary",
                            backgroundColor = T.Success,
                            width = "80%",
                            onClick = function()
                                GD.MarkActiveCompanyExited("bankrupt", "原公司破产清算，个人保留既有资产，可继续创办新公司")
                                Navigate("personal")
                            end,
                        },
                        UI.Button {
                            text = "返回主菜单",
                            variant = "primary",
                            backgroundColor = T.Primary,
                            width = "80%",
                            onClick = function()
                                GD.company.isGameOver = false
                                GD.company.gameOverReason = nil
                                GD.company.negativeCashMonths = 0
                                GD.company.showNoHeirCrisis = false
                                GD.company.noHeirDeceasedName = nil
                                GD.gameStarted = false
                                Navigate("start")
                            end,
                        },
                    }
                }
            }
        }
    end

    uiRoot_ = finalRoot
    dateLabel_ = uiRoot_:FindById("dateLabel")

    UI.SetRoot(uiRoot_, true)

    -- 同屏幕刷新时：延迟恢复滚动位置（等待布局完成后再设置）
    if isSameScreen and savedY then
        pendingScrollRestore_ = { scrollViewId = "screenScrollView", scrollY = savedY, framesLeft = 3 }
    else
        pendingScrollRestore_ = nil
    end
end

-- ============================================================================
-- AppShell - 顶栏 + 内容区 + 底部导航（竖版布局）
-- ============================================================================
function CreateAppShell(content, activeScreenId)
    return UI.Panel {
        id = "appShell",
        width = "100%",
        height = "100%",
        backgroundColor = T.BgDark,
        children = {
            CreateTopBar(),
            UI.Panel {
                id = "contentArea",
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                width = "100%",
                backgroundColor = T.BgMain,
                overflow = "hidden",
                children = { content },
            },
            CreateBottomNav(activeScreenId),
        }
    }
end

-- ============================================================================
-- TopBar - 顶栏（单行布局）
-- 日期 + 速度控制 + 下月按钮
-- ============================================================================
function CreateTopBar()
    local hasActiveCompany = GD.HasActiveOperatingCompany and GD.HasActiveOperatingCompany()
    local speedLabels = {"⏸", "▶", "▶▶", "▶▶▶"}
    local speedValues = {0, 1, 3, 6}

    local speedButtons = {}
    for i, label in ipairs(speedLabels) do
        local capturedI = i
        local isActive = (GD.gameSpeed == speedValues[i])
        table.insert(speedButtons, UI.Button {
            text = label,
            fontSize = 11,
            backgroundColor = isActive and T.PrimaryLight or T.TabInactiveBg,
            fontColor = isActive and T.Primary or T.TabInactiveFont,
            borderRadius = T.ButtonRadius,
            borderWidth = 2,
            borderColor = isActive and T.PrimaryBorder or T.TabInactiveBorder,
            paddingHorizontal = 7,
            height = 24,
            disabled = not hasActiveCompany,
            onClick = function()
                if not hasActiveCompany then return end
                if GD.company and GD.company.showHeirSelection then
                    GD.paused = true
                    Navigate("inheritance")
                    return
                end
                GD.gameSpeed = speedValues[capturedI]
                GD.paused = (speedValues[capturedI] == 0)
            end,
        })
    end

    -- 快进到下月1日
    local function skipToNextMonth()
        if not hasActiveCompany then return end
        if GD.company.isGameOver then return end
        if GD.company.showHeirSelection then
            GD.paused = true
            Navigate("inheritance")
            return
        end
        if GV.HasPendingCeoReports and GV.HasPendingCeoReports(GD) then
            if GV.ReopenPendingCeoReports(GD) > 0 then
                GD.paused = true
                Navigate("dashboard")
            end
            return
        end
        local targetMonth = GD.month + 1
        local targetYear = GD.year
        if targetMonth > 12 then
            targetMonth = 1
            targetYear = targetYear + 1
        end
        local safety = 0
        while (GD.month ~= targetMonth or GD.year ~= targetYear) and safety < 35 do
            local result = GD.DailyTick()
            if result == "gameover" or result == "ceo_pending" or GD.company.showHeirSelection then break end
            safety = safety + 1
        end
        if GD.company.isGameOver then GD.paused = true end
        Navigate(currentScreen_)
    end

    -- ── 第一行：日期 + 速度控制 + 下月 ──
    local row1 = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Label {
                id = "dateLabel",
                text = GD.GetDateStr(),
                fontSize = 13, fontColor = T.TextSecondary,
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Panel { flexDirection = "row", gap = 3, children = speedButtons },
                    UI.Button {
                        text = "下月 ▸",
                        fontSize = 11,
                        backgroundColor = T.BgCard,
                        fontColor = T.TextSecondary,
                        borderRadius = T.ButtonRadius,
                        borderWidth = T.DividerWidth, borderColor = T.Border,
                        paddingHorizontal = 8, height = 24,
                        disabled = not hasActiveCompany,
                        onClick = skipToNextMonth,
                    },
                },
            },
        },
    }

    return UI.Panel {
        id = "topBar",
        width = "100%",
        height = 96,
        minHeight = 96,
        flexDirection = "column",
        justifyContent = "center",
        paddingHorizontal = 10,
        paddingTop = 56,
        paddingBottom = 8,
        backgroundColor = T.BgCard,
        borderColor = T.Border,
        borderWidth = T.DividerWidth,
        children = { row1 },
    }
end

-- ============================================================================
-- BottomNav - 底部导航栏（两行五列，紧凑排列）
-- ============================================================================
function CreateBottomNav(activeScreenId)
    local tabChildren = {}

    for _, item in ipairs(T.NavItems) do
        local isActive = (item.id == activeScreenId)
        table.insert(tabChildren, UI.Button {
            flexDirection = "column",
            alignItems = "center",
            justifyContent = "center",
            gap = 3,
            width = "20%",
            height = 48,
            backgroundColor = isActive and T.PrimaryLight or T.Transparent,
            borderRadius = T.ButtonRadius,
            onClick = function()
                Navigate(item.id)
            end,
            children = {
                UI.Label {
                    text = item.icon,
                    fontSize = 17,
                    fontColor = isActive and T.Primary or T.TabInactiveFont,
                },
                UI.Label {
                    text = item.label,
                    fontSize = 11,
                    fontColor = isActive and T.Primary or T.TabInactiveFont,
                },
            },
        })
    end

    return UI.Panel {
        id = "bottomNav",
        width = "100%",
        height = T.BottomNavHeight,
        minHeight = T.BottomNavHeight,
        backgroundColor = T.BgSidebar,
        borderColor = T.Border,
        flexDirection = "row",
        flexWrap = "wrap",
        alignItems = "center",
        alignContent = "center",
        justifyContent = "flex-start",
        paddingHorizontal = 4,
        paddingVertical = 6,
        children = tabChildren,
    }
end

-- ============================================================================
-- TopBar - 日期局部刷新（避免每月重建复杂页面）
-- ============================================================================
function RefreshTopBarStats()
    if not GD.company then return end

    if not dateLabel_ and uiRoot_ then
        dateLabel_ = uiRoot_:FindById("dateLabel")
    end
    if dateLabel_ then dateLabel_:SetText(GD.GetDateStr()) end
end

-- ============================================================================
-- 更新循环 - 驱动时间系统(每日流逝)
-- ============================================================================
local pendingMonthRefresh_ = false   -- 月度UI刷新延迟标记（拆帧优化）
local pendingAutoSaveFrames_ = 0     -- 自动存档延迟帧数，避免和月度结算/UI重建同帧
local pendingAutoSaveLightweight_ = false
local gcAccumulator_ = 0

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- ===== 性能优化: 延迟的月度UI刷新（仅轻量页面自动重建，复杂页面只更新顶栏） =====
    if pendingMonthRefresh_ then
        pendingMonthRefresh_ = false
        local focusedWidget = UI.GetFocus()
        local isTextFieldFocused = focusedWidget and focusedWidget._className == "TextField"
        if not isTextFieldFocused and monthlyAutoRefreshScreens_[currentScreen_] then
            Navigate(currentScreen_)
        end
    end

    -- ===== 性能优化: 延迟自动存档（避开月度结算和UI重建高峰帧） =====
    if pendingAutoSaveFrames_ > 0 then
        pendingAutoSaveFrames_ = pendingAutoSaveFrames_ - 1
        if pendingAutoSaveFrames_ <= 0 and GD.gameStarted then
            local lightweight = pendingAutoSaveLightweight_
            pendingAutoSaveLightweight_ = false
            GD.AutoSave(lightweight)
        end
    end

    -- ===== 性能优化: 自适应渐进式GC，避免大暂停 =====
    -- 根据游戏进度动态调整GC步长：后期数据量大，需要更积极的GC
    local gcStep = 1
    if GD.gameStarted then
        local months = GD.totalMonths or 0
        if months > 120 then
            gcStep = 8   -- 10年以上：激进回收
        elseif months > 60 then
            gcStep = 5   -- 5年以上：中等回收
        elseif months > 24 then
            gcStep = 3   -- 2年以上：轻度加速
        end
    end
    gcAccumulator_ = gcAccumulator_ + dt
    if gcAccumulator_ >= 0.1 then
        gcAccumulator_ = gcAccumulator_ - 0.1
        collectgarbage("step", gcStep)
    end

    -- 延迟恢复滚动位置（等布局完成后再设置，避免被 bounce-back 重置）
    if pendingScrollRestore_ then
        pendingScrollRestore_.framesLeft = pendingScrollRestore_.framesLeft - 1
        if pendingScrollRestore_.framesLeft <= 0 then
            local restore = pendingScrollRestore_
            pendingScrollRestore_ = nil
            local root = UI.GetRoot()
            if root then
                local sv = root:FindById(restore.scrollViewId)
                if sv and sv.SetScrollDirect then
                    sv:SetScrollDirect(0, restore.scrollY)
                    -- 清除惯性速度，防止继续滑动
                    if sv.state then
                        sv.state.velocityY = 0
                        sv.state.velocityX = 0
                    end
                end
            end
        end
    end

    if not GD.gameStarted then return end

    if GD.company and GD.company.showHeirSelection then
        GD.paused = true
        if currentScreen_ ~= "inheritance" or GD.company.forceInheritanceScreen then
            GD.company.forceInheritanceScreen = false
            Navigate("inheritance")
        end
        return
    end

    -- ======================================================================
    -- CEO月度经营报告逐公司审批弹窗
    -- ======================================================================
    if GD._pendingCeoReportPopup and GD._pendingCeoReportQueue then
        local report = GD._pendingCeoReportQueue[1]
        if report then
            local reportCompanyOperating = false
            for _, record in ipairs(GD.companyPortfolio and GD.companyPortfolio.companies or {}) do
                if tostring(record.id or "") == tostring(report.companyId or "") then
                    reportCompanyOperating = record.status == "operating"
                    break
                end
            end
            if not reportCompanyOperating then
                report.status = "cancelled"
                report.cancelReason = "公司已退出经营"
                GD._ceoReportUiBuiltFor = nil
                GV.ReopenPendingCeoReports(GD)
                print("[CEO-REPORT] 弹窗跳过已退出公司的缓存报告 companyId=" .. tostring(report.companyId))
                return
            end
            GD.paused = true
            local reportUiKey = tostring(report.id or report.companyId or "unknown")
                .. ":" .. tostring(report.reportMonth or 0)
            if GD._ceoReportUiBuiltFor == reportUiKey then return end
            GD._ceoReportUiBuiltFor = reportUiKey
            -- 统一补齐旧存档报告字段，再由弹窗和执行层共用同一份提案结构。
            GV.GetCeoReportPendingDecisions(report)
            local proposals = report.proposals
            proposals.cashflow.enabled = proposals.cashflow.enabled ~= false
            proposals.loan.enabled = proposals.loan.enabled ~= false
            proposals.renovation = proposals.renovation or {enabled = false, decision = "reject"}
            proposals.equityInvestment = proposals.equityInvestment or {enabled = false, decision = "reject"}
            proposals.propertyOperation = proposals.propertyOperation or {enabled = false, decision = "reject"}
            proposals.presale = proposals.presale or {enabled = false, decision = "reject"}
            proposals.development.projectManager = proposals.development.projectManager or {enabled = false, decision = "reject"}
            report.summary = report.summary or {}
            report.summary.assets = tonumber(report.summary.assets)
                or math.max(1, (tonumber(report.summary.closingCash) or 0) + (tonumber(report.summary.debt) or 0))
            proposals.loan.assetBase = tonumber(proposals.loan.assetBase) or report.summary.assets
            proposals.loan.debtBase = tonumber(proposals.loan.debtBase) or tonumber(report.summary.debt) or 0
            proposals.loan.currentDebtRatio = tonumber(proposals.loan.currentDebtRatio)
                or proposals.loan.debtBase / math.max(1, proposals.loan.assetBase)
            proposals.loan.targetDebtRatio = tonumber(proposals.loan.targetDebtRatio)
                or math.min(0.65, (proposals.loan.debtBase + (tonumber(proposals.loan.amount) or 0))
                    / math.max(1, proposals.loan.assetBase + (tonumber(proposals.loan.amount) or 0)))
            local function refreshReportPopup()
                local scrollY = 0
                local root = UI.GetRoot()
                if root then
                    local scrollView = root:FindById("ceoReportScrollView")
                    if scrollView and scrollView.GetScroll then
                        local _, currentY = scrollView:GetScroll()
                        scrollY = math.max(0, currentY or 0)
                    end
                end
                GD._ceoReportUiBuiltFor = nil
                pendingScrollRestore_ = {
                    scrollViewId = "ceoReportScrollView",
                    scrollY = scrollY,
                    framesLeft = 3,
                }
            end
            local function setReportDecision(proposal, decisionKey, decision)
                proposal[decisionKey] = decision
                GD._ceoReportExecutionError = nil
            end
            local function decisionButton(label, proposal, decisionKey, decision, color)
                local selected = proposal[decisionKey] == decision
                return UI.Button {
                    text = selected and ("已" .. label) or label,
                    variant = decision == "approve" and "primary" or "secondary",
                    width = 130, height = 46,
                    backgroundColor = selected and color or (decision == "approve" and T.PrimaryLight or T.DisabledBg),
                    borderWidth = selected and 2 or T.DividerWidth,
                    borderColor = selected and T.Primary or T.Border,
                    onClick = function()
                        setReportDecision(proposal, decisionKey, decision)
                        if proposal == proposals.development and decisionKey == "decision"
                            and decision == "reject"
                        then
                            -- 整体拒绝开发后，两个从属参数同时视为拒绝，避免留下看似未选择的无效子项。
                            proposal.allocationDecision = "reject"
                            proposal.openingPriceDecision = "reject"
                        end
                        if proposal == proposals.development
                            and decisionKey == "allocationDecision"
                            and decision == "approve"
                        then
                            proposal.holdRatio = math.max(0, math.min(1, tonumber(proposal.holdRatio) or 0))
                            proposal.saleRatio = 1 - proposal.holdRatio
                        end
                        refreshReportPopup()
                    end,
                }
            end
            local rows = {}
            local function formatUnitPrice(value)
                return tostring(math.floor(math.max(0, tonumber(value) or 0))) .. " 元/㎡"
            end
            local function formatWan(value)
                return GD.FormatMoney(tonumber(value) or 0)
            end
            local function updateEstimatedRevenue(proposal)
                proposal.estimatedRevenue = math.floor(
                    math.max(0, tonumber(proposal.openingPrice) or 0)
                    * math.max(0, tonumber(proposal.estimatedArea) or 0)
                    / 10000
                )
            end
            local function updateRenovationBudget(proposal)
                local levels = GD.RENOVATION_LEVELS or {}
                local maxLevel = math.max(1, #levels)
                proposal.levelIndex = math.max(1, math.min(maxLevel, math.floor(tonumber(proposal.levelIndex) or 1)))
                local level = levels[proposal.levelIndex]
                if not level then return end
                proposal.levelName = level.name
                proposal.estimatedCost = math.floor(
                    math.max(0, tonumber(proposal.holdAreaEstimate) or 0)
                    * math.max(0, tonumber(level.costPerSqm) or 0)
                    / 10000
                )
            end
            local function addSummaryRow(label, value)
                table.insert(rows, UI.Label {
                    text = label .. "：" .. value,
                    fontSize = T.FontSmall, fontColor = T.TextSecondary,
                    whiteSpace = "normal",
                })
            end
            table.insert(rows, UI.Label {
                text = "上月经营：营收 " .. formatWan(report.summary.revenue)
                    .. "，支出 " .. formatWan(report.summary.expense)
                    .. "，利润 " .. formatWan(report.summary.profit)
                    .. "，期末现金 " .. formatWan(report.summary.closingCash)
                    .. "，负债 " .. formatWan(report.summary.debt),
                fontSize = T.FontSmall, fontColor = T.TextSecondary,
                whiteSpace = "normal",
            })
            addSummaryRow("建设投入承诺", formatWan(report.summary.constructionCommitment))
            addSummaryRow("项目经理月度成本", formatWan(report.summary.projectManagerCost))
            addSummaryRow("挂牌租金/固定资产租金", formatWan(report.summary.listedRent)
                .. " / " .. formatWan(report.summary.fixedAssetRent))
            addSummaryRow("安全预留/可动用现金", formatWan(report.summary.safeReserve)
                .. " / " .. formatWan(report.summary.availableCash))
            local function inputField(value, placeholder, onChange)
                return UI.TextField {
                    value = tostring(value or ""),
                    placeholder = placeholder,
                    width = 150, height = 42,
                    backgroundColor = T.BgInput,
                    fontColor = T.TextPrimary,
                    borderRadius = 5,
                    paddingHorizontal = 10,
                    onChange = onChange,
                }
            end
            local function stepButton(label, onClick)
                return UI.Button {
                    text = label,
                    variant = "secondary",
                    minWidth = 92,
                    height = 42,
                    flexGrow = 1,
                    flexBasis = 0,
                    onClick = onClick,
                }
            end
            local function addStepRow(children, label, valueText, decreaseText, increaseText, onDecrease, onIncrease)
                table.insert(children, UI.Panel {
                    width = "100%", marginTop = 8, gap = 7,
                    children = {
                        UI.Panel {
                            width = "100%", flexDirection = "row", alignItems = "center",
                            justifyContent = "space-between", gap = 8,
                            children = {
                                UI.Label {text = label, fontSize = T.FontSmall, fontColor = T.TextSecondary},
                                UI.Label {text = valueText, fontSize = T.FontBody, fontColor = T.Primary, fontWeight = "bold"},
                            },
                        },
                        UI.Panel {
                            width = "100%", flexDirection = "row", gap = 8,
                            children = {
                                stepButton(decreaseText, onDecrease),
                                stepButton(increaseText, onIncrease),
                            },
                        },
                    },
                })
            end
            local function adjustCashflow(key, delta)
                local cashflow = proposals.cashflow
                local reserve = math.max(0.10, math.min(0.80, tonumber(cashflow.reserveRatio) or 0.25))
                local acquisition = math.max(0, math.min(0.90, tonumber(cashflow.acquisitionRatio) or 0.35))
                local development = math.max(0, math.min(0.90, tonumber(cashflow.developmentRatio) or 0.40))
                local total = reserve + acquisition + development
                if total <= 0 then
                    reserve, acquisition, development = 0.25, 0.35, 0.40
                else
                    reserve, acquisition, development = reserve / total, acquisition / total, development / total
                end
                if key == "reserveRatio" then
                    local nextValue = math.max(0.10, math.min(0.80, reserve + delta))
                    development = math.max(0, development - (nextValue - reserve))
                    reserve = nextValue
                elseif key == "acquisitionRatio" then
                    local nextValue = math.max(0, math.min(1 - reserve, acquisition + delta))
                    development = math.max(0, development - (nextValue - acquisition))
                    acquisition = nextValue
                else
                    local nextValue = math.max(0, math.min(1 - reserve, development + delta))
                    acquisition = math.max(0, acquisition - (nextValue - development))
                    development = nextValue
                end
                local normalizedTotal = reserve + acquisition + development
                if normalizedTotal < 1 then development = development + (1 - normalizedTotal) end
                cashflow.reserveRatio = reserve
                cashflow.acquisitionRatio = acquisition
                cashflow.developmentRatio = development
                refreshReportPopup()
            end
            local function updateLoanFromTargetRatio(targetRatio)
                local loan = proposals.loan
                local assets = math.max(1, tonumber(loan.assetBase) or tonumber(report.summary.assets) or 1)
                local debt = math.max(0, tonumber(loan.debtBase) or tonumber(report.summary.debt) or 0)
                targetRatio = math.max(0, math.min(1.0, targetRatio))
                loan.targetDebtRatio = targetRatio
                loan.currentDebtRatio = debt / assets
                refreshReportPopup()
            end
            local function addDecisionRow(children, label, proposal, decisionKey, approveText, rejectText)
                table.insert(children, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8,
                    flexWrap = "wrap", width = "100%", marginTop = 6,
                    children = {
                        UI.Label {
                            text = label,
                            width = 138,
                            fontSize = T.FontSmall,
                            fontColor = T.TextSecondary,
                            flexShrink = 0,
                        },
                        decisionButton(approveText or "批准", proposal, decisionKey, "approve", T.PrimaryLight),
                        decisionButton(rejectText or "拒绝", proposal, decisionKey, "reject", T.DisabledBg),
                    },
                })
            end
            local function addProposal(title, text, proposal, adjustable)
                if not proposal.enabled and title ~= "现金流配置" then return end
                local children = {
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        width = "100%", children = {
                            UI.Label {text = title, fontSize = T.FontBody, fontColor = T.TextPrimary},
                            UI.Label {text = text, fontSize = T.FontSmall, fontColor = T.TextSecondary, flexGrow = 1, flexBasis = 0, flexShrink = 1, marginLeft = 8},
                        },
                    },
                }
                if adjustable and proposal.enabled then
                    local fields = {}
                    if proposal == proposals.land then
                        table.insert(fields, inputField(proposal.price, "土地预算", function(_, value)
                            local number = tonumber(value)
                            if number and number >= 0 then proposal.price = math.floor(number) end
                        end))
                    elseif proposal == proposals.development then
                        table.insert(fields, inputField(math.floor((proposal.holdRatio or 0) * 100), "自持%", function(_, value)
                            local number = tonumber(value)
                            if number then
                                proposal.holdRatio = math.max(0, math.min(100, number)) / 100
                                proposal.saleRatio = 1 - proposal.holdRatio
                            end
                        end))
                        table.insert(fields, inputField(proposal.openingPrice, "开盘价（元/㎡）", function(_, value)
                            local number = tonumber(value)
                            if number and number >= 1000 then
                                proposal.openingPrice = math.floor(number)
                                updateEstimatedRevenue(proposal)
                            end
                        end))
                    elseif proposal == proposals.cashflow then
                        table.insert(fields, inputField(math.floor((proposal.reserveRatio or 0) * 100), "留存%", function(_, value)
                            local number = tonumber(value)
                            if number then proposal.reserveRatio = math.max(10, math.min(80, number)) / 100 end
                        end))
                        table.insert(fields, inputField(math.floor((proposal.acquisitionRatio or 0) * 100), "拿地%", function(_, value)
                            local number = tonumber(value)
                            if number then proposal.acquisitionRatio = math.max(0, math.min(100, number)) / 100 end
                        end))
                        table.insert(fields, inputField(math.floor((proposal.developmentRatio or 0) * 100), "开发%", function(_, value)
                            local number = tonumber(value)
                            if number then proposal.developmentRatio = math.max(0, math.min(100, number)) / 100 end
                        end))
                    elseif proposal == proposals.loan then
                        -- 资产负债率控制指标，无需输入贷款额度和期限
                    elseif proposal == proposals.equityInvestment then
                        table.insert(fields, inputField(proposal.amount, "投资金额/万元", function(_, value)
                            local number = tonumber(value)
                            if number and number >= 100 then proposal.amount = math.floor(number) end
                        end))
                    end
                    if #fields > 0 then
                        table.insert(children, UI.Panel {
                            flexDirection = "row", gap = 8, flexWrap = "wrap", width = "100%", marginTop = 8,
                            children = fields,
                        })
                    end
                    if proposal == proposals.land then
                        addDecisionRow(children, "购买土地", proposal, "decision", "批准", "拒绝")
                    elseif proposal == proposals.development then
                        local holdPercent = math.floor((proposal.holdRatio or 0) * 100 + 0.5)
                        addStepRow(children, "自持比例", tostring(holdPercent) .. "%",
                            "自持 -5%", "自持 +5%",
                            function()
                                proposal.holdRatio = math.max(0, (proposal.holdRatio or 0) - 0.05)
                                proposal.saleRatio = 1 - proposal.holdRatio
                                refreshReportPopup()
                            end,
                            function()
                                proposal.holdRatio = math.min(1, (proposal.holdRatio or 0) + 0.05)
                                proposal.saleRatio = 1 - proposal.holdRatio
                                refreshReportPopup()
                            end)
                        local price = math.max(1000, math.floor(proposal.openingPrice or 1000))
                        local priceStep = math.max(100, math.floor(price * 0.05 / 100) * 100)
                        addStepRow(children, "计划开盘价", formatUnitPrice(price),
                            "调低5%", "调高5%",
                            function()
                                proposal.openingPrice = math.max(1000, price - priceStep)
                                updateEstimatedRevenue(proposal)
                                refreshReportPopup()
                            end,
                            function()
                                proposal.openingPrice = price + priceStep
                                updateEstimatedRevenue(proposal)
                                refreshReportPopup()
                            end)
                        addDecisionRow(children, "启动项目", proposal, "decision", "批准", "拒绝")
                        addDecisionRow(children, "自持/销售比例", proposal, "allocationDecision", "采用", "不采用")
                        addDecisionRow(children, "计划开盘价", proposal, "openingPriceDecision", "采用", "不采用")
                    elseif proposal == proposals.cashflow then
                        local function percent(value) return tostring(math.floor((value or 0) * 100 + 0.5)) .. "%" end
                        addStepRow(children, "现金留存", percent(proposal.reserveRatio), "留存 -5%", "留存 +5%",
                            function() adjustCashflow("reserveRatio", -0.05) end,
                            function() adjustCashflow("reserveRatio", 0.05) end)
                        addStepRow(children, "拿地配置", percent(proposal.acquisitionRatio), "拿地 -5%", "拿地 +5%",
                            function() adjustCashflow("acquisitionRatio", -0.05) end,
                            function() adjustCashflow("acquisitionRatio", 0.05) end)
                        addStepRow(children, "开发配置", percent(proposal.developmentRatio), "开发 -5%", "开发 +5%",
                            function() adjustCashflow("developmentRatio", -0.05) end,
                            function() adjustCashflow("developmentRatio", 0.05) end)
                        addDecisionRow(children, title, proposal, "decision", "批准", "拒绝")
                    elseif proposal == proposals.loan then
                        local assets = math.max(1, tonumber(proposal.assetBase) or tonumber(report.summary.assets) or 1)
                        local debt = math.max(0, tonumber(proposal.debtBase) or tonumber(report.summary.debt) or 0)
                        proposal.currentDebtRatio = tonumber(proposal.currentDebtRatio) or debt / assets
                        proposal.targetDebtRatio = tonumber(proposal.targetDebtRatio) or proposal.currentDebtRatio
                        addStepRow(children, "目标资产负债率",
                            tostring(math.floor(proposal.targetDebtRatio * 100 + 0.5)) .. "%",
                            "-5%", "+5%",
                            function() updateLoanFromTargetRatio(proposal.targetDebtRatio - 0.05) end,
                            function() updateLoanFromTargetRatio(proposal.targetDebtRatio + 0.05) end)
                        -- 纯控制指标，无需审批决策
                    elseif proposal == proposals.renovation then
                        local levelIndex = math.max(1, math.floor(tonumber(proposal.levelIndex) or 1))
                        local levelName = proposal.levelName or "固定资产装修"
                        addStepRow(children, "装修等级", levelName .. "（" .. tostring(levelIndex) .. "档）", "降低一档", "提高一档",
                            function()
                                proposal.levelIndex = math.max(1, levelIndex - 1)
                                updateRenovationBudget(proposal)
                                refreshReportPopup()
                            end,
                            function()
                                local maxLevel = GD.RENOVATION_LEVELS and #GD.RENOVATION_LEVELS or 4
                                proposal.levelIndex = math.min(maxLevel, levelIndex + 1)
                                updateRenovationBudget(proposal)
                                refreshReportPopup()
                            end)
                        addDecisionRow(children, "固定资产装修", proposal, "decision", "批准", "拒绝")
                    elseif proposal == proposals.equityInvestment then
                        addDecisionRow(children, "股权投资", proposal, "decision", "批准", "拒绝")
                    elseif proposal == proposals.propertyOperation then
                        addDecisionRow(children, "物业运营", proposal, "decision", "批准", "拒绝")
                    elseif proposal == proposals.presale then
                        local price = math.max(1, math.floor(proposal.openingPrice or 1))
                        local step = math.max(100, math.floor(price * 0.05 / 100) * 100)
                        local minimumPrice = math.max(1000, math.floor(price * 0.50 / 100) * 100)
                        addStepRow(children, "开盘价", tostring(price) .. "元/㎡",
                            "降价 -5%", "涨价 +5%",
                            function()
                                proposal.openingPrice = math.max(minimumPrice, price - step)
                                proposal.estimatedRevenue = math.floor((proposal.openingPrice) * (proposal.totalArea or 0) / 10000)
                                refreshReportPopup()
                            end,
                            function()
                                proposal.openingPrice = price + step
                                proposal.estimatedRevenue = math.floor((proposal.openingPrice) * (proposal.totalArea or 0) / 10000)
                                refreshReportPopup()
                            end)
                        addDecisionRow(children, "开盘预售", proposal, "decision", "批准", "拒绝")
                    end
                end
                table.insert(rows, C.Card {children = children})
            end
            addProposal("土地购买", (proposals.land.location or "") .. "，预算" .. GD.FormatMoney(proposals.land.price or 0), proposals.land, true)
            addProposal("新项目开发", (proposals.development.projectName or "")
                .. "，自持" .. math.floor((proposals.development.holdRatio or 0) * 100) .. "%，销售"
                .. math.floor((proposals.development.saleRatio or 0) * 100) .. "%，面积"
                .. tostring(math.floor(proposals.development.estimatedArea or 0)) .. "㎡，预计销售收入"
                .. formatWan(proposals.development.estimatedRevenue) .. "，开盘"
                .. formatUnitPrice(proposals.development.openingPrice or 0), proposals.development, true)
            addProposal("固定资产装修", (proposals.renovation.projectName or "暂无待转固项目")
                .. "，" .. (proposals.renovation.levelName or "装修方案")
                .. "，预算" .. formatWan(proposals.renovation.estimatedCost), proposals.renovation, true)
            addProposal("股权投资", (proposals.equityInvestment.targetCompanyName or "暂无投资对象")
                .. "，投资" .. formatWan(proposals.equityInvestment.amount)
                .. "，预估年分红" .. formatWan(proposals.equityInvestment.expectedDividend), proposals.equityInvestment, true)
            addProposal("物业运营", (proposals.propertyOperation.projectName or "暂无待运营物业")
                .. "，建议" .. (proposals.propertyOperation.modeName or "暂无运营模式"), proposals.propertyOperation, true)
            -- 预售开盘提案
            if proposals.presale and proposals.presale.enabled then
                local presaleDetails = (proposals.presale.projectType or "未分类项目")
                    .. "｜" .. (proposals.presale.projectCity or "")
                    .. ((proposals.presale.projectLocation or "") ~= "" and ("·" .. proposals.presale.projectLocation) or "")
                addProposal("项目开盘预售", (proposals.presale.projectName or "项目")
                    .. "（" .. presaleDetails .. "）"
                    .. "，建议开盘价" .. tostring(math.floor(proposals.presale.openingPrice or 0)) .. "元/㎡"
                    .. "，预计销售收入" .. formatWan(proposals.presale.estimatedRevenue), proposals.presale, true)
            end
            addProposal("现金流配置", "留存" .. math.floor((proposals.cashflow.reserveRatio or 0) * 100)
                .. "% / 拿地" .. math.floor((proposals.cashflow.acquisitionRatio or 0) * 100)
                .. "% / 开发" .. math.floor((proposals.cashflow.developmentRatio or 0) * 100) .. "%", proposals.cashflow, true)
            addProposal("资产负债率控制", "当前"
                .. string.format("%.0f%%", (proposals.loan.currentDebtRatio or 0) * 100)
                .. "，目标" .. string.format("%.0f%%", (proposals.loan.targetDebtRatio or 0) * 100)
                .. "（CEO自主管理贷款与还款）", proposals.loan, true)

            local clearanceResults = proposals.clearanceResults or {enabled = false, items = {}}
            if clearanceResults.enabled then
                table.insert(rows, UI.Label {
                    text = "项目开发盈利成果（确认后随本次CEO汇报正式归档）",
                    fontSize = T.FontBody,
                    fontColor = T.TextPrimary,
                    fontWeight = "bold",
                    whiteSpace = "normal",
                })
                for _, result in ipairs(clearanceResults.items or {}) do
                    local isFixedAsset = result.resultType == "fixed_asset_rental"
                    local details
                    if isFixedAsset then
                        details = tostring(result.projectName or "项目") .. "已完成自持物业装修、缴税、转固定资产并挂牌出租。开发原值"
                            .. formatWan(result.developmentCost) .. "，装修投入" .. formatWan(result.renovationCost)
                            .. "，转固税费" .. formatWan(result.tax) .. "，总投入" .. formatWan(result.totalCost)
                            .. "，当前评估值" .. formatWan(result.assetValue) .. "，评估增值"
                            .. formatWan(result.netProfit) .. "，目标月租" .. formatWan(result.targetMonthlyRent) .. "。"
                    else
                        details = tostring(result.projectName or "项目") .. "已完成销售售罄、缴税和清盘。销售收入"
                            .. formatWan(result.salesRevenue) .. "，税前总成本"
                            .. formatWan(result.totalCostBeforeTax or result.totalCost)
                            .. "，税前利润" .. formatWan(result.grossProfit) .. "，所得税"
                            .. formatWan(result.incomeTax or result.tax) .. "，税后净利润"
                            .. formatWan(result.netProfitAfterTax or result.netProfit) .. "，净利率"
                            .. string.format("%.1f%%", (tonumber(result.profitMargin) or 0) * 100) .. "。"
                    end
                    table.insert(rows, C.Card {
                        children = {
                            UI.Label {
                                text = details,
                                fontSize = T.FontSmall,
                                fontColor = T.TextSecondary,
                                whiteSpace = "normal",
                            },
                            UI.Button {
                                text = result.confirmed and "已确认（待提交汇报）" or "确认项目开发盈利成果",
                                variant = "primary",
                                width = "100%",
                                height = 48,
                                disabled = result.confirmed == true,
                                onClick = function()
                                    result.confirmed = true
                                    refreshReportPopup()
                                end,
                            },
                        },
                    })
                end
            end

            local function advanceCeoReportQueue()
                GD._ceoReportExecuting = false
                GD._ceoReportExecutionError = nil
                GD._ceoReportBatchProcessed = (GD._ceoReportBatchProcessed or 0) + 1
                GD._ceoReportUiBuiltFor = nil
                local remaining = GV.ReopenPendingCeoReports and GV.ReopenPendingCeoReports(GD) or 0
                if remaining > 0 then
                    GD._pendingCeoReportPopup = true
                    GD.paused = true
                    Navigate("dashboard")
                else
                    GD._pendingCeoReportPopup = false
                    GD.paused = false
                    GD._ceoReportBatchTotal = nil
                    GD._ceoReportBatchProcessed = nil
                    Navigate(currentScreen_)
                end
            end

            local function finishReport()
                if GD._ceoReportExecuting then return end
                GD._ceoReportExecuting = true
                local decisionsOk, decisionError = GV.ValidateCeoReportDecisions(report)
                if not decisionsOk then
                    GD._ceoReportExecuting = false
                    GD._ceoReportExecutionError = decisionError or "请先处理全部重大经营事项"
                    GD.AddEvent(GD._ceoReportExecutionError, "warning")
                    refreshReportPopup()
                    return
                end
                GD._ceoReportExecutionError = nil
                local ok, msg = GV.ApplyCeoReport(GD, report)
                if not ok then
                    GD._ceoReportExecuting = false
                    GD._ceoReportExecutionError = msg or "CEO月报执行失败"
                    GD.AddEvent(GD._ceoReportExecutionError, "danger")
                    refreshReportPopup()
                    return
                end
                advanceCeoReportQueue()
            end
            local deferReport = UI.Button {
                text = "返回",
                variant = "secondary", width = 112, height = 46,
                onClick = function()
                    GD._ceoReportExecuting = false
                    GD._ceoReportExecutionError = nil
                    GD._ceoReportUiBuiltFor = nil
                    GD._pendingCeoReportPopup = false
                    GD._ceoReportDeferred = true
                    GD.paused = false
                    GD.AddEvent("CEO月报已暂存；进入下月前必须完成全部重大事项审批", "warning")
                    Navigate(currentScreen_)
                end,
            }
            local rejectAll = UI.Button {
                text = "本公司计划全部拒绝",
                variant = "secondary", width = "100%", height = 50,
                onClick = function()
                    GD._ceoReportUiBuiltFor = nil
                    local ok, msg = GV.RejectCeoReport(GD, report)
                    if not ok then
                        GD.AddEvent(msg or "CEO月报拒绝失败", "danger")
                        Navigate("dashboard")
                        return
                    end
                    advanceCeoReportQueue()
                end,
            }
            local pendingDecisionLabels = GV.GetCeoReportPendingDecisions(report)
            local pendingDecisionText = #pendingDecisionLabels > 0
                and ("还有" .. tostring(#pendingDecisionLabels) .. "项未处理：" .. table.concat(pendingDecisionLabels, "、"))
                or "所有必选事项已处理，可以执行已选计划"
            local executionHint = UI.Label {
                text = GD._ceoReportExecutionError or pendingDecisionText,
                fontSize = T.FontSmall,
                fontColor = GD._ceoReportExecutionError and T.Danger
                    or (#pendingDecisionLabels > 0 and T.Warning or T.Success),
                textAlign = "center",
                whiteSpace = "normal",
                width = "100%",
            }
            local approveAll = UI.Button {
                text = #pendingDecisionLabels > 0
                    and ("尚有" .. tostring(#pendingDecisionLabels) .. "项未处理")
                    or "执行已选计划",
                variant = "primary", width = "100%", height = 52,
                onClick = finishReport,
            }
            local popupRoot = UI.Panel {
                width = "100%", height = "100%", backgroundColor = T.Overlay,
                justifyContent = "center", alignItems = "center", padding = 16,
                children = {
                    UI.Panel {
                        width = "98%", height = "96%", maxWidth = 680,
                        backgroundColor = T.BgCard, borderRadius = T.CardRadius,
                        borderWidth = 2, borderColor = T.Primary,
                        boxShadow = T.ShadowModal, padding = 22, gap = 12,
                        children = {
                            UI.Panel {
                                width = "100%", flexDirection = "row", alignItems = "center",
                                justifyContent = "space-between", gap = 10,
                                children = {
                                    UI.Label {
                                        text = "CEO月末经营汇报", fontSize = T.FontTitle,
                                        fontColor = T.Primary, fontWeight = "bold",
                                        flexGrow = 1, flexBasis = 0, flexShrink = 1,
                                    },
                                    deferReport,
                                },
                            },
                            UI.Label {
                                text = report.companyName .. "｜第" .. tostring(report.reportMonth) .. "个月｜第"
                                    .. tostring((GD._ceoReportBatchProcessed or 0) + 1) .. "/"
                                    .. tostring(GD._ceoReportBatchTotal or #(GD._pendingCeoReportQueue or {report})) .. "家公司",
                                fontSize = T.FontSmall,
                                fontColor = T.TextMuted,
                            },
                            UI.Panel {width = "100%", height = T.DividerWidth, backgroundColor = T.Border},
                            UI.ScrollView {
                                id = "ceoReportScrollView",
                                width = "100%", flexGrow = 1, flexBasis = 0,
                                scrollY = true, paddingRight = 12, gap = 10,
                                children = rows,
                            },
                            UI.Panel {width = "100%", height = T.DividerWidth, backgroundColor = T.Border},
                            executionHint,
                            approveAll,
                            rejectAll,
                        },
                    },
                },
            }
            UI.SetRoot(popupRoot)
            return
        end
    end

    -- ======================================================================
    -- 遗产税月度提醒弹窗
    -- ======================================================================
    if GD._pendingInheritanceTaxPopup then
        GD._pendingInheritanceTaxPopup = nil
        local status = PS.GetInheritanceTaxStatus(GD)
        if status.active then
            GD.paused = true
            local phaseText
            if status.overdue then
                phaseText = "已逾期，系统将在可抵押额度内自动办理遗产资产抵押贷款。"
            elseif status.finalMonth then
                phaseText = "这是最后一个宽限月，逾期后将自动办理遗产资产抵押贷款。"
            else
                phaseText = "请在宽限期内筹集个人资金，也可先申请个人信用贷款再缴税。"
            end
            local popupRoot = UI.Panel {
                width = "100%", height = "100%",
                justifyContent = "center", alignItems = "center",
                backgroundColor = T.Overlay, padding = 20,
                children = {
                    UI.Panel {
                        width = "90%", maxWidth = 400,
                        backgroundColor = T.BgCard,
                        borderRadius = T.CardRadius, borderWidth = 2,
                        borderColor = status.overdue and T.Danger or T.Warning,
                        boxShadow = T.ShadowModal, padding = 24,
                        alignItems = "center", gap = 14,
                        children = {
                            UI.Label {
                                text = status.overdue and "遗产税逾期提醒" or "遗产税缴纳提醒",
                                fontSize = T.FontTitle,
                                fontColor = status.overdue and T.Danger or T.Warning,
                                fontWeight = "bold",
                            },
                            UI.Panel {width = "100%", height = T.DividerWidth, backgroundColor = T.Border},
                            UI.Label {
                                text = "待缴金额：" .. GD.FormatMoney(status.remaining)
                                    .. "\n已过宽限期：" .. tostring(status.elapsedMonths) .. " / " .. tostring(status.graceMonths) .. "个月\n\n" .. phaseText,
                                fontSize = T.FontBody, fontColor = T.TextPrimary,
                                textAlign = "center", whiteSpace = "normal",
                            },
                            UI.Panel {width = "100%", height = T.DividerWidth, backgroundColor = T.Border},
                            UI.Panel {
                                flexDirection = "row", gap = 8, width = "100%",
                                children = {
                                    UI.Button {
                                        text = "前往个人财务", variant = "primary",
                                        width = "100%", height = 44,
                                        onClick = function()
                                            GD.paused = false
                                            Navigate("personal")
                                        end,
                                    },
                                    UI.Button {
                                        text = "知道了", width = "100%", height = 44,
                                        onClick = function()
                                            GD.paused = false
                                            Navigate(currentScreen_)
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            }
            UI.SetRoot(popupRoot)
            return
        end
    end

    -- ======================================================================
    -- 资金危机弹窗（检测 GD._pendingCashCrisisPopup 标记）
    -- 此标记由 MonthlyTick 在现金首次变负时设置
    -- 放在 Tick 之前，确保最早被检测到，不受任何其他逻辑干扰
    -- ======================================================================
    if GD._pendingCashCrisisPopup then
        GD._pendingCashCrisisPopup = nil  -- 立即清除，只弹一次
        GD.paused = true
        print("[CASH-CRISIS] ★★★ 弹窗触发！cash=" .. tostring(GD.company.cash))

        local ok, err = pcall(function()
            local cashStr = GD.FormatMoney and GD.FormatMoney(GD.company.cash) or tostring(GD.company.cash)
            local negMonths = GD.company.negativeCashMonths or 0
            local remainMonths = math.max(0, 6 - negMonths)

            local popupRoot = UI.Panel {
                width = "100%", height = "100%",
                justifyContent = "center", alignItems = "center",
                backgroundColor = T.Overlay,
                padding = 20,
                children = {
                    UI.Panel {
                        width = "90%", maxWidth = 380,
                        backgroundColor = T.BgCard,
                        borderRadius = T.CardRadius, borderWidth = 2, borderColor = T.Danger,
                        boxShadow = T.ShadowModal,
                        padding = 24,
                        alignItems = "center",
                        gap = 14,
                        children = {
                            UI.Label { text = "⚠ 资金危机警告", fontSize = 22, fontColor = T.Danger, fontWeight = "bold" },
                            UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                            UI.Label {
                                text = string.format(
                                    "公司现金已变为负数（%s）！\n\n若连续6个月现金流不足，公司将自动破产清算！\n\n剩余时间：%d 个月\n\n请尽快通过融资解决资金问题。",
                                    cashStr, remainMonths),
                                fontSize = 15, fontColor = T.TextPrimary, textAlign = "center",
                            },
                            UI.Panel { width = "100%", height = T.DividerWidth, backgroundColor = T.Border },
                            UI.Button {
                                text = "知道了",
                                variant = "primary",
                                width = "100%", height = 44,
                                onClick = function()
                                    GD.paused = false
                                    Navigate(currentScreen_)
                                end,
                            },
                        }
                    }
                }
            }
            UI.SetRoot(popupRoot)
            print("[CASH-CRISIS] ★★★ UI.SetRoot 成功！弹窗已显示")
        end)
        if not ok then
            print("[CASH-CRISIS] ★★★ 弹窗构建失败: " .. tostring(err))
            GD.paused = false
        end
        return  -- 弹窗帧不做其他处理
    end

    local tick = GD.Tick(dt)
    if GD.company and GD.company.showHeirSelection then
        GD.paused = true
        Navigate("inheritance")
        return
    end
    if tick == "gameover" then
        -- 游戏结束：暂停并显示结算画面
        GD.paused = true
        Navigate(currentScreen_)  -- 刷新以显示游戏结束提示
    elseif tick == "ceo_pending" then
        GD.paused = true
        Navigate("dashboard")
    elseif tick == "month" then
        -- 自动存档检查(每6个月)：只设置延迟标记，真正存档放到后续帧
        if GD.CheckAutoSave() then
            pendingAutoSaveFrames_ = math.max(pendingAutoSaveFrames_, 2)
            pendingAutoSaveLightweight_ = false
        end
        -- 需要弹窗或游戏结束等状态变化时，仍立即重建页面。
        if GD.company and GD.company.showHeirSelection then
            pendingMonthRefresh_ = true
        end
        RefreshTopBarStats()
    elseif tick == "day" then
        -- 实时存档检查(每30个游戏日)：延迟到后续低峰帧轻量保存，减少进度丢失风险
        if GD.CheckRealTimeAutoSave and GD.CheckRealTimeAutoSave() then
            if pendingAutoSaveFrames_ <= 0 then
                pendingAutoSaveFrames_ = 2
                pendingAutoSaveLightweight_ = true
            end
        end
        -- 每日: 仅刷新顶栏，不重建整个UI
        RefreshTopBarStats()
    end

end
