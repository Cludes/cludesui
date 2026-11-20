if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Store.lua
--
--  The spell assignment store (CludesUIDB.spellAssignments), the per-spell
--  stores, markers and the cooldown claim set.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ECME = Inner.ECME

-------------------------------------------------------------------------------
--  Dedicated spell assignment store helpers
--  Lives at CludesUIDB.spellAssignments; spell/bar data is per-profile at
--  spellAssignments.profiles[name].specProfiles[specKey]. Top-level (not inside
--  the profile blob) so it never travels with profile export/module sync, but
--  IS forked/dropped/renamed with the profile (CludesUI_Profiles.lua). Active
--  bucket resolves live via ns.GetActiveSpecProfiles(). One local table (Lua 5.1's 200-local cap).
-------------------------------------------------------------------------------
local SpellStore = {}

function SpellStore.Get()
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.spellAssignments then
        CludesUIDB.spellAssignments = { profiles = {} }
    end
    return CludesUIDB.spellAssignments
end

-- Active profile name for the per-profile spell store; read live so a profile switch auto-follows the next CDM rebuild, no repoint step.
function mod.GetActiveProfileName()
    return (CludesUIDB and CludesUIDB.activeProfile) or "Default"
end

-- Per-profile spell store: copying a profile forks its CDM; deleting a bar never crosses
-- profiles. Until the seeding migration (cdm_per_profile_spell_store_v1) completes (_perProfileSeeded),
-- fork the legacy shared spellAssignments.specProfiles on first access so a profile never reads empty mid-migration.
function mod.GetSpecProfilesForProfile(profileName)
    local assignments = SpellStore.Get()
    if not assignments.profiles then
        assignments.profiles = {}
    end
    local specBucket = assignments.profiles[profileName]
    if not specBucket then
        specBucket = { specProfiles = {} }
        if not assignments._perProfileSeeded and type(assignments.specProfiles) == "table" and next(assignments.specProfiles) then
            local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy
            if DeepCopy then
                specBucket.specProfiles = DeepCopy(assignments.specProfiles)
            end
        end
        assignments.profiles[profileName] = specBucket
    end
    if not specBucket.specProfiles then
        specBucket.specProfiles = {}
    end
    return specBucket.specProfiles
end

-- Cross-spec broadcast set for Tracking Bars: bar identities (preset key/custom spellID)
-- pushed to every spec via "Add Bar to All Specs". Lives on the profile bucket OUTSIDE
-- specProfiles (survives spec switches/reloads, forks with profile); drives the Add/Remove toggle label.
function mod.GetActiveTBBBroadcastSet()
    local label = mod.GetActiveProfileName()
    -- Ensure the bucket exists (with legacy seeding) via the canonical accessor.
    mod.GetSpecProfilesForProfile(label)
    local assignments = SpellStore.Get()
    local specBucket = assignments.profiles and assignments.profiles[label]
    if not specBucket then
        return {}
    end
    if not specBucket.tbbBroadcast then
        specBucket.tbbBroadcast = {}
    end
    return specBucket.tbbBroadcast
end

-- Smooth-fill switches for Tracking Bars (Bar Layout > Smooth Bars). ONE setting for ALL
-- bars in EVERY spec: profile bucket OUTSIDE specProfiles (same home as the broadcast set).
-- Keys buffs/cooldowns; absent buffs reads ENABLED, absent cooldowns reads DISABLED (defaults).
function mod.GetTBBSmoothSettings()
    local label = mod.GetActiveProfileName()
    mod.GetSpecProfilesForProfile(label)
    local assignments = SpellStore.Get()
    local specBucket = assignments.profiles and assignments.profiles[label]
    if not specBucket then
        return nil
    end
    if not specBucket.tbbSmooth then
        specBucket.tbbSmooth = {}
    end
    return specBucket.tbbSmooth
end

-- Active SPELL LAYOUT name. Layouts are an account-wide library (spellAssignments.profiles[name])
-- with a SINGLE account-wide active pointer (spellAssignments.activeLayout), DETACHED from CUI
-- profiles: a profile only changes the active layout via an opt-in binding
-- (spellAssignments.profileBindings) applied by ns.ApplyProfileBinding on profile load. Self-heals to a valid layout.
function mod.GetActiveLayoutName()
    local assignments = SpellStore.Get()
    if not assignments.profiles then
        assignments.profiles = {}
    end
    local label = assignments.activeLayout
    if type(label) ~= "string" or type(assignments.profiles[label]) ~= "table" then
        -- Self-heal: prefer a layout named after the current profile, else any existing layout, else the profile name (creates it).
        local current = (CludesUIDB and CludesUIDB.activeProfile) or "Default"
        label = nil
        if type(assignments.profiles[current]) == "table" then
            label = current
        else
            for num, val in pairs(assignments.profiles) do
                if type(val) == "table" then
                    label = num
                    break
                end
            end
        end
        label = label or current
        assignments.activeLayout = label
    end
    return label
end

-- specProfiles for the active PROFILE (the live CDM bucket): spell content is per-CUI-profile,
-- no account-wide layout pointer mediates rendering. Combat-hot and CACHED (re-deriving cost
-- ~20ms/min of combat CPU): invalidated by the spec-key cache lifecycle (ProcessSpecChange /
-- InvalidateSpecKey) plus BuildAllCDMBars' head as belt -- every profile apply, import, layout
-- switch and options rebuild passes through one of those.
function mod.GetActiveSpecProfiles()
    local specProfile = mod._cachedSpecProfiles
    if specProfile then
        return specProfile
    end
    specProfile = mod.GetSpecProfilesForProfile(mod.GetActiveProfileName())
    mod._cachedSpecProfiles = specProfile
    return specProfile
end

function SpellStore.GetSpecProfiles()
    return mod.GetActiveSpecProfiles()
end

-- (SpellStore.GetBarGlows removed -- Bar Glows disabled pending rewrite)

-------------------------------------------------------------------------------
--  Direct spell data accessor (single source of truth)
--  Returns the spell table for a bar key under the current spec, creating
--  it if needed. All spell reads/writes go through this -- no copies.
-------------------------------------------------------------------------------
-- Reference memo for combat-hot store fetches (this + the per-spell settings stores below).
-- LIVE validity: records the specProfiles ROOT table + specKey, re-checked every call, so
-- profile applies/imports/spec swaps (which change one of those two) can't be missed. Cached
-- values are TABLE REFERENCES (options edits stay visible); nil is never cached (self-heals
-- next call). Belt: BuildAllCDMBars' head drops the memo for structural ops (delete/reset) that replace an inner table.
function mod.GetBarSpellData(barId)
    local specSlot = mod.GetActiveSpecKey()
    if not specSlot or specSlot == "0" then
        return nil
    end
    local specProfile = SpellStore.GetSpecProfiles()
    local memoTbl = mod._cdmStoreMemo
    if memoTbl and memoTbl.root == specProfile and memoTbl.spec == specSlot then
        local hit = memoTbl.sd[barId]
        if hit then
            return hit
        end
    else
        memoTbl = { root = specProfile, spec = specSlot, sd = {} }
        mod._cdmStoreMemo = memoTbl
    end
    local profileTbl = specProfile[specSlot]
    if not profileTbl then
        profileTbl = { barSpells = {} }
        specProfile[specSlot] = profileTbl
    end
    if not profileTbl.barSpells then
        profileTbl.barSpells = {}
    end
    local barStore = profileTbl.barSpells[barId]
    if not barStore then
        barStore = {}
        profileTbl.barSpells[barId] = barStore
    end
    memoTbl.sd[barId] = barStore
    return barStore
end

-------------------------------------------------------------------------------
--  Tiered per-spell settings stores
--
--  Per-spell icon settings live in FAMILY stores on the spec profile (siblings of
--  barSpells), keyed by spellID -- NOT nested under a bar, so moving a spell within
--  its family keeps its settings:
--      specProf.spellSettingsCD[sid]   -- cooldown/utility family
--      specProf.spellSettingsBuff[sid] -- buff family
--  Bar-level tiers below the per-spell entries ("Apply to Bar"):
--      barSpells[barKey].barSettings   -- this bar, this spec
--      bd.barSpellSettings             -- this bar, EVERY spec (profile-level bar
--                                         def; specs with no CDM data yet inherit it)
--  Effective value per key: spell entry > barSettings > barSpellSettings > defaults,
--  via metatable __index links ResolveSpellSettings re-asserts lazily on every lookup
--  (self-heals across moves/spec swaps/profile swaps; metatables never serialize).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Hosted-buff markers
--
--  A buff placed on a CD/utility bar ("hosted") gets its own assignedSpells entry,
--  encoded as a negative marker so it never collides with the same spell's cooldown
--  entry (one spellID can be in BOTH the Essential/Utility and Tracked Buffs catalogs,
--  e.g. Divine Shield 642). The marker is an independent slot -- own position,
--  remove/move, per-icon settings -- even when the cooldown form is on the same bar.
--
--  Encoding: -(BASE + spellID). BASE sits far below the item-preset range (<= -100,
--  negated itemIDs) and the trinket slots (-13/-14), so existing negative-id branches
--  keep working; anything <= -BASE is a marker.
-------------------------------------------------------------------------------
mod.HOSTED_BUFF_MARKER_BASE = 2000000000

-------------------------------------------------------------------------------
--  Equipment-slot entries: a bar entry can store a negated INVENTORY SLOT id (-1..-19)
--  to track whatever item is equipped there; trinket slots (-13/-14) and user-added slots
--  (belt -6, cloak -15, ...) share the same frame/update machinery. Range is safe: item
--  presets are <= -100 and the custom-item popup rejects IDs below 100, so nothing else
--  occupies -1..-19. INV_SLOT_NAMES is keyed by slot id; slot 18 (obsolete ranged) is
--  deliberately absent -- SlotIDFromKey treats absence as "not a slot".
-------------------------------------------------------------------------------
mod.INV_SLOT_NAMES = {
    [1] = HEADSLOT,
    [2] = NECKSLOT,
    [3] = SHOULDERSLOT,
    [4] = SHIRTSLOT,
    [5] = CHESTSLOT,
    [6] = WAISTSLOT,
    [7] = LEGSSLOT,
    [8] = FEETSLOT,
    [9] = WRISTSLOT,
    [10] = HANDSSLOT,
    [11] = FINGER0SLOT,
    [12] = FINGER1SLOT,
    [13] = TRINKET0SLOT,
    [14] = TRINKET1SLOT,
    [15] = BACKSLOT,
    [16] = MAINHANDSLOT,
    [17] = SECONDARYHANDSLOT,
    [19] = TABARDSLOT,
}

-- Decode an equipment-slot entry to its inventory slot id; nil for anything else.
function mod.SlotIDFromKey(storeKey)
    if type(storeKey) == "number" and storeKey < 0 and mod.INV_SLOT_NAMES[-storeKey] then
        return -storeKey
    end
    return nil
end

function mod.HostedBuffMarker(spellId)
    return -(mod.HOSTED_BUFF_MARKER_BASE + spellId)
end

-- Decode a hosted-buff marker to its spellID; nil otherwise. Bounded by CD_CLAIM_MARKER_BASE so a cd-claim marker never misdecodes as a spellID.
function mod.HostedBuffMarkerToSpell(ident)
    if
        type(ident) == "number"
        and ident <= -mod.HOSTED_BUFF_MARKER_BASE
        and ident > -mod.CD_CLAIM_MARKER_BASE
    then
        return -ident - mod.HOSTED_BUFF_MARKER_BASE
    end
    return nil
end

-- True when the list already holds the hosted marker for spellID.
function mod.ListHasHostedMarker(entries, spellId)
    if not entries then
        return false
    end
    local marker = -(mod.HOSTED_BUFF_MARKER_BASE + spellId)
    for index = 1, #entries do
        if entries[index] == marker then
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Empty Slot markers: a purely decorative placeholder (no spell/item behind
--  it) that reserves a grid position on a CD/utility bar. Unlike every other
--  marker kind, there is no natural id to encode -- each Add mints a fresh one
--  so every instance is globally unique and AddTrackedSpell/RemoveTrackedSpell/
--  ReplaceTrackedSpell (dedup, cross-bar sweep, index-based remove/reorder) all
--  handle it with zero special-casing, same as any other tracked entry.
--
--  Encoding: -(EMPTY_SLOT_MARKER_BASE + seq). BASE sits above the item-preset
--  range (<= -100, real itemIDs never approach it) and below
--  HOSTED_BUFF_MARKER_BASE, so it can never collide with either.
--
--  seq is derived from the data itself (highest existing seq across every
--  spec's bars and saved slot settings, +1) rather than a saved counter: the
--  markers live in the per-spec spell store (SpellStore), but a counter lives in a
--  DIFFERENT table -- an import/sync can bring in markers the counter never
--  saw, so a freshly minted one could collide with an already-saved marker
--  (the Add then either no-ops as a "duplicate" or steals the slot from
--  whichever bar already held that id). Scanning is collision-proof by
--  construction and only runs on an explicit Add (cold path).
-------------------------------------------------------------------------------
mod.EMPTY_SLOT_MARKER_BASE = 1000000000

function mod.NewEmptySlotMarker()
    local maxSeq = 0
    local specProfile = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if specProfile then
        for _, profileTbl in pairs(specProfile) do
            -- Removed slots can leave saved conditions behind; never reuse their id.
            local prefs = profileTbl and profileTbl.spellSettingsCD
            if prefs then
                for ident in pairs(prefs) do
                    if mod.IsEmptySlotMarker(ident) then
                        local seq = -ident - mod.EMPTY_SLOT_MARKER_BASE
                        if seq > maxSeq then
                            maxSeq = seq
                        end
                    end
                end
            end
            local barSpellMap = profileTbl and profileTbl.barSpells
            if barSpellMap then
                for _, barStore in pairs(barSpellMap) do
                    local assignedList = barStore and barStore.assignedSpells
                    if assignedList then
                        for _, ident in ipairs(assignedList) do
                            if mod.IsEmptySlotMarker(ident) then
                                local seq = -ident - mod.EMPTY_SLOT_MARKER_BASE
                                if seq > maxSeq then
                                    maxSeq = seq
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return -(mod.EMPTY_SLOT_MARKER_BASE + maxSeq + 1)
end

-- True for any Empty Slot marker; bounded above HOSTED_BUFF_MARKER_BASE so it never misreads a hosted-buff marker.
function mod.IsEmptySlotMarker(ident)
    return type(ident) == "number"
        and ident <= -mod.EMPTY_SLOT_MARKER_BASE
        and ident > -mod.HOSTED_BUFF_MARKER_BASE
end

-- True for an item entry key (-itemID): an item preset or a Custom Item ID, the band
-- below the equipment slot ids (-1..-19) and above every marker base.
function mod.IsItemPresetKey(ident)
    return type(ident) == "number" and ident <= -100 and ident > -mod.EMPTY_SLOT_MARKER_BASE
end

-------------------------------------------------------------------------------
--  Cd-claim markers: a collided buff (two Blizzard buff-viewer slots sharing one canonical
--  spellID, e.g. Diabolist Demonic Art vs Diabolic Ritual) can't be told apart by spellID, so
--  a claimed slot is tracked by its cooldownID instead, using the same marker-in-assignedSpells
--  pattern as hosted-buff markers (add/remove/drag/reorder reuse the existing machinery).
--
--  Encoding: -(BASE + cooldownID). BASE sits beyond HOSTED_BUFF_MARKER_BASE (+ max plausible
--  spellID), so every hosted-buff-marker check (bounded at HOSTED_BUFF_MARKER_BASE) already excludes cd-claim markers.
-------------------------------------------------------------------------------
mod.CD_CLAIM_MARKER_BASE = 3000000000

function mod.CdClaimMarker(cdID)
    return -(mod.CD_CLAIM_MARKER_BASE + cdID)
end

-- Decode a cd-claim marker to its cooldownID; nil for anything else.
function mod.CdClaimMarkerToCdID(ident)
    if type(ident) == "number" and ident <= -mod.CD_CLAIM_MARKER_BASE then
        return -ident - mod.CD_CLAIM_MARKER_BASE
    end
    return nil
end

-- Every cd-claim marker in a bar's assignedSpells as a set ({[cdID]=true,...}), or nil if none.
function mod.CollectCdClaimSet(spellData)
    if not spellData or not spellData.assignedSpells then
        return nil
    end
    local keySet
    for _, ident in ipairs(spellData.assignedSpells) do
        local cd = mod.CdClaimMarkerToCdID(ident)
        if cd then
            keySet = keySet or {}
            keySet[cd] = true
        end
    end
    return keySet
end

-- Family store key for a bar ("spellSettingsBuff" for buff-family bars, "spellSettingsCD" for everything else, including the ghost CD bar).
function mod.SettingsFamilyKey(barKeyOrBd)
    if mod.IsBarBuffFamily and mod.IsBarBuffFamily(barKeyOrBd) then
        return "spellSettingsBuff"
    end
    return "spellSettingsCD"
end

-- Family per-spell store for an explicit spec profile table.
function mod.GetSpellSettingsStoreForProf(profileTbl, famKey, create)
    if not profileTbl then
        return nil
    end
    local state = profileTbl[famKey]
    if not state and create then
        state = {}
        profileTbl[famKey] = state
    end
    return state
end

-- Family per-spell store for the ACTIVE spec, resolved from a bar. Same live-validity
-- reference memo as GetBarSpellData: keyed by family under the shared memo, nil never
-- cached, and create=true refreshes the entry so a first-write store is immediately visible to readers.
function mod.GetSpellSettingsStore(barKeyOrBd, create)
    local specSlot = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not specSlot or specSlot == "0" then
        return nil
    end
    local specProfile = SpellStore.GetSpecProfiles()
    if not specProfile then
        return nil
    end
    local famKey = mod.SettingsFamilyKey(barKeyOrBd)
    local memoTbl = mod._cdmStoreMemo
    if memoTbl and memoTbl.root == specProfile and memoTbl.spec == specSlot then
        if not create then
            local hit = memoTbl[famKey]
            if hit then
                return hit
            end
        end
    else
        memoTbl = { root = specProfile, spec = specSlot, sd = {} }
        mod._cdmStoreMemo = memoTbl
    end
    local profileTbl = specProfile[specSlot]
    if not profileTbl then
        if not create then
            return nil
        end
        profileTbl = { barSpells = {} }
        specProfile[specSlot] = profileTbl
    end
    local state = mod.GetSpellSettingsStoreForProf(profileTbl, famKey, create)
    if state then
        memoTbl[famKey] = state
    end
    return state
end

-- Chain child.__index -> parent (or clear the link when parent is nil), so every read of a
-- per-spell table falls through to the bar tiers per KEY. Cheap: one getmetatable + compare.
function mod.ChainSettings(childFrame, hostFrame)
    if not childFrame then
        return
    end
    local meta = getmetatable(childFrame)
    if hostFrame then
        if not meta then
            setmetatable(childFrame, { __index = hostFrame })
        elseif meta.__index ~= hostFrame then
            meta.__index = hostFrame
        end
    elseif meta and meta.__index ~= nil then
        meta.__index = nil
    end
end

-- Bar-tier chain head for a bar: barSettings (chained to the profile-level bd.barSpellSettings) when present, else bd.barSpellSettings, else nil.
function mod.GetBarTierSettings(spellData, barId)
    local edge = barId and mod.barDataByKey and mod.barDataByKey[barId]
    local abs = edge and edge.barSpellSettings
    local barStore = spellData and spellData.barSettings
    if barStore then
        mod.ChainSettings(barStore, abs)
        return barStore
    end
    return abs
end

-- True when any per-icon settings could apply on this bar: family store has ANY entry
-- (over-approximate -- keyed by spell, not bar) or either bar tier is non-empty. Gates "re-resolve appearance" passes.
function mod.BarHasAnySpellSettings(barId, spellData)
    local state = mod.GetSpellSettingsStore(barId)
    if state and next(state) ~= nil then
        return true
    end
    spellData = spellData or mod.GetBarSpellData(barId)
    if spellData then
        if spellData.barSettings and next(spellData.barSettings) ~= nil then
            return true
        end
        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
        if spellData.spellSettings and next(spellData.spellSettings) ~= nil then
            return true
        end
    end
    local edge = mod.barDataByKey and mod.barDataByKey[barId]
    if edge and edge.barSpellSettings and next(edge.barSpellSettings) ~= nil then
        return true
    end
    return false
end

-- Iterate every SAVED settings block that can hold per-spell setting keys: all specs'
-- family-store entries + per-bar barSettings, plus the active profile's bar-level
-- barSpellSettings. fn(ss) returning true stops the walk. Used by login gate scans ("does anyone use feature X anywhere").
function mod.ForEachSavedSettingsBlock(func)
    if not CludesUIDB then
        return false
    end
    local specProfile = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if specProfile then
        for _, profileTbl in pairs(specProfile) do
            if type(profileTbl) == "table" then
                local cooldownState = profileTbl.spellSettingsCD
                if type(cooldownState) == "table" then
                    for _, spellSettings in pairs(cooldownState) do
                        if type(spellSettings) == "table" and func(spellSettings) then
                            return true
                        end
                    end
                end
                local stBuff = profileTbl.spellSettingsBuff
                if type(stBuff) == "table" then
                    for _, spellSettings in pairs(stBuff) do
                        if type(spellSettings) == "table" and func(spellSettings) then
                            return true
                        end
                    end
                end
                local barSpellMap = profileTbl.barSpells
                if type(barSpellMap) == "table" then
                    for _, barStore in pairs(barSpellMap) do
                        local bset = type(barStore) == "table" and barStore.barSettings
                        if type(bset) == "table" and func(bset) then
                            return true
                        end
                        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
                        local ssAll = type(barStore) == "table" and barStore.spellSettings
                        if type(ssAll) == "table" then
                            for _, spellSettings in pairs(ssAll) do
                                if type(spellSettings) == "table" and func(spellSettings) then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local profile = ECME and ECME.db and ECME.db.profile
    local barList = profile and profile.cdmBars and profile.cdmBars.bars
    if type(barList) == "table" then
        for _, edge in ipairs(barList) do
            local abs = type(edge) == "table" and edge.barSpellSettings
            if type(abs) == "table" and func(abs) then
                return true
            end
        end
    end
    return false
end

-- One-time copy of a user CUSTOM spell/buff (customSpellIDs-tagged) plus its per-spell settings
-- onto the SAME bar in other specs of the active profile (bar defs are profile-level, so the bar
-- exists in every spec). A target spec that already has the spell on ANY bar is skipped whole
-- (never duplicates within a spec). Custom Active State is NOT copied: it lives in the
-- profile-level customActiveStates store, already shared across specs. Returns the count copied to.
function mod.CopyCustomSpellToSpecs(barId, spellId, specKeys)
    if not barId or type(spellId) ~= "number" or spellId == 0 then
        return 0
    end
    if type(specKeys) ~= "table" then
        return 0
    end
    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfile then
        return 0
    end
    local curKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local famKey = mod.SettingsFamilyKey(barId)
    local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy

    -- Source metadata from the ACTIVE spec (the bar the menu was opened on).
    local srcSd = mod.GetBarSpellData(barId)
    local dur = srcSd and srcSd.spellDurations and srcSd.spellDurations[spellId]
    local srcStore = mod.GetSpellSettingsStore(barId)
    local srcSettings = srcStore and srcStore[spellId]

    local copiedTbl = 0
    for storeKey, enabled in pairs(specKeys) do
        if enabled and storeKey ~= curKey and storeKey ~= "0" then
            local profileTbl = specProfile[storeKey]
            if not profileTbl then
                profileTbl = { barSpells = {} }
                specProfile[storeKey] = profileTbl
            end
            if not profileTbl.barSpells then
                profileTbl.barSpells = {}
            end
            -- Present anywhere in this spec? Skip the whole spec.
            local exists = false
            for _, barStore in pairs(profileTbl.barSpells) do
                if type(barStore) == "table" and type(barStore.assignedSpells) == "table" then
                    for _, ident in ipairs(barStore.assignedSpells) do
                        if ident == spellId then
                            exists = true
                            break
                        end
                    end
                end
                if exists then
                    break
                end
            end
            if not exists then
                local barStore = profileTbl.barSpells[barId]
                if not barStore then
                    barStore = {}
                    profileTbl.barSpells[barId] = barStore
                end
                if not barStore.assignedSpells then
                    barStore.assignedSpells = {}
                end
                barStore.assignedSpells[#barStore.assignedSpells + 1] = spellId
                if not barStore.customSpellIDs then
                    barStore.customSpellIDs = {}
                end
                barStore.customSpellIDs[spellId] = true
                if dur and dur > 0 then
                    if not barStore.spellDurations then
                        barStore.spellDurations = {}
                    end
                    barStore.spellDurations[spellId] = dur
                end
                if type(srcSettings) == "table" and DeepCopy then
                    -- pairs()-based DeepCopy takes OWN keys only (no __index follow): own
                    -- settings, not bar-tier inherits. Copy is unchained; renderer re-chains on first resolve.
                    local storage = profileTbl[famKey]
                    if not storage then
                        storage = {}
                        profileTbl[famKey] = storage
                    end
                    if storage[spellId] == nil then
                        storage[spellId] = DeepCopy(srcSettings)
                        -- New entry (belt: one integer bump on a user click).
                        mod._cdmResGen = mod._cdmResGen + 1
                    end
                end
                copiedTbl = copiedTbl + 1
            end
        end
    end
    return copiedTbl
end

-- Set of OTHER specs (this class, active profile) with the spell on ANY bar. Drives the
-- per-spell menu's Copy/Remove label + the Remove picker's pre-check. Excludes the active spec.
function mod.SpecsWithCustomSpell(spellId)
    local result = {}
    if type(spellId) ~= "number" or spellId == 0 then
        return result
    end
    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfile then
        return result
    end
    local curKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    for storeKey, profileTbl in pairs(specProfile) do
        -- WoW Forever: the player's class is one spec there, so its other
        -- stored keys are not other specs (no picker row reaches them).
        if
            storeKey ~= curKey
            and storeKey ~= "0"
            and type(profileTbl) == "table"
            and type(profileTbl.barSpells) == "table"
            and not (
                CludesUI.IS_FOREVER
                and mod._playerClass
                and CludesUI.SpecClassOf(tonumber(storeKey)) == mod._playerClass
            )
        then
            local found = false
            for _, barStore in pairs(profileTbl.barSpells) do
                if type(barStore) == "table" and type(barStore.assignedSpells) == "table" then
                    for _, ident in ipairs(barStore.assignedSpells) do
                        if ident == spellId then
                            found = true
                            break
                        end
                    end
                end
                if found then
                    break
                end
            end
            if found then
                result[storeKey] = true
            end
        end
    end
    return result
end

-- Inverse of CopyCustomSpellToSpecs: remove the spell + its per-spell settings from the picked
-- specs (scans every bar). Never touches the active spec or the profile-level customActiveState
-- (that stays while the spell exists on ANY spec, incl. the current one). Returns the count removed.
function mod.RemoveCustomSpellFromSpecs(spellId, specKeys)
    if type(spellId) ~= "number" or spellId == 0 then
        return 0
    end
    if type(specKeys) ~= "table" then
        return 0
    end
    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfile then
        return 0
    end
    local curKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local removedList = 0
    for storeKey, enabled in pairs(specKeys) do
        if enabled and storeKey ~= curKey and storeKey ~= "0" then
            local profileTbl = specProfile[storeKey]
            if type(profileTbl) == "table" and type(profileTbl.barSpells) == "table" then
                local didRemove = false
                for _, barStore in pairs(profileTbl.barSpells) do
                    if type(barStore) == "table" and type(barStore.assignedSpells) == "table" then
                        local hitHere = false
                        for index = #barStore.assignedSpells, 1, -1 do
                            if barStore.assignedSpells[index] == spellId then
                                table.remove(barStore.assignedSpells, index)
                                hitHere = true
                                didRemove = true
                            end
                        end
                        -- Clean the per-id metadata on the bar it lived on.
                        if hitHere then
                            if barStore.customSpellIDs then
                                barStore.customSpellIDs[spellId] = nil
                            end
                            if barStore.spellDurations then
                                barStore.spellDurations[spellId] = nil
                            end
                            if barStore.customSpellDurations then
                                barStore.customSpellDurations[spellId] = nil
                            end
                            if barStore.customSpellGroups then
                                for variantID, primaryID in pairs(barStore.customSpellGroups) do
                                    if primaryID == spellId or variantID == spellId then
                                        barStore.customSpellGroups[variantID] = nil
                                    end
                                end
                            end
                        end
                    end
                end
                if didRemove then
                    -- Drop the per-spell settings entry (keyed by spellID, so clearing both family stores is safe -- only one holds it).
                    if profileTbl.spellSettingsCD then
                        profileTbl.spellSettingsCD[spellId] = nil
                    end
                    if profileTbl.spellSettingsBuff then
                        profileTbl.spellSettingsBuff[spellId] = nil
                    end
                    -- Entry deletion (belt: non-active specs by contract).
                    mod._cdmResGen = mod._cdmResGen + 1
                    removedList = removedList + 1
                end
            end
        end
    end
    return removedList
end

-- Custom Active State store, keyed by spellID at the PROFILE level (shared across every
-- bar and spec) so state travels with the spell wherever placed. Key matches assignedSpells:
-- positive = racial/custom spell, negative = item/trinket-slot preset. Entry shape: { duration,
-- activeSwipeMode, activeSwipeClassColor, activeSwipeR/G/B/A, activeGlow, glowColor, glowColorR/G/B }.
function mod.GetCustomActiveStates()
    local profile = ECME and ECME.db and ECME.db.profile
    if not profile then
        return nil
    end
    if not profile.customActiveStates then
        profile.customActiveStates = {}
    end
    return profile.customActiveStates
end

-- Read (or, with create=true, lazily create) the entry for one spell key.
function mod.GetCustomActiveState(spellId, create)
    local storage = mod.GetCustomActiveStates()
    if not storage then
        return nil
    end
    local e = storage[spellId]
    if not e and create then
        e = {}
        storage[spellId] = e
    end
    return e
end

-- Map an icon's identity token to its SETTINGS key. Equipment SLOTS key their per-spell
-- settings by the EQUIPPED item (-itemID) so each item tracks separately; bar allocation
-- stays slot-based. Everything else (item presets, racials, custom spells) keys by its own token.
function mod.ResolveCustomActiveKey(frameKey)
    local slot = mod.SlotIDFromKey(frameKey)
    if slot then
        local itemId = GetInventoryItemID("player", slot)
        if itemId then
            return -itemId
        end
    end
    return frameKey
end

-- EFFECTIVE Custom Active State for an icon token -- READ paths only. Non-slot tokens
-- resolve their own entry. Equipment SLOTS resolve the EQUIPPED item's entry (per-item,
-- written via ResolveCustomActiveKey), chained per-key over the SLOT entry -- the "Apply to
-- Bar" stamp -- so one bar application covers whatever is equipped without an entry per item.
-- Chain re-asserted lazily every resolve (metatables never serialize), mirroring
-- ResolveSpellSettings. An explicit false own value renders like nil but BLOCKS the slot
-- value from showing through (per-item "None"); the cooldown state pair readers
-- (ns.CdStateOf) read false as no effect.
function mod.GetEffectiveCustomActiveState(frameKey)
    local storage = mod.GetCustomActiveStates()
    if not storage then
        return nil
    end
    local slot = mod.SlotIDFromKey(frameKey)
    if slot then
        local slotE = storage[frameKey]
        local itemId = GetInventoryItemID("player", slot)
        local itemE = itemId and storage[-itemId] or nil
        if itemE then
            mod.ChainSettings(itemE, slotE)
            return itemE
        end
        return slotE
    end
    return storage[frameKey]
end

-- The hide effects by saved value: the base mode the evaluators run, plus
-- shift (the bar closes the gap: Shift Icons), usable (an unusable spell also
-- hides: Hidden Until Usable) and form (only the spell's form or stance
-- decides, whatever its cooldown: Hidden Outside Form/Stance). A new hide
-- effect is one entry here: the glows it cannot show beside derive from its
-- base and flags (ns.CdStateGlowConflicts).
mod.CD_STATE_HIDE = {
    hiddenOnCD = { base = "hiddenOnCD" },
    hiddenReady = { base = "hiddenReady" },
    hiddenUnusable = { base = "hiddenOnCD", usable = true },
    hiddenForm = { base = "hiddenOnCD", form = true },
    hiddenOnCDShift = { base = "hiddenOnCD", shift = true },
    hiddenReadyShift = { base = "hiddenReady", shift = true },
    hiddenUnusableShift = { base = "hiddenOnCD", shift = true, usable = true },
    hiddenFormShift = { base = "hiddenOnCD", shift = true, form = true },
}

-- True for a Shift Icons effect
function mod.CdStateShifts(eff)
    local m = eff and mod.CD_STATE_HIDE[eff]
    return m and m.shift or false
end

-------------------------------------------------------------------------------
--  Cooldown State Effect pair
--  A spell's effect is two settings read together: the hide (cdStateEffect: a
--  CD_STATE_HIDE key or "lowerAlphaOnCD") and the glow (cdStateGlow: a
--  CD_STATE_GLOWS key; the menus write only the menu values, a moved single
--  value keeps its saved name); false in either is explicitly none. Both
--  chain per key like every per-spell setting (the spell entry over the bar
--  tiers, an equipped item over its trinket slot). A glow saved in
--  cdStateEffect, the single-value form, reads as that glow with no hide, and
--  like a hide it shadows the single-value glows below it, never a cdStateGlow
--  below it. Every evaluator reads the pair through ns.CdStateOf; the menus
--  write it through ns.CdStateWriteHide / ns.CdStateWriteGlow, which move a
--  single-value glow into cdStateGlow on the table they write.
-------------------------------------------------------------------------------

-- Every saved glow value -> its menu value (a button* name is the same glow
-- with the Action Button Glow look, which ns.CdReadyGlowStyle implies).
mod.CD_STATE_GLOWS = {
    pixelGlowReady = "pixelGlowReady",
    buttonGlowReady = "pixelGlowReady",
    pixelGlowReadyUsable = "pixelGlowReadyUsable",
    buttonGlowReadyUsable = "pixelGlowReadyUsable",
    glowOnCD = "glowOnCD",
}

-- hide, glow for a settings table (nil for none). The glow comes back as saved,
-- so a single-value button* name keeps implying its style. Frames we inject
-- read nothing here: the preset menus store their effect in
-- customActiveStates, None included, so an old spell-family or bar-tier effect
-- never shows behind that menu's back.
function mod.CdStateOf(prefs, widget)
    if not prefs then
        return nil, nil
    end
    if widget and mod.CdmIsInjectedFrame and mod.CdmIsInjectedFrame(widget) then
        return nil, nil
    end
    local GLOWS = mod.CD_STATE_GLOWS
    local e = prefs.cdStateEffect
    local hide = e
    if e == false or GLOWS[e] then
        hide = nil
    end
    -- No level holds a cdStateGlow: the single value decides.
    if prefs.cdStateGlow == nil then
        if GLOWS[e] then
            return hide, e
        end
        return hide, nil
    end
    -- Top down: a level's own cdStateGlow decides (false = none), else its
    -- single-value glow while no hide or false above shadows those.
    local t, shadowed = prefs, false
    for _ = 1, 4 do
        if type(t) ~= "table" then
            break
        end
        local g = rawget(t, "cdStateGlow")
        if g ~= nil then
            return hide, g or nil
        end
        if not shadowed then
            local le = rawget(t, "cdStateEffect")
            if le ~= nil then
                if GLOWS[le] then
                    return hide, le
                end
                shadowed = true
            end
        end
        local meta = getmetatable(t)
        t = meta and meta.__index
    end
    return hide, nil
end

-- The hide half alone (the same gate, no glow walk).
function mod.CdStateHideOf(prefs, widget)
    if not prefs then
        return nil
    end
    if widget and mod.CdmIsInjectedFrame and mod.CdmIsInjectedFrame(widget) then
        return nil
    end
    local e = prefs.cdStateEffect
    if e == false or mod.CD_STATE_GLOWS[e] then
        return nil
    end
    return e
end

-- The glow half alone.
function mod.CdStateGlowOf(prefs, widget)
    local _, g = mod.CdStateOf(prefs, widget)
    return g
end

-- True when the glow can never show beside the hide: the On CD glow under a
-- hide that covers the whole cooldown (Hidden (On CD), Hidden Until Usable and
-- their Shift variants), the ready glows under Hidden (CD Ready). A form hide
-- never conflicts: only the form decides it, whatever the cooldown.
function mod.CdStateGlowConflicts(hide, glow)
    local m = hide and mod.CD_STATE_HIDE[hide]
    local g = glow and mod.CD_STATE_GLOWS[glow]
    if not (m and g) or m.form then
        return false
    end
    if g == "glowOnCD" then
        return m.base == "hiddenOnCD"
    end
    return m.base == "hiddenReady"
end

-- A valid Glow Style read through t's chain.
local function ReadsGlowStyle(t)
    local state = t.cdStateGlowStyle
    return type(state) == "number" and state >= 1 and state <= #mod.GLOW_STYLES
end

-- Move a single-value glow saved in t's own cdStateEffect into cdStateGlow,
-- leaving the pair t resolves unchanged. The saved name moves as it is: a
-- button* name keeps implying its Action Button Glow look through
-- ns.CdReadyGlowStyle, and no Glow Style is written that the tables chained
-- over t would inherit. cdStateEffect stays false where a hide below would
-- otherwise show through. True when t held one.
function mod.CdStateSplitLegacy(t)
    if type(t) ~= "table" then
        return false
    end
    local e = rawget(t, "cdStateEffect")
    if not (e and mod.CD_STATE_GLOWS[e]) then
        return false
    end
    if rawget(t, "cdStateGlow") == nil then
        t.cdStateGlow = e
    end
    t.cdStateEffect = nil
    if mod.CdStateHideOf(t) ~= nil then
        t.cdStateEffect = false
    end
    return true
end

-- A menu's hide pick on its own table t (v = a hide value, nil = None). The
-- glow t resolves is kept: when the new hide shadows or exposes another glow,
-- t pins the one it had, as saved (false for none).
function mod.CdStateWriteHide(t, val)
    local before = mod.CdStateGlowOf(t)
    mod.CdStateSplitLegacy(t)
    t.cdStateEffect = val
    if val == nil and mod.CdStateHideOf(t) ~= nil then
        t.cdStateEffect = false
    end
    if mod.CdStateGlowOf(t) ~= before then
        t.cdStateGlow = before or false
    end
end

-- A menu's glow pick on its own table t (g = a menu glow, nil = no glow). The
-- hide t resolves is kept. A button* glow being replaced leaves its Action
-- Button Glow look as the style when none is set.
function mod.CdStateWriteGlow(t, g)
    local current = mod.CdStateGlowOf(t)
    local cc = current and mod.CD_STATE_GLOWS[current]
    if g and cc and cc ~= current and not ReadsGlowStyle(t) then
        t.cdStateGlowStyle = 3
    end
    mod.CdStateSplitLegacy(t)
    t.cdStateGlow = g
    if g == nil and mod.CdStateGlowOf(t) ~= nil then
        t.cdStateGlow = false
    end
end

-- CD Ready glow style (CDM saved numbering), read from the same settings table as
-- the glow (cse = the glow as ns.CdStateOf returns it): the explicit pick, else
-- what the glow name implies (pixel* = Pixel Glow, button* = Action Button Glow,
-- glowOnCD = Blackout), so older settings render unchanged.
function mod.CdReadyGlowStyle(cse, prefs)
    local state = prefs and prefs.cdStateGlowStyle
    if type(state) == "number" and state >= 1 and state <= #mod.GLOW_STYLES then
        return state
    end
    if cse == "pixelGlowReady" or cse == "pixelGlowReadyUsable" then
        return 1
    end
    if cse == "glowOnCD" then
        return 8
    end -- Blackout: the default look for this effect
    return 3
end

-- CD Ready glow color: the icon's pick, else white for the drawn styles (their
-- long-standing look) and nil for FlipBooks (the atlas's own untinted look).
function mod.CdReadyGlowColor(style, prefs)
    local red, green, blue = mod.ResolveGlowColor(prefs)
    if red then
        return red, green, blue
    end
    local e = mod.GLOW_STYLES[style]
    if e and not (e.procedural or e.buttonGlow or e.autocast or e.shapeGlow) then
        return nil
    end
    return 1, 1, 1
end

-- CD Ready / On CD glow opacity (Blackout only; other styles ignore it).
-- nil = fully opaque, matches StartSolidFill's own default.
function mod.CdReadyGlowAlpha(prefs)
    return prefs and prefs.cdStateGlowAlpha
end

-- Does this icon have a custom Cooldown State Effect (preset cd-state)? Appearance refresh
-- uses this so it doesn't clear a preset's _cdStateHidden flag: presets store cdState in customActiveStates, not per-bar spellSettings.
function mod.PresetHasCdState(widget)
    local fc = mod._ecmeFC and mod._ecmeFC[widget]
    if not fc or not fc.spellID then
        return false
    end
    -- Only frames WE inject can own a custom active state -- same gate the
    -- Fake-Active engine applies before honoring one. Without it an orphaned
    -- profile-level entry both hid a plain tracked spell and stopped the
    -- appearance refresh from ever clearing the flag it set.
    -- Racials are the one exception: the Presets cog is their ONLY cd-state
    -- config surface (no separate per-spell settings menu, unlike custom
    -- spells), so a racial natively tracked by Blizzard's CDM must still honor it.
    if
        mod.CdmIsInjectedFrame
        and not mod.CdmIsInjectedFrame(widget)
        and not (mod._myRacialsSet and mod._myRacialsSet[fc.spellID])
    then
        return false
    end
    -- A hide, a glow (blocking-false = none in either) or a Stance Bar hide: the
    -- Fake-Active engine owns this icon's hidden state, so the other paths leave it.
    local customState = mod.GetEffectiveCustomActiveState(fc.spellID)
    local hide, glow = mod.CdStateOf(customState)
    return hide ~= nil or glow ~= nil or mod.CdmStanceBarOf(customState) ~= nil
end

-- Max Stacks Glow gate: set ns._cdmAnyMaxStacksGlow once if any saved spell (any spec) has
-- the glow enabled, so RefreshCDMIconAppearance skips its per-icon watch check entirely for
-- non-users -- 0 cost when off. Monotonic + scanned-once: runtime enables come from the option's setValue, so this only discovers already-saved settings at/after login.
function mod.RescanMaxStacksGlowFlag()
    if mod._cdmAnyMaxStacksGlow or mod._maxStacksFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._maxStacksFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.maxStacksGlow and spellSettings.maxStacksGlow > 0 then
            mod._cdmAnyMaxStacksGlow = true
            return true
        end
    end)
