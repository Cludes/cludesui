if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Auras.lua
--
--  The pre-combat aura snapshot, the per-refresh aura helpers, the tracker
--  of the player's own auras on group members, weapon types and the raid
--  buff beneficiaries.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local AURA_SCAN_LIMIT, REMIND, GetSpecID = Inner.AURA_SCAN_LIMIT, Inner.EABR, Inner.GetSpecID
local InCombat, isSecret, NON_SECRET_SPELL_IDS = Inner.InCombat, Inner.isSecret, Inner.NON_SECRET_SPELL_IDS
local SpellName = Inner.SpellName

-------------------------------------------------------------------------------
--  Pre-combat aura snapshot
-------------------------------------------------------------------------------
local _preCombatAuraCache = {} -- [spellID] = true/false, snapshotted at REGEN_DISABLED

function REMIND.IsRuntimeNonSecret(ident)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local success, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, ident)
        if not success or isSecret(secret) then
            return false
        end
        return secret == false
    end
    return true -- if API missing, assume non-secret (pre-12.0 client)
end

-- Soulstone is readable on clients/builds where Blizzard explicitly exposes
-- it. Do not hard-whitelist it on restricted builds: source ownership is the
-- defining part of this reminder and must never be guessed from secret data.
if REMIND.IsRuntimeNonSecret(20707) then
    NON_SECRET_SPELL_IDS[20707] = true
end

local function SnapshotPlayerAuras()
    wipe(_preCombatAuraCache)
    -- WoW Forever reads nothing from it: its own section shows nothing in
    -- combat, and its Raid Buffs read the live auras.
    if REMIND.FOREVER then
        return
    end
    for ident in pairs(NON_SECRET_SPELL_IDS) do
        local result = C_UnitAuras.GetPlayerAuraBySpellID(ident)
        _preCombatAuraCache[ident] = (result ~= nil)
    end
    -- Also snapshots non-whitelisted auras (e.g. Devotion Aura) going secret when a
    -- partymate combats first. 12.1: index scan hard-errors under restrictions (M+/raid) even OOC; whitelisted lookups still work, extras skipped.
    if CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted() then
        return
    end
    for idx = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", idx, "HELPFUL")
        if not aura then
            break
        end
        local spellRef = aura.spellId
        if spellRef and not isSecret(spellRef) and not NON_SECRET_SPELL_IDS[spellRef] then
            _preCombatAuraCache[spellRef] = true
        end
    end
end

-- Pre-combat snapshot for ownOnRaid buffs (Blistering Scales, Symbiotic
-- Relationship). Source of Magic
-- reads the targeted own-aura tracker instead.
local _preCombatOwnOnRaidCache = {} -- [spellID] = true/false
local _ownOnRaidIDs = { 360827, 474754 } -- Blistering Scales, Symbiotic Relationship
local SnapshotOwnOnRaidBuffs -- forward declaration; defined after _unitHasBuffFromPlayer

-- Pre-allocated scratch tables for hot per-Refresh functions (avoids GC churn)
local _idLookupScratch = {}
local _lookupScratch = {}

-------------------------------------------------------------------------------
--  Per-refresh aura helpers: targeted GetPlayerAuraBySpellID lookups (zero-alloc)
--  instead of scanning ~20-40 aura tables per refresh; GetAuraDataByIndex only as a name-based-check fallback.
-------------------------------------------------------------------------------
local _AC = { valid = false, nameScanned = false, byName = {} }

-- Lightweight reset; the expensive name scan is deferred lazily to first use.
local function BuildPlayerAuraCache()
    _AC.valid = not InCombat()
    _AC.nameScanned = false
    -- srcByID is only needed by PlayerHasSelfCastAuraByID; wiped lazily there
end

-- Food buffs share the Well Fed icon, not a spell ID.
local WELL_FED_ICON = 136000

-- Lazy: runs once per refresh, only when a name-based check (Flask/ByName) or the
-- Well Fed check needs it. One pass serves them all, so a refresh reads the aura
-- list once (each read can cost milliseconds right after an encounter): names
-- into byName, and the first aura wearing the Well Fed icon into wellFed.
function _AC.ensureNames()
    if _AC.nameScanned then
        return
    end
    _AC.nameScanned = true
    wipe(_AC.byName)
    _AC.wellFed, _AC.sawIcon = nil, false
    if InCombat() then
        return
    end
    -- 12.1: index scans hard-error under restrictions even out of combat.
    if CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted() then
        return
    end
    for idx = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", idx, "HELPFUL")
        if not aura then
            break
        end
        local aName = aura.name
        if aName and not isSecret(aName) then
            _AC.byName[aName] = true
        end
        local ic = aura.icon
        if ic and not isSecret(ic) then
            _AC.sawIcon = true
            if ic == WELL_FED_ICON and not _AC.wellFed then
                _AC.wellFed = aura
            end
        end
    end
end

local function IsUnderDuration(duration, expirationTime, sectionKey)
    return REMIND.IsUnderDuration(duration, expirationTime, sectionKey)
end

