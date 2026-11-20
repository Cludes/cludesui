if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookResolve.lua
--
--  Spell id resolution and the spell route map (which bar a cooldown id
--  belongs to).
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ECME = mod.ECME
local ResolveInfoSpellID = mod.ResolveInfoSpellID
local _ecmeFC = mod._ecmeFC

-------------------------------------------------------------------------------
--  Spell ID Resolution
-------------------------------------------------------------------------------
local function ResolveFrameSpellID(widget)
    local cdID = widget.cooldownID
    if not cdID and widget.cooldownInfo then
        cdID = widget.cooldownInfo.cooldownID
    end
    if not cdID or not C_CooldownViewer then
        return nil, nil
    end

    local fc = _ecmeFC[widget]
    if fc and fc.resolvedSid and fc.cachedCdID == cdID then
        local baseSID = fc.baseSpellID
        if baseSID and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local liveOvr = C_SpellBook.FindSpellOverrideByID(baseSID)
            if liveOvr and liveOvr ~= 0 and liveOvr ~= fc.overrideSid then
                fc.overrideSid = liveOvr
                fc.resolvedSid = liveOvr
            end
        end
        return fc.resolvedSid, fc.baseSpellID
    end

    local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    local displaySID = details and ResolveInfoSpellID(details)
    if not displaySID or displaySID <= 0 then
        -- New-category rows (racials cat 5/6, equip-slot items cat 7/8) are
        -- nil shells in BOTH the raw and merged data spaces (field-probed:
        -- racial rows carry only spellCategoryID, item rows only equipSlot,
        -- and linkedSpellIDs sits empty at rest) -- the resolved identity
        -- exists ONLY on the live frame. GetSpellID() reads SECRET while an
        -- aura is active: a plain read serves this paint and fills the memo
        -- at the head of this function for later secret windows; a secret
        -- read resolves nothing this pass (fail-open, the next inactive
        -- read heals).
        local live = widget.GetSpellID and widget:GetSpellID()
        if issecretvalue and issecretvalue(live) then
            live = nil
        end
        if type(live) == "number" and live > 0 then
            displaySID = live
        end
    end
    if not displaySID or displaySID <= 0 then
        return nil, nil
    end
    local baseSID = details and details.spellID
    if not baseSID or baseSID <= 0 then
        baseSID = displaySID
    end

    if not fc then
        fc = {}
        _ecmeFC[widget] = fc
    end
    fc.resolvedSid = displaySID
    fc.baseSpellID = baseSID
    fc.overrideSid = details and details.overrideSpellID or nil
    fc.cachedCdID = cdID
    fc.cachedAuraInstID = widget.auraInstanceID
    -- Native item rows identify by equipment slot (13/14 trinkets etc.);
    -- stashed for the slot-keyed settings/arbitration lane.
    fc.equipSlot = details and details.equipSlot or nil

    if details and details.linkedSpellIDs and #details.linkedSpellIDs > 0 then
        fc.linkedSpellIDs = details.linkedSpellIDs
        -- Learn buff-family variant aliases here, not at DecorateFrame time: only the two
        -- buff viewers host dual-tracked buff forms, and frame.viewerFrame (the raw
        -- Blizzard field) is already readable at this point, before fd._isBuffViewerFrame
        -- exists.
        if
            mod.LearnBuffVariantAlias
            and (
                widget.viewerFrame == _G.BuffIconCooldownViewer
                or widget.viewerFrame == _G.BuffBarCooldownViewer
            )
        then
            mod.LearnBuffVariantAlias(displaySID, details.linkedSpellIDs)
        end
    else
        fc.linkedSpellIDs = nil
    end

    return displaySID, baseSID
end
mod.ResolveFrameSpellID = ResolveFrameSpellID