end

-- Audio on Buff Gain/Loss gate: set ns._cdmAnyBuffSound once if any saved buff icon or
-- tracking bar (any spec) has a gain OR loss sound chosen, so DecorateFrame/RefreshCDMIconAppearance
-- skip attaching the apply-edge sound hook for non-users. The icon half keeps the scanned-once +
-- runtime-enable contract of RescanMaxStacksGlowFlag. ns._tbbAnyBuffSound is the tracking-bar
-- half on its own, so icon-only users skip the tracking-bar lookup on every buff alert. Its scan
-- is O(specs x bars) with no allocation, so it repeats on every rebuild until it finds a sound,
-- which also picks up bar sounds a live profile switch brings in.
function mod.RescanBuffSoundFlag()
    if not CludesUIDB then
        return
    end
    if not mod._buffSoundFlagScanned then
        mod._buffSoundFlagScanned = true
        if not mod._cdmAnyBuffSound then
            mod.ForEachSavedSettingsBlock(function(spellSettings)
                if
                    (spellSettings.buffActiveSoundKey and spellSettings.buffActiveSoundKey ~= "none")
                    or (spellSettings.buffLostSoundKey and spellSettings.buffLostSoundKey ~= "none")
                then
                    mod._cdmAnyBuffSound = true
                    return true
                end
            end)
        end
    end
    -- Tracking Bars keep the same two keys on their bar configs, which the
    -- settings-block walk above never visits. EnsureTBBSoundHooks flips both
    -- gates and hooks the frames already out of the buff viewer pools.
    if not mod._tbbAnyBuffSound and mod.TBBAnyBuffSound and mod.TBBAnyBuffSound() then
        mod.EnsureTBBSoundHooks()
    end
