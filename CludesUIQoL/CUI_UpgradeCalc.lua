if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- no item upgrade system on WoW Forever: no frame, no DB, no equipment listener; the QoL Upgrader tab is not registered there (every reader of CUIUpgCalc / CUIUpgCalcFrame nil-guards)
-------------------------------------------------------------------------------
--  CUI_UpgradeCalc.lua  (part of CludesUIQoL)
--  Gear upgrade planner: data tables, game logic, and calculator UI.
--  Frame: CUIUpgCalcFrame | Slash: /cuic
-------------------------------------------------------------------------------

CUIUpgCalc = CUIUpgCalc or {}
CUIUpgCalc.Data = {}

local Calc = CUIUpgCalc
local Data = CUIUpgCalc.Data
local CUI = CludesUI
local Pix = CUI.PP

local function Blocked()
    return InCombatLockdown() or (CUI.InProtectedInstance())
end

-------------------------------------------------------------------------------
--  DATA
-------------------------------------------------------------------------------

-- ── SEASON UPDATE: replace all values in Data.tracks each new season. ────────
-- Per track: crestName (tooltip display name),
-- hexColor (UI tint, can stay if the crest colour is unchanged), currID (currency
-- ID from Blizzard — check Wowhead or /dump C_CurrencyInfo.GetCurrencyInfo(id)),
-- ranks (ilvl at each of the 6 upgrade ranks, lowest to highest).
-- Add or remove tracks from Data.trackOrder to match the season's track list.
-- Midnight S2: wago.tools ItemBonusListGroupEntry -> ItemBonus -> ItemScalingConfig (12.1.5).
Data.tracks = {
    Adventurer = {
        crestName = "Adventurer Mistcrest",
        hexColor = "|cff1eff00",
        currID = 3442,
        tier = 1,
        ranks = { 266, 269, 272, 276, 279, 282 },
    },
    Veteran = {
        crestName = "Veteran Mistcrest",
        hexColor = "|cff0070dd",
        currID = 3443,
        tier = 2,
        ranks = { 279, 282, 285, 289, 292, 295 },
    },
    Champion = {
        crestName = "Champion Mistcrest",
        hexColor = "|cffa335ee",
        currID = 3444,
        tier = 3,
        ranks = { 292, 295, 298, 302, 305, 308 },
    },
    Hero = {
        crestName = "Hero Mistcrest",
        manualAdds = true,
        ascendantBonus = 12848,
        hexColor = "|cffff8000",
        currID = 3445,
        tier = 4,
        ranks = { 305, 308, 311, 315, 318, 321 },
    },
    Myth = {
        crestName = "Myth Mistcrest",
        manualAdds = true,
        ascendantBonus = 12856,
        hexColor = "|cffffd100",
        currID = 3446,
        tier = 5,
        ranks = { 318, 321, 324, 328, 331, 334 },
    },
}

Data.trackOrder = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- All equippable character slot IDs (paper-doll order; excludes ammo/relic).
Data.equipSlots = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Human-readable slot names keyed by slot ID.
Data.slotNames = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Cloak",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- SEASON UPDATE: the season's Ascendant upgrade bonus IDs and their caps.
-- Bonus IDs: Wago 12.1.5; caps include the October 23 Myth hotfix.
-- These are terminal upgrades, not a flat bonus applied to every rank or slot.
Data.ascendantBonuses = {
    [12848] = { track = "Hero", cap = 328 }, -- Ascendant Venomstone
    [12856] = { track = "Myth", cap = 341 }, -- Ascendant Venomstone
    [13848] = { track = "Myth", cap = 344 }, -- existing special Myth upgrade
    [13852] = { crafted = true, Hero = 325, Myth = 337 }, -- Venomstone: Tidal Crafted
}

function Calc:GetAscendantBonus(itemLink)
    if not canaccessallvalues(itemLink) or type(itemLink) ~= "string" then
        return nil
    end
    local payload = itemLink:match("item:([^|]+)")
    if not payload then
        return nil
    end
    local index, lastBonus = 0, 13
    for field in (payload .. ":"):gmatch("([^:]*):") do
        index = index + 1
        if index == 13 then
            lastBonus = 13 + (tonumber(field) or 0)
        elseif index > 13 then
            if index > lastBonus then
                break
            end
            local bonus = Data.ascendantBonuses[tonumber(field)]
            if bonus then
                return bonus
            end
        end
    end
end

-- Returns min/potential-max item levels, display rank/count and applied Ascendant metadata.
function Calc:GetItemUpgradeRange(itemLink, trackKey, rankNum, topRank, level, cap)
    if not canaccessallvalues(itemLink, trackKey, rankNum, topRank, level, cap) then
        return
    end
    local bonus = self:GetAscendantBonus(itemLink)
    trackKey = trackKey or (bonus and bonus.track)
    local trackData = Data.tracks[trackKey or ""]
    local rankList = trackData and trackData.ranks
    if not rankList then
        return
    end
    if bonus then
        if bonus.track ~= trackKey or level ~= bonus.cap then
            return
        end
        if cap and cap ~= 0 and cap ~= rankList[#rankList] and cap ~= bonus.cap then
            return
        end
        return rankList[1], bonus.cap, #rankList, #rankList, bonus
    end
    if not rankNum or topRank ~= #rankList or rankNum < 1 or rankNum > topRank or level ~= rankList[rankNum] then
        return
    end
    local maxLevel = rankList[topRank]
    local potential = trackData.ascendantBonus and Data.ascendantBonuses[trackData.ascendantBonus]
    if potential then
        local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemLink)
        if
            canaccessallvalues(equipLoc, classID)
            and (
                classID == Enum.ItemClass.Weapon
                or equipLoc == "INVTYPE_NECK"
                or equipLoc == "INVTYPE_TRINKET"
                or equipLoc == "INVTYPE_SHIELD"
                or equipLoc == "INVTYPE_HOLDABLE"
            )
        then
            -- Include the one-time Ascension ceiling without marking it as applied.
            maxLevel = potential.cap
        end
    end
    if cap and cap ~= 0 and cap ~= rankList[topRank] and cap ~= maxLevel then
        return
    end
    return rankList[1], maxLevel, rankNum, topRank
end

-- Reverse lookup: currencyID → crestName (built after track table is complete).
local _currIDToCrestName = {}
for _, trackData in pairs(Data.tracks) do
    if trackData.currID and trackData.currID > 0 then
        _currIDToCrestName[trackData.currID] = trackData.crestName
    end
end

-- SEASON UPDATE: update these ilvl steps to match the Spark-crafted tier ilvls
-- for the new season (Season 2: T1-T5 = 292/296/299/302/305, warcraft.wiki.gg).
-- Referenced in GetCraftedInfo; hoisted here so it is allocated once, not per call.
Data.craftedTierSteps = { 292, 296, 299, 302, 305 }

-- SEASON UPDATE: update minIlvl/maxIlvl each new season to match crafted item ilvl caps
-- (Season 2: Hero crest crafts 305-318, Myth crest crafts 318-331).
-- minIlvl: lowest ilvl at which an item belongs to this crafted band (checked highest-first).
-- maxIlvl: ilvl ceiling for crafted items in this band.
-- Ordered highest-first so CraftedBandFromIlvl can short-circuit on the first match.
Data.craftedBands = {
    { name = "Myth", minIlvl = 318, maxIlvl = 331 },
    { name = "Hero", minIlvl = 305, maxIlvl = 318 },
    { name = "None", minIlvl = 0, maxIlvl = 305 },
}
-- Reverse lookup: band name → band data (for O(1) access in ScanItemLink).
Data.craftedBandByName = {}
for _, b in ipairs(Data.craftedBands) do
    Data.craftedBandByName[b.name] = b
end

-------------------------------------------------------------------------------
--  CORE
-------------------------------------------------------------------------------

-- Pointer to the active CludesUIDB profile slice for this module.
-- Set on PLAYER_LOGIN once the profile system initialises.
-- All persistent reads/writes go through DB() and Opts() which use this.
local _cuicProfileRef = nil
-- Cached direct references to the sub-tables, set once in PLAYER_LOGIN so that
-- every subsequent DB()/Opts() call is a simple local read with no table traversal.
local _dbCache = nil
local _optsCache = nil
-- (Character key used only locally in PLAYER_LOGIN to index per-character storage;
--  not retained as a module variable since _dbCache is set directly.)

local function DB()
    if _dbCache then
        return _dbCache
    end
    local storage
    if _cuicProfileRef then
        storage = _cuicProfileRef
    else
        CludesUIQoLDB = CludesUIQoLDB or {}
        storage = CludesUIQoLDB
    end
    storage.upgradeCalc = storage.upgradeCalc or {}
    local saved = storage.upgradeCalc
    saved.cache = saved.cache or { slots = {}, ts = 0 }
    saved.calibrated = saved.calibrated or false
    saved.queue = saved.queue or {}
    saved.crestManualAdds = saved.crestManualAdds or {}
    return saved
end

local function Opts()
    if _optsCache then
        return _optsCache
    end
    local storage
    if _cuicProfileRef then
        storage = _cuicProfileRef
    else
        CludesUIQoLDB = CludesUIQoLDB or {}
        storage = CludesUIQoLDB
    end
    storage.upgradeCalcOpts = storage.upgradeCalcOpts or {}
    return storage.upgradeCalcOpts
end

-- Exposed so CUI_UpgradeCalc_Options.lua can always read the live opts table,
-- regardless of whether the profile system has been initialised yet.
Calc.GetOptsDB = function()
    return Opts()
end
Calc.GetCalcDB = function()
    return DB()
end -- exposed for Options reset helper

-- Slot IDs grouped by category, used for filter settings.
Data.slotGroups = {
    Armour = { 1, 3, 5, 6, 7, 8, 9, 10, 15 }, -- head, shoulder, chest, waist, legs, feet, wrist, hands, back
    Jewellery = { 2, 11, 12 }, -- neck, ring 1, ring 2
    Trinkets = { 13, 14 },
    Weapons = { 16, 17 },
}
-- Build reverse lookup: slotID -> group name
Data.slotToGroup = {}
for grp, ids in pairs(Data.slotGroups) do
    for _, ident in ipairs(ids) do
        Data.slotToGroup[ident] = grp
    end
end

-- C_TooltipInfo-based scanning. NEVER create a scanning GameTooltipTemplate
-- from Lua -- it taints the tooltip system. See CLAUDE.md / reference_tooltip_template_taint.
local function GetTooltipLines(itemLink)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
        return nil
    end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not data then
        return nil
    end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    return data.lines
end

local function ForEachTooltipLine(lineList, func)
    if not lineList then
        return
    end
    for _, line in ipairs(lineList) do
        local textValue = line.leftText
        if textValue and textValue ~= "" then
            func(textValue)
        end
    end
end

-- Strip WoW inline colour codes from a string.
local function Plain(text)
    return text and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or ""
end

