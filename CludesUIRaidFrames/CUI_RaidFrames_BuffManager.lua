if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_BuffManager.lua
--  Indicator-centric buff manager: icon/square/bar/healthcolor/border/framealpha
--  indicators take whitelisted healer spells + position/size/color/growth (max
--  20/spec). Rendered by the aura containers (CUI_RaidFrames_AuraContainers.lua)
--  from the indicator config; no per-frame allocs (wipe + reuse).
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove
local wipe = wipe
local floor = math.floor
local max = math.max
local min = math.min
local tostring = tostring
local tonumber = tonumber
local type = type
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue
-- WoW Forever: the preview's numbers follow the live frames (CludesUI_NumberFormat.lua).
local AbbreviateNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit

local MAX_PER_SPEC = 20

-------------------------------------------------------------------------------
--  Indicator type definitions
-------------------------------------------------------------------------------
local INDICATOR_TYPES = {
    { key = "icon", name = "Icon", placed = true },
    { key = "square", name = "Square", placed = true },
    { key = "bar", name = "Bar", placed = true, singleSpell = true },
    -- divider
    { key = "healthcolor", name = "Health Bar Color", placed = false },
    { key = "bgcolor", name = "Background Color", placed = false },
    { key = "border", name = "Frame Border", placed = false },
    { key = "framealpha", name = "Frame Alpha", placed = false },
}

local INDICATOR_TYPE_MAP = {}
for _, t in ipairs(INDICATOR_TYPES) do
    INDICATOR_TYPE_MAP[t.key] = t
end

local INDICATOR_TYPE_VALUES = {}
local INDICATOR_TYPE_ORDER = {}
for _, t in ipairs(INDICATOR_TYPES) do
    INDICATOR_TYPE_VALUES[t.key] = t.name
    -- Frame Alpha cannot be created: fading the frame needs per-aura presence, which is secret in combat. Existing ones stay listed.
    local skipType = (t.key == "framealpha")
    if not skipType then
        INDICATOR_TYPE_ORDER[#INDICATOR_TYPE_ORDER + 1] = t.key
    end
end
-- Insert divider after "bar"
tinsert(INDICATOR_TYPE_ORDER, 4, "---")

-- Gray blocking overlay + red removal notice for settings whose backing
-- machinery has no aura-container equivalent (styled after the party-tab sync
-- overlays). UI-only (the runtime side of these settings is inert elsewhere);
-- callers anchor the returned frame.
local function BuildPTROverlay(parentFrame, labelText, fontSize)
    -- Options page pool (CludesUI_FramePool.lua): on a page's pooled tile
    -- the overlay is handed out again by the next render instead of made anew.
    local CreateFrame = POOL.CreateFrame
    local shade = CreateFrame("Frame", nil, parentFrame)
    shade._searchIgnore = true -- inline search must never re-anchor/collapse it
    shade:SetFrameLevel(parentFrame:GetFrameLevel() + 60)
    shade:EnableMouse(true)
    local backdrop = shade:CreateTexture(nil, "OVERLAY")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.098, 0.090, 0.082, 0.95)
    local fontStr = shade:CreateFontString(nil, "OVERLAY")
    local fp = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    fontStr:SetFont(fp, fontSize or 12, "")
    fontStr:SetPoint("LEFT", shade, "LEFT", 8, 0)
    fontStr:SetPoint("RIGHT", shade, "RIGHT", -8, 0)
    fontStr:SetJustifyH("CENTER")
    fontStr:SetTextColor(0.86, 0.24, 0.24, 0.95)
    fontStr:SetText(CludesUI.Lf("%1$s Removed in 12.1 Unless API Changes", CludesUI.L(labelText)))
    shade._msg = fontStr
    return shade
end

-- 9-position grid
local POSITION_VALUES = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
local POSITION_ORDER = {
    "TOPLEFT",
    "TOP",
    "TOPRIGHT",
    "LEFT",
    "CENTER",
    "RIGHT",
    "BOTTOMLEFT",
    "BOTTOM",
    "BOTTOMRIGHT",
}

local GROW_VALUES = {
    RIGHT = "Right",
    LEFT = "Left",
    UP = "Up",
    DOWN = "Down",
    CENTER = "Center",
}
local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

local ORIENT_VALUES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
local ORIENT_ORDER = { "HORIZONTAL", "VERTICAL" }

-- Show when mode (for frame effects)
local SHOW_WHEN_VALUES = {
    present = "When Any Present",
    allPresent = "When All Present",
    anyMissing = "When Any Missing",
    missing = "When All Missing",
}
local SHOW_WHEN_ORDER = { "present", "allPresent", "anyMissing", "missing" }
-- Effect indicators (healthcolor/bgcolor/border) on 12.1 support ONLY the
-- presence-driven mode. The engine renders present auras; absence logic would
-- need visibility hooks on its buttons, which it forbids (secret SetShown
-- throws on scripted buttons -- field, 2026-08-14). The full four-mode list
-- previously offered here made the other modes silently render NOTHING.
-- Stale saved modes render presence-driven via the runtime heal in
-- CUI_RaidFrames_AuraContainers.lua's effect branch.
local SHOW_WHEN_VALUES_EFFECT = { present = "When Any Present" }
local SHOW_WHEN_ORDER_EFFECT = { "present" }
local SHOW_WHEN_EFFECT_TIP =
    "Effect indicators show while a tracked buff is present. Absence-based modes are not available in 12.1."

-- Indicator frame level, relative to the unit button. Icon/Square: own border at base+1, count/duration text carrier pinned at +18 regardless of mode; bars use the base only (no sub-frames).
local FRAMELVL_VALUES = {
    behindBorders = "Behind Borders",
    behindText = "Behind Text",
    medium = "Medium",
    high = "High",
    highest = "Highest",
}
local FRAMELVL_ORDER = { "behindBorders", "behindText", "medium", "high", "highest" }
local FRAMELVL_BASE = {
    behindBorders = 7, -- below the main border (+8)
    behindText = 11, -- below the name/health text carrier (+12), above borders
    medium = 13, -- ns.LVL_AURA: the original/default band
    high = 14,
    highest = 15,
}
local FRAMELVL_TEXT = 18 -- fixed count/duration text-carrier offset (icon/square)

-------------------------------------------------------------------------------
--  Healer spell database. hide=true: alt spell ID for the same aura, UI-skipped.
-------------------------------------------------------------------------------
local HEALER_SPECS = {
    {
        key = "DRUID_RESTORATION",
        specID = 105,
        name = "Restoration Druid",
        classToken = "DRUID",
        spells = {
            { id = 774, name = "Rejuvenation" },
            { id = 8936, name = "Regrowth" },
            { id = 33763, name = "Lifebloom" },
            { id = 155777, name = "Germination" },
            { id = 48438, name = "Wild Growth" },
            { id = 439530, name = "Symbiotic Blooms" },
            { id = 102342, name = "Ironbark" },
        },
    },
    {
        key = "PRIEST_DISCIPLINE",
        specID = 256,
        name = "Discipline Priest",
        classToken = "PRIEST",
        spells = {
            { id = 17, name = "Power Word: Shield" },
            { id = 194384, name = "Atonement" },
            { id = 1253593, name = "Void Shield" },
            { id = 41635, name = "Prayer of Mending" },
            { id = 33206, name = "Pain Suppression" },
            { id = 10060, name = "Power Infusion" },
        },
    },
    {
        key = "PRIEST_HOLY",
        specID = 257,
        name = "Holy Priest",
        classToken = "PRIEST",
        spells = {
            { id = 139, name = "Renew" },
            { id = 77489, name = "Echo of Light" },
            { id = 41635, name = "Prayer of Mending" },
            { id = 47788, name = "Guardian Spirit" },
            { id = 10060, name = "Power Infusion" },
        },
    },
    {
        key = "MONK_MISTWEAVER",
        specID = 270,
        name = "Mistweaver Monk",
        classToken = "MONK",
        spells = {
            { id = 119611, name = "Renewing Mist" },
            { id = 124682, name = "Enveloping Mist" },
            { id = 115175, name = "Soothing Mist" },
            { id = 450769, name = "Aspect of Harmony" },
            { id = 116849, name = "Life Cocoon" },
            { id = 443113, name = "Strength of the Black Ox" },
        },
    },
    {
        key = "SHAMAN_RESTORATION",
        specID = 264,
        name = "Restoration Shaman",
        classToken = "SHAMAN",
        spells = {
            { id = 61295, name = "Riptide" },
            { id = 974, name = "Earth Shield" },
            { id = 383648, name = "Earth Shield", hide = true },
            { id = 382024, name = "Earthliving Weapon" },
            { id = 207400, name = "Ancestral Vigor" },
            { id = 444490, name = "Hydrobubble" },
        },
    },
    {
        key = "PALADIN_HOLY",
        specID = 65,
        name = "Holy Paladin",
        classToken = "PALADIN",
        spells = {
            { id = 156910, name = "Beacon of Faith" },
            { id = 156322, name = "Eternal Flame" },
            { id = 53563, name = "Beacon of Light" },
            { id = 1244893, name = "Beacon of the Savior" },
            { id = 200025, name = "Beacon of Virtue" },
            { id = 1022, name = "Blessing of Protection" },
            { id = 432502, name = "Holy Armaments" },
            { id = 6940, name = "Blessing of Sacrifice" },
            { id = 1044, name = "Blessing of Freedom" },
            { id = 431381, name = "Dawnlight" },
        },
    },
    {
        key = "EVOKER_PRESERVATION",
        specID = 1468,
        name = "Preservation Evoker",
        classToken = "EVOKER",
        spells = {
            { id = 364343, name = "Echo" },
            { id = 366155, name = "Reversion" },
            { id = 367364, name = "Echo Reversion" },
            { id = 355941, name = "Dream Breath" },
            { id = 376788, name = "Echo Dream Breath" },
            { id = 363502, name = "Dream Flight" },
            { id = 373267, name = "Lifebind" },
            { id = 357170, name = "Time Dilation" },
            { id = 363534, name = "Rewind" },
        },
    },
    {
        key = "EVOKER_AUGMENTATION",
        specID = 1473,
        name = "Augmentation Evoker",
        classToken = "EVOKER",
        spells = {
            { id = 410089, name = "Prescience" },
            { id = 413984, name = "Shifting Sands" },
            { id = 360827, name = "Blistering Scales" },
            { id = 410263, name = "Infernos Blessing" },
            { id = 410686, name = "Symbiotic Bloom" },
            { id = 395152, name = "Ebon Might" },
            { id = 369459, name = "Source of Magic" },
            { id = 361021, name = "Sense Power" },
            -- 361021 is the caster's own permanent toggle buff; 361022 is the
            -- effect that lands on whichever ally triggers Sense Power's
            -- "powerful ability" detection. Distinct spell IDs, same client
            -- display name -- kept as separate entries so both are
            -- selectable (see SPELL_NAME_BY_ID for how the UI tells them apart).
            { id = 361022, name = "Sense Power (Ally)" },
        },
    },
}

mod.BM_HEALER_SPECS = HEALER_SPECS

-- Spec lookup by key and by spec ID (locale-independent identifier).
local SPEC_BY_KEY = {}
local SPEC_BY_ID = {}
for _, specInfo in ipairs(HEALER_SPECS) do
    SPEC_BY_KEY[specInfo.key] = specInfo
    if specInfo.specID then
        SPEC_BY_ID[specInfo.specID] = specInfo
    end
end

-- Non-healer specs that can cast a tracked buff borrow a healer spec's
-- indicator placements but show only their own spells: Ele/Enh -> Resto
-- (Earth Shield); Prot/Ret -> Holy (Freedom). Keyed by spec ID; spells = the
-- primary spell IDs indicators reference.
local BORROW_SPECS = {
    [262] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } }, -- Elemental
    [263] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } }, -- Enhancement
    [66] = { source = "PALADIN_HOLY", spells = { [1044] = true } }, -- Protection
    [70] = { source = "PALADIN_HOLY", spells = { [1044] = true } }, -- Retribution
}

-- Resolve the player's CURRENT spec to a BM spec key. MUST match by spec ID,
-- never name: GetSpecializationInfo() returns the stable non-localized ID first,
-- the LOCALIZED name second, so name-matching silently kills every indicator
-- on non-English clients. nil = not tracked.
-- Borrowing resolver (Ret/Prot -> Holy, Ele/Enh -> Resto): the v2 indicator
-- system must NEVER route through it -- v2's active bucket resolves borrow-free via BM2_SpecKey /
-- BM_SpecKeyForSpecID (maintainer ruling 2026-08-13: Ret/Prot/Ele/Enh edit and
-- render the shared All Non Healers/Aug bucket, not the borrowed healer's).
local function CurrentSpecKey()
    -- WoW Forever: the retail spec the class acts as in the Buff Manager,
    -- resolved the same way (nil until the v2 file has loaded).
    if CludesUI.IS_FOREVER then
        local spellRef = mod.BM2_ForeverSpecID and mod.BM2_ForeverSpecID()
        if not spellRef then
            return nil
        end
        local borrow = BORROW_SPECS[spellRef]
        if borrow then
            return borrow.source
        end
        local specInfo = SPEC_BY_ID[spellRef]
        return specInfo and specInfo.key or nil
    end
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then
        return nil
    end
    local specId = GetSpecializationInfo and GetSpecializationInfo(specIdx)
    if not specId then
        return nil
    end
    -- Borrow specs resolve to the spec they reuse, so options + lookup tables operate on that shared configuration.
    local borrow = BORROW_SPECS[specId]
    if borrow then
        return borrow.source
    end
    local specInfo = SPEC_BY_ID[specId]
    return specInfo and specInfo.key or nil
end
mod.BM_CurrentSpecKey = CurrentSpecKey

-- Healer/support key for a specialization ID WITHOUT borrow resolution.
-- nil = not in the healer/Aug list (so the spec owns a "spec<ID>" bucket).
function mod.BM_SpecKeyForSpecID(specId)
    local specInfo = SPEC_BY_ID[specId]
    return specInfo and specInfo.key or nil
end

-- Role GROUP bucket for a specialization ID: membership in the healer/Aug
-- list wins ("healers" -- keeps the complement exactly equal to the All Non
-- Healers/Aug bucket), then TANK role -> "tanks", everything else -> "dps".
-- Shared by the Buff Manager v2 union, the Debuff Manager union and both
-- pages' editing-spec rosters. nil specID = no bucket (no spec yet).
function mod.BM_RoleBucketForSpecID(specId)
    -- WoW Forever specs carry no role: no role bucket there.
    if CludesUI.IS_FOREVER then
        return nil
    end
    if not specId then
        return nil
    end
    if SPEC_BY_ID[specId] then
        return "healers"
    end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specId))
    if role == "TANK" then
        return "tanks"
    end
    if role then
        return "dps"
    end
    -- Unknown spec/unavailable API: no role bucket at all beats silently
    -- classing a tank as DPS.
    return nil
end

-- Curated display names by spell ID (from the spec lists above)
local STORED_NAME_BY_ID = {}
for _, specInfo in ipairs(HEALER_SPECS) do
    for _, spell in ipairs(specInfo.spells) do
        if not spell.hide then
            STORED_NAME_BY_ID[spell.id] = spell.name
        end
    end
end
-- 212641 is Guardian of Ancient Kings with Glyph of the Queen applied; Blizzard's
-- client reports it under the same name as the base buff (86659).
STORED_NAME_BY_ID[212641] = "Guardian of Ancient Kings (Glyph of the Queen)"
-- Display-name lookup. Curated names win: they distinguish variants the client
-- API cannot ("Echo Reversion" vs "Reversion") and localize via L(); the client
-- name is the uncurated fallback. No cache -- L() must stay live for locale swaps.
local SPELL_NAME_BY_ID = setmetatable({}, {
    __index = function(_, ident)
        local nm = STORED_NAME_BY_ID[ident]
        if nm then
            return CludesUI.L(nm)
        end
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
    end,
})
-- Shared with CludesUIOptions/CUI_RaidFrames_ManagerPages.lua (same ns):
-- the Filter Editor and its dropdowns build spell row labels off this too, so
-- curated names (e.g. distinguishing two client-side-identical spell names)
-- apply there as well, not just in this file's own dropdowns.
mod.SPELL_NAME_BY_ID = SPELL_NAME_BY_ID