-- Resolve the per-spell settings table for a CDM frame. Settings key by the
-- spell the user added (assignedSpells/spellSettings[id]); one logical spell can
-- report SEVERAL ids by talent state: sid2 = cooldownInfo base (can be UNRELATED,
-- e.g. Wither slot: base Immolate 348, displayed Wither 445468); canon =
-- GetCanonicalSpellIDForFrame (clean-read cached, survives secret state);
-- resolvedSid/baseSpellID = cached override/base ids. Match against the FULL
-- identity set: direct hit, linkedSpellIDs, then override resolution in BOTH
-- directions (assigned id may be the base whose live override is an identity id,
-- e.g. Corruption 172 -> Wither 445468, or vice versa).
local function ResolveSpellSettingsUncached(widget, sid2, sd2, barId)
    if not sid2 then
        return nil
    end
    -- Bar identity: explicit barKey wins (nil-frame callers), else frame context.
    local fc0 = widget and _ecmeFC[widget]
    local bk = barId or (fc0 and fc0.barKey)
    -- Bar tiers: barSettings ("Apply to Bar", per spec) chained to profile-level
    -- bd.barSpellSettings ("Apply to Bar (All Specs)"); nil when neither exists.
    local tier = mod.GetBarTierSettings and mod.GetBarTierSettings(sd2, bk)
    -- HOSTED-BUFF detection: buff frame (or inactive placeholder) on a CD/util
    -- bar, FRAME-based not flag-based (same spellID can also be this bar's CD
    -- entry and must keep CD-family resolution). hostedBuffSpellIDs nil = no host.
    -- All four signals are frame-scoped, and FC.isHostedBuff / viewerFrame are
    -- readable BEFORE the frame is decorated (the claim pass stamps the first;
    -- the second is the Blizzard field DecorateFrame later reads). A
    -- decoration-stamp-only test misses pre-decoration resolves SILENTLY: the
    -- family store below falls back to spellSettingsCD and applies a CD-era
    -- entry under the same id to the buff.
    local hostedFrame = false
    if widget and bk and sd2 and sd2.hostedBuffSpellIDs then
        local fdH = mod._hookFrameData and mod._hookFrameData[widget]
        if
            (fc0 and fc0.isHostedBuff)
            or (fdH and fdH._isBuffViewerFrame)
            or widget._isPlaceholderFrame
            or widget.viewerFrame == _G.BuffIconCooldownViewer
            or widget.viewerFrame == _G.BuffBarCooldownViewer
        then
            local bdH = mod.barDataByKey and mod.barDataByKey[bk]
            if bdH and bdH.barType ~= "buffs" and bdH.barType ~= "custom_buff" then
                hostedFrame = true
            end
        end
    end
    -- HOSTED BUFFS never inherit the host bar's Apply-to-Bar tier (shared keys:
    -- Duration Text, Border) -- own per-spell entry ONLY. Nil-frame callers fall
    -- back to the flag test (a nil-frame lookup for a hosted id is always buff).
    if
        tier
        and (hostedFrame or (not widget and sd2 and sd2.hostedBuffSpellIDs and sd2.hostedBuffSpellIDs[sid2]))
    then
        tier = nil
    end
    -- Per-spell entries live in the spec's FAMILY store (travel with the spell
    -- across bars), not the bar. A hosted buff reads the BUFF store keyed off the
    -- FRAME, so a cooldown icon of the same spellID here keeps the CD store.
    local prefs = bk
        and mod.GetSpellSettingsStore
        and mod.GetSpellSettingsStore(hostedFrame and "buffs" or bk)
    if not prefs or next(prefs) == nil then
        return tier
    end

    local ChainSettings = mod.ChainSettings

    -- Per-cooldownID buff override: two buff-viewer slots can share one canonical
    -- spellID (e.g. Demonic Art vs Diabolic Ritual) yet configure independently
    -- via a "c"..cooldownID key; gated on BuffFamHasCdKey (cached bool), buff frames only.
    if widget then
        local fdC = mod._hookFrameData and mod._hookFrameData[widget]
        -- Buff frames AND inactive placeholders (Always Show/Keep in Same Place)
        -- share the viewer cooldownID and must resolve the same per-slot entry,
        -- else styling reverts when the placeholder shows; type(cdID)=="number"
        -- excludes preset placeholders (they nil the cooldownID).
        if (fdC and fdC._isBuffViewerFrame) or widget._isPlaceholderFrame then
            local cdID = widget.cooldownID
            if type(cdID) == "number" then
                if mod.BuffFamHasCdKey and mod.BuffFamHasCdKey(prefs) then
                    local cd = prefs["c" .. cdID]
                    if cd then
                        ChainSettings(cd, tier)
                        return cd
                    end
                end
                -- Split-identity buffs (shared base spellID, per-form aura ids,
                -- e.g. Warp/Weft): the active frame's identity collapses to the
                -- shared base (GetSpellID reads secret), so a direct hit would
                -- differ from the placeholder's per-form id. Prefer the clean
                -- per-form id cached per cooldownID (equals sid2 for normal buffs;
                -- falls through to the shared key when no per-form entry exists).
                local cleanSid = mod._cdmCleanSidByCDID and mod._cdmCleanSidByCDID[cdID]
                if cleanSid and cleanSid ~= sid2 then
                    local sClean = prefs[cleanSid]
                    if sClean then
                        ChainSettings(sClean, tier)
                        return sClean
                    end
                end
            end
        end
    end

    -- Fast path: direct hit on the primary id returns before building the identity
    -- set/addId closure, keeping the hot SetSwipeColor path allocation-free. The
    -- chain re-assert self-heals: every resolve re-points __index at the CURRENT
    -- bar's tier, so bar/spec/profile swaps (and fresh logins, since metatables
    -- aren't serialized) never leave a stale link.
    local direct = prefs[sid2]
    if direct then
        ChainSettings(direct, tier)
        return direct
    end

    local fc2 = fc0

    -- Frame's deduped identity-id set (sid2 + canonical + cached override/base +
    -- GetBaseSpell bridges) is combat-hot (table alloc + canonical resolve + 2
    -- GetBaseSpell calls per repaint per icon with no own entry) and pure
    -- frame-content data, so it's cached on the frame-cache entry keyed by every
    -- input it derives from (sid2/resolvedSid/baseSpellID); ResolveFrameSpellID's
    -- re-derivation on content/override flips naturally invalidates it -- zero new
    -- edges needed. Step 3's FindSpellOverrideByID stays LIVE by design: live
    -- overrides flip mid-combat with no content change, which only that step catches.
    local ids
    if
        fc2
        and fc2.ssIds
        and fc2.ssIdsFor == sid2
        and fc2.ssIdsRS == fc2.resolvedSid
        and fc2.ssIdsBS == fc2.baseSpellID
    then
        ids = fc2.ssIds
    else
        ids = { sid2 }
        local function addId(id)
            if not id or id <= 0 then
                return
            end
            for index = 1, #ids do
                if ids[index] == id then
                    return
                end
            end
            ids[#ids + 1] = id
        end
        local canon2 = widget and mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(widget)
        if canon2 then
            addId(canon2)
        end
        if fc2 then
            addId(fc2.resolvedSid)
            addId(fc2.baseSpellID)
        end
        -- "Proc into a second ability" talent forms (e.g. DH Reap 1226019/1225826)
        -- share a GetBaseSpell base (344862) with the configured spell, but that's
        -- not the cooldownInfo base and FindSpellOverrideByID is unreliable (live
        -- override may differ from the displayed form); GetBaseSpell of the
        -- frame's ids is the stable bridge, so a setting stored under the base
        -- form resolves on the proc'd frame.
        if C_Spell and C_Spell.GetBaseSpell then
            addId(C_Spell.GetBaseSpell(sid2))
            if canon2 then
                addId(C_Spell.GetBaseSpell(canon2))
            end
        end
        if fc2 then
            fc2.ssIds = ids
            fc2.ssIdsFor = sid2
            fc2.ssIdsRS = fc2.resolvedSid
            fc2.ssIdsBS = fc2.baseSpellID
        end
    end

    -- 1. Direct hit on any identity id.
    for index = 1, #ids do
        local s = prefs[ids[index]]
        if s then
            ChainSettings(s, tier)
            return s
        end
    end

    -- 2. linkedSpellIDs reported by the cooldown info.
    if fc2 and fc2.linkedSpellIDs then
        for _, lid in ipairs(fc2.linkedSpellIDs) do
            local s = prefs[lid]
            if s then
                ChainSettings(s, tier)
                return s
            end
        end
    end

    -- 3. Override resolution across assignedSpells, both directions, against the
    --    full identity set. Non-positive identity ids (item presets, hosted /
    --    cd-claim markers) are never real spells: skip the spell API, whose
    --    int32 range check HARD-ERRORS on marker magnitudes.
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if FindOvr and sd2 and sd2.assignedSpells then
        local idOvr = {}
        for index = 1, #ids do
            local id = ids[index]
            if type(id) == "number" and id > 0 then
                idOvr[index] = FindOvr(id)
            end
        end
        for _, asid in ipairs(sd2.assignedSpells) do
            if asid and asid > 0 and prefs[asid] then
                local asidOvr = FindOvr(asid)
                for index = 1, #ids do
                    if asidOvr == ids[index] or idOvr[index] == asid then
                        local s = prefs[asid]
                        ChainSettings(s, tier)
                        return s
                    end
                end
            end
        end
    end

    -- No per-spell entry anywhere in the identity set: the bar tiers (if any)
    -- are the effective settings.
    return tier
end

-- Result memo over the resolver. Per-frame stamp keyed on ns._cdmResGen (bumped
-- by EVERY input edge: per-spell/tier create-delete, host flips, cdID-key gate
-- flip, clean-sid flips, SPELL_OVERRIDE_UPDATED, SPELLS_CHANGED, rebuilds) plus
-- the frame's content identity (sid2/resolvedSid/baseSpellID) plus the bar.
-- In-place mutation needs no bump (the memo returns the table writers edit).
-- The hit path still re-asserts the tier chain (two bars can share one family
-- entry) at one getmetatable+compare cost; nil-frame callers bypass the memo.
local function ResolveSpellSettings(widget, sid2, sd2, barId)
    local fc0 = widget and _ecmeFC[widget]
    -- sd2 == false is the LAZY sentinel: the per-repaint hooks pass it instead of
    -- fetching the bar's spell data up front, so the store walk behind
    -- GetBarSpellData runs only on a memo miss (the hit path never needs it).
    if not fc0 or not sid2 then
        if sd2 == false then
            sd2 = (barId and mod.GetBarSpellData) and mod.GetBarSpellData(barId) or nil
        end
        return ResolveSpellSettingsUncached(widget, sid2, sd2, barId)
    end
    local bk = barId or fc0.barKey
    if
        fc0.ssRGen == mod._cdmResGen
        and fc0.ssRSid == sid2
        and fc0.ssRBk == bk
        and fc0.ssRRS == fc0.resolvedSid
        and fc0.ssRBS == fc0.baseSpellID
    then
        local val = fc0.ssRVal
        if val == false then
            return nil
        end
        mod.ChainSettings(val, fc0.ssRTier)
        return val
    end
    if sd2 == false then
        sd2 = mod.GetBarSpellData and mod.GetBarSpellData(bk)
    end
    local res = ResolveSpellSettingsUncached(widget, sid2, sd2, barId)
    fc0.ssRGen = mod._cdmResGen
    fc0.ssRSid = sid2
    fc0.ssRBk = bk
    fc0.ssRRS = fc0.resolvedSid
    fc0.ssRBS = fc0.baseSpellID
    if res == nil then
        fc0.ssRVal = false
        fc0.ssRTier = nil
    else
        fc0.ssRVal = res
        local mt = getmetatable(res)
        fc0.ssRTier = mt and mt.__index or nil
    end
    return res
end
mod.ResolveSpellSettings = ResolveSpellSettings

-- Effective swipe direction for a CDM frame: the frame-KIND baseline (buffs fill
-- up, cooldowns deplete) flipped by per-spell / preset "Reverse Swipe". Every
-- writer of the widget goes through this, so they all push the SAME value: the
-- decoration + claim re-asserts used to write the bare kind baseline, which
-- stomped the per-spell reverse on the next reanchor and left it off, because
-- only an icon-set CHANGE runs the appearance pass that re-applies it (preset
-- icons escaped that -- the Fake-Active engine re-asserts their direction on its
-- own updates, so the setting looked broken for regular spells only).
-- Gated on the session flag: returns the baseline with no lookups at all unless
-- someone has the toggle on. On ns, not a file local: this file sits at Lua's
-- 200-local cap.
function mod.EffectiveReverseSwipe(widget, barId, kindBaseline)
    if not mod._cdmAnyReverseSwipe then
        return kindBaseline
    end
    local fc = widget and _ecmeFC[widget]
    local spellRef = fc and fc.spellID
    -- Bar identity: explicit key wins, else the frame context. Never resolve
    -- without one (the store lookup indexes by it).
    local bk = barId or (fc and fc.barKey)
    if not (spellRef and bk and mod.GetBarSpellData) then
        return kindBaseline
    end
    -- Pass the key explicitly: the resolver picks the FAMILY store from the bar
    -- identity, and leaving it to be inferred resolves a hosted buff against the
    -- CD store.
    local ss = ResolveSpellSettings(widget, spellRef, mod.GetBarSpellData(bk), bk)
    local rev = ss and ss.reverseSwipe
    -- Preset / custom cd-utility spell setting (profile customActiveStates;
    -- trinket slots resolve item-over-slot via the effective view).
    if not rev and mod.GetEffectiveCustomActiveState then
        local cas = mod.GetEffectiveCustomActiveState(spellRef)
        rev = cas and cas.reverseSwipe
    end
    if rev then
        return not kindBaseline
    end
    return kindBaseline
end

-- True when any assigned entry on this CD/utility bar resolves to a Shift Icons
-- cooldown-state effect. Frame-less pass over assignedSpells, called at reanchor
-- and from options disabled-state (never per-frame). Advisory only: Pass B also
-- walks the live frame list, since spillover/alias-keyed settings are invisible
-- to a frame-less scan.
function mod.CdmBarHasShiftCdState(barId)
    local sd = mod.GetBarSpellData(barId)
    local entries = sd and sd.assignedSpells
    if not entries then
        return false
    end
    for _, spellRef in ipairs(entries) do
        if spellRef and spellRef ~= 0 then
            local eff
            local hSid = mod.HostedBuffMarkerToSpell and mod.HostedBuffMarkerToSpell(spellRef)
            if hSid then
                -- Hosted buff: buff-family own entry only (hosted frames
                -- never inherit this bar's tier).
                local storage = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore("buffs")
                eff = mod.CdStateHideOf(storage and storage[hSid])
            else
                if spellRef > 0 then
                    eff = mod.CdStateHideOf(ResolveSpellSettings(nil, spellRef, sd, barId))
                end
                if not mod.CdStateShifts(eff) then
                    local casEff = mod.CdStateHideOf(mod.GetEffectiveCustomActiveState(spellRef))
                    if casEff then
                        eff = casEff
                    end
                end
            end
            if mod.CdStateShifts(eff) then
                return true
            end
        end
    end
    return false
end

-- Options-side accessor: the overflow layout bar a frame is diverted to this
-- session (nil when not diverted). The fc table is file-local.
function mod.CdmFrameOverflowBar(widget)
    local fc = widget and _ecmeFC[widget]
    return fc and fc._overflowLayoutBar or nil
end

-- Apply the per-spell active-state OVERLAYS (glow + border). Touches only OUR
-- overlays (glowOverlay, borderFrame), never Blizzard's Cooldown swipe, so it is
-- safe from the swipe hook OR the Fake-Active ticker. Idempotent via
-- fd._activeGlowOn / fd._activeBorderOn so the two drivers cooperate.
function mod.ApplyActiveOverlays(widget, fd, ss, isActive, edge)
    if not fd then
        return
    end

    -- Active glow (per-spell)
    local hasGlow = ss and ss.activeGlow and ss.activeGlow > 0
    if isActive and hasGlow then
        if fd.glowOverlay then
            -- Unified glow color takes priority
            local gr, gg, gb = mod.ResolveGlowColor(ss)
            if not gr then
                if ss.activeGlowClassColor then
                    local _, classTok = UnitClass("player")
                    if classTok then
                        local cc = RAID_CLASS_COLORS[classTok]
                        if cc then
                            gr, gg, gb = cc.r, cc.g, cc.b
                        end
                    end
                elseif ss.activeGlowR ~= nil then
                    gr, gg, gb = ss.activeGlowR, ss.activeGlowG or 0.85, ss.activeGlowB or 0
                end
            end
            -- (Re)start on first activation OR style/colour change (live edits
            -- apply); a steady active window never restarts (would flicker).
            if
                not fd._activeGlowOn
                or fd._activeGlowStyle ~= ss.activeGlow
                or fd._activeGlowR ~= gr
                or fd._activeGlowG ~= gg
                or fd._activeGlowB ~= gb
            then
                mod.StartNativeGlow(fd.glowOverlay, ss.activeGlow, gr, gg, gb)
                fd._activeGlowOn = true
                fd._activeGlowStyle = ss.activeGlow
                fd._activeGlowR, fd._activeGlowG, fd._activeGlowB = gr, gg, gb
                -- This replaced any CD-state glow on the shared overlay: the memo
                -- follows the visual, and the glow is owed back when the active
                -- window ends (below). A Blackout keeps its own overlay.
                local bo = fd.blackoutOverlay
                if fd._cdStateGlowOn and not (bo and bo._glowActive) then
                    fd._cdStateGlowOn = false
                    fd._cdGlowOwed = true
                end
            end
        end
    elseif fd._activeGlowOn then
        if fd.glowOverlay then
            mod.StopNativeGlow(fd.glowOverlay)
        end
        fd._activeGlowOn = false
        -- A CD-state glow this replaced or held back lights now, not on the
        -- icon's next cooldown edge: a buff that outlasts its cooldown ends
        -- with no further cooldown push to re-run that decision.
        if fd._cdGlowOwed then
            mod.CdGlowKick(widget)
        end
    end

    -- Active border color (per-spell): recolor while active, restore on falloff.
    -- SQUARE borders use SetBorderStyleColor (solid+textured, no-op on hidden).
    -- CUSTOM SHAPE borders ring a separate shapeBorder texture SetBorderStyleColor
    -- never touches, so recolor it directly and save/restore its vertex color
    -- (fake-active overlays seed FC with the underlying shapeBorder, so the lookup hits the real ring).
    local ifc = mod._ecmeFC and mod._ecmeFC[widget]
    local shapeBorder = ifc and ifc.shapeApplied and ifc.shapeBorder
    if isActive and ss and ss.activeBorderEnabled then
        local abR = ss.activeBorderR or 1
        local abG = ss.activeBorderG or 0.776
        local abB = ss.activeBorderB or 0.376
        local abA = ss.activeBorderA or 1
        if shapeBorder then
            if not fd._sbColorSaved then
                fd._sbR, fd._sbG, fd._sbB, fd._sbA = shapeBorder:GetVertexColor()
                fd._sbColorSaved = true
            end
            shapeBorder:SetVertexColor(abR, abG, abB, abA)
        elseif fd.borderFrame and CludesUI.SetBorderStyleColor then
            CludesUI.SetBorderStyleColor(fd.borderFrame, abR, abG, abB, abA)
        end
        fd._activeBorderOn = true
    elseif fd._activeBorderOn then
        if shapeBorder and fd._sbColorSaved then
            shapeBorder:SetVertexColor(fd._sbR, fd._sbG, fd._sbB, fd._sbA)
            fd._sbColorSaved = false
        elseif fd.borderFrame and CludesUI.SetBorderStyleColor then
            CludesUI.SetBorderStyleColor(
                fd.borderFrame,
                (edge and edge.borderR) or 0,
                (edge and edge.borderG) or 0,
                (edge and edge.borderB) or 0,
                (edge and edge.borderA) or 1
            )
        end
        fd._activeBorderOn = false
    end
end

-------------------------------------------------------------------------------
--  Spell Routing State
--
--  _divertedSpellsBuff/_divertedSpellsCD: variant-keyed maps of every spellID
--    claimed by a bar, split by viewer family so one spellID (Divine Shield 642:
--    cooldown in essential viewer AND buff in buff viewer) routes independently
--    (unsplit, the other family's pass clobbers the entry). Built by
--    RebuildSpellRouteMap, queried per-frame at reanchor by ResolveCDIDToBar.
--  _cdidRouteMap: memo cache cooldownID -> barKey, lazily filled by
--    ResolveCDIDToBar, wiped by RebuildSpellRouteMap. Safe as ONE map since a
--    cooldownID exists in only one viewer (family implicit in the key).
-------------------------------------------------------------------------------
local _cdidRouteMap = {}

local _divertedSpellsBuff = {}
local _divertedSpellsCD = {}
-- cooldownID-level buff diversions: a collided buff (two viewer slots sharing one
-- canonical spellID) is tracked on a custom bar by cooldownID (cd-claim marker in
-- assignedSpells, ns.CdClaimMarker); checked BEFORE the sid map, so it outranks a pair claim.
local _divertedBuffCdIDs = {}
--- Equipment-slot diversions, inventory slot -> barKey. Blizzard's own equipment
--- cooldown entry carries an equipSlot and NO spell of its own, so the slot is its
--- only routing key; a bar listing that slot (-13/-14 et al) claims the frame the
--- same way listing a spellID claims a spell. On ns, not a local: this file is at
--- the 200-local cap.
mod._divertedSlotCD = {}
--- Item preset diversions, entry key (-itemID) -> barKey, and the key Blizzard's own
--- potion / healthstone row renders under, by its spell category (Combat Potion 4,
--- Health Potion 30, Healthstone 1711, Demonic Healthstone 2566: Blizzard's own table
--- in CooldownViewerItemData.lua). Such a row carries no spell of its own, so the
--- preset key is its one stable identity: it takes the preset's slot and settings,
--- and the preset's own frame stands down while it is live (NativeItemKeyFor below,
--- CUI_CDM_HookReanchor.lua Phase 1 and 3). On ns: 200-local cap.
mod._divertedItemCD = {}
mod._nativeItemKeyByCat = {}
-- WoW Forever: CD-family claims by rank name (ns.CDMRankName), for a row whose
-- cooldown info does not link the rank a bar lists. On ns: 200-local cap.
mod._divertedRankCD = {}
-- "Replace with Buff" (per-spell cd/util setting): buff identity -> the cooldown
-- spellID whose slot the buff's viewer frame takes while the aura is active.
-- Spell-keyed map is variant-expanded on write; the cooldownID map serves
-- cd-claimed collided slots (numeric keys, so the collect pass never concats).
-- Read only while ns._cdmAnyBuffReplace is set. On ns: 200-local cap.
mod._buffReplaceTarget = {}
mod._buffReplaceTargetCd = {}
-- Bars holding at least one replacement: the viewer-alpha vote in
-- _CDMApplyVisibility reads it (a replacement frame stays parented to the
-- BuffIcon viewer, like a hosted buff, so its bar must keep that viewer lit).
mod._buffReplaceBars = {}
-- EXACT assigned ids, split from the maps above (which also hold variant-family
-- derived keys). One cooldown slot can carry several family members on different
-- bars (Divine Toll/override Holy Bulwark share cooldownID 29342, base 375576);
-- consulted first so the slot follows the assigned bar instead of flipping on each transform.
local _divertedDirectBuff = {}
local _divertedDirectCD = {}
-- Base ids claimed by an explicitly assigned VARIANT, keyed base -> bar. A transforming
-- slot names only its base plus the live form; the OTHER form is invisible (cooldownID
-- 29342 reports Divine Toll 375576, overrideSpellID alternates armaments, no
-- linkedSpellIDs) -- so with one armament assigned and the base repopulated elsewhere,
-- the exact-id lookup hit-or-missed by armament state and the icon changed bars on
-- every transform. The base IS stable across transforms, so recording it closes the
-- hole; consulted after exact ids and before the base's own entry. Written only when
-- the assigned id isn't the base, so ordinary spells never land here.
local _divertedVarBaseBuff = {}
local _divertedVarBaseCD = {}
-- Learned variant -> base, deliberately NEVER wiped. It's static game data, but
-- the client only answers while that variant is live (Holy Bulwark live ->
-- GetBaseSpell(432459)=375576; Sacred Weapon live -> 432459: every identity API
-- is a fixed point on the form not currently active). Deriving fresh per rebuild
-- is right only half the time on these constantly-rebuilding transforms, so
-- learn while observable and keep forever (relationship never changes).
--
-- Learning it in-session still leaves one hole, which is what the store below
-- closes: a slot only ever names its base and the form live RIGHT NOW, so a
-- fresh login can never witness the pair for an assigned variant that is not
-- the live one. The claim is therefore missing from the very first build and
-- the base falls through to whatever a repopulate assigned, until a cast
-- transforms the slot and a later rebuild finally observes it. Persisting is
-- what lets a login start where the last session left off.
--
-- SCOPED PER SPEC, and that is load-bearing. GetBaseSpell takes a `spec`
-- argument documented as "overrides may vary by Spec", and we call it without
-- one, so every answer describes the CURRENT spec only. The links are not
-- always the tidy same-ability pair the armaments suggest, either: #842 saw
-- GetBaseSpell tie SV Kill Command to a different ability entirely. Seeding one
-- spec's answer into another would hand varMap a base that belongs to a
-- different family there, and ResolveCDIDToBar consults varBaseMap BEFORE
-- directMap[info.spellID], so a bogus pair would outrank that spell's own
-- explicit assignment. Keying by spec confines every pair to the state it was
-- measured in. Sharing across characters within one spec is fine: same spec,
-- same links.
--
-- Lives on the SV root beside _capturedOnce_CDM rather than in a profile
-- because it describes the game, not the user's settings. StripDefaults only
-- walks keys present in DEFAULTS, so a root key it does not know about survives
-- logout untouched -- which also means nothing else can ever clear it, hence
-- ns.ResetVariantBaseStore below.
local _variantBaseLearned = {}
local _variantBaseSpec = nil -- spec key the live table was loaded for

local function _variantBaseSV()
    local saved = ECME and ECME.db
    return saved and saved.sv or nil
end

-- Seeds the live table for the current spec, and reloads it when the spec
-- changes, since the previous spec's pairs do not describe the new one. Reads
-- WITHOUT creating; only _learnVariantBase creates, so the table appears the
-- first time a pair is actually observed. Bails without latching while the db
-- or the spec is not up yet, so a later rebuild retries.
local function _loadVariantBases()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not specKey then
        return
    end
    if _variantBaseSpec == specKey then
        return
    end
    local savedVars = _variantBaseSV()
    if not savedVars then
        return
    end
    wipe(_variantBaseLearned)
    _variantBaseSpec = specKey
    local root = savedVars._variantBase
    if type(root) == "table" then
        -- Pre-release test builds stored pairs flat, keyed by spellID, before
        -- spec scoping existed. Those answers cannot be attributed to a spec so
        -- they cannot be trusted; drop them rather than leave them orphaned.
        -- Clearing existing fields during pairs() is defined behaviour in Lua.
        for key in pairs(root) do
            if type(key) ~= "string" then
                root[key] = nil
            end
        end
    end
    local storage = (type(root) == "table") and root[specKey] or nil
    if type(storage) ~= "table" then
        return
    end
    for variant, base in pairs(storage) do
        if type(variant) == "number" and type(base) == "number" and base > 0 and base ~= variant then
            _variantBaseLearned[variant] = base
        end
    end
end

-- Record a pair in the live table and the current spec's store. Callers gate
-- ids for secrecy before calling: a secret must never index a table, let alone
-- reach SavedVariables. The unchanged-pair early-out keeps the resolve path,
-- which relearns the live pairing on every call, from touching the store per
-- frame. Persists only once the spec is known, so a pair observed before that
-- still routes this session without being filed under the wrong spec.
local function _learnVariantBase(variant, base)
    if _variantBaseLearned[variant] == base then
        return
    end
    _variantBaseLearned[variant] = base
    if not _variantBaseSpec then
        return
    end
    local savedVars = _variantBaseSV()
    if not savedVars then
        return
    end
    local root = savedVars._variantBase
    if type(root) ~= "table" then
        root = {}
        savedVars._variantBase = root
    end
    local storage = root[_variantBaseSpec]
    if type(storage) ~= "table" then
        storage = {}
        root[_variantBaseSpec] = storage
    end
    storage[variant] = base
end

-- Reset hook for the CDM's own reset path. Without it a pair learned wrong is
-- permanent: StripDefaults never walks this key and no profile operation
-- touches it, so there would be no way back short of editing SavedVariables.
function mod.ResetVariantBaseStore()
    wipe(_variantBaseLearned)
    _variantBaseSpec = nil
    local savedVars = _variantBaseSV()
    if savedVars then
        savedVars._variantBase = nil
    end
end

-- Equivalence check for the picker/list helpers: true when both ids reach the
-- same root through the learned variant -> base ledger. The live spell APIs
-- are blind to a rotating override's inactive form (Sacred Weapon/Holy
-- Bulwark), while the ledger keeps the pair. Called from FindVariantIndex
-- loops, so no per-call closure: the two root walks are inlined. The hop cap
-- guards a cyclic pair.
function mod.IsLearnedVariantOf(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then
        return false
    end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return false
    end
    if a <= 0 or b <= 0 then
        return false
    end
    _loadVariantBases()
    local hops = 0
    while hops < 8 do
        local nxt = _variantBaseLearned[a]
        if not nxt or nxt == a then
            break
        end
        a = nxt
        hops = hops + 1
    end
    hops = 0
    while hops < 8 do
        local nxt = _variantBaseLearned[b]
        if not nxt or nxt == b then
            break
        end
        b = nxt
        hops = hops + 1
    end
    return a == b
end
mod._divertedSpellsBuff = _divertedSpellsBuff
mod._divertedSpellsCD = _divertedSpellsCD

-- Sentinel: true at the end of a successful RebuildSpellRouteMap. CollectAndReanchor's
-- safety net tests THIS, not _cdidRouteMap (lazy cache, intentionally empty post-build)
-- and not the diversion maps (legitimately empty for users with no diversions).
local _routeMapBuilt = false

--- Rebuild the diversion set. cdID->bar is computed lazily at reanchor by
--- ResolveCDIDToBar, which uses the frame's actual viewerFrame as default (NOT
--- GetCooldownViewerCategorySet, whose STATIC category can differ from where the
--- live viewer shows a spell after Edit Mode drag / per-spec layout). Default
--- bars contribute too: a spellID in cooldowns/utility assignedSpells means
--- "this default bar regardless of category", enabling cross-routing between
--- default bars (e.g. Lay on Hands, Essential viewer -> utility bar). Collision
--- priority (rare under the 1-spell-per-bar invariant): ghost bars (lowest) ->
--- custom buff -> custom CD/util -> default bars (highest), later passes
--- overwrite via preserveExisting=false. Family split: each bar writes
--- _divertedSpellsBuff or _divertedSpellsCD so buff/CD bars claiming the same
--- spellID (e.g. Divine Shield 642) never clobber each other.
function mod.RebuildSpellRouteMap()
    wipe(_cdidRouteMap)
    wipe(_divertedSpellsBuff)
    wipe(_divertedSpellsCD)
    wipe(_divertedDirectBuff)
    wipe(_divertedDirectCD)
    wipe(_divertedVarBaseBuff)
    wipe(_divertedVarBaseCD)
    wipe(_divertedBuffCdIDs)
    wipe(mod._divertedSlotCD)
    wipe(mod._divertedItemCD)
    wipe(mod._nativeItemKeyByCat)
    wipe(mod._divertedRankCD)
    wipe(mod._buffReplaceTarget)
    wipe(mod._buffReplaceTargetCd)
    wipe(mod._buffReplaceBars)
    _routeMapBuilt = false

    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then
        return
    end

    -- Before any StoreDirect: the recall below is the only thing that can supply
    -- a base for an assigned variant that is not the live form, and this is the
    -- first build of the session.
    _loadVariantBases()

    local SVV = mod.StoreVariantValue
    if not SVV then
        return
    end

    local IsBuffFamily = mod.IsBarBuffFamily

    -- Record an exact assignment plus its base when the assigned id is a variant
    -- form; same overwrite semantics as the direct sets (later pass wins).
    -- Assigned ids come from stored config (plain numbers), so no secret gating here -- the resolve side gates.
    local GetBase = C_Spell and C_Spell.GetBaseSpell
    local function StoreDirect(targetMap, spellRef, barId)
        local isBuff = (targetMap == _divertedSpellsBuff)
        SVV(targetMap, spellRef, barId, false, isBuff and _divertedDirectBuff or _divertedDirectCD)
        -- Learn the base while the client will still say, else recall the last
        -- answer: without the recall the claim is written only on rebuilds that
        -- happen while this exact variant is live, and routing still flips.
        local base
        if GetBase then
            local success, b = pcall(GetBase, spellRef)
            if success and type(b) == "number" and b > 0 and b ~= spellRef then
                base = b
                _learnVariantBase(spellRef, b)
            end
        end
        base = base or _variantBaseLearned[spellRef]
        if base and base ~= spellRef then
            local varMap = isBuff and _divertedVarBaseBuff or _divertedVarBaseCD
            varMap[base] = barId
        end
    end

    local RankName = mod.CDMRankName
    local function CollectDiversionsFor(edge, skipPositiveSet)
        local sd = mod.GetBarSpellData(edge.key)
        if not sd or not sd.assignedSpells then
            return
        end
        local targetMap = IsBuffFamily and IsBuffFamily(edge) and _divertedSpellsBuff or _divertedSpellsCD
        local byRank = RankName and targetMap == _divertedSpellsCD
        for _, spellRef in ipairs(sd.assignedSpells) do
            if type(spellRef) == "number" and spellRef > 0 then
                if not skipPositiveSet or not skipPositiveSet[spellRef] then
                    StoreDirect(targetMap, spellRef, edge.key)
                    local num = byRank
                        and not (sd.customSpellIDs and sd.customSpellIDs[spellRef])
                        and RankName(spellRef)
                    if num then
                        mod._divertedRankCD[num] = edge.key
                    end
                end
            else
                -- Equipment slot entry: routes Blizzard's own equipment cooldown
                -- for that slot, which has no spellID to key on. Same overwrite
                -- order as the sid maps above, so a custom bar outranks the
                -- default (pass 3) and a ghost bar hides it (pass 4).
                local slot = mod.SlotIDFromKey and mod.SlotIDFromKey(spellRef)
                if slot then
                    mod._divertedSlotCD[slot] = edge.key
                elseif mod.IsItemPresetKey(spellRef) then
                    -- Item preset entry: Blizzard's own row for that item (a potion
                    -- or healthstone category row) routes to the bar listing it.
                    mod._divertedItemCD[spellRef] = edge.key
                end
            end
        end
    end

    -- Pass 1: custom buff bars + custom_buff (TBB) bars. TBB bars compete for
    -- the same buff icon spells, so their diversions land in
    -- _divertedSpellsBuff even though IsBarBuffFamily is false for custom_buff.
    for _, edge in ipairs(profile.cdmBars.bars) do
        if
            edge.enabled
            and not edge.isGhostBar
            and ((edge.barType == "buffs" and edge.key ~= "buffs") or edge.barType == "custom_buff")
        then
            local sd = mod.GetBarSpellData(edge.key)
            if sd and sd.assignedSpells then
                for _, spellRef in ipairs(sd.assignedSpells) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        StoreDirect(_divertedSpellsBuff, spellRef, edge.key)
                    end
                end
            end
            -- cooldownID-level claims (collided buffs tracked by slot marker)
            local claims = sd and mod.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = edge.key
                end
            end
        end
    end
    -- Pass 2: default bars FIRST among the CD family; Pass 3 custom CD/util bars
    -- overwrite them so explicit custom-bar placement OUTRANKS the default
    -- (else a spell also in cooldowns.assignedSpells, materialized spillover
    -- both-state, renders on the default cooldowns bar).
    for _, edge in ipairs(profile.cdmBars.bars) do
        if
            edge.enabled
            and not edge.isGhostBar
            and (edge.key == "cooldowns" or edge.key == "utility" or edge.key == "buffs")
        then
            CollectDiversionsFor(edge)
        end
    end
    -- Pass 3: custom CD/utility bars overwrite the default diversions
    -- (deliberate custom-bar placement wins).
    for _, edge in ipairs(profile.cdmBars.bars) do
        if
            edge.enabled
            and not edge.isGhostBar
            and edge.key ~= "cooldowns"
            and edge.key ~= "utility"
            and edge.key ~= "buffs"
            and edge.barType ~= "buffs"
            and edge.barType ~= "custom_buff"
        then
            CollectDiversionsFor(edge)
        end
    end
    -- Pass 3b: HOSTED BUFFS. A buff on a CD/utility bar (sd.hostedBuffSpellIDs)
    -- must ALSO divert in the BUFF-family map: the frame comes from the BuffIcon
    -- viewer, so ResolveCDIDToBar reads only _divertedSpellsBuff for it. After
    -- passes 1-2 so an explicit host outranks a stray buff-bar copy; the bar's
    -- Pass 3 CD diversion is untouched (separate family maps).
    for _, edge in ipairs(profile.cdmBars.bars) do
        if
            edge.enabled
            and not edge.isGhostBar
            and edge.barType ~= "buffs"
            and edge.barType ~= "custom_buff"
        then
            local sd = mod.GetBarSpellData(edge.key)
            if sd and sd.hostedBuffSpellIDs then
                -- Keyed off hostedBuffSpellIDs, not assignedSpells: the CD/util
                -- drop pass can transiently strip a buff from assignedSpells
                -- (buffs never appear in the Essential/Utility viewer) and the
                -- diversion must survive that. SVV expands variants so any live
                -- talent/override form resolves.
                for spellRef in pairs(sd.hostedBuffSpellIDs) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        StoreDirect(_divertedSpellsBuff, spellRef, edge.key)
                    end
                end
            end
            -- Cd-claimed hosted buffs (collided slots hosted by cd-claim marker instead
            -- of the sid-keyed hostedBuffSpellIDs flag): claim the cooldownID in
            -- _divertedBuffCdIDs, same map/priority as Pass 1. ResolveCDIDToBar checks
            -- it before any sid map, so it works for any target bar type.
            local claims = sd and mod.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = edge.key
                end
            end
        end
    end
    -- Pass 3c: "Replace with Buff". A cd/util entry can name a tracked buff
    -- whose viewer frame takes the cooldown's slot while the aura is active.
    -- Divert the buff exactly like a hosted buff (same map, same variant
    -- expansion) and remember which cooldown it stands in for; the collect
    -- pass swaps the frames. Gated: a profile with no mapping skips the pass.
    if mod._cdmAnyBuffReplace then
        for _, edge in ipairs(profile.cdmBars.bars) do
            if
                edge.enabled
                and not edge.isGhostBar
                and edge.barType ~= "buffs"
                and edge.barType ~= "custom_buff"
            then
                local sd = mod.GetBarSpellData(edge.key)
                local storage = sd and sd.assignedSpells and mod.GetSpellSettingsStore(edge.key)
                if storage then
                    -- One buff frame can stand in for ONE cooldown per bar; the
                    -- setter enforces it on write, this guards data that arrived
                    -- by copy (spec/RPT sync). First assigned entry wins.
                    local seenBuff
                    for _, spellRef in ipairs(sd.assignedSpells) do
                        if type(spellRef) == "number" and spellRef > 0 then
                            local ss = storage[spellRef]
                            local buffSid = ss and rawget(ss, "replaceBuffID")
                            if type(buffSid) == "number" and buffSid > 0 then
                                local buffCd = rawget(ss, "replaceBuffCdID")
                                local ident = (type(buffCd) == "number" and buffCd > 0) and -buffCd or buffSid
                                seenBuff = seenBuff or {}
                                if not seenBuff[ident] then
                                    seenBuff[ident] = true
                                    mod._buffReplaceBars[edge.key] = true
                                    if ident < 0 then
                                        _divertedBuffCdIDs[buffCd] = edge.key
                                        mod._buffReplaceTargetCd[buffCd] = spellRef
                                    else
                                        StoreDirect(_divertedSpellsBuff, buffSid, edge.key)
                                        SVV(mod._buffReplaceTarget, buffSid, spellRef, false)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Stale ghost ALIASES of a visible family: a rotating override can sit in
    -- the ghost under one form (Holy Bulwark 432459) while its base (375576)
    -- is visibly assigned -- the add path could not remove the ghost entry
    -- because the live APIs are blind to the inactive form. Close the visible
    -- CD keys over the learned variant/base ledger, then drop from that set
    -- every id that is EXACTLY assigned to a visible bar: what remains are
    -- pure aliases, and only those ghost entries are skipped below. Routing
    -- only -- the ghost entry itself is untouched.
    local ghostAliasSkip = {}
    for spellRef in pairs(_divertedSpellsCD) do
        ghostAliasSkip[spellRef] = true
    end
    local expanded
    repeat
        expanded = false
        for variant, base in pairs(_variantBaseLearned) do
            if ghostAliasSkip[variant] or ghostAliasSkip[base] then
                if not ghostAliasSkip[variant] then
                    ghostAliasSkip[variant] = true
                    expanded = true
                end
                if not ghostAliasSkip[base] then
                    ghostAliasSkip[base] = true
                    expanded = true
                end
            end
        end
    until not expanded
    for spellRef in pairs(_divertedDirectCD) do
        ghostAliasSkip[spellRef] = nil
    end

    -- Pass 4: ghost bars LAST = HIGHEST priority. A spell the user HID stays
    -- hidden even if the same id also sits on a visible bar ("both-state");
    -- ns.AddSpellToBar removes it from the ghost, so this never hides a
    -- deliberate placement. Only a ghost entry that is a pure ALIAS of a
    -- visible family (set above) is skipped.
    for _, edge in ipairs(profile.cdmBars.bars) do
        if edge.enabled and edge.isGhostBar then
            CollectDiversionsFor(edge, ghostAliasSkip)
        end
    end

    -- The key each of Blizzard's item rows renders under: a key of its category a
    -- visible bar lists (the player's own placement), else one the ghost bar lists
    -- (the row hides with it), else the category's first key (the reseed lists it
    -- where the row renders).
    local nativeKeys = mod.CDM_NATIVE_ITEM_KEYS
    if nativeKeys then
        local byKey = mod.barDataByKey
        for category, keyList in pairs(nativeKeys) do
            local pick
            for index = 1, #keyList do
                local barFrame = mod._divertedItemCD[keyList[index]]
                local bdK = barFrame and byKey and byKey[barFrame]
                if barFrame and not (bdK and bdK.isGhostBar) then
                    pick = keyList[index]
                    break
                end
            end
            if not pick then
                for index = 1, #keyList do
                    if mod._divertedItemCD[keyList[index]] then
                        pick = keyList[index]
                        break
                    end
                end
            end
            mod._nativeItemKeyByCat[category] = pick or keyList[1]
        end
    end

    _routeMapBuilt = true
