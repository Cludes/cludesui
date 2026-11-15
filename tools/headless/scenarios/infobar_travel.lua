-- Info Bar > Travel block: the bind location, a hearthstone cooling (dimmed,
-- then a counting timer in "smart" and "both" modes), ready again, hover
-- (the tooltip ticking), bag and spell events that change nothing, a new
-- bind location, and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local bind = "Dornogal"
GetBindLocation = function() return bind end
C_Item.GetItemCount = function(id) return id == 6948 and 1 or 0 end
PlayerHasToy = function() return false end
local cd = { 0, 0 }
C_Item.GetItemCooldown = function() return cd[1], cd[2] end
C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0 } end
local b = H.Block("travel")
H.Show("travel")
H.Count("bag and spell events, nothing changed", function()
    HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
    HARNESS_FIRE_EVENT("SPELLS_CHANGED")
    HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
end)
cd = { GetTime(), 900 }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_SUCCEEDED", "player")
HARNESS_ADVANCE(1)
SNAP("travel cooling", H.Bar())
b.settings.textLeft = "smart"
H.Show("travel smart")
H.Count("timer counting 3 seconds", function()
    for _ = 1, 3 do HARNESS_ADVANCE(1) end
end)
SNAP("travel smart later", H.Bar())
H.Hover("travel hover")
H.Count("hovered 3 seconds", function()
    local btn = H.Buttons()[1]
    btn["\0scripts"].OnEnter(btn)
    for _ = 1, 3 do HARNESS_ADVANCE(1) end
    btn["\0scripts"].OnLeave(btn)
end)
cd = { 0, 0 }
HARNESS_ADVANCE(1)
SNAP("travel ready", H.Bar())
bind = "Valdrakken"
HARNESS_FIRE_EVENT("HEARTHSTONE_BOUND")
SNAP("travel new bind", H.Bar())
H.Vertical("travel vertical")
