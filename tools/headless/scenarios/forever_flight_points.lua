-- Flight Point Reminder (CludesUIForeverEssentials_FlightPoints.lua): a town
-- with an undiscovered point reminds you; leaving it, the zone-entry hold
-- shows it for 10 seconds; an unsure point asks you to open a flight
-- master's map; the taxi map saves what you know; talking to the flight
-- master marks theirs; combat hides it.
local CUI = rawget(_G, "CludesUI")
local FP = CUI._FlightPoints
OUT:write("== flight points " .. tostring(FP ~= nil) .. "\n")
if not FP then return end

local T = Enum.UIMapType
local maps = {
    [1413] = { mapID = 1413, mapType = T.Zone, parentMapID = 1414, name = "The Barrens" },
    [1414] = { mapID = 1414, mapType = T.Continent, parentMapID = 947, name = "Kalimdor" },
    [947] = { mapID = 947, mapType = T.World, parentMapID = 0, name = "Azeroth" },
}
local pos = { x = 0.5, y = 0.5 }
local nodes = {
    { nodeID = 80, name = "Crossroads, The Barrens", faction = Enum.FlightPathFaction.Horde, position = { x = 0.52, y = 0.5 }, isUndiscovered = true },
    { nodeID = 77, name = "Ratchet, The Barrens", faction = Enum.FlightPathFaction.Neutral, position = { x = 0.9, y = 0.9 }, isUndiscovered = false },
}
C_Map.GetBestMapForUnit = function() return 1413 end
C_Map.GetMapInfo = function(id) return maps[id] end
C_Map.GetPlayerMapPosition = function() return { x = pos.x, y = pos.y, GetXY = function(v) return v.x, v.y end } end
C_Map.GetWorldPosFromMapPos = function(_, p) return 1, { x = p.x * 1000, y = p.y * 1000 } end
C_Map.GetMapPosFromWorldPos = function(_, w) return 1, { x = w.x / 1000, y = w.y / 1000 } end
C_Map.GetMapInfoAtPosition = function() return maps[1413] end
C_TaxiMap.GetTaxiNodesForMap = function(id) return id == 1413 and nodes or {} end
C_TaxiMap.GetAllTaxiNodes = function()
    return { { nodeID = 80, state = Enum.FlightPathState.Unreachable }, { nodeID = 77, state = Enum.FlightPathState.Reachable } }
end
GetTaxiMapID = function() return 1414 end
UnitFactionGroup = function() return "Horde" end
UnitOnTaxi = function() return false end
GetSubZoneText = function() return "" end
UnitAffectingCombat = function() return false end
GetFileIDFromPath = function() return 136000 end
C_GossipInfo.GetOptions = function() return { { icon = 136000, name = "Show me where I can fly." } } end

FP.Cfg().enabled = true
FP.Apply()
local card = _G.CludesUIFlightPointReminder
local function State(tag)
    OUT:write(("== %s: %s %s\n"):format(tag, card:IsShown() and "shown" or "hidden", card:IsShown() and tostring(card.text:GetText()) or ""))
end
local function Move(x, y)
    pos.x, pos.y = x, y
    HARNESS_FIRE_EVENT("PLAYER_STOPPED_MOVING")
end
local function Wait(secs) for _ = 1, secs do HARNESS_ADVANCE(1) end end

State("in the Crossroads (20 yards)")
Move(0.2, 0.2)
State("left town, zone-entry hold")
Wait(11)
Move(0.21, 0.2)
State("11s later, far from both")
Move(0.9, 0.9)
State("at Ratchet (unsure: map not seen)")
HARNESS_FIRE_EVENT("TAXIMAP_OPENED")
State("taxi map opened at Ratchet (known there)")
Move(0.51, 0.5)
State("back at the Crossroads (seen, not known)")
HARNESS_FIRE_EVENT("PLAYER_REGEN_DISABLED")
State("in combat")
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
State("combat over")
HARNESS_FIRE_EVENT("GOSSIP_SHOW")
State("spoke to the Crossroads flight master")
local saved = CludesUIDB.flightPointsKnown
local _, mine = next(saved)
OUT:write(("== saved: 80=%s 77=%s seen1414=%s\n"):format(tostring(mine[80]), tostring(mine[77]), tostring(mine.seenMaps and mine.seenMaps[1414])))
FP.Cfg().enabled = false
FP.Apply()
State("off")

-- The options page: Forever Tools > Travel ends with the reminder's section.
CUI:SelectModule("CludesUIForeverEssentials")
CUI:SelectPage("Travel")
local found = {}
local function Walk(f, d)
    if d > 14 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        local t = r.GetText and r:GetText()
        if t == "FLIGHT POINT REMINDER" or t == "Flight Point Reminder" then found[#found + 1] = t end
    end
    for _, ch in ipairs({ f:GetChildren() }) do Walk(ch, d + 1) end
end
Walk(CUI._scrollFrame, 0)
OUT:write("== page: " .. table.concat(found, " | ") .. "\n")
