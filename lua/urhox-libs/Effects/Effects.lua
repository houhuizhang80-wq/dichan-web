-- ============================================================================
-- web/urhox-libs/Effects/Effects.lua —— 引擎特效/音频库的最小替代
-- 工程只用到 Effects.PlaySoundLooped（背景音乐）。
-- 返回的 handle.source 支持 `source.gain = x` 动态调音量（main.lua 的 SetMusicVolume）。
-- ============================================================================

local Effects = {}

function Effects.PlaySoundLooped(scene, path, opts)
    local gain = (opts and opts.gain) or 1
    local id = WebBridge.playMusic(path, gain)

    -- 用 __newindex 把 gain 的赋值转发给宿主音频元素
    local backing = {}
    local source = setmetatable({}, {
        __index = backing,
        __newindex = function(_, k, v)
            backing[k] = v
            if k == "gain" then WebBridge.setMusicGain(v) end
        end,
    })
    source.gain = gain
    return { source = source, id = id }
end

return Effects
