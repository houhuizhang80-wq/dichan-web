-- ============================================================================
-- web/urhox-libs/UI/Core/Theme.lua —— 引擎内置主题库的最小替代
-- 工程只用到 Theme.ExtendTheme(Theme.defaultTheme, {...})，因此只需深合并。
-- ============================================================================

local Theme = {}

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[k] = deepCopy(val, seen) end
    return out
end

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            deepMerge(dst[k], v)
        else
            dst[k] = deepCopy(v)
        end
    end
    return dst
end

-- 内置默认主题（仅保留工程会读取的字段；AppTheme 会整体覆盖）
Theme.defaultTheme = {
    fonts = {},
    colors = {
        primary = { 60, 90, 130, 255 },
        background = { 255, 255, 255, 255 },
        surface = { 250, 250, 250, 255 },
        text = { 20, 20, 20, 255 },
        border = { 200, 200, 200, 255 },
        transparent = { 0, 0, 0, 0 },
    },
    radius = { none = 0, xs = 0, sm = 0, md = 0, lg = 0, xl = 0, full = 0 },
    components = {
        Button = {
            height = 44,
            fontSize = 12,
            borderWidth = 1,
            borderColor = { 150, 150, 150, 255 },
            paddingHorizontal = 16,
        },
        TextField = {
            height = 40,
            fontSize = 11,
            borderWidth = 1,
            borderColor = { 200, 200, 200, 255 },
            backgroundColor = { 255, 255, 255, 255 },
        },
        Badge = { fontWeight = "bold", borderWidth = 1 },
        ProgressBar = { height = 14, borderWidth = 2 },
    },
    componentDefaults = {},
}

function Theme.ExtendTheme(base, override)
    local out = deepCopy(base or Theme.defaultTheme)
    if override then deepMerge(out, override) end
    return out
end

return Theme
