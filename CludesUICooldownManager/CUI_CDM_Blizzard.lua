if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Blizzard.lua
--
--  Blizzard viewer lists and fonts, position capture, Edit Mode enforcement,
--  hiding and restoring the Blizzard Cooldown Manager.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ECME, FC, _ecmeFC, cdmBarFrames = Inner.ECME, Inner.FC, Inner._ecmeFC, Inner.cdmBarFrames

-------------------------------------------------------------------------------
--  CDM Bars: Our replacement for Blizzard's Cooldown Manager
--  Captures Blizzard positions on first login, then creates our own bars.
-------------------------------------------------------------------------------
local function GetCDMFont()
    return CludesUI.GetFontPath("cdm")
end
local function SetBlizzCDMFont(fontStr, font, size, red, green, blue)
    if not (fontStr and fontStr.SetFont) then
        return
    end
    CludesUI.ApplyIconTextFont(fontStr, font, size, "cdm")
    if red then
        fontStr:SetTextColor(red, green, blue)
    end
end

-- Blizzard CDM frame names
local BLIZZ_CDM_FRAMES = {
    cooldowns = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffs = "BuffIconCooldownViewer",
}

-- BuffBarCooldownViewer is Blizzard's buff bar strip, hidden alongside the icon viewer so
-- the default buff display is fully suppressed when CDM hiding is on. Our Tracked Buff Bars replace it.
local BLIZZ_CDM_FRAMES_SECONDARY = {
    buffs = "BuffBarCooldownViewer",
}

-- CDM category numbers per bar key (for C_CooldownViewer API)
local CDM_BAR_CATEGORIES = {
    cooldowns = { 0, 1 }, -- Essential + Utility
    utility = { 0, 1 }, -- Essential + Utility
    buffs = { 2, 3 }, -- Tracked Buff + Tracked Debuff
}

-- Maximum number of custom bars a user can create
local MAX_CUSTOM_BARS = 20

-- Forward declarations
local HideBlizzardCDM, RestoreBlizzardCDM
local CaptureCDMPositions

-------------------------------------------------------------------------------
--  Capture Blizzard CDM positions (first login only)
-------------------------------------------------------------------------------
CaptureCDMPositions = function()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    for barId, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local widget = _G[frameName]
        if widget then
            local payload = {}

            -- Read the frame's scale (used to adjust icon size capture)
            local frameScale = widget:GetScale()
            if not frameScale or frameScale < 0.1 then
                frameScale = 1
            end

            -- Icon size + spacing from child icons. Blizzard CDM icons have a base size plus a
            -- per-icon scale driven by the IconSize percentage slider; spacing is the gap between two adjacent visible icons in parent coordinates.
            local numDistinctY = {}
            local shownIcons = {}
            local children = { widget:GetChildren() }
            for ci = 1, #children do
                local childFrame = children[ci]
                if childFrame and childFrame.Icon then
                    local cw = childFrame:GetWidth()
                    local cs = childFrame:GetScale()
                    if cw and cw > 1 and not payload.iconSize then
                        local visual = cw * (cs or 1)
                        payload.iconSize = math.floor(visual + 0.5)
                    end
                    -- Collect shown icons for spacing measurement
                    if childFrame:IsShown() then
                        shownIcons[#shownIcons + 1] = childFrame
                        -- Track distinct Y positions for row counting
                        if childFrame:GetPoint(1) then
                            local _, _, _, _, cy = childFrame:GetPoint(1)
                            if cy then
                                numDistinctY[math.floor(cy + 0.5)] = true
                            end
                        end
                    end
                end
            end

            if #shownIcons >= 2 and payload.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(lhs, rhs)
                    return (lhs:GetLeft() or 0) < (rhs:GetLeft() or 0)
                end)
                -- Smallest step between consecutive sorted icons. GetLeft() returns UIParent-coordinate-space values.
                local bestStep = nil
                for si = 1, #shownIcons - 1 do
                    local aLeft = shownIcons[si]:GetLeft()
                    local bLeft = shownIcons[si + 1]:GetLeft()
                    if aLeft and bLeft then
                        local dist = bLeft - aLeft
                        if dist > 0 and (not bestStep or dist < bestStep) then
                            bestStep = dist
                        end
                    end
                end
                if bestStep then
                    -- bestStep is UIParent coords; the icon-parent -> UIParent multiplier is
                    -- frame.effectiveScale / UIParent.effectiveScale, so divide for frame coords.
                    -- Frame positions use cw units while iconSize = cw * cs (visual), so multiply by cs for the step in iconSize units.
                    local frameEff = widget:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    local cs = shownIcons[1]:GetScale() or 1
                    local stepInIconUnits = parentStep * cs
                    local gap = stepInIconUnits - payload.iconSize
                    if gap < 0 then
                        gap = 0
                    end
                    payload.spacing = math.floor(gap + 0.5)
                end
            end

            -- Rows: count distinct Y positions among visible icon children
            local rowCount = 0
            for _ in pairs(numDistinctY) do
                rowCount = rowCount + 1
            end
            if rowCount >= 1 then
                payload.numRows = rowCount
            end

            if widget.isHorizontal ~= nil then
                payload.isHorizontal = widget.isHorizontal
            end

            -- Position (center-based, in UIParent coordinates)
            if widget:GetPoint(1) then
                local cx, cy = widget:GetCenter()
                if cx and cy then
                    local bScale = widget:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    payload.point = "CENTER"
                    payload.relPoint = "CENTER"
                    payload.x = cx - (uiW / 2)
                    payload.y = cy - (uiH / 2)
                end
            end

            captured[barId] = payload
        end
    end

    return captured
