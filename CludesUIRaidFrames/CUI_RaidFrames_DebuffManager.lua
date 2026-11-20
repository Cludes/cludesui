if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_RaidFrames_DebuffManager.lua
-- 12.1 Debuff Manager runtime: base-grid record union plus user-added tiles.
--
-- BASE GRID: one container group per enabled filter checkbox, negation-chained so an aura renders in exactly one
-- record wherever expressible. Priority order cc > dispel > raid > raidcombat: token records exclude higher-priority
-- ones via !TOKEN in declaration-fixed filter strings; typed-dispel has no token, excluded instead via
-- excludeDispelTypes (live candidates). Boolean records (boss/role, priority, canapply, nonplayer) negate every
-- enabled token record, so token records own their overlaps and boolean records fill in the rest. Candidate
-- booleans compare exactly in both directions (a false value is a real "not"), so boolean x boolean overlap is
-- partitionable: the boolean records rank Important > Boss > Role > Can Apply > Non-Player, each owning its
-- overlaps with every record ranked below it (see the ownership fold in BuildRecords).
--
-- MATCH ALL (dm.match == "all", All Debuffs off, 2+ show picks): the base show lane builds ONE conjunction record
-- (MatchSpec) instead of the per-category union; nil = Match Any = the union.
--
-- TILES: an "icons" tile CLAIMS a category, moving its record into the tile's own container (own anchor/size/cap)
-- while negation/exclude contributions stay global (negations read the EFFECTIVE set = base checkboxes OR claims),
-- so an aura still renders exactly once. Effect tiles (glow/square/healthcolor/bar) are ADDITIVE single-category
-- signals: no claim, may overlap icon displays by design, one re-filterable slot each (live-settable, no variant
-- churn). Tile containers persist per button (frames never freed); disabled/removed tiles park hidden, and a
-- hidden container unregisters its events (zero cost).
--
-- MATCH ALL INDICATORS (t.match == "all", 2+ show picks, All Debuffs off): a grid tile claims no category; it
-- renders ONE conjunction record and TAKES exactly that set from every other record (the hand-off: each record
-- splits into exact disjoint parts outside the set), so the rest of each picked category stays where it was.
-- Precedence: indicators over the base, more picks over fewer (ties by list order); crowd control stays with its
-- owner unless picked. An effect tile fires one conjunction slot instead of one slot per pick.
--
-- Base records render into the EXISTING per-button debuff container via the existing style/anchor/reload
-- machinery (shared integration sites live in the containers file); legacy preset groups park at 0. Settings live
-- at ns.db.profile.dmDebuff (shared raid/party/extra, absent = off = zero cost), all keys NEW/additive as a
-- nondestructive view over the existing debuff display keys (size/spacing/cap/position); legacy debuffFilter is
-- untouched and resumes control if the manager is disabled.

local _, mod = ...
local CludesUI = _G.CludesUI

local AK -- CludesUI.AuraKit, resolved at first use
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

local TYPED_DEBUFFS = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- Duration-bar frame levels relative to the unit button (BM bar Frame Level modes 1:1).
local BAR_FRAMELVL = {
    behindBorders = 7,   -- below the main border (+8)
    behindText    = 11,  -- below the name/health text carrier (+12)
    medium        = 13,  -- the aura band
    high          = 14,
    highest       = 15,
}

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-------------------------------------------------------------------------------
-- Settings access
-------------------------------------------------------------------------------
local function DM()
    -- Exclude set is internal: only the hardcoded sated/always-hide presets are blacklistable (merged in
    -- BuildRecords). Saved dm.excludeSpellIDs / dm.excludeSeedV keys are inert orphans.
    local profile = mod.db and mod.db.profile
    return profile and profile.dmDebuff
end

-- One-shot v2 filter-model upgrade per profile: checked categories now SUBTRACT from Show All instead of being
-- blocked by it. Old profiles carry add-mode category keys that Show All used to ignore; left alone they would
-- suddenly subtract content. Show All profiles reset every category key (nothing subtracted; cc nil = cc lead/glow group stays
-- on, see BuildRecords); add-mode profiles keep their selection with cc's old nil-means-on default materialized (nil now means unchecked everywhere).
local function EnsureFilterV2(dmCfg)
    if dmCfg.filtersV2 then return end
    dmCfg.filtersV2 = true
    if dmCfg.all ~= false then
        dmCfg.boss, dmCfg.role, dmCfg.priority, dmCfg.raid = nil, nil, nil, nil
        dmCfg.raidcombat, dmCfg.nonplayer, dmCfg.dispel, dmCfg.cc = nil, nil, nil, nil
    else
        dmCfg.cc = (dmCfg.cc ~= false) and true or nil
    end
end

