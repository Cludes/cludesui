-- Info Bar > Spec block (retail): spec and loadout name, uppercase, Blizzard
-- icons, no icon, loot spec differing (shown) and following, hover (the spec
-- popup, the loadout flyout), right-click (loot popup, pick one), Ctrl-click
-- (loadouts, swap one), events that change nothing, a spec change, and a
-- vertical bar. Counts draws and records the popups.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local mod = H.mod
UnitClass = function() return "Mage", "MAGE", 8 end
local SPECS = { { 62, "Arcane", 135932, "DAMAGER" }, { 63, "Fire", 135810, "DAMAGER" }, { 64, "Frost", 135846, "DAMAGER" } }
local spec, loot = 2, 0
GetNumSpecializations = function() return 3 end
C_SpecializationInfo.GetSpecializationInfo = function(i) local s = SPECS[i] if s then return s[1], s[2], "", s[3], s[4] end end
C_SpecializationInfo.GetSpecialization = function() return spec end
SET_SPEC = 0
C_SpecializationInfo.SetSpecialization = function(i) SET_SPEC = i end
GetLootSpecialization = function() return loot end
GetSpecializationInfoByID = function(id) for _, s in ipairs(SPECS) do if s[1] == id then return id, s[2] end end end
SetLootSpecialization = function(id) loot = id end
PlayerUtil = { GetCurrentSpecID = function() return SPECS[spec][1] end }
local configs = { [63] = { 101, 102 } }
local names = { [101] = "Raid ST", [102] = "M+ AoE" }
local selected = 101
LOADED = {}
C_ClassTalents.GetLastSelectedSavedConfigID = function() return selected end
C_ClassTalents.GetConfigIDsBySpecID = function(id) return configs[id] or {} end
C_ClassTalents.LoadConfig = function(id) LOADED[#LOADED + 1] = id return 0 end
C_ClassTalents.UpdateLastSelectedSavedConfigID = function(_, id) selected = id end
C_ClassTalents.GetActiveConfigID = function() return 999 end
C_Traits.GetConfigInfo = function(id) return names[id] and { name = names[id] } end
Enum.LoadConfigResult.NoChangesNecessary, Enum.LoadConfigResult.Error = 0, 2
local popups = {}
local make = mod.CreatePopupFrame
mod.CreatePopupFrame = function(...) local p = make(...) popups[#popups + 1] = p return p end
local function SnapPopups(label)
    for i, p in ipairs(popups) do
        if p:IsShown() then SNAP(label .. " popup " .. i, p) end
    end
end
local function Rows(p)
    local out = {}
    for _, c in ipairs(p.__children) do
        if c.__kind == "Button" and c.__shown and c.__scripts.OnClick then out[#out + 1] = c end
    end
    return out
end

local b = H.Block("spec")
H.Show("spec loadout")
b.settings.showLoadout = false
H.Show("spec name")
b.settings.showLoadout = nil
b.settings.useUppercase = true
H.Show("spec upper")
b.settings.useUppercase = nil
b.settings.iconStyle = "wow"
H.Show("spec wow icon")
b.settings.iconStyle = nil
b.settings.showIcon = false
H.Show("spec no icon")
b.settings.showIcon = nil
loot = 64
H.Show("spec loot differs")
local btn = H.Buttons()[1]
btn.__scripts.OnEnter(btn)
SNAP("spec hovered", H.Bar())
SnapPopups("spec hover")
-- Hover the active spec row: the loadout flyout.
local rows = popups[1] and Rows(popups[1]) or {}
for _, r in ipairs(rows) do if r.__scripts.OnEnter then r.__scripts.OnEnter(r) end end
SnapPopups("spec flyout")
btn.__scripts.OnLeave(btn)
for _, p in ipairs(popups) do if p:IsShown() then p:Hide() end end
-- Right-click: loot popup, pick "current spec".
btn.__scripts.OnClick(btn, "RightButton")
SnapPopups("spec loot")
for _, p in ipairs(popups) do
    if p:IsShown() then
        local r = Rows(p)[1]
        if r then r.__scripts.OnClick(r, "LeftButton") end
    end
end
OUT:write("== loot now ", loot, "\n")
-- Ctrl-click: loadouts, swap to the second.
IsControlKeyDown = function() return true end
btn.__scripts.OnClick(btn, "LeftButton")
IsControlKeyDown = function() return false end
SnapPopups("spec loadouts")
for _, p in ipairs(popups) do
    if p:IsShown() then
        local r = Rows(p)[2]
        if r then r.__scripts.OnClick(r, "LeftButton") end
    end
end
OUT:write("== loaded ", table.concat(LOADED, ","), " selected ", selected, "\n")
SNAP("spec swapped", H.Bar())
H.Count("events that change nothing", function()
    HARNESS_FIRE_EVENT("SPELLS_CHANGED")
    HARNESS_FIRE_EVENT("SPELLS_CHANGED")
    HARNESS_FIRE_EVENT("TRAIT_CONFIG_UPDATED", 5)
    HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
end)
spec = 3
HARNESS_FIRE_EVENT("PLAYER_SPECIALIZATION_CHANGED", "player")
SNAP("spec frost", H.Bar())
H.Vertical("spec vertical")
