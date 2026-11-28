-- Who Pulled (CludesUIForeverEssentials_PullWatch.lua, Forever): in a
-- dungeon group the first hit of a fight is reported once (a party member's
-- spell on a mob; later hits say nothing); after the group is out of combat
-- a while, a mob hitting the healer is the next pull; outside a dungeon
-- nothing is reported.
local CUI = rawget(_G, "CludesUI")
local PW = CUI._PullWatch
if not PW then
    OUT:write("== no Who Pulled on this client\n")
    return
end
local inside, fighting = true, false
IsInInstance = function() return inside, inside and "party" or "none" end
IsInGroup = function() return true end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 2 end
UnitAffectingCombat = function() return fighting end
local said = {}
local oldPrint = CUI.Print
CUI.Print = function(t) said[#said + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local PARTY, FOE = 0x0512, 0x0A48 -- party player; hostile NPC
local nextEvent
CombatLogGetCurrentEventInfo = function() return unpack(nextEvent) end
local function Log(...)
    nextEvent = { 0, ... }
    HARNESS_FIRE_EVENT("COMBAT_LOG_EVENT_UNFILTERED")
end
CludesUIDB.pullWatch = { enabled = true }
PW.Apply()
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
fighting = true
Log("SPELL_DAMAGE", false, "Player-1-A", "Sneaky", PARTY, 0, "Creature-0-1-2-3-38-1", "Defias Thug", FOE, 0, 1752, "Sinister Strike")
Log("SWING_DAMAGE", false, "Player-1-B", "Tanky", PARTY, 0, "Creature-0-1-2-3-38-1", "Defias Thug", FOE, 0)
OUT:write("== first fight: " .. table.concat(said, " / ") .. "\n")
wipe(said)
fighting = false
for _ = 1, 60 do HARNESS_ADVANCE(0.1) end
fighting = true
Log("SWING_DAMAGE", false, "Creature-0-1-2-3-589-2", "Defias Pillager", FOE, 0, "Player-1-C", "Holy", PARTY, 0)
OUT:write("== second fight: " .. table.concat(said, " / ") .. "\n")
wipe(said)
fighting = false
for _ = 1, 60 do HARNESS_ADVANCE(0.1) end
inside = false
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
fighting = true
Log("SPELL_DAMAGE", false, "Player-1-A", "Sneaky", PARTY, 0, "Creature-0-1-2-3-99-3", "Wolf", FOE, 0, 1752, "Sinister Strike")
OUT:write("== outside: " .. (#said > 0 and table.concat(said, " / ") or "(nothing)") .. "\n")
CUI.Print = oldPrint
