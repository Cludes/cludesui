-- QoL > Upgrade tooltips (retail): the file is loaded again with capturing
-- stubs (its hooks install once, at login), then each kind of item goes
-- through the pre-call (the game's upgrade line) and the post-call (items
-- whose upgrade line is missing): a mid-track item, a maxed one, an unknown
-- track, an Ascendant item, a preview override, a secret value, the memo on
-- a second pass, and the feature switched off.
local CUI = rawget(_G, "CludesUI")
local pre, post
TooltipDataProcessor = {
    AddLinePreCall = function(_, fn) pre = fn end,
    AddLinePostCall = function(_, fn) post = fn end,
}
Enum.TooltipDataLineType.ItemUpgradeLevel, Enum.TooltipDataLineType.ItemLevel = 41, 42
Enum.ItemQuality.Poor, Enum.ItemQuality.Common, Enum.ItemQuality.Uncommon = 0, 1, 2
Enum.ItemQuality.Rare, Enum.ItemQuality.Epic, Enum.ItemQuality.Legendary = 3, 4, 5
local secret = {}
canaccessallvalues = function(...)
    for i = 1, select("#", ...) do
        if select(i, ...) == secret then return false end
    end
    return true
end
CreateSimpleTextureMarkup = function(icon, w, h) return "|T" .. icon .. ":" .. w .. ":" .. h .. "|t" end
C_Item.GetItemQualityColor = function(q) return q / 10, 0.5, 1 - q / 10 end
CUI.UPGRADE_TRACK_KEYS = { Hero = "Hero", Champion = "Champion", Veteran = "Veteran" }
local items = {
    ["item:hero3"] = { info = { currentLevel = 3, maxLevel = 6, maxItemLevel = 678, trackString = "Hero" }, ilvl = 665 },
    ["item:hero6"] = { info = { currentLevel = 6, maxLevel = 6, maxItemLevel = 678, trackString = "Hero" }, ilvl = 678 },
    ["item:odd"] = { info = { currentLevel = 1, maxLevel = 4, maxItemLevel = 600, trackString = "Odd" }, ilvl = 590 },
    ["item:secret"] = { info = secret, ilvl = 600 },
    ["item:asc"] = { info = nil, ilvl = 690, ascendant = true },
}
C_Item.GetItemUpgradeInfo = function(link) return items[link] and items[link].info end
C_Item.GetDetailedItemLevelInfo = function(link) return items[link] and items[link].ilvl end
C_Item.GetItemLinkByGUID = function(guid) return guid end
C_CurrencyInfo.GetCurrencyInfo = function(id) return { name = "Crest " .. id, iconFileID = 9000 + id } end
CUIUpgCalc = {
    Data = { tracks = { Hero = { currID = 3445 }, Champion = { currID = 3444 }, Myth = { currID = 3446 } } },
    GetAscendantBonus = function(_, link) return items[link] and items[link].ascendant or false end,
    GetItemUpgradeRange = function(_, link, key, rank, maxRank, level)
        local it = items[link]
        if it and it.ascendant then return 680, 691, 2, 3, { track = "Myth" } end
        if not key then return nil end
        return level - 13 * 0 - (rank - 1) * 3, level + (maxRank - rank) * 3, rank, maxRank
    end,
}
local on = true
CUI.QoLExtrasGet = function(k) if k == "upgradeTooltips" then return on end end
CUI._applyUpgradeTooltips = nil
local chunk = assert(loadfile("Interface/AddOns/CludesUIQoL/CludesUIQoL_UpgradeTooltip.lua")
    or loadfile("CludesUIQoL/CludesUIQoL_UpgradeTooltip.lua"))
chunk("CludesUIQoL", {})
CUI._applyUpgradeTooltips()
OUT:write("== hooks: ", tostring(pre ~= nil), " ", tostring(post ~= nil), "\n")

local function Tip(link, opts)
    opts = opts or {}
    local data = { guid = opts.guid or "", hyperlink = link, overrideItemLevel = opts.override, lines = opts.lines or {} }
    local lines = {}
    local tip = {
        IsForbidden = function() return false end,
        IsProtected = function() return false end,
        GetProcessingTooltipInfo = function() return { tooltipData = data } end,
        GetPrimaryTooltipData = function() return opts.appended and {} or data end,
        AddLine = function(_, t, r, g, b) lines[#lines + 1] = ("line %s (%.2f %.2f %.2f)"):format(t, r, g, b) end,
        AddDoubleLine = function(_, l, rt, r, g, b) lines[#lines + 1] = ("double %s | %s (%.2f %.2f %.2f)"):format(l, rt, r, g, b) end,
    }
    return tip, lines
end
local function Run(label, link, opts, which)
    local tip, lines = Tip(link, opts)
    local r = (which == "post" and post or pre)(tip, which == "post" or nil)
    OUT:write("== ", label, ": returned ", tostring(r), "\n")
    for _, l in ipairs(lines) do OUT:write("   ", l, "\n") end
end
Run("hero 3/6", "item:hero3")
Run("hero 3/6 again (memo)", "item:hero3")
Run("hero 6/6", "item:hero6")
Run("unknown track", "item:odd")
Run("secret", "item:secret")
Run("override", "item:hero3", { override = 700 })
Run("appended data", "item:hero3", { appended = true })
Run("by guid", "x", { guid = "item:hero6" })
Run("ascendant post", "item:asc", {}, "post")
Run("ascendant post with native line", "item:asc", { lines = { { type = 41 } } }, "post")
Run("non-ascendant post", "item:hero3", {}, "post")
on = false
CUI._applyUpgradeTooltips()
Run("switched off", "item:hero3")
