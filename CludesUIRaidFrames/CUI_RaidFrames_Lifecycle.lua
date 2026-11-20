if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Lifecycle.lua
--
--  OnInitialize, OnEnable and the Party Mode spin.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local allButtons, defaultSet, ERF, eventFrame = Inner.allButtons, Inner.defaults, Inner.ERF, Inner.eventFrame
local InitHealthBarTextures, IsPowerBarEnabled = Inner.InitHealthBarTextures, Inner.IsPowerBarEnabled
local PixelSnap, separatedHdrs, unitTrackers = Inner.PixelSnap, Inner.separatedHdrs, Inner.unitTrackers
local StyleButton, RebuildUnitMap = Inner.StyleButton, Inner.RebuildUnitMap
local UpdateAllButtons, CreateHeaders = Inner.UpdateAllButtons, Inner.CreateHeaders
local LayoutGroups, ReloadFrames = Inner.LayoutGroups, Inner.ReloadFrames
local UpdateVisibility, OnEvent = Inner.UpdateVisibility, Inner.OnEvent
local RegisterWithUnlockMode, SetDB, SetPP = Inner.RegisterWithUnlockMode, Inner.SetDB, Inner.SetPP
local SetInCombat = Inner.SetInCombat

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val)
    containerFrame = val
end
local framesVisible = false
Inner.framesVisibleSetters[#Inner.framesVisibleSetters + 1] = function(val)
    framesVisible = val
end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (ADDON_LOADED - SavedVariables available)
-------------------------------------------------------------------------------
function ERF:OnInitialize()
    -- Detect first install before DB creation overwrites the raw SV
    local rawDB = CludesUIRaidFramesDB
    local isFirstInstall = not rawDB or not rawDB.profiles or (rawDB.profiles and not next(rawDB.profiles))

    self.db = CludesUI.Lite.NewDB("CludesUIRaidFramesDB", defaultSet, true)
    SetDB(self.db)
    mod.db = saved

    -- Migration: the legacy "Threat Borders" toggle (showThreat) became the
    -- "threatBorderSize" slider. Preserve intent for users who turned it off
    -- (false -> 0); everyone else falls through to the default size. Run for
    -- every saved profile so switching profiles mid-session keeps the choice.
    if CludesUIDB and CludesUIDB.profiles then
        for _, pdata in pairs(CludesUIDB.profiles) do
            local popFrame = pdata.addons and pdata.addons.CludesUIRaidFrames
            if popFrame then
                if popFrame.showThreat ~= nil then
                    if popFrame.showThreat == false then
                        popFrame.threatBorderSize = 0
                    end
                    popFrame.showThreat = nil
                end
                if popFrame.party_showThreat ~= nil then
                    if popFrame.party_showThreat == false then
                        popFrame.party_threatBorderSize = 0
                    end
                    popFrame.party_showThreat = nil
                end
            end
        end
    end

    -- Mark if we need to snapshot Blizzard's raid frame position
    local savedVars = self.db.sv
    self._needsCapture = not savedVars._capturedOnce_RF

    InitHealthBarTextures()
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (PLAYER_LOGIN - game data available)
-------------------------------------------------------------------------------
function ERF:OnEnable()
    SetPP(CludesUI.PanelPP or CludesUI.PP)

    -- First-install default position: left edge of frame at 200px from screen
    -- left, vertically centered.
    if self._needsCapture then
        saved.profile.unlockPos = {
            point = "LEFT",
            relPoint = "LEFT",
            x = 200,
            y = 0,
        }
        if not saved.profile.partyUnlockPos then
            saved.profile.partyUnlockPos = {
                point = "LEFT",
                relPoint = "LEFT",
                x = 400,
                y = 0,
            }
        end
        self.db.sv._capturedOnce_RF = true
        self._needsCapture = false
    end

    -- Stock styles: a profile that arrives already switched (an import, an
    -- older build) gets the style's first-visit defaults once, before the
    -- proxies below materialize them.
    if mod.RF_Stock() then
        mod.RF_SeedStock(saved.profile, mod.RF_Style())
    end
    mod.RF_MigrateSmRaidBar(saved.profile)
    mod._FrameSortRegister()

    -- Inherit the Absorbs section's party-sync state from Health Bar for
    -- profiles saved before the section split (must precede any proxy reads).
    mod._NormalizePartySyncSections()

    -- Rebase pre-top-left-anchor tier offsets (marker travels in the data)
    mod._NormalizeTierOffsetAnchors()

    -- Initialize click-cast engine (before CreateHeaders so ClickCastFrames hook is active)
    if mod.CC_Init then
        mod.CC_Init()
    end

    -- Set party strata before creating its secure header.
    if mod.ApplyFrameStrata then
        mod.ApplyFrameStrata()
    end

    -- Create headers; buttons get window-phase secure styling only
    CreateHeaders()

    -- Initial reload minus the restyle loop (sets _activeSizeW/H from group
    -- size + tier overrides, lays out headers) -- the insecure styling bodies
    -- run in the deferred pass below
    ReloadFrames(true)

    -- Create party header (after CC_Init so click-cast registers)
    mod._CreatePartyHeader()

    -- Both containers show and hide through their visibility drivers from here
    -- on, registered in the login window so a /reload in combat has them too.
    -- Blizzard's PartyFrame goes down here too, so it can never stand in for
    -- ours (a group joined in combat).
    mod._RFSyncVisDrivers()
    mod._SuppressBlizzParty(true)

    -- Size + position party container from profile
    do
        local cfg = saved.profile
        local pw, ph, pcs = mod.RF_PartyDims(cfg)
        mod._SizePartyContainer(
            PixelSnap(pw),
            PixelSnap(ph),
            PixelSnap(pcs) + mod.PT_AlongPitch(cfg),
            mod._PartyGrowth(cfg)
        )
        local place = cfg.partyUnlockPos
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = CludesUI.IsUnlockAnchored
            and CludesUI.IsUnlockAnchored("RF_PartyFrames")
            and mod._partyContainerFrame:GetLeft()
        if place and not anchored then
            mod._partyContainerFrame:ClearAllPoints()
            mod._partyContainerFrame:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
        end
    end

    -- Party layout minus the restyle loop (bodies deferred)
    mod.ReloadPartyFrames(true)

    -- Friendly Boss Frames: initial activation (raid-only boss1-5 frames)
    if mod.FB_Apply then
        mod.FB_Apply()
    end
    -- Extra Frames: initial activation (raid-only member duplicates)
    if mod.XF_Apply then
        mod.XF_Apply()
    end
    -- Pet frames: built and styled here, once (in the login window, so a combat /reload has them);
    -- the deferred reloads below find their style unchanged.
    mod.PF_Apply(true)

    -- DEFERRED LOGIN PASS, BUDGET-FRAGMENTED. Starts on the first frame
    -- after the loading screen (timers never fire during it). Everything
    -- here is combat-legal: the insecure styling bodies for every
    -- pre-spawned button (~80% of this module's login CPU), then the full
    -- reload passes, whose protected ops self-gate in combat and heal on the
    -- regen dirty-flag path. Order is load-bearing and preserved by C_Timer
    -- FIFO: BM lookup before the bodies (aura shell pools size from the
    -- indicator lists), bodies before the restyle loops.
    --
    -- WHY FRAGMENTED: each C_Timer callback is its own execution and so its
    -- own 12.1 script-watchdog budget -- but a budget is a fixed slice, and
    -- this pass's cost scales with button count x profile size. As ONE tick
    -- it exceeded its own budget on slower machines (field: watchdog kill
    -- inside _RefreshProxyModes at the TAIL of the tick -- the named line is
    -- just where the budget died, not the culprit). Now the styling loop
    -- self-limits with debugprofilestop and re-queues, and each reload pass
    -- runs as its own execution, so no single execution here scales with
    -- data size. Fast machines still finish styling in one tick; slow ones
    -- style progressively over a few frames instead of erroring. Buttons
    -- created between slices (roster spawns) are healed by the restyle-loop
    -- fallbacks and the 0.5s safety pass, same as the existing one-tick gap;
    -- UpdateButton's `not d.styled` guard covers event dispatch in the gap.
    C_Timer.After(0, function()
        -- Invalidate the frame's paint stamps so the deferred repaint can
        -- never be deduped away (mirrors _CURF_RefreshAll). Re-bumped in each
        -- later stage: every stage is a new frame with its own stamps.
        mod._paintGen = (mod._paintGen or 0) + 1
        if mod.BM_RebuildLookup then
            mod.BM_RebuildLookup(saved)
        end
        local queue = {}
        for _, button in ipairs(allButtons) do
            queue[#queue + 1] = button
        end
        for _, button in ipairs(mod._partyAllButtons) do
            queue[#queue + 1] = button
        end
        local position = 1
        local function drain()
            local deadline = debugprofilestop() + 8
            while position <= #queue do
                StyleButton(queue[position])
                position = position + 1
                if position <= #queue and debugprofilestop() > deadline then
                    C_Timer.After(0, drain)
                    return
                end
            end
            -- Styling complete: each remaining pass gets a whole budget.
            C_Timer.After(0, function()
                mod._paintGen = (mod._paintGen or 0) + 1
                ReloadFrames()
            end)
            C_Timer.After(0, function()
                mod._paintGen = (mod._paintGen or 0) + 1
                mod.ReloadPartyFrames()
            end)
            C_Timer.After(0, RegisterWithUnlockMode)
        end
        drain()
    end)

    -- Party container size + saved position. The container is implicitly
    -- protected (the secure party header is parented to it), so under combat
    -- lockdown the write is deferred to the PLAYER_REGEN_ENABLED flush instead
    -- of tripping ADDON_ACTION_BLOCKED: _CURF_RefreshAll is a public entry point
    -- (profiles, spec overrides, third-party installers) and not every caller
    -- is out of combat.
    function mod._ApplyPartyContainerGeometry()
        local c = mod._partyContainerFrame
        if not c or not mod.db then
            return
        end
        if InCombatLockdown() then
            mod._partyGeomDirtyInCombat = true
            return
        end
        local cfg = mod.db.profile
        local pw, ph, pcs = mod.RF_PartyDims(cfg)
        mod._SizePartyContainer(
            PixelSnap(pw),
            PixelSnap(ph),
            PixelSnap(pcs) + mod.PT_AlongPitch(cfg),
            mod._PartyGrowth(cfg)
        )
        local place = cfg.partyUnlockPos
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = CludesUI.IsUnlockAnchored
            and CludesUI.IsUnlockAnchored("RF_PartyFrames")
            and c:GetLeft()
        if place and not anchored then
            c:ClearAllPoints()
            c:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
        end
    end

    -- Profile-swap refresh: CludesUI.RefreshAllAddons calls this on a profile
    -- change so raid + party frames re-read the (now-swapped) profile live,
    -- instead of staying stale until /reload. Mirrors the reload sequence above.
    _G._CURF_RefreshAll = function()
        if not mod.db then
            return
        end
        -- Profile/view swaps break the same-frame paint-stamp window: the
        -- repaint of the new profile must never dedupe against a paint made
        -- under the old one earlier this frame.
        mod._paintGen = (mod._paintGen or 0) + 1
        -- Absorbs sync-state inheritance for swapped/imported profiles saved
        -- before the Absorbs section split (must precede party proxy reads).
        mod._NormalizePartySyncSections()
        -- Rebase old-scheme tier offsets on swapped/imported profiles too
        -- (the marker lives inside raidSizeOverrides, so this self-detects).
        mod._NormalizeTierOffsetAnchors()
        -- Rebuild the buff-manager spell lookup for the new profile's per-spec
        -- indicators (and the Simple Setup whitelist) before frames re-render.
        if mod.BM_RebuildLookup then
            mod.BM_RebuildLookup(mod.db)
        end
        -- Apply strata first; reload restores child frame levels.
        if mod.ApplyFrameStrata then
            mod.ApplyFrameStrata()
        end
        -- Raid frames: restyle + relayout + reposition from the new profile.
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
        -- Party container size + position (combat-deferred inside), then the party buttons.
        mod._ApplyPartyContainerGeometry()
        if mod.ReloadPartyFrames then
            mod.ReloadPartyFrames()
        end
        -- Re-sync per-unit UNIT_POWER_UPDATE registration to the new profile's
        -- power role filters, so units that GAIN power across the swap get live
        -- updates instead of a frozen one-shot snapshot (rage/runic power would
        -- otherwise sit empty out of combat). Event registration is combat-safe.
        if mod.UpdatePowerEventRegistration then
            mod.UpdatePowerEventRegistration()
        end
        -- Re-apply click-cast / hovercast bindings for the new profile.
        if mod.CC_ApplyBindings then
            mod.CC_ApplyBindings()
        end
        -- Friendly Boss Frames and Extra Frames re-read the swapped profile (the pet frames did at
        -- the tails of the raid and party reloads above).
        if mod.FB_Apply then
            mod.FB_Apply()
        end
        if mod.XF_Apply then
            mod.XF_Apply()
        end
        -- Real-preview effective overlay: RunRefreshers reaches here synchronously from
        -- every view/spec/conditional transition, so the preview's value source is
        -- corrected in the SAME frame -- the shared tickers never render a stale
        -- overlay across a flip. Near-zero cost when the overlay gate is inactive.
        if mod._RebuildPvOverlay then
            mod._RebuildPvOverlay()
        end
        -- Solo-visibility recompute: override/profile transitions can flip showWhenSolo
        -- (e.g. a healer solo-frames spec override), and the DB restore alone never
        -- re-derives container visibility or the secure showSolo header attributes, so
        -- frames kept the state of whichever override page was viewed last. Both
        -- recomputes no-op via change guards when nothing moved. OOC-gated: override
        -- refreshers are REGEN-stashed, but direct callers may not be, and secure
        -- attribute writes are combat-blocked; a combat-time skip self-heals on the
        -- existing combat-exit visibility pass.
        if not InCombatLockdown() then
            if mod.UpdateVisibility then
                mod.UpdateVisibility()
            end
            if mod._UpdatePartyVisibility then
                mod._UpdatePartyVisibility()
            end
        end
    end

    -- Buff Manager LAYER swap refresh (spec-override BM forks): re-derives
    -- the spell lookup, then re-drives the aura containers that render BM.
    -- Deliberately BM-only: never calls ReloadFrames, so profile swaps
    -- (_CURF_RefreshAll above) are not doubled. Combat-safe: BM code only
    -- touches our own pooled child frames, never the secure buttons.
    -- noPage: skip the options-page repaint when the caller IS a page build.
    _G._CURF_BMRefresh = function(noPage)
        if not mod.db then
            return
        end
        if mod.BM_RebuildLookup then
            mod.BM_RebuildLookup(mod.db)
        end
        local pv = mod._bmPreviewFrame
        if pv and pv._health and mod.BM_ApplyPreviewIndicators then
            mod.BM_ApplyPreviewIndicators(pv, 1, mod.db.profile)
        end
        -- Aura containers own BM rendering on 12.1: re-drive them so a
        -- swapped-in override fork repaints (fingerprint guards make this
        -- near-free when nothing actually changed).
        if mod.RFC_ReloadAll then
            mod.RFC_ReloadAll()
        end
        -- Open BM options page: force a rebuild so its widgets re-bind to
        -- the (identity-preserved, content-swapped) profile tables.
        if not noPage and mod._bmRoot and CludesUI and CludesUI.RefreshPage then
            CludesUI:RefreshPage(true)
        end
    end

    -- Expose CUI party frames to external trackers that support a provider
    -- API (e.g. MiniAuras). No-op when none is installed.
    mod._RegisterTrackerProviders()

    -- Event frame: register global (non-unit) events
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")

    -- Heal prediction feeds ONLY the incoming-heal display, never absorbs.
    -- Any view rendering it keeps the event; the default (all off) never
    -- registers it at all. Materialized proxies = plain table reads.
    function mod._RFPredWanted()
        return (
            mod._scaledProfile.healPrediction
            or mod._scaledPartyProxy.healPrediction
            or mod._scaledExtraProxy.healPrediction
        )
                and true
            or false
    end
    -- Idempotent toggle sync, called from the _BumpAbsorbGen options funnel.
    function mod._RFSyncPredRegistration()
        local wanted = mod._RFPredWanted()
        for unitToken, tracker in pairs(unitTrackers) do
            if wanted then
                tracker:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unitToken)
            else
                tracker:UnregisterEvent("UNIT_HEAL_PREDICTION")
            end
        end
    end

    -- Per-unit event trackers: one frame per unit.
    -- RegisterUnitEvent only accepts 1-2 units per call, so each unit gets
    -- its own frame. Units that don't exist simply don't fire (zero cost).
    local UNIT_EVENTS_BASE = {
        -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
        -- repaints prediction from health/absorb events only). The one gap --
        -- an aura-granted shield expiring on its TIMER on an unhit, topped
        -- unit (field report: VDH Infernal Strike) fires NO event at all --
        -- is covered by the armed-members belt next to the absorb coalescer.
        -- UNIT_HEAL_PREDICTION absent: it feeds ONLY the incoming-heal
        -- display (never absorbs) and fires on every healer cast at every
        -- target -- registered conditionally in MakeUnitTracker, synced by
        -- ns._RFSyncPredRegistration on options writes.
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_NAME_UPDATE",
        "UNIT_THREAT_LIST_UPDATE",
        "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_FLAGS_CHANGED",
        "UNIT_CONNECTION",
        "UNIT_IN_RANGE_UPDATE",
    }
    local function MakeUnitTracker(unitToken)
        -- Shell-pool adoption: the initial roster build runs from OnEnable
        -- (parent lifecycle context), which would bill every tracker's
        -- event tree to the parent addon for the whole session.
        local frame = mod.TakeShell()
        for _, ev in ipairs(UNIT_EVENTS_BASE) do
            frame:RegisterUnitEvent(ev, unitToken)
        end
        if mod._RFPredWanted() then
            frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unitToken)
        end
        frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unitToken)
        frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", unitToken)
        frame:SetScript("OnEvent", OnEvent)
        unitTrackers[unitToken] = frame
    end
    MakeUnitTracker("player")
    for i = 1, 4 do
        MakeUnitTracker("party" .. i)
    end
    for i = 1, 40 do
        MakeUnitTracker("raid" .. i)
    end
    eventFrame:SetScript("OnEvent", OnEvent)

    -- An opt-in unit event (UNIT_LEVEL, UNIT_TARGET) on every tracker, the Extra Frames'
    -- assigned per-slot ones included (XF_Apply registers it there on assignment).
    local function SyncOptInEvent(evt, wanted)
        for unitToken, tracker in pairs(unitTrackers) do
            if wanted then
                tracker:RegisterUnitEvent(evt, unitToken)
            else
                tracker:UnregisterEvent(evt)
            end
        end
        local XF = mod._XF
        if XF then
            for i = 1, #XF.trackers do
                local widget = XF.buttons[i]
                local unitToken = widget and widget:IsShown() and widget:GetAttribute("unit")
                if wanted and unitToken then
                    XF.trackers[i]:RegisterUnitEvent(evt, unitToken)
                elseif not wanted then
                    XF.trackers[i]:UnregisterEvent(evt)
                end
            end
        end
    end

    -- UNIT_LEVEL: registered only while a view shows the level. Called from
    -- _RefreshProxyModes (every settings write, reload and profile swap); the stamp keeps
    -- the tracker walk to real flips.
    local lvlRegistered = false
    function mod._RFSyncLevelRegistration()
        local wanted = mod.RF_TextWanted("level")
        if wanted == lvlRegistered then
            return
        end
        lvlRegistered = wanted
        SyncOptInEvent("UNIT_LEVEL", wanted)
    end
    mod._RFSyncLevelRegistration()

    -- Custom texts: UNIT_TARGET only while a view's Custom text shows [target]. A Custom
    -- text reading power keeps the power events of units whose power bar is off: the raid
    -- view's on every unit (raid frames show a party on its player and party tokens), the
    -- party view's on those tokens only (UpdatePowerEventRegistration below reads the
    -- stamps and re-runs on a flip). Called with the level's sync; the stamps keep the
    -- walks to real flips.
    local tgtRegistered, raidPowerWanted, partyPowerWanted = false, false, false
    function mod._RFSyncCustomRegistration()
        local wanted = mod.RF_TextWanted("tgt")
        if wanted ~= tgtRegistered then
            tgtRegistered = wanted
            SyncOptInEvent("UNIT_TARGET", wanted)
        end
        local region = mod.RF_TextPlan(mod._scaledProfile).reads
        local p = mod.RF_TextPlan(mod._scaledPartyProxy).reads
        local raidPP, partyPP = (region and region.pp) and true or false, (p and p.pp) and true or false
        if raidPP ~= raidPowerWanted or partyPP ~= partyPowerWanted then
            raidPowerWanted, partyPowerWanted = raidPP, partyPP
            if mod.UpdatePowerEventRegistration then
                mod.UpdatePowerEventRegistration()
            end
        end
    end
    mod._RFSyncCustomRegistration()

    -- UNIT_FLAGS is opt-in: only registered while the combat icon is enabled.
    if mod.UpdateCombatEventRegistration then
        mod.UpdateCombatEventRegistration()
    end

    -- Dynamically register/unregister UNIT_POWER_UPDATE per unit based on
    -- role and power display settings. Called after roster changes and
    -- when the user changes power bar role filters. The trackers are shared
    -- by raid AND party frames: player/party1-4 tokens also drive the party
    -- buttons, whose Power Bar section can be unsynced from raid -- those
    -- must consult the party proxy too, or raid-off/party-on would strip
    -- their events and freeze the party power bars mid-combat.
    local function UpdatePowerEventRegistration()
        local rs = saved.profile
        local ps = mod._partyProxy
        local function wantsPower(cfg, role)
            return (role == "HEALER" and cfg.powerShowForHealer)
                or (role == "TANK" and cfg.powerShowForTank)
                or (role == "DAMAGER" and cfg.powerShowForDPS)
                or (role == "NONE" and cfg.powerShowForDPS)
        end
        -- Healer Mana Display rides these registrations: healers keep their
        -- power events while its mode matches the current group type,
        -- whatever the power bar settings.
        local hmOn = mod._HMActive and mod._HMActive()
        for unitToken, tracker in pairs(unitTrackers) do
            local wantPower = false
            if UnitExists(unitToken) then
                local role = mod._ResolvePowerRole(unitToken)
                wantPower = (IsPowerBarEnabled(rs) and wantsPower(rs, role))
                    or (hmOn and role == "HEALER")
                    or raidPowerWanted
                -- player/party tokens always count as party-displayable; the
                -- routing-map check additionally covers arena, where the party
                -- header binds raid1-5.
                if
                    not wantPower
                    and (
                        unitToken == "player"
                        or unitToken:match("^party%d$")
                        or (mod._partyUnitToButton and mod._partyUnitToButton[unitToken])
                    )
                then
                    if partyPowerWanted then
                        wantPower = true
                    elseif mod.RF_PartyKit() then
                        -- Party Frames kit: the stock mana bar always shows
                        -- (while the party frames are shown; the hide edge
                        -- re-runs this through RF_KitPortraitEvents).
                        wantPower = mod._partyFramesVisible and true or false
                    elseif IsPowerBarEnabled(ps) then
                        wantPower = wantsPower(ps, role)
                    end
                end
            end
            if wantPower then
                tracker:RegisterUnitEvent("UNIT_POWER_UPDATE", unitToken)
                tracker:RegisterUnitEvent("UNIT_DISPLAYPOWER", unitToken)
            else
                tracker:UnregisterEvent("UNIT_POWER_UPDATE")
                tracker:UnregisterEvent("UNIT_DISPLAYPOWER")
            end
        end
        -- Same cadence as the registrations (roster/roles/settings changes).
        if mod.HM_Rebuild then
            mod.HM_Rebuild()
        end
    end
    mod.UpdatePowerEventRegistration = UpdatePowerEventRegistration

    -- Initial update after a short delay
    C_Timer.After(0.5, function()
        -- A /reload in combat never sees PLAYER_REGEN_DISABLED: take the combat
        -- state from the lockdown, and let the combat edge set the visibility
        -- flags the two passes below skip in combat.
        if InCombatLockdown() then
            SetInCombat(true)
            mod._RFCombatVisEdge()
            -- Members assigned while the flag was still down (the first half
            -- second) were kept out of the map; the raid branch below rebuilds too.
            if mod._partyFramesVisible then
                mod._RebuildPartyUnitMap()
            end
        end
        UpdateVisibility()
        mod._UpdatePartyVisibility()
        if framesVisible then
            RebuildUnitMap()
            LayoutGroups()
            -- Re-derive the growth-corner anchor: this can be the first
            -- sized pass when roster data arrives late, and its SetSize
            -- must not leave the container on a stale anchor.
            if mod._ApplyTierOffset then
                mod._ApplyTierOffset()
            end
            UpdateAllButtons()
        end
        if mod._partyFramesVisible then
            mod._LayoutPartyFrames()
        end
    end)

    -- Nickname integrations. When Northern Sky Raid Tools (NSAPI) or Timeline
    -- Reminders (TimelineReminders) is present, raid + party names use their
    -- nicknames (see ResolveDisplayName). Callbacks refresh names instantly
    -- without a /reload when nickname data changes or the user flips the addon's
    -- dedicated CludesUI nicknames checkbox. Both addons may load after us, so
    -- registration retries on PLAYER_LOGIN / PLAYER_ENTERING_WORLD until it sticks.
    -- All registrations are dot calls, NOT colon: the first argument is the unique
    -- registrant key (CallbackHandler keys registrations by it). A colon call would
    -- pass the API table itself as the key and collide with other addons doing the same.
    local function RegisterNSRTNicknames()
        if mod._nsrtNickHooked then
            return true
        end
        if NSAPI and NSAPI.RegisterCallback then
            local function onChange()
                if mod.RefreshAllNames then
                    mod.RefreshAllNames()
                end
            end
            NSAPI.RegisterCallback("CludesUI", "NSRT_NICKNAME_UPDATED", onChange)
            NSAPI.RegisterCallback("CludesUI", mod.EXT_NICK.nsToggle, onChange)
            mod._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterMethodInternalNicknames()
        if mod._methodInternalSurfaceNickHooked then
            return
        end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback("SurfaceNicknamesChanged", function()
                if mod.RefreshAllNames then
                    mod.RefreshAllNames()
                end
            end, "CludesUIRaidFrames")
            mod._methodInternalSurfaceNickHooked = true
        end
    end
    local function RegisterTRNicknames()
        if mod._trNickHooked then
            return true
        end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            -- CallbackHandler passes the event name as the first callback argument.
            -- Toggle fires for every addon checkbox in TR, so filter on ours.
            TR.RegisterCallback("CludesUI", "TimelineReminders_NicknameToggle", function(_, _, addOnName)
                if addOnName == mod.NICK_ADDON and mod.RefreshAllNames then
                    mod.RefreshAllNames()
                end
            end)
            TR.RegisterCallback("CludesUI", "TimelineReminders_NicknameUpdate", function()
                if mod.RefreshAllNames then
                    mod.RefreshAllNames()
                end
            end)
            mod._trNickHooked = true
            return true
        end
        return false
    end
    local function RegisterRGALIASNicknames()
        if mod._rgaliasNickHooked then
            return true
        end
        local RGA = _G.RG_ALIAS
        if RGA and RGA.RegisterCallback and _G.RG_UnitName then
            -- ns._rgaNick gates the ResolveDisplayName consult. The settings
            -- shape is nil-guarded and only read here and in callbacks, never
            -- per name resolve; a fresh RGA install with no settings table
            -- yet simply reads as module-off.
            local function SyncRGAFlag()
                local cfg = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
                mod._rgaNick = (cfg and cfg[mod.EXT_NICK.rgaModule]) and true or nil
                if mod.RefreshAllNames then
                    mod.RefreshAllNames()
                end
            end
            -- pcall: RGA owns its RegisterCallback signature; a mismatch or
            -- future change must not error our OnEnable. If registration
            -- fails, the flag is still seeded once below -- module toggles
            -- then need a /reload to be noticed (degraded, never broken).
            pcall(RGA.RegisterCallback, "DbUpdated", SyncRGAFlag)
            pcall(RGA.RegisterCallback, "ModuleEnabled", function(evt, moduleName)
                if moduleName == mod.EXT_NICK.rgaModule then
                    SyncRGAFlag()
                end
            end)
            pcall(RGA.RegisterCallback, "ModuleDisabled", function(evt, moduleName)
                if moduleName == mod.EXT_NICK.rgaModule then
                    SyncRGAFlag()
                end
            end)
            local cfg = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
            mod._rgaNick = (cfg and cfg[mod.EXT_NICK.rgaModule]) and true or nil
            mod._rgaliasNickHooked = true
            return true
        end
        return false
    end

    local nsrtHooked = RegisterNSRTNicknames()
    local trHooked = RegisterTRNicknames()
    local rgaliasHooked = RegisterRGALIASNicknames()
    if not (nsrtHooked and trHooked and rgaliasHooked) then
        local nickFrame = mod.TakeShell()
        nickFrame:RegisterEvent("PLAYER_LOGIN")
        nickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        nickFrame:SetScript("OnEvent", function(self, evt)
            local a = RegisterNSRTNicknames()
            local b = RegisterTRNicknames()
            local c = RegisterRGALIASNicknames()
            -- Anything not loaded by first PLAYER_ENTERING_WORLD is not coming.
            if (a and b and c) or evt == "PLAYER_ENTERING_WORLD" then
                self:UnregisterAllEvents()
            end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternalNicknames)
    -- CustomNames fires one callback per character, so a BattleTag rename or an
    -- import arrives as a burst: refresh once on the next frame. Nothing waits for
    -- it unless it is installed and enabled for this character.
    local function RegisterCustomNames()
        local CN = LibStub("CustomNames", true)
        if not (CN and CN.UnitName and CN.RegisterCallback) or mod._customNames then
            return
        end
        mod._customNames = CN
        local pending
        local function flush()
            pending = nil
            if mod.RefreshAllNames then
                mod.RefreshAllNames()
            end
        end
        local function onChange()
            if pending then
                return
            end
            pending = true
            C_Timer.After(0, flush)
        end
        CN.RegisterCallback("CludesUI", "Name_Added", onChange)
        CN.RegisterCallback("CludesUI", "Name_Update", onChange)
        CN.RegisterCallback("CludesUI", "Name_Removed", onChange)
        if mod.RefreshAllNames then
            mod.RefreshAllNames()
        end
    end
    if C_AddOns.IsAddOnLoaded("CustomNames") or C_AddOns.IsAddOnLoadable("CustomNames") then
        EventUtil.ContinueOnAddOnLoaded("CustomNames", RegisterCustomNames)
    end

    -- Init options module if it loaded before us
    if mod._InitCUIModule then
        C_Timer.After(0, mod._InitCUIModule)
    end