local function PlayerHasAuraByID(spellIDs, sectionKey)
    if not spellIDs or not spellIDs[1] then
        return true
    end
    local inCombat = InCombat()
    -- Direct GetPlayerAuraBySpellID lookup (zero-alloc, OOC+combat for whitelisted IDs); non-whitelisted IDs fall back to the pre-combat snapshot.
    for jdx = 1, #spellIDs do
        local ident = spellIDs[jdx]
        if NON_SECRET_SPELL_IDS[ident] then
            local success, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
            if success then
                if result ~= nil then
                    if sectionKey and IsUnderDuration(result.duration, result.expirationTime, sectionKey) then
                        return false
                    end
                    return true
                end
                if inCombat and _preCombatAuraCache[ident] then
                    return true
                end
            else
                if inCombat and _preCombatAuraCache[ident] then
                    return true
                end
            end
        elseif not inCombat then
            -- Non-whitelisted OOC: GetPlayerAuraBySpellID may return secret values, but non-nil still means the aura exists.
            local success, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
            if success and result ~= nil then
                -- 12.1: fields can be secret even OOC in restricted content; math on secrets errors, so presence alone counts then.
                local dur, exp = result.duration, result.expirationTime
                if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp) then
                    if sectionKey and IsUnderDuration(dur, exp, sectionKey) then
                        return false
                    end
                end
                return true
            end
        else
            if _preCombatAuraCache[ident] then
                return true
            end
        end
    end
    return false
end

-- Stances are shapeshift forms, not auras (GetPlayerAuraBySpellID can't see them); scan the stance bar instead. Returns (known-in-bar, currently-active).
local function GetStanceState(stanceSpellID)
    local numForms = GetNumShapeshiftForms()
    for idx = 1, numForms do
        local _, isActive, _, spellID = GetShapeshiftFormInfo(idx)
        if spellID == stanceSpellID then
            return true, isActive
        end
    end
    return false, false
end

-- Same idea, but checks a list of spellIDs instead of one fixed form index.
local function IsAnyShapeshiftFormActive(spellIDs)
    local numForms = GetNumShapeshiftForms()
    for idx = 1, numForms do
        local _, isActive, _, spellID = GetShapeshiftFormInfo(idx)
        if isActive then
            for _, ident in ipairs(spellIDs) do
                if spellID == ident then
                    return true
                end
            end
        end
    end
    return false
end

-- 12.1: aura restrictions apply in M+/raids even OOC, and index scans HARD-ERROR there (not just secret results). Every
-- OOC-only scan checks AuraKit.AurasRestricted() inline (no helper local).

-- Shared helpers for group aura scanning (hoisted to avoid per-call closure allocation)
local function _unitOk(u)
    return UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u)
end
local function _unitHasBuff(u, spellIDs)
    local inCombat = InCombat()
    -- Fast path for player: use GetPlayerAuraBySpellID for whitelisted IDs
    if UnitIsUnit(u, "player") then
        for jdx = 1, #spellIDs do
            local ident = spellIDs[jdx]
            if NON_SECRET_SPELL_IDS[ident] then
                local success, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
                if success then
                    if result ~= nil then
                        return true
                    end
                    if inCombat and _preCombatAuraCache[ident] then
                        return true
                    end
                else
                    if inCombat and _preCombatAuraCache[ident] then
                        return true
                    end
                end
            end
        end
    else
        -- Non-player units: GetUnitAuraBySpellID for whitelisted IDs; works in combat for non-secret IDs.
        for jdx = 1, #spellIDs do
            local ident = spellIDs[jdx]
            if NON_SECRET_SPELL_IDS[ident] then
                local success, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, ident)
                if success and result ~= nil and not isSecret(result) then
                    return true
                end
            end
        end
    end
    -- Iterate auras for non-whitelisted IDs: OOC and outside restricted content only (scan errors under restriction). Skipped for player (covered above).
    if
        not inCombat
        and not UnitIsUnit(u, "player")
        and not (CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted())
    then
        for idx = 1, AURA_SCAN_LIMIT do
            local aura = C_UnitAuras.GetAuraDataByIndex(u, idx, "HELPFUL")
            if not aura then
                break
            end
            local spellRef = aura.spellId
            if spellRef and not isSecret(spellRef) then
                for jdx = 1, #spellIDs do
                    if spellRef == spellIDs[jdx] then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Strict ownership of one aura: true = the player cast it, false = someone else
-- did, nil = cannot tell (the caller suppresses rather than false-fires).
-- isFromPlayerOrPlayerPet is true for ANY player's (or player pet's) cast, so it
-- only rules an aura out (false = an NPC applied it); sourceUnit proves it.
function REMIND._StrictAuraFromMe(aura)
    local fromPlayer = aura.isFromPlayerOrPlayerPet
    if not isSecret(fromPlayer) and fromPlayer == false then
        return false
    end
    local source = aura.sourceUnit
    if source == nil or isSecret(source) then
        return nil
    end
    return UnitIsUnit(source, "player") == true
end

-- Whether the player's OWN cast of `id` is on `unit`, for the in-combat cache
-- updates where sourceUnit is secret: the PLAYER filter returns only auras the
-- player applied, so another caster's copy never counts. Presence only.
function REMIND._OwnCastOn(unitToken, ident)
    local nameList = REMIND._ownCastNames
    if not nameList then
        nameList = {}
        REMIND._ownCastNames = nameList
    end
    local name = nameList[ident]
    if name == nil then
        name = C_Spell.GetSpellName(ident) or false
        nameList[ident] = name
    end
    if not name then
        return false
    end
    local success, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unitToken, name, "HELPFUL|PLAYER")
    return success and aura ~= nil and not isSecret(aura)
end

