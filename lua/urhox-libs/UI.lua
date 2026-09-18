-- ============================================================================
-- web/urhox-libs/UI.lua —— 自研声明式 UI 库的网页实现（阶段 0）
--
-- 设计要点（对照原引擎 urhox-libs/UI 的调用点反推）：
--   1. 每个控件既是「可调用表」（UI.Panel{...}），又保留 .Init / .SetText 钩子，
--      因为 Components.lua 会猴补丁覆盖 UI.Label.Init / UI.Label.SetText。
--   2. 构建期把 props 里的 function 抽成 {__cb = id} 并登记到「待生效」回调表；
--      UI.SetRoot 时把待生效表提升为当前表，旧表整体丢弃（无泄漏、无跨屏串号）。
--   3. UI 树在 Lua 侧一次性序列化成 JSON 字符串交给宿主渲染，
--      避免逐节点跨语言 FFI 开销。
--   4. 每个节点分配 __uid，宿主写到 data-uid 上，
--      供 SetText / GetScroll / SetScrollDirect 精确定位（不必依赖业务 id）。
-- ============================================================================

local json = require("web/json")

local UI = {}

UI.Scale = { DEFAULT = 1 }

-- 子节点收集策略："max" = 扫描全部正整数键（跳过 nil），"len" = 仅用 #children。
-- 工程里有 114 处 `... or nil,` 的列表中间空洞写法，"max" 能保证不丢内容。
UI.__childrenMode = "max"

-- ---------------------------------------------------------------------------
-- 回调登记
-- ---------------------------------------------------------------------------
local cbSeq = 0
local currentCbs, pendingCbs = {}, {}

local function registerCallback(fn, node)
    cbSeq = cbSeq + 1
    pendingCbs[cbSeq] = { fn = fn, node = node }
    return { __cb = cbSeq }
end

local function packValue(v, node)
    local t = type(v)
    if t == "function" then return registerCallback(v, node) end
    if t == "table" then
        local out = {}
        for k, val in pairs(v) do out[k] = packValue(val, node) end
        return out
    end
    return v
end