-- Returns { slot, link, ilvl } for every equipped item on `unit` (default "player").
function Calc:GetEquippedGear(unitToken)
    unitToken = unitToken or "player"
    local gear = {}
    for _, slot in ipairs(Data.equipSlots) do
        local itemLink = GetInventoryItemLink(unitToken, slot)
        if itemLink then
            local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink) or 0
            gear[#gear + 1] = { slot = slot, link = itemLink, ilvl = itemLevel }
        end
    end
    return gear
end

Calc._tipCache = {} -- [link] = { track, rank, maxRank, isCrafted, craftBand, craftMaxIlvl, isVoidforged, ascendant }

-- "Made by <name>" as a Lua pattern, built from the client's own global string
-- so it matches on every locale. Colour codes are stripped first because the
-- lines we test have already been through Plain(). Falls back to the enUS literal.
local CREATED_BY_PATTERN =
    Plain(ITEM_CREATED_BY or "Made by %s"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".+")

function Calc:ScanItemLink(itemLink)
    if not itemLink then
        return nil
    end
    local cached = Calc._tipCache[itemLink]
    if cached then
        return cached
    end

    local outcome = {
        track = nil,
        rank = nil,
        maxRank = nil,
        isCrafted = false,
        craftBand = nil,
        craftMaxIlvl = nil,
        isVoidforged = false,
    }

    -- Primary source: the upgrade API, which reports the track in the client's
    -- locale. CludesUI.GetUpgradeTrackKey translates it back to the English
    -- key our season tables use. Tooltip text is only a fallback -- parsing it
    -- directly is enUS-only and silently mislabels every item on other clients.
    local apiTrack, apiRank, apiMax = nil, nil, nil
    if CludesUI and CludesUI.GetUpgradeTrackKey then
        apiTrack, apiRank, apiMax = CludesUI.GetUpgradeTrackKey(itemLink)
    end

    local lineList = GetTooltipLines(itemLink)
    local foundTrack, foundRank, foundVoid = apiTrack, apiRank, false
    ForEachTooltipLine(lineList, function(textValue)
        if not foundTrack and textValue:find("Upgrade Level") then
            local t, region = textValue:match("Upgrade Level:%s+(%a+)%s+(%d+)/%d+")
            if t then
                foundTrack = t
                foundRank = tonumber(region)
            end
        end
        -- enUS-only: no API exposes the Voidforged modifier. On other locales
        -- this stays false and the ilvl-band fallback covers the max ilvl.
        if not foundVoid and Plain(textValue):find("Ascendant Voidforged") then
            foundVoid = true
        end
    end)
    outcome.track = foundTrack
    outcome.rank = foundRank
    outcome.maxRank = (foundTrack == apiTrack) and apiMax or nil
    outcome.isVoidforged = foundVoid
    local ascendant = self:GetAscendantBonus(itemLink)
    outcome.ascendant = ascendant
    if ascendant and ascendant.track then
        local trackKey = foundTrack or ascendant.track
        local level = C_Item.GetDetailedItemLevelInfo(itemLink)
        local _, _, rankNum, topRank = self:GetItemUpgradeRange(itemLink, trackKey, foundRank, apiMax, level)
        if rankNum then
            outcome.track, outcome.rank, outcome.maxRank = trackKey, rankNum, topRank
        end
    end

    -- Only scan the crafted tooltip if no upgrade track was found.
    -- Reuse the same lines -- C_TooltipInfo returns all tooltip data in one call.
    if not outcome.track then
        local isCrafted, sawHero, sawMyth = ascendant and ascendant.crafted or false, false, false
        ForEachTooltipLine(lineList, function(raw)
            local text = Plain(raw)
            if
                text:find(CREATED_BY_PATTERN)
                or text:find("Crafted")
                or text:find("Optional Reagents")
                or text:find("Recrafting")
                or text:find("Made by")
            then
                isCrafted = true
            end
            if text:find("Hero") then
                sawHero = true
            end
            if text:find("Myth") then
                sawMyth = true
            end
        end)
        outcome.isCrafted = isCrafted

        if isCrafted then
            local bname = sawMyth and "Myth" or sawHero and "Hero" or "None"
            local bdata = Data.craftedBandByName[bname]
            outcome.craftBand = bname
            outcome.craftMaxIlvl = bdata and bdata.maxIlvl or Data.craftedBandByName.None.maxIlvl
        end
    end

    Calc._tipCache[itemLink] = outcome
    return outcome
end

-- Returns: trackName (string|nil), rank (number|nil), maxRank (number|nil).
function Calc:GetItemTrackAndRank(itemLink)
    local region = self:ScanItemLink(itemLink)
    return region and region.track, region and region.rank, region and region.maxRank
end

-- Number of ranks in a track: the API's maxLevel when we have it, otherwise the
-- season table's length. Data.tracks has no Explorer entry, so td may be nil.
local function TrackMaxRank(trackData, topRank)
    return topRank or (trackData and #trackData.ranks) or 6
end

-- Shared helper: given an ilvl, returns band ("Myth"/"Hero"/"None") and maxIlvl.
-- Called by both GetCraftedInfo (tooltip fallback) and the PopulateGear heuristic
-- so the two code paths can never silently diverge on a season update.
-- Thresholds are read from Data.craftedBands — update that table each new season.
local function CraftedBandFromIlvl(itemLevel)
    for _, bandTex in ipairs(Data.craftedBands) do
        if itemLevel >= bandTex.minIlvl then
            return bandTex.name, math.max(bandTex.maxIlvl, itemLevel)
        end
    end
    -- Fallback: treat as base crafted (should never be reached; ilvl < 0 is impossible).
    local base = Data.craftedBandByName["None"]
    return "None", math.max(base and base.maxIlvl or 0, itemLevel)
end

-- Returns: isCrafted, band, tier, maxIlvl.
function Calc:GetCraftedInfo(itemLink, itemLevel)
    local region = self:ScanItemLink(itemLink)
    if not region or not region.isCrafted then
        return false
    end
    local bandTex, topIlvl = region.craftBand or "None", region.craftMaxIlvl or Data.craftedBandByName.None.maxIlvl

    -- If tooltip gave no band keywords, fall back to ilvl thresholds via shared helper.
    -- (See CraftedBandFromIlvl above for the SEASON UPDATE note.)
    if region.craftBand == "None" then
        bandTex, topIlvl = CraftedBandFromIlvl(itemLevel)
    end

    local ascendant = region.ascendant
    if ascendant and canaccessallvalues(itemLevel) and itemLevel and itemLevel > 0 then
        if itemLevel == ascendant.Hero then
            bandTex = "Hero"
        elseif itemLevel == ascendant.Myth then
            bandTex = "Myth"
        end
        topIlvl = itemLevel
    end

    local tier
    if bandTex == "None" then
        local steps = Data.craftedTierSteps
        local best, bestDist = 1, math.huge
        for i, s in ipairs(steps) do
            local skinData = math.abs(itemLevel - s)
            if skinData < bestDist then
                bestDist = skinData
                best = i
            end
        end
        tier = best
    end
    return true, bandTex, tier, topIlvl
end

-- Returns true when the item has "Ascendant Voidforged" in its tooltip.
-- SEASON UPDATE: if the Voidforged modifier is renamed or replaced, update the
-- search string below to match the new tooltip text.
function Calc:IsVoidforged(itemLink)
    local region = self:ScanItemLink(itemLink)
    return region and region.isVoidforged or false
end

-- Returns a table mapping crestName -> { quantity, cap, earned } for each track.
function Calc:GetPlayerCrests()
    local owned = {}
    for _, trackData in pairs(Data.tracks) do
        if trackData.currID and trackData.currID > 0 then
            local details = C_CurrencyInfo.GetCurrencyInfo(trackData.currID)
            if details then
                owned[trackData.crestName] = {
                    quantity = details.quantity or 0,
                    cap = (details.maxQuantity and details.maxQuantity > 0) and details.maxQuantity or nil,
                    earned = details.totalEarned or 0,
                }
            end
        end
    end
    return owned
end

-- Returns detailed cost info for a single item.
-- Non-crafted: trackName, rank, crestCost, maxIlvl
-- Crafted:     "Crafted", nil, nil, maxIlvl, tierLabel, band
function Calc:GetItemUpgradeCost(entry)
    if not canaccessallvalues(entry.ilvl) then
        return nil
    end
    local trackKey, rankNum, topRank = self:GetItemTrackAndRank(entry.link)

    if not trackKey then
        local isCrafted, bandTex, tier, topIlvl = self:GetCraftedInfo(entry.link, entry.ilvl)
        if isCrafted then
            local labelText = (bandTex == "Hero" and "Hero Craft")
                or (bandTex == "Myth" and "Myth Craft")
                or (tier and "T" .. tier .. "/5")
                or "Crafted"
            return "Crafted", nil, nil, topIlvl, labelText, bandTex
        end
        return nil
    end

    local trackData = Data.tracks[trackKey]
    if not trackData then
        return nil
    end

    local saved = DB()

    local _, expectedMax = self:GetItemUpgradeRange(entry.link, trackKey, rankNum, topRank, entry.ilvl)
    expectedMax = expectedMax or math.max(trackData.ranks[#trackData.ranks], entry.ilvl)

    -- Priority 1: exact costs from Upgrader NPC API (calibrated).
    local slotCache = saved.calibrated and saved.cache.slots[entry.slot]
    if slotCache and slotCache.crestAmounts and slotCache.link == entry.link then
        local exactCrests = 0
        for _, val in pairs(slotCache.crestAmounts) do
            exactCrests = exactCrests + val
        end
        return trackKey, rankNum, exactCrests, expectedMax
    end

    -- Priority 2: raw estimate (upgrader scan not available for this slot).
    local upgradesLeft = math.max(0, TrackMaxRank(trackData, topRank) - (rankNum or 0))
    return trackKey, rankNum, upgradesLeft * 20, expectedMax
end

function Calc:IsUpgraderOpen()
    return (ItemUpgradeFrame and ItemUpgradeFrame.IsShown and ItemUpgradeFrame:IsShown()) or false
end

local function SelectSlotInUpgrader(loc)
    -- Never touch protected API in combat; would cause taint.
    if not loc or Blocked() then
        return false
    end
    if C_ItemUpgrade and C_ItemUpgrade.ClearItemUpgrade then
        pcall(C_ItemUpgrade.ClearItemUpgrade)
    end
    for _, fnName in ipairs({ "SetItemUpgradeFromItemLocation", "SetItemUpgradeFromLocation" }) do
        if C_ItemUpgrade and C_ItemUpgrade[fnName] then
            if pcall(C_ItemUpgrade[fnName], loc) then
                return true
            end
        end
    end
    return false
end

local function TallySlotCosts(details)
    local crestCounts = {}
    local curr = details.currUpgrade or 0
    for _, lvl in ipairs(details.upgradeLevelInfos or {}) do
        if (lvl.upgradeLevel or 0) > curr then
            for _, cc in ipairs(lvl.currencyCostsToUpgrade or {}) do
                crestCounts[cc.currencyID] = (crestCounts[cc.currencyID] or 0) + (cc.cost or 0)
            end
        end
    end
    return crestCounts
end

-- Scans every equipped slot at the Upgrader NPC, building an accurate cost cache.
-- Single-pass: selects each slot via SelectSlotInUpgrader, waits 0.3 s for the
-- Upgrader frame to populate async data for that slot, then reads the result via
-- C_ItemUpgrade.GetItemUpgradeItemInfo() (no arguments — returns data for the
-- currently-selected slot). Passing a loc argument is silently ignored by the API.
function Calc:ScanEquippedAtUpgrader(onDone)
    if Blocked() then
        if onDone then
            onDone(false)
        end
        return
    end
    if Calc._scanning then
        if onDone then
            onDone(false)
        end
        return
    end
    local saved = DB()
    if not self:IsUpgraderOpen() then
        if onDone then
            onDone(false)
        end
        return
    end

    Calc._scanning = true
    Calc._tipCache = {}

    -- Build into a fresh scratch table; only swap into db.cache on success.
    local newSlots = {}
    local slots = Data.equipSlots
    local sum = #slots

    local function onScanDone(success)
        Calc._scanning = false
        if success then
            saved.cache = { slots = newSlots, ts = time() }
            saved.calibrated = true
        end
        if onDone then
            onDone(success)
        end
    end

    local function saveSlotInfo(slotId, details)
        if not (details and details.upgradeLevelInfos) then
            return
        end
        local crestCounts = TallySlotCosts(details)
        local itemLink = GetInventoryItemLink("player", slotId)
        newSlots[slotId] = {
            link = itemLink,
            crestAmounts = crestCounts,
        }
    end

    -- Single-pass scan: select each slot, wait 0.3 s for the Upgrader frame to
    -- populate async data, then call GetItemUpgradeItemInfo() with NO arguments
    -- (the API returns data for whichever slot is currently selected; passing a
    -- loc argument is silently ignored and the call returns nil).
    local si = 1
    local function scanNext()
        if Blocked() then
            onScanDone(false)
            return
        end
        if si > sum then
            onScanDone(true)
            return
        end
        local slotId = slots[si]
        local loc = ItemLocation and ItemLocation:CreateFromEquipmentSlot(slotId)
        if loc and SelectSlotInUpgrader(loc) then
            -- Wait for the Upgrader frame to load this slot's data, then read it.
            C_Timer.After(0.3, function()
                if Blocked() then
                    onScanDone(false)
                    return
                end
                local details = C_ItemUpgrade
                    and C_ItemUpgrade.GetItemUpgradeItemInfo
                    and C_ItemUpgrade.GetItemUpgradeItemInfo()
                saveSlotInfo(slotId, details)
                si = si + 1
                scanNext()
            end)
        else
            -- Slot has no item or select failed; skip it.
            si = si + 1
            C_Timer.After(0.05, scanNext)
        end
    end

    scanNext()
end

function Calc:ClearCache()
    local saved = DB()
    saved.cache = { slots = {}, ts = 0 }
    saved.calibrated = false
end

-- Rescans a single slot at the Upgrader NPC and updates the cache entry for it.
-- Used after an upgrade so the display reflects the new remaining cost immediately.
-- Calls onDone(ok) when finished; ok=false if the NPC is closed, combat fires, or
-- the API returns no data for the slot.
function Calc:RescanSlot(slotId, onDone)
    if Blocked() or Calc._scanning then
        if onDone then
            onDone(false)
        end
        return
    end
    if not self:IsUpgraderOpen() then
        if onDone then
            onDone(false)
        end
        return
    end
    local loc = ItemLocation and ItemLocation:CreateFromEquipmentSlot(slotId)
    if not loc or not SelectSlotInUpgrader(loc) then
        if onDone then
            onDone(false)
        end
        return
    end
    -- Guard the async window with _scanning so a second upgrade event within
    -- 0.3 s can't launch a concurrent rescan and overwrite the wrong slot.
    Calc._scanning = true
    local saved = DB()
    C_Timer.After(0.3, function()
        Calc._scanning = false
        if Blocked() then
            if onDone then
                onDone(false)
            end
            return
        end
        local details = C_ItemUpgrade
            and C_ItemUpgrade.GetItemUpgradeItemInfo
            and C_ItemUpgrade.GetItemUpgradeItemInfo()
        if details and details.upgradeLevelInfos then
            local crestCounts = TallySlotCosts(details)
            saved.cache = saved.cache or { slots = {}, ts = 0 }
            saved.cache.slots = saved.cache.slots or {}
            saved.cache.slots[slotId] = {
                link = GetInventoryItemLink("player", slotId),
                crestAmounts = crestCounts,
            }
        end
        if onDone then
            onDone(true)
        end
    end)
end

-------------------------------------------------------------------------------
--  UI
-------------------------------------------------------------------------------

local function SolidTex(p, l, red, green, blue, a)
    return CUI.SolidTex(p, l, red, green, blue, a)
end

local function MFont(p, s, _, red, green, blue, a)
    local fontStr = p:CreateFontString(nil, "OVERLAY")
    CludesUI.ApplyModuleFont(fontStr, nil, s, "extras")
    if red then
        fontStr:SetTextColor(red, green or 1, blue or 1, a or 1)
    end
    return fontStr
end

local G = CUI.CLUDES_GREEN
local ROW_H, FRAME_W, FRAME_H = 20, 860, 730

-- Tile layout constants
local TILE_W = 183
local TILE_H = 50 -- tile frame height
local TILE_STEP = TILE_H + 5 -- row stride: tile height + gap (used in all layout math)
local TILE_COLS = 3
local TILE_GAP = 5
local TILE_ROW_W = TILE_COLS * TILE_W + (TILE_COLS - 1) * TILE_GAP -- 559
local QUEUE_X_OFF = TILE_ROW_W + 16 -- 575
local QUEUE_W = FRAME_W - 20 - QUEUE_X_OFF -- 265

-- Per-track RGB accent colours used on tile left-edge bars
local TRACK_RGB = {
    Adventurer = { 0.12, 1.0, 0.0 },
    Veteran = { 0.0, 0.44, 0.87 },
    Champion = { 0.64, 0.21, 0.93 },
    Hero = { 1.0, 0.50, 0.0 },
    Myth = { 1.0, 0.82, 0.0 },
    Voidforged = { 0.55, 0.0, 1.0 },
}

local frame = CreateFrame("Frame", "CUIUpgCalcFrame", UIParent)
Pix.Size(frame, FRAME_W, FRAME_H)
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -40)
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

-- Session snap: dock beside CharacterFrame on each open until the user drags.
local _sessionUnpinned = false
local _cfSnapHooked = false

local function ShouldSnapToCharacterFrame()
    if _sessionUnpinned then
        return false
    end
    local castFrame = _G.CharacterFrame
    return castFrame ~= nil and castFrame:IsShown()
end

local function DockToCharacterFrame()
    local castFrame = _G.CharacterFrame
    if not castFrame or not castFrame:IsShown() then
        return
    end
    local margin = 4
    local cs = castFrame:GetEffectiveScale() or 1
    local es = frame:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wAbs = (frame:GetWidth() or 0) * es
    local leftRoom = (castFrame:GetLeft() or 0) * cs
    local rightRoom = (GetScreenWidth() or 0) * ues - (castFrame:GetRight() or 0) * cs
    local minRoom = wAbs + margin * es
    local leftFits = leftRoom >= minRoom
    local rightFits = rightRoom >= minRoom
    local dockLeft
    if rightFits then
        dockLeft = false
    elseif leftFits then
        dockLeft = true
    else
        dockLeft = leftRoom >= rightRoom
    end
    frame:ClearAllPoints()
    if dockLeft then
        frame:SetPoint("TOPRIGHT", castFrame, "TOPLEFT", -margin, 0)
    else
        frame:SetPoint("TOPLEFT", castFrame, "TOPRIGHT", margin, 0)
    end
end

local function TrySnapToCharacterFrame()
    if frame:IsShown() and ShouldSnapToCharacterFrame() then
        DockToCharacterFrame()
    end
end

local function InstallCharacterFrameSnapHooks()
    if _cfSnapHooked then
        return
    end
    local castFrame = _G.CharacterFrame
    if not castFrame then
        return
    end
    _cfSnapHooked = true
    castFrame:HookScript("OnShow", TrySnapToCharacterFrame)
    hooksecurefunc(castFrame, "SetPoint", function()
        TrySnapToCharacterFrame()
    end)
    hooksecurefunc(castFrame, "SetScale", function()
        TrySnapToCharacterFrame()
    end)
end

frame:SetScript("OnDragStart", function(self)
    _sessionUnpinned = true
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
frame:Hide()

local fBg = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
fBg:SetAllPoints(frame)
fBg:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
fBg:SetTexCoord(0.25, 1, 0, 0.75)
local fBgOverlay = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
fBgOverlay:SetAllPoints(frame)
fBgOverlay:SetColorTexture(0, 0, 0, 0.5)

function Calc.ApplyBgOpacity()
    local options = Opts()
    local alpha = options and options.bgOpacity
    if alpha == nil then
        alpha = 50
    end
    fBgOverlay:SetColorTexture(0, 0, 0, alpha / 100)
end

function Calc.ApplyScale()
    local options = Opts()
    local scale = options and options.uiScale
    if scale == nil then
        scale = 100
    end
    frame:SetScale(scale / 100)
end

if CUI and CUI.PanelPP then
    CUI.PanelPP.CreateBorder(frame, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
end

local titleBg = SolidTex(frame, "BORDER", 0, 0, 0, 0.25)
Pix.Point(titleBg, "TOPLEFT", frame, "TOPLEFT", 1, -1)
Pix.Point(titleBg, "TOPRIGHT", frame, "TOPRIGHT", -1, 0)
Pix.Height(titleBg, 32)

local titleTxt = MFont(frame, 13, "OUTLINE", 1, 1, 1, 1)
Pix.Point(titleTxt, "TOPLEFT", frame, "TOPLEFT", 10, -10)
titleTxt:SetText(CUI.L("Upgrade Calculator"))

local closeBtn = CreateFrame("Button", nil, frame)
Pix.Size(closeBtn, 24, 24)
closeBtn:SetPoint("RIGHT", titleBg, "RIGHT", -5, 5)
local closeTxt = MFont(closeBtn, 16, "", 1, 1, 1, 0.75)
closeTxt:SetPoint("CENTER", -2, -3)
closeTxt:SetText("x")
closeBtn:SetScript("OnEnter", function()
    closeTxt:SetTextColor(1, 1, 1, 1)
end)
closeBtn:SetScript("OnLeave", function()
    closeTxt:SetTextColor(1, 1, 1, 0.75)
end)
closeBtn:SetScript("OnClick", function()
    frame:Hide()
end)

-- RegisterEscapeClose is created at PLAYER_LOGIN; deferred in _firstRunEvt below.

local tabY = -36

-- Top divider removed for cleaner look

-- Row helpers
local function MakeRow(hostFrame, cols, yOffset, isAlt)
    local row = {}
    if isAlt then
        local backdrop = SolidTex(hostFrame, "BACKGROUND", 0, 0, 0, 0.15)
        Pix.Point(backdrop, "TOPLEFT", hostFrame, "TOPLEFT", 0, yOffset)
        Pix.Point(backdrop, "TOPRIGHT", hostFrame, "TOPRIGHT", 0, yOffset)
        Pix.Height(backdrop, ROW_H)
        row.altBg = backdrop -- stored so PopulateGear can reposition and hide/show it
    end
    for _, colour in ipairs(cols) do
        local cell = MFont(hostFrame, 11, nil, 0.85, 0.85, 0.85, 1)
        Pix.Point(cell, "TOPLEFT", hostFrame, "TOPLEFT", colour.x + 4, yOffset - 2)
        Pix.Width(cell, colour.w - 8)
        cell:SetJustifyH(colour.align)
        row[colour.key] = cell
    end
    return row
end

local function MakeButton(hostFrame, labelText, wid, hgt, yOff, xOff)
    local button = CreateFrame("Button", nil, hostFrame)
    Pix.Size(button, wid, hgt)
    Pix.Point(button, "TOPLEFT", hostFrame, "TOPLEFT", xOff, yOff)
    local btnBg = SolidTex(button, "BACKGROUND", 0, 0, 0, 0.35)
    btnBg:SetAllPoints()
    local bb = CUI.MakeBorder(button, 0.2, 0.2, 0.2, 1)
    if bb.SetColor then
        bb:SetColor(0.2, 0.2, 0.2, 1)
    end
    local txt = MFont(button, 10, "OUTLINE", 1, 1, 1, 0.75)
    txt:SetAllPoints()
    txt:SetJustifyH("CENTER")
    txt:SetText(labelText)
    button:SetScript("OnEnter", function()
        txt:SetTextColor(1, 1, 1, 1)
    end)
    button:SetScript("OnLeave", function()
        txt:SetTextColor(1, 1, 1, 0.75)
    end)
    return button, txt
end

-- Character Pane ──────────────────────────────────────────────────────────────
frame.charPane = CreateFrame("Frame", nil, frame)
frame.charPane:SetAllPoints(frame)

local ilvlStatLbl = MFont(frame.charPane, 12, "OUTLINE", 1, 1, 1, 1)
Pix.Point(ilvlStatLbl, "TOPLEFT", frame.charPane, "TOPLEFT", 10, tabY - 11)
ilvlStatLbl:SetText(CUI.L("Current iLvl: -   Max Possible: -"))
local ilvlEstLbl = MFont(frame.charPane, 10, "OUTLINE", 0.53, 0.53, 0.53, 1)
Pix.Point(ilvlEstLbl, "LEFT", ilvlStatLbl, "RIGHT", 4, 0)
ilvlEstLbl:SetText(CUI.L(""))

local cc = CreateFrame("Frame", nil, frame.charPane)
Pix.Point(cc, "TOPLEFT", frame.charPane, "TOPLEFT", 10, tabY - 30)
Pix.Point(cc, "TOPRIGHT", frame.charPane, "TOPRIGHT", -10, tabY - 30)
Pix.Height(cc, FRAME_H - 100)

-- ── iLvl Timeline bar ──────────────────────────────────────────────────────────
-- iLvl timeline bar: same line as the stat label, starts after "(estimated)"
local tlTrack = SolidTex(frame.charPane, "BACKGROUND", 0, 0, 0, 0.3)
Pix.Point(tlTrack, "LEFT", ilvlEstLbl, "RIGHT", 10, 0)
Pix.Height(tlTrack, 10)
-- Right edge aligns with tile row right edge (cc x=10 + TILE_ROW_W)
tlTrack:SetPoint("RIGHT", frame.charPane, "LEFT", 10 + TILE_ROW_W, 0)

-- Fill lives inside a clip frame so it can't overflow the track
local tlClip = CreateFrame("Frame", nil, frame.charPane)
tlClip:SetPoint("TOPLEFT", tlTrack, "TOPLEFT", 0, 0)
tlClip:SetPoint("BOTTOMRIGHT", tlTrack, "BOTTOMRIGHT", 0, 0)
tlClip:SetClipsChildren(true)
local tlFill = SolidTex(tlClip, "ARTWORK", G.r, G.g, G.b, 0.9)
Pix.Point(tlFill, "TOPLEFT", tlClip, "TOPLEFT", 0, 0)
Pix.Point(tlFill, "BOTTOMLEFT", tlClip, "BOTTOMLEFT", 0, 0)
tlFill:SetWidth(1) -- updated each refresh

-- ── Tile frames ──────────────────────────────────────────────────────────────────
local ToggleTileQueue -- forward declaration (defined in queue section)

local tileFrames = {}
for i = 1, 18 do
    local button = CreateFrame("Button", nil, cc)
    Pix.Size(button, TILE_W, TILE_H)
    button:Hide()
    local backdrop = SolidTex(button, "BACKGROUND", 1, 1, 1, 0.05)
    backdrop:SetAllPoints(button)
    button.bg = backdrop
    -- Left accent bar (3 px, track colour)
    local accentBar = SolidTex(button, "BORDER", 0.5, 0.5, 0.5, 1)
    Pix.Point(accentBar, "TOPLEFT", button, "TOPLEFT", 0, 0)
    Pix.Point(accentBar, "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(Pix.mult * 3)
    accentBar:SetSnapToPixelGrid(false)
    accentBar:SetTexelSnappingBias(0)
    button.accentBar = accentBar
    -- Queue overlay: 50% black with "In Queue" text
    local queueOv = CreateFrame("Frame", nil, button)
    queueOv:SetAllPoints(button)
    queueOv:SetFrameLevel(button:GetFrameLevel() + 5)
    local queueOvBg = SolidTex(queueOv, "BACKGROUND", 0, 0, 0, 0.75)
    queueOvBg:SetAllPoints()
    local queueOvTxt = MFont(queueOv, 11, "OUTLINE", 1, 1, 1, 0.9)
    queueOvTxt:SetPoint("CENTER", queueOv, "CENTER", 0, 0)
    queueOvTxt:SetText(CUI.L("In Queue"))
    queueOv:Hide()
    button.selHL = queueOv
    -- Top-left: slot name
    local sLbl = MFont(button, 12, "OUTLINE", 0.9, 0.9, 0.9, 1)
    Pix.Point(sLbl, "TOPLEFT", button, "TOPLEFT", 7, -4)
    Pix.Width(sLbl, TILE_W - 82)
    sLbl:SetJustifyH("LEFT")
    button.sLbl = sLbl
    -- Top-right: current ^ max ilvl
    local iLbl = MFont(button, 11, "OUTLINE", 0.8, 0.8, 0.8, 1)
    Pix.Point(iLbl, "TOPRIGHT", button, "TOPRIGHT", -5, -4)
    Pix.Width(iLbl, 76)
    iLbl:SetJustifyH("RIGHT")
    button.iLbl = iLbl
    -- Bottom-left: track name
    local tLbl = MFont(button, 11, "OUTLINE", 0.55, 0.55, 0.55, 1)
    Pix.Point(tLbl, "BOTTOMLEFT", button, "BOTTOMLEFT", 7, 5)
    Pix.Width(tLbl, TILE_W - 82)
    tLbl:SetJustifyH("LEFT")
    button.tLbl = tLbl
    -- Bottom-right: rank badge
    local rLbl = MFont(button, 11, "OUTLINE", 0.8, 0.8, 0.8, 1)
    Pix.Point(rLbl, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 5)
    Pix.Width(rLbl, 76)
    rLbl:SetJustifyH("RIGHT")
    button.rLbl = rLbl

    button.tileEntry = nil

    -- Handlers wired ONCE here — no closures created during refresh.
    button:SetScript("OnClick", function(self)
        if self.tileEntry then
            ToggleTileQueue(self.tileEntry, self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.1)
        local e = self.tileEntry
        if not e or not CUI.ShowWidgetTooltip then
            return
        end
        local lineList = {}
        if e.isAtMax then
            lineList[#lineList + 1] = CUI.L("|cff20c020At maximum item level|r")
        elseif e.trackKey == "Crafted" then
            lineList[#lineList + 1] = CUI.L("Crafted item — cannot be upgraded here")
        elseif e.trackKey then
            local trackData = Data.tracks[e.trackKey]
            local snap = DB()
            local scroller = snap.calibrated and snap.cache.slots[e.slotID] or nil
            -- Discard cached entry if the item in that slot has changed since the scan.
            if scroller and scroller.link and scroller.link ~= (GetInventoryItemLink("player", e.slotID) or "") then
                scroller = nil
            end
            if scroller and scroller.crestAmounts and next(scroller.crestAmounts) then
                for cid, amount in pairs(scroller.crestAmounts) do
                    local crestName = _currIDToCrestName[cid]
                    if crestName and amount > 0 then
                        lineList[#lineList + 1] = amount .. "x  " .. CUI.L(crestName)
                    end
                end
            elseif (e.crestCost or 0) > 0 then
                lineList[#lineList + 1] = "~" .. e.crestCost .. "x  " .. CUI.L(trackData and trackData.crestName or "Crest")
                lineList[#lineList + 1] = CludesUI.COLOR_CODES.DIM
                    .. CUI.L("Scan at Upgrader for exact costs")
                    .. "|r"
            end
        end
        if #lineList > 0 then
            CUI.ShowWidgetTooltip(self, table.concat(lineList, "\n"))
        end
    end)
    button:SetScript("OnLeave", function(self)
        local e = self.tileEntry
        if not e then
            return
        end
        if e.isAtMax then
            self.bg:SetColorTexture(0.1, 0.4, 0.1, 0.2)
        elseif type(e.max) == "number" and (e.max - e.ilvl) >= 10 then
            self.bg:SetColorTexture(0.5, 0.1, 0.1, 0.2)
        else
            self.bg:SetColorTexture(0.5, 0.35, 0.05, 0.2)
        end
        CUI.HideWidgetTooltip()
    end)

    tileFrames[i] = button
end

-- Section header labels and group separator line (repositioned each refresh)
local sHdrNeeds = MFont(cc, 11, "OUTLINE", 1, 1, 1, 1)
local sHdrMax = MFont(cc, 10, "OUTLINE", 0.48, 0.48, 0.48, 1)
local groupSepLine = SolidTex(cc, "BORDER", 0.2, 0.2, 0.2, 1)
groupSepLine:SetHeight(Pix.mult)
Pix.Width(groupSepLine, TILE_ROW_W)

-- ── Queue panel ──────────────────────────────────────────────────────────────────
local queuePanel = CreateFrame("Frame", nil, cc)
Pix.Size(queuePanel, QUEUE_W, FRAME_H - 140)
Pix.Point(queuePanel, "TOPLEFT", cc, "TOPLEFT", QUEUE_X_OFF, -10)

local qHdrLbl = MFont(queuePanel, 11, "OUTLINE", 1, 1, 1, 1)
Pix.Point(qHdrLbl, "TOPLEFT", queuePanel, "TOPLEFT", 0, 0)
qHdrLbl:SetText(CUI.L("Upgrade Queue"))

-- Sort-by-crest button sits in the header bar, right-aligned (swaps with qSubLbl)
local queueSortBtn = CreateFrame("Button", nil, queuePanel)
queueSortBtn:SetHeight(16)
local qSortTxt = MFont(queueSortBtn, 11, "OUTLINE", 1, 1, 1, 0.75)
qSortTxt:SetPoint("RIGHT", queueSortBtn, "RIGHT", 0, 0)
qSortTxt:SetText(CUI.L("Sort"))
queueSortBtn:SetWidth(qSortTxt:GetStringWidth() + 4)
Pix.Point(queueSortBtn, "RIGHT", queuePanel, "RIGHT", 0, 0)
queueSortBtn:SetPoint("TOP", queuePanel, "TOP", 0, 0)
queueSortBtn:SetScript("OnEnter", function(self)
    CUI.ShowWidgetTooltip(self, CUI.L("Sort queue by crest type (cheapest first)"))
end)
queueSortBtn:SetScript("OnLeave", function()
    CUI.HideWidgetTooltip()
end)
queueSortBtn:Hide() -- shown only when queue has items

local qHdrSep = CreateFrame("Frame", nil, queuePanel)
qHdrSep:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 0, -18)
qHdrSep:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", 0, -18)
qHdrSep:SetHeight(math.max(Pix.mult, 1))
qHdrSep:SetFrameLevel(queuePanel:GetFrameLevel() + 5)
local qHdrSepTex = qHdrSep:CreateTexture(nil, "OVERLAY")
qHdrSepTex:SetAllPoints()
qHdrSepTex:SetColorTexture(1, 1, 1, 0.15)

local qEmptyLbl = MFont(queuePanel, 10, "OUTLINE", 0.32, 0.32, 0.32, 1)
Pix.Point(qEmptyLbl, "TOPLEFT", queuePanel, "TOPLEFT", 4, -23)
Pix.Point(qEmptyLbl, "TOPRIGHT", queuePanel, "TOPRIGHT", -4, -23)
qEmptyLbl:SetJustifyH("LEFT")
qEmptyLbl:SetWordWrap(true)
qEmptyLbl:SetText(CUI.L("No items queued, click tiles to add an item to queue."))

-- 16 pre-created queue entry rows
local queueEntries = {}
local Q_ROW_H = 20
local Q_ROW_STEP = Q_ROW_H + Pix.mult -- row height + 1 physical pixel gap
for i = 1, 16 do
    local ef = CreateFrame("Frame", nil, queuePanel)
    Pix.Size(ef, QUEUE_W, Q_ROW_H)
    Pix.Point(ef, "TOPLEFT", queuePanel, "TOPLEFT", 0, -(23 + (i - 1) * Q_ROW_STEP))
    ef:Hide()
    local ebg = SolidTex(ef, "BACKGROUND", 1, 1, 1, 0.05)
    ebg:SetAllPoints(ef)
    local nLbl = MFont(ef, 10, "OUTLINE", 0.8, 0.8, 0.8, 1)
    Pix.Point(nLbl, "LEFT", ef, "LEFT", 4, 0)
    Pix.Width(nLbl, QUEUE_W - 84)
    nLbl:SetJustifyH("LEFT")
    local cLbl = MFont(ef, 10, nil, 0.8, 0.8, 0.8, 1)
    Pix.Point(cLbl, "RIGHT", ef, "RIGHT", -4, 0)
    Pix.Width(cLbl, 82)
    cLbl:SetJustifyH("RIGHT")
    ef.nLbl = nLbl
    ef.cLbl = cLbl
    queueEntries[i] = ef
end

local qTotalSep = CreateFrame("Frame", nil, queuePanel)
qTotalSep:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 0, -42)
qTotalSep:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", 0, -42)
qTotalSep:SetHeight(math.max(Pix.mult, 1))
qTotalSep:SetFrameLevel(queuePanel:GetFrameLevel() + 5)
local qTotalSepTex = qTotalSep:CreateTexture(nil, "OVERLAY")
qTotalSepTex:SetAllPoints()
qTotalSepTex:SetColorTexture(1, 1, 1, 0.15)
qTotalSep:Hide()

local qTotalLbl = MFont(queuePanel, 10, "OUTLINE", G.r, G.g, G.b, 1)
Pix.Point(qTotalLbl, "TOPRIGHT", queuePanel, "TOPRIGHT", -4, -46)
qTotalLbl:SetJustifyH("RIGHT")
qTotalLbl:SetText("")
qTotalLbl:Hide()

local qClearBtn = MakeButton(queuePanel, CUI.L("Clear Queue"), QUEUE_W - 6, 20, -70, 0)
qClearBtn:Hide()

-- Queue state
local queueList = {} -- ordered list of tileEntry tables
local queuedSlots = {} -- slotName -> position in queueItems
local _queueLoaded = false -- true once saved queue has been applied after session start

local manualCrests = {}
for _, trackData in pairs(Data.tracks) do
    if trackData.manualAdds then
        manualCrests[trackData.crestName] = 0
    end
end

-- Persist the current queue (slot IDs only) to the profile DB.
local function SaveQueue()
    local saved = DB()
    saved.queue = {}
    for i, it in ipairs(queueList) do
        saved.queue[i] = it.slotID
    end
end

-- Persist the current crest manual-add offsets to the profile DB.
local function SaveCrestManualAdds()
    local saved = DB()
    saved.crestManualAdds = {}
    for key, val in pairs(manualCrests) do
        saved.crestManualAdds[key] = val
    end
end

local function UpdateQueueDisplay()
    local num = #queueList
    qEmptyLbl:SetText(num == 0 and CUI.L("No items queued, click tiles to add an item to queue.") or "")
    if num > 0 then
        queueSortBtn:Show()
    else
        queueSortBtn:Hide()
    end

    local totalCrests = {}
    for i, record in ipairs(queueList) do
        local qe = queueEntries[i]
        qe:Show()
        local parts = {}
        if record.trackKey and record.trackKey ~= "Crafted" then
            local trackData = Data.tracks[record.trackKey]
            if trackData and (record.crestCost or 0) > 0 then
                local trackShortName = (trackData.crestName or record.trackKey):gsub(" Crest", "")
                parts[#parts + 1] = record.crestCost .. " " .. CUI.L(trackShortName)
                totalCrests[trackData.crestName] = (totalCrests[trackData.crestName] or 0) + record.crestCost
            end
        end
        local costStr = #parts > 0 and table.concat(parts, " ") or ("|cff20c020" .. CUI.L("Max") .. "|r")
        local gain = (not record.isAtMax and type(record.max) == "number" and record.max > record.ilvl)
                and (record.max - record.ilvl)
            or nil
        local slotNameTranslated = CUI.L(record.slotName)
        local nameStr = gain and (slotNameTranslated .. " |cff888888+" .. gain .. "|r") or slotNameTranslated
        qe.nLbl:SetText(nameStr)
        qe.cLbl:SetText(costStr)
    end
    for i = num + 1, 16 do
        queueEntries[i]:Hide()
    end

    if num > 0 then
        local parts = {}
        for _, trackLabel in ipairs(Data.trackOrder) do
            local trackData = Data.tracks[trackLabel]
            local ckey = trackData and trackData.crestName or trackLabel
            local amount = totalCrests[ckey] or 0
            if amount > 0 then
                parts[#parts + 1] = amount .. " " .. CUI.L(ckey:gsub(" Crest", ""))
            end
        end

        local sepY = -(23 + num * Q_ROW_STEP + 6)
        qTotalSep:ClearAllPoints()
        Pix.Point(qTotalSep, "TOPLEFT", queuePanel, "TOPLEFT", 0, sepY)
        Pix.Point(qTotalSep, "TOPRIGHT", queuePanel, "TOPRIGHT", 0, sepY)
        qTotalSep:SetHeight(math.max(Pix.mult, 1))
        qTotalLbl:ClearAllPoints()
        Pix.Point(qTotalLbl, "TOPRIGHT", queuePanel, "TOPRIGHT", -4, sepY - 6)
        qClearBtn:ClearAllPoints()
        Pix.Point(qClearBtn, "TOPLEFT", queuePanel, "TOPLEFT", 0, sepY - 28)

        qTotalLbl:SetText(#parts > 0 and table.concat(parts, "  ") or CUI.L("Nothing needed"))
        qTotalLbl:Show()
        qTotalSep:Show()
        qClearBtn:Show()
    else
        qTotalLbl:Hide()
        qTotalSep:Hide()
        qClearBtn:Hide()
    end
end

-- Sort the queue by crest tier (cheapest/lowest first: Adventurer→Myth→Crafted).
local function SortQueueByCrest()
    if #queueList == 0 then
        return
    end
    local trackIdx = {}
    for i, tn in ipairs(Data.trackOrder) do
        trackIdx[tn] = i
    end
    table.sort(queueList, function(lhs, rhs)
        -- No crest cost sorts first (0), then by track order, unknowns last.
        local ia = (lhs.crestCost or 0) == 0 and 0 or (trackIdx[lhs.trackKey] or 99)
        local ib = (rhs.crestCost or 0) == 0 and 0 or (trackIdx[rhs.trackKey] or 99)
        if ia ~= ib then
            return ia < ib
        end
        return (lhs.slotID or 0) < (rhs.slotID or 0)
    end)
    queuedSlots = {}
    for i, it in ipairs(queueList) do
        queuedSlots[it.slotName] = i
    end
    UpdateQueueDisplay()
    SaveQueue()
end

queueSortBtn:SetScript("OnClick", SortQueueByCrest)

ToggleTileQueue = function(record, button)
    local sn = record.slotName
    if queuedSlots[sn] then
        local position = queuedSlots[sn]
        table.remove(queueList, position)
        queuedSlots = {}
        for i, it in ipairs(queueList) do
            queuedSlots[it.slotName] = i
        end
        button.selHL:Hide()
    else
        queueList[#queueList + 1] = record
        queuedSlots[sn] = #queueList
        button.selHL:Show()
    end
    UpdateQueueDisplay()
    SaveQueue()
end

qClearBtn:SetScript("OnClick", function()
    queueList = {}
    queuedSlots = {}
    for _, button in ipairs(tileFrames) do
        button.selHL:Hide()
    end
    UpdateQueueDisplay()
    SaveQueue()
end)

-- ── Crest section — parented to a repositionable container frame ──────────────
-- crestSection is moved each PopulateGear so the window height stays tight.
local crestSection = CreateFrame("Frame", nil, cc)
Pix.Point(crestSection, "TOPLEFT", cc, "TOPLEFT", 0, -430) -- initial; overwritten each refresh
Pix.Point(crestSection, "TOPRIGHT", cc, "TOPRIGHT", 0, -430)
Pix.Height(crestSection, 200) -- large enough; content determines visible area

local gearSep = SolidTex(crestSection, "BORDER", 0.2, 0.2, 0.2, 1)
Pix.Point(gearSep, "TOPLEFT", crestSection, "TOPLEFT", 0, 4)
Pix.Point(gearSep, "TOPRIGHT", crestSection, "TOPRIGHT", 0, 4)
gearSep:SetHeight(Pix.mult)

-- Forward-declared so buttons can call it.
local PopulateGear

-- Summary text labels
local missingLbl = MFont(crestSection, 11, "OUTLINE", 1, 1, 1, 1)
Pix.Point(missingLbl, "TOPLEFT", crestSection, "TOPLEFT", 4, 0)
missingLbl:SetJustifyH("LEFT")
missingLbl:SetText(CUI.L("Total Missing Upgrades: -"))

local crestsLbl = MFont(crestSection, 11, "OUTLINE", 1, 1, 1, 1)
Pix.Point(crestsLbl, "TOPLEFT", missingLbl, "BOTTOMLEFT", 0, -4)
Pix.Width(crestsLbl, TILE_ROW_W)
crestsLbl:SetJustifyH("LEFT")
crestsLbl:SetText(CUI.L("Total Crests Needed: -"))

local refreshBtn = MakeButton(crestSection, CUI.L("Refresh"), 140, 22, 0, 0)
local scanBtn, scanBtnTxt = MakeButton(crestSection, CUI.L("Update at Upgrader"), 160, 22, 0, 150)

-- ── Per-track crest breakdown table ─────────────────────────────────────────
-- Rows are pre-created once; repositioned and populated each PopulateGear.
local CROW_H = 20
local CROW_STEP = CROW_H + 1

local CC_NAME_X, CC_NAME_W = 0, 110
local CC_NEED_X, CC_NEED_W = 115, 65
local CC_OWN_X, CC_OWN_W = 185, 65
local CC_EARN_X, CC_EARN_W = 255, 100
local CC_REM_X, CC_REM_W = 360, 90
local CC_BTN_W = 40
local CC_MINUS_X = TILE_ROW_W - CC_BTN_W * 2 - 5
local CC_PLUS_X = TILE_ROW_W - CC_BTN_W

local crestTblHdr = CreateFrame("Frame", nil, crestSection)
Pix.Size(crestTblHdr, TILE_ROW_W, CROW_H)
local cHdrBg = SolidTex(crestTblHdr, "BACKGROUND", 0, 0, 0, 0.35)
cHdrBg:SetAllPoints()
local function MakeCHdr(hostFrame, textValue, posX, wid, align)
    local labelFS = MFont(hostFrame, 10, "OUTLINE", 1, 1, 1, 0.9)
    Pix.Point(labelFS, "LEFT", hostFrame, "TOPLEFT", posX + 4, -CROW_H / 2)
    Pix.Width(labelFS, wid - 8)
    labelFS:SetJustifyH(align or "LEFT")
    labelFS:SetText(CUI.L(textValue))
    return labelFS
end
MakeCHdr(crestTblHdr, "Crest", CC_NAME_X, CC_NAME_W, "LEFT")
MakeCHdr(crestTblHdr, "Needed", CC_NEED_X, CC_NEED_W, "RIGHT")
MakeCHdr(crestTblHdr, "Owned", CC_OWN_X, CC_OWN_W, "RIGHT")
local cHdrEarn = MakeCHdr(crestTblHdr, "Earned/Cap", CC_EARN_X, CC_EARN_W, "RIGHT")
local cHdrRem = MakeCHdr(crestTblHdr, "Still Avail", CC_REM_X, CC_REM_W, "RIGHT")
crestTblHdr:Hide()

local crestTableRows = {}
for ri, trackLabel in ipairs(Data.trackOrder) do
    local trackData = Data.tracks[trackLabel]
    local crestKey = trackData and trackData.crestName or (trackLabel .. " Crest")
    local row = CreateFrame("Frame", nil, crestSection)
    Pix.Size(row, TILE_ROW_W, CROW_H)
    if ri % 2 == 0 then
        local altBg = SolidTex(row, "BACKGROUND", 0, 0, 0, 0.15)
        altBg:SetAllPoints()
    end
    local function MakeCell(posX, wid, align)
        local labelFS = MFont(row, 11, nil, 0.85, 0.85, 0.85, 1)
        Pix.Point(labelFS, "TOPLEFT", row, "TOPLEFT", posX + 4, -3)
        Pix.Width(labelFS, wid - 8)
        labelFS:SetJustifyH(align or "LEFT")
        labelFS:SetText("-")
        return labelFS
    end
    local hexColor = trackData and trackData.hexColor or CludesUI.COLOR_CODES.WHITE
    local nameLbl = MFont(row, 11, nil, 0.85, 0.85, 0.85, 1)
    Pix.Point(nameLbl, "TOPLEFT", row, "TOPLEFT", CC_NAME_X + 4, -3)
    Pix.Width(nameLbl, CC_NAME_W - 8)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetText(hexColor .. trackLabel .. "|r")
    local needLbl = MakeCell(CC_NEED_X, CC_NEED_W, "RIGHT")
    local ownLbl = MakeCell(CC_OWN_X, CC_OWN_W, "RIGHT")
    local earnLbl = MakeCell(CC_EARN_X, CC_EARN_W, "RIGHT")
    local remLbl = MakeCell(CC_REM_X, CC_REM_W, "RIGHT")
    local minusBtn, plusBtn
    if trackData and trackData.manualAdds then
        minusBtn = MakeButton(row, "-80", CC_BTN_W, CROW_H - 4, -2, CC_MINUS_X)
        plusBtn = MakeButton(row, "+80", CC_BTN_W, CROW_H - 4, -2, CC_PLUS_X)
        do
            local ck = crestKey
            minusBtn:SetScript("OnClick", function()
                manualCrests[ck] = math.max(0, (manualCrests[ck] or 0) - 80)
                SaveCrestManualAdds()
                PopulateGear()
            end)
            plusBtn:SetScript("OnClick", function()
                manualCrests[ck] = (manualCrests[ck] or 0) + 80
                SaveCrestManualAdds()
                PopulateGear()
            end)
        end
    end
    row:Hide()
    crestTableRows[ri] = {
        frame = row,
        trackName = trackLabel,
        crestKey = crestKey,
        needLbl = needLbl,
        ownLbl = ownLbl,
        earnLbl = earnLbl,
        remLbl = remLbl,
        minusBtn = minusBtn,
        plusBtn = plusBtn,
    }
end

-- ── PopulateGear ──────────────────────────────────────────────────────────────
PopulateGear = function()
    local gear = Calc:GetEquippedGear()
    local owned = Calc:GetPlayerCrests()
    local totalMissing, crestNeeds = 0, {}
    local tileEntries = {}

    -- Pre-pass: compute the theoretical max ilvl across ALL equipped slots,
    -- deliberately ignoring slotFilter and hideCrafted so the timeline bar and
    -- "Max Possible" stat always reflect the full character potential.
    -- Running this first also warms _tipCache so the display loop below pays no
    -- extra tooltip scanning cost.
    local maxTotal = 0
    for _, entry in ipairs(gear) do
        local pOk, _, _, _, _, topIlvl = pcall(Calc.GetItemUpgradeCost, Calc, entry)
        if pOk and type(topIlvl) == "number" then
            maxTotal = maxTotal + topIlvl
        elseif Calc:IsVoidforged(entry.link) then
            maxTotal = maxTotal + entry.ilvl
        elseif entry.ilvl >= 200 then
            local _, maxI = CraftedBandFromIlvl(entry.ilvl)
            maxTotal = maxTotal + maxI
        else
            maxTotal = maxTotal + entry.ilvl
        end
    end

    -- Pre-build per-slot crest breakdown from scan data.
    -- Done once here from a single DB snapshot so every item in the loop
    -- sees a consistent view of the cache with no per-item DB reads.
    -- Link validation: skip any slot whose cached link doesn't match current gear.
    local slotCrestMap = {}
    local dbSnap = DB()
    if dbSnap.calibrated then
        for slotId, scroller in pairs(dbSnap.cache.slots or {}) do
            local currentLink = GetInventoryItemLink("player", slotId)
            if scroller and scroller.crestAmounts and scroller.link == currentLink then
                local byName = {}
                for cid, amount in pairs(scroller.crestAmounts) do
                    local crestName = _currIDToCrestName[cid]
                    if crestName and amount > 0 then
                        byName[crestName] = (byName[crestName] or 0) + amount
                    end
                end
                if next(byName) then
                    slotCrestMap[slotId] = byName
                end
            end
        end
    end
    -- Read persistent settings once per refresh
    local options = Opts()
    local hideCrafted = options.hideCrafted
    local showMaxed = options.showMaxed
    local slotFilter = options.slotFilter -- table of group -> bool (nil = all shown)
    local crestFilter = options.crestFilter -- table of trackName -> bool (nil/true = shown)
    local showEarnedCap = options.showEarnedCap
    local showWeeklyRemaining = options.showWeeklyRemaining

    -- Build per-slot data
    for _, entry in ipairs(gear) do
        local grp = Data.slotToGroup[entry.slot]
        if not (slotFilter and grp and slotFilter[grp] == false) then
            local sn = Data.slotNames[entry.slot] or ("Slot " .. entry.slot)
            local pOk, pa, pb, pc, pd, pe, popFrame = pcall(Calc.GetItemUpgradeCost, Calc, entry)
            local trackKey, rankNum, crestCost, topIlvl, craftLabel
            if pOk then
                trackKey, rankNum, crestCost, topIlvl, craftLabel = pa, pb, pc, pd, pe
            end
            local dt, dm, du = "-", "-", "-"
            local isAtMax, shouldAdd = false, true

            if trackKey == "Crafted" then
                if hideCrafted then
                    shouldAdd = false
                else
                    dt = craftLabel or "Crafted"
                    dm = topIlvl or entry.ilvl
                    isAtMax = true
                    du = "Crafted"
                end
            elseif trackKey then
                local trackData = Data.tracks[trackKey]
                local scan = Calc:ScanItemLink(entry.link)
                local topRank = TrackMaxRank(trackData, scan and scan.maxRank)
                totalMissing = totalMissing + math.max(0, topRank - (rankNum or 0))
                local cn_map = slotCrestMap[entry.slot]
                if cn_map then
                    for crestName, amount in pairs(cn_map) do
                        crestNeeds[crestName] = (crestNeeds[crestName] or 0) + amount
                    end
                elseif trackData and (crestCost or 0) > 0 then
                    crestNeeds[trackData.crestName] = (crestNeeds[trackData.crestName] or 0) + crestCost
                end
                dt = trackKey
                dm = topIlvl or entry.ilvl
                du = rankNum and (rankNum .. "/" .. topRank) or "-"
                isAtMax = (rankNum == topRank)
            else
                if Calc:IsVoidforged(entry.link) then
                    dt = "Voidforged"
                    dm = entry.ilvl
                    du = "Max"
                    isAtMax = true
                elseif entry.ilvl >= 200 then
                    -- Use the shared helper so thresholds stay in one place.
                    local bandTex, maxI = CraftedBandFromIlvl(entry.ilvl)
                    local labelText = bandTex == "Myth" and "Myth Craft"
                        or bandTex == "Hero" and "Hero Craft"
                        or "Crafted"
                    dt = labelText
                    dm = maxI
                    du = entry.ilvl >= maxI and "Max" or "-"
                    isAtMax = entry.ilvl >= maxI
                else
                    dm = entry.ilvl
                    isAtMax = true
                end
            end

            if shouldAdd then
                tileEntries[#tileEntries + 1] = {
                    slotName = sn,
                    slotID = entry.slot,
                    ilvl = entry.ilvl,
                    max = dm,
                    upgrade = du,
                    trackName = dt,
                    isAtMax = isAtMax,
                    trackKey = trackKey,
                    crestCost = crestCost,
                }
            end
        end
    end

    -- Fold in manual crest additions (from the +/-80 buttons on Hero/Myth rows)
    for ckey, amount in pairs(manualCrests) do
        if (amount or 0) > 0 then
            crestNeeds[ckey] = (crestNeeds[ckey] or 0) + amount
        end
    end

    -- Sort: needs-upgrades first, then at-max. Within each group follow character sheet slot order.
    table.sort(tileEntries, function(lhs, rhs)
        if lhs.isAtMax ~= rhs.isAtMax then
            return not lhs.isAtMax
        end
        return lhs.slotID < rhs.slotID
    end)

    -- Restore queue from DB on the first PopulateGear call after a session start.
    -- We only do this once (_queueLoaded guard) so that subsequent Refresh calls
    -- don't overwrite in-session queue changes the user has made.
    if not _queueLoaded then
        _queueLoaded = true
        local savedSlots = DB().queue
        if savedSlots and #savedSlots > 0 then
            local slotToEntry = {}
            for _, entry in ipairs(tileEntries) do
                slotToEntry[entry.slotID] = entry
            end
            queueList = {}
            queuedSlots = {}
            for _, slotId in ipairs(savedSlots) do
                local e = slotToEntry[slotId]
                if e and not queuedSlots[e.slotName] then
                    queueList[#queueList + 1] = e
                    queuedSlots[e.slotName] = #queueList
                end
            end
        end
    end

    -- On every refresh, sync queue item references to the current tileEntries so
    -- UpdateQueueDisplay shows live costs rather than costs snapshotted at session open.
    -- Also prunes entries whose slot is now at max rank (tile hidden, can't be clicked
    -- to dequeue — e.g. equipped a fully-upgraded item in that slot).
    -- Safe to run on the first PopulateGear call too (entries are already fresh then).
    if #queueList > 0 then
        local slotToEntry = {}
        for _, entry in ipairs(tileEntries) do
            slotToEntry[entry.slotID] = entry
        end
        local newQueue, newSet = {}, {}
        for _, old in ipairs(queueList) do
            local fresh = slotToEntry[old.slotID]
            if fresh and not fresh.isAtMax then
                newQueue[#newQueue + 1] = fresh
                newSet[fresh.slotName] = #newQueue
            end
        end
        local pruned = (#newQueue ~= #queueList)
        queueList = newQueue
        queuedSlots = newSet
        if pruned then
            -- At least one entry was pruned; persist the trimmed queue.
            SaveQueue()
        end
    end

    -- Timeline bar
    local curAvg = select(2, GetAverageItemLevel()) or 0
    -- Blizzard counts 2H weapons as two slots; clamp so max never shows below current.
    local maxAvg = math.max(curAvg, #gear > 0 and maxTotal / #gear or 0)
    local minBase = 200
    local frac = (maxAvg > minBase and curAvg > minBase)
            and math.min(1, (curAvg - minBase) / math.max(1, maxAvg - minBase))
        or 0
    -- Defer fill width to next frame so layout has resolved tlTrack's anchor-derived width
    local capFrac = frac
    C_Timer.After(0, function()
        local trackW = tlTrack:GetWidth()
        if trackW <= 0 then
            trackW = 1
        end
        tlFill:SetWidth(math.max(1, math.floor(capFrac * trackW)))
    end)
    local acHex = CludesUI.HexColor(G.r, G.g, G.b)
    ilvlStatLbl:SetText(
        CUI.Lf("Current iLvl: %s%.1f|r     Max Possible: %s%.1f|r", acHex, curAvg, acHex, maxAvg)
    )
    ilvlEstLbl:SetText(CUI.L("(est)"))

    -- Section header positions
    local needsCount = 0
    for _, entry in ipairs(tileEntries) do
        if not entry.isAtMax then
            needsCount = needsCount + 1
        end
    end
    local maxCount = #tileEntries - needsCount
    local needsRows = needsCount > 0 and math.ceil(needsCount / TILE_COLS) or 0

    if needsCount > 0 then
        sHdrNeeds:ClearAllPoints()
        Pix.Point(sHdrNeeds, "TOPLEFT", cc, "TOPLEFT", 0, -10)
        local acH = CludesUI.HexColor(G.r, G.g, G.b)
        sHdrNeeds:SetText(CUI.Lf("Upgradable Items (%s%d|r)", acH, needsCount))
        sHdrNeeds:Show()
    else
        sHdrNeeds:SetText("")
        sHdrNeeds:Hide()
    end

    local atMaxHdrY = -10 - (needsCount > 0 and needsRows * TILE_STEP + 18 or 0)
    if maxCount > 0 and showMaxed then
        groupSepLine:ClearAllPoints()
        Pix.Point(groupSepLine, "TOPLEFT", cc, "TOPLEFT", 0, atMaxHdrY - 2)
        groupSepLine:Show()
        sHdrMax:ClearAllPoints()
        Pix.Point(sHdrMax, "TOPLEFT", cc, "TOPLEFT", 0, atMaxHdrY - 6)
        sHdrMax:SetText(string.format("At Max (%d)", maxCount))
        sHdrMax:Show()
    else
        groupSepLine:Hide()
        sHdrMax:Hide()
    end

    -- Position and fill tile frames
    local function getTilePos(group_start_y, local_idx)
        local row = math.floor(local_idx / TILE_COLS)
        local colour = local_idx % TILE_COLS
        return colour * (TILE_W + TILE_GAP), group_start_y - row * TILE_STEP
    end

    local needsStartY = -28 -- below section header(~18) + gap
    local atMaxStartY = needsStartY - needsRows * TILE_STEP - (needsCount > 0 and 34 or 18)

    for _, button in ipairs(tileFrames) do
        button:Hide()
    end

    local ni, mi = 0, 0
    for position, record in ipairs(tileEntries) do
        if position > #tileFrames then
            break
        end -- tileFrames has 18 slots; equipSlots has 16
        local button = tileFrames[position]
        local tx, ty
        if not record.isAtMax then
            tx, ty = getTilePos(needsStartY, ni)
            ni = ni + 1
        elseif showMaxed then
            tx, ty = getTilePos(atMaxStartY, mi)
            mi = mi + 1
        end
        if tx then
            button:ClearAllPoints()
            Pix.Point(button, "TOPLEFT", cc, "TOPLEFT", tx, ty)
            button:Show()

            -- Tile background colour by upgrade gap
            if record.isAtMax then
                button.bg:SetColorTexture(0.1, 0.4, 0.1, 0.2)
            elseif type(record.max) == "number" and (record.max - record.ilvl) >= 10 then
                button.bg:SetColorTexture(0.5, 0.1, 0.1, 0.2)
            else
                button.bg:SetColorTexture(0.5, 0.35, 0.05, 0.2)
            end

            -- Left accent bar: track colour
            local rgb = (record.trackKey and TRACK_RGB[record.trackKey])
                or TRACK_RGB[record.trackName]
                or { 0.4, 0.4, 0.4 }
            button.accentBar:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)

            -- Text labels
            button.sLbl:SetText(CUI.L(record.slotName))
            local maxStr = type(record.max) == "number" and tostring(record.max) or "-"
            button.iLbl:SetText(record.ilvl .. " (" .. maxStr .. ")")
            button.tLbl:SetText(CUI.L(record.trackName))
            button.tLbl:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
            button.rLbl:SetText(CUI.L(record.upgrade))

            local txtA = record.isAtMax and 0.45 or 0.9
            button.sLbl:SetTextColor(txtA, txtA, txtA, 1)
            button.iLbl:SetTextColor(txtA, txtA, txtA, 1)
            button.rLbl:SetTextColor(txtA, txtA, txtA, 1)

            -- Restore queue highlight
            if queuedSlots[record.slotName] then
                button.selHL:Show()
            else
                button.selHL:Hide()
            end

            button.tileEntry = record
        end
    end

    -- Reposition the crest section immediately below the last rendered tile row.
    local crestY
    if showMaxed and maxCount > 0 then
        -- atMaxStartY is where the at-max group starts; offset by its rows + gap.
        crestY = atMaxStartY - math.ceil(maxCount / TILE_COLS) * TILE_STEP - 20
    else
        -- Only needs-upgrade tiles are visible (or none at all).
        crestY = needsStartY - needsRows * TILE_STEP - 20
    end
    crestSection:ClearAllPoints()
    Pix.Point(crestSection, "TOPLEFT", cc, "TOPLEFT", 0, crestY)
    Pix.Width(crestSection, TILE_ROW_W)

    -- Summary text: Total Missing Upgrades + Total Crests Needed
    local acHex2 = CludesUI.HexColor(G.r, G.g, G.b)
    missingLbl:SetText(CUI.Lf("Total Missing Upgrades: %s%d|r", acHex2, totalMissing))

    local crestParts = {}
    -- Reverse order: highest tier first (Myth -> Adventurer)
    for i = #Data.trackOrder, 1, -1 do
        local trackLabel = Data.trackOrder[i]
        local trackData = Data.tracks[trackLabel]
        local ckey = trackData and trackData.crestName or trackLabel
        local amount = crestNeeds[ckey] or 0
        if amount > 0 then
            local hexColor = (trackData and trackData.hexColor) or CludesUI.COLOR_CODES.WHITE
            local formattedPart = CUI.Lf("%d " .. trackLabel, amount)
            crestParts[#crestParts + 1] = hexColor .. formattedPart .. "|r"
        end
    end
    local crestStr = #crestParts > 0 and table.concat(crestParts, ", ") or "None"
    local saved = DB()
    local accuracyTag = saved.calibrated and (" |cff20ff20" .. CUI.L("(exact)") .. "|r")
        or (" |cff888888" .. CUI.L("(est)") .. "|r")
    crestsLbl:SetText(CUI.L("Total Crests Needed") .. accuracyTag .. ": " .. CUI.L(crestStr))

    -- Crest breakdown table: populate rows, apply filter and optional columns
    cHdrEarn:SetShown(showEarnedCap or false)
    cHdrRem:SetShown(showWeeklyRemaining or false)

    local visRowCount = 0
    for _, rowInfo in ipairs(crestTableRows) do
        local tn = rowInfo.trackName
        local isShown = not (crestFilter and crestFilter[tn] == false)
        if isShown then
            local needed = crestNeeds[rowInfo.crestKey] or 0
            local ownedInfo = owned[rowInfo.crestKey]
            rowInfo.needLbl:SetText(needed > 0 and tostring(needed) or "-")
            rowInfo.ownLbl:SetText(ownedInfo and tostring(ownedInfo.quantity) or "-")
            if showEarnedCap then
                if ownedInfo then
                    local capStr = ownedInfo.cap and tostring(ownedInfo.cap) or "-"
                    rowInfo.earnLbl:SetText(ownedInfo.earned .. " / " .. capStr)
                else
                    rowInfo.earnLbl:SetText("-")
                end
                rowInfo.earnLbl:Show()
            else
                rowInfo.earnLbl:Hide()
            end
            if showWeeklyRemaining then
                if ownedInfo and ownedInfo.cap then
                    rowInfo.remLbl:SetText(tostring(math.max(0, ownedInfo.cap - ownedInfo.earned)))
                else
                    rowInfo.remLbl:SetText("-")
                end
                rowInfo.remLbl:Show()
            else
                rowInfo.remLbl:Hide()
            end
            rowInfo.frame:ClearAllPoints()
            Pix.Point(rowInfo.frame, "TOPLEFT", crestTblHdr, "BOTTOMLEFT", 0, -(visRowCount * CROW_STEP))
            rowInfo.frame:Show()
            visRowCount = visRowCount + 1
        else
            rowInfo.frame:Hide()
        end
    end

    -- Table sits above the buttons when rows are visible; buttons fall back to crestsLbl otherwise
    if visRowCount > 0 then
        crestTblHdr:ClearAllPoints()
        Pix.Point(crestTblHdr, "TOPLEFT", crestsLbl, "BOTTOMLEFT", 4, -8)
        crestTblHdr:Show()
        refreshBtn:ClearAllPoints()
        Pix.Point(refreshBtn, "TOPLEFT", crestTblHdr, "BOTTOMLEFT", -4, -(visRowCount * CROW_STEP + 10))
    else
        crestTblHdr:Hide()
        refreshBtn:ClearAllPoints()
        Pix.Point(refreshBtn, "TOPLEFT", crestsLbl, "BOTTOMLEFT", -4, -10)
    end
    scanBtn:ClearAllPoints()
    Pix.Point(scanBtn, "TOPLEFT", refreshBtn, "TOPRIGHT", 10, 0)

    -- Resize frame to fit content
    local CC_TOP = 66 -- distance from frame top to cc top
    local crestTblH = visRowCount > 0 and (CROW_H + visRowCount * CROW_STEP + 8) or 0
    local crestSectionH = 14 + 14 + 10 + 22 + 10 + crestTblH -- two text lines + gap + buttons + padding + table
    local contentH = math.abs(crestY) + crestSectionH
    local queueH = 22 + #queueList * Q_ROW_STEP + (#queueList > 0 and 50 or 0)
    local newFrameH = math.max(contentH, queueH) + CC_TOP + 10
    Pix.Size(frame, FRAME_W, newFrameH)
    Pix.Size(queuePanel, QUEUE_W, newFrameH - CC_TOP - 10)

    -- Sync queue panel text to match restored/refreshed queue state.
    UpdateQueueDisplay()
end

refreshBtn:SetScript("OnClick", PopulateGear)
Calc.PopulateGear = PopulateGear -- exposed for options page live-refresh
refreshBtn:HookScript("OnEnter", function(self)
    CUI.ShowWidgetTooltip(
        self,
        CUI.L(
            "Refresh using tooltip scan data.\n"
                .. "For exact costs, use |cffffffff'Update at Upgrader'|r\n"
                .. "while at an Item Upgrade NPC."
        )
    )
end)
refreshBtn:HookScript("OnLeave", function()
    CUI.HideWidgetTooltip()
end)

scanBtn:HookScript("OnEnter", function(self)
    if CUI.ShowWidgetTooltip then
        local tipText = "Scan all equipped gear costs at the Item Upgrade NPC.\n"
            .. "Scans each slot one at a time — this can take up to 10 seconds.\n"
            .. "Requires the Item Upgrade window to be open."
        if not Calc:IsUpgraderOpen() then
            tipText = tipText .. "\n|cffff6060Item Upgrade window is not open.|r"
        end
        CUI.ShowWidgetTooltip(self, CUI.L(tipText))
    end
end)
scanBtn:HookScript("OnLeave", function()
    CUI.HideWidgetTooltip()
end)

scanBtn:SetScript("OnClick", function()
    if Calc._scanning then
        return
    end
    scanBtnTxt:SetText(CUI.L("Scanning..."))
    scanBtn:SetAlpha(0.5)
    Calc:ScanEquippedAtUpgrader(function(success)
        scanBtnTxt:SetText(CUI.L("Update at Upgrader"))
        scanBtn:SetAlpha(1)
        if success then
            for key in pairs(manualCrests) do
                manualCrests[key] = 0
            end
            SaveCrestManualAdds()
            PopulateGear()
        end
    end)
end)

-- Debounce timer handle for PLAYER_EQUIPMENT_CHANGED: coalesces rapid gear swaps
-- (e.g. multiple pieces at once) into a single PopulateGear call.
-- Declared before equipListener so both the OnEvent and OnHide closures capture
-- the same upvalue (declaring it after would cause OnEvent to use the global slot
-- instead, making OnHide unable to cancel a pending debounce timer).
local _equipDebounce = nil

local equipListener = CreateFrame("Frame")
equipListener:SetScript("OnEvent", function(_, evt, slotId)
    if evt == "PLAYER_REGEN_DISABLED" then
        -- Combat started: close the frame silently
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end
    -- Invalidate the tip cache for the changed slot (or all if slotID is missing).
    if slotId and slotId > 0 then
        local itemLink = GetInventoryItemLink("player", slotId)
        if itemLink then
            Calc._tipCache[itemLink] = nil
        end
    else
        Calc._tipCache = {}
    end
    if not frame:IsShown() then
        return
    end
    -- If the Upgrader NPC is open and we have a valid slot ID, rescan just that
    -- slot so the exact post-upgrade cost is shown without a full re-scan.
    if slotId and slotId > 0 and Calc:IsUpgraderOpen() and not Calc._scanning then
        -- Invalidate the slot's cache entry so PopulateGear won't stale-serve
        -- the old data while the rescan is in flight.
        local saved = DB()
        if saved.cache and saved.cache.slots then
            saved.cache.slots[slotId] = nil
        end
        Calc:RescanSlot(slotId, function()
            if frame:IsShown() then
                PopulateGear()
            end
        end)
        return
    end
    -- Debounce: wait 0.3 s after the last equip event before refreshing.
    -- This prevents hammering PopulateGear when the user swaps multiple pieces.
    if _equipDebounce then
        _equipDebounce:Cancel()
    end
    _equipDebounce = C_Timer.NewTimer(0.3, function()
        _equipDebounce = nil
        if frame:IsShown() then
            PopulateGear()
        end
    end)
end)

-- Show / Hide

frame:SetScript("OnShow", function()
    if Blocked() then
        frame:Hide()
        return
    end
    Calc.ApplyBgOpacity()
    Calc.ApplyScale()
    InstallCharacterFrameSnapHooks()
    TrySnapToCharacterFrame()
    -- Reload persisted crest manual-add offsets each time the frame opens,
    -- so that values the user set before logging out are visible immediately.
    local dbAdds = DB().crestManualAdds
    for key in pairs(manualCrests) do
        manualCrests[key] = (dbAdds and dbAdds[key]) or 0
    end
    equipListener:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    equipListener:RegisterEvent("PLAYER_REGEN_DISABLED")
    PopulateGear()
end)
frame:SetScript("OnHide", function()
    equipListener:UnregisterAllEvents()
    _sessionUnpinned = false
    -- Cancel any pending equipment-change debounce.
    if _equipDebounce then
        _equipDebounce:Cancel()
        _equipDebounce = nil
    end
    -- If hidden mid-scan (e.g. combat, /reload), unblock future scans.
    Calc._scanning = false
    Calc._tipCache = {}
    -- crestManualAdds are now persisted to DB; no longer reset on hide.
end)

SLASH_CUIUPGCALC1 = "/cuic"
SLASH_CUIUPGCALC2 = "/upgcalc"
SLASH_CUIUPGCALC3 = "/cec"
SlashCmdList["CUIUPGCALC"] = function()
    if Blocked() then
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ── Profile integration + first-run crest filter ──────────────────────────── On
-- PLAYER_LOGIN we call NewDB so our data lives inside CludesUIDB.profiles (the same
-- place Cursor, BattleRes etc store theirs). Without this, NewDB wipes CludesUIQoLDB
-- and our saved data is lost every session. The first-run filter runs once (guarded by
-- opts.firstRunV2) to auto-hide crest tracks that have no upgradeable items on the
-- player's current gear. The guard is versioned so the bad verdict written by the v1
-- enUS-only scan gets discarded and recomputed.
local _firstRunEvt = CreateFrame("Frame")
_firstRunEvt:RegisterEvent("PLAYER_LOGIN")
_firstRunEvt:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    -- Register with the escape proxy system (available after PLAYER_LOGIN)
    if CUI.RegisterEscapeClose then
        CUI.RegisterEscapeClose(frame)
    end
    -- Register with the profile system; this MUST happen before Opts()/DB() are
    -- called so data is read from / written to the correct persistent location.
    if CludesUI and CludesUI.Lite and CludesUI.Lite.NewDB then
        local profileDB = CludesUI.Lite.NewDB("CludesUIQoLDB", {
            profile = {
                upgradeCalcOpts = {},
            },
        })
        _cuicProfileRef = profileDB.profile
        -- Per-character queue, scan cache and crest offsets are ACCOUNT data
        -- keyed by character name: profiles get shared, so holding this in the
        -- profile put the player's character names and realms into every
        -- export string. Options stay in the profile (they are settings); the
        -- per-character state moves top-level. The old profile copy is dropped
        -- rather than migrated -- on anyone who imported a profile it holds the
        -- exporter's characters, and this state rebuilds from the next scan.
        local storage = _cuicProfileRef
        storage.chars = nil
        -- Throwaway fallback if the parent DB is somehow absent: the session
        -- still works, nothing persists, and the global is never assigned
        -- here (a pre-SavedVariables call could shadow the real table).
        local acct = type(CludesUIDB) == "table" and CludesUIDB or {}
        local chars = acct.qolUpgradeCalcChars
        if type(chars) ~= "table" then
            chars = {}
            acct.qolUpgradeCalcChars = chars
        end
        local charKey = CludesUI.CharKey(" - ", chars)
        chars[charKey] = chars[charKey] or {}
        local charStore = chars[charKey]
        charStore.upgradeCalc = charStore.upgradeCalc or {}
        local saved = charStore.upgradeCalc
        saved.cache = saved.cache or { slots = {}, ts = 0 }
        saved.calibrated = saved.calibrated or false
        saved.queue = saved.queue or {}
        saved.crestManualAdds = saved.crestManualAdds or {}
        storage.upgradeCalcOpts = storage.upgradeCalcOpts or {}
        _dbCache = saved
        _optsCache = storage.upgradeCalcOpts
    end
    local options = Opts()
    if options.firstRunV2 then
        return
    end
    -- The v1 auto-filter ran on the old enUS-only tooltip scan, so on every
    -- other locale it detected no track at all and permanently hid every crest
    -- row. Wipe that verdict (and the per-slot costs derived from it) before
    -- re-running the scan against the upgrade API.
    if options.firstRunDone then
        options.crestFilter = nil
        Calc:ClearCache()
    end
    -- Brief delay so the client has fully loaded item data before scanning.
    C_Timer.After(1.5, function()
        options.firstRunDone = true
        options.firstRunV2 = true
        local tracksNeeded = {}
        for _, slotId in ipairs(Data.equipSlots) do
            local itemLink = GetInventoryItemLink("player", slotId)
            if itemLink then
                local region = Calc:ScanItemLink(itemLink)
                local trackData = region and region.track and Data.tracks[region.track]
                if trackData and (region.rank or 0) < TrackMaxRank(trackData, region.maxRank) then
                    tracksNeeded[region.track] = true
                end
            end
        end
        -- Only apply a filter if at least one track can be hidden.
        local anyHidden = false
        for _, tn in ipairs(Data.trackOrder) do
            if not tracksNeeded[tn] then
                anyHidden = true
                break
            end
        end
        if anyHidden then
            options.crestFilter = options.crestFilter or {}
            for _, tn in ipairs(Data.trackOrder) do
                if not tracksNeeded[tn] then
                    options.crestFilter[tn] = false
                end
            end
        end
    end)
end)

-------------------------------------------------------------------------------
--  Open/close with Crest Upgrader NPC
--  Detects the upgrade NPC via PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE
--  (type 10 = ItemUpgrade). Falls back to ITEM_UPGRADE_MASTER_UPDATE.
-------------------------------------------------------------------------------
do
    local UPGRADE_INTERACTION = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.ItemUpgrade
        or 10
    local _upgraderOpen = false

    local evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    evtFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    evtFrame:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
    evtFrame:SetScript("OnEvent", function(_, evt, interactionType)
        local options = Calc.GetOptsDB and Calc.GetOptsDB()
        if not options or not options.openWithUpgrader then
            return
        end

        if evt == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if interactionType == UPGRADE_INTERACTION then
                _upgraderOpen = true
                local fr = _G["CUIUpgCalcFrame"]
                if fr and not fr:IsShown() then
                    fr:Show()
                end
            end
            return
        end

        if evt == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if interactionType == UPGRADE_INTERACTION then
                _upgraderOpen = false
                local fr = _G["CUIUpgCalcFrame"]
                if fr and fr:IsShown() then
                    fr:Hide()
                end
            end
            return
        end

        -- ITEM_UPGRADE_MASTER_UPDATE fallback (fires when NPC sends data)
        if not _upgraderOpen and Calc:IsUpgraderOpen() then
            _upgraderOpen = true
            local fr = _G["CUIUpgCalcFrame"]
            if fr and not fr:IsShown() then
                fr:Show()
            end
        end
    end)
end

-- Open/close with Character Sheet: when the toggle is on, the calculator frame
-- follows CharacterFrame visibility. Runtime machinery, so it lives here (the
-- options page is LoadOnDemand and cannot host login-time hooks).
local _charSheetHooked = false
local function HookCharacterSheet()
    if _charSheetHooked then
        return
    end
    if not CharacterFrame then
        return
    end
    _charSheetHooked = true
    CharacterFrame:HookScript("OnShow", function()
        if Opts().openWithCharSheet then
            local fr = _G["CUIUpgCalcFrame"]
            if fr and not fr:IsShown() then
                fr:Show()
            end
        end
    end)
    CharacterFrame:HookScript("OnHide", function()
        if Opts().openWithCharSheet then
            local fr = _G["CUIUpgCalcFrame"]
            if fr and fr:IsShown() then
                fr:Hide()
            end
        end
    end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    HookCharacterSheet()
end)
