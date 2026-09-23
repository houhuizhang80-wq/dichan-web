-- ============================================================================
-- StartScreen.lua - 游戏开始界面（竖版）
-- ============================================================================

local UI = require("urhox-libs/UI")
local T = require("UITheme")
local C = require("Components")
local GD = require("GameData")

local M = {}

local CHANGELOG_VERSION = "V1.0.43"

function M.Create(navigate)
    -- 检查是否有存档可继续(含自动存档)
    local latestSave = GD.GetLatestSlotInfoWithAuto()

    local buttons = {}

    -- 继续游戏按钮（有存档时显示）
    if latestSave then
        table.insert(buttons, UI.Button {
            text = "继 续 游 戏",
            fontSize = 16,
            backgroundColor = T.Accent,
            fontColor = T.TextOnDark,
            borderRadius = T.ButtonRadius,
            paddingHorizontal = 48,
            width = 220,
            height = 48,
            onClick = function()
                local ok, err
                if latestSave.slot == "auto" then
                    ok, err = GD.LoadAutoSave()
                else
                    ok, err = GD.LoadFromSlot(latestSave.slot)
                end
                if ok then
                    navigate("dashboard")
                else
                    print("[START] 读档失败: " .. tostring(err))
                    navigate("start")
                end
            end,
        })
        -- 存档摘要
        table.insert(buttons, UI.Label {
            text = latestSave.name .. " | " .. latestSave.date,
            fontSize = T.FontCaption,
            fontColor = T.TextMuted,
            textAlign = "center",
        })
        -- 间距
        table.insert(buttons, UI.Panel { height = 6 })
    end

    -- 新游戏按钮
    table.insert(buttons, UI.Button {
        text = "新 游 戏",
        fontSize = 16,
        backgroundColor = latestSave and T.PrimaryLight or T.Accent,
        fontColor = latestSave and T.Primary or T.TextOnDark,
        borderRadius = T.ButtonRadius,
        paddingHorizontal = 48,
        width = 220,
        height = 48,
        onClick = function()
            navigate("companyCreate")
        end,
    })

    -- 读取存档按钮（有任意存档时显示）
    local hasAnySave = false
    for i = 1, GD.MANUAL_SAVE_SLOT_COUNT do
        if GD.GetSlotInfo(i) then hasAnySave = true; break end
    end
    if hasAnySave then
        table.insert(buttons, UI.Panel { height = 2 })
        table.insert(buttons, UI.Button {
            text = "读 取 存 档",
            fontSize = 14,
            backgroundColor = {0, 0, 0, 0},
            fontColor = T.TextSecondary,
            borderRadius = T.ButtonRadius,
            borderWidth = 1,
            borderColor = T.Border,
            paddingHorizontal = 36,
            width = 220,
            height = 40,
            onClick = function()
                local SS = require("screens/SettingsScreen")
                SS._activeTab = 1
                navigate("settings")
            end,
        })
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = T.BgDark,
        gap = 8,
        children = {
            -- 装饰顶线
            UI.Panel {
                width = 80,
                height = 3,
                backgroundColor = T.Accent,
                borderRadius = 2,
                marginBottom = 12,
            },

            -- 主标题
            UI.Label {
                text = "地 产 风 云",
                fontSize = 36,
                fontColor = T.Accent,
                textAlign = "center",
            },

            -- 副标题
            UI.Label {
                text = "完全模拟现实",
                fontSize = 14,
                fontColor = T.TextSecondary,
                textAlign = "center",
                marginBottom = 4,
            },

            -- 装饰底线
            UI.Panel {
                width = 60,
                height = 2,
                backgroundColor = T.Border,
                borderRadius = 1,
                marginBottom = 30,
            },

            -- 按钮区域
            UI.Panel {
                alignItems = "center",
                gap = 6,
                children = buttons,
            },

            -- 底部区域：更新日志按钮 + 版本信息
            UI.Panel {
                alignItems = "center",
                gap = 10,
                marginTop = 18,
                children = {
                    -- 更新日志按钮
                    UI.Button {
                        text = "更新日志",
                        fontSize = 12,
                        backgroundColor = { 0, 0, 0, 0 },
                        fontColor = T.Primary,
                        borderRadius = 6,
                        borderWidth = 1,
                        borderColor = T.Primary,
                        paddingHorizontal = 16,
                        height = 32,
                        onClick = function()
                            navigate("changelog")
                        end,
                    },
                    -- 版本信息
                    UI.Label {
                        text = "v1.0  |  房地产开发商经营策略模拟",
                        fontSize = T.FontCaption,
                        fontColor = T.TextMuted,
                        textAlign = "center",
                    },
                },
            },
        }
    }
end

return M