end

-- Slash command registered in CUI_RaidFrames_Options.lua

-------------------------------------------------------------------------------
--  Party Mode: spinning party and raid frames (CludesUI.PartySpin_Create).
--  Each set's shown buttons orbit the centre of its container, so the 5-slot
--  party box turns around its third frame. homeInCombat puts the secure
--  buttons back on the header layout for each fight.
-------------------------------------------------------------------------------
do
    -- A header's shown buttons, in child order.
    local function AddShown(heading, entries)
        if not (heading and heading:IsVisible()) then
            return
        end
        local i, b = 1, heading:GetAttribute("child1")
        while b do
            if b:IsVisible() then
                entries[#entries + 1] = b
            end
            i = i + 1
            b = heading:GetAttribute("child" .. i)
        end
    end

    local partyList = {}
    local partyGroup = { frames = partyList }
    local partyGroups = {}
    CludesUI.PartySpin_Create({
        target = "partyFrames",
        homeInCombat = true,
        collect = function()
            wipe(partyList)
            wipe(partyGroups)
            local box = mod._partyContainerFrame
            if box and box:IsVisible() then
                AddShown(mod._partyHeader, partyList)
                local scrollBar = mod._partySelfButton
                if scrollBar and scrollBar:IsVisible() then
                    partyList[#partyList + 1] = scrollBar
                end
                partyGroup.pivot = box
                partyGroups[1] = partyGroup
            end
            return partyGroups
        end,
    })

    local raidList = {}
    local raidGroup = { frames = raidList }
    local raidGroups = {}
    CludesUI.PartySpin_Create({
        target = "raidFrames",
        homeInCombat = true,
        collect = function()
            wipe(raidList)
            wipe(raidGroups)
            if containerFrame and containerFrame:IsVisible() then
                for g = 1, 8 do
                    AddShown(separatedHdrs[g], raidList)
                end
                AddShown(mod._flatHeader, raidList)
                raidGroup.pivot = containerFrame
                raidGroups[1] = raidGroup
            end
            return raidGroups
        end,
    })
end

Inner.broken = false
