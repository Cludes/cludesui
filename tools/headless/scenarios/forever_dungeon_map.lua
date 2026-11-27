-- Dungeon Map (CludesUIForeverEssentials_DungeonMap.lua, Forever): entering a
-- dungeon opens its map and route; kills move the route on.
local CUI = rawget(_G, "CludesUI")
local DM = CUI._DungeonMap
if not DM then
    OUT:write("== no Dungeon Map on this client\n")
    return
end
IsInInstance = function() return true, "party" end
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
HARNESS_ADVANCE(0.2)
local function Report(label)
    local d, route, nextStop = DM.State()
    local numbered = 0
    for _, e in ipairs(route) do if e.number then numbered = numbered + 1 end end
    local w = rawget(_G, "CludesUIDungeonMap")
    OUT:write(("== %s: %s, %d stops (%d on the route), next %s, window %s\n"):format(label,
        d and d.name or "none", #route, numbered,
        nextStop and (nextStop.number .. ". " .. nextStop.boss.name .. " floor " .. nextStop.floor) or "none",
        tostring(w and w:IsShown())))
end
Report("enter the Deadmines")
DM.KilledEncounter(2741) -- Rhahk'Zor
Report("Rhahk'Zor killed (encounter end)")
DM.Killed(642) -- Sneed's Shredder by its death
Report("Sneed's Shredder died")
DM.KilledEncounter(2742) -- Sneed
Report("Sneed killed")
IsInInstance = function() return false, "none" end
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
HARNESS_ADVANCE(0.1)
Report("left the dungeon")
