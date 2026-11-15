-- Info Bar > Gold block: coin colours, silver and copper, coin icons,
-- abbreviated, bag space, no icon, hover and tooltip (session, characters on
-- two realms, token), money earned and spent, bag updates with and without
-- bag space shown, and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local money = 123456789
GetMoney = function() return money end
local free = 12
C_Container.GetContainerNumFreeSlots = function(i) return i == 0 and free or 0, 0 end
local b = H.Block("gold")
H.Show("gold")
b.settings.showSmall = true
H.Show("gold small")
b.settings.coinIcons = true
H.Show("gold coin icons")
b.settings.coinIcons = nil
b.settings.abbreviate = true
H.Show("gold abbreviated")
b.settings.abbreviate = nil
b.settings.showIcons = false
H.Show("gold no icon")
b.settings.showIcons = nil
H.Count("bag updates, bag space not shown", function()
    free = 11
    HARNESS_FIRE_EVENT("BAG_UPDATE", 0)
    HARNESS_FIRE_EVENT("BAG_UPDATE", 1)
    HARNESS_ADVANCE(0.1)
end)
b.settings.showBagSpace = true
H.Show("gold bag space")
H.Count("bag update, same free slots", function()
    HARNESS_FIRE_EVENT("BAG_UPDATE", 0)
    HARNESS_ADVANCE(0.1)
end)
free = 9
HARNESS_FIRE_EVENT("BAG_UPDATE", 0)
HARNESS_ADVANCE(0.1)
SNAP("gold fewer slots", H.Bar())
money = money + 50000
HARNESS_FIRE_EVENT("PLAYER_MONEY")
HARNESS_ADVANCE(0.1)
SNAP("gold earned", H.Bar())
money = money - 20000
HARNESS_FIRE_EVENT("PLAYER_MONEY")
HARNESS_ADVANCE(0.1)
H.Hover("gold hover")
b.useCoinColor = nil
b.useAccentColor = true
H.Show("gold accent")
H.Hover("gold accent hover")
b.useAccentColor, b.useCoinColor = nil, true
H.Vertical("gold vertical")
