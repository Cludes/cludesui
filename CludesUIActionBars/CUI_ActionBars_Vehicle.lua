if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Vehicle.lua
--
--  The vehicle exit button, hiding Blizzard's vehicle and override bar,
--  the vehicle highlight fix, housing editor keybinds and grid show/hide.
--  Loads after CUI_ActionBars_Keybinds.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, pairs, pcall = ipairs, pairs, pcall
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local EFD = mod.EFD

local ABAR, EAB_VTABLE, barButtons = mod.EAB, mod.EAB_VTABLE, mod.barButtons
local Inner = mod._internals
local _gridState, BAR_CONFIG, NUM_ACTIONBAR_BUTTONS =
    Inner._gridState, Inner.BAR_CONFIG, Inner.NUM_ACTIONBAR_BUTTONS
local SafeEnableMouse = Inner.SafeEnableMouse
local SetShowGridInsecure, SHOWGRID = Inner.SetShowGridInsecure, Inner.SHOWGRID
local barFrames = Inner.barFrames
local hoverStates = Inner.hoverStates
local _bindState, _eabBindOwner, UpdateKeybinds = Inner._bindState, Inner._eabBindOwner, Inner.UpdateKeybinds

-------------------------------------------------------------------------------
--  Vehicle Exit Button: reparent to UIParent so it stays visible when
--  ActionBarParent is hidden. Position and visibility are fully
--  Blizzard-owned (no unlock mode, no SetPoint hook). ActionBarController is
--  disabled above, so Blizzard's transition system won't reposition it.
-------------------------------------------------------------------------------
do
    local button = MainMenuBarVehicleLeaveButton
    if button then
        button:SetParent(UIParent)
        local vehVis = mod.TakeShell()
        vehVis:RegisterEvent("UNIT_ENTERED_VEHICLE")
        vehVis:RegisterEvent("UNIT_EXITED_VEHICLE")
        vehVis:RegisterEvent("PLAYER_ENTERING_WORLD")
        vehVis:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Cludes: moved verbatim from CludesUIActionBars.lua
        vehVis:SetScript("OnEvent", function(self, evt, unitToken)
            -- Only the UNIT_ events carry a unit; PLAYER_ENTERING_WORLD's first
            -- arg is isInitialLogin, so testing it as a unit skipped the whole
            -- pass on a fresh login.
            if (evt == "UNIT_ENTERED_VEHICLE" or evt == "UNIT_EXITED_VEHICLE") and unitToken ~= "player" then
                return
            end
            if evt ~= "PLAYER_REGEN_ENABLED" then
                -- MainMenuBarVehicleLeaveButton is EditMode-managed, so SetShown
                -- routes through protected HideBase/ShowBase and is blocked in ANY
                -- combat, not only inside a live keystone. Do NOT AND this with a
                -- protected-instance check: that is false in every normal dungeon and
                -- goes false the instant a key COMPLETES (requires
                -- IsChallengeModeActive), so combat vehicle events call straight
                -- through and trip ADDON_ACTION_BLOCKED. Same rule as the micro
                -- menu/bag bar site above -- InCombatLockdown is the whole gate.
                -- Nothing lost by deferring: the protected call couldn't have
                -- succeeded in combat either way, and PLAYER_REGEN_ENABLED re-applies
                -- the state on lockdown end.
                if InCombatLockdown() then
                    return
                end
            end
            local show = (CanExitVehicle and CanExitVehicle()) or false
            -- A redundant SetShown on a frame already in that state still trips
            -- the block, so only issue the protected op on a real transition.
            if button:IsShown() ~= show then
                button:SetShown(show)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Hide Blizzard's Vehicle / Override Bar  (opt-in)
--
--  Bar 1 already pages to [vehicleui][possessbar] and the leave button is
--  reparented to UIParent above, so nothing is lost while hidden.
--
--  Suppression is alpha + mouse on the TOP-LEVEL bar only, never SetParent,
--  never Hide, never recursion into descendants: OverrideActionBar is a
--  protected, EditMode-managed frame (reparenting taints the transition
--  code), while SetAlpha is unprotected and combat-legal. Only mouse state
--  we disabled ourselves is ever restored.
--
--  Blizzard docks the micro menu INTO this bar, where it would inherit
--  alpha 0; it is moved out instead (ReclaimMicroMenu), not disabled in
--  place.
-------------------------------------------------------------------------------

-- Snapshot where MicroMenu lives while it is still home, so the reclaim has a
-- real anchor to restore instead of guessing one.
function ABAR:CacheMicroMenuHome()
    if self._eabMicroHome then
        return
    end
    if not (MicroMenu and MicroMenu.GetPoint) then
        return
    end
    -- Never snapshot while docked: a /reload inside a vehicle or pet battle
    -- would record the DOCKED anchor as "home" in the write-once cache.
    if self:MicroMenuDockedIn(OverrideActionBar) or self:MicroMenuDockedIn(PetBattleFrame) then
        return
    end
    local p, rel, relP, posX, posY = MicroMenu:GetPoint(1)
    if p then
        self._eabMicroHome = { p, rel, relP, posX or 0, posY or 0 }
    end
end

-- Blizzard docks MicroMenu several levels deep, so a one-level parent test
-- misses it. Walk the chain.
function ABAR:MicroMenuDockedIn(root)
    if not (MicroMenu and root) then
        return false
    end
    local p = MicroMenu.GetParent and MicroMenu:GetParent()
    local guard = 0
    while p and guard < 8 do
        if p == root then
            return true
        end
        p = p.GetParent and p:GetParent()
        guard = guard + 1
    end
    return false
end

-- Hand MicroMenu back to its own container: left docked it inherits alpha 0
-- and sits invisible over the vehicle exit button (or, for pet battles,
-- stays parented under PetBattleFrame and never comes back at all -- MicroMenuContainer
-- stays shown and draggable in Edit Mode, but empty), still taking clicks.
-- ResetMicroMenuPosition() is NOT the right call: it re-derives the dock from
-- current game state, which mid-vehicle/mid-battle resolves back into the
-- docked frame (no-op).
function ABAR:ReclaimMicroMenu()
    if InCombatLockdown() then
        return
    end
    if not (MicroMenu and MicroMenuContainer) then
        return
    end
    self:CacheMicroMenuHome()
    if not (self:MicroMenuDockedIn(OverrideActionBar) or self:MicroMenuDockedIn(PetBattleFrame)) then
        return
    end
    MicroMenu:SetParent(MicroMenuContainer)
    local hgt = self._eabMicroHome
    if hgt then
        MicroMenu:ClearAllPoints()
        MicroMenu:SetPoint(hgt[1], hgt[2] or MicroMenuContainer, hgt[3], hgt[4], hgt[5])
    end
    MicroMenu:SetAlpha(1)
    mod.AB_ExtraCapsShown("MicroBar")
end

-- Blizzard docks MicroMenu into PetBattleFrame for the duration of a pet
-- battle, the same multi-level docking behavior as OverrideActionBar for
-- vehicles -- confirmed via a live capture: MicroMenu's parent chain still
-- ran through PetBattleFrame two full seconds after PET_BATTLE_CLOSE, with
-- MicroMenuContainer sitting empty (but shown/draggable) the whole time.
-- Wild battles hold combat lockdown through their own close event, so the
-- reclaim (which no-ops in combat, see above) is retried once on the next
-- PLAYER_REGEN_ENABLED, same pattern as QueuePetBattleUnsuppress uses for
-- the sibling suppression bug this branch was originally about.
do
    -- One keyed combat-queue entry (idempotent), the QueuePetBattleUnsuppress
    -- shape above.
    local function ReclaimMicroMenu()
        ABAR:ReclaimMicroMenu()
    end
    local function TryReclaimAfterPetBattle()
        if InCombatLockdown() then
            mod.CombatQueue.Defer("ReclaimMicroMenu", ReclaimMicroMenu)
            return
        end
        ABAR:ReclaimMicroMenu()
    end
    local petBattleReclaimFrame = CreateFrame("Frame")
    petBattleReclaimFrame:RegisterEvent("PET_BATTLE_CLOSE")
    petBattleReclaimFrame:SetScript("OnEvent", TryReclaimAfterPetBattle)
end

function ABAR:ApplyVehicleBarVisibility()
    local bar = OverrideActionBar
    if not bar then
        return
    end
    local hide = self.db and self.db.profile and self.db.profile.hideBlizzardVehicleBar
    if hide then
        self:ReclaimMicroMenu()
        bar:SetAlpha(0)
        -- Guarded: the restore below may only undo OUR disable, never switch
        -- on mouse Blizzard had off for its own reasons.
        if not self._eabVehMouseOff then
            self._eabVehMouseOff = true
            SafeEnableMouse(bar, false)
        end
    else
        bar:SetAlpha(1)
        if self._eabVehMouseOff then
            self._eabVehMouseOff = nil
            SafeEnableMouse(bar, true)
        end
    end
end

-- Arm or disarm the watch. Everything is created on first enable: never
-- enabled = no event frame, no registrations, no hook. HookScript cannot be
-- undone, so the hook installs at most once and gates on the setting inside;
-- disabling unregisters the events.
function ABAR:UpdateVehicleBarWatch()
    local on = self.db and self.db.profile and self.db.profile.hideBlizzardVehicleBar
    local f = self._eabVehWatch
    if not on then
        if f then
            f:UnregisterAllEvents()
        end
        self:ApplyVehicleBarVisibility()
        return
    end
    if not f then
        f = mod.TakeShell()
        f:SetScript("OnEvent", function()
            ABAR:CacheMicroMenuHome()
            ABAR:ApplyVehicleBarVisibility()
        end)
        self._eabVehWatch = f
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The bar's own OnShow is the deterministic edge; one deferred re-assert
    -- follows because the micro menu dock can land later in the same frame.
    if not self._eabVehShowHooked and OverrideActionBar then
        self._eabVehShowHooked = true
        OverrideActionBar:HookScript("OnShow", function()
            if not (ABAR.db and ABAR.db.profile and ABAR.db.profile.hideBlizzardVehicleBar) then
                return
            end
            ABAR:ApplyVehicleBarVisibility()
            C_Timer_After(0, function()
                ABAR:ApplyVehicleBarVisibility()
            end)
        end)
    end
    self:ApplyVehicleBarVisibility()
end

-------------------------------------------------------------------------------
--  Vehicle Highlight Fix: during vehicle/override paging, empty MainBar
--  buttons can retain a stale "checked" state from the normal bar.
--  CheckedTexture uses the same texture as HighlightTexture, so it looks
--  like a permanent highlight. The inverted mouseover behavior (hides on
--  enter, returns on leave) is WoW's native CheckButton behavior when checked.
--  Fix: after a page change, clear the checked state and hide CheckedTexture
--  on MainBar buttons with no action on the new page.
-------------------------------------------------------------------------------
do
    local _vehHighlightPending = false

    local function FixVehicleHighlights()
        _vehHighlightPending = false
        local mainFrame = barFrames and barFrames["MainBar"]
        if not mainFrame then
            return
        end
        local page = tonumber(mainFrame:GetAttribute("actionpage")) or 1
        local buttons = barButtons and barButtons["MainBar"]
        if not buttons then
            return
        end

        -- Only apply the alpha-0 fallback on vehicle/override/bonus pages
        -- (page > 6). On normal pages (1-6), just restore alpha to 1 so
        -- Blizzard's SetChecked/UpdateState manages checked visuals normally.
        local isSpecialPage = (page > 6)

        for idx, button in ipairs(buttons) do
            if button then
                local ct = button.CheckedTexture
                if isSpecialPage then
                    local slot = idx + (page - 1) * NUM_ACTIONBAR_BUTTONS
                    if not HasAction(slot) then
                        -- SetChecked might be protected during combat; pcall.
                        -- Also hide CheckedTexture as a visual fallback.
                        pcall(button.SetChecked, button, false)
                        if ct then
                            ct:SetAlpha(0)
                        end
                    else
                        -- Slot has an action; restore alpha so Blizzard's
                        -- UpdateState manages checked visuals (honors the
                        -- Show Highlight on Spell Cast setting).
                        if ct then
                            ct:SetAlpha(ABAR:GetCheckedAlpha("MainBar"))
                        end
                    end
                else
                    -- Normal page: restore alpha on all buttons so checked
                    -- state renders correctly when spells are dragged in
                    -- (honors the Show Highlight on Spell Cast setting).
                    if ct then
                        ct:SetAlpha(ABAR:GetCheckedAlpha("MainBar"))
                    end
                end
            end
        end
    end

    local function QueueVehicleHighlightFix()
        if _vehHighlightPending then
            return
        end
        _vehHighlightPending = true
        C_Timer_After(0, FixVehicleHighlights)
    end

    local vehHighlightFrame = mod.TakeShell()
    vehHighlightFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    vehHighlightFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    vehHighlightFrame:SetScript("OnEvent", QueueVehicleHighlightFix)
end

-------------------------------------------------------------------------------
--  Housing Editor Keybind Clearing: when the house editor is active, clear
--  our override bindings so Blizzard's housing hotkeys work. Restore them
--  when the editor closes.
-------------------------------------------------------------------------------
local _housingEventFrame = CreateFrame("Frame")
local IsHouseEditorActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive
if IsHouseEditorActive then
    _housingEventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    _housingEventFrame:SetScript("OnEvent", function()
        if IsHouseEditorActive() then
            -- House editor opened: clear ALL override bindings so housing hotkeys work
            if _bindState.housingCleared then
                return
            end
            _bindState.housingCleared = true
            if not InCombatLockdown() then
                ClearOverrideBindings(_eabBindOwner)
                -- Bindings no longer match the cached signature; force the
                -- next UpdateKeybinds to rebuild even if routing is identical.
                _bindState.sigValid = false
            end
        else
            -- House editor closed: restore our override bindings. Call
            -- unconditionally -- UpdateKeybinds defers itself in combat, and a
            -- combat guard here would drop the restore with nothing to re-arm
            -- it, leaving every override binding cleared until reload.
            if not _bindState.housingCleared then
                return
            end
            _bindState.housingCleared = false
            UpdateKeybinds()
        end
    end)
end

-------------------------------------------------------------------------------
--  Grid Show/Hide (show empty slots during spell drag)
-------------------------------------------------------------------------------

-- Reached only on a real off -> on edge: ns.EABQueueGrid settles the event
-- storm a bag sort produces (its old 0.1s throttle here could not, because
-- every HIDEGRID in the storm reset _gridState.shown and re-armed it).
local function OnGridChange()
    if InCombatLockdown() then
        return
    end
    _gridState.shown = true

    -- Propagate showgrid to the controller so the secure environment
    -- knows buttons should be visible (handles combat transitions).
    for _, details in ipairs(BAR_CONFIG) do
        if not details.isStance and not details.isPetBar then
            local buttons = barButtons[details.key]
            if buttons then
                for _, button in ipairs(buttons) do
                    if button then
                        SetShowGridInsecure(button, true, SHOWGRID.GAME_EVENT)
                    end
                end
            end
        end
    end

    -- When the player starts dragging a spell, show all button slots
    -- so they can see where to drop it (even empty ones).
    -- Respect the icon cutoff so hidden overflow buttons stay hidden.
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            local s = ABAR.db.profile.bars[details.key]
            local numIcons = s and (s.overrideNumIcons or s.numIcons) or details.count
            if not numIcons or numIcons < 1 then
                numIcons = details.count
            end
            if numIcons > details.count then
                numIcons = details.count
            end
            if details.isStance then
                numIcons = GetNumShapeshiftForms() or details.count
            end
            if numIcons < 1 then
                numIcons = 1
            end
            for idx = 1, numIcons do
                local button = buttons[idx]
                if button then
                    -- Clear statehidden so the secure UpdateShown snippet
                    -- allows the button to stay visible during drag.
                    if button:GetAttribute("statehidden") then
                        button:SetAttributeNoHandler("statehidden", nil)
                    end
                    local gfd = EFD(button)
                    if gfd.slotBG then
                        gfd.slotBG:Show()
                    end
                    -- Show borders during drag
                    if gfd.borders and not (gfd.shapeMask and gfd.shapeMask:IsShown()) then
                        gfd.borders:Show()
                    end
                    if gfd.shapeBorder and EFD(gfd.shapeBorder).wantsShow then
                        gfd.shapeBorder:Show()
                    end
                    -- Make hidden empty buttons visible during drag. The park
                    -- verdict is taken before the Show: our own Show keeps
                    -- alpha, so it must not read as a secure reveal.
                    local parked = mod._eabParked(button)
                    button:Show()
                    if parked then
                        button:SetAlpha(1)
                    end
                    gfd.parkA0 = nil
                    -- Re-enable mouse so empty slots accept drops
                    SafeEnableMouse(button, true)
                end
            end
        end
    end

    -- Mouseover bar forcing moved to CURSOR_CHANGED handler, which only
    -- fires for real cursor drags. ACTIONBAR_SHOWGRID also fires for
    -- equipment changes, bag sorts, etc. which should not affect mouseover.
end

-- Show All During Drag: restore bars saved as Never that were surfaced for a
-- cursor drag (CURSOR_CHANGED handler). Idempotent, safe from every drag-end
-- path. Clears only the overrides the drag itself planted, so a
-- toggle-keybind override the user set stays intact. If the drag ends in
-- combat the driver swap is deferred: RefreshRuntimeVisibility skips secure
-- writes there, and PLAYER_REGEN_ENABLED's ApplyAll re-runs it clean.
function ABAR._RestoreDragNeverBars()
    local forced = _gridState._dragNeverForced
    if not forced then
        return
    end
    _gridState._dragNeverForced = nil
    if ABAR._visOverride then
        for key in pairs(forced) do
            if ABAR._visOverride[key] == "always" then
                ABAR._visOverride[key] = nil
            end
        end
    end
    ABAR:RefreshRuntimeVisibility()
    -- A bar opted into BOTH drag and spellbook surfacing skips the spellbook
    -- plant while the drag override holds it; re-evaluate so it stays up when
    -- the drag ends with the spellbook still open.
    ABAR._UpdateSpellbookNeverBars()
end

-- Show When Spellbook Is Open (per-bar opt-in, s.spellbookShow, ANY
-- visibility mode): while the spellbook (PlayerSpellsFrame) or macro panel
-- (MacroFrame) is open, opted-in bars force-show the same way a cursor drag
-- surfaces them by default:
--   * non-always modes (Never, conditional drivers) plant the runtime
--     _visOverride slot (never persisted) -- own forced-set so the drag
--     trigger and this one restore independently; same combat guard
--     (secure driver swaps are combat-blocked; a panel opened mid-combat
--     surfaces once combat ends, through the module's combat queue).
--   * mouseover bars force alpha 1 (StopFade), re-asserted on every call
--     because a drag's grid-hide fade can land while the panel stays open;
--     released to the normal fade-out on close unless hovered.
-- resync = drop everything planted first and re-evaluate (options toggle
-- flips while the panel is already open).
function ABAR._UpdateSpellbookNeverBars(resync)
    local open = (PlayerSpellsFrame and PlayerSpellsFrame:IsShown()) or (MacroFrame and MacroFrame:IsShown())
    if resync == true or not open then
        local forced = _gridState._sbNeverForced
        if forced then
            _gridState._sbNeverForced = nil
            if ABAR._visOverride then
                for key in pairs(forced) do
                    if ABAR._visOverride[key] == "always" then
                        ABAR._visOverride[key] = nil
                    end
                end
            end
            ABAR:RefreshRuntimeVisibility()
        end
        local mo = _gridState._sbMoForced
        if mo then
            _gridState._sbMoForced = nil
            for key in pairs(mo) do
                local s = ABAR.db.profile.bars[key]
                local status = hoverStates[key]
                if s and s.mouseoverEnabled and status and not status.isHovered then
                    EAB_VTABLE.Hover.FadeOut(key, status)
                end
            end
        end
        if not open then
            return
        end
    end
    if InCombatLockdown() then
        -- The panel may close before combat ends: the queued pass reads it again.
        mod.CombatQueue.Defer("SpellbookNever", ABAR._UpdateSpellbookNeverBars)
    elseif not _gridState._sbNeverForced then
        local forced
        for _, details in ipairs(BAR_CONFIG) do
            local s = ABAR.db.profile.bars[details.key]
            if
                s
                and s.spellbookShow
                and s.enabled ~= false
                and ((CludesUI.VisOverrideValue(s) or s.barVisibility or "always") ~= "always" or ABAR.VisibilityCompat.IsNever(
                    s
                ) or (ABAR._padHide and s.gamepadHideBar == true))
                and not (ABAR._visOverride and ABAR._visOverride[details.key])
            then
                ABAR._visOverride = ABAR._visOverride or {}
                ABAR._visOverride[details.key] = "always"
                forced = forced or {}
                forced[details.key] = true
            end
        end
        if forced then
            _gridState._sbNeverForced = forced
            ABAR:RefreshRuntimeVisibility()
        end
    end
    local mo
    for _, details in ipairs(BAR_CONFIG) do
        local s = ABAR.db.profile.bars[details.key]
        if s and s.spellbookShow and s.enabled ~= false and s.mouseoverEnabled then
            local widget = barFrames[details.key]
            if widget then
                -- Through the hover system's OWN fade-in, never a raw
                -- SetAlpha: FadeInOne targets the bar's true shown alpha
                -- (_savedBarAlpha) and keeps state.fadeDir truthful --
                -- a raw SetAlpha leaves the resting "out" memo in place,
                -- so the close-path FadeOut treats the bar as already
                -- faded and skips it (bar stuck visible until a hover).
                EAB_VTABLE.Hover.FadeInOne(details.key, EAB_VTABLE.Hover.GetState(details.key, widget))
                mo = mo or {}
                mo[details.key] = true
            end
        end
    end
    _gridState._sbMoForced = mo
end

-- Trigger wiring: OnShow/OnHide HookScripts on the two panels (both are
-- LoadOnDemand -- ADDON_LOADED installs late hooks, unregistering once both
-- are in).
do
    local hooked = {}
    local function OnPanelToggle()
        ABAR._UpdateSpellbookNeverBars()
    end
    local function TryHook(name)
        if hooked[name] then
            return true
        end
        local f = _G[name]
        if not f then
            return false
        end
        hooked[name] = true
        f:HookScript("OnShow", OnPanelToggle)
        f:HookScript("OnHide", OnPanelToggle)
        return true
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function(self, evt, addon)
        if evt == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            local a, b = TryHook("PlayerSpellsFrame"), TryHook("MacroFrame")
            if not (a and b) then
                self:RegisterEvent("ADDON_LOADED")
            end
        else
            local name = (addon == "Blizzard_PlayerSpells" and "PlayerSpellsFrame")
                or (addon == "Blizzard_MacroUI" and "MacroFrame")
            if not name then
                return
            end
            TryHook(name)
            if hooked.PlayerSpellsFrame and hooked.MacroFrame then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    end)
end

-- Entry points the files after this one re-import by name. The housing API
-- may be absent: false keeps the key published (a nil publish would make
-- Setup's import raise), and Setup's guard reads false as "no editor".
Inner.IsHouseEditorActive, Inner.OnGridChange = IsHouseEditorActive or false, OnGridChange
