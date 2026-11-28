-- Res Helper (CludesUIForeverEssentials_ResHelper.lua, Forever): a priest in
-- a party with Tanky dead and Holy dead but already being resurrected sees
-- both, Tanky first-class and Holy marked; each row casts Resurrection on
-- its unit; starting the cast says so in party; nobody dead hides it.
local CUI = rawget(_G, "CludesUI")
local RH = CUI._ResHelper
if not RH then
    OUT:write("== no Res Helper on this client\n")
    return
end
local dead = { party1 = true, party2 = true }
local members = { party1 = { "Tanky", "WARRIOR" }, party2 = { "Holy", "PALADIN" } }
IsPlayerSpell = function(id) return id == 2006 end
C_Spell.GetSpellName = function(id) return id == 2006 and "Resurrection" or nil end
IsInGroup = function() return true end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 2 end
UnitExists = function(u) return members[u] ~= nil or u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitIsDeadOrGhost = function(u) return dead[u] or false end
UnitIsGhost = function() return false end
UnitIsConnected = function() return true end
UnitName = function(u) return members[u] and members[u][1] or "Me" end
UnitClass = function(u) return nil, members[u] and members[u][2] or "PRIEST" end
UnitHasIncomingResurrection = function(u) return u == "party2" end
InCombatLockdown = function() return false end
local said = {}
C_ChatInfo.SendChatMessage = function(text, channel) said[#said + 1] = channel .. ": " .. text end
C_ChatInfo.InChatMessagingLockdown = function() return false end

CludesUIDB.resHelper = { enabled = true, announce = true }
RH.Apply()
local panel = rawget(_G, "CludesUIResHelper")
OUT:write("== shown " .. tostring(panel and panel:IsShown()) .. "\n")
for i = 1, 2 do
    local row = rawget(_G, "CludesUIResHelperRow" .. i)
    if row then
        OUT:write(("   row %d: %s | casts %s on %s\n"):format(i, (row:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
            tostring(row:GetAttribute("spell")), tostring(row:GetAttribute("unit"))))
    end
end
local row1 = rawget(_G, "CludesUIResHelperRow1")
local pre = row1 and row1:GetScript("PreClick")
if pre then pre(row1, "LeftButton") end
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_START", "player", "cast-1", 2006)
OUT:write("== said: " .. tostring(said[1]) .. "\n")
dead = {}
HARNESS_FIRE_EVENT("UNIT_HEALTH", "party1")
for _ = 1, 5 do HARNESS_ADVANCE(0.1) end
OUT:write("== everyone up, shown " .. tostring(panel and panel:IsShown()) .. "\n")