end

-- Resolve the configured buff gain/loss sound key for a spell id in the CURRENT
-- spec by SEARCHING saved bar spellSettings -- independent of per-frame
-- decoration state (_ecmeFC): the first buff gain after login fires its aura
-- alert BEFORE DecorateFrame populates that state, so this must resolve purely
-- from the id. O(bars): spellSettings is keyed by id.
function mod.FindBuffSoundKey(spellRef, field)
    if not spellRef then
        return nil
    end
    local specSlot = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not specSlot or specSlot == "0" then
        return nil
    end
    local specProfile = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    local profileTbl = specProfile and specProfile[specSlot]
    if not profileTbl then
        return nil
    end
    -- Per-spell tier: buff family store (explicit false = inherited bar-level
    -- sound turned OFF for this one buff -- treat as silent).
    local state = profileTbl.spellSettingsBuff
    local own = state and state[spellRef]
    if own then
        local val = rawget(own, field)
        if val ~= nil then
            if val and val ~= "none" then
                return val
            end
            return nil
        end
    end
    -- Bar tier: the buff bar this spell renders on. Extra buff bars claim
    -- their spells via assignedSpells; everything else lives on "buffs".
    local homeKey = "buffs"
    local barSpellMap = profileTbl.barSpells
    if barSpellMap then
        for barId, barStore in pairs(barSpellMap) do
            if
                barId ~= "buffs"
                and mod.IsBarBuffFamily
                and mod.IsBarBuffFamily(barId)
                and type(barStore.assignedSpells) == "table"
            then
                for _, asid in ipairs(barStore.assignedSpells) do
                    if asid == spellRef then
                        homeKey = barId
                        break
                    end
                end
            end
        end
    end
    local bsHome = barSpellMap and barSpellMap[homeKey]
    local tier = mod.GetBarTierSettings(bsHome, homeKey)
    local storeKey = tier and tier[field]
    if storeKey and storeKey ~= "none" then
        return storeKey
    end
    return nil
