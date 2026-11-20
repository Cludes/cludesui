if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_Filters.lua
--
--  The custom bar store, the buff filters and their copies, the buff
--  manager import and the spec buckets.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._pabInternals
-- CludesUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ExpandFamily, PAB, BuffBarHasContent = Inner.ExpandFamily, Inner.PAB, Inner.BuffBarHasContent

local ReloadAllCustomBars
Inner.reloadAllSetters[#Inner.reloadAllSetters + 1] = function(val)
    ReloadAllCustomBars = val
end

-------------------------------------------------------------------------------
--  Custom bars (free bar creator)
--
--  Buffs: SpellID-based -- customBuffBars entries carry filters={[filterId]=true},
--  spells={id,...}, ownOnlySpells={[id]=bool}. Same shape and same
--  PAB_ResolveSpells() union the default Buffs bar uses: default Buffs and custom
--  Buff Bars are ONE model, not two. Rendering is one candidateFilters-restricted
--  GROUP into the bar's own dedicated container with a signature-gated rebuild (see
--  PAB_ReloadCustomBuffBar for why a group, not per-spell slots). This section is
--  the CRUD data layer; engine wiring is in CUI_PlayerAuraBars_CustomBars.lua.
--
--  Debuffs: category-based (same as RaidFrames) -- customDebuffBars entries carry
--  classFilters={[classKey]=true} and render through the EXISTING
--  BuildChain/ApplyGroupConfig path, no new engine machinery.
--
--  ID scheme mirrors ns.BM2_AddFilter: a single monotonically increasing counter,
--  never reused, so a deleted bar's engine-side declarations (ADD-ONLY on the
--  container) never collide with a later bar.
-------------------------------------------------------------------------------

-- Ensures db.profile.playerAuraBars exists before writing: PAB() alone is read-only
-- and may return nil, and `PAB() or {}` silently writes into a throwaway table that
-- never persists. Only CRUD (write) functions call this.
local function PABEnsure()
    local saved = mod.db
    if not (saved and saved.profile) then
        return nil
    end
    saved.profile.playerAuraBars = saved.profile.playerAuraBars or {}
    return saved.profile.playerAuraBars
end
-- WoW Forever: returns through the checked reader above, so a table created
-- here passes the one-time buff clear before anything writes to it.
if CludesUI.FvBW then
    PABEnsure = function()
        local saved = mod.db
        if not (saved and saved.profile) then
            return nil
        end
        saved.profile.playerAuraBars = saved.profile.playerAuraBars or {}
        return PAB()
    end
end

local function NextBarId(cfg)
    cfg.nextBarId = (cfg.nextBarId or 1)
    local ident = cfg.nextBarId
    cfg.nextBarId = ident + 1
    return ident
end