-- True if the buff's source is the player. Non-player units: OOC iteration only, false in combat (caller uses the snapshot).
local function _unitHasBuffFromPlayer(u, spellIDs, strictSource)
    local inCombat = InCombat()
    local restricted = CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted()
    local idLookup = _idLookupScratch
    wipe(idLookup)
    for jdx = 1, #spellIDs do
        idLookup[spellIDs[jdx]] = true
    end

    if UnitIsUnit(u, "player") then
        -- Player-self: GetPlayerAuraBySpellID for whitelisted IDs
        for ident in pairs(idLookup) do
            if NON_SECRET_SPELL_IDS[ident] or (strictSource and not restricted) then
                local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
                if strictSource and (not success or isSecret(aura)) then
                    return nil
                end
                if success and aura ~= nil and not isSecret(aura) then
                    if strictSource then
                        return REMIND._StrictAuraFromMe(aura)
                    end
                    local source = aura.sourceUnit
                    if source and not isSecret(source) then
                        if UnitIsUnit(source, "player") then
                            return true
                        end
                    else
                        -- Source unreadable: a player's cast is assumed ours (the
                        -- flag alone cannot tell whose).
                        local fromMe = aura.isFromPlayerOrPlayerPet
                        if not isSecret(fromMe) and fromMe == true then
                            return true
                        end
                    end
                end
            end
        end
        -- A strict targeted lookup is authoritative in an unrestricted
        -- context; avoid a 255-aura fallback scan for every group unit.
        if strictSource then
            return false
        end
        if not inCombat and not restricted then
            for idx = 1, AURA_SCAN_LIMIT do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", idx, "HELPFUL")
                if not aura then
                    break
                end
                local spellRef = aura.spellId
                if spellRef and not isSecret(spellRef) and idLookup[spellRef] then
                    local source = aura.sourceUnit
                    if source and not isSecret(source) and UnitIsUnit(source, "player") then
                        return true
                    end
                end
            end
        end
        return false
    end

    if inCombat then
        return false
    end -- sourceUnit secret in combat, caller uses snapshot
    -- Fast path: 1 API call per whitelisted ID instead of scanning every aura on the unit via GetAuraDataByIndex.
    local needScan = false
    for ident in pairs(idLookup) do
        if NON_SECRET_SPELL_IDS[ident] or (strictSource and not restricted) then
            local success, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, ident)
            if strictSource and (not success or isSecret(aura)) then
                return nil
            end
            if success and aura and not isSecret(aura) then
                if strictSource then
                    return REMIND._StrictAuraFromMe(aura)
                end
                local source = aura.sourceUnit
                if source and not isSecret(source) then
                    if UnitIsUnit(source, "player") then
                        return true
                    end
                else
                    if strictSource then
                        return nil
                    end
                    return true -- sourceUnit unavailable OOC, assume ours
                end
            end
        else
            needScan = true
        end
    end
    if not needScan then
        return false
    end
    -- Scan errors under restriction; skip (caller falls back to snapshot).
    if restricted then
        return false
    end
    -- Fallback: full scan for non-whitelisted IDs only
    for idx = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex(u, idx, "HELPFUL")
        if not aura then
            break
        end
        local spellRef = aura.spellId
        if spellRef and not isSecret(spellRef) and idLookup[spellRef] then
            if strictSource then
                return REMIND._StrictAuraFromMe(aura)
            end
            local source = aura.sourceUnit
            if source and not isSecret(source) then
                if UnitIsUnit(source, "player") then
                    return true
                end
            else
                if strictSource then
                    return nil
                end
                return true -- sourceUnit unavailable OOC, assume ours
            end
        end
    end
    return false
end

-- Forward-declared earlier; assigned now that _unitHasBuffFromPlayer exists.
local _snapScratch = {} -- reused for SnapshotOwnOnRaidBuffs
SnapshotOwnOnRaidBuffs = function()
    wipe(_preCombatOwnOnRaidCache)
    for _, ident in ipairs(_ownOnRaidIDs) do
        -- Secret right now (Blistering Scales in a key): no lookup can see it,
        -- so leave the entry nil (unknown, suppressed) instead of a false miss.
        if REMIND.IsRuntimeNonSecret(ident) then
            local found = false
            _snapScratch[1] = ident
            if _unitHasBuffFromPlayer("player", _snapScratch) then
                found = true
            end
            if not found then
                if IsInRaid() then
                    for idx = 1, GetNumGroupMembers() do
                        if _unitHasBuffFromPlayer("raid" .. idx, _snapScratch) then
                            found = true
                            break
                        end
                    end
                elseif IsInGroup() then
                    for idx = 1, GetNumSubgroupMembers() do
                        if _unitHasBuffFromPlayer("party" .. idx, _snapScratch) then
                            found = true
                            break
                        end
                    end
                end
            end
            _preCombatOwnOnRaidCache[ident] = found
        end
    end
end

-- True only if the player cast the buff on themselves. OOC only -- combatOk must be false for any aura using this check.
local function PlayerHasSelfCastAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then
        return true
    end
    if InCombat() then
        return false
    end -- safety: can't read sourceUnit in combat
    -- Direct lookup: for whitelisted IDs, GetPlayerAuraBySpellID returns full aura data incl. sourceUnit (zero iteration needed).
    for jdx = 1, #spellIDs do
        local ident = spellIDs[jdx]
        local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
        if success and aura ~= nil and not isSecret(aura) then
            local source = aura.sourceUnit
            if source and not isSecret(source) and UnitIsUnit(source, "player") then
                return true
            end
            -- If sourceUnit is unavailable OOC, assume ours
            if not source or isSecret(source) then
                return true
            end
        end
    end
    return false