end

-- Audio Effect on CD Ready gate: set ns._cdmAnyCdReadySound once if any saved
-- cd/utility icon (any spec) has a CD-ready sound chosen, so the per-frame
-- SetDesaturated edge hook no-ops entirely for non-users. Same monotonic,
-- scanned-once contract as RescanBuffSoundFlag.
function mod.RescanCdReadySoundFlag()
    if mod._cdmAnyCdReadySound or mod._cdReadySoundFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._cdReadySoundFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.cdReadySoundKey and spellSettings.cdReadySoundKey ~= "none" then
            mod._cdmAnyCdReadySound = true
            return true
        end
    end)
end

-- "Replace with Buff" gate: set ns._cdmAnyBuffReplace once if any saved cd/utility
-- icon (any spec) names a replacement buff, so the route map's Pass 3c and the
-- collect pass's identity swap and compaction stay skipped for non-users. Same
-- scanned-once contract as RescanCdReadySoundFlag.
function mod.RescanBuffReplaceFlag()
    if mod._cdmAnyBuffReplace or mod._buffReplaceFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._buffReplaceFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if type(spellSettings.replaceBuffID) == "number" and spellSettings.replaceBuffID > 0 then
            mod._cdmAnyBuffReplace = true
            return true
        end
    end)
end

