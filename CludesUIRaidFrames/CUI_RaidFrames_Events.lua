if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Events.lua
--
--  OnEvent: the handler of the event frame and of every unit tracker.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ipairs = ipairs
local wipe = wipe
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local allButtons, GetFFD, unitToButton = Inner.allButtons, Inner.GetFFD, Inner.unitToButton
local RebuildUnitMap, UpdateButton = Inner.RebuildUnitMap, Inner.UpdateButton
local UpdateReadyCheck, LayoutGroups = Inner.UpdateReadyCheck, Inner.LayoutGroups
local ReloadFrames, RangeUpdate = Inner.ReloadFrames, Inner.RangeUpdate
local UpdateVisibility, SetInCombat = Inner.UpdateVisibility, Inner.SetInCombat
local SetReadyCheckActive = Inner.SetReadyCheckActive

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local inCombat = false
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val) inCombat = val end
local readyCheckActive = false
Inner.readyCheckActiveSetters[#Inner.readyCheckActiveSetters + 1] = function(val) readyCheckActive = val end
local framesVisible = false
Inner.framesVisibleSetters[#Inner.framesVisibleSetters + 1] = function(val) framesVisible = val end

-- Healer Mana Display: its rebuild normally rides the raid/party frame paths
-- (UpdatePowerEventRegistration tails). A roster change that lands with BOTH
-- frame sets hidden -- leaving a raid to solo, or to a party while CUI party
-- frames are disabled -- skips every rebuild, so the display would keep its
-- last group's content (raid-mode names included) indefinitely.
local function RebuildHealerManaIfFramesHidden()
    if not framesVisible and not mod._partyFramesVisible and mod.HM_Rebuild then mod.HM_Rebuild() end
end

-------------------------------------------------------------------------------
--  Event handlers
-------------------------------------------------------------------------------
local function OnEvent(self, evt, arg1, ...)
    -- Hot per-unit branches FIRST (thousands per pull); everything below them
    -- is rare. Order is semantics-free -- event names are distinct -- and a
    -- hidden frame set has empty routing maps, so these no-op there exactly as
    -- they did behind the visibility guard further down.
    if evt == "UNIT_HEALTH" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            -- Latched rez offer: the accept lands as a health edge (no further
            -- INCOMING_RESURRECT_CHANGED). This edge OWNS the alive-clear (the
            -- predicate is deliberately pure), then repaints the shared icon.
            -- Clearing here also stops a lingering offer window from painting a
            -- fresh, unrezzed corpse if the unit dies again. Nil lookup for
            -- everyone else.
            local hadRez = mod._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                mod._rezPend[arg1] = nil
            end
            mod._UpdateButtonHealth(button, arg1)
            if hadRez then UpdateReadyCheck(button, arg1) end
        end
    elseif evt == "UNIT_MAXHEALTH" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            -- Same latch ownership as UNIT_HEALTH: on accept both fire in
            -- unguaranteed order, and whichever runs first must fix the icon.
            local hadRez = mod._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                mod._rezPend[arg1] = nil
            end
            mod._UpdateButtonHealth(button, arg1)
            mod._ResettleButtonHealth(button)
            -- Max moves the absorb bars' range (see the header dispatcher's
            -- UNIT_MAXHEALTH branch for the full rationale).
            local dmx = GetFFD(button)
            if dmx._absActive then mod._MarkAbsorbDirty(button, arg1) end
            if hadRez then UpdateReadyCheck(button, arg1) end
        end
    elseif
        evt == "UNIT_ABSORB_AMOUNT_CHANGED"
        or evt == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        or evt == "UNIT_HEAL_PREDICTION"
        or evt == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED"
    then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            -- The event IS the arm: plainly observable even while the values
            -- are secret. Paint coalesces to once per render frame.
            -- Prediction is view-gated: with the feature off for this button's
            -- view the event changes no pixel and must not arm.
            local dropdown = GetFFD(button)
            if evt == "UNIT_HEAL_PREDICTION" then
                local savedVars = dropdown._isParty and mod._scaledPartyProxy
                    or (dropdown._isExtra and mod._scaledExtraProxy)
                    or mod._scaledProfile
                if savedVars.healPrediction then
                    mod._AbArm(button, arg1, dropdown)
                    mod._MarkAbsorbDirty(button, arg1)
                end
            else
                if evt ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then mod._AbArm(button, arg1, dropdown) end
                mod._MarkAbsorbDirty(button, arg1)
                if evt == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then mod.UpdateHealAbsorbTextFor(button, arg1) end
                -- Custom texts showing the amount this event moved (two field reads while
                -- none does); the max-health-modifier edge moves health only.
                local tp = dropdown._txP
                if tp and tp.reads and evt ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                    mod.RF_TextRepaintCustom(
                        dropdown,
                        arg1,
                        evt == "UNIT_ABSORB_AMOUNT_CHANGED" and "abs" or "habs"
                    )
                end
                if evt == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                    dropdown._rmhPct = nil -- reduced-max cache: this is its only value edge
                    mod._UpdateButtonHealth(button, arg1)
                    mod._ResettleButtonHealth(button)
                end
            end -- prediction view-gate else
        end
    elseif evt == "PLAYER_REGEN_DISABLED" then
        SetInCombat(true)
        -- HARD INVARIANT: the real party/raid frames must never be left hidden
        -- when a pull starts. Every restore op reached from here is combat-legal
        -- (SetAlpha on our own containers; Hide/SetParent on our own non-secure
        -- preview frames), so it can never be blocked or deferred. This forces
        -- the frames fully visible the instant combat begins, even if a preview
        -- or size preview was still active, independent of the panel auto-close.
        if mod._sizePreviewTier then
            mod._sizePreviewTier = nil
            if mod._HideSizePreview then mod._HideSizePreview() end
        end
        if mod.EnsureRealFramesRestored then mod.EnsureRealFramesRestored() end
        -- Combat starting: hide role/leader icons on frames using the in-combat cogs.
        if mod._UpdateRoleIcons then mod._UpdateRoleIcons() end
        if mod._UpdateLeaderIcons then mod._UpdateLeaderIcons() end
        if mod._CombatIconEnabled() and mod._UpdateCombatIcons then mod._UpdateCombatIcons() end
    elseif evt == "PLAYER_REGEN_ENABLED" then
        SetInCombat(false)
        local frameStrataDirty = mod._frameStrataDirty
        if frameStrataDirty and mod.ApplyFrameStrata then mod.ApplyFrameStrata() end
        -- Combat ended: restore any role/leader icons suppressed during combat.
        if mod._UpdateRoleIcons then mod._UpdateRoleIcons() end
        if mod._UpdateLeaderIcons then mod._UpdateLeaderIcons() end
        if mod._CombatIconEnabled() and mod._UpdateCombatIcons then mod._UpdateCombatIcons() end
        -- Complete any container reparent that was blocked during combat (e.g.
        -- the options panel was closed mid-combat while a preview was active).
        -- Without this, a combat auto-close can leave the real frames orphaned
        -- under the hidden preview parent until the next options open+close.
        if mod._restorePending then
            mod._restorePending = nil
            if mod.EnsureRealFramesRestored then mod.EnsureRealFramesRestored() end
        end
        local rosterDirty = mod._rosterDirtyInCombat
        local sizeTierDirty = mod._sizeTierDirtyInCombat
        -- Force the heavy refresh ONLY if the roster/size changed during combat.
        -- Otherwise the live per-unit events kept buttons current and the
        -- transition gate in UpdateVisibility skips the rebuild.
        if rosterDirty or sizeTierDirty then mod._visForceRebuild = true end
        mod._rosterDirtyInCombat = nil
        mod._sizeTierDirtyInCombat = nil
        UpdateVisibility()
        mod._UpdatePartyVisibility()
        if rosterDirty or sizeTierDirty then
            if framesVisible then
                if sizeTierDirty then
                    -- Size tier crossed during combat: full reload now safe
                    ReloadFrames()
                else
                    LayoutGroups()
                end
            end
            -- Same-dimension tier changes take the LayoutGroups branch; reapply offset
            -- so the container lands at the correct tier. Outside the framesVisible
            -- gate for the same reason as the roster path: a raid left mid-combat must
            -- still re-base the now-hidden container once combat ends.
            if mod._ApplyTierOffset then mod._ApplyTierOffset() end
            if mod._partyFramesVisible then mod._LayoutPartyFrames() end
            if rosterDirty then RebuildHealerManaIfFramesHidden() end
        end
        -- Party container geometry deferred by a combat-time _CURF_RefreshAll.
        if mod._partyGeomDirtyInCombat then
            mod._partyGeomDirtyInCombat = nil
            if mod._ApplyPartyContainerGeometry then mod._ApplyPartyContainerGeometry() end
        end
        -- Flush any power show/hide transitions deferred during combat (see UpdateButton);
        -- only the buttons actually marked dirty get a repaint.
        if mod._powerDirtyInCombat then
            mod._powerDirtyInCombat = nil
            for _, button in ipairs(allButtons) do
                local skinData = GetFFD(button)
                if skinData._powerDirtyInCombat then
                    skinData._powerDirtyInCombat = nil
                    UpdateButton(button)
                end
            end
            if mod._partyAllButtons then
                for _, button in ipairs(mod._partyAllButtons) do
                    local skinData = GetFFD(button)
                    if skinData._powerDirtyInCombat then
                        skinData._powerDirtyInCombat = nil
                        UpdateButton(button)
                    end
                end
            end
        end
        -- Restore child frame levels after a deferred strata change. A Party
        -- Frames kit or party portrait geometry write blocked in combat (a
        -- Frame Scale or portrait change through a combat-time refresh) needs
        -- the same full party pass: it re-sizes the buttons, re-runs the kit
        -- and portrait passes and relays the slots.
        local kitDirty = mod._partyKitDirtyInCombat
        mod._partyKitDirtyInCombat = nil
        if frameStrataDirty then
            if not (sizeTierDirty and framesVisible) then ReloadFrames() end
            if mod.ReloadPartyFrames then mod.ReloadPartyFrames() end
            -- The re-stack reset the child levels the Color Custom Borders copies took at
            -- their last restyle, which ran in combat before the strata applied; the
            -- fingerprint-gated reload above will not restyle them again.
            local AK = CUI.AuraKit
            if AK and AK.RestyleSoon then
                AK.RestyleSoon("rf:dispel:raid")
                AK.RestyleSoon("rf:dispel:party")
                AK.RestyleSoon("rf:dispel:extra")
            end
        elseif kitDirty and mod.ReloadPartyFrames then
            mod.ReloadPartyFrames()
        end
        -- Pet frames: the roster changes and applies deferred through combat, after the layout above.
        mod.PF_Flush()
    elseif evt == "ENCOUNTER_START" then
        -- Drives the raid/party frame "Out of Boss Combat" tooltip mode (read in
        -- the frame OnEnter via ns._inBossCombat).
        mod._inBossCombat = true
    elseif evt == "ENCOUNTER_END" then
        mod._inBossCombat = false
    elseif evt == "PLAYER_ROLES_ASSIGNED" then
        -- Roles changed: refresh raid sort so the player's-group nameList
        -- (Show Self First) re-orders the rest by the new roles. The other
        -- groups re-sort natively. Out of combat only; no-op if order unchanged.
        if not inCombat and framesVisible and mod._ApplySortToHeaders then mod._ApplySortToHeaders() end
        -- Party Prioritize Class and the arena self-order nameList are both
        -- role-aware, so a role change must rebuild them (native role sort
        -- updates itself; these do not). FrameSort's list is role-aware too.
        if
            not inCombat
            and mod._partyFramesVisible
            and (saved.profile.partyPrioritizeClass or mod._PartyInRaid() or mod._FsPartyMode())
            and mod._LayoutPartyFrames
        then
            mod._LayoutPartyFrames()
        end
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PARTY_LEADER_CHANGED" then
        -- Unit tokens reindex on roster changes; a latched rez offer keyed by the
        -- old token would paint on the wrong player, so drop them all.
        if evt == "GROUP_ROSTER_UPDATE" then
            wipe(mod._rezPend)
            -- Pet frames: flushed once by the roster pass below, or at combat end.
            mod.PF_MarkDirty()
        end
        -- InCombatLockdown too: a /reload in combat never sees PLAYER_REGEN_DISABLED.
        if inCombat or InCombatLockdown() then
            mod._rosterDirtyInCombat = true
            -- The visibility drivers show and hide the containers on their own;
            -- bring the Lua side (event gates, maps, tickers) in step first.
            mod._RFCombatVisEdge()
            -- Check if size tier changed during combat (deferred to REGEN)
            local numMembers = mod._GetEffectiveRaidSize()
            if numMembers > 0 then
                local newW, newH = mod._GetRaidSizeFrameDimensions(numMembers)
                if newW ~= mod._activeSizeW or newH ~= mod._activeSizeH then
                    mod._sizeTierDirtyInCombat = true
                end
                local _, newOv = mod._RFResolveTierOverride(numMembers)
                if newOv ~= mod._activeTierOverride then mod._sizeTierDirtyInCombat = true end
            end
            -- Rebuild unit maps during combat so new/moved members get events.
            if framesVisible then
                wipe(unitToButton)
                for _, button in ipairs(allButtons) do
                    if button:IsVisible() then
                        local u = button:GetAttribute("unit")
                        if u then
                            local skinData = GetFFD(button)
                            -- Extra Frames duplicates never own a map slot
                            if not skinData._isExtra then unitToButton[u] = button end
                            local _, classToken = UnitClass(u)
                            skinData.classToken = classToken
                        end
                    end
                end
            end
            -- Party frames: rebuild unit map during combat
            if mod._partyFramesVisible then
                wipe(mod._partyUnitToButton)
                for _, button in ipairs(mod._partyAllButtons) do
                    if button:IsVisible() then
                        local u = button:GetAttribute("unit")
                        if u then
                            mod._partyUnitToButton[u] = button
                            local skinData = GetFFD(button)
                            local _, classToken = UnitClass(u)
                            skinData.classToken = classToken
                        end
                    end
                end
                -- The self button's unit never changes, so no assignment remaps it
                -- when the driver shows the container a tick after this pass; its
                -- own shown flag (set out of combat) says whether it owns the player.
                local scrollBar = mod._partySelfButton
                if scrollBar and scrollBar:IsShown() then mod._partyUnitToButton.player = scrollBar end
            end
            -- Combat zone-ins deliver GROUP_ROSTER_UPDATE in storms; unit maps stay
            -- per-fire (routing must be correct immediately) but the paint coalesces to
            -- one next-frame pass reading the storm's FINAL state (same NewTimer(0)
            -- shape as the OOC branch). Paint work is unprotected, so this is combat-safe.
            if not mod._crPaintTimer and (framesVisible or mod._partyFramesVisible) then
                mod._rosterArmAt = GetTime()
                mod._crPaintTimer = C_Timer.NewTimer(0, function()
                    mod._crPaintTimer = nil
                    if framesVisible then
                        for _, button in ipairs(allButtons) do
                            local u = button:GetAttribute("unit")
                            if u and button:IsVisible() then
                                mod._RosterPassPaint(button, u)
                                mod._UpdateButtonRange(u, button)
                            end
                        end
                    end
                    if mod._partyFramesVisible then
                        for _, button in ipairs(mod._partyAllButtons) do
                            local u = button:GetAttribute("unit")
                            if u and button:IsVisible() then
                                mod._RosterPassPaint(button, u)
                                mod._UpdateButtonRange(u, button)
                            end
                        end
                    end
                end)
            end
            return
        end
        if mod._rosterUpdateTimer then
            mod._rosterUpdateTimer:Cancel()
        else
            -- First event of this cycle: paints stamped at or after this instant
            -- came from the assignment hook (or a full pass) inside the cycle.
            mod._rosterArmAt = GetTime()
        end
        mod._rosterUpdateTimer = C_Timer.NewTimer(0, function()
            mod._rosterUpdateTimer = nil
            -- Roster changed (OOC): never force UpdateVisibility's full 40-button
            -- rebuild. The per-button OnAttributeChanged hook already fully repainted
            -- (incl. auras) every reassigned button, so a blanket x40 aura re-scan is
            -- redundant; react per-unit instead. UpdateButton still runs on every visible
            -- button (no aura rescan) so leader/role/marker/health stay correct for
            -- UNCHANGED-token units (e.g. a new leader whose token didn't change).
            local numMembers = mod._GetEffectiveRaidSize()
            local newW, newH = mod._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
            local tierChanged = (newW ~= mod._activeSizeW or newH ~= mod._activeSizeH)
            -- Same-sized tiers can still differ in growth or Center Groups (the
            -- combat path checks this too); ReloadFrames re-resolves the override.
            if not tierChanged and numMembers > 0 then
                local _, newOv = mod._RFResolveTierOverride(numMembers)
                tierChanged = newOv ~= mod._activeTierOverride
            end
            local wasVis = framesVisible
            mod._visForceRebuild = nil
            UpdateVisibility()
            mod._UpdatePartyVisibility()
            -- A hidden->visible transition needs nothing more here: UpdateVisibility
            -- already laid the headers out and ran the full rebuild (RebuildUnitMap +
            -- UpdateAllButtons).
            if framesVisible then
                if tierChanged then
                    -- Tier changed: full reload (recalculates _activeSizeW/H, restyles).
                    ReloadFrames()
                    if mod.UpdatePowerEventRegistration then mod.UpdatePowerEventRegistration() end
                elseif wasVis then
                    -- Already visible, same tier: light refresh only. Aura
                    -- full-rescans are intentionally skipped (hook + UNIT_AURA
                    -- keep them current); the per-button pass repaints only what
                    -- the roster can change (see ns._RosterPassPaint).
                    RebuildUnitMap()
                    if mod.UpdatePowerEventRegistration then mod.UpdatePowerEventRegistration() end
                    for _, button in ipairs(allButtons) do
                        local u = button:GetAttribute("unit")
                        if u and button:IsVisible() then mod._RosterPassPaint(button, u) end
                    end
                    LayoutGroups()
                end
            end
            -- Re-derive the growth-corner anchor after any roster-driven layout.
            -- tierChanged only compares frame DIMENSIONS, so two same-sized tiers (fresh
            -- tiers copy the base 20-man size) take the bare-LayoutGroups branches even
            -- with different offsets/growth -- without this, a roster that refined from
            -- an early undercount (streaming subgroup data at join) stuck the container on
            -- the small-tier position until the next full reload. Cheap, idempotent,
            -- self-gates on combat. Deliberately OUTSIDE framesVisible: a raid left mid-
            -- combat still needs the dormant container re-based (it re-derives its own
            -- size while hidden) or unlock mode saves against stale raid-tier geometry.
            if mod._ApplyTierOffset then mod._ApplyTierOffset() end
            if mod._partyFramesVisible then mod._LayoutPartyFrames() end
            RebuildHealerManaIfFramesHidden()
            -- Pet frames: once per roster pass, after the groups they attach to are laid out.
            mod.PF_Flush()
        end)
    elseif evt == "UNIT_PORTRAIT_UPDATE" or evt == "PORTRAITS_UPDATED" or evt == "UNIT_MODEL_CHANGED" then
        -- Party Frames kit / party portrait only (registered while the party
        -- frames are shown with a portrait that needs them; the model event
        -- for a 3D portrait alone). Matched on each party button's unit
        -- attribute, never the routing map: a portrait is a sticky paint,
        -- and the map keeps stale tokens.
        local entries = mod._partyAllButtons
        for index = 1, #entries do
            local widget = entries[index]
            local u = widget:GetAttribute("unit")
            if u and (arg1 == nil or u == arg1) then
                local edge = GetFFD(widget)
                if (edge.kitPortrait or edge.pt) and UnitExists(u) then mod.RF_PtPaint(edge, u, evt) end
            end
        end
    elseif not framesVisible and not mod._partyFramesVisible then
        -- Skip all per-unit event processing when no frames are visible
        return
    elseif evt == "UNIT_IN_RANGE_UPDATE" then
        -- Standard ~40yd range change for this unit (event-driven, debounced).
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            mod._UpdateButtonRange(arg1, button)
            -- A 3D party portrait showing the out-of-sight question mark:
            -- a member coming into range is in sight again.
            if mod._ptModelEv then
                local edge = GetFFD(button)
                local pt = edge.pt
                if pt and pt._state == false then mod.RF_PtPaint(edge, arg1, "Probe") end
            end
        end
    elseif evt == "UNIT_PHASE" then
        -- Phasing doesn't fire UNIT_IN_RANGE_UPDATE; re-evaluate all (rare).
        if mod._RangeSeedAll then mod._RangeSeedAll() end
    elseif evt == "UNIT_POWER_UPDATE" then
        -- Healer Mana Display rides the same per-unit registration: one hash
        -- lookup when off/empty, one text repaint when this unit has a row.
        local hmRows = mod._hmUnitRows
        if hmRows and hmRows[arg1] then mod._HMUpdateValue(arg1) end
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        local skinData = button and GetFFD(button)
        if skinData and skinData.power then
            -- Value only (Blizzard's CompactUnitFrame_UpdatePower shape): type,
            -- color and bounds belong to the UNIT_DISPLAYPOWER edge below; nil
            -- = not derived yet for this occupant, derive once.
            local pType = skinData._pwType
            if pType == nil then
                mod._RFPowerTypeEdge(skinData, arg1)
                pType = skinData._pwType
            end
            -- Percent-based, secret-safe (see UpdateButton power block).
            local ppct = UnitPowerPercent(arg1, pType, true, CurveConstants.ScaleTo100)
            skinData.power:SetValue(ppct)
            -- Power Texts and the Custom texts reading power ride the same value
            -- (two field reads while the button has neither).
            local tp = skinData._txP
            if tp and (skinData._pwtOn or tp.reads) then mod.RF_TextPower(skinData, arg1, ppct, pType) end
        end
    elseif evt == "UNIT_DISPLAYPOWER" then
        -- The displayed power type changed (forms, spec swaps, vehicles):
        -- re-derive type + color + bounds once (Power Text's colour too), then push the value.
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        local skinData = button and GetFFD(button)
        if skinData and skinData.power then
            mod._RFPowerTypeEdge(skinData, arg1)
            local ppct = UnitPowerPercent(arg1, skinData._pwType, true, CurveConstants.ScaleTo100)
            skinData.power:SetValue(ppct)
            local tp = skinData._txP
            if tp and (skinData._pwtOn or tp.reads) then
                mod.RF_TextPower(skinData, arg1, ppct, skinData._pwType)
            end
        end
    elseif evt == "UNIT_NAME_UPDATE" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        -- The name arriving is also when the class becomes known (Blizzard's
        -- own comment on this edge): drop the cached class token first.
        if button then
            GetFFD(button)._clsTok = nil
            UpdateButton(button)
        end
        -- NAMELIST-driven headers (party Prioritize Class, raid Show Self
        -- First) are built from member names. A member whose name populated
        -- late, or changed since the build, sits under the trailing
        -- placeholder token (sorted last) or, when the builder bailed, in
        -- native order. Rebuild the lists now that the real name exists
        -- (debounced: names resolve in bursts after a loading screen) so the
        -- proper order returns once the last name lands.
        if inCombat then
            mod._rosterDirtyInCombat = true
        else
            if mod._nameUpdateTimer then mod._nameUpdateTimer:Cancel() end
            mod._nameUpdateTimer = C_Timer.NewTimer(0.1, function()
                mod._nameUpdateTimer = nil
                if InCombatLockdown() then
                    mod._rosterDirtyInCombat = true
                    return
                end
                if
                    mod._partyFramesVisible
                    and (saved.profile.partyPrioritizeClass or mod._PartyInRaid() or mod._FsPartyMode())
                    and mod._LayoutPartyFrames
                then
                    mod._LayoutPartyFrames()
                end
                if framesVisible and mod._ApplySortToHeaders then mod._ApplySortToHeaders() end
            end)
        end
    elseif evt == "UNIT_LEVEL" then
        -- Level only (registered while a view shows it): the name and level texts repaint.
        local button = unitToButton[arg1]
        if button then mod._RFRepaintLevel(button) end
        button = mod._partyUnitToButton[arg1]
        if button then mod._RFRepaintLevel(button) end
    elseif evt == "UNIT_TARGET" then
        -- Custom texts showing [target] only (registered while a view's Custom text does).
        local button = unitToButton[arg1]
        if button then mod.RF_TextRepaintCustom(GetFFD(button), arg1, "tgt") end
        button = mod._partyUnitToButton[arg1]
        if button then mod.RF_TextRepaintCustom(GetFFD(button), arg1, "tgt") end
    elseif evt == "UNIT_THREAT_LIST_UPDATE" or evt == "UNIT_THREAT_SITUATION_UPDATE" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            local skinData = GetFFD(button)
            mod.RF_PaintThreat(
                skinData,
                skinData._isParty and mod._scaledPartyProxy
                    or (skinData._isExtra and mod._scaledExtraProxy)
                    or mod._scaledProfile,
                arg1
            )
        end
    elseif evt == "UNIT_FLAGS" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then mod._UpdateCombatIconFor(arg1, button) end
    elseif evt == "PLAYER_FLAGS_CHANGED" or evt == "UNIT_CONNECTION" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then
            if evt == "UNIT_CONNECTION" then GetFFD(button)._clsTok = nil end
            UpdateButton(button)
            -- Connection changes don't fire UNIT_IN_RANGE_UPDATE; re-evaluate
            -- range so offline units take their fixed alpha and reconnecting
            -- units return to the normal out-of-range fade.
            if evt == "UNIT_CONNECTION" then mod._UpdateButtonRange(arg1, button) end
        end
        -- The member's pet frame, when one shows.
        if evt == "UNIT_CONNECTION" then mod._PF_OwnerRange(arg1) end
    elseif evt == "PARTY_MEMBER_ENABLE" or evt == "PARTY_MEMBER_DISABLE" then
        -- Only status text / health color changes (online/offline). The payload
        -- names the unit: repaint its button(s) alone. The full sweeps remain the
        -- fallback for a unit no button maps yet (token shape we do not route).
        local button = arg1 and (unitToButton[arg1] or mod._partyUnitToButton[arg1])
        if button then
            local pv = GetFFD(button)._isParty and mod._partyPvActive
            if not pv and button:IsVisible() then UpdateButton(button) end
            local xf = mod._xfUnitToButton[arg1]
            if xf and xf:IsVisible() then UpdateButton(xf) end
        else
            for _, btn in ipairs(allButtons) do
                local u = btn:GetAttribute("unit")
                if u and btn:IsVisible() then UpdateButton(btn) end
            end
            if not mod._partyPvActive then
                for _, btn in ipairs(mod._partyAllButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then UpdateButton(btn) end
                end
            end
        end
    elseif evt == "RAID_TARGET_UPDATE" then
        mod._UpdateRaidMarkers()
    elseif evt == "PLAYER_TARGET_CHANGED" then
        mod._UpdateTargetBorders()
    elseif evt == "READY_CHECK" then
        SetReadyCheckActive(true)
        for _, button in ipairs(allButtons) do
            local u = button:GetAttribute("unit")
            if u and button:IsVisible() then UpdateReadyCheck(button, u) end
        end
        for _, button in ipairs(mod._partyAllButtons) do
            local u = button:GetAttribute("unit")
            if u and button:IsVisible() then UpdateReadyCheck(button, u) end
        end
    elseif evt == "READY_CHECK_CONFIRM" then
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button then UpdateReadyCheck(button, arg1) end
    elseif evt == "READY_CHECK_FINISHED" then
        SetReadyCheckActive(false)
        C_Timer.After(5, function()
            if not readyCheckActive then
                -- Re-evaluate rather than force-hide: a unit may have an incoming
                -- summon active that shares the same texture.
                for _, button in ipairs(allButtons) do
                    local u = button:GetAttribute("unit")
                    if u and button:IsVisible() then UpdateReadyCheck(button, u) end
                end
                for _, button in ipairs(mod._partyAllButtons) do
                    local u = button:GetAttribute("unit")
                    if u and button:IsVisible() then UpdateReadyCheck(button, u) end
                end
            end
        end)
    elseif evt == "INCOMING_SUMMON_CHANGED" then
        -- Broadcast event (no unit payload); re-evaluate every visible button.
        for _, button in ipairs(allButtons) do
            local u = button:GetAttribute("unit")
            if u and button:IsVisible() then UpdateReadyCheck(button, u) end
        end
        for _, button in ipairs(mod._partyAllButtons) do
            local u = button:GetAttribute("unit")
            if u and button:IsVisible() then UpdateReadyCheck(button, u) end
        end
    elseif evt == "INCOMING_RESURRECT_CHANGED" then
        -- Fires with a unit payload when a rez starts/stops on that unit. The stop
        -- edge on a still-dead unit that was being cast on latches the offer window
        -- (ns._RFRezShown keeps the icon up until accept/expiry); the single-shot
        -- timer is the only thing that repaints an untouched corpse at expiry.
        if arg1 then
            if UnitHasIncomingResurrection(arg1) then
                mod._rezPend[arg1] = true
            elseif mod._rezPend[arg1] == true then
                if UnitIsDeadOrGhost(arg1) then
                    local exp = GetTime() + 60
                    mod._rezPend[arg1] = exp
                    local unitToken = arg1
                    C_Timer.After(60.1, function()
                        if mod._rezPend[unitToken] ~= exp then return end
                        mod._rezPend[unitToken] = nil
                        local widget = unitToButton[unitToken] or mod._partyUnitToButton[unitToken]
                        if widget and widget:IsVisible() then
                            if mod._UpdateButtonHealth then mod._UpdateButtonHealth(widget) end
                            UpdateReadyCheck(widget, unitToken)
                        end
                    end)
                else
                    mod._rezPend[arg1] = nil
                end
            end
        end
        -- Refresh the status text (so DEAD hides while rezzing / reappears after)
        -- as well as the shared rez icon.
        local button = unitToButton[arg1] or mod._partyUnitToButton[arg1]
        if button and button:IsVisible() then
            if mod._UpdateButtonHealth then mod._UpdateButtonHealth(button) end
            UpdateReadyCheck(button, arg1)
        end
    elseif evt == "PLAYER_SPECIALIZATION_CHANGED" then
        if mod.BM_RebuildLookup then mod.BM_RebuildLookup(saved) end
        -- The player's effective role is spec-derived (CludesUI.UnitEffectiveRole),
        -- so the player's own spec swap is a role change for every role consumer:
        -- mirror the PLAYER_ROLES_ASSIGNED refresh and repaint role icons. The
        -- event also fires for other units' spec updates; only the player's
        -- changes our answers.
        if arg1 == "player" and not inCombat then
            if framesVisible and mod._ApplySortToHeaders then mod._ApplySortToHeaders() end
            if
                mod._partyFramesVisible
                and (saved.profile.partyPrioritizeClass or mod._PartyInRaid() or mod._FsPartyMode())
                and mod._LayoutPartyFrames
            then
                mod._LayoutPartyFrames()
            end
            if mod._UpdateRoleIcons then mod._UpdateRoleIcons() end
        end
    elseif evt == "PLAYER_DIFFICULTY_CHANGED" then
        -- Hide Groups 5-8 in Mythic Raid (heard only while on): a switch inside
        -- the raid (e.g. Heroic -> Mythic) against the set the layout applied.
        if (mod._VisibleGroups() == mod._mythicGroups) ~= (mod._rfLaidMythic == true) then
            if InCombatLockdown() then
                mod._sizeTierDirtyInCombat = true -- REGEN runs the full reload
            elseif framesVisible then
                ReloadFrames()
            end
        end
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Re-sync the boss-combat flag on load. IsEncounterInProgress() still
        -- reports an active encounter after a mid-fight /reload or zone (where
        -- ENCOUNTER_START already fired and will not fire again), so "Out of Boss
        -- Combat" keeps suppressing; otherwise this clears a stale flag from a
        -- missed ENCOUNTER_END so tooltips are not stuck hidden.
        mod._inBossCombat = (IsEncounterInProgress and IsEncounterInProgress()) or false
        -- 3D party portraits: a world transition can reset a model at the
        -- same guid.
        if mod._ptModelEv and mod.RF_PtRepaintAll then mod.RF_PtRepaintAll("PLAYER_ENTERING_WORLD") end
        C_Timer.After(0.5, function()
            -- Pet frames: flushed at the end of this settle, or at combat end.
            mod.PF_MarkDirty()
            -- Zoning in mid-combat (e.g. into a raid where trash is already
            -- pulled) must NOT run the reload here: ReloadFrames calls SetSize on
            -- the protected SecureGroupHeader buttons, which Blizzard blocks in
            -- combat (ADDON_ACTION_BLOCKED). Defer the full reload to combat end
            -- via the existing size-tier dirty flag; PLAYER_REGEN_ENABLED re-runs
            -- UpdateVisibility + ReloadFrames + the party layout once it is safe.
            -- The other calls below already self-bail in combat, so skipping them
            -- until REGEN is behavior-neutral.
            if InCombatLockdown() then
                mod._sizeTierDirtyInCombat = true
                return
            end
            -- Entering or leaving a Mythic raid with Hide Groups 5-8 on changes which groups
            -- show even when the tier holds; read before UpdateVisibility can re-lay them.
            local mythicChanged = (mod._VisibleGroups() == mod._mythicGroups) ~= (mod._rfLaidMythic == true)
            UpdateVisibility()
            mod._UpdatePartyVisibility()
            if framesVisible then
                -- Full reload ONLY when the size tier actually changed across the zone
                -- -- recalculating tier dimensions is this call's whole purpose, and
                -- with the tier unchanged the restyle would re-derive identical values
                -- on every button. The unchanged path heals just what zoning can
                -- invalidate: private-aura anchor geometry (baked in at registration;
                -- the unit-guarded rebuild paths skip re-registration when tokens are
                -- unchanged), range alpha, and the boss/extra inheritors. Content
                -- staleness is covered by the per-unit event storm that follows every
                -- zone-in (the same model the roster path documents above).
                local numMembers = mod._GetEffectiveRaidSize()
                local newW, newH = mod._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
                local tierChanged = (newW ~= mod._activeSizeW or newH ~= mod._activeSizeH)
                if not tierChanged and numMembers > 0 then
                    local _, newOv = mod._RFResolveTierOverride(numMembers)
                    if newOv ~= mod._activeTierOverride then tierChanged = true end
                end
                if tierChanged or mythicChanged then
                    ReloadFrames()
                else
                    RangeUpdate()
                    if mod.FB_Apply then mod.FB_Apply() end
                    if mod.XF_Apply then mod.XF_Apply() end
                end
            end
            if mod._partyFramesVisible then
                -- Full party reload (not just layout), mirroring the raid branch above:
                -- private aura anchors registered during the loading screen can carry
                -- stale geometry (icon size / border scale are baked in at
                -- registration), and the unit-guarded rebuild paths skip
                -- re-registration when units are unchanged. ReloadPartyFrames
                -- recomputes the Auto Resize scale and re-registers every anchor.
                mod.ReloadPartyFrames()
            end
            -- A tier reload above has already applied the pets; otherwise they apply once here.
            mod.PF_Flush()
        end)
    end
end

Inner.OnEvent = OnEvent
Inner.broken = false
