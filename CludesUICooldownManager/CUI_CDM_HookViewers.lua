if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookViewers.lua
--
--  Position re-snap, the reanchor queue, SetupViewerHooks with the buff ticker
--  and the Edit Mode lock.
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
local cdmBarFrames = mod.cdmBarFrames
local cdmBarIcons = mod.cdmBarIcons
local _ecmeFC = mod._ecmeFC
local GetTime = GetTime

local GetViewerFrame, hookFrameData = Inner.GetViewerFrame, Inner.hookFrameData
local VIEWER_NAMES, ResolveFrameSpellID = Inner.VIEWER_NAMES, Inner.ResolveFrameSpellID
local _activeCache, _activeStacksCache = Inner._activeCache, Inner._activeStacksCache
local _smHookedIcons, SwiftmendEnabled = Inner._smHookedIcons, Inner.SwiftmendEnabled
local ProcessPresetCooldowns = Inner.ProcessPresetCooldowns
local CollectAndReanchor, UpdateCustomBuffBars = Inner.CollectAndReanchor, Inner.UpdateCustomBuffBars
local QueueViewerAnchor, RestoreViewerAnchors = Inner.QueueViewerAnchor, Inner.RestoreViewerAnchors

local needsReanchor = false
local reanchorFrame = nil
local viewerHooksInstalled = false

-------------------------------------------------------------------------------
--  Queue claimed icons after active-state changes without interrupting a
--  viewer's layout measurement or re-enumerating its pool.
-------------------------------------------------------------------------------
local function ReapplyPositions()
    for barId, icons in pairs(cdmBarIcons) do
        if icons then
            for index = 1, #icons do
                local widget = icons[index]
                if widget then
                    local frameData = hookFrameData[widget]
                    local anchor = frameData and frameData._cdmAnchor
                    if anchor then
                        QueueViewerAnchor(widget)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Reanchor Queue
-------------------------------------------------------------------------------
local REANCHOR_THROTTLE = 0.2
local _lastReanchorTime = 0

local function QueueReanchor()
    -- Always queue, never drop. If a spec swap is in progress the
    -- ProcessReanchorQueue gate will hold the request until the flag
    -- clears, then the queued reanchor fires naturally.
    needsReanchor = true
    if reanchorFrame then
        reanchorFrame:Show()
    end
end
mod.QueueReanchor = QueueReanchor

-- Cancel any pending queued reanchor. Used by FullCDMRebuild's spec swap branch when it
-- runs CollectAndReanchor directly -- without this, the reanchor BuildAllCDMBars queued
-- earlier in the same call would fire a second time after the throttle expires.
local function ClearQueuedReanchor()
    needsReanchor = false
end
mod.ClearQueuedReanchor = ClearQueuedReanchor

local function ProcessReanchorQueue(self)
    if not needsReanchor then
        self:Hide()
        return
    end
    local nowTime = GetTime()
    if nowTime - _lastReanchorTime < REANCHOR_THROTTLE then
        return
    end
    needsReanchor = false
    _lastReanchorTime = nowTime
    CollectAndReanchor()
    -- WoW Forever: the anti-clip glow draws the icons this placed.
    if mod.CDM_AntiClipPlaced then
        mod.CDM_AntiClipPlaced()
    end
    -- Reapply visibility: newly collected icons may be at alpha 0.
    if mod.CDMApplyVisibility then
        mod.CDMApplyVisibility()
    end
end

-------------------------------------------------------------------------------
--  Sync extra buff bars with Blizzard CDM viewer
--
--  Reanchor extra buff bars shortly after the Blizzard CDM settings panel
--  closes, once Blizzard has finished rebuilding its viewer pools.
--
--  Buff-family removal happens ONLY inside ns.ReconcileAssignedSpellDrops's
--  buff-family branch, gated on the persisted variant-alias ledger: a
--  candidate id drops only once every learned-family member is absent from
--  the buff-category catalog present-set AND not currently displayed. This
--  function never prunes. Do NOT reintroduce frame-pool-based orphan pruning
--  here (stripping any positive assignedSpells entry whose spellID isn't
--  found in the BuffIcon pool/CDM category set): DUAL-TRACKED spells
--  carrying more than one variant spell ID cause data loss. E.g. Vengeance
--  DH stores Metamorphosis as 191427, but every live Vengeance frame reports
--  187827 -- 191427 surfaces ONLY via the buff frame's linkedSpellIDs, and
--  ONLY while the buff is active, so a presence-only prune running here
--  (~0.3s after the panel closes, when Meta is typically down) would match
--  neither the pool nor the category set and delete it -- which also
--  destroys the route-map diversion, spilling re-tracked Meta onto the
--  DEFAULT buffs bar. The ledger-gated pass survives this case once the
--  191427<->187827 pairing has been learned, by keeping the whole family
--  alive while any member (e.g. 187827) is present; a family never learned
--  on this spec remains a harmless non-rendering preview entry (removable
--  by hand), consistent with the CD/utility side.
-------------------------------------------------------------------------------
function mod.SyncExtraBuffBarsWithViewer()
    QueueReanchor()
end