end

-- Blizzard's own potion / healthstone row (a spell-category row of the Essential or
-- Utility viewer): the preset key it renders under, or nil for any other row. Reads
-- the RAW cooldown info (the merged copy folds categories). The second return says
-- the row's live frame resolves a racial spell: such a row is a racial, never an
-- item, whatever category it carries, and stays on the managed spell path.
function mod.NativeItemKeyFor(details, widget)
    local category = details and details.spellCategoryID
    if type(category) ~= "number" or (issecretvalue and issecretvalue(category)) then
        return nil, false
    end
    local live = widget and widget.GetSpellID and widget:GetSpellID()
    if
        type(live) == "number"
        and not (issecretvalue and issecretvalue(live))
        and mod.ALL_RACIAL_SPELLS[live]
    then
        return nil, true
    end
    return mod._nativeItemKeyByCat[category], false
end

--- Lazily resolve a cooldownID to a bar key (per-frame at reanchor).
--- _cdidRouteMap memoizes; on miss compute from the per-family diversion map or
--- fall back to viewerDefaultBar ("cooldowns"/"utility"/"buffs" = the viewer pool
--- the frame came from, user-visible ground truth, not the static category API),
--- which also selects the family map (buffs -> _divertedSpellsBuff, else CD).

-- Plain readable positive number, never inspecting a secret (type() and
-- issecretvalue read only the tags). Mirrors _IsUsableSID in the spell picker;
-- tells a real "no diversion" answer from a blind lookup with all-secret ids.
local function CdidIDReadable(id)
    if type(id) ~= "number" then
        return false
    end
    if issecretvalue and issecretvalue(id) then
        return false
    end
    return id > 0