local SPEC_DD_VALUES = {}
local SPEC_DD_ORDER = {}
for _, specInfo in ipairs(HEALER_SPECS) do
    SPEC_DD_VALUES[specInfo.key] = specInfo.name
    SPEC_DD_ORDER[#SPEC_DD_ORDER + 1] = specInfo.key
end

-- GROUP buckets of the editing-spec dropdown (core list, shared with the
-- Debuff Manager and Player Aura Bars rosters): shared unions whose
-- indicators render across every matching spec (concrete specs show them as
-- inherited tiles with a per-spec enable).
mod.BM_GROUP_BUCKET_INFO = CludesUI.SPEC_GROUP_BUCKET_INFO

-- Group buckets a CONCRETE bucket (healer spec key or "spec<ID>") inherits
-- from, in display order: All Specs always, All Non Healers/Aug for
-- non-healer specs, then the spec's role group. nil for group buckets and
-- unknown keys (nothing inherits there). Membership tests the SPEC (tracked
-- or not), never the key shape: the Debuff Manager views healer specs
-- through "spec<ID>" keys too.
function mod.BM_InheritedGroupsFor(bucketKey, dmView)
    local hs = bucketKey and SPEC_BY_KEY[bucketKey]
    local spellRef = hs and hs.specID
    if not spellRef then
        local m = type(bucketKey) == "string" and bucketKey:match("^spec(%d+)$")
        spellRef = m and tonumber(m)
    end
    if not spellRef then
        return nil
    end
    local result = { "allspecs" }
    -- WoW Forever: a class renders All Specs and its own bucket only (no role
    -- groups there, All Non Healers/Aug included), so it inherits All Specs
    -- alone in the Buff and Debuff Manager views alike.
    if CludesUI.IS_FOREVER then
        return result
    end
    if not SPEC_BY_ID[spellRef] then
        result[#result + 1] = "nonhealer"
    end
    local roleKey = mod.BM_RoleBucketForSpecID(spellRef)
    if roleKey then
        result[#result + 1] = roleKey
    end
    return result
end

-- Sidebar/preview id offsets per group bucket: every bucket allocates ids
-- from the same base, so unioned DISPLAY lists shift inherited entries into
-- unique ranges (the runtime union in BM2_SpecIndicators carries its own
-- offsets). Role groups never co-occur, so they share one slot.
mod.BM_INH_OFFSETS = {
    allspecs = 2000000,
    nonhealer = 4000000,
    tanks = 3000000,
    dps = 3000000,
    healers = 3000000,
}

-- Alternate aura spell IDs resolving to a primary tracked ID (Earth Shield applies 383648, indicators use 974; Ebon Might self-buff 395296 vs ally 395152). Resolved at scan time so saved indicators match with no migration.
local PRIMARY_BY_ALT = {
    [383648] = 974, -- Earth Shield
    [395296] = 395152, -- Ebon Might (caster self-buff)
}

-- Active spec only: checking every spec of the class causes cross-spec bleed
-- (Disc seeing Holy indicators) and cross-class collisions.
local activeSpecKey_BM = nil

local function DetectActiveSpecKey()
    -- By spec ID (locale-independent); nil for non-tracked specs clears tracking.
    activeSpecKey_BM = CurrentSpecKey()
end

DetectActiveSpecKey()

-------------------------------------------------------------------------------
--  Default indicator factory
-------------------------------------------------------------------------------
local nextIndicatorId = 0

local function NewIndicatorId()
    nextIndicatorId = nextIndicatorId + 1
    return nextIndicatorId
end

local function NewIndicator(indicatorType, spells)
    local t = INDICATOR_TYPE_MAP[indicatorType]
    local indicator = {
        id = NewIndicatorId(),
        enabled = true,
        type = indicatorType,
        spells = spells or {},
        position = "TOPLEFT",
        size = (indicatorType == "bar") and 4 or 18,
        offsetX = 0,
        offsetY = 0,
    }
    if indicatorType == "icon" then
        indicator.size = 18
        indicator.ownOnly = true
        indicator.showStacks = true
        indicator.showDuration = true
        indicator.showDurationText = false
        indicator.durationTextColor = { r = 1, g = 1, b = 1 }
        indicator.durationTextSize = 8
        indicator.durationTextOffsetX = 0
        indicator.durationTextOffsetY = 0
        indicator.stacksTextColor = { r = 1, g = 1, b = 1 }
        indicator.stacksTextSize = 8
        indicator.stacksOffsetX = -1
        indicator.stacksOffsetY = 2
        indicator.iconOpacity = 100
        indicator.indBorderSize = 1
        indicator.indBorderColor = { r = 0, g = 0, b = 0 }
        indicator.hideIcon = false
        indicator.frameLevel = "medium"
        indicator.growDirection = "RIGHT"
        indicator.spacing = 0
    elseif indicatorType == "square" then
        indicator.ownOnly = true
        indicator.showDuration = true
        indicator.color = { r = 0x0C / 255, g = 0xD2 / 255, b = 0x9D / 255 }
        indicator.indBorderSize = 1
        indicator.indBorderColor = { r = 0, g = 0, b = 0 }
        indicator.frameLevel = "medium"
        indicator.growDirection = "RIGHT"
        indicator.spacing = 0
    elseif indicatorType == "bar" then
        indicator.ownOnly = true
        indicator.color = { r = 0x0C / 255, g = 0xD2 / 255, b = 0x9D / 255 }
        indicator.barColorOpacity = 100
        indicator.frameLevel = "behindBorders"
        indicator.barWidth = 30
        indicator.barHeight = 4
        indicator.barFullWidth = false
        indicator.barFullHeight = false
        indicator.orientation = "HORIZONTAL"
        indicator.reverseFill = false
        indicator.barBgOpacity = 50
        indicator.barBgColor = { r = 0, g = 0, b = 0 }
    elseif indicatorType == "healthcolor" then
        indicator.ownOnly = true
        indicator.color = { r = 0, g = 1, b = 0 }
        indicator.opacity = 100
        indicator.showWhen = "present"
    elseif indicatorType == "bgcolor" then
        indicator.ownOnly = true
        indicator.color = { r = 0, g = 1, b = 0 }
        indicator.opacity = 100
        indicator.showWhen = "present"
    elseif indicatorType == "border" then
        indicator.ownOnly = true
        local _ac = CludesUI and CludesUI.ACCENT_COLOR
        indicator.color = _ac and { r = _ac.r, g = _ac.g, b = _ac.b } or { r = 0.30, g = 0.79, b = 0.94 }
        indicator.borderStyle = "solid"
        indicator.borderWidth = 2
        indicator.borderDashCount = 8
        indicator.borderOpacity = 100
        indicator.showWhen = "present"
    elseif indicatorType == "framealpha" then
        indicator.ownOnly = true
        indicator.alpha = 0.4
        indicator.showWhen = "present"
    end
    return indicator
end

-- Spells that should NOT show a cooldown swipe in preview (no meaningful duration)
local PREVIEW_NO_DURATION = {
    [53563] = true, -- Beacon of Light
    [156910] = true, -- Beacon of Faith
    [369459] = true, -- Source of Magic
    [974] = true, -- Earth Shield
}
mod.BM_PREVIEW_NO_DURATION = PREVIEW_NO_DURATION

-- Preview cooldown seeds keyed "frameIdx:spellID": fraction remaining 0.2-0.9, generated once and reused.
local pvCDSeeds = {}
local function GetPvCDSeed(frameIdx, spellId)
    local keyName = frameIdx .. ":" .. spellId
    if not pvCDSeeds[keyName] then
        pvCDSeeds[keyName] = 0.2 + math.random() * 0.7
    end
    return pvCDSeeds[keyName]
end

-------------------------------------------------------------------------------
--  Default indicator presets (populated on first load per spec)
-------------------------------------------------------------------------------
local DEFAULT_INDICATORS = {
    DRUID_RESTORATION = {
        { pos = "TOPLEFT", spells = { 33763 } }, -- Lifebloom
        { pos = "TOPRIGHT", spells = { 8936, 774, 155777, 48438, 439530 } }, -- Regrowth, Rejuv, Germination, Wild Growth, Symbiotic Blooms
    },
    PRIEST_DISCIPLINE = {
        { pos = "TOPLEFT", spells = { 194384, 10060 } }, -- Atonement, Power Infusion
        { pos = "TOPRIGHT", spells = { 17, 1253593, 41635 } }, -- PW:S, Void Shield, Prayer of Mending
    },
    PRIEST_HOLY = {
        { pos = "TOPLEFT", spells = { 139, 10060 } }, -- Renew, Power Infusion
        { pos = "TOPRIGHT", spells = { 77489, 41635 } }, -- Echo of Light, Prayer of Mending
    },
    MONK_MISTWEAVER = {
        { pos = "TOPLEFT", spells = { 119611, 124682 } }, -- Renewing Mist, Enveloping Mist
        { pos = "TOPRIGHT", spells = { 115175, 443113 } }, -- Soothing Mist, Strength of the Black Ox
    },
    SHAMAN_RESTORATION = {
        { pos = "TOPLEFT", spells = { 974 } }, -- Earth Shield
        { pos = "TOPRIGHT", spells = { 61295, 207400, 444490 } }, -- Riptide, Ancestral Vigor, Hydrobubble
    },
    PALADIN_HOLY = {
        { pos = "TOPLEFT", spells = { 53563, 156910, 200025, 1244893 } }, -- Beacon of Light, Beacon of Faith, Beacon of Virtue, Beacon of the Savior
        { pos = "TOPRIGHT", spells = { 431381, 156322, 432502 } }, -- Dawnlight, Eternal Flame, Holy Armaments
    },
    EVOKER_PRESERVATION = {
        { pos = "TOPLEFT", spells = { 364343, 373267 } }, -- Echo, Lifebind
        { pos = "TOPRIGHT", spells = { 366155, 367364, 355941, 376788, 363502 } }, -- Reversion, Echo Reversion, Dream Breath, Echo Dream Breath, Dream Flight
    },
    EVOKER_AUGMENTATION = {
        { pos = "TOPLEFT", spells = { 410089, 360827, 369459 } }, -- Prescience, Blistering Scales, Source of Magic
        { pos = "TOPRIGHT", spells = { 413984, 410263, 410686, 395152, 361021 } }, -- Shifting Sands, Infernos Blessing, Symbiotic Bloom, Ebon Might, Sense Power
    },
}

local function PopulateDefaults(entries, specKey)
    local presets = DEFAULT_INDICATORS[specKey]
    if not presets then
        return
    end
    for _, preset in ipairs(presets) do
        local indicator = NewIndicator("icon", preset.spells)
        indicator.position = preset.pos
        if preset.pos == "TOPRIGHT" then
            indicator.growDirection = "LEFT"
        end
        tinsert(entries, indicator)
    end
end

-- Legacy->v2 import inputs: preset table + factory, used to detect untouched default spec buckets.
mod.BM_DefaultIndicators = DEFAULT_INDICATORS
mod.BM_NewIndicator = NewIndicator

-------------------------------------------------------------------------------
--  Assignment helpers
-------------------------------------------------------------------------------
local function GetSpecIndicators(saved, specKey)
    -- Buff Manager v2 (flag-gated): storage lives in p.bm2 spec tables
    -- (spell -> filter -> indicator), legacy-shaped plus a `filters` map, so
    -- the ENTIRE editor works on them unchanged through this one accessor.
    -- v2 keys by the CURRENT player spec (class:index); healer specKey ignored.
    if mod.BM2_SpecInds then
        -- Key routes: healer spec key = that set, "nonhealer" = shared bucket, nil = the active key.
        local inds = mod.BM2_SpecInds(specKey)
        if inds then
            return inds
        end
    end
    if not saved or not saved.profile then
        return {}
    end
    if not saved.profile.bmIndicators then
        saved.profile.bmIndicators = {}
    end
    if not saved.profile.bmIndicators[specKey] then
        saved.profile.bmIndicators[specKey] = {}
        PopulateDefaults(saved.profile.bmIndicators[specKey], specKey)
    end
    return saved.profile.bmIndicators[specKey]
end
mod.BM_PrimaryByAlt = PRIMARY_BY_ALT

-- First tracked spec of the player's class, nil for untracked classes; the per-indicator all-specs fallback resolves through it.
local function ClassFallbackSpecKey()
    local _, classFile = UnitClass("player")
    if classFile then
        for _, specInfo in ipairs(HEALER_SPECS) do
            if specInfo.classToken == classFile then
                return specInfo.key
            end
        end
    end
    return nil
end
mod.BM_ClassFallbackSpecKey = ClassFallbackSpecKey

local function CountSpecIndicators(saved, specKey)
    local entries = GetSpecIndicators(saved, specKey)
    return #entries
end

-------------------------------------------------------------------------------
--  Lookup rebuild: per-spec defaults, the active spec and the indicator id
--  counter. Rebuilt whenever indicators change (login, spec change, editor
--  writes).
-------------------------------------------------------------------------------
local function RebuildLookup(saved)
    if not saved or not saved.profile then
        return
    end

    -- Ensure defaults are populated for all specs (triggers on first load)
    for _, specInfo in ipairs(HEALER_SPECS) do
        GetSpecIndicators(saved, specInfo.key)
    end

    DetectActiveSpecKey()

    -- Sync nextIndicatorId to highest existing id
    for _, specData in pairs(saved.profile.bmIndicators) do
        if type(specData) == "table" then
            for _, indicator in ipairs(specData) do
                if indicator.id and indicator.id >= nextIndicatorId then
                    nextIndicatorId = indicator.id + 1
                end
            end
        end
    end
end

mod.BM_RebuildLookup = RebuildLookup

-------------------------------------------------------------------------------
--  Pool sizes
-------------------------------------------------------------------------------
local ICON_POOL_SIZE = 8 -- max placed indicators visible per button
local BAR_POOL_SIZE = 4

-- Size + anchor a bar indicator to its unit's health bar; shared by live and
-- preview so they stay 1:1. Full Width/Height off = slider size at the anchor;
-- on = edge-pinned to the health bar (pixel-for-pixel), anchor still drives the free axis.
local function BM_PlaceBar(barFrame, healthBar, indicator, iscale)
    local wid = indicator.barWidth or 30
    local hgt = indicator.barHeight or 4
    local isVert = (indicator.orientation or "HORIZONTAL") == "VERTICAL"
    barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    barFrame:ClearAllPoints()
    -- Full Width/Height follow the fill axis like barWidth/barHeight: vertical
    -- bars swap the spanned screen edge, so "Full Width" always spans horizontal.
    -- Explicit if/else, not `a and b or c` -- the values are booleans.
    local fullW, fullH
    if isVert then
        fullW, fullH = indicator.barFullHeight, indicator.barFullWidth
    else
        fullW, fullH = indicator.barFullWidth, indicator.barFullHeight
    end
    -- Full pins span the health bar itself, keeping the real bar even when Uniform Icon Anchoring passes the full-height reference (it back-points).
    local hugBar = healthBar._cuiHealth or healthBar
    if fullW and fullH then
        -- Exact overlay of the health bar.
        barFrame:SetAllPoints(hugBar)
    elseif fullW then
        -- Full width; cross-axis slider sets thickness, vertical edge places it.
        local place = indicator.position or "TOPLEFT"
        local vEdge = (place:find("BOTTOM", 1, true) and "BOTTOM")
            or (place:find("TOP", 1, true) and "TOP")
            or ""
        local oy = (indicator.offsetY or 0) * iscale
        barFrame:SetPoint(vEdge .. "LEFT", healthBar, vEdge .. "LEFT", 0, oy)
        barFrame:SetPoint(vEdge .. "RIGHT", healthBar, vEdge .. "RIGHT", 0, oy)
        barFrame:SetHeight(isVert and wid or hgt)
    elseif fullH then
        -- Full height; cross-axis slider sets thickness, horizontal edge places it.
        local place = indicator.position or "TOPLEFT"
        local hEdge = (place:find("RIGHT", 1, true) and "RIGHT")
            or (place:find("LEFT", 1, true) and "LEFT")
            or ""
        local ox = (indicator.offsetX or 0) * iscale
        barFrame:SetPoint("TOP" .. hEdge, hugBar, "TOP" .. hEdge, ox, 0)
        barFrame:SetPoint("BOTTOM" .. hEdge, hugBar, "BOTTOM" .. hEdge, ox, 0)
        barFrame:SetWidth(isVert and hgt or wid)
    else
        if isVert then
            barFrame:SetSize(hgt, wid)
        else
            barFrame:SetSize(wid, hgt)
        end
        barFrame:SetPoint(
            indicator.position or "TOPLEFT",
            healthBar,
            indicator.position or "TOPLEFT",
            (indicator.offsetX or 0) * iscale,
            (indicator.offsetY or 0) * iscale
        )
    end
end

-- Re-level a pooled icon/square frame for its Frame Level mode. baseLvl = the
-- unit button's level; own border at base+1, count/duration text carrier pinned
-- at +18 regardless of mode. Runs per assignment: pool frames are reused across indicators with different modes.
local function BM_ApplyIconLevel(tile, indicator, baseLvl)
    local off = FRAMELVL_BASE[indicator.frameLevel or "medium"] or FRAMELVL_BASE.medium
    tile:SetFrameLevel(baseLvl + off)
    -- Swipe + border one above the icon, text carrier on top; set each explicitly, not by child-level propagation.
    if tile._cooldown then
        tile._cooldown:SetFrameLevel(baseLvl + off + 1)
    end
    if tile._bdr then
        tile._bdr:SetFrameLevel(baseLvl + off + 1)
    end
    if tile._textCarrier then
        tile._textCarrier:SetFrameLevel(baseLvl + FRAMELVL_TEXT)
    end
end

-- Bars have no border/text sub-frames: base only, defaulting to Behind Borders.
local function BM_ApplyBarLevel(barFrame, indicator, baseLvl)
    barFrame:SetFrameLevel(
        baseLvl + (FRAMELVL_BASE[indicator.frameLevel or "behindBorders"] or FRAMELVL_BASE.behindBorders)
    )
end

-- Frame-Border effect. "dashed" = static procedural ants from the glow engine;
-- every other style (solid, textured glow/shadow/blizz/lightspark/dialog,
-- LibSharedMedia) goes through CludesUI.ApplyBorderStyle (PP-vs-
-- BackdropTemplate swap; one renderer active, style stamped on frame). r,g,b,a are non-secret configured values; callers Show().
local function ApplyEffectBorder(borderFrame, indicator, r, g, b, a, wid, hgt)
    local style = indicator.borderStyle or "solid"
    -- Sweep is not offered: no secret-safe way to drive the perimeter reveal on containers, and a full ring duplicates Solid. Stale picks render Solid.
    if style == "sweepcw" or style == "sweepccw" then
        style = "solid"
    end
    local bw = indicator.borderWidth or 2
    local Glows = CludesUI.Glows
    local hostFrame = borderFrame:GetParent()
    local baseLvl = (hostFrame and hostFrame:GetFrameLevel()) or borderFrame:GetFrameLevel()
    -- One under the raise (+9: solid strips +10, textured +9): over the base border,
    -- under the hover/target/aggro raise and the text band. Matches creation.
    borderFrame:SetFrameLevel(baseLvl + mod.LVL_RAISE - 1)
    if style == "dashed" then
        CludesUI.HideBorderStyle(borderFrame)
        Glows.StartProceduralAnts(
            borderFrame,
            indicator.borderDashCount or 8,
            bw,
            nil,
            nil,
            r,
            g,
            b,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            true
        )
        Glows.SetProceduralAntsColor(borderFrame, r, g, b, a)
    else
        Glows.StopProceduralAnts(borderFrame)
        if CludesUI.ApplyBorderStyle then
            -- Solid takes width as literal pixels; textured styles index the edge-size map (steps 1-4 only), so cap to dodge the >4 fallback.
            local sz = (style == "solid") and bw or math.min(bw, 4)
            -- Exact size (borderWidthPx, against the step and style drawn): 15th argument.
            CludesUI.ApplyBorderStyle(
                borderFrame,
                sz,
                r,
                g,
                b,
                a,
                style,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                CludesUI.BorderPx(indicator.borderWidthPx, sz, style)
            )
        end
    end
end

-- Containers path: same renderer on the effect slot's border host, same
-- styles/levels. Dashed diverges: the host sits on the forbidden slot-button
-- subtree where driver-ticked ants error outside sanctioned windows, so it uses
-- the C-side animated engine instead (identical in/out of secret; w/h come from OUR frame -- the engine never measures there).
-- Where the client can, the host is bound to its slot button (BmEffectInit), which runs the march itself while it shows an aura: a start
-- or stop the button refuses while auras are restricted re-runs at the lift (the glow engine defers it).
function mod.BM_ApplyEffectBorder(borderFrame, indicator, r, g, b, a, wid, hgt)
    local Glows = CludesUI.Glows
    if wid and (indicator.borderStyle or "solid") == "dashed" then
        CludesUI.HideBorderStyle(borderFrame)
        -- Same level as the static styles (this branch returns first): otherwise the host stays at slot+1, one level BELOW the health bar (unit+2).
        local hostFrame = borderFrame:GetParent()
        local baseLvl = (hostFrame and hostFrame:GetFrameLevel()) or borderFrame:GetFrameLevel()
        borderFrame:SetFrameLevel(baseLvl + mod.LVL_RAISE - 1)
        Glows.StartAnimatedAnts(
            borderFrame,
            indicator.borderDashCount or 8,
            indicator.borderWidth or 2,
            nil,
            r,
            g,
            b,
            wid,
            hgt,
            a
        )
        return
    end
    -- Leaving dashed tears the animated march down (no-op if never armed).
    if wid then
        Glows.StopAnimatedAnts(borderFrame)
    end
    ApplyEffectBorder(borderFrame, indicator, r, g, b, a, wid, hgt)
end

-------------------------------------------------------------------------------
--  Preview indicator creation
-------------------------------------------------------------------------------
-- Forward-declare so preview click handler can set it (defined further down)
local pickedIndicator = nil

-- Preview indicator handlers: hover shows a 2px accent border, click selects.
local function PvInd_OnEnter(self)
    if not self._bmIndId then
        return
    end
    if self._hoverBdr then
        local lPP = CludesUI.PanelPP or CludesUI.PP
        if lPP then
            local ac = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
            lPP.UpdateBorder(self._hoverBdr, 2, ac.r, ac.g, ac.b, 1)
            self._hoverBdr:Show()
        end
    end
end

local function PvInd_OnLeave(self)
    if self._hoverBdr then
        self._hoverBdr:Hide()
    end
end

-- Resolve the indicator table for a preview frame's stored indicator id.
-- Second return = the owning GROUP bucket key when the id came from an
-- INHERITED preview copy (display-offset id ranges; see BM_INH_OFFSETS).
local function BM_FindIndicatorById(indId)
    local specKey = mod._bmSelectedSpecKey
    -- v2: resolve against the REAL store (legacy is stale/absent, preview ids come from v2 copies) -- selection must hit storage so edits stick.
    local inds = mod.BM2_SpecInds(specKey)
    if inds then
        for _, indicator in ipairs(inds) do
            if indicator.id == indId then
                return indicator
            end
        end
    end
    -- Inherited copies carry their group's display offset: undo it and
    -- resolve in the owning group's store. Group-bucket ids always start
    -- at the 1000001 base (seeded buckets; legacy small ids exist only
    -- in healer-key OWN buckets), so a floor keeps a wrong-offset probe
    -- from landing in another bucket's small-id band.
    local groups = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(specKey)
    if groups then
        for gi = 1, #groups do
            local gkey = groups[gi]
            local off = mod.BM_INH_OFFSETS[gkey] or 0
            local rawId = indId - off
            if rawId >= 1000000 and rawId ~= indId then
                local ginds = mod.BM2_SpecInds(gkey)
                if ginds then
                    for _, indicator in ipairs(ginds) do
                        if indicator.id == rawId then
                            return indicator, gkey
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function PvInd_OnClick(self, btnFrame)
    if not self._bmIndId then
        return
    end
    local indicator, inhGroup = BM_FindIndicatorById(self._bmIndId)
    if not indicator then
        return
    end

    -- Right-click: deliberately no action.
    if btnFrame == "RightButton" then
        return
    end

    -- Left-click: select the indicator for editing in the sidebar. An
    -- inherited copy selects its read-only tile instead.
    if inhGroup then
        pickedIndicator = nil
        mod._bm2InhSel = { group = inhGroup, id = indicator.id }
    else
        pickedIndicator = indicator
        mod._bm2InhSel = nil
    end
    CludesUI:RefreshPage(true)
end

local function AttachPvIndHover(tile, Pix)
    if Pix then
        -- The preview's pooled frames (options page pool): handed out again by the next render.
        local CreateFrame = POOL.CreateFrame
        local hb = CreateFrame("Frame", nil, tile)
        hb:SetAllPoints()
        hb:SetFrameLevel(tile:GetFrameLevel() + 8)
        hb:EnableMouse(false)
        Pix.CreateBorder(hb, 0, 0, 0, 0, 2)
        hb:Hide()
        tile._hoverBdr = hb
    end
    tile:EnableMouse(true)
    tile:SetScript("OnEnter", PvInd_OnEnter)
    tile:SetScript("OnLeave", PvInd_OnLeave)
    tile:SetScript("OnMouseUp", PvInd_OnClick)
end

function mod.BM_CreatePreviewIndicators(f, healthBar, Pix)
    if not healthBar then
        return
    end
    -- Options page pool (CludesUI_FramePool.lua): on the Buff Manager's kept
    -- root these are handed out again, in creation order, by the next render.
    local CreateFrame = POOL.CreateFrame

    local iconPool = {}
    -- Pool is larger than per-group caps: every group must still get icons on
    -- specs with many groups (non-selected groups dim, never vanish). The
    -- extra headroom covers the editing-spec union too -- concrete views
    -- preview inherited group buckets on top of their own list, and overflow
    -- is a silent vanish.
    for idx = 1, ICON_POOL_SIZE + 24 do
        local tile = CreateFrame("Frame", nil, healthBar)
        tile:SetFrameLevel(f:GetFrameLevel() + mod.LVL_AURA)
        tile:SetSize(12, 12)
        tile:Hide()

        local tex = tile:CreateTexture(nil, "ARTWORK")
        if Pix then
            Pix.DisablePixelSnap(tex)
        end
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tile._tex = tex

        local cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.6)
        cooldown:SetReverse(true)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:EnableMouse(false)
        cooldown:Hide()
        tile._cooldown = cooldown

        if Pix then
            local bdr = CreateFrame("Frame", nil, tile)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(tile:GetFrameLevel() + 1)
            bdr:EnableMouse(false)
            Pix.CreateBorder(bdr, 0, 0, 0, 1, 1)
            tile._bdr = bdr
        end

        local textCarrier = CreateFrame("Frame", nil, tile)
        textCarrier:SetAllPoints()
        textCarrier:SetFrameLevel(tile:GetFrameLevel() + 5)
        textCarrier:EnableMouse(false)
        tile._textCarrier = textCarrier
        local countFS = textCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 1, -1)
        local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        CludesUI.ApplyIconTextFont(countFS, fontFile, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        tile._count = countFS

        local durFS = textCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", tile, "CENTER", 0, 0)
        CludesUI.ApplyIconTextFont(durFS, fontFile, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        tile._durText = durFS

        AttachPvIndHover(tile, Pix)
        iconPool[idx] = tile
    end

    local barPool = {}
    -- +4: bar indicators inherited from group buckets preview alongside the
    -- edited bucket's own (same union-headroom reasoning as the icon pool).
    for idx = 1, BAR_POOL_SIZE + 4 do
        local barFrame = CreateFrame("StatusBar", nil, healthBar)
        barFrame:SetFrameLevel(f:GetFrameLevel() + mod.LVL_AURA)
        barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        barFrame:SetMinMaxValues(0, 1)
        barFrame:SetValue(0.6)
        barFrame:Hide()

        local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.5)
        barFrame._bg = backdrop

        AttachPvIndHover(barFrame, Pix)
        barPool[idx] = barFrame
    end

    -- Frame effect overlays for preview: ARTWORK sublevel 2 sits below the dispel overlay (sublevel 3), matching the real frames.
    local hcOverlay = healthBar:CreateTexture(nil, "ARTWORK", nil, 2)
    local pvFillTex = healthBar:GetStatusBarTexture()
    if pvFillTex then
        hcOverlay:SetAllPoints(pvFillTex)
    else
        hcOverlay:SetAllPoints(healthBar)
    end
    hcOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    hcOverlay:Hide()

    -- Background Color: whole health area, BELOW the fill (ARTWORK -2) so the tint reads as the bar's background, matching the real frames.
    local bgOverlay = healthBar:CreateTexture(nil, "ARTWORK", nil, -2)
    bgOverlay:SetAllPoints(healthBar)
    bgOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    bgOverlay:Hide()

    local effectBorder = CreateFrame("Frame", nil, f)
    effectBorder:SetAllPoints(f)
    effectBorder:SetFrameLevel(f:GetFrameLevel() + mod.LVL_RAISE - 1)
    effectBorder:Hide()
    if Pix then
        Pix.CreateBorder(effectBorder, 0, 1, 0, 1, 2)
    end

    f._bmIconPool = iconPool
    f._bmBarPool = barPool
    f._bmHCOverlay = hcOverlay
    f._bmHCBar = healthBar
    f._bmBGOverlay = bgOverlay
    f._bmEffectBorder = effectBorder
end

-------------------------------------------------------------------------------
--  Preview data application: player slot 1, using the real saved configs.
-------------------------------------------------------------------------------
local previewSpellIcons = {}

local function GetSpellIcon(spellId)
    if previewSpellIcons[spellId] then
        return previewSpellIcons[spellId]
    end
    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    local icon = (details and details.iconID) or 136243
    previewSpellIcons[spellId] = icon
    return icon
end

function mod.BM_ApplyPreviewIndicators(f, index, s)
    local iconPool = f._bmIconPool
    local barPool = f._bmBarPool
    if not iconPool then
        return
    end
    -- A manager page replica built in party style keeps reading the party view.
    s = f._bmPvS or s
    -- Party preview passes the party proxy as `s`; use the party scale.
    local iscale = ((s == mod._scaledPartyProxy) and mod._partyBmScale or mod._bmScale) or 1
    -- The frames this preview stands for, which each indicator's Show In is
    -- tested against as the live frames test it (ns.BM2_SpecIndicators).
    local pvKind = (f._bmPvS or (s ~= nil and s == mod._scaledPartyProxy)) and "party" or "raid"

    -- Hide all first (reset cooldowns so they re-apply fresh)
    for _, tile in ipairs(iconPool) do
        if tile._cooldown then
            tile._cooldown:SetCooldown(0, 0)
            tile._cooldown:Hide()
        end
        if tile._durText then
            tile._durText:Hide()
        end
        if tile._hoverBdr then
            tile._hoverBdr:Hide()
        end
        tile._bmIndId = nil
        tile._bmSpellId = nil
        tile._bmIndType = nil
        tile:Hide()
    end
    if barPool then
        for _, b in ipairs(barPool) do
            if b._hoverBdr then
                b._hoverBdr:Hide()
            end
            b._bmIndId = nil
            b:Hide()
        end
    end
    if f._bmHCOverlay then
        f._bmHCOverlay:Hide()
    end
    if f._bmBGOverlay then
        f._bmBGOverlay:Hide()
    end
    if f._bmEffectBorder then
        f._bmEffectBorder:Hide()
    end
    f:SetAlpha(1)

    -- Only show on slot 1 (player) for the preview
    if index ~= 1 then
        return
    end

    local saved = mod.db
    if not saved or not saved.profile then
        return
    end
    local healthBar = mod.RF_AnchorHost and mod.RF_AnchorHost(f._health, s) or f._health
    if not healthBar then
        return
    end
    local Pix = CludesUI.PanelPP or CludesUI.PP
    -- Base level for the Frame Level setting (mirrors the live render).
    local pvBaseLvl = f:GetFrameLevel()

    -- Show only the selected spec's indicators
    local iPoolIdx = 0
    local bPoolIdx = 0

    local activeSpecKey = mod._bmSelectedSpecKey
    local specList
    -- Preview the SELECTED v2 bucket with RESOLVED spell unions.
    do
        -- Edited bucket's class: OWN-ONLY entries preview only this class's
        -- spells (a Holy Paladin editing Core Healing Buffs must not see Druid
        -- HoTs -- those can never be their own casts). Untagged/custom ids and
        -- ALL-class entries always pass; show-anyone entries are never class-filtered.
        local edClass
        for idx = 1, #HEALER_SPECS do
            if HEALER_SPECS[idx].key == activeSpecKey then
                edClass = HEALER_SPECS[idx].classToken
                break
            end
        end
        -- Per-spec buckets: class from the spec ID in the key.
        if not edClass and type(activeSpecKey) == "string" then
            local spellRef = activeSpecKey:match("^spec(%d+)$")
            if spellRef and GetSpecializationInfoByID then
                local _, _, _, _, _, castFrame = GetSpecializationInfoByID(tonumber(spellRef))
                edClass = castFrame
            end
            -- WoW Forever: no by-ID spec lookup; the class from the spec table.
            if not edClass and spellRef and CludesUI.IS_FOREVER then
                edClass = CludesUI.SpecClassOf(tonumber(spellRef))
            end
        end
        if not edClass then
            local _, castFrame = UnitClass("player")
            edClass = castFrame
        end
        local spellClass = mod.BM2_SpellClass
        local result = {}
        -- Shared per-indicator preview synthesis; idOffset shifts INHERITED
        -- copies into their display id range (BM_INH_OFFSETS) so ids stay
        -- unique for the anchor pass, selection highlight and click-resolve.
        -- list = the indicator's own bucket, where its Anchor To root lives.
        local function AppendPv(indicator, idOffset, entries)
            -- Show In: left out where the live frames of this kind leave it out.
            local showIn = mod.BM2_EffectiveShowIn and mod.BM2_EffectiveShowIn(indicator, entries)
            if (showIn == "raid" and pvKind == "party") or (showIn == "party" and pvKind ~= "party") then
                return
            end
            local resolved
            if mod.BM2_ResolveSpells then
                resolved = mod.BM2_ResolveSpells(indicator)
            end
            if not (resolved and #resolved > 0) then
                return
            end
            -- Own-only is per-indicator: preview only spells the edited class could have cast.
            local kept = {}
            for jdx = 1, #resolved do
                local spellRef = resolved[jdx]
                local c = spellClass and spellClass[spellRef]
                if not (indicator.ownOnly == true) or c == nil or c == "ALL" or c == edClass then
                    kept[#kept + 1] = spellRef
                end
            end
            if #kept == 0 then
                return
            end
            local v = {}
            for k, val in pairs(indicator) do
                v[k] = val
            end
            -- Preview parity: per-filter square colors expand exactly like the
            -- live view assembly.
            if mod.BM2_SquareFilterColors then
                v.spellColors = mod.BM2_SquareFilterColors(indicator) or indicator.spellColors
            end
            -- Healing-preset groups preview stacked icons (HoTs coexist); others preview ONE. Read by the render cap.
            local multi = false
            if indicator.filters and mod.BM2_GetFilter then
                for fid in pairs(indicator.filters) do
                    local popFrame = mod.BM2_GetFilter(fid)
                    if popFrame and (popFrame.preset == "coreheals" or popFrame.preset == "lesserheals") then
                        multi = true
                        break
                    end
                end
            end
            v._pvMulti = multi
            -- Lead with an edited-class spell so the single-icon preview shows something that spec could cast/receive.
            for jdx = 2, #kept do
                if spellClass and spellClass[kept[jdx]] == edClass then
                    kept[1], kept[jdx] = kept[jdx], kept[1]
                    break
                end
            end
            v.spells = kept
            if idOffset then
                if type(v.id) == "number" then
                    v.id = v.id + idOffset
                end
                if type(v.anchorTo) == "number" then
                    v.anchorTo = v.anchorTo + idOffset
                end
            end
            result[#result + 1] = v
        end
        local inds = mod.BM2_SpecInds(activeSpecKey)
        if inds then
            for idx = 1, #inds do
                AppendPv(inds[idx], nil, inds)
            end
        end
        -- Concrete views union the inherited group buckets, so the preview
        -- matches what the spec actually renders; per-spec disabled entries
        -- are excluded (they do not render live either).
        local inhGroups = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(activeSpecKey)
        if inhGroups then
            for gi = 1, #inhGroups do
                local gkey = inhGroups[gi]
                local ginds = mod.BM2_SpecInds(gkey)
                if ginds then
                    local off = mod.BM_INH_OFFSETS[gkey] or 0
                    for idx = 1, #ginds do
                        local gind = ginds[idx]
                        if
                            not (mod.BM2_InhDisabled and mod.BM2_InhDisabled(activeSpecKey, gkey, gind.id))
                        then
                            AppendPv(gind, off, ginds)
                        end
                    end
                end
            end
        end
        -- Party Frames kit (manager page replica in party style): the live party
        -- frames take the kit's Buff Size and one run outside the frame.
        if f._bmPvS and mod.RF_PartyKit and mod.RF_PartyKit() and mod.RF_KitBmView then
            result = mod.RF_KitBmView(result, true)
        end
        -- Anchor To: stamp members with their terminal root and order them right after it, so the preview renders each set as one run.
        do
            local byId, isMember = {}, {}
            for idx = 1, #result do
                if result[idx].id ~= nil then
                    byId[result[idx].id] = result[idx]
                end
            end
            for idx = 1, #result do
                local v = result[idx]
                local t = v.anchorTo and byId[v.anchorTo]
                if t and (t.type or "icon") == (v.type or "icon") then
                    local seen = { [v] = true }
                    local rootFrame = t
                    while rootFrame and rootFrame.anchorTo and not seen[rootFrame] do
                        seen[rootFrame] = true
                        rootFrame = byId[rootFrame.anchorTo]
                    end
                    if rootFrame and not rootFrame.anchorTo and rootFrame ~= v then
                        v._pvAnchorRoot = rootFrame.id
                        isMember[v] = true
                    end
                end
            end
            local ordered = {}
            for idx = 1, #result do
                local v = result[idx]
                if not isMember[v] then
                    ordered[#ordered + 1] = v
                    if v.id ~= nil then
                        for jdx = 1, #result do
                            if result[jdx]._pvAnchorRoot == v.id then
                                ordered[#ordered + 1] = result[jdx]
                            end
                        end
                    end
                end
            end
            result = ordered
        end
        specList = result
    end
    -- Anchor To continuation state: root id -> banked cursor/anchor, consumed by member indicators ordered right after their root.
    local pvChain = {}
    for _, specData in pairs({ specList }) do
        if type(specData) == "table" then
            for _, indicator in ipairs(specData) do
                if indicator.enabled and indicator.spells and #indicator.spells > 0 then
                    local indicatorType = indicator.type
                    local typeInfo = INDICATOR_TYPE_MAP[indicatorType]

                    -- Frame effects: show when selected or when all-indicators eyeball is on
                    if not typeInfo or not typeInfo.placed then
                        local isSelected = mod._bmSelectedIndId and indicator.id == mod._bmSelectedIndId
                        local wantShow = isSelected or mod._bmAllIndicatorsVisible
                        if wantShow then
                            if indicatorType == "healthcolor" and f._bmHCOverlay then
                                local c = indicator.color or { r = 0, g = 1, b = 0 }
                                mod.RF_TintOverBarFill(
                                    f._bmHCOverlay,
                                    f._bmHCBar,
                                    c.r,
                                    c.g,
                                    c.b,
                                    (indicator.opacity or 100) / 100
                                )
                                f._bmHCOverlay:Show()
                            elseif indicatorType == "bgcolor" and f._bmBGOverlay then
                                local c = indicator.color or { r = 0, g = 1, b = 0 }
                                mod.RF_TexBgTint(
                                    f._bmBGOverlay,
                                    mod.RF_TexBgPath(s),
                                    mod.RF_IsVerticalFill(s)
                                )
                                f._bmBGOverlay:SetColorTexture(c.r, c.g, c.b, (indicator.opacity or 100) / 100)
                                f._bmBGOverlay:Show()
                            elseif indicatorType == "border" and f._bmEffectBorder and Pix then
                                local c = indicator.color or { r = 0, g = 1, b = 0 }
                                ApplyEffectBorder(
                                    f._bmEffectBorder,
                                    indicator,
                                    c.r,
                                    c.g,
                                    c.b,
                                    (indicator.borderOpacity or 100) / 100
                                )
                                f._bmEffectBorder:Show()
                            elseif indicatorType == "framealpha" then
                                f:SetAlpha(indicator.alpha or 0.4)
                            end
                        end
                    end

                    if typeInfo and typeInfo.placed then
                        if indicatorType == "bar" then
                            bPoolIdx = bPoolIdx + 1
                            local barFrame = barPool and barPool[bPoolIdx]
                            if barFrame then
                                BM_ApplyBarLevel(barFrame, indicator, pvBaseLvl)
                                barFrame:SetReverseFill(indicator.reverseFill or false)
                                local c = indicator.color or { r = 0, g = 1, b = 0 }
                                barFrame:SetStatusBarColor(c.r, c.g, c.b, (indicator.barColorOpacity or 100) / 100)
                                if barFrame._bg then
                                    local bgc = indicator.barBgColor or { r = 0, g = 0, b = 0 }
                                    barFrame._bg:SetColorTexture(
                                        bgc.r,
                                        bgc.g,
                                        bgc.b,
                                        (indicator.barBgOpacity or 50) / 100
                                    )
                                end
                                local barSid = indicator.spells and indicator.spells[1]
                                if barSid and not PREVIEW_NO_DURATION[barSid] then
                                    barFrame:SetValue(GetPvCDSeed(index, barSid))
                                else
                                    barFrame:SetValue(1)
                                end
                                BM_PlaceBar(barFrame, healthBar, indicator, iscale)
                                -- v2 only: non-selected groups dim like icons (legacy preview never dimmed bars).
                                local barSel = mod._bmSelectedIndId and indicator.id == mod._bmSelectedIndId
                                barFrame:SetAlpha((barSel or mod._bmAllIndicatorsVisible) and 1 or 0.5)
                                barFrame._bmIndId = indicator.id
                                barFrame:Show()
                            end
                        else
                            local growDir = indicator.growDirection or "RIGHT"
                            local sz = (indicator.size or 12) * iscale
                            local snap = mod.PixelSnap
                                or function(v)
                                    return v
                                end
                            local gap = snap((indicator.spacing or 1) * iscale)
                            -- Anchor To: members continue the root's run with its growth/anchor/cursor (member wrap previews linear; live wraps properly).
                            local anchorPos = indicator.position or "TOPLEFT"
                            local anchorOX = (indicator.offsetX or 0) * iscale
                            local anchorOY = (indicator.offsetY or 0) * iscale
                            local chainSt = indicator._pvAnchorRoot and pvChain[indicator._pvAnchorRoot]
                            if chainSt then
                                growDir = chainSt.grow
                                anchorPos, anchorOX, anchorOY = chainSt.posKey, chainSt.ox, chainSt.oy
                            end
                            local isSelected = mod._bmSelectedIndId and indicator.id == mod._bmSelectedIndId
                            local maxShow
                            if indicator._pvMulti ~= nil then
                                -- v2: healing-preset groups cap at 4 selected/2 unselected (uncapped unions drain the icon pool and hide other groups); others show ONE.
                                if indicator._pvMulti then
                                    maxShow = (isSelected or mod._bmAllIndicatorsVisible) and 4 or 2
                                else
                                    maxShow = 1
                                end
                            else
                                maxShow = (isSelected or mod._bmAllIndicatorsVisible) and #indicator.spells or 2
                            end
                            -- Grid preview (12.1): mirror the live wrap/cap.
                            local per, wrapUp, wrapLeft = 0, false, false
                            per = tonumber(indicator.iconsPerRow) or 0
                            local pu = string.upper(indicator.position or "TOPLEFT")
                            wrapUp = pu:find("BOTTOM", 1, true) ~= nil or indicator.wrapUp == true
                            wrapLeft = pu:find("RIGHT", 1, true) ~= nil
                            local maxI = tonumber(indicator.maxIcons) or 0
                            if maxI > 0 and maxI < maxShow then
                                maxShow = maxI
                            end
                            local previewTotal = math.min(maxShow, #indicator.spells)
                            -- Running cursor (matches live render): each icon advances the next by its own size so size offsets reflow neighbors.
                            local cursor = 0
                            local pvSelfPoint = indicator.position or "TOPLEFT"
                            if growDir == "CENTER" then
                                -- A wrapped run centers by its first LINE (engine left-aligns continuation rows).
                                local lineCap = previewTotal
                                if per > 0 and per < lineCap then
                                    lineCap = per
                                end
                                local totalW, firstSz = 0, nil
                                for si2 = 1, lineCap do
                                    local s2 = sz
                                    if s2 < 1 then
                                        s2 = 1
                                    end
                                    if not firstSz then
                                        firstSz = s2
                                    end
                                    totalW = totalW + s2
                                end
                                if lineCap > 1 then
                                    totalW = totalW + gap * (lineCap - 1)
                                end
                                cursor = -totalW / 2
                                -- Live parity: containers x-center the run ON the
                                -- position point (vertical seat kept; chains pin
                                -- x-center, slot mode uses symmetric offsets). A
                                -- pos-corner anchor + -totalW/2 start would skew by
                                -- the corner's x-alignment (half an icon at center),
                                -- so anchor by the pos's vertical part + horizontal CENTER.
                                local posU = string.upper(pvSelfPoint)
                                if posU:find("TOP", 1, true) then
                                    pvSelfPoint = "TOP"
                                elseif posU:find("BOTTOM", 1, true) then
                                    pvSelfPoint = "BOTTOM"
                                else
                                    pvSelfPoint = "CENTER"
                                end
                                cursor = -totalW / 2 + (firstSz or sz) / 2
                            end
                            if chainSt then
                                cursor = chainSt.cursor
                                pvSelfPoint = chainSt.selfPoint
                                per = 0
                            end
                            local lineStart = cursor
                            for si, spellRef in ipairs(indicator.spells) do
                                if si > maxShow then
                                    break
                                end
                                iPoolIdx = iPoolIdx + 1
                                local tile = iconPool[iPoolIdx]
                                if tile then
                                    BM_ApplyIconLevel(tile, indicator, pvBaseLvl)
                                    local iconSz = sz
                                    if iconSz < 1 then
                                        iconSz = 1
                                    end
                                    tile:SetSize(iconSz, iconSz)
                                    tile:ClearAllPoints()
                                    -- Place at accumulated sizes, then advance by own
                                    -- size (LEFT/UP negate the axis, no first-icon guard).
                                    -- Grid: reset cursor per line break, shift lines away from the anchored edge (live wrap).
                                    local lineOff = 0
                                    if per > 0 then
                                        if si > 1 and (si - 1) % per == 0 then
                                            cursor = lineStart
                                        end
                                        lineOff = math.floor((si - 1) / per) * (iconSz + gap)
                                    end
                                    local gx, gy = 0, 0
                                    if growDir == "RIGHT" or growDir == "CENTER" then
                                        gx = cursor
                                        cursor = cursor + iconSz + gap
                                        gy = wrapUp and lineOff or -lineOff
                                    elseif growDir == "DOWN" then
                                        gy = -cursor
                                        cursor = cursor + iconSz + gap
                                        gx = wrapLeft and -lineOff or lineOff
                                    elseif growDir == "LEFT" then
                                        gx = -cursor
                                        cursor = cursor + iconSz + gap
                                        gy = wrapUp and lineOff or -lineOff
                                    elseif growDir == "UP" then
                                        gy = cursor
                                        cursor = cursor + iconSz + gap
                                        gx = wrapLeft and -lineOff or lineOff
                                    end
                                    tile:SetPoint(pvSelfPoint, healthBar, anchorPos, anchorOX + gx, anchorOY + gy)
                                    -- "Hide Icons" (icon only): keep frame alpha so stacks preview; zero texture, swipe, border.
                                    local pvHideIcon = (indicatorType == "icon") and indicator.hideIcon == true
                                    local pvAlpha = pvHideIcon and 1 or (indicator.iconOpacity or 100) / 100
                                    if mod._bmAllIndicatorsVisible then
                                        pvAlpha = 1
                                    elseif not isSelected then
                                        pvAlpha = pvAlpha * 0.5
                                    end
                                    tile:SetAlpha(pvAlpha)
                                    if indicatorType == "icon" then
                                        tile._tex:SetTexture(GetSpellIcon(spellRef))
                                        local _z = s.bmIconZoom or 0.08
                                        tile._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
                                        tile._tex:SetVertexColor(1, 1, 1, pvHideIcon and 0 or 1)
                                    else
                                        -- Per-ability color (preview): this spell's color, then legacy ind.color, then default.
                                        local c = (indicator.spellColors and indicator.spellColors[spellRef])
                                            or indicator.color
                                            or { r = 0, g = 1, b = 0 }
                                        -- Reset vertex first (as live): a reused icon frame can carry a faded tint that blanks it.
                                        tile._tex:SetVertexColor(1, 1, 1, 1)
                                        tile._tex:SetColorTexture(c.r, c.g, c.b, 1)
                                        tile._tex:SetTexCoord(0, 1, 0, 1)
                                    end
                                    -- Fixed preview stacks: Blistering Scales 8, Lifebloom 2
                                    local previewStacks = (spellRef == 360827 and "8")
                                        or (spellRef == 33763 and "2")
                                    if indicator.showStacks and previewStacks then
                                        local sSz = (indicator.stacksTextSize or 8) * iscale
                                        local sc = indicator.stacksTextColor or { r = 1, g = 1, b = 1 }
                                        local sOX = (indicator.stacksOffsetX or 0) * iscale
                                        local sOY = (indicator.stacksOffsetY or 0) * iscale
                                        local fp = (CludesUI.GetFontPath("raidFrames"))
                                            or "Fonts\\FRIZQT__.TTF"
                                        CludesUI.ApplyIconTextFont(tile._count, fp, sSz, "raidFrames")
                                        tile._count:SetTextColor(sc.r, sc.g, sc.b)
                                        tile._count:ClearAllPoints()
                                        tile._count:SetPoint(
                                            "BOTTOMRIGHT",
                                            tile,
                                            "BOTTOMRIGHT",
                                            1 + sOX,
                                            -1 + sOY
                                        )
                                        tile._count:SetText(previewStacks)
                                    else
                                        tile._count:SetText("")
                                    end
                                    tile._bmIndId = indicator.id
                                    tile._bmSpellId = spellRef
                                    tile._bmIndType = indicatorType
                                    tile:Show()
                                    -- Preview cooldown swipe (frame must be visible first)
                                    if tile._cooldown then
                                        if not PREVIEW_NO_DURATION[spellRef] then
                                            local seed = GetPvCDSeed(index, spellRef)
                                            local fakeDisplay = math.floor(3 + seed * 17)
                                            -- Use a long future expiry so swipe barely moves
                                            local nowTime = GetTime()
                                            local dur = 3600
                                            local elapsed = dur * (1 - seed)
                                            tile._cooldown:SetCooldown(nowTime - elapsed, dur)
                                            tile._cooldown:SetDrawSwipe(
                                                (not pvHideIcon) and (indicator.showDuration ~= false)
                                            )
                                            tile._cooldown:SetHideCountdownNumbers(true)
                                            -- Manual duration text (static, not a countdown); survives Hide Icons.
                                            if indicator.showDurationText and tile._durText then
                                                local dtc = indicator.durationTextColor or { r = 1, g = 1, b = 1 }
                                                local fp = (CludesUI.GetFontPath("raidFrames"))
                                                    or "Fonts\\FRIZQT__.TTF"
                                                CludesUI.ApplyIconTextFont(
                                                    tile._durText,
                                                    fp,
                                                    indicator.durationTextSize or 8,
                                                    "raidFrames"
                                                )
                                                tile._durText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                                tile._durText:ClearAllPoints()
                                                tile._durText:SetPoint(
                                                    "CENTER",
                                                    tile,
                                                    "CENTER",
                                                    indicator.durationTextOffsetX or 0,
                                                    indicator.durationTextOffsetY or 0
                                                )
                                                tile._durText:SetText(fakeDisplay)
                                                tile._durText:Show()
                                            elseif tile._durText then
                                                tile._durText:Hide()
                                            end
                                            tile._cooldown:Show()
                                        else
                                            tile._cooldown:Hide()
                                            if tile._durText then
                                                tile._durText:Hide()
                                            end
                                        end
                                    end
                                    if tile._bdr and Pix then
                                        local border = not pvHideIcon and mod.RFC_AuraBorder(indicator, "indBorder")
                                            or nil
                                        local pandemicPreview = indicatorType == "icon"
                                            and isSelected
                                            and indicator.pandemicBorderEnabled
                                            and not pvHideIcon
                                            and not CludesUI.IS_FOREVER
                                        if pandemicPreview then
                                            local c = indicator.pandemicBorderColor or { r = 1, g = 0.2, b = 0.2 }
                                            if
                                                indicator.pandemicBorderTextured == true
                                                and border
                                                and border.texture
                                                and border.texture ~= "solid"
                                                and border.texture ~= ""
                                                and CludesUI.ResolveBorderTexture(border.texture)
                                            then
                                                border[1], border[2], border[3], border[4] = c.r, c.g, c.b, 1
                                            else
                                                border =
                                                    { c.r, c.g, c.b, 1, size = indicator.pandemicBorderWidth or 2 }
                                            end
                                        end
                                        mod.RFC_ApplyAuraBorder(
                                            tile._bdr,
                                            tile._bdr,
                                            border,
                                            (tile._cooldown or tile):GetFrameLevel()
                                        )
                                    end
                                end
                            end
                            -- Anchor To: bank the run state under the ROOT id so the next member of the set keeps extending this run.
                            pvChain[indicator._pvAnchorRoot or indicator.id or 0] = {
                                cursor = cursor,
                                grow = growDir,
                                selfPoint = pvSelfPoint,
                                posKey = anchorPos,
                                ox = anchorOX,
                                oy = anchorOY,
                            }
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Options page builder: 70/30 vertical split, full page height. Left = creation
--  row then indicator settings; right = sidebar of indicator tiles, full height.
-------------------------------------------------------------------------------
-- Page-level state (persists across setting changes within same page open)
local selectedSpecKey = nil

-- WoW Forever: the page opens on All Specs each time it is entered (a tab
-- switch, or the panel opening on it); rebuilds while on it keep the pick.
function mod.BM_EnterAllSpecs()
    if not CludesUI.IS_FOREVER then
        return
    end
    mod._bm2SpecInited = true
    if selectedSpecKey == "allspecs" then
        return
    end
    selectedSpecKey = "allspecs"
    pickedIndicator = nil
    mod._bm2InhSel = nil
end

-- Class token of the EDITED bucket (dropdown selection): healer keys map
-- directly, "spec<ID>" keys resolve through the spec API, shared buckets
-- (allspecs/nonhealer) have no single class -> nil (player-class fallback).
local function SelectedBucketClass()
    local keyName = selectedSpecKey
    local hs = keyName and SPEC_BY_KEY[keyName]
    if hs then
        return hs.classToken
    end
    local spellRef = type(keyName) == "string" and keyName:match("^spec(%d+)$")
    if spellRef and GetSpecializationInfoByID then
        local _, _, _, _, _, castFrame = GetSpecializationInfoByID(tonumber(spellRef))
        return castFrame
    end
    -- WoW Forever: no by-ID spec lookup; the class from the spec table.
    if spellRef and CludesUI.IS_FOREVER then
        return CludesUI.SpecClassOf(tonumber(spellRef))
    end
    return nil
end
-- selectedIndicator: forward-declared near preview hover/click handlers
local selectedType = "icon"

local function AutoDetectSpec()
    -- Exact spec match (locale-independent, by spec ID).
    local keyName = CurrentSpecKey()
    if keyName then
        return keyName
    end

    -- Fallback for the options UI: pick the first tracked spec for the player's class so a non-tracked spec (e.g. a DPS spec) still opens on something sane.
    local _, classFile = UnitClass("player")
    if classFile then
        for _, specInfo in ipairs(HEALER_SPECS) do
            if specInfo.classToken == classFile then
                return specInfo.key
            end
        end
    end
    -- Class with no tracked spec (e.g. Warrior): open on Holy Paladin, not blank.
    return "PALADIN_HOLY"
end

-------------------------------------------------------------------------------
--  Health-bar replica preview, shared by the Debuff Manager (draws its own
--  content on it) and the Buff Manager page. opts: previewClass (default:
--  the active spec's class), minH (floor of the whole band, 91: the
--  Editing Spec block beside it), party (read the
--  party view instead of `s`), styleToggle (Raid/Party row above it),
--  kitAuras ("buffs" | "debuffs": the kit hint under that row),
--  overrideTips ({ raid = tip, party = tip }: override marks per segment).
--  Returns pvFrame, sectionH, scale.
function mod.BM_BuildSimplePreview(hostFrame, s, fontFile, Pix, centerX, topY, options)
    -- Options page pool (CludesUI_FramePool.lua): on a manager page's kept
    -- root the replica is handed out again, in creation order, by the next render.
    local CreateFrame = POOL.CreateFrame
    options = options or {}
    -- Party style: the read-only party view (party size without an attached
    -- portrait, party section overrides, party indicator scale), as the live
    -- party frames read it. The kit's art is not rebuilt here.
    if options.party and mod._scaledPartyProxy then
        s = mod._scaledPartyProxy
    end
    local PV_SCALE = 1.5
    local rawW = s.frameWidth or 72
    local rawH = s.frameHeight or 46
    local previewPad = 20
    -- Cap on-screen height at 100px via uniform downscale (keeps rawW:rawH aspect).
    if rawH * PV_SCALE > 100 then
        PV_SCALE = 100 / rawH
    end
    -- Party frames run much wider than raid cells: also keep the width inside
    -- the preview column (centered on centerX).
    if options.party then
        local maxW = centerX * 2 - previewPad * 2
        if maxW > 0 and rawW * PV_SCALE > maxW then
            PV_SCALE = maxW / rawW
        end
    end
    local pvH = floor(rawH * PV_SCALE + 0.5)
    -- The band follows the replica (it changes with the Raid/Party style);
    -- the switch row and kit room join it below.
    local sectionH = pvH + previewPad * 2

    -- Raid/Party row: captioned "Preview" and seated on the replica, so it
    -- reads as a view switch, not as a second set of settings.
    local kitMode = options.party
        and mod.RF_PartyKit
        and mod.RF_PartyKit()
        and mod.RF_KitBuffMode
        and mod.RF_KitBuffMode(mod.db and mod.db.profile)
    local rowH = 0
    if options.styleToggle then
        local row = CreateFrame("Frame", nil, hostFrame)
        local cap = row:CreateFontString(nil, "OVERLAY")
        cap:SetFont(fontFile, 12, "")
        cap:SetTextColor(1, 1, 1, 0.75)
        cap:SetText(CludesUI.L("Preview"))
        local seg, segBtn = mod.BM_BuildPreviewStyleToggle(row)
        row:SetSize(math.ceil(cap:GetStringWidth()) + 10 + seg:GetWidth(), 22)
        row:SetPoint("TOP", hostFrame, "TOPLEFT", floor(centerX), topY)
        cap:SetPoint("LEFT", row, "LEFT", 0, 0)
        seg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        -- Overrides that apply on that side: a gold "i" (the overrides UI's
        -- badge) in the segment's free right padding, carrying the tip.
        -- Motion only: the segment keeps its clicks.
        local tips = options.overrideTips
        if tips then
            local goldColor = CludesUI._SPECOV_GOLD
            for keyName, btn in pairs(segBtn) do
                local tipText = tips[keyName]
                if tipText then
                    local badge = CreateFrame("Frame", nil, btn)
                    badge:SetSize(12, 12)
                    badge:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
                    badge:SetFrameLevel(btn:GetFrameLevel() + 5)
                    local ico = badge:CreateTexture(nil, "OVERLAY")
                    ico:SetAllPoints()
                    ico:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-info.png")
                    ico:SetVertexColor(goldColor[1], goldColor[2], goldColor[3], 0.85)
                    badge:SetScript("OnEnter", function(self)
                        ico:SetVertexColor(goldColor[1], goldColor[2], goldColor[3], 1)
                        CludesUI.ShowWidgetTooltip(self, tipText)
                    end)
                    badge:SetScript("OnLeave", function()
                        ico:SetVertexColor(goldColor[1], goldColor[2], goldColor[3], 0.85)
                        CludesUI.HideWidgetTooltip()
                    end)
                    badge:SetMouseClickEnabled(false)
                end
            end
        end
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.L("Only changes the preview. Raid and party frames share these settings.")
            )
        end)
        row:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        rowH = 22 + 24
        -- The kit decides these auras' size and place on party frames: name
        -- the override and its value, in the accent colour.
        if kitMode and options.kitAuras then
            local p = mod.db.profile
            local hintText = hostFrame:CreateFontString(nil, "OVERLAY")
            hintText:SetFont(fontFile, 11, "")
            local ar, ag, ab = CludesUI.ResolveActiveAccent()
            hintText:SetTextColor(ar or 1, ag or 1, ab or 1, 0.9)
            hintText:SetWidth(centerX * 2 - previewPad * 2)
            hintText:SetWordWrap(true)
            hintText:SetJustifyH("CENTER")
            hintText:SetPoint("TOP", row, "BOTTOM", 0, -8)
            if options.kitAuras == "buffs" then
                hintText:SetText(
                    CludesUI.Lf(
                        "Party Frames kit override: Buff Size %d (Party > Frame Style)",
                        mod.RF_KitBuffSize and mod.RF_KitBuffSize(p) or 15
                    )
                )
            else
                hintText:SetText(
                    CludesUI.Lf(
                        "Party Frames kit override: Debuff Size %d (Party > Frame Style)",
                        p.partyKitDebuffSize or 15
                    )
                )
            end
            rowH = rowH + math.ceil(hintText:GetStringHeight()) + 8
        end
    end
    -- Kit buffs above the frame: room for their lines (at the Buff Manager scale).
    local aboveH = 0
    if kitMode == "ABOVE" and options.kitAuras == "buffs" and mod.RF_KitAboveUnits then
        aboveH = math.ceil(mod.RF_KitAboveUnits(mod.db.profile) * (mod._partyBmScale or 1) * PV_SCALE)
    end
    sectionH = max(sectionH + rowH + aboveH, options.minH or 91)
    topY = topY - rowH - aboveH

    local previewFrame = CreateFrame("Frame", nil, hostFrame)
    previewFrame:SetSize(rawW, rawH)
    previewFrame:SetScale(PV_SCALE)
    previewFrame:SetPoint("TOP", hostFrame, "TOPLEFT", floor(centerX / PV_SCALE), topY / PV_SCALE)
    -- The side the kit's buff run takes (callers keep their controls off it).
    previewFrame._bmKitSide = (options.kitAuras == "buffs") and kitMode or nil

    local bgc = s.customBgColor or { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
    local backdrop = previewFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()

    local rawPowerH = (s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS)
            and (s.powerHeight or 4)
        or 0
    local matchPowerBorder = s.powerBorderMatchFrame == true
        and rawPowerH > 0
        and (s.powerBorderStyle == "divider" or s.powerBorderStyle == "border")
        and not mod.RF_Stock()
        and CludesUI._pixelArtBorders[s.borderTexture]
    local rawTopBarH = s.topNameBarEnabled and (s.topNameBarHeight or 20) or 0
    local matchTopNameDivider = s.topNameBarDivider == true
        and rawTopBarH >= 4
        and (s.borderSize or 1) > 0
        and not mod.RF_Stock()
        and CludesUI._pixelArtBorders[s.borderTexture]
    -- Show on Bottom: the bar takes the bottom edge, health starts at the top and
    -- the power bar sits on the bar (as the live LayoutTopNameBar lays it out).
    local rawBottomY = (s.topNameBarEnabled and s.topNameBarBottom == true) and rawTopBarH or 0
    local healthTopY = (rawBottomY > 0) and 0 or -rawTopBarH
    local healthH = rawH - rawPowerH - rawTopBarH

    -- Health bar (matches the custom preview build exactly)
    local texKey = s.healthBarTexture or "atrocity"
    local texPath = CludesUI.ResolveTexturePath(
        mod.healthBarTextures or {},
        texKey,
        "Interface\\Buttons\\WHITE8X8"
    ) or "Interface\\Buttons\\WHITE8X8"
    local healthBar = CreateFrame("StatusBar", nil, previewFrame)
    healthBar:SetFrameLevel(previewFrame:GetFrameLevel() + 2)
    healthBar:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, healthTopY)
    healthBar:SetPoint("TOPRIGHT", previewFrame, "TOPRIGHT", 0, healthTopY)
    healthBar:SetHeight(healthH)
    healthBar:SetStatusBarTexture(texPath)
    healthBar:GetStatusBarTexture():SetHorizTile(false)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(85)

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    do
        local pvUniformRef = CreateFrame("Frame", nil, previewFrame)
        pvUniformRef:SetFrameLevel(healthBar:GetFrameLevel())
        pvUniformRef:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        pvUniformRef:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 0, rawBottomY)
        healthBar._cuiUniformRef = pvUniformRef
        pvUniformRef._cuiHealth = healthBar
    end

    -- Preview class color from the player's active spec (falls back to class)
    local previewClass = options.previewClass
    if not previewClass and activeSpecKey_BM and SPEC_BY_KEY[activeSpecKey_BM] then
        previewClass = SPEC_BY_KEY[activeSpecKey_BM].classToken
    end
    if not previewClass then
        local _, pc = UnitClass("player")
        previewClass = pc
    end
    local cc = CludesUI.GetClassColor(previewClass)
    local mode = s.healthColorMode or "class"
    local fill = healthBar:GetStatusBarTexture()
    -- Textured Background, as on the live frames.
    mod.RF_TexBgLayer(healthBar, backdrop, mod.RF_TexBgOpaque(s, mode == "dark") and mod.RF_TexBgPath(s) or nil)
    if mode == "dark" then
        local dfr, dfg, dfb, dfa = CludesUI.GetDarkModeFill()
        healthBar:SetStatusBarColor(dfr, dfg, dfb, 1)
        if fill then
            fill:SetAlpha(dfa)
        end
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        backdrop:SetColorTexture(CludesUI.GetDarkModeBg())
    elseif mode == "classic" then
        local pct = 0.85
        local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
        local g = pct > 0.5 and 1 or (pct * 2)
        healthBar:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        if fill then
            fill:SetAlpha(1)
        end
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    elseif mode == "custom" then
        local cfc = s.customFillColor or { r = 37 / 255, g = 193 / 255, b = 29 / 255 }
        healthBar:SetStatusBarColor(cfc.r, cfc.g, cfc.b, (s.healthBarOpacity or 100) / 100)
        if fill then
            fill:SetAlpha(1)
        end
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    else
        if cc then
            healthBar:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100)
        end
        if fill then
            fill:SetAlpha(1)
        end
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    end

    if rawPowerH > 0 then
        local powerBar = CreateFrame("StatusBar", nil, previewFrame)
        powerBar:SetFrameLevel(previewFrame:GetFrameLevel() + 3)
        powerBar:SetPoint("BOTTOMLEFT", previewFrame, "BOTTOMLEFT", 0, rawBottomY)
        powerBar:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 0, rawBottomY)
        powerBar:SetHeight(rawPowerH)
        powerBar:SetStatusBarTexture(texPath)
        powerBar:GetStatusBarTexture():SetHorizTile(false)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(72)
        local pInfo = CludesUI.GetPowerColor("MANA")
        if pInfo then
            powerBar:SetStatusBarColor(pInfo.r, pInfo.g, pInfo.b, 1)
        else
            powerBar:SetStatusBarColor(0, 0.5, 1, 1)
        end
        local pwBg = powerBar:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        local pbc = (s.powerBgPowerColored and pInfo) or s.powerBgColor or { r = 0, g = 0, b = 0 }
        local pbF = (s.powerBgPowerColored and pInfo) and CludesUI.GetPowerBgDarkenFactor() or 1
        mod.RF_TexBgTint(pwBg, mod.RF_TexBgPath(s))
        pwBg:SetColorTexture(pbc.r * pbF, pbc.g * pbF, pbc.b * pbF, (s.powerBgDarkness or 70) / 100)
        -- Classic WoW UI: the stock edge and divider stand in (as live).
        if Pix and mod.RF_Classic and mod.RF_Classic() then
            mod.RF_StockBuild(previewFrame, previewFrame, powerBar)
            mod.RF_StockDivider(previewFrame)
        elseif Pix and s.powerBorderStyle and s.powerBorderStyle ~= "none" then
            local pbSize = matchPowerBorder and (s.borderSize or 1) or (s.powerBorderSize or 1)
            if pbSize > 0 then
                local pwBdr = CreateFrame("Frame", nil, previewFrame)
                pwBdr:SetAllPoints(powerBar)
                pwBdr:SetFrameLevel(powerBar:GetFrameLevel() + 1)
                Pix.CreateBorder(pwBdr, 0, 0, 0, 1, 1)
                if not (matchPowerBorder and mod.RF_ApplyPowerBorderArt(pwBdr, s, true, true)) then
                    local pBc = s.powerBorderColor or { r = 0, g = 0, b = 0 }
                    Pix.UpdateBorder(pwBdr, pbSize, pBc.r, pBc.g, pBc.b, s.powerBorderAlpha or 1)
                    local ppC = Pix.GetBorders(pwBdr)
                    if ppC and s.powerBorderStyle == "divider" then
                        if ppC._bottom then
                            ppC._bottom:SetAlpha(0)
                        end
                        if ppC._left then
                            ppC._left:SetAlpha(0)
                        end
                        if ppC._right then
                            ppC._right:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end

    if Pix then
        -- Stock styles: the stock edge stands in for the CludesUI border.
        if mod.RF_Stock and mod.RF_Stock() then
            mod.RF_StockBuild(previewFrame, previewFrame)
        end
        local bsz = mod.RF_EffBorderSize and mod.RF_EffBorderSize(s) or (s.borderSize or 1)
        if bsz > 0 then
            local bdr = CreateFrame("Frame", nil, previewFrame)
            bdr:SetAllPoints(previewFrame)
            bdr:SetFrameLevel(previewFrame:GetFrameLevel() + 8)
            Pix.CreateBorder(bdr, 0, 0, 0, 1, 1)
            local bc = s.borderColor or { r = 0, g = 0, b = 0 }
            if matchPowerBorder or matchTopNameDivider then
                CludesUI.ApplyBorderStyle(
                    bdr,
                    bsz,
                    bc.r,
                    bc.g,
                    bc.b,
                    s.borderAlpha or 1,
                    s.borderTexture,
                    s.borderTextureOffset,
                    s.borderTextureOffsetY,
                    s.borderTextureShiftX,
                    s.borderTextureShiftY,
                    "unitframes",
                    bsz,
                    nil,
                    CludesUI.BorderPx(s.borderSizePx, bsz, s.borderTexture)
                )
            else
                Pix.UpdateBorder(bdr, bsz, bc.r, bc.g, bc.b, s.borderAlpha or 1)
            end
        end
    end

    -- The texts on a carrier in the live text band (ns.LVL_TEXT) so they draw above the +8 main border, exactly like real
    -- frames; the name's Show Above Icons lifts it over the aura band as live (texts set otherwise get their own carrier).
    local textCarrier = CreateFrame("Frame", nil, previewFrame)
    textCarrier:SetAllPoints(previewFrame)
    textCarrier:SetFrameLevel(
        previewFrame:GetFrameLevel() + (s.nameTextAboveIcons and (mod.LVL_AURA + 6) or (mod.LVL_TEXT or 12))
    )
    local outline = (CludesUI.GetFontOutlineFlag("raidFrames")) or ""
    local playerName = UnitName("player") or "Player"
    if Ambiguate then
        playerName = Ambiguate(playerName, "short")
    end
    playerName = mod.RF_FormatName(playerName, s)
    -- Level Position "Attach to Name" (either format): the Top Name Bar shows the level too.
    local lvlAttach = mod.RF_TextNameAttach(s)

    -- Top Name Bar band (preview replica)
    if s.topNameBarEnabled then
        local tnb = CreateFrame("Frame", nil, previewFrame)
        tnb:SetFrameLevel(previewFrame:GetFrameLevel() + 4)
        if rawBottomY > 0 then
            tnb:SetPoint("BOTTOMLEFT", previewFrame, "BOTTOMLEFT", 0, 0)
            tnb:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 0, 0)
        else
            tnb:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", previewFrame, "TOPRIGHT", 0, 0)
        end
        tnb:SetHeight(rawTopBarH)
        local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
        tnbBg:SetAllPoints()
        local tbgc = s.topNameBarBgColor or { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
        tnbBg:SetColorTexture(tbgc.r, tbgc.g, tbgc.b, (s.topNameBarBgOpacity or 80) / 100)
        local tnbText = tnb:CreateFontString(nil, "OVERLAY")
        -- The player's name: a font family, with no shadow as a plain SetFont.
        CludesUI.SetFontFamily(tnbText, fontFile, s.topNameBarTextSize or 11, outline, false)
        tnbText:SetWordWrap(false)
        if lvlAttach then
            tnbText:SetFormattedText(lvlAttach[1], mod._RFPreviewLevel(), playerName)
        else
            tnbText:SetText(playerName)
        end
        -- This preview draws no role icon, so the name keeps its full width.
        tnb._cuiRoleIcon = false
        mod.RF_PlaceTopNameText(tnbText, tnb, s)
        if (s.topNameBarTextColorMode or "class") == "custom" then
            local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
            tnbText:SetTextColor(c.r, c.g, c.b)
        elseif cc then
            tnbText:SetTextColor(cc.r, cc.g, cc.b)
        else
            tnbText:SetTextColor(1, 1, 1)
        end
        if s.topNameBarDivider == true then
            mod.RF_ApplyTopNameDivider(tnb, s, true)
        end
    end

    -- The texts as live, from this replica's sample values (85% health, 72% mana,
    -- shown with the power sample only). A fresh state per build: the carrier's pooled
    -- FontStrings come back through the pool.
    mod.RF_TextPreview({ textCarrier = textCarrier, _health = healthBar, _txW = rawW }, s, {
        hpPct = 85,
        hpPer = 12000,
        ppPct = 72,
        ppPer = 2500,
        ha = 85 * 3000,
        name = mod.CapName(playerName, s),
        power = rawPowerH > 0 or nil,
        class = previewClass,
        pToken = "MANA",
    })

    previewFrame._health = healthBar
    -- Settings source for every later indicator pass on this replica (nil = the caller's).
    previewFrame._bmPvS = options.party and s or nil

    return previewFrame, sectionH, PV_SCALE
end

-- Which frames a condition group can apply on: raid (raid, battleground),
-- party (dungeon, arena, solo, party). Keybind and Dark Mode hold wherever the
-- player is, so a group with either reaches both; neither when it has no
-- condition.
function mod.BM_CondSides(g)
    local c = g and g.conds or {}
    if c.keybind or c.darkmode then
        return true, true
    end
    return (c.raid or c.battleground) and true or false,
        (c.dungeon or c.arena or c.solo or c.party) and true or false
end

-- The preview side an override editing session pins ("raid" | "party"): a
-- condition group that applies on only one kind of frames. nil = free.
function mod.BM_PreviewPinnedSide()
    local kind, groupId = CludesUI.SpecOverrides_EditSessionInfo()
    if kind ~= "cond" then
        return nil
    end
    local toRaid, toParty = mod.BM_CondSides(CludesUI.Conditions_GroupById(groupId))
    if toParty and not toRaid then
        return "party"
    end
    if toRaid and not toParty then
        return "raid"
    end
    return nil
end

-- The manager previews' style: the pinned side while one applies, else the
-- session choice of the switch.
function mod.BM_PreviewIsParty()
    local pinned = mod.BM_PreviewPinnedSide()
    if pinned then
        return pinned == "party"
    end
    return mod._bmPvParty == true
end

-- The base debuff settings an override can hold key by key (the Debuff
-- Manager's own content rides its forks).
local DM_BASE_KEYS = {
    "debuffSize",
    "debuffPosition",
    "debuffOffsetX",
    "debuffOffsetY",
    "debuffGrowDirection",
    "debuffWrapDirection",
    "debuffPerRow",
    "debuffCap",
    "debuffSpacing",
    "debuffIconZoom",
    "debuffBorderSize",
    "debuffShowSwipe",
    "debuffBorderTexture",
    "debuffBorderSizePx",
    "debuffBorderColor",
    "debuffBorderTextureOffset",
    "debuffBorderTextureOffsetY",
    "debuffBorderTextureShiftX",
    "debuffBorderTextureShiftY",
    "debuffBorderDispelTextured",
    "debuffShowDurText",
    "debuffDurTextSize",
    "debuffShowStacks",
    "debuffStacksTextSize",
    "debuffStacksOffsetX",
    "debuffStacksOffsetY",
}

-- The manager previews' override marks: tooltips for the Raid and the Party
-- segment, nil where no override applies (read-only queries of the overrides
-- system). "bm": groups with their own Buff Manager; "dm": groups with their
-- own Debuff Manager and overrides holding base debuff settings. A condition
-- group lands on the side whose frames it applies on; spec groups land on both.
function mod.BM_PreviewOverrideTips(kind)
    local raid, party, seenR, seenP = nil, nil, {}, {}
    local function Add(label, toRaid, toParty)
        label = label or "?"
        if toRaid and not seenR[label] then
            seenR[label] = true
            raid = raid or {}
            raid[#raid + 1] = label
        end
        if toParty and not seenP[label] then
            seenP[label] = true
            party = party or {}
            party[#party + 1] = label
        end
    end
    local function AddCond(groupId)
        local g = groupId and CludesUI.Conditions_GroupById(groupId)
        if not g then
            return
        end
        local toRaid, toParty = mod.BM_CondSides(g)
        if not (toRaid or toParty) then
            toRaid, toParty = true, true
        end
        Add(g.name, toRaid, toParty)
    end
    -- Groups with their own Buff or Debuff Manager.
    local specGids, condGids = CludesUI.SpecOverrides_ManagerForkOwners(kind)
    for idx = 1, #specGids do
        local g = CludesUI.SpecOverrides_GroupById(specGids[idx])
        if g then
            Add(g.name, true, true)
        end
    end
    for idx = 1, #condGids do
        AddCond(condGids[idx])
    end
    if kind == "dm" then
        local holders = CludesUI.SpecOverrides_CapturedBy("CludesUIRaidFrames", DM_BASE_KEYS)
        for jdx = 1, #holders do
            local hgt = holders[jdx]
            if hgt.kind == "cond" then
                AddCond(hgt.id)
            else
                -- Spec values: the spec's group, else the spec's own name.
                local og = CludesUI.SpecOverrides_OwningGroupFor(hgt.id)
                local label = og and og.name
                if not label and GetSpecializationInfoByID then
                    local _, sn = GetSpecializationInfoByID(hgt.id)
                    label = sn
                end
                Add(label, true, true)
            end
        end
    end
    local sub = (kind == "bm") and CludesUI.L("These overrides use their own Buff Manager.")
        or CludesUI.L("These overrides hold their own debuff settings.")
    local rgb = CludesUI._SPECOV_GOLD
    local goldColor = CludesUI.HexColor(rgb[1], rgb[2], rgb[3])
    local function Tip(nameList)
        if not nameList then
            return nil
        end
        return goldColor
            .. CludesUI.L("Overridden by:")
            .. "|r "
            .. table.concat(nameList, ", ")
            .. "\n"
            .. CludesUI.COLOR_CODES.DIM
            .. sub
            .. "|r"
    end
    return Tip(raid), Tip(party)
end

-- Raid / Party style switch of the manager pages' previews. Session only
-- (never saved): the Buff and Debuff Manager settings are shared by both.
-- Returns the control and its segment buttons by key.
function mod.BM_BuildPreviewStyleToggle(hostFrame)
    local seg, _, _, btnOf = CludesUI.BuildSegmentedControl({
        parent = hostFrame,
        keys = { "raid", "party" },
        labels = { raid = "Raid", party = "Party" },
        autoWidth = true,
        square = true,
        height = 22,
        getChecked = function(keyName)
            return (keyName == "party") == mod.BM_PreviewIsParty()
        end,
        -- An override editing session whose contexts show one kind of frames
        -- pins the preview to that side; the other segment greys out.
        isDisabled = function(keyName)
            local pinned = mod.BM_PreviewPinnedSide()
            return pinned ~= nil and keyName ~= pinned
        end,
        disabledTip = function()
            local label = CludesUI.SpecOverrides_EditSessionName() or "?"
            if mod.BM_PreviewPinnedSide() == "party" then
                return CludesUI.Lf("Editing %s: it applies to party frames only.", label)
            end
            return CludesUI.Lf("Editing %s: it applies to raid frames only.", label)
        end,
        onToggle = function(keyName)
            if mod.BM_PreviewPinnedSide() then
                return
            end
            local party = (keyName == "party")
            if party == (mod._bmPvParty == true) then
                return
            end
            mod._bmPvParty = party
            CludesUI:RefreshPage(true)
        end,
    })
    return seg, btnOf
end

-------------------------------------------------------------------------------
--  Override list for the manager sidebars (Buff Manager here, Debuff Manager
--  in CUI_RaidFrames_ManagerPages.lua): tile rows for the override groups that
--  own a fork, under a PAB-style header. The live fork gets the accent strip
--  and a gold dot. Tile click = editing-as toggle, pencil = edit the group
--  (both card parity). kind = "bm" | "dm"; returns the new y cursor.
-------------------------------------------------------------------------------
-- Both manager pages list override groups: the overrides core rebuilds them
-- after a group is renamed, re-specced or deleted. Merged into any existing entry.
do
    local reg = CludesUI.SpecOverrides_GroupListingPages
    local pages = reg.CludesUIRaidFrames or {}
    pages["Buff Manager"], pages["Debuff Manager"] = true, true
    reg.CludesUIRaidFrames = pages
end

function mod.BM_BuildOverrideList(hostFrame, posY, width, fontFile, kind)
    local specGids, condGids = CludesUI.SpecOverrides_ManagerForkOwners(kind)
    if #specGids + #condGids == 0 then
        return posY
    end
    -- The fork live on this page (session-applied conditional first).
    local lockInfo = (kind == "dm") and CludesUI.SpecOverrides_DmPageLockInfo
        or CludesUI.SpecOverrides_BmPageLockInfo
    local liveKind, liveGid = lockInfo()
    local ovList = {}
    for idx = 1, #specGids do
        local g = CludesUI.SpecOverrides_GroupById(specGids[idx])
        if g then
            ovList[#ovList + 1] = {
                kind = "spec",
                gid = g.id,
                name = g.name or "?",
                icon = g.icon,
                active = liveKind == "spec" and liveGid == g.id,
            }
        end
    end
    for idx = 1, #condGids do
        local g = CludesUI.Conditions_GroupById(condGids[idx])
        if g then
            ovList[#ovList + 1] = {
                kind = "cond",
                gid = g.id,
                name = g.name or "?",
                icon = g.icon,
                active = liveKind == "cond" and liveGid == g.id,
            }
        end
    end
    if #ovList == 0 then
        return posY
    end
    local Pix = CludesUI.PanelPP

    -- PAB section header: inset divider, centered caps label.
    local hdrLine = hostFrame:CreateTexture(nil, "ARTWORK")
    Pix.Height(hdrLine, 1)
    Pix.Point(hdrLine, "TOPLEFT", hostFrame, "TOPLEFT", 8, posY)
    Pix.Point(hdrLine, "TOPRIGHT", hostFrame, "TOPLEFT", width - 8, posY)
    hdrLine:SetColorTexture(1, 1, 1, 0.08)
    local heading = hostFrame:CreateFontString(nil, "OVERLAY")
    heading:SetFont(fontFile, 11, "")
    Pix.Point(heading, "TOP", hostFrame, "TOPLEFT", floor(width / 2), posY - 13)
    heading:SetTextColor(0.6, 0.6, 0.6)
    -- Caps like the PAB headers; string.upper is ASCII-only, so a translation
    -- with non-ASCII letters keeps its own case instead of mixing.
    local hdrText = CludesUI.L("Overrides")
    if not hdrText:find("[\128-\255]") then
        hdrText = string.upper(hdrText)
    end
    heading:SetText(hdrText)
    posY = posY - 32

    -- Rows are the shared manager tiles at the Player Aura Bars metrics (58px,
    -- 14px pencil); the live fork is the selected tile with a gold dot.
    -- Tile click = editing-as toggle, pencil = edit the group (card parity).
    local applyIcon = CludesUI.SpecOverrides_ApplyGroupIcon
    local goldColor = CludesUI._SPECOV_GOLD
    for idx = 1, #ovList do
        local shade = ovList[idx]
        local tileH = CludesUI.BuildManagerTile(hostFrame, posY, {
            width = width,
            fontPath = fontFile,
            height = 58,
            textRight = -28,
            editSize = 14,
            editSnap = true,
            title = shade.name,
            subtitle = CludesUI.L(shade.kind == "spec" and "Spec" or "Conditional"),
            iconApply = function(tex)
                applyIcon(tex, shade.icon)
            end,
            selected = shade.active,
            statusDot = shade.active and goldColor or nil,
            onSelect = function()
                CludesUI.SpecOverrides_ToggleOverrideEdit(shade.kind, shade.gid)
            end,
            onEdit = function()
                CludesUI.SpecOverrides_EditOverrideGroup(shade.kind, shade.gid)
            end,
        })
        posY = posY - tileH
    end
    return posY - 8
end

function mod.BM_BuildPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    if not W then
        return 0
    end
    local saved = mod.db
    if not saved then
        return 0
    end
    -- Options page pool (CludesUI_FramePool.lua): everything below builds on
    -- the page's kept root, so the next render hands the same frames out again
    -- (in creation order) instead of making new ones.
    local CreateFrame = POOL.CreateFrame
    -- Override-session gate: heals a stale BM layer FIRST (renders the edited group's fork) and reports the end overlay; nil = normal WYSIWYG.
    local bmOverlayState = CludesUI.SpecOverrides_BmPagePrelude() or nil
    local Pix = CludesUI.PanelPP

    -- Auto-detect spec on first open
    if not selectedSpecKey then
        selectedSpecKey = AutoDetectSpec()
    end

    -- Light update: rebuild lookup + refresh frames/preview, no page rebuild (sliders/settings that don't change structure).
    local function ReloadAndUpdate()
        RebuildLookup(saved)
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
        local pv = mod._bmPreviewFrame
        if pv and pv._health and mod.BM_ApplyPreviewIndicators then
            mod.BM_ApplyPreviewIndicators(pv, 1, saved.profile)
        end
    end
    -- The Assigned Buffs filter picks (the manager-pages file) update the
    -- frames and preview in place through this.
    mod._bmReloadAndUpdate = ReloadAndUpdate

    -- Full update: also rebuilds the page (preview, sidebar, settings) -- used by create/delete/toggle/dropdown changes that alter structure.
    local function ReloadAndRebuild()
        RebuildLookup(saved)
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
        CludesUI:RefreshPage(true)
    end

    local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local _, hgt
    local PAD = 20 -- consistent left/right padding for creation bar + settings
    local s = saved.profile

    -- Current spec's indicators for the sidebar. v2: editing dropdown stays functional (healer specs + shared Non-Healer bucket); defaults to current spec on first page open each session.
    if mod.BM2_SpecKey and not mod._bm2SpecInited then
        mod._bm2SpecInited = true
        -- WoW Forever lands on All Specs (see ns.BM_EnterAllSpecs).
        local landKey = CludesUI.IS_FOREVER and "allspecs" or mod.BM2_SpecKey()
        -- Non-healers land on their CONCRETE "spec<ID>" view, not the shared
        -- All Non Healers/Aug group: the concrete view is where inherited
        -- group tiles (All Specs / Non Healers / role) are visible, so the
        -- player sees everything their spec actually renders. The shared
        -- bucket stays one dropdown pick away.
        if landKey == "nonhealer" then
            local specIdx = GetSpecialization and GetSpecialization()
            local spellRef = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
            if spellRef then
                landKey = "spec" .. spellRef
            end
        end
        selectedSpecKey = landKey
    end
    -- WoW Forever lists All Specs and one row per class, keyed to the bucket
    -- that class renders now: a class view follows it (the player's class
    -- moves with a live spec override's Buff Manager fork).
    if CludesUI.IS_FOREVER and mod.BM2_ForeverKey and selectedSpecKey ~= "allspecs" then
        local cls = SelectedBucketClass()
        local keyName = cls and mod.BM2_ForeverKey(cls)
        if keyName and keyName ~= selectedSpecKey then
            selectedSpecKey = keyName
            pickedIndicator = nil
            mod._bm2InhSel = nil
        end
    end
    local specIndicators = selectedSpecKey and GetSpecIndicators(saved, selectedSpecKey) or {}

    -- Group buckets this view INHERITS from (concrete spec views only):
    -- their indicators lead the sidebar as read-only tiles with a per-spec
    -- enable. nil on group-bucket views.
    local inheritedGroups = mod.BM_InheritedGroupsFor and mod.BM_InheritedGroupsFor(selectedSpecKey) or nil

    -- Inherited-tile selection (ns._bm2InhSel = { group, id }): resolve it
    -- against the owning group's store; drop it when the view no longer
    -- inherits that group or the indicator is gone. While valid it OWNS the
    -- left pane (read-only), so the indicator selection clears.
    local inhSelInd = nil
    if mod._bm2InhSel then
        local isel = mod._bm2InhSel
        for gi = 1, #(inheritedGroups or {}) do
            if inheritedGroups[gi] == isel.group then
                for _, gind in ipairs(GetSpecIndicators(saved, isel.group) or {}) do
                    if gind.id == isel.id then
                        inhSelInd = gind
                        break
                    end
                end
                break
            end
        end
        if not inhSelInd then
            mod._bm2InhSel = nil
        end
    end
    if inhSelInd then
        pickedIndicator = nil
    end

    -- Validate selected indicator
    if not inhSelInd then
        if not pickedIndicator and #specIndicators > 0 then
            pickedIndicator = specIndicators[1]
        end
        if pickedIndicator then
            local found = false
            for _, indicator in ipairs(specIndicators) do
                if indicator.id == pickedIndicator.id then
                    found = true
                    break
                end
            end
            if not found then
                pickedIndicator = specIndicators[1] or nil
            end
        end
    end

    -- Expose selected spec + indicator ID for preview logic. An inherited
    -- selection exposes its DISPLAY id (group offset applied) so the preview
    -- highlight finds the unioned copy.
    mod._bmSelectedSpecKey = selectedSpecKey
    if inhSelInd then
        mod._bmSelectedIndId = mod._bm2InhSel.id + (mod.BM_INH_OFFSETS[mod._bm2InhSel.group] or 0)
    else
        mod._bmSelectedIndId = pickedIndicator and pickedIndicator.id or nil
    end

    -- Editing-spec roster lead (CludesUI.BuildSpecBucketRoster): the
    -- healer/Aug specs and a divider between the group buckets and every
    -- other spec in the game. Standard spec icons throughout.
    local function HealerRosterLead(values, sequence, icons)
        local inHealerList = {}
        for idx = 1, #SPEC_DD_ORDER do
            local keyName = SPEC_DD_ORDER[idx]
            values[keyName] = CludesUI.L(SPEC_DD_VALUES[keyName])
            sequence[#sequence + 1] = keyName
            local hs = SPEC_BY_KEY[keyName]
            if hs and hs.specID then
                inHealerList[hs.specID] = true
                if GetSpecializationInfoByID then
                    local _, _, _, sIcon = GetSpecializationInfoByID(hs.specID)
                    icons[keyName] = sIcon
                end
            end
        end
        sequence[#sequence + 1] = "---b"
        return inHealerList
    end

    -------------------------------------------------------------------
    --  FIXED LAYOUT: fills visible area, no outer scroll.
    --  Left column (72%): creation + preview (fixed) + settings (scroll)
    --  Right sidebar (28%): full height, own scroll, dark background
    -------------------------------------------------------------------
    -- Build on the scroll frame (not the scroll child) so content is fixed and non-scrollable; no outer scrollbar.
    local scrollFrame = CludesUI._scrollFrame
    if not scrollFrame then
        return 0
    end

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28)
    local leftW = parentW - sidebarW

    -- The refreshers this render registers replace the previous render's (it
    -- may run outside a page pass: the deferred renders of a cache restore).
    CludesUI._BeginRootRender("rf.bm")
    -- Outer container: parented to scrollFrame, fills entire viewport. One
    -- for the session (the options page pool): every render dresses it again,
    -- and its reset is the previous render's teardown.
    local outerRoot = POOL.Kept(mod, "bmRoot", "Frame", scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)

    -- Store reference so we can clean up on page switch
    if mod._addNewPopup then
        mod._addNewPopup:Hide()
    end
    if CludesUI._pickMenu then
        CludesUI._pickMenu:Hide()
    end
    mod._bmRoot = outerRoot

    -- Override-session full-page overlay (state from the prelude above).
    -- "activate" offers to fork a custom Buff Manager for the edited override
    -- group; "info" explains why editing is blocked (edits would land in
    -- whatever layer is actually live and bank to the wrong owner at the next
    -- harvest). Built BEFORE page content since the Simple Setup branch returns
    -- early and must still be covered; high frame level, child of outerRoot so every teardown path destroys it.
    if bmOverlayState then
        local st = bmOverlayState
        local shade, btn = CludesUI.BuildActivationOverlay(outerRoot, {
            fontPath = fontFile,
            width = parentW,
            title = CludesUI.L("Custom Buff Manager"),
            text = st.text,
            sub = st.sub,
            buttonLabel = st.mode == "activate" and CludesUI.L("Activate Custom Buff Manager") or nil,
        })
        if btn then
            -- Create popup: pick what the new Buff Manager starts from (main
            -- copy, another override's copy, or a preset), then Create. Child of
            -- the overlay so every page teardown destroys it with the overlay.
            local createPopup
            local chosen = "main"
            btn:SetScript("OnClick", function(self)
                if createPopup and createPopup:IsShown() then
                    createPopup:Hide()
                    return
                end
                if
                    not (
                        CludesUI.SpecOverrides_ActivateBm
                        and CludesUI.SpecOverrides_BmSeedSources
                        and CludesUI.BuildDropdownControl
                    )
                then
                    CludesUI.SpecOverrides_ActivateBm(st.kind, st.gid)
                    return
                end
                local values, sequence = CludesUI.SpecOverrides_BmSeedSources(st.kind, st.gid)
                chosen = "main"
                if not createPopup then
                    local POPUP_W, POPUP_PAD, ROW_H, LABEL_H = 260, 10, 30, 14
                    local LBL_GAP, DD_GAP = 4, 11
                    local dialog = CreateFrame("Frame", nil, shade)
                    dialog:Hide() -- start hidden so Show() triggers OnShow
                    dialog:SetFrameStrata("DIALOG")
                    dialog:SetFrameLevel(shade:GetFrameLevel() + 20)
                    dialog:SetSize(
                        POPUP_W,
                        POPUP_PAD + LABEL_H + LBL_GAP + ROW_H + DD_GAP + ROW_H + POPUP_PAD
                    )
                    dialog:EnableMouse(true)
                    dialog:SetClampedToScreen(true)
                    local pbg = dialog:CreateTexture(nil, "BACKGROUND")
                    pbg:SetAllPoints()
                    pbg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                    CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, pbg)
                    -- Click-away close (not while the dropdown's own menu is open).
                    dialog:SetScript("OnShow", function(p2)
                        p2:SetScript("OnUpdate", function(m)
                            if not self:IsMouseOver() and not m:IsMouseOver() then
                                local dropdown = m._srcDD
                                if
                                    dropdown
                                    and dropdown._ddMenu
                                    and dropdown._ddMenu:IsShown()
                                    and dropdown._ddMenu:IsMouseOver()
                                then
                                    return
                                end
                                if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                    m:Hide()
                                end
                            end
                        end)
                    end)
                    dialog:SetScript("OnHide", function(p2)
                        p2:SetScript("OnUpdate", nil)
                    end)
                    local ddW = POPUP_W - POPUP_PAD * 2
                    local paneY = -POPUP_PAD
                    local srcLbl = dialog:CreateFontString(nil, "OVERLAY")
                    srcLbl:SetFont(fontFile, 11, "")
                    srcLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                    srcLbl:SetText(CludesUI.L("Start From"))
                    srcLbl:SetTextColor(1, 1, 1, 0.6)
                    paneY = paneY - LABEL_H - LBL_GAP
                    dialog._srcValues, dialog._srcOrder = values, sequence
                    local srcDD = CludesUI.BuildDropdownControl(
                        dialog,
                        ddW,
                        dialog:GetFrameLevel() + 2,
                        dialog._srcValues,
                        dialog._srcOrder,
                        function()
                            return chosen
                        end,
                        function(v)
                            chosen = v
                        end
                    )
                    srcDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                    dialog._srcDD = srcDD
                    paneY = paneY - ROW_H - DD_GAP
                    local ac = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
                    local cBtn = CreateFrame("Button", nil, dialog)
                    cBtn:SetSize(ddW, ROW_H)
                    cBtn:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                    cBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
                    local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints()
                    cBg:SetColorTexture(ac.r, ac.g, ac.b, 0.8)
                    CludesUI.RoundBody(cBtn, cBg)
                    local cLbl = cBtn:CreateFontString(nil, "OVERLAY")
                    CludesUI.PrimeFontShadow(cLbl, true)
                    cLbl:SetFont(fontFile, 12, "")
                    cLbl:SetPoint("CENTER")
                    cLbl:SetText(CludesUI.L("Create Custom Buff Manager"))
                    cLbl:SetTextColor(1, 1, 1)
                    cBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
                    CludesUI.OutlineButton(cBtn, cBg, true)
                    cBtn:SetScript("OnClick", function()
                        dialog:Hide()
                        CludesUI.SpecOverrides_ActivateBm(st.kind, st.gid, chosen)
                    end)
                    createPopup = dialog
                else
                    -- Refresh the source list in place (other overrides may have
                    -- gained or lost a Buff Manager since the popup was built).
                    wipe(createPopup._srcValues)
                    wipe(createPopup._srcOrder)
                    for k, v in pairs(values) do
                        createPopup._srcValues[k] = v
                    end
                    for idx = 1, #sequence do
                        createPopup._srcOrder[idx] = sequence[idx]
                    end
                    local dropdown = createPopup._srcDD
                    if dropdown._invalidateMenu then
                        dropdown._invalidateMenu()
                    end
                    if dropdown._refreshLabel then
                        dropdown._refreshLabel()
                    end
                end
                createPopup:ClearAllPoints()
                createPopup:SetPoint("TOP", self, "BOTTOM", 0, -6)
                createPopup:Show()
            end)
        end
    end

    local HEADER_H = 0

    -- Custom Buff Display: the full buff manager builds into the content area below the header; existing layout below uses `root` + `visibleH`.
    local rootFrame = CreateFrame("Frame", nil, outerRoot)
    rootFrame:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
    rootFrame:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    rootFrame:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH - HEADER_H

    -------------------------------------------------------------------
    --  RIGHT SIDEBAR (full visible height, own scroll, dark bg)
    -------------------------------------------------------------------
    local sidebarOuter = CreateFrame("Frame", nil, rootFrame)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(rootFrame:GetFrameLevel() + 1)

    -- Background on the outer container (renders behind the scroll frame and its child)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)
    CludesUI.CardSidebar(sidebarOuter, sbBg)

    -- Sidebar scroll frame
    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
    sidebarScroll:SetAllPoints()
    sidebarScroll:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)

    local sidebarChild = CreateFrame("Frame", nil, sidebarScroll)
    sidebarChild:SetWidth(sidebarW)
    sidebarScroll:SetScrollChild(sidebarChild)

    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel", function(self, delta)
        local scroll = self:GetVerticalScroll()
        local maxS = max(0, sidebarChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(maxS, scroll - delta * 30)))
    end)

    local sidebarFrame = sidebarChild -- alias for tile building code below

    local tileY = 0

    -------------------------------------------------------------------
    --  INHERITED group indicators lead concrete spec views: read-only
    --  here (edit them in their group), marked by a blue edge strip +
    --  blue group-name subtitle; the pill toggles ONLY the per-spec
    --  disable (BM2_SetInhDisabled) -- other specs are never affected.
    -------------------------------------------------------------------
    if inheritedGroups then
        for gi = 1, #inheritedGroups do
            local gkey = inheritedGroups[gi]
            local ginfo = mod.BM_GROUP_BUCKET_INFO[gkey]
            local gname = ginfo and CludesUI.L(ginfo.name) or gkey
            for _, gind in ipairs(GetSpecIndicators(saved, gkey) or {}) do
                local gSpells = mod.BM2_ResolveSpells and mod.BM2_ResolveSpells(gind) or gind.spells
                local face = 136243
                if gSpells and #gSpells > 0 then
                    face = GetSpellIcon(
                        (mod.BM2_PreferredSpell and mod.BM2_PreferredSpell(gind, SelectedBucketClass()))
                            or gSpells[1]
                    )
                end
                local gTypeInfo = INDICATOR_TYPE_MAP[gind.type]
                local gTypeName = gTypeInfo and gTypeInfo.name or gind.type
                local posText
                if gTypeInfo and gTypeInfo.placed and gind.position then
                    posText = "(" .. CludesUI.L(POSITION_VALUES[gind.position] or gind.position) .. ")"
                end
                -- Pill: the PER-SPEC enable ONLY; a group-level disable dims
                -- the tile instead (the control can never look dead).
                tileY = tileY
                    - CludesUI.BuildManagerTile(sidebarFrame, tileY, {
                        width = sidebarW,
                        fontPath = fontFile,
                        icon = face,
                        title = gind.name and CludesUI.L(gind.name) or CludesUI.L(gTypeName),
                        titleUnclamped = true,
                        posText = posText,
                        subtitle = gname,
                        inheritedTooltip = CludesUI.Lf("Inherited from %1$s. Editable only there.", gname),
                        selected = mod._bm2InhSel
                            and mod._bm2InhSel.group == gkey
                            and mod._bm2InhSel.id == gind.id,
                        dimmed = not gind.enabled,
                        enabled = not mod.BM2_InhDisabled(selectedSpecKey, gkey, gind.id),
                        showToggle = true,
                        onSelect = function()
                            pickedIndicator = nil
                            mod._bm2InhSel = { group = gkey, id = gind.id }
                            CludesUI:RefreshPage(true)
                        end,
                        onToggle = function()
                            mod.BM2_SetInhDisabled(
                                selectedSpecKey,
                                gkey,
                                gind.id,
                                not mod.BM2_InhDisabled(selectedSpecKey, gkey, gind.id)
                            )
                            RebuildLookup(saved)
                            if mod.ReloadFrames then
                                mod.ReloadFrames()
                            end
                            CludesUI:RefreshPage(true)
                        end,
                    })
            end
        end
    end
    -- v2: tiles render the RESOLVED spell union (assigned filters + direct
    -- spells) -- the raw list is empty for filter-driven groups. The face
    -- prefers a spell the EDITED bucket's spec/class actually uses (known
    -- spell > class-tagged > all-class). Returns face, subtitle.
    local function TileFaceSub(indicator)
        local tileSpells = indicator.spells
        if mod.BM2_ResolveSpells then
            tileSpells = mod.BM2_ResolveSpells(indicator)
        end
        if not (tileSpells and #tileSpells > 0) then
            return 136243, CludesUI.L("(no spells)")
        end
        local nameList = {}
        for _, spellRef in ipairs(tileSpells) do
            nameList[#nameList + 1] = SPELL_NAME_BY_ID[spellRef]
                or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef))
                or tostring(spellRef)
        end
        return GetSpellIcon(
            (mod.BM2_PreferredSpell and mod.BM2_PreferredSpell(indicator, SelectedBucketClass())) or tileSpells[1]
        ),
            table.concat(nameList, ", ")
    end
    for _, indicator in ipairs(specIndicators) do
        -- The selected indicator's filters are edited live in the settings
        -- column, so its tile re-reads face and subtitle on every widget refresh.
        local isSel = pickedIndicator and pickedIndicator.id == indicator.id
        local face, subtitle = TileFaceSub(indicator)

        local typeInfo2 = INDICATOR_TYPE_MAP[indicator.type]
        local typeName = typeInfo2 and typeInfo2.name or indicator.type
        local posText
        if typeInfo2 and typeInfo2.placed and indicator.position then
            posText = "(" .. CludesUI.L(POSITION_VALUES[indicator.position] or indicator.position) .. ")"
        end

        local tileH, tile = CludesUI.BuildManagerTile(sidebarFrame, tileY, {
            width = sidebarW,
            fontPath = fontFile,
            icon = face,
            iconFn = isSel and function()
                return (TileFaceSub(indicator))
            end or nil,
            -- v2: named indicators (the seeded filter groups) show their name.
            title = indicator.name and CludesUI.L(indicator.name) or CludesUI.L(typeName),
            titleUnclamped = true,
            posText = posText,
            subtitle = subtitle,
            subtitleFn = isSel and function()
                return select(2, TileFaceSub(indicator))
            end or nil,
            selected = isSel,
            enabled = indicator.enabled,
            showToggle = true,
            onSelect = function()
                mod._bm2InhSel = nil
                pickedIndicator = indicator
                CludesUI:RefreshPage(true)
            end,
            -- Right-click: "Add To" context menu -- copies this indicator into
            -- another editing-spec bucket (full clone, fresh id; source stays).
            onContext = function(tileFrame)
                if not CludesUI.ShowPickMenu then
                    return
                end
                CludesUI.ShowPickMenu(tileFrame, {
                    title = CludesUI.L("Add To"),
                    fontPath = fontFile,
                    items = CludesUI.SpecBucketMenuItems(
                        selectedSpecKey,
                        HealerRosterLead,
                        mod.BM2_ForeverKey
                    ),
                    onPick = function(keyName)
                        -- Target cap: silently blocked at the limit (house
                        -- silent-correction pattern; CountSpecIndicators
                        -- seeds only the picked bucket).
                        if CountSpecIndicators(saved, keyName) >= MAX_PER_SPEC then
                            return
                        end
                        if mod.BM2_CopyIndicator and mod.BM2_CopyIndicator(indicator, keyName) then
                            RebuildLookup(saved)
                            if mod.ReloadFrames then
                                mod.ReloadFrames()
                            end
                            CludesUI:RefreshPage(true)
                        end
                    end,
                })
            end,
            onToggle = function()
                indicator.enabled = not indicator.enabled
                RebuildLookup(saved)
                if mod.ReloadFrames then
                    mod.ReloadFrames()
                end
                CludesUI:RefreshPage(true)
            end,
            onDelete = function()
                local spellName = indicator.spells
                        and #indicator.spells > 0
                        and (SPELL_NAME_BY_ID[indicator.spells[1]] or tostring(indicator.spells[1]))
                    or "this indicator"
                CludesUI:ShowConfirmPopup({
                    title = "Delete Indicator",
                    message = "Are you sure you want to delete the indicator for " .. spellName .. "?",
                    confirmText = "Delete",
                    cancelText = "Cancel",
                    onConfirm = function()
                        local entries = GetSpecIndicators(saved, selectedSpecKey)
                        for idx = #entries, 1, -1 do
                            if entries[idx].id == indicator.id then
                                tremove(entries, idx)
                                break
                            end
                        end
                        if pickedIndicator and pickedIndicator.id == indicator.id then
                            pickedIndicator = nil
                        end
                        -- Deleting a GROUP indicator sweeps its per-spec disable
                        -- keys from every concrete bucket (stale keys are inert
                        -- but would leak forever).
                        if
                            mod.BM2_SweepInhDis
                            and mod.BM_GROUP_BUCKET_INFO
                            and mod.BM_GROUP_BUCKET_INFO[selectedSpecKey]
                        then
                            mod.BM2_SweepInhDis(selectedSpecKey, indicator.id)
                        end
                        RebuildLookup(saved)
                        if mod.ReloadFrames then
                            mod.ReloadFrames()
                        end
                        CludesUI:RefreshPage(true)
                    end,
                })
            end,
            -- Rename: the name is display-only, so a rename never touches
            -- spells/signature -- page refresh suffices.
            editTooltip = CludesUI.L("Rename Indicator"),
            onEdit = function()
                local current = indicator.name or typeName
                CludesUI:ShowInputPopup({
                    title = CludesUI.L("Rename Indicator"),
                    message = CludesUI.L("Enter a new name for this indicator:"),
                    placeholder = current,
                    confirmText = CludesUI.L("Rename"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function(textValue)
                        textValue = textValue and textValue:gsub("^%s+", ""):gsub("%s+$", "") or ""
                        -- Empty reverts to the type-name default.
                        indicator.name = (textValue ~= "") and textValue or nil
                        CludesUI:RefreshPage(true)
                    end,
                })
            end,
        })

        -- Frame Alpha is removed: the notice covers the tile body but leaves the right controls usable so it can still be toggled off or deleted.
        if indicator.type == "framealpha" then
            local shade = BuildPTROverlay(tile, "Frame Alpha", 10)
            shade:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
            shade:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -52, 1)
        end

        tileY = tileY - tileH
    end

    -------------------------------------------------------------------
    --  Empty-override hint: an override Buff Manager shows ONLY what it
    --  contains, so a spec with no indicators in it renders nothing. Say so
    --  in place of the blank tile list (fork live on this page only).
    -------------------------------------------------------------------
    if #specIndicators == 0 and CludesUI.SpecOverrides_BmActiveInfo() then
        local inhCount = 0
        if inheritedGroups then
            for gi = 1, #inheritedGroups do
                inhCount = inhCount + #(GetSpecIndicators(saved, inheritedGroups[gi]) or {})
            end
        end
        if inhCount == 0 then
            local hintText = sidebarFrame:CreateFontString(nil, "OVERLAY")
            hintText:SetFont(fontFile, 11, "")
            hintText:SetPoint("TOP", sidebarFrame, "TOPLEFT", floor(sidebarW / 2), tileY - 8)
            hintText:SetWidth(sidebarW - 24)
            hintText:SetJustifyH("CENTER")
            hintText:SetWordWrap(true)
            hintText:SetTextColor(1, 0.75, 0.35, 0.9)
            hintText:SetText(
                CludesUI.L(
                    "This override has no indicators for this spec, so nothing shows here until you add some."
                )
            )
            tileY = tileY - hintText:GetStringHeight() - 16
        end
    end

    -------------------------------------------------------------------
    --  "Add New" button at bottom of sidebar tiles
    -------------------------------------------------------------------
    local ADD_BTN_H = 30
    local ADD_BTN_PAD = 10 -- vertical padding above button
    do
        local btnW = floor(sidebarW * 0.6)
        local addBtn = CreateFrame("Button", nil, sidebarFrame)
        addBtn:SetSize(btnW, ADD_BTN_H)
        addBtn:SetPoint("TOP", sidebarFrame, "TOPLEFT", floor(sidebarW / 2), tileY - ADD_BTN_PAD)
        addBtn:SetFrameLevel(sidebarFrame:GetFrameLevel() + 1)

        local accentColor = CludesUI.CLUDES_GREEN
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        CludesUI.RoundBody(addBtn, addBg)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY")
        -- Drop shadow via the shadow FontObject, primed BEFORE SetFont (SetShadowOffset alone does not render).
        CludesUI.PrimeFontShadow(addLabel, true)
        addLabel:SetFont(fontFile, 12, "")
        addLabel:SetPoint("CENTER")
        addLabel:SetText(CludesUI.L("Add New"))
        addLabel:SetTextColor(1, 1, 1)

        addBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
        CludesUI.OutlineButton(addBtn, addBg, true)

        addBtn:SetScript("OnClick", function(self)
            -- Toggle popup
            local dialog = mod._addNewPopup
            if dialog and dialog:IsShown() then
                dialog:Hide()
                return
            end

            if not selectedSpecKey then
                return
            end

            -- Relabel the Filters and Extra Spells dropdowns (OnHide wiped the picks)
            if dialog and dialog._refreshDDs then
                dialog._refreshDDs()
            end

            if not dialog then
                local POPUP_W = 220
                local POPUP_PAD = 10
                local ROW_H = 30
                local LABEL_H = 14
                local GAP = 6

                dialog = CreateFrame("Frame", nil, UIParent)
                dialog:Hide() -- start hidden so Show() triggers OnShow
                dialog:SetFrameStrata("DIALOG")
                dialog:SetFrameLevel(200)
                local LBL_GAP = 4 -- label to dropdown
                local DD_GAP = 11 -- dropdown to next label/button
                -- Three label+dropdown pairs: Indicator, Filters, Extra Spells.
                dialog:SetSize(
                    POPUP_W,
                    POPUP_PAD + 3 * (LABEL_H + LBL_GAP + ROW_H + DD_GAP) + ROW_H + POPUP_PAD
                )
                dialog:EnableMouse(true)
                dialog:SetClampedToScreen(true)

                local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, backdrop)

                -- Auto-close when clicking outside (but not on child dropdown menus)
                dialog:SetScript("OnShow", function(p)
                    p:SetScript("OnUpdate", function(m)
                        if not self:IsMouseOver() and not m:IsMouseOver() then
                            local indDD2 = m._indDD
                            if
                                indDD2
                                and indDD2._ddMenu
                                and indDD2._ddMenu:IsShown()
                                and indDD2._ddMenu:IsMouseOver()
                            then
                                return
                            end
                            local fltDD2 = m._fltDD
                            if
                                fltDD2
                                and fltDD2._ddMenu
                                and fltDD2._ddMenu:IsShown()
                                and fltDD2._ddMenu:IsMouseOver()
                            then
                                return
                            end
                            local exDD2 = m._exDD
                            if
                                exDD2
                                and exDD2._ddMenu
                                and exDD2._ddMenu:IsShown()
                                and exDD2._ddMenu:IsMouseOver()
                            then
                                return
                            end
                            -- Modal children own the mouse: the Custom Spell ID
                            -- input and the Filter Editor open from these.
                            local ip = _G.CUIInputPopup
                            if ip and ip:IsShown() then
                                return
                            end
                            if mod._bm2FilterEditor then
                                return
                            end
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                m:Hide()
                            end
                        end
                    end)
                end)
                dialog:SetScript("OnHide", function(p)
                    p:SetScript("OnUpdate", nil)
                    -- Clear spell selections so reopening starts fresh
                    if p._v2Filters then
                        wipe(p._v2Filters)
                    end
                    if p._v2NegFilters then
                        wipe(p._v2NegFilters)
                    end
                    if p._v2Extras then
                        wipe(p._v2Extras)
                    end
                    if p._v2Exact then
                        wipe(p._v2Exact)
                    end
                end)

                local paneY = -POPUP_PAD
                local ddW = POPUP_W - POPUP_PAD * 2

                -- v2 creation flow: Indicator type, then the SAME Filters and
                -- Extra Spells dropdowns as Assigned Buffs; picks apply to the new indicator on Create.
                dialog._v2Filters = {}
                dialog._v2NegFilters = {}
                dialog._v2Extras = {}
                -- Extras typed through Custom Spell ID: tracked as that aura alone.
                dialog._v2Exact = {}

                local indLbl2 = dialog:CreateFontString(nil, "OVERLAY")
                indLbl2:SetFont(fontFile, 11, "")
                indLbl2:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                indLbl2:SetText(CludesUI.L("Indicator"))
                indLbl2:SetTextColor(1, 1, 1, 0.6)
                paneY = paneY - LABEL_H - LBL_GAP

                local indDD = CludesUI.BuildDropdownControl(
                    dialog,
                    ddW,
                    dialog:GetFrameLevel() + 2,
                    INDICATOR_TYPE_VALUES,
                    INDICATOR_TYPE_ORDER,
                    function()
                        return selectedType
                    end,
                    function(v)
                        selectedType = v
                    end
                )
                indDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                dialog._indDD = indDD
                paneY = paneY - ROW_H - DD_GAP

                local fltLbl = dialog:CreateFontString(nil, "OVERLAY")
                fltLbl:SetFont(fontFile, 11, "")
                fltLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                fltLbl:SetText(CludesUI.L("Filters"))
                fltLbl:SetTextColor(1, 1, 1, 0.6)
                paneY = paneY - LABEL_H - LBL_GAP
                local fltDDY = paneY
                paneY = paneY - ROW_H - DD_GAP

                local exLbl = dialog:CreateFontString(nil, "OVERLAY")
                exLbl:SetFont(fontFile, 11, "")
                exLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                exLbl:SetText(CludesUI.L("Extra Spells"))
                exLbl:SetTextColor(1, 1, 1, 0.6)
                paneY = paneY - LABEL_H - LBL_GAP
                local exDDY = paneY
                paneY = paneY - ROW_H - DD_GAP

                -- Built once: both menus re-read their items on every open, so a
                -- reopen only relabels the two dropdowns (OnHide wiped the picks).
                local function BuildV2DDs()
                    if dialog._fltDD then
                        dialog._fltRefresh()
                        dialog._exRefresh()
                        return
                    end

                    -- Dynamic items: fresh per menu open (adds/renames live).
                    -- Two-lane rows: Show picks (popup._v2Filters) and Hide picks
                    -- (popup._v2NegFilters), applied to the new indicator on Create.
                    local function FItems()
                        local filters = (mod.BM2_Filters and mod.BM2_Filters()) or {}
                        local fItems = {
                            {
                                isTopAction = true,
                                label = "Edit Filters",
                                onClick = function()
                                    if mod.BMP_ShowFilterEditor then
                                        mod.BMP_ShowFilterEditor(dialog._v2Filters, dialog._v2NegFilters)
                                    end
                                end,
                            },
                            { isHeader = true, label = "Show", rightLabel = "Hide" },
                        }
                        for idx = 1, #filters do
                            fItems[#fItems + 1] =
                                { key = filters[idx].id, label = filters[idx].name, dual = true }
                        end
                        return fItems
                    end
                    local fltDD, fltRefresh = CludesUI.BuildVisOptsCBDropdown(
                        dialog,
                        ddW,
                        dialog:GetFrameLevel() + 2,
                        FItems,
                        function(k, neg)
                            if neg then
                                return dialog._v2NegFilters[k] and true or false
                            end
                            return dialog._v2Filters[k] and true or false
                        end,
                        function(k, v, neg)
                            if neg then
                                dialog._v2NegFilters[k] = v and true or nil
                                if v then
                                    dialog._v2Filters[k] = nil
                                end
                            else
                                dialog._v2Filters[k] = v and true or nil
                                if v then
                                    dialog._v2NegFilters[k] = nil
                                end
                            end
                        end,
                        nil,
                        12
                    )
                    fltDD:SetSize(ddW, ROW_H)
                    fltDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, fltDDY)
                    dialog._fltDD, dialog._fltRefresh = fltDD, fltRefresh

                    local function SpellEntry(ident)
                        -- Curated name first (distinguishes variants the client
                        -- API can't, e.g. two spell IDs both named "Sense Power"
                        -- by Blizzard); SPELL_NAME_BY_ID already falls back to
                        -- the live API internally when no curated name exists.
                        local label = SPELL_NAME_BY_ID[ident]
                        local labelText = label or ("Spell " .. tostring(ident))
                        -- Truncated rows still need to be told apart on hover.
                        return {
                            key = ident,
                            label = labelText,
                            tooltip = labelText,
                            icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident),
                        }
                    end
                    -- Dynamic items: fresh per menu open. Spells already supplied by
                    -- CHECKED filters are excluded from Presets (redundant as extras); picked extras always show under Selected.
                    local function ByLabel(a, b)
                        return a.label < b.label
                    end
                    -- Custom Spell ID: a typed ID is tracked as that aura alone,
                    -- one already picked from Presets included, and the closed
                    -- dropdown names it at once.
                    local idAction = mod.BM2_SpellIdAction(function(ident)
                        dialog._v2Extras[ident] = true
                        dialog._v2Exact[ident] = true
                        dialog._exRefresh(true)
                    end)
                    local function EItems()
                        -- WoW Forever: a rank alternate stands for its family's
                        -- primary, so Presets offers no second row for that buff.
                        -- nil on every other client.
                        local ap = mod.BM2_ForeverAltPrimary
                        local covered = {}
                        if mod.BM2_GetFilter then
                            for fid in pairs(dialog._v2Filters) do
                                local f = mod.BM2_GetFilter(fid)
                                if f then
                                    for ident, on in pairs(f.spells) do
                                        if on and not mod.BM2_OtherClientSpell(f, ident) then
                                            covered[ident] = true
                                            if ap and ap[ident] then
                                                covered[ap[ident]] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        local universe = (mod.BM2_AllPresetSpells and mod.BM2_AllPresetSpells()) or {}
                        local selList, rest = {}, {}
                        local seen = {}
                        for ident in pairs(dialog._v2Extras) do
                            seen[ident] = true
                            if ap and ap[ident] then
                                seen[ap[ident]] = true
                            end
                            selList[#selList + 1] = SpellEntry(ident)
                        end
                        for idx = 1, #universe do
                            local ident = universe[idx]
                            if not seen[ident] and not covered[ident] then
                                rest[#rest + 1] = SpellEntry(ident)
                            end
                        end
                        table.sort(selList, ByLabel)
                        table.sort(rest, ByLabel)
                        local eItems = { idAction }
                        if #selList > 0 then
                            eItems[#eItems + 1] = { isHeader = true, label = "Selected" }
                            for idx = 1, #selList do
                                eItems[#eItems + 1] = selList[idx]
                            end
                        end
                        eItems[#eItems + 1] = { isHeader = true, label = "Presets" }
                        for idx = 1, #rest do
                            eItems[#eItems + 1] = rest[idx]
                        end
                        return eItems
                    end
                    local exDD, exRefresh = CludesUI.BuildVisOptsCBDropdown(
                        dialog,
                        ddW,
                        dialog:GetFrameLevel() + 2,
                        EItems,
                        function(k)
                            return dialog._v2Extras[k] and true or false
                        end,
                        function(k, v)
                            dialog._v2Extras[k] = v and true or nil
                            if not v then
                                dialog._v2Exact[k] = nil
                            end
                        end,
                        nil,
                        10,
                        true
                    )
                    exDD:SetSize(ddW, ROW_H)
                    exDD:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, exDDY)
                    dialog._exDD, dialog._exRefresh = exDD, exRefresh
                end
                BuildV2DDs()
                dialog._refreshDDs = BuildV2DDs

                -- Create button
                local cBtn = CreateFrame("Button", nil, dialog)
                cBtn:SetSize(ddW, ROW_H)
                cBtn:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, paneY)
                cBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
                local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                cBg:SetAllPoints()
                cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
                CludesUI.RoundBody(cBtn, cBg)
                local cTx = cBtn:CreateFontString(nil, "OVERLAY")
                cTx:SetPoint("CENTER")
                cTx:SetFont(fontFile, 12, "")
                cTx:SetText(CludesUI.L("Create"))
                cTx:SetTextColor(1, 1, 1)
                cBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
                CludesUI.OutlineButton(cBtn, cBg, true)
                cBtn:SetScript("OnClick", function()
                    if not selectedSpecKey then
                        return
                    end
                    if CountSpecIndicators(saved, selectedSpecKey) >= MAX_PER_SPEC then
                        return
                    end
                    -- v2: create through the v2 store (correct id namespace, edited bucket),
                    -- then assign picked filters/extra spells as Assigned Buffs does (incl. presets' own-only default).
                    local newInd = mod.BM2_AddIndicator(selectedType, selectedSpecKey)
                    if newInd then
                        for fid in pairs(dialog._v2Filters or {}) do
                            newInd.filters[fid] = true
                        end
                        if dialog._v2NegFilters and next(dialog._v2NegFilters) then
                            newInd.negFilters = {}
                            for fid in pairs(dialog._v2NegFilters) do
                                newInd.negFilters[fid] = true
                            end
                        end
                        local exList = {}
                        for spellRef in pairs(dialog._v2Extras or {}) do
                            exList[#exList + 1] = spellRef
                        end
                        table.sort(exList)
                        for idx = 1, #exList do
                            newInd.spells[#newInd.spells + 1] = exList[idx]
                            if dialog._v2Exact[exList[idx]] then
                                mod.BM2_SetSpellExact(newInd, exList[idx], true)
                            end
                        end
                        pickedIndicator = newInd
                    end
                    mod._bm2InhSel = nil
                    RebuildLookup(saved)
                    if mod.ReloadFrames then
                        mod.ReloadFrames()
                    end
                    dialog:Hide()
                    CludesUI:RefreshPage(true)
                end)

                mod._addNewPopup = dialog
            end

            -- Position below the Add New button, centered on sidebar
            dialog:ClearAllPoints()
            local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            dialog:SetScale(sc)
            dialog:SetPoint("TOP", self, "BOTTOM", 0, -12)
            dialog:Show()
        end)

        tileY = tileY - ADD_BTN_PAD - ADD_BTN_H - ADD_BTN_PAD
    end

    -- Override list (shared with the Debuff Manager sidebar).
    tileY = mod.BM_BuildOverrideList(sidebarFrame, tileY, sidebarW, fontFile, "bm")

    -------------------------------------------------------------------
    --  LEFT COLUMN (72%): Fixed top area + scrollable settings below
    -------------------------------------------------------------------
    -- Fixed top container (creation row + preview + title)
    local leftPane = CreateFrame("Frame", nil, rootFrame)
    leftPane:SetSize(leftW, 10) -- height set after content
    leftPane:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)

    local layoutY = 0 -- local Y within leftFixed
    local leftFrame = leftPane -- alias, reassigned to scroll child later

    -------------------------------------------------------------------
    --  1. SPEC SELECTOR + PREVIEW (35/65 split)
    --  Left 35%: label, spec dropdown, class icon
    --  Right 65%: centered raid frame replica
    -------------------------------------------------------------------
    -- Class icon sprite sheet (shared by spec dropdown icons + class icon display)
    local CLASS_SPRITE_TEX = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\modern.tga"
    local CLASS_SPRITE_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS
    local SPEC_CLASS_MAP = {}
    for _, specInfo in ipairs(HEALER_SPECS) do
        SPEC_CLASS_MAP[specInfo.key] = specInfo.classToken
    end

    do
        local pvSplitW = floor(leftW * 0.65) -- left 65% for preview
        local specSplitW = leftW - pvSplitW -- right 35% for editing spec

        -- Roster shared with the right-click "Add To" menu (built once per
        -- page build here; the menu rebuilds it lazily per open).
        local specDDValues, specDDOrder, specDDIcons, specDDClass =
            CludesUI.BuildSpecBucketRoster(HealerRosterLead, mod.BM2_ForeverKey)

        ---------------------------------------------------------------
        --  LEFT 65%: Preview frame (centered). Health color class =
        --  selected spec's (per-spec buckets via the roster map), else
        --  player's.
        ---------------------------------------------------------------
        local previewClass
        if selectedSpecKey and SPEC_BY_KEY[selectedSpecKey] then
            previewClass = SPEC_BY_KEY[selectedSpecKey].classToken
        end
        if not previewClass and specDDClass then
            previewClass = specDDClass[selectedSpecKey]
        end
        if not previewClass then
            local _, pc = UnitClass("player")
            previewClass = pc
        end
        local ovRaid, ovParty = mod.BM_PreviewOverrideTips("bm")
        local previewFrame, sectionH, PV_SCALE =
            mod.BM_BuildSimplePreview(leftFrame, s, fontFile, Pix, pvSplitW / 2, layoutY - 20, {
                previewClass = previewClass,
                party = mod.BM_PreviewIsParty(),
                styleToggle = true,
                kitAuras = "buffs",
                overrideTips = { raid = ovRaid, party = ovParty },
            })
        local healthBar = previewFrame._health

        -- Vertical divider between preview and editing spec
        local splitDiv = leftPane:CreateTexture(nil, "ARTWORK")
        splitDiv:SetWidth(1)
        splitDiv:SetPoint("TOP", leftPane, "TOPLEFT", pvSplitW, layoutY - 10)
        splitDiv:SetPoint("BOTTOM", leftPane, "TOPLEFT", pvSplitW, layoutY - sectionH + 10)
        splitDiv:SetColorTexture(1, 1, 1, 0.08)

        ---------------------------------------------------------------
        --  RIGHT 35%: Background class icon + centered label + dropdown
        ---------------------------------------------------------------
        local specCenterX = pvSplitW + specSplitW / 2

        -- Background class icon (covers right section, faded)
        local classIconBg = leftPane:CreateTexture(nil, "BACKGROUND", nil, 1)
        classIconBg:SetTexture(CLASS_SPRITE_TEX)
        local iconSz = sectionH * 0.7 + 10
        classIconBg:SetSize(iconSz, iconSz)
        classIconBg:SetPoint("CENTER", leftPane, "TOPLEFT", specCenterX, layoutY - sectionH / 2)
        classIconBg:SetAlpha(0.10)
        classIconBg:SetDesaturated(true)
        classIconBg:SetDesaturation(0.5)
        local selClass = selectedSpecKey and SPEC_CLASS_MAP[selectedSpecKey]
        -- Per-spec buckets resolve their class through the roster map.
        if not selClass and specDDClass then
            selClass = specDDClass[selectedSpecKey]
        end
        local selCoords = selClass and CLASS_SPRITE_COORDS[selClass]
        local selGroup = selectedSpecKey
            and mod.BM_GROUP_BUCKET_INFO
            and mod.BM_GROUP_BUCKET_INFO[selectedSpecKey]
        if selCoords then
            classIconBg:SetTexCoord(selCoords[1], selCoords[2], selCoords[3], selCoords[4])
        elseif selGroup then
            -- Group buckets wear their roster icon.
            classIconBg:SetTexture(selGroup.icon)
            classIconBg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            classIconBg:Hide()
        end

        -- Label + dropdown vertically centered: 14 + 7 gap + 30 = 51 tall.
        local groupH = 14 + 7 + 30
        local groupTopY = layoutY - (sectionH - groupH) / 2

        local specLabel = leftPane:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontFile, 12, "")
        specLabel:SetPoint("TOP", leftPane, "TOPLEFT", specCenterX, groupTopY)
        specLabel:SetJustifyH("CENTER")
        specLabel:SetText(CludesUI.L("Editing Spec"))
        specLabel:SetTextColor(1, 1, 1, 0.75)

        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(keyName)
                -- Standard spec icons; group buckets wear their roster
                -- icon.
                local g = mod.BM_GROUP_BUCKET_INFO and mod.BM_GROUP_BUCKET_INFO[keyName]
                if g then
                    return g.icon
                end
                local ic = specDDIcons and specDDIcons[keyName]
                if ic then
                    return ic
                end
                local ct = SPEC_CLASS_MAP[keyName]
                local coords = ct and CLASS_SPRITE_COORDS[ct]
                if coords then
                    return CLASS_SPRITE_TEX, coords[1], coords[2], coords[3], coords[4]
                end
            end,
        }

        local specDDW = specSplitW - PAD - 50
        local specDD = CludesUI.BuildDropdownControl(
            leftPane,
            specDDW,
            leftPane:GetFrameLevel() + 2,
            specDDValues,
            specDDOrder,
            function()
                return selectedSpecKey or ""
            end,
            function(v)
                selectedSpecKey = v
                pickedIndicator = nil
                mod._bm2InhSel = nil
                CludesUI:RefreshPage(true)
            end
        )
        specDD:SetPoint("TOP", specLabel, "BOTTOM", 0, -7)

        -- Buff manager indicators on the preview
        if mod.BM_CreatePreviewIndicators then
            mod.BM_CreatePreviewIndicators(previewFrame, healthBar, Pix)
        end
        if mod.BM_ApplyPreviewIndicators then
            mod.BM_ApplyPreviewIndicators(previewFrame, 1, s)
        end

        -- Eyeball toggle: show all indicators at full opacity
        do
            local EYE_VIS = CludesUI.EYE_VISIBLE_ICON
            local EYE_INVIS = CludesUI.EYE_INVISIBLE_ICON
            mod._bmAllIndicatorsVisible = mod._bmAllIndicatorsVisible or false

            local eyeBtn = CreateFrame("Button", nil, leftFrame)
            eyeBtn:SetSize(26, 26)
            -- The kit's buff run beside the frame on the right: the eyeball moves left.
            if previewFrame._bmKitSide == "RIGHT" then
                eyeBtn:SetPoint("RIGHT", previewFrame, "LEFT", -18 / PV_SCALE, 0)
            else
                eyeBtn:SetPoint("LEFT", previewFrame, "RIGHT", 18 / PV_SCALE, 0)
            end
            eyeBtn:SetFrameLevel(leftFrame:GetFrameLevel() + 5)

            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            eyeTex:SetTexture(mod._bmAllIndicatorsVisible and EYE_INVIS or EYE_VIS)
            eyeBtn:SetAlpha(0.4)

            eyeBtn:SetScript("OnClick", function()
                mod._bmAllIndicatorsVisible = not mod._bmAllIndicatorsVisible
                eyeTex:SetTexture(mod._bmAllIndicatorsVisible and EYE_INVIS or EYE_VIS)
                if mod.BM_ApplyPreviewIndicators then
                    mod.BM_ApplyPreviewIndicators(previewFrame, 1, saved.profile)
                end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                CludesUI.ShowWidgetTooltip(self, "Toggle All Indicators")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                CludesUI.HideWidgetTooltip()
            end)
        end

        -- Store reference so ReloadAndUpdate can refresh preview live
        mod._bmPreviewFrame = previewFrame

        -- Small helper subtitle under the preview explaining icon interactions; click
        -- to dismiss permanently (CludesUIDB.bmIconHintDismissed). When dismissed it is not built and the extra 10px gap below collapses to 0.
        if not (CludesUIDB and CludesUIDB.bmIconHintDismissed) then
            -- Clickable button (FontStrings can't take clicks); label is its child.
            local hintBtn = CreateFrame("Button", nil, leftFrame)
            hintBtn:SetPoint("TOP", previewFrame, "BOTTOM", 0, -8)
            local hintFS = hintBtn:CreateFontString(nil, "OVERLAY")
            hintFS:SetFont(fontFile, 11, "")
            hintFS:SetAllPoints(hintBtn)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetWordWrap(false)
            hintFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
            hintFS:SetText(
                CludesUI.L("For Icons: Left click to edit group, Right click to custom size individual")
            )
            hintBtn:SetSize(hintFS:GetStringWidth() + 8, 14)
            hintBtn:SetScript("OnEnter", function()
                hintFS:SetTextColor(1, 1, 1, 0.85)
            end)
            hintBtn:SetScript("OnLeave", function()
                hintFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
            end)
            hintBtn:SetScript("OnClick", function()
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                CludesUIDB.bmIconHintDismissed = true
                CludesUI:RefreshPage(true)
            end)
            -- Extra 10px below the subtitle before the divider/settings.
            layoutY = layoutY - sectionH - 10
        else
            layoutY = layoutY - sectionH
        end
    end

    -------------------------------------------------------------------
    --  DIVIDER (below spec/preview, above settings title)
    -------------------------------------------------------------------
    local div1 = leftPane:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", leftPane, "TOPLEFT", PAD, layoutY)
    div1:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT", -PAD, layoutY)
    div1:SetColorTexture(1, 1, 1, 0.08)

    -------------------------------------------------------------------
    --  LEFT COLUMN: Accent title + settings
    -------------------------------------------------------------------
    layoutY = layoutY - 25 -- 25px spacing above title

    -- Accent-colored title (on fixed area)
    local settingsTitle = leftPane:CreateFontString(nil, "OVERLAY")
    settingsTitle:SetFont(fontFile, 18, "")
    settingsTitle:SetPoint("TOPLEFT", leftPane, "TOPLEFT", PAD, layoutY)
    settingsTitle:SetJustifyH("LEFT")
    settingsTitle:SetWordWrap(false)

    -- Spell names as a separate white 75% opacity font string (inline after title)
    local spellsTitle = leftPane:CreateFontString(nil, "OVERLAY")
    spellsTitle:SetFont(fontFile, 13, "")
    spellsTitle:SetPoint("LEFT", settingsTitle, "RIGHT", 4, 0)
    spellsTitle:SetPoint("RIGHT", leftPane, "RIGHT", -PAD, 0)
    spellsTitle:SetJustifyH("LEFT")
    spellsTitle:SetWordWrap(false)
    spellsTitle:SetTextColor(0.75, 0.75, 0.75, 0.65)

    layoutY = layoutY - 18 - 10 -- title + spacing

    -- Finalize fixed top area height
    local fixedH = math.abs(layoutY)
    leftPane:SetHeight(fixedH)

    -- Settings area below the fixed top. DualRow subtracts CONTENT_PAD*2 from parent
    -- width and offsets by CONTENT_PAD, so to align with our PAD (20px): width = leftW + (CONTENT_PAD - PAD)*2, offset = -(CONTENT_PAD - PAD).
    local contentPad = CludesUI.CONTENT_PAD or 45
    local padDiff = contentPad - PAD
    local viewportH = max(10, visibleH - fixedH)
    local settingsW = leftW + padDiff * 2

    -- Smooth-scrolling viewport (mirrors the main options page): rows build into the
    -- scroll child, sized to content after building. The smooth frame is parented to the scroll frame, so it stops on page rebuild.
    local settingsScroll = CreateFrame("ScrollFrame", nil, rootFrame)
    -- +5 raises the settings panel (CORE section first) 5px into the fixed area's bottom spacing, tightening the gap above CORE for every indicator.
    settingsScroll:SetPoint("TOPLEFT", leftPane, "BOTTOMLEFT", -padDiff, 5)
    settingsScroll:SetSize(settingsW, viewportH)
    settingsScroll:SetFrameLevel(rootFrame:GetFrameLevel() + 1)
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetSize(settingsW, viewportH)
    settingsScroll:SetScrollChild(settingsChild)

    -- Scrollbar: thin track + thumb at the viewport's right edge (shown only on overflow).
    local UpdateThumb = CludesUI.AttachSmoothScrollbar(settingsScroll, {
        step = 60,
        width = 5,
        rightInset = 31,
        topInset = 12,
        level = 20,
        trackAlpha = 0.05,
        thumbAlpha = 0.22,
        child = settingsChild,
        panelWheel = true,
    })

    -- From here, DualRows build inside the scroll child
    leftFrame = settingsChild
    leftFrame._showRowDivider = true
    local sy = 0 -- Y within settings scroll child

    if inhSelInd then
        -------------------------------------------------------------------
        --  Read-only pane for an INHERITED group indicator: explains where
        --  it lives, links to the owning group, and points at the tile
        --  toggle for the per-spec enable. No settings render -- edits
        --  belong to the group.
        -------------------------------------------------------------------
        local indicator = inhSelInd
        local gkey = mod._bm2InhSel.group
        local ginfo = mod.BM_GROUP_BUCKET_INFO[gkey]
        local gname = ginfo and CludesUI.L(ginfo.name) or gkey
        local inhTypeName = INDICATOR_TYPE_MAP[indicator.type] and INDICATOR_TYPE_MAP[indicator.type].name or indicator.type
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(indicator.name and CludesUI.L(indicator.name) or CludesUI.L(inhTypeName .. " Indicator"))
        spellsTitle:SetText("(" .. CludesUI.Lf("Inherited from %1$s", gname) .. ")")

        -- Child x = padDiff + PAD aligns with the PAD margin (the scroll
        -- child is widened by padDiff each side and shifted left, so x = 0
        -- sits OFF the visible column and clips).
        local details = leftFrame:CreateFontString(nil, "OVERLAY")
        details:SetFont(fontFile, 12, "")
        details:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", padDiff + PAD, sy - 14)
        details:SetPoint("RIGHT", leftFrame, "RIGHT", -(padDiff + PAD), 0)
        details:SetJustifyH("LEFT")
        details:SetWordWrap(true)
        details:SetText(
            CludesUI.Lf(
                "Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.",
                gname
            )
        )
        details:SetTextColor(0.65, 0.65, 0.65)
        sy = sy - 64

        local itemLink = CreateFrame("Button", nil, leftFrame)
        itemLink:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", padDiff + PAD, sy - 4)
        itemLink:SetFrameLevel(leftFrame:GetFrameLevel() + 2)
        local linkFS = itemLink:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontFile, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(CludesUI.Lf("Edit in %1$s", gname))
        local lac = CludesUI.CLUDES_GREEN
        if lac then
            linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else
            linkFS:SetTextColor(0.30, 0.79, 0.94, 0.85)
        end
        itemLink:SetSize(linkFS:GetStringWidth() + 4, 18)
        itemLink:SetScript("OnEnter", function()
            linkFS:SetAlpha(1)
        end)
        itemLink:SetScript("OnLeave", function()
            linkFS:SetAlpha(0.85)
        end)
        itemLink:SetScript("OnClick", function()
            selectedSpecKey = gkey
            pickedIndicator = indicator
            mod._bm2InhSel = nil
            CludesUI:RefreshPage(true)
        end)
        -- WoW Forever: All Non Healers/Aug is not in the Editing Spec list
        -- there, so its tiles stay read-only (the tile toggle still works).
        if CludesUI.IS_FOREVER and gkey == "nonhealer" then
            itemLink:Hide()
        end
        sy = sy - 30
    elseif pickedIndicator then
        local indicator = pickedIndicator
        local indicatorType = indicator.type
        local typeInfo = INDICATOR_TYPE_MAP[indicatorType]

        -- v2: Assigned Filters section leads the settings (built by the manager-pages
        -- file; returns the new y cursor); the rest of the legacy per-type settings apply to the same v2 indicator table.
        if mod.BMP_BuildAssignedFilters then
            sy = mod.BMP_BuildAssignedFilters(leftFrame, sy, indicator, fontFile)
        end

        -- Build title: accent "Icon Indicator: " + white "Rejuvenation, Lifebloom"
        local typeName = INDICATOR_TYPE_MAP[indicatorType] and INDICATOR_TYPE_MAP[indicatorType].name or indicatorType
        local ac2 = CludesUI.CLUDES_GREEN
        if ac2 then
            settingsTitle:SetTextColor(ac2.r, ac2.g, ac2.b)
        else
            settingsTitle:SetTextColor(0.30, 0.79, 0.94)
        end
        settingsTitle:SetText(CludesUI.L(typeName .. " Indicator"))

        -- v2: named filter-driven groups head their settings with the group name; spell-driven indicators keep the legacy name list.
        if indicator.name then
            spellsTitle:SetText("(" .. CludesUI.L(indicator.name) .. ")")
        else
            local spellNames = {}
            if indicator.spells then
                for _, spellRef in ipairs(indicator.spells) do
                    spellNames[#spellNames + 1] = SPELL_NAME_BY_ID[spellRef]
                        or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef))
                        or tostring(spellRef)
                end
            end
            spellsTitle:SetText(
                #spellNames > 0 and ("(" .. table.concat(spellNames, ", ") .. ")")
                    or CludesUI.L("(no spells)")
            )
        end

        -- Helper: build a DualRow inside leftFrame
        local function SettingsRow(leftCfg, rightCfg)
            local row
            row, hgt = W:DualRow(leftFrame, sy, leftCfg, rightCfg)
            sy = sy - hgt
            return row
        end

        -- Own Only is per-INDICATOR (no per-source dropdown).
        local function BuildOwnOnlyRow()
            SettingsRow({
                type = "toggle",
                text = "Own Only",
                tooltip = "Only show buffs cast by you.",
                getValue = function()
                    return indicator.ownOnly == true
                end,
                setValue = function(v)
                    indicator.ownOnly = v and true or false
                    ReloadAndUpdate()
                end,
            }, { type = "label", text = "" })
        end

        -- Auto-default growth direction based on position
        local function GetDefaultGrow(place)
            if place == "RIGHT" or place == "TOPRIGHT" or place == "BOTTOMRIGHT" then
                return "LEFT"
            end
            if place == "LEFT" or place == "TOPLEFT" or place == "BOTTOMLEFT" then
                return "RIGHT"
            end
            if place == "TOP" then
                return "DOWN"
            end
            if place == "BOTTOM" then
                return "UP"
            end
            return "RIGHT"
        end

        -- THRESHOLD TEXT (after DISPLAY, for placed types icon/square/bar): recolors
        -- duration text below the threshold via the engine color curve (secret-safe);
        -- default OFF so existing indicators are unchanged.
        local function BuildThresholdRow()
            _, hgt = W:SectionHeader(leftFrame, "THRESHOLD TEXT", sy)
            sy = sy - hgt

            -- Sub-settings are interactive only while Enable Threshold is on.
            local thOff = function()
                return not indicator.thresholdEnabled
            end

            -- The engine color curve is the only threshold display the duration bindings support.
            local thRow = SettingsRow({
                type = "toggle",
                text = "Enable Threshold Text",
                getValue = function()
                    return indicator.thresholdEnabled or false
                end,
                setValue = function(v)
                    indicator.thresholdEnabled = v
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "slider",
                text = "Threshold (sec)",
                min = 1,
                max = 10,
                step = 1,
                trackWidth = 120,
                disabled = thOff,
                disabledTooltip = "Enable Threshold Text",
                getValue = function()
                    return indicator.threshold or 3
                end,
                setValue = function(v)
                    indicator.threshold = v
                    ReloadAndUpdate()
                end,
            })

            -- Inline swatch on the toggle: threshold text color; dimmed and inert while the threshold is off.
            do
                local region = thRow._leftRegion
                local swatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    thRow:GetFrameLevel() + 3,
                    function()
                        local c = indicator.thresholdColor or { r = 1, g = 0.2, b = 0.2 }
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        indicator.thresholdColor = { r = r, g = g, b = b }
                        ReloadAndUpdate()
                    end,
                    false,
                    20
                )
                swatch:SetPoint("RIGHT", region._control, "LEFT", -8, 0)
                -- Click-gate while the threshold is off (dimmed swatch).
                local origClick = swatch:GetScript("OnClick")
                swatch:SetScript("OnClick", function(self, ...)
                    if thOff() then
                        return
                    end
                    if origClick then
                        origClick(self, ...)
                    end
                end)
                swatch:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        swatch,
                        thOff() and CludesUI.DisabledTooltip("Enable Threshold Text")
                            or "Threshold Text Color"
                    )
                end)
                swatch:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function SwatchState()
                    swatch:SetAlpha(thOff() and 0.3 or 1)
                end
                CludesUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    SwatchState()
                end)
                SwatchState()
                region._lastInline = swatch
            end
        end

        if indicatorType == "icon" or indicatorType == "square" then
            -----------------------------------------------------------
            --  CORE
            -----------------------------------------------------------
            _, hgt = W:SectionHeader(leftFrame, "CORE", sy)
            sy = sy - hgt

            -- Assignment lives in ASSIGNED BUFFS: rows are Position | Growth
            -- Direction, then Own Only.
            -- Own Only is per-INDICATOR (no per-source dropdown).
            local ownCfg = {
                type = "toggle",
                text = "Own Only",
                tooltip = "Only show buffs cast by you.",
                getValue = function()
                    return indicator.ownOnly == true
                end,
                setValue = function(v)
                    indicator.ownOnly = v and true or false
                    ReloadAndUpdate()
                end,
            }
            -- Position gains an "Anchor To" subnav (v2): picking another indicator
            -- of the SAME type continues its run; anchored position/growth/wrap come from the target.
            local posValues, posOrder = {}, {}
            for _, k in ipairs(POSITION_ORDER) do
                posOrder[#posOrder + 1] = k
                posValues[k] = POSITION_VALUES[k]
            end
            local anchorVals = {}
            local entries = GetSpecIndicators(saved, selectedSpecKey) or {}
            local byId = {}
            for idx = 1, #entries do
                if entries[idx].id ~= nil then
                    byId[entries[idx].id] = entries[idx]
                end
            end
            -- Following the candidate's own anchor links must never reach back to this indicator (no cycles).
            local function WouldCycle(target)
                local seen, current = {}, target
                while current do
                    if current == indicator or seen[current] then
                        return true
                    end
                    seen[current] = true
                    current = current.anchorTo and byId[current.anchorTo] or nil
                end
                return false
            end
            local ao = {}
            for idx = 1, #entries do
                local t = entries[idx]
                if
                    t ~= indicator
                    and t.id ~= nil
                    and t.enabled
                    and (t.type or "icon") == (indicatorType or "icon")
                    and not WouldCycle(t)
                then
                    local keyName = "@" .. t.id
                    local labelText = (t.name and t.name ~= "" and t.name) or nil
                    if not labelText then
                        local spellRef = mod.BM2_PreferredSpell
                            and mod.BM2_PreferredSpell(t, SelectedBucketClass())
                        local nm = spellRef
                            and C_Spell
                            and C_Spell.GetSpellName
                            and C_Spell.GetSpellName(spellRef)
                        labelText = nm or ("Indicator " .. t.id)
                    end
                    anchorVals[keyName] = labelText
                    ao[#ao + 1] = keyName
                end
            end
            if #ao > 0 then
                -- Subnav children report through onSelect (they never
                -- reach the dropdown's setValue); route both paths into
                -- the shared setter below. "Anchor To" leads the list.
                posValues["__anchor"] = {
                    text = "Anchor To",
                    subnav = {
                        values = anchorVals,
                        order = ao,
                        onSelect = function(childKey)
                            local tid = type(childKey) == "string" and string.match(childKey, "^@(%d+)$")
                            if tid then
                                indicator.anchorTo = tonumber(tid)
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                            end
                        end,
                        icon = function(keyName)
                            local ident = tonumber(string.match(keyName, "^@(%d+)$"))
                            local t = ident and byId[ident]
                            local spellRef = t
                                and mod.BM2_PreferredSpell
                                and mod.BM2_PreferredSpell(t, SelectedBucketClass())
                            return spellRef
                                    and C_Spell
                                    and C_Spell.GetSpellTexture
                                    and C_Spell.GetSpellTexture(spellRef)
                                or nil
                        end,
                    },
                }
                tinsert(posOrder, 1, "__anchor")
            end
            local Anchored = function()
                return indicator.anchorTo ~= nil
            end
            local posCfg = {
                type = "dropdown",
                text = "Position",
                values = posValues,
                order = posOrder,
                getValue = function()
                    local ak = indicator.anchorTo and ("@" .. indicator.anchorTo)
                    if ak and anchorVals[ak] then
                        return ak
                    end
                    return indicator.position or "TOPLEFT"
                end,
                setValue = function(v)
                    local tid = type(v) == "string" and string.match(v, "^@(%d+)$")
                    if tid then
                        indicator.anchorTo = tonumber(tid)
                    else
                        indicator.anchorTo = nil
                        indicator.position = v
                        indicator.growDirection = GetDefaultGrow(v)
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
            }
            local growCfg = {
                type = "dropdown",
                text = "Growth Direction",
                values = GROW_VALUES,
                order = GROW_ORDER,
                disabled = Anchored,
                disabledTooltip = "Remove the Anchor To position",
                getValue = function()
                    return indicator.growDirection or "RIGHT"
                end,
                setValue = function(v)
                    indicator.growDirection = v
                    ReloadAndUpdate()
                end,
            }
            -- Grid wrap+cap is a container capability (chain groups wrap natively; live
            -- indicators are linear runs). Icons Per Row rides row 2's right slot (v2 keeps it blank otherwise); Max Icons sits on an inline cog beside it.
            local perRowCfg
            perRowCfg = {
                type = "slider",
                text = "Icons Per Row",
                min = 0,
                max = 20,
                step = 1,
                trackWidth = 120,
                tooltip = "Wraps into a new row (or column for vertical growth) after this many icons; 0 keeps one continuous run.",
                disabled = Anchored,
                disabledTooltip = "Remove the Anchor To position",
                getValue = function()
                    return indicator.iconsPerRow or 0
                end,
                setValue = function(v)
                    indicator.iconsPerRow = (v and v > 0) and v or nil
                    ReloadAndUpdate()
                end,
            }
            local row1, posRow, perRgn
            posRow = SettingsRow(posCfg, growCfg)
            row1 = SettingsRow(ownCfg, perRowCfg or { type = "label", text = "" })
            if perRowCfg then
                perRgn = row1._rightRegion
            end
            if perRgn then
                CludesUI.BuildInlineCog(perRgn, {
                    tip = "Max Icons",
                    title = "Max Icons",
                    rows = {
                        {
                            type = "slider",
                            label = "Max Icons",
                            min = 0,
                            max = 40,
                            step = 1,
                            get = function()
                                return indicator.maxIcons or 0
                            end,
                            set = function(v)
                                indicator.maxIcons = (v and v > 0) and v or nil
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
            end

            -- Cog for position offset X/Y (rides the Position slot, LEFT in both modes)
            do
                local region = posRow._leftRegion
                -- Anchored: only the ALONG-RUN offset does anything (cross-axis
                -- has no engine expression in a shared flow); Frame Level is inert
                -- on continuation groups. Run axis comes from the anchor target's growth (terminal root).
                local function AnchorRunVertical()
                    if not indicator.anchorTo then
                        return nil
                    end
                    local entries = GetSpecIndicators(saved, selectedSpecKey) or {}
                    local byId2 = {}
                    for idx = 1, #entries do
                        if entries[idx].id ~= nil then
                            byId2[entries[idx].id] = entries[idx]
                        end
                    end
                    local seen, current = {}, byId2[indicator.anchorTo]
                    while current and current.anchorTo and not seen[current] do
                        seen[current] = true
                        current = byId2[current.anchorTo]
                    end
                    if not current then
                        return nil
                    end
                    local g = current.growDirection or "RIGHT"
                    return g == "UP" or g == "DOWN"
                end
                CludesUI.BuildInlineCog(region, {
                    title = "Position Offset",
                    rows = {
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -50,
                            max = 50,
                            step = 1,
                            disabled = function()
                                return AnchorRunVertical() == true
                            end,
                            disabledTooltip = "A Horizontally Growing Anchor Target",
                            get = function()
                                return indicator.offsetX or 0
                            end,
                            set = function(v)
                                indicator.offsetX = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -50,
                            max = 50,
                            step = 1,
                            disabled = function()
                                return AnchorRunVertical() == false
                            end,
                            disabledTooltip = "A Vertically Growing Anchor Target",
                            get = function()
                                return indicator.offsetY or 0
                            end,
                            set = function(v)
                                indicator.offsetY = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "dropdown",
                            label = "Frame Level",
                            values = FRAMELVL_VALUES,
                            order = FRAMELVL_ORDER,
                            disabled = function()
                                return indicator.anchorTo ~= nil
                            end,
                            disabledTooltip = "An Unanchored Position",
                            get = function()
                                return indicator.frameLevel or "medium"
                            end,
                            set = function(v)
                                indicator.frameLevel = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
            end

            -----------------------------------------------------------
            --  DISPLAY
            -----------------------------------------------------------
            _, hgt = W:SectionHeader(leftFrame, "DISPLAY", sy)
            sy = sy - hgt

            local IconHidden = function()
                return indicatorType == "icon" and indicator.hideIcon == true
            end
            local sizeRow = SettingsRow({
                type = "slider",
                text = "Size",
                min = 4,
                max = 80,
                step = 1,
                getValue = function()
                    return indicator.size or 12
                end,
                setValue = function(v)
                    indicator.size = v
                    ReloadAndUpdate()
                end,
            }, {
                type = "slider",
                pixel = true,
                text = "Spacing",
                min = -1,
                max = 10,
                step = 1,
                getValue = function()
                    return indicator.spacing or 1
                end,
                setValue = function(v)
                    indicator.spacing = v
                    ReloadAndUpdate()
                end,
            })

            -- Icon Zoom cog (icon type only): one profile-wide value shared by all icon indicators.
            if indicatorType == "icon" then
                local region = sizeRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    disabled = IconHidden,
                    disabledTooltip = "Hide Icons",
                    requireState = "disabled",
                    title = "Icon Zoom",
                    rows = {
                        {
                            type = "slider",
                            label = "Zoom",
                            min = 0,
                            max = 0.20,
                            step = 0.01,
                            get = function()
                                return mod.db.profile.bmIconZoom or 0.08
                            end,
                            set = function(v)
                                mod.db.profile.bmIconZoom = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
            end

            SettingsRow({
                type = "slider",
                text = "Opacity",
                min = 0,
                max = 100,
                step = 1,
                disabled = IconHidden,
                disabledTooltip = "Hide Icons",
                requireState = "disabled",
                getValue = function()
                    return indicator.iconOpacity or 100
                end,
                setValue = function(v)
                    indicator.iconOpacity = v
                    ReloadAndUpdate()
                end,
            }, {
                type = "toggle",
                text = "Duration Swipe",
                disabled = IconHidden,
                disabledTooltip = "Hide Icons",
                requireState = "disabled",
                getValue = function()
                    return indicator.showDuration ~= false
                end,
                setValue = function(v)
                    indicator.showDuration = v
                    ReloadAndUpdate()
                end,
            })
            sy = mod.RFO_AuraBorderSettings(leftFrame, sy, W, function(k)
                return indicator["indBorder" .. k]
            end, function(k, v)
                indicator["indBorder" .. k] = v
            end, ReloadAndUpdate, IconHidden)

            local durRow = SettingsRow({
                type = "toggle",
                text = "Duration Text",
                getValue = function()
                    return indicator.showDurationText or false
                end,
                setValue = function(v)
                    indicator.showDurationText = v
                    ReloadAndUpdate()
                end,
            }, {
                type = "toggle",
                text = "Show Stacks",
                getValue = function()
                    return indicator.showStacks ~= false
                end,
                setValue = function(v)
                    indicator.showStacks = v
                    ReloadAndUpdate()
                end,
            })
            do
                local region = durRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Duration Text",
                    rows = {
                        {
                            type = "slider",
                            label = "Text Size",
                            min = 6,
                            max = 26,
                            step = 1,
                            get = function()
                                return indicator.durationTextSize or 8
                            end,
                            set = function(v)
                                indicator.durationTextSize = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -20,
                            max = 20,
                            step = 1,
                            get = function()
                                return indicator.durationTextOffsetX or 0
                            end,
                            set = function(v)
                                indicator.durationTextOffsetX = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -20,
                            max = 20,
                            step = 1,
                            get = function()
                                return indicator.durationTextOffsetY or 0
                            end,
                            set = function(v)
                                indicator.durationTextOffsetY = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })

                local swatch = CludesUI.BuildColorSwatch(region, durRow:GetFrameLevel() + 3, function()
                    local c = indicator.durationTextColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, 1
                end, function(r, g, b)
                    indicator.durationTextColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = swatch
            end

            do
                local region = durRow._rightRegion
                CludesUI.BuildInlineCog(region, {
                    disabled = function()
                        return indicator.showStacks == false
                    end,
                    disabledTooltip = "Show Stacks",
                    title = "Stacks Text",
                    rows = {
                        {
                            type = "slider",
                            label = "Text Size",
                            min = 6,
                            max = 26,
                            step = 1,
                            get = function()
                                return indicator.stacksTextSize or 8
                            end,
                            set = function(v)
                                indicator.stacksTextSize = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -20,
                            max = 20,
                            step = 1,
                            get = function()
                                return indicator.stacksOffsetX or 0
                            end,
                            set = function(v)
                                indicator.stacksOffsetX = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -20,
                            max = 20,
                            step = 1,
                            get = function()
                                return indicator.stacksOffsetY or 0
                            end,
                            set = function(v)
                                indicator.stacksOffsetY = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
            end
            do
                local region = durRow._rightRegion
                local swatch = CludesUI.BuildColorSwatch(region, durRow:GetFrameLevel() + 3, function()
                    local c = indicator.stacksTextColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, 1
                end, function(r, g, b)
                    indicator.stacksTextColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = swatch
            end
            -- Display-level Icon Glow (v2): permanent, every visible icon of the
            -- group glows while shown. No Max Duration setting by design: the
            -- engine offers no baseline/cap on its duration bindings.
            local GO = CludesUI.GlowOptions
            local glowDesc = GO.PrefixSite(function()
                return indicator
            end, "displayGlow", "engine", ReloadAndUpdate)
            -- The color swatches take the free right half.
            local mdRow =
                SettingsRow(GO.DropdownSpec(glowDesc, "Icon Glow"), { type = "label", text = "Glow Color" })
            if not CludesUI._prebuilding then
                local region = mdRow._leftRegion
                GO.AttachInline(region, glowDesc, mdRow._rightRegion)
                local pv = GO.BuildPreview(region, glowDesc, {
                    bar = false,
                    width = 26,
                    height = 26,
                    anchor = region._lastInline or region._control,
                    x = -12,
                })
                if pv then
                    pv:SetFrameLevel(region:GetFrameLevel() + 5)
                    region._lastInline = pv
                end
            end

            local extraCfg = (indicatorType == "square") and { type = "label", text = "Colors" }
                or {
                    type = "toggle",
                    text = "Hide Icons",
                    tooltip = "Hide the icon texture, border, and duration swipe, leaving only the stack count. Forces icon opacity, border, and duration swipe off.",
                    getValue = function()
                        return indicator.hideIcon == true
                    end,
                    setValue = function(v)
                        indicator.hideIcon = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                }
            local extraRow
            if indicatorType ~= "icon" or CludesUI.IS_FOREVER then
                extraRow = SettingsRow(extraCfg, CludesUI.BlankRowCfg())
            end

            -- Per-ability color swatches (square only), right-to-left like every inline
            -- swatch row (ability 1 at the right edge); no per-spell color falls back to ind.color, then the default.
            if indicatorType == "square" then
                local region = extraRow._leftRegion
                local DEFAULT_SQ = { r = 0.30, g = 0.79, b = 0.94 }
                local prev = nil
                for _, spellRef in ipairs(indicator.spells or {}) do
                    local mySid = spellRef
                    local swatch = CludesUI.BuildColorSwatch(region, extraRow:GetFrameLevel() + 3, function()
                        local c = (indicator.spellColors and indicator.spellColors[mySid]) or indicator.color or DEFAULT_SQ
                        return c.r, c.g, c.b, 1
                    end, function(r, g, b)
                        if not indicator.spellColors then
                            indicator.spellColors = {}
                        end
                        indicator.spellColors[mySid] = { r = r, g = g, b = b }
                        ReloadAndUpdate()
                    end, false, 20)
                    if prev then
                        swatch:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                    else
                        swatch:SetPoint("RIGHT", region, "RIGHT", -20, 0)
                    end
                    prev = swatch
                    -- Tooltip: ability name so each swatch is identifiable.
                    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(mySid)
                    if nm then
                        swatch:HookScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(swatch, nm)
                        end)
                        swatch:HookScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    end
                end
                -- One swatch per ASSIGNED FILTER, continuing the chain: colors
                -- every spell that filter shows (direct per-spell swatches
                -- above win on overlap -- BM2_SquareFilterColors doctrine).
                -- Ascending fid order matches the runtime's overlap resolution.
                if indicator.filters then
                    local fids = {}
                    -- Presets only the other client offers get no swatch here.
                    for fid in pairs(indicator.filters) do
                        if not mod.BM2_HiddenPresetFilter(fid) then
                            fids[#fids + 1] = fid
                        end
                    end
                    table.sort(fids)
                    for _, fid in ipairs(fids) do
                        local myFid = fid
                        local swatch = CludesUI.BuildColorSwatch(
                            region,
                            extraRow:GetFrameLevel() + 3,
                            function()
                                local c = (indicator.filterColors and indicator.filterColors[myFid])
                                    or indicator.color
                                    or DEFAULT_SQ
                                return c.r, c.g, c.b, 1
                            end,
                            function(r, g, b)
                                if not indicator.filterColors then
                                    indicator.filterColors = {}
                                end
                                indicator.filterColors[myFid] = { r = r, g = g, b = b }
                                ReloadAndUpdate()
                            end,
                            false,
                            20
                        )
                        if prev then
                            swatch:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                        else
                            swatch:SetPoint("RIGHT", region, "RIGHT", -20, 0)
                        end
                        prev = swatch
                        local f = mod.BM2_GetFilter and mod.BM2_GetFilter(myFid)
                        local fname = (f and f.name) or ("Filter " .. tostring(myFid))
                        swatch:HookScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(swatch, fname)
                        end)
                        swatch:HookScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    end
                end
                region._lastInline = prev
            end

            -- Pandemic Border (icon only, not on WoW Forever): the game shows it while
            -- the buff is in its refresh window; color and size in the row's swatch and cog.
            if indicatorType == "icon" and not CludesUI.IS_FOREVER then
                local pandemicOff = function()
                    return IconHidden() or not indicator.pandemicBorderEnabled
                end
                local pandemicTip = function()
                    return IconHidden() and "Hide Icons" or "Pandemic Border"
                end
                local pandemicState = function()
                    return IconHidden() and "disabled" or "enabled"
                end
                local function PandemicTextureOff()
                    local tex = indicator.indBorderTexture
                    return not tex
                        or tex == "solid"
                        or tex == ""
                        or (indicator.indBorderSize or 1) <= 0
                        or not CludesUI.ResolveBorderTexture(tex)
                end
                local pandemicRow = SettingsRow({
                    type = "toggle",
                    text = "Pandemic Border",
                    tooltip = "Shows a colored border on these icons while the buff can be refreshed without losing time.",
                    disabled = IconHidden,
                    disabledTooltip = "Hide Icons",
                    requireState = "disabled",
                    getValue = function()
                        return indicator.pandemicBorderEnabled == true
                    end,
                    setValue = function(v)
                        indicator.pandemicBorderEnabled = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                }, extraCfg)
                local region = pandemicRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    disabled = pandemicOff,
                    disabledTooltip = pandemicTip,
                    requireState = pandemicState,
                    title = "Pandemic Border",
                    rows = {
                        {
                            type = "toggle",
                            label = "Textured Pandemic Ring",
                            tooltip = "Uses the selected aura Border Style, size, shifts and offsets for the pandemic highlight.",
                            disabled = PandemicTextureOff,
                            disabledTooltip = "This option requires a textured aura Border Style and a Border Size above 0.",
                            get = function()
                                return indicator.pandemicBorderTextured == true
                            end,
                            set = function(v)
                                indicator.pandemicBorderTextured = v
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Border Size",
                            min = 1,
                            max = 5,
                            step = 1,
                            disabled = function()
                                return indicator.pandemicBorderTextured == true and not PandemicTextureOff()
                            end,
                            disabledTooltip = "Textured Pandemic Ring uses the aura's Border Size.",
                            get = function()
                                return indicator.pandemicBorderWidth or 2
                            end,
                            set = function(v)
                                indicator.pandemicBorderWidth = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
                CludesUI.BuildInlineSwatches(region, {
                    {
                        tooltip = "Pandemic Border Color",
                        getValue = function()
                            local c = indicator.pandemicBorderColor or { r = 1, g = 0.2, b = 0.2 }
                            return c.r, c.g, c.b, 1
                        end,
                        setValue = function(r, g, b)
                            indicator.pandemicBorderColor = { r = r, g = g, b = b }
                            ReloadAndUpdate()
                        end,
                    },
                }, {
                    disabled = pandemicOff,
                    disabledTooltip = pandemicTip,
                    requireState = pandemicState,
                    size = 20,
                })
            end

            -- THRESHOLD section
            BuildThresholdRow()
        elseif typeInfo and typeInfo.placed then
            if indicatorType == "bar" then
                -----------------------------------------------------------
                --  BAR: CORE
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "CORE", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "dropdown",
                    text = "Orientation",
                    values = ORIENT_VALUES,
                    order = ORIENT_ORDER,
                    getValue = function()
                        return indicator.orientation or "HORIZONTAL"
                    end,
                    -- RefreshPage(true) = full rebuild so the Width/Height + Full
                    -- Width/Height labels re-evaluate isVert and flip live (fast path only re-reads values, not static labels).
                    setValue = function(v)
                        indicator.orientation = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage(true)
                    end,
                }, {
                    type = "toggle",
                    text = "Own Only",
                    tooltip = "Only show buffs cast by you.",
                    getValue = function()
                        return indicator.ownOnly == true
                    end,
                    setValue = function(v)
                        indicator.ownOnly = v and true or false
                        ReloadAndUpdate()
                    end,
                })

                local posRow = SettingsRow({
                    type = "dropdown",
                    text = "Position",
                    values = POSITION_VALUES,
                    order = POSITION_ORDER,
                    getValue = function()
                        return indicator.position or "TOPLEFT"
                    end,
                    setValue = function(v)
                        indicator.position = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "toggle",
                    text = "Reverse Fill",
                    getValue = function()
                        return indicator.reverseFill or false
                    end,
                    setValue = function(v)
                        indicator.reverseFill = v
                        ReloadAndUpdate()
                    end,
                })
                do
                    local region = posRow._leftRegion
                    CludesUI.BuildInlineCog(region, {
                        title = "Position Offset",
                        rows = {
                            {
                                type = "slider",
                                label = "Offset X",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return indicator.offsetX or 0
                                end,
                                set = function(v)
                                    indicator.offsetX = v
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Offset Y",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return indicator.offsetY or 0
                                end,
                                set = function(v)
                                    indicator.offsetY = v
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "dropdown",
                                label = "Frame Level",
                                values = FRAMELVL_VALUES,
                                order = FRAMELVL_ORDER,
                                get = function()
                                    return indicator.frameLevel or "behindBorders"
                                end,
                                set = function(v)
                                    indicator.frameLevel = v
                                    ReloadAndUpdate()
                                end,
                            },
                        },
                    })
                end

                -----------------------------------------------------------
                --  BAR: DISPLAY
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "DISPLAY", sy)
                sy = sy - hgt

                local isVert = (indicator.orientation or "HORIZONTAL") == "VERTICAL"

                -- Labels flip with orientation so each slot always names the
                -- on-screen axis; each slider disables while its Full toggle is on.
                SettingsRow({
                    type = "slider",
                    text = isVert and "Height" or "Width",
                    min = 5,
                    max = 200,
                    step = 1,
                    disabled = function()
                        return indicator.barFullWidth
                    end,
                    disabledTooltip = isVert and "Full Height Bar" or "Full Width Bar",
                    requireState = "disabled",
                    getValue = function()
                        return indicator.barWidth or 30
                    end,
                    setValue = function(v)
                        indicator.barWidth = v
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "slider",
                    text = isVert and "Width" or "Height",
                    min = 1,
                    max = 100,
                    step = 1,
                    disabled = function()
                        return indicator.barFullHeight
                    end,
                    disabledTooltip = isVert and "Full Width Bar" or "Full Height Bar",
                    requireState = "disabled",
                    getValue = function()
                        return indicator.barHeight or 4
                    end,
                    setValue = function(v)
                        indicator.barHeight = v
                        ReloadAndUpdate()
                    end,
                })

                -- Labels flip with orientation like the sliders above; RefreshPage()
                -- so the Width/Height disabled state updates live.
                SettingsRow({
                    type = "toggle",
                    text = isVert and "Full Height Bar" or "Full Width Bar",
                    getValue = function()
                        return indicator.barFullWidth or false
                    end,
                    setValue = function(v)
                        indicator.barFullWidth = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "toggle",
                    text = isVert and "Full Width Bar" or "Full Height Bar",
                    getValue = function()
                        return indicator.barFullHeight or false
                    end,
                    setValue = function(v)
                        indicator.barFullHeight = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                })

                local barBgRow = SettingsRow({
                    type = "slider",
                    text = "Color",
                    min = 0,
                    max = 100,
                    step = 1,
                    trackWidth = 120,
                    getValue = function()
                        return indicator.barColorOpacity or 100
                    end,
                    setValue = function(v)
                        indicator.barColorOpacity = v
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "slider",
                    text = "Background",
                    min = 0,
                    max = 100,
                    step = 1,
                    trackWidth = 120,
                    getValue = function()
                        return indicator.barBgOpacity or 50
                    end,
                    setValue = function(v)
                        indicator.barBgOpacity = v
                        ReloadAndUpdate()
                    end,
                })
                do
                    local region = barBgRow._leftRegion
                    local colorSwatch = CludesUI.BuildColorSwatch(
                        region,
                        barBgRow:GetFrameLevel() + 3,
                        function()
                            local c = indicator.color or { r = 0x0C / 255, g = 0xD2 / 255, b = 0x9D / 255 }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            indicator.color = { r = r, g = g, b = b }
                            ReloadAndUpdate()
                        end,
                        false,
                        20
                    )
                    colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                end
                do
                    local region = barBgRow._rightRegion
                    local bgSwatch = CludesUI.BuildColorSwatch(
                        region,
                        barBgRow:GetFrameLevel() + 3,
                        function()
                            local c = indicator.barBgColor or { r = 0, g = 0, b = 0 }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            indicator.barBgColor = { r = r, g = g, b = b }
                            ReloadAndUpdate()
                        end,
                        false,
                        20
                    )
                    bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = bgSwatch
                end

                -- THRESHOLD section
                BuildThresholdRow()
            elseif indicatorType == "square" then
                -- Unreachable: square is handled by the icon/square path above.
            else
                -- Other placed types (future): Position + cog
                local posRow = SettingsRow({
                    type = "dropdown",
                    text = "Position",
                    values = POSITION_VALUES,
                    order = POSITION_ORDER,
                    getValue = function()
                        return indicator.position or "TOPLEFT"
                    end,
                    setValue = function(v)
                        indicator.position = v
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "" })
                do
                    local region = posRow._leftRegion
                    CludesUI.BuildInlineCog(region, {
                        title = "Position Offset",
                        rows = {
                            {
                                type = "slider",
                                label = "Offset X",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return indicator.offsetX or 0
                                end,
                                set = function(v)
                                    indicator.offsetX = v
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Offset Y",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return indicator.offsetY or 0
                                end,
                                set = function(v)
                                    indicator.offsetY = v
                                    ReloadAndUpdate()
                                end,
                            },
                        },
                    })
                end
                BuildOwnOnlyRow()
            end
        else
            -- Frame effects: healthcolor, border, framealpha

            if indicatorType == "border" then
                -----------------------------------------------------------
                --  FRAME BORDER: CORE
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "CORE", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "dropdown",
                    text = "Show When",
                    values = SHOW_WHEN_VALUES_EFFECT,
                    order = SHOW_WHEN_ORDER_EFFECT,
                    tooltip = SHOW_WHEN_EFFECT_TIP,
                    getValue = function()
                        return "present"
                    end,
                    setValue = function(v)
                        indicator.showWhen = "present"
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "toggle",
                    text = "Own Only",
                    tooltip = "Only show buffs cast by you.",
                    getValue = function()
                        return indicator.ownOnly == true
                    end,
                    setValue = function(v)
                        indicator.ownOnly = v and true or false
                        ReloadAndUpdate()
                    end,
                })

                -----------------------------------------------------------
                --  FRAME BORDER: DISPLAY
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "DISPLAY", sy)
                sy = sy - hgt

                -- Offered styles: shared border-texture set minus "shadow" (identical
                -- to glow without behind/black handling) and "lightspark" (oversized
                -- outward halo), plus "Dashed" (static ants) after Solid. LibSharedMedia
                -- kept; built per-render so newly registered ones appear without a reload.
                local EXCLUDED_BORDER_STYLES = { shadow = true, lightspark = true }
                local allVals, allOrder = CludesUI.GetBorderTextureDropdown()
                local bsVals, bsOrder = {}, {}
                for _, k in ipairs(allOrder) do
                    if not EXCLUDED_BORDER_STYLES[k] then
                        bsVals[k] = allVals[k]
                        bsOrder[#bsOrder + 1] = k
                        if k == "solid" then
                            bsVals.dashed = "Dashed"
                            bsOrder[#bsOrder + 1] = "dashed"
                        end
                    end
                end

                -- Border Width: the dashed ants keep their 1-6 width; every other style
                -- takes an exact pixel size (borderWidthPx beside borderWidth). The step
                -- read here is the one ApplyEffectBorder draws (a textured width caps at 4).
                local bwSlot
                if (indicator.borderStyle or "solid") == "dashed" then
                    bwSlot = {
                        type = "slider",
                        text = "Border Width",
                        min = 1,
                        max = 6,
                        step = 1,
                        trackWidth = 120,
                        getValue = function()
                            return indicator.borderWidth or 2
                        end,
                        setValue = function(v)
                            indicator.borderWidth = v
                            ReloadAndUpdate()
                        end,
                    }
                else
                    local function BwStyle()
                        local s = indicator.borderStyle or "solid"
                        if s == "sweepcw" or s == "sweepccw" then
                            s = "solid"
                        end
                        return s
                    end
                    bwSlot = CludesUI.BorderPxSliderCfg({
                        text = "Border Width",
                        trackWidth = 120,
                        getStep = function()
                            local bw = indicator.borderWidth or 2
                            return (BwStyle() == "solid") and bw or math.min(bw, 4)
                        end,
                        setStep = function(v)
                            indicator.borderWidth = v
                        end,
                        getTex = BwStyle,
                        getPx = function()
                            return indicator.borderWidthPx
                        end,
                        setPx = function(v)
                            indicator.borderWidthPx = v
                        end,
                        apply = ReloadAndUpdate,
                    })
                    -- This surface never allowed 0 (the dashed style would inherit it).
                    bwSlot.min = 1
                end
                SettingsRow({
                    type = "dropdown",
                    text = "Border Style",
                    values = bsVals,
                    order = bsOrder,
                    -- Fall back to Solid if the stored style is no longer offered.
                    getValue = function()
                        local s = indicator.borderStyle or "solid"
                        return bsVals[s] and s or "solid"
                    end,
                    setValue = function(v)
                        indicator.borderStyle = v
                        ReloadAndRebuild()
                    end,
                }, bwSlot)

                -- Dashes slot applies only to the dashed style; blank label otherwise (allowed on a section's last row).
                local ac = CludesUI.ACCENT_COLOR or { r = 0.30, g = 0.79, b = 0.94 }
                local dashesSlot
                if (indicator.borderStyle or "solid") == "dashed" then
                    dashesSlot = {
                        type = "slider",
                        text = "Dashes",
                        min = 4,
                        max = 16,
                        step = 1,
                        trackWidth = 120,
                        getValue = function()
                            return indicator.borderDashCount or 8
                        end,
                        setValue = function(v)
                            indicator.borderDashCount = v
                            ReloadAndUpdate()
                        end,
                    }
                else
                    dashesSlot = { type = "label", text = "" }
                end
                local bdrColorRow = SettingsRow({
                    type = "slider",
                    text = "Color",
                    min = 0,
                    max = 100,
                    step = 1,
                    trackWidth = 120,
                    getValue = function()
                        return indicator.borderOpacity or 100
                    end,
                    setValue = function(v)
                        indicator.borderOpacity = v
                        ReloadAndUpdate()
                    end,
                }, dashesSlot)
                do
                    local region = bdrColorRow._leftRegion
                    local colorSwatch = CludesUI.BuildColorSwatch(
                        region,
                        bdrColorRow:GetFrameLevel() + 3,
                        function()
                            local c = indicator.color or { r = ac.r, g = ac.g, b = ac.b }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            indicator.color = { r = r, g = g, b = b }
                            ReloadAndUpdate()
                        end,
                        false,
                        20
                    )
                    colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                end
            elseif indicatorType == "healthcolor" or indicatorType == "bgcolor" then
                -----------------------------------------------------------
                --  HEALTH BAR COLOR / BACKGROUND COLOR: CORE
                --  (identical settings; bgcolor tints the health bar's
                --  background area instead of the fill)
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "CORE", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "dropdown",
                    text = "Show When",
                    values = SHOW_WHEN_VALUES_EFFECT,
                    order = SHOW_WHEN_ORDER_EFFECT,
                    tooltip = SHOW_WHEN_EFFECT_TIP,
                    getValue = function()
                        return "present"
                    end,
                    setValue = function(v)
                        indicator.showWhen = "present"
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "toggle",
                    text = "Own Only",
                    tooltip = "Only show buffs cast by you.",
                    getValue = function()
                        return indicator.ownOnly == true
                    end,
                    setValue = function(v)
                        indicator.ownOnly = v and true or false
                        ReloadAndUpdate()
                    end,
                })

                -----------------------------------------------------------
                --  HEALTH BAR COLOR: DISPLAY
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "DISPLAY", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "colorpicker",
                    text = "Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = indicator.color or { r = 0x0C / 255, g = 0xD2 / 255, b = 0x9D / 255 }
                        return c.r, c.g, c.b
                    end,
                    setValue = function(r, g, b)
                        indicator.color = { r = r, g = g, b = b }
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "slider",
                    text = "Opacity",
                    min = 5,
                    max = 100,
                    step = 1,
                    getValue = function()
                        return indicator.opacity or 100
                    end,
                    setValue = function(v)
                        indicator.opacity = v
                        ReloadAndUpdate()
                    end,
                })
            else
                -- framealpha
                -----------------------------------------------------------
                --  FRAME ALPHA: CORE
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "CORE", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "dropdown",
                    text = "Show When",
                    values = SHOW_WHEN_VALUES,
                    order = SHOW_WHEN_ORDER,
                    getValue = function()
                        return indicator.showWhen or "present"
                    end,
                    setValue = function(v)
                        indicator.showWhen = v
                        ReloadAndUpdate()
                    end,
                }, {
                    type = "toggle",
                    text = "Own Only",
                    tooltip = "Only show buffs cast by you.",
                    getValue = function()
                        return indicator.ownOnly == true
                    end,
                    setValue = function(v)
                        indicator.ownOnly = v and true or false
                        ReloadAndUpdate()
                    end,
                })

                -----------------------------------------------------------
                --  FRAME ALPHA: DISPLAY
                -----------------------------------------------------------
                _, hgt = W:SectionHeader(leftFrame, "DISPLAY", sy)
                sy = sy - hgt

                SettingsRow({
                    type = "slider",
                    text = "Alpha",
                    min = 5,
                    max = 100,
                    step = 1,
                    getValue = function()
                        return floor((indicator.alpha or 0.4) * 100)
                    end,
                    setValue = function(v)
                        indicator.alpha = v / 100
                        ReloadAndUpdate()
                    end,
                }, { type = "label", text = "" })
                -- Frame Alpha has no Threshold section: its alpha multiplies with the range-fade alpha and two secret values can't be combined.
            end
        end
    else
        if selectedSpecKey then
            settingsTitle:SetText(CludesUI.L("Create an indicator to get started."))
        else
            settingsTitle:SetText(CludesUI.L("Select a spec above."))
        end
        settingsTitle:SetTextColor(0.4, 0.4, 0.4)
        spellsTitle:SetText("")
    end

    -- Size the settings scroll child to its built content + sync the scrollbar.
    settingsChild:SetHeight(max(viewportH, math.abs(sy) + 12))
    UpdateThumb()

    -- Size the sidebar scroll child to its content (tiles + Add New button)
    local sidebarContentH = max(10, math.abs(tileY))
    sidebarChild:SetHeight(sidebarContentH)

    CludesUI._EndRootRender("rf.bm")
    -- Return 0: content lives on scrollFrame directly, so no outer scroll range.
    return 0
end
