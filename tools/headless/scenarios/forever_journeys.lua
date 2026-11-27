-- Journeys (CludesUIForeverEssentials_Journeys.lua, Forever): with a pin
-- in Duskwood and you at Sentinel Hill, the plan walks to the flight
-- master, flies and walks to the pin; with no flights known it walks; a
-- Stormwind-to-Darnassus pin takes the boat; arriving ends it; removing
-- the pin hides the card.
local CUI = rawget(_G, "CludesUI")
local JY = CUI._Journeys
if not JY then
    OUT:write("== no Journeys on this client\n")
    return
end
local here = { x = -10640, y = 1050, c = 0 }
local pin = { c = 0, x = -10560, y = -1180 }
UnitPosition = function() return here.x, here.y, 0, here.c end
GetPlayerFacing = function() return 0 end
UnitName = function(u) return u == "player" and "Me" or nil end
GetRealmName = function() return "Lightbane" end
UnitFactionGroup = function() return "Alliance" end
UnitOnTaxi = function() return false end
IsInInstance = function() return false end
InCombatLockdown = function() return false end
C_Map.HasUserWaypoint = function() return pin ~= nil end
C_Map.GetUserWaypoint = function() return pin and { uiMapID = 1431, position = { x = 0.5, y = 0.5 } } end
C_Map.GetWorldPosFromMapPos = function() return pin.c, { x = pin.x, y = pin.y } end
C_Map.GetMapInfo = function() return { name = "Duskwood" } end
C_Item.GetItemCount = function() return 0 end

local function Report(label)
    JY.Replan()
    local plan, goal, arrived = JY.Plan()
    OUT:write(("== %s: %s\n"):format(label, arrived and "arrived" or plan and ("%d legs, %ds"):format(#plan.legs, plan.seconds) or "no plan"))
    for i, leg in ipairs(plan and plan.legs or {}) do
        OUT:write(("   %d. %s (%s, %ds)\n"):format(i, JY.StepText(leg), leg.mode, leg.seconds))
    end
    local card = rawget(_G, "CludesUIJourney")
    OUT:write("   card shown " .. tostring(card and card:IsShown()) .. "\n")
end

CludesUIDB.journeys = { enabled = true, chars = { ["Me-Lightbane"] = { flights = {}, landings = {} } } }
JY.Apply()
Report("no flights known")
CludesUIDB.journeys.chars["Me-Lightbane"].flights = { [2] = true, [4] = true, [12] = true }
-- A new flight known bumps the network version on a real flight master's
-- map; here a fresh character store does the same.
CludesUIDB.journeys.chars["Me-Lightbane"] = nil
CludesUIDB.flightPointsKnown = { ["Me-Lightbane"] = { [2] = true, [4] = true, [12] = true } }
JY.Apply()
Report("Sentinel Hill, Stormwind and Darkshire flights known")
here = { x = -8830, y = 480, c = 0 }
pin = { c = 1, x = 9947, y = 2630 }
Report("Stormwind to Darnassus")
here = { x = -10565, y = -1185, c = 0 }
pin = { c = 0, x = -10560, y = -1180 }
Report("at the pin")
pin = nil
Report("pin removed")
