if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarTick.lua
--
--  The combat and visibility gates and UpdateTrackedBuffBarTimers, the
--  per-frame tick.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetTime = GetTime
local pcall = pcall
local abs = math.abs
local min = math.min
local ANTI_CLIP = mod.CDM_ANTI_CLIP

local _pandemicState, FormatTime = Inner._pandemicState, Inner.FormatTime
local LifebloomPandemic, _tbbWake = Inner.LifebloomPandemic, Inner._tbbWake
local ReflowVisibleGroupedTBBars, tbbFrames = Inner.ReflowVisibleGroupedTBBars, Inner.tbbFrames
local AnchorTBBSparkState, ApplyTBBTickMarks = Inner.AnchorTBBSparkState, Inner.ApplyTBBTickMarks
local FeedTBBThresholdOverlay, _tbbStickyCdID = Inner.FeedTBBThresholdOverlay, Inner._tbbStickyCdID
local AssignFramesToConfigs, CfgWantsSID = Inner.AssignFramesToConfigs, Inner.CfgWantsSID
local MatchesSID, TbbCfgFamilyMatch = Inner.MatchesSID, Inner.TbbCfgFamilyMatch
local TbbNameFamily, TbbSlotVariantLabeled = Inner.TbbNameFamily, Inner.TbbSlotVariantLabeled
local _potionDur, _potionExpiry, _ts = Inner._potionDur, Inner._potionExpiry, Inner._ts
local _UpdateSelfTimedBar, ClearPandemic = Inner._UpdateSelfTimedBar, Inner.ClearPandemic
local EffectiveIconSpellID = Inner.EffectiveIconSpellID
local GetBlizzBarFontStrings, MirrorEngineTimer = Inner.GetBlizzBarFontStrings, Inner.MirrorEngineTimer
local TIME_SPIRAL_DURATION, UpdateLustBar = Inner.TIME_SPIRAL_DURATION, Inner.UpdateLustBar
local UpdatePandemic, UpdateStacks = Inner.UpdatePandemic, Inner.UpdateStacks
local _UpdateCooldownBar, SetAssignDirty = Inner._UpdateCooldownBar, Inner.SetAssignDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val)
    ECME = val
