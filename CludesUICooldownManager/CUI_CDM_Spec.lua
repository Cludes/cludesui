if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_Spec.lua
--
--  Spec key cache, spell id resolvers, the available spell pool, spec change
--  handling and the bar roots.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local GetTime = GetTime

local ECME, SpellStore = Inner.ECME, Inner.SpellStore

-------------------------------------------------------------------------------
--  Spec helpers
--
--  Single source of truth: the live game API, cached on first read. Never nil during
--  normal operation -- transitions atomically old->new key inside ProcessSpecChange.
--  InvalidateSpecKey is for the early-login wakeFrame ONLY (before CDM setup completes),
--  never during spec change processing.
--
--  Returns nil when the spec API isn't ready (very early login); consumers MUST bail on nil rather than fall back to a stored value, so CDM never builds with a wrong/guessed spec.
-------------------------------------------------------------------------------
local _cachedSpecKey = nil

function mod.GetActiveSpecKey()
    if _cachedSpecKey then return _cachedSpecKey end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    _cachedSpecKey = tostring(specID)
    return _cachedSpecKey
end

-- Early-login wakeFrame use only (before CDM setup completes); never called during spec change processing.
function mod.InvalidateSpecKey()
    _cachedSpecKey = nil
    mod._cachedSpecProfiles = nil
    mod._cdmStoreMemo = nil
end

-- Live spec key from the game API without touching the cache; nil if not ready.
local function LiveSpecKey()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    return tostring(specID)
end
mod.ComputeLiveSpecKey = LiveSpecKey

if CUI.IS_FOREVER then
    -- WoW Forever reports one spec per class. The store key is the Forever
    -- spec's own key if the ACTIVE profile's store holds it (the layout the
    -- client has been showing), else the first retail spec of the class with
    -- a bucket, else the class's first retail spec. Resolved once per store
    -- table: an edit inside a profile never moves the key; a profile switch or
    -- import (a new store table) re-resolves it before the rebuild reads
    -- anything. SPELLS_CHANGED compares against this same memo, so it can
    -- never mistake a data edit for a spec swap. Memo inputs: the store root
    -- and the raw live spec ID. The active key also records the store root it
    -- was resolved for (ns._fvSpecKeyRoot), so a key resolved against one
    -- profile's store is never served against another's.
    LiveSpecKey = function()
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if not specIndex or specIndex == 0 then return nil end
        local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
        if not specID or specID == 0 then return nil end
        local specProfiles = mod.GetActiveSpecProfiles()
        local m = mod._fvSpecKeyMemo
        if m and m.root == specProfiles and m.raw == specID then return m.key end
        local key = tostring(CUI.SpecFor(specID, CUI.SpecHasStringEntry, specProfiles))
        mod._fvSpecKeyMemo = { root = specProfiles, raw = specID, key = key }
        return key
    end
    mod.ComputeLiveSpecKey = LiveSpecKey
    function mod.GetActiveSpecKey()
        if _cachedSpecKey and mod._fvSpecKeyRoot == mod.GetActiveSpecProfiles() then return _cachedSpecKey end
        local key = LiveSpecKey()
        if not key then return nil end
        _cachedSpecKey = key
        mod._fvSpecKeyRoot = mod.GetActiveSpecProfiles()
        return key
    end
end

-- Per-character key of the bar size cache and the Repopulate requests and
-- records; all three stores take over older keys through CharKey. No longer
-- used for spec storage.
function mod.GetCharKey()
    local saved = CludesUIDB
    return CUI.CharKey(
        "-",
        saved and saved.cdmCachedBarSizes,
        saved and saved.cdmRepopulatePending,
        saved and saved.cdmRepopulateDone
    ) or "Unknown-Unknown"
end

local function EnsureSpec(profile, key)
    profile.spec[key] = profile.spec[key] or { mappings = {}, selectedMapping = 1 }
    return profile.spec[key]
end

local function GetStore()
    local profile = ECME.db.profile
    local specKey = mod.GetActiveSpecKey()
    return EnsureSpec(profile, specKey)
end

local function EnsureMappings(storage)
    if not storage.mappings then storage.mappings = {} end
    if #storage.mappings == 0 then
        storage.mappings[1] = {
            enabled = false,
            name = mod.DEFAULT_MAPPING_NAME,
            actionBar = 1,
            actionButton = 1,
            cdmSlot = 1,
            hideFromCDM = false,
            mode = "ACTIVE",
            glowStyle = 1,
            glowColor = { r = 1, g = 0.82, b = 0.1 },
        }
    end
    storage.selectedMapping = tonumber(storage.selectedMapping) or 1
    if storage.selectedMapping < 1 then storage.selectedMapping = 1 end
    if storage.selectedMapping > #storage.mappings then storage.selectedMapping = #storage.mappings end
    for _, m in ipairs(storage.mappings) do
        if m.enabled == nil then m.enabled = true end
        if m.hideFromCDM == nil then m.hideFromCDM = false end
        if m.mode ~= "MISSING" then m.mode = "ACTIVE" end
        m.glowStyle = tonumber(m.glowStyle) or 1
        if not m.glowColor then m.glowColor = { r = 1, g = 0.82, b = 0.1 } end
        m.name = tostring(m.name or "")
        if type(m.actionBar) ~= "string" or not mod.CDM_BAR_ROOTS[m.actionBar] then
            m.actionBar = tonumber(m.actionBar) or 1
        end
        m.actionButton = tonumber(m.actionButton) or 1
        m.cdmSlot = tonumber(m.cdmSlot) or 1
    end
