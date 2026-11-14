if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Events.lua
--
--  The event frame for run-time maintenance and the slash commands.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ECME, _bonusScanSeen, _cdmViewerNames = Inner.ECME, Inner._bonusScanSeen, Inner._cdmViewerNames
local _ecmeFC, _maxChargeCount = Inner._ecmeFC, Inner._maxChargeCount
local _multiChargeSpells, CheckSpecChange = Inner._multiChargeSpells, Inner.CheckSpecChange
local OnProcGlowEvent = Inner.OnProcGlowEvent
local BLIZZ_CDM_FRAMES_SECONDARY = Inner.BLIZZ_CDM_FRAMES_SECONDARY
local HideBlizzardCDM, RestoreBlizzardBuffFrame = Inner.HideBlizzardCDM, Inner.RestoreBlizzardBuffFrame
local BuildAllCDMBars, UpdateCDMKeybinds = Inner.BuildAllCDMBars, Inner.UpdateCDMKeybinds
local _CDMApplyVisibility, RequestUpdate = Inner._CDMApplyVisibility, Inner.RequestUpdate
local SetInCombat = Inner.SetInCombat
local OpenBlizzardCDMTab = Inner.OpenBlizzardCDMTab

-- Debounced keybind refresh: one prebuilt callback fires 0.5s after the LAST
-- triggering event (each event only pushes the deadline), so a slot-event storm
-- (mouseover macros re-fire ACTIONBAR_SLOT_CHANGED on every hover change)
-- allocates nothing per event.
local _keybindDue, _keybindArmed = 0, false
local function KeybindDebounceFire()
    local wait = _keybindDue - GetTime()
    if wait > 0.01 then
        C_Timer.After(wait, KeybindDebounceFire)
        return
    end
    _keybindArmed = false
    UpdateCDMKeybinds()
end

-------------------------------------------------------------------------------
--  Event-Driven Runtime Maintenance
--
--  This frame owns the non-tick triggers: login/world transitions, spec swaps,
--  talent changes, roster updates, binding changes, proc-glow signals, and
--  combat/visibility state. Most heavy work is deferred into rebuild helpers
--  rather than performed inline in the event callback.
-------------------------------------------------------------------------------
-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
-- Live override flips (proc-based hero-talent transforms): resolution memos
-- derived from override state go stale the moment this fires.
eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
-- Only ever acted on for an override id we armed ourselves; Blizzard's own base-spell
-- registrations dispatch here too and fall straight through.
eventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
-- Hero talent / loadout change events
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
-- Viewer data landing after our init: the injection phase keys on live
-- Blizzard frames (frames as truth), so a build that ran before the viewer
-- populated may have injected a custom racial frame the native viewer now
-- covers. One debounced rebuild re-evaluates; fires rarely (login, and
-- Blizzard-side data refreshes).
eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
-- Cinematic/cutscene end: Blizzard restores hidden frames, so re-hide ours
eventFrame:RegisterEvent("CINEMATIC_STOP")
eventFrame:RegisterEvent("STOP_MOVIE")
-- Equipment changes: trinket/weapon swaps update trinket frames and reanchor
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Visibility option events: mounted, target, instance zone changes
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Resting: IsResting() has no dedicated poll, so without this the Resting
-- axis only re-evaluated when some unrelated event above happened to fire.
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
-- Party Mode axis: no game event; the core fires its own edge.
if CludesUI.RegisterVisEdge then
    CludesUI.RegisterVisEdge(function()
        _CDMApplyVisibility()
    end)
end
-- Vehicle edges for the In Vehicle axis (player-filtered; same reasoning).
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
-- Dragonriding visibility modes: capability edge (mount/dismount/zone) plus
-- the airborne edge (takeoff/landing while staying mounted; probed at load
-- in CludesUI_Visibility.lua -- absent = the checklist items lock).
eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
if CludesUI._hasGlidingEvent then
    eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