end

-------------------------------------------------------------------------------
--  EnforceCooldownViewerEditModeSettings (one-shot)
--  Runs ONCE on init to force Edit Mode settings so Blizzard's hideWhenInactive/visibility
--  modes can't interfere with CDM's frame management:
--    - VisibleSetting = Always on ALL viewers
--    - HideWhenInactive = 1 on buff viewers (BuffIcon + BuffBar)
--  SaveLayouts is called at most once, during init, NEVER at runtime: a SaveLayouts-triggered layout reapply from addon code taints Blizzard frame properties (isActive, etc.).
-------------------------------------------------------------------------------
local _editModePolicyApplied = false

-- Shown when our automatic save did NOT take (see the loop breaker below). Dismissable, and
-- deliberately repeats every login until the layout is correct: going quiet would leave CDM
-- misbehaving unexplained. CDM must be OFF while the user follows the steps -- this addon hides
-- Blizzard's cooldown viewers, and a hidden system cannot be selected in Edit Mode; the confirm
-- button does that step. Step 6 lives in the text because once CDM is disabled nothing of ours runs to remind them to re-enable it.
local function ShowManualEditModeFixPopup()
    C_Timer.After(0, function()
        if not (CludesUI and CludesUI.ShowConfirmPopup) then
            return
        end
        CludesUI:ShowConfirmPopup({
            title = "Edit Mode Needs a Manual Fix",
            message = "CludesUI could not save this change to your Edit Mode layout, so it has to be set by hand. The Cooldown Manager has to be off while you do it, because it hides Blizzard's cooldown viewers and a hidden viewer cannot be selected in Edit Mode.\n\n"
                .. "1. Disable CludesUI Cooldown Manager (button below).\n"
                .. "2. Open Edit Mode from the Game Menu.\n"
                .. "3. Select each Cooldown Manager viewer and set Visibility to Always.\n"
                .. "4. On Tracked Buffs and Tracked Bars, tick Hide When Inactive.\n"
                .. "5. Save the layout and leave Edit Mode.\n"
                .. "6. Re-enable CludesUI Cooldown Manager.",
            disclaimer = "This will keep appearing each login until the layout is correct.",
            confirmText = "Disable CDM & Reload",
            cancelText = "Not Now",
            reload = true,
            onConfirm = function()
                C_AddOns.DisableAddOn("CludesUICooldownManager")
            end,
        })
    end)
end

