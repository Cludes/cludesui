if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_QuickKeybind.lua
--
--  Quick Keybind Mode support for the EAB buttons and the paging arrows, and
--  the Swiftmend brightness scan over the action buttons. Loads after
--  CUI_ActionBars_ExtraBars.lua and reads the main file through ns only.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local RegisterAttributeDriver = RegisterAttributeDriver
local GetBindingKey = GetBindingKey
local EFD = mod.EFD

local ABAR, barButtons = mod.EAB, mod.barButtons
local LayoutPagingFrame, ResolveBorderThickness = mod.LayoutPagingFrame, mod.ResolveBorderThickness
local Inner = mod._internals
local BAR_CONFIG, barFrames, hoverStates, _quickKeybindState =
    Inner.BAR_CONFIG, Inner.barFrames, Inner.hoverStates, Inner._quickKeybindState
local InitPagingQuickKeybindButton, SyncPagingAlpha, StopFade =
    Inner.InitPagingQuickKeybindButton, Inner.SyncPagingAlpha, Inner.StopFade
local SHOWGRID, SetShowGridInsecure = Inner.SHOWGRID, Inner.SetShowGridInsecure
local SafeEnableMouseMotionOnly, ShouldQuickKeybindSurfaceBar =
    Inner.SafeEnableMouseMotionOnly, Inner.ShouldQuickKeybindSurfaceBar
local EAB_UpdateQuickKeybindButtons -- assigned below, published as ns.EAB_UpdateQuickKeybindButtons
local _pagingFrame -- set through SetPagingFrame (CUI_ActionBars_Paging.lua)
Inner.pagingFrameSetters[#Inner.pagingFrameSetters + 1] = function(val)
    _pagingFrame = val
end

-------------------------------------------------------------------------------
--  QuickKeybind compatibility: modern QuickKeybind works off visible
--  buttons' `commandName` plus `DoModeChange(...)`. Blizzard's stock helpers
--  only know about their own named bar buttons, so only EAB-owned buttons
--  and the custom paging arrows need an explicit mode toggle here.
-------------------------------------------------------------------------------
local function EAB_SetQuickKeybindEffects(button, show)
    if not button or button:IsForbidden() then
        return
    end
    if button.DoModeChange then
        button:DoModeChange(show)
    elseif button.QuickKeybindHighlightTexture then
        button.QuickKeybindHighlightTexture:SetShown(show)
    end
    -- Suppress/restore the secure action so spells don't fire during QKB.
    -- Only action buttons (those with an action attr) need this.
    if not InCombatLockdown() and button.commandName and button:GetAttribute("action") then
        if show then
            button:SetAttribute("type", nil)
        else
            button:SetAttribute("type", "action")
        end
    end
    _quickKeybindState.art.ApplyButtonHighlightAlpha(button, show)
    if button.UpdateMouseWheelHandler then
        button:UpdateMouseWheelHandler()
    end
end

EAB_UpdateQuickKeybindButtons = function(show)
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for _, button in ipairs(buttons) do
                if button and button.commandName then
                    EAB_SetQuickKeybindEffects(button, show)
                end
            end
        end
    end
    if _pagingFrame then
        if _pagingFrame._upBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._upBtn, show)
        end
        if _pagingFrame._downBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._downBtn, show)
        end
    end
end

_quickKeybindState.macroButtons = setmetatable({}, { __mode = "k" })

-- Macro quick-keybind uses our OWN capture overlay instead of Blizzard's
-- QuickKeybindButtonTemplateMixin. Driving Blizzard's secure input path from
-- addon code tainted it, so any key Blizzard passes through during capture
-- -- e.g. F11 = SCREENSHOT, which it RUNs via the protected RunBinding --
-- threw ADDON_ACTION_FORBIDDEN. Capturing on a plain frame we own consumes
-- the key before Blizzard's input handler sees it, so every key (including
-- system/function keys) binds cleanly with no taint.

_quickKeybindState.GetMacroBindingContext = function(command)
    return C_KeyBindings
        and C_KeyBindings.GetBindingContextForAction
        and C_KeyBindings.GetBindingContextForAction(command)