end

-- Expose for options
mod.GetStore = GetStore
mod.EnsureMappings = EnsureMappings

-------------------------------------------------------------------------------
--  Per-Spec Profile Helpers
--  Saves/restores spell lists, bar glows, and buff bars per specialization.
--  Bar structure, settings, and positions are shared across all specs.
-------------------------------------------------------------------------------
local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }

-- Ghost CD bar: hidden routing sink for CD/utility spells. "Removing" a spell routes it
-- here instead of deleting it, so every spell in Blizzard's viewer pool always has a route -- no allowSet filtering needed during collection.
local GHOST_CD_BAR_KEY = "__ghost_cd"
MAIN_BAR_KEYS[GHOST_CD_BAR_KEY] = true

-------------------------------------------------------------------------------
--  Resolve the best spellID from a CooldownViewerCooldownInfo struct.
--  Priority: overrideSpellID > first linkedSpellID > spellID. The base spellID field
--  can be a spec aura (e.g. 137007 "Unholy Death Knight") while the real tracked spell lives in linkedSpellIDs.
-------------------------------------------------------------------------------
local function ResolveInfoSpellID(details)
    if not details then return nil end
    local spellRef
    if details.overrideSpellID and details.overrideSpellID > 0 then
        spellRef = details.overrideSpellID
    else
        local linked = details.linkedSpellIDs
        if linked then
            for index = 1, #linked do
                if linked[index] and linked[index] > 0 then
                    spellRef = linked[index]
                    break
                end
            end
        end
        if not spellRef and details.spellID and details.spellID > 0 then spellRef = details.spellID end
    end
    return spellRef
end