local function EnforceCooldownViewerEditModeSettings()
    if _editModePolicyApplied then
        return
    end
    if
        not (
            C_EditMode
            and C_EditMode.GetLayouts
            and C_EditMode.SaveLayouts
            and Enum
            and Enum.EditModeSystem
            and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting
            and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSystemIndices
        )
    then
        return
    end

    -- Presets merged first so the activeLayout index resolves correctly. Presets unresolved:
    -- activeLayout counts them, so without the merge it picks the WRONG layout below and the
    -- save hands the client a list its own index no longer fits.
    local layoutInfo, numPresets = CludesUI.EditModeLayoutsForSave()
    if not layoutInfo then
        return
    end

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then
        return
    end

    -- Preset layouts are read-only: SaveLayouts won't persist changes to them, which would
    -- loop enforce -> save -> reload forever (the preset resets next login). Skip enforcement for presets.
    if
        numPresets > 0
        and type(layoutInfo.activeLayout) == "number"
        and layoutInfo.activeLayout <= numPresets
    then
        -- Nothing to enforce on a preset: Always Show Buffs needs no layout change (it draws placeholder icons).
        _editModePolicyApplied = true
        return
    end

    local changed = false
    local cooldownSystem = Enum.EditModeSystem.CooldownViewer
    local visSetting = Enum.EditModeCooldownViewerSetting.VisibleSetting
    local visAlways = Enum.CooldownViewerVisibleSetting.Always
    local hideEnum = Enum.EditModeCooldownViewerSetting.HideWhenInactive
    local buffIconIdx = Enum.EditModeCooldownViewerSystemIndices.BuffIcon
    local buffBarIdx = Enum.EditModeCooldownViewerSystemIndices.BuffBar

    -- Returns changed(bool). A layout stores a CooldownViewer setting ONLY when changed away
    -- from Blizzard's default, so an absent entry means "at the default" (defaultValue). When
    -- that already equals what we want, leave the entry absent (no change, no forced reload); only add an explicit entry when default differs from desired.
    -- Each change is noted for Uninstall CUI (only the player's own earlier value is put
    -- back: these are Blizzard's defaults, so there is no fallback).
    local function UpsertSetting(sysInfo, settingEnum, desiredValue, defaultValue)
        local prefs = sysInfo.settings
        for _, s in ipairs(prefs) do
            if s.setting == settingEnum then
                if s.value ~= desiredValue then
                    CludesUI.NoteEditModeSetting(activeLayout, sysInfo, settingEnum, s.value, desiredValue)
                    s.value = desiredValue
                    return true
                end
                return false
            end
        end
        -- Absent: at the Blizzard default. Nothing to do if that already matches.
        if desiredValue == defaultValue then
            return false
        end
        CludesUI.NoteEditModeSetting(activeLayout, sysInfo, settingEnum, defaultValue, desiredValue)
        prefs[#prefs + 1] = { setting = settingEnum, value = desiredValue }
        return true
    end

    for _, sysInfo in ipairs(activeLayout.systems) do
        if sysInfo.system == cooldownSystem and type(sysInfo.settings) == "table" then
            -- VisibleSetting=Always on ALL viewers. That IS the default, so an absent entry is already correct and is left alone.
            if UpsertSetting(sysInfo, visSetting, visAlways, visAlways) then
                changed = true
            end
            -- Both buff viewers keep Blizzard's default HideWhenInactive=1 (inactive entries
            -- stay hidden): Always Show Buffs is drawn by our own per-bar placeholder icons, NOT
            -- Blizzard's layout, so any stale HideWhenInactive=0 is reset. New installs are already at the default (no change, no reload).
            if sysInfo.systemIndex == buffIconIdx or sysInfo.systemIndex == buffBarIdx then
                if UpsertSetting(sysInfo, hideEnum, 1, 1) then
                    changed = true
                end
            end
        end
    end

    _editModePolicyApplied = true
    if not changed then
        -- Settled: the layout already carries what we want, so a previous save DID stick.
        -- Re-arm the loop breaker so a genuine future change (new layout, manual edit) still prompts.
        if CludesUIDB then
            CludesUIDB.cdmEditModeSavePending = nil
        end
        return
    end

    -- Save the corrected layout. Blizzard won't visually apply it until the next login/reload, so force a reload via popup.
    C_EditMode.SaveLayouts(layoutInfo)

    -- LOOP BREAKER: a forced reload only makes sense if the save persisted. If this exact
    -- correction was saved in a PREVIOUS session and the delta is STILL here, the save did not
    -- stick, so re-offering the same non-dismissable reload would trap the user every login.
    -- The forced reload is offered at most once per unresolved correction; after that the user
    -- gets manual instructions every login until the layout comes back clean. Flag clears itself
    -- in the not-changed branch above, so a working user pays nothing. Backstop, NOT the cure -- it stops the loop without knowing why the save failed.
    local savedLastSession = CludesUIDB and CludesUIDB.cdmEditModeSavePending
    if CludesUIDB then
        CludesUIDB.cdmEditModeSavePending = true
    end
    if savedLastSession then
        ShowManualEditModeFixPopup()
        return
    end

    -- Forced (non-dismissable) reload popup. On first install the Welcome picker is
    -- pending/open and ALWAYS ends in its own reload, which applies the layout we
    -- just saved -- a second forced popup would stomp the picker, so stay silent and ride that reload.
    if CludesUI and CludesUI._firstInstallPending then
        return
    end
    C_Timer.After(0, function()
        CludesUI:ShowConfirmPopup({
            title = "Edit Mode Update",
            message = "CludesUI has updated your CDM Edit Mode settings to ensure cooldown tracking works correctly.\n\nA UI reload is required for the changes to take effect.",
            confirmText = "Reload UI",
            reload = true,
            -- Forced: no cancel, no Escape, no click-outside dismiss.
            hideCancel = true,
            modal = true,
        })
    end)
end

-- One-time per-profile migration: the GLOBAL Always Show Buffs settings (cdmBars.showInactiveBuffIcons/
-- .desaturateInactiveBuffs) become PER-BAR fields; a profile with the global ON turns every buff bar ON.
-- Runs once per profile (flag on cdmBars); re-runs on swap to a pre-migration profile, which carries no flag.
function mod.MigrateAlwaysShowBuffsToPerBar()
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars or profile.cdmBars._asbPerBarMigrated then
        return
    end
    profile.cdmBars._asbPerBarMigrated = true
    local oldOn = profile.cdmBars.showInactiveBuffIcons
    local oldDesat = profile.cdmBars.desaturateInactiveBuffs
    if oldOn == nil and oldDesat == nil then
        return
    end
    if type(profile.cdmBars.bars) ~= "table" then
        return
    end
    for _, edge in ipairs(profile.cdmBars.bars) do
        if edge.barType == "buffs" then
            if oldOn ~= nil then
                edge.showInactiveBuffIcons = oldOn and true or false
            end
            if oldDesat ~= nil then
                edge.desaturateInactiveBuffs = oldDesat
            end
        end
    end
end

-- One-time per-profile migration: the custom_buff ("Auras") bar type merged into the buff
-- family. Converts every custom_buff bar to "buffs" in place -- key, assignedSpells,
-- spellDurations, customSpellIDs, position and all visual settings carry over unchanged. The
-- buff phase injects the same cast-timer custom buffs, so a converted bar behaves as an extra
-- buff-family bar (its key stays custom_*, never "buffs"). Same once-per-profile contract as
-- above. MUST run AFTER MigrateAlwaysShowBuffsToPerBar so the old global Always-Show value only lands on original buff bars, not converted Auras bars.
function mod.MigrateCustomBuffBarsToBuffBars()
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars or profile.cdmBars._customBuffMergedV1 then
        return
    end
    profile.cdmBars._customBuffMergedV1 = true
    if type(profile.cdmBars.bars) ~= "table" then
        return
    end
    for _, edge in ipairs(profile.cdmBars.bars) do
        if edge.barType == "custom_buff" then
            edge.barType = "buffs"
        end
    end
end

-------------------------------------------------------------------------------
--  Hide / Restore Blizzard CDM
-------------------------------------------------------------------------------

-- Suppress the secondary buff-bar viewer (BuffBarCooldownViewer).
--
-- Parked off the top-left (or clamped into that corner), NEVER Hidden: TBB mirrors
-- min/max/value straight off Blizzard's Bar frames
-- and a hidden viewer stops updating them. The park, not the alpha, is what holds -- Blizzard's
-- hide-when-inactive fade animates the viewer's alpha back to 1 whenever a tracked buff goes
-- active, through a path no hook can see (same lesson as the unclaimed-frame park in
-- CollectAndReanchor). So once anything re-anchors the viewer to its Edit Mode position (layout
-- apply, SaveLayouts, zone-in), the next buff proc in combat draws Blizzard's bars over ours. The SetPoint hook makes the park self-healing, mirroring the unclaimed CD/utility pool frames' hook.
function mod.ParkSecondaryBuffViewer(widget)
    if not widget then
        return
    end
    local fc = FC(widget)
    widget:SetAlpha(0)
    if InCombatLockdown() then
        -- Flushed on PLAYER_REGEN_ENABLED.
        mod._secondaryParkPending = true
    else
        mod._secondaryParkPending = nil
        -- An Edit Mode system: the saved C methods keep its snap state and
        -- Edit Mode's anchor sweep Blizzard's, and never reach the hooks below.
        -- Known limit: a snap the player gave a viewer survives, so when Edit
        -- Mode breaks it (Blizzard hides a target sized to its children, such
        -- as the party, raid or boss container or another viewer; the target
        -- is reset or reverted; or it is a party, raid, boss or arena frame or
        -- the quest tracker at a save) it notes the viewer where it stands:
        -- this park, most likely clamped into the screen's top-left corner,
        -- or our bar's spot for the Essential and Utility viewers. Only the
        -- player's next Edit Mode save keeps it (renaming or deleting a layout
        -- saves too), and with our Cooldown Manager off Blizzard's tracked
        -- bars then show in that corner.
        CludesUI.ClearFramePoints(widget)
        CludesUI.SetFramePoint(widget, "TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    end
    if not fc.parkHooked then
        fc.parkHooked = true
        -- Deferred by a frame: Blizzard re-anchors this viewer inside its Edit Mode layout pass,
        -- which goes on to move protected systems (action bars); re-parking inline would carry
        -- our taint into the rest of that pass. The delay also coalesces ClearAllPoints + SetPoint bursts into one park, and a single frame of a stray bar is invisible.
        local function QueueRepark(self, method)
            local c = _ecmeFC[self]
            if not c or not c.hidden or c.restoring or c.parkQueued then
                return
            end
            c.parkQueued = true
            C_Timer.After(0, function()
                c.parkQueued = nil
                if c.hidden and not c.restoring then
                    mod.ParkSecondaryBuffViewer(self)
                end
            end)
        end
        hooksecurefunc(widget, "SetPoint", function(self)
            QueueRepark(self, "SetPoint")
        end)
        -- SetPoint is not the only way off the park: SetAllPoints and SetParent strand the
        -- viewer on screen without ever calling it, and nothing heals that until an unrelated SetPoint happens to fire.
        hooksecurefunc(widget, "SetAllPoints", function(self)
            QueueRepark(self, "SetAllPoints")
        end)
        hooksecurefunc(widget, "SetParent", function(self)
            QueueRepark(self, "SetParent")
        end)
    end
end

-- Park integrity check, edge-driven via ns._parkEdges below.
--
-- The hooks above cover the movers we can see; a scale change, a mover that swaps anchors
-- through an unhooked path, or the one-frame gap the deferred re-park leaves open all put
-- Blizzard's bars back on screen. This closes the loop from the other end: read where the
-- viewer actually IS and re-park. Position ONLY -- alpha is deliberately not checked, since
-- Blizzard's hide-when-inactive fade animates it back to 1 through a path no hook sees and re-asserting would fight that animation while the frame is offscreen anyway.
function mod.CheckSecondaryBuffViewerPark()
    local widget = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
    if not widget then
        return
    end
    local fc = _ecmeFC[widget]
    if not fc or not fc.hidden or fc.restoring or fc.parkQueued then
        return
    end
    local pt, rel, relPt, posX, posY
    -- Indexing past the last point errors; an unanchored viewer counts as drifted and falls through to the re-park.
    if widget:GetNumPoints() > 0 then
        pt, rel, relPt, posX, posY = widget:GetPoint(1)
    end
    -- Tolerant compare: GetPoint round-trips through UI scale, so the stored -10000/10000 can
    -- read back with float drift, and a parent-anchored point can report its relative frame as
    -- nil. Exact equality fails every pass on scaled UIs, re-parking forever. Anywhere far offscreen top-left IS parked.
    if
        pt == "TOPLEFT"
        and (rel == UIParent or rel == nil)
        and relPt == "TOPLEFT"
        and posX
        and posX < -9990
        and posY
        and posY > 9990
    then
        return
    end
    -- In combat this re-asserts alpha 0 and defers the park itself; the frame is protected, so alpha is the only lever until PLAYER_REGEN_ENABLED.
    mod.ParkSecondaryBuffViewer(widget)
end

-- Park integrity for visibility-hidden cursor bars (edge-driven via ns._parkEdges below).
-- Their glue shells sleep while hidden, so a mover that strands one on-screen is healed here instead of by a per-frame OnUpdate. A parked bar costs two reads.
function mod._CheckCursorParks()
    for _, widget in pairs(cdmBarFrames) do
        if widget and widget._mouseTrack and widget._visHidden and (widget:GetLeft() or 0) > -9000 then
            widget._mouseParked = true
            widget:ClearAllPoints()
            widget:SetPoint(widget._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        end
    end
end

-- Edge-driven park integrity (NO polling patrols): hookable movers self-heal via the
-- QueueRepark hooksecurefuncs, LayoutCDMBar guards hidden cursor bars directly, and these are
-- the remaining un-hookable edges (scale changes and Edit Mode layout passes re-anchor Blizzard frames through paths no hook sees). A stale park beyond these is a missing edge to add here -- never a patrol.
mod._parkEdges = CreateFrame("Frame")
mod._parkEdges:RegisterEvent("UI_SCALE_CHANGED")
mod._parkEdges:RegisterEvent("DISPLAY_SIZE_CHANGED")
mod._parkEdges:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
mod._parkEdges:RegisterEvent("PLAYER_ENTERING_WORLD")
mod._parkEdges:SetScript("OnEvent", function()
    if mod.CheckSecondaryBuffViewerPark then
        mod.CheckSecondaryBuffViewerPark()
    end
    if mod._CheckCursorParks then
        mod._CheckCursorParks()
    end
end)

-------------------------------------------------------------------------------
--  Group loot rolls. Blizzard stacks GroupLootContainer in the bottom managed
--  column above the three Cooldown Manager viewers. Ours keeps them shown, so
--  while they sit in their default Edit Mode spot the column lifts the rolls
--  by whatever they measure (off screen behind a tall buff viewer). While our
--  CDM owns the viewers, the rolls take the lowest spot up from the column's
--  bottom, kept under the top of the screen, that covers none of these: a
--  shown column frame other than the viewers, a CDM bar, a Tracking Bar (or
--  Blizzard's tracked bars in their place), an CUI action bar, or the extra
--  ability container while it shows. Our bars count unless hidden for good,
--  so one that shows later never comes up under rolls already up. With
--  nothing else in the way that is Blizzard's spot with the viewers out of
--  the column. The viewers' sizes are never read. CludesUI.SetFramePlacer
--  applies the result; Blizzard frames are only read here.
-------------------------------------------------------------------------------
local lootL, lootB, lootR, lootT = {}, {}, {}, {}

local function AnySecret(...)
    for index = 1, select("#", ...) do
        if issecretvalue((select(index, ...))) then
            return true
        end
    end
    return false
end

-- Stores f's screen rect as obstacle n + 1 when it is readable and not empty;
-- returns the obstacle count.
local function AddLootRect(frame, num)
    local l, b, wid, hgt = frame:GetRect()
    local s = frame:GetEffectiveScale()
    if AnySecret(l, b, wid, hgt, s) or not l or wid <= 0 or hgt <= 0 then
        return num
    end
    num = num + 1
    lootL[num], lootB[num], lootR[num], lootT[num] = l * s, b * s, (l + wid) * s, (b + hgt) * s
    return num
end

-- The same, for a shown frame only.
local function AddLootObstacle(frame, num)
    local isShown = frame:IsShown()
    if issecretvalue(isShown) or not isShown then
        return num
    end
    return AddLootRect(frame, num)
end

-- The column's layout children, except the rolls and the three viewers.
local function AddLootColumnObstacles(num, skipA, skipB, skipC, skipD, ...)
    for index = 1, select("#", ...) do
        local c = select(index, ...)
        if not issecretvalue(c) and c ~= skipA and c ~= skipB and c ~= skipC and c ~= skipD then
            local forbidden = c:IsForbidden()
            if not issecretvalue(forbidden) and not forbidden and c.layoutIndex and not c.ignoreInLayout then
                num = AddLootObstacle(c, num)
            end
        end
    end
    return num
end

-- Nil when the rolls are not in the column's own anchor; false (asked again
-- after combat) when a geometry read is secret.
local function PlaceLootRolls(widget, anchorPoint, relativeTo, relativePoint, posX, posY)
    local colour = BottomManagedFrameContainer
    if not colour then
        return nil
    end
    -- Only the column's own anchor: TOP of the rolls to the TOP of the column.
    local hostFrame = widget:GetParent()
    if
        issecretvalue(hostFrame)
        or hostFrame ~= colour
        or anchorPoint ~= "TOP"
        or relativePoint ~= "TOP"
        or relativeTo ~= colour
    then
        return nil
    end
    local cs, s, us = colour:GetEffectiveScale(), widget:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local colTop, colBottom, colL, colR = colour:GetTop(), colour:GetBottom(), colour:GetLeft(), colour:GetRight()
    local wid, hgt, uiTop = widget:GetWidth(), widget:GetHeight(), UIParent:GetTop()
    if AnySecret(cs, s, us, colTop, colBottom, colL, colR, wid, hgt, uiTop) then
        return false
    end
    if not (colTop and colBottom and colL and colR and uiTop) then
        return nil
    end
    -- Screen pixels. Anchor offsets are in the rolls' own scale. The roll and
    -- Bonus Roll windows hang centred from the container and are wider than
    -- it: a roll window is 277 wide with 286-wide art, Bonus Roll 286.
    local height = hgt * s
    local cx = (colL + colR) * 0.5 * cs + posX * s
    local half = math.max(wid, 286) * s * 0.5
    local leftX, right = cx - half, cx + half
    local topY = colBottom * cs + height

    local num = AddLootColumnObstacles(
        0,
        widget,
        _G[BLIZZ_CDM_FRAMES.cooldowns],
        _G[BLIZZ_CDM_FRAMES.utility],
        _G[BLIZZ_CDM_FRAMES.buffs],
        colour:GetChildren()
    )
    local profile = ECME.db and ECME.db.profile
    local cdmBars = profile and profile.cdmBars
    local barList = cdmBars and cdmBars.bars
    if barList then
        local focusKick = mod.FOCUSKICK_BAR_KEY
        for index = 1, #barList do
            local edge = barList[index]
            if
                edge.enabled
                and not edge.isGhostBar
                and edge.key ~= focusKick
                and edge.barVisibility ~= "never"
            then
                -- A bar hidden by its visibility rules keeps its spot (it can
                -- show while the rolls are up); a cursor bar holds none.
                local frame = cdmBarFrames[edge.key]
                if frame and not frame._mouseTrack then
                    num = AddLootObstacle(frame, num)
                end
            end
        end
    end
    if cdmBars and cdmBars.useBlizzardBuffBars then
        local bbv = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
        if bbv then
            num = AddLootObstacle(bbv, num)
        end
    else
        -- Each enabled Tracking Bar keeps its spot while hidden too: an
        -- inactive one shows the moment its aura procs.
        local getTBB, getBars = mod.GetTBBFrame, mod.GetTrackedBuffBars
        local tbb = getTBB and getBars and getBars()
        local cfgs = tbb and tbb.bars
        if cfgs then
            for index = 1, #cfgs do
                local conf = cfgs[index]
                if conf.enabled ~= false and conf.barVisibility ~= "never" then
                    local frame = getTBB(index)
                    if frame then
                        num = AddLootRect(frame, num)
                    end
                end
            end
        end
    end
    -- Action bars (bars 1-10, stance, pet): the rolls sit above their buttons.
    -- A bar keeps its spot unless it is hidden for good: one that shows only
    -- in combat can appear under rolls placed out of combat. The stance bar
    -- of a class with no forms never shows (the test its driver uses).
    local abKeys, elems = CludesUI._abBarKeys, CludesUI._unlockRegisteredElements
    if abKeys then
        for key in pairs(abKeys) do
            local e = elems[key]
            local frame = e and e.getFrame and e.getFrame(key)
            if
                frame
                and not (e.isHidden and e.isHidden())
                and not (key == "StanceBar" and (GetNumShapeshiftForms() or 0) == 0)
            then
                num = AddLootRect(frame, num)
            end
        end
    end
    -- The extra and zone ability buttons while they show, wherever Action
    -- Bars holds their container (in the column it is counted above too),
    -- unless the Extra Action Button is hidden for good: its holder is then
    -- hidden while Blizzard keeps the container shown.
    local xac = ExtraAbilityContainer
    if xac then
        local xe = elems.ExtraActionButton
        if not (xe and xe.isHidden and xe.isHidden()) then
            num = AddLootObstacle(xac, num)
        end
    end

    -- Rise above every obstacle the rolls cover, one column spacing clear:
    -- each pass jumps once past the highest top among the obstacles covered
    -- now. Once risen, an obstacle less than one spacing under the rolls
    -- counts as covered too, so they never stop closer than that to one
    -- they jumped past. Each pass clears a higher top than the last, so n
    -- passes cover every rise, whatever the obstacles' order.
    local gap = (colour.spacing or 0) * cs
    local reach = 0
    for _ = 1, num do
        local hi
        for index = 1, num do
            if
                leftX < lootR[index]
                and right > lootL[index]
                and topY - height < lootT[index] + reach
                and topY > lootB[index]
                and not (hi and hi >= lootT[index])
            then
                hi = lootT[index]
            end
        end
        if not hi then
            break
        end
        topY = hi + gap + height
        reach = gap
    end
    if topY > uiTop * us then
        topY = uiTop * us
    end
    return anchorPoint, colour, relativePoint, posX, (topY - colTop * cs) / s
end

-- Rolls already up follow a CDM bar or Tracking Bar that was rebuilt, moved
-- or resized. One read while no roll is up; requests made in one frame
-- collapse into one placement.
function mod.RequestLootPlacement()
    local loot = GroupLootContainer
    if not loot then
        return
    end
    local isShown = loot:IsShown()
    if not issecretvalue(isShown) and isShown then
        CludesUI.RequestFramePlacement(loot)
    end
end

HideBlizzardCDM = function()
    -- Anchor each viewer to our corresponding bar container. Frames stay parented to viewers
    -- (no reparenting = no taint); the viewer becomes an invisible shell overlapping our
    -- container and CollectAndReanchor re-anchors individual icons within it. Viewer alpha stays at 1 so child frames inherit visibility.
    local viewerToBar = {
        [BLIZZ_CDM_FRAMES.cooldowns] = "cooldowns",
        [BLIZZ_CDM_FRAMES.utility] = "utility",
        [BLIZZ_CDM_FRAMES.buffs] = "buffs",
    }
    local allFrameNames = {}
    for _, func in pairs(BLIZZ_CDM_FRAMES) do
        allFrameNames[#allFrameNames + 1] = func
    end
    for _, func in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do
        allFrameNames[#allFrameNames + 1] = func
    end
    for _, frameName in ipairs(allFrameNames) do
        local widget = _G[frameName]
        if widget then
            local fc = FC(widget)
            if not fc.hidden then
                fc.origPoints = {}
                for index = 1, widget:GetNumPoints() do
                    fc.origPoints[index] = { widget:GetPoint(index) }
                end
                fc.hidden = true
            end
            -- NEVER reposition primary viewers (Essential/Utility/BuffIcon): individual icon
            -- anchoring handles that. The secondary BuffBarCooldownViewer gets alpha + offscreen park, since TBB renders its own bars and we don't hook its Cooldown widgets.
            local isSecondary = (frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs)
            if isSecondary then
                mod.ParkSecondaryBuffViewer(widget)
            end
            if not InCombatLockdown() then
                widget:EnableMouse(false)
                if widget.EnableMouseMotion then
                    widget:EnableMouseMotion(false)
                end
            end
        end
    end
    local loot = GroupLootContainer
    if loot then
        CludesUI.SetFramePlacer(loot, "cdm", PlaceLootRolls)
        -- Rebuilds run through here: rolls already up follow the rebuilt bars.
        mod.RequestLootPlacement()
    end
end

RestoreBlizzardCDM = function()
    if GroupLootContainer then
        CludesUI.SetFramePlacer(GroupLootContainer, "cdm", nil)
    end
    local allFrameNames = {}
    for _, func in pairs(BLIZZ_CDM_FRAMES) do
        allFrameNames[#allFrameNames + 1] = func
    end
    for _, func in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do
        allFrameNames[#allFrameNames + 1] = func
    end
    for _, frameName in ipairs(allFrameNames) do
        local widget = _G[frameName]
        local fc = widget and _ecmeFC[widget]
        if fc and fc.hidden then
            fc.restoring = true
            mod._secondaryParkPending = nil
            if fc.origPoints then
                CludesUI.ClearFramePoints(widget)
                for _, pt in ipairs(fc.origPoints) do
                    CludesUI.SetFramePoint(widget, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            -- The secondary viewer is the only alpha-suppressed one, and its Blizzard default is EnableMouse(false) -- restoring it true leaves an invisible click-catcher.
            if frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs then
                widget:SetAlpha(1)
            else
                widget:EnableMouse(true)
                if widget.EnableMouseMotion then
                    widget:EnableMouseMotion(true)
                end
            end
            fc.hidden = false
            fc.restoring = nil
        end
    end
end

-- Restore Blizzard's BuffBarCooldownViewer (bar-style buff tracking strip) when TBB is
-- disabled via "Use Blizzard CDM Bars". Touches ONLY the secondary bar viewer; CDM icon bars are never affected.
local function RestoreBlizzardBuffFrame()
    local frameName = BLIZZ_CDM_FRAMES_SECONDARY.buffs
    if not frameName then
        return
    end
    local widget = _G[frameName]
    local fc = widget and _ecmeFC[widget]
    if fc and fc.hidden then
        fc.restoring = true
        mod._secondaryParkPending = nil
        if fc.origPoints then
            CludesUI.ClearFramePoints(widget)
            for _, pt in ipairs(fc.origPoints) do
                CludesUI.SetFramePoint(widget, pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        widget:SetAlpha(1)
        -- BuffBarCooldownViewer's default is EnableMouse(false); EnableMouse(true) would create an invisible click-catcher. Other viewers need mouse for tooltip hover.
        if frameName ~= "BuffBarCooldownViewer" then
            widget:EnableMouse(true)
            if widget.EnableMouseMotion then
                widget:EnableMouseMotion(true)
            end
        end
        fc.hidden = false
        fc.restoring = nil
    end
end

Inner.BLIZZ_CDM_FRAMES, Inner.BLIZZ_CDM_FRAMES_SECONDARY = BLIZZ_CDM_FRAMES, BLIZZ_CDM_FRAMES_SECONDARY
Inner.CaptureCDMPositions, Inner.CDM_BAR_CATEGORIES = CaptureCDMPositions, CDM_BAR_CATEGORIES
Inner.EnforceCooldownViewerEditModeSettings = EnforceCooldownViewerEditModeSettings
Inner.GetCDMFont, Inner.HideBlizzardCDM = GetCDMFont, HideBlizzardCDM
Inner.MAX_CUSTOM_BARS, Inner.RestoreBlizzardBuffFrame = MAX_CUSTOM_BARS, RestoreBlizzardBuffFrame
Inner.RestoreBlizzardCDM, Inner.SetBlizzCDMFont = RestoreBlizzardCDM, SetBlizzCDMFont
Inner.broken = false
