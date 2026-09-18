-- ============================================================================
-- web/json.lua —— 纯 Lua JSON 实现（网页移植版，替代引擎内置 cjson）
-- 同时被 web/shims.lua 的 cjson 与 urhox-libs/UI 的 UI 树序列化复用。
-- ============================================================================

local json = {}

-- ---------------------------------------------------------------------------
-- UTF-8 编码（供 \uXXXX 转义还原使用）
-- ---------------------------------------------------------------------------
local function utf8Encode(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + math.floor(cp / 0x1000) % 0x40,
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
end

-- ---------------------------------------------------------------------------
-- 编码
-- ---------------------------------------------------------------------------
local function encodeString(s)
    -- 快路径：无控制字符/引号/反斜杠时原样输出
    if not s:find('[%c"\\]') then return '"' .. s .. '"' end
    return '"' .. s:gsub('.', function(c)
        local b = string.byte(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        if b < 32 then return string.format('\\u%04x', b) end
        return c
    end) .. '"'
end

-- 判断是否为纯数组（键为 1..n 连续整数）；空表按对象处理，与 cjson 一致
local function arrayLen(t)
    local count, max = 0, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return nil end
        count = count + 1
        if k > max then max = k end
    end
    if count == 0 then return nil end
    if count ~= max then return nil end
    return max
end

local encodeValue

encodeValue = function(v, seen)
    if v == nil then return "null" end
    local t = type(v)
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.type and math.type(v) == "integer" then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if t == "string" then return encodeString(v) end
    if t ~= "table" then return "null" end

    if seen[v] then error("json.encode: 检测到循环引用", 0) end
    seen[v] = true

    local out
    local n = arrayLen(v)
    if n then
        out = {}
        for i = 1, n do out[i] = encodeValue(v[i], seen) end
        out = "[" .. table.concat(out, ",") .. "]"
    else
        out = {}
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then
                out[#out + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(val, seen)
            end
        end
        out = "{" .. table.concat(out, ",") .. "}"
    end

    seen[v] = nil
    return out
end

function json.encode(v)
    return encodeValue(v, {})
end

-- ---------------------------------------------------------------------------
-- 解码
-- ---------------------------------------------------------------------------
local escapes = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

local function decodeError(s, i, msg)
    local from = math.max(1, i - 20)
    error(string.format("json.decode: %s（位置 %d，附近: %q）", msg, i, s:sub(from, i + 20)), 0)
end

local function skipWs(s, i)
    local _, e = s:find("^[ \t\r\n]*", i)
    return (e or (i - 1)) + 1
end

local function parseString(s, i)
    local buf, j = {}, i + 1
    while true do
        local stop = s:find('["\\]', j)
        if not stop then decodeError(s, j, "字符串未闭合") end
        if stop > j then buf[#buf + 1] = s:sub(j, stop - 1) end
        local c = s:sub(stop, stop)
        if c == '"' then return table.concat(buf), stop + 1 end

        local esc = s:sub(stop + 1, stop + 1)
        if esc == "u" then
            local cp = tonumber(s:sub(stop + 2, stop + 5), 16)
            if not cp then decodeError(s, stop, "非法 \\u 转义") end
            j = stop + 6
            if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
                local lo = tonumber(s:sub(j + 2, j + 5), 16)
                if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    j = j + 6
                end
            end
            buf[#buf + 1] = utf8Encode(cp)
        else
            buf[#buf + 1] = escapes[esc] or esc
            j = stop + 2
        end
    end
end

local parseValue

parseValue = function(s, i)
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == "" then decodeError(s, i, "内容意外结束") end

    if c == "{" then
        local obj = {}
        i = skipWs(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            if s:sub(i, i) ~= '"' then decodeError(s, i, "对象的键必须是字符串") end
            local key
            key, i = parseString(s, i)
            i = skipWs(s, i)
            if s:sub(i, i) ~= ":" then decodeError(s, i, "缺少 ':'") end
            local val
            val, i = parseValue(s, i + 1)
            obj[key] = val
            i = skipWs(s, i)
            local d = s:sub(i, i)
            if d == "," then
                i = i + 1
            elseif d == "}" then
                return obj, i + 1
            else
                decodeError(s, i, "对象内缺少 ',' 或 '}'")
            end
        end
    end

    if c == "[" then
        local arr, n = {}, 0
        i = skipWs(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local val
            val, i = parseValue(s, i)
            n = n + 1
            arr[n] = val
            i = skipWs(s, i)
            local d = s:sub(i, i)
            if d == "," then
                i = i + 1
            elseif d == "]" then
                return arr, i + 1
            else
                decodeError(s, i, "数组内缺少 ',' 或 ']'")
            end
        end
    end

    if c == '"' then return parseString(s, i) end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end

    local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    if not num or num == "" then decodeError(s, i, "非法字面量") end
    return tonumber(num), i + #num
end

function json.decode(s)
    if type(s) ~= "string" then error("json.decode: 需要字符串", 0) end
    local v = parseValue(s, 1)
    return v
end

return json