-- "Hide CD Text (Charges)" gate: set ns._cdmAnyChargeHideCdText once if any saved spell
-- (any spec) has the toggle on; RefreshCDMIconAppearance then skips its per-icon watch
-- check for non-users. Same contract as RescanMaxStacksGlowFlag.
function mod.RescanChargeCdTextFlag()
    if mod._cdmAnyChargeHideCdText or mod._chargeCdTextFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._chargeCdTextFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.chargeHideCdText then
            mod._cdmAnyChargeHideCdText = true
            return true
        end
    end)
end

-- Per-spell Duration Text gate: set ns._cdmAnySpellDurationText once if any saved spell
-- (any spec) overrides showCooldownText either way. ~= nil, not truthiness: a per-spell
-- ON must beat a bar that is OFF, same as the options resolver reads it.
function mod.RescanSpellDurationTextFlag()
    if mod._cdmAnySpellDurationText or mod._spellDurationTextFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._spellDurationTextFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.showCooldownText ~= nil then
            mod._cdmAnySpellDurationText = true
            return true
        end
    end)
end

-- "Hide Charge Text" gate: set ns._cdmAnyHideChargeText once if any saved spell
-- (any spec) has the toggle on. The appearance pass consults it to reach
-- WatchZeroChargeTextIfEnabled for users of neither the bar-level zero-charge
-- feature nor an active watch -- without it the per-spell hide never runs.
-- Same monotonic, scanned-once contract as RescanChargeCdTextFlag.
function mod.RescanHideChargeTextFlag()
    if mod._cdmAnyHideChargeText or mod._hideChargeTextFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._hideChargeTextFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.hideChargeText then
            mod._cdmAnyHideChargeText = true
            return true
        end
    end)
