-- UITheme.lua - 地产风云 · 明亮现代房地产商业风格
-- 保持既有布局、内容、比例与交互，仅统一背景、字体与视觉色彩令牌。

local Theme = require("urhox-libs/UI/Core/Theme")

local T = {}

-- 基础色板（石材白 + 雾蓝灰：明亮、真实、专业的房地产商务质感）
T.Background    = {238, 242, 246, 255}    -- #EEF2F6 建筑雾灰主背景
T.NeutralBg     = {229, 235, 241, 255}    -- #E5EBF1 分区底衬
T.Card          = {252, 253, 254, 255}    -- #FCFDFE 卡片/弹窗/浮层
T.Divider       = {194, 204, 214, 255}    -- #C2CCD6 建筑线框分割

T.TextPrimary   = {28, 42, 56, 255}       -- #1C2A38 深海军蓝正文
T.TextSecondary = {76, 91, 106, 255}      -- #4C5B6A 标签/说明
T.TextMuted     = {126, 140, 153, 255}    -- #7E8C99 占位/禁用
T.TextDark      = T.TextPrimary
T.TextOnDark    = {248, 250, 252, 255}
T.TextOnPrimary = {248, 250, 252, 255}
T.TextOnSelected = {248, 250, 252, 255}

-- 建筑蓝主色：稳健、专业；香槟金仅作为行业质感强调
T.Primary       = {38, 84, 124, 255}      -- #26547C 建筑蓝
T.PrimaryLight  = {220, 232, 241, 255}    -- #DCE8F1 选中底衬
T.PrimaryDark   = {27, 63, 96, 255}       -- #1B3F60 深建筑蓝
T.PrimaryBorder = {80, 119, 151, 255}     -- #507797
T.Accent        = {145, 102, 35, 255}     -- #916623 深香槟金，兼顾白底文字可读性
T.AccentLight   = {246, 238, 222, 255}
T.AccentDark    = {111, 75, 20, 255}
T.AccentBg      = T.AccentLight

T.Success       = {47, 124, 91, 255}      -- 稳健资产绿
T.SuccessBg     = {225, 241, 233, 255}

T.Warning       = {178, 116, 28, 255}     -- 地产暖金警示
T.WarningBg     = {250, 238, 215, 255}
T.Danger        = {181, 68, 68, 255}      -- 克制风险红
T.DangerBg      = {249, 229, 229, 255}

T.Info          = {49, 108, 148, 255}     -- 城市信息蓝
T.InfoBg        = {222, 237, 247, 255}

-- 背景与表面别名（兼容既有页面）
T.BgDark        = T.Background             -- 兼容旧页面命名，统一使用明亮建筑雾灰背景
T.BgMain        = T.Background
T.BgCard        = T.Card
T.BgCardHover   = {241, 246, 250, 255}
T.BgInput       = {255, 255, 255, 255}
T.BgSidebar     = {222, 229, 236, 255}
T.BgElevated    = {245, 248, 251, 255}
T.CardBackground = T.Card
T.Surface       = {244, 247, 250, 255}
T.BgBase        = T.NeutralBg
T.DisabledBg    = {226, 231, 236, 255}
T.TrackBg       = {214, 222, 230, 255}

-- 边框/分割线
T.Border        = T.Divider
T.BorderLight   = {161, 174, 187, 255}
T.BorderAccent  = T.PrimaryBorder
T.FocusBorder   = T.Primary
T.Transparent   = {0, 0, 0, 0}
T.Overlay       = {23, 35, 47, 112}

-- 非活跃 Tab/选项按钮
T.TabInactiveBg     = {241, 245, 248, 255}
T.TabInactiveFont   = T.TextSecondary
T.TabInactiveBorder = T.Border

-- 状态标签配色规则
T.StatusColors = {
    progress = {bg = T.PrimaryLight, fg = T.Primary, dot = T.Primary},
    done     = {bg = T.SuccessBg, fg = T.Success, dot = T.Success},
    planned  = {bg = T.NeutralBg, fg = T.TextSecondary, dot = T.TextMuted},
    alert    = {bg = T.DangerBg, fg = T.Danger, dot = T.Danger},
}

