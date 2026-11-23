-- Auto Loot While Fishing (CludesUIForeverEssentials_Fishing.lua): a Fishing
-- cast turns auto loot on for the session; moving ends it and puts the
-- player's own setting back; off, a cast leaves it alone.
local CUI = rawget(_G, "CludesUI")
local FI = CUI._Fishing
OUT:write("== fishing " .. tostring(FI ~= nil) .. "\n")
if not FI then return end

local cvars = { autoLootDefault = "0" }
GetCVar = function(n) return cvars[n] end
C_CVar.GetCVar = function(n) return cvars[n] end
SetCVar = function(n, v) cvars[n] = tostring(v) return true end
C_CVar.SetCVar = function(n, v) cvars[n] = tostring(v) return true end
IsPlayerSpell = function(id) return id == 7620 end
C_Spell.GetSpellName = function(id) return id == 7620 and "Fishing" or nil end

local function Cast(tag)
    HARNESS_FIRE_EVENT("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    OUT:write(("== %s: autoLootDefault=%s\n"):format(tag, tostring(cvars.autoLootDefault)))
end
local function Move(tag)
    HARNESS_FIRE_EVENT("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    HARNESS_FIRE_EVENT("PLAYER_STARTED_MOVING")
    OUT:write(("== %s: autoLootDefault=%s\n"):format(tag, tostring(cvars.autoLootDefault)))
end

FI.Cfg().autoLoot = true
FI.Apply()
HARNESS_FIRE_EVENT("SPELLS_CHANGED")
Cast("cast with Auto Loot While Fishing on")
Move("moved away")
FI.Cfg().autoLoot = nil
FI.Apply()
Cast("cast with it off")