-------------------------------------------------------------------------------
--  SetupViewerHooks (mixin hooks)
--
--  Hook strategy:
--    1. OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    2. Pool Acquire on all viewers -> QueueReanchor
--    3. Viewer Layout -> QueueReanchor (catches frame removals)
--    4. Buff ticker (0.1s) for staleness + glow
-------------------------------------------------------------------------------
function mod.SetupViewerHooks()
    if viewerHooksInstalled then
        return
    end
    viewerHooksInstalled = true

    -- Reanchor queue frame
    reanchorFrame = mod.TakeShell()
    reanchorFrame:SetScript("OnUpdate", ProcessReanchorQueue)
    reanchorFrame:Hide()

    -- 1. Mixin hooks: detect spell changes on CDM frames. Reset frame spell
    --    cache so the next reanchor re-resolves the spellID (handles transforms
    --    like Avenging Crusader -> Crusader Strike). CD/utility bars: spell set
    --    is locked during a session (changes only via FullCDMRebuild on
    --    spec/talent/equip events) -- real-time reanchors from OnCooldownIDSet
    --    are unnecessary and catastrophic when Blizzard continuously rebuilds
    --    pools (e.g. Lightsmith Holy Armaments), so we only clear the FC cache
    --    for the next rebuild. Buff bars ARE dynamic (appear/disappear at
    --    runtime), so they still need real-time OnCooldownIDSet reanchors.
    local function ResetFrameCache(widget)
        -- Content churn: re-arm the buff ticker's dirty + pool gates.
        mod._acGen = (mod._acGen or 0) + 1
        mod._btDirty = true
        if mod.ArmBuffTicker then
            mod.ArmBuffTicker()
        end
        if widget then
            local frameCache = _ecmeFC[widget]
            if frameCache then
                frameCache.resolvedSid = nil
                frameCache.baseSpellID = nil
                frameCache.overrideSid = nil
                frameCache.cachedCdID = nil
            end
        end
    end
    -- Buff mixins: clear cache + reanchor (dynamic)
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", function(widget)
            ResetFrameCache(widget)
            QueueReanchor()
        end)
    end
    if CooldownViewerBuffBarItemMixin and CooldownViewerBuffBarItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffBarItemMixin, "OnCooldownIDSet", function(widget)
            mod._acGen = (mod._acGen or 0) + 1
            mod._btDirty = true
            if mod.ArmBuffTicker then
                mod.ArmBuffTicker()
            end
            if mod.InvalidateTBBFrameCache then
                mod.InvalidateTBBFrameCache()
            end
            ResetFrameCache(widget)
            QueueReanchor()
        end)
    end
    -- CD/utility mixins: clear cache only (static set, rebuilt by FullCDMRebuild)
    if CooldownViewerEssentialItemMixin and CooldownViewerEssentialItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerEssentialItemMixin, "OnCooldownIDSet", ResetFrameCache)
    end
    if CooldownViewerUtilityItemMixin and CooldownViewerUtilityItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerUtilityItemMixin, "OnCooldownIDSet", ResetFrameCache)
    end

    -- (Per-spell Custom Icon re-assert is NOT hooked here: mixin-table hooks
    -- never fire for item frames created before install, because the mixin's
    -- functions are copied onto each frame instance at creation. The re-assert
    -- is a per-frame instance hook installed lazily by ApplyCustomIcon.)

    -- 2. Pool acquire hooks: detect new frames + install per-frame hooks
    -- Track which frames have been hooked (weak-keyed, no taint)
    local _activeStateHooked = setmetatable({}, { __mode = "k" })
    local _activeStateReanchorPending = false

    local function InstallBuffFrameHooks(viewerFrame)
        if not viewerFrame or not viewerFrame.itemFramePool then
            return
        end
        -- Attach the buff gain/loss sound hook here -- at pool-acquire time, BEFORE
        -- Blizzard finishes setting the frame up and fires its first
        -- TriggerAuraAppliedAlert. Installing it lazily in DecorateFrame ran one step
        -- too late on a frame's FIRST activation, so the very first "buff gained" cue
        -- was missed (loss + later gains worked because the hook then persisted).
        -- EnsureBuffSoundHook self-guards (hooks once), gated 0-cost on the feature.
        local ensureSound = mod._cdmAnyBuffSound and mod.EnsureBuffSoundHook
        for widget in viewerFrame.itemFramePool:EnumerateActive() do
            if ensureSound then
                mod.EnsureBuffSoundHook(widget)
            end
            if not _activeStateHooked[widget] then
                _activeStateHooked[widget] = true
                -- Hook OnActiveStateChanged: Blizzard calls this when a buff
                -- becomes active/inactive. Run a full reanchor so new/removed
                -- icons get collected and centered. Batched via C_Timer to
                -- collapse the spam (fires many times per frame).
                -- Use the throttled queue here, not a direct call, so bursts
                -- of state changes can't stack up multiple full reanchors.
                if widget.OnActiveStateChanged then
                    local _asDeferFrame = CreateFrame("Frame")
                    _asDeferFrame:Hide()
                    local _asDeferTicks = 0
                    _asDeferFrame:SetScript("OnUpdate", function(self)
                        _asDeferTicks = _asDeferTicks + 1
                        if _asDeferTicks < 2 then
                            return
                        end
                        self:Hide()
                        _activeStateReanchorPending = false
                        QueueReanchor()
                    end)
                    local isBarViewer = viewerFrame == _G["BuffBarCooldownViewer"]
                    hooksecurefunc(widget, "OnActiveStateChanged", function(itemIcon)
                        -- Wake a parked Tracking Bars tick when this item activates (a
                        -- deactivation has nothing to show): the sleeper's probe can run
                        -- before the item binds its aura, reads a secret aura as nil and
                        -- hears no target auras. Keep this ahead of the shared pending
                        -- return below, which any buff item's change holds for two frames.
                        if isBarViewer and mod.WakeTBBTickIfParked then
                            mod.WakeTBBTickIfParked(itemIcon)
                        end
                        ReapplyPositions()
                        if _activeStateReanchorPending then
                            return
                        end
                        _activeStateReanchorPending = true
                        _asDeferTicks = 0
                        _asDeferFrame:Show()
                    end)
                end
            end
        end
    end

    for viewerIndex, vName in ipairs(VIEWER_NAMES) do
        local val = _G[vName]
        if val and val.itemFramePool then
            if val.RefreshLayout then
                hooksecurefunc(val, "RefreshLayout", RestoreViewerAnchors)
            end
            local isBuff = (viewerIndex == 3 or viewerIndex == 4) -- BuffIcon or BuffBar
            local isBarViewer = (viewerIndex == 4) -- BuffBarCooldownViewer
            hooksecurefunc(val.itemFramePool, "Acquire", function()
                mod._acGen = (mod._acGen or 0) + 1
                mod._btDirty = true
                if mod.ArmBuffTicker then
                    mod.ArmBuffTicker()
                end
                if isBuff then
                    InstallBuffFrameHooks(val)
                end
                if isBarViewer and mod.InvalidateTBBFrameCache then
                    mod.InvalidateTBBFrameCache()
                end
                -- A new tracked-bar spell acquires a pool frame here: let the
                -- Tracking Bars auto-add pass pick it up (debounced, no-op
                -- unless a never-seen spell appeared).
                if isBarViewer and mod.QueueTBBAutoAdd then
                    mod.QueueTBBAutoAdd()
                end
                -- Only buff viewers need real-time reanchors on Acquire.
                -- CD/utility spell sets are static (rebuilt by FullCDMRebuild).
                if isBuff then
                    QueueReanchor()
                end
            end)
            -- Hook existing frames too
            if isBuff then
                InstallBuffFrameHooks(val)
            end

            -- Intercept newly acquired frames the instant Blizzard creates them, before
            -- they render at the viewer's default position. Alpha 0 until our reanchor
            -- claims and positions them. The pool Acquire hook above already queues a
            -- reanchor. Skip during init: on /reload ALL frames are acquired at once
            -- and our reanchor hasn't run yet, so blanking them would hide all buffs
            -- until the first buff change.
            if val.OnAcquireItemFrame then
                hooksecurefunc(val, "OnAcquireItemFrame", function(_, itemIcon)
                    if not mod._initialReanchorDone then
                        return
                    end
                    -- Skip blanking bar viewer children when user wants Blizzard tracked bars
                    if isBarViewer then
                        local pp = ECME.db and ECME.db.profile
                        if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then
                            return
                        end
                    end
                    -- CD/utility viewers: spell set is static (rebuilt only by
                    -- FullCDMRebuild on spec/talent/equip). Pool churn from spell
                    -- transforms (e.g. Monk Empty Barrel -> Keg Smash) re-acquires
                    -- frames but does NOT queue a reanchor, so blanking here leaves
                    -- icons invisible with nothing to restore them. The SetPoint hook
                    -- already handles repositioning for these viewers.
                    if not isBuff then
                        return
                    end
                    if itemIcon then
                        -- Only blank frames we haven't seen before. During
                        -- pool churn (e.g. Lightsmith Holy Armaments transform
                        -- every tick), Blizzard releases and re-acquires ALL
                        -- frames. Blanking already-decorated frames causes
                        -- the entire bar to flicker alpha 0 -> barOpacity
                        -- every cycle. Previously-decorated frames keep their
                        -- current alpha; our SetPoint hook handles positioning.
                        local frameData = hookFrameData[itemIcon]
                        if frameData and frameData.decorated then
                            -- Recycled frame: briefly hide at Blizzard's position
                            -- until CollectAndReanchor repositions it into our bar.
                            -- Without this, the frame flashes at the wrong spot
                            -- for 1 frame before snapping into place.
                            itemIcon:SetAlpha(0)
                            return
                        end
                        itemIcon:SetAlpha(0)
                        if itemIcon.Cooldown and itemIcon.Cooldown.SetDrawSwipe then
                            itemIcon.Cooldown:SetDrawSwipe(false)
                        end
                    end
                end)
            end
        end
    end

    -- 3. Viewer Layout hooks (Essential + Utility only).
    -- Buff viewers are dynamic and positioned per-frame by CollectAndReanchor;
    -- hooking Layout on them causes taint when Blizzard calls it internally.
    local SYNC_VIEWERS = {
        EssentialCooldownViewer = "cooldowns",
        UtilityCooldownViewer = "utility",
    }
    for viewerName, barId in pairs(SYNC_VIEWERS) do
        local viewerFrame = _G[viewerName]
        if viewerFrame then
            -- CD/utility spell sets are rebuilt by FullCDMRebuild, while the
            -- shared restoration queue handles their icons after each layout.
            -- The viewers are Edit Mode systems: pin them through the saved C
            -- methods so Edit Mode's anchor sweep and snap state stay Blizzard's.
            -- The SetPoint hook below watches Blizzard's own writes only.
            -- A pin asked for in combat runs once combat ends (one queued pin
            -- per viewer, however many asks).
            local pinKey = "CDMViewerPin" .. barId
            local function SyncViewerToBar()
                if InCombatLockdown() then
                    mod.CombatQueue.Defer(pinKey, SyncViewerToBar)
                    return
                end
                local boxHolder = cdmBarFrames[barId]
                if not boxHolder then
                    return
                end
                CludesUI.ClearFramePoints(viewerFrame)
                CludesUI.SetFramePoint(viewerFrame, "TOPLEFT", boxHolder, "TOPLEFT", 0, 0)
                CludesUI.SetFramePoint(viewerFrame, "BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", 0, 0)
            end
            -- After a Blizzard SetPoint, a viewer in the bottom managed column
            -- is pinned at once, so the column's next pass measures our bar. A
            -- viewer outside it (moved or snapped in Edit Mode) is pinned once
            -- Blizzard's call has returned: Edit Mode reads the anchor back right
            -- after its own SetPoint (a snap break saves it into the layout) and
            -- must find its own anchor there, never our bar.
            local deferPin
            hooksecurefunc(viewerFrame, "Layout", SyncViewerToBar)
            hooksecurefunc(viewerFrame, "SetPoint", function(_, _, relativeTo)
                if InCombatLockdown() then
                    SyncViewerToBar() -- queues the pin for combat end
                    return
                end
                local boxHolder = cdmBarFrames[barId]
                if relativeTo == boxHolder then
                    return
                end
                local hostFrame = viewerFrame:GetParent()
                if not issecretvalue(hostFrame) and hostFrame == BottomManagedFrameContainer then
                    SyncViewerToBar()
                    return
                end
                if not deferPin then
                    deferPin = mod.TakeShell()
                    deferPin:SetScript("OnUpdate", function(self)
                        self:Hide()
                        SyncViewerToBar()
                    end)
                end
                deferPin:Show()
            end)
            SyncViewerToBar()
        end
    end

    -- 3b. Buff viewer RefreshLayout hooks: IMMEDIATE reanchor so buff
    -- icons appear at our positions instantly (no 0.2s flash). A minimal
    -- time guard collapses the spam when Blizzard rebuilds all pools
    -- every tick (Lightsmith Holy Armaments churn) without adding latency
    -- to real buff procs. 0.05s = one frame at 20 fps.
    local _lastDirectReanchor = 0
    local DIRECT_REANCHOR_GUARD = 0.05
    local function DirectBuffReanchor()
        -- The shared RefreshLayout hook restores anchors before this throttle.
        local nowTime = GetTime()
        if nowTime - _lastDirectReanchor < DIRECT_REANCHOR_GUARD then
            return
        end
        _lastDirectReanchor = nowTime
        CollectAndReanchor()
        if mod.CDM_AntiClipPlaced then
            mod.CDM_AntiClipPlaced()
        end
    end
    local buffIconViewer = _G["BuffIconCooldownViewer"]
    if buffIconViewer and buffIconViewer.RefreshLayout then
        hooksecurefunc(buffIconViewer, "RefreshLayout", DirectBuffReanchor)
    end
    local buffBarsViewer = _G["BuffBarCooldownViewer"]
    if buffBarsViewer and buffBarsViewer.RefreshLayout then
        hooksecurefunc(buffBarsViewer, "RefreshLayout", DirectBuffReanchor)
    end

    -- 4. CooldownViewerSettings show/hide: force reanchor.
    -- When CDM settings panel closes, Blizzard may re-layout its viewers.
    -- Queue a reanchor to re-sync our bar positions.  Also sync extra buff
    -- bars: spells removed from Blizzard CDM no longer produce viewer frames,
    -- so their assignedSpells entries become orphans stuck in the preview.
    if EventRegistry and EventRegistry.RegisterCallback then
        local cdmSettingsOwner = {}
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", QueueReanchor, cdmSettingsOwner)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
            -- In-place edits to the ACTIVE Blizzard layout (spell added to the
            -- layout you are already on) do not change its layout id, so the
            -- spec+layout auto-reseed gate would never re-materialize them.
            -- Wipe the session table here, on panel close (edits happen with the
            -- panel open; the reanchor queued below re-runs the add-only
            -- reseed). NOT on CooldownViewerSettings.OnDataChanged: Blizzard
            -- also fires that from RefreshFromExternalUpdate on SPELLS_CHANGED
            -- / PLAYER_EQUIPMENT_CHANGED / PvP talent updates, which would
            -- re-run a full reseed pass on every form swap or gear change.
            if mod._reseededSpecsSession then
                wipe(mod._reseededSpecsSession)
            end
            C_Timer.After(0.1, QueueReanchor)
            -- Delay sync slightly longer so Blizzard finishes rebuilding pools
            C_Timer.After(0.3, function()
                mod.SyncExtraBuffBarsWithViewer()
            end)
            -- Reconcile keep/drop after Blizzard's layout writes settle and
            -- our own sync/reanchor above have run, so the pass sees the
            -- post-close viewer state rather than a mid-close transient.
            C_Timer.After(0.4, function()
                if mod.RequestCDMDropPass then
                    mod.RequestCDMDropPass("settings")
                end
            end)
        end, cdmSettingsOwner)
    end

    -- 4b. Delayed reanchor on load: catch frames created after initial setup.
    -- Some buff frames (e.g. Dread Plague) may not exist until Blizzard's
    -- viewer finishes its deferred layout pass. Also invalidate TBB cache
    -- so tracking bars re-scan for late-loading BuffBar viewer frames.
    local function DelayedFullRefresh()
        if mod.InvalidateTBBFrameCache then
            mod.InvalidateTBBFrameCache()
        end
        QueueReanchor()
    end
    C_Timer.After(1, DelayedFullRefresh)
    C_Timer.After(3, DelayedFullRefresh)
    C_Timer.After(6, DelayedFullRefresh)

    -- 5. Buff ticker: staleness check + buff/pandemic glow (0.1s)
    do
        local buffTicker = mod.TakeShell()
        local _, _cachedClassToken = UnitClass("player")
        -- 10 Hz anim ticker: the C engine fires the body at cadence and
        -- sleeps between fires, replacing a per-frame OnUpdate whose
        -- accumulator check ran at frame rate (~200x/sec) just to gate this
        -- 10 Hz job -- the dispatch-floor disease the ERB rebuild removed.
        -- Body and cadence unchanged; fn returns true to keep looping.
        local _btBody = function()
            -- Dirty-gated (timed: the full body ran 0.26ms per fire at 10 Hz
            -- = nearly all of CDM's combat CPU). The body runs ONLY when a
            -- dirty edge fired -- player aura/totem flip, viewer pool churn,
            -- pandemic edge, preset-cooldown dirt. There is no staleness
            -- net: after ~1s of settled fires the ticker STOPS ITSELF and
            -- every dirty writer re-arms it via ns.ArmBuffTicker. A stale
            -- glow/desat is a missing edge to register, never to sweep for.
            local _btNow = GetTime()
            -- Park integrity lives on event edges now (ns._parkEdges in the
            -- CUI_CDM_Blizzard.lua + the QueueRepark hooksecurefuncs) -- no patrol here.
            if not mod._btDirty then
                -- Preset cooldowns drain independently on clean fires, capped at 1 Hz:
                -- the dirty flag re-arms ~22x/sec from the racial/ trinket catch-alls,
                -- so an uncapped drain runs at full tick cadence. Casts bypass the cap
                -- (the racial listener's fast lane zeroes ns._pcLast), and swipes are
                -- engine-animated once pushed, so the slow lane is imperceptible.
                local presetDirty = mod._isPresetCdDirty()
                if presetDirty and _btNow - (mod._pcLast or 0) >= 1 then
                    mod._pcLast = _btNow
                    ProcessPresetCooldowns()
                    presetDirty = mod._isPresetCdDirty()
                end
                if presetDirty then
                    mod._btCleanFires = 0
                elseif (mod._btCleanFires or 0) < 10 then
                    mod._btCleanFires = (mod._btCleanFires or 0) + 1
                else
                    -- Settled for ~1s (no dirty edge, presets drained): stop
                    -- the ticker outright. Zero fires until the next edge.
                    mod._btCleanFires = 0
                    return false
                end
                return true
            end
            mod._btCleanFires = 0
            mod._btDirty = nil
            local antiClip = mod.CDM_ANTI_CLIP
            local profile = ECME and ECME.db and ECME.db.profile
            if not profile or not profile.cdmBars or not profile.cdmBars.bars then
                return true
            end
            local needsReanchor = false
            for _, edge in ipairs(profile.cdmBars.bars) do
                if edge.enabled then
                    local isBuff = (
                        edge.barType == "buffs"
                        or edge.key == "buffs"
                        or edge.barType == "custom_buff"
                    )
                    local buffGlowType = isBuff and (edge.buffGlowType or 0) or 0
                    local pandemicOn = edge.pandemicGlow
                    local icons = cdmBarIcons[edge.key]
                    if icons then
                        for fi = 1, #icons do
                            local widget = icons[fi]
                            if widget and widget:IsShown() then
                                local frameCache = _ecmeFC[widget]
                                local spellRef = frameCache and frameCache.resolvedSid
                                local frameData = hookFrameData[widget]
                                -- A buff ICON (whether on a buffs bar, or a real Blizzard
                                -- buff frame hosted on a CD/util bar, or a placeholder for
                                -- an inactive hosted buff) gets the buff glow/desat logic
                                -- below regardless of the hosting bar's family.
                                local isBuffIcon = isBuff
                                    or (frameData and frameData._isBuffViewerFrame)
                                    or widget._isPlaceholderFrame
                                    or false
                                if frameCache and frameCache._missingN then
                                    mod.MissingRecheck(widget, frameCache)
                                end

                                local isActiveBuff = (
                                    widget.wasSetFromAura == true
                                    or widget.auraInstanceID ~= nil
                                )
                                -- Totems and other non-aura buff-viewer items never set
                                -- wasSetFromAura/auraInstanceID even while up, so the aura
                                -- check above misses them. But Blizzard only SHOWS a buff
                                -- frame while it is active (inactive buffs are hidden; our
                                -- Always-Show injects separate _isPlaceholderFrame frames,
                                -- and presets are our own _isCustomBuffFrame frames). We're
                                -- already inside `frame:IsShown()`, so any shown buff-bar
                                -- frame that is NOT a placeholder is active regardless of
                                -- aura props -- this is what catches totems and presets
                                -- (for both the glow and the desaturate-inactive logic).
                                if not isActiveBuff and isBuffIcon and not widget._isPlaceholderFrame then
                                    isActiveBuff = true
                                end

                                -- Desaturate inactive buff icons when Always Show
                                -- Buffs is on and Desaturate Off CD is enabled. When
                                -- Always Show Buffs is off, desaturation is ignored
                                -- (no inactive icons should be visible anyway).
                                -- Placeholder icons (and any inactive buff) are
                                -- greyed when this bar's Always Show Buffs +
                                -- Desaturate Off CD are on. Per-bar now -- not a
                                -- global. Active real auras stay full color.
                                if isBuffIcon and edge.barType ~= "custom_buff" and frameData and frameData.tex then
                                    -- A shown, inactive buff icon is present only because
                                    -- Always Show Buffs resolved true for it (bar-level OR
                                    -- per-icon -> placeholder frame). Per-icon Desaturate
                                    -- Inactive (fd._desatOverride) beats the bar's
                                    -- Desaturate Off CD. Active auras stay full color.
                                    -- A HOSTED buff (on a CD/util bar) has no bar toggle, so
                                    -- it defaults ON (desaturate the inactive placeholder --
                                    -- the baked-in "cd ability" look), with no per-icon row.
                                    local desatOn = (edge.desaturateInactiveBuffs ~= false)
                                    if frameData._desatOverride == "on" then
                                        desatOn = true
                                    elseif frameData._desatOverride == "off" then
                                        desatOn = false
                                    end
                                    if
                                        (edge.showInactiveBuffIcons or widget._isPlaceholderFrame)
                                        and desatOn
                                        and not isActiveBuff
                                    then
                                        frameData.tex:SetDesaturated(true)
                                    elseif frameData.tex:IsDesaturated() then
                                        frameData.tex:SetDesaturated(false)
                                    end
                                end

                                -- Buff glow shows on active buffs. isActiveBuff above
                                -- already counts shown totems and our preset/custom
                                -- own-frames as active, so this just reads it.
                                local buffPresent = isActiveBuff
                                    or (edge.barType == "custom_buff" and widget:IsShown())
                                local glowActive = buffPresent
                                -- Glow When Visible: lit exactly while the icon paints (a Show
                                -- When Missing placeholder, an Always Show icon, a present buff).
                                if frameData and frameData._bgVisible then
                                    glowActive = not (
                                            frameCache and (frameCache._missingActiveHidden or frameCache._cdStateHidden)
                                        )
                                        and not mod.IsPlaceholderRenderHidden(widget, edge)
                                end
                                -- Glow at Stacks REPLACES the presence glow for
                                -- thresholded icons: route to the gate instead.
                                if frameData and frameData._bgThreshold then
                                    glowActive = false
                                    mod.StackGlow_Feed(widget, buffPresent)
                                end
                                -- Effective Buff Glow = per-icon override (fd._bgT,
                                -- stashed by RefreshCDMIconAppearance) falling back to
                                -- the bar's Buff Glow. nil override => inherit; 0 => None.
                                local effGlowType = buffGlowType
                                if frameData and frameData._bgT ~= nil then
                                    effGlowType = frameData._bgT
                                end
                                -- Glow When Visible always needs a style: None / Default use Modern WoW Glow.
                                if effGlowType <= 0 and frameData and frameData._bgVisible then
                                    effGlowType = 6
                                end
                                if effGlowType > 0 and frameData and glowActive then
                                    if not frameData.buffGlowOverlay then
                                        local shade = CreateFrame("Frame", nil, widget)
                                        shade:SetAllPoints(widget)
                                        shade:EnableMouse(false)
                                        frameData.buffGlowOverlay = shade
                                    end
                                    -- Keep the glow above Blizzard's cooldown swipe on
                                    -- every icon. Blizzard increments each viewer icon's
                                    -- base frame level by +1, so an absolute level lands
                                    -- BEHIND the swipe on later icons (and the swipe then
                                    -- clips the inner edge of the ring, making it look
                                    -- thinner). Track the icon's base level and re-apply
                                    -- each pass, matching the primary glowOverlay (+16).
                                    frameData.buffGlowOverlay:SetFrameLevel(widget:GetFrameLevel() + 16)
                                    if not frameData.buffGlowActive then
                                        local cr, cg, callback
                                        if edge.buffGlowMode == "custom" then
                                            cr, cg, callback = edge.buffGlowR, edge.buffGlowG, edge.buffGlowB
                                        end
                                        local classColor = edge.buffGlowMode == "class"
                                        if frameData._bgColor == "class" then
                                            classColor = true
                                        elseif frameData._bgColor == "custom" then
                                            classColor = false
                                            cr, cg, callback = frameData._bgR or cr, frameData._bgG or cg, frameData._bgB or callback
                                        end
                                        if classColor then
                                            local classColor = CludesUI.GetClassColor(CludesUI._playerClass)
                                            cr, cg, callback = classColor.r, classColor.g, classColor.b
                                        end
                                        frameData.buffGlowOverlay:SetAlpha(1)
                                        mod.StartNativeGlow(frameData.buffGlowOverlay, effGlowType, cr, cg, callback, {
                                            N = edge.buffGlowLines or 8,
                                            th = edge.buffGlowThickness or 2,
                                            period = edge.buffGlowSpeed or 4,
                                            bg = edge.buffGlowBackground
                                                    and {
                                                        r = edge.buffGlowBackgroundR or 0,
                                                        g = edge.buffGlowBackgroundG or 0,
                                                        b = edge.buffGlowBackgroundB or 0,
                                                    }
                                                or nil,
                                        })
                                        frameData.buffGlowActive = true
                                    end
                                elseif frameData and frameData.buffGlowActive and frameData.buffGlowOverlay then
                                    mod.StopNativeGlow(frameData.buffGlowOverlay)
                                    frameData.buffGlowActive = false
                                end

                                -- Pandemic glow: Blizzard's ShowPandemicStateFrame hook sets
                                -- _pandemicState (user configures pandemic alerts in Blizzard
                                -- CDM settings). Only the START side is gated on the setting;
                                -- the STOP side below must stay reachable with the setting OFF,
                                -- or a glow already running when the user disables it never
                                -- takes down (stuck lit until the aura lapses, re-lapses, since
                                -- only that finally makes the stop branch reachable). The buff glow directly above already has this shape.
                                local inPandemic = false
                                if frameData and antiClip then
                                    -- WoW Forever: the bar's Pandemic Glow is the anti-clip glow
                                    -- (CUI_CDM_ForeverAntiClip.lua). Vanilla auras carry no time
                                    -- over, so Blizzard opens no pandemic window there; Blizzard
                                    -- Default (-1) and None draw nothing.
                                    if
                                        pandemicOn
                                        and (edge.pandemicGlowStyle or 1) ~= -1
                                        and mod.CDM_AntiClip
                                    then
                                        inPandemic = mod.CDM_AntiClip(widget, true)
                                    end
                                elseif frameData then
                                    -- Blizzard Default (-1) is the ONLY config that
                                    -- needs no hook: Blizzard's native PandemicIcon
                                    -- does the whole job, so that config still costs
                                    -- zero. EVERY other config needs the hook --
                                    -- custom styles (>0) to REPLACE the icon, and
                                    -- None (pandemicGlow off) to SUPPRESS it.
                                    --
                                    -- Installing was gated on `pandemicOn`, so None got no
                                    -- hook at all and _PandemicShow (which hides Blizzard's
                                    -- icon) never ran, letting Blizzard's PandemicIcon render
                                    -- unopposed with no way to turn the option off -- same shape
                                    -- as the stop-branch bug: code that acts when a setting is
                                    -- OFF must not sit behind a gate requiring it ON. For custom
                                    -- styles the hooks still install lazily HERE on first need;
                                    -- this tick runs on a CDM shell, so install-time work bills
                                    -- CooldownManager too. nil is NOT the same as false here: a
                                    -- never-configured bar has pandemicGlow == nil and must keep
                                    -- behaving as Blizzard Default (the three built-in bars never
                                    -- seed the key, while every seeding template ships true +
                                    -- style -1) -- only an EXPLICIT false (user picks None)
                                    -- suppresses, so this fix can't silently strip the pandemic icon from anyone who never touched it.
                                    local pStyle = edge.pandemicGlowStyle or 1
                                    local custom = pandemicOn and pStyle ~= -1
                                    local isNone = (edge.pandemicGlow == false)
                                    if custom or isNone then
                                        if
                                            mod._pandemicHooked
                                            and not mod._pandemicHooked[widget]
                                            and mod.HookPandemicState
                                        then
                                            mod.HookPandemicState(widget)
                                        end
                                    end
                                    if custom then
                                        -- Not while the flag is describing an aura
                                        -- that already ended (ns._PandemicIconHide).
                                        inPandemic = not frameData._panStale
                                            and mod._pandemicState
                                            and mod._pandemicState[widget]
                                    elseif isNone then
                                        -- The hook only fires on the NEXT
                                        -- ShowPandemicStateFrame, so an icon already
                                        -- lit when the user picked None would stay up
                                        -- until the aura lapsed. Take it down here
                                        -- too; Hide is idempotent and this only runs
                                        -- for bars actually set to None.
                                        local pi = widget.PandemicIcon
                                        if pi and pi:IsShown() then
                                            pi:Hide()
                                        end
                                    end
                                end
                                if inPandemic and frameData then
                                    if not frameData.pandemicOverlay then
                                        local shade = CreateFrame("Frame", nil, widget)
                                        shade:SetAllPoints(widget)
                                        shade:EnableMouse(false)
                                        frameData.pandemicOverlay = shade
                                        -- Once per frame, and only for icons that
                                        -- actually glow: the stop edge the tick
                                        -- cannot see, and the window edge that
                                        -- says the flag is current again (see
                                        -- ns._PandemicIconHide).
                                        widget:HookScript("OnHide", mod._PandemicIconHide)
                                        if widget.SetPandemicAlertTriggerTime then
                                            hooksecurefunc(
                                                widget,
                                                "SetPandemicAlertTriggerTime",
                                                mod._PandemicWindowSet
                                            )
                                        end
                                    end
                                    -- Same base-level tracking as the buff glow, one
                                    -- level higher so pandemic sits above buff glow.
                                    frameData.pandemicOverlay:SetFrameLevel(widget:GetFrameLevel() + 17)
                                    if not frameData.pandemicGlowActive then
                                        local c
                                        if edge.pandemicGlowMode == "class" then
                                            c = CludesUI.GetClassColor(CludesUI._playerClass)
                                        elseif edge.pandemicGlowMode == "custom" then
                                            c = edge.pandemicGlowColor
                                        end
                                        local style = edge.pandemicGlowStyle or 1
                                        local glowOpts = (style == 1)
                                                and {
                                                    N = edge.pandemicGlowLines or 8,
                                                    th = edge.pandemicGlowThickness or 2,
                                                    period = edge.pandemicGlowSpeed or 4,
                                                    bg = edge.pandemicGlowBackground
                                                            and {
                                                                r = (
                                                                    edge.pandemicGlowBackgroundColor
                                                                    and edge.pandemicGlowBackgroundColor.r
                                                                )
                                                                    or 0,
                                                                g = (
                                                                    edge.pandemicGlowBackgroundColor
                                                                    and edge.pandemicGlowBackgroundColor.g
                                                                )
                                                                    or 0,
                                                                b = (
                                                                    edge.pandemicGlowBackgroundColor
                                                                    and edge.pandemicGlowBackgroundColor.b
                                                                )
                                                                    or 0,
                                                            }
                                                        or nil,
                                                }
                                            or nil
                                        frameData.pandemicOverlay:SetAlpha(1)
                                        mod.StartNativeGlow(
                                            frameData.pandemicOverlay,
                                            style,
                                            c and c.r,
                                            c and c.g,
                                            c and c.b,
                                            glowOpts
                                        )
                                        frameData.pandemicGlowActive = true
                                    end
                                elseif frameData and frameData.pandemicGlowActive and frameData.pandemicOverlay then
                                    mod.StopNativeGlow(frameData.pandemicOverlay)
                                    frameData.pandemicGlowActive = false
                                end

                                -- Active State Glow integrity, BOTH edges. The glow is
                                -- normally driven as a side effect of Blizzard calling
                                -- Cooldown:SetSwipeColor, and Blizzard skips that call
                                -- on either aura edge (a DoT expiring naturally pushes
                                -- no swipe until the next GCD; an aura landing outside
                                -- a cooldown refresh pushes none at all). The rise edge
                                -- additionally breaks when another owner of the shared
                                -- glowOverlay -- the CD-state glow or proc glow --
                                -- stops the texture without clearing fd._activeGlowOn:
                                -- the hook's idempotence check then believes the glow
                                -- is still running and never restarts it, leaving the
                                -- icon dark for the rest of the session. Re-assert from
                                -- the same swipe colour the hook reads so both edges
                                -- self-heal within a tick.
                                if
                                    frameData
                                    and not frameData._isBuffViewerFrame
                                    and (frameData._activeGlowOn or mod._cdmAnyActiveGlow)
                                then
                                    local swipeColor = widget.cooldownSwipeColor
                                    local region
                                    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                                        region = swipeColor:GetRGBA()
                                        -- Secret or unavailable reads as "no
                                        -- data" -- neither edge acts on it.
                                        if type(region) ~= "number" or issecretvalue(region) then
                                            region = nil
                                        end
                                    end
                                    if region == 0 then
                                        -- Clean 0: not active. Clear a glow we own.
                                        -- Also re-arm the no-config latch below so
                                        -- the next activation re-checks settings.
                                        frameData._activeGlowNoCfg = nil
                                        if frameData._activeGlowOn then
                                            if frameData.glowOverlay then
                                                mod.StopNativeGlow(frameData.glowOverlay)
                                            end
                                            frameData._activeGlowOn = false
                                            -- The falling edge Blizzard pushed no
                                            -- swipe for: light an owed CD-state
                                            -- glow now (see ApplyActiveOverlays).
                                            if frameData._cdGlowOwed then
                                                mod.CdGlowKick(widget)
                                            end
                                        end
                                    elseif
                                        region
                                        and mod._cdmAnyActiveGlow
                                        and not frameData._activeGlowNoCfg
                                        and not (
                                            frameData._activeGlowOn
                                            and frameData.glowOverlay
                                            and frameData.glowOverlay._glowActive
                                        )
                                    then
                                        -- Active, but no glow is actually running
                                        -- on the overlay. Drop any orphaned flag
                                        -- so ApplyActiveOverlays really restarts,
                                        -- then let it re-resolve style + colour.
                                        frameData._activeGlowOn = false
                                        local ssA = mod._ResolveCdmSS(widget)
                                        if ssA and (tonumber(ssA.activeGlow) or 0) > 0 then
                                            mod.ApplyActiveOverlays(widget, frameData, ssA, true, edge)
                                        else
                                            -- No active glow configured for THIS
                                            -- icon, so the resolve can only answer
                                            -- "no" again for the rest of this
                                            -- active window. Latch it off.
                                            --
                                            -- ns._cdmAnyActiveGlow is a GLOBAL gate
                                            -- -- one spell anywhere with a glow arms
                                            -- it for every frame -- so without this
                                            -- every active icon in the profile pays a
                                            -- full settings resolve on every pass
                                            -- purely to rediscover it has nothing to
                                            -- do. Icons that DO have a glow never reach
                                            -- here, so the repair this pass exists for
                                            -- is untouched. Re-armed on the falloff
                                            -- edge above and by DecorateFrame, so a
                                            -- newly enabled glow is picked up without
                                            -- waiting for the aura to drop.
                                            frameData._activeGlowNoCfg = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if needsReanchor then
                QueueReanchor()
            end
            -- Refresh aura active cache. This is the sole maintainer of _activeCache;
            -- bar glow overlays read from ns._tickBlizzActiveCache. Walk the live
            -- pools and mark any frame whose Blizzard-set
            -- wasSetFromAura/auraInstanceID indicates an active aura. Calls
            -- ResolveFrameSpellID (which has its own resolve cache) so
            -- BuffBarCooldownViewer frames -- which CollectAndReanchor never visits --
            -- still get their fc populated for bar glow triggers on Tracked Bar spells
            -- (Divine Protection etc). Pool-generation gate: aura ticks dirty the BODY
            -- but do not reshuffle viewer pools, so the four-pool enumeration below
            -- only reruns after actual pool churn (Acquire/Release/OnCooldownIDSet
            -- bump the generation) or on a 1s staleness net.
            if mod._acGen ~= mod._acSeenGen or _btNow - (mod._acLastFull or 0) >= 1 then
                mod._acSeenGen = mod._acGen
                mod._acLastFull = _btNow
                do
                    local ac = _activeCache
                    local asc = _activeStacksCache
                    wipe(ac)
                    wipe(asc)
                    for viewerIndex = 1, 4 do
                        local viewerRef = GetViewerFrame(viewerIndex)
                        -- BuffIcon (3) / BuffBar (4) viewers SHOW a frame only while its
                        -- buff/effect is active; the cooldown viewers (1,2) always show
                        -- their icons, so "shown" is meaningless there. So in the buff
                        -- viewers a shown, non-placeholder frame counts as active even
                        -- without aura props -- this catches totems and pet-summon
                        -- "buffs" (e.g. Mindbender) that Blizzard never gives an
                        -- auraInstanceID. Mirrors the buff-bar glow logic in BuffTicker.
                        local isBuffViewer = (viewerIndex >= 3)
                        if viewerRef and viewerRef.itemFramePool and viewerRef.itemFramePool.EnumerateActive then
                            for widget in viewerRef.itemFramePool:EnumerateActive() do
                                local isActive = widget.wasSetFromAura == true or widget.auraInstanceID ~= nil
                                if
                                    not isActive
                                    and isBuffViewer
                                    and widget:IsShown()
                                    and not widget._isPlaceholderFrame
                                then
                                    isActive = true
                                end
                                if isActive then
                                    local spellRef, baseSID = ResolveFrameSpellID(widget)
                                    if spellRef and spellRef > 0 then
                                        ac[spellRef] = true
                                        local hasBase = baseSID and baseSID > 0
                                        if hasBase then
                                            ac[baseSID] = true
                                        end
                                        local frameCache = _ecmeFC[widget]
                                        local isLinked = frameCache and frameCache.linkedSpellIDs
                                        if isLinked then
                                            for layoutIndex = 1, #isLinked do
                                                local lsid = isLinked[layoutIndex]
                                                if lsid and lsid > 0 then
                                                    ac[lsid] = true
                                                end
                                            end
                                        end
                                        -- Stack counts for Bar Glows' At Stacks gate: read
                                        -- ONLY for frames a gated entry names by sid, base
                                        -- or linked id (ns._barGlowStackSids, maintained by
                                        -- CdmBarGlows.lua's SetupOverlays; nil with no gated
                                        -- entry). The live read allocates a data table per
                                        -- call, so it never runs for unrelated frames.
                                        local sids = mod._barGlowStackSids
                                        if sids then
                                            local wanted = sids[spellRef] or (hasBase and sids[baseSID])
                                            if not wanted and isLinked then
                                                for layoutIndex = 1, #isLinked do
                                                    local lsid = isLinked[layoutIndex]
                                                    if lsid and sids[lsid] then
                                                        wanted = true
                                                        break
                                                    end
                                                end
                                            end
                                            if wanted and mod._ReadBuffApplications then
                                                local apps = mod._ReadBuffApplications(widget)
                                                -- Secret probe FIRST: a nil test on a secret
                                                -- value hard-errors.
                                                if (issecretvalue and issecretvalue(apps)) or apps ~= nil then
                                                    asc[spellRef] = apps
                                                    if hasBase then
                                                        asc[baseSID] = apps
                                                    end
                                                    if isLinked then
                                                        for layoutIndex = 1, #isLinked do
                                                            local lsid = isLinked[layoutIndex]
                                                            if lsid and lsid > 0 then
                                                                asc[lsid] = apps
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if mod.UpdateOverlayVisuals then
                        mod.UpdateOverlayVisuals()
                    end
                end
            end -- pool-generation gate
            -- Process preset cooldowns (trinkets/items/racials) if any event
            -- dirtied the flag since the last tick. Coalesces dozens of per-GCD
            -- SPELL_UPDATE_COOLDOWN events into a single 10Hz update pass.
            if mod._isPresetCdDirty and mod._isPresetCdDirty() and _btNow - (mod._pcLast or 0) >= 1 then
                -- Same 1 Hz slow lane as the clean-fire drain (casts reset
                -- the cap in the racial listener's fast lane).
                mod._pcLast = _btNow
                mod._ProcessPresetCooldowns()
            end
            return true
        end
        -- Dirty sources with dedicated events: aura and totem flips change buff/glow
        -- state without pool churn. Frame is CDM-born, so the handler bills
        -- CooldownManager. Aura REMOVALS also release buff-viewer pool frames with no
        -- Acquire, so they bump the pool generation (the precise fade signal) with no
        -- Release hook -- a Release hook was tried and reverted: its closures were born
        -- under parent dispatch, billing the parent per fade, and mass release/reacquire
        -- churn re-armed the rebuild every tick. The ticker is created LAZILY on the
        -- first event ON PURPOSE: the animation group (OnLoop entry object) bills the
        -- addon whose execution context CREATED it, and this setup function runs under
        -- the parent's lifecycle dispatch, so creating it here would bill the entire
        -- 10Hz body to the PARENT. The first event on this CDM-born frame is a
        -- CooldownManager context, so the group is born correctly billed.
        local _btTicker
        buffTicker:RegisterUnitEvent("UNIT_AURA", "player")
        -- Target auras: a Bar Glow on a tracked TARGET debuff (e.g. Freezing) changes
        -- with no player aura edge, so with a player-only listener its glow waited
        -- for some unrelated player aura (or a target swap) -- seconds late. The
        -- target unit is added only while a Bar Glow tracks a non-self aura (Bar
        -- Glows' SetupOverlays calls this with its want, remembered in
        -- ns._bgWantTargetAuras in case it runs before this block), so glows on
        -- your own buffs never pay for target (raid boss) aura churn.
        mod.SetBarGlowTargetAuras = function(wanted)
            wanted = wanted and true or false
            if wanted == mod._bgTargetAuras then
                return
            end
            mod._bgTargetAuras = wanted
            if wanted then
                buffTicker:RegisterUnitEvent("UNIT_AURA", "player", "target")
            else
                buffTicker:RegisterUnitEvent("UNIT_AURA", "player")
            end
        end
        mod.SetBarGlowTargetAuras(mod._bgWantTargetAuras)
        buffTicker:RegisterEvent("PLAYER_TOTEM_UPDATE")
        buffTicker:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Target-applied auras bind and release on this edge and on no player-scoped
        -- one, so without it a tracked debuff's glow could only be picked up by the
        -- 1s staleness net below, or not at all once the ticker had settled.
        buffTicker:RegisterEvent("PLAYER_TARGET_CHANGED")
        buffTicker:SetScript("OnEvent", function(_, evt, _, updateInfo)
            mod._btDirty = true
            -- Gen bump on anything that can CHANGE which auras are active: additions
            -- (a glow must LIGHT), plus anything that can release a pool frame --
            -- removals/full updates, totem drops/despawns, world entry. Additions
            -- matter because a spell tracked in a COOLDOWN viewer keeps its frame
            -- acquired permanently, so Blizzard merely sets wasSetFromAura/
            -- auraInstanceID on the frame that's already there -- no Acquire, no
            -- generation bump, so lighting a Bar Glow (e.g. Killing Machine ->
            -- Obliterate) would fall through to the 1s staleness net below, up to a
            -- second late and missed entirely if the proc was consumed inside that
            -- window. Only UNIT_AURA carries an updateInfo table in this slot --
            -- PLAYER_ENTERING_WORLD's second arg is the isReconnect BOOLEAN (true on
            -- /reload), so the payload must never be indexed for the other events.
            if evt ~= "UNIT_AURA" then
                mod._acGen = (mod._acGen or 0) + 1
            elseif updateInfo then
                -- SECRET-SAFE: the payload TABLE and each of its fields can all arrive
                -- secret in instanced content, and a secret can never be boolean-tested
                -- in Lua (a hard error, not a falsy read). So: guard the table before
                -- indexing it, bind fields to locals (reading a secret is always
                -- legal), then issecretvalue-gate every test. When unreadable, assume
                -- churn -- one extra pool rebuild costs far less than a cache still
                -- holding released frames. Same guard shape as the lust listener in CUI_CDM_BuffBarPresets.lua.
                if issecretvalue(updateInfo) then
                    mod._acGen = (mod._acGen or 0) + 1
                else
                    local full = updateInfo.isFullUpdate
                    local removed = updateInfo.removedAuraInstanceIDs
                    local added = updateInfo.addedAuras
                    -- A stack change arrives as an UPDATE (no add/remove), so a
                    -- stack-gated Bar Glow's count stayed stale until some other
                    -- edge. Read only while a stack-gated glow exists (nil otherwise).
                    local updated = mod._barGlowStackSids and updateInfo.updatedAuraInstanceIDs
                    if
                        issecretvalue(full)
                        or issecretvalue(removed)
                        or issecretvalue(added)
                        or issecretvalue(updated)
                        or full
                        or removed
                        or added
                        or updated
                    then
                        mod._acGen = (mod._acGen or 0) + 1
                    end
                end
            end
            if not _btTicker then
                _btTicker = CludesUI.Tick.NewAnimTicker(buffTicker, _btBody, 0.1)
            end
            _btTicker.Start()
        end)
        -- Re-arm for every dirty writer. The body self-stops when settled; Start() on a
        -- playing ticker is one IsPlaying check, so arming stays indiscriminate.
        -- Creation is EXCLUSIVELY the OnEvent above's job (guaranteed CDM execution
        -- context -- see the attribution note), so a pre-first-event arm is a no-op;
        -- PLAYER_ENTERING_WORLD always creates it at login.
        mod.ArmBuffTicker = function()
            if _btTicker then
                _btTicker.Start()
            end
        end
    end

    -- CDM settings panel: reanchor when user finishes editing
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, QueueReanchor)
        end)
    end

    -- CUI options panel: reanchor on show/hide
    CludesUI:RegisterOnShow(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)
    CludesUI:RegisterOnHide(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)

    -- Edit Mode close: full rebuild to restore CDM after Blizzard repositioned viewers.
    -- FullCDMRebuild is combat-safe (only touches our own frames).
    do
        local emf = _G.EditModeManagerFrame
        if emf then
            hooksecurefunc(emf, "Hide", function()
                C_Timer.After(0.1, function()
                    if mod.FullCDMRebuild then
                        mod.FullCDMRebuild("editmode_close")
                    end
                end)
            end)
        end
    end

    -- Listen for EditMode layout updates: Blizzard resets viewer frame
    -- pools when applying a layout (happens on spec swap). Reanchor to
    -- recollect the new frames. No flag manipulation -- just reanchor.
    do
        local emEventFrame = mod.TakeShell()
        emEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        emEventFrame:SetScript("OnEvent", function()
            QueueReanchor()
        end)
    end

    -- Lock EditMode for CDM frames (prevent user changes, avoid taint)
    mod.SetupEditModeLock()

    -- Initial reanchor
    C_Timer.After(0.2, function()
        QueueReanchor()
        UpdateCustomBuffBars()
    end)
