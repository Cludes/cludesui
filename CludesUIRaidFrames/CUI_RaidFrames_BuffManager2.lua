if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_RaidFrames_BuffManager2.lua
-- 12.1 Buff Manager v2: the spell -> filter -> indicator model.
-- FILTERS are named spell sets: presets ship with the addon (rename/delete
-- locked, curated lists), users add custom filters and spell IDs, every spell
-- has an on/off checkbox. INDICATORS consume filters and/or direct spells;
-- the runtime set is the UNION of direct spells and assigned filters' enabled
-- spells. Buff spellID filtering is engine-legal on friendly units (helpful
-- auras on assistable targets pass the identity gate). Class tags are UI
-- grouping ONLY: the runtime includes every enabled spell, since externals/
-- raid CDs are cast BY other classes. There is NO base grid for buffs (unlike
-- the Debuff Manager); three ordinary indicator groups seed per spec instead:
-- "Defensives & Utility" (Defensives + Raid CDs + Utility + Externals)
-- center, "Core Healing Buffs" top left, "Lesser Healing Buffs" top right.
-- The Defensives & Utility group's position migrates from the retired
-- defensives-row setting; brand-new profiles default to center.
--
-- WIPE STRATEGY: v2 reads ONLY p.bm2. The legacy BM keys (bmIndicators/
-- bmSimple/bmDisplayMode, override-banked configs) are LEFT INTACT and
-- ignored: profiles are shared with the 12.0 client through SavedVariables,
-- so wiping them here would destroy the user's retail Buff Manager. Physical
-- deletion belongs to the at-launch cleanup pass.

local _, mod = ...
local CludesUI = _G.CludesUI
-- WoW Forever one-time buff clear (CludesUI_Migration.lua); nil on every
-- other client.
local FVBW = CludesUI.FvBW

-------------------------------------------------------------------------------
-- Preset filter definitions
-------------------------------------------------------------------------------
-- Preset identity/order and the curated spell lists live in the parent's
-- shared catalogue (CludesUI_BuffPresets.lua) -- THE single curation
-- source, also consumed (alt-flattened) by Player Aura Bars' filter seed.
-- Add or edit curated ids THERE, never here.
local PRESET_FILTERS = CludesUI.BUFF_PRESETS.filters
mod.BM2_PRESET_FILTERS = PRESET_FILTERS

-- Curated spell lists: see the parent catalogue (shape documented there).
local DEFAULT_FILTER_SPELLS = CludesUI.BUFF_PRESETS.spells
mod.BM2_DEFAULT_FILTER_SPELLS = DEFAULT_FILTER_SPELLS

-- Profiles shared between retail and WoW Forever: the other client's curated
-- ids per preset key, and the preset keys only that client offers (see the
-- parent catalogue). Preset filters keep both stored untouched; here they are
-- inert and hidden.
local OTHER_IDS = CludesUI.BUFF_PRESET_OTHER_IDS
local OTHER_ONLY_PRESETS = {}
do
    local offered = {}
    for idx = 1, #PRESET_FILTERS do offered[PRESET_FILTERS[idx].key] = true end
    local other = CludesUI.BUFF_PRESET_OTHER_FILTERS
    for idx = 1, #other do
        if not offered[other[idx].key] then OTHER_ONLY_PRESETS[other[idx].key] = true end
    end
end

-- A stored preset filter only the other client offers: kept untouched for
-- the profile's next visit there, invisible to every list and lookup here.
local function OtherClientPreset(f)
    local key = f.preset
    return key ~= nil and OTHER_ONLY_PRESETS[key] == true
end

-- A spell a preset filter keeps only because the other client's catalogue
-- curates it there (not curated here, not user-added): its stored state
-- waits for that client, and here it counts as absent -- no editor row, no
-- resolution, no filter color.
local function OtherClientSpell(f, ident)
    local key = f.preset
    local other = key and OTHER_IDS[key]
    if not (other and other[ident]) then return false end
    local curated = DEFAULT_FILTER_SPELLS[key]
    return not (curated and curated[ident]) and not (f.custom and f.custom[ident])
end
mod.BM2_OtherClientSpell = OtherClientSpell

