-- Info Bar > Currency block: nothing picked, a plain currency, a capped one,
-- a season-earned cap (crests), an undiscovered one, no icon, description
-- off, a vertical bar, hover and tooltip, and currency events (another
-- currency, then its own).
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local DB = {
    [1] = { name = "Valorstones", quantity = 1234, iconFileID = 111, quality = 3, description = "Spend them on upgrades." },
    [2] = { name = "Honor", quantity = 500, maxQuantity = 15000, iconFileID = 222, quality = 1 },
    [3] = { name = "Gilded Crest", quantity = 40, maxQuantity = 90, totalEarned = 60, useTotalEarnedForMaxQty = true, iconFileID = 333, quality = 4 },
    [4] = { name = "Hidden", quantity = 0, discovered = false },
}
C_CurrencyInfo.GetCurrencyInfo = function(id) return DB[id] end
BreakUpLargeNumbers = function(n) return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "currency")
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Button()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__kind == "Button" and f.__scripts.OnClick and f.__scripts.OnEnter and f.__shown then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end
local function Hover(label)
    local btn = Button()
    if not btn then return end
    btn.__scripts.OnEnter(btn)
    SNAP(label .. " hovered", Bar())
    SNAP(label .. " tooltip", rawget(_G, "CludesUIDataBarsTip"))
    btn.__scripts.OnLeave(btn)
    SNAP(label .. " left", Bar())
end

Show("currency none")
Hover("currency none")
for id = 1, 4 do
    b.settings.currencyId = id
    Show("currency " .. id)
    Hover("currency " .. id)
end
b.settings.currencyId = 1
b.settings.showIcon = false
Show("currency no icon")
b.settings.showIcon = true
Show("currency icon back on") -- the settings page redraws the bar after a change
b.settings.showDescription = false
Hover("currency no description")
b.settings.showDescription = nil

-- Events: another currency changes (this one stays), then this one does.
DB[2].quantity = 600
HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE", 2, 600)
SNAP("currency after another changed", Bar())
DB[1].quantity = 1300
HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE", 1, 1300)
SNAP("currency after its own changed", Bar())
HARNESS_FIRE_EVENT("CURRENCY_DISPLAY_UPDATE")
SNAP("currency after a full update", Bar())

bar.orientation = "V"
Show("currency vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
