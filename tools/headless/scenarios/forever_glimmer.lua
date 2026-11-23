-- Glimmer (CludesUIForeverEssentials_Glimmer.lua): the soft interact
-- settings held while on and put back when off; a Silverleaf node lit on
-- its nameplate in its skill-up colour with its line; a chest; a corpse off
-- by default; combat releases it; a gathered herb is noted for the map.
local CUI = rawget(_G, "CludesUI")
local GL = CUI._Glimmer
OUT:write("== glimmer " .. tostring(GL ~= nil) .. "\n")
if not GL then return end

local cvars = { SoftTargetInteract = "0", SoftTargetInteractOnlyInRange = "1", SoftTargetIconGameObject = "0",
    SoftTargetInteractRange = "10", SoftTargetInteractArc = "0", SoftTargetNameplateInteract = "0" }
GetCVar = function(n) return cvars[n] end
C_CVar.GetCVar = function(n) return cvars[n] end
SetCVar = function(n, v) cvars[n] = tostring(v) return true end
C_CVar.SetCVar = function(n, v) cvars[n] = tostring(v) return true end
local plate = CreateFrame("Frame", "FakeSoftPlate", UIParent)
C_NamePlate.GetNamePlateForUnit = function(u) return u == "softinteract" and plate or nil end
local guid = "GameObject-0-1-2-3-1617-00000ABCDE"
UnitGUID = function(u) return u == "softinteract" and guid or "Player-1-1" end
UnitIsGameObject = function() return true end
UnitIsInInteractRange = function() return true end
SetUnitCursorTexture = function() return false end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Herbalism", 0, 30, 300, 0, 0, 182, 0 end
IsInInstance = function() return false end
C_Spell.GetSpellTexture = function() return 136065 end
C_TooltipInfo.GetUnit = function() return { lines = {} } end

local function CV() return ("interact=%s range=%s plate=%s"):format(cvars.SoftTargetInteract, cvars.SoftTargetInteractRange, cvars.SoftTargetNameplateInteract) end
local function FxState(tag)
    local fx, line = GL.Fx()
    local lit = fx ~= nil and fx:IsShown() and fx:GetParent() == plate
    OUT:write(("== %s: lit=%s style=%s color=%s line=%s | %s\n"):format(tag, tostring(lit), tostring(fx and fx.style),
        lit and ("%.2f %.2f %.2f"):format(fx.r, fx.g, fx.b) or "-", tostring(lit and line:IsShown() and line:GetText() or nil), CV()))
end

OUT:write("== before: " .. CV() .. "\n")
GL.Cfg().enabled = true
GL.Apply()
OUT:write("== on: " .. CV() .. "\n")
HARNESS_FIRE_EVENT("PLAYER_SOFT_INTERACT_CHANGED")
FxState("Silverleaf (skill 30 of 1 needed)")
GL.Cfg().skillColors = false
GL.Apply()
HARNESS_FIRE_EVENT("PLAYER_SOFT_INTERACT_CHANGED")
FxState("skill colors off (herb green)")
GL.Cfg().skillColors = nil
guid = "GameObject-0-1-2-3-32-00000ABCDE"
HARNESS_FIRE_EVENT("PLAYER_SOFT_INTERACT_CHANGED")
FxState("Sunken Chest")
GL.Cfg().chest = false
HARNESS_FIRE_EVENT("PLAYER_SOFT_INTERACT_CHANGED")
FxState("chests off")
GL.Cfg().chest = nil
HARNESS_FIRE_EVENT("PLAYER_SOFT_INTERACT_CHANGED")
HARNESS_FIRE_EVENT("PLAYER_REGEN_DISABLED")
FxState("combat")

-- Gathering: a loot window from the Silverleaf node.
GL.Cfg().gatheredPins = true
GL.Apply()
C_Map.GetBestMapForUnit = function() return 1411 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end
GetNumLootItems = function() return 1 end
GetLootSourceInfo = function() return "GameObject-0-1-2-3-1617-00000FFFFF", 1 end
HARNESS_FIRE_EVENT("LOOT_READY")
local n, entry = 0, nil
for _, e in pairs(GL.Gathered(1411) or {}) do
    n, entry = n + 1, e
end
OUT:write(("== gathered: %d entry id=%s x=%s y=%s count=%s\n"):format(n, tostring(entry and entry.id), tostring(entry and entry.x),
    tostring(entry and entry.y), tostring(entry and entry.count)))

GL.Cfg().enabled = false
GL.Apply()
OUT:write("== off: " .. CV() .. "\n")