-------------------------------------------------------------------------------
--  Buff Filters (BM2-style named spell sets)
--
--  Global registry (db.profile.playerAuraBars.pabFilters), same shape as
--  RaidFrames' ns.BM2_Filters storage ({ nextId = 1, list = {} }), id/name/nextId
--  counter pattern mirrored 1:1. User-created filters are fully renameable/deletable;
--  the 10 curated presets imported via ns.PAB_ImportBM2Filters carry `f.preset = true`
--  and are NOT renameable or deletable (Filter Editor sidebar/detail-header guards).
--  Spell-level checkboxes stay editable in a preset -- only its name/existence is
--  protected.
--
--  Referenced by id from any buff-side cfg's `filters` table ([filterId]=true): the
--  default Buffs bar and every custom buff bar share ONE filter registry. Own-only
--  tracking (BM2's ownFilters/ownExtras) is NOT implemented here; bar.ownOnlySpells
--  stays reserved-but-unused.
-------------------------------------------------------------------------------

local function FilterStore(cfg)
    cfg.pabFilters = cfg.pabFilters or { nextId = 1, list = {} }
    return cfg.pabFilters
end

-- The filter list every picker and editor shows: the stored list itself, or,
-- on a client missing presets the other one offers, a fresh copy without them
-- (ns.PAB_OtherClientPreset).
function mod.PAB_Filters()
    local pabCfg = PAB()
    local storage = pabCfg and pabCfg.pabFilters
    local entries = storage and storage.list or nil
    if not entries or next(mod.PAB_OTHER_ONLY_PRESETS) == nil then
        return entries
    end
    local result = {}
    for i = 1, #entries do
        if not mod.PAB_OtherClientPreset(entries[i]) then
            result[#result + 1] = entries[i]
        end
    end
    return result
end

-- Scans the stored list (no copy per lookup); nil for a preset only the other
-- client offers, so every resolver treats an assignment to it as a dangling id.
function mod.PAB_GetFilter(ident)
    local pabCfg = PAB()
    local storage = pabCfg and pabCfg.pabFilters
    local entries = storage and storage.list
    if not entries then
        return nil
    end
    for i = 1, #entries do
        local frame = entries[i]
        if frame.id == ident then
            if mod.PAB_OtherClientPreset(frame) then
                return nil
            end
            return frame
        end
    end
end

-- Profiles travel between retail and WoW Forever. A preset filter only the
-- other client offers stays stored untouched (bars and states intact for the
-- next visit there) but is hidden here. Seeded filters carry the catalogue's
-- preset name, so the name identifies the preset.
function mod.PAB_OtherClientPreset(frame)
    return frame.preset and mod.PAB_OTHER_ONLY_PRESETS[frame.name] or false
end

-- An id a preset filter keeps only for the other client: never shown or
-- resolved here, its stored state waits for that client. On WoW Forever that
-- is every id only the retail catalogue curates under the preset. On retail
-- it is an id the Forever seed added (f.foreverSeeded, see
-- ns.PAB_ImportBM2Filters) that retail does not curate there: a retail user
-- may add such an id by hand, so only the seed's own note tells them apart.
function mod.PAB_OtherClientSpell(frame, ident)
    local filterKey = frame.preset and mod.PAB_PRESET_KEY[frame.name]
    if not filterKey then
        return false
    end
    local here = CludesUI.BUFF_PRESET_IDS[filterKey]
    if here and here[ident] then
        return false
    end
    if CludesUI.IS_FOREVER == true then
        local otherSet = CludesUI.BUFF_PRESET_OTHER_IDS[filterKey]
        return (otherSet and otherSet[ident]) == true
    end
    local m = frame.foreverSeeded
    return (m and m[ident]) == true
end

-- True for a stored filter id that belongs to a preset only the other client
-- offers (ns.PAB_GetFilter returns nil for it); false for every other id,
-- dangling ones included. Always false while this client offers every preset.
function mod.PAB_HiddenPresetFilter(ident)
    if next(mod.PAB_OTHER_ONLY_PRESETS) == nil then
        return false
    end
    local pabCfg = PAB()
    local storage = pabCfg and pabCfg.pabFilters
    local entries = storage and storage.list
    if not entries then
        return false
    end
    for i = 1, #entries do
        if entries[i].id == ident then
            return mod.PAB_OtherClientPreset(entries[i]) == true
        end
    end
    return false
end

function mod.PAB_AddFilter(label)
    local pabCfg = PABEnsure()
    if not pabCfg then
        return nil
    end
    local storage = FilterStore(pabCfg)
    local frame = { id = storage.nextId, name = label or "New Filter", spells = {} }
    storage.nextId = storage.nextId + 1
    storage.list[#storage.list + 1] = frame
    return frame
end

function mod.PAB_RenameFilter(ident, label)
    local frame = mod.PAB_GetFilter(ident)
    if frame and label and label ~= "" then
        frame.name = label
    end
end

-- Also strips the filter's assignment from every buff-side cfg that could reference
-- it: default Buffs bar + every custom buff bar (both lanes), plus the player UNIT
-- FRAME's buff filter lanes -- it shares this registry through its own keys
-- (buffFilters/buffNegFilters, see PlayerBuffChain in CUI_UnitFrames_AuraContainers.lua).
function mod.PAB_DeleteFilter(ident)
    local pabCfg = PAB()
    if not (pabCfg and pabCfg.pabFilters) then
        return
    end
    local entries = pabCfg.pabFilters.list
    for i = #entries, 1, -1 do
        if entries[i].id == ident then
            table.remove(entries, i)
        end
    end
    local function Strip(barFrame, isDefault)
        if barFrame.filters then
            barFrame.filters[ident] = nil
        end
        if barFrame.negFilters then
            barFrame.negFilters[ident] = nil
        end
        -- No-empty rule: deleting an ENABLED bar's last content source falls
        -- back to All Buffs, same as unchecking it in the Filters dropdown
        -- would. Disabled bars keep their stored state untouched (the
        -- EnsureBarEnable invariant).
        if barFrame.enabled ~= false and not BuffBarHasContent(barFrame, isDefault) then
            barFrame.showAllBuffs = nil
        end
    end
    if pabCfg.defaultBuffs then
        Strip(pabCfg.defaultBuffs, true)
    end
    local customBars = pabCfg.customBuffBars
    if customBars then
        for i = 1, #customBars do
            Strip(customBars[i], false)
        end
    end
    -- Editing-spec bucket bars share the same filter registry.
    if pabCfg.pabSpecBars then
        for _, bar in pairs(pabCfg.pabSpecBars) do
            local blockList = bar.buffBars
            if blockList then
                for i = 1, #blockList do
                    Strip(blockList[i], false)
                end
            end
        end
    end
    local ps = mod.db and mod.db.profile and mod.db.profile.player
    if ps then
        if ps.buffFilters then
            ps.buffFilters[ident] = nil
        end
        if ps.buffNegFilters then
            ps.buffNegFilters[ident] = nil
        end
        -- Same fallback for the player frame's buff filter (shared registry).
        if
            ps.buffShowAll == false
            and ps.buffHasDuration ~= true
            and not (ps.buffFilters and next(ps.buffFilters))
            and not (ps.buffSpells and #ps.buffSpells > 0)
        then
            ps.buffShowAll = nil
        end
        -- The player FRAME's buff container resolves this registry through the
        -- UF reload pass, not through the PAB apply the caller runs.
        if _G._CUUF_ReloadFrames then
            _G._CUUF_ReloadFrames()
        end
    end
end

-- Checkbox state for one spell within one filter. state=nil removes the spell
-- entirely: every PAB filter spell is "custom", no curated/preset spell to fall back to.
-- The write applies to the whole SAME-NAME FAMILY within the filter: PAB flattens
-- curated alternates into their own keys, and the Filter Editor shows one row per
-- NAME (lowest id), so a click on the visible row must carry the hidden alternates
-- with it -- otherwise a disabled-seeded family like Divine Hymn (64843 + alt
-- 64844) checks only the primary while the buff that actually lands is the alt
-- (field report 2026-08-16: "64844 not tracked"). Name-matching mirrors the
-- editor's dedup exactly (both fall back to the id when the name is uncached).
-- Ids kept only for the other client (ns.PAB_OtherClientSpell) are never
-- rewritten from here.
function mod.PAB_SetSpellState(filterId, spellId, status)
    local frame = mod.PAB_GetFilter(filterId)
    if not frame then
        return
    end
    local function Write(ident)
        if status == nil then
            frame.spells[ident] = nil
        else
            frame.spells[ident] = status and true or false
        end
    end
    Write(spellId)
    -- Members of a curated family follow the clicked row, deletes included: the editor
    -- shows one row per NAME, so a member under a different name has a row of its own
    -- but is still the same buff, and would otherwise linger as a tracked id with no
    -- row left to clear it from. Only ids the filter already holds are rewritten.
    local fam = mod.PAB_SPELL_FAMILY and mod.PAB_SPELL_FAMILY[spellId]
    if fam then
        for i = 1, #fam do
            if fam[i] ~= spellId and frame.spells[fam[i]] ~= nil and not mod.PAB_OtherClientSpell(frame, fam[i]) then
                Write(fam[i])
            end
        end
    end
    local label = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
    if label then
        for ident in pairs(frame.spells) do
            if
                ident ~= spellId
                and not mod.PAB_OtherClientSpell(frame, ident)
                and C_Spell.GetSpellName(ident) == label
            then
                Write(ident)
            end
        end
    end
end

-- On retail, a Forever-seeded id kept inert here (ns.PAB_OtherClientSpell)
-- counts as absent, and every add drops the id's seed note (one can outlive
-- its id after a delete): the added id is an ordinary row on both clients.
function mod.PAB_AddSpellToFilter(filterId, spellId)
    local frame = mod.PAB_GetFilter(filterId)
    if not (frame and spellId and spellId > 0) then
        return false
    end
    local m = CludesUI.IS_FOREVER ~= true and frame.foreverSeeded or nil
    if frame.spells[spellId] ~= nil and not (m and mod.PAB_OtherClientSpell(frame, spellId)) then
        return false -- already present
    end
    if m then
        m[spellId] = nil
    end
    frame.spells[spellId] = true
    return true
end

-- Union of a buff-side cfg's direct spells (cfg.spells) and the enabled spells of
-- every filter it references (cfg.filters), minus own-only tracking (see above).
-- Sorted so the caller's signature diffing stays deterministic.
function mod.PAB_ResolveSpells(conf)
    local set = {}
    local direct
    local spellSet = conf.spells
    if spellSet then
        direct = {}
        for i = 1, #spellSet do
            set[spellSet[i]] = true
            direct[spellSet[i]] = true
            ExpandFamily(direct, spellSet[i])
            ExpandFamily(set, spellSet[i])
        end
    end
    -- Under the broad modes (All Buffs / Has Duration) the hide-lane filters leave via
    -- the catch-all's excludeSpellIDs (see BuffBarChain), so the spells group carries
    -- only Extra Spells there. In add mode the show-lane filters union in, minus the
    -- hide lane. Extra Spells stay additive in both modes and win over the hide lane.
    local addMode = conf.showAllBuffs == false and conf.hasDuration ~= true
    local filters = addMode and conf.filters or nil
    if filters then
        for filterId in pairs(filters) do
            local frame = mod.PAB_GetFilter(filterId)
            if frame then
                for ident, on in pairs(frame.spells) do
                    if on and not mod.PAB_OtherClientSpell(frame, ident) then
                        set[ident] = true
                        ExpandFamily(set, ident, frame.spells)
                    end
                end
            end
        end
    end
    local negFilters = addMode and conf.negFilters or nil
    if negFilters then
        local hide = {}
        for filterId in pairs(negFilters) do
            local frame = mod.PAB_GetFilter(filterId)
            if frame then
                for ident, on in pairs(frame.spells) do
                    if on and not mod.PAB_OtherClientSpell(frame, ident) then
                        hide[ident] = true
                        ExpandFamily(hide, ident, frame.spells)
                    end
                end
            end
        end
        for ident in pairs(hide) do
            if not (direct and direct[ident]) then
                set[ident] = nil
            end
        end
    end
    local result = {}
    for ident in pairs(set) do
        result[#result + 1] = ident
    end
    table.sort(result)
    return result
end

-------------------------------------------------------------------------------
--  One-time filter copies between this registry and the Raid Frames Buff
--  Manager library (via the parent-published CludesUI._BM2FilterBridge --
--  absent when that module is disabled, and both editor buttons hide). The
--  registries stay fully independent: a copy matches filters by NAME in the
--  TARGET's own id space (missing filters are created, same-named ones have
--  their spell content replaced), so no assignment on either side ever needs
--  remapping and nothing stays linked afterward.
-------------------------------------------------------------------------------

local function NameToId(entries)
    local m = {}
    for i = 1, #entries do
        local frame = entries[i]
        if m[frame.name] == nil then
            m[frame.name] = frame.id
        end
    end
    return m
end

-- "Copy Raid & Party Filters" (our Filter Editor): one-time copy of the Buff
-- Manager library into this registry. The library stores curated PRIMARY ids
-- and expands talent/rank alternates at resolution; this registry flattens
-- alternates into their own keys (seed convention), so each copied primary
-- fans out to its alternates with the same state.
function mod.PAB_CopyBM2FiltersIn()
    local buffRules = CludesUI._BM2FilterBridge
    local pabCfg = PABEnsure()
    if not (buffRules and pabCfg) then
        return false
    end
    local source = buffRules.Filters() or {}
    local altsMap = buffRules.PresetAlts and buffRules.PresetAlts() or nil
    -- An id typed into a library filter tracks that aura alone there, so it
    -- comes over alone (an older library has no such ids).
    local typedIn = buffRules.SpellExact
    local nameToId = NameToId(FilterStore(pabCfg).list)
    for i = 1, #source do
        local scrollFrame = source[i]
        local typeId = nameToId[scrollFrame.name]
        local typeFilter = typeId and mod.PAB_GetFilter(typeId)
        if not typeFilter then
            typeFilter = mod.PAB_AddFilter(scrollFrame.name)
        end
        if typeFilter then
            local spellSet = {}
            for ident, on in pairs(scrollFrame.spells) do
                -- Ids the library keeps only for the other client are not
                -- this client's to copy.
                if not buffRules.OtherClientSpell(scrollFrame, ident) then
                    local status = on and true or false
                    spellSet[ident] = status
                    local a = altsMap and altsMap[ident]
                    if a and not (typedIn and typedIn(scrollFrame, ident)) then
                        for jdx = 1, #a do
                            spellSet[a[jdx]] = status
                        end
                    end
                end
            end
            -- Retail: a copied id is the library's live content, no longer a
            -- Forever-seed note.
            local m = typeFilter.foreverSeeded
            if m and CludesUI.IS_FOREVER ~= true then
                for ident in pairs(spellSet) do
                    m[ident] = nil
                end
            end
            -- The copy overwrites what this editor shows; ids kept only for
            -- the other client are not shown, so they stay.
            for ident, on in pairs(typeFilter.spells) do
                if spellSet[ident] == nil and mod.PAB_OtherClientSpell(typeFilter, ident) then
                    spellSet[ident] = on
                end
            end
            typeFilter.spells = spellSet
        end
    end
    -- The player FRAME's buff container resolves this registry through the UF
    -- reload pass, not through the PAB apply the caller runs.
    if _G._CUUF_ReloadFrames then
        _G._CUUF_ReloadFrames()
    end
    return true
end

-- "Copy Player Auras Filters" (Buff Manager side): one-time copy of this
-- registry's filter setups INTO the Buff Manager library by name -- same-
-- named filters take our spell states wholesale, missing filters are created.
-- Library ids never change, so indicator assignments and banked spec-override
-- forks stay valid.
function mod.PAB_CopyOwnFiltersIntoBM2()
    local buffRules = CludesUI._BM2FilterBridge
    local pabCfg = PAB()
    if not (buffRules and pabCfg) then
        return false
    end
    -- Alt id -> primary: our registry flattens talent/rank alternates into
    -- their own keys; the Buff Manager library stores primaries and expands
    -- alternates at resolution, so alternates fold onto their primary here.
    local altToPrimary = {}
    local altsMap = buffRules.PresetAlts and buffRules.PresetAlts() or nil
    if altsMap then
        for primary, alts in pairs(altsMap) do
            for i = 1, #alts do
                altToPrimary[alts[i]] = primary
            end
        end
    end
    -- Presets only the other client offers stay out (ns.PAB_Filters' view).
    local own = mod.PAB_Filters() or FilterStore(pabCfg).list
    local nameToId = NameToId(buffRules.Filters() or {})
    for i = 1, #own do
        local of = own[i]
        local typeId = nameToId[of.name]
        if not typeId then
            local nf = buffRules.AddFilter(of.name)
            typeId = nf and nf.id
        end
        local typeFilter = typeId and buffRules.GetFilter(typeId)
        if typeFilter then
            local desired = {}
            for ident, on in pairs(of.spells) do
                -- Ids kept only for the other client are not this client's to copy.
                if not mod.PAB_OtherClientSpell(of, ident) then
                    local p = altToPrimary[ident]
                    if p then
                        -- Primary's own explicit state wins over an alternate's.
                        if of.spells[p] == nil and desired[p] == nil then
                            desired[p] = on and true or false
                        end
                    else
                        desired[ident] = on and true or false
                    end
                end
            end
            local curated = typeFilter.preset and buffRules.CuratedSpells and buffRules.CuratedSpells(typeFilter.preset) or nil
            for ident, on in pairs(desired) do
                -- An id the library keeps only for the other client counts as
                -- absent (BM2_AddCustomSpell takes it over).
                if
                    (typeFilter.spells[ident] == nil or buffRules.OtherClientSpell(typeFilter, ident))
                    and not (curated and curated[ident])
                then
                    -- New non-curated id must carry the custom marker or the
                    -- library's curation prune strips it on the next merge.
                    buffRules.AddCustomSpell(typeId, ident)
                end
                buffRules.SetSpellState(typeId, ident, on)
            end
            -- Our version is authoritative: ids we don't carry go unchecked
            -- (false, not nil -- a nil curated id gets re-seeded to its
            -- default) and foreign custom ids are removed. Ids the library
            -- keeps only for the other client are left as they are.
            for ident in pairs(typeFilter.spells) do
                if desired[ident] == nil and not buffRules.OtherClientSpell(typeFilter, ident) then
                    if typeFilter.custom and typeFilter.custom[ident] then
                        buffRules.SetSpellState(typeId, ident, nil)
                    else
                        buffRules.SetSpellState(typeId, ident, false)
                    end
                end
            end
        end
    end
    buffRules.Refresh()
    return true
end

-- Parent-published counterpart of _BM2FilterBridge: lets the Buff Manager's
-- Filter Editor drive its one-time copy from its side. Absent = this module
-- is disabled, and its button hides.
CludesUI._PABFilterBridge = {
    CopyIntoBM2 = function()
        return mod.PAB_CopyOwnFiltersIntoBM2()
    end,
}

function mod.PAB_CustomBuffBars()
    local pabCfg = PAB()
    return pabCfg and pabCfg.customBuffBars or nil
end

-------------------------------------------------------------------------------
-- Buff Manager filter import: the 10 curated preset filters (Defensives, Raid CDs,
--  Externals, Core/Lesser Healing Buffs, Support, Offensive CDs, Movement, Utility,
--  Consumables) as a starting point for PAB Filters.
--
--  Both tables below derive AT LOAD from the parent's canonical
--  CludesUI.BUFF_PRESETS catalogue (CludesUI_BuffPresets.lua -- THE
--  single curation source, bound directly by the RF Buff Manager, so the two
--  systems can never drift). PAB flattens `alts` into their own rows (PAB
--  Filters have no primary/alt grouping: every id is its own checkbox row);
--  alts inherit their primary's disabled state and class hint. `disabled`
--  entries import unchecked here too. One pass over ~250 entries at load.
-------------------------------------------------------------------------------

-- Display-only hint: which class a curated (imported) spell belongs to, so the
-- Filter Editor can group/color rows. Purely cosmetic -- PAB_ResolveSpells/
-- PAB_SetSpellState never consult it; a filter's spells are always a flat {id=bool}
-- set. "ALL"-class spells get no hint (no class header row for them).
local SPELL_CLASS_HINTS = {}
local BM2_FILTER_SEED = {}
-- Curated primary -> alts (own copy: the RF bridge is absent when that
-- module is disabled, and the family heal below must not depend on it).
local PRESET_ALTS = {}
do
    local BP = CludesUI.BUFF_PRESETS
    for i = 1, #BP.filters do
        local def = BP.filters[i]
        local entries = BP.spells[def.key]
        local isEnabled, disabled = {}, {}
        if entries then
            for ident, details in pairs(entries) do
                local dst = details.disabled and disabled or isEnabled
                dst[#dst + 1] = ident
                if details.class ~= "ALL" then
                    SPELL_CLASS_HINTS[ident] = details.class
                end
                if details.alts then
                    PRESET_ALTS[ident] = details.alts
                    for jdx = 1, #details.alts do
                        local alt = details.alts[jdx]
                        dst[#dst + 1] = alt
                        if details.class ~= "ALL" then
                            SPELL_CLASS_HINTS[alt] = details.class
                        end
                    end
                end
            end
        end
        table.sort(isEnabled)
        table.sort(disabled)
        BM2_FILTER_SEED[#BM2_FILTER_SEED + 1] =
            { key = def.key, name = def.name, enabled = isEnabled, disabled = disabled }
    end
    -- Every member of a curated family (primary + its alternates) maps to the whole
    -- member list, so PAB_ResolveSpells can expand from whichever id the user has.
    -- Families are disjoint, so one carried by two preset filters rewrites an equal entry.
    local fams = {}
    for primary, alts in pairs(PRESET_ALTS) do
        local fam = { primary }
        for i = 1, #alts do
            fam[#fam + 1] = alts[i]
        end
        for i = 1, #fam do
            fams[fam[i]] = fam
        end
    end
    mod.PAB_SPELL_FAMILY = fams
    -- Preset name -> key across both clients' catalogues, and the names of the
    -- presets only the other client offers (ns.PAB_OtherClientPreset,
    -- ns.PAB_OtherClientSpell): seeded filters carry the catalogue's name.
    local keyByName, offered, otherOnly = {}, {}, {}
    for i = 1, #BP.filters do
        keyByName[BP.filters[i].name] = BP.filters[i].key
        offered[BP.filters[i].key] = true
    end
    local otherSet = CludesUI.BUFF_PRESET_OTHER_FILTERS
    for i = 1, #otherSet do
        local def = otherSet[i]
        if keyByName[def.name] == nil then
            keyByName[def.name] = def.key
        end
        if not offered[def.key] then
            otherOnly[def.name] = true
        end
    end
    mod.PAB_PRESET_KEY = keyByName
    mod.PAB_OTHER_ONLY_PRESETS = otherOnly
end
mod.PAB_SPELL_CLASS_HINTS = SPELL_CLASS_HINTS

-- PAB_ImportBM2Filters (below) is idempotent: it skips any seed entry whose exact
-- name already exists, so re-clicking Import creates no duplicates, and returns the
-- number of filters actually created.
--
-- PAB_AllPresetSpells returns every spell ID across all 10 curated presets (enabled
-- AND disabled entries both count). Because BM2_FILTER_SEED already has `alts`
-- flattened into its lists, this is a superset of what BM2_AllPresetSpells returns --
-- intended, alts ARE valid trackable buff IDs.
function mod.PAB_AllPresetSpells()
    local set = {}
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        for jdx = 1, #seed.enabled do
            set[seed.enabled[jdx]] = true
        end
        for jdx = 1, #seed.disabled do
            set[seed.disabled[jdx]] = true
        end
    end
    local result = {}
    for ident in pairs(set) do
        result[#result + 1] = ident
    end
    table.sort(result)
    return result
end

function mod.PAB_ImportBM2Filters()
    local byName = {}
    local entries = mod.PAB_Filters() or {}
    for i = 1, #entries do
        byName[entries[i].name] = entries[i]
    end

    -- WoW Forever: every id this seed adds that the retail catalogue does not
    -- curate under the preset is noted on the filter (f.foreverSeeded), so
    -- retail keeps it inert when the profile goes back there
    -- (ns.PAB_OtherClientSpell). Nothing is noted on retail.
    local retailIds = CludesUI.IS_FOREVER == true and CludesUI.BUFF_PRESET_OTHER_IDS or nil
    local function NoteSeed(frame, filterKey, ident)
        if not retailIds then
            return
        end
        local current = retailIds[filterKey]
        if current and current[ident] then
            return
        end
        local m = frame.foreverSeeded
        if not m then
            m = {}
            frame.foreverSeeded = m
        end
        m[ident] = true
    end

    local created = 0
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        local frame = byName[seed.name]
        if not frame then
            frame = mod.PAB_AddFilter(seed.name)
            if frame then
                for jdx = 1, #seed.enabled do
                    frame.spells[seed.enabled[jdx]] = true
                end
                for jdx = 1, #seed.disabled do
                    frame.spells[seed.disabled[jdx]] = false
                end
                if retailIds then
                    for jdx = 1, #seed.enabled do
                        NoteSeed(frame, seed.key, seed.enabled[jdx])
                    end
                    for jdx = 1, #seed.disabled do
                        NoteSeed(frame, seed.key, seed.disabled[jdx])
                    end
                end
                created = created + 1
            end
        end
        -- Runs every call, not just on fresh creation, so filters the idempotent-by-name
        -- skip would otherwise leave unflagged forever still get the protection flag.
        if frame then
            frame.preset = true
            -- Additive curation merge (mirrors BM2's EnsureFilters): curated ids
            -- NEW since this filter was created join it with their seed state;
            -- ids the user already has (either state) are never overwritten.
            -- No prune counterpart: PAB has no custom-vs-curated marker, so
            -- removing non-seed ids would delete user additions.
            for jdx = 1, #seed.enabled do
                local ident = seed.enabled[jdx]
                if frame.spells[ident] == nil then
                    frame.spells[ident] = true
                    NoteSeed(frame, seed.key, ident)
                end
            end
            for jdx = 1, #seed.disabled do
                local ident = seed.disabled[jdx]
                if frame.spells[ident] == nil then
                    frame.spells[ident] = false
                    NoteSeed(frame, seed.key, ident)
                end
            end
            -- Family heal: a checked PRIMARY whose curated alternates were left
            -- unchecked (the pre-fix editor toggled only the visible row) pulls
            -- its alternates up. Enable-only, primary->alt only, curated
            -- families only: never disables, never touches user-added ids.
            for primary, alts in pairs(PRESET_ALTS) do
                if frame.spells[primary] == true then
                    for k = 1, #alts do
                        if frame.spells[alts[k]] == false then
                            frame.spells[alts[k]] = true
                        end
                    end
                end
            end
        end
    end
    return created
end

function mod.PAB_CustomDebuffBars()
    local pabCfg = PAB()
    return pabCfg and pabCfg.customDebuffBars or nil
end

-- Both lookups search the legacy array first, then every editing-spec
-- bucket (ids are globally unique). Second return = the owning bucket key
-- ("allspecs" for the legacy array) for callers that gate on applicability.
function mod.PAB_GetCustomBuffBar(ident)
    local entries = mod.PAB_CustomBuffBars()
    if entries then
        for i = 1, #entries do
            if entries[i].id == ident then
                return entries[i], "allspecs"
            end
        end
    end
    local pabCfg = PAB()
    local state = pabCfg and pabCfg.pabSpecBars
    if state then
        for filterKey, b in pairs(state) do
            local blockList = b.buffBars
            if blockList then
                for i = 1, #blockList do
                    if blockList[i].id == ident then
                        return blockList[i], filterKey
                    end
                end
            end
        end
    end
end

function mod.PAB_GetCustomDebuffBar(ident)
    local entries = mod.PAB_CustomDebuffBars()
    if entries then
        for i = 1, #entries do
            if entries[i].id == ident then
                return entries[i], "allspecs"
            end
        end
    end
    local pabCfg = PAB()
    local state = pabCfg and pabCfg.pabSpecBars
    if state then
        for filterKey, b in pairs(state) do
            local blockList = b.debuffBars
            if blockList then
                for i = 1, #blockList do
                    if blockList[i].id == ident then
                        return blockList[i], filterKey
                    end
                end
            end
        end
    end
end

-- Bar objects (both kinds) also carry the same shared+category cfg fields as
-- DefaultBuffsCfg/DefaultDebuffsCfg (iconSize, durationShow/stackShow,
-- durationPosition/TextSize/OffsetX/Y/ColorR/G/B, stackPosition/TextSize/OffsetX/
-- Y/ColorR/G/B; buff/debuff bars additionally borderSize/R/G/B/A, borderTexture and
-- optional texture offset/shift/layer fields, iconZoom, padding,
-- iconsPerRow, maxRows, maxTotal; debuff bars additionally dispelColorMagic/Curse/
-- Disease/Poison/Bleed). NOT pre-populated, same as those two starting as {}:
-- BuildStyle/ComputeGrid apply the same `or <default>` fallbacks either way, so a
-- fresh bar renders with sane defaults and Options only writes fields the user touches.
function mod.PAB_AddCustomBuffBar(label, bucket)
    local pabCfg = PABEnsure()
    if not pabCfg then
        return nil
    end
    pabCfg.customBuffBars = pabCfg.customBuffBars or {}
    local barFrame = {
        id = NextBarId(pabCfg),
        name = label or "New Buff Bar",
        enabled = true,
        filters = {}, -- [filterId] = true (BM2-style assigned filters)
        spells = {}, -- {spellID, ...} direct/custom spells
        ownOnlySpells = {}, -- [spellID] = bool
        growDirection = "LEFT",
        -- Starting grid: a compact single row, deliberately distinct from the default
        -- bars' ComputeGrid fallback (11x3 for buffs) -- a fresh custom bar starts
        -- small rather than inheriting the larger grid.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    -- The edited editing-spec bucket owns the new bar; ids come from the ONE
    -- shared counter regardless of bucket.
    local target = mod.PAB_BucketBars(true, bucket, true) or pabCfg.customBuffBars
    target[#target + 1] = barFrame
    return barFrame
end

function mod.PAB_AddCustomDebuffBar(label, bucket)
    local pabCfg = PABEnsure()
    if not pabCfg then
        return nil
    end
    pabCfg.customDebuffBars = pabCfg.customDebuffBars or {}
    local barFrame = {
        id = NextBarId(pabCfg),
        name = label or "New Debuff Bar",
        enabled = true,
        classFilters = {}, -- [classKey] = true, same vocabulary as BuildChain
        growDirection = "LEFT",
        -- Same starting-grid reasoning as PAB_AddCustomBuffBar above.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    local target = mod.PAB_BucketBars(false, bucket, true) or pabCfg.customDebuffBars
    target[#target + 1] = barFrame
    return barFrame
end

-- Deletion only strips the DB entry; it deliberately does NOT remove the bar's
-- engine-side group/slots (containers are add-only). The engine-wiring layer must
-- instead detect the missing DB entry and set maxFrameCount = 0 / hide the bar's
-- frames, like disabled default groups.
-- Deep-copies a custom bar into another editing-spec bucket (the right-click
-- "Add To" menu): full settings clone -- position included -- under a fresh
-- global id; the source is untouched.
function mod.PAB_CopyCustomBar(isBuff, source, bucket)
    local pabCfg = PABEnsure()
    if not (pabCfg and source) then
        return nil
    end
    local target = mod.PAB_BucketBars(isBuff, bucket, true)
    if not target then
        return nil
    end
    local barFrame = CopyTable(source)
    barFrame.id = NextBarId(pabCfg)
    target[#target + 1] = barFrame
    return barFrame
end

-- Shared by both deletes: strip the id from every editing-spec bucket and
-- sweep its per-spec disable keys (ids are global and never reused, so a
-- deleted bar's key could only leak).
local function DeleteFromSpecBuckets(cfg, ident, listField)
    local state = cfg.pabSpecBars
    if not state then
        return
    end
    for _, b in pairs(state) do
        local blockList = b[listField]
        if blockList then
            for i = #blockList, 1, -1 do
                if blockList[i].id == ident then
                    table.remove(blockList, i)
                end
            end
        end
        if b.inhDis then
            b.inhDis[ident] = nil
        end
    end
end

function mod.PAB_DeleteCustomBuffBar(ident)
    local pabCfg = PABEnsure()
    if not pabCfg then
        return
    end
    -- WoW Forever: a delete can empty the bucket the player's class renders
    -- (its bars, or the per-spec disables the sweep clears), which moves it
    -- to the next class spec with data (ns.PAB_ForeverSpecID); a move
    -- re-drives every custom bar once.
    local fvSid = CludesUI.IS_FOREVER and mod.PAB_ForeverSpecID() or nil
    if pabCfg.customBuffBars then
        for i = #pabCfg.customBuffBars, 1, -1 do
            if pabCfg.customBuffBars[i].id == ident then
                table.remove(pabCfg.customBuffBars, i)
            end
        end
    end
    DeleteFromSpecBuckets(pabCfg, ident, "buffBars")
    if fvSid and mod.PAB_ForeverSpecID() ~= fvSid then
        ReloadAllCustomBars()
    end
end

function mod.PAB_DeleteCustomDebuffBar(ident)
    local pabCfg = PABEnsure()
    if not pabCfg then
        return
    end
    -- WoW Forever: same bucket-move check as ns.PAB_DeleteCustomBuffBar.
    local fvSid = CludesUI.IS_FOREVER and mod.PAB_ForeverSpecID() or nil
    if pabCfg.customDebuffBars then
        for i = #pabCfg.customDebuffBars, 1, -1 do
            if pabCfg.customDebuffBars[i].id == ident then
                table.remove(pabCfg.customDebuffBars, i)
            end
        end
    end
    DeleteFromSpecBuckets(pabCfg, ident, "debuffBars")
    if fvSid and mod.PAB_ForeverSpecID() ~= fvSid then
        ReloadAllCustomBars()
    end
end

-------------------------------------------------------------------------------
--  Editing-spec buckets. The legacy arrays (s.customBuffBars /
--  s.customDebuffBars) ARE the "All Specs" bucket, in place: zero migration,
--  and profiles opened by older builds keep rendering them. Every other
--  bucket lives under s.pabSpecBars[key] = { buffBars, debuffBars, inhDis },
--  key = "nonhealer"/"tanks"/"dps"/"healers" (group buckets) or "spec<ID>"
--  (a concrete spec; healer specs included). Bar ids stay globally unique
--  across buckets (the one shared s.nextBarId), so per-spec disables key on
--  the bare id. Absent pabSpecBars = feature unused = every path below
--  degenerates to the legacy behavior at zero cost.
-------------------------------------------------------------------------------

-- Role group for a specialization ID. Mirrors the RaidFrames helper
-- (ns.BM_RoleBucketForSpecID lives in a different addon namespace, hence a
-- local twin): healers/Aug = HEALER role or Augmentation (1473), keeping
-- "All Non Healers/Aug" its exact complement.
local function RoleBucketForSpecID(specID)
    -- WoW Forever specs carry no role (same rule as the RaidFrames twin).
    if CludesUI.IS_FOREVER then
        return nil
    end
    if not specID then
        return nil
    end
    if specID == 1473 then
        return "healers"
    end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specID))
    if role == "HEALER" then
        return "healers"
    end
    if role == "TANK" then
        return "tanks"
    end
    if role then
        return "dps"
    end
    -- Unknown spec/unavailable API: no role bucket beats a wrong one.
    return nil
end
mod.PAB_RoleBucketForSpecID = RoleBucketForSpecID

local function CurrentSpecID()
    -- WoW Forever: the retail spec the player's class acts as.
    if CludesUI.IS_FOREVER then
        return mod.PAB_ForeverSpecID()
    end
    local position = GetSpecialization and GetSpecialization()
    return position and GetSpecializationInfo and GetSpecializationInfo(position) or nil
end

-- Group buckets a concrete "spec<ID>" view inherits from, in display order.
-- nil for group views and unknown keys.
function mod.PAB_InheritedGroupsFor(bucket)
    local m = type(bucket) == "string" and bucket:match("^spec(%d+)$")
    local spellRef = m and tonumber(m)
    if not spellRef then
        return nil
    end
    -- WoW Forever has no spec roles: a class view inherits All Specs only.
    if CludesUI.IS_FOREVER then
        return { "allspecs" }
    end
    local result = { "allspecs" }
    local roleKey = RoleBucketForSpecID(spellRef)
    if roleKey ~= "healers" then
        result[#result + 1] = "nonhealer"
    end
    if roleKey then
        result[#result + 1] = roleKey
    end
    return result
end

local function SpecBarBucket(cfg, filterKey, create)
    local state = cfg.pabSpecBars
    if not state then
        if not create then
            return nil
        end
        state = {}
        cfg.pabSpecBars = state
    end
    local b = state[filterKey]
    if not b then
        if not create then
            return nil
        end
        b = { buffBars = {}, debuffBars = {}, inhDis = {} }
        state[filterKey] = b
    end
    b.buffBars = b.buffBars or {}
    b.debuffBars = b.debuffBars or {}
    b.inhDis = b.inhDis or {}
    return b
end

-- WoW Forever: a class acts as the first of its retail specs (class order)
-- whose "spec<ID>" bucket holds data (buff bars, debuff bars or per-spec
-- disables of All Specs bars), else its first spec. token nil = the player's
-- class. Resolved per reload / page build / removal, never per frame.
function mod.PAB_BucketHasData(ident, state)
    local b = state and state["spec" .. ident]
    if b == nil then
        return false
    end
    if (b.buffBars and #b.buffBars > 0) or (b.debuffBars and #b.debuffBars > 0) then
        return true
    end
    local dis = b.inhDis
    if not (dis and next(dis) ~= nil) then
        return false
    end
    if not CludesUI.IS_FOREVER then
        return true
    end
    -- WoW Forever renders All Specs and the class's own bucket only, so only
    -- a disable of an All Specs bar counts. Scans the bar arrays in place.
    local pabCfg = PAB()
    local entries = pabCfg and pabCfg.customBuffBars
    for i = 1, (entries and #entries or 0) do
        if dis[entries[i].id] then
            return true
        end
    end
    entries = pabCfg and pabCfg.customDebuffBars
    for i = 1, (entries and #entries or 0) do
        if dis[entries[i].id] then
            return true
        end
    end
    return false
end
function mod.PAB_ForeverSpecID(token)
    local pabCfg = PAB()
    return CludesUI.ForeverClassSpec(token, mod.PAB_BucketHasData, pabCfg and pabCfg.pabSpecBars)
end
-- The bucket a Forever class row edits: the one that class renders.
function mod.PAB_ForeverKey(token)
    local spellRef = mod.PAB_ForeverSpecID(token)
    return spellRef and ("spec" .. spellRef) or nil
end

-- Bucket bar array for an EDITED view ("allspecs"/nil = the legacy arrays).
function mod.PAB_BucketBars(isBuff, filterKey, create)
    local s = create and PABEnsure() or PAB()
    if not s then
        return nil
    end
    if not filterKey or filterKey == "allspecs" then
        if isBuff then
            if create then
                s.customBuffBars = s.customBuffBars or {}
            end
            return s.customBuffBars
        end
        if create then
            s.customDebuffBars = s.customDebuffBars or {}
        end
        return s.customDebuffBars
    end
    local b = SpecBarBucket(s, filterKey, create)
    if not b then
        return nil
    end
    if isBuff then
        return b.buffBars
    end
    return b.debuffBars
end

-- Per-spec disable of a GROUP bucket's bar, stored on the viewing spec's
-- concrete "spec<ID>" bucket (ids are global, the bare id suffices).
function mod.PAB_InhDisabled(concreteKey, ident)
    local pabCfg = PAB()
    local b = pabCfg and SpecBarBucket(pabCfg, concreteKey, false)
    return (b and b.inhDis and b.inhDis[ident]) and true or false
end

function mod.PAB_SetInhDisabled(concreteKey, ident, disabled)
    local pabCfg = PABEnsure()
    if not (pabCfg and concreteKey and ident) then
        return
    end
    -- WoW Forever: clearing the last per-spec disable can move the bucket
    -- the player's class renders (see ns.PAB_DeleteCustomBuffBar).
    local fvSid = CludesUI.IS_FOREVER and mod.PAB_ForeverSpecID() or nil
    local b = SpecBarBucket(pabCfg, concreteKey, true)
    b.inhDis[ident] = disabled and true or nil
    if fvSid and mod.PAB_ForeverSpecID() ~= fvSid then
        ReloadAllCustomBars()
    end
end

-- Does bucketKey's content render for the given spec?
local function BucketApplies(bucket, spellRef)
    if not bucket or bucket == "allspecs" then
        return true
    end
    local m = bucket:match("^spec(%d+)$")
    if m then
        return spellRef == tonumber(m)
    end
    -- WoW Forever has no spec roles: no group bucket applies there.
    if CludesUI.IS_FOREVER then
        return false
    end
    if not spellRef then
        return false
    end
    local roleKey = RoleBucketForSpecID(spellRef)
    if bucket == "nonhealer" then
        return roleKey ~= "healers"
    end
    return bucket == roleKey
end

-- Render verdict for a custom bar: the MODULE is on (Disable All is a full
-- stand-down, custom bars included -- the field bug was custom bars
-- lingering), the bar's own toggle is on, its owning bucket applies to the
-- CURRENT spec, and (group buckets, All Specs included) this spec hasn't
-- per-spec disabled it. bucketKey nil = legacy = "allspecs".
function mod.PAB_BarActive(barFrame, bucket)
    if not barFrame or barFrame.enabled == false then
        return false
    end
    local sMaster = PAB()
    if not sMaster or sMaster.enabled ~= true then
        return false
    end
    local spellRef = CurrentSpecID()
    if not BucketApplies(bucket, spellRef) then
        return false
    end
    local isOwn = bucket and bucket:match("^spec%d") and true or false
    if not isOwn and spellRef then
        local pabCfg = PAB()
        local con = pabCfg and pabCfg.pabSpecBars and pabCfg.pabSpecBars["spec" .. spellRef]
        if con and con.inhDis and con.inhDis[barFrame.id] then
            return false
        end
    end
    return true
end

Inner.broken = false