end
-- Druid travel/flight/aquatic form needs an explicit re-check for the
-- visHideMounted option. PLAYER_MOUNT_DISPLAY_CHANGED only fires for real
-- mounts, and the viewer hooks rebuild icon content on shapeshift but
-- don't re-run bar-level visibility. Only register for druids -- non-druid
-- classes have no mount-like shapeshift forms, and druid combat shifts
-- (Bear/Cat) would otherwise trigger unnecessary visibility recomputes.
local _, _playerClassCDM = UnitClass("player")
if _playerClassCDM == "DRUID" then
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
end

-- Debounce token for talent-change rebuilds: rapid talent clicks collapse
-- into a single deferred rebuild rather than firing once per click.
local _talentRebuildToken = 0

local function ScheduleTalentRebuild()
    _talentRebuildToken = _talentRebuildToken + 1
    local token = _talentRebuildToken
    C_Timer.After(0.5, function()
        if token ~= _talentRebuildToken then
            return
        end -- superseded
        -- Wipe per-spell caches that may reference stale override IDs or stale charge
        -- data from spells that changed with the talent swap. Also wipe the persisted
        -- DB entries so CacheMultiChargeSpell re-detects from live API rather than
        -- reading a stale false entry. Skip during combat: actual talent changes are
        -- combat-locked, so these events only fire mid-combat from hero talent procs
        -- (e.g. Celestial Infusion). Wiping here would clear charge data for all spells
        -- with no way to re-detect it until the next out-of-combat cache rebuild.
        if not InCombatLockdown() then
            wipe(_multiChargeSpells)
            wipe(_maxChargeCount)
            local saved = ECME.db
            if saved and saved.sv and saved.sv.multiChargeSpells then
                wipe(saved.sv.multiChargeSpells)
            end
            -- Hidden Outside Form/Stance answers (a talent can change which
            -- forms a spell needs)
            if mod.CdmWipeFormCache then
                mod.CdmWipeFormCache()
            end
        end
        -- Rebuild the cdID route map against the new talent set. The stored
        -- assignedSpells is left untouched (it's pure user intent); the route map is
        -- the live source of truth for which frame renders on which bar. A full CDM
        -- rebuild + reanchor below picks up the new routing.
        if mod.RebuildSpellRouteMap then
            mod.RebuildSpellRouteMap()
        end
        -- The placeholder icon bridge reads the spellbook, and a talent swap is
        -- exactly what changes which form a name resolves to.
        if mod.WipeCdmBookNameCache then
            mod.WipeCdmBookNameCache()
        end
        -- Clear cached viewer child info so the next tick re-reads from API
        -- (overrideSpellID may have changed with the new talent set)
        for _, vname in ipairs(_cdmViewerNames) do
            local vf = _G[vname]
            if vf and vf:GetNumChildren() > 0 then
                local children = { vf:GetChildren() }
                for ci = 1, #children do
                    local ch = children[ci]
                    if ch then
                        local chfc = _ecmeFC[ch]
                        if chfc then
                            chfc.resolvedSid = nil
                            chfc.baseSpellID = nil
                            chfc.overrideSid = nil
                            chfc.cachedCdID = nil
                            chfc.isChargeSpell = nil
                            chfc.maxCharges = nil
                        end
                    end
                end
            end
        end
        mod._cdmUnresolvedRetries = 0 -- fresh window; see FullCDMRebuild
        -- Rebuild keybind cache (talent swap may change action slot contents)
        UpdateCDMKeybinds()
        -- Invalidate TBB frame cache + spell caches, then reanchor so
        -- overlays re-evaluate against the new viewer pool state.
        if mod.InvalidateTBBFrameCache then
            mod.InvalidateTBBFrameCache()
        end
        if mod.MarkCDMSpellCacheDirty then
            mod.MarkCDMSpellCacheDirty()
        end
        if mod.QueueReanchor then
            mod.QueueReanchor()
        end
    end)
end

local _rosterRebuildPending = false
local _equipRebuildPending = false

local function ScheduleRosterRebuild()
    -- Roster changes (promote, join, leave) don't change spells or bar
    -- routing. Only party frame anchoring needs a refresh. A full
    -- BuildAllCDMBars was causing massive single-frame CPU spikes.
    CludesUI.InvalidateFrameCache()
    if InCombatLockdown() then
        _rosterRebuildPending = true
        return
    end
    -- Lightweight: just reanchor bars that depend on party frames
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
end

-- Events that can move an ability to another action button (Bar Glows keyed per ability).
local BAR_REBIND_EVENTS = {
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true,
    SPELLS_CHANGED = true,
}

eventFrame:SetScript("OnEvent", function(_, evt, unitToken, updateInfo, arg3)
    if not ECME.db then
        return
    end
    if mod._barGlowRebindOn and BAR_REBIND_EVENTS[evt] then
        mod.QueueBarGlowRebind(evt, unitToken)
    end
    if evt == "PLAYER_LOGOUT" then
        mod.SaveCachedBarSizes()
        return
    end
    if evt == "SPELL_RANGE_CHECK_UPDATE" then
        mod.RepaintOverrideRange(unitToken) -- payload is (spellID, isInRange, checksRange)
        return
    end
    if evt == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        -- Bump-only: painting is driven by the cooldown/desat hooks, which re-resolve on their next fire. No repaint request from here.
        mod._cdmResGen = mod._cdmResGen + 1
        -- Except the range tint, which no hook re-resolves -- Blizzard's own check
        -- is armed on the base id and never re-polls for the override.
        -- Payload here is (baseSpellID, overrideSpellID).
        mod.ResyncCdmRange(unitToken, updateInfo)
        return
    end
    if evt == "COMBAT_LOG_EVENT_UNFILTERED" then
        return
    end
    if evt == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or evt == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnProcGlowEvent(evt, unitToken) -- unit = spellID (first arg after event)
        return
    end
    if
        evt == "UPDATE_BINDINGS"
        or evt == "ACTIONBAR_SLOT_CHANGED"
        or evt == "ACTIONBAR_PAGE_CHANGED"
        or evt == "UPDATE_BONUS_ACTIONBAR"
        or evt == "UPDATE_OVERRIDE_ACTIONBAR"
        or evt == "UPDATE_VEHICLE_ACTIONBAR"
    then
        -- A page/bonus/override/vehicle swap only changes which page is
        -- active, not the contents of the slots the stable scan reads -- so it
        -- cannot change the cache. Drop it, and with it the rebuild storm a
        -- stealthing rogue or shapeshifting druid used to cause. Only
        -- UPDATE_BINDINGS and ACTIONBAR_SLOT_CHANGED are real edits.
        --
        -- Exception, as insurance: let the first sighting of each bonus bar
        -- through, in case that form's slots (73-132) are only populated when
        -- the player first shifts into it rather than at login.
        --
        -- Without stable keys the keys follow the page the bars show, so a swap
        -- rebuilds them on the next frame (ns.CDMKeybindPageSwap), never after
        -- the slot-storm debounce below.
        if evt ~= "UPDATE_BINDINGS" and evt ~= "ACTIONBAR_SLOT_CHANGED" then
            if not (mod.CDMStableKeybindsEnabled and mod.CDMStableKeybindsEnabled()) then
                mod.CDMKeybindPageSwap()
                return
            end
            local firstSighting = false
            if evt == "UPDATE_BONUS_ACTIONBAR" then
                local off = GetBonusBarOffset and GetBonusBarOffset() or 0
                if off > 0 and not _bonusScanSeen[off] then
                    _bonusScanSeen[off] = true
                    firstSighting = true
                end
            end
            if not firstSighting then
                return
            end
        end
        -- Debounce: one-button rotation addons fire ACTIONBAR_SLOT_CHANGED on every GCD. Rapid-fire events coalesce into a single update 0.5s after the last event.
        _keybindDue = GetTime() + 0.5
        if not _keybindArmed then
            _keybindArmed = true
            C_Timer.After(0.5, KeybindDebounceFire)
        end
        return
    end
    if evt == "COOLDOWN_VIEWER_DATA_LOADED" or evt == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        -- Native viewer data arrived (usually after login init), or a server
        -- hotfix rewrote the cooldown tables mid-session (the viewer then
        -- releases and re-acquires its whole item pool, which the CD/utility
        -- hooks deliberately do not follow): re-evaluate the
        -- frames-as-truth injection decisions against the now-live frame set.
        -- Rides the same debounced rebuild as talent changes; the reanchor sweep
        -- hides any injected racial frame the native viewer now covers. The spell
        -- picker's learned-set cache refreshes too (category sets just changed),
        -- and the reseed session stamps clear so base-bar materialization re-runs
        -- against the COMPLETE icon set (an init-time reseed may have seen a
        -- partial viewer; the racial-family guard keeps the re-run from minting
        -- a second racial slot).
        if mod.MarkCDMSpellCacheDirty then
            mod.MarkCDMSpellCacheDirty()
        end
        if mod._reseededSpecsSession then
            wipe(mod._reseededSpecsSession)
        end
        ScheduleTalentRebuild()
        return
    end
    if
        evt == "TRAIT_CONFIG_UPDATED"
        or evt == "PLAYER_TALENT_UPDATE"
        or evt == "ACTIVE_TALENT_GROUP_CHANGED"
        or evt == "PLAYER_PVP_TALENT_UPDATE"
    then
        -- Hero talent, loadout, or PvP talent context change -- debounced rebuild. PvP talents
        -- (de)activating on arena enter/exit makes Blizzard re-evaluate the viewer's tracked
        -- cooldown set; without a rebuild the new pool frames are never re-claimed and the
        -- unclaimed-frame cleanup blanks them (arena-exit empty-CDM bug). The spell set may have changed: let the post-rebuild reanchor re-run the automatic base-bar materialization for this spec.
        if mod._reseededSpecsSession then
            wipe(mod._reseededSpecsSession)
        end
        -- Drop the spellbook name map NOW, not only in the debounced rebuild. It answers "which
        -- form does the player have", which is exactly what just changed, and anything repainting
        -- inside the debounce window would otherwise resolve against the pre-swap book. The rebuild
        -- wipes it again, which still matters: this early rebuild can read a book the client has not finished updating, and that second wipe corrects it.
        if mod.WipeCdmBookNameCache then
            mod.WipeCdmBookNameCache()
        end
        -- Talent Conditions read node ranks from a cache; the rebuild's reanchor re-evaluates them.
        -- Unconditional: the options popup fills the cache before the gate is ever set.
        mod.TalentCondInvalidate()
        -- Bar Glows limited to a hero tree: re-check them now (only while one exists).
        if mod._barGlowAnyHero and mod.UpdateOverlayVisuals then
            mod.UpdateOverlayVisuals()
        end
        ScheduleTalentRebuild()
        return
    end
    if evt == "GROUP_ROSTER_UPDATE" then
        ScheduleRosterRebuild()
        _CDMApplyVisibility()
        return
    end
    if evt == "CINEMATIC_STOP" or evt == "STOP_MOVIE" then
        -- Blizzard restores frame positions/alpha after cinematics end. Re-hide immediately so the Blizzard CDM doesn't reappear.
        local p = ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.hideBlizzard then
            C_Timer.After(0, function()
                HideBlizzardCDM()
                if p.cdmBars.useBlizzardBuffBars then
                    RestoreBlizzardBuffFrame()
                end
            end)
        end
        return
    end
    if evt == "PLAYER_EQUIPMENT_CHANGED" then
        -- One rebuild per gear swap: an equipment set fires this once per slot, and
        -- each rebuild is ~3.5 ms. Combat swaps need none (the trinket hook updates).
        if InCombatLockdown() or _equipRebuildPending then
            return
        end
        _equipRebuildPending = true
        C_Timer.After(0, function()
            -- Combat began before the flush (/equipset + opener): stay pending,
            -- PLAYER_REGEN_ENABLED rebuilds.
            if InCombatLockdown() then
                return
            end
            _equipRebuildPending = false
            BuildAllCDMBars()
            if mod.QueueReanchor then
                mod.QueueReanchor()
            end
        end)
        return
    end
    if
        evt == "PLAYER_TARGET_CHANGED"
        or evt == "PLAYER_UPDATE_RESTING"
        or evt == "UNIT_ENTERED_VEHICLE"
        or evt == "UNIT_EXITED_VEHICLE"
    then
        _CDMApplyVisibility()
        return
    end
    if
        evt == "PLAYER_MOUNT_DISPLAY_CHANGED"
        or evt == "PLAYER_CAN_GLIDE_CHANGED"
        or evt == "PLAYER_IS_GLIDING_CHANGED"
    then
        -- Defer to a clean execution context: the event handler chain can carry taint from other
        -- addons, which propagates into LayoutCDMBar when a bar transitions from hidden to visible (visHideMounted). The dragonriding edges take the same deferred path for the same reason (mid-flight unhide runs LayoutCDMBar).
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if evt == "UPDATE_SHAPESHIFT_FORM" then
        -- Bail fast if no bar actually uses visHideMounted: druids shift constantly in combat (Bear/Cat) and we don't want to re-run the visibility pipeline for nothing.
        local p = ECME.db and ECME.db.profile
        local barList = p and p.cdmBars and p.cdmBars.bars
        if not barList then
            return
        end
        local anyMountedOpt = false
        for _, edge in ipairs(barList) do
            if edge.visHideMounted then
                anyMountedOpt = true
                break
            end
        end
        if not anyMountedOpt then
            return
        end
        -- Defer one frame: the Travel Form aura is applied slightly after UPDATE_SHAPESHIFT_FORM fires, so IsPlayerMountedLike's aura check would miss it on the immediate pass.
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if evt == "PLAYER_REGEN_DISABLED" or evt == "PLAYER_REGEN_ENABLED" or evt == "ZONE_CHANGED_NEW_AREA" then
        if mod._syncRotationCombatState then
            mod._syncRotationCombatState()
        end
        if evt == "PLAYER_REGEN_DISABLED" then
            SetInCombat(true)
            _CDMApplyVisibility()
            mod.RefreshItemCountOOCBars()
            -- Straight through, same as the exit edge below: the sweep only
            -- touches our own overlays, so it needs nothing from the visibility
            -- pass above, and a deferral would leave the pull one frame dark.
            mod.CDMGlowCombatSync()
        elseif evt == "PLAYER_REGEN_ENABLED" then
            -- Buffer combat exit: brief out-of-combat blips (mob dies, re-aggro) shouldn't flash visibility changes.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    SetInCombat(false)
                    _CDMApplyVisibility()
                    mod.RefreshItemCountOOCBars()
                    mod.CDMGlowCombatSync()
                end
            end)
        else
            -- Zone transition: re-apply visibility (mounted state etc. may have changed). No rebuild or reanchor -- SPELLS_CHANGED handles the rebuild if the spec changed.
            _CDMApplyVisibility()
        end
        -- Flush deferred TBB rebuild that was queued during combat
        if evt == "PLAYER_REGEN_ENABLED" and mod.IsTBBRebuildPending and mod.IsTBBRebuildPending() then
            if mod.BuildTrackedBuffBars then
                mod.BuildTrackedBuffBars()
            end
        end
        -- Flush a secondary buff-viewer park that was blocked during combat
        if evt == "PLAYER_REGEN_ENABLED" and mod._secondaryParkPending then
            mod._secondaryParkPending = nil
            local sv = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
            local svc = sv and _ecmeFC[sv]
            if svc and svc.hidden then
                mod.ParkSecondaryBuffViewer(sv)
            end
        end
        -- Flush deferred roster reanchor that was blocked during combat
        if evt == "PLAYER_REGEN_ENABLED" and _rosterRebuildPending then
            _rosterRebuildPending = false
            if mod.QueueReanchor then
                mod.QueueReanchor()
            end
        end
        if evt == "PLAYER_REGEN_ENABLED" and _equipRebuildPending then
            _equipRebuildPending = false
            BuildAllCDMBars()
            if mod.QueueReanchor then
                mod.QueueReanchor()
            end
        end
        return
    end
    if evt == "PLAYER_ENTERING_WORLD" then
        -- UnitAffectingCombat, not InCombatLockdown: the latter reads false in
        -- the login window of a combat /reload, which seeded "out of combat"
        -- for the rest of the pull (in-combat visibility modes and the OOC
        -- fade then hid every bar). Secret in restricted content: fall back.
        local c = UnitAffectingCombat and UnitAffectingCombat("player")
        if c == nil or (issecretvalue and issecretvalue(c)) then
            c = InCombatLockdown and InCombatLockdown() or false
        end
        SetInCombat(c == true)
        -- Re-read the gate (a profile may have loaded), then reconcile against
        -- the combat state sampled just above: the regen events never fire for
        -- a zone-in that lands mid-combat. At the very first world entry nothing
        -- is recorded yet, so only the gate read matters there.
        mod.RefreshGlowCombatGate()
        mod.CDMGlowCombatSync()
        -- PvP instance transition backstop: entering or leaving a PvP instance rebuilds viewer pools (PvP talents activate/deactivate). Rebuild + reanchor so the new pool frames are claimed.
        local _, instType = IsInInstance()
        local wasPvP = mod._cdmWasInPvP
        local isPvP = (instType == "arena" or instType == "pvp")
        if wasPvP and not isPvP then
            ScheduleTalentRebuild()
        end
        mod._cdmWasInPvP = isPvP or nil
        if isPvP and not wasPvP then
            if mod.QueueReanchor then
                mod.QueueReanchor()
            end
        end
        -- Install rotation helper hook after CDM frames have been built
        C_Timer.After(1, function()
            mod.InstallRotationHook()
        end)
        -- Safety: re-apply visibility after loading screen settles. Two passes to catch both fast and late viewer pool rebuilds.
        C_Timer.After(1.5, _CDMApplyVisibility)
        C_Timer.After(3, _CDMApplyVisibility)
    end
    if evt == "SPELLS_CHANGED" then
        CheckSpecChange()
        mod._spellsReadyForApply = true
        -- Spell data churn invalidates cooldownID resolution memos.
        mod._cdmResGen = mod._cdmResGen + 1
        -- Engine spell data changed (spec-swap churn tail, druid form swap, talent/spell overrides).
        -- The variant-expanded diversion maps and the memoized cdID->bar routes were derived from
        -- the PREVIOUS spell state; a route resolved mid-churn against transitional cooldown info
        -- is cached until the next map rebuild and pins a ghosted/custom spell onto the wrong
        -- visible bar. Re-derive from current truth and re-claim -- the LAST fire of any churn
        -- burst always leaves the final state correct, with no settle timers. (CheckSpecChange's reconcile also rebuilds the map, but a same-key fire means the data changed again after that rebuild.)
        if mod.RebuildSpellRouteMap then
            mod.RebuildSpellRouteMap()
        end
        -- The tracked-buff catalog can change in the same churn, and the login-pass reconcile may
        -- have consumed its dirty flag against a still-empty viewer pool (the flag is cleared
        -- before the call and an empty catalog no-ops). Re-arm so the queued reanchor reconciles the buff display order against the populated catalog.
        mod._cdmBuffOrderDirty = true
        if mod.QueueReanchor then
            mod.QueueReanchor()
        end
        return
    end
    if evt == "PLAYER_SPECIALIZATION_CHANGED" and unitToken == "player" then
        mod.DisarmOverrideRanges() -- the new spec's overrides re-arm on their own events
        -- Non-rebuild work only. The actual spec change rebuild is driven by SPELLS_CHANGED above
        -- (which fires for both manual and auto swaps). This handler just invalidates caches that need immediate clearing.
        CludesUI.InvalidateFrameCache()
    end
    RequestUpdate()
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ECME1 = "/ccme"
SLASH_ECME2 = "/cdmeffects"
SLASH_ECME3 = "/ccdm"
SlashCmdList.ECME = function(msg)
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    CludesUI:ShowModule("CludesUICooldownManager")
end

-- /cd toggles Blizzard's Cooldown Manager settings: out of combat, a frame
-- later (off the chat line, as the parent's commands run). The /cd alias
-- itself is set in ECME:OnInitialize, and only while Quality of Life's
-- "Type /cd to open Blizzard CDM" is on.
SlashCmdList.CUIBLIZZCDM = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            CludesUI.PrintError(CludesUI.L("Cannot open the Cooldown Manager during combat."))
            return
        end
        OpenBlizzardCDMTab()
    end)
end

Inner.broken = false
