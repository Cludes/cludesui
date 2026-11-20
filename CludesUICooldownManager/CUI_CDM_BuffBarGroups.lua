if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarGroups.lua
--
--  The frame table, the idle sleeper, bar groups (per spec and global), style
--  copy, style presets and the group reflow.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local SetECME, SetAssignDirty, SetReflowDirty = Inner.SetECME, Inner.SetAssignDirty, Inner.SetReflowDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val)
    ECME = val
end
-- True while any bar uses a Visibility mode/option, i.e. a state no tick-side aura or
-- cooldown edge can reveal. Gates the dispatcher wake below so profiles that never touch
-- Visibility keep the idle sleeper's original wake set.
local _anyVisCond = false
Inner.anyVisCondSetters[#Inner.anyVisCondSetters + 1] = function(val)
    _anyVisCond = val
end

-------------------------------------------------------------------------------
--  Frame Table & State
-------------------------------------------------------------------------------
local tbbFrames = {}
local tbbTickFrame
Inner.tickFrameSetters[#Inner.tickFrameSetters + 1] = function(val)
    tbbTickFrame = val
end
local _tbbRebuildPending = false
Inner.rebuildPendingSetters[#Inner.rebuildPendingSetters + 1] = function(val)
    _tbbRebuildPending = val
end

-- Group reflow gate: ReflowGroup's inputs are the visible member sequence plus the
-- group's grow direction and spacing. Bar frames dirty this from their OnShow/OnHide,
-- the group setting writers, rebuilds and wakes dirty it directly, and the tick
-- reflows only while it is set instead of re-walking every bar every 16 ms.
local function _MarkTBBReflowDirty()
    SetReflowDirty(true)
end

-- TBB idle sleeper: UpdateTrackedBuffBarTimers counts consecutive dead ticks (no
-- active/fallback aura, self-timed window, running cooldown, or placeholder preview);
-- after ~0.5s it parks the tick frame (OnUpdate stops) and this frame listens for the
-- cheap edges that revive it. Lust from other players and the Time Spiral glow arm
-- outside these events, so their arm sites call Wake directly instead, and a Tracked
-- Bars viewer item going active wakes it through ns.WakeTBBTickIfParked (the item's
-- OnActiveStateChanged hook in CUI_CDM_HookViewers.lua).
local _tbbWake = CreateFrame("Frame")
_tbbWake._idleTicks = 0
-- Aura edge counts for the tick's fallback reads (a bar the viewer has not bound
-- reads the player's aura, else the target's): player aura events, and target
-- aura events plus target changes. A bar re-queries a half only after its count moved.
_tbbWake._fbPGen, _tbbWake._fbTGen = 0, 0
function _tbbWake.Sleep()
    if tbbTickFrame then
        tbbTickFrame:Hide()
    end
    -- NEVER register SPELL_UPDATE_COOLDOWN here: it fires steadily at idle and would defeat
    -- the sleep. A tracked cooldown can only START via a player cast (item/shapeshift
    -- included), covered by the cast event; a RUNNING cooldown keeps the tick awake by liveness.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player")
    _tbbWake:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    _tbbWake:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- A debuff the player left on a new target is live the moment it is selected, and
    -- none of the player-scoped edges above can see that. Probe before waking.
    _tbbWake:RegisterEvent("PLAYER_TARGET_CHANGED")
end
function _tbbWake.Wake()
    -- Tracking Bars off: no tick to revive, so nothing registers. BuildTrackedBuffBars
    -- sets _enabled before its own Wake.
    if not _tbbWake._enabled then
        return
    end
    _tbbWake:UnregisterAllEvents()
    -- Stay subscribed to the aura edge while AWAKE: pool composition changes only on a
    -- player aura event or a pool Acquire (hooked separately), retiring the assignment memo.
    -- The target's aura events only retire the fallback reads (OnEvent); Sleep's
    -- player-only registration drops them again.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player", "target")
    _tbbWake._fbPGen, _tbbWake._fbTGen = _tbbWake._fbPGen + 1, _tbbWake._fbTGen + 1
    -- Target changes rebind which auras the viewer's frames carry, so the awake branch
    -- of OnEvent retires the assignment memo on this the same as any other non-aura edge.
    _tbbWake:RegisterEvent("PLAYER_TARGET_CHANGED")
    _tbbWake._idleTicks = 0
    SetAssignDirty(true)
    SetReflowDirty(true)
    if tbbTickFrame then
        tbbTickFrame:Show()
    end
end
-- UNIT_AURA fires steadily in group content and every false wake buys ~0.5s of full
-- ticking, so this probe answers "could any bar be live?" WITHOUT waking: an active
-- viewer frame, or a live player aura for a fallback-class config. Casts and combat
-- entry skip the probe (rare at idle; the legitimate start edges the probe can't see).
-- Cache names by configuration, retiring entries when their configuration is dropped.
_tbbWake._targetNames = setmetatable({}, { __mode = "k" })
function _tbbWake.GetTargetAura(conf)
    if not UnitExists("target") then
        return nil
    end
    local nameList = _tbbWake._targetNames[conf]
    if not nameList then
        nameList = {}
        _tbbWake._targetNames[conf] = nameList
    end
    if nameList.spellID ~= conf.spellID then
        nameList.spellID, nameList.name = conf.spellID, nil
    end
    if nameList.baseSpellID ~= conf.baseSpellID then
        nameList.baseSpellID, nameList.baseName = conf.baseSpellID, nil
    end
    if not nameList.name then
        nameList.name = C_Spell.GetSpellName(conf.spellID)
    end
    if not nameList.baseName and conf.baseSpellID and conf.baseSpellID > 0 then
        nameList.baseName = C_Spell.GetSpellName(conf.baseSpellID)
    end
    -- Ownership is filtered by the engine; never inspect a secret sourceUnit.
    local filter = UnitIsFriend("player", "target") and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
    local aura = nameList.name and C_UnitAuras.GetAuraDataBySpellName("target", nameList.name, filter)
    if not aura and nameList.baseName and nameList.baseName ~= nameList.name then
        aura = C_UnitAuras.GetAuraDataBySpellName("target", nameList.baseName, filter)
    end
    return aura
end
function _tbbWake.Probe()
    if mod._tbbPlaceholderMode then
        return true
    end
    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for widget in viewer.itemFramePool:EnumerateActive() do
            if widget.IsActive and widget:IsActive() then
                return true
            end
        end
    end
    if not (ECME and ECME.db) then
        return true
    end
    local trackBars = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    local barList = trackBars and trackBars.bars
    if barList and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, conf in ipairs(barList) do
            if
                conf.enabled ~= false
                and not conf.spellIDs
                and not conf.popularKey
                and conf.trackType ~= "cooldown"
                and conf.spellID
                and conf.spellID > 0
            then
                if
                    C_UnitAuras.GetPlayerAuraBySpellID(conf.spellID)
                    or (conf.baseSpellID and conf.baseSpellID > 0 and C_UnitAuras.GetPlayerAuraBySpellID(
                        conf.baseSpellID
                    ))
                    or _tbbWake.GetTargetAura(conf)
                then
                    return true
                end
            end
        end
    end
    return false
end
function _tbbWake.OnEvent(_, evt, unitToken, updateInfo)
    -- Awake: this is the composition edge that retires the assignment memo. Mark and
    -- let the next tick re-pair; no probe, no state change. Pairing keys on frame
    -- identity only (pool membership, cooldown slot, aura spell variant), and an
    -- update-only payload (refresh / stack change on auras already bound) moves none
    -- of those, so only additions, removals, full updates, or an unreadable payload
    -- retire the memo -- the same secret guard as the buff ticker's UNIT_AURA writer:
    -- the table and each field can arrive secret in instanced content, and a secret
    -- can never be boolean-tested, so unreadable means assume churn.
    if tbbTickFrame and tbbTickFrame:IsShown() then
        if evt == "UNIT_AURA" then
            if unitToken == "target" then
                -- No viewer frame moves on a target aura event (no target aura
                -- subscription retired the memo before): the fallback reads only.
                _tbbWake._fbTGen = _tbbWake._fbTGen + 1
                return
            end
            _tbbWake._fbPGen = _tbbWake._fbPGen + 1
        else
            _tbbWake._fbTGen = _tbbWake._fbTGen + 1
        end
        if evt ~= "UNIT_AURA" or not updateInfo or issecretvalue(updateInfo) then
            SetAssignDirty(true)
        else
            local full = updateInfo.isFullUpdate
            local removed = updateInfo.removedAuraInstanceIDs
            local added = updateInfo.addedAuras
            if
                issecretvalue(full)
                or issecretvalue(removed)
                or issecretvalue(added)
                or full
                or removed
                or added
            then
                SetAssignDirty(true)
            end
        end
        return
    end
    if (evt == "UNIT_AURA" or evt == "PLAYER_TARGET_CHANGED") and not _tbbWake.Probe() then
        return
    end
    _tbbWake.Wake()
end
_tbbWake:SetScript("OnEvent", _tbbWake.OnEvent)
mod.WakeTBBTick = _tbbWake.Wake

function mod.WakeTBBTickIfParked(entry)
    if
        _tbbWake._enabled
        and tbbTickFrame
        and not tbbTickFrame:IsShown()
        and (not entry or entry:IsActive())
    then
        _tbbWake.Wake()
    end
end

-- The Visibility edges (mount, shapeshift, gliding, target, group, zone, combat) are exactly
-- the set the shared dispatcher already owns, so subscribe there instead of re-registering
-- them on the sleeper. Without this a parked tick never learns that a Visibility condition
-- flipped: a bar hidden while mounted stays hidden past the dismount until some unrelated
-- aura or cast happens to wake it, and the dragonriding modes never fire at all because
-- takeoff/landing is not in the sleeper's wake set.
if CludesUI.RegisterVisibilityUpdater then
    CludesUI.RegisterVisibilityUpdater(function()
        -- Only a parked tick needs the nudge; an awake one re-evaluates every frame anyway.
        if _anyVisCond then
            mod.WakeTBBTickIfParked()
        end
    end)
end

function mod.GetTBBFrame(position)
    return tbbFrames[position]
end

-------------------------------------------------------------------------------
--  Bar grouping helpers (multi-group)
--  Membership: per-bar numeric cfg.groupId (0 = independent). Legacy bars carry only
--  the boolean cfg.grouped, read as a VIEW (true/default = group 1, false =
--  independent); writes set groupId and mirror the boolean for older-version export
--  compat. Groups chain in index order: the first ENABLED member is the anchor (owns
--  position/mover), later members chain to it sharing its width/height.
-------------------------------------------------------------------------------
function mod.TBBBarGroupID(conf)
    if not conf then
        return 0
    end
    if conf.groupId ~= nil then
        return conf.groupId
    end
    return (conf.grouped ~= false) and 1 or 0
end

function mod.TBBSetBarGroup(conf, groupKey)
    if not conf then
        return
    end
    groupKey = groupKey or 0
    conf.groupId = groupKey
    -- Legacy mirror: older versions only know one group ("checked" bars).
    conf.grouped = (groupKey ~= 0)
end

-- Sorted list of group ids currently used by at least one bar.
function mod.TBBGroupIDsInUse()
    local t = mod.GetTrackedBuffBars()
    local seen, entries = {}, {}
    for _, c in ipairs(t.bars or {}) do
        local groupKey = mod.TBBBarGroupID(c)
        if groupKey ~= 0 and not seen[groupKey] then
            seen[groupKey] = true
            entries[#entries + 1] = groupKey
        end
    end
    table.sort(entries)
    return entries
end

-- Smallest positive group id not currently in use (fills holes left by dissolved groups so group names stay compact).
function mod.TBBNextGroupID()
    local t = mod.GetTrackedBuffBars()
    local used = {}
    for _, c in ipairs(t.bars or {}) do
        used[mod.TBBBarGroupID(c)] = true
    end
    local groupKey = 1
    while used[groupKey] do
        groupKey = groupKey + 1
    end
    return groupKey
end

-- Per-group settings live in tbb.groups[tostring(gid)]. Group 1 VIEWS the legacy keys
-- (tbb.groupGrowDirection/groupSpacing) for zero-migration old-config compat; group-1
-- writes keep those keys synced for old-version imports. gid->string memo below avoids a
-- tostring allocation in the per-tick reflow.
local _gidKeys = setmetatable({}, {
    __index = function(t, groupKey)
        local s = tostring(groupKey)
        rawset(t, groupKey, s)
        return s
    end,
})

local function TBBGroupStore(trackBars, groupKey, create)
    if not trackBars.groups then
        if not create then
            return nil
        end
        trackBars.groups = {}
    end
    local k = _gidKeys[groupKey]
    local g = trackBars.groups[k]
    if not g and create then
        g = {}
        trackBars.groups[k] = g
    end
    return g
end

-- Internal reads take the tbb table directly so the per-tick reflow does not re-resolve the active spec profile per group.
local function GroupGrowOf(trackBars, groupKey)
    local g = TBBGroupStore(trackBars, groupKey, false)
    if g and g.globalKey then
        -- Global group: shared value from the profile registry. A stale key (entry deleted) falls through to the local values.
        local e = mod.TBBGlobalGroup and mod.TBBGlobalGroup(g.globalKey)
        if e then
            return e.grow or "DOWN"
        end
    end
    if g and g.grow then
        return g.grow
    end
    if groupKey == 1 and trackBars.groupGrowDirection then
        return trackBars.groupGrowDirection
    end
    return "DOWN"
end

local function GroupSpacingOf(trackBars, groupKey)
    local g = TBBGroupStore(trackBars, groupKey, false)
    if g and g.globalKey then
        local e = mod.TBBGlobalGroup and mod.TBBGlobalGroup(g.globalKey)
        if e and e.spacing ~= nil then
            return e.spacing
        end
    end
    if g and g.spacing ~= nil then
        return g.spacing
    end
    if groupKey == 1 and trackBars.groupSpacing ~= nil then
        return trackBars.groupSpacing
    end
    return 2
end

function mod.TBBGroupGrow(groupKey)
    return GroupGrowOf(mod.GetTrackedBuffBars(), groupKey)
end

function mod.TBBSetGroupGrow(groupKey, val)
    local t = mod.GetTrackedBuffBars()
    local groupId = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupKey)
    if groupId then
        local e = mod.TBBGlobalGroup(groupId)
        if e then
            e.grow = val
            SetReflowDirty(true)
        end
        return
    end
    TBBGroupStore(t, groupKey, true).grow = val
    if groupKey == 1 then
        t.groupGrowDirection = val
    end
    SetReflowDirty(true)
end

function mod.TBBGroupSpacing(groupKey)
    return GroupSpacingOf(mod.GetTrackedBuffBars(), groupKey)
end

function mod.TBBSetGroupSpacing(groupKey, val)
    local t = mod.GetTrackedBuffBars()
    local groupId = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupKey)
    if groupId then
        local e = mod.TBBGlobalGroup(groupId)
        if e then
            e.spacing = val
            SetReflowDirty(true)
        end
        return
    end
    TBBGroupStore(t, groupKey, true).spacing = val
    if groupKey == 1 then
        t.groupSpacing = val
    end
    SetReflowDirty(true)
end

-- Clear a group's stored settings when its id is (re)claimed for a brand-new group, so a dissolved group's leftovers do not leak into it.
function mod.TBBResetGroupSettings(groupKey)
    local t = mod.GetTrackedBuffBars()
    if t.groups then
        t.groups[_gidKeys[groupKey]] = nil
    end
    SetReflowDirty(true)
end

-- Optional user-given group name (Group Settings input). Empty/absent = nil, callers fall back to the default "Group N" label.
function mod.TBBGroupName(groupKey)
    local t = mod.GetTrackedBuffBars()
    local g = TBBGroupStore(t, groupKey, false)
    if g and g.globalKey then
        local e = mod.TBBGlobalGroup and mod.TBBGlobalGroup(g.globalKey)
        if e and type(e.name) == "string" and e.name ~= "" then
            return e.name
        end
    end
    local num = g and g.name
    if type(num) == "string" and num ~= "" then
        return num
    end
    return nil
end

function mod.TBBSetGroupName(groupKey, label)
    local t = mod.GetTrackedBuffBars()
    local groupId = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupKey)
    if groupId then
        -- Shared name lives in the registry and is never blanked: movers and dropdown rows on other specs need a concrete label.
        local e = mod.TBBGlobalGroup(groupId)
        if e then
            if type(label) == "string" and label ~= "" then
                e.name = label
            end
        end
        return
    end
    if type(label) ~= "string" or label == "" then
        local g = TBBGroupStore(t, groupKey, false)
        if g then
            g.name = nil
        end
    else
        TBBGroupStore(t, groupKey, true).name = label
    end
end

-------------------------------------------------------------------------------
--  Global groups: a PROFILE-scoped registry shared by every spec. A per-spec group
--  opts in by stamping groups[gid].globalKey; its name/grow/spacing/position then
--  resolve through the registry entry (including the unlock mover, keyed stably as
--  "TBBG_<gkey>"), so every spec linked to the key shares one identity. Membership
--  stays per-spec: a spec with no bars on the key has no frames and a hidden mover.
--  Keys are monotonic and NEVER reused (reuse would resurrect stale unlock anchor
--  links). Zero migration: a group without a globalKey stamp is purely local.
-------------------------------------------------------------------------------
do
    local function TBBGlobalDB(create)
        if not (ECME and ECME.db) then
            SetECME(mod.ECME)
        end
        local p = ECME and ECME.db and ECME.db.profile
        if not p then
            return nil
        end
        if not p.tbbGlobalGroups and create then
            p.tbbGlobalGroups = {}
        end
        return p.tbbGlobalGroups, p
    end

    function mod.GetTBBGlobalGroups()
        return TBBGlobalDB(false)
    end

    function mod.TBBGlobalGroup(groupId)
        local registry = TBBGlobalDB(false)
        return registry and groupId and registry[groupId] or nil
    end

    -- The globalKey a per-spec group is linked to (nil = local group). A stale stamp whose registry entry was deleted reads as local.
    function mod.TBBGroupGlobalKey(groupKey)
        local g = TBBGroupStore(mod.GetTrackedBuffBars(), groupKey, false)
        local groupId = g and g.globalKey
        if groupId and mod.TBBGlobalGroup(groupId) then
            return groupId
        end
        return nil
    end

    -- Local gid linked to a global group on the ACTIVE spec (nil if none).
    function mod.TBBLocalGidForGlobal(groupId)
        local t = mod.GetTrackedBuffBars()
        if not t.groups then
            return nil
        end
        for k, group in pairs(t.groups) do
            if group.globalKey == groupId then
                return tonumber(k)
            end
        end
        return nil
    end

    -- Find-or-create the active spec's local group for a global group. The id must dodge
    -- BOTH gids used by bars and gids held by memberless global links (TBBNextGroupID only
    -- scans bars; reusing a linked gid here would wipe another global group's link).
    function mod.TBBEnsureLocalGroupForGlobal(groupId)
        if not mod.TBBGlobalGroup(groupId) then
            return nil
        end
        local groupKey = mod.TBBLocalGidForGlobal(groupId)
        if groupKey then
            return groupKey
        end
        local t = mod.GetTrackedBuffBars()
        local used = {}
        for _, c in ipairs(t.bars or {}) do
            used[mod.TBBBarGroupID(c)] = true
        end
        if t.groups then
            for k, group in pairs(t.groups) do
                if group.globalKey then
                    local kn = tonumber(k)
                    if kn then
                        used[kn] = true
                    end
                end
            end
        end
        groupKey = 1
        while used[groupKey] do
            groupKey = groupKey + 1
        end
        mod.TBBResetGroupSettings(groupKey)
        TBBGroupStore(t, groupKey, true).globalKey = groupId
        return groupKey
    end

    -- Sorted registry keys (stable ordering for dropdown rows / movers).
    function mod.TBBGlobalGroupKeys()
        local registry = TBBGlobalDB(false)
        local entries = {}
        if registry then
            for k in pairs(registry) do
                entries[#entries + 1] = k
            end
            table.sort(entries, function(lhs, rhs)
                return (tonumber(lhs:match("%d+")) or 0) < (tonumber(rhs:match("%d+")) or 0)
            end)
        end
        return entries
    end

    -- "Shift Elements If No Bars" (entry.shiftNoBar = "Up"/"Down", nil = None;
    -- entry.shiftNoBarExtraY tunes the magnitude). Stand-in frame for a global
    -- group on memberless specs, created ONLY while the option is set (None =
    -- byte-identical legacy behavior: nil getFrame, anchors dormant/fallback):
    -- a bare script-free frame holding the group's slot -- registry position,
    -- last-stamped anchor-bar size -- so anchored elements keep resolvable
    -- bounds and the shift has a magnitude when no member bar frame exists.
    -- Renders nothing and costs nothing (no events, no OnUpdate). Re-positioned
    -- every build; the IsUnlockAnchored guard leaves it alone when the anchor
    -- system owns the TBBG_ key (same guard as the bar placement below).
    local tbbStandins = {}
    function mod.TBBEnsureStandin(matchGroupKey)
        local record = mod.TBBGlobalGroup(matchGroupKey)
        if not record then
            return nil
        end
        local frame = tbbStandins[matchGroupKey]
        if not frame then
            frame = CreateFrame("Frame", nil, UIParent)
            tbbStandins[matchGroupKey] = frame
        end
        local PPl = CludesUI and CludesUI.PP
        local sn = PPl and PPl.Snap or function(val)
            return val
        end
        frame:SetSize(sn(record.width or 270), sn(record.height or 24))
        -- SetPoint ONLY on an actual position change (signature-stamped): this
        -- runs from getFrame, and the unlock machinery hooksecurefuncs SetPoint
        -- on resolved frames -- an unconditional re-point per resolve fed the
        -- move-check timer a fresh SetPoint every frame, forever (audit-caught).
        -- getFrame must never mutate what it merely resolves.
        local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("TBBG_" .. matchGroupKey)
        if anchored and frame:GetLeft() then
            return frame
        end
        local place = record.pos
        local sig
        if place and place.point then
            sig = place.point
                .. "|"
                .. (place.relPoint or place.point)
                .. "|"
                .. (place.x or 0)
                .. "|"
                .. (place.y or 0)
        else
            sig = "default"
        end
        if frame._posSig ~= sig then
            frame._posSig = sig
            frame:ClearAllPoints()
            if place and place.point then
                frame:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x or 0, place.y or 0)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
        end
        return frame
    end
    -- Read-only lookup (no create): lets getFrame keep resolving a stand-in
    -- built earlier this session after the option flips to None, so the flip's
    -- cascade can land anchored children back at the true slot instead of
    -- stranding them shifted. A fresh session with the option off never creates
    -- one, preserving the legacy nil-frame behavior.
    function mod.TBBStandinFrame(matchGroupKey)
        return tbbStandins[matchGroupKey]
    end

    -- Whether ANY spec profile links this global key. A fully-orphaned entry
    -- (every spec detached; the registry keeps it for re-attachment) must stop
    -- shifting -- with no linked spec, no group settings page can reach the
    -- option to clear it (audit-caught). Bounded scan: specs x groups, only
    -- reached when the option is set and the ACTIVE spec is memberless.
    local function TBBGlobalLinkedAnywhere(groupId)
        local specRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
        if not specRec then
            return false
        end
        for _, profileTbl in pairs(specRec) do
            local trackBars = profileTbl.trackedBuffBars
            local groups = trackBars and trackBars.groups
            if groups then
                for _, group in pairs(groups) do
                    if group.globalKey == groupId then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Direction the shift WOULD apply for one registry entry (ignores unlock
    -- state): 0 while the active spec has an enabled member bar (the real
    -- anchor frame covers the slot), the option is off, or no spec links the
    -- entry at all; else +1/-1.
    local function TBBShiftDirFor(record, matchGroupKey)
        local mode = record and record.shiftNoBar
        if mode ~= "Up" and mode ~= "Down" then
            return 0
        end
        local groupKey = mod.TBBLocalGidForGlobal(matchGroupKey)
        if groupKey and mod.TBBGroupAnchorIndex(groupKey) then
            return 0
        end
        if not TBBGlobalLinkedAnywhere(matchGroupKey) then
            return 0
        end
        return (mode == "Up") and 1 or -1
    end
    mod.TBBShiftDirFor = TBBShiftDirFor

    -- Seeded into the shared shift-provider list (CUI_UnlockMode.lua dispatches
    -- CludesUI._GetAnchorTargetShiftDir over it; ResourceBars seeds the
    -- ERB_* keys the same way). Direct or-preserve push, NEVER an API call:
    -- registration must carry zero load-order coupling. Elements anchored to a
    -- shifting TBBG_ key move into the empty slot by the stand-in's height +
    -- Extra Y -- visual-only, never written to saved positions; 0 while unlock
    -- mode is active so movers capture true positions.
    CludesUI._anchorShiftProviders = CludesUI._anchorShiftProviders or {}
    table.insert(CludesUI._anchorShiftProviders, {
        dir = function(targetKey)
            if CludesUI._unlockActive then
                return 0
            end
            if type(targetKey) ~= "string" or targetKey:sub(1, 5) ~= "TBBG_" then
                return 0
            end
            local matchGroupKey = targetKey:sub(6)
            local record = mod.TBBGlobalGroup(matchGroupKey)
            local direction = TBBShiftDirFor(record, matchGroupKey)
            if direction == 0 then
                return 0
            end
            return direction, record.shiftNoBarExtraY or 0
        end,
        wants = function()
            local registry = TBBGlobalDB(false)
            if not registry then
                return false
            end
            for matchGroupKey, record in pairs(registry) do
                if TBBShiftDirFor(record, matchGroupKey) ~= 0 then
                    return true
                end
            end
            return false
        end,
        restore = function()
            if not CludesUI.PropagateAnchorChain then
                return
            end
            local registry = TBBGlobalDB(false)
            if not registry then
                return
            end
            for matchGroupKey, record in pairs(registry) do
                if TBBShiftDirFor(record, matchGroupKey) ~= 0 then
                    CludesUI.PropagateAnchorChain("TBBG_" .. matchGroupKey)
                end
            end
        end,
    })

    -- Opt in: seed the registry from the group's current per-spec settings and anchor
    -- position. Detach: materialize shared values back into the per-spec store so nothing
    -- moves; the registry entry persists for other specs (full removal is TBBDeleteGlobalGroup).
    function mod.TBBSetGroupGlobal(groupKey, on)
        local t = mod.GetTrackedBuffBars()
        local g = TBBGroupStore(t, groupKey, true)
        if on then
            if g.globalKey and mod.TBBGlobalGroup(g.globalKey) then
                return
            end
            local registry, p = TBBGlobalDB(true)
            if not registry then
                return
            end
            local ident = (p.tbbGlobalGroupNextId or 0) + 1
            p.tbbGlobalGroupNextId = ident
            local groupId = "g" .. ident
            local L = CludesUI and CludesUI.L
            local record = {
                name = mod.TBBGroupName(groupKey) or ((L and L("Group") or "Group") .. " " .. groupKey),
                grow = GroupGrowOf(t, groupKey),
                spacing = GroupSpacingOf(t, groupKey),
            }
            local ai = mod.TBBGroupAnchorIndex(groupKey)
            local place = ai and mod.GetTBBPositions()[tostring(ai)]
            if place and place.point then
                record.pos = { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
            end
            registry[groupId] = record
            g.globalKey = groupId
        else
            local groupId = g.globalKey
            g.globalKey = nil
            local record = groupId and mod.TBBGlobalGroup(groupId)
            if record then
                g.name = record.name
                g.grow = record.grow
                g.spacing = record.spacing
                if groupKey == 1 then
                    t.groupGrowDirection = record.grow
                    t.groupSpacing = record.spacing
                end
                SetReflowDirty(true)
                if record.pos then
                    local posDB = mod.GetTBBPositions()
                    for jdx, c in ipairs(t.bars or {}) do
                        if mod.TBBBarGroupID(c) == groupKey then
                            posDB[tostring(jdx)] = {
                                point = record.pos.point,
                                relPoint = record.pos.relPoint,
                                x = record.pos.x,
                                y = record.pos.y,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Growth-edge extent: when an element anchors to the side of a tracking bar group
    -- that MATCHES the group's growth direction (TOP of an upward-growing group, LEFT
    -- of a leftward one), the anchor edge follows the outermost VISIBLE member instead
    -- of the static anchor bar, so it rides the stack as bars appear/fade. Every other
    -- side/target combo is untouched: the provider returns nil and the anchor system
    -- uses the frame's own bounds.
    local GROW_TO_SIDE = { UP = "TOP", DOWN = "BOTTOM", LEFT = "LEFT", RIGHT = "RIGHT" }

    -- Resolve an anchor target key to a group id IF the anchored side matches that group's growth direction (nil otherwise).
    function mod.TBBExtentGidForTarget(targetKey, edgeSide)
        if type(targetKey) ~= "string" or not edgeSide then
            return nil
        end
        local groupKey
        local groupId = targetKey:match("^TBBG_(.+)$")
        if groupId then
            groupKey = mod.TBBLocalGidForGlobal(groupId)
        else
            local position = tonumber(targetKey:match("^TBB_(%d+)$"))
            if not position then
                return nil
            end
            local t = mod.GetTrackedBuffBars()
            local c = t.bars and t.bars[position]
            groupKey = c and mod.TBBBarGroupID(c) or 0
            if groupKey == 0 or position ~= mod.TBBGroupAnchorIndex(groupKey) then
                return nil
            end
        end
        if not groupKey then
            return nil
        end
        local grow = (mod.TBBGroupGrow(groupKey) or "DOWN"):upper()
        if edgeSide ~= "POINT" and GROW_TO_SIDE[grow] ~= edgeSide then
            return nil
        end
        return groupKey
    end

    -- Anchor-system hook: outermost visible member edge in UIParent space, or nil to use
    -- the target frame's own bounds. Inert while unlock mode or the placeholder preview owns positions.
    function CludesUI._GetAnchorTargetExtent(targetKey, edgeSide)
        if CludesUI._unlockActive or mod._tbbPlaceholderMode then
            return nil
        end
        local groupKey = mod.TBBExtentGidForTarget(targetKey, edgeSide)
        if not groupKey then
            return nil
        end
        local t = mod.GetTrackedBuffBars()
        local uiS = UIParent:GetEffectiveScale()
        local bestMatch
        for i, c in ipairs(t.bars or {}) do
            if c.enabled ~= false and mod.TBBBarGroupID(c) == groupKey then
                local frame = tbbFrames[i]
                if frame and frame:IsShown() and frame:GetLeft() then
                    local fS = frame:GetEffectiveScale() / uiS
                    local val
                    if edgeSide == "TOP" then
                        val = (frame:GetTop() or 0) * fS
                    elseif edgeSide == "BOTTOM" then
                        val = (frame:GetBottom() or 0) * fS
                    elseif edgeSide == "LEFT" then
                        val = (frame:GetLeft() or 0) * fS
                    else
                        val = (frame:GetRight() or 0) * fS
                    end
                    if not bestMatch then
                        bestMatch = val
                    elseif edgeSide == "TOP" or edgeSide == "RIGHT" then
                        if val > bestMatch then
                            bestMatch = val
                        end
                    elseif val < bestMatch then
                        bestMatch = val
                    end
                end
            end
        end
        return bestMatch
    end

    -- gid -> anchored unlock key needing extent updates. Memo invalidation: the unlock
    -- module bumps _anchorLinksStamp on link changes; RegisterTBBUnlockElements nils the
    -- memo on every build (grow/membership/spec changes).
    local function RebuildExtentWatch()
        local wid = {}
        local anchors = CludesUIDB and CludesUIDB.unlockAnchors
        if anchors then
            for _, details in pairs(anchors) do
                if details.target then
                    local groupKey = mod.TBBExtentGidForTarget(
                        details.target,
                        details.mode == "POINT" and "POINT" or details.side
                    )
                    if groupKey then
                        wid[groupKey] = details.target
                    end
                end
                local fb = details.fallback
                if fb and fb.target then
                    local groupKey = mod.TBBExtentGidForTarget(fb.target, fb.side)
                    if groupKey then
                        wid[groupKey] = fb.target
                    end
                end
            end
        end
        return wid
    end

    local function TBBExtentWatchKey(groupKey)
        if not groupKey or groupKey == 0 then
            return nil
        end
        local stamp = CludesUI._anchorLinksStamp or 0
        local wid = mod._tbbExtentWatch
        if not wid or mod._tbbExtentWatchStamp ~= stamp then
            wid = RebuildExtentWatch()
            mod._tbbExtentWatch = wid
            mod._tbbExtentWatchStamp = stamp
        end
        return wid[groupKey]
    end

    -- Called by the reflow only when a group's visible footprint actually changed
    -- (change-gated there, NOT per-tick). Queues batched anchor propagation for the unlock key.
    function mod._NotifyTBBExtentChanged(groupKey)
        local key = TBBExtentWatchKey(groupKey)
        if not key then
            return
        end
        if CludesUI.PropagateAnchorChain then
            CludesUI.PropagateAnchorChain(key, "all")
        end
    end

    -- Remove a global group everywhere: every spec's linked group detaches with the shared
    -- values materialized locally (bars keep their positions), then the registry entry is deleted.
    function mod.TBBDeleteGlobalGroup(groupId)
        local registry = TBBGlobalDB(false)
        local record = registry and registry[groupId]
        if not record then
            return
        end
        local specRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
        if specRec then
            for _, profileTbl in pairs(specRec) do
                local trackBars = profileTbl.trackedBuffBars
                if trackBars and trackBars.groups then
                    for k, group in pairs(trackBars.groups) do
                        if group.globalKey == groupId then
                            group.globalKey = nil
                            group.name = record.name
                            group.grow = record.grow
                            group.spacing = record.spacing
                            if k == "1" then
                                trackBars.groupGrowDirection = record.grow
                                trackBars.groupSpacing = record.spacing
                            end
                            SetReflowDirty(true)
                            if record.pos then
                                if not profileTbl.tbbPositions then
                                    profileTbl.tbbPositions = {}
                                end
                                local kn = tonumber(k)
                                for jdx, c in ipairs(trackBars.bars or {}) do
                                    if mod.TBBBarGroupID(c) == kn then
                                        profileTbl.tbbPositions[tostring(jdx)] = {
                                            point = record.pos.point,
                                            relPoint = record.pos.relPoint,
                                            x = record.pos.x,
                                            y = record.pos.y,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        registry[groupId] = nil
        -- Retire the group's shift stand-in with it: a leftover frame would keep
        -- resolving through getFrame's session fallback and glue anchored
        -- elements to the deleted group's last position (audit-caught).
        local scrollFrame = tbbStandins[groupId]
        if scrollFrame then
            scrollFrame:Hide()
            tbbStandins[groupId] = nil
        end
    end
end

-- "Auto-Add New to This Group": the flagged group receives a bar for every spell newly
-- appearing in Blizzard's Tracked Bars section. At most ONE group holds the flag; enabling it clears the others.
function mod.TBBGroupAutoAdd(groupKey)
    local t = mod.GetTrackedBuffBars()
    local g = TBBGroupStore(t, groupKey, false)
    return g ~= nil and g.autoAdd == true
end

function mod.TBBSetGroupAutoAdd(groupKey, val)
    local t = mod.GetTrackedBuffBars()
    if val then
        if t.groups then
            for _, group in pairs(t.groups) do
                group.autoAdd = nil
            end
        end
        TBBGroupStore(t, groupKey, true).autoAdd = true
    else
        local g = TBBGroupStore(t, groupKey, false)
        if g then
            g.autoAdd = nil
        end
    end
end

-- The group flagged for auto-add (or nil). Smallest id wins if a stale table somehow carries more than one flag.
function mod.TBBAutoAddGroupID()
    local t = mod.GetTrackedBuffBars()
    if not t.groups then
        return nil
    end
    local bestMatch
    for k, group in pairs(t.groups) do
        if group.autoAdd == true then
            local groupKey = tonumber(k)
            if groupKey and (not bestMatch or groupKey < bestMatch) then
                bestMatch = groupKey
            end
        end
    end
    return bestMatch
end

-- Index of a group's anchor = its first enabled member (or nil if none). gid nil = group 1 (legacy callers).
function mod.TBBGroupAnchorIndex(groupKey)
    groupKey = groupKey or 1
    local t = mod.GetTrackedBuffBars()
    for i, c in ipairs(t.bars or {}) do
        if c.enabled ~= false and mod.TBBBarGroupID(c) == groupKey then
            return i
        end
    end
    return nil
end

-- Member count: with gid, counts that group's bars (regardless of enabled); without, counts bars in ANY group (drives options disabled gates).
function mod.TBBGroupedCount(groupKey)
    local t = mod.GetTrackedBuffBars()
    local num = 0
    for _, c in ipairs(t.bars or {}) do
        local g = mod.TBBBarGroupID(c)
        if (groupKey and g == groupKey) or (not groupKey and g ~= 0) then
            num = num + 1
        end
    end
    return num
end

-- Groups are orientation-uniform (shared width/height only make sense if every member
-- reads dimensions the same way). The group's FIRST member defines the orientation; a
-- disagreeing member (preset on one bar, cross-spec copy, import) is coerced, swapping
-- its stored dims so on-screen proportions carry over. Runs every rebuild; the options
-- Vertical Orientation toggle flips the whole group explicitly so deliberate flips
-- never fight it.
function mod.EnforceTBBGroupOrientation(trackBars)
    trackBars = trackBars or mod.GetTrackedBuffBars()
    local firstOrient = {}
    for _, conf in ipairs(trackBars.bars or {}) do
        local groupKey = mod.TBBBarGroupID(conf)
        if groupKey ~= 0 then
            local wanted = firstOrient[groupKey]
            local mine = conf.verticalOrientation and true or false
            if wanted == nil then
                firstOrient[groupKey] = mine
            elseif mine ~= wanted then
                conf.width, conf.height = (conf.height or 24), (conf.width or 270)
                conf.verticalOrientation = wanted
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Style copy
--  A bar's "style" = every visual key EXCEPT tracked spell identity, enable state,
--  group membership, and stack-threshold/stack-based-fill keys (spell-specific;
--  matches AddTrackedBuffBar's reset set) -- a copied style must never carry
--  threshold numbers.
-------------------------------------------------------------------------------
local TBB_STYLE_KEYS = {
    "height",
    "width",
    "verticalOrientation",
    "reverseFill",
    "fillUp",
    "chargeHashLines",
    "chargeHashLineWidth",
    "chargeHashLineR",
    "chargeHashLineG",
    "chargeHashLineB",
    "chargeHashLineA",
    "chargeHashShade",
    "chargeHashShadeAlpha",
    "texture",
    "strata",
    "fillColorMode",
    "fillR",
    "fillG",
    "fillB",
    "fillA",
    "bgR",
    "bgG",
    "bgB",
    "bgA",
    "gradientEnabled",
    "gradientR",
    "gradientG",
    "gradientB",
    "gradientA",
    "gradientDir",
    "opacity",
    "hideWhenInactive",
    "onlyInCombat",
    -- Visibility rides along because the onlyInCombat toggle it replaced already did: a new
    -- bar inheriting a neighbour's style, or one joining a group, kept that gate before.
    "barVisibility",
    "visibilityModes",
    "visibilityMatch",
    -- The option lanes themselves are appended from the shared list below.
    "showTimer",
    "timerPosition",
    "timerSize",
    "timerX",
    "timerY",
    "timerTextR",
    "timerTextG",
    "timerTextB",
    "timerTextA",
    "timerDecimals",
    "timerDecimalThreshold",
    "showName",
    "namePosition",
    "nameSize",
    "nameX",
    "nameY",
    "nameTextR",
    "nameTextG",
    "nameTextB",
    "nameTextA",
    "showSpark",
    "iconDisplay",
    "iconSize",
    "iconX",
    "iconY",
    "iconBorderSize",
    "stacksPosition",
    "stacksSize",
    "stacksX",
    "stacksY",
    "stacksTextR",
    "stacksTextG",
    "stacksTextB",
    "stacksTextA",
    "borderSize",
    "borderSizePx",
    "borderTexture",
    "borderR",
    "borderG",
    "borderB",
    "borderTextureOffset",
    "borderTextureOffsetY",
    "borderTextureShiftX",
    "borderTextureShiftY",
    "borderBehind",
    "stockBorderScale",
    "pandemicGlow",
    "pandemicGlowStyle",
    "pandemicGlowColor",
    "pandemicGlowMode",
    "pandemicGlowLines",
    "pandemicGlowThickness",
    "pandemicGlowSpeed",
    "pandemicGlowBackground",
    "pandemicGlowBackgroundColor",
}
-- Appended rather than spelled out: a lane added to the shared list is copied with the
-- rest of the style instead of silently staying behind on the source bar.
if CludesUI.VIS_OPT_KEYS then
    for i = 1, #CludesUI.VIS_OPT_KEYS do
        TBB_STYLE_KEYS[#TBB_STYLE_KEYS + 1] = CludesUI.VIS_OPT_KEYS[i]
    end
end
mod.TBB_STYLE_KEYS = TBB_STYLE_KEYS

-- Copy src's visual style onto dst, key-exact (including nil) so both bars resolve defaults
-- identically. Table values (glow color) are deep-copied so the two never share a mutable table.
function mod.CopyTBBStyle(source, dst)
    if not source or not dst or source == dst then
        return
    end
    for _, k in ipairs(TBB_STYLE_KEYS) do
        local val = source[k]
        if type(val) == "table" then
            local copy = {}
            for tk, tv in pairs(val) do
                copy[tk] = tv
            end
            val = copy
        end
        dst[k] = val
    end
end

-- The bar whose style represents a group: its anchor, or (all members disabled) its first member.
function mod.TBBGroupStyleSource(groupKey)
    if not groupKey or groupKey == 0 then
        return nil
    end
    local t = mod.GetTrackedBuffBars()
    local ai = mod.TBBGroupAnchorIndex(groupKey)
    if ai then
        return t.bars[ai]
    end
    for _, c in ipairs(t.bars or {}) do
        if mod.TBBBarGroupID(c) == groupKey then
            return c
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Style presets (PROFILE-scoped: persist across specs, travel with profile
--  export). Entry = { name, style = {<TBB_STYLE_KEYS values>} }. A bar
--  remembers the preset last applied to it (cfg.stylePresetName) so new bars
--  can resolve a preset by association.
-------------------------------------------------------------------------------
function mod.GetTBBStylePresets()
    if not (ECME and ECME.db) then
        SetECME(mod.ECME)
    end
    local p = ECME and ECME.db and ECME.db.profile
    if not p then
        return nil
    end
    if not p.tbbStylePresets then
        p.tbbStylePresets = {}
    end
    -- Same icon-footprint fold as GetTrackedBuffBars: legacy presets stored the FILL size rather than the icon-inclusive total.
    if not p._tbbPresetIconTotal then
        for _, presetRec in ipairs(p.tbbStylePresets) do
            local s = presetRec.style
            if s and (s.iconDisplay or "none") ~= "none" then
                if s.verticalOrientation then
                    s.height = (s.height or 24) + (s.width or 270)
                else
                    s.width = (s.width or 270) + (s.height or 24)
                end
            end
        end
        p._tbbPresetIconTotal = true
    end
    return p.tbbStylePresets
end

function mod.FindTBBStylePreset(label)
    if not label or label == "" then
        return nil
    end
    local presetList = mod.GetTBBStylePresets()
    if not presetList then
        return nil
    end
    for _, presetRec in ipairs(presetList) do
        if presetRec.name == label then
            return presetRec
        end
    end
    return nil
end

-- Save (or overwrite) a preset from a bar's current style, and associate the source bar with it.
function mod.SaveTBBStylePreset(label, srcCfg)
    if not label or label == "" or not srcCfg then
        return nil
    end
    local presetList = mod.GetTBBStylePresets()
    if not presetList then
        return nil
    end
    local style = {}
    mod.CopyTBBStyle(srcCfg, style)
    local presetRec = mod.FindTBBStylePreset(label)
    if presetRec then
        presetRec.style = style
    else
        presetRec = { name = label, style = style }
        presetList[#presetList + 1] = presetRec
    end
    srcCfg.stylePresetName = label
    return presetRec
end

function mod.ApplyTBBStylePresetToCfg(preset, conf)
    if not preset or not preset.style or not conf then
        return
    end
    mod.CopyTBBStyle(preset.style, conf)
    conf.stylePresetName = preset.name
end

-- Delete a saved preset. Bar associations (cfg.stylePresetName) are left in place and go inert: FindTBBStylePreset returns nil for a missing name.
function mod.DeleteTBBStylePreset(label)
    if not label or label == "" then
        return false
    end
    local presetList = mod.GetTBBStylePresets()
    if not presetList then
        return false
    end
    for i, presetRec in ipairs(presetList) do
        if presetRec.name == label then
            table.remove(presetList, i)
            local p = ECME and ECME.db and ECME.db.profile
            if p and p.tbbSelectedStylePreset == label then
                p.tbbSelectedStylePreset = nil
            end
            return true
        end
    end
    return false
end

-- Rename a preset, carrying bar associations (across every spec of the active profile) and the UI selection pointer with it.
function mod.RenameTBBStylePreset(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then
        return false
    end
    if oldName == newName or mod.FindTBBStylePreset(newName) then
        return false
    end
    local presetRec = mod.FindTBBStylePreset(oldName)
    if not presetRec then
        return false
    end
    presetRec.name = newName
    local specRec = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if specRec then
        for _, profileTbl in pairs(specRec) do
            local barList = type(profileTbl) == "table" and profileTbl.trackedBuffBars and profileTbl.trackedBuffBars.bars
            if barList then
                for _, c in ipairs(barList) do
                    if c.stylePresetName == oldName then
                        c.stylePresetName = newName
                    end
                end
            end
        end
    end
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.tbbSelectedStylePreset == oldName then
        p.tbbSelectedStylePreset = newName
    end
    return true
end

-- New-bar resolution: the preset associated with a bar already in the target group (nil if none).
function mod.ResolveTBBGroupPreset(trackBars, groupKey)
    if not groupKey or groupKey == 0 then
        return nil
    end
    for _, c in ipairs(trackBars.bars or {}) do
        if mod.TBBBarGroupID(c) == groupKey then
            local presetRec = mod.FindTBBStylePreset(c.stylePresetName)
            if presetRec then
                return presetRec
            end
        end
    end
    return nil
end

-- New-bar fallback: a preset associated with any bar of this spec, else any saved preset (nil when none are saved).
function mod.ResolveTBBFallbackPreset(trackBars)
    local presetList = mod.GetTBBStylePresets()
    if not presetList or #presetList == 0 then
        return nil
    end
    for _, c in ipairs(trackBars.bars or {}) do
        local presetRec = mod.FindTBBStylePreset(c.stylePresetName)
        if presetRec then
            return presetRec
        end
    end
    return presetList[1]
end

-- Runtime reflow for grouped Tracking Bars: BuildTrackedBuffBars creates the static
-- group chain, but the tick decides which bars are visible, so only visible grouped
-- members are reflowed to leave no holes when a buff is inactive/hidden -- e.g. with
-- configured order Buff 1/2/3 and only 2/3 active, Buff 2 sits at the group anchor.
local _tbbReflowStates = {} -- gid -> pooled per-group reflow state
local function GetReflowState(groupKey)
    local state = _tbbReflowStates[groupKey]
    if not state then
        state = { visible = {}, lastIdx = {}, lastCount = 0, lastGrow = nil, lastSpacing = nil }
        _tbbReflowStates[groupKey] = state
    end
    return state
end
local function ResetReflowStates()
    for _, state in pairs(_tbbReflowStates) do
        state.lastCount = -1
    end
end
local _tbbReflowDone = {} -- reused per-tick "group handled" set

local function ReflowGroup(trackBars, groupKey, barList)
    local state = GetReflowState(groupKey)

    local anchorIdx
    for i, c in ipairs(barList) do
        if c.enabled ~= false and mod.TBBBarGroupID(c) == groupKey then
            anchorIdx = i
            break
        end
    end
    if not anchorIdx then
        return
    end

    local growDirection = (GroupGrowOf(trackBars, groupKey) or "DOWN"):upper()
    local spacing = GroupSpacingOf(trackBars, groupKey) or 2

    -- Collect this group's enabled + visible bars in saved hierarchy order. A bar with
    -- hideWhenInactive=false is visible so it keeps its slot (shows inactive bars). Entry
    -- tables are pooled and reused across ticks: zero allocation in this every-16ms path.
    local visible = state.visible
    local total = 0
    for i, conf in ipairs(barList) do
        local frame = tbbFrames[i]
        if
            conf
            and conf.enabled ~= false
            and mod.TBBBarGroupID(conf) == groupKey
            and frame
            and frame._tbbReady
            and frame:IsShown()
        then
            total = total + 1
            local e = visible[total]
            if not e then
                e = {}
                visible[total] = e
            end
            e.idx = i
            e.frame = frame
        end
    end

    if total == 0 then
        -- Group fully collapsed: anchored elements fall back to the anchor bar's own (hidden but resolvable) bounds. Notify once.
        if state.lastCount ~= 0 and mod._NotifyTBBExtentChanged then
            mod._NotifyTBBExtentChanged(groupKey)
        end
        state.lastCount = 0
        return
    end

    -- Re-anchor only when the visible member sequence or the grow/spacing tuple changes. Compared element-wise so no string is allocated per tick.
    local lastIdx = state.lastIdx
    local changed = total ~= state.lastCount or growDirection ~= state.lastGrow or spacing ~= state.lastSpacing
    if not changed then
        for num = 1, total do
            if visible[num].idx ~= lastIdx[num] then
                changed = true
                break
            end
        end
    end
    if not changed then
        return
    end
    state.lastCount = total
    state.lastGrow = growDirection
    state.lastSpacing = spacing
    for num = 1, total do
        lastIdx[num] = visible[num].idx
    end

    local first = visible[1].frame
    local anchor = tbbFrames[anchorIdx]

    if anchor and anchor ~= first then
        -- Configured anchor buff is inactive/hidden: pin the first VISIBLE member onto the
        -- anchor frame's slot so it takes the group origin. The anchor frame keeps whatever
        -- position BuildTrackedBuffBars/the unlock system gave it (element anchoring included).
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
    -- else the first visible bar IS the anchor: NEVER touch its point. BuildTrackedBuffBars
    -- and the unlock system already position it and honor IsUnlockAnchored, so re-deriving
    -- from tbbPositions would clobber an element-anchored group (stale coord/screen center).

    local previous = first
    for num = 2, total do
        local frame = visible[num].frame
        frame:ClearAllPoints()
        if growDirection == "DOWN" then
            frame:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
        elseif growDirection == "UP" then
            frame:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
        elseif growDirection == "RIGHT" then
            frame:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
        elseif growDirection == "LEFT" then
            frame:SetPoint("RIGHT", previous, "LEFT", -spacing, 0)
        else
            frame:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
        end
        previous = frame
    end

    -- Only reached when the visible sequence/grow/spacing actually changed: let elements anchored to the group's growth side re-read the moving edge.
    if mod._NotifyTBBExtentChanged then
        mod._NotifyTBBExtentChanged(groupKey)
    end
end

local function ReflowVisibleGroupedTBBars(trackBars, barList)
    if not (trackBars and barList and tbbFrames) then
        return
    end
    -- Never fight edit-preview (placeholder) or unlock-mode dragging: there BuildTrackedBuffBars and the unlock system own bar positions.
    if mod._tbbPlaceholderMode or CludesUI._unlockActive then
        return
    end
    -- Reflow each present group once; the done-set is reused across ticks so this pass allocates nothing.
    SetReflowDirty(false)
    wipe(_tbbReflowDone)
    for _, conf in ipairs(barList) do
        local groupKey = mod.TBBBarGroupID(conf)
        if groupKey ~= 0 and not _tbbReflowDone[groupKey] then
            _tbbReflowDone[groupKey] = true
            ReflowGroup(trackBars, groupKey, barList)
        end
    end
end

-- Fan a width/height change from a grouped bar to every sibling in the SAME group:
-- write each sibling's LOGICAL cfg.width/cfg.height (NOT icon-inclusive total) and
-- resize its frame with its OWN icon math. Used by options sliders, unlock
-- drag-resize and size-MATCH; re-entrancy guarded so a sibling write cannot recurse.
local _tbbGroupSizing = false
function mod.PropagateTBBGroupSize(srcIdx, size, value)
    if _tbbGroupSizing then
        return
    end
    local t = mod.GetTrackedBuffBars()
    local barList = t.bars
    if not barList then
        return
    end
    local source = barList[srcIdx]
    local srcGid = source and mod.TBBBarGroupID(source) or 0
    if srcGid == 0 then
        return
    end
    _tbbGroupSizing = true
    for i, c in ipairs(barList) do
        if i ~= srcIdx and mod.TBBBarGroupID(c) == srcGid then
            c[size] = value
            local frame = tbbFrames[i]
            if frame then
                -- width/height are the total footprint (icon included), so the frame takes the value directly.
                if size == "width" then
                    frame:SetWidth(value)
                else
                    frame:SetHeight(value)
                end
            end
        end
    end
    _tbbGroupSizing = false
end

function mod.IsTBBRebuildPending()
    return _tbbRebuildPending
end

Inner._MarkTBBReflowDirty, Inner._tbbWake, Inner.GroupGrowOf = _MarkTBBReflowDirty, _tbbWake, GroupGrowOf
Inner.GroupSpacingOf, Inner.ReflowVisibleGroupedTBBars = GroupSpacingOf, ReflowVisibleGroupedTBBars
Inner.ResetReflowStates, Inner.tbbFrames = ResetReflowStates, tbbFrames
Inner.broken = false
