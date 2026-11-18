if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_ApplyAll.lua
--
--  ApplyAll, the full visual application over every bar.
--  Loads after CUI_ActionBars_Vehicle.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs, pairs = ipairs, pairs
local wipe = wipe
local InCombatLockdown = InCombatLockdown

local ABAR, EAB_VTABLE = mod.EAB, mod.EAB_VTABLE
local Inner = mod._internals
local _dragState, BAR_CONFIG = Inner._dragState, Inner.BAR_CONFIG
local barFrames = Inner.barFrames
local LayoutBar = Inner.LayoutBar
local SetIsApplyingAll = Inner.SetIsApplyingAll

-------------------------------------------------------------------------------
--  Apply All orchestrates full visual application
-------------------------------------------------------------------------------
local function ApplyAll()
    SetIsApplyingAll(true)
    -- Full applies can create/enable bars and reassign slots without any
    -- dispatcher content event: retire the filled-slot fast lists, and the
    -- curated memo with them (profile swaps can land mid-session).
    mod._cdFilledDirty = true
    mod._cdCuratedDirty = true

    -- Restore any strata raised during a drag that wasn't cleaned up
    if _dragState.visible then
        _dragState.visible = false
        for widget, orig in pairs(_dragState.strataCache) do
            widget:SetFrameStrata(orig)
        end
        wipe(_dragState.strataCache)
    end

    local inCombat = InCombatLockdown()

    if not inCombat then
        EAB_VTABLE.MainBarPageSync.InstallAll()
    end

    for _, details in ipairs(BAR_CONFIG) do
        local key = details.key
        local s = ABAR.db.profile.bars[key]
        local widget = barFrames[key]

        -- Bar enabled/disabled toggle (protected frames can't be shown/hidden in combat)
        if widget and s and not inCombat then
            if s.enabled == false then
                widget:Hide()
            elseif not ABAR.VisibilityCompat.IsNever(s) then
                -- Skip Show if a state-visibility driver is managing this frame
                -- (the driver handles show/hide; calling Show() causes a one-frame blink)
                if not widget._eabLastVisStr then
                    widget:Show()
                end
            end
        end

        if not inCombat then
            LayoutBar(key)
        end
        if not inCombat then
            ABAR:ApplyBordersForBar(key)
        end
        if not inCombat then
            ABAR:ApplyShapesForBar(key)
        end
        ABAR:ApplyFontsForBar(key)
        ABAR:ApplyBackgroundForBar(key)
        ABAR:ApplyIconBackgroundForBar(key)
        if not inCombat then
            ABAR:ApplyAlwaysShowButtons(key)
        end
        if not inCombat then
            ABAR:ApplyClickThroughForBar(key)
        end
    end
    -- The micro menu's and bag bar's caps (a profile or spec switch changes
    -- their keys without bar 1's layout stamp moving).
    mod.AB_ExtraCapsAll()

    ABAR:ApplyPushedTextures()
    ABAR:HookPushedFlash()
    ABAR:ApplyHighlightTextures()
    ABAR:ApplyCooldownFonts()
    ABAR:ApplyCooldownSwipeColor()
    ABAR:ApplySlotBackgroundColor()
    -- Gated so it's zero-touch at the default (100); the live handler + setValue
    -- own the rest.
    if ABAR.db and ABAR.db.profile and ABAR.db.profile.alphaWhenOnCD ~= 100 then
        ABAR:ApplyCDAlphaAll()
    end
    ABAR:ApplyCooldownEdge()
    ABAR:ApplyMiscTextures()
    ABAR:ApplyCheckedTextures()
    ABAR:ApplyEquippedBorder(true)
    if not inCombat then
        ABAR:ApplyCombatVisibility()
    end
    if not inCombat then
        ABAR:RefreshRuntimeVisibility()
    end
    ABAR:RefreshMouseover()
    ABAR:RefreshProcGlows()
    ABAR:ApplyRangeColoring()

    -- A full apply that ran DURING combat skipped every `not inCombat` step
    -- above; the REGEN_ENABLED re-run (gated on this flag) converges them.
    if inCombat then
        mod._eabApplyDeferred = true
    end

    -- Dormancy re-sync: a profile swap or options change can re-register
    -- visibility drivers without firing the per-bar OnShow/OnHide edges the
    -- dormancy map saw. Per-key memoized, so unchanged bars cost one table read.
    for _, details in ipairs(BAR_CONFIG) do
        local frame = barFrames[details.key]
        if frame then
            mod.ApplyBarDormancy(details.key, not frame:IsVisible())
        end
    end

    -- Party Mode orbit: claims the buttons this rebuild built or showed (Party
    -- Mode may have started -- login, keybind, Bloodlust -- before they
    -- existed); a button the rebuild re-anchored re-measures its rest through
    -- the engine's SetPoint hook.
    mod.PartySpin_Refresh()

    -- Paging drivers are built at setup and rebuilt by the options controls; a
    -- profile swap or spec override apply changes paging settings with neither,
    -- so re-check here. Unchanged bars are skipped (see RebuildBarPaging).
    if not inCombat then
        local rebuilt
        for barId in pairs(EAB_VTABLE.BAR_KEY_TO_PAGE) do
            if mod.RebuildBarPaging(barId, true) then
                rebuilt = true
            end
        end
        -- The keybind routing pass the rebuilt bars left out, once for all of them.
        if rebuilt and _G._CUAB_UpdateKeybinds then
            _G._CUAB_UpdateKeybinds()
        end
        mod.RefreshPagingCycleMacros()
    end
    SetIsApplyingAll(false)
end

-- Handle for the lazy bar build in RefreshRuntimeVisibility, which sits above
-- this definition and cannot see the local. On ns and not on EAB deliberately:
-- the CUI_UnlockMode hook watches EAB.ApplyAll, and putting it there would
-- start firing that hook for the first time.
mod._eabApplyAll = ApplyAll

-- Entry points the files after this one re-import by name.
Inner.ApplyAll = ApplyAll