end

-- Range check mirrors raid frames: UnitInRange (~40yd helpful, combat-safe, unprotected) is primary, but can be a SECRET
-- value in instances (raid frames feed it to SetAlphaFromBoolean instead of branching). When secret here, falls back to
-- UnitIsVisible (~100yd, same phase/zone) -- proven branch-safe by the raid frames' ghost-aura sweep; coarser than true cast range but excludes cross-wing/zone/phase false positives.
local function _unitInRange(u)
    if UnitIsUnit(u, "player") then
        return true
    end
    if not UnitExists(u) then
        return false
    end
    local inRange, checked = UnitInRange(u)
    if not (isSecret(inRange) or isSecret(checked)) and checked then
        return inRange == true
    end
    -- Secret or uncheckable: visibility fallback
    local vis = UnitIsVisible(u)
    if isSecret(vis) then
        return true
    end
    return vis == true
end

-- Counts how many in-range beneficiaries have the buff vs how many should
-- (the "12/15" coverage badge). `benefit` is the buff's benefit KEY
-- ("intellect"/"attackPower"/nil = everyone). EABR.UnitBenefits resolves it
-- spec-aware when comm data exists, class-level otherwise, and skips units
-- whose identity reads come back secret (teardown/restriction edges).
-- Returns have, total.
local function CountGroupBuffCoverage(spellIDs, benefit)
    local have, sum = 0, 0
    if not IsInGroup() then
        if REMIND.UnitBenefits("player", benefit) and _unitOk("player") then
            sum = 1
            if _unitHasBuff("player", spellIDs) then
                have = 1
            end
        end
        return have, sum
    end
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            local u = "raid" .. idx
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                if REMIND.UnitBenefits(u, benefit) then
                    sum = sum + 1
                    if _unitHasBuff(u, spellIDs) then
                        have = have + 1
                    end
                end
            end
        end
    else
        if REMIND.UnitBenefits("player", benefit) and _unitOk("player") then
            sum = sum + 1
            if _unitHasBuff("player", spellIDs) then
                have = have + 1
            end
        end
        for idx = 1, GetNumSubgroupMembers() do
            local u = "party" .. idx
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                if REMIND.UnitBenefits(u, benefit) then
                    sum = sum + 1
                    if _unitHasBuff(u, spellIDs) then
                        have = have + 1
                    end
                end
            end
        end
    end
    return have, sum
end

-- True if the buff exists on any group member, any source. Used for Symbiotic Relationship.
local function BuffExistsOnAnyGroupMember(spellIDs)
    if _unitHasBuff("player", spellIDs) then
        return true
    end
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            if _unitHasBuff("raid" .. idx, spellIDs) then
                return true
            end
        end
    elseif IsInGroup() then
        for idx = 1, GetNumSubgroupMembers() do
            if _unitHasBuff("party" .. idx, spellIDs) then
                return true
            end
        end
    end
    return false
end

-- Generic event-driven tracker for player-owned targeted auras on OTHER group members.
-- Reminder-specific policy (which spell/class/talent/location enables tracking) stays
-- in UpdateGroupAuraRegistration; this block only owns lookup/cache/synchronization.
REMIND._ownOtherAuraCache = {}
REMIND._ownOtherAuraTargetGUID = {}
REMIND._ownOtherAuraDuration = {}
REMIND._ownOtherAuraExpiration = {}
REMIND._ownOtherAuraStateVersion = 0
REMIND._trackOwnOtherAuraID = nil
REMIND._ownOtherAuraScanGeneration = 0

-- Generic ownership lookup. The PLAYER filter is defined by Blizzard as auras
-- cast by the local player/pet/vehicle, so another Shaman/Evoker cannot satisfy
-- this lookup. Spell-name lookup remains usable for explicitly non-secret auras
-- when generic aura payloads are restricted.
function REMIND.GetOwnOtherAuraData(unitToken, spellID)
    if not unitToken or not spellID then
        return nil, nil
    end
    if not (unitToken:match("^party%d+$") or unitToken:match("^raid%d+$")) then
        return nil, nil
    end
    -- A dead/ghost unit is not a reliable negative aura lookup. Preserve the
    -- last known state until the unit is alive again, leaves the group, or an
    -- authoritative aura update/rescan can establish a new state.
    if UnitIsDeadOrGhost(unitToken) then
        return nil, nil
    end
    -- Nor is an out-of-view member (another map or phase): the client holds no
    -- aura data for it.
    local vis = UnitIsVisible(unitToken)
    if not isSecret(vis) and not vis then
        return nil, nil
    end
    local name = SpellName(spellID)
    if not name or isSecret(name) then
        return nil, nil
    end
    local success, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unitToken, name, "HELPFUL|PLAYER")
    if not success or isSecret(aura) then
        return nil, nil
    end
    if aura == nil then
        -- A restricted lookup withholds a secret aura (nil while it is up). In
        -- combat a miss proves nothing; under restriction out of combat only a
        -- whitelisted non-secret id reads a trustworthy miss.
        if InCombat() then
            return nil, nil
        end
        if not NON_SECRET_SPELL_IDS[spellID] and CludesUI.AuraKit.AurasRestricted() then
            return nil, nil
        end
        return false, nil
    end
    return true, aura
end