end

function mod.IsViewerHooked()
    return viewerHooksInstalled
end

-------------------------------------------------------------------------------
--  EditMode Lock
--  Prevents users from changing CDM viewer settings via EditMode.
--  Hides the settings dialog, disables dragging, shows a lock notice.
-------------------------------------------------------------------------------
local _editModeLockInstalled = false
local _editModeLockNoticeShown = false

local function IsCooldownViewerSystemFrame(widget)
    local cooldownSystem = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    return cooldownSystem and widget and widget.system == cooldownSystem
end

-- Skip locking the BuffBarCooldownViewer when the user has enabled "Use Blizzard CDM
-- Bars" -- they want to drag/configure that frame in Edit Mode themselves. All other
-- CDM viewers stay locked because CUI manages their position via icon-level anchoring.
local function ShouldLockViewer(widget)
    if widget == _G["BuffBarCooldownViewer"] then
        local profile = ECME and ECME.db and ECME.db.profile
        if profile and profile.cdmBars and profile.cdmBars.useBlizzardBuffBars then
            return false
        end
    end
    return true
end

local function ShowEditModeLockNotice()
    if not _editModeLockNoticeShown then
        CludesUI.Print(
            CludesUI.L(
                "|cff4cc9f0CludesUI CDM:|r Cooldown Viewer settings are managed by CludesUI. Edit Mode changes are disabled."
            )
        )
        _editModeLockNoticeShown = true
    end