-- 品级/资质等级配色
T.GradeDraft = T.TextMuted
T.Grade3     = T.Info
T.Grade2     = T.Primary
T.Grade1     = T.Success
T.GradeTop   = T.Warning
T.GradeColors = {
    ["暂定级"] = T.GradeDraft,
    ["三级"] = T.Grade3,
    ["二级"] = T.Grade2,
    ["一级"] = T.Grade1,
    ["特级"] = T.GradeTop,
}

function T.GetGradeColor(name)
    return T.GradeColors[name] or T.TextSecondary
end

-- 真实建筑空间光影：高频卡片/按钮避免每帧模糊卷积，依靠边框与轻硬阴影保持层次。
-- Popup/Modal 数量少，保留较小扩散半径突出浮层关系。
T.ShadowCard = {
    { x = 0, y = 2, blur = 0, color = {41, 59, 76, 24} },
}
T.ShadowPopup = {
    { x = 0, y = 5, blur = 8, color = {36, 53, 69, 42} },
}
T.ShadowModal = {
    { x = 0, y = 7, blur = 12, color = {27, 42, 56, 54} },
}
T.ShadowButton = false

-- 尺寸常量
T.TopBarHeight    = 115
T.BottomNavHeight = 110
T.CardRadius      = 0
T.ButtonRadius    = 0
T.InputRadius     = 0
T.CardPadding     = 16
T.PagePadding     = 16
T.Gap             = 12
T.DividerWidth    = 2

-- 字体使用项目现有的 Noto Sans SC 商务无衬线字体，保持文字比例与阅读密度不变
T.FontTitle       = 20
T.FontSubtitle    = 16
T.FontBody        = 15
T.FontSmall       = 13
T.FontCaption     = 12
T.FontHuge        = 28

-- 底部导航项：两行五列，保留原有8项并增加集团、国际一级入口
T.NavItems = {
    {id = "dashboard",  label = "总览",  icon = "■"},
    {id = "city",       label = "城市",  icon = "▲"},
    {id = "invest",     label = "投资",  icon = "△"},
    {id = "asset",      label = "运营",  icon = "★"},
    {id = "capital",    label = "资本",  icon = "◎"},
    {id = "group",      label = "集团",  icon = "◆"},
    {id = "international", label = "国际", icon = "◇"},
    {id = "personal",   label = "个人",  icon = "○"},
    {id = "governance", label = "治理",  icon = "☆"},
    {id = "settings",   label = "设置",  icon = "⚙"},
}