end

_quickKeybindState.SetOutput = function(textValue)
    if QuickKeybindFrame and QuickKeybindFrame.SetOutputText then
        QuickKeybindFrame:SetOutputText(textValue)
    end
end

_quickKeybindState.NormalizeMacroBindInput = function(input)
    input = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
    if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(input) then
        return
    end
    return input
end

_quickKeybindState.SetMacroButtonTooltip = function(btnFrame)
    if not btnFrame or not btnFrame.commandName or not QuickKeybindTooltip then
        return
    end
    QuickKeybindTooltip:SetOwner(btnFrame, "ANCHOR_RIGHT")
    GameTooltip_AddHighlightLine(QuickKeybindTooltip, GetBindingName(btnFrame.commandName))

    local key1 = GetBindingKeyForAction(btnFrame.commandName)
    if key1 then
        GameTooltip_AddInstructionLine(QuickKeybindTooltip, key1)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, ESCAPE_TO_UNBIND)
    else
        GameTooltip_AddErrorLine(QuickKeybindTooltip, NOT_BOUND)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, PRESS_KEY_TO_BIND)
    end

    QuickKeybindTooltip:Show()
end

_quickKeybindState.BindMacroInput = function(input)
    -- Rebinding during combat is unsafe and the rest of QKB is combat-gated, so
    -- match that here even though our capture frame is insecure.
    if InCombatLockdown() then
        return
    end
    local btnFrame = _quickKeybindState.hoveredMacroButton
    if not btnFrame then
        return
    end

    _quickKeybindState.UpdateMacroButtonCommand(btnFrame)
    local command = btnFrame.commandName
    if not command then
        return
    end

    local context = _quickKeybindState.GetMacroBindingContext(command)
    local old1, old2 = GetBindingKey(command, nil, context)

    if input == "ESCAPE" then
        -- Full unbind: clear EVERY key bound to this macro, matching the rebind
        -- path below (which clears both old keys before setting the new one).
        if old1 then
            SetBinding(old1, nil, context)
        end
        if old2 then
            SetBinding(old2, nil, context)
        end
        _quickKeybindState.SetOutput(KEY_UNBOUND)
        _quickKeybindState.SetMacroButtonTooltip(btnFrame)
        return
    end

    local key = _quickKeybindState.NormalizeMacroBindInput(input)
    if not key then
        return
    end

    local newKey = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
    if old1 then
        SetBinding(old1, nil, context)
    end
    if old2 then
        SetBinding(old2, nil, context)
    end
    SetBinding(newKey, nil, context)

    if SetBinding(newKey, command, context) then
        _quickKeybindState.SetOutput(KEY_BOUND)
    else
        if old1 then
            SetBinding(old1, command, context)
        end
        if old2 then
            SetBinding(old2, command, context)
        end
    end

    _quickKeybindState.SetMacroButtonTooltip(btnFrame)
end