end

local function LockCooldownViewerFrames()
    for _, vName in ipairs(VIEWER_NAMES) do
        local widget = _G[vName]
        if IsCooldownViewerSystemFrame(widget) and ShouldLockViewer(widget) then
            widget:SetMovable(false)
            -- No drag button on the selection box: a drag never starts there, so
            -- Edit Mode's own OnDragStart / OnDragStop (left in place) never run.
            local selection = widget.Selection
            if selection then
                selection:RegisterForDrag()
            end
        end
    end
end

function mod.SetupEditModeLock()
    if _editModeLockInstalled then
        return
    end

    local function TrySetup()
        local dialogFrame = _G.EditModeSystemSettingsDialog
        if not (dialogFrame and Enum and Enum.EditModeSystem) then
            return false
        end

        -- When EditMode tries to show the settings dialog for a CDM frame, hide it
        hooksecurefunc(dialogFrame, "AttachToSystemFrame", function(dlg, systemFrame)
            if not IsCooldownViewerSystemFrame(systemFrame) then
                return
            end
            if not ShouldLockViewer(systemFrame) then
                return
            end
            dlg:Hide()
            ShowEditModeLockNotice()
        end)

        -- When a CDM frame is selected in EditMode, lock it
        for _, vName in ipairs(VIEWER_NAMES) do
            local widget = _G[vName]
            if IsCooldownViewerSystemFrame(widget) then
                hooksecurefunc(widget, "SelectSystem", function(scrollFrame)
                    if not ShouldLockViewer(scrollFrame) then
                        return
                    end
                    scrollFrame:SetMovable(false)
                    if dialogFrame.attachedToSystem == scrollFrame then
                        dialogFrame:Hide()
                    end
                    ShowEditModeLockNotice()
                end)
            end
        end

        _editModeLockInstalled = true
        LockCooldownViewerFrames()
        return true
    end

    if not TrySetup() then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function()
            TrySetup()
        end)
    end
end

-- Swiftmend Brightness Fix (CDM): hooks install via TryHookSwiftmend during
-- DecorateFrame. The scan hook only re-brightens already-hooked icons so the
-- General Settings toggle takes effect immediately when switched on (the
-- SetVertexColor hook reads the toggle live for everything after that).
_G._CUCDM_ScanSwiftmend = function()
    if not SwiftmendEnabled() then
        return
    end
    for index = 1, #_smHookedIcons do
        _smHookedIcons[index]:SetVertexColor(1, 1, 1)
    end
end

Inner.broken = false
