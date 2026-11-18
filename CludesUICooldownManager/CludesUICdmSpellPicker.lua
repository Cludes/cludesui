if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUICdmSpellPicker.lua
--  Interactive Preview Helpers (used by options spell picker): spell list
--  building, add/remove/swap/move/replace, and custom bar creation/removal.
-------------------------------------------------------------------------------
local _, mod = ...

-- Upvalue aliases (populated by CludesUICooldownManager.lua and the CUI_CDM_*.lua files)
local ECME = mod.ECME
local barDataByKey = mod.barDataByKey
local cdmBarFrames = mod.cdmBarFrames
local cdmBarIcons = mod.cdmBarIcons
local ResolveInfoSpellID = mod.ResolveInfoSpellID
local ComputeTopRowStride = mod.ComputeTopRowStride

-------------------------------------------------------------------------------
--  SpellVariant helpers
--  "variant family" = { spellID, base, override, override-of-base }. Treats
--  e.g. Heroism/Bloodlust override variants as one logical entry.
--  StoreVariantValue(target, spellID, value, preserveExisting, directSet):
--  writes value under every family key. preserveExisting applies to the EXACT
--  id only (first-write-wins); derived keys never overwrite an existing entry,
--  so one spell's expansion can't displace another's exact assignment.
--  directSet, if given, records the exact id separately from derived keys.
--  ResolveVariantValue(sourceMap, spellID): first non-nil sourceMap[k] across
--  the family, else nil. IsVariantOf(a, b): true if a and b share any member.
-------------------------------------------------------------------------------
-- Reject secret-tainted numbers before comparing: frame:GetSpellID() on active
-- viewer frames can return a secret, and `id > 0` on it taints us.
-- issecretvalue/type() read safely without touching the value.
local function _IsUsableSID(ident)
    if type(ident) ~= "number" then
        return false
    end
    if issecretvalue and issecretvalue(ident) then
        return false
    end
    return ident > 0 and ident == math.floor(ident)
end

local function _GetBase(spellRef)
    if not _IsUsableSID(spellRef) or not C_Spell or not C_Spell.GetBaseSpell then
        return nil
    end
    local b = C_Spell.GetBaseSpell(spellRef)
    if _IsUsableSID(b) and b ~= spellRef then
        return b
    end
    return nil
end

local function _GetOverride(spellRef)
    if not _IsUsableSID(spellRef) or not C_Spell or not C_Spell.GetOverrideSpell then
        return nil
    end
    local o = C_Spell.GetOverrideSpell(spellRef)
    if _IsUsableSID(o) and o ~= spellRef then
        return o
    end
    return nil
end

local function _StoreIfValid(target, ident, value, preserveExisting)
    if not _IsUsableSID(ident) then
        return
    end
    if preserveExisting and target[ident] ~= nil then
        return
    end
    target[ident] = value
end

-- Concrete case for directSet: Divine Toll and its override share cooldownID/
-- base, so without it the winner would depend on collection order and the
-- slot could change bars as the spell transforms. Derived keys fill gaps only.
local function StoreVariantValue(target, spellId, value, preserveExisting, directSet)
    if type(target) ~= "table" or not _IsUsableSID(spellId) then
        return
    end
    _StoreIfValid(target, spellId, value, preserveExisting)
    if type(directSet) == "table" then
        directSet[spellId] = value
    end
    _StoreIfValid(target, _GetOverride(spellId), value, true)
    local baseId = _GetBase(spellId)
    if baseId then
        _StoreIfValid(target, baseId, value, true)
        _StoreIfValid(target, _GetOverride(baseId), value, true)
    end
end

local function ResolveVariantValue(sourceMap, spellId)
    if type(sourceMap) ~= "table" or not _IsUsableSID(spellId) then
        return nil
    end
    local direct = sourceMap[spellId]
    if direct ~= nil then
        return direct
    end
    local baseId = _GetBase(spellId)
    if baseId then
        local v = sourceMap[baseId]
        if v ~= nil then
            return v
        end
    end
    local overrideID = _GetOverride(spellId)
    if overrideID then
        local v = sourceMap[overrideID]
        if v ~= nil then
            return v
        end
    end
    if baseId then
        local baseOverrideID = _GetOverride(baseId)
        if baseOverrideID then
            local v = sourceMap[baseOverrideID]
            if v ~= nil then
                return v
            end
        end
    end
    return nil
end

local function IsVariantOf(spellIDA, spellIDB)
    if not _IsUsableSID(spellIDA) or not _IsUsableSID(spellIDB) then
        return false
    end
    if spellIDA == spellIDB then
        return true
    end
    -- Some rotating viewer spells expose no reversible relationship through
    -- GetBaseSpell/GetOverrideSpell in one of their live states.  The hook
    -- layer persists the clean, spec-scoped pairing when the viewer does expose
    -- it; consult that ledger so moving/re-adding Sacred Weapon also removes a
    -- stale Holy Bulwark/base entry from the old bar or ghost list.
    if mod.IsLearnedVariantOf and mod.IsLearnedVariantOf(spellIDA, spellIDB) then
        return true
    end
    if _GetBase(spellIDA) == spellIDB or _GetBase(spellIDB) == spellIDA then
        return true
    end
    if _GetOverride(spellIDA) == spellIDB or _GetOverride(spellIDB) == spellIDA then
        return true
    end
    local baseA = _GetBase(spellIDA)
    local baseB = _GetBase(spellIDB)
    if baseA and baseB and baseA == baseB then
        return true
    end
    return false
end

mod.StoreVariantValue = StoreVariantValue
mod.ResolveVariantValue = ResolveVariantValue
mod.IsVariantOf = IsVariantOf

-- WoW Forever: each rank of a spell is a spell ID of its own, and the ranks
-- share the spell's name. Blizzard's Cooldown Manager shows a spell's ranks as
-- one entry (the highest rank known), so a bar lists a spell once, under any
-- of its ranks: list presence (FindVariantIndex below), the options normalize
-- pass, the keep/drop pass and the picker's on-bar mark all match ranks by
-- this name. nil off Forever. Names are client spell data, the same all
-- session; a name the client has not loaded yet is not kept.
local RankName
if CludesUI.IS_FOREVER then
    local nameList = {}
    RankName = function(ident)
        if not _IsUsableSID(ident) then
            return nil
        end
        local n = nameList[ident]
        if n == nil then
            n = C_Spell.GetSpellName(ident)
            if n then
                nameList[ident] = n
            end
        end
        return n
    end
end
mod.CDMRankName = RankName