-- One cache writer shared by live events and recovery scans. It deliberately
-- does not touch scan generations; callers decide whether their write is an
-- authoritative live update or the result of the currently valid scan.
function REMIND.WriteOwnOtherAuraState(spellID, status, unitToken, aura)
    if status == nil then
        return
    end
    local old = REMIND._ownOtherAuraCache[spellID]
    REMIND._ownOtherAuraCache[spellID] = status
    if status then
        REMIND._ownOtherAuraTargetGUID[spellID] = unitToken and UnitGUID(unitToken) or nil
        local dur = aura and aura.duration
        local exp = aura and aura.expirationTime
        REMIND._ownOtherAuraDuration[spellID] = (type(dur) == "number" and not isSecret(dur)) and dur or nil
        REMIND._ownOtherAuraExpiration[spellID] = (type(exp) == "number" and not isSecret(exp)) and exp or nil
    else
        REMIND._ownOtherAuraTargetGUID[spellID] = nil
        REMIND._ownOtherAuraDuration[spellID] = nil
        REMIND._ownOtherAuraExpiration[spellID] = nil
    end
    if old ~= status and _G._CUABR_RequestRefresh then
        _G._CUABR_RequestRefresh()
    end
end

-- Authoritative live updates invalidate older recovery work before publishing.
function REMIND.SetOwnOtherAuraState(spellID, status, unitToken, aura)
    if status == nil then
        return
    end
    REMIND._ownOtherAuraStateVersion = REMIND._ownOtherAuraStateVersion + 1
    REMIND._ownOtherAuraScanGeneration = REMIND._ownOtherAuraScanGeneration + 1
    REMIND.WriteOwnOtherAuraState(spellID, status, unitToken, aura)
end

-- Incremental recovery scan: one unit per frame. It never wins a race against
-- newer live data: any UNIT_AURA/cast state change bumps stateVersion/generation,
-- invalidating this scan before it can publish its result.
function REMIND.RescanOwnOtherAura(spellID)
    if InCombat() or REMIND._trackOwnOtherAuraID ~= spellID then
        return
    end

    REMIND._ownOtherAuraScanGeneration = REMIND._ownOtherAuraScanGeneration + 1
    local generation = REMIND._ownOtherAuraScanGeneration
    local stateVersion = REMIND._ownOtherAuraStateVersion
    local isRaid = IsInRaid()
    local count = isRaid and GetNumGroupMembers() or (IsInGroup() and GetNumSubgroupMembers() or 0)
    local slotPos = 1
    local sawUnknown = false

    local function scanNext()
        if
            generation ~= REMIND._ownOtherAuraScanGeneration
            or stateVersion ~= REMIND._ownOtherAuraStateVersion
        then
            return
        end
        if InCombat() or REMIND._trackOwnOtherAuraID ~= spellID then
            return
        end

        while slotPos <= count do
            local u = (isRaid and "raid" or "party") .. slotPos
            slotPos = slotPos + 1
            -- If our last known target is dead, its aura cannot be reliably
            -- disproved. Do not let a recovery scan publish false and flash the
            -- reminder while that target remains in the group.
            if UnitExists(u) and UnitIsConnected(u) and not UnitIsUnit(u, "player") then
                local unitGuid = UnitGUID(u)
                if
                    UnitIsDeadOrGhost(u)
                    and unitGuid
                    and REMIND._ownOtherAuraCache[spellID] == true
                    and REMIND._ownOtherAuraTargetGUID[spellID] == unitGuid
                then
                    return
                end
                local status, aura = REMIND.GetOwnOtherAuraData(u, spellID)
                if status == true then
                    -- The generation/version guards above prove this scan is still
                    -- current, so publish through the shared writer without
                    -- invalidating the scan that produced the result.
                    REMIND.WriteOwnOtherAuraState(spellID, true, u, aura)
                    return
                elseif status == nil then
                    -- Unknown must never become "missing": the scan then ends
                    -- without a verdict and keeps the previous cache.
                    sawUnknown = true
                end
                C_Timer.After(0, scanNext)
                return
            end
        end

        if
            generation ~= REMIND._ownOtherAuraScanGeneration
            or stateVersion ~= REMIND._ownOtherAuraStateVersion
        then
            return
        end
        if sawUnknown then
            return
        end
        REMIND.WriteOwnOtherAuraState(spellID, false)
    end

    scanNext()
end

-- UNIT_AURA is only a trigger here. In restricted combat its updateInfo can be
-- fully secret, so do not depend on addedAuras/sourceUnit. Query exactly the
-- changed party/raid unit with HELPFUL|PLAYER instead. This same generic path is
-- used by Earth Shield and Source of Magic.
function REMIND.UpdateOwnOtherAuraForUnit(unitToken)
    local spellID = REMIND._trackOwnOtherAuraID
    if not spellID or not unitToken or UnitIsUnit(unitToken, "player") then
        return
    end
    if not (unitToken:match("^party%d+$") or unitToken:match("^raid%d+$")) then
        return
    end

    local status, aura = REMIND.GetOwnOtherAuraData(unitToken, spellID)
    if status == true then
        REMIND.SetOwnOtherAuraState(spellID, true, unitToken, aura)
        return
    end
    -- Unknown (secret, dead, out of view) never clears. A miss is authoritative only for
    -- the unit holding our cached aura; another unit's miss proves nothing, and
    -- recovery/roster scans establish a group-wide false.
    if status == nil then
        return
    end
    local unitGuid = UnitGUID(unitToken)
    if unitGuid and REMIND._ownOtherAuraTargetGUID[spellID] == unitGuid then
        REMIND.SetOwnOtherAuraState(spellID, false)
    end
