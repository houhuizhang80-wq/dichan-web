local UI = require("urhox-libs/UI")
local GD = require("GameData")
local InternationalScreen = require("screens/InternationalScreen")

local function run()
    UI.Init({theme = "default-dark", scale = UI.Scale.DEFAULT})
    GD.group = GD.group or {}
    GD.group.active = true
    GD.group.cash = math.max(100000, tonumber(GD.group.cash) or 0)
    local INS = GD.InternationalSystem
    INS.EnsureFields(GD)
    if not GD.international.division.active then assert(INS.RegisterDivision(GD, 5000)) end
    GD.international.dueDiligence.us = {countryId = "us", status = "completed", remainMonths = 0}
    for tab = 1, 4 do
        InternationalScreen._activeTab = tab
        local root = InternationalScreen.Create(function() end)
        assert(root ~= nil, "tab " .. tostring(tab) .. " root nil")
        UI.SetRoot(root, true)
        UI.Layout()
        print("[INTERNATIONAL-UI-TEST] tab=" .. tostring(tab) .. " PASS")
    end
    UI.Shutdown()
    print("[INTERNATIONAL-UI-TEST] PASS tabs=4")
end

function Start()
    local ok, err = pcall(run)
    if not ok then
        print("[INTERNATIONAL-UI-TEST] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, tostring(err))
    end
    engine:Exit()
end
