-- Interrupt Tracker (CludesUIForeverEssentials_KickTracker.lua, Forever): a
-- party of you (a level 30 mage: Counterspell), a rogue (Kick) and a level
-- 20 warrior (Shield Bash, not Pummel yet) and a priest (no interrupt); the
-- rogue kicks: on cooldown, the others ready and
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
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_SUCCEEDED", "nameplate3", "cast-0", 1767)
Show("a nameplate's Kick (not the group's) changes nothing")
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-1", 1767)
Show("Sneaky kicked (rank 2)")
HARNESS_ADVANCE(11)
Show("eleven seconds later")
