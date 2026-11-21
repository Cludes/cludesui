if CUI_CLIENT_BLOCKED then return end
local CUI = CludesUI
if CUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  CludesUIQoL_UpgradeTooltip.lua - a fuller upgrade line on gear tooltips.
--
--  Replaces the game's "Upgrade Level: Hero 3/6" line with "3/6 Hero
--  (659-674)" in the track's quality colour, plus the crest that upgrades it
--  while it is not maxed. Items whose upgrade line the game leaves out (the
--  Ascendant ones) get the line added after their item level.
--
--  The game rebuilds a shown tooltip every 0.2s and every gear tooltip passes
--  the item level hook, so each item link is worked out once and kept (the
--  link carries the item's bonuses and rank; the season data, colours and
--  crest names do not change in a session). A read that meets a secret value
--  keeps nothing and draws nothing.
-------------------------------------------------------------------------------
local on, hooked = false, false
local QUALITY -- track -> item quality, filled when first switched on

-- Lines by item link, one table per hook (false = leave the game's line).
local KEEP_AT_MOST = 200
local keptPre, keptPost, kept = {}, {}, 0

local function Readable(...) return canaccessallvalues(...) end

-- The line for an item: a table, false to leave the game's line, or nil
-- while something it needs is secret.
local function LineFor(calc, link, afterItemLevel, data)
    if afterItemLevel then
        -- Only Ascendant items, and only when the game drew no upgrade line.
        if not calc:GetAscendantBonus(link) then return false end
        if not Readable(data.lines) or not data.lines then return nil end
        for _, line in ipairs(data.lines) do
            if not Readable(line) or not Readable(line.type) then return nil end
            if line.type == Enum.TooltipDataLineType.ItemUpgradeLevel then return false end
        end
    end
    local info = C_Item.GetItemUpgradeInfo(link)
    if not Readable(info) then return nil end
    local rank, maxRank, cap, trackName
    if info then
        rank, maxRank, cap, trackName = info.currentLevel, info.maxLevel, info.maxItemLevel, info.trackString
    end
    if not Readable(rank, maxRank, cap, trackName) then return nil end
    local itemLevel = C_Item.GetDetailedItemLevelInfo(link)
    if not Readable(itemLevel) then return nil end

    -- An unknown track (a new season before the calculator's data is
    -- updated) keeps the game's line.
    local track = CUI.UPGRADE_TRACK_KEYS[trackName or ""]
    local low, high, shownRank, shownMax, ascendant =
        calc:GetItemUpgradeRange(link, track, rank, maxRank, itemLevel, cap)
    if not low then return false end
    track = track or (ascendant and ascendant.track)
    if not trackName or trackName == "" then trackName = CUI.L(track) end
    local quality = QUALITY[track]
    if not quality then return false end
    local red, green, blue = C_Item.GetItemQualityColor(quality)
    local range = CUI.COLOR_CODES.WHITE .. "(" .. low .. "-" .. high .. ")|r"
    local text = CludesUI.Lf("%1$d/%2$d %3$s %4$s", shownRank, shownMax, trackName, range)

    -- The crest that upgrades it, while there are ranks left.
    local crest
    if shownRank < shownMax then
        local currency = C_CurrencyInfo.GetCurrencyInfo(calc.Data.tracks[track].currID)
        if not Readable(currency) then return nil end
        if currency and Readable(currency.name, currency.iconFileID) and currency.name then
            crest = currency.name
            if currency.iconFileID then
                crest = CreateSimpleTextureMarkup(currency.iconFileID, 14, 14) .. " " .. crest
            end
        end
    end
    return { text = text, r = red, g = green, b = blue, crest = crest }
end

-- Both hooks: draws the line, and (as the pre-hook) returns true so the
-- game's own line is not drawn as well.
local function Annotate(tooltip, afterItemLevel)
    if not on or tooltip:IsForbidden() or tooltip:IsProtected() then return end
    local processing = tooltip:GetProcessingTooltipInfo()
    if not Readable(processing) or not processing then return end
    local data = processing.tooltipData
    if not Readable(data) or not data then return end
    -- An item appended to another's tooltip is not annotated (the main one already is).
    if tooltip:GetPrimaryTooltipData() ~= data then return end
    if not Readable(data.guid, data.hyperlink, data.overrideItemLevel) then return end
    -- A preview's level can differ from the link's.
    if data.overrideItemLevel and data.overrideItemLevel > 0 then return end
    local link = data.hyperlink
    if data.guid and data.guid ~= "" then link = C_Item.GetItemLinkByGUID(data.guid) end
    if not Readable(link) or type(link) ~= "string" or link == "" then return end
    local calc = CUIUpgCalc
    if not (calc and calc.GetItemUpgradeRange) then return end

    local store = afterItemLevel and keptPost or keptPre
    local line = store[link]
    if line == nil then
        line = LineFor(calc, link, afterItemLevel, data)
        if line == nil then return end
        if kept >= KEEP_AT_MOST then
            wipe(keptPre)
            wipe(keptPost)
            kept = 0
        end
        store[link] = line
        kept = kept + 1
    end
    if not line then return end
    if line.crest then
        tooltip:AddDoubleLine(line.text, line.crest, line.r, line.g, line.b, 1, 1, 1)
    else
        tooltip:AddLine(line.text, line.r, line.g, line.b)
    end
    return true
end

-- Login, the option and profile changes all come here. The hooks are added
-- the first time it is switched on; the game has no way to remove them, so
-- switching off just stops them drawing.
function CUI._applyUpgradeTooltips()
    on = CUI.QoLExtrasGet("upgradeTooltips") == true
    if not on or hooked then return end
    hooked = true
    local Q = Enum.ItemQuality
    QUALITY = {
        Explorer = Q.Poor,
        Adventurer = Q.Common,
        Veteran = Q.Uncommon,
        Champion = Q.Rare,
        Hero = Q.Epic,
        Myth = Q.Legendary,
    }
    -- Takes over the upgrade line only: neither the game's data nor its text is changed.
    TooltipDataProcessor.AddLinePreCall(
        Enum.TooltipDataLineType.ItemUpgradeLevel,
        function(tooltip) return Annotate(tooltip) end
    )
    TooltipDataProcessor.AddLinePostCall(
        Enum.TooltipDataLineType.ItemLevel,
        function(tooltip) Annotate(tooltip, true) end
    )
end