_quickKeybindState.GetMacroBindFrame = function()
    if _quickKeybindState.macroBindFrame then
        return _quickKeybindState.macroBindFrame
    end

    -- A plain (insecure) frame we fully own -- never a secure template.
    -- Capturing input on it consumes the keypress, so it never reaches
    -- Blizzard's secure input path (no SetPropagateKeyboardInput, default = consume).
    local widget = CreateFrame("Frame", nil, UIParent)
    widget:SetFrameStrata("FULLSCREEN_DIALOG")
    widget:SetFrameLevel(1000)
    widget:EnableMouse(true)
    widget:EnableKeyboard(true)
    widget:EnableMouseWheel(true)
    widget:Hide()

    widget:SetScript("OnLeave", function(self)
        local btnFrame = self.button
        self.button = nil
        _quickKeybindState.hoveredMacroButton = nil
        self:Hide()
        if QuickKeybindTooltip then
            QuickKeybindTooltip:Hide()
        end
        if btnFrame then
            _quickKeybindState.RefreshMacroButton(btnFrame)
        end
    end)
    widget:SetScript("OnKeyDown", function(_, key)
        _quickKeybindState.BindMacroInput(key)
    end)
    widget:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then
            _quickKeybindState.BindMacroInput(mouseButton)
        end
    end)
    widget:SetScript("OnMouseWheel", function(_, delta)
        _quickKeybindState.BindMacroInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    _quickKeybindState.macroBindFrame = widget
    return widget
end

-- Controller: while armed over a macro, the overlay also takes Blizzard's
-- native gamepad buttons, re-decided on every arm, so buttons bind only while
-- a controller is the active input and the overlay is shown. The pad button
-- bound to the game menu unbinds the macro, as Escape does, instead of being
-- bound to it.
-- Never while the controller-cursor addon is loaded or the Gamepad interface
-- style is on: their D-pad and face buttons drive a cursor or the focus and
-- would bind here instead.
_quickKeybindState.ArmMacroPad = function(widget)
    local wanted = CludesUI.PadNative() and not CludesUI.PadCP() and not CludesUI.PadGamepadUI()
    if not wanted and not widget._padOn then
        return
    end
    -- Binding is out of combat only (BindMacroInput), so is the switch.
    if InCombatLockdown() then
        return
    end
    if wanted and not widget._padInit then
        widget._padInit = true
        widget:SetScript("OnGamePadButtonDown", function(_, btnFrame)
            -- The pointer's click buttons click, as Left/Right do on the mouse.
            if
                btnFrame == GetCVar("GamePadCursorLeftClick")
                or btnFrame == GetCVar("GamePadCursorRightClick")
            then
                return
            end
            if GetBindingFromClick(btnFrame) == "TOGGLEGAMEMENU" then
                btnFrame = "ESCAPE"
            end
            _quickKeybindState.BindMacroInput(btnFrame)
        end)
    end
    widget._padOn = wanted or nil
    widget:EnableGamePadButton(wanted)
end

_quickKeybindState.HideMacroBindFrame = function()
    local widget = _quickKeybindState.macroBindFrame
    if not widget then
        return
    end

    local btnFrame = widget.button
    widget.button = nil
    _quickKeybindState.hoveredMacroButton = nil
    widget:Hide()
    if QuickKeybindTooltip then
        QuickKeybindTooltip:Hide()
    end
    if btnFrame then
        _quickKeybindState.RefreshMacroButton(btnFrame, false)
    end
end

_quickKeybindState.UpdateMacroButtonCommand = function(btnFrame)
    if not btnFrame or not MacroFrame or not MacroFrame.GetMacroDataIndex or not GetMacroInfo then
        return
    end

    local index
    if
        (btnFrame == MacroFrameSelectedMacroButton or btnFrame == MacroFrame.SelectedMacroButton)
        and MacroFrame.GetSelectedIndex
    then
        local selected = MacroFrame:GetSelectedIndex()
        if selected then
            index = MacroFrame:GetMacroDataIndex(selected)
        end
    elseif btnFrame.GetElementData then
        local payload = btnFrame:GetElementData()
        if payload then
            index = MacroFrame:GetMacroDataIndex(payload)
        end
    end

    local name = index and GetMacroInfo(index)
    btnFrame.commandName = name and ("MACRO " .. name) or nil
end

_quickKeybindState.RefreshMacroButton = function(btnFrame, show)
    if not btnFrame then
        return
    end
    _quickKeybindState.UpdateMacroButtonCommand(btnFrame)
    if show == nil then
        show = _quickKeybindState.open
    end
    EAB_SetQuickKeybindEffects(btnFrame, show and btnFrame:IsShown())
end

-- On hover (in QKB mode) park the capture overlay over the macro button and arm
-- its tooltip, so the next key/mouse/wheel press binds to THIS macro.
_quickKeybindState.SelectMacroButton = function(btnFrame)
    if not _quickKeybindState.open then
        return
    end
    _quickKeybindState.UpdateMacroButtonCommand(btnFrame)
    if not btnFrame.commandName then
        return
    end

    _quickKeybindState.hoveredMacroButton = btnFrame

    local widget = _quickKeybindState.GetMacroBindFrame()
    widget.button = btnFrame
    widget:ClearAllPoints()
    widget:SetAllPoints(btnFrame)
    _quickKeybindState.ArmMacroPad(widget) -- controller buttons, only while armed
    widget:Show()

    _quickKeybindState.RefreshMacroButton(btnFrame, true)
    if btnFrame.QuickKeybindHighlightTexture then
        btnFrame.QuickKeybindHighlightTexture:SetAlpha(1)
    end
    _quickKeybindState.SetMacroButtonTooltip(btnFrame)
end

_quickKeybindState.InitMacroButton = function(btnFrame)
    if not btnFrame or EFD(btnFrame).qkbMacroHooked or not QuickKeybindButtonTemplateMixin then
        return
    end

    -- No Mixin/QuickKeybindButton* method calls: those invoke Blizzard's secure input
    -- path from addon code and taint it. Our own capture overlay (above) handles all
    -- key/mouse/wheel input; these hooks only manage hover + visuals. Do NOT
    -- EnableMouseWheel on the Blizzard button -- with no wheel handler it would swallow
    -- scroll and break the macro list; the overlay owns the wheel.
    if not btnFrame.QuickKeybindHighlightTexture then
        local texture = btnFrame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(btnFrame)
        texture:SetBlendMode("ADD")
        texture:SetAlpha(0.5)
        texture:Hide()
        btnFrame.QuickKeybindHighlightTexture = texture
    end

    btnFrame:HookScript("OnShow", function(self)
        _quickKeybindState.RefreshMacroButton(self)
    end)
    btnFrame:HookScript("OnHide", function(self)
        _quickKeybindState.RefreshMacroButton(self, false)
    end)
    btnFrame:HookScript("OnClick", function(self)
        _quickKeybindState.UpdateMacroButtonCommand(self)
        if _quickKeybindState.open then
            _quickKeybindState.SetMacroButtonTooltip(self)
        end
    end)
    btnFrame:HookScript("OnEnter", function(self)
        _quickKeybindState.SelectMacroButton(self)
    end)
    btnFrame:HookScript("OnLeave", function(self)
        -- The overlay sits over the button, so the button's OnLeave fires the
        -- instant we park it. Ignore that case; the overlay's own OnLeave tears
        -- down when the cursor truly leaves.
        local widget = _quickKeybindState.macroBindFrame
        if widget and widget:IsShown() and widget.button == self then
            return
        end
        if _quickKeybindState.hoveredMacroButton == self then
            _quickKeybindState.hoveredMacroButton = nil
        end
        if QuickKeybindTooltip then
            QuickKeybindTooltip:Hide()
        end
        _quickKeybindState.RefreshMacroButton(self)
    end)

    local fd = EFD(btnFrame)
    fd.qkbMacroHooked = true
    _quickKeybindState.macroButtons[btnFrame] = true
    _quickKeybindState.RefreshMacroButton(btnFrame)
end

_quickKeybindState.UpdateMacroButtons = function(show)
    if show == false then
        _quickKeybindState.HideMacroBindFrame()
    end
    for btnFrame in pairs(_quickKeybindState.macroButtons) do
        _quickKeybindState.RefreshMacroButton(btnFrame, show)
    end
end

_quickKeybindState.InitMacroFrame = function()
    if _quickKeybindState.macroFrameHooked or not MacroFrame or not QuickKeybindButtonTemplateMixin then
        return
    end

    _quickKeybindState.InitMacroButton(MacroFrameSelectedMacroButton or MacroFrame.SelectedMacroButton)

    local scrollBox = MacroFrame.MacroSelector and MacroFrame.MacroSelector.ScrollBox
    if not scrollBox or not scrollBox.ForEachFrame then
        return
    end

    _quickKeybindState.macroScrollUpdate = function(widget)
        if not widget or not widget.GetView or not widget:GetView() then
            return
        end
        widget:ForEachFrame(_quickKeybindState.InitMacroButton)
        _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
    end
    C_Timer_After(0, function()
        _quickKeybindState.macroScrollUpdate(scrollBox)
    end)
    hooksecurefunc(scrollBox, "Update", _quickKeybindState.macroScrollUpdate)

    _quickKeybindState.macroFrameHooked = true
    _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
end

local function EAB_UpdateQuickKeybindVisibility(show)
    if InCombatLockdown() then
        return
    end

    for _, details in ipairs(BAR_CONFIG) do
        local key = details.key
        local s = ABAR.db and ABAR.db.profile and ABAR.db.profile.bars and ABAR.db.profile.bars[key]
        local widget = barFrames[key]

        if show and widget and ShouldQuickKeybindSurfaceBar(s) then
            RegisterAttributeDriver(widget, "state-visibility", "show")
            -- Keep the visibility cache in sync with the driver we just set.
            -- Otherwise RefreshRuntimeVisibility on QKB exit sees the stale
            -- pre-QKB string still equal to the recomputed real string and
            -- skips re-registering, leaving conditionally-hidden bars
            -- (notably the Pet Bar on non-pet classes) stuck on "show" until reload.
            widget._eabLastVisStr = "show"
            widget:Show()
            SafeEnableMouseMotionOnly(widget, true)
        end

        local buttons = barButtons[key]
        if buttons then
            for _, button in ipairs(buttons) do
                if button then
                    _quickKeybindState.art.ApplyButtonHighlightAlpha(button, show)
                end
            end
        end

        if not details.isStance and not details.isPetBar then
            if buttons then
                for _, button in ipairs(buttons) do
                    if button then
                        SetShowGridInsecure(button, show, SHOWGRID.KEYBOUND)
                    end
                end
            end
        end
    end

    _quickKeybindState.art.ForEachSpecialButton(function(button)
        _quickKeybindState.art.ApplyButtonHighlightAlpha(button, show)
    end)

    if show then
        for _, details in ipairs(BAR_CONFIG) do
            local key = details.key
            local s = ABAR.db and ABAR.db.profile and ABAR.db.profile.bars and ABAR.db.profile.bars[key]
            local widget = barFrames[key]
            local status = hoverStates[key]
            if widget and ShouldQuickKeybindSurfaceBar(s) and s.mouseoverEnabled then
                StopFade(widget, 1)
                if status then
                    status.fadeDir = "in"
                end
                if key == "MainBar" then
                    SyncPagingAlpha(1)
                end
            end
            ABAR:ApplyAlwaysShowButtons(key)
            ABAR:ApplyClickThroughForBar(key)
        end
    else
        -- Pad verdict back first (the open flag is already down), so the
        -- drivers below compile Hide Bar When Using Gamepad again.
        ABAR._PadSync()
        ABAR:ApplyCombatVisibility()
        ABAR:RefreshRuntimeVisibility()
        for _, details in ipairs(BAR_CONFIG) do
            ABAR:ApplyAlwaysShowButtons(details.key)
            ABAR:ApplyClickThroughForBar(details.key)
        end
        ABAR:RefreshMouseover()
    end

    if _pagingFrame then
        LayoutPagingFrame()
    end
end

_quickKeybindState.FinishClose = function()
    _quickKeybindState.closePending = false
    -- Restore action type on buttons that were suppressed during QKB mode. This handles
    -- the deferred-close-during-combat case where SetAttribute was blocked earlier.
    EAB_UpdateQuickKeybindButtons(false)
    EAB_UpdateQuickKeybindVisibility(false)
    -- Restore bar strata if HideDim couldn't (combat-deferred close)
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for widget, orig in pairs(_quickKeybindState.strataCache) do
            widget:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

-- One-time initialization: hook QKB scripts on all action buttons so mouse
-- binding works. ActionBarButtonTemplate provides the mixin methods but
-- Blizzard only wires OnClick/OnEnter/OnLeave on buttons it knows by name
-- (ActionButton1-12, MultiBar*, etc.); our custom EABButtons need explicit
-- hookup for mouse-button binding to communicate with QKB.
_quickKeybindState.InitButtons = function()
    if _quickKeybindState.buttonsInit then
        return
    end
    if not QuickKeybindButtonTemplateMixin then
        return
    end
    _quickKeybindState.buttonsInit = true
    local Pix = CludesUI and CludesUI.PP
    local ACC = CludesUI and CludesUI.CLUDES_GREEN
    for _, details in ipairs(BAR_CONFIG) do
        if not details.isStance and not details.isPetBar then
            local buttons = barButtons[details.key]
            if buttons then
                for _, button in ipairs(buttons) do
                    if button and button.commandName then
                        if not button.QuickKeybindButtonOnClick then
                            Mixin(button, QuickKeybindButtonTemplateMixin)
                        end
                        local fd = EFD(button)
                        if not fd.qkbClickHooked and button.QuickKeybindButtonOnClick then
                            button:HookScript("OnClick", button.QuickKeybindButtonOnClick)
                            button:HookScript("OnEnter", button.QuickKeybindButtonOnEnter)
                            button:HookScript("OnLeave", button.QuickKeybindButtonOnLeave)
                            -- Accent border + highlight color on hover during QKB
                            button:HookScript("OnEnter", function(self)
                                if not _quickKeybindState.open then
                                    return
                                end
                                if not ACC then
                                    return
                                end
                                local fd = EFD(self)
                                if fd.borders and Pix then
                                    Pix.UpdateBorder(self, nil, ACC.r, ACC.g, ACC.b, 0.9)
                                    fd.borderKey = nil
                                end
                                local highlight = self.HighlightTexture
                                if highlight then
                                    highlight:SetVertexColor(ACC.r, ACC.g, ACC.b, 1)
                                end
                                fd.qkbHoverActive = true
                            end)
                            button:HookScript("OnLeave", function(self)
                                local fd = EFD(self)
                                if not fd.qkbHoverActive then
                                    return
                                end
                                fd.qkbHoverActive = nil
                                fd.borderKey = nil
                                local bk = fd.barKey
                                if bk and Pix then
                                    ABAR:ApplyBordersForBar(bk)
                                end
                                local highlight = self.HighlightTexture
                                if highlight then
                                    local p = ABAR and ABAR.db and ABAR.db.profile
                                    local useCC = p and p.highlightUseClassColor
                                    local cc = (p and p.highlightCustomColor)
                                        or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
                                    local hr, hg, hb = cc.r, cc.g, cc.b
                                    if useCC then
                                        local _, ct = UnitClass("player")
                                        local c2 = ct and RAID_CLASS_COLORS[ct]
                                        if c2 then
                                            hr, hg, hb = c2.r, c2.g, c2.b
                                        end
                                    end
                                    highlight:SetVertexColor(hr, hg, hb, 1)
                                end
                                local bk = EFD(self).barKey
                                local s = bk
                                    and ABAR.db
                                    and ABAR.db.profile
                                    and ABAR.db.profile.bars
                                    and ABAR.db.profile.bars[bk]
                                if s and Pix then
                                    local c = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                                    local cr, cg, callback, ca = c.r, c.g, c.b, c.a or 1
                                    if s.borderClassColor then
                                        local _, ct = UnitClass("player")
                                        local cc = ct and RAID_CLASS_COLORS[ct]
                                        if cc then
                                            cr, cg, callback = cc.r, cc.g, cc.b
                                        end
                                    end
                                    local sz, px = ResolveBorderThickness(s)
                                    -- Solid strips: an exact size flows only for a solid bar
                                    -- (a textured bar's exact size is its edge art, not a strip).
                                    if px and (s.borderTexture or "solid") == "solid" then
                                        sz = px
                                    end
                                    if sz > 0 then
                                        Pix.UpdateBorder(self, sz, cr, cg, callback, ca)
                                    else
                                        Pix.HideBorder(self)
                                    end
                                end
                            end)
                            fd.qkbClickHooked = true
                        end
                    end
                end
            end
        end
    end
end

-- Dim overlay: darkens the rest of the UI while Quick Keybind mode is active.
-- Action bars are raised above it so they remain visually prominent.
_quickKeybindState.GetDimOverlay = function()
    if _quickKeybindState.dimFrame then
        return _quickKeybindState.dimFrame
    end
    local size = CreateFrame("Frame", nil, UIParent)
    size:SetFrameStrata("HIGH")
    size:SetFrameLevel(0)
    size:SetAllPoints(UIParent)
    size:EnableMouse(false)
    size:SetMouseClickEnabled(false)
    size:SetMouseMotionEnabled(false)
    local texture = size:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0, 0, 0, 0.40)
    size:SetAlpha(0)
    size:Hide()
    _quickKeybindState.dimFrame = size
    return size
end

_quickKeybindState.ShowDim = function()
    local size = _quickKeybindState.GetDimOverlay()
    size:Show()
    UIFrameFadeIn(size, 0.2, size:GetAlpha(), 1)
    -- Raise action bar frames above the dim
    for _, details in ipairs(BAR_CONFIG) do
        local widget = barFrames[details.key]
        if widget and not InCombatLockdown() then
            if not _quickKeybindState.strataCache then
                _quickKeybindState.strataCache = {}
            end
            if not _quickKeybindState.strataCache[widget] then
                _quickKeybindState.strataCache[widget] = widget:GetFrameStrata()
            end
            widget:SetFrameStrata("DIALOG")
        end
    end
    if _pagingFrame and not InCombatLockdown() then
        if not _quickKeybindState.strataCache then
            _quickKeybindState.strataCache = {}
        end
        if not _quickKeybindState.strataCache[_pagingFrame] then
            _quickKeybindState.strataCache[_pagingFrame] = _pagingFrame:GetFrameStrata()
        end
        _pagingFrame:SetFrameStrata("DIALOG")
    end
end

_quickKeybindState.HideDim = function()
    local size = _quickKeybindState.dimFrame
    if not size then
        return
    end
    UIFrameFadeOut(size, 0.2, size:GetAlpha(), 0)
    C_Timer_After(0.2, function()
        if size:GetAlpha() < 0.01 then
            size:Hide()
        end
    end)
    -- Restore bar strata
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for widget, orig in pairs(_quickKeybindState.strataCache) do
            widget:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

_quickKeybindState.Open = function()
    if _quickKeybindState.open then
        return
    end
    if InCombatLockdown() then
        return
    end
    _quickKeybindState.closePending = false
    _quickKeybindState.open = true
    -- Bars hidden by Hide Bar When Using Gamepad come back for binding: the
    -- open flag drops the pad verdict (EAB._PadSync), so they leave the Never
    -- set and surface below like any other runtime-hidden bar.
    if ABAR._padHide then
        ABAR:RefreshRuntimeVisibility()
    end
    _quickKeybindState.InitButtons()
    _quickKeybindState.InitMacroFrame()
    EAB_UpdateQuickKeybindButtons(true)
    _quickKeybindState.UpdateMacroButtons(true)
    EAB_UpdateQuickKeybindVisibility(true)
    _quickKeybindState.ShowDim()
end

local function EAB_QuickKeybindClose()
    if not _quickKeybindState.open and not _quickKeybindState.closePending then
        return
    end
    _quickKeybindState.HideDim()
    if InCombatLockdown() then
        -- Drop the visual bind overlays immediately so Bar 1 does not look
        -- stuck in QuickKeybind mode, then defer the protected visibility
        -- cleanup until combat ends.
        _quickKeybindState.open = false
        _quickKeybindState.closePending = true
        EAB_UpdateQuickKeybindButtons(false)
        _quickKeybindState.UpdateMacroButtons(false)
        -- Mouseover fading is alpha-only and already operates during combat,
        -- so restore that presentation immediately even though secure
        -- visibility drivers still have to wait until combat ends.
        ABAR:RefreshMouseover()
        mod.CombatQueue.Defer("QuickKeybindClose", function()
            if _quickKeybindState.closePending then
                _quickKeybindState.FinishClose()
            elseif _quickKeybindState.open and not (QuickKeybindFrame and QuickKeybindFrame:IsShown()) then
                EAB_QuickKeybindClose()
            end
        end)
        return
    end
    _quickKeybindState.open = false
    EAB_UpdateQuickKeybindButtons(false)
    _quickKeybindState.UpdateMacroButtons(false)
    _quickKeybindState.FinishClose()
end

-- Defer hook until QuickKeybindFrame exists (it loads after PLAYER_LOGIN).
local _qkbHookFrame = CreateFrame("Frame")
_qkbHookFrame:RegisterEvent("PLAYER_LOGIN")
_qkbHookFrame:RegisterEvent("ADDON_LOADED")
_qkbHookFrame:SetScript("OnEvent", function(self, evt, addonName)
    if evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer_After(1, function()
            local qkb = QuickKeybindFrame
            if qkb then
                if _pagingFrame then
                    InitPagingQuickKeybindButton(
                        _pagingFrame._upBtn,
                        "UI-HUD-ActionBar-PageUpArrow-Mouseover"
                    )
                    InitPagingQuickKeybindButton(
                        _pagingFrame._downBtn,
                        "UI-HUD-ActionBar-PageDownArrow-Mouseover"
                    )
                end
                -- Install a stable frame-owned wrapper once, then update
                -- target callbacks each session so /reload never stacks
                -- stale closures pointing at an old Lua chunk.
                local qfd = EFD(qkb)
                if not qfd.quickKeybindShowHook then
                    qfd.quickKeybindShowHook = function(widget)
                        local ffd = EFD(widget)
                        if ffd.quickKeybindOnShow then
                            ffd.quickKeybindOnShow()
                        end
                    end
                    qfd.quickKeybindHideHook = function(widget)
                        local ffd = EFD(widget)
                        if ffd.quickKeybindOnHide then
                            ffd.quickKeybindOnHide()
                        end
                    end
                    qkb:HookScript("OnShow", qfd.quickKeybindShowHook)
                    qkb:HookScript("OnHide", qfd.quickKeybindHideHook)
                end
                qfd.quickKeybindOnShow = _quickKeybindState.Open
                qfd.quickKeybindOnHide = EAB_QuickKeybindClose
                _quickKeybindState.InitMacroFrame()
                if _quickKeybindState.macroFrameHooked then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end
        end)
    elseif
        evt == "ADDON_LOADED" and (addonName == "Blizzard_MacroUI" or addonName == "Blizzard_QuickKeybind")
    then
        _quickKeybindState.InitMacroFrame()
        if _quickKeybindState.macroFrameHooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)--  Swiftmend by matching icon file ID. Re-scans on slot changes so bar
--  rearrangement is covered.
-------------------------------------------------------------------------------
; ------------------------------------------------------------------------------- --  Swiftmend Brightness Fix (action bar scan): scans all EABButton slots for
(function()
    local function ScanABSwiftmend()
        local _, cls = UnitClass("player")
        if cls ~= "DRUID" then
            return
        end
        local hook = CludesUI and CludesUI._HookSwiftmendIcon
        local iconID = CludesUI and CludesUI._SWIFTMEND_ICON
        if not hook or not iconID then
            return
        end
        for slot = 1, 180 do
            local button = _G["EABButton" .. slot]
            if button and button.icon then
                local t = button.icon:GetTexture()
                if not issecretvalue(t) and t == iconID then
                    hook(button.icon)
                end
            end
        end
    end
    _G._CUAB_ScanSwiftmend = ScanABSwiftmend
    -- The scan is druid-only (it bails on class), so non-druids get no
    -- listener at all: class never changes within a session.
    local _, _playerCls = UnitClass("player")
    if _playerCls ~= "DRUID" then
        return
    end
    local frame = mod.TakeShell()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    -- Coalesced: one 0.5s rescan window at a time. ACTIONBAR_SLOT_CHANGED can
    -- storm (mouseover-conditional macros re-resolving on every flip);
    -- scheduling a timer per event ran the full scan dozens of times/sec.
    local _smPending = false
    local function SwiftmendRescan()
        _smPending = false
        ScanABSwiftmend()
    end
    frame:SetScript("OnEvent", function()
        if not _smPending then
            _smPending = true
            C_Timer.After(0.5, SwiftmendRescan)
        end
    end)
end)()

mod.EAB_UpdateQuickKeybindButtons = EAB_UpdateQuickKeybindButtons -- called by CUI_ActionBars_ButtonArt.lua
