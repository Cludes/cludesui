-- QoL > /way (loaded with the option on, as it only loads then): the
-- usage line, coordinates in the current zone (every pair format), a map ID,
-- unknown IDs and zones, a zone by name (exact, partial, several matches,
-- same-named maps told apart by parent), a description, several
-- destinations, clear, arrival at a listed pin (and the next one), arrival
-- in combat (held), a hand-placed pin with and without the option, and
-- /way taken by another addon. Records every chat line.
local CUI = rawget(_G, "CludesUI")
LINES = {}
CUI.Print = function(m) LINES[#LINES + 1] = m end
CUI.PrintError = function(m) LINES[#LINES + 1] = "ERR " .. m end
CaseAccentInsensitiveParse = function(s) return s end
strcmputf8i = function(a, b) return a < b and -1 or (a > b and 1 or 0) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
MAP_PIN_HYPERLINK = "Map Pin"
hash_SlashCmdList = {}
Enum.UIMapType.Continent, Enum.UIMapType.Zone, Enum.UIMapType.Dungeon, Enum.UIMapType.Micro = 2, 3, 4, 5
local MAPS = {
    [946] = { mapID = 946, name = "Cosmic", parentMapID = 0, mapType = 0 },
    [2274] = { mapID = 2274, name = "Khaz Algar", parentMapID = 946, mapType = 2 },
    [2339] = { mapID = 2339, name = "Dornogal", parentMapID = 2274, mapType = 3 },
    [2248] = { mapID = 2248, name = "Isle of Dorn", parentMapID = 2274, mapType = 3 },
    [2215] = { mapID = 2215, name = "Hallowfall", parentMapID = 2274, mapType = 3 },
    [3001] = { mapID = 3001, name = "Twin Peak", parentMapID = 2248, mapType = 5 },
    [3002] = { mapID = 3002, name = "Twin Peak", parentMapID = 2215, mapType = 5 },
    [3003] = { mapID = 3003, name = "Twin Peak Upper", parentMapID = 2215, mapType = 5 },
    [3004] = { mapID = 3004, name = "Deep Vault", parentMapID = 2215, mapType = 4 },
}
local noPins = { [3004] = true }
C_Map.GetMapInfo = function(id) return MAPS[id] end
C_Map.GetFallbackWorldMapID = function() return 2274 end
C_Map.GetMapChildrenInfo = function()
    local out = {}
    for id, m in pairs(MAPS) do if id ~= 946 then out[#out + 1] = m end end
    table.sort(out, function(a, b) return a.mapID < b.mapID end)
    return out
end
C_Map.CanSetUserWaypointOnMap = function(id) return not noPins[id] end
local here = 2339
C_Map.GetBestMapForUnit = function() return here end
IsInInstance = function() return false end
local pin
C_Map.HasUserWaypoint = function() return pin ~= nil end
C_Map.GetUserWaypoint = function() return pin end
local player = { x = 0, y = 0 }
player.GetXY = function(self) return self.x, self.y end -- the minimap reads it too
C_Map.GetPlayerMapPosition = function() return player end
C_Map.GetMapWorldSize = function() return 1000, 1000 end
local combat = false
InCombatLockdown = function() return combat end
local deferred = {}
local ns = { CombatQueue = { Defer = function(k, f) deferred[k] = f end } }
CludesUIDB = CludesUIDB or {}
CludesUIDB.waypointCmd = { enabled = true }

local function Load()
    local chunk = assert(loadfile("CludesUIQoL/CludesUIQoL_Waypoint.lua"))
    chunk("CludesUIQoL", ns)
    HARNESS_ADVANCE(0.1)
end
local function Way(label, msg)
    LINES = {}
    SlashCmdList.CUIWAY(msg)
    OUT:write("== ", label, " [", msg, "]\n")
    for _, l in ipairs(LINES) do OUT:write("   ", l, "\n") end
end
local function Arrive(label, map, x, y, px, py)
    pin = map and { uiMapID = map, position = { x = x, y = y } } or nil
    player.x, player.y = px, py
    LINES = {}
    HARNESS_FIRE_EVENT("NAVIGATION_DESTINATION_REACHED")
    OUT:write("== ", label, "\n")
    for _, l in ipairs(LINES) do OUT:write("   ", l, "\n") end
end

Load()
OUT:write("== slash: ", tostring(SLASH_CUIWAY1), " ", tostring(SLASH_CUIWAY2), "\n")
Way("empty", "")
Way("nonsense", "hello there")
Way("dot pair", "45.3 67.8")
Way("comma decimals", "45,3 67,8")
Way("comma separated", "45.3, 67.8")
Way("joined", "45.3,67.8")
Way("out of range", "145 20")
Way("description", "12 34 The big anvil")
Way("map id", "#2248 50 50")
Way("bare map id", "2215 10 90 Arathi camp")
Way("unknown id", "#99 1 2")
Way("huge id", "#12345678 1 2")
Way("no pins on map", "#3004 5 5")
Way("zone exact", "Isle of Dorn 40 40")
Way("zone partial", "hallow 20 30")
Way("zone unknown", "Nowhere 1 1")
Way("zone without pins", "Deep Vault 1 1")
Way("several names", "Twin 5 5")
Way("same-named maps", "Twin Peak 5 5")
Way("several destinations", "10 10 First; #2248 20 20 Second; 30 30")
Way("pasted commands", "10 10 One /way 20 20 Two")
-- Arrival: far away, then at the first, then the second, then the last.
Way("list", "10 10 Alpha; 20 20 Beta; 30 30 Gamma")
Arrive("far away", 2339, 0.10, 0.10, 0.50, 0.50)
Arrive("at alpha", 2339, 0.10, 0.10, 0.101, 0.10)
Arrive("at alpha again", 2339, 0.10, 0.10, 0.10, 0.10)
Arrive("at beta", 2339, 0.20, 0.20, 0.20, 0.20)
combat = true
Arrive("at gamma in combat", 2339, 0.30, 0.30, 0.30, 0.30)
combat = false
LINES = {}
if deferred.waypointArrival then deferred.waypointArrival() end
OUT:write("== after combat\n")
for _, l in ipairs(LINES) do OUT:write("   ", l, "\n") end
Arrive("hand pin, option off", 2339, 0.55, 0.55, 0.55, 0.55)
CludesUIDB.waypointCmd.manualArrival = true
ns.WaypointArrivalSync() -- as the options cog does
Arrive("hand pin, option on", 2339, 0.56, 0.56, 0.56, 0.56)
Arrive("no pin", nil, 0, 0, 0, 0)
Way("clear", "clear")
-- /way already taken by another addon.
SlashCmdList.OTHERWAY = function() end
SLASH_OTHERWAY1 = "/way"
SLASH_CUIWAY2 = nil
Load()
OUT:write("== slash when taken: ", tostring(SLASH_CUIWAY1), " ", tostring(SLASH_CUIWAY2), "\n")
Way("usage names cuiway", "")
