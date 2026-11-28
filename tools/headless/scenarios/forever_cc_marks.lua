-- CC Marker Bar (CludesUIForeverEssentials_CCMarks.lua, Forever): in a
-- group of a mage (you), a rogue and a priest, CC on a humanoid gives
-- Polymorph (Moon), the next humanoid Sap (Star), an undead Shackle Undead
-- (Triangle); a demon has nobody; Dextren Ward (immune to Polymorph by
-- Creature Scout's real data) gets Sap; Sap is never given in combat; the
-- CC button's macro marks with the chosen mark; Say posts all of it.
local CUI = rawget(_G, "CludesUI")
local CC = CUI._CCMarks
if not CC then
    OUT:write("== no CC Marker Bar on this client\n")
    return
end
C_EncodingUtil = dofile("tools/headless/encoding_util.lua")
Enum.CompressionMethod = Enum.CompressionMethod or {}
Enum.CompressionMethod.Deflate = 1

local members = {
    player = { "Me", "MAGE", 30 },
    party1 = { "Sneaky", "ROGUE", 30 },
    party2 = { "Holy", "PRIEST", 28 },
}
local target = {}
local function Stub(e)
    e.IsInRaid = function() return false end
    e.IsInGroup = function() return true end
    e.GetNumSubgroupMembers = function() return 2 end
    e.GetNumGroupMembers = function() return 3 end
    e.UnitExists = function(u) return members[u] ~= nil or (u == "target" and target.guid ~= nil) end
    e.UnitName = function(u)
        if u == "target" then return target.name end
        return members[u] and members[u][1]
    end
    e.UnitClass = function(u) return nil, members[u] and members[u][2] end
    e.UnitLevel = function(u) return members[u] and members[u][3] or 30 end
    e.UnitIsPlayer = function(u) return members[u] ~= nil end
    e.UnitIsDead = function() return false end
    e.UnitCanAttack = function(_, u) return u == "target" end
    e.UnitCreatureType = function() return target.kind end
    e.UnitGUID = function(u) return u == "target" and target.guid or nil end
    e.UnitAffectingCombat = function() return target.combat or false end
    e.InCombatLockdown = function() return false end
    e.IsInInstance = function() return true, "party" end
end
Stub(_G)
local said = {}
C_ChatInfo.SendChatMessage = function(text, channel) said[#said + 1] = channel .. ": " .. text end
C_ChatInfo.InChatMessagingLockdown = function() return false end

CludesUIDB.ccMarks = { enabled = true, announce = true }
CC.Apply()
local bar = rawget(_G, "CludesUICCMarkBar")
local button = rawget(_G, "CludesUICCAssign")
OUT:write("== bar shown in a dungeon " .. tostring(bar and bar:IsShown()) .. ", CC button " .. tostring(button ~= nil) .. "\n")
if not button then return end

local function Press(label, kind, npc, name, combat)
    target = { kind = kind, guid = ("Creature-0-1-2-3-%d-00000%05d"):format(npc, npc), name = name, combat = combat }
    wipe(said)
    local pre, post = button:GetScript("PreClick"), button:GetScript("PostClick")
    pre(button, "LeftButton")
    local macro = button:GetAttribute("macrotext")
    post(button, "LeftButton")
    OUT:write(("== %s: macro %q%s\n"):format(label, macro or "", said[1] and ("; said " .. said[1]) or ""))
end

Press("Defias Thug (humanoid)", "Humanoid", 38, "Defias Thug")
Press("Defias Pillager (humanoid)", "Humanoid", 589, "Defias Pillager")
Press("Rotting Ghoul (undead)", "Undead", 1525, "Rotting Ghoul")
Press("Felhound (demon), nobody free", "Demon", 6010, "Felhound")
CC.Reset()
Press("Dextren Ward (immune to Polymorph)", "Humanoid", 1663, "Dextren Ward")
CC.Reset()
Press("humanoid already in combat: no Sap", "Humanoid", 38, "Defias Thug", true)
Press("second humanoid in combat, mage busy", "Humanoid", 589, "Defias Pillager", true)
wipe(said)
CC.Announce()
OUT:write("== Say: " .. tostring(said[1]) .. "\n")
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
local n = 0
for _ in pairs(CC.State()) do n = n + 1 end
OUT:write("== after the fight, assignments left " .. n .. "\n")

-- Inside a dungeon the game can hide the creature type: the tooltip line
-- ("Level 44 Undead") is read instead; with that hidden too, a control is
-- still given and you are told to check it fits.
CC.Reset()
local HIDDEN = {}
issecretvalue = function(v) return v == HIDDEN end
UnitCreatureType = function() return HIDDEN end
local tipLine
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetUnit = function() return { lines = { { leftText = "Barbed Lasher" }, { leftText = tipLine } } } end
local printed = {}
local oldPrint = CUI.Print
CUI.Print = function(t) printed[#printed + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
tipLine = "Level 44 Undead"
Press("type hidden, tooltip says Undead", HIDDEN, 1525, "Rotting Ghoul")
tipLine = HIDDEN
Press("type and tooltip hidden", HIDDEN, 38, "Defias Thug")
OUT:write("== printed: " .. table.concat(printed, " / ") .. "\n")

-- GUIDs hidden as well, with two mages: the second humanoid gets the other
-- mage's Polymorph on a free mark, never the first mob's Moon.
CC.Reset()
UnitCreatureType = function() return target.kind end
members.party3 = { "Frosty", "MAGE", 30 }
GetNumSubgroupMembers = function() return 3 end
GetNumGroupMembers = function() return 4 end
UnitGUID = function(u) return u == "target" and HIDDEN or nil end
Press("GUID hidden, first humanoid", "Humanoid", 38, "Defias Thug")
Press("GUID hidden, second humanoid", "Humanoid", 589, "Defias Pillager")
CUI.Print = oldPrint