end

-- Per-spell Suppress GCD gate: the entry-B re-arm and the preset-frame GCD
-- swipe pass resolve per-spell settings only behind this flag. Same
-- monotonic, scanned-once contract as RescanChargeCdTextFlag.
function mod.RescanSuppressGcdFlag()
    if mod._cdmAnySuppressGcd or mod._suppressGcdFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._suppressGcdFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.suppressGCD then
            mod._cdmAnySuppressGcd = true
            return true
        end
    end)
end

-- Charge style gate: set ns._cdmAnyChargeStyle once if any saved spell (any spec)
-- has Hide Swipe (Charges) or Hide Recharge Edge enabled. Same monotonic,
-- scanned-once contract as RescanChargeCdTextFlag.
--
-- This flag is the one charge gate that had no priming pass: it was set only from
-- inside the SetSwipeColor hook, i.e. not until the first cooldown re-push after
-- login, which is already after the rebuild has run RefreshCDMIconAppearance. So
-- the rebuild's ReapplyChargeStyle was skipped, and ApplyCdmChargeStyle itself
-- gates its whole Hide Swipe / Hide Recharge Edge block on the flag -- meaning a
-- charge spell already recharging at login kept its swipe until something pushed
-- its cooldown again. Priming here closes that window; the reactive hooks then
-- carry it as before.
function mod.RescanChargeStyleFlag()
    if mod._cdmAnyChargeStyle or mod._chargeStyleFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._chargeStyleFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.chargeHideSwipe or spellSettings.hideRechargeEdge then
            mod._cdmAnyChargeStyle = true
            return true
        end
    end)
