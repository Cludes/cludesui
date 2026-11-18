if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Thresholds.lua
--
--  The Class Resource Color fill resolver, the bar-type spec map, the
--  per-spec threshold entries and the threshold and band color curves.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local format = string.format
local UnitClass, GetShapeshiftFormID = UnitClass, GetShapeshiftFormID
local IsPlayerSpell = IsPlayerSpell

local ERB, GetPrimaryPowerType = Inner.ERB, Inner.GetPrimaryPowerType
local GetSpecialization, PT = Inner.GetSpecialization, Inner.PT

-------------------------------------------------------------------------------
--  "Class Resource Color" fill resolver: discrete resources -> Class Resource
--  Colors; power-type bar secondaries -> Power Colors. Returns nil for resources
--  with no dedicated color (DK runes, Ironfur, Ignore Pain, Stagger), so callers
--  fall back to class color. On ERB + a global alias for preview.
-------------------------------------------------------------------------------
do
    local RKEY = {
        [PT.COMBO] = "ComboPoints",
        [PT.RUNES] = "Runes",
        [PT.HOLY_POWER] = "HolyPower",
        [PT.CHI] = "Chi",
        [PT.SOUL_SHARDS] = "SoulShards",
        [PT.ARCANE] = "ArcaneCharges",
        [PT.ESSENCE] = "Essence",
        ["ICICLES"] = "Icicles",
        ["SOUL_FRAGMENTS_VENGEANCE"] = "SoulFragments",
        ["SOUL_FRAGMENTS_DEVOURER"] = "SoulFragments",
        ["MAELSTROM_WEAPON"] = "MaelstromWeapon",
        ["TIP_OF_THE_SPEAR"] = "TipOfTheSpear",
        ["WHIRLWIND_STACKS"] = "WhirlwindStacks",
        ["SWEEPING_STRIKES"] = "SweepingStrikes",
    }
    local PKEY = {
        ["LUNAR_POWER_BAR"] = "LUNAR_POWER",
        ["MAELSTROM_BAR"] = "MAELSTROM",
        ["INSANITY_BAR"] = "INSANITY",
        ["FOCUS_BAR"] = "FOCUS",
    }
    function ERB.ResolveSecondaryResourceColor(powerKey)
        local rk = RKEY[powerKey]
        if rk and CludesUI.GetClassResourceColor then
            local c = CludesUI.GetClassResourceColor(rk)
            if c then
                return c.r, c.g, c.b
            end
        end
        local pk = PKEY[powerKey]
        if pk and CludesUI.GetPowerColor then
            local c = CludesUI.GetPowerColor(pk)
            if c then
                return c.r, c.g, c.b
            end
        end
        return nil
    end
    _G._CURB_ResolveSecondaryResourceColor = ERB.ResolveSecondaryResourceColor
end

-- Bar-type spec lookup: specID -> true for specs using a bar-type secondary
-- resource (Astral Power, Maelstrom, Insanity, Stagger, Focus, Devourer Soul
-- Fragments). Built once at init; exposed for options panel.
local BAR_TYPE_SPECS = {}

local function BuildBarTypeSpecMap()
    -- The spec positions below are retail's: WoW Forever's specs are its
    -- vanilla talent trees, none of which has these resources, so the map
    -- stays empty there.
    if CludesUI.IS_FOREVER then
        return
    end
    for classID = 1, GetNumClasses() do
        local _, class = GetClassInfo(classID)
        if class then
            local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            for specIndex = 1, numSpecs do
                local specID = GetSpecializationInfoForClassID(classID, specIndex)
                if specID then
                    local isBar = false
                    if class == "DRUID" and specIndex == 1 then
                        isBar = true
                    elseif class == "SHAMAN" and specIndex == 1 then
                        isBar = true
                    elseif class == "PRIEST" and specIndex == 3 then
                        isBar = true
                    elseif class == "MONK" and specIndex == 1 then
                        isBar = true
                    elseif class == "HUNTER" and (specIndex == 1 or specIndex == 2) then
                        isBar = true
                    elseif class == "DEMONHUNTER" and specID == 1480 then
                        isBar = true
                    end
                    BAR_TYPE_SPECS[specID] = isBar
                end
            end
        end
    end
end