end

function REMIND.RescanOwnOtherAuras()
    local spellID = REMIND._trackOwnOtherAuraID
    if spellID then
        REMIND.RescanOwnOtherAura(spellID)
    end
end

-- Registration pass for the roster, loading-screen and talent edges. A
-- tracking change clears or rescans inside the pass, so only an unchanged
-- tracker rescans here.
function REMIND.ReevaluateOwnOtherAuraTracking()
    local before = REMIND._trackOwnOtherAuraID
    if _G._CUABR_UpdateGroupAuraRegistration then
        _G._CUABR_UpdateGroupAuraRegistration()
    end
    if before and REMIND._trackOwnOtherAuraID == before then
        REMIND.RescanOwnOtherAuras()
    end
end

-- Early rebuff for a targeted aura follows the Display "Show Below" / "Show
-- Below Pre-Key" window (never in combat or an active key); sectionKey is the
-- owning section ("aura" / "special").
function REMIND.OwnOtherAuraNeedsRebuff(spellID, sectionKey)
    if REMIND._ownOtherAuraCache[spellID] ~= true then
        return false
    end
    local dur = REMIND._ownOtherAuraDuration[spellID]
    local exp = REMIND._ownOtherAuraExpiration[spellID]
    if type(dur) ~= "number" or type(exp) ~= "number" then
        return false
    end
    return REMIND.IsUnderDuration(dur, exp, sectionKey)
end

-- True when another group member is alive, connected and in range: a targeted
-- buff reminder has nobody to go on otherwise.
function REMIND.AnyReachableGroupMember()
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            local u = "raid" .. idx
            if _unitOk(u) and not UnitIsUnit(u, "player") and _unitInRange(u) then
                return true
            end
        end
    elseif IsInGroup() then
        for idx = 1, GetNumSubgroupMembers() do
            local u = "party" .. idx
            if _unitOk(u) and _unitInRange(u) then
                return true
            end
        end
    end
    return false
end

-- True if the player's own cast exists on any group member, OR no in-range member is a valid target (suppress either way). Used for the ownOnRaid auras other than Source of Magic.
local function PlayerOwnBuffOnAnyGroupMember(spellIDs)
    if _unitHasBuffFromPlayer("player", spellIDs) then
        return true
    end
    local anyInRangeWithoutBuff = false
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            local u = "raid" .. idx
            if _unitOk(u) and not UnitIsUnit(u, "player") then
                if _unitHasBuffFromPlayer(u, spellIDs) then
                    return true
                end
                if _unitInRange(u) then
                    anyInRangeWithoutBuff = true
                end
            end
        end
    elseif IsInGroup() then
        for idx = 1, GetNumSubgroupMembers() do
            local u = "party" .. idx
            if _unitOk(u) then
                if _unitHasBuffFromPlayer(u, spellIDs) then
                    return true
                end
                if _unitInRange(u) then
                    anyInRangeWithoutBuff = true
                end
            end
        end
    end
    -- No reminder if nobody reachable is missing the buff.
    return not anyInRangeWithoutBuff
end

-- Soulstone differs from targeted maintenance buffs: self is always a valid
-- destination, and an existing cast on an out-of-range group member still
-- satisfies the reminder. Returns nil when restricted aura data cannot prove
-- ownership, allowing the caller to suppress rather than false-fire.
function REMIND.PlayerOwnBuffOnGroupOrSelf(spellIDs)
    if not spellIDs or not spellIDs[1] then
        return true
    end
    if CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted() then
        for idx = 1, #spellIDs do
            if not NON_SECRET_SPELL_IDS[spellIDs[idx]] then
                return nil
            end
        end
    end
    local uncertain = false
    local status = _unitHasBuffFromPlayer("player", spellIDs, true)
    if status == true then
        return true
    elseif status == nil then
        uncertain = true
    end
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            local u = "raid" .. idx
            if not UnitIsUnit(u, "player") and UnitExists(u) and UnitIsConnected(u) and UnitIsPlayer(u) then
                status = _unitHasBuffFromPlayer(u, spellIDs, true)
                if status == true then
                    return true
                elseif status == nil then
                    uncertain = true
                end
            end
        end
    elseif IsInGroup() then
        for idx = 1, GetNumSubgroupMembers() do
            local u = "party" .. idx
            if UnitExists(u) and UnitIsConnected(u) and UnitIsPlayer(u) then
                status = _unitHasBuffFromPlayer(u, spellIDs, true)
                if status == true then
                    return true
                elseif status == nil then
                    uncertain = true
                end
            end
        end
    end
    if uncertain then
        return nil
    end
    return false
end

-------------------------------------------------------------------------------
--  Weapon type classification (for weapon enchant matching)
-------------------------------------------------------------------------------
local BLADED_SET, BLUNT_SET, RANGED_SET
do
    local Widgets = (Enum and Enum.ItemWeaponSubclass) or {}
    local function setFrom(...)
        local t = {}
        for idx = 1, select("#", ...) do
            local val = select(idx, ...)
            if val ~= nil then
                t[val] = true
            end
        end
        return t
    end
    BLADED_SET = setFrom(
        Widgets.Axe1H,
        Widgets.Axe2H,
        Widgets.Sword1H,
        Widgets.Sword2H,
        Widgets.Dagger,
        Widgets.Polearm,
        Widgets.Warglaive
    )
    BLUNT_SET = setFrom(Widgets.Mace1H, Widgets.Mace2H, Widgets.Staff, Widgets.Fist)
    RANGED_SET = setFrom(Widgets.Bow, Widgets.Gun, Widgets.Crossbow, Widgets.Wand)
