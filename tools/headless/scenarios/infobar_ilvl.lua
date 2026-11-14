-- Info Bar > Item Level block: each value mode, precision, each prefix
-- (short, long, icon, none), hover and tooltip (with PvP), gear events, a
-- change during combat and the pass when it ends, and a vertical bar.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local ilvl = { 652.375, 648.5, 0 }
GetAverageItemLevel = function() return ilvl[1], ilvl[2], ilvl[3] end
local combat = false
InCombatLockdown = function() return combat end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "ilvl")
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Hoverable()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__kind == "Button" and f.__scripts.OnEnter and f.__shown then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end

Show("ilvl default")
for _, mode in ipairs({ "total", "both", "equipped" }) do
    b.settings.value = mode
    Show("ilvl " .. mode)
end
for _, p in ipairs({ 1, 2, 0 }) do
    b.settings.precision = p
    Show("ilvl precision " .. p)
end
for _, prefix in ipairs({ "long", "icon", "none", "short" }) do
    b.settings.prefix = prefix
    Show("ilvl prefix " .. prefix)
end

local h = Hoverable()
h.__scripts.OnEnter(h)
SNAP("ilvl hovered", Bar())
SNAP("ilvl tooltip", rawget(_G, "CludesUIDataBarsTip"))
h.__scripts.OnLeave(h)
ilvl[3] = 640
h.__scripts.OnEnter(h)
SNAP("ilvl tooltip pvp", rawget(_G, "CludesUIDataBarsTip"))
h.__scripts.OnLeave(h)

-- Gear: an upgrade, then the same value again (both events), then in combat and after.
ilvl[2] = 650.25
HARNESS_FIRE_EVENT("PLAYER_EQUIPMENT_CHANGED", 1, true)
HARNESS_FIRE_EVENT("PLAYER_AVG_ITEM_LEVEL_UPDATE")
SNAP("ilvl after upgrade", Bar())
HARNESS_FIRE_EVENT("PLAYER_EQUIPMENT_CHANGED", 2, true)
SNAP("ilvl unchanged", Bar())
combat = true
ilvl[2] = 655
HARNESS_FIRE_EVENT("PLAYER_AVG_ITEM_LEVEL_UPDATE")
SNAP("ilvl in combat", Bar())
combat = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
SNAP("ilvl after combat", Bar())

bar.orientation = "V"
Show("ilvl vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
