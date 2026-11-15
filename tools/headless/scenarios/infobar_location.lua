-- Info Bar > Location and Coordinates blocks: zone and subzone, subzone off,
-- manual width, no icon, coordinate precision, moving (ticks), standing still,
-- zone events that change nothing, an instance (coords collapse), hover and
-- tooltip, and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local mod = H.mod
local zone, sub = "Dornogal", "The Coreway"
GetRealZoneText = function() return zone end
GetMinimapZoneText = function() return sub end
local pos = { 0.4512, 0.6034 }
local inInstance = false
C_Map.GetBestMapForUnit = function() return 2339 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return pos[1], pos[2] end } end
C_Map.GetMapInfo = function(id) if id == 2339 then return { mapType = 3, parentMapID = 2274 } end return { mapType = 2, name = "Khaz Algar", parentMapID = 0 } end
IsInInstance = function() return inInstance end
C_PvP.GetZonePVPInfo = function() return inInstance and nil or "sanctuary" end

H.Block("location")
local co = mod.AddBlock(H.bar.id, "coords")
co.settings = co.settings or {}
local lo = H.b
H.Show("location")
lo.settings.showSubZone = false
H.Show("location no subzone")
lo.settings.showSubZone = nil
lo.settings.widthMode, lo.settings.maxWidth = "manual", 150
H.Show("location manual width")
lo.settings.widthMode, lo.settings.maxWidth = nil, nil
lo.settings.showIcon = false
H.Show("location no icon")
lo.settings.showIcon = nil
for _, p in ipairs({ 1, 2, 0 }) do
    co.settings.precision = p
    H.Show("coords precision " .. p)
end
H.Count("moving for 2 seconds", function()
    for i = 1, 4 do
        pos[1] = pos[1] + 0.01
        HARNESS_ADVANCE(0.5)
    end
end)
SNAP("location moved", H.Bar())
H.Count("standing still for 2 seconds", function()
    for _ = 1, 4 do HARNESS_ADVANCE(0.5) end
end)
H.Count("zone events, same place", function()
    HARNESS_FIRE_EVENT("ZONE_CHANGED")
    HARNESS_FIRE_EVENT("ZONE_CHANGED_INDOORS")
    HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
end)
sub = "Foundation Hall"
HARNESS_FIRE_EVENT("ZONE_CHANGED")
SNAP("location new subzone", H.Bar())
H.Hover("location hover", 1)
inInstance = true
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
SNAP("location instance", H.Bar())
inInstance = false
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
H.Vertical("location vertical")
