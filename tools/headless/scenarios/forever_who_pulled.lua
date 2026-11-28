-- Who Pulled (CludesUIForeverEssentials_PullWatch.lua, Forever): in a
-- dungeon group the first member into combat is reported once (Sneaky with a
-- hostile target; the tank joining after says nothing); after the group is
-- out of combat a while, the healer being attacked first is the next pull;
-- a hunter's pet counts for its owner; outside a dungeon nothing is reported.
local CUI = rawget(_G, "CludesUI")
local PW = CUI._PullWatch
if not PW then
    OUT:write("== no Who Pulled on this client\n")
    return
end
local inside = true
local inCombat, targets = {}, {}
local names = { player = "Me", party1 = "Sneaky", party2 = "Tanky", party3 = "Holy", party4 = "Arrow", partypet4 = "Wolfie" }
IsInInstance = function() return inside, inside and "party" or "none" end
IsInGroup = function() return true end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 4 end
UnitExists = function(u) return names[u] ~= nil or targets[u] ~= nil end
UnitName = function(u) return names[u] or targets[u] end
UnitAffectingCombat = function(u) return inCombat[u] or false end
UnitCanAttack = function(_, t) return targets[t] ~= nil end
local said = {}
local oldPrint = CUI.Print
CUI.Print = function(t) said[#said + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Enter(unit)
    inCombat[unit] = true
    HARNESS_FIRE_EVENT("UNIT_FLAGS", unit)
end
local function Calm()
    wipe(inCombat)
    wipe(targets)
    for _ = 1, 60 do HARNESS_ADVANCE(0.1) end
end
local function Report(label)
    OUT:write("== " .. label .. ": " .. (#said > 0 and table.concat(said, " / ") or "(nothing)") .. "\n")
    wipe(said)
end
CludesUIDB.pullWatch = { enabled = true }
PW.Apply()
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
targets.party1target = "Defias Thug"
Enter("party1")
Enter("party2")
Report("first fight")
Calm()
Enter("party3")
Report("second fight")
Calm()
targets.partypet4target = "Defias Pillager"
Enter("partypet4")
Report("third fight")
Calm()
inside = false
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
Enter("party1")
Report("outside")
CUI.Print = oldPrint