-------------------------------------------------------------------------------
--  CDM category-set constants (Midnight's 9-value CooldownViewerCategory).
--  CDM_ICON_CD_CATS: cooldown/utility icon categories (Essential, Utility,
--  SpecAgnosticEssential, EquipSlotEssential). CDM_BUFF_CATS: buff-family
--  categories (TrackedBuff, GroupBuff, SpecAgnosticTracked, EquipSlotTracked).
--  TrackedBar (3) is scoped separately by GetTrackedBarSpells and is a member
--  of neither set. Hidden pseudo-categories (HiddenActive/HiddenPassive,
--  negative values) are never members of either set. Numeric fallbacks let
--  these build even if the Enum table is ever unavailable at load.
-------------------------------------------------------------------------------
do
    local evc = Enum and Enum.CooldownViewerCategory
    mod.CDM_ICON_CD_CATS = {
        [(evc and evc.Essential) or 0] = true,
        [(evc and evc.Utility) or 1] = true,
        [(evc and evc.SpecAgnosticEssential) or 5] = true,
        [(evc and evc.EquipSlotEssential) or 7] = true,
    }
    mod.CDM_BUFF_CATS = {
        [(evc and evc.TrackedBuff) or 2] = true,
        [(evc and evc.GroupBuff) or 4] = true,
        [(evc and evc.SpecAgnosticTracked) or 6] = true,
        [(evc and evc.EquipSlotTracked) or 8] = true,
    }
end

-- Normalize a spell ID to its base (undo talent overrides), e.g. Voltaic
-- Blaze (470057) -> Flame Shock (188389). Resident home for what used to be
-- an options-file-local pair so every consumer (the keep/drop reconcile
-- pass, the picker, migration) shares one implementation and one secrecy
-- gate. Degrades to identity on any invalid/secret id or missing API so
-- callers can key tables on the result without a separate validity check.
function mod.NormalizeToBase(spellRef)
    if not _IsUsableSID(spellRef) or not C_Spell or not C_Spell.GetBaseSpell then
        return spellRef
    end
    local base = C_Spell.GetBaseSpell(spellRef)
    if _IsUsableSID(base) then
        return base
    end
    return spellRef
end

-- Resolve a base spell ID to its current live version (talent overrides),
-- e.g. Flame Shock (188389) -> Voltaic Blaze (470057) when talented. Uses
-- the spellbook override bridge (not this file's private _GetOverride, which
-- is C_Spell.GetOverrideSpell -- a different API with different semantics)
-- so catalog/live-icon membership tests agree with the rest of the resident code.
function mod.ResolveToLive(spellRef)
    if not _IsUsableSID(spellRef) or not C_SpellBook or not C_SpellBook.FindSpellOverrideByID then
        return spellRef
    end
    local ovr = C_SpellBook.FindSpellOverrideByID(spellRef)
    if _IsUsableSID(ovr) then
        return ovr
    end
    return spellRef
end

-------------------------------------------------------------------------------
--  Buff variant-alias ledger
--  A buff whose live cooldown-viewer report rotates among several spellIDs
--  (e.g. a dual-tracked or talent-swapped form) only exposes its OTHER forms
--  via linkedSpellIDs, and only while that exact instance is the one
--  currently active. This ledger records every id pairing ever observed
--  together on the active spec, persisted under the spec profile
--  (prof.buffVariantAliases, sibling of barSpells), so a later reconcile
--  pass can recognize the whole family as one entity even when only one
--  member is currently reporting.
--
--  Storage is a SET per id (ledger[a] = { [b] = true, ... }), not a single
--  scalar partner: an N-way family writes every pairwise edge from one
--  observation, and a scalar slot would let a later pair silently overwrite
--  an earlier one, disconnecting part of the family from closure expansion.
-------------------------------------------------------------------------------
local _buffAliasSeen = {}

-- Learns every pairwise edge among {displaySID} union linkedList that this session
-- hasn't already recorded. Ids are gated for secrecy/plausibility here so callers never
-- need to; the session-cache early-out (mirrors _learnVariantBase in
-- CUI_CDM_HookResolve.lua) keeps repeat observations of an already-known pairing from
-- touching the profile table.
function mod.LearnBuffVariantAlias(displaySID, linkedList)
    if type(linkedList) ~= "table" or #linkedList == 0 then
        return
    end
    local idList
    if _IsUsableSID(displaySID) then
        idList = { displaySID }
    end
    for i = 1, #linkedList do
        local lid = linkedList[i]
        if _IsUsableSID(lid) then
            idList = idList or {}
            idList[#idList + 1] = lid
        end
    end
    if not idList or #idList < 2 then
        return
    end

    local ledgerTbl
    for i = 1, #idList do
        local a = idList[i]
        for jdx = i + 1, #idList do
            local b = idList[jdx]
            local seenA = _buffAliasSeen[a]
            if not (seenA and seenA[b]) then
                if not ledgerTbl then
                    local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                    local sk = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                    local profileTbl = spellRec and sk and spellRec[sk]
                    if not profileTbl then
                        return
                    end
                    if not profileTbl.buffVariantAliases then
                        profileTbl.buffVariantAliases = {}
                    end
                    ledgerTbl = profileTbl.buffVariantAliases
                end
                ledgerTbl[a] = ledgerTbl[a] or {}
                ledgerTbl[a][b] = true
                ledgerTbl[b] = ledgerTbl[b] or {}
                ledgerTbl[b][a] = true
                _buffAliasSeen[a] = _buffAliasSeen[a] or {}
                _buffAliasSeen[a][b] = true
                _buffAliasSeen[b] = _buffAliasSeen[b] or {}
                _buffAliasSeen[b][a] = true
            end
        end
    end
end

-- Shared empty fallback; never mutated (only the writer above creates the real table).
local _EMPTY_ALIAS_LEDGER = {}

-- Active spec's learned buff-family ledger, or a shared empty table when no profile is
-- active yet or no pairing has ever been learned. Read-only: never creates the key.
function mod.GetBuffVariantAliases()
    local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    local sk = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local profileTbl = spellRec and sk and spellRec[sk]
    return (profileTbl and profileTbl.buffVariantAliases) or _EMPTY_ALIAS_LEDGER
end

-- Per-cooldownID cache of the last CLEAN frame:GetSpellID(). While a viewer
-- frame is ACTIVE, GetSpellID()/GetAuraSpellID() return secret values, so the
-- live talent form is unreadable and would degrade to the generic
-- cooldownInfo.spellID; reuse the clean value from the last INACTIVE read so
-- picker/preview agree regardless of aura state. Shared (ns) so reanchor can
-- prime it at login. Self-heals: any later clean read overwrites the entry.
mod._cdmCleanSidByCDID = mod._cdmCleanSidByCDID or {}
local _cleanSidByCDID = mod._cdmCleanSidByCDID

-- GetCanonicalSpellIDForFrame: preferred spell ID to STORE for a Blizzard CDM
-- viewer frame. Picker, migration, and runtime resolution all use this so
-- they agree on the ID for the same logical spell. Priority (first non-nil
-- wins): 1. frame:GetSpellID() -- most authoritative, the active variant
-- under transforms (e.g. Glacial Spike from Frostbolt), what the user can
-- actually cast, not the static info; 2. info.overrideSpellID; 3. info.spellID;
-- 4. base of (1) as fallback. (linkedSpellIDs is deliberately NOT a rung --
-- see the comment at the info branch.)
local function GetCanonicalSpellIDForFrame(widget)
    if not widget then
        return nil
    end

    local fnGetSpellID = widget.GetSpellID
    if type(fnGetSpellID) == "function" then
        local spellRef = fnGetSpellID(widget)
        if _IsUsableSID(spellRef) then
            -- Clean read: cache by cooldownID so a later secret read still resolves.
            local cdid = widget.cooldownID
            if type(cdid) == "number" then
                _cleanSidByCDID[cdid] = spellRef
            end
            return spellRef
        end
    end

    -- GetAuraSpellID(): buff frames expose the aura variant (Eclipse Solar
    -- vs Lunar); GetSpellID may not exist there.
    local fnGetAura = widget.GetAuraSpellID
    if type(fnGetAura) == "function" then
        local spellRef = fnGetAura(widget)
        if _IsUsableSID(spellRef) then
            -- Clean read: prime the cooldownID cache here too, so buff frames
            -- (no GetSpellID) still resolve while their aura is up.
            local cdid = widget.cooldownID
            if type(cdid) == "number" then
                _cleanSidByCDID[cdid] = spellRef
            end
            return spellRef
        end
    end

    -- Active-frame fallback: both getters returned secret/nil (aura is up).
    -- Reuse the clean GetSpellID cached while inactive, instead of degrading
    -- to the generic cooldownInfo.spellID below.
    local cdid = widget.cooldownID
    if type(cdid) == "number" then
        local cached = _cleanSidByCDID[cdid]
        if cached then
            return cached
        end
    end

    local details = widget.cooldownInfo
    if not details then
        local fnGetInfo = widget.GetCooldownInfo
        if type(fnGetInfo) == "function" then
            details = fnGetInfo(widget)
        end
    end

    if details then
        if _IsUsableSID(details.overrideSpellID) then
            return details.overrideSpellID
        end
        if _IsUsableSID(details.spellID) then
            return details.spellID
        end
        -- Deliberately NOT falling back to linkedSpellIDs[1] here: the frame's
        -- own info is the MERGED provider table (Blizzard caches
        -- GetCooldownInfoForID at SetCooldownID), where linked lists are
        -- group-shared and categories are folded to DISPLAY values -- it can
        -- tell neither frames nor native equip rows apart. The one legitimate
        -- linked-identity source is the RAW API block below.
    end

    -- Native tracked trinket buff rows (RAW equipSlot + category
    -- EquipSlotTracked): these carry no spellID at all at rest, and their RAW
    -- linked list is Blizzard's own designed identity channel for the row's
    -- tracked buff -- field-probed 2026-08-16 as per-row UNIQUE (buffSlot 1
    -- and 2 of one trinket carry different single-entry lists). The RAW
    -- GetCooldownViewerCooldownInfo table is the proven source: the frame's
    -- merged copy folds category to the display value (TrackedBuff) and
    -- cannot pass this gate. Resolved sid is cached by cooldownID like the
    -- clean GetSpellID path, so secret windows (proc active in combat) keep
    -- resolving from the memo. Reached only after every other rung failed
    -- (identity-less shells), so the extra C call is shell-only.
    if type(cdid) == "number" and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local raw = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdid)
        local eqTracked = Enum
                and Enum.CooldownViewerCategory
                and Enum.CooldownViewerCategory.EquipSlotTracked
            or 8
        if
            raw
            and raw.equipSlot
            and not (issecretvalue and issecretvalue(raw.equipSlot))
            and raw.category
            and not (issecretvalue and issecretvalue(raw.category))
            and raw.category == eqTracked
        then
            local linked = raw.linkedSpellIDs
            if type(linked) == "table" then
                local lid = linked[1]
                if _IsUsableSID(lid) then
                    _cleanSidByCDID[cdid] = lid
                    return lid
                end
            end
        end
    end

    -- Last resort: base of frame:GetSpellID()
    if type(fnGetSpellID) == "function" then
        local raw = fnGetSpellID(widget)
        if _IsUsableSID(raw) then
            local base = _GetBase(raw)
            if base then
                return base
            end
            return raw
        end
    end

    return nil
end
mod.GetCanonicalSpellIDForFrame = GetCanonicalSpellIDForFrame

-- EnumerateCDMViewerSpells: walks the CD/util viewer pools, returns canonical
-- spell entries in viewer-then-layoutIndex render order. Shared source of
-- truth for picker AND migration -- the same spells the route map sees.
local function EnumerateCDMViewerSpells(includeBuffViewer)
    local viewers
    if includeBuffViewer then
        viewers = { "BuffIconCooldownViewer" }
    else
        viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
    end

    local result = {}
    local seenSet = {}
    local viewerOrder = 0
    local entryList = {}

    for _, vName in ipairs(viewers) do
        local viewer = _G[vName]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            for widget in viewer.itemFramePool:EnumerateActive() do
                if widget:IsShown() or widget.cooldownInfo then
                    local spellRef = GetCanonicalSpellIDForFrame(widget)
                    -- Dedup identity: BUFF viewer can have two cooldownIDs share
                    -- one spellID (e.g. Diabolist: Demonic Art vs Diabolic
                    -- Ritual), so key on cooldownID there (sid-dedup would
                    -- wrongly merge them); CD/util viewers keep sid-dedup to
                    -- collapse a spell shown in two viewers. Non-colliding specs
                    -- are unaffected: a unique sid there implies a unique cooldownID.
                    local cd = widget.cooldownID
                    local dkey = (includeBuffViewer and type(cd) == "number") and ("c" .. cd) or spellRef
                    if _IsUsableSID(spellRef) and dkey ~= nil and not seenSet[dkey] then
                        seenSet[dkey] = true
                        entryList[#entryList + 1] = {
                            sid = spellRef,
                            cdID = widget.cooldownID,
                            viewerName = vName,
                            viewerOrder = viewerOrder,
                            layoutIndex = widget.layoutIndex or 0,
                        }
                    end
                end
            end
        end
        viewerOrder = viewerOrder + 10000
    end

    table.sort(entryList, function(a, b)
        if a.viewerOrder ~= b.viewerOrder then
            return a.viewerOrder < b.viewerOrder
        end
        if a.layoutIndex ~= b.layoutIndex then
            return a.layoutIndex < b.layoutIndex
        end
        return a.sid < b.sid
    end)

    for i, e in ipairs(entryList) do
        result[i] = e -- preserve metadata for picker
    end
    return result
end
mod.EnumerateCDMViewerSpells = EnumerateCDMViewerSpells

-- Unified spell list helpers: ONE add path and ONE remove path for every CDM
-- bar's assignedSpells list (default/custom/ghost bars). Variant-aware via
-- IsVariantOf, so adding the same spell under a different variant ID is a
-- no-op. AddTrackedSpell/RemoveTrackedSpell delegate to these.

--- Find an entry's index in a spell list. Positive IDs (real spells) match by
--- variant family (re-adding any variant is a no-op), then on WoW Forever by
--- rank (RankName above); negative IDs (trinkets <= -13/-14, item presets
--- <= -100) match by exact equality -- variant resolution doesn't apply to
--- injection markers.
local function FindVariantIndex(spellArray, spellId)
    if type(spellArray) ~= "table" or type(spellId) ~= "number" or spellId == 0 then
        return nil
    end
    if spellId > 0 then
        for i = 1, #spellArray do
            local existing = spellArray[i]
            if _IsUsableSID(existing) and IsVariantOf(existing, spellId) then
                return i
            end
        end
        local label = RankName and RankName(spellId)
        if label then
            for i = 1, #spellArray do
                if RankName(spellArray[i]) == label then
                    return i
                end
            end
        end
    else
        for i = 1, #spellArray do
            if spellArray[i] == spellId then
                return i
            end
        end
    end
    return nil
end
mod.FindVariantIndexInList = FindVariantIndex

--- Add a spellID to a bar's assignedSpells list. Idempotent under variant
--- equivalence (no-op if any family member is present). True on add, else false.
function mod.AddSpellToBar(barId, spellId)
    if not _IsUsableSID(spellId) then
        return false
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    if not barSpells.assignedSpells then
        barSpells.assignedSpells = {}
    end
    if FindVariantIndex(barSpells.assignedSpells, spellId) then
        return false
    end
    barSpells.assignedSpells[#barSpells.assignedSpells + 1] = spellId
    mod._spellOrderDirty = true
    -- Mutual exclusivity with the ghost bar: the route map gives the ghost
    -- highest priority, so a spell left in both stays hidden; un-hide it here.
    if barId ~= mod.GHOST_CD_BAR_KEY and mod.RemoveSpellFromBar then
        mod.RemoveSpellFromBar(mod.GHOST_CD_BAR_KEY, spellId)
    end
    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    -- FocusKick arms its proxies on bar CONTENT; nothing else re-runs that when
    -- content changes here, so an add must explicitly re-evaluate.
    if barId == mod.FOCUSKICK_BAR_KEY and mod.RefreshFocusKickProxies then
        mod.RefreshFocusKickProxies("spell-added")
    end
    return true
end

--- Remove a spellID from a bar's assignedSpells list (variant-aware). Returns
--- the removed spellID (actual stored variant, may differ from queried) or nil.
function mod.RemoveSpellFromBar(barId, spellId)
    -- Accepts positive (real spell) or negative (trinket/item preset) IDs;
    -- FindVariantIndex dispatches internally.
    if type(spellId) ~= "number" or spellId == 0 then
        return nil
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells or not barSpells.assignedSpells then
        return nil
    end
    local position = FindVariantIndex(barSpells.assignedSpells, spellId)
    if not position then
        return nil
    end
    local removed = table.remove(barSpells.assignedSpells, position)
    mod._spellOrderDirty = true
    -- Clean up auxiliary per-spell metadata for the removed entry
    if barSpells.customSpellDurations then
        barSpells.customSpellDurations[removed] = nil
    end
    if barSpells.spellDurations then
        barSpells.spellDurations[removed] = nil
    end
    if barSpells.customSpellIDs then
        barSpells.customSpellIDs[removed] = nil
    end
    if barSpells.customSpellGroups then
        for variantID, primaryId in pairs(barSpells.customSpellGroups) do
            if primaryId == removed then
                barSpells.customSpellGroups[variantID] = nil
            end
        end
    end
    -- Default buffs bar: scrub the removed custom buff's stable order key. Absent keys
    -- are normally kept as gaps (talent-swap feature), but a user-removed custom buff
    -- never returns to fill its gap, and the orphans would desync the preview's
    -- rendered slots. Blizzard-tracked buffs key as "c"..cooldownID and are unaffected.
    if
        barId == "buffs"
        and type(removed) == "number"
        and removed > 0
        and type(barSpells.buffDisplayOrder) == "table"
    then
        local t = barSpells.buffDisplayOrder
        local skey = "s" .. removed
        for i = #t, 1, -1 do
            if t[i] == skey then
                table.remove(t, i)
            end
        end
    end
    -- Hosted-buff bookkeeping: removing the MARKER (or a legacy plain entry that
    -- represents the buff: flag set, no marker in the list) un-hosts the buff --
    -- otherwise the orphaned flag makes the options self-heal re-append the
    -- spell here (spell reappears on two bars). A plain entry removed while a
    -- marker still exists is a cooldown-only removal; the hosted buff stays.
    local hostedSid = mod.HostedBuffMarkerToSpell and mod.HostedBuffMarkerToSpell(removed)
    if
        not hostedSid
        and removed
        and removed > 0
        and barSpells.hostedBuffSpellIDs
        and barSpells.hostedBuffSpellIDs[removed]
        and not (mod.ListHasHostedMarker and mod.ListHasHostedMarker(barSpells.assignedSpells, removed))
    then
        hostedSid = removed
    end
    if hostedSid and barSpells.hostedBuffSpellIDs then
        barSpells.hostedBuffSpellIDs[hostedSid] = nil
        -- Host flip changes resolution routing: retire memoized results.
        mod._cdmResGen = (mod._cdmResGen or 0) + 1
    end
    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    -- Same as AddSpellToBar: emptying the kick bar must re-evaluate proxies
    -- (cast sound survives an empty bar if an explicit interrupt is set).
    if barId == mod.FOCUSKICK_BAR_KEY and mod.RefreshFocusKickProxies then
        mod.RefreshFocusKickProxies("spell-removed")
    end
    -- Aura-tracked customs: re-sync the bar's engine strip so a removed
    -- custom stops rendering immediately (the strip's include filter is
    -- declaration-fixed -- without this it keeps matching the removed id
    -- until the next full rebuild). Signature-gated: a no-op for every
    -- other kind of removal.
    if mod.UpdateCustomBuffAuraTracking then
        mod.UpdateCustomBuffAuraTracking()
    end
    return removed
end

-- EnumerateCDMSettingsCatalog: arrangement-aware, talent-independent tracked CD/utility
-- cooldown enumeration from the Blizzard CDM settings panel's data provider. Unlike
-- live viewer pools, includes untalented spells (never get a viewer frame); unlike the
-- static category API, respects arrangement (Not Displayed reads Hidden, skipped) and
-- returns the arranged order. READ-ONLY, pcall-guarded; nil if provider/method missing
-- (callers fall back to live-pool behavior). Returns { cdID, sid, category } array,
-- Essential + Utility only.
function mod.EnumerateCDMSettingsCatalog(wantSet)
    local evc = Enum and Enum.CooldownViewerCategory
    if not evc then
        return nil
    end
    -- Default (no arg): full CD/utility catalog via ns.CDM_ICON_CD_CATS
    -- (Essential, Utility, SpecAgnosticEssential, EquipSlotEssential). Buff
    -- (ns.CDM_BUFF_CATS) / tracked-bar (TrackedBar=3) callers pass an explicit
    -- { [catValue] = true } set so each bar type scopes its own catalog.
    if wantSet == nil then
        if evc.Essential == nil or evc.Utility == nil then
            return nil
        end
        wantSet = mod.CDM_ICON_CD_CATS
    end
    local prefs = _G.CooldownViewerSettings
    if not prefs or type(prefs.GetDataProvider) ~= "function" then
        return nil
    end
    local okP, provider = pcall(prefs.GetDataProvider, prefs)
    if not okP or type(provider) ~= "table" then
        return nil
    end
    -- Read the already-built display table, never the getters that would
    -- build it (see ns.CDMGetProviderDisplayData, CUI_CDM_Reconcile.lua).
    local ordered, infoByID = mod.CDMGetProviderDisplayData(provider)
    if not ordered then
        return nil
    end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then
        return nil
    end

    local result = {}
    for _, cooldownId in ipairs(ordered) do
        local pInfo = _IsUsableSID(cooldownId) and infoByID[cooldownId]
        local category
        if type(pInfo) == "table" then
            category = pInfo.category
        end
        if category ~= nil and wantSet[category] then
            -- Same shape the migration and spell caches use. Prefer override
            -- only when the player actually has it -- CDM info can report a
            -- stale override after the talent providing it is gone.
            local details = gci(cooldownId)
            local spellRef
            if details then
                local ovr = details.overrideSpellID
                if ovr and ovr > 0 and IsPlayerSpell and IsPlayerSpell(ovr) then
                    spellRef = ovr
                else
                    spellRef = details.spellID
                end
            end
            if _IsUsableSID(spellRef) then
                result[#result + 1] = { cdID = cooldownId, sid = spellRef, category = category }
            end
        end
    end
    return result
end

-- True when the picker's spell list for a CD/utility bar holds spellID (or a
-- variant of it): a cooldown in Blizzard's Essential/Utility viewers or its
-- settings catalog, talented or not (GetCDMSpellsForBar's own sources). Added
-- by Spell ID, such a spell is drawn from Blizzard's frame, which never reads
-- the custom-spell settings its menu writes. A spell set to Not Displayed is
-- left out, as the list leaves it out: it has no Blizzard frame, so CUI draws
-- its own and those settings work. Built per call (Add Custom Spell only).
function mod.IsCDMTrackedCooldown(spellId)
    if not _IsUsableSID(spellId) then
        return false
    end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local set = {}
    local function Add(cooldownId, spellRef)
        if _IsUsableSID(spellRef) then
            set[spellRef] = true
        end
        local details = gci and _IsUsableSID(cooldownId) and gci(cooldownId)
        if details then
            if _IsUsableSID(details.spellID) then
                set[details.spellID] = true
            end
            if _IsUsableSID(details.overrideSpellID) then
                set[details.overrideSpellID] = true
            end
        end
    end
    for _, e in ipairs(EnumerateCDMViewerSpells(false)) do
        Add(e.cdID, e.sid)
    end
    local catalog = mod.EnumerateCDMSettingsCatalog(mod.CDM_ICON_CD_CATS)
    if catalog then
        for _, ce in ipairs(catalog) do
            Add(ce.cdID, ce.sid)
        end
    end
    return ResolveVariantValue(set, spellId) == true
end

--- Returns array of { cdID, spellID, name, icon, cdmCat, cdmCatGroup, onCUIBar, isKnown },
--- sorted by viewer order (Essential before Utility) then alpha.
--- Walks Blizzard's CDM viewer pools (live frames), NOT the static category
--- API -- the same source of truth the route map uses, so picker contents
--- always match what routes to bars at reanchor. For CD/utility bars,
--- untalented tracked spells (no live frame) are appended from the settings
--- catalog so whole layouts can be arranged without swapping talents.
function mod.GetCDMSpellsForBar(barId, includeUntalented)
    -- ns.IsBarBuffFamily: forward reference, defined further down this file.
    local isBuffType = mod.IsBarBuffFamily and mod.IsBarBuffFamily(barId) or false

    -- Variant-keyed lookup of spells already on THIS bar (for onCUIBar flag).
    -- WoW Forever: plus their names, so a spell listed under another rank
    -- reads as on the bar (RankName above).
    local ourPool = {}
    local ourNames = RankName and {}
    local barSpells = mod.GetBarSpellData(barId)
    if barSpells and barSpells.assignedSpells then
        for _, spellRef in ipairs(barSpells.assignedSpells) do
            if spellRef and spellRef ~= 0 then
                StoreVariantValue(ourPool, spellRef, true, false)
                local n = ourNames and RankName(spellRef)
                if n then
                    ourNames[n] = true
                end
            end
        end
    end

    -- Picker only enumerates pool members, so every result is Blizzard-tracked.
    local entryList = EnumerateCDMViewerSpells(isBuffType)

    local spellSet = {}
    for _, e in ipairs(entryList) do
        local spellRef = e.sid
        local label = C_Spell.GetSpellName(spellRef)
        local texture = C_Spell.GetSpellTexture(spellRef)
        if label then
            local isOnThisBar = (ResolveVariantValue(ourPool, spellRef) == true)
                or (ourNames ~= nil and ourNames[label] == true)
            spellSet[#spellSet + 1] = {
                cdID = e.cdID,
                spellID = spellRef,
                name = label,
                icon = texture,
                cdmCat = e.viewerOrder, -- preserve viewer grouping for sort
                cdmCatGroup = isBuffType and "buff" or "cooldown",
                onCUIBar = isOnThisBar,
                isKnown = true, -- live viewer pool members are always learned
            }
        end
    end

    -- CD/utility bars: also list untalented spells and conditionally-pooled
    -- ones Blizzard currently hides, sourced from the settings catalog
    -- (respects Not Displayed). Buff pickers untouched.
    if not isBuffType and mod.EnumerateCDMSettingsCatalog then
        -- Explicit set (mirrors the function's own default) so this call
        -- stays correct even if that default is ever narrowed.
        local catalog = mod.EnumerateCDMSettingsCatalog(mod.CDM_ICON_CD_CATS)
        if catalog then
            local evc = Enum and Enum.CooldownViewerCategory
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entryList) do
                if e.cdID ~= nil then
                    seenCd[e.cdID] = true
                end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID] and not ResolveVariantValue(seenSid, ce.sid) then
                    local label = C_Spell.GetSpellName(ce.sid)
                    local texture = C_Spell.GetSpellTexture(ce.sid)
                    if label then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then
                            known = true
                        end
                        spellSet[#spellSet + 1] = {
                            cdID = ce.cdID,
                            spellID = ce.sid,
                            name = label,
                            icon = texture,
                            -- Match live grouping so catalog spells sort beside learned peers.
                            cdmCat = (evc and ce.category == evc.Utility) and 10000 or 0,
                            cdmCatGroup = "cooldown",
                            onCUIBar = (ResolveVariantValue(ourPool, ce.sid) == true)
                                or (ourNames ~= nil and ourNames[label] == true),
                            isKnown = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
        end
    end

    -- Buff bars: also list untalented buff-family entries (TrackedBuff,
    -- GroupBuff, SpecAgnosticTracked, EquipSlotTracked). Picker-only, so
    -- BarGlows/other consumers stay live-only.
    if isBuffType and includeUntalented and mod.EnumerateCDMSettingsCatalog then
        local catalog = mod.EnumerateCDMSettingsCatalog(mod.CDM_BUFF_CATS)
        if catalog then
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entryList) do
                if e.cdID ~= nil then
                    seenCd[e.cdID] = true
                end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID] and not ResolveVariantValue(seenSid, ce.sid) then
                    local label = C_Spell.GetSpellName(ce.sid)
                    local texture = C_Spell.GetSpellTexture(ce.sid)
                    if label then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then
                            known = true
                        end
                        spellSet[#spellSet + 1] = {
                            cdID = ce.cdID,
                            spellID = ce.sid,
                            name = label,
                            icon = texture,
                            cdmCat = 0, -- single buff viewer bucket
                            cdmCatGroup = "buff",
                            onCUIBar = (ResolveVariantValue(ourPool, ce.sid) == true)
                                or (ourNames ~= nil and ourNames[label] == true),
                            isKnown = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
        end
    end

    -- Viewer order first (Essential before Utility), then alpha.
    table.sort(spellSet, function(a, b)
        if a.cdmCat ~= b.cdmCat then
            return (a.cdmCat or 0) < (b.cdmCat or 0)
        end
        return a.name < b.name
    end)

    return spellSet
end

-- (ns.GetTBBSpellPool removed -- TBB disabled pending rewrite)

--- One-time per-spec pass serving two purposes with the same logic: (1) legacy
--- migration of pre-refactor "assignedSpells as content filter" on default
--- CD/utility bars into the "ghost-bar diversion" model, preserving the
--- user's visual state; (2) import-authoritative ghosting (_importGhostMode):
--- a fresh import starts the ghost EMPTY, so this ghosts every importer-
--- tracked spell except what the layout assigns to a visible bar, so an
--- unplaced tracked cooldown hides instead of spilling onto the default bar.
--- Both reduce to: ghost (tracked) MINUS (assigned to any visible bar) MINUS
--- (already ghosted), over Essential + Utility categories.
--- Per-spec lazy (category APIs are spec-dependent); runs once via
--- prof._barFilterModelV6. Skipped when default bars have no populated
--- assignedSpells (clean install) UNLESS _importGhostMode is set.
--- Buff bars are NOT migrated: the old buff path's viewerBarKey fallback
--- already showed everything from BuffIconCooldownViewer regardless of
--- assignedSpells. Ghost buff bar cleanup is handled by EnsureGhostBars.
function mod.MigrateSpecToBarFilterModelV6()
    local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not spellRec then
        return
    end

    local specKey = mod.GetActiveSpecKey()
    if not specKey or specKey == "0" then
        return
    end

    local profileTbl = spellRec[specKey]
    if not profileTbl or profileTbl._barFilterModelV6 then
        return
    end
    -- Never consume import ghosting in the import session: this pass reads the LIVE
    -- Blizzard CDM tracked set, which an installer that rewrites Blizzard's own layout
    -- leaves unlaundered until a reload -- so return without stamping and retry next
    -- session. Fail-open: unplaced spells stay visible until then.
    if profileTbl._importGhostMode and CludesUI and CludesUI._cdmImportGhostDeferred then
        return
    end
    if not profileTbl.barSpells then
        profileTbl._barFilterModelV6 = true
        return
    end

    local p = ECME.db and ECME.db.profile
    local barList = p and p.cdmBars and p.cdmBars.bars
    if type(barList) ~= "table" then
        return
    end

    -- Step 1: orphan cleanup -- drop spell data for bars that no longer exist
    local liveBarKeys = {
        ["cooldowns"] = true,
        ["utility"] = true,
        ["buffs"] = true,
        ["__ghost_cd"] = true,
    }
    for _, edge in ipairs(barList) do
        if edge.key then
            liveBarKeys[edge.key] = true
        end
    end
    for barId in pairs(profileTbl.barSpells) do
        if not liveBarKeys[barId] then
            profileTbl.barSpells[barId] = nil
        end
    end

    -- Skip if both default CD/util bars are empty: nothing to preserve.
    -- EXCEPTION: imported layouts (_importGhostMode) always run -- a
    -- custom-bar-only layout still needs unplaced tracked spells ghosted.
    local cdBs = profileTbl.barSpells.cooldowns
    local utBs = profileTbl.barSpells.utility
    local hasCDList = cdBs and cdBs.assignedSpells and #cdBs.assignedSpells > 0
    local hasUTList = utBs and utBs.assignedSpells and #utBs.assignedSpells > 0
    if not hasCDList and not hasUTList and not profileTbl._importGhostMode then
        profileTbl._barFilterModelV6 = true
        return
    end

    -- Bail if viewer pools aren't populated yet -- migration must use the
    -- same source of truth as the route map; retry next session if empty.
    local function HasPopulatedPool()
        for _, vName in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
            local v = _G[vName]
            if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
                for _ in v.itemFramePool:EnumerateActive() do
                    return true
                end
            end
        end
        return false
    end
    if not HasPopulatedPool() then
        return
    end

    -- Step 2: build assignedSet from the LIVE bar list. Default bars
    -- (cooldowns/utility) contribute too -- their assignedSpells under the
    -- new model is "preferred order / explicit assignment" and stay visible.
    -- WoW Forever: by name too (RankName above), custom spell IDs aside. A
    -- frame reads as the highest rank known, while the layout can list any
    -- rank of the spell.
    local assignedSet = {}
    local assignedNames = RankName and {}
    for _, edge in ipairs(barList) do
        if
            edge.enabled
            and not edge.isGhostBar
            and edge.barType ~= "buffs"
            and edge.barType ~= "custom_buff"
            and edge.key ~= "buffs"
        then
            local bs = profileTbl.barSpells[edge.key]
            if bs and bs.assignedSpells then
                for _, spellRef in ipairs(bs.assignedSpells) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        StoreVariantValue(assignedSet, spellRef, true, false)
                        local n = assignedNames
                            and not (bs.customSpellIDs and bs.customSpellIDs[spellRef])
                            and RankName(spellRef)
                        if n then
                            assignedNames[n] = true
                        end
                    end
                end
            end
        end
    end

    local ghostBs = profileTbl.barSpells.__ghost_cd
    if not ghostBs then
        ghostBs = {}
        profileTbl.barSpells.__ghost_cd = ghostBs
    end
    if not ghostBs.assignedSpells then
        ghostBs.assignedSpells = {}
    end

    -- WoW Forever: one ghost entry per spell, whatever its rank.
    local existingGhost = {}
    local ghostNames = RankName and {}
    for _, spellRef in ipairs(ghostBs.assignedSpells) do
        if type(spellRef) == "number" and spellRef > 0 then
            StoreVariantValue(existingGhost, spellRef, true, false)
            local n = ghostNames and RankName(spellRef)
            if n then
                ghostNames[n] = true
            end
        end
    end

    -- Union of every CD/util spell to migrate: (1) LIVE viewer pools, catching
    -- per-spec/Edit Mode placements differing from static category; (2)
    -- STATIC category API, catching spells Blizzard currently hides by
    -- combat/buff/target state (e.g. Beacon of Light: always Essential for
    -- Holy Pally, but only pooled when relevant). Either alone misses spells.
    local sidUnion = {} -- sid -> true (deduped)

    local entryList = EnumerateCDMViewerSpells(false)
    for _, e in ipairs(entryList) do
        if _IsUsableSID(e.sid) then
            sidUnion[e.sid] = true
        end
    end

    local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local evc = Enum and Enum.CooldownViewerCategory
    if gcs and gci and evc then
        -- Full CD/utility category set so SpecAgnosticEssential/EquipSlotEssential
        -- entries become ghost/migration candidates alongside Essential/Utility.
        for cat in pairs(mod.CDM_ICON_CD_CATS) do
            local cdIDs = gcs(cat, true)
            if cdIDs then
                for _, cooldownId in ipairs(cdIDs) do
                    local details = gci(cooldownId)
                    if details then
                        local spellRef = details.overrideSpellID or details.spellID
                        if _IsUsableSID(spellRef) then
                            sidUnion[spellRef] = true
                        end
                    end
                end
            end
        end
    end

    -- Walk the union, ghost anything that isn't already assigned or ghosted.
    local addedCount = 0
    for spellRef in pairs(sidUnion) do
        local label = RankName and RankName(spellRef)
        local isAssigned = ResolveVariantValue(assignedSet, spellRef) or (label and assignedNames[label])
        local isGhosted = ResolveVariantValue(existingGhost, spellRef) or (label and ghostNames[label])
        if not isAssigned and not isGhosted then
            ghostBs.assignedSpells[#ghostBs.assignedSpells + 1] = spellRef
            StoreVariantValue(existingGhost, spellRef, true, false)
            if label then
                ghostNames[label] = true
            end
            addedCount = addedCount + 1
        end
    end

    profileTbl._barFilterModelV6 = true
    profileTbl._importGhostMode = nil -- import-authoritative ghosting done for this spec
    return addedCount
end

--- One-shot per-spec migration: merge pre-existing dormantSpells back into
--- assignedSpells at their stored slot. The old reconcile model evicted
--- "currently-unknown" spells (pet abilities, choice-node talents) into
--- dormantSpells to preserve position; the new model treats assignedSpells
--- as pure user intent, never mutated by known-ness, so dormant entries must
--- fold back at their saved positions. Wipes sd.dormantSpells afterward.
--- Flagged per-spec via prof._dormantMerged (runs once).
function mod.MergeDormantSpellsIntoAssigned()
    local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not spellRec then
        return
    end

    local specKey = mod.GetActiveSpecKey()
    if not specKey or specKey == "0" then
        return
    end

    local profileTbl = spellRec[specKey]
    if not profileTbl or profileTbl._dormantMerged then
        return
    end
    if not profileTbl.barSpells then
        profileTbl._dormantMerged = true
        return
    end

    for _barKey, bs in pairs(profileTbl.barSpells) do
        if type(bs) == "table" and type(bs.dormantSpells) == "table" then
            if not bs.assignedSpells then
                bs.assignedSpells = {}
            end

            -- Collect dormant entries sorted by saved slot (lowest first)
            -- so earlier inserts don't shift later slots.
            local returning = {}
            for spellRef, slot in pairs(bs.dormantSpells) do
                if type(spellRef) == "number" and spellRef ~= 0 and type(slot) == "number" then
                    returning[#returning + 1] = { sid = spellRef, slot = slot }
                end
            end
            table.sort(returning, function(a, b)
                return a.slot < b.slot
            end)

            -- Build dedup set for the active list so we don't double-insert
            local activeSet = {}
            for _, spellRef in ipairs(bs.assignedSpells) do
                activeSet[spellRef] = true
            end

            for _, record in ipairs(returning) do
                if not activeSet[record.sid] then
                    local insertAt = record.slot
                    if insertAt > #bs.assignedSpells + 1 then
                        insertAt = #bs.assignedSpells + 1
                    end
                    if insertAt < 1 then
                        insertAt = 1
                    end
                    table.insert(bs.assignedSpells, insertAt, record.sid)
                    activeSet[record.sid] = true
                end
            end

            bs.dormantSpells = nil
        end
    end

    profileTbl._dormantMerged = true
end

--- Lazy-seed assignedSpells from the bar's currently rendered icons. Called
--- by reorder helpers (Swap/Move) on an empty-assignedSpells bar to capture
--- the visible order so the reorder has something to manipulate.
local function EnsureBarOrderSeeded(barId, barSpells)
    if barSpells.assignedSpells and #barSpells.assignedSpells > 0 then
        return
    end
    if not barSpells.assignedSpells then
        barSpells.assignedSpells = {}
    end
    local icons = cdmBarIcons and cdmBarIcons[barId]
    if not icons then
        return
    end
    local fcCache = mod._ecmeFC
    -- Buff-family bars seed by the DISPLAYED/canonical id (what per-icon
    -- settings and preview key off), not fc.spellID (cooldownInfo base /
    -- shared ability id for buffs). CD/utility keep fc.spellID since icon
    -- IS the ability there, so the two ids coincide.
    local isBuff = mod.IsBarBuffFamily and mod.IsBarBuffFamily(barId)
    for i = 1, #icons do
        local iconTex = icons[i]
        if iconTex then
            local fc = fcCache and fcCache[iconTex]
            local spellRef
            if isBuff then
                spellRef = (mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(iconTex))
                    or (fc and fc.spellID)
            else
                spellRef = fc and fc.spellID
            end
            if type(spellRef) == "number" and spellRef > 0 then
                -- A hosted buff seeds as its MARKER: the plain id would register
                -- the same spell's COOLDOWN form on this bar.
                if fc and fc.isHostedBuff and mod.HostedBuffMarker then
                    barSpells.assignedSpells[#barSpells.assignedSpells + 1] = mod.HostedBuffMarker(spellRef)
                else
                    barSpells.assignedSpells[#barSpells.assignedSpells + 1] = spellRef
                end
            end
        end
    end
end

--- Swap two tracked spell positions
function mod.SwapTrackedSpells(barId, idx1, idx2)
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    EnsureBarOrderSeeded(barId, barSpells)
    local t = barSpells.assignedSpells
    if idx1 < 1 or idx2 < 1 then
        return false
    end
    local maxIdx = math.max(idx1, idx2)
    while #t < maxIdx do
        t[#t + 1] = 0
    end
    t[idx1], t[idx2] = t[idx2], t[idx1]
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do
        t[#t] = nil
    end
    mod._spellOrderDirty = true
    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- Move a tracked spell from one position to another (insert, not swap)
function mod.MoveTrackedSpell(barId, fromIdx, toIdx)
    if fromIdx == toIdx then
        return false
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    EnsureBarOrderSeeded(barId, barSpells)
    local t = barSpells.assignedSpells
    if fromIdx < 1 or fromIdx > #t then
        return false
    end
    if toIdx < 1 then
        toIdx = 1
    end
    while #t < toIdx do
        t[#t + 1] = 0
    end
    local val = table.remove(t, fromIdx)
    table.insert(t, toIdx, val)
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do
        t[#t] = nil
    end
    mod._spellOrderDirty = true
    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- Stable display-order key for a Blizzard-tracked buff (cooldownID) or custom.
local function BuffDisplayStableKey(spellRef, cooldownId)
    if type(cooldownId) == "number" then
        return "c" .. cooldownId
    end
    if type(spellRef) == "number" and spellRef > 0 then
        return "s" .. spellRef
    end
    return nil
end
mod.BuffDisplayStableKey = BuffDisplayStableKey

--- Spell ids associated with a stored buffDisplayOrder key ("c"..cdID / "s"..sid).
local function SpellIdsForBuffOrderKey(barKey)
    if type(barKey) ~= "string" then
        return nil
    end
    local pfx, num = string.sub(barKey, 1, 1), tonumber(string.sub(barKey, 2))
    if not num or num <= 0 then
        return nil
    end
    if pfx == "s" then
        return num
    end
    if pfx == "c" and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(num)
        if not details then
            return nil
        end
        if _IsUsableSID(details.overrideSpellID) then
            return details.overrideSpellID
        end
        if _IsUsableSID(details.spellID) then
            return details.spellID
        end
    end
    return nil
end

--- True when a live buff entry matches a stored buffDisplayOrder key, including
--- hero-talent / override variants (cooldownID can drift across talent swaps).
local function BuffOrderKeyMatchesEntry(barKey, spellRef, cooldownId, widget)
    if not barKey then
        return false
    end
    local stable = BuffDisplayStableKey(spellRef, cooldownId)
    if stable and stable == barKey then
        return true
    end
    local storedSid = SpellIdsForBuffOrderKey(barKey)
    if not storedSid then
        return false
    end
    if spellRef and IsVariantOf(storedSid, spellRef) then
        return true
    end
    if widget and mod.GetCanonicalSpellIDForFrame then
        local canon = mod.GetCanonicalSpellIDForFrame(widget)
        if canon and IsVariantOf(storedSid, canon) then
            return true
        end
    end
    if cooldownId and type(cooldownId) == "number" and mod._cdmCleanSidByCDID then
        local clean = mod._cdmCleanSidByCDID[cooldownId]
        if clean and IsVariantOf(storedSid, clean) then
            return true
        end
    end
    return false
end

--- Enumerate default-buffs-bar entries (viewer pool + this bar's customs/items),
--- minus spells diverted to other buff-family or hosted CD/utility bars.
function mod.CollectDefaultBuffTrackEntries()
    -- Variant-aware (base/override family), not a plain sid set: a claimed
    -- buff's stored id and the id this same viewer slot enumerates as later
    -- can legitimately differ (a talent-override swap, or a fresh clean-cache
    -- forcing GetCanonicalSpellIDForFrame down its cooldownInfo fallback --
    -- see the comment there). An exact-number set misses that drift and the
    -- claimed buff reappears here as a phantom duplicate of the other bar's
    -- entry. StoreVariantValue/ResolveVariantValue are the same mechanism
    -- RebuildSpellRouteMap and ns.GetCDMSpellsForBar already use to answer
    -- "is this the same buff" everywhere else in this file.
    local diverted = {}
    local divertedCd = {} -- cooldownID-level diversions (collided-buff slots)
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, otherBd in ipairs(p.cdmBars.bars) do
            if otherBd.enabled and otherBd.key ~= "buffs" then
                local otherSd = mod.GetBarSpellData(otherBd.key)
                if otherBd.barType == "buffs" or otherBd.barType == "custom_buff" then
                    if otherSd and otherSd.assignedSpells then
                        for _, spellRef in ipairs(otherSd.assignedSpells) do
                            if type(spellRef) == "number" and spellRef > 0 then
                                StoreVariantValue(diverted, spellRef, true, false)
                            end
                        end
                    end
                    local otherClaims = otherSd and mod.CollectCdClaimSet(otherSd)
                    if otherClaims then
                        for cooldownId in pairs(otherClaims) do
                            divertedCd[cooldownId] = true
                        end
                    end
                elseif otherSd and otherSd.hostedBuffSpellIDs then
                    for spellRef in pairs(otherSd.hostedBuffSpellIDs) do
                        if type(spellRef) == "number" and spellRef > 0 then
                            StoreVariantValue(diverted, spellRef, true, false)
                        end
                    end
                end
            end
        end
    end

    if mod.PruneEquipmentBuffRows then
        mod.PruneEquipmentBuffRows()
    end
    local out = {}
    local seenSet = {}
    local entryList = mod.EnumerateCDMViewerSpells and mod.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entryList) do
        -- Dedup on the stable (cooldownID-derived) key, not e.sid: two viewer
        -- slots can share a spellID but are distinct cooldownIDs; keying on
        -- sid would re-merge what EnumerateCDMViewerSpells keeps separate.
        local barKey = BuffDisplayStableKey(e.sid, e.cdID)
        -- Native equipment ON-USE rows (equipSlot + category EquipSlotEssential)
        -- are preset-lane-only: never surface them as default-bar buff entries.
        -- Tracked trinket PROC BUFF rows (equipSlot + category EquipSlotTracked)
        -- are first-class buff citizens (user directive 2026-08-16): Blizzard's
        -- CDM lets users track a trinket's buff like any spell, and our buff
        -- bars must mirror that. Field-probed 2026-08-16: buffSlot=1 rides
        -- BOTH categories (and plain cat-2 rows), so CATEGORY is the only
        -- reliable discriminator.
        local eqInfo = e.cdID
            and C_CooldownViewer
            and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(e.cdID)
        local eqTracked = Enum
                and Enum.CooldownViewerCategory
                and Enum.CooldownViewerCategory.EquipSlotTracked
            or 8
        if
            e.sid
            and not (eqInfo and eqInfo.equipSlot and eqInfo.category ~= eqTracked)
            and not ResolveVariantValue(diverted, e.sid)
            and not (e.cdID and divertedCd[e.cdID])
            and barKey
            and not seenSet[barKey]
        then
            seenSet[barKey] = true
            out[#out + 1] = {
                key = barKey,
                sid = e.sid,
                cdID = e.cdID,
                layoutIndex = e.layoutIndex or 0,
            }
        end
    end

    local sdSelf = mod.GetBarSpellData("buffs")
    if sdSelf and sdSelf.assignedSpells then
        local extraRec = 5000
        if sdSelf.spellDurations then
            for _, spellRef in ipairs(sdSelf.assignedSpells) do
                if
                    type(spellRef) == "number"
                    and spellRef > 0
                    and (sdSelf.spellDurations[spellRef] or 0) > 0
                then
                    local barKey = BuffDisplayStableKey(spellRef, nil)
                    if barKey and not seenSet[barKey] then
                        seenSet[barKey] = true
                        out[#out + 1] = { key = barKey, sid = spellRef, cdID = nil, layoutIndex = extraRec }
                        extraRec = extraRec + 1
                    end
                end
            end
        end
        -- Aura-tracked customs (customSpellIDs tag, NO stored duration): same
        -- slot treatment as the legacy cast-timer customs above.
        if sdSelf.customSpellIDs then
            for _, spellRef in ipairs(sdSelf.assignedSpells) do
                if
                    type(spellRef) == "number"
                    and spellRef > 0
                    and sdSelf.customSpellIDs[spellRef]
                    and not (sdSelf.spellDurations and (sdSelf.spellDurations[spellRef] or 0) > 0)
                then
                    local barKey = BuffDisplayStableKey(spellRef, nil)
                    if barKey and not seenSet[barKey] then
                        seenSet[barKey] = true
                        out[#out + 1] = { key = barKey, sid = spellRef, cdID = nil, layoutIndex = extraRec }
                        extraRec = extraRec + 1
                    end
                end
            end
        end
        extraRec = 6000
        for _, spellRef in ipairs(sdSelf.assignedSpells) do
            if type(spellRef) == "number" and spellRef <= -100 then
                local barKey = BuffDisplayStableKey(spellRef, nil)
                if barKey and not seenSet[barKey] then
                    seenSet[barKey] = true
                    out[#out + 1] = { key = barKey, sid = spellRef, cdID = nil, layoutIndex = extraRec }
                    extraRec = extraRec + 1
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then
            return a.layoutIndex < b.layoutIndex
        end
        return (a.key or "") < (b.key or "")
    end)
    return out
end

-- Same-spellID buff disambiguation (e.g. Diabolist: Demonic Art vs Diabolic Ritual):
-- Blizzard can report the SAME spellID on two DIFFERENT buff-viewer cooldownIDs,
-- colliding onto one spellID-keyed settings entry. A COLLIDED slot keys by
-- "c"..cooldownID instead, giving each its own entry -- non-collided buffs keep spellID
-- (survives talent swaps; cooldownID drifts). Collided slots trade that: session-stable
-- but may not follow a talent-loadout swap, unavoidable given the shared identity.

--- Set of canonical spellIDs that map to 2+ distinct buff-viewer cooldownIDs.
--- Cold path (settings popup); recomputed per call from the live viewer pool.
function mod.CollidedBuffSids()
    local counts, out = {}, {}
    local entryList = mod.EnumerateCDMViewerSpells and mod.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entryList) do
        if e.sid and type(e.cdID) == "number" then
            counts[e.sid] = (counts[e.sid] or 0) + 1
        end
    end
    for spellRef, n in pairs(counts) do
        if n > 1 then
            out[spellRef] = true
        end
    end
    return out
end

function mod.IsCollidedBuffSid(spellRef)
    if type(spellRef) ~= "number" or spellRef <= 0 then
        return false
    end
    return mod.CollidedBuffSids()[spellRef] == true
end

--- Buff slots claimed by cooldownID instead of spellID: collided pairs, and
--- tracked trinket proc rows (EquipSlotTracked). A trinket row reads no spellID
--- while its proc is down, so a sid claim can neither route it after a reload
--- nor be told apart from an equipment use-spell by the prune; its cooldownID
--- is fixed per equipment slot, so the usual cooldownID drift does not apply.
local function IsTrackedTrinketRow(cooldownId)
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local details = gci and gci(cooldownId)
    local cat = details and details.category
    if type(cat) ~= "number" or (issecretvalue and issecretvalue(cat)) then
        return false
    end
    return cat == (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.EquipSlotTracked or 8)
end

function mod.ClaimBuffByCdID(spellRef, cooldownId)
    if type(cooldownId) ~= "number" or cooldownId <= 0 then
        return false
    end
    return IsTrackedTrinketRow(cooldownId) or mod.IsCollidedBuffSid(spellRef)
end

-- Claiming a trinket row by cooldownID drops any spellID claim of it (a bar
-- entry or a hosted marker), so it never shows twice. Collided pairs keep
-- theirs: that spellID also names the twin slot.
local function DropTrinketSidClaims(cooldownId, spellRef)
    if
        type(spellRef) ~= "number"
        or spellRef <= 0
        or not IsTrackedTrinketRow(cooldownId)
        or mod.IsCollidedBuffSid(spellRef)
    then
        return
    end
    local p = ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then
        return
    end
    for _, b in ipairs(p.cdmBars.bars) do
        if b.barType ~= "custom_buff" then
            if mod.IsBarBuffFamily(b) then
                mod.RemoveSpellFromBar(b.key, spellRef)
            else
                mod.RemoveSpellFromBar(b.key, mod.HostedBuffMarker(spellRef))
            end
        end
    end
end

-- Runtime hot-path gate: true only when the current spec's buffs store holds at least
-- one "c"..cooldownID key. Cached by store-table identity, so a spec/profile swap
-- (different store table) recomputes for free with no explicit invalidation hook.
local _cdKeyGate
function mod.BuffFamHasCdKey(storage)
    -- Accept caller's store (runtime resolver already holds it) to skip a
    -- second spec/profile lookup per buff-frame resolve.
    storage = storage or (mod.GetSpellSettingsStore and mod.GetSpellSettingsStore("buffs"))
    if not storage then
        return false
    end
    if _cdKeyGate and _cdKeyGate.store == storage then
        return _cdKeyGate.has
    end
    local hit = false
    for k in pairs(storage) do
        if type(k) == "string" and string.byte(k, 1) == 99 then
            hit = true
            break
        end -- 'c'
    end
    _cdKeyGate = { store = storage, has = hit }
    return hit
end

--- Called when a "c"..cooldownID buff entry is first persisted, so the hot-path
--- gate flips on without waiting for the store-identity cache to expire.
function mod.MarkBuffFamHasCdKey()
    local storage = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore("buffs")
    _cdKeyGate = { store = storage, has = true }
    -- The cdID-key gate feeds resolution: retire memoized results.
    mod._cdmResGen = (mod._cdmResGen or 0) + 1
end

--- Reorder present keys to match Blizzard viewer order while absent keys (talent
--- gaps, untalented catalog entries) keep their stored slots.
local function SyncPresentBuffOrderToBlizzard(sequence, present, entryList)
    if not sequence or #sequence == 0 or not entryList or #entryList == 0 then
        return sequence
    end
    local blizzRank = {}
    for i, e in ipairs(entryList) do
        if blizzRank[e.key] == nil then
            blizzRank[e.key] = i
        end
    end
    local sortedPresent = {}
    for _, barKey in ipairs(sequence) do
        if present[barKey] then
            sortedPresent[#sortedPresent + 1] = barKey
        end
    end
    table.sort(sortedPresent, function(a, b)
        return (blizzRank[a] or 99999) < (blizzRank[b] or 99999)
    end)
    local pi = 1
    local synced = {}
    for _, barKey in ipairs(sequence) do
        if present[barKey] then
            synced[#synced + 1] = sortedPresent[pi]
            pi = pi + 1
        else
            synced[#synced + 1] = barKey
        end
    end
    return synced
end

--- Dirty flag gating the reconcile in the hot reanchor path: the tracked
--- CATALOG (viewer pool incl. inactive + diversions) only changes on rebuild/
--- repopulate, not on mere buff appear/disappear, so combat reanchors skip
--- the full enumeration/sort. Set true wherever composition can change
--- (FullCDMRebuild, RepopulateFromBlizzard); an unreconciled newcomer still
--- renders via the layoutIndex spillover fallback until the next rebuild.
--- Starts true for the login seed pass.
mod._cdmBuffOrderDirty = true

--- Keep stored buffDisplayOrder across talent/spec gaps, seed on first stable
--- pass, and insert newly-tracked buffs by Blizzard layoutIndex (not at tail).
function mod.ReconcileBuffDisplayOrder()
    if mod._cdmSpecRebuildStale then
        return
    end
    local barSpells = mod.GetBarSpellData("buffs")
    if not barSpells then
        return
    end

    local sequence = barSpells.buffDisplayOrder
    if sequence and type(sequence[1]) == "number" then
        barSpells.buffDisplayOrder = nil
        sequence = nil
    end

    local entryList = mod.CollectDefaultBuffTrackEntries()
    if #entryList == 0 then
        return
    end

    local present = {}
    for _, e in ipairs(entryList) do
        if present[e.key] == nil then
            present[e.key] = { sid = e.sid, cdID = e.cdID, layoutIndex = e.layoutIndex or 0 }
        end
    end

    if not sequence or #sequence == 0 then
        local seeded = {}
        for _, e in ipairs(entryList) do
            seeded[#seeded + 1] = e.key
        end
        barSpells.buffDisplayOrder = seeded
        mod._spellOrderDirty = true
        return
    end

    local nextOrder, seenSet = {}, {}
    for _, barKey in ipairs(sequence) do
        if not seenSet[barKey] then
            seenSet[barKey] = true
            nextOrder[#nextOrder + 1] = barKey
        end
    end

    local newcomers = {}
    for _, e in ipairs(entryList) do
        if not seenSet[e.key] then
            newcomers[#newcomers + 1] = e
        end
    end
    if #newcomers > 0 then
        table.sort(newcomers, function(a, b)
            if a.layoutIndex ~= b.layoutIndex then
                return a.layoutIndex < b.layoutIndex
            end
            return (a.key or "") < (b.key or "")
        end)
        local blizzRank = {}
        for i, e in ipairs(entryList) do
            blizzRank[e.key] = i
        end
        for _, e in ipairs(newcomers) do
            local insertAt = #nextOrder + 1
            for i, barKey in ipairs(nextOrder) do
                local rank = blizzRank[barKey]
                if rank and rank > blizzRank[e.key] then
                    insertAt = i
                    break
                end
            end
            table.insert(nextOrder, insertAt, e.key)
            seenSet[e.key] = true
        end
    end

    if not barSpells._buffDisplayOrderUserModified then
        nextOrder = SyncPresentBuffOrderToBlizzard(nextOrder, present, entryList)
    end

    local changed = (#nextOrder ~= #sequence)
    if not changed then
        for i = 1, #nextOrder do
            if nextOrder[i] ~= sequence[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        barSpells.buffDisplayOrder = nextOrder
        mod._spellOrderDirty = true
    end
end

--- Resolve a buff bar entry's sort index from buffDisplayOrder (variant-aware).
function mod.ResolveBuffDisplaySortIndex(record, buffOrder, isDefaultBuffs)
    if not buffOrder or not record then
        return nil
    end
    if isDefaultBuffs then
        local cd = record.frame and record.frame.cooldownID
        local spellRef = record.spellID
        -- Steady state: direct stable-key match, O(1) zero-alloc. The variant
        -- scan below allocates per miss (calls GetCooldownViewerCooldownInfo),
        -- so it's reserved for genuine talent-gap frames whose cooldownID drifted.
        local stable = BuffDisplayStableKey(spellRef, cd)
        local direct = stable and buffOrder[stable]
        if direct then
            return direct
        end
        for barKey, position in pairs(buffOrder) do
            if BuffOrderKeyMatchesEntry(barKey, spellRef, cd, record.frame) then
                return position
            end
        end
        return nil
    end
    local ef = record.frame
    -- Collided-buff slot (cd-claim marker, see ns.CdClaimMarker): both runtime
    -- frames of the pair share one spellID, so a spellID-keyed lookup can't
    -- tell them apart. Check cooldownID first (same stable-key convention as
    -- the isDefaultBuffs branch above).
    local cdKey = ef and ef.cooldownID and BuffDisplayStableKey(nil, ef.cooldownID)
    if cdKey and buffOrder[cdKey] then
        return buffOrder[cdKey]
    end
    local canon = ef and mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(ef)
    return (canon and buffOrder[canon])
        or (record.spellID and buffOrder[record.spellID])
        or (record.baseSpellID and buffOrder[record.baseSpellID])
end

--- Default buffs bar DISPLAY-ORDER reorder helpers. assignedSpells is shared
--- with routing + custom injection (RebuildSpellRouteMap Pass 4 diverts it at
--- highest priority), so it can't carry the full buff order without
--- clobbering diverted buffs. Order instead lives in buffDisplayOrder: an
--- array of STABLE keys ("c"..cooldownID for Blizzard buffs, "s"..spellID for
--- customs) that only sort/preview/drag read -- routing never touches it.
--- cooldownID (not spellID) is used because a buff's canonical id flips
--- between ability/aura form across active<->inactive.
--- KEY-BASED, not index-based: ABSENT keys keep their slot (talent-gapped
--- buffs reclaim position on return); preview renders only PRESENT keys, so a
--- slot index doesn't map 1:1 onto the array past any gap. Callers pass
--- rendered slots' stable keys (pf._buffSlotKeys), resolved live at call time.
local function BuffOrderIndexOf(t, barKey)
    for i = 1, #t do
        if t[i] == barKey then
            return i
        end
    end
    return nil
end

local function FinishBuffOrderWrite(barSpells)
    barSpells._buffDisplayOrderUserModified = true
    mod._spellOrderDirty = true
    local widget = cdmBarFrames["buffs"]
    if widget then
        widget._blizzCache = nil
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
end

function mod.SwapBuffDisplayKeys(key1, key2)
    if not key1 or not key2 or key1 == key2 then
        return false
    end
    local barSpells = mod.GetBarSpellData("buffs")
    local t = barSpells and barSpells.buffDisplayOrder
    if not t then
        return false
    end
    local i1, i2 = BuffOrderIndexOf(t, key1), BuffOrderIndexOf(t, key2)
    if not i1 or not i2 then
        return false
    end
    t[i1], t[i2] = t[i2], t[i1]
    FinishBuffOrderWrite(barSpells)
    return true
end

--- Move dragKey so it renders immediately before beforeKey; nil beforeKey
--- appends after everything (drop past the last rendered slot).
function mod.MoveBuffDisplayKey(dragKey, beforeKey)
    if not dragKey or dragKey == beforeKey then
        return false
    end
    local barSpells = mod.GetBarSpellData("buffs")
    local t = barSpells and barSpells.buffDisplayOrder
    if not t then
        return false
    end
    local from = BuffOrderIndexOf(t, dragKey)
    if not from then
        return false
    end
    local val = table.remove(t, from)
    local to
    if beforeKey then
        to = BuffOrderIndexOf(t, beforeKey)
    end
    if not to then
        to = #t + 1
    end
    table.insert(t, to, val)
    FinishBuffOrderWrite(barSpells)
    return true
end

--- Single source of truth for "what type is this bar" / "what family is it in".
--- The 3 default bars have barType stamped in DEFAULTS, but legacy installs
--- may have nil barType; both helpers fall back to key-based inference.
--- Accepts either a bar key (string) or a bar data table (.key/.barType).
local function ResolveBarType(bdOrKey)
    local edge, barKey
    if type(bdOrKey) == "table" then
        edge = bdOrKey
        barKey = edge.key
    else
        barKey = bdOrKey
        edge = barDataByKey[barKey]
    end

    if edge and edge.barType then
        return edge.barType
    end

    if barKey == "cooldowns" then
        return "cooldowns"
    end
    if barKey == "utility" then
        return "utility"
    end
    if barKey == "buffs" then
        return "buffs"
    end

    return nil
end
mod.GetBarType = ResolveBarType

--- True if a bar is in the "buff" family (default buffs bar or ghost buffs
--- bar; custom_buff is NOT a buff bar, it's a separate aura system). Used by
--- AddTrackedSpell's auto-move sweep, render path, route map, and picker
--- source selection. __ghost_cd is always non-buff family.
local function IsBarBuffFamily(bdOrKey)
    local edge, barKey
    if type(bdOrKey) == "table" then
        edge = bdOrKey
        barKey = edge.key
    else
        barKey = bdOrKey
        edge = barDataByKey[barKey]
    end

    if barKey == "__ghost_cd" then
        return false
    end

    local barKind = ResolveBarType(edge or barKey)
    return barKind == "buffs"
end
mod.IsBarBuffFamily = IsBarBuffFamily

-- Old local alias for backward compat within this file
local GetBarType = ResolveBarType

-- Centralized Spell Assignment Checks -- used by pickers, overlay system,
-- and options: (1) is a spell already on ANY bar (CDM + TBB)? (2) is a
-- spell tracked in the correct Blizzard CDM section for a bar type?

-- (SpellUsedOnAnyOtherBar deleted: unneeded for CD/util/buff custom bar
-- pickers since AddTrackedSpell auto-moves the spell from any other bar in
-- the same family -- adding is always a "claim it", never a "blocked" case.)

--- Same check for TBB (Tracking Bars vs other Tracking Bars only). trackType
--- scopes to one family: nil/"buff" = buff bars, "cooldown" = cooldown bars.
--- A different track type never blocks a pick (distinct, legitimate picks).
function mod.SpellUsedOnAnyOtherTBB(spellId, excludeIdx, trackType)
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if not tbb or not tbb.bars then
        return nil
    end
    for i, conf in ipairs(tbb.bars) do
        if i ~= excludeIdx then
            if (conf.trackType or "buff") ~= (trackType or "buff") then
                -- Different track type never blocks a pick.
            else
                if conf.spellID and conf.spellID == spellId then
                    return conf.name or ("Tracking Bar " .. i)
                end
                if conf.spellIDs then
                    for _, spellRef in ipairs(conf.spellIDs) do
                        if spellRef == spellId then
                            return conf.name or ("Tracking Bar " .. i)
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- Check if a spell is tracked in the correct Blizzard CDM section for a bar
--- type (true = properly tracked, no popup/overlay needed): CD/utility bar
--- needs Essential/Utility viewer; buff bar needs BuffIcon viewer (not just
--- Tracked Bars); TBB needs BuffBar viewer (not just Tracked Buffs).
--- Cached lookup sets, rebuilt once per RebuildCDMSpellCaches() call instead
--- of full category scans per-frame.
local _knownSpellSet = {} -- learned spells (cat, false)
local _allSpellSet = {} -- all spells including unlearned (cat, true)
local _cdmSpellCacheDirty = true

function mod.MarkCDMSpellCacheDirty()
    _cdmSpellCacheDirty = true
end

local function RebuildCDMSpellCaches()
    if not _cdmSpellCacheDirty then
        return
    end
    _cdmSpellCacheDirty = false
    wipe(_knownSpellSet)
    wipe(_allSpellSet)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return
    end
    local gci = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then
        return
    end
    for cat = 0, 3 do
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if knownIDs then
            for _, cooldownId in ipairs(knownIDs) do
                local details = gci(cooldownId)
                if details then
                    if details.spellID and details.spellID > 0 then
                        _knownSpellSet[details.spellID] = true
                    end
                    if details.overrideSpellID and details.overrideSpellID > 0 then
                        _knownSpellSet[details.overrideSpellID] = true
                    end
                    local spellRef = mod.ResolveInfoSpellID(details)
                    if spellRef and spellRef > 0 then
                        _knownSpellSet[spellRef] = true
                    end
                end
            end
        end
        local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if allIDs then
            for _, cooldownId in ipairs(allIDs) do
                local details = gci(cooldownId)
                if details then
                    if details.spellID and details.spellID > 0 then
                        _allSpellSet[details.spellID] = true
                    end
                    if details.overrideSpellID and details.overrideSpellID > 0 then
                        _allSpellSet[details.overrideSpellID] = true
                    end
                    local spellRef = mod.ResolveInfoSpellID(details)
                    if spellRef and spellRef > 0 then
                        _allSpellSet[spellRef] = true
                    end
                end
            end
        end
    end
end
mod.RebuildCDMSpellCaches = RebuildCDMSpellCaches

function mod.IsSpellKnownInCDM(spellId)
    if not spellId or spellId <= 0 then
        return false
    end
    RebuildCDMSpellCaches()
    return _knownSpellSet[spellId] == true
end

--- Add a preset group to a bar. custom_buff bars: adds ALL spell IDs as plain
--- entries (each gets its own C_UnitAuras check -- only the active variant
--- shows). Other bars: adds primary ID with duration/group metadata.
function mod.AddPresetToBar(barId, preset)
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    if not barSpells.assignedSpells then
        barSpells.assignedSpells = {}
    end
    local spellArray = barSpells.assignedSpells

    -- Buff-family bars use the same cast-timer custom-buff path as custom_buff
    -- (Auras) bars: store primary spellID + hardcoded duration; the buff
    -- phase injects an own-frame and the buff tick drives it.
    local edge = barDataByKey[barId]
    local isCustomBuff = edge and (edge.barType == "custom_buff" or edge.barType == "buffs")

    if isCustomBuff then
        if preset.glowBased then
            -- Glow-based presets removed (Time Spiral etc.)
            return false
        else
            -- Check ALL preset members against existing spells so partial
            -- overlap is rejected (e.g. variant 701 already on bar blocks
            -- adding preset {700, 701, 702}).
            for _, spellRef in ipairs(preset.spellIDs) do
                for _, existing in ipairs(spellArray) do
                    if existing == spellRef then
                        return false, "exists"
                    end
                end
            end
            local primaryId = preset.spellIDs[1]
            spellArray[#spellArray + 1] = primaryId
            if not barSpells.spellDurations then
                barSpells.spellDurations = {}
            end
            barSpells.spellDurations[primaryId] = preset.duration or 30
        end
    else
        -- Legacy: add primary ID with duration/group metadata
        local primaryId = preset.spellIDs[1]
        for _, existing in ipairs(spellArray) do
            if existing == primaryId then
                return false, "exists"
            end
        end
        spellArray[#spellArray + 1] = primaryId
        if not barSpells.customSpellDurations then
            barSpells.customSpellDurations = {}
        end
        barSpells.customSpellDurations[primaryId] = preset.duration
        if not barSpells.customSpellGroups then
            barSpells.customSpellGroups = {}
        end
        for _, spellRef in ipairs(preset.spellIDs) do
            barSpells.customSpellGroups[spellRef] = primaryId
        end
    end

    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    return true
end

--- Is any member of this preset already on the bar? The inverse of the "exists"
--- guard above, so the picker greys exactly what an add would reject: a preset
--- with variant ids (the invisibility potions, the two faction lust ids) counts
--- as present no matter which member is stored.
function mod.IsPresetOnBar(barId, preset)
    local barSpells = mod.GetBarSpellData(barId)
    local spellArray = barSpells and barSpells.assignedSpells
    if not spellArray or type(preset.spellIDs) ~= "table" then
        return false
    end
    for _, spellRef in ipairs(preset.spellIDs) do
        for _, existing in ipairs(spellArray) do
            if existing == spellRef then
                return true
            end
        end
    end
    return false
end

--- Add a tracked spell (spellID) to a bar. Picker-driven add: always treated
--- as "claim this spell for the target bar" -- auto-removed from EVERY other
--- bar in the same family (default + custom + matching ghost) first. One
--- spell, one home, always. Picker passes IDs from GetCanonicalSpellIDForFrame
--- (already in route-map/reanchor form; no override-to-base normalization
--- needed here).
function mod.AddTrackedSpell(barId, ident)
    -- Non-zero integer required. Positive = real spell; negative = injection
    -- marker Phase 3 of CollectAndReanchor uses for custom frames (trinkets
    -- at -13/-14, item presets at <= -100) -- both valid.
    if type(ident) ~= "number" or ident == 0 then
        return false
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    if not barSpells.assignedSpells then
        barSpells.assignedSpells = {}
    end

    -- Dedup against THIS bar: variant-aware for positive IDs; exact-match
    -- linear scan for negatives (FindVariantIndex bails on non-positives).
    if ident > 0 then
        if FindVariantIndex(barSpells.assignedSpells, ident) then
            return false
        end
    else
        for _, existing in ipairs(barSpells.assignedSpells) do
            if existing == ident then
                return false
            end
        end
    end

    -- Auto-move from any other bar in the same family: a spell has ONE home
    -- at a time, so adding to bar X removes it from every other bar in the
    -- family (incl. ghost, so a hidden spell auto-restores when claimed
    -- elsewhere). Family = ns.IsBarBuffFamily; custom_buff bars are a
    -- separate system, never swept. Negative IDs sweep within whichever
    -- family the target bar belongs to (no positivity gate): trinkets stay
    -- on CD/util bars, custom items sweep only their own family.
    local targetBd = barDataByKey[barId]
    local p = ECME.db.profile
    local targetIsBuff = IsBarBuffFamily(barId)
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= barId and b.barType ~= "custom_buff" then
                if IsBarBuffFamily(b) == targetIsBuff then
                    mod.RemoveSpellFromBar(b.key, ident)
                end
            end
        end
    end

    -- Top-row insertion for multi-row bars.
    local curCount = #barSpells.assignedSpells
    local stride, _, topRowCount = ComputeTopRowStride(targetBd or {}, curCount)
    if stride < 1 then
        stride = 1
    end
    local newCount = curCount + 1
    local newStride, _, newTopRow = ComputeTopRowStride(targetBd or {}, newCount)
    if newStride < 1 then
        newStride = 1
    end
    if newStride == stride and newTopRow > topRowCount then
        table.insert(barSpells.assignedSpells, topRowCount + 1, ident)
    else
        barSpells.assignedSpells[newCount] = ident
    end
    mod._spellOrderDirty = true

    if barSpells.removedSpells then
        barSpells.removedSpells[ident] = nil
    end
    -- Picked from the picker: the entry is the preset's own (an entry the reseed
    -- listed for Blizzard's row of this item stood for that row alone).
    if barSpells.nativeItems then
        barSpells.nativeItems[ident] = nil
    end

    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    if mod.RebuildSpellRouteMap then
        mod.RebuildSpellRouteMap()
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- An item entry leaving a CD/utility bar by a user removal: one Blizzard's own
--- row can render under (a potion or healthstone, the preset's nativeCategory) is
--- ghosted like a racial, so the row routes to the ghost bar and stays hidden
--- instead of coming back at the next reseed; the next add from the picker
--- un-ghosts it (AddTrackedSpell's sweep). Any mark that the entry stood for
--- Blizzard's row goes with it. Nothing for every other entry.
function mod.NoteItemEntryRemoved(barSpells, barKey)
    if not mod.IsItemPresetKey(barKey) then
        return
    end
    if barSpells and barSpells.nativeItems then
        barSpells.nativeItems[barKey] = nil
    end
    local pr = mod.ItemPresetForKey(barKey)
    if not (pr and pr.nativeCategory) then
        return
    end
    local gsd = mod.GetBarSpellData(mod.GHOST_CD_BAR_KEY)
    if not gsd then
        return
    end
    if not gsd.assignedSpells then
        gsd.assignedSpells = {}
    end
    for _, g in ipairs(gsd.assignedSpells) do
        if g == barKey then
            return
        end
    end
    gsd.assignedSpells[#gsd.assignedSpells + 1] = barKey
end

--- An entry the reseed listed for Blizzard's own row of an item (sd.nativeItems)
--- picked again from the picker: it becomes the preset's own entry, whose frame
--- stands in once Blizzard's row is gone. False for any other entry.
function mod.AdoptNativeItemEntry(barId, barKey)
    local barSpells = mod.GetBarSpellData(barId)
    if not (barSpells and barSpells.nativeItems and barSpells.nativeItems[barKey]) then
        return false
    end
    barSpells.nativeItems[barKey] = nil
    if next(barSpells.nativeItems) == nil then
        barSpells.nativeItems = nil
    end
    mod._spellOrderDirty = true
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- Track a single buff-viewer SLOT (cooldownID) on a buff-family bar.
--- Collision escape hatch: two viewer slots can share one spellID, making
--- AddTrackedSpell's variant dedup reject the second slot by sid. Claiming via
--- a cd-claim MARKER (ns.CdClaimMarker, distinct negative id per cooldownID)
--- sidesteps that while reusing AddTrackedSpell's plumbing unchanged, and
--- gives the claim a real assignedSpells index (drags/reorders/removes like
--- any entry). Gated by ns.ClaimBuffByCdID: every other buff keeps the sid
--- path (survives talent swaps). The default "buffs" bar enumerates the live
--- viewer pool, never assignedSpells, so adding a slot to it releases every
--- other buff bar's claim on that slot instead.
function mod.AddTrackedBuffByCdID(barId, cooldownId, spellRef)
    if type(cooldownId) ~= "number" or cooldownId <= 0 then
        return false
    end
    DropTrinketSidClaims(cooldownId, spellRef)
    local marker = mod.CdClaimMarker(cooldownId)
    if barId == "buffs" then
        local p = ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, b in ipairs(p.cdmBars.bars) do
                if b.key ~= "buffs" and b.barType ~= "custom_buff" and IsBarBuffFamily(b) then
                    mod.RemoveSpellFromBar(b.key, marker)
                end
            end
        end
        if mod.RebuildSpellRouteMap then
            mod.RebuildSpellRouteMap()
        end
        if mod.QueueReanchor then
            mod.QueueReanchor()
        end
        return true
    end
    return mod.AddTrackedSpell(barId, marker)
end

--- Place a BUFF on a CD/utility bar. HOSTED: RebuildSpellRouteMap diverts its
--- real Blizzard buff-viewer frame onto this bar; reanchor reparents it into
--- the layout when active / a placeholder when inactive -- like the buffs bar,
--- just on CD/util. Blizzard's CDM stays the source of truth, so auras, DoTs,
--- totems and pet-summons all work with no detection code. NOT a custom
--- injected spell -- Phase 3 draws no frame of its own over Blizzard's; only a
--- Custom Spell ID Blizzard does not track (customSpellIDs tag, no hosted frame
--- or placeholder on the bar) is drawn by an aura icon of ours
--- (CUI_CDM_AuraIcons.lua). Additive: only our own data table is written
--- (variant-keyed).
function mod.AddBuffToCDUtilBar(barId, spellId)
    if type(spellId) ~= "number" or spellId <= 0 then
        return false
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    -- Already hosted (marker entry, or legacy plain entry pre-marker model): no-op.
    if
        barSpells.hostedBuffSpellIDs
        and barSpells.hostedBuffSpellIDs[spellId]
        and barSpells.assignedSpells
        and (
            mod.ListHasHostedMarker(barSpells.assignedSpells, spellId)
            or mod.FindVariantIndexInList(barSpells.assignedSpells, spellId)
        )
    then
        return true
    end
    -- Claim via the hosted MARKER, never the plain spellID (the COOLDOWN
    -- form's identity; one spell can be both cooldown and buff, same id).
    -- The marker gives the buff its own slot to coexist and reorder
    -- independently; AddTrackedSpell auto-moves it off other CD/util bars.
    mod.AddTrackedSpell(barId, mod.HostedBuffMarker(spellId))
    -- Flag keyed by picked/canonical spellID so route-map/drop-pass/self-heal
    -- match it directly; the route map expands variants on write, so the
    -- LIVE frame resolves regardless of talent/override form.
    if not barSpells.hostedBuffSpellIDs then
        barSpells.hostedBuffSpellIDs = {}
    end
    barSpells.hostedBuffSpellIDs[spellId] = true
    -- Host flip changes resolution routing: retire memoized results.
    mod._cdmResGen = (mod._cdmResGen or 0) + 1
    if mod.RebuildSpellRouteMap then
        mod.RebuildSpellRouteMap()
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- "Replace with Buff": name a tracked buff whose viewer frame takes this
--- cooldown's slot while the aura is active (nil buffSID clears it). Per-spell
--- only, in the cooldown family store, so it rides the spec/override capture
--- like every other per-spell key. No marker and no hosted flag: the route
--- map's Pass 3c diverts the buff and the collect pass swaps the frames. One
--- buff may stand in for one cooldown per bar; the same buff on another entry
--- is cleared here. buffCdID names a cd-claimed collided slot.
function mod.SetCooldownBuffReplacement(barId, targetSID, buffSID, buffCdID)
    if type(targetSID) ~= "number" or targetSID <= 0 then
        return false
    end
    if buffSID ~= nil and (type(buffSID) ~= "number" or buffSID <= 0) then
        return false
    end
    local storage = mod.GetSpellSettingsStore(barId, true)
    if not storage then
        return false
    end
    if buffSID then
        for barKey, other in pairs(storage) do
            if barKey ~= targetSID and type(other) == "table" then
                local oSid = rawget(other, "replaceBuffID")
                local oCd = rawget(other, "replaceBuffCdID")
                local same = (buffCdID and oCd == buffCdID)
                    or (not buffCdID and not oCd and oSid and IsVariantOf(oSid, buffSID))
                if same then
                    other.replaceBuffID = nil
                    other.replaceBuffCdID = nil
                    if next(other) == nil then
                        storage[barKey] = nil
                    end
                end
            end
        end
    end
    local ss = storage[targetSID]
    if not ss then
        if not buffSID then
            return true
        end
        ss = {}
        storage[targetSID] = ss
    end
    ss.replaceBuffID = buffSID
    ss.replaceBuffCdID = buffSID and buffCdID or nil
    if next(ss) == nil then
        storage[targetSID] = nil
    end
    if buffSID then
        mod._cdmAnyBuffReplace = true
    end
    mod._cdmResGen = (mod._cdmResGen or 0) + 1
    mod._spellOrderDirty = true
    if mod.RebuildSpellRouteMap then
        mod.RebuildSpellRouteMap()
    end
    -- User-settings edge: the BuffIcon viewer's alpha vote now includes this
    -- bar (BarUsesBuffViewer), so re-apply visibility here rather than wait
    -- for the next combat/zone edge.
    if mod.CDMApplyVisibility then
        mod.CDMApplyVisibility()
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- Host a single collided-buff SLOT (cooldownID) on a CD/util bar. Same
--- collision escape hatch as ns.AddTrackedBuffByCdID: two viewer slots can
--- share one canonical spellID, so AddBuffToCDUtilBar's spellID-keyed
--- idempotency guard would treat the second slot as "already hosted" and
--- silently no-op it. Claiming by the cd-claim MARKER sidesteps that, reusing
--- AddTrackedSpell's plumbing unchanged. Collision-gated by the caller:
--- non-collided buffs keep AddBuffToCDUtilBar's sid path (survives talent
--- swaps).
function mod.AddHostedBuffByCdID(barId, cooldownId, spellRef)
    if type(cooldownId) ~= "number" or cooldownId <= 0 then
        return false
    end
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    DropTrinketSidClaims(cooldownId, spellRef)
    -- Empty-table sentinel: ResolveSpellSettings' hostedFrame gate
    -- (CUI_CDM_HookResolve.lua) short-circuits on this table being non-nil to
    -- skip pricier frame-flag checks. A cd-claimed hosted buff resolves its
    -- own "c"..cooldownID key independently -- only the table's existence matters.
    barSpells.hostedBuffSpellIDs = barSpells.hostedBuffSpellIDs or {}
    return mod.AddTrackedSpell(barId, mod.CdClaimMarker(cooldownId))
end

--- Remove a tracked spell by index. Routes positive viewer spells to the
--- ghost CD bar so they stay in the routing system but are hidden.
--- Picker-driven remove path. Wraps RemoveSpellFromBar.
function mod.RemoveTrackedSpell(barId, position)
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    local list = barSpells.assignedSpells
    if not list or position < 1 or position > #list then
        return false
    end
    local removedID = list[position]
    table.remove(list, position)
    mod._spellOrderDirty = true

    -- Hosted-buff removal? Entry is a MARKER, or a legacy plain entry
    -- representing the buff (flag set, no marker in list). A plain entry
    -- WITH a marker present is the same spell's COOLDOWN slot -- buff stays.
    local hostedSid = removedID and mod.HostedBuffMarkerToSpell(removedID)
    if
        not hostedSid
        and removedID
        and removedID > 0
        and barSpells.hostedBuffSpellIDs
        and barSpells.hostedBuffSpellIDs[removedID]
        and not mod.ListHasHostedMarker(list, removedID)
    then
        hostedSid = removedID
    end
    if hostedSid then
        -- Un-host: clear the flag so the route map stops diverting here (buff
        -- returns to the buffs bar). Never ghost-route a hosted buff -- the
        -- ghost bar hides by spellID, hiding the COOLDOWN form everywhere too.
        if barSpells.hostedBuffSpellIDs then
            barSpells.hostedBuffSpellIDs[hostedSid] = nil
            -- Host flip changes resolution routing: retire memoized results.
            mod._cdmResGen = (mod._cdmResGen or 0) + 1
        end
    else
        -- Auxiliary metadata cleanup, mirroring RemoveSpellFromBar's side
        -- effects for symmetry with index-based removal.
        if removedID and barSpells.customSpellDurations then
            barSpells.customSpellDurations[removedID] = nil
        end
        if removedID and barSpells.spellDurations then
            barSpells.spellDurations[removedID] = nil
        end
        if removedID and barSpells.customSpellIDs then
            barSpells.customSpellIDs[removedID] = nil
        end
        if removedID and barSpells.customSpellGroups then
            for variantID, primaryId in pairs(barSpells.customSpellGroups) do
                if primaryId == removedID then
                    barSpells.customSpellGroups[variantID] = nil
                end
            end
        end
        -- An Empty Slot's id is never reused (NewEmptySlotMarker), so its own
        -- settings entry (its Talent Conditions) goes with it.
        if removedID and mod.IsEmptySlotMarker(removedID) then
            local storage = mod.GetSpellSettingsStore(barId)
            if storage then
                storage[removedID] = nil
            end
        end
        -- An item preset Blizzard's own row can render under: ghosted like a
        -- racial (ns.NoteItemEntryRemoved), CD/utility bars only.
        if removedID and not IsBarBuffFamily(barId) then
            mod.NoteItemEntryRemoved(barSpells, removedID)
        end

        -- Route to the ghost CD bar so frames stay routed but hidden. Buff-family bars
        -- don't ghost (visibility managed by Blizzard's CDM settings); negative IDs and
        -- non-viewer spells (customs) skip ghost routing entirely.
        -- RACIALS GHOST like any viewer spell (changed 2026-08-13): 12.1's native
        -- racial tracking gives them a PERSISTENT live viewer frame, so a removed
        -- racial without a ghost is instantly re-added by the live-icon append on
        -- the next options refresh -- remove appeared to do nothing (field: dwarf
        -- Stoneform 20594 unremovable). The old skip was a pre-native fossil: back
        -- then no frame existed to re-add from, and removal alone stopped the
        -- injection lane. Customs still skip: those frames are OURS, not viewer pool.
        local isNonViewer = removedID
            and removedID > 0
            and (barSpells.customSpellIDs and barSpells.customSpellIDs[removedID])
        if removedID and removedID > 0 and not isNonViewer and not IsBarBuffFamily(barId) then
            mod.AddSpellToBar(mod.GHOST_CD_BAR_KEY, removedID)
        end
    end

    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    if mod.RebuildSpellRouteMap then
        mod.RebuildSpellRouteMap()
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

--- Replace a tracked spell at a given index with a new spellID
function mod.ReplaceTrackedSpell(barId, position, newID)
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return false
    end
    if not barSpells.assignedSpells then
        barSpells.assignedSpells = {}
    end
    local list = barSpells.assignedSpells
    if position < 1 then
        return false
    end
    while #list < position do
        list[#list + 1] = 0
    end
    for i, existing in ipairs(list) do
        if existing == newID and i ~= position then
            table.remove(list, i)
            if i < position then
                position = position - 1
            end
            break
        end
    end
    list[position] = newID
    while #list > 0 and (list[#list] == 0 or list[#list] == nil) do
        list[#list] = nil
    end
    if barSpells.removedSpells then
        barSpells.removedSpells[newID] = nil
    end
    local widget = cdmBarFrames[barId]
    if widget then
        widget._blizzCache = nil
        widget._prevVisibleCount = nil
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    return true
end

function mod.AddCDMBar(barKind, label, numRows)
    local BuildAllCDMBars = mod.BuildAllCDMBars
    local LayoutCDMBar = mod.LayoutCDMBar
    local RegisterCDMUnlockElements = mod.RegisterCDMUnlockElements
    local MAX_CUSTOM_BARS = mod.MAX_CUSTOM_BARS

    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local customCount = 0
    for _, b in ipairs(bars) do
        if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not b.isGhostBar then
            customCount = customCount + 1
        end
    end
    if customCount >= MAX_CUSTOM_BARS then
        return nil
    end
    barKind = barKind or "cooldowns"
    local typeLabel = barKind == "cooldowns" and "Cooldowns"
        or barKind == "utility" and "Utility"
        or barKind == "buffs" and "Buffs"
        or barKind == "custom_buff" and "Auras"
        or "Cooldowns"
    local typeCount = 0
    for _, b in ipairs(bars) do
        if b.barType == barKind then
            typeCount = typeCount + 1
        end
    end
    local barKey = "custom_" .. (#bars + 1) .. "_" .. GetTime()
    barKey = barKey:gsub("%.", "_")
    bars[#bars + 1] = {
        key = barKey,
        name = label or ("Custom " .. typeLabel .. " Bar " .. (typeCount + 1)),
        barType = barKind,
        enabled = true,
        iconSize = 36,
        numRows = numRows or 1,
        spacing = 2,
        borderSize = 1,
        borderR = 0,
        borderG = 0,
        borderB = 0,
        borderA = 1,
        borderClassColor = false,
        borderThickness = "thin",
        bgR = 0.08,
        bgG = 0.08,
        bgB = 0.08,
        bgA = 0.6,
        iconZoom = 0.08,
        iconShape = "none",
        verticalOrientation = false,
        barBgEnabled = false,
        barBgR = 0,
        barBgG = 0,
        barBgB = 0,
        showCooldownText = true,
        cooldownTextPosition = "center",
        showItemCount = true,
        cooldownFontSize = 12,
        showCharges = true,
        chargeFontSize = 11,
        desaturateOnCD = true,
        swipeAlpha = 0.7,
        activeStateAnim = "blizzard",
        anchorTo = "none",
        anchorPosition = "left",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
        barVisibility = "always",
        housingHideEnabled = true,
        visHideHousing = true,
        visOnlyInstances = false,
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,
        showStackCount = false,
        stackCountSize = 11,
        stackCountX = 0,
        stackCountY = 0,
        stackCountR = 1,
        stackCountG = 1,
        stackCountB = 1,
        -- Custom bars use a spell list instead of mirroring Blizzard
        outOfRangeOverlay = false,
        pandemicGlow = true,
        pandemicGlowStyle = -1,
        pandemicGlowLines = 8,
        pandemicGlowThickness = 2,
        pandemicGlowSpeed = 4,
    }
    local barSpells = mod.GetBarSpellData(barKey)
    if barSpells then
        barSpells.assignedSpells = {}
    end
    BuildAllCDMBars()
    LayoutCDMBar(barKey)
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
    RegisterCDMUnlockElements()
    return barKey
end

-- Remove a custom CDM bar (only custom bars, not the 3 defaults). Spells that were on
-- the deleted bar are migrated to the matching ghost bar for their family so they stay
-- hidden, instead of spilling back onto the default bar for their viewer category.
function mod.RemoveCDMBar(barKey)
    if barKey == "cooldowns" or barKey == "utility" or barKey == "buffs" then
        return false
    end
    local RegisterCDMUnlockElements = mod.RegisterCDMUnlockElements
    local p = ECME.db.profile
    for i, barInfo in ipairs(p.cdmBars.bars) do
        if barInfo.key == barKey then
            local widget = cdmBarFrames[barKey]
            if widget then
                CludesUI.SetElementVisibility(widget, false)
            end
            cdmBarFrames[barKey] = nil
            cdmBarIcons[barKey] = nil
            p.cdmBarPositions[barKey] = nil
            table.remove(p.cdmBars.bars, i)
            -- Max Icons overflow: clear targets pointing at the removed bar
            -- (runtime fail-safes on a dangling key; this is config hygiene).
            for _, b in ipairs(p.cdmBars.bars) do
                if b.overflowTarget == barKey then
                    b.overflowTarget = nil
                end
            end
            -- Deletion shifts every later bar's array index, so captured
            -- override paths into cdmBars.bars would point at the WRONG bars.
            -- Drop them all (users re-capture) -- honest beats corrupt.
            CludesUI.SpecOverrides_OnCDMBarsRestructured()

            -- Free all spells (don't ghost them): delete the bar's spell data
            -- from every spec of the ACTIVE profile only -- other profiles own
            -- independent stores and keep their copy (a copied profile's bar
            -- deletion must not wipe the origin's). Bar defs are per-profile
            -- but spec-independent, so clear all of THIS profile's specs.
            local spellRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
            if spellRec then
                for _, specData in pairs(spellRec) do
                    if type(specData) == "table" and specData.barSpells and specData.barSpells[barKey] then
                        specData.barSpells[barKey] = nil
                    end
                end
            end

            CludesUI:UnregisterUnlockElement("CDM_" .. barKey)
            -- Re-register remaining bars to update linkedKeys
            RegisterCDMUnlockElements()
            -- Reanchor so frames re-route to the ghost bar (or wherever)
            if mod.RebuildSpellRouteMap then
                mod.RebuildSpellRouteMap()
            end
            if mod.CollectAndReanchor then
                mod.CollectAndReanchor()
            end
            return true
        end
    end
    return false
end

-- Native equipment rows that the dual-lane era auto-added into buff bar
-- stores (12.1 EquipSlot* tracked-buff mirroring): pruned automatically.
-- POSITIVE identification only -- a stored sid drops solely when a live
-- viewer entry with that sid carries equipSlot; absence keeps the row
-- (zero-values law: an unequipped item resolves nothing and must not be
-- convicted). Runs OOC-cheap from the buff entry collector, so every
-- options open and reconcile pass self-heals the store.
function mod.PruneEquipmentBuffRows()
    local equip, any = {}, false
    -- Tracked trinket PROC BUFF rows (equipSlot + category EquipSlotTracked)
    -- are LEGITIMATE buff-bar content (user directive 2026-08-16) -- they must
    -- never be convicted, by EITHER source below. Positive identification
    -- only, same zero-values posture as the conviction sets: a live
    -- EquipSlotTracked viewer entry vouches for its sid (covers on-use
    -- trinkets whose use-spell IS the tracked proc aura -- source 2 would
    -- otherwise convict the legitimate row whenever the trinket is worn).
    -- CATEGORY is the discriminator, not buffSlot (field-probed 2026-08-16:
    -- buffSlot=1 rides the on-use cat-7 rows too).
    local exempt = {}
    local eqTracked = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.EquipSlotTracked
        or 8
    -- Viewer source: trusted only with CDM data loaded and a populated
    -- enumeration. These guards gate THIS source alone -- the equipped-item
    -- source below needs neither and must run regardless.
    local entryList = mod._cdmDataLoaded and mod.EnumerateCDMViewerSpells and mod.EnumerateCDMViewerSpells(true)
        or nil
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if entryList and entryList[1] and gci then
        for _, e in ipairs(entryList) do
            if e.sid and e.cdID then
                local details = gci(e.cdID)
                if details and details.equipSlot then
                    if details.category == eqTracked then
                        StoreVariantValue(exempt, e.sid, true, false)
                    else
                        StoreVariantValue(equip, e.sid, true, false)
                        any = true
                    end
                end
            end
        end
    end
    -- Second proof source, viewer-independent: an EQUIPPED item vouches for
    -- its own use-spell (GetItemSpell). Covers rows whose native viewer entry
    -- is gone (untracked in Blizzard's CDM) while the item is still worn.
    local gis = C_Item.GetItemSpell
    if GetInventoryItemID then
        for slot = 1, 19 do
            local itemId = GetInventoryItemID("player", slot)
            if itemId then
                local _, useSid = gis(itemId)
                if type(useSid) == "number" and useSid > 0 then
                    StoreVariantValue(equip, useSid, true, false)
                    any = true
                end
            end
        end
    end
    if not any then
        return
    end
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if not bars then
        return
    end
    for _, edge in ipairs(bars) do
        -- Every bar type: dual-lane-era auto-adds landed item use-spells on
        -- cooldowns/utility bars too, not just buff bars. Only positive ids
        -- matching the proven equipment set drop -- markers and real spells
        -- cannot match.
        if edge.key ~= (mod.GHOST_CD_BAR_KEY or "__ghost_cd") then
            local barSpells = mod.GetBarSpellData(edge.key)
            local list = barSpells and barSpells.assignedSpells
            if list then
                local wid = 1
                for i = 1, #list do
                    local spellRef = list[i]
                    -- User-typed custom spell ids are exempt: a deliberate
                    -- entry that happens to equal a worn item's use-spell
                    -- (tinkers, embellishments) must never be convicted.
                    -- Tracked proc-buff sids (buffSlot-vouched above) are
                    -- exempt from both conviction sources.
                    if
                        not (
                            type(spellRef) == "number"
                            and spellRef > 0
                            and ResolveVariantValue(equip, spellRef)
                            and not ResolveVariantValue(exempt, spellRef)
                            and not (barSpells.customSpellIDs and barSpells.customSpellIDs[spellRef])
                        )
                    then
                        list[wid] = spellRef
                        wid = wid + 1
                    end
                end
                for i = #list, wid, -1 do
                    list[i] = nil
                end
            end
        end
    end
end