end

local function ResolveCDIDToBar(cdID, viewerDefaultBar)
    if not cdID then
        return viewerDefaultBar
    end
    local cached = _cdidRouteMap[cdID]
    if cached then
        return cached
    end

    -- cooldownID-level claim first (collided buffs tracked by slot). Needs no
    -- cooldownInfo read, so it also works while every sid field is secret.
    if viewerDefaultBar == "buffs" then
        local cdRoute = _divertedBuffCdIDs[cdID]
        if cdRoute then
            _cdidRouteMap[cdID] = cdRoute
            return cdRoute
        end
    end

    local RVV = mod.ResolveVariantValue
    local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not RVV or not getCdInfo then
        _cdidRouteMap[cdID] = viewerDefaultBar
        return viewerDefaultBar
    end

    local divertMap = (viewerDefaultBar == "buffs") and _divertedSpellsBuff or _divertedSpellsCD
    local directMap = (viewerDefaultBar == "buffs") and _divertedDirectBuff or _divertedDirectCD
    local varBaseMap = (viewerDefaultBar == "buffs") and _divertedVarBaseBuff or _divertedVarBaseCD

    local details = getCdInfo(cdID)
    if not details then
        -- Info not ready (transient: login / spec swap). Return the fallback
        -- WITHOUT caching: _cdidRouteMap is wiped only by RebuildSpellRouteMap,
        -- so caching would pin a ghosted/custom spell to its default bar.
        return viewerDefaultBar
    end
    -- Free learning: a slot always reports its stable base alongside the live
    -- variant, so every resolve teaches one pairing. Covers a session starting
    -- with the assigned variant NOT live: the first transform makes it known.
    if
        CdidIDReadable(details.spellID)
        and CdidIDReadable(details.overrideSpellID)
        and details.overrideSpellID ~= details.spellID
    then
        _learnVariantBase(details.overrideSpellID, details.spellID)
    end

    -- Equipment-backed entry: the slot is the only identity it has, so it routes
    -- before every sid probe below (all of which would miss). Memoized like any
    -- other resolve; the slot map is rebuilt with the rest. CD/utility viewers
    -- ONLY: a BUFF-viewer equipment row is a tracked trinket PROC BUFF
    -- (category EquipSlotTracked), and the slot map is the CD-side preset
    -- lane -- routing buff rows through it captured proc buffs onto the
    -- trinket preset's bar, overriding their custom buff bar assignment
    -- (field report 2026-08-16: worked with the presets absent, captured with
    -- them present). Buff rows fall through to the sid probes instead: their
    -- raw linked list carries the proc sid even at rest.
    if viewerDefaultBar ~= "buffs" then
        if CdidIDReadable(details.equipSlot) then
            local slotBar = mod._divertedSlotCD[details.equipSlot]
            if slotBar then
                _cdidRouteMap[cdID] = slotBar
                return slotBar
            end
        elseif issecretvalue and issecretvalue(details.equipSlot) then
            -- Equipment row with its slot UNREADABLE (active in restricted
            -- content): the sid probes below see the active window's use-spell
            -- forms and can route -- and PIN via the cdID cache -- the row onto
            -- whatever bar happens to carry that form (the occasional
            -- custom->default "trinket jump", same field report). The slot is
            -- the one stable channel for these rows, so resolve transiently to
            -- the fallback, uncached, and let the next clean pass route by
            -- slot.
            return viewerDefaultBar
        end
        -- Blizzard's own potion / healthstone row: no spell of its own either, so
        -- it routes by the preset key its category maps to (NativeItemKeyFor) to
        -- the bar listing that preset (a ghost listing hides it), else the viewer
        -- default; cached like the slot route (the reseed that lists the key
        -- rebuilds the map). A category UNREADABLE in restricted content resolves
        -- transiently, uncached, like an unreadable slot.
        local category = details.spellCategoryID
        if category ~= nil then
            if issecretvalue and issecretvalue(category) then
                return viewerDefaultBar
            end
            local itemKey = mod._nativeItemKeyByCat[category]
            if itemKey then
                local itemBar = mod._divertedItemCD[itemKey] or viewerDefaultBar
                _cdidRouteMap[cdID] = itemBar
                return itemBar
            end
        end
    end

    local routedBar = nil
    do
        -- EXACT assignments first, override form before base: one slot can carry
        -- several variant-family members on different bars and only the exact ids
        -- say where each was wanted. The override wins because it's the form
        -- castable right now (e.g. "Holy Bulwark on utility" beats the
        -- repopulated base Divine Toll on cooldowns) -- otherwise the winner
        -- depended on collection order. The base comes LAST: it's typically
        -- present via repopulate while override/linked forms are player-chosen,
        -- so it must never outrank them (either mistake made the icon change bars
        -- on every transform). Every id is gated through CdidIDReadable: on an
        -- active viewer frame these can be SECRET, never index a table with one.
        if CdidIDReadable(details.overrideSpellID) then
            routedBar = directMap[details.overrideSpellID]
        end
        if not routedBar and details.linkedSpellIDs then
            for _, lid in ipairs(details.linkedSpellIDs) do
                if CdidIDReadable(lid) then
                    routedBar = directMap[lid]
                    if routedBar then
                        break
                    end
                end
            end
        end
        -- The variant this slot is NOT transformed into is invisible here (no
        -- linkedSpellIDs): findable only via its base, the one constant id.
        if not routedBar and CdidIDReadable(details.spellID) then
            routedBar = varBaseMap[details.spellID]
        end
        if not routedBar and CdidIDReadable(details.spellID) then
            routedBar = directMap[details.spellID]
        end
        -- No raw `> 0` / `~=` comparisons on info.spellID/overrideSpellID: on an
        -- active viewer frame these can be secret and comparing a secret taints
        -- execution. RVV gates its input through _IsUsableSID internally, so feed
        -- it the raw fields and let it reject anything unusable.
        if not routedBar then
            routedBar = RVV(divertMap, details.spellID)
        end
        if not routedBar then
            routedBar = RVV(divertMap, details.overrideSpellID)
        end
        if not routedBar and details.linkedSpellIDs then
            for _, lid in ipairs(details.linkedSpellIDs) do
                routedBar = RVV(divertMap, lid)
                if routedBar then
                    break
                end
            end
        end
        -- WoW Forever: a row that does not link the listed rank goes by its name.
        local RankName = mod.CDMRankName
        if not routedBar and RankName and viewerDefaultBar ~= "buffs" then
            routedBar =
                mod._divertedRankCD[RankName(details.overrideSpellID) or RankName(details.spellID) or false]
        end
    end

    if not routedBar then
        -- No diversion found. Trust (and cache) that only if at least one id was
        -- readable: with every id secret (active viewer frame in combat) the
        -- lookup was blind and caching would pin the wrong bar until the next
        -- RebuildSpellRouteMap.
        local sawReadable = CdidIDReadable(details.spellID) or CdidIDReadable(details.overrideSpellID)
        if not sawReadable and details.linkedSpellIDs then
            for _, lid in ipairs(details.linkedSpellIDs) do
                if CdidIDReadable(lid) then
                    sawReadable = true
                    break
                end
            end
        end
        if not sawReadable then
            return viewerDefaultBar
        end
    end

    routedBar = routedBar or viewerDefaultBar
    _cdidRouteMap[cdID] = routedBar
    return routedBar
end
mod.ResolveCDIDToBar = ResolveCDIDToBar
mod._cdidRouteMap = _cdidRouteMap

Inner.ResolveCDIDToBar, Inner.ResolveFrameSpellID = ResolveCDIDToBar, ResolveFrameSpellID
Inner.ResolveSpellSettings = ResolveSpellSettings
Inner.IsRouteMapBuilt = function()
    return _routeMapBuilt
end
Inner.broken = false
