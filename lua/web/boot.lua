-- ============================================================================
-- web/boot.lua —— 网页宿主入口
-- 1) 用宿主提供的模块源替换 Lua 的 require（不走引擎资源系统）
-- 2) 安装引擎全局桩
-- 3) 加载并启动 main.lua
-- 4) 暴露 __webTick / __webInvoke 给宿主驱动
-- ============================================================================

local WebBridge = assert(_G.WebBridge, "WebBridge 未注入")

-- ---------------------------------------------------------------------------
-- 模块加载：宿主按「模块名 -> 源码」提供（浏览器 fetch / Node fs）
-- ---------------------------------------------------------------------------
local moduleCache = {}
local rawLoad = load

local function loadModuleSource(name)
    local src = WebBridge.readModule(name)
    if not src then return nil, "找不到模块源: " .. tostring(name) end
    local chunk, err = rawLoad(src, "@" .. name)
    if not chunk then return nil, "语法错误: " .. tostring(err) end
    return chunk(name)
end

_G.require = function(name)
    local hit = moduleCache[name]
    if hit ~= nil then return hit end
    local mod, err = loadModuleSource(name)
    if mod == nil then error("[web] " .. tostring(err or ("模块不存在: " .. name)), 2) end
    moduleCache[name] = mod
    return mod
end

_G.package = {
    loaded = moduleCache,
    preload = {},
    path = "",
    cpath = "",
    config = "/\n;\n?\n!\n-\n",
}

-- ---------------------------------------------------------------------------
-- 引擎全局桩
-- ---------------------------------------------------------------------------
require("web/shims")

-- ---------------------------------------------------------------------------
-- 加载 main.lua
-- ---------------------------------------------------------------------------
local mainSrc = WebBridge.readModule("main")
if not mainSrc then error("[web] 缺少 main.lua", 0) end
local mainChunk, mainErr = rawLoad(mainSrc, "@main.lua")
if not mainChunk then error("[web] main.lua 语法错误: " .. tostring(mainErr), 0) end
mainChunk()

-- ---------------------------------------------------------------------------
-- 启动
-- ---------------------------------------------------------------------------
local okStart, startErr = pcall(Start)
if not okStart then
    WebBridge.log("[web] Start() 出错: " .. tostring(startErr))
end

-- Start() 默认先进更新日志页（showChangelogOnStart_ = true），阶段 0 直接切到开场页
local target = WebBridge.initialScreen and WebBridge.initialScreen() or "start"
local okNav, navErr = pcall(Navigate, target)
if not okNav then
    WebBridge.log("[web] Navigate('" .. tostring(target) .. "') 出错: " .. tostring(navErr))
end

-- ---------------------------------------------------------------------------
-- 宿主回调
-- ---------------------------------------------------------------------------
_G.__webTick = function(dt)
    local handler = _G.HandleUpdate
    if not handler then return end
    handler("Update", {
        TimeStep = {
            GetFloat = function() return dt end,
        },
    })
end

_G.__webInvoke = function(id, value)
    local UI = package.loaded["urhox-libs/UI"]
    if UI and UI.__invoke then UI.__invoke(id, value) end
end

_G.__webNavigate = function(screen)
    local ok, err = pcall(Navigate, screen)
    if not ok then WebBridge.log("[web] Navigate 出错: " .. tostring(err)) end
    return ok
end

_G.__webStats = function()
    local GD = package.loaded["GameData"]
    local n = 0
    for _ in pairs(moduleCache) do n = n + 1 end
    return {
        modules = n,
        gameStarted = GD and GD.gameStarted or false,
        year = GD and GD.year or 0,
        month = GD and GD.month or 0,
    }
end

WebBridge.log("[web] boot 完成，模块数=" .. tostring((function()
    local n = 0
    for _ in pairs(moduleCache) do n = n + 1 end
    return n
end)()))

return true
