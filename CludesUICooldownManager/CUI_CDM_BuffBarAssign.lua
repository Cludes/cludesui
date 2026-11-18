if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarAssign.lua
--
--  Pairing of the Blizzard viewer frames with the bar configs, the buff
--  gain/loss sounds and auto-add.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pcall = pcall

local AddTrackedBuffBarCore, SetECME = Inner.AddTrackedBuffBarCore, Inner.SetECME
local SetAssignDirty = Inner.SetAssignDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val)
    ECME = val
end
-- Assignment memo gate: cfg->frame pairing changes only on viewer pool composition
-- edges (aura events, pool Acquire, rebuilds, spec/cache invalidation); the tick
-- reuses the last pairing until dirtied. Starts dirty so the first tick always pairs.
local _tbbAssignDirty = true
Inner.assignDirtySetters[#Inner.assignDirtySetters + 1] = function(val)
    _tbbAssignDirty = val
end
local _tbbAssignedFor

-------------------------------------------------------------------------------
--  CDM Child Lookup
--  Iterates the BuffBarCooldownViewer pool directly (tiny, 3-5 frames).
--  Matches by cooldownID first (cached on cfg), then by spell ID variants from
--  cooldownInfo. No external caches, no stale data in combat.
-------------------------------------------------------------------------------
-- cfg -> base-spell id seen once, awaiting a confirming second pass before the
-- permanent cfg.baseSpellID write (a pool frame mid-reuse can echo another
-- slot's ids for one pass). Separate table: frame-adjacent state must never
-- ride the config into SavedVariables.
local _tbbBaseCapturePending = {}

local function MatchesSID(details, spellRef)
    -- cooldownInfo id fields can read SECRET in restricted content, and a
    -- secret on either side of == hard-errors: every compare is gated. sid is
    -- the caller's cfg-side id (plain by contract).
    local secret = issecretvalue
    if not (secret and secret(details.overrideSpellID)) and details.overrideSpellID == spellRef then
        return true
    end
    if not (secret and secret(details.spellID)) and details.spellID == spellRef then
        return true
    end
    if details.linkedSpellIDs then
        for _, lid in ipairs(details.linkedSpellIDs) do
            if not (secret and secret(lid)) and lid == spellRef then
                return true
            end
        end
    end
    return false
end

local function MatchFrameToConfig(widget, conf)
    -- Cooldown-tracking bars are self-driven and never bind a viewer frame.
    if conf.trackType == "cooldown" then
        return false
    end
    local cooldownId = widget.cooldownID
    if not cooldownId then
        return false
    end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then
        return false
    end
    local details = gci(cooldownId)
    if not details then
        return false
    end
    -- Self-healing base capture for hero-talent override spells. A bar saved
    -- for the OVERRIDE form, matched while talented, sees the override in
    -- info.overrideSpellID and the BASE form in info.spellID. Record the base
    -- on the config so the bar keeps matching once the talent is removed:
    -- cooldownInfo carries the override id ONLY while talented, so without the
    -- stored base the bar goes dark when untalented (the cast becomes the base
    -- spell). Also backfills bars saved without a pick-time baseSpellID.
    local secret = issecretvalue
    if
        conf.spellID
        and conf.spellID > 0
        and not conf.baseSpellID
        and not (secret and secret(details.overrideSpellID))
        and not (secret and secret(details.spellID))
        and details.overrideSpellID == conf.spellID
        and details.spellID
        and details.spellID > 0
        and details.spellID ~= conf.spellID
    then
        -- Two matching reads on separate passes before committing: the write is
        -- permanent (SavedVariables), so a single transient echo from a frame
        -- mid-reuse must never corrupt the config's identity.
        if _tbbBaseCapturePending[conf] == details.spellID then
            conf.baseSpellID = details.spellID
            _tbbBaseCapturePending[conf] = nil
        else
            _tbbBaseCapturePending[conf] = details.spellID
        end
    end
    -- Fast path: match via cooldownInfo struct fields.
    if conf.spellIDs then
        for _, spellRef in ipairs(conf.spellIDs) do
            if MatchesSID(details, spellRef) then
                return true
            end
        end
    elseif conf.spellID and conf.spellID > 0 then
        if MatchesSID(details, conf.spellID) then
            return true
        end
        -- Talent-override fallback: a bar saved for the override form also tracks its base, so it keeps showing after the talent is removed.
        if conf.baseSpellID and conf.baseSpellID > 0 and MatchesSID(details, conf.baseSpellID) then
            return true
        end
    else
        return false
    end
    -- Fallback: the frame's canonical spell ID. Buff bar frames expose the actual aura
    -- variant via GetAuraSpellID, which may not appear in the cooldownInfo struct (e.g. Eclipse Solar/Lunar).
    local GetCanonical = mod.GetCanonicalSpellIDForFrame
    if GetCanonical then
        local frameSID = GetCanonical(widget)
        if frameSID then
            if conf.spellIDs then
                for _, spellRef in ipairs(conf.spellIDs) do
                    if frameSID == spellRef then
                        return true
                    end
                end
            elseif conf.spellID and conf.spellID > 0 then
                if frameSID == conf.spellID then
                    return true
                end
                if conf.baseSpellID and frameSID == conf.baseSpellID then
                    return true
                end
            end
        end
    end
    return false
end

local _findChildGeneration = 0
-- Frame cache lives in its own table, NEVER on the config (which is in SavedVariables): frame refs must not leak into serialization.
local _findChildCache = {}

-- Sticky cfg->frame bindings for the one-to-one assignment pass below (cfg table -> last
-- paired Blizzard frame). Separate table for the same serialization reason; dropped on cache invalidation.
local _tbbStickyFrame = {}
-- cooldownID each sticky frame carried when bound: the secret-trust branch can
-- only trust a binding while the pooled frame still serves the same cooldown
-- slot (Blizzard reuses frame objects fast in combat). cooldownID stays a
-- plain readable number in secret windows (the clean-sid cache keys on it).
local _tbbStickyCdID = {}

function mod.InvalidateTBBFrameCache()
    _findChildGeneration = _findChildGeneration + 1
    wipe(_findChildCache)
    wipe(_tbbStickyFrame)
    wipe(_tbbStickyCdID)
    wipe(_tbbBaseCapturePending)
    -- Every structural edge funnels here (pool Acquire, spec swap, rebuilds), so the assignment memo retires with the caches.
    SetAssignDirty(true)
end

local function FindChild(conf)
    -- Fast path: cached result from a previous match (hit or miss).
    local cachedValue = _findChildCache[conf]
    if cachedValue and cachedValue.gen == _findChildGeneration then
        if cachedValue.frame and cachedValue.frame.cooldownID == cachedValue.cdID then
            return cachedValue.frame
        end
    end
    -- Full scan: iterate BuffBarCooldownViewer pool (TBB's own viewer).
    local record = { gen = _findChildGeneration, frame = nil, cdID = nil }
    _findChildCache[conf] = record
    local viewerFrame = _G["BuffBarCooldownViewer"]
    if viewerFrame and viewerFrame.itemFramePool then
        for widget in viewerFrame.itemFramePool:EnumerateActive() do
            if MatchFrameToConfig(widget, conf) then
                record.frame = widget
                record.cdID = widget.cooldownID
                return widget
            end
        end
    end
    return nil
end
mod.FindTBBChild = FindChild

-------------------------------------------------------------------------------
--  AssignFramesToConfigs
--
--  Pairs each tracked-bar config to AT MOST ONE BuffBarCooldownViewer frame,
--  consuming every frame once so two configs can never mirror the same frame.
--  Required for multi-variant spells like Eclipse: Solar and Lunar share one
--  cooldownInfo (linkedSpellIDs lists both), so per-config FindChild() greedily
--  binds BOTH to whichever frame enumerates first ("Lunar twice, Solar never", and
--  the mirror case). Frame-driven matches the icon viewer: decorate one display per
--  Blizzard child rather than matching a stored spell back to an ambiguous frame.
--
--  Three passes, each only over still-unconsumed frames:
--    1. Sticky   -- reuse last tick's binding. Frame OBJECT identity never goes secret,
--       so a pairing locked out of combat survives GetAuraSpellID turning secret
--       mid-fight; revalidated against a clean read when one exists (self-heals a
--       recycled pool frame), trusted blindly while secret.
--    2. Exact    -- per-frame canonical id == the config's spell (clean reads pair
--       frameSolar->cfgSolar, frameLunar->cfgLunar); locks the sticky binding for future ticks.
--    3. Fallback -- cooldownInfo/linkedSpellIDs struct match for configs still unpaired
--       (combat, no prior sticky binding); consumption still guarantees no two configs land on the same frame.
--
--  Returns a cfg->frame map (a REUSED module table; copy it to retain it).
-------------------------------------------------------------------------------
local _tbbAssignment = {}
local _tbbFrameScratch = {}
local _tbbConsumed = {}
local _tbbFrameSID = {} -- frame -> canonical spell id, computed once per call
local _tbbFrameMember = {} -- frame -> live linked-family member, computed once per call

local function CfgWantsSID(conf, spellRef)
    -- Cooldown-tracking bars NEVER match buff-viewer frames or buff coverage.
    if conf.trackType == "cooldown" then
        return false
    end
    if not spellRef then
        return false
    end
    -- Tick paths feed raw aura/struct ids (icon, coverage): a secret survives
    -- the nil check and hard-errors on ==. Narrow matcher: secret = not
    -- provably ours.
    if issecretvalue and issecretvalue(spellRef) then
        return false
    end
    if conf.spellIDs then
        for _, s in ipairs(conf.spellIDs) do
            if s == spellRef then
                return true
            end
        end
        return false
    end
    if conf.spellID and conf.spellID > 0 then
        if spellRef == conf.spellID then
            return true
        end
        if conf.baseSpellID and conf.baseSpellID > 0 and spellRef == conf.baseSpellID then
            return true
        end
    end
    return false
end

local function FrameIsActive(frameList, target)
    for i = 1, #frameList do
        if frameList[i] == target then
            return true
        end
    end
    return false
end

-- Name FAMILY of a display name: the part before the first colon, lowered
-- ("Diabolic Ritual: Overlord" -> "diabolic ritual"; a name without a colon
-- is its own family). Disambiguates collided viewer slots whose aura names
-- share a canonical spellID but not a prefix. nil for empty/unreadable.
local function TbbNameFamily(label)
    if type(label) ~= "string" or label == "" then
        return nil
    end
    local i = label:find(":", 1, true)
    -- zhCN/zhTW labels separate variants with the fullwidth colon (U+FF1A;
    -- decimal byte escapes -- Lua 5.1 has no hex escapes).
    local jdx = label:find("\239\188\154", 1, true)
    if jdx and (not i or jdx < i) then
        i = jdx
    end
    local family = i and label:sub(1, i - 1) or label
    family = family:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if family == "" then
        return nil
    end
    return family
end

-- Live aura name family of a pool frame; nil when no clean aura read exists
-- (secret in restricted content, no bound instance) -- callers fall back to
-- first-match. Aura reads are the ONLY name source: never the frame's label.
local function TbbFrameNameFamily(widget)
    local iid = widget.auraInstanceID
    if not iid or (issecretvalue and issecretvalue(iid)) then
        return nil
    end
    local unitToken = widget.auraDataUnit
    if not unitToken then
        return nil
    end
    local success, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, iid)
    if not success or not ad then
        return nil
    end
    local spellName = ad.name
    if spellName == nil or (issecretvalue and issecretvalue(spellName)) then
        return nil
    end
    return TbbNameFamily(spellName)
end

-- Which member of a LINKED FAMILY a buff slot is mirroring right now. Blizzard
-- binds ONE cooldownID to whichever of its linkedSpellIDs is on the player and
-- publishes the answer as cooldownInfo.linkedSpellID, maintained on the aura
-- edges (CooldownViewerItemMixin:NeedsAddedAuraUpdate / OnUnitAuraRemovedEvent),
-- so Roll the Bones cycles a single slot through every outcome and the hint
-- follows. Needed because GetSpellID()/GetAuraSpellID() read secret while the
-- slot is active, leaving the canonical resolver to answer from the clean-read
-- memo keyed on cooldownID, which still names the member that was up at the last
-- CLEAN read: the previous outcome keeps the frame and mirrors the new outcome's
-- timer while the new outcome draws a second bar off the per-spell aura fallback.
local function TbbLinkedMemberSID(widget)
    local details = widget.cooldownInfo
    if not details then
        local fnGetInfo = widget.GetCooldownInfo
        if type(fnGetInfo) ~= "function" then
            return nil
        end
        details = fnGetInfo(widget)
    end
    local linked = details and details.linkedSpellIDs
    if type(linked) ~= "table" or #linked < 2 then
        return nil
    end
    -- Set from the added aura's spellId, so it can be secret in restricted content.
    local spellRef = details.linkedSpellID
    if type(spellRef) ~= "number" or (issecretvalue and issecretvalue(spellRef)) then
        return nil
    end
    return spellRef
end

-- Per-config name families for label/binding compatibility: cfg.name (the
-- picker's display name) plus the resolved spellID/baseSpellID names.
-- Weak-keyed memo; every input is re-checked on hit so options edits
-- self-invalidate, and entries with unloaded spell data retry until resolved
-- (same class as the deferred name fill).
local _tbbCfgFamilies = setmetatable({}, { __mode = "k" })

local function TbbCfgFamilies(conf)
    local e = _tbbCfgFamilies[conf]
    if e and not e.retry and e.nm == conf.name and e.sid == conf.spellID and e.bsid == conf.baseSpellID then
        return e
    end
    if not e then
        e = {}
        _tbbCfgFamilies[conf] = e
    end
    e.nm, e.sid, e.bsid = conf.name, conf.spellID, conf.baseSpellID
    e.retry = nil
    e.f1 = TbbNameFamily(conf.name)
    e.f2, e.f3 = nil, nil
    if conf.spellID and conf.spellID > 0 then
        local spellInfo = C_Spell.GetSpellInfo(conf.spellID)
        if spellInfo and spellInfo.name then
            e.f2 = TbbNameFamily(spellInfo.name)
        else
            e.retry = true
        end
    end
    if conf.baseSpellID and conf.baseSpellID > 0 then
        local spellInfo = C_Spell.GetSpellInfo(conf.baseSpellID)
        if spellInfo and spellInfo.name then
            e.f3 = TbbNameFamily(spellInfo.name)
        else
            e.retry = true
        end
    end
    return e
end

-- Two families are compatible when equal or one extends the other ("eclipse"
-- vs "eclipse (solar)") -- variant naming keeps the base name as a prefix,
-- while different abilities ("spirit walk" vs "spirit wolf") never do.
local function TbbFamiliesCompatible(a, b)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end
    return a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1
end

-- fam vs ANY of the config's known families. openOnUnknown decides the
-- verdict when either side is unknowable (the label gate fails OPEN to
-- today's behavior; variant evidence fails CLOSED).
local function TbbCfgFamilyMatch(conf, family, openOnUnknown)
    local e = TbbCfgFamilies(conf)
    local f1, f2, f3 = e.f1, e.f2, e.f3
    if family == nil or not (f1 or f2 or f3) then
        return openOnUnknown
    end
    return TbbFamiliesCompatible(family, f1) or TbbFamiliesCompatible(family, f2) or TbbFamiliesCompatible(family, f3)
end

-- cooldownID -> definite "variant-labeled slot" verdict, session-long (cdIDs
-- are stable per session; verdicts only come from fully readable inputs). A
-- slot is variant-labeled when its linked forms resolve to MORE THAN ONE
-- distinct display string (Diabolist ritual trios, Eclipse Solar/Lunar) --
-- the only case where a SECRET label can say something the config name
-- cannot. Field 2026-08: a hidden pool frame can render another slot's text
-- persistently after re-acquire, so unproven slots never paint secret labels.
local _tbbVariantSlot = {}

local function TbbSlotVariantLabeled(barFrame, cooldownId)
    if type(cooldownId) ~= "number" or (issecretvalue and issecretvalue(cooldownId)) then
        return false
    end
    local known = _tbbVariantSlot[cooldownId]
    if known ~= nil then
        return known
    end
    -- In combat one indefinite probe is pinned per binding (secret linked ids
    -- would otherwise re-derive at 60Hz); out of combat retries until the
    -- verdict is definite (spell data load is the only wait).
    if barFrame._varProbeCd == cooldownId and InCombatLockdown() then
        return barFrame._varProbeVal or false
    end
    local verdict, complete = false, false
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local success, details = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownId)
        if success and details then
            local secret = issecretvalue
            local lids = details.linkedSpellIDs
            if not lids or #lids == 0 then
                -- No linked forms at all: definitively single-labeled.
                _tbbVariantSlot[cooldownId] = false
                return false
            end
            complete = true
            local baseNm
            local bsid = details.spellID
            if bsid and not (secret and secret(bsid)) then
                local spellInfo = C_Spell.GetSpellInfo(bsid)
                local spellName = spellInfo and spellInfo.name
                if spellName and not (secret and secret(spellName)) then
                    baseNm = spellName:lower()
                end
            end
            if not baseNm then
                complete = false
            end
            local firstNm
            for k = 1, #lids do
                local lid = lids[k]
                local spellName
                if type(lid) == "number" and not (secret and secret(lid)) then
                    local spellInfo = C_Spell.GetSpellInfo(lid)
                    spellName = spellInfo and spellInfo.name
                    if spellName and (secret and secret(spellName)) then
                        spellName = nil
                    end
                end
                if not spellName then
                    complete = false
                else
                    spellName = spellName:lower()
                    if baseNm and spellName ~= baseNm then
                        verdict = true
                        break
                    end
                    if firstNm == nil then
                        firstNm = spellName
                    elseif spellName ~= firstNm then
                        verdict = true
                        break
                    end
                end
            end
        end
    end
    if verdict or complete then
        _tbbVariantSlot[cooldownId] = verdict
    else
        barFrame._varProbeCd, barFrame._varProbeVal = cooldownId, verdict
    end
    return verdict
end

-- Pass-3 candidate veto: a fuzzy struct match (linked-group membership) can
-- be a mechanically different neighbor -- Blizzard links Spirit Walk into the
-- Spirit Wolf slot's group, and with Spirit Walk's own frame inactive the
-- neighbor is the UNIQUE match (field 2026-08). A READABLE live aura name
-- that is family-incompatible with the config rejects the candidate;
-- secret/unreadable fails open so variant slots stay bindable in combat.
local function TbbFuzzyNameOK(conf, widget)
    local family = TbbFrameNameFamily(widget)
    if not family then
        return true
    end
    return TbbCfgFamilyMatch(conf, family, true)
end

local function AssignFramesToConfigs(barList)
    local assignedBar = _tbbAssignment
    -- Memo: pairing moves only on composition edges (player aura events, pool
    -- Acquire, cache invalidation, rebuilds -- all set the dirty flag), so the
    -- ~60Hz tick reuses the last map instead of re-enumerating the pool and
    -- re-resolving canonical ids every frame. Bars-table identity check is the
    -- belt for spec swaps that replace the table without hitting an invalidation site.
    if not _tbbAssignDirty and _tbbAssignedFor == barList then
        return assignedBar
    end
    SetAssignDirty(false)
    _tbbAssignedFor = barList
    wipe(assignedBar)
    if not barList then
        return assignedBar
    end

    local viewerFrame = _G["BuffBarCooldownViewer"]
    if not viewerFrame or not viewerFrame.itemFramePool then
        return assignedBar
    end

    -- Snapshot the active pool once (EnumerateActive consumes the enumeration) and
    -- resolve each frame's canonical spell id ONCE -- otherwise the passes below
    -- re-query it O(configs x frames) per tick, each call pcalling live frame APIs.
    -- Caching also gives every pass a consistent within-tick view of frame identity.
    local GetCanonical = mod.GetCanonicalSpellIDForFrame
    local frameList = _tbbFrameScratch
    wipe(frameList)
    wipe(_tbbFrameSID)
    wipe(_tbbFrameMember)
    for widget in viewerFrame.itemFramePool:EnumerateActive() do
        frameList[#frameList + 1] = widget
        _tbbFrameSID[widget] = GetCanonical and GetCanonical(widget) or nil
        if widget.IsActive and widget:IsActive() then
            _tbbFrameMember[widget] = TbbLinkedMemberSID(widget)
        end
    end

    -- The family hint overrides the canonical memo only where (1) some enabled
    -- bar actually WANTS the member: a single bar tracking the family under
    -- its base/shared id must keep its per-slot memo, or the flip releases a
    -- working binding for nothing (claim-style gate; also keeps shared-id
    -- configs like Diabolist's on their memos if a variant stamp ever reads
    -- clean), and (2) it is UNIQUE among the active slots: collided slots each
    -- list the whole family (Eclipse Solar and Lunar, both up), so an added
    -- aura stamps the same member on BOTH and only their per-slot memos still
    -- tell them apart.
    for i = 1, #frameList do
        local m = _tbbFrameMember[frameList[i]]
        if m then
            local wanted = false
            for _, c in ipairs(barList) do
                if CfgWantsSID(c, m) then
                    wanted = true
                    break
                end
            end
            local unique = wanted
            if unique then
                for jdx = 1, #frameList do
                    if jdx ~= i and _tbbFrameMember[frameList[jdx]] == m then
                        unique = false
                        break
                    end
                end
            end
            if unique then
                _tbbFrameSID[frameList[i]] = m
            end
        end
    end

    local consumed = _tbbConsumed
    wipe(consumed)

    -- Pass 1: sticky.
    for _, conf in ipairs(barList) do
        local bound = _tbbStickyFrame[conf]
        -- A bar converted to cooldown tracking must release its old viewer-frame binding
        -- immediately: the secret-trust branch below never calls CfgWantsSID, so otherwise it would keep consuming the frame.
        if bound and conf.trackType == "cooldown" then
            _tbbStickyFrame[conf] = nil
            bound = nil
        end
        if bound and not consumed[bound] and FrameIsActive(frameList, bound) then
            local spellRef = _tbbFrameSID[bound]
            if spellRef then
                -- Clean read available: keep only if still the right variant AND
                -- (collided slots) still the right name family -- a crossed
                -- pairing must release here or pass 2 can never re-pair it.
                local keep = CfgWantsSID(conf, spellRef)
                if keep then
                    local want = TbbNameFamily(conf.name)
                    if want then
                        local family = TbbFrameNameFamily(bound)
                        if family and family ~= want then
                            keep = false
                        end
                    end
                end
                if keep then
                    assignedBar[conf] = bound
                    consumed[bound] = true
                    _tbbStickyCdID[conf] = bound.cooldownID
                else
                    _tbbStickyFrame[conf] = nil
                    _tbbStickyCdID[conf] = nil
                end
            elseif bound.cooldownID == _tbbStickyCdID[conf] then
                -- Secret/combat, but the frame still serves the cooldown slot it
                -- was bound under: trust the binding locked in earlier.
                assignedBar[conf] = bound
                consumed[bound] = true
            else
                -- Same frame object, different cooldown slot (pool reused it
                -- mid-secret-window) -- a stale binding here is exactly the
                -- wrong-name/wrong-icon report; drop it rather than guess.
                _tbbStickyFrame[conf] = nil
                _tbbStickyCdID[conf] = nil
            end
        end
    end

    -- Pass 2: exact per-frame identity. COLLIDED slots (two viewer slots
    -- sharing one canonical spellID -- Diabolist Demonic Art vs Diabolic
    -- Ritual, where Blizzard hands the Art slot the Ritual's id) fit two
    -- configs identically by sid, and a first-match pairing crosses them
    -- ("Diabolic Ritual" bar bound to the Art frame, faithfully naming
    -- Overlord). Tie-break by NAME FAMILY: the config keeps the picker's
    -- display name and the two slots' aura names differ by prefix, so among
    -- sid-matching frames the one whose live aura name shares the config
    -- name's prefix wins; unique matches take the fast path unchanged.
    for _, conf in ipairs(barList) do
        if not assignedBar[conf] then
            local pick
            local want = TbbNameFamily(conf.name)
            for i = 1, #frameList do
                local widget = frameList[i]
                if not consumed[widget] then
                    local spellRef = _tbbFrameSID[widget]
                    if spellRef and CfgWantsSID(conf, spellRef) then
                        if not want then
                            pick = widget
                            break
                        end
                        local family = TbbFrameNameFamily(widget)
                        if family == want then
                            pick = widget
                            break
                        end
                        -- Family unreadable/other: remember the first, keep looking
                        -- for a frame that actually names this config's family.
                        if not pick then
                            pick = widget
                        end
                    end
                end
            end
            if pick then
                assignedBar[conf] = pick
                consumed[pick] = true
                _tbbStickyFrame[conf] = pick
                _tbbStickyCdID[conf] = pick.cooldownID
            end
        end
    end

    -- Pass 3: cooldownInfo/linkedSpellIDs struct fallback. NEVER sticky a fuzzy
    -- match: let a later clean read re-pair it exactly in pass 2. Binds only
    -- when the match is unique BOTH ways (one frame fits this cfg, and no other
    -- unassigned cfg fits that frame) -- shared linkedSpellIDs data makes fuzzy
    -- matches ambiguous, and a guessed pairing is worse than a blank bar.
    for _, conf in ipairs(barList) do
        if not assignedBar[conf] then
            local candidate, matches = nil, 0
            for i = 1, #frameList do
                local widget = frameList[i]
                if
                    not consumed[widget]
                    and MatchFrameToConfig(widget, conf)
                    and TbbFuzzyNameOK(conf, widget)
                then
                    matches = matches + 1
                    candidate = widget
                end
            end
            if matches == 1 then
                local cfgMatches = 0
                for _, other in ipairs(barList) do
                    if
                        not assignedBar[other]
                        and MatchFrameToConfig(candidate, other)
                        and TbbFuzzyNameOK(other, candidate)
                    then
                        cfgMatches = cfgMatches + 1
                    end
                end
                if cfgMatches == 1 then
                    assignedBar[conf] = candidate
                    consumed[candidate] = true
                end
            end
        end
    end

    return assignedBar
end
mod.AssignTBBFramesToConfigs = AssignFramesToConfigs

-------------------------------------------------------------------------------
--  Audio on Buff Gain / Loss for Tracking Bars
--
--  Same two keys as the CDM buff icons (buffActiveSoundKey / buffLostSoundKey,
--  nil = silent), stored per bar config, and the same pipeline. Blizzard-tracked
--  bars need no hook of their own: InstallBuffFrameHooks already puts the
--  apply/remove alert hooks on both buff viewers' frames, and RecordBuffEdge
--  asks ns.FindTBBSoundKey (ahead of the Buffs bar tiers for a Tracked Bars
--  frame, after them for a buff icon frame). The self-timed presets have no
--  Blizzard alert, so their timer edges call ns.TBBPresetSoundEdge. Bars that
--  track a cooldown never cue. Everything here is on ns. Gated 0-cost on
--  ns._tbbAnyBuffSound, the tracking-bar half of ns._cdmAnyBuffSound.
-------------------------------------------------------------------------------

-- Sound key for the tracking bar that owns this Blizzard frame / spell id.
-- The current pairing names the exact bar (Eclipse-style shared slots), but
-- only while it still fits the frame: the pool reuses frame objects across
-- cooldown slots, and a relayout while the tick sleeps leaves the pairing
-- stale. An id match covers a frame the pairing has not seen yet (its first
-- activation). Presets cue from their own windows, never from an alert.
-- Returns the key; false when the owning bar has a sound on its other edge
-- only (this edge is its own silence, so no Buffs bar sound may stand in);
-- nil when no bar has a say.
function mod.FindTBBSoundKey(widget, spellRef, field)
    if not (ECME and ECME.db) then
        SetECME(mod.ECME)
    end
    local p = ECME and ECME.db and ECME.db.profile
    if not p or (p.cdmBars and p.cdmBars.useBlizzardBuffBars) then
        return nil
    end
    local trackBars = mod.GetTrackedBuffBars()
    local barList = trackBars and trackBars.bars
    if not barList then
        return nil
    end
    local conf
    if widget and _tbbAssignedFor == barList then
        for c, frame in pairs(_tbbAssignment) do
            if frame == widget then
                if c.enabled ~= false and not c.popularKey and c.trackType ~= "cooldown" then
                    local sc = _tbbStickyCdID[c]
                    if
                        (sc ~= nil and widget.cooldownID == sc)
                        or CfgWantsSID(c, spellRef)
                        or MatchFrameToConfig(widget, c)
                    then
                        conf = c
                    end
                end
                break
            end
        end
    end
    if not conf then
        for _, c in ipairs(barList) do
            if c.enabled ~= false and not c.popularKey and CfgWantsSID(c, spellRef) then
                conf = c
                break
            end
        end
    end
    if not conf then
        return nil
    end
    local key = conf[field]
    if key and key ~= "none" then
        return key
    end
    local g, l = conf.buffActiveSoundKey, conf.buffLostSoundKey
    if (g and g ~= "none") or (l and l ~= "none") then
        return false
    end
    return nil
end

-- Any tracking bar in any spec of this profile with a gain or loss sound
-- (feeds ns.RescanBuffSoundFlag). Cooldown-tracking bars never cue.
function mod.TBBAnyBuffSound()
    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfile then
        return false
    end
    for _, prof in pairs(specProfile) do
        local trackBars = type(prof) == "table" and prof.trackedBuffBars
        if type(trackBars) == "table" and type(trackBars.bars) == "table" then
            for _, c in ipairs(trackBars.bars) do
                if c.trackType ~= "cooldown" then
                    local g, l = c.buffActiveSoundKey, c.buffLostSoundKey
                    if (g and g ~= "none") or (l and l ~= "none") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Tracking-bar sound enable (a bar's sound set in options, or the rescan
-- finding one): flips both gates live and hooks the buff viewer frames already
-- out of their pools, since pool Acquire only hooks while the gate is on. Both
-- viewers: a bar's spell can live in either one.
function mod.EnsureTBBSoundHooks()
    mod._cdmAnyBuffSound = true
    mod._tbbAnyBuffSound = true
    local hook = mod.EnsureBuffSoundHook
    if not hook then
        return
    end
    local viewerFrame = _G.BuffBarCooldownViewer
    local pool = viewerFrame and viewerFrame.itemFramePool
    if pool then
        for widget in pool:EnumerateActive() do
            hook(widget)
        end
    end
    viewerFrame = _G.BuffIconCooldownViewer
    pool = viewerFrame and viewerFrame.itemFramePool
    if pool then
        for widget in pool:EnumerateActive() do
            hook(widget)
        end
    end
end

-- [popularKey] = GetTime() a latched preset window ends at (loss still to cue).
mod._tbbPresetLoss = {}

-- Self-timed preset edge. The gain comes from the event that (re)starts the
-- window (Sated rise, Time Spiral glow, potion cast), so a refresh cues again,
-- and latches the loss at the window's end (expiry) while a bar of that preset
-- has a loss sound. The tracking-bar tick fires the latch ahead of its
-- visibility gates, so a bar parked at that moment still cues; a consumed
-- Time Spiral cues from its glow hide, which clears the latch. One cue per
-- edge: the throttle id is per preset, so with two bars of one preset only
-- the first bar with a sound plays.
function mod.TBBPresetSoundEdge(popularKey, gainEdge, expiry)
    if not mod._tbbAnyBuffSound or not popularKey then
        return
    end
    local latch = mod._tbbPresetLoss
    -- Clear only a present entry: the tick calls in here while walking the latch table.
    if latch[popularKey] then
        latch[popularKey] = nil
    end
    if not (ECME and ECME.db) then
        SetECME(mod.ECME)
    end
    local p = ECME and ECME.db and ECME.db.profile
    if not p or (p.cdmBars and p.cdmBars.useBlizzardBuffBars) then
        return
    end
    local trackBars = mod.GetTrackedBuffBars()
    local barList = trackBars and trackBars.bars
    if not barList then
        return
    end
    local field = gainEdge and "buffActiveSoundKey" or "buffLostSoundKey"
    for _, conf in ipairs(barList) do
        if conf.enabled ~= false and conf.popularKey == popularKey and conf.trackType ~= "cooldown" then
            local key = conf[field]
            if key and key ~= "none" then
                mod.PlayBuffSoundEdge(key, "tbb:" .. popularKey, gainEdge)
            end
            local lost = conf.buffLostSoundKey
            if gainEdge and expiry and lost and lost ~= "none" then
                latch[popularKey] = expiry
            end
        end
    end
end

--- Frame-based check: is a spellID present in BuffBarCooldownViewer? Iterates the tiny pool
--- (~3-5 frames), matching via MatchesSID across all fields (overrideSpellID, spellID, linkedSpellIDs).
function mod.IsSpellInBuffBarViewer(spellId)
    if not spellId or spellId <= 0 then
        return false
    end
    local viewerFrame = _G["BuffBarCooldownViewer"]
    if not viewerFrame or not viewerFrame.itemFramePool then
        return false
    end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then
        return false
    end
    local GetCanonical = mod.GetCanonicalSpellIDForFrame
    for widget in viewerFrame.itemFramePool:EnumerateActive() do
        local cooldownId = widget.cooldownID
        if cooldownId then
            local details = gci(cooldownId)
            if details and MatchesSID(details, spellId) then
                return true
            end
            -- Fallback: check frame's canonical spell ID (aura variants).
            if GetCanonical then
                local frameSID = GetCanonical(widget)
                if frameSID == spellId then
                    return true
                end
            end
        end
    end
    return false
end

--- Enumerate all spells in BuffBarCooldownViewer ("Tracked Bars") as {spellID, cdID, name,
--- icon} sorted by layoutIndex then name. Source of truth for the TBB spell picker: TBB IS
--- our display of these bars, so the picker enumerates THIS pool, never the Tracked Buffs icon viewer.
function mod.GetTrackedBarSpells(includeUntalented)
    local outcome = {}
    local GetCanonical = mod.GetCanonicalSpellIDForFrame
    local seen = {}

    -- Display name plus subtext (e.g. "Solar", "Lunar") to disambiguate spells sharing a base name like Eclipse.
    local function ResolveName(spellRef)
        local label = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef)
        if label and C_Spell.GetSpellSubtext then
            local sub = C_Spell.GetSpellSubtext(spellRef)
            if sub and sub ~= "" then
                label = label .. " (" .. sub .. ")"
            end
        end
        return label
    end

    local viewerFrame = _G["BuffBarCooldownViewer"]
    if viewerFrame and viewerFrame.itemFramePool then
        for widget in viewerFrame.itemFramePool:EnumerateActive() do
            if widget:IsShown() or widget.cooldownInfo then
                local spellRef = GetCanonical and GetCanonical(widget)
                if spellRef and spellRef > 0 and not seen[spellRef] then
                    seen[spellRef] = true
                    local iconTex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRef)
                    outcome[#outcome + 1] = {
                        spellID = spellRef,
                        cdID = widget.cooldownID,
                        name = ResolveName(spellRef) or ("Spell " .. spellRef),
                        icon = iconTex,
                        layoutIndex = widget.layoutIndex or 0,
                        -- Live pool members are always learned; catalog entries appended below may not be.
                        isKnown = true,
                    }
                end
            end
        end
    end

    -- Tracked-but-untalented bar spells have no live BuffBar frame, so pull them from the
    -- settings catalog (TrackedBar category). Picker-only (includeUntalented); auto-add and
    -- section checks stay live-only. Provider down/names missing -> nothing appended. Dedup
    -- by canonical sid, same as the live-pool dedup above.
    if includeUntalented and mod.EnumerateCDMSettingsCatalog then
        local evc = Enum and Enum.CooldownViewerCategory
        local barCat = evc and (evc.TrackedBar or 3)
        local catalog = barCat and mod.EnumerateCDMSettingsCatalog({ [barCat] = true })
        if catalog then
            local extra = 0
            for _, cooldownEntry in ipairs(catalog) do
                if cooldownEntry.sid and cooldownEntry.sid > 0 and not seen[cooldownEntry.sid] then
                    seen[cooldownEntry.sid] = true
                    local spellName = ResolveName(cooldownEntry.sid)
                    if spellName then
                        local known = (IsPlayerSpell and IsPlayerSpell(cooldownEntry.sid)) and true or false
                        local iconTex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(cooldownEntry.sid)
                        extra = extra + 1
                        outcome[#outcome + 1] = {
                            spellID = cooldownEntry.sid,
                            cdID = cooldownEntry.cdID,
                            name = spellName,
                            icon = iconTex,
                            -- No live frame -> no layoutIndex; sort after live entries, keeping catalog order among themselves.
                            layoutIndex = 100000 + extra,
                            isKnown = known,
                        }
                    end
                end
            end
        end
    end

    table.sort(outcome, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then
            return a.layoutIndex < b.layoutIndex
        end
        return (a.name or "") < (b.name or "")
    end)
    return outcome
end

-------------------------------------------------------------------------------
--  Auto-add: opt-in per group ("Auto-Add New to This Group"). While a group holds
--  the flag, any spell newly appearing in Blizzard's Tracked Bars section gets a
--  bar in that group; turning the flag ON populates a bar for every currently
--  tracked spell. Deleted bars stay deleted -- their spells remain in the
--  tbb.autoSeen ledger; only the populate-on-enable pass ignores it ("give me everything").
-------------------------------------------------------------------------------
local function SpellCoveredByBars(barList, specProfile)
    -- Variant/override coverage: a bar saved for one form covers the whole linked set
    -- (base/override/aura variants share a cooldownInfo), so an Eclipse Solar bar is not
    -- duplicated when Lunar's frame appears under a talent-swapped id.
    local details
    if specProfile.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        details = C_CooldownViewer.GetCooldownViewerCooldownInfo(specProfile.cdID)
    end
    for _, conf in ipairs(barList) do
        if CfgWantsSID(conf, specProfile.spellID) then
            return true
        end
        if details then
            if CfgWantsSID(conf, details.spellID) then
                return true
            end
            if CfgWantsSID(conf, details.overrideSpellID) then
                return true
            end
            if details.linkedSpellIDs then
                for _, lid in ipairs(details.linkedSpellIDs) do
                    if CfgWantsSID(conf, lid) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Shared guards for both auto-add passes. Returns the tbb table, or nil when the pass must not run right now.
local function AutoAddReady()
    if not (ECME and ECME.db) then
        SetECME(mod.ECME)
    end
    if not (ECME and ECME.db) then
        return nil
    end
    local p = ECME.db.profile
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then
        return nil
    end
    if InCombatLockdown() then
        return nil
    end
    return mod.GetTrackedBuffBars()
end

-- Worker: create a bar in `gid` for every tracked spell not covered by an existing bar.
-- `ignoreSeen` = full populate (enable pass); otherwise only never-seen spells count, so deleted bars stay deleted.
local function AutoAddTrackedToGroup(trackBars, groupId, ignoreSeen)
    local tracked = mod.GetTrackedBarSpells and mod.GetTrackedBarSpells() or {}
    -- An empty list also means "viewer not populated yet" (login order): nothing to act on either way.
    if #tracked == 0 then
        return 0
    end
    -- Postpone while any pool frame's spell identity is unresolved (login spell-data races):
    -- acting on a partial list could later mis-read a long-tracked spell as "new".
    do
        local viewerFrame = _G["BuffBarCooldownViewer"]
        local GetCanonical = mod.GetCanonicalSpellIDForFrame
        if viewerFrame and viewerFrame.itemFramePool and GetCanonical then
            for widget in viewerFrame.itemFramePool:EnumerateActive() do
                if (widget:IsShown() or widget.cooldownInfo) and not GetCanonical(widget) then
                    return 0
                end
            end
        end
    end
    trackBars.autoSeen = trackBars.autoSeen or {}
    local added = 0
    for _, specProfile in ipairs(tracked) do
        if ignoreSeen or not trackBars.autoSeen[specProfile.spellID] then
            trackBars.autoSeen[specProfile.spellID] = true
            if not SpellCoveredByBars(trackBars.bars, specProfile) then
                local position = AddTrackedBuffBarCore(trackBars, groupId)
                local nb = trackBars.bars[position]
                nb.spellID = specProfile.spellID
                nb.name = specProfile.name
                -- Base-form capture for talent-override spells (same as the picker): keeps the bar matching once the talent is removed.
                if specProfile.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(specProfile.cdID)
                    if
                        details
                        and details.spellID
                        and details.spellID > 0
                        and details.spellID ~= specProfile.spellID
                    then
                        nb.baseSpellID = details.spellID
                    end
                end
                added = added + 1
            end
        end
    end
    return added
end

-- Incremental pass: bars for spells newly appearing in the Tracked Bars section, routed to
-- the flagged group. Returns bars added (configs only; callers rebuild); no-op unless a group opted in.
function mod.EnsureTBBAutoBars()
    local trackBars = AutoAddReady()
    if not trackBars then
        return 0
    end
    local groupId = mod.TBBAutoAddGroupID()
    if not groupId then
        return 0
    end
    return AutoAddTrackedToGroup(trackBars, groupId, false)
end

-- Full populate for the moment "Auto-Add New to This Group" is switched ON: one bar per tracked spell not already covered somewhere, ledger ignored.
function mod.PopulateTBBAutoAddGroup(groupId)
    if not groupId or groupId == 0 then
        return 0
    end
    local trackBars = AutoAddReady()
    if not trackBars then
        return 0
    end
    return AutoAddTrackedToGroup(trackBars, groupId, true)
end

-- Debounced entry point for the buff-bar viewer pool hooks: a spell dragged into Blizzard's
-- Tracked Bars section acquires a new pool frame and lands here. Combat acquires are skipped
-- (tracked-set edits happen out of combat; mid-fight acquires are just known auras activating).
local _tbbAutoAddQueued = false
function mod.QueueTBBAutoAdd()
    if _tbbAutoAddQueued then
        return
    end
    if InCombatLockdown() then
        return
    end
    _tbbAutoAddQueued = true
    C_Timer.After(1.0, function()
        _tbbAutoAddQueued = false
        if mod.EnsureTBBAutoBars() > 0 then
            mod.BuildTrackedBuffBars()
            if mod.OnTBBBarsAutoAdded then
                mod.OnTBBBarsAutoAdded()
            end
        end
    end)
end

Inner._tbbAssignment, Inner._tbbStickyCdID = _tbbAssignment, _tbbStickyCdID
Inner.AssignFramesToConfigs, Inner.CfgWantsSID = AssignFramesToConfigs, CfgWantsSID
Inner.MatchesSID, Inner.TbbCfgFamilyMatch = MatchesSID, TbbCfgFamilyMatch
Inner.TbbNameFamily, Inner.TbbSlotVariantLabeled = TbbNameFamily, TbbSlotVariantLabeled
Inner.broken = false