-- One-shot lane split (per profile, after EnsureFilterV2): the base Filters
-- dropdown became two-lane (show/hide), so the single mode-dependent selection
-- splits into dm[cat] (SHOW lane) and dm.neg[cat] (HIDE lane). Show All
-- profiles' checked categories were subtracting -- move them to the hide lane
-- so record synthesis is bit-identical (incl. cc: checked-under-All meant "park
-- the cc group"); add-mode selections already mean SHOW and stay put.
local function EnsureFilterLanes(dmCfg)
    if dmCfg.lanesV1 then return end
    dmCfg.lanesV1 = true
    if dmCfg.all ~= false then
        local negated
        local function Move(category)
            if dmCfg[category] == true then
                negated = negated or {}
                negated[category] = true
                dmCfg[category] = nil
            end
        end
        Move("boss"); Move("role"); Move("priority"); Move("cc")
        Move("raid"); Move("raidcombat"); Move("dispel"); Move("nonplayer")
        if negated then dmCfg.neg = negated end
    end
end

-- One-shot: maps the retired Auras-tab preset onto the manager, runs ONLY
-- while the profile has no dmDebuff yet (a brand-new profile maps nil/"all" preset to the defaults, harmless). No
-- display/style key mapping needed; the base grid reads legacy debuff keys directly (nondestructive view).
local function EnsureMigrated()
    local profile = mod.db and mod.db.profile
    if not profile then return end
    if profile.dmDebuff then
        EnsureFilterV2(profile.dmDebuff)
        EnsureFilterLanes(profile.dmDebuff)
        return
    end
    local preset = profile.debuffFilter
    local dmCfg = { _fromPreset = preset or "default" }
    if preset == "raid" then
        dmCfg.all = false
        dmCfg.raid = true
        dmCfg.raidcombat = true
    elseif preset == "dispellable" then
        dmCfg.all = false
        dmCfg.dispel = true
        dmCfg.dispelMode = "you" -- the by-you token, 1:1 with the preset
    elseif preset == "none" then
        -- No disable concept: "none" = empty base grid (Show All + CC off).
        dmCfg.all = false
        dmCfg.cc = false
    end
    -- The retired dispellable-location split becomes a Dispellable icons tile at the old anchor, riding the
    -- "typed" dispel flavor (it covered exactly the TYPED debuffs, 1:1 parity).
    if preset ~= "none" and (profile.dispellableDebuffLocation or "same") ~= "same" then
        local size = profile.dispellableDebuffSize
        if not size or size <= 0 then size = profile.debuffSize or 18 end
        dmCfg.dispelMode = "typed"
        dmCfg.tiles = { {
            id = 1, enabled = true, type = "icons",
            claim = { dispel = true },
            position = profile.dispellableDebuffLocation,
            growDirection = profile.dispellableDebuffGrowDirection or "CENTER",
            offsetX = profile.dispellableDebuffOffsetX or 0,
            offsetY = profile.dispellableDebuffOffsetY or 0,
            size = size,
            spacing = profile.debuffSpacing or 1,
            cap = profile.debuffCap or 3,
        } }
        dmCfg.nextTileId = 2
    end
    profile.dmDebuff = dmCfg
    EnsureFilterV2(dmCfg)
    EnsureFilterLanes(dmCfg)
end

function mod.DM_Active()
    -- ALWAYS ON: the manager IS the 12.1 debuff system, no disable (an empty grid is expressed via filters); kept
    -- as a function for the containers delegation and as the migration hook. Show All + cc default on for legacy parity.
    EnsureMigrated()
    return true
end

-- Mirrors the containers file's tiny per-button helpers (that file is at its local cap; duplicating two 4-line lookups beats exporting them).
local function SettingsFor(skinData)
    if skinData._isParty then return mod._scaledPartyProxy end
    if skinData._isExtra then return mod._scaledExtraProxy end
    return mod._scaledProfile
end

local function ClassToken(skinData)
    if skinData._isParty then return "party" end
    if skinData._isExtra then return "extra" end
    return "raid"
end

-- Debuff Manager tile sizes live inside dmDebuff rather than as top-level
-- profile keys, so the raid-frame proxy cannot scale them through
-- INDICATOR_SCALE_KEYS. Keep their physical size on the same class-specific
-- scale as the base debuff grid. Snapped to whole physical pixels: styles,
-- flow layouts and row widths all take this one value.
local function EffectiveIconSizeForClass(rawSize, classToken)
    local scale
    if classToken == "party" then
        scale = mod._partyIndicatorScale or 1
    else
        scale = mod._indicatorScale or 1
        if classToken == "extra" then
            scale = scale * (mod._xfExtraRatio or 1)
        end
    end
    return mod.RFC_SnapSize((tonumber(rawSize) or 18) * scale)
end

local function EffectiveIconSize(skinData, rawSize)
    return EffectiveIconSizeForClass(rawSize, ClassToken(skinData))
end

local function StyleKeyFor(skinData)
    return "rf:debuff:" .. ClassToken(skinData)
end

-- The category vocabulary. token = filter-string routing (negatable); cand = candidate-boolean routing (exact in
-- both directions, a false value negates; never identity-gated -- the engine gates only spell-ID candidates).
local CATS = { "boss", "role", "priority", "cc", "raid", "raidcombat", "dispel", "nonplayer",
    -- Less common filters: the PLAYER token, one include map per dispel type, and
    -- the canApplyAura boolean. "From Any Player" is a FLAVOR of nonplayer
    -- (dm.nonplayerMode == "any"), never a category of its own: both sides share
    -- one engine field, so the dropdown keeps them mutually exclusive like the
    -- two dispel flavors.
    "castbyme", "magic", "curse", "poison", "disease", "bleed", "canapply" }
local LESS_CATS = { "castbyme", "magic", "curse", "poison", "disease", "bleed", "canapply" }
-- Per-type dispel categories: engine dispel name + a static single-type include
-- map per category (never mutated; type folds copy on write).
local TYPE_ORDER = { "magic", "curse", "poison", "disease", "bleed" }
local TYPE_CATS = { magic = "Magic", curse = "Curse", poison = "Poison", disease = "Disease", bleed = "Bleed" }
local TYPE_INCLUDE = {}
for category, T in pairs(TYPE_CATS) do TYPE_INCLUDE[category] = { [T] = true } end

-------------------------------------------------------------------------------
-- MATCH ALL (base show lane, dm.match == "all"): every show pick ANDs into ONE
-- record instead of one record per category. Live only with All Debuffs off and
-- 2+ show picks; anything else takes the union path unchanged. A spec is
-- { tok = { TOKEN = true|false }, cf = { field = bool }, inc = set, exc = set,
-- empty = bool }: MatchApply ANDs one category (pos) or its complement, and a
-- contradiction marks the spec empty (it can never match, so nothing builds).
-------------------------------------------------------------------------------
local MATCH_TOKEN = { cc = "CROWD_CONTROL", raid = "RAID", raidcombat = "RAID_IN_COMBAT", castbyme = "PLAYER" }
local MATCH_BOOL = { boss = "isBossAura", role = "isRoleAura", priority = "isPriorityAura", canapply = "canApplyAura" }
local MATCH_TOK_ORDER = { "CROWD_CONTROL", "RAID_PLAYER_DISPELLABLE", "RAID", "RAID_IN_COMBAT", "PLAYER" }

local function MatchOn(baseView)
    if baseView.match ~= "all" or baseView.all ~= false then return false end
    local num = 0
    for i = 1, #CATS do
        if baseView[CATS[i]] == true then
            num = num + 1
            if num >= 2 then return true end
        end
    end
    return false
end

local function MatchCopy(match)
    local copy = { tok = {}, cf = {}, empty = match.empty }
    for k, val in pairs(match.tok) do copy.tok[k] = val end
    for k, val in pairs(match.cf) do copy.cf[k] = val end
    if match.inc then copy.inc = {}; for T in pairs(match.inc) do copy.inc[T] = true end end
    if match.exc then copy.exc = {}; for T in pairs(match.exc) do copy.exc[T] = true end end
    return copy
end

local function MatchSet(match, map, key, val)
    local current = map[key]
    if current ~= nil and current ~= val then match.empty = true end
    map[key] = val
end

-- Dispel types: a positive set intersects the include set (a debuff has one
-- type), a negative set joins the exclude set.
local function MatchTypes(match, set, place)
    if not place then
        match.exc = match.exc or {}
        for T in pairs(set) do match.exc[T] = true end
    elseif match.inc then
        for T in pairs(match.inc) do
            if not set[T] then match.inc[T] = nil end
        end
    else
        match.inc = {}
        for T in pairs(set) do match.inc[T] = true end
    end
end

-- ANDs category `cat` (pos) or its complement onto the spec; the dispel and
-- Non-Player flavors come from the profile table. False = unknown category.
local function MatchApply(match, category, place, dmCfg)
    local tok = MATCH_TOKEN[category]
    if tok then MatchSet(match, match.tok, tok, place) return true end
    local field = MATCH_BOOL[category]
    if field then MatchSet(match, match.cf, field, place) return true end
    if category == "nonplayer" then
        -- Flavor value when shown (false = Non-Player Auras, true = From Any Player), its complement when not.
        MatchSet(match, match.cf, "isFromPlayerOrPlayerPet", place == (dmCfg.nonplayerMode == "any"))
        return true
    end
    if category == "dispel" then
        if dmCfg.dispelMode == "typed" then
            MatchTypes(match, TYPED_DEBUFFS, place)
        else
            MatchSet(match, match.tok, "RAID_PLAYER_DISPELLABLE", place)
        end
        return true
    end
    if TYPE_INCLUDE[category] then MatchTypes(match, TYPE_INCLUDE[category], place) return true end
    return false
end

-- The spec of one show lane (the base's RAW lane, never the effective set, which
-- mixes in claims and effects; or an indicator's own picks): every pick ANDed,
-- dispel-type picks OR'd into one include set (so Magic + Dispels means Magic),
-- the hide lane `neg` as plain vetoes, and every category in `claims` excluded
-- (the claiming indicator keeps rendering it). Returns the spec and the sorted
-- pick list.
local function MatchSpec(show, negated, dmCfg, claimMap)
    local match = { tok = {}, cf = {} }
    local catList, types = {}, nil
    for i = 1, #CATS do
        local category = CATS[i]
        if show[category] == true then
            catList[#catList + 1] = category
            if TYPE_CATS[category] then
                types = types or {}
                types[TYPE_CATS[category]] = true
            end
        end
    end
    if types then MatchTypes(match, types, true) end
    for i = 1, #catList do
        if not TYPE_CATS[catList[i]] then MatchApply(match, catList[i], true, dmCfg) end
    end
    for i = 1, #CATS do
        local category = CATS[i]
        if negated and negated[category] == true then MatchApply(match, category, false, dmCfg) end
        if claimMap and claimMap[category] then MatchApply(match, category, false, dmCfg) end
    end
    table.sort(catList)
    return match, catList
end

-- Resolves a spec into filter tokens + a fresh candidate table, or nil when it
-- can never match.
local function MatchFinish(match)
    if match.empty then return nil end
    -- PLAYER (your casts, pet and vehicle included) is always a player source.
    if match.tok.PLAYER == true and match.cf.isFromPlayerOrPlayerPet == false then return nil end
    -- The merged Boss/Role field (only a record carried into the hand-off has
    -- it) is Boss OR Role, so it contradicts both halves being false.
    local br = match.cf.isBossOrRoleAura
    if br == true and match.cf.isBossAura == false and match.cf.isRoleAura == false then return nil end
    if br == false and (match.cf.isBossAura == true or match.cf.isRoleAura == true) then return nil end
    local castFrame = {}
    for k, val in pairs(match.cf) do castFrame[k] = val end
    if match.inc then
        local included
        for T in pairs(match.inc) do
            if not (match.exc and match.exc[T]) then
                included = included or {}
                included[T] = true
            end
        end
        if not included then return nil end
        castFrame.includeDispelTypes = included
    elseif match.exc and next(match.exc) then
        local exc = {}
        for T in pairs(match.exc) do exc[T] = true end
        castFrame.excludeDispelTypes = exc
    end
    local tokenList = { "HARMFUL" }
    for i = 1, #MATCH_TOK_ORDER do
        local tok = MATCH_TOK_ORDER[i]
        local place = match.tok[tok]
        if place == true then
            tokenList[#tokenList + 1] = tok
        elseif place == false then
            tokenList[#tokenList + 1] = "!" .. tok
        end
    end
    return tokenList, castFrame
end

-- A tile hosts a catch-all record when All Debuffs is checked, or when Has
-- Duration (an AND-modifier) is checked with no claimed categories -- checked
-- alone it acts as the timed catch-all, mirroring the base dropdown.
local function TileCatchAllOn(tileDef)
    if tileDef.all == true then return true end
    if tileDef.hasDuration ~= true then return false end
    if tileDef.claim then
        for _, val in pairs(tileDef.claim) do
            if val then return false end
        end
    end
    return true
end

-- MATCH ALL INDICATORS (t.match == "all", the indicator's All Debuffs off, 2+
-- Show picks; nil = Match Any): a grid indicator renders ONE conjunction record
-- instead of claiming each pick, and takes exactly that set out of every other
-- record (the hand-off at the end of BuildRecords), so the rest of each picked
-- category stays where it was. An effect indicator fires one conjunction slot
-- instead of one slot per pick. One pick keeps the claim path unchanged.
local function TilePicks(tileDef)
    local c, num = tileDef.claim, 0
    if c then
        for i = 1, #CATS do
            if c[CATS[i]] == true then num = num + 1 end
        end
    end
    return num
end

local function TileMatchOn(tileDef)
    return tileDef.match == "all" and tileDef.all ~= true and TilePicks(tileDef) >= 2
end

-- True when a Match All indicator's own lanes can never match together.
local function TileMatchEmpty(tileDef, dmCfg)
    return MatchFinish((MatchSpec(tileDef.claim, tileDef.neg, dmCfg))) == nil
end

-- Hand-off atoms: the set a Match All indicator takes, as AND terms -- the
-- per-type dispel picks as ONE OR'd set (first, as it decides disjointness
-- soonest), every other pick alone, and NOT crowd control while crowd control
-- stays with its own owner (see BuildRecords).
local function MatchAtoms(show, ccNeg)
    local atoms, types = {}, nil
    for i = 1, #CATS do
        local category = CATS[i]
        if show[category] == true then
            local T = TYPE_CATS[category]
            if T then
                types = types or {}
                types[T] = true
            else
                atoms[#atoms + 1] = { cat = category }
            end
        end
    end
    if types then table.insert(atoms, 1, { types = types }) end
    if ccNeg then atoms[#atoms + 1] = { cat = "cc", neg = true } end
    return atoms
end

-- ANDs atom `a` (pos) or its complement onto spec m.
local function MatchAtom(match, a, place, dmCfg)
    if a.types then
        MatchTypes(match, a.types, place)
    else
        MatchApply(match, a.cat, place ~= (a.neg == true), dmCfg)
    end
end

-- A claimed record keeps its overlap with a hidden token category ranked below
-- its own (per-type > dispel > raid > raidcombat > castbyme; a per-type record
-- negates only crowd control), so a base hide of `cat` does not reach a Match
-- All set when one of its picks outranks it.
local TOK_HIDE_RANK = { dispel = 1, raid = 2, raidcombat = 3, castbyme = 4 }
local function TokHideOwned(show, category)
    local rx = TOK_HIDE_RANK[category]
    if not rx then return false end
    for i = 1, #TYPE_ORDER do
        if show[TYPE_ORDER[i]] == true then return true end
    end
    for pc, region in pairs(TOK_HIDE_RANK) do
        if region < rx and show[pc] == true then return true end
    end
    return false
end

-- A record as a spec, the inverse of MatchFinish (candidate fields other than
-- the dispel-type sets ride along untouched). Nil for a token outside the Match
-- vocabulary, which the hand-off then leaves alone.
local MATCH_TOK_KNOWN = {}
for i = 1, #MATCH_TOK_ORDER do MATCH_TOK_KNOWN[MATCH_TOK_ORDER[i]] = true end
local function RecSpec(region)
    local match = { tok = {}, cf = {} }
    local tokenList = region.tokens
    for i = 1, #tokenList do
        local tk = tokenList[i]
        if tk ~= "HARMFUL" then
            local place = tk:sub(1, 1) ~= "!"
            if not place then tk = tk:sub(2) end
            if not MATCH_TOK_KNOWN[tk] then return nil end
            MatchSet(match, match.tok, tk, place)
        end
    end
    for k, val in pairs(region.cand) do
        if k == "includeDispelTypes" then
            match.inc = {}
            for T in pairs(val) do match.inc[T] = true end
        elseif k == "excludeDispelTypes" then
            match.exc = {}
            for T in pairs(val) do match.exc[T] = true end
        else
            match.cf[k] = val
        end
    end
    return match
end

-- Record r minus the conjunction of `atoms`, as exact disjoint parts:
-- r AND NOT a1, r AND a1 AND NOT a2, ... A part is skipped where r already
-- decides its atom, and the remainder inside the set goes to the indicator.
-- Returns nil when r shares nothing with the set (r stays byte-identical),
-- else the part specs (an empty list when r lies wholly inside the set).
local function Carve(region, atoms, dmCfg)
    local current = RecSpec(region)
    if not current then return nil end
    local parts
    for i = 1, #atoms do
        -- What is left of r shares nothing with the rest of the set: it stays whole.
        local rest = MatchCopy(current)
        for jdx = i, #atoms do MatchAtom(rest, atoms[jdx], true, dmCfg) end
        if not MatchFinish(rest) then
            if not parts then return nil end
            parts[#parts + 1] = current
            return parts
        end
        local result = MatchCopy(current)
        MatchAtom(result, atoms[i], false, dmCfg)
        if MatchFinish(result) then
            parts = parts or {}
            parts[#parts + 1] = result
        end
        MatchAtom(current, atoms[i], true, dmCfg)
    end
    return parts or {}
end

-- Fingerprint inputs the record/tile synthesis reads beyond the containers file's DebuffCfgFP (which appends this);
-- a missed key = that option never live-applies. Per-tile style keys VIEW the base debuff style keys (nil = inherit,
-- ZERO migration) via a proxy table shadowing non-nil tile keys, so the style build and its fingerprint both see
-- effective values. Declared ABOVE the config fingerprint, which must flip when overrides change (EnsureTileStyle only runs behind it).
local TILE_STYLE_KEYS = {
    iconZoom = "debuffIconZoom",
    borderSize = "debuffBorderSize", borderColor = "debuffBorderColor",
    borderTexture = "debuffBorderTexture", borderSizePx = "debuffBorderSizePx",
    borderTextureOffset = "debuffBorderTextureOffset", borderTextureOffsetY = "debuffBorderTextureOffsetY",
    borderTextureShiftX = "debuffBorderTextureShiftX", borderTextureShiftY = "debuffBorderTextureShiftY",
    borderDispelTextured = "debuffBorderDispelTextured",
    showSwipe = "debuffShowSwipe", showDurText = "debuffShowDurText",
    durTextColor = "debuffDurTextColor", durTextSize = "debuffDurTextSize",
    durTextOffsetX = "debuffDurTextOffsetX", durTextOffsetY = "debuffDurTextOffsetY",
    showStacks = "debuffShowStacks", stacksTextColor = "debuffStacksTextColor",
    stacksTextSize = "debuffStacksTextSize",
    stacksOffsetX = "debuffStacksOffsetX", stacksOffsetY = "debuffStacksOffsetY",
    hideTooltips = "debuffHideTooltips",
}
local function TileStyleView(s, tileDef)
    local copy
    for tk, bk in pairs(TILE_STYLE_KEYS) do
        if tileDef[tk] ~= nil then
            if not copy then copy = {} end
            copy[bk] = tileDef[tk]
        end
    end
    if not copy then return s end
    if tileDef.borderSize ~= nil or tileDef.borderTexture ~= nil then
        copy.debuffBorderSizePx = tileDef.borderSizePx or false
    end
    return setmetatable(copy, { __index = s })
end
-- The options preview renders tile runs through this same view, so what the
-- page shows for a tile's Display values is what the live frames resolve.
mod.DM_TileStyleView = TileStyleView
-- Sorted fingerprint of one tile's style overrides (part of DM_CfgFP).
local function TileStyleFP(tileDef)
    local copy = {}
    for tk in pairs(TILE_STYLE_KEYS) do
        local tv = tileDef[tk]
        if tv ~= nil then
            if type(tv) == "table" then
                copy[#copy + 1] = tk .. "=" .. string.format("%.2f,%.2f,%.2f,%.2f",
                    tv.r or 0, tv.g or 0, tv.b or 0, tv.a or 1)
            else
                copy[#copy + 1] = tk .. "=" .. tostring(tv)
            end
        end
    end
    if #copy == 0 then return "-" end
    table.sort(copy)
    return table.concat(copy, ";")
end

-- EFFECTS: per-filter blocks (fxList). Each entry: a filters set + optional
-- Icon Glow (glow* prefix keys, CludesUI.Glows.PrefixKeys), Border override (borderSize/
-- borderColor), and Size for matched categories (0/nil = base grid size).
-- ACTIVE = filters checked and at least one payload; FIRST matching block
-- wins per button category. Declared ABOVE the config fingerprint (its caller).
local function FxEntryActive(entry)
    return entry.filters ~= nil and next(entry.filters) ~= nil
        and (((entry.glowType or 0) > 0) or ((entry.borderSize or 0) > 0)
            or ((tonumber(entry.size) or 0) > 0))
end
local function FxListView(entries)
    if not entries then return nil end
    local result
    for i = 1, #entries do
        if FxEntryActive(entries[i]) then
            result = result or {}
            result[#result + 1] = entries[i]
        end
    end
    return result
end
local function FxListFP(entries)
    if not entries or #entries == 0 then return "fx0" end
    local parts = {}
    for i = 1, #entries do
        local entry = entries[i]
        local keyList = {}
        if entry.filters then
            for k, on in pairs(entry.filters) do if on then keyList[#keyList + 1] = k end end
            table.sort(keyList)
        end
        local bc = entry.borderColor or {}
        parts[#parts + 1] = table.concat({
            table.concat(keyList, "+"),
            tostring(entry.glowType or 0), entry.glowClassColor and "cc" or "-",
            mod.RF_GlowClassFP(entry.glowColorMode, entry.glowClassColor),
            string.format("%.2f,%.2f,%.2f", entry.glowR or 1, entry.glowG or 0.776, entry.glowB or 0.376),
            tostring(entry.glowColorMode), tostring(entry.glowLines), tostring(entry.glowThickness),
            tostring(entry.glowSpeed), tostring(entry.glowBackground),
            string.format("%.2f,%.2f,%.2f", entry.glowBackgroundR or 0, entry.glowBackgroundG or 0, entry.glowBackgroundB or 0),
            tostring(entry.borderSize or 0),
            string.format("%.2f,%.2f,%.2f", bc.r or 0, bc.g or 0, bc.b or 0),
            tostring(entry.size or 0),
        }, "|")
    end
    return "fx:" .. table.concat(parts, ";")
end
-- One-time heal: fold a legacy single fxGlow config into fxList.
local function FxHeal(ownerFrame)
    local fg = ownerFrame and ownerFrame.fxGlow
    if fg then
        ownerFrame.fxList = ownerFrame.fxList or {}
        ownerFrame.fxList[#ownerFrame.fxList + 1] = {
            filters = fg.filters or {},
            glowType = fg.type, glowClassColor = fg.classColor,
            glowR = fg.r, glowG = fg.g, glowB = fg.b,
        }
        ownerFrame.fxGlow = nil
    end
end
-- Per-filter Size for a record category: FIRST matching ACTIVE block owns the
-- category outright (same rule as the glow/border applier's DmFxBlockFor, so
-- a later block's Size never reaches an already-matched category). Merged
-- "bossrole" record matches either constituent, like the applier. `cat` may
-- also be a category LIST (a Match All or Icon Effect split record): the
-- first active block matching any of them wins.
local function FxSizeFor(entries, category)
    if not entries then return nil end
    local multi = type(category) == "table"
    for i = 1, #entries do
        local entry = entries[i]
        if FxEntryActive(entry) then
            local frame = entry.filters
            local hit = frame and not multi and (frame[category] or (category == "bossrole" and (frame.boss or frame.role)))
            if frame and multi then
                for jdx = 1, #category do
                    if frame[category[jdx]] then hit = true; break end
                end
            end
            if hit then
                local sz = tonumber(entry.size)
                if sz and sz > 0 then return sz end
                return nil
            end
        end
    end
end

-- Base fx accessors for the containers file (base debuff style build + FP).
function mod.DM_FxList()
    local dmCfg = DM()
    if dmCfg then FxHeal(dmCfg) end
    return FxListView(dmCfg and dmCfg.fxList)
end
function mod.DM_FxFP()
    local dmCfg = DM()
    if dmCfg then FxHeal(dmCfg) end
    return FxListFP(dmCfg and dmCfg.fxList)
end

-------------------------------------------------------------------------------
-- Debuff tooltip modifier ("Shown on Modifier" mode + the Use Modifier cog,
-- p.debuffTooltipModifier: none | shift | control | alt). Style-side the
-- mode renders as plain Shown (native engine tooltips, no button writes);
-- the gating is a MOTION EATER per debuff container: a frame WE own, laid
-- over the container above the engine buttons, motion-only (EnableMouse
-- false, clicks pass through untouched) and CONSUMING motion. While the
-- eater is shown, hover never reaches the aura buttons and no tooltip
-- appears (the eater forwards OnEnter/OnLeave to the unit button, so the
-- frame's own hover behaviour is untouched); holding the configured key hides it. Show/Hide on our own frames
-- stays legal while auras are secret, so this behaves identically under
-- /cuidev, in instanced combat and in the open world -- unlike
-- button-surface writes (SetMouseMotionEnabled), which the engine refuses
-- under secrecy (field-confirmed 2026-08-24; the tooltip frame itself,
-- AuraButtonTooltip, is forbidden + hideFromGlobalEnv, so no alpha/hook
-- lever exists there either). The eater IS a unit button: a named
-- SecureUnitButton sub-button of the unit button (useparent-unit), so
-- targeting, the unit menu, mouseover and click-cast bindings all work on
-- the band natively; the click-cast header wraps its enter/leave (secure,
-- combat-legal) and runs the peek: the hovered eater hides itself while the
-- modifier is held, so hover falls through to the aura button beneath, and
-- re-shows on release -- one macro-conditional check per key edge and no
-- work at all for an unhovered press (see CUI_RaidFrames_ClickCast.lua,
-- tooltip-modifier eaters). Creation, geometry and parking are out-of-combat
-- writes on a protected frame; an in-combat need latches d.rfcBmPending and
-- the regen reload re-runs the ensure. "none" and the other modes cost
-- nothing: eaters park hidden and the header driver is released.
-------------------------------------------------------------------------------
function mod.DM_TipMod()
    local profile = mod.db and mod.db.profile
    local match = profile and profile.debuffTooltipModifier
    if match == "shift" or match == "control" or match == "alt" then return match end
    return "none"
end

-- All live eaters (eater frame -> true), weak-keyed so eaters of released
-- unit buttons drop out with their hosts. Per-container handles live on the
-- unit button's own data table (d.tipModEaters, keyed "base" / tile id).
local tipModEaters = setmetatable({}, { __mode = "k" })

-- Park one eater: hide it and drop the header's peek/hover references to it.
-- Protected frame, so this is an out-of-combat write; callers latch the regen
-- reload otherwise.
local function ParkEater(entry)
    entry._cuiActive = false
    entry:Hide()
    if mod.CC_ReleaseTipEater then mod.CC_ReleaseTipEater(entry) end
end

-- Is any debuff display actually in the "Shown on Modifier" mode? Base row
-- plus enabled grid tiles' overrides (nil override inherits the base).
local function TipModeInUse()
    local profile = mod.db and mod.db.profile
    if not profile then return false end
    if profile.debuffHideTooltips == "modifier" then return true end
    -- The tiles the current spec renders (every bucket), as the apply pass sees them.
    local tiles = mod.DM_ActiveTiles()
    if tiles then
        for i = 1, #tiles do
            local tileDef = tiles[i]
            if tileDef.enabled ~= false and tileDef.hideTooltips == "modifier" then return true end
        end
    end
    return false
end

-- Arm state + the header's peek key. The ensure pass calls this on every
-- containers reload, so login, setting edits and profile switches all land
-- here; RF fully disabled never reloads. A stored key is a no-op outside the
-- "modifier" mode: every eater parks and the header driver is released.
-- Header and eater writes are out-of-combat; in combat the calling button
-- latches the regen reload, which re-enters here.
local tipModArmed = false
-- Key last pushed to the click-cast header; starts DISARMED so a profile
-- without the feature never touches the header at all (zero cost while off).
local tipModKeyApplied = false

-- Feature wanted at all: a key is set AND some debuff display is in the
-- "modifier" mode. The apply pass gates every footprint/ensure write on this.
function mod.DM_TipModWanted()
    return mod.DM_TipMod() ~= "none" and TipModeInUse()
end

function mod.DM_TipModSync(skinData)
    local key = mod.DM_TipMod()
    local wanted = key ~= "none" and TipModeInUse()
    local wantKey = wanted and key or false
    if wanted == tipModArmed and wantKey == tipModKeyApplied then return end
    if InCombatLockdown() then
        if skinData then skinData.rfcBmPending = true end
        return
    end
    tipModArmed = wanted
    if wantKey ~= tipModKeyApplied then
        tipModKeyApplied = wantKey
        if mod.CC_SetTipModKey then mod.CC_SetTipModKey(wantKey or nil) end
    end
    if not wanted then
        for eater in pairs(tipModEaters) do
            if eater._cuiActive then ParkEater(eater) end
        end
    end
end

-- Icon-tile pin: the point on the health frame the tile's flow starts from.
-- Shared by AnchorTileContainer (the container) and the tooltip eater below,
-- so the two can never drift apart. Party Frames kit: grid tiles seat under
-- the kit's debuff row instead (ns.DM_KitTileY), flowing right.
local function TilePin(tileDef, s, skinData)
    local ky = mod.DM_KitTileY(tileDef, s, skinData)
    if ky then
        local _, _, bx = mod.RFC_DebuffPin(s)
        return "TOPLEFT", "TOPLEFT", bx, ky
    end
    local pl = tileDef.position or "top"
    local corner = CORNERS[pl] or "TOP"
    local anchorPoint = corner
    if (tileDef.growDirection or "CENTER") == "CENTER" then
        -- Center only the growth axis on the position point; the vertical
        -- seat stays flush with the anchored edge (see AnchorTileContainer).
        anchorPoint = pl:find("top", 1, true) and "TOP"
            or (pl:find("bottom", 1, true) and "BOTTOM" or "CENTER")
    end
    return anchorPoint, corner, tileDef.offsetX or 0, tileDef.offsetY or 0
end

-- Maximum footprint of a flow display: n cells of `cell` px with `spacing`
-- between them, wrapped every `per` cells (per < 2 = one unbounded line),
-- lines stacked across; `vertical` flips the line axis (columns). Width, height.
local function TipFootprint(num, cell, spacing, per, vertical)
    if not num or num < 1 then return 0, 0 end
    local lineCells, lines = num, 1
    if per and per >= 2 then
        if num > per then lineCells = per end
        lines = math.ceil(num / per)
    end
    local along = lineCells * cell + (lineCells - 1) * spacing
    local across = lines * cell + (lines - 1) * spacing
    if vertical then return across, along end
    return along, across
end

-- Party Frames kit (user 2026-09-22: all debuffs below the frame): each grid
-- tile (icons / square) the apply pass renders seats as its own block under
-- the kit's debuff row, below the base row's maximum footprint and every
-- earlier rendered grid tile's -- the seat is worked out by that pass from
-- the same counts it declares (d.dmTipGeo). Bar and effect tiles keep their
-- own placement. Returns the seat's Y offset on the kit host (X is the base
-- row's), or nil off the kit.
function mod.DM_KitTileY(tileDef, s, skinData)
    if not (skinData and skinData.kit and tileDef and (tileDef.type == "icons" or tileDef.type == "square")) then return nil end
    local tipGeo = skinData.dmTipGeo
    local gt = tipGeo and tipGeo.tiles and tipGeo.tiles[tileDef.id]
    return gt and gt.kitY
end

-- One eater per gated container; after creation only Show/Hide and, on a
-- geometry change, one re-pin ever touch it. Host = the unit button (our
-- frame). The rect is OURS end to end: pinned to the health frame at the
-- container's own pin and sized to the display's maximum footprint from
-- settings (declared caps x largest cell), cut to the unit button's own rect
-- (EaterRect), never anchored to the engine container: the engine lays the
-- icons out around the container's anchor and never resizes the container
-- frame itself (it stays at its 1x1 provisional size; probed live
-- 2026-08-25), so a frame anchored to the container's corners is a 1x1
-- frame nobody can hover (the first field builds: "tooltip always shows").
-- Motion is CONSUMED: SetPropagateMouseMotion(true) is pass-through -- it
-- un-blocks everything beneath, aura buttons included (probed live with a
-- working eater: focus stack = eater + unit button, tooltip still showed).
-- The unit frame's own hover is restored by FORWARDING: the eater's
-- OnEnter/OnLeave call the unit button's handlers with the button as self,
-- so highlight and unit tooltip behave as in every other tooltip mode.
-- Mouseover resolves through the unit button's subtree exactly as it does
-- for the aura buttons themselves.
-- CLICKS pass through: a motion-only frame is still the mouse focus, and a
-- click delivered to a focus frame with clicks disabled is dropped, nothing
-- beneath sees it (field: "clicks dead over the debuff band"). Propagating
-- clicks is the pass-through we want here -- the aura buttons beneath are
-- click-disabled (AuraKit, raid-frame styles), so the click lands on the
-- unit button exactly as it did before the eater existed.
local function ForwardEnter(self)
    local hgt = self:GetParent()
    local frame = hgt and hgt:GetScript("OnEnter")
    if frame then frame(hgt) end
end
local function ForwardLeave(self)
    local hgt = self:GetParent()
    local frame = hgt and hgt:GetScript("OnLeave")
    if frame then frame(hgt) end
end

-- Every write below lands on a PROTECTED frame (creation, geometry, level,
-- show/hide), so the whole apply is out-of-combat: when something actually
-- needs to change in combat the button latches d.rfcBmPending and the regen
-- reload re-runs this ensure. An unchanged eater costs a few compares and
-- never touches the frame.
local tipEaterCount = 0
-- Ensure-pass stamp: a tile eater the current pass did not ensure is parked at its end.
local tipPass = 0

-- A frame point's horizontal and vertical share: 0 = left / bottom edge,
-- 1 = right / top edge, 0.5 = the middle.
local function PointShare(profile)
    local sx, sy = 0.5, 0.5
    if profile:find("LEFT", 1, true) then sx = 0 elseif profile:find("RIGHT", 1, true) then sx = 1 end
    if profile:find("BOTTOM", 1, true) then sy = 0 elseif profile:find("TOP", 1, true) then sy = 1 end
    return sx, sy
end

local function Round2(val) return math.floor(val * 100 + 0.5) / 100 end

-- Where the eater goes: the footprint placed at its pin, kept on the unit
-- button's own rect. The eater is a unit button, so any part of it past that
-- rect would answer hover, clicks and click-cast bindings for this unit over
-- empty space or over a neighbouring frame. Returns the eater's bottom-left
-- offset and size, relative to the pinned corner of the pin host, or (when
-- clipped, hostRel) to the unit button's bottom-left corner, so a clipped edge
-- stays on the button when the pin host resizes; nil when no part of the
-- footprint lies on the unit. Both frames are ours and share one scale. Before
-- either has a readable position the footprint is placed unclipped; every
-- pass measures again.
local function EaterRect(owner, pinHost, anchorPoint, corner, offX, offY, wid, hgt)
    local px, py = PointShare(anchorPoint)
    local x0, y0 = Round2(offX - px * wid), Round2(offY - py * hgt)
    local pl, pb = pinHost:GetLeft(), pinHost:GetBottom()
    local highlight, hb, hr, ht = owner:GetLeft(), owner:GetBottom(), owner:GetRight(), owner:GetTop()
    if not (pl and pb and highlight and hb and hr and ht)
        or CludesUI.IsSecret(pl) or CludesUI.IsSecret(highlight) then
        return x0, y0, wid, hgt
    end
    local pw, ph = pinHost:GetSize()
    local cx, cy = PointShare(corner)
    local ox, oy = pl + cx * pw, pb + cy * ph
    highlight, hr, hb, ht = Round2(highlight - ox), Round2(hr - ox), Round2(hb - oy), Round2(ht - oy)
    local x1, y1 = x0 + wid, y0 + hgt
    if x0 >= highlight and x1 <= hr and y0 >= hb and y1 <= ht then return x0, y0, wid, hgt end
    if x0 < highlight then x0 = highlight end
    if x1 > hr then x1 = hr end
    if y0 < hb then y0 = hb end
    if y1 > ht then y1 = ht end
    if x1 - x0 < 1 or y1 - y0 < 1 then return nil end
    return x0 - highlight, y0 - hb, x1 - x0, y1 - y0, true
end

local function EnsureEater(skinData, slot, owner, boxHolder, isActive, pinHost, anchorPoint, corner, offX, offY, wid, hgt)
    local map = skinData.tipModEaters
    local entry = map and map[slot]
    if not isActive or not pinHost then
        if entry and entry._cuiActive then
            if InCombatLockdown() then skinData.rfcBmPending = true; return end
            ParkEater(entry)
        end
        return
    end
    -- Clamp the footprint to the unit it serves: the settings maximum (cap
    -- per declared group, stacked in rows) can be taller than the frame, and
    -- with a centered or inward pin the excess would sit on the neighbouring
    -- units at a higher level, stealing their hover and clicks for this unit.
    -- Bounds = the smaller of the button and the pin host (both our frames,
    -- settings-sized). Offsets that place icons outside the frame do not
    -- take the eater with them: EaterRect keeps it on the button, and those
    -- icons answer hover as in plain Shown.
    local maxW, maxH = owner:GetSize()
    local pw, ph = pinHost:GetSize()
    if pw and pw > 0 and pw < maxW then maxW = pw end
    if ph and ph > 0 and ph < maxH then maxH = ph end
    if wid > maxW then wid = maxW end
    if hgt > maxH then hgt = maxH end
    local ex, ey, ew, eh, hostRel = EaterRect(owner, pinHost, anchorPoint, corner, offX, offY, wid, hgt)
    if not ex then
        -- No part of the footprint lies on the unit: nothing to gate here.
        if entry and entry._cuiActive then
            if InCombatLockdown() then skinData.rfcBmPending = true; return end
            ParkEater(entry)
        end
        return
    end
    local lvl = (boxHolder:GetFrameLevel() or 1) + 30
    local geoChanged = not entry or entry._cuiRel ~= hostRel or entry._cuiCorner ~= corner
        or entry._cuiOX ~= ex or entry._cuiOY ~= ey or entry._cuiHost ~= pinHost
        or entry._cuiW ~= ew or entry._cuiH ~= eh
    local lvlChanged = not entry or entry._cuiLvl ~= lvl
    local armChanged = not entry or not entry._cuiActive
    if not (geoChanged or lvlChanged or armChanged) then
        entry._cuiContainer = boxHolder
        return
    end
    if InCombatLockdown() then skinData.rfcBmPending = true; return end
    if not entry then
        -- Named: click-cast's frame keybinds route by frame name. Unit from
        -- the parent (useparent-unit) for the action path; the header's enter
        -- wrap also stamps a real "unit" for the engine's mouseover.
        tipEaterCount = tipEaterCount + 1
        entry = CreateFrame("Button", "CUIRFTipEater" .. tipEaterCount, owner, "SecureUnitButtonTemplate")
        entry:RegisterForClicks("AnyUp")
        entry:SetAttribute("useparent-unit", true)
        entry:SetAttribute("cui_tipeater", true)
        -- Native clicks mirror the unit button: left = target, right = the
        -- secure unit menu. Click-cast re-writes these when it is enabled.
        entry:SetAttribute("type1", "target")
        entry:SetAttribute("*type1", "target")
        CludesUI.AttachSecureUnitMenu(entry)
        -- HookScript, not SetScript: the click-cast header wraps these same
        -- script slots securely, and a hook never displaces a wrap. The Lua
        -- side forwards the unit button's own hover (highlight, unit tooltip).
        entry:HookScript("OnEnter", ForwardEnter)
        entry:HookScript("OnLeave", ForwardLeave)
        entry._cuiD = skinData
        if not map then map = {}; skinData.tipModEaters = map end
        map[slot] = entry
        tipModEaters[entry] = true
        if mod.CC_RegisterTipEater then mod.CC_RegisterTipEater(entry) end
    end
    entry._cuiContainer = boxHolder
    if lvlChanged then
        entry._cuiLvl = lvl
        entry:SetFrameLevel(lvl)
    end
    if geoChanged then
        entry._cuiRel, entry._cuiCorner, entry._cuiOX, entry._cuiOY = hostRel, corner, ex, ey
        entry._cuiHost, entry._cuiW, entry._cuiH = pinHost, ew, eh
        entry:ClearAllPoints()
        if hostRel then
            entry:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", ex, ey)
        else
            entry:SetPoint("BOTTOMLEFT", pinHost, corner, ex, ey)
        end
        entry:SetSize(ew, eh)
    end
    if armChanged then
        entry._cuiActive = true
        entry:Show()
    end
end

-- Per-unit ensure, called from the containers reload loop and from the tail
-- of every DM_ApplyDebuffConfig (fresh footprint inputs; tile containers
-- built on the deferred lanes re-enter through that apply): base container
-- plus every rendered grid tile whose effective tooltip mode (own override, else the
-- base mode) is "modifier". Cheap when the feature is off -- a few reads and
-- existing eaters just park hidden.
function mod.DM_TipModEnsure(btnFrame, skinData, cfg)
    mod.DM_TipModSync(skinData)
    -- Off (no key, or no display in the mode): the sync above parked any
    -- eaters on the flip, so there is nothing per button to do -- zero cost.
    if not tipModArmed then return end
    local baseMode = cfg and cfg.debuffHideTooltips
    local health = skinData.rfcHealth
    local pinHost = health and ((mod.RF_AnchorHost and mod.RF_AnchorHost(health, cfg)) or health)
    local tipGeo = skinData.dmTipGeo
    if skinData.rfcDebuffs then
        local isActive = baseMode == "modifier"
        local anchorPoint, corner, offX, offY, wid, hgt
        if isActive and pinHost and mod.RFC_DebuffPin then
            local size, spacing, per, vertical
            anchorPoint, corner, offX, offY, size, spacing, per, vertical = mod.RFC_DebuffPin(cfg)
            local g = tipGeo and tipGeo.base
            wid, hgt = TipFootprint((g and g.n) or (cfg.debuffCap or 3), (g and g.cell) or size,
                spacing, per, vertical)
        end
        EnsureEater(skinData, "base", btnFrame, skinData.rfcDebuffs, isActive and anchorPoint ~= nil,
            pinHost, anchorPoint, corner, offX, offY, wid, hgt)
    end
    tipPass = tipPass + 1
    local hosts = skinData.dmTiles
    if hosts then
        local entries = mod.DM_ActiveTiles()
        if entries then
            for i = 1, #entries do
                local tileDef = entries[i]
                local c = hosts[tileDef.id]
                if c and (tileDef.type == "icons" or tileDef.type == "square") and c._dmType == tileDef.type then
                    local eff = tileDef.hideTooltips
                    if eff == nil then eff = baseMode end
                    -- IsShown: the apply hides a grid tile with no records, so nothing renders under the eater.
                    local isActive = tileDef.enabled ~= false and eff == "modifier" and c:IsShown()
                    local anchorPoint, corner, offX, offY, wid, hgt
                    if isActive and pinHost then
                        anchorPoint, corner, offX, offY = TilePin(tileDef, cfg, skinData)
                        local grow = mod.DM_KitTileY(tileDef, cfg, skinData) and "RIGHT" or (tileDef.growDirection or "CENTER")
                        local g = tipGeo and tipGeo.tiles and tipGeo.tiles[tileDef.id]
                        wid, hgt = TipFootprint((g and g.n) or (tileDef.cap or cfg.debuffCap or 3),
                            (g and g.cell) or EffectiveIconSize(skinData, tileDef.size or 18), tileDef.spacing or 1,
                            tonumber(tileDef.iconsPerRow) or 0, (grow == "UP" or grow == "DOWN"))
                    end
                    EnsureEater(skinData, tileDef.id, btnFrame, c, isActive and anchorPoint ~= nil,
                        pinHost, anchorPoint, corner, offX, offY, wid, hgt)
                    local entry = skinData.tipModEaters and skinData.tipModEaters[tileDef.id]
                    if entry then entry._cuiPass = tipPass end
                end
            end
        end
    end
    -- Tile eaters this pass did not reach (tile deleted, disabled for this spec, or its id now another type) park.
    local map = skinData.tipModEaters
    if map then
        for slot, entry in pairs(map) do
            if slot ~= "base" and entry._cuiActive and entry._cuiPass ~= tipPass then
                if InCombatLockdown() then skinData.rfcBmPending = true else ParkEater(entry) end
            end
        end
    end
end

-- Base Icons view for the CURRENT spec. The base grid lives in All Specs
-- like any indicator there, so a concrete spec can switch it off for itself
-- (ns.DM_SetBaseDisabled): every base-owned input (mode, lanes, duration
-- modifier, base effects) then reads this empty view and no base record is
-- built -- tiles, claims and the shared dispel flavor (always read off the
-- profile table) are untouched. Read-only by construction.
local BASE_OFF_VIEW = { all = false }
local function BaseView(dmCfg)
    if mod.DM_CurrentSpecBaseOff and mod.DM_CurrentSpecBaseOff() then return BASE_OFF_VIEW end
    return dmCfg
end

function mod.DM_CfgFP()
    EnsureMigrated() -- profile switches re-fingerprint before rendering
    local dmCfg = DM() or {}
    FxHeal(dmCfg)
    local baseView = BaseView(dmCfg)
    local prof = mod.db and mod.db.profile
    local negated = baseView.neg
    local parts = {
        "on",
        baseView.all ~= false and 1 or 0, baseView.hasDuration == true and 1 or 0,
        baseView.boss and 1 or 0, baseView.role and 1 or 0,
        baseView.priority and 1 or 0, baseView.cc == true and 1 or 0, baseView.raid and 1 or 0,
        baseView.raidcombat and 1 or 0, baseView.dispel and 1 or 0,
        baseView.nonplayer and 1 or 0,
        -- Hide lane (dm.neg): subtracts in both modes, so every entry is a
        -- record-shape input.
        negated and table.concat({
            negated.boss and 1 or 0, negated.role and 1 or 0, negated.priority and 1 or 0,
            negated.cc and 1 or 0, negated.raid and 1 or 0, negated.raidcombat and 1 or 0,
            negated.dispel and 1 or 0, negated.nonplayer and 1 or 0 }, "") or "-",
        (dmCfg.dispelMode == "typed") and "typed" or "you",
        FxListFP(baseView.fxList), -- base effects force records
        -- Exclude set varies only with the lust-debuff opt-out (hardcoded lists are load-constant).
        (not prof or prof.hideLustDebuff ~= false) and "lx1" or "lx0",
    }
    -- Max Duration joins the fingerprint only when set, so Unlimited profiles
    -- keep a byte-identical print (no re-apply on the update).
    if baseView.maxDurSec then parts[#parts + 1] = "md" .. tostring(baseView.maxDurSec) end
    -- Match All: same only-when-set rule (nil = Match Any).
    if baseView.match == "all" then parts[#parts + 1] = "mA" end
    -- Less common categories (both lanes) and the Non-Player flavor: appended
    -- only when set, same byte-identical rule.
    do
        local lc
        for i = 1, #LESS_CATS do
            local c = LESS_CATS[i]
            if baseView[c] == true then lc = lc or {}; lc[#lc + 1] = c end
            if negated and negated[c] == true then lc = lc or {}; lc[#lc + 1] = "-" .. c end
        end
        if dmCfg.nonplayerMode == "any" then lc = lc or {}; lc[#lc + 1] = "npany" end
        if lc then parts[#parts + 1] = table.concat(lc, "+") end
    end
    -- Fingerprint the ACTIVE union: spec swaps, bucket edits and per-spec
    -- disables all land here, so the containers re-apply exactly when the
    -- rendered tile set changes (edits to buckets other specs own don't).
    local tiles = mod.DM_ActiveTiles()
    if tiles then
        for i = 1, #tiles do
            local tileDef = tiles[i]
            parts[#parts + 1] = table.concat({
                "t", tostring(tileDef.id), tileDef.enabled and 1 or 0, tostring(tileDef.type),
                tostring(tileDef.cat), tostring(tileDef.position), tostring(tileDef.growDirection),
                tostring(tileDef.offsetX), tostring(tileDef.offsetY), tostring(tileDef.size),
                tostring(tileDef.spacing), tostring(tileDef.cap), tostring(tileDef.iconsPerRow),
                tostring(tileDef.width), tostring(tileDef.height),
                tileDef.color and string.format("%.2f,%.2f,%.2f,%.2f",
                    tileDef.color.r or 1, tileDef.color.g or 1, tileDef.color.b or 1, tileDef.color.a or 1) or "-",
                tostring(tileDef.glowType), tostring(tileDef.glowLines), tostring(tileDef.glowThickness),
                tostring(tileDef.glowSpeed), tostring(tileDef.glowColorMode), tostring(tileDef.opacity),
                mod.RF_GlowClassFP(tileDef.glowColorMode),
                tostring(tileDef.glowBackground), tileDef.glowBackgroundColor and string.format("%.2f,%.2f,%.2f",
                    tileDef.glowBackgroundColor.r or 0, tileDef.glowBackgroundColor.g or 0, tileDef.glowBackgroundColor.b or 0) or "-",
                tostring(tileDef.orientation), tostring(tileDef.reverseFill),
                tostring(tileDef.barFullWidth), tostring(tileDef.barFullHeight),
                tostring(tileDef.barColorOpacity), tostring(tileDef.barBgOpacity),
                tostring(tileDef.frameLevel),
                tileDef.barBgColor and string.format("%.2f,%.2f,%.2f",
                    tileDef.barBgColor.r or 0, tileDef.barBgColor.g or 0, tileDef.barBgColor.b or 0) or "-",
                tileDef.claim and table.concat({
                    tileDef.claim.boss and 1 or 0, tileDef.claim.role and 1 or 0,
                    tileDef.claim.priority and 1 or 0, tileDef.claim.cc and 1 or 0,
                    tileDef.claim.raid and 1 or 0, tileDef.claim.raidcombat and 1 or 0,
                    tileDef.claim.dispel and 1 or 0,
                    tileDef.claim.nonplayer and 1 or 0 }, "") or "-",
                -- Tile hide lane + catch-all + duration modifier: all record-shape inputs.
                tileDef.neg and table.concat({
                    tileDef.neg.boss and 1 or 0, tileDef.neg.role and 1 or 0,
                    tileDef.neg.priority and 1 or 0, tileDef.neg.cc and 1 or 0,
                    tileDef.neg.raid and 1 or 0, tileDef.neg.raidcombat and 1 or 0,
                    tileDef.neg.dispel and 1 or 0, tileDef.neg.nonplayer and 1 or 0 }, "") or "-",
                tileDef.all == true and 1 or 0, tileDef.hasDuration == true and 1 or 0,
                TileStyleFP(tileDef),
                FxListFP(tileDef.fxList),
            }, ",")
            if tileDef.maxDurSec then
                parts[#parts] = parts[#parts] .. ",md" .. tostring(tileDef.maxDurSec)
            end
            -- Match All: only-when-set, like the base's mA.
            if tileDef.match == "all" then parts[#parts] = parts[#parts] .. ",mA" end
            for li = 1, #LESS_CATS do
                local c = LESS_CATS[li]
                if tileDef.claim and tileDef.claim[c] then parts[#parts] = parts[#parts] .. "," .. c end
                if tileDef.neg and tileDef.neg[c] == true then parts[#parts] = parts[#parts] .. ",-" .. c end
            end
        end
    end
    return table.concat(parts, ":")
end

-------------------------------------------------------------------------------
-- Record synthesis
-------------------------------------------------------------------------------

-- Claims over a tile union, in its order: claims[cat] = the first enabled
-- Match Any grid indicator that picks cat, claimsAll = the first enabled grid
-- indicator in catch-all state (TileCatchAllOn: All Debuffs checked, or Has
-- Duration alone), matchTiles = the Match All grid indicators (they claim
-- nothing; nil when there are none). Record routing (EffectiveState) and the
-- options page's owner hints (ns.DM_ClaimOwners) both read it.
local function ClaimMap(tiles)
    local claimMap, claimsAll, matchTiles = {}, nil, nil
    if tiles then
        for i = 1, #tiles do
            local tileDef = tiles[i]
            if tileDef.enabled and (tileDef.type == "icons" or tileDef.type == "square") then
                if not claimsAll and TileCatchAllOn(tileDef) then claimsAll = tileDef end
                if TileMatchOn(tileDef) then
                    matchTiles = matchTiles or {}
                    matchTiles[#matchTiles + 1] = tileDef
                elseif tileDef.claim then
                    for c = 1, #CATS do
                        local category = CATS[c]
                        if tileDef.claim[category] and not claimMap[category] then claimMap[category] = tileDef end
                    end
                end
            end
        end
    end
    return claimMap, claimsAll, matchTiles
end

-- Effective enabled flags: a category is "on" if its base checkbox is set OR
-- an enabled icons tile claims it; negations key off THESE (a claimed
-- category must still be excluded from every other record). Also resolves
-- claims[cat] = tile table (first enabled claimer wins). Match All grid tiles
-- claim nothing: they come back as a list instead (nil when there are none).
local function EffectiveState(dmCfg, matchOn)
    -- Every category key is an explicit checkbox (true/nil); cc's base-grid default-on lives in the apply pass's Show All branch, not here.
    -- Show-lane checkboxes are DORMANT while Show All is on (the dropdown dims the
    -- lane and lanes persist across mode flips): a dormant pick must not leak into
    -- the eff-driven negation gates (dispelToken/!RAID/!RAID_IN_COMBAT would strip
    -- content from other records with no record of its own re-adding it). Claims
    -- and fx routing below still force categories on in both modes. Has Duration
    -- is an AND-modifier, never a mode: it does not touch the show lane.
    -- Match All reads the show lane as empty the same way: its picks build the
    -- one conjunction record, never per-category records or negations elsewhere.
    local eff
    if dmCfg.all ~= false or matchOn then
        eff = { cc = false }
    else
        eff = { boss = dmCfg.boss, role = dmCfg.role, priority = dmCfg.priority,
            cc = dmCfg.cc == true, raid = dmCfg.raid, raidcombat = dmCfg.raidcombat, dispel = dmCfg.dispel,
            nonplayer = dmCfg.nonplayer,
            castbyme = dmCfg.castbyme, magic = dmCfg.magic, curse = dmCfg.curse, poison = dmCfg.poison,
            disease = dmCfg.disease, bleed = dmCfg.bleed, canapply = dmCfg.canapply }
    end
    -- The ACTIVE union (all-specs + group buckets + own spec, per-spec
    -- disables applied): claims follow whatever the current spec renders.
    -- claimsAll hosts a tile catch-all record, with the tile's hide lane and
    -- duration modifier folded in by BuildRecords.
    local claimMap, claimsAll, matchTiles = ClaimMap(mod.DM_ActiveTiles())
    for category in pairs(claimMap) do eff[category] = true end
    return eff, claimMap, claimsAll, matchTiles
end

-- Boolean ownership rank, read by the ownership fold in BuildRecords:
-- Important > Boss > Role > Can Apply > Non-Player, the catch-alls last. The
-- merged Boss/Role record ranks as Boss and hands both constituents down.
-- field: the category's candidate boolean (a split below a record takes it).
-- cats: the categories a record's own buttons stamp. npKey/npCats: the
-- Non-Player effect split of a record ranked above Non-Player (its record key
-- and the category list its buttons stamp).
local BOOL_OWN = {
    priority = { rank = 1, cats = { "priority" }, npKey = "prinp", npCats = { "nonplayer", "priority" } },
    boss = { rank = 2, field = "isBossAura", cats = { "boss" }, npKey = "bossnp", npCats = { "nonplayer", "boss" } },
    bossrole = { rank = 2, cats = { "boss", "role" }, npKey = "bossrolenp", npCats = { "nonplayer", "boss", "role" } },
    role = { rank = 3, field = "isRoleAura", cats = { "role" }, npKey = "rolenp", npCats = { "nonplayer", "role" } },
    canapply = { rank = 4, field = "canApplyAura", cats = { "canapply" }, npKey = "canapplynp", npCats = { "nonplayer", "canapply" } },
    nonplayer = { rank = 5, field = "isFromPlayerOrPlayerPet" },
    all = { rank = 6 },
}

-- Builds ALL active records. Each: key, tokens (declaration-fixed filter
-- parts), cand (fresh candidate table), tile (hosting tile table or nil =
-- base), cats (Match All and Icon Effect split records only: the
-- category list stamped on their buttons), match (Match All records),
-- ccLead (the base CC row in record form, see the Match All indicators).
-- Also returns the cc candidate table: while cc is UNCLAIMED the base drives
-- the legacy "cc" group (fixed filter, CC glow style); a claimed cc renders in
-- its tile with the tile style, and the CC glow stays a base-group property.
local function BuildRecords(s, dmCfg)
    -- Base-owned inputs read the current spec's base view (empty when the
    -- spec switched the All Specs base grid off); dm keeps the shared flavor.
    local baseView = BaseView(dmCfg)
    local matchOn = MatchOn(baseView)
    local eff, claimMap, claimsAll, matchTiles = EffectiveState(baseView, matchOn)
    -- EFFECTS routing: per-filter icon effects need their categories as
    -- SEPARATE base records even under Show All (like claims, but rendering in
    -- the base container) so the effect can target exactly those buttons
    -- (stamped d.dmCat). Token categories negate out of the all-record, and
    -- boolean categories leave it through the ownership fold below.
    -- Under Match All effects only PAINT: nothing is forced here, the
    -- conjunction record splits instead (see the Match All block).
    local effectCats = {}
    if not matchOn then
        local fl = baseView.fxList
        if fl then
            for i = 1, #fl do
                local entry = fl[i]
                if FxEntryActive(entry) then
                    for category, on in pairs(entry.filters) do
                        if on then
                            effectCats[category] = true
                            eff[category] = true
                        end
                    end
                end
            end
        end
    end
    local allOn = baseView.all ~= false -- Show All defaults ON (legacy "all" preset parity)
    -- Has Duration is an AND-MODIFIER (user directive 2026-08-16): it rides
    -- every base-owned record via the duration fold at the bottom. The base
    -- catch-all record joins when Show All is on, or when Has Duration is
    -- checked with no show-lane picks (checked alone = every timed debuff).
    local durOn = baseView.hasDuration == true
    local anyShow = baseView.boss == true or baseView.role == true or baseView.priority == true
        or baseView.cc == true or baseView.raid == true or baseView.raidcombat == true
        or baseView.dispel == true or baseView.nonplayer == true
        or baseView.castbyme == true or baseView.magic == true or baseView.curse == true or baseView.poison == true
        or baseView.disease == true or baseView.bleed == true or baseView.canapply == true
    local durAlone = durOn and not allOn and not anyShow
    -- HIDE lane (dm.neg): subtracts in BOTH modes. Token categories negate off
    -- every lower-ranked record (ownership rank cc > dispel > raid > raidcombat
    -- holds for subtraction too -- a higher-ranked shown category keeps its
    -- overlap, same doctrine as cc owning dispellable CC), typed dispels ride
    -- excludeDispelTypes, boolean categories use false-valued candidate booleans
    -- (nonplayer via the complementary TRUE).
    local negated = baseView.neg
    local function NegHas(category) return negated ~= nil and negated[category] == true end
    local sub = allOn and {
        boss = NegHas("boss"), role = NegHas("role"),
        priority = NegHas("priority"), raid = NegHas("raid"),
        raidcombat = NegHas("raidcombat"), dispel = NegHas("dispel"),
        nonplayer = NegHas("nonplayer"), canapply = NegHas("canapply"),
    } or nil
    -- Non-cc records always exclude CROWD_CONTROL under Show All (cc group
    -- renders CC while on, and a subtracted cc -- parked by the apply pass --
    -- must stay hidden everywhere), when cc is effectively on, and when the
    -- hide lane subtracts cc in add mode.
    local ccOn = allOn or (eff.cc and true or false) or NegHas("cc")
    -- Non-Player flavor: the nonplayer category renders isFromPlayerOrPlayerPet
    -- = false ("Non-Player Auras") or = true ("From Any Player"); every fold the
    -- category applies to OTHER records carries the complement.
    local npAny = dmCfg.nonplayerMode == "any"
    local npHideVal = not npAny
    -- Cast By You (PLAYER token) ranks lowest among token categories: it negates
    -- every other token owner, and every non-token record negates !PLAYER while
    -- it is shown or hidden anywhere (same shape as raid/raidcombat).
    local castActive = (eff.castbyme and true or false) or NegHas("castbyme")
    -- Per-type dispel ownership: a type shown as its own record, or hidden, is
    -- excluded from every other record (the typed dispel record loses it from
    -- its include map, everything else gains an exclude entry). Per-type records
    -- negate only crowd control, so they own their type outright.
    local typeEx
    for i = 1, #TYPE_ORDER do
        local category = TYPE_ORDER[i]
        if (eff[category] and (claimMap[category] or effectCats[category] or not allOn)) or NegHas(category) then
            typeEx = typeEx or {}
            typeEx[TYPE_CATS[category]] = true
        end
    end
    -- Copy-on-write type exclusion. Include maps derived from TYPED_DEBUFFS (the
    -- typed dispel record) shrink; a per-type record's own single-type include is
    -- never touched; every other record grows an exclude map. Static vocabulary
    -- tables are never mutated.
    local typedCopies = {}
    local function ExcludeType(castFrame, T)
        local included = castFrame.includeDispelTypes
        if included then
            if (included == TYPED_DEBUFFS or typedCopies[included]) and included[T] then
                local match = {}
                for k, val in pairs(included) do match[k] = val end
                match[T] = nil
                typedCopies[match] = true
                castFrame.includeDispelTypes = match
            end
            return
        end
        local exm = castFrame.excludeDispelTypes
        if exm == TYPED_DEBUFFS or (exm and exm[T]) then return end
        local match = {}
        if exm then for k, val in pairs(exm) do match[k] = val end end
        match[T] = true
        castFrame.excludeDispelTypes = match
    end

    -- Two dispel flavors: "you" = RAID_PLAYER_DISPELLABLE token; "typed" = any dispel
    -- type (candidate include map, not tokenizable, dedup rides excludeDispelTypes instead of a !token).
    -- dispelActive covers the hide lane too: a hidden dispel category emits no
    -- record but its !token / typed exclude must still reach the others.
    local dispelOn = eff.dispel and true or false
    local dispelActive = dispelOn or NegHas("dispel")
    local dispelMode = (dmCfg.dispelMode == "typed") and "typed" or "you"
    local dispelToken = (dispelActive and dispelMode == "you") and "RAID_PLAYER_DISPELLABLE" or nil
    -- Typed exclude applies only while the typed dispel record is really BUILT (claimed, or base without Show All)
    -- or the category is hidden, else Show All excludes debuffs nothing re-adds.
    local typedMap = dispelActive and dispelMode == "typed"
        and ((claimMap.dispel or effectCats.dispel or not allOn or NegHas("dispel")) and true or false)

    -- Internal exclude set: hardcoded sated list (honoring Show Lust Debuff
    -- opt-out) plus the always-hide pair. 68824's never-secret identity-gate
    -- exemption makes these real on friendly units for never-secret spells; a
    -- secret-flagged entry is accepted but inert (engine drops it silently).
    local ex = {}
    if mod.RFC_AlwaysHideDebuffs then
        for ident in pairs(mod.RFC_AlwaysHideDebuffs) do ex[ident] = true end
    end
    local prof = mod.db and mod.db.profile
    if (not prof or prof.hideLustDebuff ~= false) and mod.RFC_SatedDebuffs then
        for ident in pairs(mod.RFC_SatedDebuffs) do ex[ident] = true end
    end

    local function Cand(important, extra)
        local castFrame = extra or {}
        castFrame.excludeSpellIDs = ex
        if typedMap and not castFrame.includeDispelTypes then
            castFrame.excludeDispelTypes = TYPED_DEBUFFS
        end
        -- Per-type ownership folds (see typeEx); a per-type record's own include
        -- map is left alone inside ExcludeType.
        if typeEx then
            for T in pairs(typeEx) do ExcludeType(castFrame, T) end
        end
        -- Add-mode hide lane, boolean categories: false-valued candidate booleans
        -- ride every positive record (never overriding a record's own positive
        -- boolean; the merged bossrole record skips both constituents). Under
        -- Show All the all-record's explicit sub block owns this instead, so
        -- legacy record shapes stay byte-identical.
        if negated and not allOn then
            if negated.boss and castFrame.isBossAura == nil and castFrame.isBossOrRoleAura == nil then castFrame.isBossAura = false end
            if negated.role and castFrame.isRoleAura == nil and castFrame.isBossOrRoleAura == nil then castFrame.isRoleAura = false end
            if negated.priority and castFrame.isPriorityAura == nil then castFrame.isPriorityAura = false end
            if negated.nonplayer and castFrame.isFromPlayerOrPlayerPet == nil then castFrame.isFromPlayerOrPlayerPet = npHideVal end
            if negated.canapply and castFrame.canApplyAura == nil then castFrame.canApplyAura = false end
        end
        return castFrame
    end

    -- The cc group/record owns dispellable crowd control: its candidates must
    -- NOT carry the typed exclude (a magic stun would vanish from both).
    local ccCand = { excludeSpellIDs = ex }

    local records = {}

    local function Neg(tokenList, negCC, negDispel, negRaid)
        if negCC and ccOn then tokenList[#tokenList + 1] = "!CROWD_CONTROL" end
        if negDispel and dispelToken then tokenList[#tokenList + 1] = "!" .. dispelToken end
        if negRaid and (eff.raid or NegHas("raid")) then tokenList[#tokenList + 1] = "!RAID" end
        return tokenList
    end

    -- Show All (or Has Duration alone) short-circuits the BASE union (other base records would be pure duplicates
    -- in one row) but tiles still render their claims; the catch-all record negates claimed TOKEN categories to
    -- stay single-rendered (boolean claims leave it through the ownership fold below). The NegHas terms are
    -- byte-identical under Show All (sub mirrors NegHas) and carry the hide lane when durAlone builds this with
    -- sub nil.
    if allOn or durAlone then
        local tokenList = { "HARMFUL" }
        Neg(tokenList, true,
            ((sub and sub.dispel) or claimMap.dispel or effectCats.dispel or NegHas("dispel")) and true or false,
            ((sub and sub.raid) or claimMap.raid or effectCats.raid or NegHas("raid")) and true or false)
        if (sub and sub.raidcombat) or claimMap.raidcombat or effectCats.raidcombat or NegHas("raidcombat") then tokenList[#tokenList + 1] = "!RAID_IN_COMBAT" end
        if castActive then tokenList[#tokenList + 1] = "!PLAYER" end
        local castFrame = Cand(false)
        -- Subtracted boolean categories (see `sub`); fx-routed keeps its forced base record (effect wins over
        -- subtraction). Under durAlone (add mode) Cand's own hide-lane branch already applied these.
        if sub then
            if sub.boss then castFrame.isBossAura = false end
            if sub.role then castFrame.isRoleAura = false end
            if sub.priority then castFrame.isPriorityAura = false end
            if sub.nonplayer then castFrame.isFromPlayerOrPlayerPet = npHideVal end
            if sub.canapply then castFrame.canApplyAura = false end
        end
        records[#records + 1] = { key = "all", tokens = tokenList, cand = castFrame }
    end

    -- Claimed crowd control: base normally rides the legacy cc group, but a claiming tile hosts cc as a normal
    -- record (fresh candidate table, NEVER the typed exclude -- see ccCand; tile style, CC glow stays base-only).
    if eff.cc and claimMap.cc then
        records[#records + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex }, tile = claimMap.cc }
    end

    -- Sized base crowd control: Icon Effects Size cannot resize the legacy "cc" group (group->style binding fixed
    -- at declare), so cc becomes a base record variant carrying the CC-glow style; apply pass parks the legacy group while this record exists.
    if eff.cc and not claimMap.cc and FxSizeFor(baseView.fxList, "cc") then
        records[#records + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex } }
    end

    -- Match All indicators in hand-off precedence: more AND terms first (the
    -- more specific set; the dispel-type picks OR into ONE term, so an extra
    -- type widens a set and never ranks it higher), ties by list order. Each
    -- keeps the atoms of the set it takes -- NOT crowd control unless it picks
    -- Crowd Control, which otherwise stays with its owner like it does for
    -- every indicator; a set that can never match takes nothing.
    local matchSets
    if matchTiles then
        local sequence, picks = {}, {}
        for i = 1, #matchTiles do
            local tileDef = matchTiles[i]
            sequence[tileDef], picks[tileDef] = i, #MatchAtoms(tileDef.claim, false)
        end
        table.sort(matchTiles, function(lhs, rhs)
            if picks[lhs] ~= picks[rhs] then return picks[lhs] > picks[rhs] end
            return sequence[lhs] < sequence[rhs]
        end)
        for i = 1, #matchTiles do
            local tileDef = matchTiles[i]
            local atoms = MatchAtoms(tileDef.claim, ccOn and tileDef.claim.cc ~= true)
            local match = { tok = {}, cf = {} }
            for jdx = 1, #atoms do MatchAtom(match, atoms[jdx], true, dmCfg) end
            if MatchFinish(match) then
                matchSets = matchSets or {}
                matchSets[#matchSets + 1] = { tile = tileDef, atoms = atoms }
            end
        end
    end

    -- A Match All indicator that picks Crowd Control takes its matching crowd
    -- control out of the base CC row, which needs the row in record form (the
    -- legacy "cc" group's filter is declaration-fixed): the record the sized path
    -- builds, bound to the row's own CC-glow style and leading the row (ccLead).
    if matchSets and not claimMap.cc and not (eff.cc and FxSizeFor(baseView.fxList, "cc")) then
        local ccRow = (allOn and not NegHas("cc")) or (not allOn and baseView.cc == true and not matchOn)
            or effectCats.cc == true
        if ccRow then
            for i = 1, #matchSets do
                if matchSets[i].tile.claim.cc == true then
                    records[#records + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
                        cand = { excludeSpellIDs = ex }, ccLead = true }
                    break
                end
            end
        end
    end

    -- Category records: skipped in base when Show All covers them, always built for a claiming tile.
    if dispelOn and (claimMap.dispel or effectCats.dispel or not allOn) then
        local tokenList = { "HARMFUL" }
        if dispelToken then tokenList[#tokenList + 1] = dispelToken end
        Neg(tokenList, true, false, false)
        local castFrame
        if typedMap then
            castFrame = Cand(false, { includeDispelTypes = TYPED_DEBUFFS })
        else
            castFrame = Cand(false)
        end
        records[#records + 1] = { key = "dispel", tokens = tokenList, cand = castFrame, tile = claimMap.dispel }
    end
    if eff.raid and (claimMap.raid or effectCats.raid or not allOn) then
        records[#records + 1] = { key = "raid",
            tokens = Neg({ "HARMFUL", "RAID" }, true, true, false),
            cand = Cand(false), tile = claimMap.raid }
    end
    if eff.raidcombat and (claimMap.raidcombat or effectCats.raidcombat or not allOn) then
        local tokenList = Neg({ "HARMFUL", "RAID_IN_COMBAT" }, true, true, true)
        records[#records + 1] = { key = "raidcombat", tokens = tokenList,
            cand = Cand(false), tile = claimMap.raidcombat }
    end

    local function BoolTokens()
        local tokenList = Neg({ "HARMFUL" }, true, true, true)
        if eff.raidcombat or NegHas("raidcombat") then tokenList[#tokenList + 1] = "!RAID_IN_COMBAT" end
        if castActive then tokenList[#tokenList + 1] = "!PLAYER" end
        return tokenList
    end
    -- Cast By You: token record, lowest token rank (negates every other token
    -- owner; per-type dispel ownership reaches it through Cand's type folds).
    if eff.castbyme and (claimMap.castbyme or effectCats.castbyme or not allOn) then
        local tokenList = Neg({ "HARMFUL", "PLAYER" }, true, true, true)
        if eff.raidcombat or NegHas("raidcombat") then tokenList[#tokenList + 1] = "!RAID_IN_COMBAT" end
        records[#records + 1] = { key = "castbyme", tokens = tokenList, cand = Cand(false), tile = claimMap.castbyme }
    end
    -- Per-type dispels: one include-map record per shown type. Only crowd
    -- control is negated (cc owns every overlap); every other record excludes
    -- the type through typeEx, so each record owns its type outright.
    for i = 1, #TYPE_ORDER do
        local category = TYPE_ORDER[i]
        if eff[category] and (claimMap[category] or effectCats[category] or not allOn) then
            records[#records + 1] = { key = category, tokens = Neg({ "HARMFUL" }, true, false, false),
                cand = Cand(false, { includeDispelTypes = TYPE_INCLUDE[category] }), tile = claimMap[category] }
        end
    end
    -- Boss/role merge into one record only when they route to the SAME place; split claims build separate records.
    local bossTile, roleTile = claimMap.boss, claimMap.role
    local bossOn = eff.boss and (bossTile or effectCats.boss or not allOn)
    local roleOn = eff.role and (roleTile or effectCats.role or not allOn)
    if bossOn and roleOn and bossTile == roleTile then
        records[#records + 1] = { key = "bossrole", tokens = BoolTokens(),
            cand = Cand(true, { isBossOrRoleAura = true }), tile = bossTile }
    else
        if bossOn then
            records[#records + 1] = { key = "boss", tokens = BoolTokens(),
                cand = Cand(true, { isBossAura = true }), tile = bossTile }
        end
        if roleOn then
            records[#records + 1] = { key = "role", tokens = BoolTokens(),
                cand = Cand(true, { isRoleAura = true }), tile = roleTile }
        end
    end
    if eff.priority and (claimMap.priority or effectCats.priority or not allOn) then
        records[#records + 1] = { key = "priority", tokens = BoolTokens(),
            cand = Cand(true, { isPriorityAura = true }), tile = claimMap.priority }
    end
    -- Can Apply Aura: boolean record (debuffs the player's own class can apply),
    -- same shape and overlap doctrine as the other boolean categories.
    if eff.canapply and (claimMap.canapply or effectCats.canapply or not allOn) then
        records[#records + 1] = { key = "canapply", tokens = BoolTokens(),
            cand = Cand(true, { canApplyAura = true }), tile = claimMap.canapply }
    end

    -- Non-Player Auras: boolean record (isFromPlayerOrPlayerPet = false -- debuffs not caused by ANY player or
    -- player pet, engine-evaluated; a !PLAYER token would exclude only YOUR casts, never other players' Sated/Forbearance noise). Full
    -- token negation set keeps token categories owning their overlaps; Important, Boss, Role and Can Apply own
    -- theirs through the ownership fold below. Pure subset of the all-record
    -- under Show All, so the base skips it there; a claiming tile or a per-filter effect still forces it (same
    -- routing as the other boolean categories).
    if eff.nonplayer and (claimMap.nonplayer or effectCats.nonplayer or not allOn) then
        records[#records + 1] = { key = "nonplayer", tokens = BoolTokens(),
            cand = Cand(false, { isFromPlayerOrPlayerPet = npAny }), tile = claimMap.nonplayer }
    end

    -- MATCH ALL: ONE conjunction record per Match All set, hosted by `tile` (nil =
    -- the base, from its raw show lane, MatchSpec). Icon Effects (the owner's
    -- own list) only PAINT here: a block on a category inside the set paints
    -- the whole group (its stamped category list matches the block); a block on
    -- a category X outside the set splits the rest into (set AND X, painted) and
    -- (set AND NOT X), in block order, until a block reaches inside the set.
    -- A part that can never match is skipped, so a hidden or claimed X paints
    -- nothing (Hide beats an effect). Exact complements (every category, the
    -- boolean ones included, has an exact opposite): no debuff lands in two
    -- parts. A set that can never match builds nothing (ns.DM_MatchEmpty and
    -- ns.DM_TileMatchEmpty are the options warnings' tests).
    local function EmitMatch(rest, catList, fl, tile)
        local restT, restC = MatchFinish(rest)
        if restT and fl then
            local inSet, split = {}, {}
            for i = 1, #catList do inSet[catList[i]] = true end
            for i = 1, #fl do
                local entry = fl[i]
                if FxEntryActive(entry) then
                    local xs, inside = {}, false
                    for category, on in pairs(entry.filters) do
                        if on then
                            if inSet[category] then inside = true end
                            xs[#xs + 1] = category
                        end
                    end
                    if inside then break end
                    table.sort(xs)
                    for k = 1, #xs do
                        local X = xs[k]
                        if restT and not split[X] then
                            split[X] = true
                            local place = MatchCopy(rest)
                            if MatchApply(place, X, true, dmCfg) then
                                local pT, pC = MatchFinish(place)
                                if pT then
                                    local pcats = { X }
                                    for c = 1, #catList do pcats[#pcats + 1] = catList[c] end
                                    table.sort(pcats)
                                    pC.excludeSpellIDs = ex
                                    records[#records + 1] = { key = "match:" .. table.concat(pcats, "+"),
                                        tokens = pT, cand = pC, cats = pcats, tile = tile, match = true }
                                    local negm = MatchCopy(rest)
                                    MatchApply(negm, X, false, dmCfg)
                                    rest = negm
                                    restT, restC = MatchFinish(negm)
                                end
                            end
                        end
                    end
                    if not restT then break end
                end
            end
        end
        if restT then
            restC.excludeSpellIDs = ex
            records[#records + 1] = { key = "match:" .. table.concat(catList, "+"),
                tokens = restT, cand = restC, cats = catList, tile = tile, match = true }
        end
    end
    if matchOn then
        local rest, catList = MatchSpec(baseView, baseView.neg, dmCfg, claimMap)
        EmitMatch(rest, catList, baseView.fxList, nil)
    end

    -- Match All indicators: each renders its set in its own container with its
    -- own hide lane and Icon Effects, plus the base hide lane wherever that
    -- reaches a claiming indicator's records today: dispel-type categories
    -- always, token categories no pick outranks (TokHideOwned), boolean ones off
    -- All Debuffs, and nothing at all on a set that picks Crowd Control (cc
    -- records take no folds) -- never on a category the indicator picks, and
    -- never where it would empty the picks (a pick beats a hide, as a claim's
    -- own filter does). Crowd control stays out unless picked (see matchSets).
    -- Whatever the indicator's own hide lane and Has Duration drop from its set
    -- shows nowhere, the claims policy.
    if matchTiles then
        for i = 1, #matchTiles do
            local tileDef = matchTiles[i]
            local match, catList = MatchSpec(tileDef.claim, tileDef.neg, dmCfg)
            if ccOn and tileDef.claim.cc ~= true then MatchApply(match, "cc", false, dmCfg) end
            if negated and tileDef.claim.cc ~= true then
                for c = 1, #CATS do
                    local category = CATS[c]
                    if negated[category] == true and category ~= "cc" and tileDef.claim[category] ~= true
                        and not (allOn and (MATCH_BOOL[category] or category == "nonplayer"))
                        and not TokHideOwned(tileDef.claim, category) then
                        local try = MatchCopy(match)
                        MatchApply(try, category, false, dmCfg)
                        if MatchFinish(try) then match = try end
                    end
                end
            end
            EmitMatch(match, catList, tileDef.fxList, tileDef)
        end
    end

    -- Tile-hosted catch-all: the first enabled grid tile in catch-all state
    -- (All Debuffs checked, or Has Duration alone -- the duration fold below
    -- narrows it) renders its own broad record. Independent of the base record
    -- on purpose: negating "everything" out of the base would empty it, so
    -- overlap with a broad base is accepted (a deliberate user config). BoolTokens
    -- negates token categories rendered or hidden elsewhere, and the ownership
    -- fold below drops every boolean record's content, so categorized
    -- content stays single-rendered. Under Match All the base conjunction is
    -- NOT negated here (NOT(A AND B) is no single filter), so its content also
    -- shows in this indicator (accepted, like a broad base).
    if claimsAll then
        local castFrame = Cand(false)
        if sub then
            if sub.boss then castFrame.isBossAura = false end
            if sub.role then castFrame.isRoleAura = false end
            if sub.priority then castFrame.isPriorityAura = false end
            if sub.nonplayer then castFrame.isFromPlayerOrPlayerPet = npHideVal end
            if sub.canapply then castFrame.canApplyAura = false end
        end
        records[#records + 1] = { key = "all", tokens = BoolTokens(),
            cand = castFrame, tile = claimsAll }
    end

    -- Dead-corpse catch-all: ONE indicator showing Non-Player Auras drops ALL its
    -- filters while its unit is dead and shows every debuff instead (persist-through-
    -- death NPC debuffs matter for res decisions). Compiled as an extra token-only
    -- record (HARMFUL + hygiene excludes; token-only on purpose -- candidate flags
    -- don't stream on dead units) parked at 0; the apply pass wires the death-edge
    -- swap (park the indicator's normal records, unpark this). Qualifier = first
    -- enabled ICONS tile whose show lane includes nonplayer, else the base grid's
    -- nonplayer checkbox; suppressed entirely when a literal All Debuffs indicator
    -- exists (base Show All or a grid tile's All bit) -- everything already shows.
    do
        local deadTile, deadBlocked
        if allOn then deadBlocked = true end
        local dtiles = mod.DM_ActiveTiles()
        if dtiles then
            for i = 1, #dtiles do
                local tileDef = dtiles[i]
                if tileDef.enabled and (tileDef.type == "icons" or tileDef.type == "square") and tileDef.all == true then
                    deadBlocked = true
                end
                if not deadTile and tileDef.enabled and tileDef.type == "icons" and tileDef.claim and tileDef.claim.nonplayer then
                    deadTile = tileDef
                end
            end
        end
        -- The From Any Player flavor is not "Non-Player Auras": no corpse swap.
        if not deadBlocked and not npAny and (deadTile or baseView.nonplayer == true) then
            records[#records + 1] = { key = "npdead", tokens = { "HARMFUL" },
                cand = { excludeSpellIDs = ex }, deadOnly = true, tile = deadTile }
        end
    end

    -- Ownership fold: one linear owner order over the boolean records (BOOL_OWN:
    -- Important > Boss > Role > Can Apply > Non-Player, catch-alls last).
    -- Candidate booleans compare exactly, so false values partition in and out
    -- of restriction. While a boolean record exists anywhere (base show lane, a
    -- claiming indicator or an Icon Effect), every record ranked below it drops
    -- its content (a false value; Non-Player's complement for the catch-alls),
    -- so a debuff lands in the highest-ranked record it matches and both
    -- catch-alls (the base and the indicator All Debuffs records) keep only
    -- what no boolean record shows. A record takes only HIGHER ranks, and only
    -- from a higher record that does not already hide its category, so the
    -- order never cycles. Only empty fields are set, so a record's own filter
    -- and the hide lanes' folds (same values) always win; cc, npdead and Match
    -- All records take no fold. A setup without two of these records side by
    -- side builds byte-identical payloads, and a changed payload declares its
    -- new variant once through the usual missing-group path.
    do
        local hasPri, hasBoss, hasRole, hasCan, hasNp = false, false, false, false, false
        local byCat = {}
        for i = 1, #records do
            local record = records[i]
            local k = record.key
            if k == "priority" then hasPri = true; byCat.priority = record
            elseif k == "boss" then hasBoss = true; byCat.boss = record
            elseif k == "role" then hasRole = true; byCat.role = record
            elseif k == "bossrole" then hasBoss = true; hasRole = true; byCat.boss = record; byCat.role = record
            elseif k == "canapply" then hasCan = true; byCat.canapply = record
            elseif k == "nonplayer" then hasNp = true end
        end
        -- True when record h already keeps category c out: the base add-mode
        -- hide lane Cand folded in, or its indicator's hide lane (applied below).
        local function Hides(hgt, c)
            local tn = hgt.tile and hgt.tile.neg
            if tn and tn[c] == true then return true end
            if c == "nonplayer" then return hgt.cand.isFromPlayerOrPlayerPet == npHideVal end
            return hgt.cand[MATCH_BOOL[c]] == false
        end
        -- A lower record keyed lk takes h's NOT only while h can show part of
        -- lk's content: an h that already hides lk's category shares none of it,
        -- and folding it too would drop that overlap from both. A merged
        -- Boss/Role record with either half hidden keeps its overlap.
        local function Owns(hgt, lk)
            if not hgt then return false end
            if lk == "all" then return true end
            if lk == "bossrole" then return not (Hides(hgt, "boss") or Hides(hgt, "role")) end
            return not Hides(hgt, lk)
        end
        if hasPri or hasBoss or hasRole or hasCan or hasNp then
            for i = 1, #records do
                local record = records[i]
                local own = BOOL_OWN[record.key]
                if own then
                    local castFrame, rank, k = record.cand, own.rank, record.key
                    if rank > 1 and castFrame.isPriorityAura == nil and Owns(byCat.priority, k) then castFrame.isPriorityAura = false end
                    if rank > 2 and castFrame.isBossAura == nil and Owns(byCat.boss, k) then castFrame.isBossAura = false end
                    if rank > 3 and castFrame.isRoleAura == nil and Owns(byCat.role, k) then castFrame.isRoleAura = false end
                    if rank > 4 and castFrame.canApplyAura == nil and Owns(byCat.canapply, k) then castFrame.canApplyAura = false end
                    if rank > 5 and hasNp and castFrame.isFromPlayerOrPlayerPet == nil then
                        castFrame.isFromPlayerOrPlayerPet = npHideVal
                    end
                end
            end
        end
        -- An Icon Effect on a lower-ranked boolean keeps painting what the fold
        -- above moved out of that category's group: each record ranked above it
        -- walks its OWN owner list in block order, stops at a block that already
        -- paints its own category (first matching block wins), and splits its
        -- remainder into an exact complement pair per lower category a block
        -- names. The matching half stamps both categories (the Non-Player half
        -- keeps BOOL_OWN npKey/npCats); the rest keeps its key. A merged
        -- Boss/Role group paints both constituents, so a split below it takes
        -- both. Setups without such a block build byte-identical records.
        local has = { boss = hasBoss, role = hasRole, canapply = hasCan, nonplayer = hasNp }
        local merged = byCat.boss ~= nil and byCat.boss == byCat.role
        local n0 = #records
        for i = 1, n0 do
            local record = records[i]
            local own = BOOL_OWN[record.key]
            local fl
            if own and own.cats then
                if record.tile then fl = record.tile.fxList else fl = baseView.fxList end
            end
            if fl then
                local castFrame, tn, done = record.cand, record.tile and record.tile.neg, {}
                for jdx = 1, #fl do
                    local entry = fl[jdx]
                    if FxEntryActive(entry) then
                        local frame, inside = entry.filters, false
                        for c = 1, #own.cats do
                            if frame[own.cats[c]] then inside = true end
                        end
                        if inside then break end
                        local xs = {}
                        for category, on in pairs(frame) do
                            if on then xs[#xs + 1] = category end
                        end
                        if merged and (frame.boss or frame.role) then
                            if not frame.boss then xs[#xs + 1] = "boss" end
                            if not frame.role then xs[#xs + 1] = "role" end
                        end
                        table.sort(xs)
                        for posX = 1, #xs do
                            local X = xs[posX]
                            local xo = BOOL_OWN[X]
                            if xo and xo.field and xo.rank > own.rank and has[X] and not done[X]
                                and castFrame[xo.field] == nil and not (tn and tn[X] == true) then
                                done[X] = true
                                local castCopy, tokenCopy = {}, {}
                                for kk, val in pairs(castFrame) do castCopy[kk] = val end
                                for kk = 1, #record.tokens do tokenCopy[kk] = record.tokens[kk] end
                                local key, pcats = own.npKey, own.npCats
                                if X == "nonplayer" then
                                    castCopy[xo.field], castFrame[xo.field] = npAny, npHideVal
                                else
                                    castCopy[xo.field], castFrame[xo.field] = true, false
                                    key = record.key .. "+" .. X
                                    pcats = { X }
                                    if merged and (X == "boss" or X == "role") then
                                        pcats[2] = (X == "boss") and "role" or "boss"
                                    end
                                    for c = 1, #own.cats do pcats[#pcats + 1] = own.cats[c] end
                                end
                                records[#records + 1] = { key = key, tokens = tokenCopy, cand = castCopy,
                                    tile = record.tile, cats = pcats }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Tile HIDE lanes: a hosting tile's hide lane folds into every record it
    -- hosts, additive to the base lane (which already rode Cand/sub above).
    -- Token categories negate via tokens, typed dispels via the exclude map,
    -- boolean categories via false-valued candidate booleans -- always
    -- deferring to a record's own positive filter (own-category hides are
    -- UI-locked; the key checks here are the engine-side guard). The cc
    -- record takes NO folds at all (base parity: ccCand bypasses Cand, so the
    -- base hide lane never touches cc content either -- cc owns its overlaps,
    -- and a magic stun must never vanish from both cc and dispel).
    local function HasTok(tokenList, tok)
        for i = 1, #tokenList do if tokenList[i] == tok then return true end end
        return false
    end
    for i = 1, #records do
        local record = records[i]
        local tn = record.tile and record.tile.neg
        -- npdead ignores ALL filters by definition: no hide-lane folds, no duration cap.
        -- Match All records already carry their indicator's hide lane (MatchSpec).
        if tn and record.key ~= "cc" and record.key ~= "npdead" and not record.match then
            local tokenList, castFrame, key = record.tokens, record.cand, record.key
            if tn.cc == true and not HasTok(tokenList, "!CROWD_CONTROL") then
                tokenList[#tokenList + 1] = "!CROWD_CONTROL"
            end
            if tn.dispel == true and key ~= "dispel" then
                if dispelMode == "typed" then
                    if not castFrame.includeDispelTypes then castFrame.excludeDispelTypes = TYPED_DEBUFFS end
                elseif not HasTok(tokenList, "!RAID_PLAYER_DISPELLABLE") then
                    tokenList[#tokenList + 1] = "!RAID_PLAYER_DISPELLABLE"
                end
            end
            if tn.raid == true and key ~= "raid" and not HasTok(tokenList, "!RAID") then
                tokenList[#tokenList + 1] = "!RAID"
            end
            if tn.raidcombat == true and key ~= "raidcombat" and not HasTok(tokenList, "!RAID_IN_COMBAT") then
                tokenList[#tokenList + 1] = "!RAID_IN_COMBAT"
            end
            if tn.boss == true and castFrame.isBossAura == nil and castFrame.isBossOrRoleAura == nil then castFrame.isBossAura = false end
            if tn.role == true and castFrame.isRoleAura == nil and castFrame.isBossOrRoleAura == nil then castFrame.isRoleAura = false end
            if tn.priority == true and castFrame.isPriorityAura == nil then castFrame.isPriorityAura = false end
            if tn.nonplayer == true and key ~= "nonplayer" and castFrame.isFromPlayerOrPlayerPet == nil then
                castFrame.isFromPlayerOrPlayerPet = npHideVal
            end
            -- Less common categories: token, boolean, and per-type folds.
            if tn.castbyme == true and key ~= "castbyme" and not HasTok(tokenList, "!PLAYER") then
                tokenList[#tokenList + 1] = "!PLAYER"
            end
            if tn.canapply == true and castFrame.canApplyAura == nil then castFrame.canApplyAura = false end
            for ti = 1, #TYPE_ORDER do
                local tcat = TYPE_ORDER[ti]
                if tn[tcat] == true and key ~= tcat then ExcludeType(castFrame, TYPE_CATS[tcat]) end
            end
        end
    end

    -- Has Duration fold: the owner surface's modifier ANDs the native duration
    -- gate onto every record it owns (base records read dm, tile-hosted read
    -- their tile). maxDuration rejects duration == 0 (permanents) and anything
    -- above the cap, so math.huge keeps every timed debuff and drops only
    -- permanents. cc records are exempt like every other fold: the legacy cc
    -- group's candidates are declaration-fixed (no live retake), so the base
    -- cc surfaces could never honor a flip -- crowd control always shows.
    -- Also stamp each record with its owner list's resolved Size (base reads
    -- base blocks, tile-hosted reads its tile's).
    for i = 1, #records do
        local record = records[i]
        local ownerFrame = record.tile or baseView
        -- Max Duration (seconds) is the same native gate with a real cap; it
        -- implies Has Duration (a capped aura is a timed aura). nil = Unlimited
        -- = no field on the candidate table at all.
        local cap = ownerFrame.maxDurSec or (ownerFrame.hasDuration == true and math.huge) or nil
        if cap and record.key ~= "cc" and record.key ~= "npdead" then
            record.cand.maxDuration = cap
        end
        record.fxSize = FxSizeFor(record.tile and record.tile.fxList or baseView.fxList, record.cats or record.key)
    end

    -- HAND-OFF: each Match All set (matchSets, in precedence order) is taken out
    -- of every record not yet settled -- the base, Match Any indicators, the
    -- catch-alls and lower-precedence Match All indicators -- by splitting the
    -- record into exact disjoint parts outside the set (Carve). Parts keep the
    -- record's key, host, category stamp, size and flags, so Icon Effects, sizes
    -- and the CC row behave as before; a record that shares nothing with the
    -- set stays byte-identical. The dead-corpse record shows everything by
    -- design and is never split.
    if matchSets then
        local settled = {}
        for k = 1, #matchSets do
            local set = matchSets[k]
            settled[set.tile] = true
            local result = {}
            for i = 1, #records do
                local record = records[i]
                local parts
                if not record.deadOnly and not (record.tile and settled[record.tile]) then
                    parts = Carve(record, set.atoms, dmCfg)
                end
                if parts then
                    for profile = 1, #parts do
                        local tokenList, castFrame = MatchFinish(parts[profile])
                        if tokenList then
                            result[#result + 1] = { key = record.key, tokens = tokenList, cand = castFrame, tile = record.tile,
                                cats = record.cats, fxSize = record.fxSize, match = record.match, ccLead = record.ccLead }
                        end
                    end
                else
                    result[#result + 1] = record
                end
            end
            records = result
        end
    end

    return records, ccCand, claimMap, Cand, effectCats, matchOn
end

-- Shared "Match All can never match" test: the builder above builds nothing
-- for such a set, and the options page's empty-selection warning asks the
-- same question through this. False whenever Match All is not live.
function mod.DM_MatchEmpty(view)
    local dmCfg = DM()
    if not (view and dmCfg and MatchOn(view)) then return false end
    local _, claimMap = EffectiveState(view, true)
    return MatchFinish((MatchSpec(view, view.neg, dmCfg, claimMap))) == nil
end

-- Indicator Match All (options: the Filters summary join, the sidebar
-- subtitle and the "can never match" warning).
function mod.DM_TileMatchOn(tileDef)
    return tileDef ~= nil and TileMatchOn(tileDef)
end

function mod.DM_TileMatchEmpty(tileDef)
    local dmCfg = DM()
    if not (tileDef and dmCfg and TileMatchOn(tileDef)) then return false end
    return TileMatchEmpty(tileDef, dmCfg)
end

-- Order-independent fingerprint of a candidate-filter table. Candidate payloads are DECLARATION-FIXED
-- (SetAuraGroupCandidateFilters on a live group does not retake), so a payload change must land in the group key
-- and declare a fresh variant. Number-keyed sets (spell ids) fingerprint as count:sum; string-keyed sets (dispel names) join outright.
local function CandFP(castFrame)
    if not castFrame then return "-" end
    local keyList = {}
    for k in pairs(castFrame) do keyList[#keyList + 1] = k end
    table.sort(keyList)
    local parts = {}
    for i = 1, #keyList do
        local k = keyList[i]
        local val = castFrame[k]
        if type(val) == "table" then
            local first = next(val)
            if type(first) == "number" then
                local num, sum = 0, 0
                for ident in pairs(val) do
                    num = num + 1
                    sum = (sum + ident) % 2147483647
                end
                parts[#parts + 1] = k .. "=" .. num .. ":" .. sum
            else
                local nameList = {}
                for name in pairs(val) do nameList[#nameList + 1] = tostring(name) end
                table.sort(nameList)
                parts[#parts + 1] = k .. "=" .. table.concat(nameList, "+")
            end
        else
            parts[#parts + 1] = k .. "=" .. tostring(val)
        end
    end
    return table.concat(parts, ",")
end

-- Group keys embed the normalized filter string AND the candidate fingerprint (both declaration-fixed), so any
-- change to a record's negation set or candidate payload (subtracted boolean categories, typed-dispel exclude, lust
-- exclude set) declares a NEW variant group and parks the old at 0 (add-only engine, leak-free). Boolean records
-- share token sets, so the record-key prefix keeps them distinct.
local function GroupKey(AKL, region)
    -- "|sz" marks a SIZED record (group->style binding fixed at declare, so gaining/losing a Size swaps the
    -- variant); size VALUE excluded on purpose since the sized style key is stable per category and its content
    -- rebuilds on edits, so a slider drag restyles buttons instead of minting an engine batch per step.
    -- "|lead" marks the CC row's record form (its own style and flow slot, see BuildRecords).
    return "dm_" .. region.key .. "|" .. AKL.Filter(unpack(region.tokens))
        .. (region.fxSize and "|sz" or "") .. (region.ccLead and "|lead" or "") .. "|" .. CandFP(region.cand)
end

-- Effect-tile category resolution: one live-settable slot per tile.
local function EffectFilterFor(dmCfg, category)
    if category == "cc" then return { "HARMFUL", "CROWD_CONTROL" }, nil end
    if category == "raid" then return { "HARMFUL", "RAID" }, nil end
    if category == "raidcombat" then return { "HARMFUL", "RAID_IN_COMBAT" }, nil end
    if category == "dispel" then
        -- Follows the base dispel flavor: by-you token or typed include map.
        if dmCfg.dispelMode == "typed" then
            return { "HARMFUL" }, { includeDispelTypes = TYPED_DEBUFFS }
        end
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, nil
    end
    if category == "boss" then return { "HARMFUL" }, { isBossAura = true } end
    if category == "role" then return { "HARMFUL" }, { isRoleAura = true } end
    -- Follows the base Non-Player flavor (false = Non-Player Auras, true = From Any Player).
    if category == "nonplayer" then return { "HARMFUL" }, { isFromPlayerOrPlayerPet = dmCfg.nonplayerMode == "any" } end
    if category == "castbyme" then return { "HARMFUL", "PLAYER" }, nil end
    if TYPE_CATS[category] then return { "HARMFUL" }, { includeDispelTypes = TYPE_INCLUDE[category] } end
    if category == "canapply" then return { "HARMFUL" }, { canApplyAura = true } end
    -- Catch-all pseudo-category (TileCatchAllOn tiles; the duration modifier folds in via EffectFilterForTile).
    if category == "all" then return { "HARMFUL" }, nil end
    -- "priority" (default)
    return { "HARMFUL" }, { isPriorityAura = true }
end

-- Effect-slot resolution with the tile's HIDE lane and Has Duration modifier
-- folded in (same doctrine as record synthesis: tokens for token categories,
-- the typed exclude map for typed dispels, false-valued candidate booleans for
-- the rest, maxDuration for the modifier; a slot's own category defers, and
-- the cc slot takes no folds at all -- cc owns its overlaps, base parity with
-- ccCand bypassing Cand).
local function EffectFilterForTile(dmCfg, tileDef, category)
    local cap = tileDef and (tileDef.maxDurSec or (tileDef.hasDuration == true and math.huge)) or nil
    -- Match All: ONE conjunction slot from the tile's lanes (its hide lane is in
    -- the spec). A set that can never match keeps a plain filter; FxApply's gate
    -- (fx.matchLive) silences the slot instead.
    if category == "match" then
        local tokenList, castFrame = MatchFinish((MatchSpec(tileDef.claim, tileDef.neg, dmCfg)))
        if not tokenList then return { "HARMFUL" }, {} end
        if cap then castFrame.maxDuration = cap end
        return tokenList, castFrame
    end
    local tokenList, castFrame = EffectFilterFor(dmCfg, category)
    if cap and category ~= "cc" then
        castFrame = castFrame or {}
        if castFrame.maxDuration == nil then castFrame.maxDuration = cap end
    end
    local tn = tileDef and tileDef.neg
    if tn and category ~= "cc" then
        if tn.cc == true then tokenList[#tokenList + 1] = "!CROWD_CONTROL" end
        if tn.dispel == true and category ~= "dispel" then
            if dmCfg.dispelMode == "typed" then
                castFrame = castFrame or {}
                if not castFrame.includeDispelTypes then castFrame.excludeDispelTypes = TYPED_DEBUFFS end
            else
                tokenList[#tokenList + 1] = "!RAID_PLAYER_DISPELLABLE"
            end
        end
        if tn.raid == true and category ~= "raid" then tokenList[#tokenList + 1] = "!RAID" end
        if tn.raidcombat == true and category ~= "raidcombat" then tokenList[#tokenList + 1] = "!RAID_IN_COMBAT" end
        if tn.boss == true and category ~= "boss" then
            castFrame = castFrame or {}
            if castFrame.isBossAura == nil then castFrame.isBossAura = false end
        end
        if tn.role == true and category ~= "role" then
            castFrame = castFrame or {}
            if castFrame.isRoleAura == nil then castFrame.isRoleAura = false end
        end
        if tn.priority == true and category ~= "priority" then
            castFrame = castFrame or {}
            if castFrame.isPriorityAura == nil then castFrame.isPriorityAura = false end
        end
        if tn.nonplayer == true and category ~= "nonplayer" then
            castFrame = castFrame or {}
            if castFrame.isFromPlayerOrPlayerPet == nil then castFrame.isFromPlayerOrPlayerPet = (dmCfg.nonplayerMode ~= "any") end
        end
        if tn.castbyme == true and category ~= "castbyme" then tokenList[#tokenList + 1] = "!PLAYER" end
        if tn.canapply == true and category ~= "canapply" then
            castFrame = castFrame or {}
            if castFrame.canApplyAura == nil then castFrame.canApplyAura = false end
        end
        -- Per-type hides: the typed dispel slot's include map shrinks (copy),
        -- any other slot gains an exclude entry; a slot's own type is skipped.
        for ti = 1, #TYPE_ORDER do
            local tcat = TYPE_ORDER[ti]
            if tn[tcat] == true and category ~= tcat then
                local T = TYPE_CATS[tcat]
                castFrame = castFrame or {}
                local included = castFrame.includeDispelTypes
                if included then
                    if included[T] then
                        local match = {}
                        for k, val in pairs(included) do match[k] = val end
                        match[T] = nil
                        castFrame.includeDispelTypes = match
                    end
                elseif castFrame.excludeDispelTypes ~= TYPED_DEBUFFS then
                    local match = {}
                    if castFrame.excludeDispelTypes then
                        for k, val in pairs(castFrame.excludeDispelTypes) do match[k] = val end
                    end
                    match[T] = true
                    castFrame.excludeDispelTypes = match
                end
            end
        end
    end
    return tokenList, castFrame
end

-- Effect-tile category set: claimed categories plus the "all" pseudo-category
-- while the tile is in catch-all state (nil when the tile targets nothing);
-- under Match All the one "match" pseudo-category instead (the per-pick slots
-- stay declared, silenced by FxApply's gate).
local MATCH_FX_SET = { match = true }
local function EffectCatSet(tileDef)
    if TileMatchOn(tileDef) then return MATCH_FX_SET end
    local set
    if tileDef.claim then
        for category, on in pairs(tileDef.claim) do
            if on then
                set = set or {}
                set[category] = true
            end
        end
    end
    if TileCatchAllOn(tileDef) then
        set = set or {}
        set.all = true
    end
    return set
end

-------------------------------------------------------------------------------
-- Tile containers (per button, persistent, parked when unused)
-------------------------------------------------------------------------------

-- Per-slot-button refs for the effect appliers (weak keys: engine buttons are pooled frames, never write properties onto them).
local fxRefs = setmetatable({}, { __mode = "k" })

-- Effect visuals: ALL created in the slot's extraInit, the ONLY window where insecure calls on the engine button
-- are legal (elsewhere the engine permanently denies reads/writes and the restyler's pcall swallows the denial
-- silently, so creating in the applier builds nothing, ever). FxApply only parameterizes frames we own. Children
-- hang off the slot button (visibility rides the aura match) and anchor OUTWARD to our clean frames (unit button /
-- health), the dispel-overlay/BmEffectInit precedent. FxHideAll hides every effect visual on one slot button
-- (shared by filter-gated slots and teardown paths).
local function FxHideAll(dropdown)
    if dropdown.dmFxGlow then
        if dropdown.dmFxGlow._cuiGlowActive then CludesUI.Glows.StopGlow(dropdown.dmFxGlow) end
        dropdown.dmFxGlow:Hide()
    end
    if dropdown.dmFxHcFrame then dropdown.dmFxHcFrame:Hide() end
    if dropdown.dmFxGeoF then dropdown.dmFxGeoF:Hide() end
end

-- Frame Glow tiles draw Pixel only: their prewarm builds the animated ants alone.
local TILE_GLOW_NEED = { ants = true }

-- Creation-window builder: one kind-specific visual set per effect slot, parked hidden until the applier arms it.
-- Runs in extraInit inside a CreateFrameBatch: an error here kills the whole slot declaration, hence the pcall-degraded engine binding.
-- owner: the tile container, which keys its Health Bar Color overlays in the bar's tint registry (the stale sweep drops only its own).
local function FxCreateVisuals(btnFrame, dropdown, kind, hostBtn, health, ownerFrame)
    if not dropdown then return end
    if kind == "glow" then
        local g = CreateFrame("Frame", nil, btnFrame)
        -- The Party Frames kit glows round the visible party frame; the
        -- level band stays the unit button's.
        g:SetAllPoints((health and health._cuiKitRef) or hostBtn)
        g:SetFrameLevel((hostBtn:GetFrameLevel() or 1) + 15)
        g:EnableMouse(false)
        g:Hide()
        dropdown.dmFxGlow = g
        -- Every region a later colour/parameter/background change can need, created here in the window.
        CludesUI.Glows.PrewarmEngineHost(g, 24, 24, TILE_GLOW_NEED)
        -- The slot button runs the glow's animations itself (only while it shows an aura), where the client
        -- can. The slot registers no icon: it gets a hidden one here, which restarts the glow on a later change.
        if CludesUI.Glows.BindEngineHost(g, btnFrame, dropdown) then
            CludesUI.AuraKit.EnsureKickIcon(btnFrame, dropdown)
        end
    elseif kind == "healthcolor" then
        -- BM healthcolor parity via an owned wrapper: level-tied WITH (not above) the health frame so the tint
        -- sorts against health's ARTWORK sublevels (above fill=0, below heal absorb/prediction=+1, shields=+3);
        -- anchored to the current-health area (the fill texture, or the rest of the bar under Inverted Fill) so it
        -- covers only current health. Wrapper is ours, so the level tie stays legal.
        local frame = CreateFrame("Frame", nil, btnFrame)
        mod.RF_AnchorCurHealth(frame, health, health.GetStatusBarTexture and health:GetStatusBarTexture())
        frame:SetFrameLevel(health:GetFrameLevel())
        local texture = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        texture:SetAllPoints(frame)
        frame:Hide()
        dropdown.dmFxHcFrame = frame
        dropdown.dmFxHc = texture
        mod.RF_RegisterBarTint(health, texture, frame, ownerFrame)
    elseif kind == "square" then
        local frame = CreateFrame("Frame", nil, btnFrame)
        frame:SetPoint("CENTER", health, "CENTER")
        frame:SetSize(10, 10)
        local texture = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        texture:SetAllPoints(frame)
        frame:Hide()
        dropdown.dmFxGeoF = frame
        dropdown.dmFxSq = texture
    elseif kind == "bar" then
        local scrollBar = CreateFrame("StatusBar", nil, btnFrame)
        scrollBar:SetPoint("CENTER", health, "CENTER")
        scrollBar:SetSize(10, 10)
        scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        scrollBar:SetMinMaxValues(0, 1)
        scrollBar:SetValue(1)
        local backdrop = scrollBar:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(scrollBar)
        scrollBar:Hide()
        dropdown.dmFxGeoF = scrollBar
        dropdown.dmFxBar = scrollBar
        dropdown.dmFxBarBg = backdrop
        -- Engine drives the fill from the aura's duration object; button call legal only HERE.
        local success = pcall(btnFrame.SetDurationBar, btnFrame, scrollBar, {})
        if not success then pcall(btnFrame.SetDurationBar, btnFrame, scrollBar) end
    end
end

local FX_GLOW_SPEC = {}
local function FxApplyInner(btnFrame, dropdown, refs, effect)
    if effect.kind == "glow" then
        local Glows = CludesUI.Glows
        local owner = dropdown.dmFxGlow
        if not owner then return end -- created in extraInit
        -- A bound host's button refuses our calls while auras are restricted (outside its creation window):
        -- re-run this style at the lift instead of letting the pcall below drop the change.
        if Glows.IsEngineHostBound(owner) and not CludesUI.AuraKit.CanTouchButton(btnFrame) then
            CludesUI.AuraKit.DeferRestyle(dropdown.styleKey)
            return
        end
        owner:Show()
        -- Tile color mode: nil has always meant default here (proc gold).
        local specInfo = FX_GLOW_SPEC
        specInfo.style = effect.glowType or 1
        specInfo.excludes = Glows.RECT_EXCLUDES
        specInfo.r, specInfo.g, specInfo.b = Glows.ResolveColor(effect.glowMode or "default", effect.r, effect.g, effect.b, 1, 0.78, 0.38)
        specInfo.lines, specInfo.thickness, specInfo.speed = effect.glowLines, effect.glowThickness, effect.glowSpeed
        specInfo.bg, specInfo.bgR, specInfo.bgG, specInfo.bgB = effect.glowBg, effect.glowBgR, effect.glowBgG, effect.glowBgB
        -- Size from the unit frame's REAL rect (refs.host is ours, outside the forbidden subtree, so the read is legal here).
        local rect = (refs.health and refs.health._cuiKitRef) or refs.host
        local gw = rect:GetWidth() or 0
        local gh = rect:GetHeight() or 0
        if gw < 1 then gw = 24 end
        if gh < 1 then gh = gw end
        -- Engine host: C-side styles only (driver-ticked glows freeze on the forbidden slot subtree).
        Glows.StartSpecGlow(owner, specInfo, gw, gh, "engine")

    elseif effect.kind == "healthcolor" then
        local frame = dropdown.dmFxHcFrame
        local texture = dropdown.dmFxHc
        if not (frame and texture) then return end -- created in extraInit
        -- Level tie set at creation; NO re-check here -- subtree reads (ours included) are denied outside the creation window and would kill this branch.
        -- The bar itself is OURS and outside that subtree, so the tint can read its
        -- fill texture here and keep the health bar's shading instead of flattening it.
        mod.RF_TintOverBarFill(texture, refs.health, effect.r or 1, effect.g or 0.2, effect.b or 0.2, effect.a or 0.5)
        -- Re-anchored to the bar's current fill direction on every restyle as well: a
        -- container back from the stale sweep missed the registry's re-anchor.
        mod.RF_AnchorCurHealth(frame, refs.health,
            refs.health.GetStatusBarTexture and refs.health:GetStatusBarTexture())
        frame:Show()

    elseif effect.kind == "square" then
        local geoFrame = dropdown.dmFxGeoF
        if not geoFrame then return end -- created in extraInit
        local wid = effect.w or 10
        local hgt = effect.h or 10
        local sig = table.concat({ tostring(wid), tostring(hgt), tostring(effect.corner),
            tostring(effect.offX), tostring(effect.offY) }, ",")
        if dropdown.dmFxGeo ~= sig then
            -- Geometry rides OUR frame (always-legal calls); the sig cache keeps repeat applies cheap.
            geoFrame:SetSize(wid, hgt)
            geoFrame:ClearAllPoints()
            geoFrame:SetPoint(effect.corner or "CENTER", refs.health, effect.corner or "CENTER",
                effect.offX or 0, effect.offY or 0)
            dropdown.dmFxGeo = sig
        end
        local texture = dropdown.dmFxSq
        if texture then texture:SetColorTexture(effect.r or 1, effect.g or 1, effect.b or 1, effect.a or 1) end
        geoFrame:Show()

    elseif effect.kind == "bar" then
        local geoFrame = dropdown.dmFxGeoF
        if not geoFrame then return end -- created in extraInit
        -- BM_PlaceBar 1:1: width/height are FILL-axis sliders and Full toggles follow the fill axis, swapping
        -- screen edges when vertical. Geometry rides OUR StatusBar; sig cache keeps repeat applies cheap.
        local wid = effect.w or 30
        local hgt = effect.h or 4
        local isVert = effect.orient == "VERTICAL"
        local sig = table.concat({ tostring(wid), tostring(hgt), tostring(effect.corner),
            tostring(effect.offX), tostring(effect.offY), tostring(effect.orient),
            tostring(effect.fullW), tostring(effect.fullH), tostring(effect.lvl) }, ",")
        if dropdown.dmFxGeo ~= sig then
            local health = refs.health
            geoFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
            geoFrame:ClearAllPoints()
            local fullW, fullH
            if isVert then
                fullW, fullH = effect.fullH, effect.fullW
            else
                fullW, fullH = effect.fullW, effect.fullH
            end
            local place = effect.corner or "BOTTOM"
            if fullW and fullH then
                geoFrame:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                geoFrame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            elseif fullW then
                local vEdge = (place:find("BOTTOM", 1, true) and "BOTTOM")
                    or (place:find("TOP", 1, true) and "TOP") or ""
                local oy = effect.offY or 0
                geoFrame:SetPoint(vEdge .. "LEFT", health, vEdge .. "LEFT", 0, oy)
                geoFrame:SetPoint(vEdge .. "RIGHT", health, vEdge .. "RIGHT", 0, oy)
                geoFrame:SetHeight(isVert and wid or hgt)
            elseif fullH then
                local hEdge = (place:find("RIGHT", 1, true) and "RIGHT")
                    or (place:find("LEFT", 1, true) and "LEFT") or ""
                local ox = effect.offX or 0
                geoFrame:SetPoint("TOP" .. hEdge, health, "TOP" .. hEdge, ox, 0)
                geoFrame:SetPoint("BOTTOM" .. hEdge, health, "BOTTOM" .. hEdge, ox, 0)
                geoFrame:SetWidth(isVert and hgt or wid)
            else
                if isVert then geoFrame:SetSize(hgt, wid) else geoFrame:SetSize(wid, hgt) end
                geoFrame:SetPoint(place, health, place, effect.offX or 0, effect.offY or 0)
            end
            -- Frame Level band relative to the unit button (our frame; the read is legal in the creation window).
            geoFrame:SetFrameLevel((refs.host:GetFrameLevel() or 1) + (effect.lvl or 7))
            dropdown.dmFxGeo = sig
        end
        geoFrame:SetReverseFill(effect.reverseFill or false)
        geoFrame:SetStatusBarColor(effect.r or 0.25, effect.g or 0.8, effect.b or 0.45,
            (effect.colorOp or 100) / 100)
        if dropdown.dmFxBarBg then
            dropdown.dmFxBarBg:SetColorTexture(effect.bgR or 0, effect.bgG or 0, effect.bgB or 0,
                (effect.bgOp or 50) / 100)
        end
        geoFrame:Show()
    end
end

local function FxApply(btnFrame, dropdown, style)
    local refs = fxRefs[btnFrame]
    local effect = style.fx
    if not (refs and effect) then return end

    -- Per-filter gating: an effect tile declares one slot per EVER-checked category
    -- (add-only engine -- a slot cannot be un-declared), so a slot whose category is
    -- currently UNCHECKED must render nothing. dd.dmCat is stamped at slot creation
    -- and fx.filters is the live checked set, so the two together are the gate. The
    -- catch-all pseudo-slot ("all") gates on the live tile's current catch-all
    -- state instead (never a claim key). Under Match All only the "match"
    -- pseudo-slot renders (fx.matchOn / fx.matchLive, resolved at style build).
    -- Both paths stay pcall-wrapped: this runs inside the engine's CreateFrameBatch,
    -- where an uncaught error aborts the whole batch and the slot never appears.
    if dropdown and effect.filters and ((dropdown.dmCat == "match" and effect.matchLive)
        or (not effect.matchOn and effect.filters[dropdown.dmCat])
        or (dropdown.dmCat == "all" and effect.tile and TileCatchAllOn(effect.tile))) then
        pcall(FxApplyInner, btnFrame, dropdown, refs, effect)
    else
        pcall(FxHideAll, dropdown)
    end
end

-- Icon-tile flow anchoring: corner-pinned chain, CENTER growth centers the
-- row on the anchor point's X (based on the defensives-row math, with tile
-- settings and the vertical seat kept flush with the anchored edge).
local function AnchorTileContainer(boxHolder, health, s, tileDef, skinData)
    health = mod.RF_AnchorHost and mod.RF_AnchorHost(health, s) or health
    -- Pin shared with the tooltip-modifier eater (TilePin): point = corner for
    -- directional growth, the flush edge midpoint for CENTER growth.
    local anchorPoint, corner, offX, offY = TilePin(tileDef, s, skinData)
    -- Party Frames kit seat (TilePin): a TOPLEFT block flowing right,
    -- wrapping down.
    local kitSeat = anchorPoint == "TOPLEFT" and mod.DM_KitTileY(tileDef, s, skinData) ~= nil
    local grow = kitSeat and "RIGHT" or (tileDef.growDirection or "CENTER")

    AK = AK or CludesUI.AuraKit
    -- Grid wrap: Icons Per Row >= 2 wraps lines away from the anchored edge (simple-grid convention, lowercase
    -- position tokens here); vertical growth flips the flow axis so lines become columns. Below 2 =
    -- single run, corner pick untouched.
    local per = tonumber(tileDef.iconsPerRow) or 0
    local pl = kitSeat and "topleft" or (tileDef.position or "top")
    local wrapUp = pl:find("bottom", 1, true) ~= nil
    local wrapLeft = pl:find("right", 1, true) ~= nil
    boxHolder:ClearAllPoints()
    if grow == "CENTER" then
        -- Center ONLY the growth (horizontal) axis on the position point; the
        -- vertical component sits flush with the anchored edge exactly like
        -- the directional branch below. (A full CENTER pin -- the raw
        -- defensives-row math -- straddled top/bottom edges by half an icon.)
        boxHolder:SetPoint(anchorPoint, health, corner, offX, offY)
        local gV = (per >= 2 and wrapUp) and "UP" or "DOWN"
        AK.SetContainerAnchor(boxHolder, (gV == "UP") and "BOTTOMLEFT" or "TOPLEFT")
        AK.SetContainerGrowth(boxHolder, FlowDir("RIGHT"), FlowDir(gV))
    else
        boxHolder:SetPoint(corner, health, corner, offX, offY)
        local gV = (grow == "UP" or grow == "DOWN") and grow or "DOWN"
        local gH = (grow == "LEFT" or grow == "RIGHT") and grow or "RIGHT"
        if per >= 2 then
            if grow == "UP" or grow == "DOWN" then
                gH = wrapLeft and "LEFT" or "RIGHT"
            else
                gV = wrapUp and "UP" or "DOWN"
            end
            AK.SetContainerAnchor(boxHolder,
                ((gV == "UP") and "BOTTOM" or "TOP") .. ((gH == "LEFT") and "RIGHT" or "LEFT"))
        else
            AK.SetContainerAnchor(boxHolder, corner)
        end
        AK.SetContainerGrowth(boxHolder, FlowDir(gH), FlowDir(gV))
    end

    local size = EffectiveIconSize(skinData, tileDef.size or 18)
    local spacing = tileDef.spacing or 1
    local vertical = (grow == "UP" or grow == "DOWN")
    if per >= 2 then
        AK.SetContainerAxis(boxHolder, vertical)
        AK.SetContainerRowWidth(boxHolder, per * size + (per - 1) * spacing + 0.4)
    else
        AK.SetContainerAxis(boxHolder, false)
        AK.SetContainerRowWidth(boxHolder, vertical and (size + 0.4) or nil)
    end
end

-- Per-class tile fingerprints (style/geometry), keyed class .. ":" .. id.
local dmTileFP = {}

-- Ensures one tile's per-class style exists and is current: icon tiles reuse the debuff style at tile size; effect
-- tiles get a bare noRegions style whose applyExtra renders style.fx. szOv/szCat: an Icon Effects Size hosts the
-- sized record on its own STABLE per-category variant (content rebuilds on size edits, group variant swaps only at sized/unsized).
-- Grid-tile style core, shared by EnsureTileStyle and DM_RefreshSizedStyles: tile styles VIEW the base debuff
-- style keys, so a pure base-style edit must re-derive them here too or they render stale (same as sized siblings).
local function RefreshTileGridStyle(key, tileStyle, s, tileDef, renderSize, font)
    local savedVars = TileStyleView(s, tileDef)
    local val = ((mod.RFC_DebuffStyleFP and mod.RFC_DebuffStyleFP(savedVars, font)) or "")
        .. "|" .. tostring(renderSize)
        .. "|" .. FxListFP(tileDef.fxList)
    if tileDef.type == "square" then
        local color = tileDef.color or {}
        val = val .. "|sq" .. string.format("%.2f,%.2f,%.2f,%.2f",
            color.r or 1, color.g or 0.35, color.b or 0.35, color.a or 1)
    end
    if tileStyle.style ~= val and mod.RFC_BuildDebuffStyle then
        tileStyle.style = val
        local sty = mod.RFC_BuildDebuffStyle(savedVars, renderSize)
        if tileDef.type == "square" then
            -- Square grid: flat color block over the icon (shared applier).
            sty.squareColor = tileDef.color or { r = 1, g = 0.35, b = 0.35, a = 1 }
        end
        -- Per-tile Effects override the base-injected fx explicitly, including nil: a tile without blocks must not inherit the base.
        sty.fxList = FxListView(tileDef.fxList)
        AK.styles[key] = sty
        AK.RestyleSoon(key)
    end
end

local function EnsureTileStyle(skinData, s, tileDef, szOv, szCat)
    local cls = ClassToken(skinData)
    local key
    local isGrid = (tileDef.type == "icons" or tileDef.type == "square")
    if isGrid then
        key = "rf:dmt:" .. cls .. ":" .. tostring(tileDef.id)
        if szOv then key = key .. ":sz:" .. tostring(szCat) end
    else
        key = "rf:dmfx:" .. cls .. ":" .. tostring(tileDef.id)
    end
    local tileStyle = dmTileFP[key]
    if not tileStyle then tileStyle = {}; dmTileFP[key] = tileStyle end

    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    local val
    if isGrid then
        -- Rebuild handles for DM_RefreshSizedStyles (base-style edits re-derive this key without an apply pass).
        tileStyle.cls, tileStyle.tid, tileStyle.szOv, tileStyle.grid = cls, tileDef.id, szOv, true
        RefreshTileGridStyle(key, tileStyle, s, tileDef,
            EffectiveIconSizeForClass(szOv or tileDef.size or 18, cls), font)
    else
        local color = tileDef.color or {}
        local bgc = tileDef.barBgColor or {}
        local cl = {}
        if tileDef.claim then
            for k2, on in pairs(tileDef.claim) do if on then cl[#cl + 1] = k2 end end
            table.sort(cl)
        end
        -- Match All gate inputs (FxApply): on, and whether the set can match at all
        -- (reads the tile's lanes and the shared dispel / Non-Player flavors).
        local mOn = TileMatchOn(tileDef)
        local mLive = mOn and not TileMatchEmpty(tileDef, DM() or {})
        val = table.concat({ tostring(tileDef.type), tostring(tileDef.glowType), tostring(tileDef.glowLines),
            tostring(tileDef.glowThickness), tostring(tileDef.glowSpeed), tostring(tileDef.glowColorMode),
            mod.RF_GlowClassFP(tileDef.glowColorMode),
            tostring(tileDef.glowBackground), tileDef.glowBackgroundColor and string.format("%.2f,%.2f,%.2f",
                tileDef.glowBackgroundColor.r or 0, tileDef.glowBackgroundColor.g or 0, tileDef.glowBackgroundColor.b or 0) or "-",
            tostring(tileDef.opacity), tostring(tileDef.size),
            tostring(tileDef.width), tostring(tileDef.height), tostring(tileDef.position),
            tostring(tileDef.offsetX), tostring(tileDef.offsetY),
            tostring(tileDef.orientation), tostring(tileDef.reverseFill),
            tostring(tileDef.barFullWidth), tostring(tileDef.barFullHeight),
            tostring(tileDef.barColorOpacity), tostring(tileDef.barBgOpacity),
            tostring(tileDef.frameLevel),
            string.format("%.2f,%.2f,%.2f,%.2f", color.r or 1, color.g or 1, color.b or 1, color.a or 1),
            string.format("%.2f,%.2f,%.2f", bgc.r or 0, bgc.g or 0, bgc.b or 0),
            table.concat(cl, "+"), tostring(tileDef.all), tostring(tileDef.hasDuration),
            mOn and (mLive and "mA" or "mE") or "-",
        }, "|")
        if tileStyle.style ~= val then
            tileStyle.style = val
            AK.styles[key] = {
                noRegions = true,
                applyExtra = FxApply,
                fx = {
                    kind = tileDef.type,
                    matchOn = mOn, matchLive = mLive,
                    -- Checked-filter set: the applier's per-slot gate (live table reference; the FP above rebuilds on changes).
                    filters = tileDef.claim or {},
                    -- Live tile reference: the catch-all pseudo-slot's gate (see FxApply).
                    tile = tileDef,
                    glowType = tileDef.glowType or 1, glowLines = tileDef.glowLines,
                    glowThickness = tileDef.glowThickness, glowSpeed = tileDef.glowSpeed,
                    glowMode = tileDef.glowColorMode,
                    glowBg = tileDef.glowBackground == true or nil,
                    glowBgR = tileDef.glowBackgroundColor and tileDef.glowBackgroundColor.r,
                    glowBgG = tileDef.glowBackgroundColor and tileDef.glowBackgroundColor.g,
                    glowBgB = tileDef.glowBackgroundColor and tileDef.glowBackgroundColor.b,
                    size = tileDef.size,
                    w = tileDef.width or 10, h = tileDef.height or 10,
                    corner = CORNERS[tileDef.position or "center"] or "CENTER",
                    offX = tileDef.offsetX, offY = tileDef.offsetY,
                    orient = tileDef.orientation, reverseFill = tileDef.reverseFill,
                    fullW = tileDef.barFullWidth, fullH = tileDef.barFullHeight,
                    colorOp = tileDef.barColorOpacity, bgOp = tileDef.barBgOpacity,
                    bgR = bgc.r, bgG = bgc.g, bgB = bgc.b,
                    lvl = BAR_FRAMELVL[tileDef.frameLevel or "behindBorders"],
                    r = color.r, g = color.g, b = color.b,
                    -- Health color rides a dedicated Opacity setting (the swatch has no alpha strip there, matching BM).
                    a = (tileDef.type == "healthcolor")
                        and ((tileDef.opacity or 45) / 100) or color.a,
                },
            }
            AK.RestyleSoon(key)
        end
    end
    return key
end

-- Sized BASE-record styles: an Icon Effects block with a Size renders its categories at that size. Buttons take
-- physical size from the style at creation, so each sized category gets its own STABLE style key: content rebuilds
-- on size/base-style changes, group variant swaps only at the sized/unsized edge (GroupKey "|sz"). "cc" builds the
-- CC-glow flavor so sized crowd control keeps its glow; registry entries let the containers file refresh these on its own rebuilds (DM_RefreshSizedStyles).
local dmSizeFP = {}
local function EnsureBaseSizeStyle(skinData, s, category, size)
    local cls = ClassToken(skinData)
    local key = "rf:dmsz:" .. cls .. ":" .. tostring(category)
    local tileStyle = dmSizeFP[key]
    if not tileStyle then tileStyle = { cls = cls, cat = category }; dmSizeFP[key] = tileStyle end
    tileStyle.rawSize = size
    size = EffectiveIconSizeForClass(size, cls)
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    local val = ((mod.RFC_DebuffStyleFP and mod.RFC_DebuffStyleFP(s, font)) or "")
        .. "|" .. tostring(size)
    if tileStyle.style ~= val and mod.RFC_BuildDebuffStyle then
        tileStyle.style = val
        local sty
        if category == "cc" and mod.RFC_BuildDebuffCCStyle then
            sty = mod.RFC_BuildDebuffCCStyle(s, size)
        else
            sty = mod.RFC_BuildDebuffStyle(s, size)
        end
        AK.styles[key] = sty
        AK.RestyleSoon(key)
    end
    return key
end

-- Called by the containers file when it rebuilds a class's base debuff styles on a style-fingerprint change: a pure
-- style edit (border color, font) does not flip the config fingerprint (so the apply pass/EnsureBaseSizeStyle may not run) -- sized siblings must refresh here or render stale.
function mod.DM_RefreshSizedStyles(baseStyleKey, s)
    AK = AK or CludesUI.AuraKit
    if not AK then return end
    local cls = baseStyleKey:match("^rf:debuff:(.+)$")
    if not cls then return end
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    for key, tileStyle in pairs(dmSizeFP) do
        if tileStyle.cls == cls and tileStyle.style and tileStyle.rawSize then
            local size = EffectiveIconSizeForClass(tileStyle.rawSize, cls)
            local val = ((mod.RFC_DebuffStyleFP and mod.RFC_DebuffStyleFP(s, font)) or "")
                .. "|" .. tostring(size)
            if tileStyle.style ~= val and mod.RFC_BuildDebuffStyle then
                tileStyle.style = val
                local sty
                if tileStyle.cat == "cc" and mod.RFC_BuildDebuffCCStyle then
                    sty = mod.RFC_BuildDebuffCCStyle(s, size)
                else
                    sty = mod.RFC_BuildDebuffStyle(s, size)
                end
                AK.styles[key] = sty
                AK.RestyleSoon(key)
            end
        end
    end
    -- Grid tiles view the same base style keys; refresh them on this edge too.
    local activeTiles = mod.DM_ActiveTiles and mod.DM_ActiveTiles()
    if activeTiles then
        local byId = {}
        for i = 1, #activeTiles do byId[activeTiles[i].id] = activeTiles[i] end
        for key, tileStyle in pairs(dmTileFP) do
            if tileStyle.grid and tileStyle.cls == cls then
                local tileDef = byId[tileStyle.tid]
                if tileDef then
                    local size = EffectiveIconSizeForClass(tileStyle.szOv or tileDef.size or 18, cls)
                    RefreshTileGridStyle(key, tileStyle, s, tileDef, size, font)
                end
            end
        end
    end
end

-- Parks a tile container (the Buff Manager pool's park): hidden, and its buttons released at once -- record groups
-- to a cap of 0, effect slots switched off (where the client can; both clear their buttons right away, while a
-- hidden container's own re-parse waits until it shows) -- so each button stops the glow animations it runs
-- itself. Then switched off and bound to no unit, so nothing re-parses meanwhile; unit re-assignments skip it
-- (_dmParked) and the apply that shows it again unparks it and re-points it (_dmUnit). Repeat parks only hide.
local function ParkTileContainer(c)
    c:Hide()
    if c._dmParked then return end
    c._dmParked = true
    local AKit = CludesUI.AuraKit
    local grid = c._dmType == "icons" or c._dmType == "square"
    if c._dmDecl then
        for k in pairs(c._dmDecl) do
            if grid then
                AKit.SetGroupCap(c, k, 0)
            elseif c.SetAuraSlotEnabled then
                c:SetAuraSlotEnabled(k, false)
            end
        end
    end
    c:SetEnabled(false)
    c:SetUnit("none")
    c._dmUnit = "none"
end

-- Undoes ParkTileContainer before the apply configures and shows the container: its group caps come from the
-- apply itself, its effect slots switch back on here, and the apply's _dmUnit check re-points it.
local function UnparkTileContainer(c)
    if not c._dmParked then return end
    c._dmParked = nil
    c:SetEnabled(true)
    if c._dmDecl and c.SetAuraSlotEnabled and c._dmType ~= "icons" and c._dmType ~= "square" then
        for k in pairs(c._dmDecl) do c:SetAuraSlotEnabled(k, true) end
    end
end

-- Ensures one tile's container exists for this button (queued: container shells are combat-illegal). Effect tiles
-- declare their single slot at build; icon tiles get record groups from the apply pass (combat-legal adds on existing containers).
-- A container is built for one tile TYPE (effect slots vs record groups) and carries its own declared keys (_dmDecl).
-- Override layers fork the whole tile list, so a tile id can come back as another type: the built container parks
-- hidden (dmTilesParked[id][type]) and a parked container of the right type is restored before anything is built.
local function EnsureTileContainer(skinData, tileDef)
    local tiles = skinData.dmTiles
    if not tiles then tiles = {}; skinData.dmTiles = tiles end
    local c = tiles[tileDef.id]
    if c then
        if c._dmType == tileDef.type then return c end
        ParkTileContainer(c)
        local parked = skinData.dmTilesParked
        if not parked then parked = {}; skinData.dmTilesParked = parked end
        local byType = parked[tileDef.id]
        if not byType then byType = {}; parked[tileDef.id] = byType end
        byType[c._dmType] = c
        tiles[tileDef.id] = nil
        -- Its bar tints stay registered: parked containers are bounded (one per id and type) and come back as they were.
    end
    local byType = skinData.dmTilesParked and skinData.dmTilesParked[tileDef.id]
    local back = byType and byType[tileDef.type]
    if back then
        byType[tileDef.type] = nil
        tiles[tileDef.id] = back
        -- A stale-tile sweep may have dropped its healthcolor tints meanwhile; the apply restyles it once.
        if back._dmType == "healthcolor" then back._dmRestyle = true end
        return back
    end
    local pend = skinData.dmTilePend
    if not pend then pend = {}; skinData.dmTilePend = pend end
    if pend[tileDef.id] then return nil end
    pend[tileDef.id] = true
    local tileId = tileDef.id
    AKWorker:Queue(function()
        skinData.dmTilePend[tileId] = nil
        if skinData.dmTiles[tileId] then return end
        if not mod.DM_Active() then return end
        local btnFrame = skinData.dmHost
        local health = skinData.rfcHealth
        local unitToken = skinData.rfcUnit
        if not (btnFrame and health) then return end
        -- Re-resolve from the ACTIVE union: a tile that left it between
        -- queue and run (delete, spec swap, per-spec disable) builds nothing.
        local activeTiles = mod.DM_ActiveTiles()
        local liveTile
        if activeTiles then
            for i = 1, #activeTiles do
                if activeTiles[i].id == tileId then liveTile = activeTiles[i] break end
            end
        end
        if not liveTile then return end
        local frameCfg = SettingsFor(skinData)
        if not frameCfg then return end
        -- A container parked for this type (the tile flipped back while this job waited) is restored, not rebuilt.
        local parkedT = skinData.dmTilesParked and skinData.dmTilesParked[tileId]
        local back = parkedT and parkedT[liveTile.type]
        if back then
            parkedT[liveTile.type] = nil
            skinData.dmTiles[tileId] = back
            if back._dmType == "healthcolor" then back._dmRestyle = true end
            if skinData.rfcDebuffs then mod.DM_ApplyDebuffConfig(skinData.rfcDebuffs, skinData, frameCfg, StyleKeyFor(skinData)) end
            return
        end
        -- EffectFilterFor below reads dm (dispelMode); the active-union
        -- re-resolve above no longer carries it.
        local liveCfg = DM() or {}
        local styleKey = EnsureTileStyle(skinData, frameCfg, liveTile)
        local boxHolder = AK.CreateContainerShell(btnFrame, {
            point = { "CENTER", health, "CENTER" },
        })
        -- Level bands: grid and bar tiles render in the aura band (button + LVL_AURA = 13, above borders/text like
        -- legacy aura icons). Healthcolor slots re-tie to the health frame in the applier and glow hosts level
        -- themselves (+15), so this is only a pre-apply default (container defaults are far lower, which would put tile icons under borders/text).
        if liveTile.type == "healthcolor" then
            boxHolder:SetFrameLevel(btnFrame:GetFrameLevel() + 6)
        else
            boxHolder:SetFrameLevel(btnFrame:GetFrameLevel() + (mod.LVL_AURA or 13))
        end
        local tDecl = {}
        boxHolder._dmType = liveTile.type
        boxHolder._dmDecl = tDecl
        if liveTile.type ~= "icons" and liveTile.type ~= "square" then
            -- One slot PER checked filter category; later checks add slots on the live lane, gate silences unchecked ones.
            local owner = btnFrame
            local hp = health
            local tileKind = liveTile.type
            local cs = EffectCatSet(liveTile)
            if cs then
                for category in pairs(cs) do
                    local catKey = category
                    local filter, candidates = EffectFilterForTile(liveCfg, liveTile, catKey)
                    AK.AddSlotToContainer(boxHolder, {
                        key = "fx_" .. catKey,
                        filter = filter,
                        candidateFilters = candidates,
                        style = styleKey,
                        extraInit = function(slotButton, slotData, style)
                            -- Stamp category (applier filter gate) + refs (weak map, NEVER frame properties) +
                            -- create/arm visuals: the only window subtree calls are legal (earlier applyExtra call with refs nil bailed).
                            if slotData then slotData.dmCat = catKey end
                            fxRefs[slotButton] = { host = owner, health = hp }
                            slotButton:SetPoint("CENTER", hp, "CENTER")
                            slotButton:SetMouseMotionEnabled(false)
                            FxCreateVisuals(slotButton, slotData, tileKind, owner, hp, boxHolder)
                            if style then FxApply(slotButton, slotData, style) end
                        end,
                    })
                    tDecl["fx_" .. catKey] = AK.Filter(unpack(filter))
                end
            end
        end
        AK.FinishContainer(boxHolder, unitToken or "none")
        boxHolder._dmUnit = unitToken
        skinData.dmTiles[tileId] = boxHolder
        -- Re-drive this button's config so the fresh container gets its groups/counts/anchor (per-button, cheap).
        local debuffBox = skinData.rfcDebuffs
        if debuffBox then
            mod.DM_ApplyDebuffConfig(debuffBox, skinData, frameCfg, StyleKeyFor(skinData))
        end
    end, "rf:dm-tile")
    return nil
end

-------------------------------------------------------------------------------
-- The apply pass (owns the whole debuff-container config while active)
-------------------------------------------------------------------------------
function mod.DM_ApplyDebuffConfig(boxHolder, skinData, cfg, styleKey)
    AK = AK or CludesUI.AuraKit
    -- Default-ON: no dmDebuff table yet = the defaults (Show All + cc on).
    local dmCfg = DM() or {}
    local declared = skinData.rfcDebuffGroups
    if not (AK and declared) then return end

    local cap = cfg.debuffCap or 3
    local size = mod.RFC_DebuffSize(cfg)
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = cfg.debuffSpacing or 1, lineSpacing = cfg.debuffSpacing or 1,
    }
    -- Tooltip-modifier eaters: every footprint sum, stash and ensure below
    -- is gated on the feature being wanted, so the plain apply pays nothing.
    local tipOn = mod.DM_TipModWanted and mod.DM_TipModWanted() or false
    -- The same footprint counts seat the Party Frames kit's grid tiles.
    local geoOn = tipOn or (skinData.kit and true) or false

    local records, ccCand, claimMap, _, effectCats, matchOn = BuildRecords(cfg, dmCfg)

    -- Dead-corpse swap state rebuilds fresh every apply; a config that lost its
    -- npdead record sheds the swap here (the stale variant parks below).
    skinData.dmDeadSwap = nil
    local deadRec, ccParkCount

    -- Partition records: base container vs per-tile containers.
    local wantedBase, missingBase = {}, false
    local baseSizedCC = false -- sized cc record replaces the legacy cc group
    local tileRecs = {} -- [tileId] = array of records
    for i = 1, #records do
        local record = records[i]
        record.gkey = GroupKey(AK, record)
        if record.deadOnly then deadRec = record end
        if record.tile then
            local ident = record.tile.id
            local entries = tileRecs[ident]
            if not entries then entries = {}; tileRecs[ident] = entries end
            entries[#entries + 1] = record
        else
            if record.key == "cc" then baseSizedCC = true end
            wantedBase[record.gkey] = record
            if not declared[record.gkey] then missingBase = true end
        end
    end

    -- Park everything the base does not want (legacy preset groups, stale record variants); setters are dirty marks, runs only on an FP change.
    for k in pairs(declared) do
        if k ~= "cc" and not wantedBase[k] then
            CludesUI.AuraKit.SetGroupCap(boxHolder, k, 0)
        end
    end

    -- Crowd Control rides the existing cc group (CC glow intact) while enabled and UNCLAIMED; a claiming tile
    -- hosts it as a normal record instead (tile style, glow stays base-only).
    if declared.cc then
        -- A sized base cc record supplants the legacy group: park it or CC debuffs render twice. Under Show All
        -- the cc lead/glow group is on unless Crowd Control rides the hide lane (dm.neg.cc = subtracted); in add
        -- mode it is on exactly when the show lane checks it; fx routing forces it either way. Has Duration never
        -- flips this: cc surfaces are exempt from the duration fold (declaration-fixed candidates). Under Match
        -- All a picked cc lives inside the conjunction record (AND the rest), so the lead group stays parked.
        local baseView = BaseView(dmCfg)
        local allOn = baseView.all ~= false
        local ccHidden = baseView.neg ~= nil and baseView.neg.cc == true
        local ccPicked = (allOn and not ccHidden) or (not allOn and baseView.cc == true and not matchOn)
        local ccBase = (ccPicked or (effectCats and effectCats.cc)) and not claimMap.cc
            and not baseSizedCC
        ccParkCount = ccBase and cap or 0
        CludesUI.AuraKit.SetGroupCap(boxHolder, "cc", ccParkCount)
        boxHolder:SetAuraGroupCandidateFilters("cc", ccCand)
        boxHolder:SetAuraGroupLayout("cc", layout)
    end

    -- NO ASSIST GATE: records render on every unit, assistable or not. Candidate
    -- booleans (boss/role/Important/Can Apply) are never identity-gated by the
    -- engine -- only spell-ID candidates are, and those (the internal exclude
    -- set) ride every record alike -- so parking the boolean records on a
    -- non-assistable unit (Friendly Boss slots) would only hide correct
    -- content, and with the ownership fold the Non-Player record would drop
    -- Important debuffs there with nothing left to show them.

    -- Tooltip-eater footprint inputs (Shown on Modifier): the base row's
    -- maximum icon count = cap per DECLARED group, regardless of death
    -- parking (it flips live without a re-apply), plus the cc group's
    -- live count (0 while claimed, hidden or supplanted), and the largest
    -- cell (sized records).
    local tipN, tipCell = ccParkCount or 0, size

    -- Base records.
    local leadLayout
    for groupKey, region in pairs(wantedBase) do
        if declared[groupKey] then
            local recordSize = region.fxSize and EffectiveIconSize(skinData, region.fxSize)
            if geoOn then
                tipN = tipN + cap
                if recordSize and recordSize > tipCell then tipCell = recordSize end
            end
            local num = cap
            if region.deadOnly then num = 0 end -- parked until the death edge unparks it
            CludesUI.AuraKit.SetGroupCap(boxHolder, groupKey, num)
            boxHolder:SetAuraGroupCandidateFilters(groupKey, region.cand)
            if region.fxSize then
                -- Sized record: keep the stable per-category style fresh (size edits restyle existing buttons) + same size in the flow math.
                EnsureBaseSizeStyle(skinData, cfg, region.key, region.fxSize)
                boxHolder:SetAuraGroupLayout(groupKey, {
                    elementWidth = recordSize, elementHeight = recordSize,
                    elementSpacing = cfg.debuffSpacing or 1,
                    lineSpacing = cfg.debuffSpacing or 1,
                })
            elseif region.ccLead then
                -- The CC row's record form keeps the row's lead (flow order 0 sorts
                -- before every registered group).
                leadLayout = leadLayout or {
                    elementWidth = size, elementHeight = size,
                    elementSpacing = cfg.debuffSpacing or 1, lineSpacing = cfg.debuffSpacing or 1,
                    layoutIndex = 0,
                }
                boxHolder:SetAuraGroupLayout(groupKey, leadLayout)
            else
                boxHolder:SetAuraGroupLayout(groupKey, layout)
            end
        end
    end
    if geoOn then
        local tipGeo = skinData.dmTipGeo
        if not tipGeo then tipGeo = { tiles = {} }; skinData.dmTipGeo = tipGeo end
        local gb = tipGeo.base
        if not gb then gb = {}; tipGeo.base = gb end
        gb.n, gb.cell = tipN, tipCell
        -- Tiles re-stash below as they render (a tile that stopped
        -- rendering must not keep reserving room).
        wipe(tipGeo.tiles)
        -- Party Frames kit: the first grid tile seats under the base row.
        if skinData.kit and mod.RFC_DebuffPin then
            local _, _, _, by, _, bSpc, bPer, bVert = mod.RFC_DebuffPin(cfg)
            local _, bh = TipFootprint(tipN, tipCell, bSpc, bPer, bVert)
            tipGeo.kitY = by - ((bh > 0) and (bh + bSpc) or 0)
        else
            tipGeo.kitY = nil
        end
    end

    -- Base-hosted dead swap: park set = every normal base record (legacy cc group
    -- included) with its restore count; the death edge zeroes them and unparks npdead.
    if deadRec and not deadRec.tile and declared[deadRec.gkey] then
        local park = {}
        for groupKey, region in pairs(wantedBase) do
            if declared[groupKey] and not region.deadOnly then
                park[groupKey] = cap
            end
        end
        if declared.cc then park.cc = ccParkCount end
        skinData.dmDeadSwap = { show = deadRec.gkey, cap = cap, park = park }
    end

    -- Missing base record variants: declare on the combat-legal live lane, then re-apply (mirrors the containers file's preset-ensure pattern).
    if missingBase and not skinData.dmEnsure then
        skinData.dmEnsure = true
        AKWorker:Queue(function()
            skinData.dmEnsure = nil
            local debuffBox = skinData.rfcDebuffs
            local debuffGroups = skinData.rfcDebuffGroups
            if not (debuffBox and debuffGroups and mod.DM_Active()) then return end
            local frameCfg = SettingsFor(skinData)
            local liveCfg = DM() or {}
            if not frameCfg then return end
            local recs2 = BuildRecords(frameCfg, liveCfg)
            for i = 1, #recs2 do
                local region = recs2[i]
                if not region.tile then
                    local groupKey = GroupKey(AK, region)
                    if not debuffGroups[groupKey] then
                        -- Stamp category (per-filter EFFECTS match on it) and arm ICON EFFECTS in the creation
                        -- window (style applier ran before this stamp and found none). A Match All or Non-Player
                        -- split record stamps its category LIST (its key names the same list, so a group's list
                        -- never changes).
                        local catKey = region.cats or region.key
                        -- Sized records bind their per-category sized style (buttons take physical size at creation);
                        -- the CC row's record form binds the row's own CC-glow style (the containers
                        -- file builds it beside the base debuff style) and leads the row.
                        local sk = region.fxSize
                            and EnsureBaseSizeStyle(skinData, frameCfg, region.key, region.fxSize)
                            or (region.ccLead and ("rf:debuffcc:" .. ClassToken(skinData)))
                            or StyleKeyFor(skinData)
                        local groupSize = region.fxSize
                            and EffectiveIconSize(skinData, region.fxSize) or mod.RFC_DebuffSize(frameCfg)
                        local groupSpacing = frameCfg.debuffSpacing or 1
                        AK.AddGroupToContainer(debuffBox, {
                            key = groupKey,
                            filter = region.tokens,
                            candidateFilters = region.cand,
                            maxFrameCount = 0,
                            style = sk,
                            layout = {
                                elementWidth = groupSize, elementHeight = groupSize,
                                elementSpacing = groupSpacing, lineSpacing = groupSpacing,
                                layoutIndex = (region.ccLead and not region.fxSize) and 0 or nil,
                            },
                            extraInit = function(btn2, slotData, style)
                                if slotData then slotData.dmCat = catKey end
                                if style and mod.RFC_ApplyDmFx then
                                    mod.RFC_ApplyDmFx(btn2, slotData, style)
                                end
                            end,
                        })
                        debuffGroups[groupKey] = true
                    end
                end
            end
            mod.DM_ApplyDebuffConfig(debuffBox, skinData, frameCfg, StyleKeyFor(skinData))
        end, "rf:dm-ensure")
    end

    -- Tiles. Stash the host ref the deferred tile builds need (the base debuff container is parented to the unit button on every build path).
    skinData.dmHost = skinData.dmHost or (boxHolder.GetParent and boxHolder:GetParent())
    -- The ACTIVE union: tiles from buckets the current spec doesn't render
    -- (spec swaps, per-spec disables) fall out of `present` below and park
    -- their containers exactly like a deleted tile.
    local dmTiles = mod.DM_ActiveTiles()
    local live = skinData.dmTiles
    if dmTiles then
        for i = 1, #dmTiles do
            local tileDef = dmTiles[i]
            local recsFor = tileRecs[tileDef.id]
            local isEffect = tileDef.type ~= "icons" and tileDef.type ~= "square"
            local isActive = tileDef.enabled and (isEffect or (recsFor and #recsFor > 0))
            if isActive then
                local tileHost = EnsureTileContainer(skinData, tileDef)
                if tileHost then
                    -- Back from a park: switched on again before it is configured (re-pointed below).
                    UnparkTileContainer(tileHost)
                    local tStyleKey = EnsureTileStyle(skinData, cfg, tileDef)
                    -- Back from the stale sweep: its overlays left the bar's registry and
                    -- missed any fill swap or fill direction change meanwhile.
                    if tileHost._dmSwept then
                        tileHost._dmSwept = nil
                        tileHost._dmRestyle = true
                    end
                    if tileHost._dmRestyle then
                        -- Restored healthcolor container: repaint re-registers its overlays on the bar
                        -- and re-anchors them to the current fill direction (FxApplyInner).
                        tileHost._dmRestyle = nil
                        AK.RestyleSoon(tStyleKey)
                    end
                    local tDecl = tileHost._dmDecl

                    if isEffect then
                        -- One live-settable slot PER CHECKED category: filter setter takes the NORMALIZED string,
                        -- candidates an explicit empty table (NEVER nil -- NP field lesson); newly-checked categories without a slot add on the combat-legal live lane below.
                        local missingCats = false
                        local cs = EffectCatSet(tileDef)
                        if cs then
                            for category in pairs(cs) do
                                local skey = "fx_" .. category
                                local filter, candidates = EffectFilterForTile(dmCfg, tileDef, category)
                                if tDecl[skey] then
                                    local fsig = AK.Filter(unpack(filter))
                                    if tDecl[skey] ~= fsig then
                                        tileHost:SetAuraSlotFilterString(skey, fsig)
                                        tDecl[skey] = fsig
                                    end
                                    tileHost:SetAuraSlotCandidateFilters(skey, candidates or {})
                                else
                                    missingCats = true
                                end
                            end
                        end
                        if missingCats then
                            local pendKey = "fx" .. tostring(tileDef.id)
                            local pend = skinData.dmTilePend
                            if not pend then pend = {}; skinData.dmTilePend = pend end
                            if not pend[pendKey] then
                                pend[pendKey] = true
                                local tileId = tileDef.id
                                AKWorker:Queue(function()
                                    skinData.dmTilePend[pendKey] = nil
                                    local tc2 = skinData.dmTiles and skinData.dmTiles[tileId]
                                    local decl2 = tc2 and tc2._dmDecl
                                    if not (decl2 and mod.DM_Active()) then return end
                                    local frameCfg = SettingsFor(skinData)
                                    local liveCfg = DM() or {}
                                    if not frameCfg then return end
                                    -- Active-union re-resolve (delete/spec
                                    -- swap/per-spec disable between queue and
                                    -- run = skip).
                                    local activeTiles = mod.DM_ActiveTiles()
                                    local liveTile
                                    if activeTiles then
                                        for ti2 = 1, #activeTiles do
                                            if activeTiles[ti2].id == tileId then liveTile = activeTiles[ti2] break end
                                        end
                                    end
                                    local owner = skinData.dmHost
                                    local hp = skinData.rfcHealth
                                    -- Effect slots only ever go on an effect container of the tile's current type; a flip
                                    -- to a grid tile (its icons container restored meanwhile) was configured by that apply.
                                    if not (liveTile and owner and hp and tc2._dmType == liveTile.type) then return end
                                    if liveTile.type == "icons" or liveTile.type == "square" then return end
                                    local styleKey2 = EnsureTileStyle(skinData, frameCfg, liveTile)
                                    local tileKind = liveTile.type
                                    local cs2 = EffectCatSet(liveTile)
                                    for category in pairs(cs2 or {}) do
                                        local skey = "fx_" .. category
                                        if not decl2[skey] then
                                            local catKey = category
                                            local filter, candidates = EffectFilterForTile(liveCfg, liveTile, catKey)
                                            AK.AddSlotToContainer(tc2, {
                                                key = skey,
                                                filter = filter,
                                                candidateFilters = candidates,
                                                style = styleKey2,
                                                extraInit = function(slotButton, slotData, style)
                                                    if slotData then slotData.dmCat = catKey end
                                                    fxRefs[slotButton] = { host = owner, health = hp }
                                                    slotButton:SetPoint("CENTER", hp, "CENTER")
                                                    slotButton:SetMouseMotionEnabled(false)
                                                    FxCreateVisuals(slotButton, slotData, tileKind, owner, hp, tc2)
                                                    if style then FxApply(slotButton, slotData, style) end
                                                end,
                                            })
                                            decl2[skey] = AK.Filter(unpack(filter))
                                        end
                                    end
                                    local debuffBox = skinData.rfcDebuffs
                                    if debuffBox then mod.DM_ApplyDebuffConfig(debuffBox, skinData, frameCfg, StyleKeyFor(skinData)) end
                                end, "rf:dm-fx-slots")
                            end
                        end
                    else
                        -- Record groups on the tile container (variant keys, additive declares, park stale variants).
                        local tWanted = {}
                        local tMissing = false
                        for ri = 1, #recsFor do
                            local region = recsFor[ri]
                            tWanted[region.gkey] = region
                            if not tDecl[region.gkey] then tMissing = true end
                        end
                        for k in pairs(tDecl) do
                            if tWanted[k] == nil then
                                CludesUI.AuraKit.SetGroupCap(tileHost, k, 0)
                            end
                        end
                        local tCap = tileDef.cap or cap
                        local tSize = EffectiveIconSize(skinData, tileDef.size or 18)
                        local tLayout = {
                            elementWidth = tSize, elementHeight = tSize,
                            elementSpacing = tileDef.spacing or 1, lineSpacing = tileDef.spacing or 1,
                        }
                        -- Tooltip-eater footprint inputs for this tile (see the base site).
                        local tN, tCell = 0, tSize
                        for groupKey, region in pairs(tWanted) do
                            if tDecl[groupKey] then
                                local recordSize = region.fxSize and EffectiveIconSize(skinData, region.fxSize)
                                if geoOn then
                                    tN = tN + tCap
                                    if recordSize and recordSize > tCell then tCell = recordSize end
                                end
                                local num = tCap
                                if region.deadOnly then num = 0 end -- parked until the death edge unparks it
                                CludesUI.AuraKit.SetGroupCap(tileHost, groupKey, num)
                                tileHost:SetAuraGroupCandidateFilters(groupKey, region.cand)
                                if region.fxSize then
                                    -- Sized record: per-category tile style variant fresh + matching flow math.
                                    EnsureTileStyle(skinData, cfg, tileDef, region.fxSize, region.key)
                                    tileHost:SetAuraGroupLayout(groupKey, {
                                        elementWidth = recordSize, elementHeight = recordSize,
                                        elementSpacing = tileDef.spacing or 1,
                                        lineSpacing = tileDef.spacing or 1,
                                    })
                                else
                                    tileHost:SetAuraGroupLayout(groupKey, tLayout)
                                end
                            end
                        end
                        if geoOn then
                            local tipGeo = skinData.dmTipGeo
                            if not tipGeo then tipGeo = { tiles = {} }; skinData.dmTipGeo = tipGeo end
                            local gt = tipGeo.tiles[tileDef.id]
                            if not gt then gt = {}; tipGeo.tiles[tileDef.id] = gt end
                            gt.n, gt.cell = tN, tCell
                            -- Party Frames kit: this tile's seat, then the next
                            -- one's below it (one block per tile, flowing right).
                            gt.kitY = tipGeo.kitY
                            if tipGeo.kitY then
                                local _, th = TipFootprint(tN, tCell, tileDef.spacing or 1,
                                    tonumber(tileDef.iconsPerRow) or 0, false)
                                if th > 0 then tipGeo.kitY = tipGeo.kitY - th - (tileDef.spacing or 1) end
                            end
                        end
                        if tMissing then
                            -- Combat-legal group adds on the existing tile container; keyed ensure per tile.
                            local pendKey = "g" .. tostring(tileDef.id)
                            local pend = skinData.dmTilePend
                            if not pend then pend = {}; skinData.dmTilePend = pend end
                            if not pend[pendKey] then
                                pend[pendKey] = true
                                local tileId = tileDef.id
                                AKWorker:Queue(function()
                                    skinData.dmTilePend[pendKey] = nil
                                    local tc2 = skinData.dmTiles and skinData.dmTiles[tileId]
                                    local decl2 = tc2 and tc2._dmDecl
                                    if not (decl2 and mod.DM_Active()) then return end
                                    local frameCfg = SettingsFor(skinData)
                                    local liveCfg = DM() or {}
                                    if not frameCfg then return end
                                    local recs2 = BuildRecords(frameCfg, liveCfg)
                                    for ri = 1, #recs2 do
                                        local region = recs2[ri]
                                        if region.tile and region.tile.id == tileId and region.tile.type == tc2._dmType then
                                            local groupKey = GroupKey(AK, region)
                                            if not decl2[groupKey] then
                                                local catKey = region.cats or region.key
                                                local groupSize = EffectiveIconSize(skinData,
                                                    region.fxSize or region.tile.size or 18)
                                                local groupSpacing = region.tile.spacing or 1
                                                AK.AddGroupToContainer(tc2, {
                                                    key = groupKey,
                                                    filter = region.tokens,
                                                    candidateFilters = region.cand,
                                                    maxFrameCount = 0,
                                                    -- Sized records bind the per-category sized tile-style variant.
                                                    style = region.fxSize
                                                        and EnsureTileStyle(skinData, frameCfg, region.tile, region.fxSize, region.key)
                                                        or EnsureTileStyle(skinData, frameCfg, region.tile),
                                                    layout = {
                                                        elementWidth = groupSize, elementHeight = groupSize,
                                                        elementSpacing = groupSpacing, lineSpacing = groupSpacing,
                                                    },
                                                    extraInit = function(btn2, slotData, style)
                                                        if slotData then slotData.dmCat = catKey end
                                                        -- Arm ICON EFFECTS in the creation window (see the base-record site).
                                                        if style and mod.RFC_ApplyDmFx then
                                                            mod.RFC_ApplyDmFx(btn2, slotData, style)
                                                        end
                                                    end,
                                                })
                                                decl2[groupKey] = true
                                            end
                                        end
                                    end
                                    local debuffBox = skinData.rfcDebuffs
                                    if debuffBox then mod.DM_ApplyDebuffConfig(debuffBox, skinData, frameCfg, StyleKeyFor(skinData)) end
                                end, "rf:dm-tile-groups")
                            end
                        end
                        -- Tile-hosted dead swap: park set = the tile's normal records with restore counts.
                        if deadRec and deadRec.tile == tileDef and tDecl[deadRec.gkey] then
                            local park = {}
                            for groupKey, region in pairs(tWanted) do
                                if tDecl[groupKey] and not region.deadOnly then
                                    park[groupKey] = tCap
                                end
                            end
                            skinData.dmDeadSwap = { show = deadRec.gkey, cap = tCap, park = park, tileId = tileDef.id }
                        end
                        AnchorTileContainer(tileHost, skinData.rfcHealth, cfg, tileDef, skinData)
                    end

                    -- Shown on every unit (no assist gate, see the base records).
                    tileHost:Show()
                    -- Same-unit re-sets are a full engine re-registration (the RF roster-reprocess storm lesson), so stamp on our own container frame and re-point on change.
                    if skinData.rfcUnit and tileHost._dmUnit ~= skinData.rfcUnit then
                        tileHost:SetUnit(skinData.rfcUnit)
                        tileHost:UpdateAllAuras()
                        tileHost._dmUnit = skinData.rfcUnit
                    end
                end
            elseif live and live[tileDef.id] then
                ParkTileContainer(live[tileDef.id])
            end
        end
    end
    -- Stale containers from deleted tiles (or another profile) park hidden.
    if live then
        local present = {}
        if dmTiles then
            for i = 1, #dmTiles do present[dmTiles[i].id] = true end
        end
        for ident, c in pairs(live) do
            if not present[ident] then
                ParkTileContainer(c)
                -- A parked container keeps its slot buttons, so a healthcolor tile's
                -- overlays would stay registered on the health bar and every later
                -- layout pass would walk them for the session. Only this container's
                -- own are dropped (they are keyed to it): live tiles stay registered,
                -- so a fill swap or fill direction change still re-anchors them. It
                -- restyles once if it comes back (_dmSwept, the tile loop above).
                if c._dmType == "healthcolor" then
                    if skinData.rfcHealth then mod.RF_ClearBarTints(skinData.rfcHealth, c) end
                    c._dmSwept = true
                end
            end
        end
    end

    -- Party Frames kit: the lowest seat the debuffs reach below the frame
    -- (the base row's footprint, then every grid tile), which the Friendly
    -- Boss group clears below horizontal frames. Every party button reads
    -- one settings view, so any button's value is the floor.
    if skinData.kit and skinData._isParty then
        local floor = skinData.dmTipGeo and skinData.dmTipGeo.kitY
        if floor ~= mod._kitDmFloor then
            mod._kitDmFloor = floor
            if mod.FB_ReAnchor then mod.FB_ReAnchor() end
        end
    end

    -- Sync the dead swap to the unit's actual state: the count loops above wrote
    -- alive-shape counts, so a corpse existing at apply time (config change while
    -- someone is dead) must swap now -- no later event is guaranteed on a corpse.
    skinData.dmDead = nil
    if skinData.dmDeadSwap and skinData.rfcUnit then mod.DM_DeadEdge(skinData, skinData.rfcUnit) end

    -- Tooltip-modifier eaters: footprint inputs above are fresh, and tile
    -- containers built on the deferred lanes re-enter through this apply.
    -- Off: nothing runs here (the containers reload's ensure parks on a flip).
    if tipOn and mod.DM_TipModEnsure and skinData.dmHost then mod.DM_TipModEnsure(skinData.dmHost, skinData, cfg) end
end

-- Death-edge hook (from the UNIT_HEALTH repaint path, unit assignment, and the
-- apply tail). Change-gated on d.dmDead; d.dmDeadSwap is nil for every button
-- unless a config qualifies, so the hot-path cost is one field read. Count flips
-- re-render engine-side; where a cap of 0 also switches the group off (12.1.5+,
-- AuraKit.SetGroupCap) a group switched back on re-parses once.
function mod.DM_DeadEdge(skinData, unitToken)
    local swap = skinData.dmDeadSwap
    if not swap or not unitToken then return end
    local dead = UnitIsDeadOrGhost(unitToken) and true or false
    if skinData.dmDead == dead then return end
    skinData.dmDead = dead
    -- A tile swap never falls back to the base container: its keys are tile group keys.
    local c
    if swap.tileId then c = skinData.dmTiles and skinData.dmTiles[swap.tileId] else c = skinData.rfcDebuffs end
    if not c then return end
    if dead then
        for k in pairs(swap.park) do CludesUI.AuraKit.SetGroupCap(c, k, 0) end
        CludesUI.AuraKit.SetGroupCap(c, swap.show, swap.cap)
    else
        for k, num in pairs(swap.park) do CludesUI.AuraKit.SetGroupCap(c, k, num) end
        CludesUI.AuraKit.SetGroupCap(c, swap.show, 0)
    end
end

-- Legacy-config tail hook: while INACTIVE the legacy ApplyDebuffConfig drives only its own preset groups, so a
-- just-disabled manager's record variants and tile containers would otherwise keep rendering.
function mod.DM_ParkGroups(boxHolder, declared, skinData)
    for k in pairs(declared) do
        if k:sub(1, 3) == "dm_" then
            CludesUI.AuraKit.SetGroupCap(boxHolder, k, 0)
        end
    end
    if skinData and skinData.dmTiles then
        for _, c in pairs(skinData.dmTiles) do ParkTileContainer(c) end
    end
end

-- Unit re-assignment hook (from RFC_OnUnitAssigned's unit-change branch): tile containers must re-point like every
-- per-button container; the engine does not re-parse on unit change alone.
function mod.DM_OnUnitAssigned(skinData, unitToken)
    -- New unit, unknown dead state: force the dead swap to re-evaluate.
    if skinData.dmDeadSwap then
        skinData.dmDead = nil
        mod.DM_DeadEdge(skinData, unitToken)
    end
    local tiles = skinData.dmTiles
    if not tiles then return end
    for _, c in pairs(tiles) do
        -- The container's own binding, not the stamp beside it: the stamp is a
        -- shadow, and a re-point that reaches the container by any other route
        -- would leave it lying about what the tile is actually parsing. A parked
        -- one stays on no unit until the apply that shows it re-points it.
        if not c._dmParked and c:GetUnit() ~= unitToken then
            c:SetUnit(unitToken)
            c:UpdateAllAuras()
            c._dmUnit = unitToken
        end
    end
end

-------------------------------------------------------------------------------
-- Tile list editing API (consumed by the options page)
-------------------------------------------------------------------------------
-- Read-heals shared by every bucket: expand the old single-cat + width/
-- height square shape, effect single-cat, fx single-config and healthcolor
-- alpha once. Legacy shapes only ever existed in the all-specs array, but
-- healing everywhere is idempotent and keeps one path.
local function HealTiles(arr)
    for i = 1, #arr do
        local tileDef = arr[i]
        if tileDef.type == "square" and not tileDef.claim then
            tileDef.claim = {}
            if tileDef.cat then tileDef.claim[tileDef.cat] = true; tileDef.cat = nil end
            local sz = tileDef.width or tileDef.height
            if sz and sz > 0 then tileDef.size = sz end
            tileDef.width, tileDef.height = nil, nil
            tileDef.growDirection = tileDef.growDirection or "CENTER"
            tileDef.spacing = tileDef.spacing or 1
            tileDef.cap = tileDef.cap or 3
        end
        -- Effect tiles moved from a single t.cat to the filter set; expand once.
        if (tileDef.type == "glow" or tileDef.type == "healthcolor" or tileDef.type == "bar")
            and not tileDef.claim then
            tileDef.claim = {}
            if tileDef.cat then tileDef.claim[tileDef.cat] = true; tileDef.cat = nil end
        end
        -- Effects single-config -> block list (one-time).
        FxHeal(tileDef)
        -- Health color: stored swatch alpha -> the Opacity setting (one-time).
        if tileDef.type == "healthcolor" and tileDef.opacity == nil and tileDef.color and tileDef.color.a then
            tileDef.opacity = math.floor((tileDef.color.a * 100) + 0.5)
        end
    end
end

-- The ALL-SPECS bucket: the legacy dm.tiles array, IN PLACE (zero
-- migration; profiles opened by older builds keep rendering it).
function mod.DM_Tiles()
    local dmCfg = DM()
    if not dmCfg then return nil end
    if not dmCfg.tiles then dmCfg.tiles = {} end
    HealTiles(dmCfg.tiles)
    return dmCfg.tiles
end

-------------------------------------------------------------------------------
-- Editing-spec buckets. dm.tiles IS "allspecs"; every other bucket lives
-- under dm.specTiles[key] = { tiles, inhDis, baseOff }, key = "nonhealer"/"tanks"/
-- "dps"/"healers" (group buckets) or "spec<ID>" (a concrete spec -- healer
-- specs included; the Debuff Manager has no healer-key legacy). Tile ids
-- stay globally unique across buckets (one shared dm.nextTileId), so
-- per-spec disables key on the bare tile id. Absent specTiles = feature
-- unused = the active union degenerates to the legacy array.
-------------------------------------------------------------------------------
local function SpecBucket(dmCfg, key, create)
    local tileStyle = dmCfg.specTiles
    if not tileStyle then
        if not create then return nil end
        tileStyle = {}; dmCfg.specTiles = tileStyle
    end
    local b = tileStyle[key]
    if not b then
        if not create then return nil end
        b = { tiles = {}, inhDis = {} }
        tileStyle[key] = b
    end
    if not b.tiles then b.tiles = {} end
    if not b.inhDis then b.inhDis = {} end
    return b
end

-- WoW Forever: a class acts as the first of its retail specs (class order)
-- whose "spec<ID>" bucket holds data (tiles, per-spec disables or Base
-- Icons off), else its first spec. Class rows edit that same bucket.
function mod.DM_BucketHasData(ident, tileStyle)
    local b = tileStyle and tileStyle["spec" .. ident]
    if b == nil then return false end
    if (b.tiles and #b.tiles > 0) or b.baseOff == true then return true end
    local dis = b.inhDis
    if not (dis and next(dis) ~= nil) then return false end
    if not CludesUI.IS_FOREVER then return true end
    -- WoW Forever renders All Specs and the class's own bucket only, so only
    -- a disable of an All Specs tile counts. Scans dm.tiles in place and
    -- never creates it.
    local dmCfg = DM()
    local base = dmCfg and dmCfg.tiles
    for i = 1, (base and #base or 0) do
        if dis[base[i].id] then return true end
    end
    return false
end
-- While a spec override's Debuff Manager fork is live (outside a
-- conditional's editing session), the player's class acts as the spec that
-- fork serves instead (published by Spec Overrides, seeded from the saved
-- pointer at the first read).
function mod.DM_ForeverSpecID(token)
    if not CludesUI._SO_DmForkSeeded then CludesUI._SO_SeedForkSpec(true) end
    local fk = CludesUI.SpecOverrides_DmForkSpecID
    if fk and not CludesUI._dmSessionGid
       and (token == nil or token == CludesUI.SpecClassOf(fk)) then
        return fk
    end
    local dmCfg = DM()
    return CludesUI.ForeverClassSpec(token, mod.DM_BucketHasData, dmCfg and dmCfg.specTiles)
end
function mod.DM_ForeverKey(token)
    local spellRef = mod.DM_ForeverSpecID(token)
    return spellRef and ("spec" .. spellRef) or nil
end

-- Bucket tile array for an EDITED view ("allspecs"/nil = the legacy array).
function mod.DM_BucketTiles(key, create)
    if not key or key == "allspecs" then return mod.DM_Tiles() end
    local dmCfg = DM()
    if not dmCfg then return nil end
    local b = SpecBucket(dmCfg, key, create)
    if not b then return nil end
    HealTiles(b.tiles)
    return b.tiles
end

-- Per-spec disable of a GROUP bucket's tile, stored on the viewing spec's
-- concrete "spec<ID>" bucket (ids are global, so the bare id suffices).
function mod.DM_InhDisabled(concreteKey, ident)
    local dmCfg = DM()
    local b = dmCfg and SpecBucket(dmCfg, concreteKey, false)
    return (b and b.inhDis[ident]) and true or false
end

function mod.DM_SetInhDisabled(concreteKey, ident, disabled)
    local dmCfg = DM()
    if not (dmCfg and concreteKey and ident) then return end
    local b = SpecBucket(dmCfg, concreteKey, true)
    b.inhDis[ident] = disabled and true or nil
end

-- Per-spec disable of the Base Icons grid (the All Specs base, inherited by
-- every concrete spec like an All Specs tile): b.baseOff on the viewing
-- spec's bucket, beside the tile disables.
function mod.DM_BaseDisabled(concreteKey)
    local dmCfg = DM()
    local b = dmCfg and SpecBucket(dmCfg, concreteKey, false)
    return (b and b.baseOff) and true or false
end

function mod.DM_SetBaseDisabled(concreteKey, disabled)
    local dmCfg = DM()
    if not (dmCfg and concreteKey) then return end
    local b = SpecBucket(dmCfg, concreteKey, true)
    b.baseOff = disabled and true or nil
end

-- Runtime read for the player's CURRENT spec (record synthesis + FP). No
-- specTiles = buckets never used = zero cost.
function mod.DM_CurrentSpecBaseOff()
    local dmCfg = DM()
    local tileStyle = dmCfg and dmCfg.specTiles
    if not tileStyle then return false end
    local index = GetSpecialization and GetSpecialization()
    local spellRef = index and GetSpecializationInfo and GetSpecializationInfo(index) or nil
    if CludesUI.IS_FOREVER then spellRef = mod.DM_ForeverSpecID() end
    local b = spellRef and tileStyle["spec" .. spellRef] or nil
    return (b and b.baseOff) and true or false
end

-- The union a spec renders (sid = its spec ID, nil = no spec yet), in bucket
-- order (allspecs, nonhealer, role group, own spec); group tiles the spec has
-- per-spec disabled drop out here. Returns a FRESH array per call -- the
-- apply pass iterates one while nested BuildRecords/EffectiveState calls
-- build another, so a reused scratch would be wiped under the iterator.
-- Config-pass frequency only (never per-frame), so the allocation is fine.
-- The tile TABLES inside are the stable store tables. Role/tracked
-- resolution rides the Buff Manager helpers (same ns, resolved at call
-- time).
local function UnionFor(dmCfg, spellRef)
    -- Read dm.tiles WITHOUT materializing it (DM_Tiles creates the array;
    -- this runs on the runtime config path and must not write an empty
    -- table into every tile-less profile's SavedVariables).
    local base = dmCfg.tiles
    if base then HealTiles(base) end
    local result = {}
    local tileStyle = dmCfg.specTiles
    local con = tileStyle and spellRef and tileStyle["spec" .. spellRef] or nil
    local dis = con and con.inhDis or nil
    if base then
        for i = 1, #base do
            local tileDef = base[i]
            if not (dis and dis[tileDef.id]) then result[#result + 1] = tileDef end
        end
    end
    if tileStyle and spellRef then
        local function AddBucket(key, filtered)
            local b = tileStyle[key]
            local tileList = b and b.tiles
            if not tileList then return end
            HealTiles(tileList)
            for i = 1, #tileList do
                local tileDef = tileList[i]
                if not (filtered and dis and dis[tileDef.id]) then result[#result + 1] = tileDef end
            end
        end
        -- WoW Forever: a class renders All Specs and its own bucket only
        -- (group buckets are not offered there).
        if not CludesUI.IS_FOREVER and not (mod.BM_SpecKeyForSpecID and mod.BM_SpecKeyForSpecID(spellRef)) then
            AddBucket("nonhealer", true)
        end
        local roleKey = mod.BM_RoleBucketForSpecID and mod.BM_RoleBucketForSpecID(spellRef)
        if roleKey then AddBucket(roleKey, true) end
        AddBucket("spec" .. spellRef, false)
    end
    return result
end

-- The ACTIVE union: every tile the CURRENT spec renders (UnionFor).
function mod.DM_ActiveTiles()
    local dmCfg = DM()
    if not dmCfg then return nil end
    local index = GetSpecialization and GetSpecialization()
    local spellRef = index and GetSpecializationInfo and GetSpecializationInfo(index) or nil
    if CludesUI.IS_FOREVER then spellRef = mod.DM_ForeverSpecID() end
    return UnionFor(dmCfg, spellRef)
end

-- The union an options-page VIEW renders, in the same order: a concrete
-- "spec<ID>" view is that spec's, All Specs is the current spec's, and a
-- group view is All Specs, then All Non Healers/Aug under a tank or damage
-- group, then its own tiles. Never materializes a bucket.
function mod.DM_ViewTiles(view)
    local dmCfg = DM()
    if not dmCfg then return nil end
    if not view or view == "allspecs" then return mod.DM_ActiveTiles() end
    local match = type(view) == "string" and view:match("^spec(%d+)$")
    if match then return UnionFor(dmCfg, tonumber(match)) end
    local result = {}
    local function Add(entries)
        if not entries then return end
        HealTiles(entries)
        for i = 1, #entries do result[#result + 1] = entries[i] end
    end
    Add(dmCfg.tiles)
    local tileStyle = dmCfg.specTiles
    if tileStyle then
        if view == "tanks" or view == "dps" then Add(tileStyle.nonhealer and tileStyle.nonhealer.tiles) end
        Add(tileStyle[view] and tileStyle[view].tiles)
    end
    return result
end

-- Owner hints for the options page over a view's union (ns.DM_ViewTiles):
-- claims[cat] = the indicator that shows cat, claimsAll = the indicator
-- hosting the indicator catch-all, pos[tile] = its place in that order.
function mod.DM_ClaimOwners(view)
    local tiles = mod.DM_ViewTiles(view)
    local claimMap, claimsAll = ClaimMap(tiles)
    local place = {}
    if tiles then
        for i = 1, #tiles do place[tiles[i]] = i end
    end
    return claimMap, claimsAll, place
end

function mod.DM_AddTile(tileType, bucketKey)
    local profile = mod.db and mod.db.profile
    if not profile then return nil end
    local dmCfg = profile.dmDebuff
    if not dmCfg then dmCfg = {}; profile.dmDebuff = dmCfg end
    if not dmCfg.tiles then dmCfg.tiles = {} end
    local ident = (dmCfg.nextTileId or 1)
    -- Counter heal: ids must stay GLOBALLY unique across every bucket
    -- (per-spec disables key on the bare id), so a reset/hand-edited
    -- counter re-bases above every existing tile before allocating.
    do
        local maxId = 0
        for i = 1, #dmCfg.tiles do
            local tid = tonumber(dmCfg.tiles[i].id) or 0
            if tid > maxId then maxId = tid end
        end
        if dmCfg.specTiles then
            for _, b in pairs(dmCfg.specTiles) do
                local tileList = b.tiles
                if tileList then
                    for i = 1, #tileList do
                        local tid = tonumber(tileList[i].id) or 0
                        if tid > maxId then maxId = tid end
                    end
                end
            end
        end
        if ident <= maxId then ident = maxId + 1 end
    end
    dmCfg.nextTileId = ident + 1
    local tileDef = { id = ident, enabled = true, type = tileType or "icons" }
    if tileDef.type == "icons" or tileDef.type == "square" then
        -- Grid tiles (Icon / Square): identical shape; squares add a color.
        tileDef.claim = {}
        tileDef.position = "top"
        tileDef.growDirection = "CENTER"
        tileDef.size = 18
        tileDef.spacing = 1
        tileDef.cap = 3
        if tileDef.type == "square" then
            tileDef.color = { r = 1, g = 0.35, b = 0.35, a = 1 }
        end
    else
        -- Effect tiles: filters come from the checkbox dropdown or the Add New popup's picks; none checked = nothing.
        tileDef.claim = {}
        if tileDef.type == "bar" then
            tileDef.position = "bottom"; tileDef.width = 60; tileDef.height = 5
            tileDef.orientation = "HORIZONTAL"
            tileDef.color = { r = 0.25, g = 0.8, b = 0.45 }
            tileDef.barColorOpacity = 100
            tileDef.barBgColor = { r = 0, g = 0, b = 0 }
            tileDef.barBgOpacity = 50
            tileDef.frameLevel = "behindBorders"
        elseif tileDef.type == "healthcolor" then
            tileDef.color = { r = 1, g = 0.25, b = 0.25 }
            tileDef.opacity = 45
        else -- glow
            tileDef.glowType = 1
            tileDef.color = { r = 1, g = 0.78, b = 0.38, a = 1 }
        end
    end
    -- The edited bucket owns the new tile; ids come from the ONE shared
    -- counter above regardless of bucket.
    local target = dmCfg.tiles
    if bucketKey and bucketKey ~= "allspecs" then
        target = SpecBucket(dmCfg, bucketKey, true).tiles
    end
    target[#target + 1] = tileDef
    return tileDef
end

-- Deep-copies a tile into another bucket (the right-click "Add To" menu):
-- full settings clone under a fresh GLOBAL id; the source is untouched.
-- DM_AddTile owns bucket creation + the healed id allocation; its default
-- fields are then replaced wholesale by the clone (id kept).
function mod.DM_CopyTile(source, bucketKey)
    if not source then return nil end
    local tileDef = mod.DM_AddTile(source.type, bucketKey)
    if not tileDef then return nil end
    local keep = tileDef.id
    for k in pairs(tileDef) do tileDef[k] = nil end
    for k, val in pairs(CopyTable(source)) do tileDef[k] = val end
    tileDef.id = keep
    return tileDef
end

function mod.DM_DeleteTile(ident)
    local dmCfg = DM()
    if not dmCfg then return end
    if dmCfg.tiles then
        for i = #dmCfg.tiles, 1, -1 do
            if dmCfg.tiles[i].id == ident then table.remove(dmCfg.tiles, i) end
        end
    end
    local tileStyle = dmCfg.specTiles
    if tileStyle then
        for _, b in pairs(tileStyle) do
            local tileList = b.tiles
            if tileList then
                for i = #tileList, 1, -1 do
                    if tileList[i].id == ident then table.remove(tileList, i) end
                end
            end
            -- Sweep the per-spec disable keys everywhere: ids are global and
            -- never reused, so a deleted tile's key can only leak.
            if b.inhDis then b.inhDis[ident] = nil end
        end
    end
end




-------------------------------------------------------------------------------
-- Override-layer bridge (SpecOverrides DM layers): a fork is a wholesale deep copy of the profile's dmDebuff table.
-- Both hooks run EnsureMigrated first, so the one-shot preset mapping always precedes any fork traffic.
-------------------------------------------------------------------------------

-- Snapshot of the live Debuff Manager config for layer harvests.
function _G._CURF_DMHarvestFork()
    local profile = mod.db and mod.db.profile
    if not profile then return nil end
    EnsureMigrated()
    local dmCfg = profile.dmDebuff
    if type(dmCfg) ~= "table" then return nil end
    return CopyTable(dmCfg)
end

-- Applies a SpecOverrides DM layer into the live profile (wipe + refill in place: open manager pages capture
-- subtable refs) and re-drives the container runtime (DM_CfgFP flips on content change).
function _G._CURF_DMApplyLayer(dmCfg, noPageRefresh)
    if type(dmCfg) ~= "table" then return false end
    local profile = mod.db and mod.db.profile
    if not profile then return false end
    EnsureMigrated()
    local live = profile.dmDebuff
    if type(live) ~= "table" then live = {}; profile.dmDebuff = live end
    wipe(live)
    for k, val in pairs(CopyTable(dmCfg)) do live[k] = val end
    if mod.RFC_ReloadAll then mod.RFC_ReloadAll() end
    if not noPageRefresh and mod._dmRoot and CludesUI and CludesUI.RefreshPage then
        CludesUI:RefreshPage(true)
    end
    return true
end
