-- Info Bar > FPS, Latency, Durability and Combat blocks: values, icons,
-- latency modes, FPS ticking (same digit count, then 99 -> 100), durability
-- events, combat on and off (and only-in-combat), hovers and tooltips, and a
-- vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local mod = H.mod
local fps, net, dur, fighting = 61, { 12.5, 3.1, 45, 92 }, { 80, 100 }, false
GetFramerate = function() return fps end
GetNetStats = function() return net[1], net[2], net[3], net[4] end
GetInventoryItemDurability = function(s) if s == 5 then return dur[1], dur[2] end if s == 1 then return 50, 50 end end
UnitAffectingCombat = function() return fighting end
C_AddOns.GetNumAddOns = function() return 2 end
C_AddOns.GetAddOnInfo = function(i) return nil, i == 1 and "CludesUI" or "Details" end
GetAddOnMemoryUsage = function(i) return i == 1 and 4096 or 300 end
UpdateAddOnMemoryUsage = function() end
local function Colour(r, g, b) return { GetRGB = function() return r, g, b end } end
GREEN_FONT_COLOR, YELLOW_FONT_COLOR, RED_FONT_COLOR = Colour(0.1, 1, 0.1), Colour(1, 0.82, 0), Colour(1, 0.1, 0.1)

H.Block("fps")
local ms = mod.AddBlock(H.bar.id, "ms")
local du = mod.AddBlock(H.bar.id, "durability")
local co = mod.AddBlock(H.bar.id, "combat")
for _, x in ipairs({ ms, du, co }) do x.settings = x.settings or {} end
H.Show("stats")
ms.settings.showIcon = true
H.Show("stats ms icon")
for _, m in ipairs({ "world", "both", "home" }) do
    ms.settings.latencyMode = m
    H.Show("stats ms " .. m)
end
H.Hover("stats fps hover", 1)
H.Hover("stats ms hover", 2)
H.Hover("stats durability hover", 3)
H.Hover("stats combat hover", 4)
H.Count("fps 61 -> 58 -> 75 over 9 seconds", function()
    fps = 58
    for _ = 1, 3 do HARNESS_ADVANCE(1) end
    fps = 75
    for _ = 1, 3 do HARNESS_ADVANCE(1) end
end)
SNAP("stats fps 75", H.Bar())
fps = 100
for _ = 1, 3 do HARNESS_ADVANCE(1) end
SNAP("stats fps 100", H.Bar())
H.Count("latency the same for 5 seconds", function()
    for _ = 1, 5 do HARNESS_ADVANCE(1) end
end)
net[3] = 130
HARNESS_ADVANCE(1)
SNAP("stats ms 130", H.Bar())
H.Count("durability 80 -> 70", function()
    dur[1] = 70
    HARNESS_FIRE_EVENT("UPDATE_INVENTORY_DURABILITY")
    HARNESS_FIRE_EVENT("UPDATE_INVENTORY_ALERTS")
    HARNESS_ADVANCE(3)
end)
SNAP("stats durability 70", H.Bar())
fighting = true
HARNESS_FIRE_EVENT("PLAYER_REGEN_DISABLED")
SNAP("stats in combat", H.Bar())
fighting = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
co.settings.onlyInCombat = true
H.Show("stats only in combat")
du.settings.showIcon = false
H.Show("stats durability no icon")
H.Vertical("stats vertical")
