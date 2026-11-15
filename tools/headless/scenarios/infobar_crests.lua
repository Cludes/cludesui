-- Info Bar > Crests block (retail): crest colours, separators, reverse,
-- season progress, hide empty, a crest unticked, no icons, hover (plain
-- colours) and tooltip, currency events (another currency, a bulk update
-- with no change, a crest change), and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local cur = {
    [3442] = { name = "Weathered Crest", quantity = 40, maxQuantity = 90, totalEarned = 60, useTotalEarnedForMaxQty = true, iconFileID = 1 },
    [3443] = { name = "Carved Crest", quantity = 0, maxQuantity = 90, totalEarned = 0, useTotalEarnedForMaxQty = true, iconFileID = 2 },
    [3444] = { name = "Runed Crest", quantity = 12, maxQuantity = 0, iconFileID = 3 },
    [3445] = { name = "Gilded Crest", quantity = 1250, maxQuantity = 2000, totalEarned = 1500, useTotalEarnedForMaxQty = true, iconFileID = 4 },
}
C_CurrencyInfo.GetCurrencyInfo = function(id) return cur[id] end
local b = H.Block("crests")
H.Show("crests default")
for _, sep in ipairs({ "line", "dash", "space", "slash" }) do
    b.settings.separator = sep
    H.Show("crests sep " .. sep)
end
b.settings.reverse = true
H.Show("crests reverse")
b.settings.reverse = nil
b.settings.showSeasonProgress = true
H.Show("crests season")
b.settings.showSeasonProgress = nil
b.settings.hideEmpty = true
H.Show("crests hide empty")
b.settings.hideEmpty = nil
b.settings.t4 = false
H.Show("crests no gilded")
b.settings.t4 = nil
b.settings.showIcons = false
H.Show("crests no icons")
b.settings.showIcons = nil
b.useAccentColor = true
H.Show("crests accent colour")
b.useAccentColor = nil
H.Show("crests colours back")
H.Hover("crests hover")
H.Count("another currency and a bulk update with no change", function()
    HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE", 1792)
    HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE")
    HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE", 3442)
end)
cur[3442].quantity = 55
HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE", 3442)
SNAP("crests changed", H.Bar())
H.Vertical("crests vertical")