-- 项目级现代都市主题：兜底覆盖没有显式传色的内置 UI 控件
T.AppTheme = Theme.ExtendTheme(Theme.defaultTheme, {
    fonts = {
        { family = "sans", weights = {
            normal = "Fonts/NotoSansSC-Regular.ttf",
            bold = "Fonts/NotoSansSC-Bold.ttf",
        }},
        { family = "mono", weights = {
            normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf",
        }},
    },
    colors = {
        primary = T.Primary,
        primaryHover = {50, 100, 142, 255},
        primaryPressed = T.PrimaryDark,
        primaryDeep = T.PrimaryDark,
        primarySoft = T.PrimaryLight,
        primaryShadow = {31, 55, 76, 38},
        secondary = {104, 123, 139, 255},
        secondaryHover = {82, 104, 122, 255},
        secondaryPressed = {65, 84, 101, 255},
        secondaryDeep = {65, 84, 101, 255},
        background = T.Background,
        surface = T.Card,
        surfaceAlt = T.Surface,
        surfaceHover = T.BgCardHover,
        surfaceRaised = T.Card,
        text = T.TextPrimary,
        textSecondary = T.TextSecondary,
        textMuted = T.TextMuted,
        textPlaceholder = T.TextMuted,
        textDisabled = T.TextMuted,
        textInverse = T.TextOnPrimary,
        border = T.Border,
        borderStrong = T.BorderLight,
        borderFocus = T.Primary,
        divider = T.Border,
        disabled = T.DisabledBg,
        disabledBorder = T.Border,
        disabledText = T.TextMuted,
        success = T.Success,
        successHover = {58, 143, 106, 255},
        successPressed = {36, 100, 73, 255},
        successShadow = {31, 72, 55, 32},
        warning = T.Warning,
        warningHover = {197, 136, 43, 255},
        warningPressed = {145, 91, 18, 255},
        error = T.Danger,
        errorHover = {199, 84, 84, 255},
        errorPressed = {151, 51, 51, 255},
        danger = T.Danger,
        dangerHover = {199, 84, 84, 255},
        dangerPressed = {151, 51, 51, 255},
        overlay = T.Overlay,
        transparent = T.Transparent,
        hover = {38, 84, 124, 22},
        info = T.Info,
        infoSoft = T.InfoBg,
        successSoft = T.SuccessBg,
        warningSoft = T.WarningBg,
        dangerSoft = T.DangerBg,
        surfaceTooltip = {31, 49, 65, 245},
        borderTooltip = T.Border,
    },
    radius = {
        none = 0,
        xs = 0,
        sm = 0,
        md = 0,
        lg = 0,
        xl = 0,
        full = 0,
    },
    componentDefaults = {
        borderRadius = 0,
    },
    components = {
        Button = {
            borderRadius = 0,
            height = 44,
            fontSize = 12,
            fontWeight = "bold",
            borderWidth = 2,
            borderColor = T.PrimaryBorder,
            paddingHorizontal = 16,
            boxShadow = T.ShadowButton,
        },
        TextField = {
            borderWidth = 2,
            borderRadius = 0,
            borderColor = T.Border,
            hoverBorderColor = T.Primary,
            focusBorderColor = T.Primary,
            backgroundColor = T.BgInput,
            fontSize = 11,
            height = 40,
            disabledBorderColor = T.Border,
        },
        Card = {
            borderRadius = 0,
            borderWidth = 2,
            borderColor = T.Border,
            boxShadow = T.ShadowCard,
        },
        Modal = {
            borderWidth = 2,
            borderRadius = 0,
            boxShadow = T.ShadowModal,
            headerBgColor = T.NeutralBg,
            headerBorderWidth = 2,
            footerBorderWidth = 2,
            contentPadding = {16, 20, 16, 20},
            contentGap = 16,
            titleFontWeight = "bold",
        },
        Table = {
            headerBgColor = T.BgCardHover,
            headerTextColor = T.Primary,
            cellTextColor = T.TextPrimary,
            rowOddBgColor = T.Card,
            rowEvenBgColor = {244, 247, 250, 255},
            rowHoverBgColor = {38, 84, 124, 18},
            rowBorderWidth = 2,
            borderWidth = 2,
        },
        Badge = { borderRadius = 0, fontWeight = "bold", borderWidth = 1 },
        ProgressBar = {
            height = 14,
            borderWidth = 2,
            fillColor = T.Primary,
            backgroundColor = T.TrackBg,
        },
        Slider = {
            trackBgColor = T.TrackBg,
            trackFillColor = T.Primary,
            thumbColor = T.Primary,
            thumbBorderColor = T.PrimaryBorder,
            thumbBorderWidth = 2,
        },
        Tabs = {
            borderWidth = 2,
            activeBorderColor = T.Primary,
            inactiveTextColor = T.TextSecondary,
            activeFontWeight = "bold",
            tabGap = 8,
        },
        Dropdown = {
            borderWidth = 2,
            boxShadow = T.ShadowPopup,
            arrowColor = T.Primary,
            itemHoverBgColor = {38, 84, 124, 22},
            itemHoverTextColor = T.Primary,
        },
        Toast = {
            borderWidth = 2,
            boxShadow = T.ShadowPopup,
            showIcon = false,
        },
    },
})

return T
