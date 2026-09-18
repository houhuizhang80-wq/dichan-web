-- ============================================================================
-- web/shims.lua —— 引擎/平台全局桩（网页移植版）
-- 覆盖原 Urho3D 系引擎中工程实际用到的全部全局：
--   File / FILE_READ / FILE_WRITE / fileSystem / cjson / graphics /
--   Scene / SubscribeToEvent / SOUND_MUSIC
-- clientCloud 故意不定义：工程内均为 `if not clientCloud then` 保护，nil 即安全降级。
-- ============================================================================

local json = require("web/json")
local WebBridge = assert(_G.WebBridge, "WebBridge 未注入")

-- ---------------------------------------------------------------------------
-- 引擎常量
-- ---------------------------------------------------------------------------
FILE_READ  = 1
FILE_WRITE = 2
SOUND_MUSIC = 1

-- ---------------------------------------------------------------------------
-- cjson（存档用）
-- ---------------------------------------------------------------------------
cjson = {
    encode = json.encode,
    decode = json.decode,
    null = nil,
}

-- ---------------------------------------------------------------------------
-- graphics / Scene / SubscribeToEvent（仅用于接收时间步进，实际由 rAF 驱动）
-- ---------------------------------------------------------------------------
graphics = { windowTitle = "" }

-- Scene 仅作为音频宿主存在，工程只调用 scene_:CreateComponent("Octree")
local SceneObject = {}
SceneObject.__index = SceneObject
function SceneObject:CreateComponent(_) return nil end

function Scene()
    return setmetatable({}, SceneObject)
end

function SubscribeToEvent(eventName, handlerName)
    _G.__engineEventHandlers = _G.__engineEventHandlers or {}
    _G.__engineEventHandlers[eventName] = handlerName
end

-- ---------------------------------------------------------------------------
-- File：原引擎的同步文件句柄。这里落到宿主虚拟文件系统（浏览器 localStorage /
-- Node 本地磁盘），保持 IsOpen/WriteString/ReadString/Close 四个方法不变。
-- ---------------------------------------------------------------------------
local FileHandle = {}
FileHandle.__index = FileHandle

function FileHandle:IsOpen() return self._open == true end

function FileHandle:WriteString(text)
    if not self._open then return false end
    self._buffer = (self._buffer or "") .. tostring(text)
    WebBridge.fsWrite(self._path, self._buffer)
    return true
end

function FileHandle:ReadString()
    return self._content or ""
end

function FileHandle:Close()
    self._open = false
    return true
end

function File(path, mode)
    path = tostring(path)
    local handle = setmetatable({ _path = path, _mode = mode }, FileHandle)
    if mode == FILE_WRITE then
        handle._open = true
        handle._buffer = ""
    else
        local content = WebBridge.fsRead(path)
        handle._content = content
        handle._open = content ~= nil
    end
    return handle
end

-- ---------------------------------------------------------------------------
-- fileSystem
-- ---------------------------------------------------------------------------
fileSystem = {
    CreateDir = function(_, dir) WebBridge.fsMkdir(dir); return true end,
    FileExists = function(_, path) return WebBridge.fsExists(path) == true end,
    Delete = function(_, path) WebBridge.fsDelete(path); return true end,
    Copy = function(_, from, to)
        local content = WebBridge.fsRead(from)
        if content == nil then return false end
        WebBridge.fsWrite(to, content)
        return true
    end,
    Rename = function(_, from, to)
        local content = WebBridge.fsRead(from)
        if content == nil then return false end
        WebBridge.fsWrite(to, content)
        WebBridge.fsDelete(from)
        return true
    end,
}

-- ---------------------------------------------------------------------------
-- collectgarbage：工程使用了 Lua 5.4 的 "incremental" 模式；若运行时不支持则降级
-- ---------------------------------------------------------------------------
local rawCollectGarbage = collectgarbage
collectgarbage = function(cmd, ...)
    if cmd == "incremental" then
        if not pcall(rawCollectGarbage, "incremental", ...) then
            pcall(rawCollectGarbage, "restart")
        end
        return
    end
    local ok, result = pcall(rawCollectGarbage, cmd, ...)
    if not ok then return nil end
    return result
end

-- ---------------------------------------------------------------------------
-- Lua 5.1 / 5.2 兼容层
-- 原引擎的 Lua 方言是 5.1 时代（工程里用了 math.pow），wasmoon 是 5.4，
-- 这里补齐 5.3 被移除的旧接口。实测全工程只用到 math.pow 一个。
-- ---------------------------------------------------------------------------
math.pow = math.pow or function(a, b) return a ^ b end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.mod = math.mod or math.fmod
math.ldexp = math.ldexp or function(m, e) return m * 2.0 ^ e end
math.frexp = math.frexp or function(x)
    if x == 0 then return 0, 0 end
    local e = math.floor(math.log(math.abs(x)) / math.log(2)) + 1
    return x / 2.0 ^ e, e
end

table.getn = table.getn or function(t) return #t end
table.maxn = table.maxn or function(t)
    local max = 0
    for k in pairs(t) do
        if type(k) == "number" and k > max then max = k end
    end
    return max
end

unpack = unpack or table.unpack
loadstring = loadstring or load
string.gfind = string.gfind or string.gmatch

-- ---------------------------------------------------------------------------
-- 其他：os.date 兜底（WASM 版 Lua 若缺 os.date 时使用宿主时间）
-- ---------------------------------------------------------------------------
if not (os and os.date) then
    os = os or {}
    os.date = function(fmt)
        if fmt == "%Y-%m-%d %H:%M:%S" or fmt == nil then
            return WebBridge.nowString()
        end
        return WebBridge.nowString()
    end
end

return true