-- ---------------------------------------------------------------------------
-- 子节点收集
-- ---------------------------------------------------------------------------
local function collectChildren(kids)
    if type(kids) ~= "table" then return nil end

    local limit = #kids
    if UI.__childrenMode == "max" then
        for k in pairs(kids) do
            if type(k) == "number" and k % 1 == 0 and k > limit then limit = k end
        end
    end
    if limit == 0 then return nil end

    local out
    for i = 1, limit do
        local c = kids[i]
        if type(c) == "table" then
            out = out or {}
            out[#out + 1] = c
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 节点
-- ---------------------------------------------------------------------------
local NodeMT = {}
NodeMT.__index = NodeMT

function NodeMT.FindById(self, id)
    return UI.__findProxy(id)
end

-- ---------------------------------------------------------------------------
-- 控件工厂
-- ---------------------------------------------------------------------------
local function makeWidget(kind)
    local W = {}
    W._className = kind

    -- 兼容 Components.lua 的猴补丁：labelInit(self, props) 中 self 是控件表本身
    W.Init = function(_, props)
        return W(props)
    end

    -- 兼容 node:SetText(v)（self 为节点）
    W.SetText = function(self, text)
        UI.__setText(self, text)
    end

    setmetatable(W, {
        __call = function(_, props)
            props = props or {}
            local node = setmetatable({ __type = kind, _className = kind }, NodeMT)

            for k, v in pairs(props) do
                if k ~= "children" then node[k] = packValue(v, node) end
            end

            local kids = collectChildren(props.children)
            if kids then node.children = kids end

            return node
        end,
    })

    return W
end

UI.Panel      = makeWidget("Panel")
UI.Layout     = makeWidget("Layout")
UI.Label      = makeWidget("Label")
UI.Button     = makeWidget("Button")
UI.TextField  = makeWidget("TextField")
UI.ScrollView = makeWidget("ScrollView")
UI.Checkbox   = makeWidget("Checkbox")
UI.Slider     = makeWidget("Slider")

-- ---------------------------------------------------------------------------
-- 动态文本 / 滚动
-- ---------------------------------------------------------------------------
function UI.__setText(node, text)
    if type(node) ~= "table" then return end
    text = tostring(text)
    node.text = text
    local uid = node.__uid
    if uid then WebBridge.setText(uid, text) end
end

function UI.__findProxy(id)
    local proxy = { _id = id, _className = "Proxy", state = { velocityX = 0, velocityY = 0 } }

    function proxy:GetScroll()
        local r = WebBridge.getScroll(self._id)
        if type(r) == "table" then return r.x or 0, r.y or 0 end
        return 0, 0
    end

    function proxy:SetScrollDirect(x, y)
        WebBridge.setScroll(self._id, x or 0, y or 0)
    end

    function proxy:SetText(text)
        WebBridge.setTextById(self._id, tostring(text))
    end

    return proxy
end

-- ---------------------------------------------------------------------------
-- 根节点 / 生命周期
-- ---------------------------------------------------------------------------
local root_ = nil
local uidSeq = 0

local function assignUids(node)
    uidSeq = uidSeq + 1
    node.__uid = uidSeq
    local kids = node.children
    if kids then
        for i = 1, #kids do assignUids(kids[i]) end
    end
end

function UI.Init(props)
    props = props or {}
    local theme = props.theme
    if not theme then return end

    -- AppTheme 只声明了 primary/secondary/success/warning/danger 等令牌，
    -- 工程自己的 UITheme 里还有 Accent（暖金）等色板；Button 的 variant 推导需要它们。
    local okTheme, ProjectTheme = pcall(require, "UITheme")
    if okTheme and type(ProjectTheme) == "table" then
        local colors = {}
        for k, v in pairs(theme.colors or {}) do colors[k] = v end
        local aliases = {
            accent = "Accent", accentLight = "AccentLight", accentDark = "AccentDark",
            primary = "Primary", primaryDeep = "PrimaryDark", primarySoft = "PrimaryLight",
            success = "Success", warning = "Warning", danger = "Danger",
            error = "Danger", info = "Info",
        }
        for token, luaKey in pairs(aliases) do
            if colors[token] == nil and ProjectTheme[luaKey] ~= nil then
                colors[token] = ProjectTheme[luaKey]
            end
        end
        local copy = {}
        for k, v in pairs(theme) do copy[k] = v end
        copy.colors = colors
        theme = copy
    end

    local ok, encoded = pcall(json.encode, theme)
    if ok then WebBridge.setTheme(encoded) end
end

function UI.Shutdown() end

function UI.SetRoot(node, _fullRebuild)
    root_ = node
    if not node then return end

    uidSeq = 0
    assignUids(node)

    local ok, encoded = pcall(json.encode, node)
    if not ok then
        WebBridge.log("[UI] UI 树序列化失败: " .. tostring(encoded))
        return
    end

    -- 本次构建期登记的回调生效；上一屏的回调整体丢弃
    currentCbs, pendingCbs = pendingCbs, {}

    WebBridge.setRoot(encoded)
end

function UI.GetRoot() return root_ end

function UI.GetFocus()
    local cls = WebBridge.getFocusClass()
    if cls then return { _className = cls } end
    return nil
end

-- ---------------------------------------------------------------------------
-- 供宿主回调
-- ---------------------------------------------------------------------------
function UI.__invoke(id, value)
    local entry = currentCbs[id] or pendingCbs[id]
    if not entry then
        WebBridge.log("[UI] 未知回调 id=" .. tostring(id))
        return
    end
    local ok, err = pcall(entry.fn, entry.node, value)
    if not ok then
        WebBridge.log("[UI] 回调执行出错: " .. tostring(err))
    end
end

return UI
