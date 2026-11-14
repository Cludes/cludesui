if CUI_CLIENT_BLOCKED then
    return
end
local CUI = CludesUI
if CUI.IS_FOREVER then
    return
end

local enabled, installed = false, false
local qualities

-- Built lines by item link, one table per callback (false = keep Blizzard's
-- line). A shown tooltip is rebuilt every 0.2 s and every gear tooltip passes the
-- item-level callback, so each link is worked out once. The link carries the
-- item's bonuses and upgrade rank; the season tables, quality colours and crest
-- names are fixed for the session. A read that meets a secret value caches nothing.
local MEMO_MAX = 200
local memoPre, memoPost, memoN = {}, {}, 0

-- The line for link, false to keep Blizzard's, nil while a value it needs is secret
local function Build(calc, itemLink, fallback, payload)
    if fallback then
        if not calc:GetAscendantBonus(itemLink) then
            return false
        end
        if not canaccessallvalues(payload.lines) or not payload.lines then
            return nil
        end
        for _, line in ipairs(payload.lines) do
            if not canaccessallvalues(line) or not canaccessallvalues(line.type) then
                return nil
            end
            if line.type == Enum.TooltipDataLineType.ItemUpgradeLevel then
                return false
            end
        end
    end
    local details = C_Item.GetItemUpgradeInfo(itemLink)
    if not canaccessallvalues(details) then
        return nil
    end
    local rank, maxRank, cap, name
    if details then
        rank, maxRank, cap, name =
            details.currentLevel, details.maxLevel, details.maxItemLevel, details.trackString
    end
    if not canaccessallvalues(rank, maxRank, cap, name) then
        return nil
    end

    local level = C_Item.GetDetailedItemLevelInfo(itemLink)
    if not canaccessallvalues(level) then
        return nil
    end

    local key = CUI.UPGRADE_TRACK_KEYS[name or ""]
    -- shortcut: leave unmatched seasons/tracks unchanged; update shared calculator data for new seasons.
    local minLevel, maxLevel, displayRank, displayMax, ascendant =
        calc:GetItemUpgradeRange(itemLink, key, rank, maxRank, level, cap)
    if not minLevel then
        return false
    end
    key = key or (ascendant and ascendant.track)
    if not name or name == "" then
        name = CUI.L(key)
    end
    local quality = qualities[key]
    if not quality then
        return false
    end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    local textValue = CludesUI.Lf(
        "%1$d/%2$d %3$s %4$s",
        displayRank,
        displayMax,
        name,
        CUI.COLOR_CODES.WHITE .. "(" .. minLevel .. "-" .. maxLevel .. ")|r"
    )
    local crest
    if displayRank < displayMax then
        local currency = C_CurrencyInfo.GetCurrencyInfo(calc.Data.tracks[key].currID)
        if not canaccessallvalues(currency) then
            return nil
        end
        if currency and canaccessallvalues(currency.name, currency.iconFileID) and currency.name then
            crest = currency.name
            if currency.iconFileID then
                crest = CreateSimpleTextureMarkup(currency.iconFileID, 14, 14) .. " " .. crest
            end
        end
    end
    return { text = textValue, r = r, g = g, b = b, crest = crest }
end

local function OnUpgradeLine(tooltip, fallback)
    if not enabled or tooltip:IsForbidden() or tooltip:IsProtected() then
        return
    end
    local processing = tooltip:GetProcessingTooltipInfo()
    if not canaccessallvalues(processing) or not processing then
        return
    end
    local payload = processing.tooltipData
    if not canaccessallvalues(payload) or not payload then
        return
    end
    -- Appended item data must not annotate the primary item's tooltip twice.
    if tooltip:GetPrimaryTooltipData() ~= payload then
        return
    end
    if not canaccessallvalues(payload.guid, payload.hyperlink, payload.overrideItemLevel) then
        return
    end
    -- Preview overrides can differ from the hyperlink's actual item level.
    if payload.overrideItemLevel and payload.overrideItemLevel > 0 then
        return
    end
    local itemLink = payload.hyperlink
    if payload.guid and payload.guid ~= "" then
        itemLink = C_Item.GetItemLinkByGUID(payload.guid)
    end
    if not canaccessallvalues(itemLink) or type(itemLink) ~= "string" or itemLink == "" then
        return
    end

    local calc = CUIUpgCalc
    if not calc or not calc.GetItemUpgradeRange then
        return
    end
    local memo = fallback and memoPost or memoPre
    local line = memo[itemLink]
    if line == nil then
        line = Build(calc, itemLink, fallback, payload)
        if line == nil then
            return
        end
        if memoN >= MEMO_MAX then
            wipe(memoPre)
            wipe(memoPost)
            memoN = 0
        end
        memo[itemLink] = line
        memoN = memoN + 1
    end
    if not line then
        return
    end
    if line.crest then
        tooltip:AddDoubleLine(line.text, line.crest, line.r, line.g, line.b, 1, 1, 1)
    else
        tooltip:AddLine(line.text, line.r, line.g, line.b)
    end
    return true
end

-- Login, option changes and profile swaps share this lazy registration path.
function CUI._applyUpgradeTooltips()
    enabled = CUI.QoLExtrasGet("upgradeTooltips") == true
    -- Blizzard exposes no removal API; disabling leaves only the enabled guard.
    if enabled and not installed then
        installed = true
        qualities = {
            Explorer = Enum.ItemQuality.Poor,
            Adventurer = Enum.ItemQuality.Common,
            Veteran = Enum.ItemQuality.Uncommon,
            Champion = Enum.ItemQuality.Rare,
            Hero = Enum.ItemQuality.Epic,
            Myth = Enum.ItemQuality.Legendary,
        }
        -- Consume only the upgrade line; do not mutate Blizzard's tooltip data or font strings.
        TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.ItemUpgradeLevel, function(tooltip)
            return OnUpgradeLine(tooltip)
        end)
        -- Terminal upgrades may omit the native upgrade line entirely.
        TooltipDataProcessor.AddLinePostCall(Enum.TooltipDataLineType.ItemLevel, function(tooltip)
            OnUpgradeLine(tooltip, true)
        end)
    end
end
