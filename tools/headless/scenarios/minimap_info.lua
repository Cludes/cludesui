-- Minimap > clock, location and coordinates text: clock inside / on the edge
-- / hidden, 12 and 24 hour, AM/PM in the description colour, the location
-- with reactive colour and subzone, coordinates (precision, always shown),
-- the tickers standing still and moving, and zone events. Counts text writes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIMinimap
local Inner = mod._internals
local SKIN = Inner.EBS
local p = SKIN.db.profile.minimap

local clock = { 14, 5 }
GetGameTime = function() return clock[1], clock[2] end
local cvars = { timeMgrUseMilitaryTime = "0", timeMgrUseLocalTime = "0" }
GetCVar = function(k) return cvars[k] or "1" end
local zone, sub = "Dornogal", "The Coreway"
GetZoneText = function() return zone end
GetSubZoneText = function() return sub end
local pvp = "sanctuary"
C_PvP.GetZonePVPInfo = function() return pvp end
local pos = { 0.4512, 0.6034 }
C_Map.GetBestMapForUnit = function() return 2339 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return pos[1], pos[2] end } end

WRITES = 0
local function Counted(frame)
    if not frame or frame.__counted then return end
    frame.__counted = true
    for _, m in ipairs({ "SetText", "SetFormattedText" }) do
        local f = frame[m]
        frame[m] = function(...)
            WRITES = WRITES + 1
            return f(...)
        end
    end
end
local function Snap(label)
    for _, name in ipairs({ "_CUBS_ClockBg", "_CUBS_LocationBg", "_CUBS_CoordFrame" }) do
        local f = rawget(_G, name)
        if f then SNAP(label .. " " .. name, f) else OUT:write("== " .. label .. " " .. name .. " (none)\n") end
    end
end
local function Apply(label)
    Inner.ApplyMinimap()
    Counted(rawget(_G, "_CUBS_CoordFrame"))
    Snap(label)
end

p.clockMode, p.locationMode, p.coordsMode = "inside", "inside", "always"
Apply("default")
p.clockMode = "edge"
p.clockPosition = "bottomRight"
Apply("clock edge")
cvars.timeMgrUseMilitaryTime = "1"
Inner.RefreshClockCVars()
Inner.UpdateClock()
Snap("clock 24h")
cvars.timeMgrUseMilitaryTime = "0"
Inner.RefreshClockCVars()
p.fpsColorClockAMPM, p.fpsColor = true, { r = 1, g = 0.5, b = 0 }
Inner.UpdateClock()
Snap("clock ampm coloured")
p.fpsUseAccent = true
Inner.UpdateClock()
Snap("clock ampm accent")
p.fpsColorClockAMPM, p.fpsUseAccent = nil, nil
clock = { 0, 7 }
Inner.UpdateClock()
Snap("clock midnight")
clock = { 14, 5 }

p.zoneReactiveColor = true
Inner.UpdateLocation()
Snap("location reactive")
pvp = "hostile"
Inner.UpdateLocation()
Snap("location hostile")
p.zoneShowSubZone = true
Inner.UpdateLocation()
Snap("location subzone")
p.locationMode = "edge"
p.locationPosition = "top"
Apply("location edge")

for _, prec in ipairs({ 0, 2, 1 }) do
    p.coordPrecision = prec
    Inner.UpdateCoords()
    Snap("coords precision " .. prec)
end
local before = WRITES
for _ = 1, 6 do HARNESS_ADVANCE(0.5) end
OUT:write("== coordinate writes standing still for 3 seconds: ", WRITES - before, "\n")
before = WRITES
for _ = 1, 4 do
    pos[1] = pos[1] + 0.001
    HARNESS_ADVANCE(0.5)
end
OUT:write("== coordinate writes moving for 2 seconds: ", WRITES - before, "\n")
Snap("coords moved")
C_Map.GetBestMapForUnit = function() return nil end
Inner.UpdateCoords()
Snap("coords no map")
C_Map.GetBestMapForUnit = function() return 2339 end
Inner.UpdateCoords()

zone, sub = "Isle of Dorn", ""
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
Snap("location new zone")
p.clockMode, p.locationMode, p.coordsMode = "none", "none", "never"
Apply("all hidden")
p.clockMode, p.locationMode, p.coordsMode = "inside", "inside", "always"
p.clockPosition, p.locationPosition, p.coordPrecision, p.zoneReactiveColor, p.zoneShowSubZone = nil, nil, nil, nil, nil
Apply("restored")