-------------------------------------------------------------------------------
--  Resolve the best spellID from a Blizzard CDM viewer child frame. For buff bars
--  cooldownInfo often holds the wrong spellID (spec aura, not the tracked buff); the
--  child frame knows the correct one via GetAuraSpellID/GetSpellID at runtime. Falls back
--  to ResolveInfoSpellID when those are unavailable. ONLY used in out-of-combat paths (snapshot, dropdown, reconcile).
-------------------------------------------------------------------------------
local function ResolveChildSpellID(childFrame)
    if not childFrame then return nil end
    -- Prefer the aura spellID (most accurate for buff viewers). Comparisons are pcall-wrapped:
    -- these methods can return SECRET numbers in combat, which cannot be compared with > 0.
    if childFrame.GetAuraSpellID then
        local success, auraID = pcall(childFrame.GetAuraSpellID, childFrame)
        if success and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return auraID end
        end
    end
    if childFrame.GetSpellID then
        local success, fid = pcall(childFrame.GetSpellID, childFrame)
        if success and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return fid end
        end
    end
    local cdID = childFrame.cooldownID or (childFrame.cooldownInfo and childFrame.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        return ResolveInfoSpellID(details)
    end
    return nil
end

local DeepCopy = CUI.Lite.DeepCopy

-------------------------------------------------------------------------------
--  Cached bar sizes -- cosmetic hint for pre-sizing frames on login so anchored
--  elements don't jump. Zero impact on spell logic or icons. Stored at
--  CludesUIDB.cdmCachedBarSizes[charKey][specKey][barKey] = count
-------------------------------------------------------------------------------
function mod.SaveCachedBarSizes()
    if not CludesUIDB then return end
    local charKey = mod.GetCharKey()
    local specKey = mod.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    if not CludesUIDB.cdmCachedBarSizes then CludesUIDB.cdmCachedBarSizes = {} end
    if not CludesUIDB.cdmCachedBarSizes[charKey] then CludesUIDB.cdmCachedBarSizes[charKey] = {} end
    local frameList = mod.cdmBarFrames
    local iconsByKey = mod.cdmBarIcons
    if not frameList or not iconsByKey then return end
    local counts = {}
    for key, widget in pairs(frameList) do
        local icons = iconsByKey[key]
        if icons then
            local vis = 0
            for _, iconTex in ipairs(icons) do
                if iconTex:IsShown() then vis = vis + 1 end
            end
            if vis > 0 then counts[key] = vis end
        end
    end
    CludesUIDB.cdmCachedBarSizes[charKey][specKey] = counts
end

--- Save the current spec's non-spell per-spec data. Spell data lives directly in the global store via ns.GetBarSpellData() and never needs copying.
local function SaveCurrentSpecProfile()
    local profile = ECME.db.profile
    local specKey = mod.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    local specProfiles = SpellStore.GetSpecProfiles()
    if not specProfiles[specKey] then specProfiles[specKey] = { barSpells = {} } end
    local prof = specProfiles[specKey]

    -- Bar Glows and Tracked Buff Bars live in specProfiles[specKey]; GetBarGlows()/GetTrackedBuffBars() read/write there directly, so nothing extra to copy here.

    -- Snapshot visible icon counts for pre-sizing on next login
    mod.SaveCachedBarSizes()
end

--- Spec change processing. NEVER a fixed wall-clock delay: Blizzard's viewer pools repopulate
--- at unpredictable times after a spec swap. SPELLS_CHANGED is the sole trigger -- fires for
--- manual and LFG auto-swaps and guarantees spell data/viewer pools are fully populated.
--- CheckSpecChange compares the live spec key to the cached one on every SPELLS_CHANGED and runs
--- a full talent_reconcile rebuild on a difference. The cached key swaps atomically BEFORE the rebuild so GetBarSpellData always has a valid key. No nil window.
local function ProcessSpecChange(newSpecKey)
    if not newSpecKey then return end
    mod._spellOrderDirty = true -- force spell order cache rebuild

    -- Atomic swap: write the new key BEFORE rebuilding so every GetBarSpellData call during the rebuild reads the correct spec.
    _cachedSpecKey = newSpecKey
    mod._cachedSpecProfiles = nil
    mod._cdmStoreMemo = nil

    -- Suppress the _CUCME_Apply rebuild the profile system fires via RefreshAllAddons: the talent_reconcile rebuild below is strictly stronger.
    mod._specChangeJustRan = true
    -- Time-box stamp for the justRan consume in _CUCME_Apply: suppression is honored only while
    -- the spec change is recent, so a flag left armed by a non-consuming path fails OPEN (extra rebuild) instead of eating a needed one.
    mod._specChangeAt = GetTime()

    mod._pendingApplyOnReanchor = true

    -- Full wipe + rebuild: talent_reconcile takes FullCDMRebuild's isFullWipe branch (wipes
    -- icon arrays, _prevIconRefs/_prevVisibleCount, anchor state in _hookFrameData, all FC
    -- caches on viewer pool frames, then a direct synchronous CollectAndReanchor); cdmBarIcons
    -- holds the new spec's icons after this returns. Placeholder injection is HELD across the
    -- synchronous pass: on a spec switch it runs BEFORE the per-spec profile swap, so
    -- barDataByKey still carries the OLD spec's Always-Show/Keep-in-Place flags and injecting
    -- would flash placeholders the new spec never asked for. The following reanchor (profile_import, or the next buff event) re-injects correctly from the active profile.
    if mod.FullCDMRebuild then
        mod._cdmSpecRebuildStale = true
        mod.FullCDMRebuild("talent_reconcile")
        mod._cdmSpecRebuildStale = false
    end

    -- Signal the profile system that CDM's spec rebuild is complete: clears _specProfileSwitching and re-applies width/height matches.
    CUI.OnSpecSwitchComplete()

    -- Refresh the CDM options pages now that _cachedSpecKey is swapped: their own
    -- PLAYER_SPECIALIZATION_CHANGED watcher can fire before SPELLS_CHANGED, so driving it
    -- here guarantees they rebuild against the new spec instead of keeping the old spec's selected bar.
    if mod.OnTBBSpecChanged then mod.OnTBBSpecChanged() end
end
mod.ProcessSpecChange = ProcessSpecChange

-- Compare live spec to cached; if different, process the change. Called exclusively from
-- SPELLS_CHANGED. Idempotent: after ProcessSpecChange the cached key matches live and subsequent calls are no-ops.
local function CheckSpecChange()
    local liveKey = LiveSpecKey()
    if liveKey and liveKey ~= _cachedSpecKey then ProcessSpecChange(liveKey) end
end
mod.CheckSpecChange = CheckSpecChange

-------------------------------------------------------------------------------
--  CDM Bar Roots
-------------------------------------------------------------------------------
mod.CDM_BAR_ROOTS = {
    CDM_COOLDOWN = "EssentialCooldownViewer",
    CDM_UTILITY = "UtilityCooldownViewer",
}

Inner.CheckSpecChange = CheckSpecChange
Inner.ComputeLiveSpecKey, Inner.EnsureMappings = LiveSpecKey, EnsureMappings
Inner.GetStore, Inner.GHOST_CD_BAR_KEY, Inner.MAIN_BAR_KEYS = GetStore, GHOST_CD_BAR_KEY, MAIN_BAR_KEYS
Inner.ResolveChildSpellID, Inner.ResolveInfoSpellID = ResolveChildSpellID, ResolveInfoSpellID
Inner.SaveCurrentSpecProfile = SaveCurrentSpecProfile
Inner.GetCachedSpecKey = function() return _cachedSpecKey end
Inner.broken = false