end

local function GetWeaponCategory(slotID)
    local itemId = GetInventoryItemID("player", slotID)
    if not itemId then
        return nil
    end
    local _, _, _, equipLoc, _, classID, subClassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemId)
    else
        _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemId)
    end
    if not classID or classID ~= ((Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2) then
        return nil
    end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
        return nil
    end
    if subClassID and BLADED_SET[subClassID] then
        return "BLADED"
    end
    if subClassID and BLUNT_SET[subClassID] then
        return "BLUNT"
    end
    if subClassID and RANGED_SET[subClassID] then
        return "RANGED"
    end
    return "NEUTRAL"
end

-- Off-hand slot holds a shield. Gates the shield-only imbue reminders
-- (requireShield rows); on EABR, not a local.
-- UNIT_INVENTORY_CHANGED already refreshes, so no new event.
function REMIND.HasShieldEquipped()
    local itemId = GetInventoryItemID("player", 17)
    if not itemId then
        return false
    end
    local _, _, _, equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    else
        _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    end
    return equipLoc == "INVTYPE_SHIELD"
end

-------------------------------------------------------------------------------
--  Raid buff beneficiaries (class-level). Only Intellect/Attack Power are stat-restricted (versatility/stamina/
--  skyfury/bronze help everyone, no filter). A class is listed if ANY spec wants the stat -- hybrids may over-count, never under.
-------------------------------------------------------------------------------
local BUFF_BENEFICIARIES = {
    intellect = {
        MAGE = true,
        WARLOCK = true,
        PRIEST = true,
        DRUID = true,
        SHAMAN = true,
        MONK = true,
        EVOKER = true,
        PALADIN = true,
        DEMONHUNTER = true, -- Devourer (1480) is Intellect; Havoc/Vengeance are not
    },
    attackPower = {
        WARRIOR = true,
        ROGUE = true,
        HUNTER = true,
        DEATHKNIGHT = true,
        PALADIN = true,
        MONK = true,
        DRUID = true,
        DEMONHUNTER = true,
        SHAMAN = true,
    },
}
-- WoW Forever: Intellect serves every mana user (hunters included) and Battle
-- Shout raises melee attack power only (a hunter shoots with ranged).
if REMIND.FOREVER then
    -- The shared Intellect family's list (the Raid Frames Missing Buffs reads it too).
    BUFF_BENEFICIARIES.intellect = CludesUI.FOREVER_BUFF_FAMILIES.ai.beneficiaries
    BUFF_BENEFICIARIES.attackPower = {
        DRUID = true,
        PALADIN = true,
        ROGUE = true,
        SHAMAN = true,
        WARRIOR = true,
    }
end

-- Set of player classes present in the group (online, alive, in range),
-- excluding the local player. Built on demand for the receiver view ("I am
-- missing others' buffs") so a buff is only flagged when someone who can
-- cast it is actually nearby. Secret class tokens are skipped (identity
-- restriction edges). Hung on EABR.
REMIND._groupClassSet = REMIND._groupClassSet or {}
function REMIND.BuildGroupClassSet()
    local group = wipe(REMIND._groupClassSet)
    if IsInRaid() then
        for idx = 1, GetNumGroupMembers() do
            local u = "raid" .. idx
            if _unitOk(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player") and _unitInRange(u) then
                local _, classFile = UnitClass(u)
                if classFile ~= nil and not isSecret(classFile) then
                    group[classFile] = true
                end
            end
        end
    elseif IsInGroup() then
        for idx = 1, GetNumSubgroupMembers() do
            local u = "party" .. idx
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                local _, classFile = UnitClass(u)
                if classFile ~= nil and not isSecret(classFile) then
                    group[classFile] = true
                end
            end
        end
    end
    return group
end

-------------------------------------------------------------------------------
--  Spec-aware beneficiaries. Group members' specs arrive over addon comms
--  (LibSpecialization, cached by player name in EABR._groupSpecs); when a
--  member's spec is unknown (no LibSpec-embedding addon) the class table
--  above is the fallback -- spec sharpens, class never under-counts. Only
--  the two stat-filtered buffs consult these sets.
-------------------------------------------------------------------------------
REMIND.SPEC_BENEFITS = {
    intellect = {
        [62] = true,
        [63] = true,
        [64] = true, -- Mage
        [265] = true,
        [266] = true,
        [267] = true, -- Warlock
        [256] = true,
        [257] = true,
        [258] = true, -- Priest
        [1467] = true,
        [1468] = true,
        [1473] = true, -- Evoker
        [102] = true,
        [105] = true, -- Druid: Balance, Restoration
        [262] = true,
        [264] = true, -- Shaman: Elemental, Restoration
        [270] = true, -- Monk: Mistweaver
        [65] = true, -- Paladin: Holy
        [1480] = true, -- Demon Hunter: Devourer (Intellect, not Agility)
    },
    attackPower = {
        [71] = true,
        [72] = true,
        [73] = true, -- Warrior
        [259] = true,
        [260] = true,
        [261] = true, -- Rogue
        [253] = true,
        [254] = true,
        [255] = true, -- Hunter
        [250] = true,
        [251] = true,
        [252] = true, -- Death Knight
        [577] = true,
        [581] = true, -- Demon Hunter: Havoc, Vengeance
        [103] = true,
        [104] = true, -- Druid: Feral, Guardian
        [66] = true,
        [70] = true, -- Paladin: Protection, Retribution
        [268] = true,
        [269] = true, -- Monk: Brewmaster, Windwalker
        [263] = true, -- Shaman: Enhancement
    },
}

-- Name-keyed spec cache filled by the LibSpecialization group callback
-- (wired in OnEnable). Entries self-heal: a rejoining player rebroadcasts
-- on their own group-join, overwriting any stale spec. Bounded growth
-- (name -> number), so no pruning needed.
REMIND._groupSpecs = REMIND._groupSpecs or {}

-- Resolves a unit's specID: own spec directly (always readable), others
-- from the comm cache keyed the way the lib keys senders (Name for same
-- realm, Name-Realm cross-realm).
function REMIND.GroupSpecFor(u)
    if UnitIsUnit(u, "player") then
        return GetSpecID()
    end
    local num, r = UnitNameUnmodified(u)
    if num == nil or isSecret(num) then
        return nil
    end
    if r ~= nil and not isSecret(r) and r ~= "" then
        num = num .. "-" .. r
    end
    return REMIND._groupSpecs[num]
end

-- Whether a unit benefits from a stat-filtered buff. Resolution ladder:
-- (1) cached spec verdict when known and mapped (unknown/starter spec IDs
-- fall through); (2) assigned-ROLE refinement for combos the role alone
-- decides (no comms needed); (3) the class table. Unreadable class = not
-- counted (coverage skips the unit).
function REMIND.UnitBenefits(u, benefit)
    if not benefit then
        return true
    end
    -- WoW Forever has no spec data to look up (no comms cache, no specs).
    local specSet = not REMIND.FOREVER and REMIND.SPEC_BENEFITS[benefit]
    if specSet then
        local specInfo = REMIND.GroupSpecFor(u)
        if specInfo then
            if specSet[specInfo] then
                return true
            end
            -- A spec listed under any benefit set is a real, mapped spec:
            -- its absence here is a definitive no. Anything else (starter
            -- specs, future IDs) falls back to the checks below.
            for _, group in pairs(REMIND.SPEC_BENEFITS) do
                if group[specInfo] then
                    return false
                end
            end
        end
    end
    local classSet = BUFF_BENEFICIARIES[benefit]
    if not classSet then
        return true
    end
    local _, classFile = UnitClass(u)
    if classFile == nil or isSecret(classFile) then
        return false
    end
    if not classSet[classFile] then
        return false
    end
    -- Role refinement for members with no spec data: some class+benefit
    -- pairs are decided by the role alone -- Intellect only serves the
    -- HEALER spec of Paladin/Monk (and never a Druid tank); Attack Power
    -- never serves the healer spec of these hybrids. Ambiguous combos
    -- (e.g. a DAMAGER Druid: Balance wants int, Feral wants AP) and
    -- unassigned ("NONE") or secret roles fall through to the class answer.
    -- Effective role: the player's spec wins over a stale assigned role. On
    -- WoW Forever every mana user wants Intellect, whatever the role.
    local role = CludesUI.UnitEffectiveRole(u)
    if role ~= nil and not isSecret(role) then
        if benefit == "intellect" and not REMIND.FOREVER then
            if (classFile == "PALADIN" or classFile == "MONK") and (role == "DAMAGER" or role == "TANK") then
                return false
            end
            if classFile == "DRUID" and role == "TANK" then
                return false
            end
        elseif benefit == "attackPower" then
            if
                role == "HEALER"
                and (
                    classFile == "PALADIN"
                    or classFile == "MONK"
                    or classFile == "DRUID"
                    or classFile == "SHAMAN"
                )
            then
                return false
            end
        end
    end
    return true
end

-- Whether the local player benefits from a raid buff (spec-aware; class
-- fallback). Buffs with no benefit key help everyone.
function REMIND.PlayerBenefitsFromBuff(buff)
    return REMIND.UnitBenefits("player", buff.benefit) and true or false
end

Inner._AC, Inner._ownOnRaidIDs = _AC, _ownOnRaidIDs
Inner._preCombatOwnOnRaidCache, Inner._unitInRange = _preCombatOwnOnRaidCache, _unitInRange
Inner._unitOk, Inner.BuffExistsOnAnyGroupMember = _unitOk, BuffExistsOnAnyGroupMember
Inner.BuildPlayerAuraCache, Inner.CountGroupBuffCoverage = BuildPlayerAuraCache, CountGroupBuffCoverage
Inner.GetStanceState, Inner.GetWeaponCategory = GetStanceState, GetWeaponCategory
Inner.IsAnyShapeshiftFormActive, Inner.IsUnderDuration = IsAnyShapeshiftFormActive, IsUnderDuration
Inner.PlayerHasAuraByID, Inner.PlayerHasSelfCastAuraByID = PlayerHasAuraByID, PlayerHasSelfCastAuraByID
Inner.PlayerOwnBuffOnAnyGroupMember = PlayerOwnBuffOnAnyGroupMember
Inner.SnapshotOwnOnRaidBuffs, Inner.SnapshotPlayerAuras = SnapshotOwnOnRaidBuffs, SnapshotPlayerAuras
Inner.broken = false
