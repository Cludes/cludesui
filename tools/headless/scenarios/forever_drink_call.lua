-- Say When You Drink (CludesUIForeverEssentials_GroupWatch.lua, Forever): a
-- priest in a dungeon group at 25% mana sits down to drink: "Drinking (25%
-- mana)" in party; at full mana "Mana full", once; standing up and sitting
-- again at full mana says nothing; off, nothing at all.
local CUI = rawget(_G, "CludesUI")
local GW = CUI._GroupWatch
if not GW then
    OUT:write("== no Group Watch on this client\n")
    return
end
local mana, drinking = 250, false
IsInGroup = function() return true end
IsInRaid = function() return false end
IsInInstance = function() return true, "party" end
UnitClass = function() return "Priest", "PRIEST" end
UnitGroupRolesAssigned = function() return "HEALER" end
UnitPower = function() return mana end
UnitPowerMax = function() return 1000 end
C_Spell.GetSpellName = function(id) return id == 430 and "Drink" or nil end
C_UnitAuras.GetAuraDataBySpellName = function(_, name) return drinking and name == "Drink" and { auraInstanceID = 1 } or nil end
local said = {}
C_ChatInfo.SendChatMessage = function(text, channel) said[#said + 1] = channel .. ": " .. text end
C_ChatInfo.InChatMessagingLockdown = function() return false end
local function Step(label)
    HARNESS_FIRE_EVENT("UNIT_AURA", "player")
    HARNESS_FIRE_EVENT("UNIT_POWER_UPDATE", "player", "MANA")
    OUT:write(("== %s: %s\n"):format(label, #said > 0 and table.concat(said, " / ") or "(nothing)"))
    wipe(said)
end
CludesUIDB.healerMana = { sayDrink = true }
GW.healer.Apply()
drinking = true
Step("sits down at 25%")
mana = 600
Step("halfway")
mana = 1000
Step("full")
Step("still full")
drinking = false
Step("stands up")
drinking = true
Step("sits again at full")
drinking = false
Step("up")
CludesUIDB.healerMana.sayDrink = false
GW.healer.Apply()
mana, drinking = 200, true
Step("setting off, sits at 20%")
