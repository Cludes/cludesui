-- Interrupt Tracker (CludesUIForeverEssentials_KickTracker.lua, Forever): a
-- party of you (a level 30 mage: Counterspell), a rogue (Kick) and a level
-- 20 warrior (Shield Bash, not Pummel yet) and a priest (no interrupt); the
-- rogue kicks and lands it: on cooldown and counted, the others ready and
-- the first marked next; the cooldown runs out.
local CUI = rawget(_G, "CludesUI")
local KT = CUI._KickTracker
if not KT then
    OUT:write("== no Interrupt Tracker on this client\n")
    return
end
local members = {
    player = { "Me", "MAGE", 30, "Player-1-ME" },
    party1 = { "Sneaky", "ROGUE", 30, "Player-1-R" },
    party2 = { "Tanky", "WARRIOR", 20, "Player-1-W" },
    party3 = { "Holy", "PRIEST", 30, "Player-1-P" },
}
IsInInstance = function() return true, "party" end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 3 end
UnitExists = function(u) return members[u] ~= nil end
UnitName = function(u) return members[u] and members[u][1] end
UnitClass = function(u) return nil, members[u] and members[u][2] end
UnitLevel = function(u) return members[u] and members[u][3] or 1 end
UnitGUID = function(u) return members[u] and members[u][4] end
GetSpellBaseCooldown = function(id) return id == 1766 and 10000 or 0, 1500 end
local nextEvent
CombatLogGetCurrentEventInfo = function() return unpack(nextEvent) end
local function Log(...)
    nextEvent = { 0, ... }
    HARNESS_FIRE_EVENT("COMBAT_LOG_EVENT_UNFILTERED")
end
local function Show(label)
    KT.Draw()
    OUT:write("== " .. label .. "\n")
    local panel = rawget(_G, "CludesUIKickTracker")
    if not panel then return end
    for _, child in ipairs({ panel:GetChildren() }) do
        if child.name and child:IsShown() then
            local text = (child.name:GetText() .. "  " .. child.state:GetText()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            OUT:write("   " .. text .. "\n")
        end
    end
end
CludesUIDB.kickTracker = { enabled = true }
KT.Apply()
Show("start")
Log("SPELL_CAST_SUCCESS", false, "Player-1-R", "Sneaky", 0x511, 0, "Creature-0-1-2-3-38-1", "Defias Thug", 0xa48, 0, 1767, "Kick")
Log("SPELL_INTERRUPT", false, "Player-1-R", "Sneaky", 0x511, 0, "Creature-0-1-2-3-38-1", "Defias Thug", 0xa48, 0, 1767, "Kick")
Show("Sneaky kicked (rank 2) and stopped a cast")
HARNESS_ADVANCE(11)
Show("eleven seconds later")