-- Primary -> alternates, built from the curated data at load. Resolution
-- expands every primary so alternates follow their primary's checkbox state.
local PRESET_ALTS = {}
-- Class tag per curated spell (alternates inherit the primary's); drives
-- class-aware display picks like the sidebar tile icon.
local SPELL_CLASS = {}
for _, spells in pairs(DEFAULT_FILTER_SPELLS) do
    for ident, details in pairs(spells) do
        if details.alts then PRESET_ALTS[ident] = details.alts end
        if details.class then
            SPELL_CLASS[ident] = details.class
            if details.alts then
                for idx = 1, #details.alts do SPELL_CLASS[details.alts[idx]] = details.class end
            end
        end
    end
end
mod.BM2_PresetAlts = PRESET_ALTS
mod.BM2_SpellClass = SPELL_CLASS
-- WoW Forever: alternate -> primary over the curated families (disjoint on
-- that catalogue). A direct pick or user filter holding a rank alternate
-- resolves to its family's primary, so it keeps matching every rank. nil on
-- every other client.
if CludesUI.IS_FOREVER == true then
    local ap = {}
    for ident, alts in pairs(PRESET_ALTS) do
        for idx = 1, #alts do ap[alts[idx]] = ident end
    end
    mod.BM2_ForeverAltPrimary = ap
end

-- Sorted array of every curated spell id: the Search Spells popup universe.
function mod.BM2_AllPresetSpells()
    local set = {}
    for _, spells in pairs(DEFAULT_FILTER_SPELLS) do
        for ident in pairs(spells) do set[ident] = true end
    end
    local result = {}
    for ident in pairs(set) do result[#result + 1] = ident end
    table.sort(result)
    return result
end

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
local function P()
    return mod.db and mod.db.profile
end

-------------------------------------------------------------------------------
-- One-shot legacy import (only while the profile has no bm2 store): legacy
-- Buff Manager buckets that were customized carry into v2 as direct-spell
-- indicators, grouping preserved 1:1; default buckets go to SeedSpec instead.
-------------------------------------------------------------------------------

local function LegacyCopy(v)
    if type(v) ~= "table" then return v end
    local tbl = {}
    for key, posX in pairs(v) do tbl[key] = LegacyCopy(posX) end
    return tbl
end

-- Spell arrays compare as SETS: only membership is user-editable, not order.
local function SameSpellSet(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end
    local set = {}
    for idx = 1, #a do set[a[idx]] = true end
    for idx = 1, #b do
        if not set[b[idx]] then return false end
    end
    return true
end

local function SameValue(a, b)
    if type(a) == "table" and type(b) == "table" then
        for key, val in pairs(a) do
            if not SameValue(val, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end
    return a == b
end

-- Untouched = every field the stored indicator carries matches the freshly
-- built default (fields the default lacks are ignored). When in doubt migrate:
-- copying a near-default setup is harmless, dropping a customized one is not.
local function IndMatchesDefault(ind, def)
    if (ind.type or "icon") ~= "icon" then return false end
    if ind.position ~= def.position then return false end
    if not SameSpellSet(ind.spells, def.spells) then return false end
    for key, val in pairs(ind) do
        if key ~= "id" and key ~= "spells" and key ~= "position" then
            local dv = def[key]
            if dv ~= nil and not SameValue(val, dv) then return false end
        end
    end
    return true
end

local function IsDefaultBucket(specKey, entries)
    local newInd = mod.BM_NewIndicator
    local presets = mod.BM_DefaultIndicators and mod.BM_DefaultIndicators[specKey]
    if not newInd or not presets then return #entries == 0 end
    if #entries ~= #presets then return false end
    for idx = 1, #presets do
        local def = newInd("icon", presets[idx].spells)
        def.position = presets[idx].pos
        if presets[idx].pos == "TOPRIGHT" then def.growDirection = "LEFT" end
        if not IndMatchesDefault(entries[idx], def) then return false end
    end
    return true
end

-- Frame Alpha has no 12.1 renderer (fading needs per-aura presence, secret in
-- combat) so those indicators drop; Frame Border migrates (containers render).
local IMPORT_SKIP_TYPES = { framealpha = true }

-- Legacy indicator -> v2: same shape, empty filter assignments, spells kept
-- as direct spells. Own-only is per-INDICATOR in v2, so the legacy per-spell
-- resolution (ownOnlySpells, else ownOnly, nil = own-only) collapses by
-- MAJORITY (tie = any-caster). Removed per-icon size offsets never carry
-- over; nil return = retired type.
local function ImportLegacyInd(ind)
    if IMPORT_SKIP_TYPES[ind.type or "icon"] then return nil end
    local v = LegacyCopy(ind)
    v.filters = {}
    local ownSpells = ind.ownOnlySpells
    local ownFallback = ind.ownOnly ~= false
    local sum, ownCount = 0, 0
    for idx = 1, #(ind.spells or {}) do
        local spellRef = ind.spells[idx]
        local own
        if ownSpells and ownSpells[spellRef] ~= nil then
            own = ownSpells[spellRef]
        else
            own = ownFallback
        end
        sum = sum + 1
        if own then ownCount = ownCount + 1 end
    end
    v.ownOnly = ownCount > (sum - ownCount)
    v.ownOnlySpells = nil
    v.sizeOffsets = nil
    return v
end

-- Legacy indicator array -> v2 list (nil if nothing survives the type skip).
function mod.BM2_ImportLegacyBucket(entries)
    local result
    for idx = 1, #(entries or {}) do
        local v = ImportLegacyInd(entries[idx])
        if v then
            result = result or {}
            result[#result + 1] = v
        end
    end
    return result
end

-- bmIndicators-shaped legacy set -> v2 fork data { specs, seeded }. Simple-
-- grid sets convert to empty (no v2 home; every spec takes the starter
-- groups). Used by the profile one-shot and by override-layer conversion.
function mod.BM2_ConvertLegacySet(source, displayMode)
    local result = { specs = {}, seeded = {} }
    if type(source) ~= "table" or displayMode == "simple" then return result end
    for specKey, entries in pairs(source) do
        -- Any customized bucket migrates, INCLUDING one customized down to
        -- nothing (all indicators deleted, or only retired types left): an
        -- empty seeded bucket preserves "no buff display" intent, where
        -- leaving it unseeded would force the starter groups back on.
        if type(entries) == "table" and not IsDefaultBucket(specKey, entries) then
            local inds = mod.BM2_ImportLegacyBucket(entries) or {}
            local maxId = 0
            for idx = 1, #inds do
                local ident = tonumber(inds[idx].id) or 0
                if ident > maxId then maxId = ident end
            end
            result.specs[specKey] = {
                nextId = math.max(1000001, maxId + 1),
                inds = inds,
            }
            result.seeded[specKey] = true
        end
    end
    return result
end

-- Legacy truth is LIVE bmIndicators, deliberately even while a BM override
-- fork is applied: the runtime pointer says live IS the fork, so the store
-- must mirror it (the first harvest banks live v2 data into the fork's
-- layer). Baseline and other forks convert lazily in _CURF_BM2ApplyLayer.
local function ImportLegacyProfile(profile, b)
    local fork = mod.BM2_ConvertLegacySet(profile.bmIndicators, profile.bmDisplayMode)
    b.specs = fork.specs
    b.seeded = fork.seeded
end

local function Store()
    local profile = P()
    if not profile then return nil end
    local b = profile.bm2
    -- WoW Forever: the one-time buff clear ("fvBuffWipe" is its frozen mark,
    -- CludesUI_Migration.lua). A missing store is built blank there, so the
    -- legacy one-shot below never runs on that client.
    if FVBW and not (b and b.fvBuffWipe) then
        local nb = FVBW.ClearBM(profile)
        if nb then b = nb; mod.BM2_Invalidate() end
    end
    if not b then
        b = { filters = { nextId = 1, list = {} }, specs = {}, seeded = {} }
        profile.bm2 = b
        ImportLegacyProfile(profile, b)
    end
    return b
end

-------------------------------------------------------------------------------
-- Override-layer bridge (SpecOverrides BM layers). A fork's v2 payload is the
-- spec indicator sets + seeded map ONLY: the filter library stays shared
-- profile-wide, so custom filters and curated updates never diverge per fork.
-- Both hooks go through Store(), so the legacy one-shot always ran first.
-------------------------------------------------------------------------------

-- Snapshot of the live v2 fork data for layer harvests.
function _G._CURF_BM2HarvestFork()
    local store = Store()
    if not store then return nil end
    return { specs = LegacyCopy(store.specs), seeded = LegacyCopy(store.seeded) }
end

-- Preset v2 payloads for a fork created from scratch (SpecOverrides' create
-- popup). "default" = a fresh profile: nothing seeded, so SeedSpec lays down
-- the starter sets on first read. "empty" = every key SeedSpec would fill with
-- content (healer keys + the shared non-healer key) pre-seeded EMPTY, so nothing
-- renders anywhere until the user builds it; the additive group buckets start
-- empty either way.
function _G._CURF_BM2PresetFork(kind)
    local result = { specs = {}, seeded = {} }
    -- WoW Forever builds "default" exactly like "empty": nothing seeds there,
    -- and the pre-seeded payload reads blank on the other client as well
    -- (CludesUI_Migration.lua).
    if kind ~= "empty" and not (FVBW and FVBW.ClientOK()) then return result end
    local function Empty(key)
        result.specs[key] = { nextId = 1000001, inds = {} }
        result.seeded[key] = true
    end
    for _, specInfo in ipairs(mod.BM_HEALER_SPECS or {}) do
        if specInfo.key then Empty(specInfo.key) end
    end
    Empty("nonhealer")
    return result
end

-- Applies a BM layer's v2 payload into the live store, converting legacy-only
-- layers in place on first touch. layer.bm2 doubles as the conversion marker:
-- layers already carrying v2 data are never re-derived from legacy fields.
function _G._CURF_BM2ApplyLayer(layer)
    local store = Store()
    if not store or not layer then return end
    if not layer.bm2 then
        -- WoW Forever never converts legacy layers: it starts blank there.
        if not (FVBW and FVBW.BlankLayer(layer)) then
            layer.bm2 = mod.BM2_ConvertLegacySet(layer.indicators, layer.displayMode)
        end
    end
    wipe(store.specs)
    for key, val in pairs(layer.bm2.specs or {}) do store.specs[key] = LegacyCopy(val) end
    wipe(store.seeded)
    for key, val in pairs(layer.bm2.seeded or {}) do store.seeded[key] = val end
    -- WoW Forever: the starter seed reads which layer live now holds
    -- (CludesUI_Migration.lua).
    if FVBW then FVBW.Painted(layer) end
    mod.BM2_Invalidate()
end

-- Resolution cache generation: any filter/indicator edit bumps it.
local gen = 1
function mod.BM2_Invalidate()
    gen = gen + 1
end

-------------------------------------------------------------------------------
-- Filter registry
-------------------------------------------------------------------------------
local function FindPreset(b, key)
    for idx = 1, #b.filters.list do
        if b.filters.list[idx].preset == key then return b.filters.list[idx] end
    end
end

-- Seeds missing preset filters and merges only NEW curated ids: an id the
-- filter has already seen keeps the user's checkbox state.
local function FilterStore()
    local store = Store()
    if not store then return nil end
    for idx = 1, #PRESET_FILTERS do
        local def = PRESET_FILTERS[idx]
        local f = FindPreset(store, def.key)
        if not f then
            f = { id = store.filters.nextId, name = def.name, preset = def.key,
                spells = {}, custom = {} }
            store.filters.nextId = store.filters.nextId + 1
            store.filters.list[#store.filters.list + 1] = f
        end
        local curated = DEFAULT_FILTER_SPELLS[def.key]
        if curated then
            for ident, details in pairs(curated) do
                if f.spells[ident] == nil and not f.custom[ident] then
                    f.spells[ident] = not details.disabled
                end
            end
        end
        -- Prune the other way: a spell REMOVED from curated data must leave
        -- existing profiles too, or its seeded state lingers forever, still
        -- resolving onto frames and undeletable in the Filter Editor (no
        -- f.custom membership = no remove control). f.custom spells and
        -- still-curated states stay, and so does every id the other client's
        -- catalogue curates under this preset: a profile shared with that
        -- client keeps those checkbox states for its next visit there
        -- (OtherClientSpell keeps them inert here). Clearing a key in pairs()
        -- is legal in 5.1.
        local other = OTHER_IDS[def.key]
        for ident in pairs(f.spells) do
            if not (curated and curated[ident]) and not f.custom[ident]
                and not (other and other[ident]) then
                f.spells[ident] = nil
            end
        end
    end
    -- WoW Forever: the starter seed, decided once per store now that the
    -- preset filters exist ("fvBmSeed" is its frozen mark,
    -- CludesUI_Migration.lua). A marked store costs one field read.
    if FVBW and store.fvBmSeed == nil and FVBW.SeedStarter(P(), store) then
        mod.BM2_Invalidate()
    end
    return store
end

-- The filter list every picker and editor shows: the stored list itself, or,
-- on a client missing presets the other one offers, a fresh copy without them.
function mod.BM2_Filters()
    local b = FilterStore()
    if not b then return nil end
    local entries = b.filters.list
    if next(OTHER_ONLY_PRESETS) == nil then return entries end
    local result = {}
    for idx = 1, #entries do
        if not OtherClientPreset(entries[idx]) then result[#result + 1] = entries[idx] end
    end
    return result
end

-- nil for a preset only the other client offers: resolution, pickers and
-- colors treat an assignment to it as a dangling id.
function mod.BM2_GetFilter(ident)
    local store = Store()
    if not store then return nil end
    for idx = 1, #store.filters.list do
        local f = store.filters.list[idx]
        if f.id == ident then
            if OtherClientPreset(f) then return nil end
            return f
        end
    end
end

-- True for a stored filter id that belongs to a preset only the other client
-- offers (BM2_GetFilter returns nil for it); false for every other id,
-- dangling ones included. Always false while this client offers every preset.
function mod.BM2_HiddenPresetFilter(ident)
    if next(OTHER_ONLY_PRESETS) == nil then return false end
    local store = Store()
    if not store then return false end
    for idx = 1, #store.filters.list do
        local f = store.filters.list[idx]
        if f.id == ident then return OtherClientPreset(f) end
    end
    return false
end

-- Square per-FILTER colors (ind.filterColors[fid], options swatches): fan the
-- filter's color out to every enabled member so the whole per-spell color
-- machinery downstream (BmSquareColor, BmChainMode slot forcing, style keys)
-- consumes it unchanged. DIRECT per-spell colors overlay last (an explicit
-- pick wins); overlapping colored filters resolve in ascending fid order
-- (deterministic). Returns nil when no filter color exists, so plain
-- indicators keep their raw spellColors reference -- zero behavior change.
-- A single uniform filter color keeps chain GROUP mode (identical entries);
-- only genuinely mixed colors force per-spell slots, same as mixed direct
-- colors always did. Keyed by PRIMARY ids (alternates ride their primary's
-- include map and inherit its slot color).
function mod.BM2_SquareFilterColors(ind)
    local fc = ind.filterColors
    if ind.type ~= "square" then return nil end
    -- WoW Forever: a rank alternate resolves to its family's primary
    -- (BM2_ResolveSpellsOwn), so colors key by that primary. nil elsewhere.
    local ap = mod.BM2_ForeverAltPrimary
    local fids
    if fc and ind.filters then
        for fid in pairs(ind.filters) do
            if fc[fid] then
                fids = fids or {}
                fids[#fids + 1] = fid
            end
        end
    end
    local merged
    if fids then
        table.sort(fids)
        for idx = 1, #fids do
            local c = fc[fids[idx]]
            local f = mod.BM2_GetFilter(fids[idx])
            if f and f.spells then
                for ident, on in pairs(f.spells) do
                    if on and not OtherClientSpell(f, ident) then
                        local k = (ap and ap[ident]) or ident
                        merged = merged or {}
                        if merged[k] == nil then merged[k] = c end
                    end
                end
            end
        end
    end
    local sc = ind.spellColors
    if not merged then
        -- No filter color: the raw spellColors reference stands, unless a
        -- direct color sits under a rank alternate (WoW Forever).
        if not (ap and sc) then return nil end
        for ident in pairs(sc) do
            if ap[ident] then merged = {}; break end
        end
        if not merged then return nil end
    end
    if sc then
        local won -- primary -> the alternate whose direct color it holds
        for ident, c in pairs(sc) do
            -- An alternate's direct color lands on its primary unless the
            -- primary has a direct color of its own; among alternates the
            -- lowest id wins.
            local k = ap and ap[ident]
            if not k then
                merged[ident] = c
            elseif sc[k] == nil and not (won and won[k] and won[k] < ident) then
                merged[k] = c
                won = won or {}
                won[k] = ident
            end
        end
    end
    return merged
end

function mod.BM2_AddFilter(name)
    local store = Store()
    if not store then return nil end
    local f = { id = store.filters.nextId, name = name or "New Filter",
        spells = {}, custom = {} }
    store.filters.nextId = store.filters.nextId + 1
    store.filters.list[#store.filters.list + 1] = f
    mod.BM2_Invalidate()
    return f
end

function mod.BM2_RenameFilter(ident, name)
    local f = mod.BM2_GetFilter(ident)
    if f and not f.preset and name and name ~= "" then f.name = name end
end

-- Presets cannot be deleted; deleting a custom filter also strips its
-- assignments from every indicator on every spec.
function mod.BM2_DeleteFilter(ident)
    local store = Store()
    if not store then return end
    for idx = #store.filters.list, 1, -1 do
        local f = store.filters.list[idx]
        if f.id == ident and not f.preset then
            table.remove(store.filters.list, idx)
        end
    end
    for _, specInfo in pairs(store.specs) do
        for jdx = 1, #specInfo.inds do
            local ind = specInfo.inds[jdx]
            if ind.filters then ind.filters[ident] = nil end
            if ind.negFilters then ind.negFilters[ident] = nil end
        end
    end
    mod.BM2_Invalidate()
end

-- Checkbox state: true/false explicit; nil on a CUSTOM spell removes it,
-- its typed mark included.
function mod.BM2_SetSpellState(filterId, spellId, status)
    local f = mod.BM2_GetFilter(filterId)
    if not f then return end
    if status == nil and f.custom[spellId] then
        f.custom[spellId] = nil
        f.spells[spellId] = nil
        local fx = f.exact
        if fx then
            fx[spellId] = nil
            if next(fx) == nil then f.exact = nil end
        end
    else
        f.spells[spellId] = status and true or false
    end
    mod.BM2_Invalidate()
end

-- A filter's own typed mark on id (f.exact[id], written by BM2_AddCustomSpell):
-- void where the filter's preset curates the id, since a curated spell
-- always keeps its family.
local function FilterExact(f, ident)
    local fx = f.exact
    if not (fx and fx[ident]) then return false end
    local curated = f.preset and DEFAULT_FILTER_SPELLS[f.preset]
    return not (curated and curated[ident])
end

-- An id kept only for the other client counts as absent: adding it makes it
-- the user's own on both clients. typed (the Filter Editor's Add Spell ID,
-- never its Search Spells pick or a copy from another library): the id tracks
-- that aura alone from now on (f.exact[id]), and typing one the filter
-- already holds as the user's own narrows it the same way; ids saved before
-- carry no mark and keep their family. No mark on WoW Forever, where a typed
-- rank stands for every rank of its spell.
function mod.BM2_AddCustomSpell(filterId, spellId, typed)
    local f = mod.BM2_GetFilter(filterId)
    if not (f and spellId and spellId > 0) then return false end
    local mark = typed == true and CludesUI.IS_FOREVER ~= true
    if f.spells[spellId] ~= nil and not OtherClientSpell(f, spellId) then
        -- Already present: only a typed id not yet marked, and not one the
        -- filter's preset curates, changes anything.
        local curated = f.preset and DEFAULT_FILTER_SPELLS[f.preset]
        if not mark or (curated and curated[spellId]) or (f.exact and f.exact[spellId]) then
            return false
        end
    else
        f.custom[spellId] = true
        f.spells[spellId] = true
    end
    if mark then
        f.exact = f.exact or {}
        f.exact[spellId] = true
    end
    mod.BM2_Invalidate()
    return true
end

-------------------------------------------------------------------------------
-- Spec indicators (seeding + access)
-------------------------------------------------------------------------------
-- WoW Forever: the Buff Manager spec a class acts as. While a spec override's
-- Buff Manager fork is live (outside a conditional's editing session), the
-- player's class acts as the spec that fork serves (published by Spec
-- Overrides, seeded from the saved pointer at the first read); otherwise
-- every class acts as its first spec. token nil = the player's class.
function mod.BM2_ForeverSpecID(token)
    if not CludesUI._SO_BmForkSeeded then CludesUI._SO_SeedForkSpec(false) end
    local fk = CludesUI.SpecOverrides_BmForkSpecID
    if fk and not CludesUI._bmSessionGid
       and (token == nil or token == CludesUI.SpecClassOf(fk)) then
        return fk
    end
    return CludesUI.ForeverClassSpec(token)
end
-- The bucket a class row edits: the healer key of a healer spec, else the
-- spec's own "spec<ID>" bucket (as on retail).
function mod.BM2_ForeverKey(token)
    local spellRef = mod.BM2_ForeverSpecID(token)
    if not spellRef then return nil end
    return (mod.BM_SpecKeyForSpecID and mod.BM_SpecKeyForSpecID(spellRef)) or ("spec" .. spellRef)
end

-- ACTIVE config key: the healer/Aug spec key on a tracked spec, else the shared
-- "nonhealer" bucket -- every spec outside the editor's healer list shares ONE
-- config (class-agnostic display; filters resolve it at runtime).
-- Resolved WITHOUT borrow (BM_SpecKeyForSpecID, never BM_CurrentSpecKey):
-- BM_CurrentSpecKey routes Ret/Prot -> Holy and Ele/Enh -> Resto, and v2 has no
-- castability strip to narrow a borrowed set, so borrowing here would hand
-- Ret/Prot Holy's FULL healer config and keep them out of the All Non
-- Healers/Aug bucket (maintainer ruling 2026-08-13: non-healer specs edit and
-- render the shared bucket).
function mod.BM2_SpecKey()
    -- WoW Forever: the same formula with the spec the class acts as.
    if CludesUI.IS_FOREVER then
        local spellRef = mod.BM2_ForeverSpecID()
        return (spellRef and mod.BM_SpecKeyForSpecID and mod.BM_SpecKeyForSpecID(spellRef)) or "nonhealer"
    end
    local specIdx = GetSpecialization and GetSpecialization()
    local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
    return (specID and mod.BM_SpecKeyForSpecID and mod.BM_SpecKeyForSpecID(specID)) or "nonhealer"
end

local function PresetIdsByKey(b)
    local map = {}
    for idx = 1, #b.filters.list do
        local f = b.filters.list[idx]
        if f.preset then map[f.preset] = f.id end
    end
    return map
end

-- Seeds the starter groups: group 1 center, healing corners top-left/right.
local function SeedSpec(b, specKey)
    -- WoW Forever never runs this per-bucket seed: its own All Specs starter
    -- seed is placed once per store from EnsureFilters (CludesUI_Migration.lua).
    -- A seeded bucket with its arrays costs plain reads; anything else passes
    -- the gate once.
    if FVBW then
        local bk = b.seeded[specKey] and b.specs[specKey]
        if type(bk) == "table" and bk.inds and bk.nextId then return end
        if FVBW.SeedEmpty(b, specKey) then return end
    end
    if b.seeded[specKey] then return end
    b.seeded[specKey] = true
    local specInfo = b.specs[specKey]
    -- Id namespace offset: the legacy page's own global id counter is synced
    -- from LEGACY storage only, so v2 ids start far above its reachable range.
    if not specInfo then specInfo = { nextId = 1000001, inds = {} }; b.specs[specKey] = specInfo end

    -- Additive union buckets ("allspecs", the role groups "tanks"/"dps"/
    -- "healers", per-spec "spec<ID>") start EMPTY: nothing renders from them
    -- until the user builds something there, so existing setups are
    -- untouched by their arrival.
    if specKey == "allspecs" or specKey == "tanks" or specKey == "dps"
        or specKey == "healers" or specKey:match("^spec%d") then return end

    -- Resolved only for healer-key seeds (below the group early-return so
    -- group buckets never pay the scan, and so a caller that reached here
    -- through Store() without EnsureFilters cannot bake empty assignments).
    local popFrame = PresetIdsByKey(b)

    local g1 = {
        id = specInfo.nextId, enabled = true, type = "icon",
        name = "Defensives & Utility",
        -- Any-caster: externals/raid CDs are cast BY others.
        ownOnly = false,
        filters = {},
        spells = {},
        position = "CENTER", growDirection = "CENTER", size = 18,
    }
    if popFrame.defensives then g1.filters[popFrame.defensives] = true end
    if popFrame.raidcds then g1.filters[popFrame.raidcds] = true end
    if popFrame.utility then g1.filters[popFrame.utility] = true end
    if popFrame.externals then g1.filters[popFrame.externals] = true end
    specInfo.nextId = specInfo.nextId + 1
    specInfo.inds[#specInfo.inds + 1] = g1

    -- Healing-buff corners are healer-only and default own-only (the healer's
    -- OWN HoTs); the shared nonhealer bucket seeds group 1 alone.
    if specKey ~= "nonhealer" then
        local g2 = { id = specInfo.nextId, enabled = true, type = "icon",
            name = "Core Healing Buffs", ownOnly = true,
            filters = {}, spells = {},
            position = "TOPLEFT", growDirection = "RIGHT", size = 18 }
        if popFrame.coreheals then
            g2.filters[popFrame.coreheals] = true
        end
        specInfo.nextId = specInfo.nextId + 1
        specInfo.inds[#specInfo.inds + 1] = g2

        local g3 = { id = specInfo.nextId, enabled = true, type = "icon",
            name = "Lesser Healing Buffs", ownOnly = true,
            filters = {}, spells = {},
            position = "TOPRIGHT", growDirection = "LEFT", size = 18 }
        if popFrame.lesserheals then
            g3.filters[popFrame.lesserheals] = true
        end
        specInfo.nextId = specInfo.nextId + 1
        specInfo.inds[#specInfo.inds + 1] = g3
    end
end

-- key = healer spec key or "nonhealer" (editor); nil = player's ACTIVE key.
function mod.BM2_SpecInds(key)
    local b = FilterStore()
    if not b then return nil, nil end
    local specKey = key or mod.BM2_SpecKey()
    SeedSpec(b, specKey)
    local specInfo = b.specs[specKey]
    if specInfo then
        -- Token normalization: the BM machinery expects UPPERCASE position/
        -- growth tokens (lowercase breaks to defaults); healed on every read.
        for idx = 1, #specInfo.inds do
            local ind = specInfo.inds[idx]
            if ind.position then ind.position = string.upper(ind.position) end
            if ind.growDirection then ind.growDirection = string.upper(ind.growDirection) end
            -- Per-icon size offsets are removed: purge stale data.
            ind.sizeOffsets = nil
            -- Own-only is per-INDICATOR (per-source flags forced per-spell
            -- slot layout, which exploded at filter-union scale): collapse
            -- stale flags by MAJORITY of resolved own states, tie = any-caster.
            if ind.ownFilters or ind.ownExtras then
                local resolved, own = mod.BM2_ResolveSpellsOwn(ind)
                local ownCount = 0
                for jdx = 1, #resolved do
                    if own[resolved[jdx]] then ownCount = ownCount + 1 end
                end
                ind.ownOnly = ownCount > (#resolved - ownCount)
                ind.ownFilters = nil
                ind.ownExtras = nil
                ind.ownOnlySpells = nil
            elseif ind.ownOnly == nil then
                ind.ownOnly = false
            end
            -- Seed-name heal: rewrite only the untouched old group-1 name,
            -- never a user's own rename.
            if ind.name == "Defensive & Support CDs" then
                ind.name = "Defensives & Utility"
            end
        end
    end
    return specInfo and specInfo.inds or nil, specKey
end

-------------------------------------------------------------------------------
-- Per-spec disables of GROUP-bucket indicators ("allspecs"/"nonhealer"/
-- "tanks"/"dps"/"healers"). Stored on the CONCRETE bucket (a healer spec key,
-- or a non-healer spec's "spec<ID>" bucket) as inhDis["<group>:<id>"] = true.
-- The group indicator itself is untouched: every other spec keeps rendering
-- it, and re-enabling is a pure key delete.
-------------------------------------------------------------------------------
function mod.BM2_InhDisabled(concreteKey, groupKey, ident)
    local store = Store()
    local specInfo = store and concreteKey and store.specs[concreteKey]
    local dis = specInfo and specInfo.inhDis
    return (dis and dis[groupKey .. ":" .. ident]) and true or false
end

function mod.BM2_SetInhDisabled(concreteKey, groupKey, ident, disabled)
    -- EnsureFilters (not bare Store): a healer key seeding here must see the
    -- preset filters or its starter groups would bake empty assignments.
    local b = FilterStore()
    if not (b and concreteKey and groupKey and ident) then return end
    SeedSpec(b, concreteKey)
    local specInfo = b.specs[concreteKey]
    -- seeded[k] can outlive specs[k] (layer payloads/imports may prune empty
    -- bucket tables): re-create rather than index nil.
    if not specInfo then
        specInfo = { nextId = 1000001, inds = {} }
        b.specs[concreteKey] = specInfo
    end
    specInfo.inhDis = specInfo.inhDis or {}
    specInfo.inhDis[groupKey .. ":" .. ident] = disabled and true or nil
    mod.BM2_Invalidate()
end

-- Deep-copies an indicator into another bucket (the right-click "Add To"
-- menu): full settings clone under a FRESH id from the TARGET bucket's
-- counter; the source is untouched. anchorTo is severed -- it references a
-- sibling id in the SOURCE bucket, which in the target would be an
-- unrelated indicator (or dangle).
function mod.BM2_CopyIndicator(srcInd, targetKey)
    local b = FilterStore()
    if not (b and srcInd and targetKey) then return nil end
    SeedSpec(b, targetKey)
    local specInfo = b.specs[targetKey]
    if not specInfo then
        specInfo = { nextId = 1000001, inds = {} }
        b.specs[targetKey] = specInfo
    end
    local v = LegacyCopy(srcInd)
    v.id = specInfo.nextId
    specInfo.nextId = specInfo.nextId + 1
    v.anchorTo = nil
    specInfo.inds[#specInfo.inds + 1] = v
    mod.BM2_Invalidate()
    return v
end

-- Deleting a GROUP indicator sweeps its per-spec disable keys from every
-- concrete bucket (stale keys are inert but would leak forever).
function mod.BM2_SweepInhDis(groupKey, ident)
    local store = Store()
    if not store then return end
    local k = groupKey .. ":" .. ident
    for _, specInfo in pairs(store.specs) do
        if specInfo.inhDis then specInfo.inhDis[k] = nil end
    end
end

-- key (optional) = the EDITED bucket; defaults to the player's active key.
function mod.BM2_AddIndicator(indType, key)
    local store = Store()
    if not store then return nil end
    local specKey = key or mod.BM2_SpecKey()
    SeedSpec(store, specKey)
    local specInfo = store.specs[specKey]
    -- Growth must match the position the way the Position dropdown derives it
    -- (TOPLEFT -> RIGHT): CENTER growth centers the run ON the anchor, so a
    -- corner + CENTER hangs half the icons off the frame (preview and live).
    local ind = { id = specInfo.nextId, enabled = true, type = indType or "icon",
        name = "New Indicator", filters = {}, spells = {},
        ownOnly = false,
        position = "TOPLEFT", growDirection = "RIGHT", size = 18 }
    specInfo.nextId = specInfo.nextId + 1
    specInfo.inds[#specInfo.inds + 1] = ind
    mod.BM2_Invalidate()
    return ind
end

-------------------------------------------------------------------------------
-- Resolution: indicator -> effective spell array
-------------------------------------------------------------------------------
-- Whether a source that keeps the curated family brings id into the
-- indicator: a direct spell with no typed mark, or an assigned filter that
-- holds it switched on without one. Asked only for the few ids a source typed.
local function FamilySource(ind, ident)
    local sp = ind.spells
    if sp then
        local ex = ind.exactSpells
        if not (ex and ex[ident]) then
            for idx = 1, #sp do
                if sp[idx] == ident then return true end
            end
        end
    end
    if ind.filters then
        for fid in pairs(ind.filters) do
            local f = mod.BM2_GetFilter(fid)
            if f and f.spells[ident] and not FilterExact(f, ident) and not OtherClientSpell(f, ident) then
                return true
            end
        end
    end
    return false
end

-- Union of direct spells + enabled spells of assigned filters, plus per-spell
-- OWNERSHIP: each source (filter or direct extra) has its own flag (ind.ownFilters[fid]
-- / ind.ownExtras[sid]); a spell from several sources is own-only ONLY if all say so
-- (show-all wins, the less restrictive intent). Alternates inherit their primary's
-- state. Returns (sortedList, ownMap, exactMap), stable-sorted for deterministic
-- signatures. exactMap (nil when empty) holds the ids every source typed (a
-- direct one through BM2_SetSpellExact, a filter's through BM2_AddCustomSpell):
-- those match their own aura alone. One source that keeps the family (a pick
-- from Presets, a filter's curated or saved spell) and the family counts.
-- Rebuilt every call (cheap: once per class per reload) because the LEGACY editor
-- mutates ind.spells without bumping the edit generation, so a generation-keyed cache
-- would serve stale unions after a spell edit.
function mod.BM2_ResolveSpellsOwn(ind)
    local set = {} -- id -> own-only boolean
    -- WoW Forever: a rank alternate counts as its family's primary (nil on
    -- every other client). Per-extra own flags stay keyed by the stored id.
    local ap = mod.BM2_ForeverAltPrimary
    -- Typed marks are never read on WoW Forever, where a typed rank stands
    -- for every rank of its spell. typed = the ids some source marks, made
    -- only when one does.
    local typed
    if not ap and ind.exactSpells then
        typed = {}
        for ident in pairs(ind.exactSpells) do typed[ident] = true end
    end
    local function Add(ident, own)
        local current = set[ident]
        if current == nil then
            set[ident] = own and true or false
        elseif current and not own then
            set[ident] = false
        end
    end
    if ind.spells then
        local oe = ind.ownExtras
        for idx = 1, #ind.spells do
            local ident = ind.spells[idx]
            Add((ap and ap[ident]) or ident, oe and oe[ident])
        end
    end
    if ind.filters then
        local of = ind.ownFilters
        for fid in pairs(ind.filters) do
            local f = mod.BM2_GetFilter(fid)
            if f then
                local fOwn = of and of[fid]
                local fx = (not ap) and f.exact or nil
                for ident, on in pairs(f.spells) do
                    if on and not OtherClientSpell(f, ident) then
                        Add((ap and ap[ident]) or ident, fOwn)
                        if fx and fx[ident] then
                            typed = typed or {}
                            typed[ident] = true
                        end
                    end
                end
            end
        end
    end
    -- Hide lane (ind.negFilters): hidden filters' enabled spells drop out of the
    -- union. Direct spell picks (ind.spells) win over the hide lane -- an explicit
    -- pick is the stronger statement. Excluded primaries never reach the engine
    -- include maps, so their alternates fall away with them.
    if ind.negFilters then
        local direct
        if ind.spells then
            direct = {}
            for idx = 1, #ind.spells do
                local ident = ind.spells[idx]
                direct[(ap and ap[ident]) or ident] = true
            end
        end
        for fid in pairs(ind.negFilters) do
            local f = mod.BM2_GetFilter(fid)
            if f then
                for ident, on in pairs(f.spells) do
                    local k = (ap and ap[ident]) or ident
                    if on and not (direct and direct[k])
                        and not OtherClientSpell(f, ident) then set[k] = nil end
                end
            end
        end
    end
    -- Alternates are deliberately NOT in the resolved list: one entry per buff
    -- FAMILY, else the preview/slot layer renders the same buff once per
    -- talent/rank id. Alt ids ride the engine include maps instead
    -- (BmIncludeMap consults BM2_PresetAlts) so they still match their slot.
    local result = {}
    for ident in pairs(set) do result[#result + 1] = ident end
    table.sort(result)
    local exact
    if typed then
        for ident in pairs(typed) do
            if set[ident] ~= nil and not FamilySource(ind, ident) then
                exact = exact or {}
                exact[ident] = true
            end
        end
    end
    return result, set, exact
end

function mod.BM2_ResolveSpells(ind)
    local result = mod.BM2_ResolveSpellsOwn(ind)
    return result
end

-- A spell ID typed through Custom Spell ID tracks that aura alone
-- (ind.exactSpells[id]); a pick from the Presets list, like a filter, keeps the
-- other ids of its curated family. Not written on WoW Forever, where a typed
-- rank stands for every rank of its spell.
function mod.BM2_SetSpellExact(ind, ident, exact)
    if exact then
        if CludesUI.IS_FOREVER == true then return end
        ind.exactSpells = ind.exactSpells or {}
        ind.exactSpells[ident] = true
    elseif ind.exactSpells then
        ind.exactSpells[ident] = nil
        if next(ind.exactSpells) == nil then ind.exactSpells = nil end
    end
end

-- The Custom Spell ID top action of an Extra Spells menu (the indicator
-- editor's and the New Indicator popup's): onID(id) takes each number
-- confirmed in its popup.
function mod.BM2_SpellIdAction(onID)
    return { isTopAction = true, label = "Custom Spell ID", onClick = function()
        CludesUI:ShowInputPopup({
            title = CludesUI.L("Add Spell ID"),
            message = CludesUI.L("Enter the spell ID to track on this indicator."),
            placeholder = CludesUI.L("Spell ID"),
            confirmText = CludesUI.L("Add"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = function(textValue)
                local ident = tonumber(textValue or "")
                if ident and ident > 0 then onID(ident) end
            end,
        })
    end }
end

-- Preferred DISPLAY spell (sidebar tile icon etc.): a resolved spell the
-- player knows (IsPlayerSpell, spec-accurate), else one curated for the
-- target class, else an "ALL" entry, else the first resolved spell.
-- classOverride = the EDITED bucket's class (dropdown selection), so tiles
-- face the spec being edited; nil = the player's class. The known-spell
-- pass only applies when the target class IS the player's -- IsPlayerSpell
-- can't speak for other classes.
function mod.BM2_PreferredSpell(ind, classOverride)
    local resolved = mod.BM2_ResolveSpells(ind)
    if #resolved == 0 then return nil end
    local _, playerClass = UnitClass("player")
    local class = classOverride or playerClass
    local useKnown = class == playerClass
    local classPick, allPick
    for idx = 1, #resolved do
        local ident = resolved[idx]
        if useKnown and IsPlayerSpell then
            -- One PRIMARY per family: the player may know only an alternate.
            if IsPlayerSpell(ident) then return ident end
            local alts = PRESET_ALTS[ident]
            if alts then
                for jdx = 1, #alts do
                    if IsPlayerSpell(alts[jdx]) then return ident end
                end
            end
        end
        local c = SPELL_CLASS[ident]
        if not classPick and c == class then classPick = ident end
        if not allPick and c == "ALL" then allPick = ident end
    end
    return classPick or allPick or resolved[1]
end

-- Adapter for the containers runtime: legacy-shaped indicator list with
-- resolved spell arrays, recomputed per call (the legacy editor mutates
-- indicator tables directly, so an edit-generation cache is unsound).
-- Indicators resolving to EMPTY are skipped (empty include map = unverified
-- semantics). The views are STABLE, one per bucket + indicator id (its
-- position in the bucket's list when id-less), and refreshed IN PLACE: the
-- container machinery captures them in its per-button meta at build time and
-- re-reads them on every geometry fingerprint/anchor pass, so a fresh table
-- per call freezes position/growth edits until reload. Not keyed by the store
-- table: an override layer swap replaces every store indicator with a copy
-- (_CURF_BM2ApplyLayer) without changing the container signature. Bounded by
-- the indicators ever rendered this session. [bucket][id] -> view: the
-- per-button container builds call this too, so the key is the id itself (a
-- string only for id-less legacy rows).
local bm2ViewCache = {}

-- Show In as rendered: an Anchor To member continues its root's run, so the
-- terminal root's value decides (the member's own is not offered while it is
-- anchored). list = the indicator's own bucket (Anchor To links stay inside
-- it). nil = raid and party.
function mod.BM2_EffectiveShowIn(ind, entries)
    local source = ind
    if entries and source.anchorTo ~= nil then
        for _ = 1, #entries do
            local tid = source.anchorTo
            if tid == nil then break end
            local nxt
            for jdx = 1, #entries do
                if entries[jdx].id == tid then nxt = entries[jdx]; break end
            end
            if not nxt or nxt == ind then break end
            source = nxt
        end
    end
    return source.showIn
end

-- frameKind ("raid" | "party", nil = every indicator): the frames asking.
-- Indicators whose Show In names the other kind are left out.
function mod.BM2_SpecIndicators(frameKind)
    local inds, specKey = mod.BM2_SpecInds()
    -- Additive union buckets: "allspecs" renders for EVERY spec, the role
    -- group ("tanks"/"dps"/"healers") for specs of that role, and a spec
    -- outside the healer/Aug list also renders its own "spec<ID>" bucket on
    -- top of its active one (for those specs the active bucket IS "nonhealer"
    -- -- BM2_SpecKey resolves borrow-free, so Ret/Prot/Ele/Enh land here like
    -- every other non-healer). All are empty until the user fills them.
    local ownInds, allInds, roleInds
    local specIdx = GetSpecialization and GetSpecialization()
    local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
    -- WoW Forever: the spec the class acts as (no role group there).
    if CludesUI.IS_FOREVER then specID = mod.BM2_ForeverSpecID() end
    local tracked = specID and mod.BM_SpecKeyForSpecID and mod.BM_SpecKeyForSpecID(specID) or nil
    -- WoW Forever: no role groups there, All Non Healers/Aug included -- an
    -- untracked class renders its own bucket and All Specs only.
    if CludesUI.IS_FOREVER and not tracked then inds = nil end
    if specID and not tracked then
        ownInds = mod.BM2_SpecInds("spec" .. specID)
    end
    allInds = mod.BM2_SpecInds("allspecs")
    local roleKey = specID and mod.BM_RoleBucketForSpecID and mod.BM_RoleBucketForSpecID(specID) or nil
    if roleKey then roleInds = mod.BM2_SpecInds(roleKey) end
    if not inds and not ownInds and not allInds and not roleInds then return nil, specKey, "custom" end
    -- Per-spec disables of group indicators live on the CONCRETE bucket:
    -- the healer spec key itself, or the non-healer spec's "spec<ID>".
    local concreteKey = tracked and specKey or (specID and ("spec" .. specID)) or nil
    local bStore = concreteKey and Store() or nil
    local cSpec = bStore and bStore.specs[concreteKey]
    local inhDis = cSpec and cSpec.inhDis or nil
    local result = {}
    -- idOffset disambiguates slot/chain/style keys across unioned buckets
    -- (every bucket allocates ids from the same 1000001 base) and shifts
    -- anchorTo identically so Anchor To links stay bucket-internal.
    -- groupKey marks a GROUP bucket's contribution: the active spec's
    -- per-spec disable set drops those indicators here (render side); the
    -- indicator itself is untouched for every other spec.
    local function Append(entries, idOffset, groupKey, bucket)
        if not entries then return end
        local views  -- this bucket's stable views, fetched on first use
        for idx = 1, #entries do
            local ind = entries[idx]
            local drop = groupKey and inhDis and inhDis[groupKey .. ":" .. ind.id]
            if not drop and frameKind then
                local showIn = mod.BM2_EffectiveShowIn(ind, entries)
                if showIn == "raid" then drop = frameKind == "party"
                elseif showIn == "party" then drop = frameKind ~= "party" end
            end
            local resolved, exact
            if not drop then
                local _
                resolved, _, exact = mod.BM2_ResolveSpellsOwn(ind)
            end
            if resolved and #resolved > 0 then
                if not views then
                    views = bm2ViewCache[bucket or "?"]
                    if not views then views = {}; bm2ViewCache[bucket or "?"] = views end
                end
                local viewKey = ind.id or ("x" .. idx)
                local v = views[viewKey]
                if not v then v = {}; views[viewKey] = v end
                for key in pairs(v) do v[key] = nil end
                for key, val in pairs(ind) do v[key] = val end
                v.spells = resolved
                -- Exact ids, which match their own aura alone (nil = every id
                -- keeps its curated family; BmIncludeMap reads it).
                v.exactSpells = exact
                -- Per-filter square colors fan out into the view's spellColors
                -- (fresh merged table; readers reach it through the stable
                -- view, so the identity-stability contract holds).
                v.spellColors = mod.BM2_SquareFilterColors(ind) or ind.spellColors
                -- Always explicit: the legacy nil-default (own-only TRUE)
                -- can't leak.
                v.ownOnly = ind.ownOnly == true
                v.ownOnlySpells = nil
                if idOffset then
                    if type(v.id) == "number" then v.id = v.id + idOffset end
                    if type(v.anchorTo) == "number" then v.anchorTo = v.anchorTo + idOffset end
                end
                result[#result + 1] = v
            end
        end
    end
    -- For non-healer specs the active bucket IS the All Non Healers/Aug
    -- group, so its rows honor the per-spec disable set too.
    Append(inds, nil, (not tracked) and "nonhealer" or nil, specKey)
    Append(ownInds, 1000000, nil, specID and ("spec" .. specID))
    Append(allInds, 2000000, "allspecs", "allspecs")
    Append(roleInds, 3000000, roleKey, roleKey)
    return result, specKey, "custom"
end

-------------------------------------------------------------------------------
-- Cross-module filter bridge (parent-published): the ONE-TIME filter copies
-- between this library and Player Aura Bars ride it (both Filter Editors'
-- copy buttons). Absence of the table = this module is off, and the
-- other side's button hides, so consumers must read it lazily at call time.
-- Mutators already Invalidate internally; Refresh repaints raid frames after
-- a copy lands new spell content here.
-------------------------------------------------------------------------------
CludesUI._BM2FilterBridge = {
    Filters        = function() return mod.BM2_Filters() end,
    GetFilter      = function(ident) return mod.BM2_GetFilter(ident) end,
    AddFilter      = function(name) return mod.BM2_AddFilter(name) end,
    SetSpellState  = function(ident, spellId, status) return mod.BM2_SetSpellState(ident, spellId, status) end,
    AddCustomSpell = function(ident, spellId) return mod.BM2_AddCustomSpell(ident, spellId) end,
    -- True for an id typed into filter f: it tracks that aura alone here,
    -- so a copy does not fan it out to its alternates.
    SpellExact     = function(f, ident) return CludesUI.IS_FOREVER ~= true and FilterExact(f, ident) end,
    PresetAlts     = function() return mod.BM2_PresetAlts end,
    CuratedSpells  = function(presetKey) return presetKey and DEFAULT_FILTER_SPELLS[presetKey] or nil end,
    -- True for an id a preset filter keeps only for the other client.
    OtherClientSpell = OtherClientSpell,
    Refresh        = function()
        if mod.BM2_Invalidate then mod.BM2_Invalidate() end
        if mod.ReloadFrames then mod.ReloadFrames() end
    end,
}