end
-- Feature-gating flags (rebuilt in BuildTrackedBuffBars, read in tick)
local _anyPandemic = false
Inner.anyPandemicSetters[#Inner.anyPandemicSetters + 1] = function(val)
    _anyPandemic = val
end
local _anyThreshold = false
Inner.anyThresholdSetters[#Inner.anyThresholdSetters + 1] = function(val)
    _anyThreshold = val
end
local _anyStacks = false
Inner.anyStacksSetters[#Inner.anyStacksSetters + 1] = function(val)
    _anyStacks = val
end
local _anyVisCond = false
Inner.anyVisCondSetters[#Inner.anyVisCondSetters + 1] = function(val)
    _anyVisCond = val
end
local tbbTickFrame
Inner.tickFrameSetters[#Inner.tickFrameSetters + 1] = function(val)
    tbbTickFrame = val
end
-- Group reflow gate: see _MarkTBBReflowDirty in CUI_CDM_BuffBarGroups.lua.
local _tbbReflowDirty = true
Inner.reflowDirtySetters[#Inner.reflowDirtySetters + 1] = function(val)
    _tbbReflowDirty = val
end
-- Smooth-fill switch memo for the tick: GetTBBSmoothSettings walks the profile store,
-- and its result can only change with the active profile name or the live spec-profile bucket, both re-read per tick without a call.
local _tickSm, _tickSmProf, _tickSmSp

-------------------------------------------------------------------------------
--  "Only In Combat" gate
--  Combat state comes from the main module's event-tracked flag (debounced combat
--  exit, so a mob dying between pulls does not flash every bar away).
--  InCombatLockdown() is only the fallback for a load order that has not published
--  the shared read yet.
-------------------------------------------------------------------------------
local function TBBInCombat()
    if mod.CDMInCombat then
        return mod.CDMInCombat()
    end
    return InCombatLockdown() and true or false
end

-- Park a bar the combat gate hides. Drops the same transient render state the inactive
-- branches drop, so the next in-combat show re-resolves icon/name/fill from scratch instead of mirroring a stale frame.
local function HideTBBBarForCombat(bar)
    -- Already parked: nothing to tear down, and clearing _nameSet here would make the
    -- deferred name-fill pass re-resolve the spell every frame for the whole time out of combat.
    if not bar:IsShown() then
        return
    end
    if bar._pandemicGlowActive then
        ClearPandemic(bar)
    end
    if bar._stacksText then
        bar._stacksText:Hide()
    end
    bar._stackCount = 0
    bar._cachedBlizzFillTex = nil
    bar._cachedOurFillTex = nil
    bar._cachedBlizzIconTex = nil
    bar._cachedBlizzIconOwner = nil
    bar._lastIconSID = nil
    bar._nameSet = nil
    bar:Hide()
end

-------------------------------------------------------------------------------
--  "Visibility" gate (CDM-Bars-style mode + options, TBB-scoped)
--  Mirrors _CDMApplyVisibility's priority-2/3 checks (CUI_CDM_Rebuild.lua),
--  but folded into TBB's own tick since TBB bars are not native CDM bars.
--  Zero cost for bars without a condition: the tick consults the gate only
--  for bars flagged at build (bar._tbbVisCond) and fills the shared state
--  table ONCE per pass (TBBFillVisState) when any bar carries a condition.
-------------------------------------------------------------------------------
local _tbbVisState = {}

local function TBBFillVisState()
    local inRaid = IsInRaid and IsInRaid() or false
    _tbbVisState.inCombat = TBBInCombat()
    _tbbVisState.inRaid = inRaid
    _tbbVisState.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
end

local function TBBVisibilityHides(conf)
    if CludesUI.CheckVisibilityOptions(conf) then
        return true
    end

    local vis = conf.barVisibility or "always"
    local visExt =
        CludesUI.EvalVisibilityExtended(conf, "barVisibility", _tbbVisState, CludesUI.VIS_CAPS_DEFAULT)
    if visExt ~= nil then
        return not visExt
    end
    if vis == "never" then
        return true
    end
    if vis == "in_combat" then
        return not _tbbVisState.inCombat
    end
    if vis == "out_of_combat" then
        return _tbbVisState.inCombat
    end
    if vis == "in_raid" then
        return not _tbbVisState.inRaid
    end
    if vis == "in_party" then
        return not _tbbVisState.inParty
    end
    if vis == "solo" then
        return _tbbVisState.inRaid or _tbbVisState.inParty
    end
    return false
end

-- Does this bar rely on a Visibility mode or option? Mirrors what TBBVisibilityHides reads,
-- minus hideWhenInactive/onlyInCombat, which flip on the aura and combat edges the sleeper
-- already wakes on. Option keys come from the shared list so a new one is covered here too.
local function TBBUsesVisCondition(conf)
    if not conf then
        return false
    end
    local vis = conf.barVisibility
    if vis and vis ~= "always" then
        return true
    end
    local vm = conf.visibilityModes
    if type(vm) == "table" and next(vm) then
        return true
    end
    local keyList = CludesUI.VIS_OPT_KEYS
    if keyList then
        for idx = 1, #keyList do
            if conf[keyList[idx]] then
                return true
            end
        end
    end
    return false
end

-- Name, icon, auto fill colour and stacks on a mirrored bar change only when
-- Blizzard refreshes the bound frame's data: on player and target aura events
-- and target changes (the wake frame counts both), a new binding or slot, and
-- the active edge. So the tick re-reads them on those edges, once more on the
-- tick after (Blizzard cleans a dirty frame in its own OnUpdate, which may run
-- after ours), and at least every TBB_CONTENT_REFRESH seconds for the edges it
-- does not count (totems, spell overrides, icon updates). Every path that
-- leaves the active mirror, and every settings apply, clears bar._cChild, so a
-- return is always an edge. An unreadable cooldownID fails open to every tick.
local TBB_CONTENT_REFRESH = 0.25
local function TBBContentDue(bar, blzChild, conf, wasShown, nowTime)
    local cd = blzChild.cooldownID
    local pGen, tGen = _tbbWake._fbPGen, _tbbWake._fbTGen
    local sticky = _tbbStickyCdID[conf]
    if
        not wasShown
        or bar._cChild ~= blzChild
        or bar._cPGen ~= pGen
        or bar._cTGen ~= tGen
        or bar._cSticky ~= sticky
        or issecretvalue(cd)
        or bar._cCdID ~= cd
    then
        bar._cChild, bar._cPGen, bar._cTGen, bar._cSticky = blzChild, pGen, tGen, sticky
        bar._cCdID = not issecretvalue(cd) and cd or nil
        bar._cAgain = true
        bar._cAt = nowTime
        return true
    end
    if bar._cAgain or nowTime - bar._cAt >= TBB_CONTENT_REFRESH then
        bar._cAgain = nil
        bar._cAt = nowTime
        return true
    end
    return false
end

-------------------------------------------------------------------------------
--  Main Tick: UpdateTrackedBuffBarTimers
--  Direct reskin of Blizzard's BuffBarCooldownViewer StatusBars: reads
--  min/max/value from Blizzard's Bar, zero duration computation.
-------------------------------------------------------------------------------
function mod.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then
        return
    end
    local tbb = mod.GetTrackedBuffBars()
    local barList = tbb.bars
    if not barList then
        return
    end

    -- Liveness for the idle sleeper: set by any branch below that is actually animating or tracking something this tick.
    local tickLive = false
    local nowTime = GetTime()

    -- Resolved once per tick, not per bar: the bind-miss fallback below asks the target
    -- for a debuff the player applied, and there is no point asking with nothing targeted.
    local hasTarget = UnitExists and UnitExists("target") and true or false

    -- Profile-wide smooth-fill switches, resolved once per tick for every fill site (absent buffs key = enabled; absent cooldowns key = OFF).
    local sm
    do
        local pn = CludesUIDB and CludesUIDB.activeProfile
        local sp = mod._cachedSpecProfiles
        if _tickSm and pn == _tickSmProf and sp == _tickSmSp then
            sm = _tickSm
        else
            sm = mod.GetTBBSmoothSettings and mod.GetTBBSmoothSettings()
            _tickSm, _tickSmProf, _tickSmSp = sm, pn, sp
        end
    end
    if sm then
        _tbbWake._smoothBuffs = sm.buffs ~= false
        _tbbWake._smoothCooldowns = sm.cooldowns == true
    else
        _tbbWake._smoothBuffs, _tbbWake._smoothCooldowns = true, false
    end

    -- Self-heal placeholder mode when the user navigates away from Tracking Bars
    if mod._tbbPlaceholderMode then
        local am = CludesUI:GetActiveModule()
        local ap = CludesUI:GetActivePage()
        if am ~= "CludesUICooldownManager" or ap ~= "Tracking Bars" then
            mod._tbbPlaceholderMode = false
            if mod.HideTBBPlaceholders then
                mod.HideTBBPlaceholders()
            end
            -- Auras may have moved while the preview was up: re-pair on the first real mirror tick.
            SetAssignDirty(true)
            -- The preview may have written the self-timed bars' timer text and
            -- the mirrored bars' name, icon and stacks: drop their stamps so the
            -- next live tick rewrites them.
            for bi = 1, #tbbFrames do
                local b = tbbFrames[bi]
                if b then
                    b._stTxtKey = nil
                    b._cChild = nil
                end
            end
        end
    end

    -- Pair configs to Blizzard frames ONE-TO-ONE up front, consuming each frame once, so two
    -- configs sharing a cooldownInfo (Eclipse Solar+Lunar) cannot both mirror the same frame and show twice.
    local assignment = AssignFramesToConfigs(barList)

    -- Visibility gate inputs, once per pass, only when some bar has a condition.
    if _anyVisCond then
        TBBFillVisState()
    end

    -- Audio on Buff Loss for the self-timed presets: a latch the gain armed
    -- fires at the window's end ahead of every visibility gate below, so a bar
    -- parked at that moment (Only In Combat after combat drops) still cues.
    -- The window has no end event, so a pending latch keeps the tick awake;
    -- one found long past its end (the tick was parked) clears silently.
    local lossLatch = mod._tbbPresetLoss
    if next(lossLatch) then
        for pk, at in pairs(lossLatch) do
            if nowTime >= at then
                lossLatch[pk] = nil
                if nowTime - at < 1 then
                    mod.TBBPresetSoundEdge(pk, false)
                end
            else
                tickLive = true
            end
        end
    end

    for idx, conf in ipairs(barList) do
        local bar = tbbFrames[idx]
        if not bar or not bar._tbbReady then
            -- skip
        elseif mod._tbbPlaceholderMode then
            tickLive = true
            if not bar:IsShown() then
                bar:Show()
            end
        elseif conf.enabled == false then
            bar:Hide()
        elseif bar._tbbVisCond and TBBVisibilityHides(conf) then
            HideTBBBarForCombat(bar)
        elseif conf.onlyInCombat and not TBBInCombat() then
            -- "Only In Combat": out of combat the bar is gone regardless of aura/cooldown state, and regardless of Hide When Inactive.
            HideTBBBarForCombat(bar)
        elseif conf.popularKey == "bloodlust" then
            -- Self-driven 40s lust bar; no Blizzard frame to mirror.
            if UpdateLustBar(bar, conf) then
                tickLive = true
            end
        elseif conf.popularKey == "timespiral" then
            -- Self-driven 10s Time Spiral "Free Move" bar; glow-armed, no frame.
            if _UpdateSelfTimedBar(bar, conf, _ts.expiry, TIME_SPIRAL_DURATION) then
                tickLive = true
            end
        elseif conf.popularKey and _potionDur[conf.popularKey] then
            -- Self-cast potion preset: hardcoded window off the spell-cast edge; no aura tracking, no Blizzard frame to mirror.
            if
                _UpdateSelfTimedBar(
                    bar,
                    conf,
                    _potionExpiry[conf.popularKey] or 0,
                    _potionDur[conf.popularKey]
                )
            then
                tickLive = true
            end
        elseif conf.trackType == "cooldown" then
            -- Spell-cooldown tracking: self-driven, no Blizzard frame/aura.
            _UpdateCooldownBar(bar, conf)
            -- Live while an engine handle drives the fill OR the bar is on screen: covers the
            -- secret-timing mirror drain and always-shown bars, both needing per-tick updates.
            if bar._cdDurObj or bar:IsShown() then
                tickLive = true
            end
        else
            local blzChild = assignment[conf]
            if blzChild then
                mod.HookPandemicState(blzChild)
            end

            -- Active state MUST come from the CooldownViewer item's IsActive() (real
            -- aura state: expirationTime > now, or infinite auras), NEVER IsShown(): a
            -- buff-bar item stays SHOWN while inactive unless the user enabled
            -- Blizzard's "Hide When Inactive" edit-mode option (off by default), which
            -- would leave our bar visible 100% of the time. Fall back to IsShown() only
            -- if IsActive is absent.
            local isActive = false
            if blzChild then
                if blzChild.IsActive then
                    isActive = blzChild:IsActive() and true or false
                elseif blzChild.IsShown then
                    isActive = blzChild:IsShown() or false
                end
            end

            -- Blizzard viewer bind-miss / not-tracked-at-all fallback: covers (1) the
            -- buff-bar viewer failing to bind a freshly applied aura (auraInstanceID
            -- never set, IsActive stuck false until another bar's activation forces a
            -- refresh) and (2) a spell absent from every CooldownViewer category
            -- (blzChild permanently nil, e.g. a hero-talent proc CDM never registers).
            -- Either way, when the player demonstrably carries the aura (known-spellID
            -- player-aura query, no scanning), drive the bar from the aura data --
            -- reads only, our own frames only, NEVER pokes the Blizzard frame.
            local fbAura
            if
                not isActive
                and not conf.spellIDs
                and conf.spellID
                and conf.spellID > 0
                and C_UnitAuras
                and C_UnitAuras.GetPlayerAuraBySpellID
            then
                -- Each half re-queries only after its own aura edge (the wake frame
                -- counts player aura events in _fbPGen; target aura events and target
                -- changes in _fbTGen), not on every tick: a refresh or an expiry is
                -- such an event, so the kept aura data stays current.
                if bar._fbCfg ~= conf or bar._fbSpell ~= conf.spellID or bar._fbBase ~= conf.baseSpellID then
                    bar._fbCfg, bar._fbSpell, bar._fbBase = conf, conf.spellID, conf.baseSpellID
                    bar._fbPGen, bar._fbTGen = nil, nil
                end
                if bar._fbPGen ~= _tbbWake._fbPGen then
                    bar._fbPGen = _tbbWake._fbPGen
                    local a = C_UnitAuras.GetPlayerAuraBySpellID(conf.spellID)
                    if not a and conf.baseSpellID and conf.baseSpellID > 0 then
                        a = C_UnitAuras.GetPlayerAuraBySpellID(conf.baseSpellID)
                    end
                    bar._fbPAura = a or false
                end
                fbAura = bar._fbPAura or nil
                -- Same net for a debuff the player put on the TARGET, which the queries
                -- above can never see. Blizzard's viewer stalls exactly there after a
                -- macro that clears and restores the target inside one frame: its
                -- OnPlayerTargetChanged compares GUIDs, sees the same one it stored, and
                -- never refreshes, so the item stays inactive until a real target switch.
                if not fbAura and hasTarget then
                    if bar._fbTGen ~= _tbbWake._fbTGen then
                        bar._fbTGen = _tbbWake._fbTGen
                        bar._fbTAura = _tbbWake.GetTargetAura(conf) or false
                    end
                    fbAura = bar._fbTAura or nil
                end
                -- Fallback driving means the viewer has not bound this aura yet, and
                -- Blizzard's late-bind can land WITHOUT a fresh player aura event. Keep
                -- the memo dirty while any fallback is live so the next tick re-pairs
                -- the moment the frame appears (restoring stacks/pandemic from mirror).
                if fbAura then
                    SetAssignDirty(true)
                end
            end
            if isActive or fbAura then
                tickLive = true
            end

            -- Read Blizzard's StatusBar (the data source for fill/timer)
            local blizzBar = blzChild and blzChild.Bar

            if isActive then
                local wasShown = bar:IsShown()
                if not wasShown then
                    bar:Show()
                end
                local scrollBar = bar._bar
                -- Name, icon, auto fill colour and stacks: on edges only (TBBContentDue).
                local contentFrame = TBBContentDue(bar, blzChild, conf, wasShown, nowTime)

                -- Stacks (gated)
                if _anyStacks and contentFrame then
                    UpdateStacks(bar, blzChild, conf)
                end

                if blizzBar then
                    -- Mirror Blizzard's bar onto ours. Secret values pass natively to widget
                    -- setters (NEVER compared in Lua). Smooth fill is baseline (see UpdateLustBar note).
                    local smooth = _tbbWake._smoothBuffs
                        and wasShown
                        and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if
                        conf.stackBasedBar
                        and conf.trackType ~= "cooldown"
                        and conf.stackThresholdMaxEnabled
                    then
                        -- Stack-based fill: current stacks over the user's Max Stacks instead
                        -- of the time mirror. An unreadable count (no cached aura data, no
                        -- readable instance id) fails open to a full bar, like every unreadable fill here.
                        if bar._stackUnreadable then
                            scrollBar:SetMinMaxValues(0, 1)
                            scrollBar:SetValue(1)
                        else
                            scrollBar:SetMinMaxValues(0, conf.stackThresholdMax or 10)
                            if smooth then
                                scrollBar:SetValue(bar._stackCount or 0, smooth)
                            else
                                scrollBar:SetValue(bar._stackCount or 0)
                            end
                        end
                    elseif smooth then
                        scrollBar:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        scrollBar:SetValue(blizzBar:GetValue(), smooth)
                    else
                        scrollBar:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        scrollBar:SetValue(blizzBar:GetValue())
                    end
                    if conf.showSpark and bar._spark then
                        bar._spark:Show()
                    end

                    -- Auto fill color from Blizzard's bar texture
                    if contentFrame and (conf.fillColorMode or "auto") == "auto" then
                        -- Cache texture refs: GetStatusBarTexture() allocates userdata per call.
                        local blizzFillTex = bar._cachedBlizzFillTex
                        if not blizzFillTex then
                            blizzFillTex = blizzBar:GetStatusBarTexture()
                            bar._cachedBlizzFillTex = blizzFillTex
                        end
                        if blizzFillTex then
                            local br, backdrop, bb, ba = blizzFillTex:GetVertexColor()
                            if br then
                                if bar._gradientActive and bar._gradTex then
                                    local c1 = bar._gradColor1 or CreateColor(0, 0, 0, 1)
                                    local c2 = bar._gradColor2 or CreateColor(0, 0, 0, 1)
                                    bar._gradColor1 = c1
                                    bar._gradColor2 = c2
                                    c1.r, c1.g, c1.b, c1.a = br, backdrop, bb, ba or 1
                                    c2.r, c2.g, c2.b, c2.a =
                                        conf.gradientR or 0.20,
                                        conf.gradientG or 0.20,
                                        conf.gradientB or 0.80,
                                        conf.gradientA or 1
                                    bar._gradTex:SetGradient(conf.gradientDir or "HORIZONTAL", c1, c2)
                                else
                                    local ourFillTex = bar._cachedOurFillTex
                                    if not ourFillTex then
                                        ourFillTex = scrollBar:GetStatusBarTexture()
                                        bar._cachedOurFillTex = ourFillTex
                                    end
                                    if ourFillTex then
                                        ourFillTex:SetVertexColor(br, backdrop, bb, ba or 1)
                                    end
                                end
                            end
                        end
                    end

                    -- Name resolution ladder:
                    --  1. Blizzard's rendered label FontString on the BOUND
                    --     frame -- the only channel carrying live variant
                    --     names (Diabolist probe 2026-08-16: on the active
                    --     ritual frame every id AND the aura-instance read are
                    --     secret even out of combat; only the label knows
                    --     which ritual is up). FIELD-PROVEN 2026-08: a hidden
                    --     pool frame's label can ALSO hold another slot's
                    --     readable text persistently after re-acquire (binding
                    --     right, label lying -- SotR as "Consecration", Bone
                    --     Shield as "Blood Draw"), so the label is trusted
                    --     only inside the config's name family: readable text
                    --     must be family-compatible, and secret text paints
                    --     only on slots whose linked forms provably render
                    --     distinct names. Secrets pass straight to SetText
                    --     (never compared or stored).
                    --  2. Live aura data, when readable and provably this bar's
                    --     family (exact config ids or the bound slot's
                    --     cooldownInfo override/spellID/linkedSpellIDs).
                    --  3. The configured spell's name (deterministic).
                    -- None of it runs for a bar with a custom name: the build painted
                    -- that, and nothing else writes the label.
                    if
                        contentFrame
                        and bar._nameText
                        and bar._nameText:IsShown()
                        and not mod.TBBCustomName(conf)
                    then
                        local nameStr
                        -- auraInstanceID may itself be SECRET on the active frame
                        -- (probe-confirmed): type() reads the tag without touching
                        -- the value -- the taint-safe presence test for secrets.
                        -- SLOT CHECK (the Wardead class, 2+ bars in one group in
                        -- combat): cooldownID stays a plain readable number in
                        -- secret windows, so a pooled frame moved to another slot
                        -- since binding is caught before its label is read (the
                        -- sticky pass applies the identical test on its own
                        -- schedule); a mismatch skips the label and falls through.
                        if
                            blzChild
                            and blzChild:IsShown()
                            and blizzBar
                            and type(blzChild.auraInstanceID) ~= "nil"
                            and (_tbbStickyCdID[conf] == nil or blzChild.cooldownID == _tbbStickyCdID[conf])
                        then
                            local blizzNameFS = GetBlizzBarFontStrings(blizzBar)
                            if blizzNameFS then
                                local success, txt = pcall(blizzNameFS.GetText, blizzNameFS)
                                if success and txt ~= nil then
                                    if issecretvalue and issecretvalue(txt) then
                                        if TbbSlotVariantLabeled(bar, blzChild.cooldownID) then
                                            nameStr = txt
                                        end
                                    elseif txt ~= "" then
                                        -- Family gate memoized on (cfg, cfg.name,
                                        -- text): the verdict only moves when the
                                        -- rendered string or the config does.
                                        if
                                            bar._labelGateCfg ~= conf
                                            or bar._labelGateNm ~= conf.name
                                            or bar._labelGateTxt ~= txt
                                        then
                                            bar._labelGateCfg = conf
                                            bar._labelGateNm = conf.name
                                            bar._labelGateTxt = txt
                                            bar._labelGateOk =
                                                TbbCfgFamilyMatch(conf, TbbNameFamily(txt), true)
                                        end
                                        if bar._labelGateOk then
                                            nameStr = txt
                                        end
                                    end
                                end
                            end
                        end
                        if
                            not nameStr
                            and blzChild
                            and blzChild.auraInstanceID
                            and blzChild.auraDataUnit
                            and not (issecretvalue and issecretvalue(blzChild.auraInstanceID))
                        then
                            local success, ad = pcall(
                                C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit,
                                blzChild.auraInstanceID
                            )
                            if
                                success
                                and ad
                                and ad.name
                                and not (issecretvalue and issecretvalue(ad.name))
                            then
                                local spellRef = ad.spellId
                                if spellRef ~= nil and not (issecretvalue and issecretvalue(spellRef)) then
                                    local mine = CfgWantsSID(conf, spellRef)
                                    if
                                        not mine
                                        and blzChild.cooldownID
                                        and not (issecretvalue and issecretvalue(blzChild.cooldownID))
                                        and C_CooldownViewer
                                        and C_CooldownViewer.GetCooldownViewerCooldownInfo
                                    then
                                        local ok2, details = pcall(
                                            C_CooldownViewer.GetCooldownViewerCooldownInfo,
                                            blzChild.cooldownID
                                        )
                                        if ok2 and details then
                                            local ok3, m = pcall(MatchesSID, details, spellRef)
                                            mine = ok3 and m
                                        end
                                    end
                                    if mine then
                                        nameStr = ad.name
                                    end
                                end
                            end
                        end
                        if not nameStr and conf.spellID and conf.spellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(conf.spellID)
                            if spInfo then
                                nameStr = spInfo.name
                            elseif C_Spell.RequestLoadSpellData then
                                C_Spell.RequestLoadSpellData(conf.spellID)
                            end
                        end
                        if not nameStr and conf.baseSpellID and conf.baseSpellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(conf.baseSpellID)
                            if spInfo then
                                nameStr = spInfo.name
                            end
                        end
                        if nameStr then
                            bar._nameText:SetText(nameStr)
                            bar._nameSet = true
                        end
                    end
                    -- Timer: engine-bound decimal mirror first (the engine formats the secret
                    -- remaining time into a hidden FS we copy). Fallback: passthrough from
                    -- Blizzard's FontString every frame (it changes constantly).
                    if MirrorEngineTimer(bar, conf) then
                        bar._timerText:Show()
                    else
                        local _, blizzTimerFS = GetBlizzBarFontStrings(blizzBar)
                        if conf.showTimer and bar._timerText and blizzTimerFS then
                            bar._timerText:SetText(blizzTimerFS:GetText())
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    end

                    -- Icon source priority: 1) Blizzard's icon texture on the bound
                    -- frame (SetBarContent already resolved the override/variant form,
                    -- so mirroring the file can never disagree with Blizzard's own CDM;
                    -- mirrored on the content edges like the fill color, passes through
                    -- even when secret since SetTexture accepts secrets); 2) live aura data
                    -- (frames without an icon region), so dynamic buffs (Roll the
                    -- Bones) show the rolled buff; 3) effective config spell
                    -- (override-resolved saved id). Every non-config write clears
                    -- _lastIconSID so the config fallback can't skip its SetTexture
                    -- against a stale cache and strand another source's icon.
                    if contentFrame and bar._icon and bar._icon:IsShown() then
                        local gotIcon = false
                        if bar._cachedBlizzIconOwner ~= blzChild then
                            local iconRegion = blzChild.Icon
                            bar._cachedBlizzIconTex = (iconRegion and iconRegion.Icon) or false
                            bar._cachedBlizzIconOwner = blzChild
                        end
                        local blzIconTex = bar._cachedBlizzIconTex
                        if blzIconTex then
                            local file = blzIconTex:GetTexture()
                            if file then
                                bar._icon._tex:SetTexture(file)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon and blzChild.auraInstanceID and blzChild.auraDataUnit then
                            local success, ad = pcall(
                                C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit,
                                blzChild.auraInstanceID
                            )
                            -- Instance ids recycle onto other buffs; only trust a match.
                            if success and ad and ad.icon and CfgWantsSID(conf, ad.spellId) then
                                bar._icon._tex:SetTexture(ad.icon)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon then
                            local iconSID = EffectiveIconSpellID(conf)
                            if iconSID and iconSID ~= bar._lastIconSID then
                                local spInfo = C_Spell.GetSpellInfo(iconSID)
                                if spInfo and spInfo.iconID then
                                    bar._icon._tex:SetTexture(spInfo.iconID)
                                    bar._lastIconSID = iconSID
                                end
                            end
                        end
                    end

                    -- Pandemic glow: the ShowPandemicStateFrame hook sets _pandemicState.
                    -- Requires the user to enable pandemic alerts in Blizzard CDM settings.
                    -- WoW Forever: the anti-clip glow instead (CUI_CDM_ForeverAntiClip.lua).
                    if _anyPandemic and conf.pandemicGlow then
                        local inPandemic
                        if ANTI_CLIP then
                            inPandemic = blzChild and mod.CDM_AntiClip and mod.CDM_AntiClip(blzChild)
                        else
                            inPandemic = blzChild and _pandemicState[blzChild]
                            -- Fallback for auras Blizzard never pandemic-flags (currently only
                            -- Lifebloom). bar._isLifebloom is cached after the first resolve, so a
                            -- bar known not to be Lifebloom costs one table read and skips.
                            if not inPandemic and blzChild and bar._isLifebloom ~= false then
                                inPandemic = LifebloomPandemic(bar, blzChild)
                            end
                        end
                        -- TBBs always show OUR glow (Blizzard Default included): the native
                        -- PandemicIcon lives on the hidden blzChild frame, not our visible TBB bar.
                        if inPandemic then
                            if not bar._pandemicGlowActive then
                                UpdatePandemic(bar, conf)
                            end
                            if bar._pandemicGlowTarget then
                                bar._pandemicGlowTarget:SetAlpha(1)
                            end
                        elseif bar._pandemicGlowActive then
                            ClearPandemic(bar)
                        end
                    elseif bar._pandemicGlowActive then
                        ClearPandemic(bar)
                    end
                else
                    -- Active aura but no Blizzard bar data: show full bar
                    scrollBar:SetMinMaxValues(0, 1)
                    scrollBar:SetValue(1)
                    if bar._timerText then
                        bar._timerText:Hide()
                    end
                    if bar._spark then
                        bar._spark:Hide()
                    end
                    if bar._pandemicGlowActive then
                        ClearPandemic(bar)
                    end
                end

                -- Threshold feed (gated)
                if _anyThreshold and conf.stackThresholdEnabled then
                    FeedTBBThresholdOverlay(bar)
                end

                -- Deferred tick marks
                if bar._ticksDirty and scrollBar then
                    local bw = scrollBar:GetWidth()
                    if bw and bw > 0 then
                        ApplyTBBTickMarks(
                            scrollBar,
                            conf,
                            bar._threshTicks,
                            conf.verticalOrientation,
                            bar._tickOverlay
                        )
                        bar._ticksDirty = nil
                    end
                end
            elseif fbAura then
                -- Bind-miss fallback: self-drive fill/timer from the live aura until
                -- Blizzard's frame catches up; isActive then resumes the normal mirror path seamlessly.
                bar._cChild = nil
                local wasShown = bar:IsShown()
                if not wasShown then
                    bar:Show()
                end
                local scrollBar = bar._bar
                local dur = fbAura.duration
                local exp = fbAura.expirationTime
                local isSec = issecretvalue
                local clean = dur and exp and not (isSec and (isSec(dur) or isSec(exp)))
                -- Stack-based fill works in fallback mode too: fill and stacks text come from
                -- the live aura's applications (plain or secret; SetValue/SetText accept both) while the timer keeps tracking remaining time.
                local fbStackFill = conf.stackBasedBar
                    and conf.trackType ~= "cooldown"
                    and conf.stackThresholdMaxEnabled
                if scrollBar and fbStackFill then
                    local apps = fbAura.applications
                    -- The aura is up, so a readable count floors at 1 even when applications reads 0/nil (non-stacking aura).
                    if not apps or (not (isSec and isSec(apps)) and apps < 1) then
                        apps = 1
                    end
                    scrollBar:SetMinMaxValues(0, conf.stackThresholdMax or 10)
                    local smooth = _tbbWake._smoothBuffs
                        and wasShown
                        and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if smooth then
                        scrollBar:SetValue(apps, smooth)
                    else
                        scrollBar:SetValue(apps)
                    end
                    bar._stackCount = apps
                    if bar._stacksText and not bar._stacksHidden then
                        bar._stacksText:SetText(apps)
                        bar._stacksText:Show()
                    elseif bar._stacksText then
                        bar._stacksText:Hide()
                    end
                    -- Timer text: same handling as the duration fill below.
                    if clean and dur > 0 then
                        if conf.showTimer and bar._timerText then
                            local remaining = exp - GetTime()
                            if remaining < 0 then
                                remaining = 0
                            end
                            if not MirrorEngineTimer(bar, conf) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    elseif bar._timerText then
                        bar._timerText:SetShown(MirrorEngineTimer(bar, conf))
                    end
                    if conf.showSpark and bar._spark then
                        bar._spark:Show()
                    end
                elseif scrollBar then
                    if clean and dur > 0 then
                        local remaining = exp - GetTime()
                        if remaining < 0 then
                            remaining = 0
                        end
                        scrollBar:SetMinMaxValues(0, dur)
                        local smooth = _tbbWake._smoothBuffs
                            and wasShown
                            and Enum
                            and Enum.StatusBarInterpolation
                            and Enum.StatusBarInterpolation.ExponentialEaseOut
                        if smooth then
                            scrollBar:SetValue(remaining, smooth)
                        else
                            scrollBar:SetValue(remaining)
                        end
                        if conf.showTimer and bar._timerText then
                            -- Engine-bound decimal mirror first; the clean local format is the fallback.
                            if not MirrorEngineTimer(bar, conf) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    else
                        -- Duration unreadable (secret) or infinite aura: show a full bar with no countdown.
                        scrollBar:SetMinMaxValues(0, 1)
                        scrollBar:SetValue(1)
                        if bar._timerText then
                            -- The engine-bound decimal mirror can render the secret remaining
                            -- time we cannot; otherwise no readable time -> no text.
                            bar._timerText:SetShown(MirrorEngineTimer(bar, conf))
                        end
                    end
                    if conf.showSpark and bar._spark then
                        bar._spark:Show()
                    end
                end
                -- Icon/name from the aura data itself: fires when the frame mirror is
                -- unavailable, and for override/variant spells the build-time saved-form
                -- icon can be the wrong form, so the live aura is the truth. Icon passes
                -- through even when secret (SetTexture accepts secrets); name applies
                -- only on a clean read (font strings need a plain string) and never
                -- over a bar's custom name.
                if bar._icon and bar._icon:IsShown() and fbAura.icon then
                    bar._icon._tex:SetTexture(fbAura.icon)
                    bar._lastIconSID = nil
                end
                local fbName = fbAura.name
                if
                    bar._nameText
                    and bar._nameText:IsShown()
                    and fbName
                    and not (isSec and isSec(fbName))
                    and not mod.TBBCustomName(conf)
                then
                    bar._nameText:SetText(fbName)
                    bar._nameSet = true
                end
                -- Extras stay quiet in fallback mode: no Blizzard child to read stacks/pandemic from. Skipped when the stack fill drove them.
                if not (scrollBar and fbStackFill) then
                    if bar._stacksText then
                        bar._stacksText:Hide()
                    end
                    bar._stackCount = 0
                end
                if bar._pandemicGlowActive then
                    ClearPandemic(bar)
                end
            else
                -- Inactive: clear transient state
                bar._cChild = nil
                bar._cachedBlizzFillTex = nil
                bar._cachedOurFillTex = nil
                bar._cachedBlizzIconTex = nil
                bar._cachedBlizzIconOwner = nil
                bar._lastIconSID = nil
                if _anyPandemic and bar._pandemicGlowActive then
                    ClearPandemic(bar)
                end
                if bar._stacksText then
                    bar._stacksText:Hide()
                end
                bar._stackCount = 0
                if conf.hideWhenInactive == false then
                    -- "Hide When Inactive" off: keep the bar on screen as an empty idle bar (name visible, no fill/timer/spark).
                    if not bar:IsShown() then
                        bar:Show()
                    end
                    local scrollBar = bar._bar
                    if scrollBar then
                        scrollBar:SetMinMaxValues(0, 1)
                        scrollBar:SetValue(0)
                    end
                    if bar._timerText then
                        bar._timerText:Hide()
                    end
                    if bar._spark then
                        bar._spark:Hide()
                    end
                elseif bar:IsShown() then
                    -- Clear the name latch on the hide EDGE only: clearing it every hidden
                    -- tick would make the deferred name fill call C_Spell.GetSpellInfo every tick for every hidden bar.
                    bar._nameSet = nil
                    bar:Hide()
                end
            end
        end
    end

    -- Re-pack visible grouped Tracking Bars after the active/inactive pass so hidden buffs do not reserve a slot in the group.
    if _tbbReflowDirty then
        ReflowVisibleGroupedTBBars(tbb, barList)
    end

    -- Deferred name fill: retry each tick when BuildTrackedBuffBars could not resolve the spell name (spell data not loaded yet).
    for idx, conf in ipairs(barList) do
        local bar = tbbFrames[idx]
        if bar and bar._nameText and not bar._nameSet then
            local customName = mod.TBBCustomName(conf)
            if customName then
                bar._nameText:SetText(customName)
                bar._nameSet = true
            elseif conf.spellID and conf.spellID > 0 then
                local si = C_Spell.GetSpellInfo(conf.spellID)
                if si and si.name then
                    bar._nameText:SetText(si.name)
                    bar._nameSet = true
                end
            end
        end
    end

    -- Normal-fill spark maintenance (hash-fill sparks are anchored by their own renderer).
    -- Both paths use AnchorTBBSparkState's scalar signature, so unchanged anchors do no native layout work and allocate nothing.
    for _, bar in ipairs(tbbFrames) do
        -- bar:IsShown() gate: a child spark's own shown flag stays latched true after its
        -- parent bar Hides, so without this the loop would keep anchoring sparks of hidden bars every tick forever.
        if bar and bar:IsShown() and bar._spark and bar._spark:IsShown() and bar._bar then
            if not bar._chargeHashFillActive then
                local anchor = (bar._gradientActive and bar._gradClip) or bar._cachedOurFillTex
                if not anchor then
                    anchor = bar._bar:GetStatusBarTexture()
                    bar._cachedOurFillTex = anchor
                end
                if anchor then
                    AnchorTBBSparkState(bar, anchor, bar._lastVertical, bar._lastReverse, false)
                end
            end
        end
    end

    -- Smooth opacity lerp
    local dt = tbbTickFrame and tbbTickFrame._lastDt or 0.016
    local lerpSpeed = dt * 8
    for _, f in ipairs(tbbFrames) do
        if f and f._opacityTarget then
            local current = f:GetAlpha()
            local tgt = f._opacityTarget
            if abs(current - tgt) > 0.005 then
                f:SetAlpha(current + (tgt - current) * min(1, lerpSpeed))
            elseif current ~= tgt then
                f:SetAlpha(tgt)
            end
        end
    end

    -- Idle sleeper: after ~0.5s of ticks with nothing live, park the OnUpdate entirely and
    -- let the wake listeners re-arm it. The settle window lets smooth fills and the opacity
    -- lerp converge (both ease within ~0.35s) before updates stop, and stays short so wake bursts remain cheap.
    if tickLive then
        _tbbWake._idleTicks = 0
    elseif tbbTickFrame and tbbTickFrame:IsShown() then
        local num = _tbbWake._idleTicks + 1
        _tbbWake._idleTicks = num
        if num >= 30 then
            _tbbWake.Sleep()
        end
    end
end

Inner.TBBUsesVisCondition = TBBUsesVisCondition
Inner.broken = false