-- Resolve the active thresholdSpecs entry for the current spec, or nil. Priority:
-- 1) spec match + active talent gate  2) spec match, no gate  3) All Specs
-- (specID 0) + active gate  4) All Specs, no gate. Entries with an inactive
-- talent gate are skipped. A druid Power Bar still saved in the retired
-- "form specific" mode (thresholdFormMode, entries keyed by the form's power
-- type via entry.formKey) takes the form's entry in that form and the scan
-- above in any form without one. Wrapped in a do-block
-- so cache state/helpers free main-chunk local slots; only
-- ResolveThresholdSpecEntry stays a main-chunk local, others reached via
-- ns.InvalidateThresholdCaches / _G._CURB_ResolveSpecIDCached.
local ResolveThresholdSpecEntry
do
    local FORM_THRESHOLD_KEY = { [PT.MANA] = "mana", [PT.RAGE] = "rage", [PT.ENERGY] = "energy" }

    -- Spec ID and talent-gate state only change on spec/talent events, but
    -- ResolveThresholdSpecEntry runs hot (~60fps via the Ironfur bar), so both are
    -- cached to keep GetSpecialization/IsPlayerSpell/IsSpellKnown out of the frame
    -- loop; InvalidateThresholdCaches clears them on those events. The entry list is
    -- still re-scanned live each call, so options edits apply immediately.
    local _thrSpecID -- nil = unknown, false = resolved-to-none, number = specID
    local _talentGateCache = {} -- gate spellID -> bool
    local function InvalidateThresholdCaches()
        _thrSpecID = nil
        wipe(_talentGateCache)
        if CludesUI.IS_FOREVER and mod._fvThrPick then
            wipe(mod._fvThrPick)
        end
    end
    mod.InvalidateThresholdCaches = InvalidateThresholdCaches

    local function ResolveSpecIDCached()
        if _thrSpecID ~= nil then
            return _thrSpecID or nil
        end
        local position = GetSpecialization and GetSpecialization()
        local spellRef = position
                and C_SpecializationInfo
                and C_SpecializationInfo.GetSpecializationInfo(position)
            or nil
        _thrSpecID = spellRef or false
        return spellRef
    end
    _G._CURB_ResolveSpecIDCached = ResolveSpecIDCached

    local function IsTalentGateActive(gate)
        local val = _talentGateCache[gate]
        if val == nil then
            val = ((IsPlayerSpell and IsPlayerSpell(gate)) or (IsSpellKnown and IsSpellKnown(gate))) and true
                or false
            _talentGateCache[gate] = val
        end
        return val
    end

    -- WoW Forever: true when a card counts for this spec in the class's pick: it
    -- names the spec and, as in the scan below, is not skipped for an inactive
    -- talent gate.
    function mod.ThresholdCardLiveFor(record, ident)
        local ids = record.specIDs
        if not ids then
            return false
        end
        for jdx = 1, #ids do
            if ids[jdx] == ident then
                local gate = record.talentSpellID
                return not gate or IsTalentGateActive(gate)
            end
        end
        return false
    end

    -- WoW Forever: true when any card of the list counts for this spec.
    function mod.ThresholdEntriesMention(ident, entries)
        for i = 1, #entries do
            if mod.ThresholdCardLiveFor(entries[i], ident) then
                return true
            end
        end
        return false
    end

    -- WoW Forever: the spec the class resolves thresholds as for one card list --
    -- the first class spec (class order) a live card names, else the class's first
    -- spec. A Druid's Class Resource there is only Cat Form combo points, so that
    -- list skips Balance (102, Astral Power) and, with no live card naming another
    -- Druid spec, resolves as no spec (the All Specs tiers only). Unmemoized: the
    -- options helpers call it directly.
    function mod.ForeverThresholdPick(entries)
        local p = ERB.db and ERB.db.profile
        local sec = p and p.secondary
        if sec and entries == sec.thresholdSpecs and select(2, UnitClass("player")) == "DRUID" then
            local ids = CludesUI.ForeverClassSpecIDs("DRUID")
            for i = 1, (ids and #ids or 0) do
                if ids[i] ~= 102 and mod.ThresholdEntriesMention(ids[i], entries) then
                    return ids[i]
                end
            end
            return nil
        end
        return CludesUI.ForeverClassSpec(nil, mod.ThresholdEntriesMention, entries)
    end

    -- The resolver runs per frame, so the pick is memoized per list on ns.CfgGen
    -- (BuildBars / ApplyAll bump it on every option edit and on profile, spec,
    -- talent and form changes; a profile change is also what moves which list is
    -- the Class Resource one) and the card count; InvalidateThresholdCaches clears
    -- it together with the talent-gate cache it reads.
    function mod.ForeverThresholdSpec(entries)
        local memo = mod._fvThrPick
        if not memo then
            memo = setmetatable({}, { __mode = "k" })
            mod._fvThrPick = memo
        end
        local m = memo[entries]
        if m and m.gen == mod.CfgGen and m.n == #entries then
            return m.sid
        end
        if not m then
            m = {}
            memo[entries] = m
        end
        m.gen, m.n = mod.CfgGen, #entries
        m.sid = mod.ForeverThresholdPick(entries)
        return m.sid
    end

    ResolveThresholdSpecEntry = function(sp)
        local entries = sp.thresholdSpecs
        if not entries or #entries == 0 then
            return nil
        end

        -- Form-specific mode (druid power bar): the entry matching the current
        -- form wins. Moonkin (31/35) is checked directly by form ID since it shares
        -- Mana with Caster on GetPrimaryPowerType() and would otherwise collide
        -- with the "mana" bucket. A form with no entry falls through to the spec
        -- scan (form entries carry no specIDs, so the scan never picks one).
        if sp.thresholdFormMode then
            local form = GetShapeshiftFormID()
            local key = (form == 31 or form == 35) and "moonkin" or FORM_THRESHOLD_KEY[GetPrimaryPowerType()]
            if key then
                for _, record in ipairs(entries) do
                    if record.formKey == key then
                        return record
                    end
                end
            end
        end

        local specID = ResolveSpecIDCached()
        -- WoW Forever: the class counts as each of its retail specs, so the scan
        -- runs as the spec ns.ForeverThresholdSpec picks (none named by a live
        -- card: the class's first spec, or no spec for a Druid's Class Resource,
        -- either way leaving the All Specs tiers 3 and 4).
        if CludesUI.IS_FOREVER then
            specID = mod.ForeverThresholdSpec(entries)
        end
        if not specID and not CludesUI.IS_FOREVER then
            return nil
        end

        local specPlain, allTalent, allPlain
        for _, record in ipairs(entries) do
            if record.specIDs then
                local matchSpec, matchAll = false, false
                for _, spellRef in ipairs(record.specIDs) do
                    if spellRef == specID then
                        matchSpec = true
                    end
                    if spellRef == 0 then
                        matchAll = true
                    end
                end
                if matchSpec or matchAll then
                    local gate = record.talentSpellID
                    if gate then
                        if IsTalentGateActive(gate) then
                            -- spec + active talent gate is the top tier: nothing can
                            -- outrank it, so return as soon as it is found.
                            if matchSpec then
                                return record
                            end
                            allTalent = allTalent or record
                        end
                    -- gated but inactive: skip
                    else
                        if matchSpec then
                            specPlain = specPlain or record
                        else
                            allPlain = allPlain or record
                        end
                    end
                end
            end
        end

        return specPlain or allTalent or allPlain
    end
end -- do (threshold resolution)

-- Expose for options panel
_G._CURB_BAR_TYPE_SPECS = BAR_TYPE_SPECS
_G._CURB_BuildBarTypeSpecMap = BuildBarTypeSpecMap
_G._CURB_ResolveThresholdSpecEntry = ResolveThresholdSpecEntry

-- Per-spec values live in the shared Spec Overrides system, which writes them into
-- these same Simple config tables on spec change. These resolvers stay functions
-- for call-site stability but resolve the Simple config only.
_G._CURB_ResolveHealthCfg = function(profile)
    local p = profile or (ERB and ERB.db and ERB.db.profile)
    return p and p.health
end

_G._CURB_ResolvePowerCfg = function(profile)
    local p = profile or (ERB and ERB.db and ERB.db.profile)
    return p and p.primary
end

_G._CURB_ResolveSecondaryCfg = function(profile)
    local p = profile or (ERB and ERB.db and ERB.db.profile)
    return p and p.secondary
end

-- Always false: the options page overlays keyed off this are permanently dormant.
_G._CURB_CurSpecOverridesSection = function()
    return false
end

-- ColorCurve helper for secret-value-safe bar threshold coloring: a two-point
-- step curve (base color below threshold, threshold color at/above), passed to
-- UnitPowerPercent as the 4th arg so WoW evaluates the secret value C-side and
-- returns a Color object.
local _barColorCurve = nil
local _barColorCurveHash = nil

local function GetBarThresholdCurve(baseR, baseG, baseB, threshR, threshG, threshB, threshPct)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
        return nil
    end

    -- Direct comparison, never a format() hash: UpdatePrimaryBar calls this twice
    -- per power event (~30/sec while casting), so hashing would allocate a string
    -- and do seven float conversions per call, cache hits included -- costlier than
    -- the curve build it guards. _barColorCurveHash holds prior inputs in a reused
    -- table (no new file-scope local).
    local hgt = _barColorCurveHash
    if
        hgt
        and hgt[1] == baseR
        and hgt[2] == baseG
        and hgt[3] == baseB
        and hgt[4] == threshR
        and hgt[5] == threshG
        and hgt[6] == threshB
        and hgt[7] == threshPct
    then
        return _barColorCurve
    end
    if not hgt then
        hgt = {}
        _barColorCurveHash = hgt
    end
    hgt[1], hgt[2], hgt[3] = baseR, baseG, baseB
    hgt[4], hgt[5], hgt[6] = threshR, threshG, threshB
    hgt[7] = threshPct

    local curve = C_CurveUtil.CreateColorCurve()
    local t = math.max(0, math.min(1, threshPct / 100))
    local EPSILON = 0.0001

    -- At or below threshold -> use threshold color
    curve:AddPoint(0.0, CreateColor(threshR, threshG, threshB, 1))

    if t > EPSILON then
        curve:AddPoint(t, CreateColor(threshR, threshG, threshB, 1))
    end

    -- Above threshold -> revert to base bar color
    if t < 1.0 then
        curve:AddPoint(math.min(1.0, t + EPSILON), CreateColor(baseR, baseG, baseB, 1))
    end

    curve:AddPoint(1.0, CreateColor(baseR, baseG, baseB, 1))

    _barColorCurve = curve
    return curve
end

-------------------------------------------------------------------------------
--  Multi-band threshold coloring. Values outside the last band fall back to the
--  fill color (last band "up to 80" -> 81-100 fill; first band "from 20" -> 0-19 fill).
-------------------------------------------------------------------------------
-- sp: base bar table; entry: resolved per-spec threshold entry (may be nil).
-- Returns: enabled(bool), bands(array), mode("percent"|"value"), reverse(bool)
-- reverse false => "up to" (<=), true => "from" (>=)
local function ResolveBandConfig(sp, record)
    local enabled, bands, mode, reverse
    if record then
        enabled = record.multiBandEnabled
        if enabled == nil then
            enabled = sp.multiBandEnabled
        end
        bands = (record.bands and #record.bands > 0) and record.bands or sp.bands
        mode = record.bandMode or sp.bandMode or "percent"
        reverse = record.bandReverse
        if reverse == nil then
            reverse = sp.bandReverse
        end
    else
        enabled = sp.multiBandEnabled
        bands = sp.bands
        mode = sp.bandMode or "percent"
        reverse = sp.bandReverse
    end
    if not enabled or not bands or #bands == 0 then
        return false
    end
    return true, bands, mode, reverse and true or false
end

-- Find the band whose count range contains `count` (pip resources)
local function FindCountBand(bands, total, reverse)
    if not bands or #bands == 0 then
        return nil
    end
    if reverse then
        for i = #bands, 1, -1 do
            if total >= (bands[i].to or 0) then
                return bands[i]
            end
        end
        return nil
    end
    for i = 1, #bands do
        if total <= (bands[i].to or 0) then
            return bands[i]
        end
    end
    return nil
end

-- Multi-stop step ColorCurve from band fractions. `stops` is ordered
-- { frac=<0..1 upper boundary>, r, g, b, a }. Secret-safe: evaluated C-side by
-- UnitPowerPercent/UnitHealthPercent against the secret value; only boundaries
-- (derived from the clean max) live in Lua. Cache is cacheKey -> {hash, curve},
-- keyed per bar so concurrent multi-band bars don't evict each other. The
-- change-signature is checked BEFORE building stops/curve/CreateColor points,
-- so an unchanged tick allocates nothing.
local _bandCurveCache = {}

-- Build the ordered `stops` (frac space) for a bar-type resource from `bands`.
-- `mode` "percent" -> frac = to/100; "value" -> frac = to/max (max clean for player).
-- Returns a stops array, or nil if no usable bands.
local function BuildBandStops(bands, mode, maxVal)
    if not bands or #bands == 0 then
        return nil
    end
    local stops = {}
    for i = 1, #bands do
        local b = bands[i]
        local frac
        if mode == "value" then
            if not maxVal or maxVal <= 0 then
                return nil
            end
            frac = (b.to or 0) / maxVal
        else
            frac = (b.to or 0) / 100
        end
        stops[i] = { frac = frac, r = b.r or 1, g = b.g or 1, b = b.b or 1, a = b.a or 1 }
    end
    return stops
end

-- cacheKey is a stable per-bar id ("health"/"primary"/"secondary"/"healthpoll").
-- baseR/G/B is the bar's normal fill color. reverse=false (up to) / true (from).
local function GetBarBandCurve(cacheKey, bands, mode, maxVal, baseR, baseG, baseB, reverse)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
        return nil
    end
    if not bands or #bands == 0 then
        return nil
    end

    -- Cheap signature from the raw inputs, before any stops/curve allocation.
    local parts = {}
    for i = 1, #bands do
        local b = bands[i]
        parts[i] = format("%.3f:%.3f,%.3f,%.3f,%.3f", b.to or 0, b.r or 1, b.g or 1, b.b or 1, b.a or 1)
    end
    parts[#parts + 1] = format(
        "|%s|%.3f|%.3f,%.3f,%.3f|%s",
        mode or "",
        maxVal or -1,
        baseR or -1,
        baseG or -1,
        baseB or -1,
        reverse and "r" or ""
    )
    local hash = table.concat(parts, "|")

    local slot = _bandCurveCache[cacheKey]
    if slot and slot.hash == hash then
        return slot.curve
    end
    if not slot then
        slot = {}
        _bandCurveCache[cacheKey] = slot
    end

    local stops = BuildBandStops(bands, mode, maxVal)
    if not stops then
        slot.hash, slot.curve = hash, nil
        return nil
    end

    local curve = C_CurveUtil.CreateColorCurve()
    local EPSILON = 0.0001

    if reverse then
        -- "From" semantics: base fill holds from 0 up to the first boundary, then
        -- each band's color steps in AT its boundary (inclusive) and holds upward.
        local br, backdrop, bb = baseR or 1, baseG or 1, baseB or 1
        curve:AddPoint(0.0, CreateColor(br, backdrop, bb, 1))
        local pr, pg, pb, pa = br, backdrop, bb, 1
        for i = 1, #stops do
            local s = stops[i]
            local frame = math.max(0, math.min(1, s.frac or 0))
            -- hold the previous region's color to just before the boundary, then
            -- switch to this band exactly at the boundary.
            if frame > 0.0 then
                curve:AddPoint(math.max(0.0, frame - EPSILON), CreateColor(pr, pg, pb, pa))
            end
            curve:AddPoint(frame, CreateColor(s.r or 1, s.g or 1, s.b or 1, s.a or 1))
            pr, pg, pb, pa = s.r or 1, s.g or 1, s.b or 1, s.a or 1
        end
        -- Top band holds to the end.
        curve:AddPoint(1.0, CreateColor(pr, pg, pb, pa))
    else
        -- Hold the first band's color from 0 up to its boundary.
        local first = stops[1]
        curve:AddPoint(0.0, CreateColor(first.r or 1, first.g or 1, first.b or 1, first.a or 1))
        for i = 1, #stops do
            local s = stops[i]
            local frame = math.max(0, math.min(1, s.frac or 0))
            curve:AddPoint(frame, CreateColor(s.r or 1, s.g or 1, s.b or 1, s.a or 1))
            local nxt = stops[i + 1]
            if nxt and frame < 1.0 then
                curve:AddPoint(
                    math.min(1.0, frame + EPSILON),
                    CreateColor(nxt.r or 1, nxt.g or 1, nxt.b or 1, nxt.a or 1)
                )
            end
        end
        -- Above the top band: revert to the base fill color
        local last = stops[#stops]
        local lastF = math.max(0, math.min(1, last.frac or 0))
        if baseR and lastF < 1.0 then
            curve:AddPoint(math.min(1.0, lastF + EPSILON), CreateColor(baseR, baseG, baseB, 1))
            curve:AddPoint(1.0, CreateColor(baseR, baseG, baseB, 1))
        else
            curve:AddPoint(1.0, CreateColor(last.r or 1, last.g or 1, last.b or 1, last.a or 1))
        end
    end

    slot.hash, slot.curve = hash, curve
    return curve
end

Inner.BuildBarTypeSpecMap, Inner.FindCountBand = BuildBarTypeSpecMap, FindCountBand
Inner.GetBarBandCurve, Inner.GetBarThresholdCurve = GetBarBandCurve, GetBarThresholdCurve
Inner.ResolveBandConfig, Inner.ResolveThresholdSpecEntry = ResolveBandConfig, ResolveThresholdSpecEntry
-- Expose for the options panel preview, beside _CURB_ResolveThresholdSpecEntry
_G._CURB_ResolveBandConfig, _G._CURB_FindCountBand = ResolveBandConfig, FindCountBand
Inner.broken = false