end

-- Custom Item gate: set ns._cdmAnyCustomItem once if any saved bar (any spec) tracks a custom
-- item (assignedSpells entry <= -100); the buff-bar injection pass is skipped entirely for non-users. Same contract as the flags above.
function mod.RescanCustomItemFlag()
    if mod._cdmAnyCustomItem or mod._customItemFlagScanned then
        return
    end
    local specProfile = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not specProfile then
        return
    end
    mod._customItemFlagScanned = true
    for _, profileTbl in pairs(specProfile) do
        local barSpellMap = profileTbl and profileTbl.barSpells
        if barSpellMap then
            for _, barStore in pairs(barSpellMap) do
                local assignedList = barStore and barStore.assignedSpells
                if assignedList then
                    for _, spellRef in ipairs(assignedList) do
                        -- Hosted-buff and Empty Slot markers are also <= -100; they are not items.
                        if
                            type(spellRef) == "number"
                            and spellRef <= -100
                            and spellRef > -mod.EMPTY_SLOT_MARKER_BASE
                        then
                            mod._cdmAnyCustomItem = true
                            return
                        end
                    end
                end
            end
        end
    end
end

-- "Show Charges" (custom CD/utility spells) gate. Same contract as the flags above; zero cost in ProcessPresetCooldowns unless a custom spell opted in.
function mod.RescanCustomForceCountFlag()
    if mod._cdmAnyCustomForceCount or mod._customForceCountScanned then
        return
    end
    local specProfile = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not specProfile then
        return
    end
    mod._customForceCountScanned = true
    for _, profileTbl in pairs(specProfile) do
        local barSpellMap = profileTbl and profileTbl.barSpells
        if barSpellMap then
            for _, barStore in pairs(barSpellMap) do
                if barStore and type(barStore.customSpellForceCount) == "table" and next(barStore.customSpellForceCount) then
                    mod._cdmAnyCustomForceCount = true
                    return
                end
            end
        end
    end
end

-- "Out of Range Coloring" (spells added by Spell ID) gate. Same contract as the flags above;
-- lives in the profile customActiveStates. Zero cost in the preset pass (and no range check
-- armed, no listener events) unless a custom spell opted in.
function mod.RescanCustomRangeColorFlag()
    if mod._cdmAnyCustomRangeColor or mod._customRangeColorScanned then
        return
    end
    local customState = mod.GetCustomActiveStates()
    if not customState then
        return
    end
    mod._customRangeColorScanned = true
    for _, entry in pairs(customState) do
        if type(entry) == "table" and entry.outOfRangeColoring then
            mod._cdmAnyCustomRangeColor = true
            -- Arming rides the Show edge; icons already shown missed it.
            mod.RefreshCustomSpellRange()
            return
        end
    end
end

-- Reverse Swipe gate: set ns._cdmAnyReverseSwipe once if any saved spell (any spec) has
-- per-spell reverseSwipe on; the reverse-apply in RefreshCDMIconAppearance is skipped for
-- non-users. Also gates hideCDSwipe -- both monotonic per-spell swipe flags scanned in one pass, costing nothing until used.
function mod.RescanReverseSwipeFlag()
    if mod._reverseSwipeFlagScanned then
        return
    end
    if mod._cdmAnyReverseSwipe and mod._cdmAnyHideCDSwipe then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._reverseSwipeFlagScanned = true
    -- Regular per-spell settings (family stores + bar tiers, every spec).
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if spellSettings.reverseSwipe then
            mod._cdmAnyReverseSwipe = true
        end
        if spellSettings.hideCDSwipe then
            mod._cdmAnyHideCDSwipe = true
        end
    end)
    -- Preset / custom cd-utility spells (profile-level customActiveStates).
    local customState = mod.GetCustomActiveStates and mod.GetCustomActiveStates()
    if customState then
        for _, entry in pairs(customState) do
            if entry then
                if entry.reverseSwipe then
                    mod._cdmAnyReverseSwipe = true
                end
                if entry.hideCDSwipe then
                    mod._cdmAnyHideCDSwipe = true
                end
            end
        end
    end
end

-- Threshold Text gate: set ns._cdmAnyThresholdText once if any saved spell (any spec) has
-- Threshold Seconds armed -- per-spell family stores, bar tiers, or preset/custom
-- customActiveStates entries. Skips the formatter attach in RefreshCDMIconAppearance (and the fake-active/custom-buff attach sites) for non-users. Same monotonic, scanned-once contract.
function mod.RescanThresholdTextFlag()
    if mod._cdmAnyThresholdText or mod._thresholdTextFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._thresholdTextFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if (tonumber(spellSettings.thresholdSeconds) or 0) > 0 then
            mod._cdmAnyThresholdText = true
            return true
        end
    end)
    if not mod._cdmAnyThresholdText then
        local customState = mod.GetCustomActiveStates and mod.GetCustomActiveStates()
        if customState then
            for _, entry in pairs(customState) do
                if type(entry) == "table" and (tonumber(entry.thresholdSeconds) or 0) > 0 then
                    mod._cdmAnyThresholdText = true
                    break
                end
            end
        end
    end
end

-- Custom Icon gate: set ns._cdmAnyCustomIcon once if any saved spell (any spec) has a
-- per-spell replacement icon. Skips the DecorateFrame re-stamp and the RefreshSpellTexture
-- post-hooks for non-users. Same monotonic, scanned-once contract; customIcon is never written to bar tiers.
function mod.RescanCustomIconFlag()
    if mod._cdmAnyCustomIcon or mod._customIconFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._customIconFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if type(spellSettings.customIcon) == "number" and spellSettings.customIcon > 0 then
            mod._cdmAnyCustomIcon = true
            return true
        end
    end)
end

-- Active State Glow gate: set ns._cdmAnyActiveGlow once if any saved spell (any spec) has
-- per-spell activeGlow set. Skips the buff ticker's active-glow integrity pass (safety net
-- that lights the glow when Blizzard skips the SetSwipeColor call that normally drives it) for non-users. Same monotonic, scanned-once contract.
function mod.RescanActiveGlowFlag()
    if mod._cdmAnyActiveGlow or mod._activeGlowFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._activeGlowFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(spellSettings)
        if (tonumber(spellSettings.activeGlow) or 0) > 0 then
            mod._cdmAnyActiveGlow = true
            return true
        end
    end)
end

Inner.SpellStore = SpellStore
Inner.broken = false
